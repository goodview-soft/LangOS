extends SceneTree
## Test Terminal + Éditeur de code. flatpak run org.godotengine.Godot --headless --path . --script res://tests/dev_test.gd

func _init() -> void:
	var f: Array = []
	DirAccess.remove_absolute("user://code_session.json")
	var vp := SubViewport.new(); vp.size = Vector2i(1280, 720); vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	var m = load("res://main.tscn").instantiate(); vp.add_child(m)
	await create_timer(0.8).timeout
	for id in ["terminal", "code"]:
		if not m.APPS.has(id) or not m.FOLDERS["f_soft"].has(id): f.append("app " + id)
	# ---- terminal
	m._open_app("terminal"); await create_timer(0.4).timeout
	var T = null; var E = null
	for n in m.wins["terminal"]["win"].find_children("*", "Control", true, false): if n.has_method("run_line"): T = n
	if T == null: f.append("terminal introuvable")
	else:
		var s: Dictionary = T.tabs[0]
		T.run_line(s, "echo bonjour")
		var t0 := Time.get_ticks_msec()
		while s["run"] != null and Time.get_ticks_msec() - t0 < 8000: await process_frame
		await create_timer(0.2).timeout
		if not T.out_text(s).contains("bonjour"): f.append("echo bash: " + T.out_text(s))
		DirAccess.make_dir_recursive_absolute("user://tt/sub")
		FileAccess.open("user://tt/a.txt", FileAccess.WRITE).store_string("contenu")
		T.run_line(s, "cd user://tt")
		if s["cwd"] != "user://tt": f.append("cd " + str(s["cwd"]))
		T.run_line(s, "cd sub"); T.run_line(s, "cd ..")
		if s["cwd"] != "user://tt": f.append("cd relatif " + str(s["cwd"]))
		T.run_line(s, "cd inexistant")
		if not T.out_text(s).contains("introuvable"): f.append("cd erreur")
		# builtins forcés (mode Android)
		T.builtins_only = true
		T.run_line(s, "ls"); T.run_line(s, "cat a.txt"); T.run_line(s, "mkdir d1"); T.run_line(s, "cp a.txt d1"); T.run_line(s, "mv d1/a.txt d1/b.txt"); T.run_line(s, "echo \"x  y\"")
		if not FileAccess.file_exists("user://tt/d1/b.txt") or FileAccess.file_exists("user://tt/d1/a.txt"): f.append("cp/mv")
		var o: String = T.out_text(s)
		if not o.contains("contenu") or not o.contains("a.txt") or not o.contains("x  y"): f.append("ls/cat/echo")
		T.run_line(s, "rm d1"); T.run_line(s, "rm -r d1")
		if DirAccess.dir_exists_absolute("user://tt/d1"): f.append("rm -r")
		T.run_line(s, "clear")
		if T.out_text(s).contains("contenu"): f.append("clear")
		T.run_line(s, "help")
		if not T.out_text(s).contains("TTY"): f.append("help")
		T.builtins_only = false
		# annulation
		T.run_line(s, "sleep 30")
		await create_timer(0.3).timeout
		if s["run"] == null: f.append("sleep terminé trop tôt")
		else:
			T.cancel(s); t0 = Time.get_ticks_msec()
			while s["run"] != null and Time.get_ticks_msec() - t0 < 5000: await process_frame
			if s["run"] != null: f.append("annulation")
		# onglets
		T.new_session(); T._select(1)
		if T.tabs.size() != 2: f.append("onglets terminal")
		DirAccess.remove_absolute("user://tt/a.txt"); DirAccess.remove_absolute("user://tt/d1/b.txt")
	# ---- éditeur
	var P := "user://dev_test.gd"
	FileAccess.open(P, FileAccess.WRITE).store_string("func a():\n\tpass\n")
	m._open_app("code"); await create_timer(0.4).timeout
	for n in m.wins["code"]["win"].find_children("*", "Control", true, false): if n.has_method("open_path"): E = n
	if E == null: f.append("éditeur introuvable")
	else:
		if not E.open_path(P): f.append("ouverture")
		var d: Dictionary = E.docs[E.cur]
		var ce: CodeEdit = d["ce"]
		if ce.text != "func a():\n\tpass\n": f.append("contenu")
		if not (ce.syntax_highlighter is CodeHighlighter) or (ce.syntax_highlighter as CodeHighlighter).keyword_colors.is_empty(): f.append("coloration")
		if not ce.gutters_draw_line_numbers: f.append("numéros")
		ce.text = ce.text + "var z = 1\n"; ce.text_changed.emit()
		if not E.is_dirty(d): f.append("dirty")
		if not E.save_doc(d) or not FileAccess.get_file_as_string(P).contains("var z = 1"): f.append("enregistrement")
		if E.is_dirty(d): f.append("dirty après save")
		ce.set_caret_line(0); ce.set_caret_column(0)
		if not E.find_next("var z"): f.append("recherche")
		if E.replace_all("z", "w") != 1 or not ce.text.contains("var w"): f.append("remplacement")
		E.set_font_size(20)
		if ce.get_theme_font_size("font_size") != 20: f.append("taille police")
		var d2: Dictionary = E.new_doc("user://x.py", "def f(): pass")
		if E.make_hl("py").keyword_colors.is_empty() or not (d2["ce"] as CodeEdit).syntax_highlighter is CodeHighlighter: f.append("py")
		for ext in ["js", "html", "css", "json", "md", "sh", "php", "gd"]:
			if not E.KW.has(E.lang_for("a." + ext)): f.append("lang " + ext)
		E.autosave()
		if not FileAccess.file_exists(E.SESSION): f.append("autosave")
		# depuis Fichiers
		m._open_app("files"); await create_timer(0.4).timeout
		var fm = null
		for n in m.wins["files"]["win"].find_children("*", "Control", true, false): if n.has_method("open_in_editor"): fm = n
		if fm == null: f.append("files")
		else:
			var nb: int = E.docs.size(); fm.open_in_editor("user://dev_test2.md")
			FileAccess.open("user://dev_test2.md", FileAccess.WRITE).store_string("# t")
			fm.open_in_editor("user://dev_test2.md")
			if E.docs.size() != nb + 1: f.append("ouvrir dans l'éditeur")
		DirAccess.remove_absolute("user://dev_test2.md")
	DirAccess.remove_absolute(P); DirAccess.remove_absolute("user://code_session.json")
	print("DEV-TEST OK" if f.is_empty() else "DEV-TEST ECHEC: " + str(f))
	quit()
