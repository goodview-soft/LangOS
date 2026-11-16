extends Control
## Galerie : photos et vidéos de plusieurs dossiers (Images, Vidéos, DCIM, pages du Scanner, dossiers ajoutés) en grille de miniatures.
## Photo : visionneuse (précédent / suivant, éditer dans « Images »). Vidéo .ogv : lecture intégrée ; autres formats : lecteur du système.
const UI = preload("res://apps/ui.gd")
const CFG := "user://gallery.cfg"
const IMPORT_DIR := "user://gallery"
const IMG := ["png", "jpg", "jpeg", "webp", "bmp"]
const VID := ["ogv", "mp4", "webm", "mkv", "mov", "avi"]
const MAX_ITEMS := 400

var m
var dirs: Array = []          # dossiers ajoutés par l'utilisateur
var items: Array = []         # {p, vid, t}
var filt := "all"             # all | img | vid
var gen := 0
var cache := {}               # chemin -> miniature
var nodes := {}               # chemin -> TextureRect
var shown: Array = []         # éléments affichés (pour précédent / suivant)
var root: VBoxContainer
var grid: HFlowContainer
var info: Label
var over: ColorRect           # visionneuse plein cadre
var ov_img: TextureRect
var ov_vid: VideoStreamPlayer
var ov_lbl: Label
var ov_i := 0
var hov := -1                 # cellule survolée (aperçu rapide avec Espace)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(IMPORT_DIR)
	var c := ConfigFile.new()
	if c.load(CFG) == OK:
		var d = c.get_value("g", "dirs", [])
		if d is Array: dirs = d
	var mg := MarginContainer.new(); mg.set_anchors_preset(PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]: mg.add_theme_constant_override("margin_" + k, 10)
	add_child(mg)
	root = VBoxContainer.new(); root.add_theme_constant_override("separation", 8); mg.add_child(root)
	var hb := UI.header_bar("Galerie", false); root.add_child(hb)
	var en := UI.bar_end(hb)
	UI.bar_act(hb, en, "upload", "Importer des photos / vidéos", _import_pick)
	UI.bar_act(hb, en, "folder-plus", "Ajouter un dossier", _add_dir)
	var fr := HBoxContainer.new(); fr.add_theme_constant_override("separation", 6); root.add_child(fr)
	for f in [["all", "Tout"], ["img", "Photos"], ["vid", "Vidéos"]]:
		var b := Button.new(); b.text = f[1]; b.focus_mode = Control.FOCUS_NONE; b.custom_minimum_size = Vector2(90, 38)
		b.pressed.connect(_set_filter.bind(f[0])); fr.add_child(b)
	info = UI.small(""); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; fr.add_child(info)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; root.add_child(sc)
	grid = HFlowContainer.new(); grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6); grid.add_theme_constant_override("v_separation", 6); sc.add_child(grid)
	_build_overlay()
	if OS.get_name() == "Android":   # accès aux photos / vidéos : demandé à l'ouverture de la Galerie, puis on relit les dossiers
		get_tree().on_request_permissions_result.connect(func(_p, _ok): _rescan())
		for p in ["READ_MEDIA_IMAGES", "READ_MEDIA_VIDEO"]: OS.request_permission(p)
	_rescan()


func _sources() -> Array:
	var out: Array = [IMPORT_DIR, "user://scans"]
	for k in [OS.SYSTEM_DIR_PICTURES, OS.SYSTEM_DIR_MOVIES, OS.SYSTEM_DIR_DCIM]:
		var p := OS.get_system_dir(k)
		if p != "" and not out.has(p): out.append(p)
	for d in dirs:
		if not out.has(d): out.append(d)
	return out


func _rescan() -> void:
	items = []
	var seen := {}
	for d in _sources(): _scan(str(d), 0, seen)
	items.sort_custom(func(a, b): return a.t > b.t)
	if items.size() > MAX_ITEMS: items.resize(MAX_ITEMS)
	_fill()


func _scan(dir: String, depth: int, seen: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null: return
	for f in d.get_files():
		var e := f.get_extension().to_lower()
		var p := dir.path_join(f)
		if seen.has(p) or (e not in IMG and e not in VID): continue
		seen[p] = true
		items.append({"p": p, "vid": e in VID, "t": FileAccess.get_modified_time(p)})
	if depth < 2:
		for sub in d.get_directories():
			if not sub.begins_with("."): _scan(dir.path_join(sub), depth + 1, seen)


func _set_filter(f: String) -> void:
	filt = f; _fill()


func _fill() -> void:
	gen += 1
	for c in grid.get_children():
		grid.remove_child(c); c.queue_free()
	nodes = {}; shown = []
	for it in items:
		if filt == "img" and it.vid: continue
		if filt == "vid" and not it.vid: continue
		shown.append(it)
	info.text = "%d élément(s)" % shown.size() if not shown.is_empty() else "Aucune photo ni vidéo — importe-en avec le bouton d'import ou ajoute un dossier."
	for i in shown.size():
		var it: Dictionary = shown[i]
		var cell := Control.new(); cell.custom_minimum_size = Vector2(130, 130); cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		cell.clip_contents = true; grid.add_child(cell)
		var bg := ColorRect.new(); bg.color = Color(0.5, 0.5, 0.55, 0.18); bg.set_anchors_preset(PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(bg)
		var t := TextureRect.new(); t.set_anchors_preset(PRESET_FULL_RECT); t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; t.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(t)
		if it.vid:
			var pl := TextureRect.new(); pl.texture = UI.icon("play"); pl.set_anchors_preset(PRESET_CENTER); pl.custom_minimum_size = Vector2(36, 36)
			pl.position = Vector2(47, 47); pl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; pl.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(pl)
			var nm := Label.new(); nm.text = str(it.p).get_file(); nm.clip_text = true; nm.add_theme_font_size_override("font_size", 11)
			nm.set_anchors_preset(PRESET_BOTTOM_WIDE); nm.mouse_filter = Control.MOUSE_FILTER_IGNORE; cell.add_child(nm)
		else:
			nodes[it.p] = t
			if cache.has(it.p): t.texture = cache[it.p]
			else: _load_thumb(str(it.p))
		cell.mouse_entered.connect(func(): hov = i); cell.mouse_exited.connect(func(): if hov == i: hov = -1)
		cell.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _open(i))


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_SPACE and is_visible_in_tree() and not over.visible and hov >= 0 and hov < shown.size():
		load("res://apps/quicklook.gd").show_for(self, shown[hov].p); get_viewport().set_input_as_handled()


func _load_thumb(p: String) -> void:
	var tok := gen
	WorkerThreadPool.add_task(func():
		var im := Image.load_from_file(p)
		if im != null and not im.is_empty():
			var k := 200.0 / float(maxi(im.get_width(), im.get_height()))
			if k < 1.0: im.resize(maxi(8, int(im.get_width() * k)), maxi(8, int(im.get_height() * k)), Image.INTERPOLATE_BILINEAR)
		if is_instance_valid(self): _thumb_done.call_deferred(p, im, tok))


func _thumb_done(p: String, im: Image, tok: int) -> void:
	if im == null or im.is_empty(): return
	cache[p] = ImageTexture.create_from_image(im)
	if tok == gen and nodes.has(p) and is_instance_valid(nodes[p]): nodes[p].texture = cache[p]


# ---------------------------------------------------------------- Visionneuse
func _build_overlay() -> void:
	over = ColorRect.new(); over.color = Color(0, 0, 0, 0.94); over.set_anchors_preset(PRESET_FULL_RECT); over.visible = false
	over.mouse_filter = Control.MOUSE_FILTER_STOP; add_child(over)
	ov_img = TextureRect.new(); ov_img.set_anchors_preset(PRESET_FULL_RECT); ov_img.offset_top = 56; ov_img.offset_bottom = -8
	ov_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ov_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; over.add_child(ov_img)
	ov_vid = VideoStreamPlayer.new(); ov_vid.set_anchors_preset(PRESET_FULL_RECT); ov_vid.offset_top = 56; ov_vid.offset_bottom = -8; ov_vid.expand = true; ov_vid.visible = false; over.add_child(ov_vid)
	var bar := HBoxContainer.new(); bar.set_anchors_preset(PRESET_TOP_WIDE); bar.custom_minimum_size.y = 48; bar.add_theme_constant_override("separation", 6); over.add_child(bar)
	bar.add_child(UI.icon_btn("x", "Fermer", _close, "Flat", 44))
	ov_lbl = Label.new(); ov_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ov_lbl.clip_text = true; ov_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; bar.add_child(ov_lbl)
	bar.add_child(UI.icon_btn("arrow-left", "Précédent", _step.bind(-1), "Flat", 44))
	bar.add_child(UI.icon_btn("arrow-right", "Suivant", _step.bind(1), "Flat", 44))
	bar.add_child(UI.icon_btn("pencil", "Modifier dans Images", _edit, "Flat", 44))
	bar.add_child(UI.icon_btn("trash-2", "Supprimer", _delete, "Flat", 44))


func _open(i: int) -> void:
	ov_i = i; var it: Dictionary = shown[i]; var p: String = it.p
	if it.vid and p.get_extension().to_lower() != "ogv":
		OS.shell_open("file://" + ProjectSettings.globalize_path(p)); return
	over.visible = true; ov_lbl.text = "%s   (%d/%d)" % [p.get_file(), i + 1, shown.size()]
	ov_vid.stop(); ov_vid.visible = it.vid; ov_img.visible = not it.vid
	if it.vid:
		var vs := VideoStreamTheora.new(); vs.file = p; ov_vid.stream = vs; ov_vid.play()
	else:
		var im := Image.load_from_file(p)
		ov_img.texture = ImageTexture.create_from_image(im) if im != null and not im.is_empty() else null


## Déplace dans la Corbeille de LangOS (récupérable depuis l'appli Fichiers) au lieu de supprimer définitivement.
func _to_trash(p: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://trash")
	var dst := "user://trash".path_join("%d_%s" % [Time.get_ticks_msec(), p.get_file()])
	if DirAccess.rename_absolute(p, dst) == OK: return
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null: return
	var o := FileAccess.open(dst, FileAccess.WRITE)
	if o == null: return
	o.store_buffer(f.get_buffer(f.get_length())); o.close(); f.close()
	DirAccess.remove_absolute(p)


func _close() -> void:
	ov_vid.stop(); over.visible = false


func _step(d: int) -> void:
	if shown.is_empty(): return
	_open(posmod(ov_i + d, shown.size()))


func _edit() -> void:
	var p: String = shown[ov_i].p
	if not shown[ov_i].vid and m != null: _close(); m.open_with("imgview", p)


func _delete() -> void:
	if shown.is_empty(): return
	var p: String = shown[ov_i].p
	_to_trash(p)
	items = items.filter(func(x): return x.p != p); cache.erase(p)
	_close(); _fill()


# ---------------------------------------------------------------- Ajout de médias
func _import_pick() -> void:
	var fd := FileDialog.new(); fd.file_mode = FileDialog.FILE_MODE_OPEN_FILES; fd.access = FileDialog.ACCESS_FILESYSTEM; fd.use_native_dialog = true
	fd.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp,*.bmp,*.ogv,*.mp4,*.webm,*.mkv,*.mov ; Photos et vidéos"])
	fd.files_selected.connect(func(ps: PackedStringArray): import_files(ps); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd); fd.popup_centered_ratio(0.7)


func import_files(paths: PackedStringArray) -> void:
	for p in paths:
		var src := FileAccess.open(p, FileAccess.READ)
		if src == null: continue
		var dst := IMPORT_DIR.path_join(p.get_file())
		if FileAccess.file_exists(dst): dst = IMPORT_DIR.path_join("%d_%s" % [Time.get_ticks_msec(), p.get_file()])
		var o := FileAccess.open(dst, FileAccess.WRITE)
		if o == null: continue
		o.store_buffer(src.get_buffer(src.get_length())); o.close()
	_rescan()


func _add_dir() -> void:
	var fd := FileDialog.new(); fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR; fd.access = FileDialog.ACCESS_FILESYSTEM; fd.use_native_dialog = true
	fd.dir_selected.connect(func(p: String):
		if not dirs.has(p): dirs.append(p)
		var c := ConfigFile.new(); c.set_value("g", "dirs", dirs); c.save(CFG)
		fd.queue_free(); _rescan())
	fd.canceled.connect(fd.queue_free)
	add_child(fd); fd.popup_centered_ratio(0.7)
