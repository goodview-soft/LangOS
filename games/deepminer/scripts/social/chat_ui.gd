class_name ChatUI
extends Control
## Chat pixel-art (640x360) : log qui s'estompe, saisie (Entrée/Échap, PgHaut/PgBas = historique), liste des joueurs (P), « X écrit… ».

signal typing_started   ## le jeu doit couper ses contrôles
signal typing_ended

const COLORS := {
	"AMI": Color("6fdc6f"), "ALLIE": Color("6fa8ff"), "ENNEMI": Color("ff5a5a"),
	"NEUTRE": Color("f2f2f2"), "INCONNU": Color("9a9a9a"), "SYSTEME": Color("ffd84a"), "JOUEUR": Color("cfe8ff"),
}
const MAX_LINES := 8
const FADE_START := 8.0
const FADE_TIME := 2.0
const FONT_SIZE := 11
const LOG_WIDTH := 300.0  # sits above the hotbar

@export var release_mouse_on_type: bool = true

var hub: SocialHub
var blocked: Callable  ## optionnel : une autre saisie du jeu est ouverte (ne pas ouvrir le chat)
var is_open: bool = false       ## vrai pendant la saisie : le jeu ignore ses touches
var _log: VBoxContainer
var _entry: LineEdit
var _typing_label: Label
var _list_panel: PanelContainer
var _list_box: VBoxContainer
var _lines: Array = []          ## {label, born}
var _typing: Array[String] = []
var _prev_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var _list_refresh: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# smooth (anti-aliased) font for the chat only: the rest of the HUD keeps the crisp pixel look
	var f: Font = ThemeDB.fallback_font.duplicate()
	if f is FontFile:
		(f as FontFile).antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		(f as FontFile).hinting = TextServer.HINTING_LIGHT
	var th := Theme.new()
	th.default_font = f
	th.default_font_size = FONT_SIZE
	theme = th
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func bind_hub(h: SocialHub) -> void:
	hub = h
	hub.chat_message.connect(_on_chat)
	hub.typing_changed.connect(_on_typing)
	for e: Dictionary in hub.history.slice(-MAX_LINES):
		_on_chat(e)


# ---------------------------------------------------------------- construction
func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_content_margin_all(3)
	sb.anti_aliasing = false
	return sb


func _label(text: String, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build() -> void:
	_log = VBoxContainer.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_constant_override("separation", 0)
	_log.alignment = BoxContainer.ALIGNMENT_END
	_log.anchor_top = 1.0
	_log.anchor_bottom = 1.0
	_log.offset_left = 4
	_log.offset_right = 4 + LOG_WIDTH
	_log.offset_top = -240
	_log.offset_bottom = -74
	add_child(_log)

	_typing_label = _label("", Color("bdbdbd"))
	_typing_label.anchor_top = 1.0
	_typing_label.anchor_bottom = 1.0
	_typing_label.offset_left = 4
	_typing_label.offset_top = -73
	_typing_label.offset_bottom = -60
	add_child(_typing_label)

	_entry = LineEdit.new()
	_entry.anchor_top = 1.0
	_entry.anchor_bottom = 1.0
	_entry.offset_left = 4
	_entry.offset_right = 4 + LOG_WIDTH
	_entry.offset_top = -58
	_entry.offset_bottom = -38
	_entry.max_length = 200
	_entry.placeholder_text = "message… (@pseudo pour viser)"
	_entry.add_theme_font_size_override("font_size", FONT_SIZE)
	_entry.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0.75), Color("ffd84a")))
	_entry.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0.75), Color("ffd84a")))
	_entry.context_menu_enabled = false
	_entry.visible = false
	_entry.text_submitted.connect(_on_submit)
	_entry.gui_input.connect(_on_input_gui)
	add_child(_entry)

	_list_panel = PanelContainer.new()
	_list_panel.add_theme_stylebox_override("panel", _style(Color(0.05, 0.05, 0.08, 0.88), Color("6b6b80")))
	_list_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_list_panel.offset_left = -150
	_list_panel.offset_right = 150
	_list_panel.offset_top = 24
	_list_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_panel.visible = false
	add_child(_list_panel)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 1)
	_list_panel.add_child(_list_box)


# ---------------------------------------------------------------- log
const HIST_MAX := 100

var _all: Array = []            ## {text, color, born} : historique complet (PgHaut/PgBas pendant la saisie)
var _scroll: int = 0            ## 0 = les plus récents ; n = n lignes plus haut


func _on_chat(e: Dictionary) -> void:
	var kind := String(e.get("kind", "agent"))
	if kind == "agent" and not DMSettings.chat_bots:
		return  # bots are silent in the chat (/chat on to show them)
	var text := ""
	var col: Color = COLORS["NEUTRE"]
	if kind == "system":
		text = String(e["text"])
		col = COLORS["SYSTEME"]
	else:
		text = "<%s> %s" % [e["from"], e["text"]]
		col = COLORS.get(String(e.get("status", "NEUTRE")), COLORS["NEUTRE"])
		if kind == "player":
			col = COLORS["JOUEUR"]
	_all.append({"text": text, "color": col, "born": Time.get_ticks_msec() / 1000.0})
	while _all.size() > HIST_MAX:
		_all.pop_front()
	if _scroll > 0:
		_scroll = mini(_scroll + 1, maxi(0, _all.size() - MAX_LINES))
	_render()


## Affiche la fenêtre de MAX_LINES lignes de l'historique selon _scroll.
func _render() -> void:
	for d: Dictionary in _lines:
		(d["label"] as Label).queue_free()
	_lines.clear()
	var end := _all.size() - _scroll
	for i in range(maxi(0, end - MAX_LINES), end):
		var h: Dictionary = _all[i]
		var l := _label(String(h["text"]), h["color"])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = LOG_WIDTH
		_log.add_child(l)
		_lines.append({"label": l, "born": float(h["born"])})


func scroll_history(dir: int) -> void:
	_scroll = clampi(_scroll + dir * (MAX_LINES / 2), 0, maxi(0, _all.size() - MAX_LINES))
	_render()


func _on_typing(pseudo: String, typing: bool) -> void:
	if not DMSettings.chat_bots:
		return
	if typing and not _typing.has(pseudo):
		_typing.append(pseudo)
	elif not typing:
		_typing.erase(pseudo)
	if _typing.is_empty():
		_typing_label.text = ""
	elif _typing.size() == 1:
		_typing_label.text = "%s écrit…" % _typing[0]
	else:
		_typing_label.text = "%s écrivent…" % ", ".join(PackedStringArray(_typing))


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for d: Dictionary in _lines:
		var age := t - float(d["born"])
		var a := 1.0 if (is_open or _scroll > 0) else clampf(1.0 - (age - FADE_START) / FADE_TIME, 0.0, 1.0)
		(d["label"] as Label).modulate.a = a
	if _list_panel.visible:
		_list_refresh -= delta
		if _list_refresh <= 0.0:
			_refresh_list()


# ---------------------------------------------------------------- saisie
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	if is_open:
		return  # la LineEdit gère tout
	if blocked.is_valid() and blocked.call():
		return
	if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_T:  # T like Minecraft
		open_input()
		_entry.call_deferred("clear")  # the T itself must not land in the text
		get_viewport().set_input_as_handled()
	elif k == KEY_P:
		_list_panel.visible = not _list_panel.visible
		if _list_panel.visible:
			_refresh_list()
		get_viewport().set_input_as_handled()


func open_input() -> void:
	is_open = true
	_entry.visible = true
	_entry.text = ""
	_entry.grab_focus()
	if release_mouse_on_type:
		_prev_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	typing_started.emit()


func close_input() -> void:
	is_open = false
	_scroll = 0
	_render()
	_entry.release_focus()
	_entry.visible = false
	if release_mouse_on_type:
		Input.mouse_mode = _prev_mouse_mode as Input.MouseMode
	typing_ended.emit()


func _on_input_gui(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_ESCAPE:
			close_input()
		elif kc == KEY_PAGEUP or kc == KEY_PAGEDOWN:
			scroll_history(1 if kc == KEY_PAGEUP else -1)
	# (no accept_event here: it would stop the LineEdit itself; the game ignores keys while the chat is open)


func _on_submit(text: String) -> void:
	if hub and not text.strip_edges().is_empty():
		hub.send_player_message(text)
	close_input()


# ---------------------------------------------------------------- liste des joueurs
func _refresh_list() -> void:
	_list_refresh = 1.0
	for c: Node in _list_box.get_children():
		c.queue_free()
	_list_box.add_child(_label("JOUEURS  (P pour fermer)", COLORS["SYSTEME"]))
	if hub == null:
		return
	for p: Dictionary in hub.get_player_list():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var online := bool(p["online"])
		var col: Color = COLORS.get(String(p["status"]), COLORS["NEUTRE"])
		if not online:
			col = col.darkened(0.5)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(4, 4)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = Color("4ade4a") if online else Color("555555")
		row.add_child(dot)
		var name_l := _label(String(p["pseudo"]), col)
		name_l.custom_minimum_size.x = 96
		name_l.clip_text = true
		row.add_child(name_l)
		var st := _label(String(p["status"]).to_lower(), col)
		st.custom_minimum_size.x = 46
		row.add_child(st)
		var ping_l := _label(("%dms" % int(p["ping"])) if online else "hors ligne", Color("bdbdbd") if online else Color("777777"))
		ping_l.custom_minimum_size.x = 50
		row.add_child(ping_l)
		row.add_child(_affinity_bar(int(p["affinity"])))
		_list_box.add_child(row)


## Barre centrée : à gauche rouge (négatif), à droite verte (positif).
func _affinity_bar(aff: int) -> Control:
	var w := 60.0
	var bg := ColorRect.new()
	bg.custom_minimum_size = Vector2(w, 5)
	bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bg.color = Color(0.18, 0.18, 0.22)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	var half := w / 2.0
	var fill_len := absf(aff) / 100.0 * half
	fill.color = Color("6fdc6f") if aff >= 0 else Color("ff5a5a")
	fill.position = Vector2(half if aff >= 0 else half - fill_len, 0)
	fill.size = Vector2(maxf(fill_len, 0.0), 5)
	bg.add_child(fill)
	var mid := ColorRect.new()
	mid.color = Color(1, 1, 1, 0.5)
	mid.position = Vector2(half, 0)
	mid.size = Vector2(1, 5)
	bg.add_child(mid)
	return bg
