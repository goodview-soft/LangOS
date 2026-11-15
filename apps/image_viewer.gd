extends Control
## Visionneuse d'images : zoom/déplacement, rotation, navigation dans le dossier, recadrage, conversion, fond d'écran.
## Les opérations (load_image, rotate, crop, save_as) fonctionnent sans interface ; build() ajoute l'UI.
var m
const EXT := ["png", "jpg", "jpeg", "webp", "bmp", "svg"]
var img: Image
var path := ""
var siblings: Array = []
var idx := 0
var tex: ImageTexture
var zoom := 1.0
var pan := Vector2.ZERO
var view: Control
var lbl: Label
var fmt: OptionButton
var crop_mode := false
var _drag := false
var _c0 := Vector2.ZERO
var _c1 := Vector2.ZERO

# ------------------------------------------------------------------ opérations
func load_image(p: String) -> bool:
	if not FileAccess.file_exists(p): return false
	var im := Image.load_from_file(p)
	if im == null or im.is_empty(): return false
	img = im; path = p
	siblings = []
	var dir := p.get_base_dir()
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in EXT: siblings.append(dir.path_join(f))
	siblings.sort()
	idx = maxi(siblings.find(p), 0)
	_refresh(true)
	return true

func rotate(cw := true) -> void:
	if img == null: return
	if cw: img.rotate_90(CLOCKWISE)
	else: img.rotate_90(COUNTERCLOCKWISE)
	_refresh(false)

## Recadre sur Rect2i (en pixels de l'image) ; false si invalide.
func crop(r: Rect2i) -> bool:
	if img == null: return false
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x < 1 or r.size.y < 1: return false
	img = img.get_region(r); _refresh(false)
	return true

## Enregistre en png/jpg/webp selon l'extension de p.
func save_as(p: String) -> bool:
	if img == null: return false
	var e := p.get_extension().to_lower()
	var im := img.duplicate() as Image
	var err := ERR_FILE_UNRECOGNIZED
	match e:
		"png": err = im.save_png(p)
		"jpg", "jpeg":
			if im.get_format() == Image.FORMAT_RGBA8: im.convert(Image.FORMAT_RGB8)
			err = im.save_jpg(p, 0.92)
		"webp": err = im.save_webp(p, true, 0.92)
	return err == OK

func step(d: int) -> void:
	if siblings.size() < 2: return
	idx = posmod(idx + d, siblings.size())
	var p: String = siblings[idx]
	var keep := siblings
	if load_image(p): siblings = keep; idx = keep.find(p)
	_label()

func _refresh(fit: bool) -> void:
	if img == null: return
	tex = ImageTexture.create_from_image(img)
	if fit: _fit()
	_label()
	if view: view.queue_redraw()

func _fit() -> void:
	if view == null or img == null: return
	var s := img.get_size()
	zoom = minf(1.0, minf((view.size.x - 20) / s.x, (view.size.y - 20) / s.y)) if view.size.x > 40 else 1.0
	pan = Vector2.ZERO

func _label() -> void:
	if lbl and img: lbl.text = "%s  %dx%d  %d%%  (%d/%d)" % [path.get_file(), img.get_width(), img.get_height(), int(zoom * 100), idx + 1, maxi(siblings.size(), 1)]

# ------------------------------------------------------------------ interface
func _c(k: String) -> Color: return m._p(k) if m else Color("232834")

func build() -> void:
	var vb := VBoxContainer.new(); vb.set_anchors_preset(Control.PRESET_FULL_RECT); vb.add_theme_constant_override("separation", 6); add_child(vb)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 4); vb.add_child(top)
	for b in [["‹", func(): step(-1)], ["›", func(): step(1)], ["+", func(): _zoom(1.25)], ["−", func(): _zoom(0.8)], ["Ajuster", func(): _fit(); _label(); view.queue_redraw()],
			["⟲", func(): rotate(false)], ["⟳", func(): rotate(true)], ["Recadrer", _toggle_crop], ["Fond d'écran", _wall]]:
		var bt := Button.new(); bt.text = b[0]; bt.custom_minimum_size = Vector2(46, 40); bt.pressed.connect(b[1]); top.add_child(bt)
	fmt = OptionButton.new(); for f in ["png", "jpg", "webp"]: fmt.add_item(f)
	fmt.custom_minimum_size.y = 40; top.add_child(fmt)
	var sv := Button.new(); sv.text = "Enregistrer"; sv.custom_minimum_size.y = 40; sv.pressed.connect(_save); top.add_child(sv)
	view = Control.new(); view.size_flags_vertical = Control.SIZE_EXPAND_FILL; view.size_flags_horizontal = Control.SIZE_EXPAND_FILL; view.clip_contents = true
	view.draw.connect(_draw_view); view.gui_input.connect(_view_input); view.resized.connect(view.queue_redraw); vb.add_child(view)
	lbl = Label.new(); lbl.text = "Ouvre une image depuis Fichiers ou la recherche."; vb.add_child(lbl)

func open_path(p: String) -> void:
	if not load_image(p) and lbl: lbl.text = "Image illisible : " + p.get_file()

func _zoom(f: float) -> void: zoom = clampf(zoom * f, 0.05, 16.0); _label(); view.queue_redraw()

func _rect() -> Rect2:
	var s := img.get_size() * zoom
	return Rect2((view.size - s) / 2 + pan, s)

func _wall() -> void:
	if img == null or m == null: return
	img.save_png("user://_viewer_tmp.png")
	if m._set_wallpaper("user://_viewer_tmp.png"): m.notify("Fond d'écran", "Image appliquée : " + path.get_file())

func _save() -> void:
	if img == null: return
	var e: String = fmt.get_item_text(fmt.selected)
	var dir := path.get_base_dir()
	var out := dir.path_join(path.get_file().get_basename() + "_edit." + e)
	if save_as(out): if m: m.notify("Images", "Enregistré : " + out.get_file())
	else:
		out = "user://" + out.get_file()
		if save_as(out): if m: m.notify("Images", "Enregistré : " + out)
		elif m: m.notify("Images", "Échec de l'enregistrement")

func _toggle_crop() -> void:
	crop_mode = not crop_mode; _c0 = Vector2.ZERO; _c1 = Vector2.ZERO
	lbl.text = "Recadrage : trace un rectangle sur l'image." if crop_mode else lbl.text; view.queue_redraw()

func _view_input(e: InputEvent) -> void:
	if img == null: return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed: _zoom(1.15)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed: _zoom(1 / 1.15)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			_drag = e.pressed
			if crop_mode:
				if e.pressed: _c0 = e.position; _c1 = e.position
				else:
					var r := _rect()
					var a := (Vector2(minf(_c0.x, _c1.x), minf(_c0.y, _c1.y)) - r.position) / zoom
					var b := (Vector2(maxf(_c0.x, _c1.x), maxf(_c0.y, _c1.y)) - r.position) / zoom
					crop_mode = false
					if b.x - a.x > 2 and b.y - a.y > 2: crop(Rect2i(Vector2i(a.floor()), Vector2i((b - a).ceil())))
					_c0 = Vector2.ZERO; _c1 = Vector2.ZERO; view.queue_redraw()
	elif e is InputEventMouseMotion and _drag:
		if crop_mode: _c1 = e.position
		else: pan += e.relative
		view.queue_redraw()

func _draw_view() -> void:
	view.draw_rect(Rect2(Vector2.ZERO, view.size), _c("field"))
	if tex == null: return
	view.draw_texture_rect(tex, _rect(), false)
	if crop_mode and _c0 != _c1:
		var r := Rect2(_c0, _c1 - _c0).abs()
		view.draw_rect(r, Color(1, 1, 1, 0.15)); view.draw_rect(r, Color.WHITE, false, 2.0)
