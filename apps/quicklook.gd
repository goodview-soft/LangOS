extends ColorRect
## Aperçu rapide (Espace) : image, texte, ou icône + nom pour les autres fichiers (PDF, vidéo...). Espace / Échap / clic ferme.
const UI = preload("res://apps/ui.gd")
const IMG := ["png", "jpg", "jpeg", "webp", "bmp", "svg", "gif"]
const TXT := ["txt", "md", "json", "gd", "cfg", "csv", "log", "py", "js", "html", "css", "xml", "yml", "yaml", "ini", "sh", "ics", "tscn"]

## Ouvre l'aperçu de « path » par-dessus « host » (un seul à la fois par hôte).
static func show_for(host: Control, path: String) -> void:
	for c in host.get_children(): if c.has_meta("quicklook"): return
	var q := ColorRect.new(); q.set_script(load("res://apps/quicklook.gd")); q.set_meta("quicklook", true)
	host.add_child(q); q.call("setup", path)

func setup(path: String) -> void:
	color = Color(0, 0, 0, 0.72); set_anchors_preset(Control.PRESET_FULL_RECT); mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: _close())
	var mg := MarginContainer.new(); mg.set_anchors_preset(Control.PRESET_FULL_RECT); mg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in ["left", "right", "top", "bottom"]: mg.add_theme_constant_override("margin_" + k, 16)
	add_child(mg)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; mg.add_child(v)
	var name_l := UI.heading(path.get_file()); name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; v.add_child(name_l)
	var e := path.get_extension().to_lower()
	var body: Control = null
	if e in IMG:
		var im := Image.load_from_file(path)
		if im != null and not im.is_empty():
			var tr := TextureRect.new(); tr.texture = ImageTexture.create_from_image(im); tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; tr.size_flags_vertical = Control.SIZE_EXPAND_FILL; tr.mouse_filter = Control.MOUSE_FILTER_IGNORE; body = tr
	elif e in TXT:
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var t := f.get_buffer(mini(6000, f.get_length())).get_string_from_utf8()
			var pc := PanelContainer.new(); pc.size_flags_vertical = Control.SIZE_EXPAND_FILL; pc.clip_contents = true; pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pc.add_theme_stylebox_override("panel", UI.box(UI.p("view"), UI.rad(), UI.p("edge"), 1, 12))
			var l := Label.new(); l.text = t; l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY; l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.vertical_alignment = VERTICAL_ALIGNMENT_TOP; l.add_theme_font_override("font", UI.mono()); pc.add_child(l); body = pc
	if body == null:
		var cc := CenterContainer.new(); cc.size_flags_vertical = Control.SIZE_EXPAND_FILL; cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := TextureRect.new(); ic.texture = UI.icon("file-text" if e != "pdf" else "file"); ic.custom_minimum_size = Vector2(96, 96)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vb := VBoxContainer.new(); vb.alignment = BoxContainer.ALIGNMENT_CENTER; vb.mouse_filter = Control.MOUSE_FILTER_IGNORE; cc.add_child(vb)
		vb.add_child(ic)
		var sz := UI.small(String.humanize_size(FileAccess.get_size(path)) if FileAccess.file_exists(path) else ""); sz.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vb.add_child(sz)
		body = cc
	v.add_child(body)
	var hint := UI.small("Espace ou Échap pour fermer"); hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(hint)

func _close() -> void:
	queue_free()

func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev.keycode == KEY_SPACE or ev.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled(); _close()
