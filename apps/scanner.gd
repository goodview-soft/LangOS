extends Control
## Scanner de documents (façon CamScanner) : photo ou import -> détection des bords -> recadrage manuel
## -> redressement en perspective -> filtres (Magique, N&B, Gris) -> pages d'un document -> PDF.
const UI = preload("res://apps/ui.gd")
const DIR := "user://scans"
const IDX := "user://scans/index.json"
const MAXSRC := 2400    # taille max de la photo de départ (px)
const MAXOUT := 1500    # taille max de la page redressée (px)
const FILTERS := [["orig", "Original"], ["magic", "Magique"], ["bw", "N&B"], ["gray", "Gris"]]

var m
var docs: Array = []          # {id, name, date, pages: [chemins jpg]}
var doc: Dictionary = {}      # document ouvert ({} = nouveau, créé à l'enregistrement de la 1re page)
var root: VBoxContainer
var src: Image
var warped: Image
var result: Image
var filt := "magic"
var crop: CropView
var prev: TextureRect
var cam_view: TextureRect
var cam_msg: Label
var perm_btn: Button
var cam_tex: CameraTexture
var cam_feed: CameraFeed
var busy: ColorRect
var busy_lbl: Label
var pending: Array = []       # photos importées en attente de traitement
var job := 0
var thumbs := {}


## Vue de recadrage : photo + 4 poignées déplaçables (coordonnées en pixels de l'image).
class CropView extends Control:
	var tex: ImageTexture
	var isz := Vector2.ONE
	var pts: Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var drag := -1

	func set_image(img: Image, c: Array) -> void:
		tex = ImageTexture.create_from_image(img); isz = Vector2(img.get_size()); pts = c.duplicate(); queue_redraw()

	func _fit() -> Rect2:
		var s := minf(size.x / isz.x, size.y / isz.y)
		var sz := isz * s
		return Rect2((size - sz) / 2.0, sz)

	func _to_screen(p: Vector2) -> Vector2:
		var r := _fit()
		return r.position + p / isz * r.size

	func _to_img(p: Vector2) -> Vector2:
		var r := _fit()
		return ((p - r.position) / r.size * isz).clamp(Vector2.ZERO, isz)

	func _draw() -> void:
		if tex == null: return
		draw_texture_rect(tex, _fit(), false)
		var sp := PackedVector2Array()
		for p in pts: sp.append(_to_screen(p))
		var ac := Color("5aa2ff")
		draw_colored_polygon(sp, Color(ac, 0.2))
		var cl := sp.duplicate(); cl.append(sp[0])
		draw_polyline(cl, ac, 2.5, true)
		for p in sp:
			draw_circle(p, 14, Color(1, 1, 1, 0.95))
			draw_arc(p, 14, 0, TAU, 24, ac, 3.0, true)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			drag = -1
			if ev.pressed:
				var best := 48.0
				for i in 4:
					var d := _to_screen(pts[i]).distance_to(ev.position)
					if d < best:
						best = d; drag = i
		elif ev is InputEventMouseMotion and drag >= 0:
			pts[drag] = _to_img(ev.position); queue_redraw()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_load()
	var mg := MarginContainer.new(); mg.set_anchors_preset(PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]: mg.add_theme_constant_override("margin_" + k, 10)
	add_child(mg)
	root = VBoxContainer.new(); root.add_theme_constant_override("separation", 10); mg.add_child(root)
	busy = ColorRect.new(); busy.color = Color(0, 0, 0, 0.55); busy.set_anchors_preset(PRESET_FULL_RECT); busy.visible = false
	busy.mouse_filter = Control.MOUSE_FILTER_STOP; add_child(busy)
	busy_lbl = Label.new(); busy_lbl.set_anchors_preset(PRESET_CENTER); busy_lbl.add_theme_font_size_override("font_size", 22); busy.add_child(busy_lbl)
	_home()


func _exit_tree() -> void:
	_stop_camera()


# ---------------------------------------------------------------- Données
func _load() -> void:
	if FileAccess.file_exists(IDX):
		var d = JSON.parse_string(FileAccess.get_file_as_string(IDX))
		if d is Array: docs = d


func _save() -> void:
	var f := FileAccess.open(IDX, FileAccess.WRITE)
	f.store_string(JSON.stringify(docs)); f.close()


func _thumb(path: String) -> Texture2D:
	if thumbs.has(path): return thumbs[path]
	var img := Image.load_from_file(path)
	if img == null: return null
	var k := 220.0 / maxf(img.get_width(), img.get_height())
	img.resize(maxi(8, int(img.get_width() * k)), maxi(8, int(img.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	thumbs[path] = ImageTexture.create_from_image(img)
	return thumbs[path]


# ---------------------------------------------------------------- Aides d'interface
func _clear() -> void:
	_stop_camera()
	for c in root.get_children():
		root.remove_child(c); c.queue_free()
	crop = null; prev = null; cam_view = null; cam_msg = null


func _bar(title: String, back := Callable()) -> PanelContainer:
	var hb := UI.header_bar(title, false); root.add_child(hb)
	if back.is_valid(): UI.bar_act(hb, hb.get_meta("start"), "arrow-left", "Retour", back)
	return hb


func _btn(t: String, cb: Callable, variation := "", w := 0) -> Button:
	var b := Button.new(); b.text = t; b.focus_mode = Control.FOCUS_NONE; b.custom_minimum_size = Vector2(w, 42)
	if variation != "": b.theme_type_variation = variation
	b.pressed.connect(cb); return b


func _row() -> HFlowContainer:
	var r := HFlowContainer.new(); r.add_theme_constant_override("h_separation", 6); r.add_theme_constant_override("v_separation", 6)
	r.alignment = FlowContainer.ALIGNMENT_CENTER; root.add_child(r); return r


func _set_busy(t: String) -> void:
	busy.visible = t != ""; busy_lbl.text = t
	busy_lbl.position = (busy.size - busy_lbl.size) / 2.0
	if t != "": busy.move_to_front()


## Travail lourd dans un thread ; `done` n'est appelé que si l'utilisateur n'a pas changé d'écran entre-temps.
func _bg(label: String, work: Callable, done: Callable) -> void:
	_set_busy(label); job += 1
	var tok := job
	WorkerThreadPool.add_task(func():
		var r = work.call()
		if is_instance_valid(self): _bg_finish.call_deferred(tok, done, r))


func _bg_finish(tok: int, done: Callable, r) -> void:
	if tok != job: return
	_set_busy(""); done.call(r)


# ---------------------------------------------------------------- Accueil : liste des documents
func _home() -> void:
	_clear(); doc = {}; pending = []; job += 1; _set_busy("")
	var hb := _bar("Scanner")
	var en := UI.bar_end(hb)
	UI.bar_act(hb, en, "upload", "Importer des photos", _import_pick)
	UI.bar_act(hb, en, "scan", "Scanner avec la caméra", _camera)
	if docs.is_empty():
		var l := Label.new(); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.text = "Aucun document.\nPhotographie une feuille ou importe une photo : elle sera redressée et rendue bien lisible."
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; root.add_child(l)
		var r := _row(); r.add_child(_btn("Scanner", _camera, "FlatOn", 140)); r.add_child(_btn("Importer une photo", _import_pick, "", 180))
		return
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; root.add_child(sc)
	var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.add_theme_constant_override("separation", 8); sc.add_child(v)
	for i in range(docs.size() - 1, -1, -1):
		var d: Dictionary = docs[i]
		var card := PanelContainer.new(); card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		UI.style(card, "panel", func(): var sb := StyleBoxFlat.new(); sb.bg_color = UI.p("card"); sb.set_corner_radius_all(UI.rad()); sb.set_content_margin_all(10); return sb)
		card.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _open_doc(i))
		var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 12); card.add_child(h)
		var t := TextureRect.new(); t.custom_minimum_size = Vector2(60, 78); t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not d.pages.is_empty(): t.texture = _thumb(d.pages[0])
		h.add_child(t)
		var nv := VBoxContainer.new(); nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; nv.alignment = BoxContainer.ALIGNMENT_CENTER; nv.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(nv)
		var nl := Label.new(); nl.text = str(d.name); nl.clip_text = true; nl.mouse_filter = Control.MOUSE_FILTER_IGNORE; nv.add_child(nl)
		var sl := UI.small("%d page(s) · %s" % [d.pages.size(), d.date]); sl.mouse_filter = Control.MOUSE_FILTER_IGNORE; nv.add_child(sl)
		v.add_child(card)


# ---------------------------------------------------------------- Document ouvert
func _open_doc(i: int) -> void:
	doc = docs[i]; _doc_view()


func _doc_view() -> void:
	_clear(); pending = []
	var hb := _bar(str(doc.name), _home)
	var en := UI.bar_end(hb)
	UI.bar_act(hb, en, "trash-2", "Supprimer le document", _delete_doc)
	UI.bar_act(hb, en, "download", "Enregistrer le PDF…", _save_pdf_as)
	UI.bar_act(hb, en, "file-text", "Lire le PDF", func(): _read_pdf())
	UI.bar_act(hb, en, "upload", "Ajouter une photo", _import_pick)
	UI.bar_act(hb, en, "scan", "Ajouter une page (caméra)", _camera)
	var ne := LineEdit.new(); ne.text = str(doc.name); ne.custom_minimum_size.y = 40; ne.placeholder_text = "Nom du document"
	ne.text_submitted.connect(func(t: String): _rename(t)); ne.focus_exited.connect(func(): _rename(ne.text)); root.add_child(ne)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; root.add_child(sc)
	var g := HFlowContainer.new(); g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 10); g.add_theme_constant_override("v_separation", 10); sc.add_child(g)
	for i in doc.pages.size():
		var p: String = doc.pages[i]
		var cv := VBoxContainer.new(); cv.add_theme_constant_override("separation", 4); g.add_child(cv)
		var t := TextureRect.new(); t.custom_minimum_size = Vector2(150, 200); t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; t.texture = _thumb(p); cv.add_child(t)
		var rb := HBoxContainer.new(); rb.alignment = BoxContainer.ALIGNMENT_CENTER; cv.add_child(rb)
		rb.add_child(UI.small("Page %d" % (i + 1)))
		var x := UI.icon_btn("trash-2", "Supprimer la page", func(): _delete_page(i), "Flat", 32); rb.add_child(x)


func _rename(t: String) -> void:
	if t.strip_edges() != "" and not doc.is_empty():
		doc.name = t.strip_edges(); _save()


func _delete_page(i: int) -> void:
	var p: String = doc.pages[i]
	if FileAccess.file_exists(p): DirAccess.remove_absolute(p)
	thumbs.erase(p); doc.pages.remove_at(i)
	if doc.pages.is_empty(): _delete_doc(); return
	_save(); _doc_view()


func _delete_doc() -> void:
	for p in doc.pages:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(p)
		thumbs.erase(p)
	var pdf := DIR.path_join(str(doc.id) + ".pdf")
	if FileAccess.file_exists(pdf): DirAccess.remove_absolute(pdf)
	docs.erase(doc); _save(); _home()


# ---------------------------------------------------------------- PDF
func _build_pdf() -> String:
	var out := DIR.path_join(str(doc.id) + ".pdf")
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null: return ""
	f.store_buffer(_make_pdf(doc.pages)); f.close()
	return out


func _read_pdf() -> void:
	var p := _build_pdf()
	if p != "" and m != null: m.open_with("pdf", p)


func _save_pdf_as() -> void:
	var p := _build_pdf()
	if p == "": return
	var fd := FileDialog.new(); fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE; fd.access = FileDialog.ACCESS_FILESYSTEM; fd.use_native_dialog = true
	fd.filters = PackedStringArray(["*.pdf ; PDF"]); fd.current_file = str(doc.name) + ".pdf"
	fd.file_selected.connect(func(dst: String):
		var o := FileAccess.open(dst, FileAccess.WRITE)
		if o: o.store_buffer(FileAccess.get_file_as_bytes(p)); o.close()
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd); fd.popup_centered_ratio(0.7)


## PDF minimal : une page par image, JPEG intégré tel quel (DCTDecode).
func _make_pdf(files: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new(); var offs := {}
	b.put_data("%PDF-1.4\n".to_utf8_buffer())
	var n := files.size(); var kids := ""
	for i in n: kids += "%d 0 R " % (3 + 3 * i)
	_pdf_obj(b, offs, 1, "<< /Type /Catalog /Pages 2 0 R >>")
	_pdf_obj(b, offs, 2, "<< /Type /Pages /Kids [%s] /Count %d >>" % [kids, n])
	for i in n:
		var jpg := FileAccess.get_file_as_bytes(files[i])
		var im := Image.load_from_file(files[i])
		var w := im.get_width(); var h := im.get_height()
		var k := 842.0 / float(maxi(w, h))
		var pw := "%.2f" % (w * k); var ph := "%.2f" % (h * k)
		var pg := 3 + 3 * i
		_pdf_obj(b, offs, pg, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %s %s] /Resources << /XObject << /Im0 %d 0 R >> >> /Contents %d 0 R >>" % [pw, ph, pg + 2, pg + 1])
		var cs := ("q %s 0 0 %s 0 0 cm /Im0 Do Q" % [pw, ph]).to_utf8_buffer()
		_pdf_obj(b, offs, pg + 1, "<< /Length %d >>" % cs.size(), cs)
		_pdf_obj(b, offs, pg + 2, "<< /Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length %d >>" % [w, h, jpg.size()], jpg)
	var total := 2 + 3 * n
	var xpos := b.get_position()
	var x := "xref\n0 %d\n0000000000 65535 f \n" % (total + 1)
	for num in range(1, total + 1): x += "%010d 00000 n \n" % offs[num]
	x += "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF" % [total + 1, xpos]
	b.put_data(x.to_utf8_buffer())
	return b.data_array


func _pdf_obj(b: StreamPeerBuffer, offs: Dictionary, num: int, head: String, stream := PackedByteArray()) -> void:
	offs[num] = b.get_position()
	b.put_data(("%d 0 obj\n%s" % [num, head]).to_utf8_buffer())
	if not stream.is_empty():
		b.put_data("\nstream\n".to_utf8_buffer()); b.put_data(stream); b.put_data("\nendstream".to_utf8_buffer())
	b.put_data("\nendobj\n".to_utf8_buffer())


# ---------------------------------------------------------------- Acquisition : caméra ou import
func _camera() -> void:
	_clear()
	var back: Callable = _home if doc.is_empty() else _doc_view
	_bar("Caméra", back)
	cam_view = TextureRect.new(); cam_view.size_flags_vertical = Control.SIZE_EXPAND_FILL; cam_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cam_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; root.add_child(cam_view)
	cam_msg = Label.new(); cam_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; cam_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; root.add_child(cam_msg)
	var r := _row()
	r.add_child(_btn("Capturer", _capture, "FlatOn", 160)); r.add_child(_btn("Importer une photo", _import_pick, "", 180))
	perm_btn = _btn("Réglages", func(): OS.request_permissions(), "", 120); perm_btn.visible = false; r.add_child(perm_btn)
	_start_camera()


func _start_camera() -> void:
	if OS.get_name() == "Android" and not OS.request_permission("CAMERA"):
		cam_msg.text = "Autorise la caméra dans la fenêtre Android qui s'affiche…"
		var res = await get_tree().on_request_permissions_result
		if not is_instance_valid(cam_view): return
		if res is Array and res.size() > 1 and not res[1]:
			cam_msg.text = "Permission caméra refusée. Touche « Réglages » pour l'autoriser, ou importe une photo."
			perm_btn.visible = true; return
		cam_msg.text = ""
	CameraServer.monitoring_feeds = true
	await get_tree().create_timer(0.8).timeout
	if not is_instance_valid(cam_view): return
	var fs := CameraServer.feeds()
	if fs.is_empty():
		cam_msg.text = "Aucune caméra détectée. Importe une photo avec le bouton ci-dessous."; return
	cam_feed = fs[0]; cam_feed.feed_is_active = true
	cam_tex = CameraTexture.new(); cam_tex.camera_feed_id = cam_feed.get_id(); cam_view.texture = cam_tex


func _stop_camera() -> void:
	if cam_feed != null: cam_feed.feed_is_active = false
	cam_feed = null; cam_tex = null
	CameraServer.monitoring_feeds = false


func _capture() -> void:
	var img: Image = cam_tex.get_image() if cam_tex != null else null
	if img == null or img.is_empty():
		if cam_msg: cam_msg.text = "Image de la caméra indisponible : importe une photo à la place."
		return
	_begin_crop(img)


func _import_pick() -> void:
	var fd := FileDialog.new(); fd.file_mode = FileDialog.FILE_MODE_OPEN_FILES; fd.access = FileDialog.ACCESS_FILESYSTEM; fd.use_native_dialog = true
	fd.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp,*.bmp ; Images"])
	fd.files_selected.connect(func(p: PackedStringArray): import_files(p); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd); fd.popup_centered_ratio(0.7)


func import_files(paths: PackedStringArray) -> void:
	pending = Array(paths); _next_pending()


func _next_pending() -> void:
	while not pending.is_empty():
		var img := Image.load_from_file(pending.pop_front())
		if img != null and not img.is_empty(): _begin_crop(img); return
	if doc.is_empty(): _home()
	else: _doc_view()


# ---------------------------------------------------------------- Recadrage
func _begin_crop(img: Image) -> void:
	if maxi(img.get_width(), img.get_height()) > MAXSRC:
		var k := float(MAXSRC) / maxi(img.get_width(), img.get_height())
		img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGB8); src = img
	_crop_view()


func _cancel_crop() -> void:
	if doc.is_empty(): _home()
	else: _doc_view()


func _set_filter(id: String) -> void:
	filt = id; _filter_view()


func _rot_warped(dir: ClockDirection) -> void:
	warped.rotate_90(dir); _apply_filter()


func _crop_view() -> void:
	_clear()
	_bar("Recadrer", _cancel_crop)
	crop = CropView.new(); crop.size_flags_vertical = Control.SIZE_EXPAND_FILL; crop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crop.custom_minimum_size = Vector2(200, 200); crop.clip_contents = true; root.add_child(crop)
	crop.set_image(src, detect(src))
	var r := _row()
	r.add_child(UI.icon_btn("rotate-ccw", "Pivoter à gauche", _rot_src.bind(COUNTERCLOCKWISE), "Flat", 44))
	r.add_child(UI.icon_btn("rotate-cw", "Pivoter à droite", _rot_src.bind(CLOCKWISE), "Flat", 44))
	r.add_child(_btn("Auto", _auto_crop, "", 80))
	r.add_child(_btn("Image entière", _full_crop, "", 130))
	r.add_child(_btn("Continuer  ›", _crop_done, "FlatOn", 140))


func _auto_crop() -> void:
	crop.set_image(src, detect(src))


func _full_crop() -> void:
	crop.set_image(src, _full(src))


func _rot_src(dir: ClockDirection) -> void:
	src.rotate_90(dir); crop.set_image(src, detect(src))


static func _full(img: Image) -> Array:
	var w := float(img.get_width()); var h := float(img.get_height())
	return [Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]


func _crop_done() -> void:
	var pts: Array = crop.pts.duplicate(); var s := src
	_bg("Redressement…", func(): return warp(s, pts), _on_warped)


# ---------------------------------------------------------------- Filtres et enregistrement
func _on_warped(r: Image) -> void:
	warped = r; _filter_view()


func _on_result(r: Image) -> void:
	result = r
	if prev: prev.texture = ImageTexture.create_from_image(r)


func _filter_view() -> void:
	_clear()
	_bar("Améliorer", _crop_view)
	prev = TextureRect.new(); prev.size_flags_vertical = Control.SIZE_EXPAND_FILL; prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; root.add_child(prev)
	var r := _row()
	for f in FILTERS:
		var id: String = f[0]
		r.add_child(_btn(f[1], _set_filter.bind(id), "FlatOn" if filt == id else "", 100))
	var r2 := _row()
	r2.add_child(UI.icon_btn("rotate-ccw", "Pivoter à gauche", _rot_warped.bind(COUNTERCLOCKWISE), "Flat", 44))
	r2.add_child(UI.icon_btn("rotate-cw", "Pivoter à droite", _rot_warped.bind(CLOCKWISE), "Flat", 44))
	r2.add_child(_btn("Enregistrer la page", _save_page.bind(false), "FlatOn", 190))
	r2.add_child(_btn("+ Page suivante", _save_page.bind(true), "", 160))
	_apply_filter()


func _apply_filter() -> void:
	var w := warped; var mode := filt
	_bg("Amélioration…", func(): return apply_filter(w, mode), _on_result)


func _save_page(more: bool) -> void:
	if result == null: return
	if doc.is_empty():
		var t := Time.get_datetime_dict_from_system()
		doc = {"id": "d%d" % Time.get_ticks_usec(), "name": "Scan %02d/%02d %02d:%02d" % [t.day, t.month, t.hour, t.minute],
			"date": "%02d/%02d/%d" % [t.day, t.month, t.year], "pages": []}
		docs.append(doc)
	DirAccess.make_dir_recursive_absolute(DIR.path_join(str(doc.id)))
	var p := DIR.path_join("%s/p%d.jpg" % [doc.id, Time.get_ticks_usec()])
	result.save_jpg(p, 0.9)
	doc.pages.append(p); _save()
	if not pending.is_empty(): _next_pending()
	elif more: _camera()
	else: _doc_view()


# ---------------------------------------------------------------- Traitement d'image (statique : utilisable dans un thread)
## Cherche la feuille : seuil d'Otsu, plus grande zone claire, coins = points extrêmes. Repli : cadre avec marge.
static func detect(img: Image) -> Array:
	var W := img.get_width(); var H := img.get_height()
	var sc := 240.0 / float(maxi(W, H))
	var s: Image = img.duplicate()
	s.resize(maxi(8, int(W * sc)), maxi(8, int(H * sc)), Image.INTERPOLATE_BILINEAR); s.convert(Image.FORMAT_L8)
	var w := s.get_width(); var h := s.get_height(); var d := s.get_data(); var n := w * h
	var hist := PackedInt32Array(); hist.resize(256)
	for v in d: hist[v] += 1
	var sum := 0.0
	for i in 256: sum += float(i * hist[i])
	var wb := 0; var sb := 0.0; var best := -1.0; var thr := 128
	for t in 256:
		wb += hist[t]
		if wb == 0: continue
		var wf := n - wb
		if wf == 0: break
		sb += float(t * hist[t])
		var mb := sb / wb; var mf := (sum - sb) / wf
		var vb := float(wb) * float(wf) * (mb - mf) * (mb - mf)
		if vb > best:
			best = vb; thr = t
	var seen := PackedByteArray(); seen.resize(n)
	var bcorn: Array = []; var bsize := 0
	for i0 in n:
		if d[i0] <= thr or seen[i0] == 1: continue
		var stack: Array = [i0]; seen[i0] = 1
		var cnt := 0
		var ext: Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		var key: Array = [1e9, -1e9, -1e9, 1e9]
		while not stack.is_empty():
			var idx: int = stack.pop_back(); cnt += 1
			var x := idx % w; var y := idx / w
			var p := Vector2(x, y)
			if x + y < key[0]:
				key[0] = x + y; ext[0] = p
			if x - y > key[1]:
				key[1] = x - y; ext[1] = p
			if x + y > key[2]:
				key[2] = x + y; ext[2] = p
			if x - y < key[3]:
				key[3] = x - y; ext[3] = p
			if x > 0 and seen[idx - 1] == 0 and d[idx - 1] > thr:
				seen[idx - 1] = 1; stack.append(idx - 1)
			if x < w - 1 and seen[idx + 1] == 0 and d[idx + 1] > thr:
				seen[idx + 1] = 1; stack.append(idx + 1)
			if y > 0 and seen[idx - w] == 0 and d[idx - w] > thr:
				seen[idx - w] = 1; stack.append(idx - w)
			if y < h - 1 and seen[idx + w] == 0 and d[idx + w] > thr:
				seen[idx + w] = 1; stack.append(idx + w)
		if cnt > bsize:
			bsize = cnt; bcorn = ext
	if bsize >= 0.12 * n and bsize <= 0.97 * n:
		var a := 0.0
		for i in 4:
			var p1: Vector2 = bcorn[i]; var p2: Vector2 = bcorn[(i + 1) % 4]
			a += p1.x * p2.y - p2.x * p1.y
		if absf(a) / 2.0 >= 0.12 * n:
			var out: Array = []
			for p in bcorn: out.append(p / sc)
			return out
	var mx := W * 0.06; var my := H * 0.06
	return [Vector2(mx, my), Vector2(W - mx, my), Vector2(W - mx, H - my), Vector2(mx, H - my)]


## Homographie : coefficients (a,b,c,d,e,f,g,h) qui envoient le rectangle de sortie sur les 4 coins de la photo.
static func _homography(dst: Array, srcp: Array) -> PackedFloat64Array:
	var A: Array = []
	for k in 4:
		var x: float = dst[k].x; var y: float = dst[k].y; var u: float = srcp[k].x; var v: float = srcp[k].y
		A.append([x, y, 1.0, 0.0, 0.0, 0.0, -x * u, -y * u, u])
		A.append([0.0, 0.0, 0.0, x, y, 1.0, -x * v, -y * v, v])
	for c in 8:
		var p := c
		for r in range(c + 1, 8):
			if absf(A[r][c]) > absf(A[p][c]): p = r
		var tmp: Array = A[c]; A[c] = A[p]; A[p] = tmp
		var pv: float = A[c][c]
		if absf(pv) < 1e-12: return PackedFloat64Array()
		for j in range(c, 9): A[c][j] = A[c][j] / pv
		for r in 8:
			if r == c: continue
			var f: float = A[r][c]
			if f == 0.0: continue
			for j in range(c, 9): A[r][j] = A[r][j] - f * A[c][j]
	var o := PackedFloat64Array()
	for r in 8: o.append(A[r][8])
	return o


## Redresse la zone délimitée par les 4 coins (haut-gauche, haut-droite, bas-droite, bas-gauche) en page rectangulaire.
static func warp(img: Image, c: Array) -> Image:
	var W := maxf((c[0] as Vector2).distance_to(c[1]), (c[3] as Vector2).distance_to(c[2]))
	var H := maxf((c[0] as Vector2).distance_to(c[3]), (c[1] as Vector2).distance_to(c[2]))
	var k := minf(1.0, float(MAXOUT) / maxf(W, H))
	var ow := maxi(16, int(W * k)); var oh := maxi(16, int(H * k))
	var hm := _homography([Vector2(0, 0), Vector2(ow, 0), Vector2(ow, oh), Vector2(0, oh)], c)
	if hm.is_empty(): return img.duplicate()
	var s: Image = img.duplicate(); s.convert(Image.FORMAT_RGB8)
	var sd := s.get_data(); var sw := s.get_width(); var sh := s.get_height()
	var out := PackedByteArray(); out.resize(ow * oh * 3)
	var a := hm[0]; var b := hm[1]; var cc := hm[2]; var d := hm[3]; var e := hm[4]; var f := hm[5]; var g := hm[6]; var hh := hm[7]
	var o := 0
	for y in oh:
		for x in ow:
			var den := g * x + hh * y + 1.0
			var u: float = (a * x + b * y + cc) / den
			var v: float = (d * x + e * y + f) / den
			var x0 := clampi(floori(u), 0, sw - 2); var y0 := clampi(floori(v), 0, sh - 2)
			var fx := clampf(u - x0, 0.0, 1.0); var fy := clampf(v - y0, 0.0, 1.0)
			var i00 := (y0 * sw + x0) * 3; var i10 := i00 + 3; var i01 := i00 + sw * 3; var i11 := i01 + 3
			for ch in 3:
				var top := sd[i00 + ch] * (1.0 - fx) + sd[i10 + ch] * fx
				var bot := sd[i01 + ch] * (1.0 - fx) + sd[i11 + ch] * fx
				out[o + ch] = int(top * (1.0 - fy) + bot * fy)
			o += 3
	return Image.create_from_data(ow, oh, false, Image.FORMAT_RGB8, out)


## Filtres : on estime le fond (papier + éclairage) puis on divise par lui -> fond blanc uniforme, texte net.
static func apply_filter(img: Image, mode: String) -> Image:
	var o: Image = img.duplicate(); o.convert(Image.FORMAT_RGB8)
	if mode == "orig": return o
	var w := o.get_width(); var h := o.get_height()
	var sw := maxi(4, w / 16); var sh := maxi(4, h / 16)
	var small: Image = o.duplicate(); small.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
	var sd := small.get_data(); var mx := sd.duplicate()
	for y in sh:
		for x in sw:
			for ch in 3:
				var bv := 0
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						bv = maxi(bv, sd[(clampi(y + dy, 0, sh - 1) * sw + clampi(x + dx, 0, sw - 1)) * 3 + ch])
				mx[(y * sw + x) * 3 + ch] = bv
	var bg := Image.create_from_data(sw, sh, false, Image.FORMAT_RGB8, mx)
	bg.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var bd := bg.get_data(); var od := o.get_data()
	# Courbes pré-calculées (smoothstep) : couleur (Magique) et niveaux de gris / noir et blanc.
	var lut_c := PackedByteArray(); var lut_g := PackedByteArray(); var lut_b := PackedByteArray()
	for i in 256:
		var v := i / 255.0
		var t := clampf((v - 0.30) / 0.65, 0.0, 1.0); lut_c.append(int(t * t * (3.0 - 2.0 * t) * 255.0))
		t = clampf((v - 0.28) / 0.67, 0.0, 1.0); lut_g.append(int(t * t * (3.0 - 2.0 * t) * 255.0))
		t = clampf((v - 0.58) / 0.22, 0.0, 1.0); lut_b.append(int(t * t * (3.0 - 2.0 * t) * 255.0))
	var n := w * h * 3
	if mode == "magic":
		for i in n:
			var r := int(clampf(float(od[i]) / maxf(bd[i], 1.0), 0.0, 1.0) * 255.0)
			od[i] = lut_c[r]
	else:
		var lut := lut_b if mode == "bw" else lut_g
		for i in range(0, n, 3):
			var gy := 0.299 * od[i] + 0.587 * od[i + 1] + 0.114 * od[i + 2]
			var gb := 0.299 * bd[i] + 0.587 * bd[i + 1] + 0.114 * bd[i + 2]
			var r := lut[int(clampf(gy / maxf(gb, 1.0), 0.0, 1.0) * 255.0)]
			od[i] = r; od[i + 1] = r; od[i + 2] = r
	return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, od)
