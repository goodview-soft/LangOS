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
	"music": ["Music", "res://icons/app_music.svg"],
	"soundlink": ["Sound Link", "res://icons/app_soundlink.svg"],
	"update": ["Mise à jour", "res://icons/app_update.svg"],
}
var active := ""
var set_cfg := {"bg": 0, "font": 22, "ollama": "http://127.0.0.1:11434", "model": "", "engine": -1}
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
	if "--os-test" in OS.get_cmdline_user_args():
		for id in APPS: _open_app(id)
		_toggle_menu(); _toggle_menu(); _toggle_kb()
		await get_tree().create_timer(1.0).timeout
		_dic_search("casa")
		print("DICT: ", dic_list.get_item_text(0), " | ", dic_def.get_parsed_text().replace("\n", " ").substr(0, 70), " | ", dic_info.text)
		print("OS-TEST OK wins=", wins.size())
		get_tree().quit()

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
	bg = TextureRect.new(); bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
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
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	desk = Control.new(); desk.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desk.clip_contents = true; root.add_child(desk)
	var i := 0
	for id in APPS:
		_desk_icon(id, Vector2(16, 16 + i * 108)); i += 1
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
	var kbb := _icon_btn("keyboard", "Flat", 48, 42, 24); kbb.pressed.connect(_toggle_kb); bh.add_child(kbb)
	clock = Label.new(); clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.add_theme_font_size_override("font_size", 14); bh.add_child(clock)
	bar_h = 54.0
	_build_keyboard()
	_build_menu()

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
	desk.add_child(b)

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
	for id in APPS:
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
	match id:
		"notepad": _app_notepad()
		"settings": _app_settings()
		"system": _app_system()
		"translate": _app_translate()
		"dict": _app_dict()
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

func _app_settings() -> void:
	var wv := _make_window("settings", "⚙ Paramètres", Vector2(520, 420), Vector2(220, 60))
	var m := MarginContainer.new(); m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 18)
	wv.add_child(m)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12); m.add_child(v)
	v.add_child(_dlbl("Fond d'écran"))
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); v.add_child(row)
	for i in BG_GRADS.size():
		var b := _mk_btn("", 64, 44)
		var sw := StyleBoxTexture.new(); sw.texture = _grad_tex(i, 64, 44)
		var swh := StyleBoxTexture.new(); swh.texture = sw.texture; swh.modulate_color = Color(1.25, 1.25, 1.25)
		b.add_theme_stylebox_override("normal", sw); b.add_theme_stylebox_override("hover", swh); b.add_theme_stylebox_override("pressed", swh)
		b.pressed.connect(func(): set_cfg["bg"] = i; _apply_bg(); _save_settings())
		row.add_child(b)
	var fl := _mlbl("Taille du texte du Bloc-notes : %d" % set_cfg["font"]); v.add_child(fl)
	var sl := HSlider.new(); sl.min_value = 14; sl.max_value = 40; sl.step = 1; sl.value = set_cfg["font"]
	sl.custom_minimum_size.y = 28; sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(func(val: float):
		set_cfg["font"] = int(val); fl.text = "Taille du texte du Bloc-notes : %d" % int(val)
		if edit and is_instance_valid(edit): edit.add_theme_font_size_override("font_size", int(val))
		_save_settings())
	v.add_child(sl)
	v.add_child(_dlbl("Serveur de traduction (Ollama local)"))
	var le := LineEdit.new(); le.text = set_cfg["ollama"]; le.virtual_keyboard_enabled = false
	le.text_changed.connect(func(t: String): set_cfg["ollama"] = t.strip_edges().rstrip("/"); _save_settings())
	v.add_child(le)
	v.add_child(_mlbl("Sur téléphone : adresse du PC, ex. http://192.168.1.20:11434"))

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

const LANGS := [["Français", "French"], ["English", "English"], ["Español", "Spanish"], ["Deutsch", "German"],
	["Italiano", "Italian"], ["Português", "Portuguese"], ["Nederlands", "Dutch"], ["日本語", "Japanese"]]
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
var tr_src: OptionButton
var tr_dst: OptionButton
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
	tr_src = OptionButton.new(); tr_src.focus_mode = Control.FOCUS_NONE; tr_src.add_item("Détecter")
	for l in LANGS: tr_src.add_item(l[0])
	tr_dst = OptionButton.new(); tr_dst.focus_mode = Control.FOCUS_NONE
	for l in LANGS: tr_dst.add_item(l[0])
	var sw := _mk_btn("⇄", 48, 40); sw.pressed.connect(_tr_swap)
	row.add_child(tr_src); row.add_child(sw); row.add_child(tr_dst)
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
	var from_part := ""
	if tr_src.selected > 0: from_part = "from %s " % LANGS[tr_src.selected - 1][1]
	var sys := "You are a translation engine. Translate the user's text %sinto %s. Output ONLY the translation: no notes, no quotes, no explanations." % [from_part, LANGS[tr_dst.selected][1]]
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
	var s := tr_src.selected
	if s > 0:
		var d := tr_dst.selected
		tr_dst.select(s - 1); tr_src.select(d + 1)
	var t := tr_in.text; tr_in.text = tr_out.text; tr_out.text = t

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
	var from_part := ""
	if tr_src.selected > 0: from_part = "from %s " % LANGS[tr_src.selected - 1][1]
	var sys := "You are a translation engine. Translate the user's text %sinto %s. Output ONLY the translation: no notes, no quotes, no explanations." % [from_part, LANGS[tr_dst.selected][1]]
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

# ---------------------------------------------------------------- Music (app intégrée)

func _app_music() -> void:
	var wv := _make_window("music", "", Vector2(1040, 660), Vector2(110, 10))
	var mu := Control.new()
	mu.set_script(load("res://apps/music.gd"))
	mu.set("ollama_url", set_cfg["ollama"])
	mu.size_flags_vertical = Control.SIZE_EXPAND_FILL; mu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mu.custom_minimum_size = Vector2(900, 520); mu.clip_contents = true
	wv.add_child(mu)

# ---------------------------------------------------------------- Sound Link (app intégrée)

func _app_soundlink() -> void:
	var wv := _make_window("soundlink", "", Vector2(500, 740), Vector2(240, 16))
	var sl := Control.new()
	sl.set_script(load("res://apps/soundlink.gd"))
	sl.size_flags_vertical = Control.SIZE_EXPAND_FILL; sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(440, 560); sl.clip_contents = true
	wv.add_child(sl)

# ---------------------------------------------------------------- Dictionnaire (hors ligne, données FreeDict)

const DIC_LANGS := {"fra": "Français", "eng": "English", "spa": "Español", "ita": "Italiano", "por": "Português", "nld": "Nederlands", "jpn": "日本語"}
const DIC_PAIRS := ["fra-eng", "eng-fra", "spa-eng", "eng-spa", "ita-eng", "eng-ita", "por-eng", "eng-por", "nld-eng", "eng-nld", "jpn-eng", "eng-jpn"]
const DIC_PAGE := 200
const ACC := {"à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a", "ç": "c", "è": "e", "é": "e", "ê": "e", "ë": "e",
	"ì": "i", "í": "i", "î": "i", "ï": "i", "ñ": "n", "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o", "ù": "u", "ú": "u", "û": "u", "ü": "u", "ý": "y", "ÿ": "y"}
var dic_src: OptionButton
var dic_dst: OptionButton
var dic_search: LineEdit
var dic_list: ItemList
var dic_def: RichTextLabel
var dic_info: Label
var dic_lines := PackedStringArray()
var dic_start := 0
var dic_codes: Array = []   # codes langue de dic_src
var dic_loading := false

func _dkey(t: String) -> String:
	var o := ""
	for c in t.strip_edges().to_lower(): o += ACC.get(c, c)
	return o

func _app_dict() -> void:
	var wv := _make_window("dict", "", Vector2(920, 580), Vector2(170, 24))
	var m := MarginContainer.new(); m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 14)
	wv.add_child(m)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); m.add_child(v)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); v.add_child(row)
	row.add_child(_mlbl("Mots en"))
	dic_src = OptionButton.new(); dic_src.focus_mode = Control.FOCUS_NONE; row.add_child(dic_src)
	row.add_child(_mlbl("→"))
	dic_dst = OptionButton.new(); dic_dst.focus_mode = Control.FOCUS_NONE; row.add_child(dic_dst)
	dic_codes = []
	for p in DIC_PAIRS:
		var a: String = p.split("-")[0]
		if not a in dic_codes: dic_codes.append(a)
	for c in dic_codes: dic_src.add_item(DIC_LANGS[c])
	dic_src.item_selected.connect(func(_i: int): _dic_fill_dst(); _dic_load())
	dic_dst.item_selected.connect(func(_i: int): _dic_load())
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
	dic_def = RichTextLabel.new(); dic_def.bbcode_enabled = true; dic_def.selection_enabled = true
	dic_def.add_theme_font_size_override("normal_font_size", 20); dic_def.add_theme_font_size_override("bold_font_size", 28)
	pc.add_child(dic_def)
	var def_idx := dic_codes.find("spa") if dic_codes.has("spa") else 0
	dic_src.select(def_idx)
	_dic_fill_dst(); _dic_load()

func _dic_fill_dst() -> void:
	var a: String = dic_codes[dic_src.selected]
	dic_dst.clear()
	for p in DIC_PAIRS:
		if p.begins_with(a + "-"): dic_dst.add_item(DIC_LANGS[p.get_slice("-", 1)])
	dic_dst.select(0)

func _dic_pair() -> String:
	var a: String = dic_codes[dic_src.selected]
	var b := ""
	for c in DIC_LANGS:
		if DIC_LANGS[c] == dic_dst.get_item_text(dic_dst.selected): b = c
	return "%s-%s" % [a, b]

func _dic_load() -> void:
	var path := "res://dicts/%s.tsv" % _dic_pair()
	dic_list.clear(); dic_def.text = ""
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
		set_cfg["engine"] = int(c.get_value("translate", "engine", -1))

func _save_settings() -> void:
	var c := ConfigFile.new()
	c.set_value("ui", "bg", set_cfg["bg"]); c.set_value("ui", "font", set_cfg["font"])
	c.set_value("translate", "server", set_cfg["ollama"]); c.set_value("translate", "model", set_cfg["model"]); c.set_value("translate", "engine", set_cfg["engine"])
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
