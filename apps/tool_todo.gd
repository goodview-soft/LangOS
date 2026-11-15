extends Control
## Listes de tâches et de courses (plusieurs listes, enregistrées sur l'appareil).

const PATH := "user://todo.json"
var data := {"Tâches": [], "Courses": []}   # liste -> [{t, d}]
var cur := "Tâches"
var opt: OptionButton
var box: VBoxContainer
var inp: LineEdit

func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary and not d.is_empty(): data = d
	cur = data.keys()[0]
	var vb := VBoxContainer.new(); vb.set_anchors_preset(Control.PRESET_FULL_RECT); vb.add_theme_constant_override("separation", 8); add_child(vb)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 6); vb.add_child(top)
	opt = OptionButton.new(); opt.custom_minimum_size.y = 48; opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.item_selected.connect(func(i): cur = opt.get_item_text(i); _rebuild()); top.add_child(opt)
	var nl := Button.new(); nl.text = "+ Liste"; nl.custom_minimum_size = Vector2(90, 48); nl.pressed.connect(_new_list); top.add_child(nl)
	var dl := Button.new(); dl.text = "Suppr."; dl.custom_minimum_size = Vector2(80, 48); dl.pressed.connect(_del_list); top.add_child(dl)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6); vb.add_child(row)
	inp = LineEdit.new(); inp.placeholder_text = "Nouvel élément…"; inp.custom_minimum_size.y = 48; inp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inp.text_submitted.connect(func(_t): _add()); row.add_child(inp)
	var ab := Button.new(); ab.text = "Ajouter"; ab.custom_minimum_size = Vector2(90, 48); ab.pressed.connect(_add); row.add_child(ab)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; vb.add_child(sc)
	box = VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation", 4); sc.add_child(box)
	var cb := Button.new(); cb.text = "Retirer les éléments cochés"; cb.custom_minimum_size.y = 48; cb.pressed.connect(_clear_done); vb.add_child(cb)
	_rebuild()

func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(data))

func _add() -> void:
	var t := inp.text.strip_edges()
	if t == "": return
	data[cur].append({"t": t, "d": false}); inp.text = ""; _save(); _rebuild()

func _new_list() -> void:
	var n := inp.text.strip_edges()
	if n == "" or data.has(n): inp.placeholder_text = "Écris le nom de la liste ici, puis « + Liste »"; return
	data[n] = []; cur = n; inp.text = ""; _save(); _rebuild()

func _del_list() -> void:
	if data.size() <= 1: return
	data.erase(cur); cur = data.keys()[0]; _save(); _rebuild()

func _clear_done() -> void:
	data[cur] = data[cur].filter(func(e): return not e.d); _save(); _rebuild()

func _rebuild() -> void:
	opt.clear()
	for k in data: opt.add_item(k); if k == cur: opt.select(opt.item_count - 1)
	for c in box.get_children(): c.queue_free()
	var items: Array = data[cur]
	for i in items.size():
		var e: Dictionary = items[i]
		var r := HBoxContainer.new(); r.add_theme_constant_override("separation", 4); box.add_child(r)
		var cb := CheckBox.new(); cb.text = e.t; cb.button_pressed = e.d; cb.custom_minimum_size.y = 48; cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.add_theme_font_size_override("font_size", 20); cb.focus_mode = Control.FOCUS_NONE
		if e.d: cb.modulate = Color(1, 1, 1, 0.45)
		cb.toggled.connect(func(on): e.d = on; _save(); cb.modulate = Color(1, 1, 1, 0.45 if on else 1.0)); r.add_child(cb)
		var x := Button.new(); x.text = "✕"; x.custom_minimum_size = Vector2(48, 48); x.focus_mode = Control.FOCUS_NONE
		x.pressed.connect(func(): items.erase(e); _save(); _rebuild()); r.add_child(x)
	if items.is_empty():
		var l := Label.new(); l.text = "Liste vide."; l.modulate = Color(1, 1, 1, 0.5); box.add_child(l)
