extends Control
const UI = preload("res://apps/ui.gd")
## Interface de l'agenda (vues mois / semaine) ; la logique est dans apps/calendar.gd (m.cal).
var m
var cal
var year := 0
var month := 1
var sel := ""
var week := false
var grid: GridContainer
var list: VBoxContainer
var title: Label
var in_t: LineEdit
var in_tm: LineEdit
var in_rep: OptionButton
var in_rem: OptionButton
const REM := [-1, 0, 5, 15, 60, 1440]
const RN := ["Aucun rappel", "À l'heure", "5 min avant", "15 min avant", "1 h avant", "1 jour avant"]
const MN := ["", "Janvier", "Février", "Mars", "Avril", "Mai", "Juin", "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"]
const DN := ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

func build() -> void:
	cal = m.cal
	var t := Time.get_date_dict_from_unix_time(cal.now_unix())
	year = t.year; month = t.month; sel = "%04d-%02d-%02d" % [t.year, t.month, t.day]
	var vb := VBoxContainer.new(); vb.set_anchors_preset(Control.PRESET_FULL_RECT); vb.add_theme_constant_override("separation", 6); add_child(vb)
	var top := UI.toolbar(); vb.add_child(top)
	var bt := func(txt: String, f: Callable) -> void:
		var b := Button.new(); b.text = txt; b.custom_minimum_size = Vector2(46, 40); b.pressed.connect(f); top.add_child(b)
	bt.call("‹", func(): _nav(-1)); bt.call("›", func(): _nav(1))
	title = Label.new(); title.custom_minimum_size.x = 170; title.add_theme_font_size_override("font_size", 20); top.add_child(title)
	bt.call("Mois/Semaine", func(): week = not week; _rebuild())
	bt.call("Export .ics", _exp); bt.call("Import .ics", _imp)
	grid = GridContainer.new(); grid.columns = 7; grid.add_theme_constant_override("h_separation", 3); grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL; vb.add_child(grid)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 4); vb.add_child(row)
	in_t = LineEdit.new(); in_t.placeholder_text = "Nouvel événement"; in_t.custom_minimum_size.y = 40; in_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(in_t)
	in_tm = LineEdit.new(); in_tm.text = "09:00"; in_tm.custom_minimum_size = Vector2(64, 40); row.add_child(in_tm)
	in_rep = OptionButton.new(); for r in ["Une fois", "Chaque jour", "Chaque semaine", "Chaque mois"]: in_rep.add_item(r)
	row.add_child(in_rep)
	in_rem = OptionButton.new(); for r in RN: in_rem.add_item(r)
	row.add_child(in_rem)
	var ab := Button.new(); ab.text = "Ajouter"; ab.custom_minimum_size.y = 40; ab.pressed.connect(_add); row.add_child(ab)
	var sc := ScrollContainer.new(); sc.custom_minimum_size.y = 130; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; vb.add_child(sc)
	list = VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(list)
	_rebuild()

func _nav(d: int) -> void:
	if week: sel = cal.ds_of(cal.day_num(sel) + 7 * d); var p := sel.split("-"); year = int(p[0]); month = int(p[1])
	else:
		month += d
		if month < 1: month = 12; year -= 1
		elif month > 12: month = 1; year += 1
	_rebuild()

func _add() -> void:
	if in_t.text.strip_edges() == "": return
	var tm := in_tm.text.strip_edges()
	if tm.length() != 5 or tm[2] != ":" or not tm.substr(0, 2).is_valid_int() or not tm.substr(3, 2).is_valid_int(): tm = "09:00"
	cal.add(in_t.text, sel, tm, cal.REPS[in_rep.selected], REM[in_rem.selected]); in_t.text = ""; _rebuild()

func _exp() -> void:
	var f := FileAccess.open("user://agenda.ics", FileAccess.WRITE)
	if f: f.store_string(cal.to_ics()); m.notify("Agenda", "Exporté : user://agenda.ics")

func _imp() -> void:
	if not FileAccess.file_exists("user://agenda.ics"): m.notify("Agenda", "Dépose un fichier user://agenda.ics (ou ouvre un .ics dans Fichiers)."); return
	open_path("user://agenda.ics")

func open_path(p: String) -> void:
	var n: int = cal.from_ics(FileAccess.get_file_as_string(p)); m.notify("Agenda", "%d événement(s) importé(s)" % n); _rebuild()

func _cell(ds: String, label: String, dim: bool) -> void:
	var b := Button.new(); b.custom_minimum_size = Vector2(60, 56 if not week else 180); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ev: Array = cal.events_on(ds)
	b.text = label + ("" if ev.is_empty() else (" ●%d" % ev.size() if not week else "\n" + "\n".join(ev.slice(0, 6).map(func(e): return e["tm"] + " " + e["t"]))))
	b.clip_text = true; b.alignment = HORIZONTAL_ALIGNMENT_LEFT; b.focus_mode = Control.FOCUS_NONE
	if dim: b.modulate = Color(1, 1, 1, 0.5)
	if ds == sel: UI.style(b, "normal", func(): return UI.box(Color(UI.accent(), 0.35), 6, UI.accent(), 2))
	b.pressed.connect(func(): sel = ds; _rebuild()); grid.add_child(b)

func _rebuild() -> void:
	for c in grid.get_children(): c.queue_free()
	for d in DN:
		var l := Label.new(); l.text = d; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; grid.add_child(l)
	var first: int
	var count: int
	if week:
		var wd: int = (Time.get_date_dict_from_unix_time(cal.day_num(sel) * 86400).weekday + 6) % 7
		first = cal.day_num(sel) - wd; count = 7
		title.text = "Semaine du " + cal.ds_of(first)
	else:
		var f1: int = cal.day_num("%04d-%02d-01" % [year, month])
		first = f1 - (Time.get_date_dict_from_unix_time(f1 * 86400).weekday + 6) % 7; count = 42
		title.text = "%s %d" % [MN[month], year]
	for i in count:
		var ds: String = cal.ds_of(first + i)
		_cell(ds, ds.substr(8, 2), not week and int(ds.substr(5, 2)) != month)
	for c in list.get_children(): c.queue_free()
	var h := Label.new(); h.text = sel; list.add_child(h)
	for e in cal.events_on(sel):
		var r := HBoxContainer.new(); list.add_child(r)
		var l := Label.new(); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = "%s  %s%s%s" % [e["tm"], e["t"], "  ↻" if e["rep"] != "none" else "", "  ⏰" if int(e["rem"]) >= 0 else ""]; r.add_child(l)
		var tb := Button.new(); tb.text = "→ Tâches"; tb.pressed.connect(func(): if cal.to_todo(e): m.notify("Agenda", "Ajouté aux Tâches")); r.add_child(tb)
		var x := Button.new(); x.text = "✕"; x.pressed.connect(func(): cal.remove(int(e["id"])); _rebuild()); r.add_child(x)
