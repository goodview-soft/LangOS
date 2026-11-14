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
var bg: ColorRect
var upd_text := ""
var upd_avail := false
var upd_lbl: Label
const BG_COLORS := ["2b5a8a", "2e3440", "3b6e4f", "6b3f6e", "a0522d"]
var set_cfg := {"bg": 0, "font": 22}
var kb: PanelContainer
var upd_http: HTTPRequest
var upd_btn: Button
var upd_info := {}
var bar_h := 48.0

func _ready() -> void:
	_load_settings()
	_build_theme()
	_build_desktop()
	var t := Timer.new(); t.wait_time = 1.0; t.autostart = true
	t.timeout.connect(_tick); add_child(t); _tick()
	_check_update()

func _tick() -> void:
	clock.text = Time.get_datetime_string_from_system().substr(11, 5)

func _build_theme() -> void:
	var th := Theme.new()
	var sb := func(c: Color, r := 6) -> StyleBoxFlat:
		var s := StyleBoxFlat.new(); s.bg_color = c
		s.set_corner_radius_all(r); s.content_margin_left = 8; s.content_margin_right = 8
		s.content_margin_top = 4; s.content_margin_bottom = 4
		return s
	th.set_stylebox("normal", "Button", sb.call(Color("3b4252")))
	th.set_stylebox("hover", "Button", sb.call(Color("4c566a")))
	th.set_stylebox("pressed", "Button", sb.call(Color("5e81ac")))
	th.set_color("font_color", "Button", Color("eceff4"))
	th.set_font_size("font_size", "Button", 20)
	th.set_font_size("font_size", "Label", 16)
	th.set_stylebox("normal", "TextEdit", sb.call(Color("fdfdfd"), 4))
	th.set_stylebox("focus", "TextEdit", sb.call(Color("fdfdfd"), 4))
	th.set_color("font_color", "TextEdit", Color("222222"))
	th.set_color("caret_color", "TextEdit", Color("2e5cb8"))
	th.set_font_size("font_size", "TextEdit", 22)
	theme = th

func _flat(c: Color, r := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = c; s.set_corner_radius_all(r)
	return s

func _mk_btn(txt: String, w := 56, h := 56) -> Button:
	var b := Button.new(); b.text = txt
	b.custom_minimum_size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	return b

func _build_desktop() -> void:
	bg = ColorRect.new(); bg.color = Color(BG_COLORS[set_cfg["bg"]])
	bg.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	desk = Control.new(); desk.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desk.clip_contents = true; root.add_child(desk)
	var ic := Button.new(); ic.text = "📝\nBloc-notes"; ic.focus_mode = Control.FOCUS_NONE
	ic.custom_minimum_size = Vector2(110, 100); ic.position = Vector2(20, 20)
	ic.add_theme_stylebox_override("normal", _flat(Color(0, 0, 0, 0), 8))
	ic.add_theme_font_size_override("font_size", 18)
	ic.pressed.connect(_open_app.bind("notepad"))
	desk.add_child(ic)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _flat(Color(0.08, 0.09, 0.12, 0.97)))
	root.add_child(bar)
	var bh := HBoxContainer.new(); bar.add_child(bh)
	start_btn = _mk_btn("◉ Démarrer", 130, 40); start_btn.pressed.connect(_toggle_menu); bh.add_child(start_btn)
	task_box = HBoxContainer.new(); bh.add_child(task_box)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bh.add_child(sp)
	var kbb := _mk_btn("⌨", 50, 40); kbb.pressed.connect(_toggle_kb); bh.add_child(kbb)
	clock = Label.new(); bh.add_child(clock)
	var pad := Label.new(); pad.text = "  "; bh.add_child(pad)
	bar_h = 48.0
	_build_keyboard()
	_build_menu()

# ---------------------------------------------------------------- Menu Démarrer

func _build_menu() -> void:
	catcher = Control.new(); catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.visible = false
	catcher.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: _toggle_menu())
	add_child(catcher)
	menu = PanelContainer.new(); menu.visible = false
	var st := _flat(Color("2e3440"), 10)
	st.set_content_margin_all(8); st.border_color = Color("4c566a"); st.set_border_width_all(1)
	menu.add_theme_stylebox_override("panel", st)
	add_child(menu)
	var v := VBoxContainer.new(); menu.add_child(v)
	var head := Label.new(); head.text = "LangOS"; head.add_theme_color_override("font_color", Color("88c0d0")); v.add_child(head)
	for e in [["📝  Bloc-notes", "notepad"], ["⚙  Paramètres", "settings"], ["🖥  Système", "system"], ["⬆  Mise à jour", "update"]]:
		var b := _mk_btn(e[0], 260, 44); b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): _toggle_menu(); _open_app(e[1]))
		v.add_child(b)
	v.add_child(HSeparator.new())
	var q := _mk_btn("⏻  Quitter", 260, 44); q.alignment = HORIZONTAL_ALIGNMENT_LEFT
	q.pressed.connect(_quit); v.add_child(q)

func _toggle_menu() -> void:
	menu.visible = not menu.visible
	catcher.visible = menu.visible
	if menu.visible:
		menu.size = menu.get_combined_minimum_size()
		menu.position = Vector2(8, size.y - bar_h - 6 - menu.size.y)
		if kb.visible: kb.move_to_front()
		catcher.move_to_front(); menu.move_to_front()

func _quit() -> void:
	if wins.has("notepad"): _save()
	get_tree().quit()

func _build_keyboard() -> void:
	kb = PanelContainer.new()
	kb.add_theme_stylebox_override("panel", _flat(Color("2e3440")))
	kb.visible = false
	add_child(kb)
	kb.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	var kv := VBoxContainer.new(); kv.alignment = BoxContainer.ALIGNMENT_CENTER
	kv.add_theme_constant_override("separation", 6); kb.add_child(kv)
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

func _bs() -> void:
	var f := _target()
	if f is TextEdit: f.backspace()
	elif f is LineEdit and f.caret_column > 0: f.delete_text(f.caret_column - 1, f.caret_column)

func _toggle_kb() -> void:
	kb.visible = not kb.visible
	kb.offset_top = -(bar_h + kb.get_combined_minimum_size().y)
	kb.offset_bottom = -bar_h

# ---------------------------------------------------------------- Fenêtres

func _dlbl(t: String, sz := 18) -> Label:
	var l := Label.new(); l.text = t
	l.add_theme_color_override("font_color", Color("222222"))
	l.add_theme_font_size_override("font_size", sz)
	return l

func _open_app(id: String) -> void:
	if wins.has(id):
		_show(id); return
	match id:
		"notepad": _app_notepad()
		"settings": _app_settings()
		"system": _app_system()
		"update": _app_update()

func _show(id: String) -> void:
	wins[id]["win"].visible = true
	wins[id]["win"].move_to_front()
	if kb.visible: kb.move_to_front()

## Crée une fenêtre déplaçable ; renvoie son conteneur vertical.
func _make_window(id: String, title: String, sz: Vector2, pos: Vector2) -> VBoxContainer:
	var w := PanelContainer.new()
	w.add_theme_stylebox_override("panel", _flat(Color("e9e9ed"), 10))
	w.size = sz; w.position = pos
	desk.add_child(w)
	var wv := VBoxContainer.new(); wv.add_theme_constant_override("separation", 0)
	w.add_child(wv)
	var tb := PanelContainer.new()
	var tbs := _flat(Color("2e3440"), 10)
	tbs.corner_radius_bottom_left = 0; tbs.corner_radius_bottom_right = 0
	tb.add_theme_stylebox_override("panel", tbs)
	tb.gui_input.connect(_title_input.bind(id))
	wv.add_child(tb)
	var tbh := HBoxContainer.new(); tb.add_child(tbh)
	var tl := Label.new(); tl.text = "  " + title
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.mouse_filter = Control.MOUSE_FILTER_PASS
	tbh.add_child(tl)
	var mn := _mk_btn("—", 40, 28); mn.pressed.connect(_toggle_win.bind(id)); tbh.add_child(mn)
	var mx := _mk_btn("▢", 40, 28); mx.pressed.connect(_toggle_max.bind(id)); tbh.add_child(mx)
	var cl := _mk_btn("✕", 40, 28); cl.pressed.connect(_close_win.bind(id)); tbh.add_child(cl)
	var tk := _mk_btn(title, 160, 40); tk.pressed.connect(_toggle_win.bind(id)); task_box.add_child(tk)
	wins[id] = {"win": w, "task": tk, "maxed": false, "saved": Rect2(), "title": tl}
	w.move_to_front()
	if kb.visible: kb.move_to_front()
	return wv

func _title_input(ev: InputEvent, id: String) -> void:
	var d: Dictionary = wins[id]
	var w: PanelContainer = d["win"]
	if ev is InputEventMouseButton and ev.pressed:
		w.move_to_front()
		if kb.visible: kb.move_to_front()
		if ev.double_click: _toggle_max(id)
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) and not d["maxed"]:
		var p: Vector2 = w.position + ev.relative
		var lim: Vector2 = desk.size - Vector2(120, 40)
		w.position = Vector2(clampf(p.x, -w.size.x + 120, lim.x), clampf(p.y, 0, lim.y))

func _toggle_win(id: String) -> void:
	var w: PanelContainer = wins[id]["win"]
	w.visible = not w.visible
	if w.visible: _show(id)

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

# ---------------------------------------------------------------- Applications

func _app_notepad() -> void:
	var wv := _make_window("notepad", "📝 Bloc-notes", Vector2(900, 560), Vector2(150, 20))
	title_lbl = wins["notepad"]["title"]
	var mb := HBoxContainer.new(); wv.add_child(mb)
	var bn := _mk_btn("Nouveau", 110, 36); bn.pressed.connect(_new); mb.add_child(bn)
	var bsv := _mk_btn("Enregistrer", 110, 36); bsv.pressed.connect(_save); mb.add_child(bsv)
	edit = TextEdit.new(); edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.virtual_keyboard_enabled = false
	edit.placeholder_text = "Écrivez ici…"
	edit.add_theme_font_size_override("font_size", set_cfg["font"])
	edit.text_changed.connect(func(): dirty = true; _update_status())
	edit.caret_changed.connect(_update_status)
	wv.add_child(edit)
	status = Label.new(); status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color("333333"))
	wv.add_child(status)
	if FileAccess.file_exists(SAVE_PATH):
		edit.text = FileAccess.get_file_as_string(SAVE_PATH)
	dirty = false
	edit.grab_focus()
	_update_status()

func _app_settings() -> void:
	var wv := _make_window("settings", "⚙ Paramètres", Vector2(520, 340), Vector2(220, 60))
	var m := MarginContainer.new(); m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 18)
	wv.add_child(m)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12); m.add_child(v)
	v.add_child(_dlbl("Fond d'écran"))
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); v.add_child(row)
	for i in BG_COLORS.size():
		var b := _mk_btn("", 56, 40)
		b.add_theme_stylebox_override("normal", _flat(Color(BG_COLORS[i]), 6))
		b.add_theme_stylebox_override("hover", _flat(Color(BG_COLORS[i]).lightened(0.2), 6))
		b.pressed.connect(func(): set_cfg["bg"] = i; bg.color = Color(BG_COLORS[i]); _save_settings())
		row.add_child(b)
	var fl := _dlbl("Taille du texte du Bloc-notes : %d" % set_cfg["font"]); v.add_child(fl)
	var sl := HSlider.new(); sl.min_value = 14; sl.max_value = 40; sl.step = 1; sl.value = set_cfg["font"]
	sl.custom_minimum_size.y = 28; sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(func(val: float):
		set_cfg["font"] = int(val); fl.text = "Taille du texte du Bloc-notes : %d" % int(val)
		if edit and is_instance_valid(edit): edit.add_theme_font_size_override("font_size", int(val))
		_save_settings())
	v.add_child(sl)

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
	upd_btn = _mk_btn("Vérifier", 240, 44); upd_btn.pressed.connect(_do_update); v.add_child(upd_btn)
	_set_upd(upd_lbl_text, upd_btn_text)
	if upd_http == null or upd_btn_text == "Vérifier": _check_update()

# ---------------------------------------------------------------- Réglages

func _load_settings() -> void:
	var c := ConfigFile.new()
	if c.load("user://settings.cfg") == OK:
		set_cfg["bg"] = clampi(int(c.get_value("ui", "bg", 0)), 0, BG_COLORS.size() - 1)
		set_cfg["font"] = clampi(int(c.get_value("ui", "font", 22)), 14, 40)

func _save_settings() -> void:
	var c := ConfigFile.new()
	c.set_value("ui", "bg", set_cfg["bg"]); c.set_value("ui", "font", set_cfg["font"])
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
	shift_btns[0].modulate = Color("88c0d0") if shift else Color.WHITE
	shift_btns[1].modulate = Color("88c0d0") if caps else Color.WHITE

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
	if title_lbl and is_instance_valid(title_lbl): title_lbl.text = "  📝 Bloc-notes" + (" •" if dirty else "")


# ---------------------------------------------------------------- Mise à jour

var upd_lbl_text := ""
var upd_btn_text := "Vérifier"

func _set_upd(label: String, btn: String, disabled := false) -> void:
	upd_lbl_text = label; upd_btn_text = btn
	if upd_lbl and is_instance_valid(upd_lbl): upd_lbl.text = label
	if upd_btn and is_instance_valid(upd_btn): upd_btn.text = btn; upd_btn.disabled = disabled
	upd_avail = btn.begins_with("Mettre") or btn.begins_with("Télécharger")
	start_btn.text = "◉ Démarrer" + (" ●" if upd_avail else "")

func _check_update() -> void:
	if not CHECK_UPDATES:
		_set_upd("Mises à jour désactivées.", "Vérifier"); return
	if upd_http == null:
		upd_http = HTTPRequest.new(); upd_http.timeout = 10.0; add_child(upd_http)
	upd_http.cancel_request()
	_set_upd("Recherche de mises à jour…", "Vérifier", true)
	upd_http.request_completed.connect(_on_version_json, CONNECT_ONE_SHOT)
	upd_http.request(UPDATE_URL)

func _on_version_json(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_set_upd("✓ v%s (aucune version publiée)" % VERSION if code == 404 else "Vérification impossible (hors ligne ?).", "Vérifier")
		return
	var info = JSON.parse_string(body.get_string_from_utf8())
	if not (info is Dictionary) or not info.has("version"):
		_set_upd("Réponse invalide.", "Vérifier"); return
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
