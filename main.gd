extends Control
# Bloc-notes avec clavier visuel, interface façon OS.

const VERSION: String = preload("res://version.gd").VERSION
const UPDATE_URL := "https://github.com/goodview-soft/LangOS/releases/latest/download/version.json"
const RELEASES_URL := "https://github.com/goodview-soft/LangOS/releases/latest"
const CHECK_UPDATES := true
const SAVE_PATH := "user://note.txt"
const ROWS_LOWER := [
	["²","&","é","\"","'","(","-","è","_","ç","à",")","="],
	["a","z","e","r","t","y","u","i","o","p","^","$"],
	["q","s","d","f","g","h","j","k","l","m","ù","*"],
	["<","w","x","c","v","b","n",",",";",":","!"],
]
const ROWS_UPPER := [
	["~","1","2","3","4","5","6","7","8","9","0","°","+"],
	["A","Z","E","R","T","Y","U","I","O","P","¨","£"],
	["Q","S","D","F","G","H","J","K","L","M","%","µ"],
	[">","W","X","C","V","B","N","?",".","/","§"],
]

var edit: TextEdit
var status: Label
var clock: Label
var title_lbl: Label
var shift := false
var caps := false
var char_btns: Array = []   # [Button, row, col]
var shift_btns: Array = []
var dirty := false

var desk: Control
var wins := {}   # id -> {win, task, maxed, saved}
var task_box: HBoxContainer
var start_btn: Button
var menu: PanelContainer
var catcher: Control
var bg: TextureRect
var upd_text := ""
var upd_avail := false
var apk_prompted := false
var upd_lbl: Label
const BG_GRADS := [["16213e","2f5fa8","7a4fb0"], ["0f1c26","1f4e5f","2e8b7a"], ["16161f","3a2a5c","b0507a"], ["12141a","2a2f3d","56607a"], ["1c120d","6b3a1f","e0873a"]]
const ACCENT := Color("5aa2ff")
const TEXT := Color("e5e9f0")
const MUTED := Color("8f9bb3")
const APPS := {
	"notepad": ["Bloc-notes", "res://icons/app_notepad.svg"],
	"settings": ["Paramètres", "res://icons/app_settings.svg"],
	"system": ["Système", "res://icons/app_system.svg"],
	"translate": ["Traducteur", "res://icons/app_translate.svg"],
	"dict": ["Dictionnaire", "res://icons/app_dict.svg"],
	"messenger": ["Messenger", "res://icons/app_messenger.svg"],
	"remote": ["RemoteDesk", "res://icons/app_remote.svg"],
	"chat": ["Chat IA", "res://icons/app_chat.svg"],
	"music": ["Music", "res://icons/app_music.svg"],
	"soundlink": ["Sound Link", "res://icons/app_soundlink.svg"],
	"update": ["Mise à jour", "res://icons/app_update.svg"],
	"chess": ["Échecs", "res://icons/app_chess.svg"],
	"f_lang": ["Langue", "res://icons/app_f_lang.svg"],
	"f_games": ["Jeux", "res://icons/app_f_games.svg"],
	"f_comm": ["Communication", "res://icons/app_f_comm.svg"],
	"hika": ["Hikabrain", "res://icons/app_hika.svg"],
	"chromium": ["Chromium", "res://icons/app_chromium.svg"],
	"android_apps": ["Applis Android", "res://icons/app_android.svg"],
	"f_soft": ["Logiciels", "res://icons/app_f_soft.svg"],
	"f_tools": ["Outils", "res://icons/app_f_tools.svg"],
	"calc": ["Calculatrice", "res://icons/app_calc.svg"],
	"units": ["Convertisseur", "res://icons/app_units.svg"],
	"timer": ["Minuteur", "res://icons/app_timer.svg"],
	"todo": ["Listes", "res://icons/app_todo.svg"],
	"vault": ["Coffre-fort", "res://icons/app_vault.svg"],
	"cards": ["Cartes mémoire", "res://icons/app_cards.svg"],
}
## Dossiers du bureau : id -> applications contenues (affichées seulement dans le dossier).
const FOLDERS := {
	"f_lang": ["translate", "dict", "music"],
	"f_games": ["chess", "hika"],
	"f_soft": ["chromium"],
	"f_comm": ["messenger", "remote", "chat", "soundlink"],
	"f_tools": ["calc", "units", "timer", "todo", "vault", "cards"],
}

func _top_ids() -> Array:
	var inside := []
	for f in FOLDERS: inside += FOLDERS[f]
	var android := OS.get_name() == "Android"
	return APPS.keys().filter(func(k): return not inside.has(k) and (k != "android_apps" or android))
var active := ""
var set_cfg := {"bg": 0, "font": 22, "ollama": "http://127.0.0.1:11434", "kb": "osk", "cursor": "auto", "pad": false, "pad_speed": 0.7, "zoom": 1.0, "model": "", "engine": -1, "src": "spa", "tgt": "fra"}
var kb: PanelContainer
var ui_root: VBoxContainer
var pointer: Control
var flex: PanelContainer
var fold_half := false
var fold_top := 0.0
var fold_bottom := 0.0
var fold_px_top := 0.0       # charnière en pixels écran (indépendant du zoom)
var fold_px_bottom := 0.0
var zoom_save := false
var fold_gen := 0
var kb_btn: Button
var upd_http: HTTPRequest
var upd_btn: Button
var upd_info := {}
var bar_h := 48.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # le bureau reste actif quand un jeu se met en pause
	_load_settings()
	OS.low_processor_usage_mode = true
	OS.low_processor_usage_mode_sleep_usec = 16000
	_build_theme()
	_build_desktop()
	_setup_chat()
	var t := Timer.new(); t.wait_time = 1.0; t.autostart = true
	t.timeout.connect(_tick); add_child(t); _tick()
	_check_update()
	if "--pad-test" in OS.get_cmdline_user_args(): set_cfg["pad"] = true; _update_flex.call_deferred()
	if "--perf-test" in OS.get_cmdline_user_args():
		_perf_test(); return
	if "--ctl-test" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1.5).timeout
		var snd := PacketPeerUDP.new(); var tp := 4360
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--ctl-port="): tp = a.get_slice("=", 1).to_int()
		snd.set_dest_address("127.0.0.1", tp); snd.put_packet("toggle-chat".to_utf8_buffer())
		await get_tree().create_timer(0.6).timeout
		print("CTL ctl.bound=", ctl.is_bound(), " ouvert après toggle UDP: ", chat_ov != null and chat_ov.is_open(), " win=", chat_ov.win != null if chat_ov else "-")
		snd.put_packet("toggle-chat".to_utf8_buffer()); await get_tree().create_timer(0.6).timeout
		print("CTL fermé après 2e toggle: ", chat_ov != null and not chat_ov.is_open())
		get_tree().quit()
	if "--os-test" in OS.get_cmdline_user_args():
		for id in APPS: _open_app(id)
		_toggle_menu(); _toggle_menu(); _toggle_kb()
		await get_tree().create_timer(1.0).timeout
		_dic_search("casa")
		print("DICT: ", dic_list.get_item_text(0), " | ", dic_def.get_parsed_text().replace("\n", " ").substr(0, 70), " | ", dic_info.text)
		set_cfg["src"] = "fra"; set_cfg["tgt"] = "eng"; _apply_langs()
		await get_tree().create_timer(1.0).timeout
		print("LANGS: ", dic_note.text, " | ", dic_info.text, " | music=", music_node.get("src"), ">", music_node.get("tgt"), " | tr=", tr_pair.text)
		set_cfg["src"] = "spa"; set_cfg["tgt"] = "fra"; _apply_langs()
		await get_tree().create_timer(1.0).timeout
		print("LANGS2: ", dic_note.text)
		edit.text = "bonjour tout le monde"; edit.grab_focus(); _clip_action("all"); _clip_action("copy"); edit.text = ""; _clip_action("paste")
		print("CLIP: ", edit.text)
		_show_ctx(edit, Vector2(400, 300)); print("CTX: ", ctx_menu.visible, " ", ctx_menu.get_child(0).get_child_count(), " boutons"); _hide_ctx()
		print("OS-TEST OK wins=", wins.size())
		get_tree().quit()

# ---------------------------------------------------------------- Appui long : menu Copier / Coller

func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_MINUS and chat_ov:
		var fo := get_viewport().gui_get_focus_owner()
		if not (fo is LineEdit or fo is TextEdit):
			chat_ov.toggle(); get_viewport().set_input_as_handled(); return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed: _raise_window_at(ev.position)
		lp_active = ev.pressed; lp_pos = ev.position; lp_t = Time.get_ticks_msec()
	elif ev is InputEventMouseMotion and lp_active and ev.position.distance_to(lp_pos) > 16.0:
		lp_active = false

## Un clic n'importe où dans une fenêtre la met au premier plan (la dernière sélectionnée passe devant).
func _raise_window_at(pos: Vector2) -> void:
	if desk == null or menu.visible: return
	var p := pos - desk.global_position
	var kids := desk.get_children()
	kids.reverse()
	for c in kids:
		if not (c is PanelContainer and c.visible and Rect2(c.position, c.size).has_point(p)): continue
		for id in wins:
			if wins[id]["win"] == c:
				if active != id: _show(id)
				return
		return

func _check_longpress() -> void:
	if lp_active and Time.get_ticks_msec() - lp_t > 550:
		lp_active = false
		var c := get_viewport().gui_get_hovered_control()
		while c and not (c is TextEdit or c is LineEdit or c is RichTextLabel): c = c.get_parent() as Control
		if c: _show_ctx(c, lp_pos)

func _show_ctx(t: Control, at: Vector2) -> void:
	_hide_ctx()
	ctx_target = t
	var editable: bool = (t is TextEdit and t.editable) or (t is LineEdit and t.editable)
	if t is TextEdit and not t.has_selection(): t.select_word_under_caret()
	var has_sel := false
	if t is TextEdit or t is LineEdit: has_sel = t.has_selection() if t is TextEdit else t.has_selection()
	ctx_catcher = Control.new(); ctx_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctx_catcher.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: _hide_ctx())
	add_child(ctx_catcher)
	ctx_menu = PanelContainer.new()
	ctx_menu.add_theme_stylebox_override("panel", _box(Color(0.12, 0.14, 0.2, 0.98), 12, Color(1, 1, 1, 0.14), 1, 18, 6))
	add_child(ctx_menu)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 2); ctx_menu.add_child(h)
	var items := []
	if editable and has_sel: items.append(["Couper", "cut"])
	items.append(["Copier", "copy"])
	if editable: items.append(["Coller", "paste"])
	items.append(["Tout sélectionner", "all"])
	for e in items:
		var b := _mk_btn(e[0], 0, 48); b.theme_type_variation = "Flat"; b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func(): _ctx_do(e[1]))
		h.add_child(b)
	ctx_menu.size = ctx_menu.get_combined_minimum_size()
	ctx_menu.position = Vector2(clampf(at.x - ctx_menu.size.x / 2.0, 8, size.x - ctx_menu.size.x - 8), maxf(8, at.y - ctx_menu.size.y - 28))

func _ctx_do(a: String) -> void:
	var t := ctx_target
	if is_instance_valid(t):
		t.grab_focus()
		if t is RichTextLabel and a == "copy":
			var s: String = t.get_selected_text()
			DisplayServer.clipboard_set(s if s != "" else t.get_parsed_text())
		else: _clip_action(a)
	_hide_ctx()

func _hide_ctx() -> void:
	if is_instance_valid(ctx_menu): ctx_menu.queue_free()
	if is_instance_valid(ctx_catcher): ctx_catcher.queue_free()

func _process(_d: float) -> void:
	_check_longpress()
	_poll_ctl()

func _cpu_ticks() -> int:
	var out := []
	OS.execute("cat", ["/proc/%d/stat" % OS.get_process_id()], out)
	if out.is_empty(): return 0
	var f: String = out[0]
	var p := f.substr(f.rfind(")") + 2).split(" ")
	return int(p[11]) + int(p[12])

func _perf_sample(label: String, secs: float) -> void:
	var c0 := _cpu_ticks(); var t0 := Time.get_ticks_msec()
	var n := 0; var worst := 0.0; var dc := 0.0; var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec(); var dt := (now - last) / 1000.0; last = now
		worst = maxf(worst, dt); n += 1
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var wall := (Time.get_ticks_msec() - t0) / 1000.0
	var cpu := float(_cpu_ticks() - c0) / 100.0 / wall * 100.0
	print("PERF %-38s CPU=%5.1f%%  fps=%5.1f  pire image=%6.1f ms  draw_calls=%4.0f" % [label, cpu, n / wall, worst, dc / maxf(1, n)])

func _perf_test() -> void:
	await get_tree().create_timer(1.0).timeout
	await _perf_sample("bureau seul", 5.0)
	_open_app("music")
	await get_tree().create_timer(0.8).timeout
	var mu := music_node
	mu.set("tracks", [{"id": "perf", "title": "T", "artist": "A", "track": "Titre", "duration": 120.0, "file": OS.get_environment("HOME") + "/mtest/s.mp3", "lrc": "", "offset": 0.0, "no_lyrics": true, "video": OS.get_environment("HOME") + "/mtest/c.ogv" if "--perf-video" in OS.get_cmdline_user_args() else ""}])
	mu.call("_play", 0)
	var ls := []
	for i in 30: ls.append([i * 3.0, "Voy de buena onda, me invita a tu casa y ahora tú me dice' que yo me agacha %d" % i])
	mu.set("lines", ls)
	var tr := {}
	for i in 30: tr[i] = {"tr": "Je suis cool, il m'invite chez lui et maintenant tu me dis", "words": [{"w": "onda", "sens": "ambiance"}, {"w": "casa", "sens": "maison"}, {"w": "agacha", "sens": "me baisser"}]}
	mu.set("trans", tr)
	mu.get("kv").call("set_data", ls, tr)
	await _perf_sample("Music : lecteur karaoké (au 1er plan)", 6.0)
	mu.set("ov_mode", 1); mu.set("cw_mode", 2)
	await _perf_sample("+ overlay paroles + mot centre", 6.0)
	mu.set("ov_mode", 0); mu.set("cw_mode", 0)
	await get_tree().create_timer(2.0).timeout
	await _perf_sample("Music, overlays coupés (après 2 s)", 4.0)
	get_tree().quit()

func _notification(what: int) -> void:
	# Au premier plan : ~60 images/s ; en arrière-plan (jeu au premier plan) : ~30, les overlays suffisent.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: OS.low_processor_usage_mode_sleep_usec = 33000
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN: OS.low_processor_usage_mode_sleep_usec = 16000

func _tick() -> void:
	var d := Time.get_date_dict_from_system()
	clock.text = "%s\n%02d/%02d/%d" % [Time.get_datetime_string_from_system().substr(11, 5), d["day"], d["month"], d["year"]]

func _box(c: Color, r := 8, bc := Color(0, 0, 0, 0), bw := 0, sh := 0, m := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = c; s.set_corner_radius_all(r)
	if bw > 0: s.border_color = bc; s.set_border_width_all(bw)
	if sh > 0: s.shadow_color = Color(0, 0, 0, 0.45); s.shadow_size = sh; s.shadow_offset = Vector2(0, sh * 0.3)
	if m > 0: s.set_content_margin_all(m)
	return s

func _flat(c: Color, r := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = c; s.set_corner_radius_all(r)
	return s

func _ico(n: String) -> Texture2D:
	return load("res://icons/%s.svg" % n)

func _grad_tex(i: int, w := 512, h := 288) -> GradientTexture2D:
	var g := Gradient.new()
	var cols := PackedColorArray(); var offs := PackedFloat32Array()
	var arr: Array = BG_GRADS[i]
	for k in arr.size():
		cols.append(Color(arr[k])); offs.append(float(k) / (arr.size() - 1))
	g.colors = cols; g.offsets = offs
	var t := GradientTexture2D.new(); t.gradient = g; t.width = w; t.height = h
	t.fill_from = Vector2(0, 0); t.fill_to = Vector2(1, 1)
	return t

func _build_theme() -> void:
	var th := Theme.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Inter", "Noto Sans", "Ubuntu", "Cantarell", "Roboto", "DejaVu Sans"])
	th.default_font = f; th.default_font_size = 17
	var w := func(a: float) -> Color: return Color(1, 1, 1, a)
	# Boutons (touches) : remplis
	for st in [["normal", w.call(0.08)], ["hover", w.call(0.16)], ["pressed", ACCENT], ["disabled", w.call(0.04)]]:
		var sb := _box(st[1], 10); sb.content_margin_left = 12; sb.content_margin_right = 12
		sb.content_margin_top = 6; sb.content_margin_bottom = 6
		th.set_stylebox(st[0], "Button", sb)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", TEXT); th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("icon_normal_color", "Button", TEXT); th.set_color("icon_hover_color", "Button", Color.WHITE)
	th.set_color("icon_pressed_color", "Button", Color.WHITE)
	th.set_font_size("font_size", "Button", 19)
	th.set_constant("icon_max_width", "Button", 22); th.set_constant("h_separation", "Button", 10)
	for st in ["normal", "hover", "pressed", "disabled"]:
		th.set_stylebox(st, "OptionButton", th.get_stylebox(st, "Button"))
	th.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	th.set_color("font_color", "OptionButton", TEXT); th.set_color("font_hover_color", "OptionButton", Color.WHITE)
	th.set_font_size("font_size", "OptionButton", 17)
	th.set_stylebox("panel", "PopupMenu", _box(Color("1b1f2a"), 10, w.call(0.12), 1, 12, 6))
	th.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT, 0.35), 6))
	th.set_color("font_color", "PopupMenu", TEXT); th.set_font_size("font_size", "PopupMenu", 17)
	th.set_constant("v_separation", "PopupMenu", 8)
	th.set_stylebox("panel", "ItemList", _box(Color("171b25"), 10, w.call(0.07), 1, 0, 6))
	th.set_stylebox("selected", "ItemList", _box(Color(ACCENT, 0.35), 6)); th.set_stylebox("selected_focus", "ItemList", _box(Color(ACCENT, 0.35), 6))
	th.set_stylebox("hovered", "ItemList", _box(w.call(0.06), 6)); th.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	th.set_color("font_color", "ItemList", TEXT); th.set_color("font_selected_color", "ItemList", Color.WHITE)
	th.set_font_size("font_size", "ItemList", 19); th.set_constant("v_separation", "ItemList", 6)
	th.set_color("default_color", "RichTextLabel", TEXT)
	# Variante transparente
	th.set_type_variation("Flat", "Button")
	for st in [["normal", 0.0], ["hover", 0.09], ["pressed", 0.16]]:
		var sb := _box(w.call(st[1]), 8); sb.content_margin_left = 12; sb.content_margin_right = 12
		sb.content_margin_top = 5; sb.content_margin_bottom = 5
		th.set_stylebox(st[0], "Flat", sb)
	th.set_type_variation("Close", "Button")
	for st in [["normal", Color(0, 0, 0, 0)], ["hover", Color("e5484d")], ["pressed", Color("c0363b")]]:
		var sb := _box(st[1], 6); sb.content_margin_left = 8; sb.content_margin_right = 8
		th.set_stylebox(st[0], "Close", sb)
	th.set_type_variation("Accent", "Button")
	for st in [["normal", ACCENT], ["hover", ACCENT.lightened(0.15)], ["pressed", ACCENT.darkened(0.2)], ["disabled", ACCENT.darkened(0.5)]]:
		var sb := _box(st[1], 10); sb.content_margin_left = 16; sb.content_margin_right = 16
		sb.content_margin_top = 8; sb.content_margin_bottom = 8
		th.set_stylebox(st[0], "Accent", sb)
	th.set_color("font_color", "Accent", Color("0b1220")); th.set_color("font_hover_color", "Accent", Color("0b1220"))
	th.set_color("font_pressed_color", "Accent", Color("0b1220")); th.set_color("font_disabled_color", "Accent", Color(0.04, 0.07, 0.12, 0.6))
	# Texte
	th.set_color("font_color", "Label", TEXT)
	th.set_font_size("font_size", "Label", 16)
	var te := _box(Color("171b25"), 10, w.call(0.07), 1, 0, 14)
	th.set_stylebox("normal", "TextEdit", te); th.set_stylebox("focus", "TextEdit", _box(Color("171b25"), 10, ACCENT.darkened(0.3), 1, 0, 14))
	th.set_color("font_color", "TextEdit", TEXT); th.set_color("caret_color", "TextEdit", ACCENT)
	th.set_color("font_placeholder_color", "TextEdit", Color(0.56, 0.61, 0.7, 0.6))
	th.set_color("selection_color", "TextEdit", Color(ACCENT, 0.35)); th.set_color("current_line_color", "TextEdit", w.call(0.03))
	th.set_font_size("font_size", "TextEdit", 22)
	th.set_stylebox("normal", "LineEdit", _box(Color("171b25"), 8, w.call(0.07), 1, 0, 10))
	th.set_stylebox("focus", "LineEdit", _box(Color("171b25"), 8, ACCENT.darkened(0.3), 1, 0, 10))
	th.set_color("font_color", "LineEdit", TEXT); th.set_color("caret_color", "LineEdit", ACCENT)
	# Curseur
	th.set_stylebox("slider", "HSlider", _box(w.call(0.12), 4, Color(0, 0, 0, 0), 0, 0, 0))
	th.get_stylebox("slider", "HSlider").content_margin_top = 3; th.get_stylebox("slider", "HSlider").content_margin_bottom = 3
	th.set_stylebox("grabber_area", "HSlider", _box(ACCENT, 4)); th.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT.lightened(0.2), 4))
	var sl := StyleBoxLine.new(); sl.color = w.call(0.1); sl.thickness = 1
	th.set_stylebox("separator", "HSeparator", sl)
	theme = th

func _mk_btn(txt: String, w := 56, h := 56) -> Button:
	var b := Button.new(); b.text = txt
	b.custom_minimum_size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	return b

func _icon_btn(icon: String, variation := "Flat", w := 40, h := 36, isz := 18) -> Button:
	var b := _mk_btn("", w, h); b.theme_type_variation = variation
	b.icon = _ico(icon); b.add_theme_constant_override("icon_max_width", isz)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b

func _apply_bg() -> void:
	bg.texture = _grad_tex(set_cfg["bg"])

func _build_desktop() -> void:
	bg = TextureRect.new(); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(bg); _apply_bg()
	# Halo lumineux
	var gl := Gradient.new(); gl.colors = PackedColorArray([Color(1, 1, 1, 0.14), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new(); gt.gradient = gl; gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.25, 0.2); gt.fill_to = Vector2(0.95, 0.2); gt.width = 256; gt.height = 256
	var halo := TextureRect.new(); halo.texture = gt; halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE; halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(halo)
	var root := VBoxContainer.new()
	ui_root = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	desk = Control.new(); desk.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desk.clip_contents = true; root.add_child(desk)
	for id in _top_ids(): _desk_icon(id, Vector2.ZERO)
	desk.resized.connect(_layout_icons); desk.resized.connect(_clamp_windows); _layout_icons.call_deferred()
	# Barre des tâches
	var bar := PanelContainer.new()
	var bs := _box(Color(0.07, 0.08, 0.11, 0.9), 0); bs.border_width_top = 1; bs.border_color = Color(1, 1, 1, 0.08)
	bs.content_margin_left = 8; bs.content_margin_right = 12; bs.content_margin_top = 5; bs.content_margin_bottom = 5
	bar.add_theme_stylebox_override("panel", bs)
	root.add_child(bar)
	var bh := HBoxContainer.new(); bh.add_theme_constant_override("separation", 6); bar.add_child(bh)
	start_btn = _mk_btn("LangOS", 130, 42); start_btn.theme_type_variation = "Flat"
	start_btn.icon = _ico("start"); start_btn.add_theme_constant_override("icon_max_width", 20)
	start_btn.add_theme_color_override("icon_normal_color", ACCENT); start_btn.add_theme_color_override("icon_hover_color", ACCENT)
	start_btn.add_theme_font_size_override("font_size", 18)
	start_btn.pressed.connect(_toggle_menu); bh.add_child(start_btn)
	var vs := VSeparator.new(); vs.modulate = Color(1, 1, 1, 0.4); bh.add_child(vs)
	task_box = HBoxContainer.new(); task_box.add_theme_constant_override("separation", 4); bh.add_child(task_box)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bh.add_child(sp)
	kb_btn = _icon_btn("keyboard", "Flat", 48, 42, 24); kb_btn.pressed.connect(_toggle_kb); bh.add_child(kb_btn)
	var tray := Control.new(); tray.set_script(load("res://apps/systray.gd")); bh.add_child(tray)
	clock = Label.new(); clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.add_theme_font_size_override("font_size", 14); bh.add_child(clock)
	bar_h = 54.0
	_build_keyboard()
	get_tree().node_added.connect(_on_node_added)
	pointer = Control.new(); pointer.set_script(load("res://apps/pointer.gd")); pointer.set("mode", set_cfg["cursor"]); add_child(pointer)
	flex = PanelContainer.new(); flex.set_script(load("res://apps/flex_pad.gd")); flex.set("pointer", pointer); flex.set("gain", set_cfg["pad_speed"]); flex.set("on_zoom", Callable(self, "_set_zoom")); flex.set("get_zoom", Callable(self, "_get_zoom")); flex.visible = false; add_child(flex)
	flex.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	if OS.get_name() == "Android" and Engine.has_singleton("LangLauncher") and int(Engine.get_singleton("LangLauncher").nativeLevel()) >= 7:
		var ll := Engine.get_singleton("LangLauncher")
		ll.connect("fold_changed", _on_fold); _on_fold(str(ll.foldState()))
	get_window().content_scale_factor = set_cfg["zoom"]
	resized.connect(_update_flex)
	_update_flex.call_deferred()
	_apply_kb.call_deferred()
	_build_menu()

## Range les icônes en colonnes ; passe à la colonne suivante quand la hauteur est atteinte.
## Après une rotation ou un changement de zone (mode Flex) : les fenêtres restent dans le bureau, les fenêtres agrandies le remplissent.
func _clamp_windows() -> void:
	for id in wins:
		var d: Dictionary = wins[id]
		var w: PanelContainer = d["win"]
		if d["maxed"]: w.position = Vector2.ZERO; w.size = desk.size; continue
		var mn := w.get_combined_minimum_size()
		w.size = Vector2(minf(maxf(w.size.x, mn.x), desk.size.x - 8.0), minf(maxf(w.size.y, mn.y), desk.size.y - 8.0))
		w.position = Vector2(clampf(w.position.x, 0.0, maxf(0.0, desk.size.x - w.size.x)), clampf(w.position.y, 0.0, maxf(0.0, desk.size.y - w.size.y)))

func _layout_icons() -> void:
	var per_col := maxi(1, int((desk.size.y - 16.0) / 108.0))
	for i in desk_icons.size():
		desk_icons[i].position = Vector2(16 + (i / per_col) * 108, 16 + (i % per_col) * 108)

func _desk_icon(id: String, pos: Vector2) -> void:
	var b := Button.new(); b.theme_type_variation = "Flat"; b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(100, 100); b.position = pos; b.size = Vector2(100, 100)
	var v := VBoxContainer.new(); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_FULL_RECT); v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6); b.add_child(v)
	var t := TextureRect.new(); t.texture = load(APPS[id][1]); t.custom_minimum_size = Vector2(56, 56)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(t)
	var l := Label.new(); l.text = APPS[id][0]; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14); l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1); l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(l)
	b.pressed.connect(_open_app.bind(id))
	desk.add_child(b); desk_icons.append(b)

# ---------------------------------------------------------------- Menu Démarrer

func _build_menu() -> void:
	catcher = Control.new(); catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.visible = false
	catcher.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: _toggle_menu())
	add_child(catcher)
	menu = PanelContainer.new(); menu.visible = false
	menu.add_theme_stylebox_override("panel", _box(Color(0.11, 0.13, 0.18, 0.97), 16, Color(1, 1, 1, 0.1), 1, 28, 12))
	add_child(menu)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 4); menu.add_child(v)
	var head := HBoxContainer.new(); v.add_child(head)
	var hi := TextureRect.new(); hi.texture = _ico("start"); hi.modulate = ACCENT; hi.custom_minimum_size = Vector2(22, 22)
	hi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; hi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; head.add_child(hi)
	var ht := Label.new(); ht.text = " LangOS"; ht.add_theme_font_size_override("font_size", 20); ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(ht)
	var hv := Label.new(); hv.text = "v" + VERSION; hv.add_theme_color_override("font_color", MUTED); hv.add_theme_font_size_override("font_size", 14); head.add_child(hv)
	var sp := Control.new(); sp.custom_minimum_size.y = 6; v.add_child(sp)
	for id in _top_ids():
		var b := _mk_btn(APPS[id][0], 300, 50); b.theme_type_variation = "Flat"; b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = load(APPS[id][1]); b.add_theme_constant_override("icon_max_width", 34)
		b.add_theme_color_override("icon_normal_color", Color.WHITE); b.add_theme_color_override("icon_hover_color", Color.WHITE)
		b.add_theme_constant_override("h_separation", 14)
		b.pressed.connect(func(): _toggle_menu(); _open_app(id))
		v.add_child(b)
	var sp2 := Control.new(); sp2.custom_minimum_size.y = 4; v.add_child(sp2)
	v.add_child(HSeparator.new())
	var q := _mk_btn("Quitter", 300, 46); q.theme_type_variation = "Flat"; q.alignment = HORIZONTAL_ALIGNMENT_LEFT
	q.icon = _ico("power"); q.add_theme_constant_override("icon_max_width", 22)
	q.add_theme_constant_override("h_separation", 14)
	q.pressed.connect(_quit); v.add_child(q)

func _toggle_menu() -> void:
	menu.visible = not menu.visible
	catcher.visible = menu.visible
	if menu.visible:
		menu.size = menu.get_combined_minimum_size()
		var end := Vector2(10, size.y - bar_h - 10 - menu.size.y)
		menu.position = end + Vector2(0, 14); menu.modulate.a = 0.0
		catcher.move_to_front(); menu.move_to_front()
		var tw := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(menu, "position", end, 0.16); tw.tween_property(menu, "modulate:a", 1.0, 0.16)

func _quit() -> void:
	if wins.has("notepad"): _save()
	get_tree().quit()

func _build_keyboard() -> void:
	kb = PanelContainer.new()
	var ks := _box(Color(0.09, 0.1, 0.14, 0.97), 16, Color(1, 1, 1, 0.1), 1, 24, 12); ks.corner_radius_bottom_left = 0; ks.corner_radius_bottom_right = 0
	kb.add_theme_stylebox_override("panel", ks)
	kb.visible = false
	add_child(kb)
	kb.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	var kv := VBoxContainer.new(); kv.alignment = BoxContainer.ALIGNMENT_CENTER
	kv.add_theme_constant_override("separation", 6); kb.add_child(kv)
	var act := HBoxContainer.new(); act.alignment = BoxContainer.ALIGNMENT_CENTER
	act.add_theme_constant_override("separation", 6); kv.add_child(act)
	for e in [["Tout", "all"], ["Copier", "copy"], ["Couper", "cut"], ["Coller", "paste"], ["↑", "up"], ["↓", "down"], ["⇤", "home"], ["⇥", "end"]]:
		var ab := _mk_btn(e[0], 92 if e[0].length() > 1 else 56, 44); ab.pressed.connect(_clip_action.bind(e[1])); act.add_child(ab)
	for r in ROWS_LOWER.size():
		var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6); kv.add_child(row)
		if r == 3:
			var sh := _mk_btn("⇧", 80); sh.pressed.connect(_toggle_shift); row.add_child(sh); shift_btns.append(sh)
		for c in ROWS_LOWER[r].size():
			var k := _mk_btn(ROWS_LOWER[r][c], 50, 50)
			k.pressed.connect(_type_key.bind(r, c))
			row.add_child(k); char_btns.append([k, r, c])
		if r == 0:
			var bs := _mk_btn("⌫", 80, 50); bs.pressed.connect(func(): _bs()); row.add_child(bs)
		if r == 1:
			var en := _mk_btn("⏎", 80, 50); en.pressed.connect(func(): _ins("\n")); row.add_child(en)
		if r == 2:
			var cp := _mk_btn("Maj", 80, 50); cp.pressed.connect(_toggle_caps); row.add_child(cp); shift_btns.append(cp)
	var last := HBoxContainer.new(); last.alignment = BoxContainer.ALIGNMENT_CENTER
	last.add_theme_constant_override("separation", 6); kv.add_child(last)
	for p in [["←", -1], ["→", 1]]:
		var a := _mk_btn(p[0], 70, 50); a.pressed.connect(_move.bind(p[1])); last.add_child(a)
	var space := _mk_btn("Espace", 420, 50); space.pressed.connect(func(): _ins(" "))
	last.add_child(space)
	var tab := _mk_btn("Tab", 70, 50); tab.pressed.connect(func(): _ins("\t")); last.add_child(tab)
	_refresh_keys()

func _target() -> Control:
	var f := get_viewport().gui_get_focus_owner()
	return f if (f is TextEdit or f is LineEdit) else null

func _ins(t: String) -> void:
	var f := _target()
	if f: f.insert_text_at_caret(t)
	else:
		var r := get_viewport().gui_get_focus_owner()
		if r and r.has_meta("remote"): r.get_meta("remote").call("send_text", t)

func _bs() -> void:
	var f := _target()
	if f == null:
		var r := get_viewport().gui_get_focus_owner()
		if r and r.has_meta("remote"): r.get_meta("remote").call("send_key", KEY_BACKSPACE)
	if f is TextEdit: f.backspace()
	elif f is LineEdit and f.caret_column > 0: f.delete_text(f.caret_column - 1, f.caret_column)

## Actions presse-papiers / curseur du clavier visuel (utile sur tablette, sans Ctrl+C / Ctrl+V).
func _clip_action(a: String) -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f is RichTextLabel:
		if a == "all": f.select_all()
		elif a == "copy" and f.get_selected_text() != "": DisplayServer.clipboard_set(f.get_selected_text())
		return
	if f is TextEdit:
		match a:
			"all": f.select_all()
			"copy": f.copy()
			"cut": if f.editable: f.cut()
			"paste": if f.editable: f.paste()
			"up": f.set_caret_line(maxi(0, f.get_caret_line() - 1))
			"down": f.set_caret_line(mini(f.get_line_count() - 1, f.get_caret_line() + 1))
			"home": f.set_caret_column(0)
			"end": f.set_caret_column(f.get_line(f.get_caret_line()).length())
	elif f is LineEdit:
		match a:
			"all": f.select_all()
			"copy": f.menu_option(LineEdit.MENU_COPY)
			"cut": f.menu_option(LineEdit.MENU_CUT)
			"paste": f.menu_option(LineEdit.MENU_PASTE)
			"home": f.caret_column = 0
			"end": f.caret_column = f.text.length()

## Clavier : « osk » = clavier visuel de LangOS (bouton de la barre), « system » = clavier normal du système, « none » = aucun (clavier physique ou secondaire).
## Mode Flex : appareil plié à moitié (charnière horizontale) → écran du haut = bureau, écran du bas = pavé tactile.
func _on_fold(json: String) -> void:
	var d = JSON.parse_string(json)
	# Mode Flex : charnière horizontale, soit état « mi-ouvert » de la bibliothèque, soit angle de charnière entre 25° et 160°
	var want: bool = d is Dictionary and FlexLogic.is_half(d, fold_half)
	if want:
		fold_px_top = float(d["top"]); fold_px_bottom = float(d["bottom"])
	fold_gen += 1
	var gen := fold_gen
	if want == fold_half: _update_flex(); return
	# le changement d'état ne s'applique qu'après 350 ms de stabilité (évite le clignotement du pavé quand la charnière vibre)
	get_tree().create_timer(0.35).timeout.connect(func():
		if gen == fold_gen: fold_half = want; _update_flex())

func _get_zoom() -> float: return float(set_cfg["zoom"])

## Zoom de l'interface (pincement à deux doigts sur le pavé, ou réglage) : 0,5 à 2,2.
func _set_zoom(z: float) -> void:
	z = clampf(snappedf(z, 0.02), 0.5, 2.2)
	if is_equal_approx(z, float(set_cfg["zoom"])): return
	set_cfg["zoom"] = z; get_window().content_scale_factor = z
	if not zoom_save:
		zoom_save = true
		get_tree().create_timer(0.8).timeout.connect(func(): zoom_save = false; _save_settings())

func _update_flex() -> void:
	if flex == null: return
	var on: bool = fold_half or bool(set_cfg["pad"])
	if fold_half:
		var inv := get_viewport().get_final_transform().affine_inverse()
		fold_top = (inv * Vector2(0, fold_px_top)).y; fold_bottom = (inv * Vector2(0, fold_px_bottom)).y
	var top := fold_top if fold_half else size.y * 0.55
	var bot := fold_bottom if fold_half else top
	var sc := get_viewport().get_final_transform().get_scale().y
	if on and (top * sc < 200.0 or (size.y - bot) * sc < 200.0): on = false   # zone trop petite (en pixels réels, donc indépendante du zoom)
	flex.visible = on
	pointer.set("pad_active", on); pointer.set("pad_top", bot if on else -1.0)
	flex.set("top_h", top)
	if on:
		flex.offset_left = 0.0; flex.offset_right = 0.0; flex.offset_top = -(size.y - bot); flex.offset_bottom = 0.0
		ui_root.offset_bottom = -(size.y - top)
		var cp: Vector2 = pointer.pos
		if cp.y < 0.0: cp = Vector2(size.x * 0.5, top * 0.5)              # première apparition : au centre de la moitié haute
		pointer.move_to(cp.clamp(Vector2.ZERO, Vector2(size.x - 1.0, maxf(1.0, top - 1.0))))   # sinon on garde la place (pas de saut quand la charnière bouge)
	else:
		ui_root.offset_bottom = 0.0

func _on_node_added(n: Node) -> void:
	if n is LineEdit or n is TextEdit: n.virtual_keyboard_enabled = set_cfg["kb"] == "system"

func _apply_kb() -> void:
	var mode: String = set_cfg["kb"]
	kb_btn.visible = mode == "osk"
	if mode != "osk": kb.visible = false
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is LineEdit or n is TextEdit: n.virtual_keyboard_enabled = mode == "system"
		stack.append_array(n.get_children())

func _toggle_kb() -> void:
	kb.visible = not kb.visible
	kb.offset_top = -(bar_h + kb.get_combined_minimum_size().y)
	kb.offset_bottom = -bar_h

# ---------------------------------------------------------------- Fenêtres

func _dlbl(t: String, sz := 17) -> Label:
	var l := Label.new(); l.text = t
	l.add_theme_font_size_override("font_size", sz)
	return l

func _mlbl(t: String, sz := 14) -> Label:
	var l := _dlbl(t, sz); l.add_theme_color_override("font_color", MUTED)
	return l

func _open_app(id: String) -> void:
	if wins.has(id):
		_show(id); return
	if FOLDERS.has(id): _app_folder(id); return
	match id:
		"chromium": _app_browser()
		"android_apps": _app_android_apps()
		"hika": _app_hika()
		"chess": _app_chess()
		"calc": _app_tool("calc", Vector2(620, 520))
		"units": _app_tool("units", Vector2(460, 560))
		"timer": _app_tool("timer", Vector2(460, 600))
		"todo": _app_tool("todo", Vector2(440, 600))
		"vault": _app_tool("vault", Vector2(440, 520))
		"cards": _app_tool("cards", Vector2(460, 640))
		"notepad": _app_notepad()
		"settings": _app_settings()
		"system": _app_system()
		"translate": _app_translate()
		"dict": _app_dict()
		"messenger": _app_messenger()
		"remote": _app_remote()
		"chat": _app_chat()
		"music": _app_music()
		"soundlink": _app_soundlink()
		"update": _app_update()

func _show(id: String) -> void:
	wins[id]["win"].visible = true
	wins[id]["win"].move_to_front()
	if kb.visible: kb.move_to_front()
	_set_active(id)

func _set_active(id: String) -> void:
	active = id
	for k in wins:
		var on: bool = k == id
		var tb: PanelContainer = wins[k]["tb"]
		var st := _box(Color("1f2432") if on else Color("171a23"), 12)
		st.corner_radius_bottom_left = 0; st.corner_radius_bottom_right = 0
		st.content_margin_left = 12; st.content_margin_right = 6; st.content_margin_top = 4; st.content_margin_bottom = 4
		tb.add_theme_stylebox_override("panel", st)
		wins[k]["title"].modulate = Color.WHITE if on else Color(1, 1, 1, 0.5)
		var t: Button = wins[k]["task"]
		if on:
			var sb := _box(Color(1, 1, 1, 0.12), 8); sb.border_width_bottom = 3; sb.border_color = ACCENT
			sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 5; sb.content_margin_bottom = 5
			t.add_theme_stylebox_override("normal", sb)
		else:
			t.remove_theme_stylebox_override("normal")

## Crée une fenêtre déplaçable ; renvoie son conteneur vertical.
func _make_window(id: String, _title: String, sz: Vector2, pos: Vector2) -> VBoxContainer:
	var title: String = APPS[id][0]
	var w := PanelContainer.new()
	w.add_theme_stylebox_override("panel", _box(Color("232834"), 12, Color(1, 1, 1, 0.1), 1, 34))
	# Petits écrans : la fenêtre ne dépasse pas le bureau ; sur téléphone (bureau étroit) elle s'ouvre agrandie.
	var ds := desk.size if desk.size.x > 100.0 else Vector2(1280, 740)
	sz = Vector2(minf(sz.x, ds.x - 8.0), minf(sz.y, ds.y - 8.0))
	pos = Vector2(clampf(pos.x, 0.0, maxf(0.0, ds.x - sz.x)), clampf(pos.y, 0.0, maxf(0.0, ds.y - sz.y)))
	w.size = sz; w.position = pos
	desk.add_child(w)
	var wv := VBoxContainer.new(); wv.add_theme_constant_override("separation", 0)
	w.add_child(wv)
	var tb := PanelContainer.new()
	tb.gui_input.connect(_title_input.bind(id))
	wv.add_child(tb)
	var tbh := HBoxContainer.new(); tbh.add_theme_constant_override("separation", 2); tb.add_child(tbh)
	var ti := TextureRect.new(); ti.texture = load(APPS[id][1]); ti.custom_minimum_size = Vector2(20, 20)
	ti.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ti.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ti.mouse_filter = Control.MOUSE_FILTER_PASS; tbh.add_child(ti)
	var tl := Label.new(); tl.text = "  " + title
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.mouse_filter = Control.MOUSE_FILTER_PASS
	tbh.add_child(tl)
	var mn := _icon_btn("minimize", "Flat", 38, 30, 14); mn.pressed.connect(_toggle_win.bind(id)); tbh.add_child(mn)
	var mx := _icon_btn("maximize", "Flat", 38, 30, 14); mx.pressed.connect(_toggle_max.bind(id)); tbh.add_child(mx)
	var cl := _icon_btn("close", "Close", 38, 30, 14); cl.pressed.connect(_close_win.bind(id)); tbh.add_child(cl)
	var tk := _mk_btn(title, 150, 42); tk.theme_type_variation = "Flat"
	tk.icon = load(APPS[id][1]); tk.add_theme_constant_override("icon_max_width", 24)
	tk.add_theme_color_override("icon_normal_color", Color.WHITE); tk.add_theme_color_override("icon_hover_color", Color.WHITE)
	tk.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tk.pressed.connect(func(): if active == id and w.visible: _toggle_win(id) else: (_show(id) if w.visible else _toggle_win(id)))
	task_box.add_child(tk)
	wins[id] = {"win": w, "task": tk, "tb": tb, "maxed": false, "saved": Rect2(), "title": tl}
	_show(id)
	var end := pos
	w.position = pos + Vector2(0, 18); w.modulate.a = 0.0
	var tw := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(w, "position", end, 0.18); tw.tween_property(w, "modulate:a", 1.0, 0.18)
	_clamp_windows.call_deferred()
	get_tree().create_timer(0.3).timeout.connect(_clamp_windows)   # après l'animation d'ouverture et la mise en place du contenu
	return wv

func _title_input(ev: InputEvent, id: String) -> void:
	var d: Dictionary = wins[id]
	var w: PanelContainer = d["win"]
	if ev is InputEventMouseButton and ev.pressed:
		_show(id)
		if ev.double_click: _toggle_max(id)
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) and not d["maxed"]:
		var p: Vector2 = w.position + ev.relative
		var lim: Vector2 = desk.size - Vector2(120, 40)
		w.position = Vector2(clampf(p.x, -w.size.x + 120, lim.x), clampf(p.y, 0, lim.y))

func _toggle_win(id: String) -> void:
	var w: PanelContainer = wins[id]["win"]
	w.visible = not w.visible
	if w.visible: _show(id)
	else: _set_active("")

func _toggle_max(id: String) -> void:
	var d: Dictionary = wins[id]
	var w: PanelContainer = d["win"]
	if d["maxed"]:
		w.position = d["saved"].position; w.size = d["saved"].size
	else:
		d["saved"] = Rect2(w.position, w.size)
		w.position = Vector2.ZERO; w.size = desk.size
	d["maxed"] = not d["maxed"]

func _close_win(id: String) -> void:
	if id == "notepad": _save()
	wins[id]["win"].queue_free(); wins[id]["task"].queue_free()
	wins.erase(id)
	_set_active("")

# ---------------------------------------------------------------- Applications

func _app_notepad() -> void:
	var wv := _make_window("notepad", "📝 Bloc-notes", Vector2(900, 560), Vector2(150, 20))
	title_lbl = wins["notepad"]["title"]
	var mm := MarginContainer.new()
	for k in ["left", "right", "top"]: mm.add_theme_constant_override("margin_" + k, 8)
	wv.add_child(mm)
	var mb := HBoxContainer.new(); mm.add_child(mb)
	for e in [["Nouveau", "new", _new], ["Enregistrer", "save", _save]]:
		var bn := _mk_btn(e[0], 100, 36); bn.theme_type_variation = "Flat"; bn.icon = _ico(e[1])
		bn.add_theme_constant_override("icon_max_width", 18); bn.add_theme_font_size_override("font_size", 16)
		bn.pressed.connect(e[2]); mb.add_child(bn)
	edit = TextEdit.new(); edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.virtual_keyboard_enabled = false
	edit.placeholder_text = "Écrivez ici…"
	edit.add_theme_font_size_override("font_size", set_cfg["font"])
	edit.text_changed.connect(func(): dirty = true; _update_status())
	edit.caret_changed.connect(_update_status)
	var em := MarginContainer.new(); em.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top"]: em.add_theme_constant_override("margin_" + k, 10)
	em.add_child(edit); wv.add_child(em)
	status = Label.new(); status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override("font_color", MUTED)
	var sm := MarginContainer.new()
	for k in ["left", "right"]: sm.add_theme_constant_override("margin_" + k, 14)
	for k in ["top", "bottom"]: sm.add_theme_constant_override("margin_" + k, 7)
	sm.add_child(status); wv.add_child(sm)
	if FileAccess.file_exists(SAVE_PATH):
		edit.text = FileAccess.get_file_as_string(SAVE_PATH)
	dirty = false
	edit.grab_focus()
	_update_status()

## ---- Paramètres : sections en cartes, lignes « libellé | réglage » qui passent à la ligne sur petit écran, défilement vertical.
func _s_card(parent: Control, title: String) -> VBoxContainer:
	var pc := PanelContainer.new(); pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := _box(Color("1c2131"), 14, Color(1, 1, 1, 0.07), 1); sb.content_margin_left = 16; sb.content_margin_right = 16; sb.content_margin_top = 14; sb.content_margin_bottom = 14
	pc.add_theme_stylebox_override("panel", sb); parent.add_child(pc)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12); pc.add_child(v)
	var h := Label.new(); h.text = title.to_upper(); h.add_theme_font_size_override("font_size", 13); h.add_theme_color_override("font_color", ACCENT); v.add_child(h)
	return v

## Une ligne de réglage : le libellé à gauche, le contrôle à droite ; s'il manque de place, le contrôle passe dessous.
func _s_row(card: Control, text: String, ctl: Control, min_ctl := 160.0) -> void:
	var f := HFlowContainer.new(); f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.add_theme_constant_override("h_separation", 12); f.add_theme_constant_override("v_separation", 6); card.add_child(f)
	var l := Label.new(); l.text = text; l.custom_minimum_size.x = 150; l.add_theme_font_size_override("font_size", 16); f.add_child(l)
	ctl.custom_minimum_size.x = maxf(ctl.custom_minimum_size.x, min_ctl); ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.add_child(ctl)

func _s_note(card: Control, text: String) -> void:
	var l := _mlbl(text, 13); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.custom_minimum_size.x = 10; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; card.add_child(l)

func _s_opt(items: Array, current: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new(); o.focus_mode = Control.FOCUS_NONE; o.clip_text = true; o.fit_to_longest_item = false
	for t in items: o.add_item(t)
	o.select(maxi(0, current)); o.item_selected.connect(cb); return o

func _s_slider(lo: float, hi: float, step: float, val: float, cb: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 10)
	var s := HSlider.new(); s.min_value = lo; s.max_value = hi; s.step = step; s.value = val; s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(110, 32); s.size_flags_horizontal = Control.SIZE_EXPAND_FILL; s.size_flags_vertical = Control.SIZE_SHRINK_CENTER; hb.add_child(s)
	var v := Label.new(); v.custom_minimum_size.x = 56; v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; v.add_theme_color_override("font_color", MUTED); hb.add_child(v)
	s.value_changed.connect(func(x: float): cb.call(x, v)); cb.call(val, v)
	return hb

func _app_settings() -> void:
	var wv := _make_window("settings", "", Vector2(600, 700), Vector2(200, 20))
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; wv.add_child(sc)
	var mg := MarginContainer.new(); mg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]: mg.add_theme_constant_override("margin_" + k, 14)
	sc.add_child(mg)
	var page := VBoxContainer.new(); page.add_theme_constant_override("separation", 14); page.size_flags_horizontal = Control.SIZE_EXPAND_FILL; mg.add_child(page)
	var ttl := Label.new(); ttl.text = "Paramètres"; ttl.add_theme_font_size_override("font_size", 26); page.add_child(ttl)

	# --- Affichage
	var c := _s_card(page, "Affichage")
	var sw := HFlowContainer.new(); sw.add_theme_constant_override("h_separation", 8); sw.add_theme_constant_override("v_separation", 8)
	for i in BG_GRADS.size():
		var b := _mk_btn("", 56, 40)
		var st := StyleBoxTexture.new(); st.texture = _grad_tex(i, 64, 44)
		var sth := StyleBoxTexture.new(); sth.texture = st.texture; sth.modulate_color = Color(1.25, 1.25, 1.25)
		b.add_theme_stylebox_override("normal", st); b.add_theme_stylebox_override("hover", sth); b.add_theme_stylebox_override("pressed", sth)
		b.pressed.connect(func(): set_cfg["bg"] = i; _apply_bg(); _save_settings())
		sw.add_child(b)
	_s_row(c, "Fond d'écran", sw, 200)
	_s_row(c, "Zoom de l'interface", _s_slider(0.5, 2.2, 0.05, float(set_cfg["zoom"]), func(x: float, l: Label): _set_zoom(x); l.text = "%d %%" % int(float(set_cfg["zoom"]) * 100)))
	_s_row(c, "Texte du Bloc-notes", _s_slider(14, 40, 1, float(set_cfg["font"]), func(x: float, l: Label):
		l.text = "%d" % int(x); set_cfg["font"] = int(x)
		if edit and is_instance_valid(edit): edit.add_theme_font_size_override("font_size", int(x))
		_save_settings()))

	# --- Souris et pavé tactile
	c = _s_card(page, "Souris et pavé tactile")
	var cmodes := ["auto", "on", "off"]
	_s_row(c, "Curseur", _s_opt(["Auto (écran tactile)", "Toujours visible", "Jamais"], cmodes.find(set_cfg["cursor"]),
		func(i: int): set_cfg["cursor"] = cmodes[i]; _save_settings(); pointer.set("mode", cmodes[i]); pointer.queue_redraw()))
	var pc := CheckButton.new(); pc.focus_mode = Control.FOCUS_NONE; pc.button_pressed = bool(set_cfg["pad"]); pc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pc.toggled.connect(func(on: bool): set_cfg["pad"] = on; _save_settings(); _update_flex())
	_s_row(c, "Pavé tactile", pc, 60)
	_s_row(c, "Vitesse du curseur", _s_slider(0.2, 2.5, 0.1, float(set_cfg["pad_speed"]), func(x: float, l: Label): set_cfg["pad_speed"] = x; l.text = "%.1f" % x; flex.set("gain", x); _save_settings()))
	_s_note(c, "Le pavé s'affiche en bas de l'écran, et tout seul quand un téléphone pliable est plié à moitié. Deux doigts qui s'écartent ou se rapprochent dessus règlent le zoom.")

	# --- Clavier
	c = _s_card(page, "Clavier")
	var kmodes := ["osk", "system", "none"]
	_s_row(c, "Clavier", _s_opt(["Visuel LangOS", "Normal du système", "Aucun"], kmodes.find(set_cfg["kb"]), func(i: int): set_cfg["kb"] = kmodes[i]; _save_settings(); _apply_kb()))
	_s_note(c, "Visuel : bouton dans la barre des tâches. Aucun : pour un clavier physique ou secondaire.")

	# --- Langues
	c = _s_card(page, "Langues (Traducteur, Dictionnaire, Music)")
	var names: Array = GL.map(func(l): return l[0])
	var so := _s_opt(names, GL.find_custom(func(l): return l[1] == set_cfg["src"]), func(i: int): set_cfg["src"] = GL[i][1]; _apply_langs())
	var to := _s_opt(names, GL.find_custom(func(l): return l[1] == set_cfg["tgt"]), func(i: int): set_cfg["tgt"] = GL[i][1]; _apply_langs())
	_s_row(c, "Langue d'origine", so); _s_row(c, "Traduire vers", to)
	var swp := _mk_btn("⇄  Inverser les deux langues", 0, 42)
	swp.pressed.connect(func():
		var t: String = set_cfg["src"]; set_cfg["src"] = set_cfg["tgt"]; set_cfg["tgt"] = t
		so.select(GL.find_custom(func(l): return l[1] == set_cfg["src"])); to.select(GL.find_custom(func(l): return l[1] == set_cfg["tgt"])); _apply_langs())
	c.add_child(swp)

	# --- Android : écran d'accueil
	if OS.get_name() == "Android" and Engine.has_singleton("LangLauncher"):
		c = _s_card(page, "Écran d'accueil")
		var hb := _mk_btn("Choisir l'écran d'accueil", 0, 46); hb.pressed.connect(func(): Engine.get_singleton("LangLauncher").chooseHome()); c.add_child(hb)
		_s_note(c, "Android affiche la liste des écrans d'accueil : choisis LangOS pour l'utiliser, ou ton ancien pour y revenir.")

	# --- Serveur de traduction
	c = _s_card(page, "Serveur de traduction (Ollama)")
	var le := LineEdit.new(); le.text = set_cfg["ollama"]; le.virtual_keyboard_enabled = false; le.placeholder_text = "http://127.0.0.1:11434"
	le.text_changed.connect(func(t: String): set_cfg["ollama"] = t.strip_edges().rstrip("/"); _save_settings())
	_s_row(c, "Adresse", le, 200)
	_s_note(c, "Sur téléphone : adresse d'un PC qui fait tourner Ollama, par exemple http://192.168.1.20:11434. Sinon le Traducteur utilise le modèle sur l'appareil.")

	# --- À propos
	c = _s_card(page, "À propos")
	_s_note(c, "LangOS version %s" % VERSION)

func _app_system() -> void:
	var wv := _make_window("system", "🖥 Système", Vector2(520, 360), Vector2(260, 80))
	var m := MarginContainer.new(); m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 18)
	wv.add_child(m)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); m.add_child(v)
	var gv := Engine.get_version_info()
	var mem := OS.get_memory_info()
	var rows := [
		["Application", "Bloc-notes v" + VERSION],
		["Système", "%s %s" % [OS.get_name(), OS.get_version()]],
		["Moteur", "Godot %s" % gv["string"]],
		["Processeur", "%s (%d cœurs)" % [OS.get_processor_name(), OS.get_processor_count()]],
		["Carte graphique", RenderingServer.get_video_adapter_name()],
		["Mémoire", "%d Mo" % (int(mem.get("physical", 0)) / 1048576) if int(mem.get("physical", 0)) > 0 else "inconnue"],
		["Écran", "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]],
		["Données", ProjectSettings.globalize_path("user://")],
	]
	for r in rows:
		var h := HBoxContainer.new(); v.add_child(h)
		var k := _dlbl(r[0], 16); k.custom_minimum_size.x = 140; h.add_child(k)
		var val := _dlbl(str(r[1]), 16); val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY; h.add_child(val)

func _app_update() -> void:
	var wv := _make_window("update", "⬆ Mise à jour", Vector2(480, 240), Vector2(280, 100))
	var m := MarginContainer.new(); m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 18)
	wv.add_child(m)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 14); m.add_child(v)
	v.add_child(_dlbl("Version installée : " + VERSION, 20))
	upd_lbl = _dlbl("", 16); upd_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(upd_lbl)
	upd_btn = _mk_btn("Vérifier", 240, 46); upd_btn.theme_type_variation = "Accent"; upd_btn.pressed.connect(_do_update); v.add_child(upd_btn)
	_set_upd(upd_lbl_text, upd_btn_text)
	if upd_http == null or upd_btn_text == "Vérifier": _check_update()

# ---------------------------------------------------------------- Traducteur (modèle local, sans API)

const GL := [["Français", "fra", "French"], ["English", "eng", "English"], ["Español", "spa", "Spanish"], ["Deutsch", "deu", "German"],
	["Italiano", "ita", "Italian"], ["Português", "por", "Portuguese"], ["Nederlands", "nld", "Dutch"], ["日本語", "jpn", "Japanese"]]
var music_node: Control
var desk_icons: Array = []
var lp_active := false
var lp_pos := Vector2.ZERO
var lp_t := 0
var ctx_menu: PanelContainer
var ctx_catcher: Control
var ctx_target: Control
var tr_pair: Label

func _gname(code: String, i := 0) -> String:
	for l in GL:
		if l[1] == code: return l[i if i != 2 else 2] if i != 1 else l[0]
	return code

func _pair_text() -> String:
	return "%s  →  %s" % [_gname(set_cfg["src"], 1), _gname(set_cfg["tgt"], 1)]

func _apply_langs() -> void:
	_save_settings()
	if wins.has("translate") and is_instance_valid(tr_pair): tr_pair.text = _pair_text()
	if wins.has("dict"): _dic_load()
	if wins.has("music") and is_instance_valid(music_node): music_node.call("set_langs", set_cfg["src"], set_cfg["tgt"])
const LOCAL_URL := "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"
const LOCAL_FILE := "user://models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
const LOCAL_MIN := 1000000000
var tr_http: HTTPRequest
var tr_dl: HTTPRequest
var tr_llm: Object
var tr_engine: OptionButton
var tr_srv: HBoxContainer
var tr_timer: Timer
var tr_tags: HTTPRequest
var tr_model: OptionButton
var tr_in: TextEdit
var tr_out: TextEdit
var tr_status: Label
var tr_btn: Button
var tr_t0 := 0

func _app_translate() -> void:
	var wv := _make_window("translate", "", Vector2(800, 520), Vector2(190, 36))
	var m := MarginContainer.new(); m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 14)
	wv.add_child(m)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); m.add_child(v)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); v.add_child(row)
	tr_pair = _dlbl(_pair_text(), 18)
	var sw := _mk_btn("⇄", 48, 40); sw.pressed.connect(_tr_swap)
	row.add_child(tr_pair); row.add_child(sw)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(sp)
	tr_engine = OptionButton.new(); tr_engine.focus_mode = Control.FOCUS_NONE
	tr_engine.add_item("Sur l'appareil"); tr_engine.add_item("Serveur Ollama")
	if set_cfg["engine"] < 0: set_cfg["engine"] = 0 if OS.has_feature("android") else 1
	tr_engine.select(set_cfg["engine"])
	tr_engine.item_selected.connect(func(i: int): set_cfg["engine"] = i; _save_settings(); _tr_engine_changed())
	row.add_child(tr_engine)
	tr_model = OptionButton.new(); tr_model.focus_mode = Control.FOCUS_NONE
	tr_model.item_selected.connect(func(i: int): set_cfg["model"] = tr_model.get_item_text(i); _save_settings())
	row.add_child(tr_model)
	var srv := HBoxContainer.new(); srv.add_theme_constant_override("separation", 8); v.add_child(srv); tr_srv = srv
	srv.add_child(_mlbl("Serveur"))
	var le := LineEdit.new(); le.text = set_cfg["ollama"]; le.virtual_keyboard_enabled = false
	le.placeholder_text = "http://IP-du-PC:11434"; le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srv.add_child(le)
	var cn := _mk_btn("Connecter", 120, 38); cn.theme_type_variation = "Flat"
	cn.pressed.connect(func():
		var t := le.text.strip_edges().rstrip("/")
		if not t.begins_with("http"): t = "http://" + t
		if not ":" in t.substr(7): t += ":11434"
		le.text = t; set_cfg["ollama"] = t; _save_settings(); _tr_models())
	srv.add_child(cn)
	var tx := HBoxContainer.new(); tx.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tx.add_theme_constant_override("separation", 10); v.add_child(tx)
	tr_in = TextEdit.new(); tr_out = TextEdit.new()
	for t in [tr_in, tr_out]:
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; t.virtual_keyboard_enabled = false
		t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; t.add_theme_font_size_override("font_size", 20); tx.add_child(t)
	tr_in.placeholder_text = "Texte à traduire…"; tr_out.editable = false; tr_out.placeholder_text = "Traduction"
	var bt := HBoxContainer.new(); bt.add_theme_constant_override("separation", 8); v.add_child(bt)
	tr_status = _mlbl("", 14); tr_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; bt.add_child(tr_status)
	var cp := _mk_btn("Copier", 90, 42); cp.theme_type_variation = "Flat"
	cp.pressed.connect(func(): DisplayServer.clipboard_set(tr_out.text)); bt.add_child(cp)
	tr_btn = _mk_btn("Traduire", 130, 42); tr_btn.theme_type_variation = "Accent"
	tr_btn.pressed.connect(_tr_translate); bt.add_child(tr_btn)
	tr_in.grab_focus()
	_tr_engine_changed()

func _tr_engine_changed() -> void:
	var local: bool = set_cfg["engine"] == 0
	tr_srv.visible = not local; tr_model.visible = not local
	tr_btn.text = "Traduire"; tr_btn.disabled = false
	if local: _tr_local_check()
	else: _tr_models()

func _tr_local_check() -> void:
	if not ClassDB.class_exists("GDLlama"):
		tr_status.text = "Moteur local indisponible sur cet appareil : utiliser « Serveur Ollama »."
		tr_btn.disabled = true
	elif not _tr_model_ok():
		tr_status.text = "Modèle local à télécharger une seule fois (≈ 1,1 Go, Wi-Fi conseillé)."
		tr_btn.text = "Télécharger le modèle"
	else:
		tr_status.text = "Prêt (sur l'appareil, hors ligne)."

func _tr_model_ok() -> bool:
	if not FileAccess.file_exists(LOCAL_FILE): return false
	var f := FileAccess.open(LOCAL_FILE, FileAccess.READ)
	return f != null and f.get_length() > LOCAL_MIN

func _tr_download() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://models"))
	if tr_dl == null:
		tr_dl = HTTPRequest.new(); tr_dl.download_chunk_size = 1048576; tr_dl.timeout = 0.0; add_child(tr_dl)
		tr_dl.request_completed.connect(_on_tr_dl)
		tr_timer = Timer.new(); tr_timer.wait_time = 0.5; add_child(tr_timer)
		tr_timer.timeout.connect(func():
			if is_instance_valid(tr_status) and tr_dl.get_body_size() > 0:
				tr_status.text = "Téléchargement du modèle : %d %%  (%d / %d Mo)" % [100 * tr_dl.get_downloaded_bytes() / tr_dl.get_body_size(), tr_dl.get_downloaded_bytes() / 1048576, tr_dl.get_body_size() / 1048576])
	tr_dl.download_file = ProjectSettings.globalize_path("user://models/model.tmp")
	tr_btn.disabled = true; tr_status.text = "Téléchargement du modèle…"
	tr_timer.start()
	var err := tr_dl.request(LOCAL_URL)
	if err != OK: tr_status.text = "Téléchargement impossible (réseau ?)."; tr_btn.disabled = false; tr_timer.stop()

func _on_tr_dl(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	tr_timer.stop()
	var tmp := "user://models/model.tmp"
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200 and FileAccess.file_exists(tmp)
	if ok:
		var f := FileAccess.open(tmp, FileAccess.READ); ok = f != null and f.get_length() > LOCAL_MIN
	if not ok:
		DirAccess.remove_absolute(tmp)
		if is_instance_valid(tr_status): tr_status.text = "Échec du téléchargement, réessayer."; tr_btn.disabled = false
		return
	DirAccess.rename_absolute(tmp, LOCAL_FILE)
	if is_instance_valid(tr_status): _tr_engine_changed()

func _tr_local_translate(text: String) -> void:
	if tr_llm == null:
		tr_llm = ClassDB.instantiate("GDLlama")
		add_child(tr_llm)
		tr_llm.set("model_path", ProjectSettings.globalize_path(LOCAL_FILE))
		tr_llm.set("n_predict", 400); tr_llm.set("n_ctx", 2048)
		tr_llm.set("should_output_prompt", false); tr_llm.set("should_output_special", false)
		tr_llm.set("n_threads", maxi(2, OS.get_processor_count() / 2))
		tr_llm.connect("generate_text_finished", _on_tr_local_done)
	var from_part := "from %s " % _gname(set_cfg["src"], 2)
	var sys := "You are a translation engine. Translate the user's text %sinto %s. Output ONLY the translation: no notes, no quotes, no explanations." % [from_part, _gname(set_cfg["tgt"], 2)]
	var prompt := "<|im_start|>system\n%s<|im_end|>\n<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n" % [sys, text]
	tr_btn.disabled = true; tr_status.text = "Traduction sur l'appareil (le premier appel charge le modèle)…"
	tr_t0 = Time.get_ticks_msec()
	tr_llm.call("run_generate_text", prompt, "", "")

func _on_tr_local_done(t: String) -> void:
	if not is_instance_valid(tr_out): return
	tr_btn.disabled = false
	var out := t.get_slice("<|im_end|>", 0).strip_edges()
	tr_out.text = out
	tr_status.text = "✓ %.1f s — traduit sur l'appareil" % ((Time.get_ticks_msec() - tr_t0) / 1000.0)

func _tr_swap() -> void:
	var s: String = set_cfg["src"]; set_cfg["src"] = set_cfg["tgt"]; set_cfg["tgt"] = s
	var t := tr_in.text; tr_in.text = tr_out.text; tr_out.text = t
	_apply_langs()

func _tr_models() -> void:
	if tr_tags == null: tr_tags = HTTPRequest.new(); tr_tags.timeout = 5.0; add_child(tr_tags)
	tr_status.text = "Connexion au modèle local…"
	if not tr_tags.request_completed.is_connected(_on_tr_tags): tr_tags.request_completed.connect(_on_tr_tags)
	tr_tags.request(set_cfg["ollama"] + "/api/tags")

func _on_tr_tags(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if not is_instance_valid(tr_model): return
	var info = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if not (info is Dictionary) or not info.has("models"):
		tr_status.text = ("Sur téléphone, « Serveur » = adresse du PC (ex. http://192.168.1.20:11434), Ollama lancé avec OLLAMA_HOST=0.0.0.0, même Wi-Fi." \
			if OS.has_feature("android") else "Modèle local introuvable : lancer « ollama serve » ou régler le serveur ci-dessus.")
		tr_btn.disabled = true; return
	tr_model.clear()
	var names: Array = []
	for mm in info["models"]: names.append(str(mm["name"]))
	names.sort_custom(func(a, b): return _tr_rank(a) < _tr_rank(b))
	for n in names: tr_model.add_item(n)
	var pick := names.find(set_cfg["model"])
	tr_model.select(maxi(pick, 0))
	tr_btn.disabled = names.is_empty()
	tr_status.text = "Prêt (local, hors ligne)." if not names.is_empty() else "Aucun modèle : « ollama pull gemma3:4b »."

## Petits modèles rapides en premier ; les modèles « raisonnement » en dernier.
func _tr_rank(n: String) -> int:
	if n.begins_with("gemma3:4b"): return 0
	if n.begins_with("llama3.2:3b"): return 1
	if n.begins_with("gemma"): return 2
	if n.begins_with("qwen3") or "coder" in n or "vision" in n: return 9
	return 5

func _tr_translate() -> void:
	if set_cfg["engine"] == 0:
		if not _tr_model_ok(): _tr_download(); return
		var lt := tr_in.text.strip_edges()
		if not lt.is_empty(): _tr_local_translate(lt)
		return
	var text := tr_in.text.strip_edges()
	if text.is_empty() or tr_model.item_count == 0: return
	if tr_http == null: tr_http = HTTPRequest.new(); tr_http.timeout = 180.0; add_child(tr_http)
	var from_part := "from %s " % _gname(set_cfg["src"], 2)
	var sys := "You are a translation engine. Translate the user's text %sinto %s. Output ONLY the translation: no notes, no quotes, no explanations." % [from_part, _gname(set_cfg["tgt"], 2)]
	var body := {"model": tr_model.get_item_text(tr_model.selected), "stream": false, "keep_alive": "10m",
		"options": {"temperature": 0.1, "num_predict": 1024},
		"messages": [{"role": "system", "content": sys}, {"role": "user", "content": text}]}
	tr_btn.disabled = true; tr_status.text = "Traduction…"; tr_t0 = Time.get_ticks_msec()
	if not tr_http.request_completed.is_connected(_on_tr_done): tr_http.request_completed.connect(_on_tr_done)
	tr_http.request(set_cfg["ollama"] + "/api/chat", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))

func _on_tr_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if not is_instance_valid(tr_out): return
	tr_btn.disabled = false
	var info = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if not (info is Dictionary) or not info.has("message"):
		tr_status.text = "Échec de la traduction (serveur local arrêté ?)."; return
	var rx := RegEx.create_from_string("(?s)<think>.*?</think>")
	tr_out.text = rx.sub(str(info["message"]["content"]), "", true).strip_edges()
	tr_status.text = "✓ %.1f s — traduit localement" % ((Time.get_ticks_msec() - tr_t0) / 1000.0)

# ---------------------------------------------------------------- RemoteDesk (app intégrée)

func _app_remote() -> void:
	var wv := _make_window("remote", "", Vector2(940, 620), Vector2(130, 18))
	var rd := Control.new()
	rd.set_script(load("res://apps/remotedesk.gd"))
	rd.size_flags_vertical = Control.SIZE_EXPAND_FILL; rd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rd.custom_minimum_size = Vector2(320, 360); rd.clip_contents = true
	wv.add_child(rd)

# ---------------------------------------------------------------- Messenger (app intégrée)

func _app_messenger() -> void:
	var wv := _make_window("messenger", "", Vector2(960, 620), Vector2(120, 20))
	var ms := Control.new()
	ms.set_script(load("res://apps/messenger.gd"))
	ms.size_flags_vertical = Control.SIZE_EXPAND_FILL; ms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ms.custom_minimum_size = Vector2(320, 360); ms.clip_contents = true
	wv.add_child(ms)

# ---------------------------------------------------------------- Chat IA (app + overlay « - »)

var chat_core: ChatCore
var chat_ov: ChatOverlay
var ctl := PacketPeerUDP.new()

func _setup_chat() -> void:
	chat_core = ChatCore.new(); add_child(chat_core)
	if OS.has_feature("mobile"): return
	chat_ov = ChatOverlay.new(); chat_ov.core = chat_core; add_child(chat_ov)
	# Canal de commande local : le raccourci global du système envoie « toggle-chat » (voir langos-chat.sh)
	var cport := 4360
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ctl-port="): cport = a.get_slice("=", 1).to_int()
	var be := ctl.bind(cport, "127.0.0.1")
	if be != OK: push_warning("Port 4360 occupé : raccourci global du chat indisponible (%d)" % be)

func _poll_ctl() -> void:
	while ctl.is_bound() and ctl.get_available_packet_count() > 0:
		var cmd := ctl.get_packet().get_string_from_utf8().strip_edges()
		if cmd == "toggle-chat" and chat_ov: chat_ov.toggle()
		elif cmd == "show-chat" and chat_ov: chat_ov.show_chat()

func _app_chat() -> void:
	var wv := _make_window("chat", "", Vector2(820, 600), Vector2(160, 20))
	var c := Control.new()
	c.set_script(load("res://apps/chat.gd"))
	c.set("core", chat_core)
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(320, 360); c.clip_contents = true
	wv.add_child(c)

# ---------------------------------------------------------------- Music (app intégrée)

func _app_music() -> void:
	var big := Vector2(minf(1500.0, desk.size.x - 24.0), minf(900.0, desk.size.y - 16.0))
	var wv := _make_window("music", "", big, Vector2(12, 8))
	var mu := Control.new()
	mu.set_script(load("res://apps/music.gd"))
	mu.set("ollama_url", set_cfg["ollama"]); mu.set("src", set_cfg["src"]); mu.set("tgt", set_cfg["tgt"]); music_node = mu
	mu.size_flags_vertical = Control.SIZE_EXPAND_FILL; mu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mu.custom_minimum_size = Vector2(320, 360); mu.clip_contents = true
	wv.add_child(mu)

# ---------------------------------------------------------------- Dossiers et Échecs

func _app_folder(fid: String) -> void:
	var wv := _make_window(fid, "", Vector2(420, 300), Vector2(200 + randi() % 60, 60 + randi() % 40))
	var g := GridContainer.new(); g.columns = 3; g.size_flags_vertical = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 8); g.add_theme_constant_override("v_separation", 8)
	var m := MarginContainer.new(); m.add_theme_constant_override("margin_left", 12); m.add_theme_constant_override("margin_top", 12)
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL; m.add_child(g); wv.add_child(m)
	for id in FOLDERS[fid]:
		var b := Button.new(); b.theme_type_variation = "Flat"; b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(120, 100)
		var v := VBoxContainer.new(); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_preset(Control.PRESET_FULL_RECT); v.alignment = BoxContainer.ALIGNMENT_CENTER; b.add_child(v)
		var t := TextureRect.new(); t.texture = load(APPS[id][1]); t.custom_minimum_size = Vector2(56, 56)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(t)
		var l := Label.new(); l.text = APPS[id][0]; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(l)
		b.pressed.connect(_open_app.bind(id)); g.add_child(b)

## Lance Chromium (ou, à défaut, Chrome / Chromium Flatpak) hors de LangOS ; sur Android, le navigateur par défaut.
func _launch_browser() -> void:
	if OS.get_name() == "Android": OS.shell_open("https://www.google.com"); return
	var sh := "for b in chromium chromium-browser google-chrome google-chrome-stable; do command -v $b >/dev/null 2>&1 && exec $b; done; flatpak info org.chromium.Chromium >/dev/null 2>&1 && exec flatpak run org.chromium.Chromium; exit 127"
	var args := ["-c", sh]
	var cmd := "sh"
	if FileAccess.file_exists("/.flatpak-info"): cmd = "flatpak-spawn"; args = ["--host", "sh", "-c", sh]   # Godot lancé en Flatpak
	if OS.create_process(cmd, args) < 0: status.text = "Impossible de lancer Chromium."
	else: status.text = "Chromium lancé (s'il est installé : sudo apt install chromium)."

func _app_android_apps() -> void:
	var big := Vector2(minf(900.0, desk.size.x - 24.0), minf(640.0, desk.size.y - 16.0))
	var wv := _make_window("android_apps", "", big, Vector2(30, 12))
	var c := Control.new(); c.set_script(load("res://apps/android_apps.gd"))
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(320, 360); c.clip_contents = true; wv.add_child(c)

func _app_browser() -> void:
	var big := Vector2(minf(1100.0, desk.size.x - 24.0), minf(700.0, desk.size.y - 16.0))
	var wv := _make_window("chromium", "", big, Vector2(20, 10))
	var br := Control.new(); br.set_script(load("res://apps/browser.gd")); br.set("external", Callable(self, "_launch_browser"))
	br.size_flags_vertical = Control.SIZE_EXPAND_FILL; br.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.custom_minimum_size = Vector2(320, 360); br.clip_contents = true; wv.add_child(br)

func _app_hika() -> void:
	var big := Vector2(minf(1100.0, desk.size.x - 24.0), minf(700.0, desk.size.y - 16.0))
	var wv := _make_window("hika", "", big, Vector2(12, 8))
	var h := Control.new(); h.set_script(load("res://apps/hika_host.gd"))
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL; h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.custom_minimum_size = Vector2(320, 360); wv.add_child(h)

## Petits outils (dossier Outils) : un script apps/tool_<id>.gd par outil.
func _app_tool(id: String, sz: Vector2) -> void:
	var wv := _make_window(id, "", sz + Vector2(0, 60), Vector2(200 + randi() % 80, 20 + randi() % 40))
	var c := Control.new()
	c.set_script(load("res://apps/tool_%s.gd" % id))
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(minf(sz.x, maxf(280.0, desk.size.x - 16.0)), sz.y); c.clip_contents = true
	wv.add_child(c)

func _app_chess() -> void:
	var wv := _make_window("chess", "", Vector2(900, 680), Vector2(180, 10))
	var ch := Control.new()
	ch.set_script(load("res://apps/chess.gd"))
	ch.size_flags_vertical = Control.SIZE_EXPAND_FILL; ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.custom_minimum_size = Vector2(320, 360); ch.clip_contents = true
	wv.add_child(ch)

# ---------------------------------------------------------------- Sound Link (app intégrée)

func _app_soundlink() -> void:
	var wv := _make_window("soundlink", "", Vector2(500, 740), Vector2(240, 16))
	var sl := Control.new()
	sl.set_script(load("res://apps/soundlink.gd"))
	sl.size_flags_vertical = Control.SIZE_EXPAND_FILL; sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(320, 360); sl.clip_contents = true
	wv.add_child(sl)

# ---------------------------------------------------------------- Dictionnaire (hors ligne, données FreeDict)

const DIC_LANGS := {"fra": "Français", "eng": "English", "spa": "Español", "ita": "Italiano", "por": "Português", "nld": "Nederlands", "jpn": "日本語"}
const DIC_PAIRS := ["fra-eng", "eng-fra", "spa-eng", "eng-spa", "ita-eng", "eng-ita", "por-eng", "eng-por", "nld-eng", "eng-nld", "jpn-eng", "eng-jpn"]
const DIC_PAGE := 200
const ACC := {"à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a", "ç": "c", "è": "e", "é": "e", "ê": "e", "ë": "e",
	"ì": "i", "í": "i", "î": "i", "ï": "i", "ñ": "n", "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o", "ù": "u", "ú": "u", "û": "u", "ü": "u", "ý": "y", "ÿ": "y"}
var dic_note: Label
var dic_search: LineEdit
var dic_list: ItemList
var dic_def: RichTextLabel
var dic_info: Label
var dic_lines := PackedStringArray()
var dic_start := 0
var dic_loading := false

func _dkey(t: String) -> String:
	var o := ""
	for c in t.strip_edges().to_lower(): o += ACC.get(c, c)
	return o

func _app_dict() -> void:
	var wv := _make_window("dict", "", Vector2(920, 580), Vector2(170, 24))
	var mm := MarginContainer.new(); mm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]: mm.add_theme_constant_override("margin_" + k, 14)
	wv.add_child(mm)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); mm.add_child(v)
	dic_note = _mlbl("", 14); v.add_child(dic_note)
	dic_search = LineEdit.new(); dic_search.placeholder_text = "Rechercher un mot…"; dic_search.virtual_keyboard_enabled = false
	dic_search.clear_button_enabled = true; dic_search.add_theme_font_size_override("font_size", 20)
	dic_search.text_changed.connect(_dic_search); v.add_child(dic_search)
	var hb := HBoxContainer.new(); hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 10); v.add_child(hb)
	var left := VBoxContainer.new(); left.custom_minimum_size.x = 330; left.add_theme_constant_override("separation", 6); hb.add_child(left)
	dic_list = ItemList.new(); dic_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dic_list.item_selected.connect(_dic_show); left.add_child(dic_list)
	var pg := HBoxContainer.new(); pg.add_theme_constant_override("separation", 6); left.add_child(pg)
	var pv := _mk_btn("◀", 48, 36); pv.pressed.connect(_dic_page.bind(-1)); pg.add_child(pv)
	dic_info = _mlbl("", 13); dic_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dic_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; pg.add_child(dic_info)
	var nx := _mk_btn("▶", 48, 36); nx.pressed.connect(_dic_page.bind(1)); pg.add_child(nx)
	var pc := PanelContainer.new(); pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", _box(Color("171b25"), 10, Color(1, 1, 1, 0.07), 1, 0, 16)); hb.add_child(pc)
	dic_def = RichTextLabel.new(); dic_def.bbcode_enabled = true; dic_def.selection_enabled = true; dic_def.context_menu_enabled = true
	dic_def.add_theme_font_size_override("normal_font_size", 20); dic_def.add_theme_font_size_override("bold_font_size", 28)
	pc.add_child(dic_def)
	_dic_load()

## Fichier à utiliser pour la paire des paramètres ; repli sur « langue → English » si pas de dictionnaire direct.
func _dic_pair() -> String:
	var s: String = set_cfg["src"]; var t: String = set_cfg["tgt"]
	if FileAccess.file_exists("res://dicts/%s-%s.tsv" % [s, t]): return "%s-%s" % [s, t]
	if s != "eng" and FileAccess.file_exists("res://dicts/%s-eng.tsv" % s): return "%s-eng" % s
	return ""

func _dic_load() -> void:
	var pair := _dic_pair()
	dic_list.clear(); dic_def.text = ""
	if pair == "":
		dic_lines = PackedStringArray(); dic_info.text = ""
		dic_note.text = "%s : pas de dictionnaire pour cette langue." % _pair_text(); return
	var real := "%s  →  %s" % [_gname(pair.get_slice("-", 0), 1), _gname(pair.get_slice("-", 1), 1)]
	dic_note.text = real if real == _pair_text() else "%s  (pas de dictionnaire direct vers %s : traductions en anglais)" % [real, _gname(set_cfg["tgt"], 1)]
	var path := "res://dicts/%s.tsv" % pair
	dic_info.text = "Chargement…"
	dic_loading = true
	await get_tree().process_frame
	if not is_instance_valid(dic_list): return
	dic_lines = FileAccess.get_file_as_string(path).split("\n", false)
	dic_loading = false
	dic_search.text = ""; dic_start = 0
	_dic_refresh(); dic_search.grab_focus()

func _dic_refresh() -> void:
	dic_list.clear()
	var n := dic_lines.size()
	dic_start = clampi(dic_start, 0, maxi(0, n - 1))
	var e := mini(n, dic_start + DIC_PAGE)
	for i in range(dic_start, e): dic_list.add_item(dic_lines[i].get_slice("\t", 1))
	dic_info.text = "%d–%d / %d mots" % [dic_start + 1, e, n]
	if dic_list.item_count > 0: dic_list.select(0); _dic_show(0)
	else: dic_def.text = ""

func _dic_page(d: int) -> void:
	if dic_loading: return
	dic_start += d * DIC_PAGE; _dic_refresh()

func _dic_search(t: String) -> void:
	if dic_loading: return
	var k := _dkey(t)
	if k.is_empty(): dic_start = 0
	else:
		var lo := 0; var hi := dic_lines.size()
		while lo < hi:
			var mid := (lo + hi) / 2
			if dic_lines[mid].get_slice("\t", 0) < k: lo = mid + 1
			else: hi = mid
		dic_start = lo
	_dic_refresh()

func _dic_show(i: int) -> void:
	var line := dic_lines[dic_start + i]
	var word := line.get_slice("\t", 1).replace("[", "[lb]")
	var out := "[b]%s[/b]\n\n" % word
	for d in line.get_slice("\t", 2).split("¶"):
		var t := d.replace("[", "[lb]")
		if t.begins_with("("):
			var e := t.find(")")
			out += "[color=#8f9bb3]%s[/color] %s\n\n" % [t.substr(0, e + 1), t.substr(e + 1)]
		else: out += t + "\n\n"
	dic_def.text = out

# ---------------------------------------------------------------- Réglages

func _load_settings() -> void:
	var c := ConfigFile.new()
	if c.load("user://settings.cfg") == OK:
		set_cfg["bg"] = clampi(int(c.get_value("ui", "bg", 0)), 0, BG_GRADS.size() - 1)
		set_cfg["font"] = clampi(int(c.get_value("ui", "font", 22)), 14, 40)
		set_cfg["ollama"] = str(c.get_value("translate", "server", set_cfg["ollama"]))
		set_cfg["model"] = str(c.get_value("translate", "model", ""))
		set_cfg["kb"] = str(c.get_value("ui", "kb", "osk")); set_cfg["cursor"] = str(c.get_value("ui", "cursor", "auto")); set_cfg["pad"] = bool(c.get_value("ui", "pad", false)); set_cfg["pad_speed"] = clampf(float(c.get_value("ui", "pad_speed", 0.7)), 0.2, 2.5); set_cfg["zoom"] = clampf(float(c.get_value("ui", "zoom", 1.0)), 0.5, 2.2)
		set_cfg["engine"] = int(c.get_value("translate", "engine", -1))
		set_cfg["src"] = str(c.get_value("lang", "src", "spa")); set_cfg["tgt"] = str(c.get_value("lang", "tgt", "fra"))

func _save_settings() -> void:
	var c := ConfigFile.new()
	c.set_value("ui", "bg", set_cfg["bg"]); c.set_value("ui", "font", set_cfg["font"]); c.set_value("ui", "kb", set_cfg["kb"]); c.set_value("ui", "cursor", set_cfg["cursor"]); c.set_value("ui", "pad", set_cfg["pad"]); c.set_value("ui", "pad_speed", set_cfg["pad_speed"]); c.set_value("ui", "zoom", set_cfg["zoom"])
	c.set_value("translate", "server", set_cfg["ollama"]); c.set_value("translate", "model", set_cfg["model"]); c.set_value("translate", "engine", set_cfg["engine"])
	c.set_value("lang", "src", set_cfg["src"]); c.set_value("lang", "tgt", set_cfg["tgt"])
	c.save("user://settings.cfg")

func _type_key(r: int, c: int) -> void:
	var up := shift != caps
	_ins((ROWS_UPPER if up else ROWS_LOWER)[r][c])
	if shift: shift = false; _refresh_keys()

func _toggle_shift() -> void:
	shift = not shift; _refresh_keys()

func _toggle_caps() -> void:
	caps = not caps; _refresh_keys()

func _refresh_keys() -> void:
	var up := shift != caps
	for e in char_btns:
		e[0].text = (ROWS_UPPER if up else ROWS_LOWER)[e[1]][e[2]]
	shift_btns[0].modulate = ACCENT.lightened(0.3) if shift else Color.WHITE
	shift_btns[1].modulate = ACCENT.lightened(0.3) if caps else Color.WHITE

func _move(d: int) -> void:
	var f := _target()
	if f is TextEdit: f.set_caret_column(clampi(f.get_caret_column() + d, 0, f.get_line(f.get_caret_line()).length()))
	elif f is LineEdit: f.caret_column = clampi(f.caret_column + d, 0, f.text.length())

func _new() -> void:
	edit.text = ""; dirty = true; _update_status()

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f: f.store_string(edit.text); f.close()
	dirty = false; _update_status()

func _update_status() -> void:
	if not edit or not is_instance_valid(edit): return
	status.text = "  Ligne %d, Col %d   •   %d caractères   •   %s" % [
		edit.get_caret_line() + 1, edit.get_caret_column() + 1, edit.text.length(),
		"modifié" if dirty else "enregistré"]
	if title_lbl and is_instance_valid(title_lbl): title_lbl.text = "  Bloc-notes" + (" •" if dirty else "")


# ---------------------------------------------------------------- Mise à jour

var upd_lbl_text := ""
var upd_btn_text := "Vérifier"

func _set_upd(label: String, btn: String, disabled := false) -> void:
	upd_lbl_text = label; upd_btn_text = btn
	if upd_lbl and is_instance_valid(upd_lbl): upd_lbl.text = label
	if upd_btn and is_instance_valid(upd_btn): upd_btn.text = btn; upd_btn.disabled = disabled
	upd_avail = btn.begins_with("Mettre") or btn.begins_with("Télécharger")
	start_btn.text = "LangOS" + (" ●" if upd_avail else "")

func _check_update() -> void:
	if not CHECK_UPDATES:
		_set_upd("Mises à jour désactivées.", "Vérifier"); return
	if upd_http == null:
		upd_http = HTTPRequest.new(); upd_http.timeout = 10.0; add_child(upd_http)
	if upd_http.request_completed.is_connected(_on_version_json): return
	_set_upd("Recherche de mises à jour…", "Vérifier", true)
	upd_http.request_completed.connect(_on_version_json, CONNECT_ONE_SHOT)
	upd_http.request(UPDATE_URL)

const APK_URL := "https://github.com/goodview-soft/LangOS/releases/latest/download/BlocNote.apk"

## Niveau de la partie native de l'APK installée (99 hors Android). 0 = très ancienne, 1 = WebView, 2+ = lanceur…
func _native_level() -> int:
	if OS.get_name() != "Android": return 99
	if Engine.has_singleton("LangLauncher"): return int(Engine.get_singleton("LangLauncher").nativeLevel())
	return 1 if Engine.has_singleton("LangWebView") else 0

func _apk_prompt() -> void:
	if apk_prompted: return
	apk_prompted = true
	var cc := CenterContainer.new(); cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(cc)
	var pc := PanelContainer.new(); pc.add_theme_stylebox_override("panel", _box(Color(0.11, 0.13, 0.18, 0.99), 16, Color(1, 1, 1, 0.15), 1, 30, 18)); cc.add_child(pc)
	var v := VBoxContainer.new(); v.custom_minimum_size.x = 420; v.add_theme_constant_override("separation", 12); pc.add_child(v)
	v.add_child(_dlbl("Nouvelle APK à installer", 22))
	var l := _mlbl("Cette version de LangOS apporte des fonctions Android (navigateur, applis, écran d'accueil) qui demandent de réinstaller l'APK. La mise à jour légère ne suffit pas.", 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(l)
	var b1 := _mk_btn("Télécharger l'APK", 380, 50); b1.theme_type_variation = "Accent"; b1.pressed.connect(func(): OS.shell_open(APK_URL); cc.queue_free()); v.add_child(b1)
	var b2 := _mk_btn("Plus tard", 380, 44); b2.pressed.connect(func(): cc.queue_free()); v.add_child(b2)

func _on_version_json(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_set_upd("✓ v%s (aucune version publiée)" % VERSION if code == 404 else "Vérification impossible (hors ligne ?).", "Vérifier")
		return
	var info = JSON.parse_string(body.get_string_from_utf8())
	if not (info is Dictionary) or not info.has("version"):
		_set_upd("Réponse invalide.", "Vérifier"); return
	if int(info.get("native", 0)) > _native_level():
		_set_upd("Nouvelle APK requise : la partie Android de cette version (niveau %d, installé %d) doit être réinstallée." % [int(info["native"]), _native_level()], "Télécharger l'APK")
		_apk_prompt(); return
	if not preload("res://boot.gd").newer(str(info["version"]), VERSION):
		_set_upd("✓ À jour (v%s)" % VERSION, "Vérifier"); return
	upd_info = info
	var v := Engine.get_version_info()
	var same: bool = str(info.get("godot", "")) == "%d.%d.%d" % [v.major, v.minor, v.patch]
	if same and info.has("pck"):
		_set_upd("Version %s disponible." % info["version"], "Mettre à jour")
	else:
		_set_upd("Version %s disponible (nouveau programme à télécharger)." % info["version"], "Télécharger")

func _do_update() -> void:
	match upd_btn_text:
		"Télécharger": OS.shell_open(RELEASES_URL)
		"Télécharger l'APK": OS.shell_open(APK_URL)
		"Redémarrer": OS.set_restart_on_exit(true); get_tree().quit()
		"Mettre à jour", "Réessayer":
			_set_upd("Téléchargement…", "Mettre à jour", true)
			upd_http.download_file = "user://update.tmp"
			upd_http.request_completed.connect(_on_pck, CONNECT_ONE_SHOT)
			upd_http.request(str(upd_info["pck"]))
		_: _check_update()

func _on_pck(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	upd_http.download_file = ""
	var tmp := "user://update.tmp"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or FileAccess.get_sha256(tmp) != str(upd_info.get("sha256", "")):
		DirAccess.remove_absolute(tmp); _set_upd("Échec du téléchargement.", "Réessayer"); return
	DirAccess.rename_absolute(tmp, "user://update.pck")
	var c := ConfigFile.new()
	c.set_value("update", "version", str(upd_info["version"])); c.save("user://update.cfg")
	if OS.has_feature("pc"): _set_upd("Mise à jour %s installée." % upd_info["version"], "Redémarrer")
	else: _set_upd("Mise à jour %s installée : fermer puis rouvrir l'appli." % upd_info["version"], "Redémarrer")
