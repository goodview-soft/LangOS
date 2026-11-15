extends Node
## Recherche globale (Ctrl+Espace) : apps, profils, paramètres, commandes, notes, fichiers (index paresseux en thread, cache user://search_index.json).
var m
var panel: PanelContainer
var catcher: Control
var field: LineEdit
var box: VBoxContainer
var res: Array = []      # [type, titre, détail, Callable]
var sel := 0
var index: Array = []
var th: Thread
var scanning := false
var found: Array = []
var stamp := 0
var deb: Timer
const CACHE := "user://search_index.json"
const MAX_FILES := 6000
const MAX_DEPTH := 4
const SKIP := ["node_modules", "snap", "build", "venv", "__pycache__", "proc", "sys"]
const CODE := ["txt", "md", "log", "json", "cfg", "gd", "csv", "ini", "xml", "html", "py", "sh", "js", "css", "php", "yml", "yaml", "toml"]
const IMG := ["png", "jpg", "jpeg", "webp", "bmp"]
const SETTINGS := ["Apparence", "Fond d'écran", "Taille de police", "Zoom", "Clavier", "Curseur et pavé tactile", "Langues", "Animations", "Rayon des coins", "Transparence des fenêtres", "Couleur d'accent"]

func is_open() -> bool: return panel != null and is_instance_valid(panel)

func fold(s: String) -> String:
	s = s.to_lower()
	for p in [["é", "e"], ["è", "e"], ["ê", "e"], ["ë", "e"], ["à", "a"], ["â", "a"], ["î", "i"], ["ï", "i"], ["ô", "o"], ["ù", "u"], ["û", "u"], ["ç", "c"], ["'", " "], ["’", " "]]: s = s.replace(p[0], p[1])
	return s

# ------------------------------------------------------------------ index des fichiers
func roots() -> Array:
	var r := [ProjectSettings.globalize_path("user://")]
	var h := OS.get_environment("HOME")
	if h != "" and OS.get_name() != "Android": r.append(h)
	return r

func ensure_index() -> void:
	if index.is_empty() and FileAccess.file_exists(CACHE):
		var j = JSON.parse_string(FileAccess.get_file_as_string(CACHE))
		if j is Dictionary: index = j.get("f", []); stamp = int(j.get("t", 0))
	if not scanning and Time.get_unix_time_from_system() - stamp > 600: reindex()

func reindex() -> void:
	if scanning: return
	scanning = true; found = []
	th = Thread.new(); th.start(_scan.bind(roots()))
	set_process(true)

func _scan(rs: Array) -> void:
	var out := []; var q := []
	for r in rs: q.append([r, 0])
	while not q.is_empty() and out.size() < MAX_FILES:
		var e: Array = q.pop_front(); var d := DirAccess.open(e[0])
		if d == null: continue
		d.include_hidden = false
		for n in d.get_files(): if out.size() < MAX_FILES: out.append(e[0].path_join(n))
		if e[1] < MAX_DEPTH:
			for n in d.get_directories(): if not SKIP.has(n): q.append([e[0].path_join(n), e[1] + 1])
	found = out; scanning = false

func _process(_dt: float) -> void:
	if th != null and not scanning:
		th.wait_to_finish(); th = null; index = found; stamp = int(Time.get_unix_time_from_system()); set_process(false)
		var f := FileAccess.open(CACHE, FileAccess.WRITE)
		if f: f.store_string(JSON.stringify({"t": stamp, "f": index}))
		if is_open(): _show_results(query(field.text, true))

func _exit_tree() -> void:
	if th != null: th.wait_to_finish()

# ------------------------------------------------------------------ requêtes
func query(q: String, files := true) -> Array:
	var f := fold(q.strip_edges()); var out: Array = []
	var P = m.prof
	if f == "":
		for i in P.all().size(): out.append(["Profil", str(P.all()[i]["name"]), "Activer", P.activate.bind(i)])
		return out.slice(0, 8)
	var cmds := [["Thème clair", func(): if not m.set_cfg.get("light", false): m._set_light(true)], ["Thème sombre", func(): if m.set_cfg.get("light", false): m._set_light(false)],
		["Nouveau bureau virtuel", m._vd_add], ["Disposer les fenêtres", m._tile_all], ["Ranger les icônes", m._reset_icons], ["Fond d'écran suivant", func(): m._set_gradient((int(m.set_cfg["bg"]) + 1) % m.BG_GRADS.size())],
		["Animations activées / désactivées", func(): m.fx.set_anim(not m.fx.on())]]
	for i in m.n_vd: cmds.append(["Aller au bureau %d" % (i + 1), m._goto_vd.bind(i)])
	var pre := []; var inn := []
	for id in m.APPS:
		var n := fold(str(m.APPS[id][0]))
		if n.begins_with(f): pre.append(["Application", m.APPS[id][0], "Ouvrir", m._open_app.bind(id)])
		elif n.contains(f): inn.append(["Application", m.APPS[id][0], "Ouvrir", m._open_app.bind(id)])
	out += pre + inn
	for c in cmds: if fold(c[0]).contains(f): out.append(["Commande", c[0], "", c[1]])
	for i in P.all().size():
		var p: Dictionary = P.all()[i]
		if fold(str(p["name"])).contains(f) or "profil".begins_with(f): out.append(["Profil", str(p["name"]), "Activer", P.activate.bind(i)])
	for s in SETTINGS: if fold(s).contains(f): out.append(["Paramètre", s, "Paramètres", m._open_app.bind("settings")])
	var note: String = m.edit.text if is_instance_valid(m.edit) else FileAccess.get_file_as_string(m.SAVE_PATH)
	var k := 0
	for ln in note.split("\n"):
		if k >= 3: break
		if fold(ln).contains(f): out.append(["Note", ln.strip_edges().left(70), "Bloc-notes", m._open_app.bind("notepad")]); k += 1
	if files and f.length() >= 2:
		ensure_index(); k = 0
		for p in index:
			if fold(p.get_file()).contains(f):
				out.append(["Fichier", p.get_file(), p.get_base_dir(), open_file.bind(p)]); k += 1
				if k >= 8: break
	return out

func open_file(p: String) -> void:
	var e := p.get_extension().to_lower()
	if e in CODE:
		m._open_app("code")
		for n in m.wins["code"]["win"].find_children("*", "Control", true, false): if n.has_method("open_path"): n.open_path(p); return
	elif e in IMG: m.open_with("imgview", p)
	elif e == "pdf": m.open_with("pdf", p)
	elif m._real(): OS.shell_open(p)

# ------------------------------------------------------------------ interface
func toggle() -> void:
	if is_open(): close(); return
	catcher = Control.new(); catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: close())
	m.add_child(catcher)
	panel = PanelContainer.new(); panel.add_theme_stylebox_override("panel", m._box(m._p("menu"), m._rad() + 4, m._p("edge"), 1, 28, 14))
	m.add_child(panel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6); panel.add_child(v)
	field = LineEdit.new(); field.placeholder_text = "Rechercher apps, fichiers, notes, commandes…"; field.custom_minimum_size = Vector2(minf(560.0, m.size.x - 40.0), 46)
	field.add_theme_font_size_override("font_size", 20); field.text_changed.connect(_changed); field.gui_input.connect(_key); v.add_child(field)
	box = VBoxContainer.new(); box.add_theme_constant_override("separation", 0); v.add_child(box)
	deb = Timer.new(); deb.one_shot = true; deb.wait_time = 0.15; deb.timeout.connect(func(): _show_results(query(field.text, true))); panel.add_child(deb)
	_show_results(query("", false)); m.fx.popup_in(panel, false)
	field.grab_focus(); ensure_index()

func close() -> void:
	if is_instance_valid(panel): panel.queue_free()
	if is_instance_valid(catcher): catcher.queue_free()

func _changed(t: String) -> void:
	_show_results(query(t, false)); deb.start()

func _key(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed): return
	match ev.keycode:
		KEY_DOWN: _move(1)
		KEY_UP: _move(-1)
		KEY_ENTER, KEY_KP_ENTER: run(sel)
		KEY_ESCAPE: close()
		_: return
	field.accept_event()

func _move(d: int) -> void:
	if res.is_empty(): return
	sel = posmod(sel + d, res.size()); _paint()

func run(i: int) -> void:
	if i < 0 or i >= res.size(): return
	var c: Callable = res[i][3]; close(); c.call()

func _show_results(r: Array) -> void:
	res = r.slice(0, 9); sel = clampi(sel, 0, maxi(0, res.size() - 1))
	for c in box.get_children(): box.remove_child(c); c.queue_free()
	for i in res.size():
		var b: Button = m._mk_btn("%s   ·  %s   %s" % [res[i][0], res[i][1], res[i][2]], 0, 40); b.theme_type_variation = "Flat"; b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 16); b.clip_text = true; b.pressed.connect(run.bind(i)); b.focus_mode = Control.FOCUS_NONE; box.add_child(b)
	_paint()
	panel.size = panel.get_combined_minimum_size()
	panel.position = Vector2((m.size.x - panel.size.x) / 2.0, minf(m.size.y * 0.16, 120.0))

func _paint() -> void:
	for i in box.get_child_count(): box.get_child(i).modulate = m.ACCENT.lightened(0.45) if i == sel else Color.WHITE
