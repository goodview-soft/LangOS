extends Control
## Lecteur PDF : pas de moteur PDF dans Godot, on utilise pdftoppm / pdftotext / pdfinfo (poppler) s'ils existent (Linux).
## Sinon (Android, outils absents) : message « moteur PDF indisponible ». Pages rendues en cache user://pdfcache.
## Annotations (surlignage + notes) : user://pdfnotes_<hash>.json.
var m
const CACHE := "user://pdfcache"
var path := ""
var pages := 0
var page := 1
var zoom := 1.0
var tex: ImageTexture
var notes := {}            # "page" -> [{r:[x,y,w,h] (0..1), n:texte}]
var texts: Array = []      # texte par page (recherche)
var hl_mode := false
var view: Control
var lbl: Label
var pg_in: LineEdit
var q_in: LineEdit
var note_in: LineEdit
var _drag := false
var _a := Vector2.ZERO
var _b := Vector2.ZERO
var _avail := -1

static func tool_ok(t: String) -> bool:
	if OS.get_name() not in ["Linux", "macOS", "FreeBSD", "NetBSD", "OpenBSD"]: return false
	var o := []
	return OS.execute("which", [t], o) == 0 and not "".join(o).strip_edges().is_empty()

func engine_ok() -> bool:
	if _avail < 0: _avail = 1 if tool_ok("pdftoppm") and tool_ok("pdftotext") else 0
	return _avail == 1

func _key() -> String: return path.md5_text().substr(0, 12)
func _npath() -> String: return "user://pdfnotes_%s.json" % _key()

## Ouvre un PDF ; renvoie false (sans erreur) si moteur absent ou fichier illisible.
func load_pdf(p: String) -> bool:
	path = p; pages = 0; page = 1; tex = null; texts = []; notes = {}
	if not engine_ok(): _say("Moteur PDF indisponible sur cet appareil (pdftoppm requis)."); return false
	if not FileAccess.file_exists(p): _say("Fichier introuvable."); return false
	var o := []
	if tool_ok("pdfinfo") and OS.execute("pdfinfo", [p], o) == 0:
		for l in "".join(o).split("\n"): if l.begins_with("Pages:"): pages = int(l.substr(6).strip_edges())
	if pages < 1: _say("PDF illisible."); return false
	if FileAccess.file_exists(_npath()):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(_npath()))
		if d is Dictionary: notes = d
	_render()
	return true

func _cfile(pg: int, z: float) -> String: return "%s/%s_%d_%d.png" % [CACHE, _key(), pg, int(z * 100)]

## Rend la page (cache disque) ; renvoie le chemin PNG ou "".
func render_page(pg: int, z: float) -> String:
	DirAccess.make_dir_recursive_absolute(CACHE)
	var out := _cfile(pg, z)
	if FileAccess.file_exists(out): return out
	var base := ProjectSettings.globalize_path(out).trim_suffix(".png")
	var rc := OS.execute("pdftoppm", ["-f", str(pg), "-l", str(pg), "-r", str(int(90 * z)), "-png", "-singlefile", path, base])
	return out if rc == 0 and FileAccess.file_exists(out) else ""

func _render() -> void:
	var f := render_page(page, zoom)
	if f == "": _say("Rendu impossible."); tex = null
	else:
		var im := Image.load_from_file(f)
		tex = ImageTexture.create_from_image(im) if im else null
	_say("%s  page %d/%d  %d%%" % [path.get_file(), page, pages, int(zoom * 100)])
	if pg_in: pg_in.text = str(page)
	if view: view.queue_redraw()

## Pages contenant q (1-based), via pdftotext.
func search(q: String) -> Array:
	var out := []
	if q.strip_edges() == "" or not engine_ok() or pages < 1: return out
	if texts.is_empty():
		var o := []
		if OS.execute("pdftotext", ["-layout", path, "-"], o) != 0: return out
		texts = "".join(o).split("\f")
	for i in texts.size():
		if texts[i].to_lower().contains(q.to_lower()): out.append(i + 1)
	return out

func goto(p: int) -> void:
	if pages < 1: return
	page = clampi(p, 1, pages); _render()

func add_note(pg: int, r: Array, text: String) -> void:
	var k := str(pg)
	if not notes.has(k): notes[k] = []
	notes[k].append({"r": r, "n": text}); _save_notes()

func _save_notes() -> void:
	var f := FileAccess.open(_npath(), FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(notes))

func _say(t: String) -> void: if lbl: lbl.text = t

# ------------------------------------------------------------------ interface
func _c(k: String) -> Color: return m._p(k) if m else Color("232834")

func build() -> void:
	var vb := VBoxContainer.new(); vb.set_anchors_preset(Control.PRESET_FULL_RECT); vb.add_theme_constant_override("separation", 6); add_child(vb)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 4); vb.add_child(top)
	var bt := func(t: String, f: Callable) -> void:
		var b := Button.new(); b.text = t; b.custom_minimum_size = Vector2(44, 40); b.pressed.connect(f); top.add_child(b)
	bt.call("‹", func(): goto(page - 1)); bt.call("›", func(): goto(page + 1))
	pg_in = LineEdit.new(); pg_in.custom_minimum_size = Vector2(56, 40); pg_in.text_submitted.connect(func(t): goto(int(t))); top.add_child(pg_in)
	bt.call("+", func(): zoom = minf(zoom * 1.25, 4.0); _render()); bt.call("−", func(): zoom = maxf(zoom * 0.8, 0.4); _render())
	bt.call("Surligner", func(): hl_mode = not hl_mode; _say("Surlignage : trace un rectangle." if hl_mode else "Surlignage désactivé."))
	bt.call("Effacer", func(): notes.erase(str(page)); _save_notes(); view.queue_redraw())
	note_in = LineEdit.new(); note_in.placeholder_text = "Note du prochain surlignage"; note_in.custom_minimum_size.y = 40; note_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(note_in)
	var sr := HBoxContainer.new(); sr.add_theme_constant_override("separation", 4); vb.add_child(sr)
	q_in = LineEdit.new(); q_in.placeholder_text = "Rechercher dans le PDF…"; q_in.custom_minimum_size.y = 40; q_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q_in.text_submitted.connect(_search_ui); sr.add_child(q_in)
	view = Control.new(); view.size_flags_vertical = Control.SIZE_EXPAND_FILL; view.size_flags_horizontal = Control.SIZE_EXPAND_FILL; view.clip_contents = true
	view.draw.connect(_draw_view); view.gui_input.connect(_view_input); view.resized.connect(view.queue_redraw); vb.add_child(view)
	lbl = Label.new(); vb.add_child(lbl)
	_say("Ouvre un PDF depuis Fichiers." if engine_ok() else "Moteur PDF indisponible sur cet appareil (pdftoppm requis).")

func open_path(p: String) -> void: load_pdf(p)

func _search_ui(t: String) -> void:
	var r := search(t)
	if r.is_empty(): _say("Aucun résultat."); return
	_say("Trouvé pages : " + ", ".join(r.slice(0, 12).map(str))); goto(r[0] if not r.has(page) else r[(r.find(page) + 1) % r.size()])

var _scroll := 0.0
func _rect() -> Rect2:
	var s := tex.get_size()
	return Rect2(Vector2(maxf((view.size.x - s.x) / 2, 0.0), 8 - _scroll), s)

func _view_input(e: InputEvent) -> void:
	if tex == null: return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed: _scroll = clampf(_scroll + 60, 0, maxf(tex.get_height() - view.size.y + 16, 0)); view.queue_redraw()
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed: _scroll = maxf(_scroll - 60, 0); view.queue_redraw()
		elif e.button_index == MOUSE_BUTTON_LEFT and hl_mode:
			_drag = e.pressed
			if e.pressed: _a = e.position; _b = e.position
			else:
				var r := _rect(); var rr := Rect2(_a, _b - _a).abs()
				if rr.size.x > 3 and rr.size.y > 3:
					rr.position = (rr.position - r.position) / r.size; rr.size /= r.size
					add_note(page, [rr.position.x, rr.position.y, rr.size.x, rr.size.y], note_in.text); note_in.text = ""
				view.queue_redraw()
	elif e is InputEventMouseMotion and _drag: _b = e.position; view.queue_redraw()

func _draw_view() -> void:
	view.draw_rect(Rect2(Vector2.ZERO, view.size), _c("field"))
	if tex == null: return
	var r := _rect()
	view.draw_texture_rect(tex, r, false)
	for a in notes.get(str(page), []):
		var q: Array = a["r"]
		var rr := Rect2(r.position + Vector2(q[0], q[1]) * r.size, Vector2(q[2], q[3]) * r.size)
		view.draw_rect(rr, Color(1, 0.9, 0.1, 0.35))
		if str(a["n"]) != "": view.draw_string(get_theme_default_font(), rr.position + Vector2(2, -4), str(a["n"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("b45309"))
	if _drag: view.draw_rect(Rect2(_a, _b - _a).abs(), Color(1, 0.9, 0.1, 0.3))
