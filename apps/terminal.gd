extends Control
const UI = preload("res://apps/ui.gd")
## Terminal : onglets, historique, cd. Linux : bash -c via OS.execute_with_pipe (non bloquant, Ctrl+C, timeout).
## Android (ou builtins_only) : commandes intégrées seulement. Pas de TTY interactif complet.

var main: Node = null
var builtins_only := OS.get_name() != "Linux"
var timeout_s := 120.0
var tabs: Array = []     # sessions : {out, cwd, hist, hi, run, name}
var cur := 0
var tabbar: HBoxContainer
var stack: Control
var inp: LineEdit
var plbl: Label
var mono: SystemFont

const HELP := "Terminal LangOS\\n  Linux : toute commande est exécutée par bash -c (ssh, git, python... fonctionnent).\\n  Intégrées : ls cd cat echo pwd mkdir rm cp mv clear help exit\\n  Ctrl+C : interrompt la commande ; Haut/Bas : historique ; pendant une commande, la saisie est envoyée sur son entrée standard.\\n  Limite : pas de TTY interactif complet (pas de vim/top/ssh avec mot de passe interactif, pas de couleurs ANSI).\\n  Android : seules les commandes intégrées sont disponibles."

func _col(k: String, fb: Color) -> Color: return main._p(k) if main else fb

func home() -> String:
	if OS.get_name() == "Android": return "/storage/emulated/0" if DirAccess.dir_exists_absolute("/storage/emulated/0") else "user://"
	var h := OS.get_environment("HOME")
	return h if h != "" else "user://"

# ------------------------------------------------------------------ sessions
func new_session() -> Dictionary:
	var o := RichTextLabel.new(); o.scroll_following = true; o.selection_enabled = true; o.context_menu_enabled = true
	o.set_anchors_preset(Control.PRESET_FULL_RECT); o.fit_content = false
	o.add_theme_font_override("normal_font", mono); o.add_theme_font_override("bold_font", mono)
	o.add_theme_font_size_override("normal_font_size", 16); o.add_theme_font_size_override("bold_font_size", 16)
	o.add_theme_color_override("default_color", _col("text", Color("e5e9f0")))
	var s := {"out": o, "cwd": home(), "hist": [], "hi": 0, "run": null, "name": "Terminal %d" % (tabs.size() + 1)}
	if stack: stack.add_child(o)
	tabs.append(s)
	return s

func _sess() -> Dictionary: return tabs[cur]

func println(s: Dictionary, t: String, col := Color(0, 0, 0, 0)) -> void:
	var o: RichTextLabel = s["out"]
	if col.a > 0: o.push_color(col)
	o.add_text(t)
	if col.a > 0: o.pop()

func out_text(s: Dictionary) -> String: return (s["out"] as RichTextLabel).get_parsed_text()

func resolve(s: Dictionary, p: String) -> String:
	if p == "~" or p.begins_with("~/"): p = home().path_join(p.substr(2))
	if p.begins_with("/") or p.contains("://"): return p.simplify_path()
	return str(s["cwd"]).path_join(p).simplify_path()

func tokenize(line: String) -> PackedStringArray:
	var out := PackedStringArray(); var cur_t := ""; var q := ""; var has := false
	for ch in line:
		if q != "":
			if ch == q: q = ""
			else: cur_t += ch
		elif ch == "\"" or ch == "'": q = ch; has = true
		elif ch == " " or ch == "\t":
			if cur_t != "" or has: out.append(cur_t); cur_t = ""; has = false
		else: cur_t += ch
	if cur_t != "" or has: out.append(cur_t)
	return out

# ------------------------------------------------------------------ commandes intégrées
func _rmr(p: String) -> void:
	if DirAccess.dir_exists_absolute(p):
		for d in DirAccess.get_directories_at(p): _rmr(p.path_join(d))
		for f in DirAccess.get_files_at(p): DirAccess.remove_absolute(p.path_join(f))
	DirAccess.remove_absolute(p)

func _cpr(a: String, b: String) -> bool:
	if DirAccess.dir_exists_absolute(a):
		if b == a or b.begins_with(a + "/"): return false
		DirAccess.make_dir_recursive_absolute(b); var ok := true
		for d in DirAccess.get_directories_at(a): ok = _cpr(a.path_join(d), b.path_join(d)) and ok
		for f in DirAccess.get_files_at(a): ok = DirAccess.copy_absolute(a.path_join(f), b.path_join(f)) == OK and ok
		return ok
	return DirAccess.copy_absolute(a, b) == OK

## Exécute une commande intégrée ; renvoie false si la commande n'en est pas une.
func builtin(s: Dictionary, line: String, force := false) -> bool:
	var a := tokenize(line)
	if a.is_empty(): return true
	var c := a[0]; var args: Array = Array(a.slice(1))
	var flags := args.filter(func(x): return x.begins_with("-") and x.length() > 1)
	var pa := args.filter(func(x): return not (x.begins_with("-") and x.length() > 1))
	var always := ["cd", "clear", "help", "exit"]
	if not (c in always) and not builtins_only and not force: return false
	match c:
		"help": println(s, HELP.replace("\\n", "\n") + "\n")
		"clear": (s["out"] as RichTextLabel).clear()
		"exit": _close_tab(tabs.find(s))
		"pwd": println(s, str(s["cwd"]) + "\n")
		"echo": println(s, " ".join(args) + "\n")
		"cd":
			var t := home() if pa.is_empty() else resolve(s, pa[0])
			if DirAccess.dir_exists_absolute(t): s["cwd"] = t
			else: println(s, "cd: %s : dossier introuvable\n" % t, UI.err())
		"ls":
			var d := resolve(s, pa[0]) if not pa.is_empty() else str(s["cwd"])
			if FileAccess.file_exists(d): println(s, d.get_file() + "\n"); return true
			if not DirAccess.dir_exists_absolute(d): println(s, "ls: %s : introuvable\n" % d, UI.err()); return true
			var names: Array = []
			for x in DirAccess.get_directories_at(d): names.append(x + "/")
			for x in DirAccess.get_files_at(d): names.append(x)
			names.sort_custom(func(x, y): return x.naturalnocasecmp_to(y) < 0)
			if "-l" in flags:
				for n in names: println(s, ("d " if n.ends_with("/") else "- ") + n + "\n")
			else: println(s, "  ".join(names) + "\n")
		"cat":
			for p in pa:
				var f := resolve(s, p)
				if FileAccess.file_exists(f): println(s, FileAccess.get_file_as_string(f) + ("" if FileAccess.get_file_as_string(f).ends_with("\n") else "\n"))
				else: println(s, "cat: %s : fichier introuvable\n" % p, UI.err())
		"mkdir":
			for p in pa: DirAccess.make_dir_recursive_absolute(resolve(s, p))
		"rm":
			var rec := false
			for f in flags: if f.contains("r") or f.contains("R"): rec = true
			for p in pa:
				var f := resolve(s, p)
				if DirAccess.dir_exists_absolute(f):
					if rec: _rmr(f)
					else: println(s, "rm: %s est un dossier (utiliser -r)\n" % p, UI.err())
				elif FileAccess.file_exists(f): DirAccess.remove_absolute(f)
				else: println(s, "rm: %s : introuvable\n" % p, UI.err())
		"cp", "mv":
			if pa.size() != 2: println(s, "%s : usage : %s source destination\n" % [c, c], UI.err()); return true
			var src := resolve(s, pa[0]); var dst := resolve(s, pa[1])
			if DirAccess.dir_exists_absolute(dst): dst = dst.path_join(src.get_file())
			if not (FileAccess.file_exists(src) or DirAccess.dir_exists_absolute(src)): println(s, "%s: %s : introuvable\n" % [c, pa[0]], UI.err()); return true
			var ok := _cpr(src, dst)
			if ok and c == "mv": _rmr(src)
			if not ok: println(s, "%s : échec\n" % c, UI.err())
		_:
			println(s, "%s : commande inconnue (tapez help)\n" % c, UI.err())
	return true

# ------------------------------------------------------------------ exécution bash
class Job:
	var pid := 0
	var io: FileAccess
	var err: FileAccess
	var mtx := Mutex.new()
	var buf := PackedByteArray()
	var ebuf := PackedByteArray()
	var th: Array = []
	var done := 0
	var t0 := 0.0
	func pump(f: FileAccess, e: bool) -> void:
		while f.is_open():
			var b := f.get_buffer(1)
			if b.is_empty(): break
			mtx.lock()
			if e: ebuf.append(b[0])
			else: buf.append(b[0])
			mtx.unlock()
		mtx.lock(); done += 1; mtx.unlock()

var _ansi := RegEx.new()

func run_line(s: Dictionary, line: String) -> void:
	line = line.strip_edges()
	if line == "": return
	if s["run"] != null: # entrée standard de la commande en cours
		var j: Job = s["run"]
		if j.io and j.io.is_open(): j.io.store_string(line + "\n"); j.io.flush()
		return
	println(s, "%s $ %s\n" % [str(s["cwd"]).get_file() if str(s["cwd"]) != "/" else "/", line], _col("text", Color.WHITE).darkened(0.25))
	if builtin(s, line): return
	var j := Job.new()
	var r := OS.execute_with_pipe("bash", ["-c", "cd \"$0\" && eval \"$1\"", ProjectSettings.globalize_path(str(s["cwd"])), line], false)
	if r.is_empty() or int(r.get("pid", 0)) <= 0:
		println(s, "Impossible de lancer bash\n", UI.err()); return
	j.pid = int(r["pid"]); j.io = r["stdio"]; j.err = r["stderr"]; j.t0 = Time.get_ticks_msec() / 1000.0
	for pr in [[j.io, false], [j.err, true]]:
		var t := Thread.new(); t.start(j.pump.bind(pr[0], pr[1])); j.th.append(t)
	s["run"] = j

func cancel(s: Dictionary, why := "^C") -> void:
	var j: Job = s["run"]
	if j == null: return
	OS.execute("pkill", ["-TERM", "-P", str(j.pid)])
	OS.kill(j.pid)
	println(s, why + "\n", UI.warn())

func _clean(b: PackedByteArray) -> String:
	if _ansi.get_group_count() == 0 and _ansi.get_pattern() == "": _ansi.compile("\u001b\\[[0-9;?]*[ -/]*[@-~]")
	return _ansi.sub(b.get_string_from_utf8().replace("\r", ""), "", true)

func _process(_d: float) -> void:
	for s in tabs:
		var j: Job = s["run"]
		if j == null: continue
		j.mtx.lock(); var b := j.buf; var e := j.ebuf; j.buf = PackedByteArray(); j.ebuf = PackedByteArray(); var dn := j.done; j.mtx.unlock()
		if b.size() > 0: println(s, _clean(b))
		if e.size() > 0: println(s, _clean(e), UI.err())
		if dn >= 2 and not OS.is_process_running(j.pid):
			for t in j.th: (t as Thread).wait_to_finish()
			s["run"] = null
			if s == tabs[cur]: _refresh_prompt()
		elif Time.get_ticks_msec() / 1000.0 - j.t0 > timeout_s:
			cancel(s, "[délai de %d s dépassé]" % int(timeout_s)); j.t0 = 1e12
	if inp and not tabs.is_empty() and plbl:
		var busy: bool = tabs[cur]["run"] != null
		var want := "▶" if busy else str(tabs[cur]["cwd"]).get_file() + " $"
		if plbl.text != want: plbl.text = want

func _exit_tree() -> void:
	for s in tabs: if s["run"] != null: OS.kill((s["run"] as Job).pid)

# ------------------------------------------------------------------ interface
func _refresh_prompt() -> void: pass

func _ready() -> void:
	mono = SystemFont.new(); mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Noto Sans Mono", "monospace"])
	var vb := VBoxContainer.new(); vb.set_anchors_preset(Control.PRESET_FULL_RECT); vb.add_theme_constant_override("separation", 4); add_child(vb)
	tabbar = HBoxContainer.new(); tabbar.add_theme_constant_override("separation", 4); vb.add_child(tabbar)
	var pc := PanelContainer.new(); pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UI.style(pc, "panel", func(): return UI.box(_col("field", Color("171b25")), UI.rad(-4), Color(0, 0, 0, 0), 0, UI.S2)); vb.add_child(pc)
	stack = Control.new(); stack.clip_contents = true; pc.add_child(stack)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6); vb.add_child(row)
	plbl = Label.new(); plbl.add_theme_font_override("font", mono); plbl.add_theme_color_override("font_color", UI.ok()); row.add_child(plbl)
	inp = LineEdit.new(); inp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; inp.custom_minimum_size.y = 40
	inp.add_theme_font_override("font", mono); inp.placeholder_text = "Commande (help)"
	inp.text_submitted.connect(_submit); inp.gui_input.connect(_key); row.add_child(inp)
	var s := new_session()
	println(s, "Terminal LangOS : tapez help.\n", UI.muted_c())
	_rebuild_tabs(); inp.grab_focus()

func _rebuild_tabs() -> void:
	for c in tabbar.get_children(): c.queue_free()
	for i in tabs.size():
		var b := Button.new(); b.text = tabs[i]["name"]; b.toggle_mode = true; b.button_pressed = i == cur; b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(90, 36); b.pressed.connect(_select.bind(i)); tabbar.add_child(b)
	var n := Button.new(); n.text = "+"; n.custom_minimum_size = Vector2(40, 36); n.focus_mode = Control.FOCUS_NONE
	n.pressed.connect(func(): new_session(); _select(tabs.size() - 1)); tabbar.add_child(n)
	var x := Button.new(); x.text = "✕"; x.custom_minimum_size = Vector2(40, 36); x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(func(): _close_tab(cur)); tabbar.add_child(x)

func _select(i: int) -> void:
	cur = clampi(i, 0, tabs.size() - 1)
	for k in tabs.size(): (tabs[k]["out"] as Control).visible = k == cur
	_rebuild_tabs()

func _close_tab(i: int) -> void:
	if i < 0 or i >= tabs.size(): return
	cancel(tabs[i], "")
	(tabs[i]["out"] as Node).queue_free(); tabs.remove_at(i)
	if tabs.is_empty(): new_session()
	_select(mini(cur, tabs.size() - 1))

func _submit(t: String) -> void:
	inp.clear()
	var s := _sess()
	if s["run"] == null and t.strip_edges() != "":
		s["hist"].append(t); s["hi"] = s["hist"].size()
	run_line(s, t)

func _key(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed): return
	var s := _sess()
	if ev.keycode == KEY_C and ev.ctrl_pressed and s["run"] != null: cancel(s); inp.accept_event()
	elif ev.keycode == KEY_UP and not s["hist"].is_empty():
		s["hi"] = maxi(0, int(s["hi"]) - 1); inp.text = s["hist"][s["hi"]]; inp.caret_column = inp.text.length(); inp.accept_event()
	elif ev.keycode == KEY_DOWN:
		s["hi"] = mini(s["hist"].size(), int(s["hi"]) + 1)
		inp.text = "" if s["hi"] >= s["hist"].size() else s["hist"][s["hi"]]; inp.caret_column = inp.text.length(); inp.accept_event()
