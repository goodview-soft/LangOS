extends Control
## Gestionnaire de fichiers : onglets, double panneau, corbeille, recherche, aperçu, ZIP, glisser-déposer.

const TRASH := "user://trash"
const TMETA := "user://trash.json"
const TXT := ["txt", "md", "log", "json", "cfg", "gd", "csv", "ini", "xml", "html", "py", "sh", "js", "css", "php", "yml", "yaml", "toml"]
const IMG := ["png", "jpg", "jpeg", "webp", "bmp", "svg"]
var main: Node = null
var cb := {"p": [], "cut": false}
var panes: Array = []
var act := 0
var dual := false
var prev_on := false
var pathe: LineEdit
var bar2: HBoxContainer
var pr_lbl: Label
var pr_in: LineEdit
var pr_cb: Callable
var prev_box: ScrollContainer
var prev_txt: Label
var prev_img: TextureRect
var panes_box: HBoxContainer
var ico := {}

class P:
	var tabs: Array = ["user://"]
	var i := 0
	var q := ""
	var items: Array = []
	var list: ItemList
	var tabbar: HBoxContainer
	var root: VBoxContainer

# ------------------------------------------------------------------ opérations (sans interface)
func _n(t: String, x := "") -> void:
	if main: main.notify(t, x)

func uniq(dir: String, name: String) -> String:
	var p := dir.path_join(name)
	var k := 2
	while FileAccess.file_exists(p) or DirAccess.dir_exists_absolute(p):
		p = dir.path_join("%s_%d%s" % [name.get_basename() if name.get_extension() != "" else name, k, "." + name.get_extension() if name.get_extension() != "" else ""]); k += 1
	return p

func ls(dir: String) -> Array:
	var d: Array = []; var f: Array = []
	for n in DirAccess.get_directories_at(dir): d.append(n)
	for n in DirAccess.get_files_at(dir): f.append(n)
	d.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0); f.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	return d.map(func(n): return dir.path_join(n)) + f.map(func(n): return dir.path_join(n))

func is_dir(p: String) -> bool: return DirAccess.dir_exists_absolute(p)

func fs_copy(src: String, dst: String) -> bool:
	if is_dir(src):
		if dst == src or dst.begins_with(src + "/"): return false
		DirAccess.make_dir_recursive_absolute(dst); var ok := true
		for c in ls(src): ok = fs_copy(c, dst.path_join(c.get_file())) and ok
		return ok
	return DirAccess.copy_absolute(src, dst) == OK

func fs_rm(p: String) -> void:
	if is_dir(p):
		for c in ls(p): fs_rm(c)
	DirAccess.remove_absolute(p)

func fs_move(src: String, dst: String) -> bool:
	if src == dst or dst.begins_with(src + "/"): return false
	if DirAccess.rename_absolute(src, dst) == OK: return true
	if fs_copy(src, dst): fs_rm(src); return true
	return false

func _meta() -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(TMETA)) if FileAccess.file_exists(TMETA) else {}
	return d if d is Dictionary else {}

func _save_meta(d: Dictionary) -> void:
	var f := FileAccess.open(TMETA, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))

func fs_trash(p: String) -> bool:
	DirAccess.make_dir_recursive_absolute(TRASH)
	var dst := uniq(TRASH, p.get_file())
	if not fs_move(p, dst): return false
	var m := _meta(); m[dst.get_file()] = p; _save_meta(m); return true

func fs_restore(p: String) -> bool:
	var m := _meta(); var orig: String = m.get(p.get_file(), "")
	if orig == "": orig = "user://".path_join(p.get_file())
	DirAccess.make_dir_recursive_absolute(orig.get_base_dir())
	if not fs_move(p, uniq(orig.get_base_dir(), orig.get_file())): return false
	m.erase(p.get_file()); _save_meta(m); return true

func fs_empty_trash() -> int:
	var n := 0
	if is_dir(TRASH):
		for c in ls(TRASH): fs_rm(c); n += 1
	_save_meta({}); return n

func fs_search(root: String, q: String, depth := 6, lim := 300) -> Array:
	var out: Array = []; q = q.to_lower()
	_srch(root, q, depth, lim, out); return out

func _srch(dir: String, q: String, depth: int, lim: int, out: Array) -> void:
	for c in ls(dir):
		if out.size() >= lim: return
		if c.get_file().to_lower().contains(q): out.append(c)
		if depth > 0 and is_dir(c): _srch(c, q, depth - 1, lim, out)

func _zadd(z: ZIPPacker, p: String, rel: String) -> void:
	if is_dir(p):
		for c in ls(p): _zadd(z, c, rel + "/" + c.get_file())
	else:
		z.start_file(rel); z.write_file(FileAccess.get_file_as_bytes(p)); z.close_file()

func fs_zip(paths: Array, zip: String) -> bool:
	var z := ZIPPacker.new()
	if z.open(zip) != OK: return false
	for p in paths: _zadd(z, p, p.get_file())
	z.close(); return true

func fs_unzip(zip: String, dir: String) -> bool:
	var r := ZIPReader.new()
	if r.open(zip) != OK: return false
	DirAccess.make_dir_recursive_absolute(dir)
	for f in r.get_files():
		if f.contains("..") or f.begins_with("/"): continue
		var dst := dir.path_join(f)
		if f.ends_with("/"): DirAccess.make_dir_recursive_absolute(dst); continue
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		var o := FileAccess.open(dst, FileAccess.WRITE)
		if o: o.store_buffer(r.read_file(f))
	r.close(); return true

func fs_paste(dst_dir: String) -> int:
	var n := 0
	for s in cb["p"]:
		if not (FileAccess.file_exists(s) or is_dir(s)): continue
		var d := uniq(dst_dir, s.get_file())
		if (fs_move(s, d) if cb["cut"] else fs_copy(s, d)): n += 1
	if cb["cut"]: cb["p"] = []
	return n

# ------------------------------------------------------------------ interface
func _col(k: String, fb: Color) -> Color: return main._p(k) if main else fb

func _icon(svg: String) -> ImageTexture:
	var im := Image.new(); im.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">%s</svg>' % svg)
	return ImageTexture.create_from_image(im)

func _btn(t: String, w: float, f: Callable) -> Button:
	var b := Button.new(); b.text = t; b.custom_minimum_size = Vector2(w, 40); b.focus_mode = Control.FOCUS_NONE; b.pressed.connect(f); return b

func _ready() -> void:
	ico = {"d": _icon('<path d="M3 9a2 2 0 0 1 2-2h8l3 3h11a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" fill="#f5b83d"/>'),
		"f": _icon('<path d="M8 3h11l6 6v20H8z" fill="#cbd5e1"/><path d="M19 3v6h6z" fill="#94a3b8"/>'),
		"i": _icon('<rect x="4" y="6" width="24" height="20" rx="3" fill="#34d399"/><circle cx="11" cy="13" r="3" fill="#fff"/><path d="M5 25l8-8 5 5 4-4 6 6z" fill="#047857"/>'),
		"z": _icon('<path d="M8 3h16v26H8z" fill="#a78bfa"/><path d="M15 3h2v3h-2v3h2v3h-2v3h2v3h-2" stroke="#fff" stroke-width="1.5" fill="none"/>')}
	var vb := VBoxContainer.new(); vb.set_anchors_preset(Control.PRESET_FULL_RECT); vb.add_theme_constant_override("separation", 6); add_child(vb)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 4); vb.add_child(top)
	top.add_child(_btn("↑", 44, func(): _go(_parent(_cur()))))
	pathe = LineEdit.new(); pathe.custom_minimum_size.y = 40; pathe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pathe.text_submitted.connect(func(t): _go(t.strip_edges())); top.add_child(pathe)
	top.add_child(_btn("+ Onglet", 80, func(): _new_tab()))
	top.add_child(_btn("2 volets", 84, func(): dual = not dual; panes[1].root.visible = dual))
	top.add_child(_btn("Aperçu", 70, func(): prev_on = not prev_on; prev_box.visible = prev_on; _preview()))
	var pl := ScrollContainer.new(); pl.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; pl.custom_minimum_size.y = 46; vb.add_child(pl)
	var pr := HBoxContainer.new(); pr.add_theme_constant_override("separation", 4); pl.add_child(pr)
	var places := [["Accueil", "user://"], ["Corbeille", TRASH]]
	var home := "/storage/emulated/0" if OS.get_name() == "Android" else OS.get_environment("HOME")
	if home != "" and is_dir(home): places.insert(1, ["Dossier perso", home])
	for p in ["/media", "/run/media/" + OS.get_environment("USER")]:
		if OS.get_name() == "Linux" and is_dir(p): places.append([p.get_file() if p == "/media" else "Média", p])
	for pp in places: pr.add_child(_btn(pp[0], 90, func(): _go(pp[1])))
	bar2 = HBoxContainer.new(); bar2.visible = false; bar2.add_theme_constant_override("separation", 4); vb.add_child(bar2)
	pr_lbl = Label.new(); bar2.add_child(pr_lbl)
	pr_in = LineEdit.new(); pr_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL; pr_in.custom_minimum_size.y = 40
	pr_in.text_submitted.connect(func(_t): _prompt_ok()); bar2.add_child(pr_in)
	bar2.add_child(_btn("OK", 50, _prompt_ok)); bar2.add_child(_btn("✕", 44, func(): bar2.visible = false))
	var mid := HBoxContainer.new(); mid.size_flags_vertical = Control.SIZE_EXPAND_FILL; mid.add_theme_constant_override("separation", 6); vb.add_child(mid)
	panes_box = HBoxContainer.new(); panes_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panes_box.add_theme_constant_override("separation", 6); mid.add_child(panes_box)
	for k in 2: panes.append(_mk_pane(k))
	panes[1].root.visible = false
	prev_box = ScrollContainer.new(); prev_box.custom_minimum_size.x = 200; prev_box.visible = false; mid.add_child(prev_box)
	var pv := VBoxContainer.new(); pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; prev_box.add_child(pv)
	prev_img = TextureRect.new(); prev_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; prev_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT; prev_img.custom_minimum_size = Vector2(190, 160); pv.add_child(prev_img)
	prev_txt = Label.new(); prev_txt.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY; prev_txt.custom_minimum_size.x = 190; pv.add_child(prev_txt)
	var sb := HBoxContainer.new(); sb.add_theme_constant_override("separation", 4); vb.add_child(sb)
	var se := LineEdit.new(); se.placeholder_text = "Rechercher par nom (sous-dossiers)…"; se.custom_minimum_size.y = 40; se.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	se.text_submitted.connect(func(t): search(t)); sb.add_child(se)
	sb.add_child(_btn("Chercher", 80, func(): search(se.text)))
	sb.add_child(_btn("Menu", 60, func(): _menu(get_global_mouse_position() - Vector2(0, 10), true)))
	_go("user://")

func _mk_pane(k: int) -> P:
	var p := P.new()
	p.root = VBoxContainer.new(); p.root.size_flags_horizontal = Control.SIZE_EXPAND_FILL; p.root.add_theme_constant_override("separation", 2); panes_box.add_child(p.root)
	var sc := ScrollContainer.new(); sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; sc.custom_minimum_size.y = 38; p.root.add_child(sc)
	p.tabbar = HBoxContainer.new(); p.tabbar.add_theme_constant_override("separation", 2); sc.add_child(p.tabbar)
	p.list = ItemList.new(); p.list.size_flags_vertical = Control.SIZE_EXPAND_FILL; p.list.select_mode = ItemList.SELECT_MULTI
	p.list.icon_mode = ItemList.ICON_MODE_LEFT; p.list.add_theme_font_size_override("font_size", 17); p.list.fixed_icon_size = Vector2i(26, 26)
	var sbx := StyleBoxFlat.new(); sbx.bg_color = _col("field", Color("171b25")); sbx.set_corner_radius_all(8); p.list.add_theme_stylebox_override("panel", sbx)
	p.list.add_theme_color_override("font_color", _col("text", Color("e5e9f0")))
	p.list.item_activated.connect(func(i): act = k; _open_item(p, i))
	p.list.item_selected.connect(func(_i): act = k; _preview())
	p.list.item_clicked.connect(func(i, at, b): act = k; if b == MOUSE_BUTTON_RIGHT: _menu(p.list.get_global_transform() * at, false, i))
	p.list.empty_clicked.connect(func(at, b): act = k; if b == MOUSE_BUTTON_RIGHT: _menu(p.list.get_global_transform() * at, true))
	p.list.set_drag_forwarding(func(_at): return _drag(p), func(_at, d): return d is Dictionary and d.has("fx"), func(at, d): _drop(p, at, d))
	p.root.add_child(p.list); return p

func _cur(pi := -1) -> String:
	var p: P = panes[act if pi < 0 else pi]; return p.tabs[p.i]

func _parent(p: String) -> String:
	if p.ends_with("://") or p == "/": return p
	var b := p.trim_suffix("/").get_base_dir()
	return b if b != "" else "/"

func _go(path: String, pi := -1) -> void:
	var p: P = panes[act if pi < 0 else pi]
	if path.begins_with("~"): path = OS.get_environment("HOME") + path.substr(1)
	if path == TRASH: DirAccess.make_dir_recursive_absolute(TRASH)
	if not is_dir(path):
		_n("Fichiers", "Dossier introuvable : " + path); return
	p.tabs[p.i] = path; p.q = ""; refresh()

func _new_tab() -> void:
	var p: P = panes[act]; p.tabs.append(_cur()); p.i = p.tabs.size() - 1; refresh()

func refresh() -> void:
	for p: P in panes:
		p.items = ls(p.tabs[p.i]) if p.q == "" else p.items
		_fill(p)
		for c in p.tabbar.get_children(): c.queue_free()
		for t in p.tabs.size():
			var b := Button.new(); b.text = p.tabs[t].get_file() if p.tabs[t].get_file() != "" else p.tabs[t]; b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size.y = 34; b.toggle_mode = true; b.button_pressed = t == p.i
			b.pressed.connect(func(): act = panes.find(p); p.i = t; p.q = ""; refresh())
			b.set_drag_forwarding(Callable(), func(_at, d): return d is Dictionary and d.has("fx"), func(_at, d): _do_drop(d, p.tabs[t]))
			p.tabbar.add_child(b)
			if p.tabs.size() > 1:
				var x := Button.new(); x.text = "×"; x.flat = true; x.focus_mode = Control.FOCUS_NONE
				x.pressed.connect(func(): p.tabs.remove_at(t); p.i = clampi(p.i, 0, p.tabs.size() - 1); refresh()); p.tabbar.add_child(x)
	pathe.text = _cur(); _preview()

func _fill(p: P) -> void:
	p.list.clear()
	for f in p.items:
		var e := str(f).get_extension().to_lower(); var d := is_dir(f)
		var t: String = str(f).get_file() if p.q == "" else str(f).trim_prefix(p.tabs[p.i])
		if not d: t += "   —   %s · %s" % [String.humanize_size(_size(f)), Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(f)).replace("T", " ").substr(0, 16)]
		p.list.add_item(t, ico["d"] if d else ico["i"] if e in IMG else ico["z"] if e == "zip" else ico["f"])
	if p.items.is_empty(): p.list.add_item("(vide)", null, false); p.list.set_item_disabled(0, true)

func _size(f: String) -> int:
	var h := FileAccess.open(f, FileAccess.READ)
	return h.get_length() if h else 0

func search(q: String) -> void:
	q = q.strip_edges(); if q == "": refresh(); return
	var p: P = panes[act]; p.items = fs_search(p.tabs[p.i], q); p.q = q; _fill(p)
	_n("Recherche", "%d résultat(s) pour « %s »" % [p.items.size(), q])

func _sel() -> Array:
	var p: P = panes[act]; var r: Array = []
	for i in p.list.get_selected_items(): if i < p.items.size(): r.append(p.items[i])
	return r

func _open_item(p: P, i: int) -> void:
	if i >= p.items.size(): return
	var f: String = p.items[i]
	if is_dir(f): _go(f)
	else: open_file(f)

func open_file(f: String) -> void:
	var e := f.get_extension().to_lower()
	if not main: return
	if e in IMG: if main._set_wallpaper(f): main.notify("Fond d'écran", "Image appliquée : " + f.get_file())
	elif e in TXT: main._open_app("notepad"); main.edit.text = FileAccess.get_file_as_string(f); main.notify("Bloc-notes", f.get_file() + " ouvert")
	elif e == "zip": _do_unzip(f)

func open_in_editor(f: String) -> void:
	if not main: return
	main._open_app("code")
	for n in main.wins["code"]["win"].find_children("*", "Control", true, false):
		if n.has_method("open_path"): n.open_path(f); return

func _preview() -> void:
	if not prev_on: return
	var s := _sel(); prev_img.texture = null; prev_txt.text = ""
	if s.is_empty(): return
	var f: String = s[0]; var e := f.get_extension().to_lower()
	if is_dir(f): prev_txt.text = "%s\n%d élément(s)" % [f.get_file(), ls(f).size()]
	elif e in IMG:
		var im := Image.load_from_file(f)
		if im: prev_img.texture = ImageTexture.create_from_image(im)
		prev_txt.text = f.get_file()
	elif e in TXT: prev_txt.text = FileAccess.get_file_as_string(f).substr(0, 3000)
	else: prev_txt.text = "%s\n%s" % [f.get_file(), String.humanize_size(_size(f))]

# ------------------------------------------------------------------ actions
func _menu(at: Vector2, bg: bool, idx := -1) -> void:
	if not main: return
	var s := _sel(); var p: P = panes[act]
	if idx >= 0 and idx < p.items.size() and not p.list.is_selected(idx): p.list.select(idx, true); s = _sel()
	var intr := _cur() == TRASH; var it: Array = []
	if not s.is_empty() and not bg:
		if s.size() == 1: it.append(["Ouvrir", func(): _open_item(p, p.items.find(s[0]))])
		if intr: it.append(["Restaurer", func(): _act_restore(s)])
		else: it += [["Copier", func(): cb = {"p": s, "cut": false}], ["Couper", func(): cb = {"p": s, "cut": true}]]
		if s.size() == 1 and not intr: it.append(["Renommer", func(): _ask("Nom :", s[0].get_file(), func(t): _rename(s[0], t))])
		if not intr: it.append(["Compresser en ZIP", func(): _do_zip(s)])
		if s.size() == 1 and s[0].get_extension().to_lower() == "zip": it.append(["Extraire ici", func(): _do_unzip(s[0])])
		if s.size() == 1 and not is_dir(s[0]) and s[0].get_extension().to_lower() in TXT: it.append(["Ouvrir dans l'éditeur", func(): open_in_editor(s[0])])
		if s.size() == 1 and s[0].get_extension().to_lower() in IMG: it.append(["Définir comme fond", func(): open_file(s[0])])
		it.append(["Supprimer définitivement" if intr else "Mettre à la corbeille", func(): _act_del(s, intr)])
		it.append(null)
	if not intr: it += [["Coller", func(): _act_paste()], ["Nouveau dossier", func(): _ask("Nom du dossier :", "Nouveau dossier", func(t): DirAccess.make_dir_recursive_absolute(uniq(_cur(), t)); refresh())]]
	else: it.append(["Vider la corbeille", func(): _n("Corbeille", "%d élément(s) supprimé(s)" % fs_empty_trash()); refresh()])
	it += [["Actualiser", refresh]]
	main._popup_menu(it, at)

func _ask(lbl: String, init: String, cbk: Callable) -> void:
	pr_lbl.text = lbl; pr_in.text = init; pr_cb = cbk; bar2.visible = true; pr_in.grab_focus()

func _prompt_ok() -> void:
	bar2.visible = false
	var t := pr_in.text.strip_edges()
	if t != "" and pr_cb.is_valid() and not t.contains("/"): pr_cb.call(t)

func _rename(f: String, t: String) -> void:
	if fs_move(f, f.get_base_dir().path_join(t)): refresh()

func _act_del(s: Array, perm: bool) -> void:
	for f in s:
		if perm: fs_rm(f)
		else: fs_trash(f)
	_n("Fichiers", "%d élément(s) %s" % [s.size(), "supprimé(s)" if perm else "mis à la corbeille"]); refresh()

func _act_restore(s: Array) -> void:
	var n := 0
	for f in s: if fs_restore(f): n += 1
	_n("Corbeille", "%d élément(s) restauré(s)" % n); refresh()

func _act_paste() -> void:
	var n := fs_paste(_cur()); _n("Fichiers", "%d élément(s) collé(s)" % n); refresh()

func _do_zip(s: Array) -> void:
	var z := uniq(_cur(), (s[0].get_file().get_basename() if s.size() == 1 else "archive") + ".zip")
	_n("ZIP", "Compression en cours…")
	_n("ZIP", z.get_file() + (" créé" if fs_zip(s, z) else " : échec")); refresh()

func _do_unzip(f: String) -> void:
	var d := uniq(f.get_base_dir(), f.get_file().get_basename())
	_n("ZIP", "Extraction en cours…")
	_n("ZIP", ("Extrait dans " + d.get_file()) if fs_unzip(f, d) else "Échec de l'extraction"); refresh()

func _drag(p: P) -> Variant:
	var s := _sel()
	if s.is_empty(): return null
	var l := Label.new(); l.text = "%d élément(s)" % s.size(); p.list.set_drag_preview(l)
	return {"fx": s}

func _drop(p: P, at: Vector2, d: Dictionary) -> void:
	var i := p.list.get_item_at_position(at, true)
	var dst: String = p.items[i] if i >= 0 and i < p.items.size() and is_dir(p.items[i]) else p.tabs[p.i]
	_do_drop(d, dst)

func _do_drop(d: Dictionary, dst: String) -> void:
	var n := 0
	for f in d["fx"]:
		if f.get_base_dir() == dst and not Input.is_key_pressed(KEY_CTRL): continue
		var t := uniq(dst, f.get_file())
		if (fs_copy(f, t) if Input.is_key_pressed(KEY_CTRL) else fs_move(f, t)): n += 1
	_n("Fichiers", "%d élément(s) déplacé(s)" % n); refresh()
