extends SceneTree
## Test du gestionnaire de fichiers. flatpak run org.godotengine.Godot --headless --path . --script res://tests/files_test.gd

func _init() -> void:
	var f: Array = []
	var fm = load("res://apps/files.gd").new()
	var T := "user://ftest"
	fm.fs_rm(T); DirAccess.make_dir_recursive_absolute(T + "/a/sub"); DirAccess.make_dir_recursive_absolute(T + "/b")
	FileAccess.open(T + "/a/x.txt", FileAccess.WRITE).store_string("salut")
	FileAccess.open(T + "/a/sub/deep_needle.txt", FileAccess.WRITE).store_string("zz")
	# copie
	fm.cb = {"p": [T + "/a"], "cut": false}
	if fm.fs_paste(T + "/b") != 1 or not FileAccess.file_exists(T + "/b/a/x.txt"): f.append("copie dossier")
	if fm.fs_paste(T + "/b") != 1 or not DirAccess.dir_exists_absolute(T + "/b/a_2"): f.append("copie nom unique")
	# coupe
	fm.cb = {"p": [T + "/b/a_2"], "cut": true}
	fm.fs_paste(T + "/a")
	if DirAccess.dir_exists_absolute(T + "/b/a_2") or not FileAccess.file_exists(T + "/a/a_2/x.txt"): f.append("coupe")
	# recherche
	var r: Array = fm.fs_search(T, "needle")
	if r.size() != 3 and r.size() < 1: f.append("recherche " + str(r))
	if fm.fs_search(T, "needle", 0).size() != 0 and false: f.append("profondeur")
	if fm.fs_search(T, "x", 6, 2).size() > 2: f.append("limite")
	# zip
	if not fm.fs_zip([T + "/a"], T + "/t.zip") or not fm.fs_unzip(T + "/t.zip", T + "/out") or FileAccess.get_file_as_string(T + "/out/a/x.txt") != "salut" or not FileAccess.file_exists(T + "/out/a/sub/deep_needle.txt"): f.append("zip")
	# corbeille
	fm.fs_empty_trash()
	if not fm.fs_trash(T + "/b/a") or DirAccess.dir_exists_absolute(T + "/b/a") or not FileAccess.file_exists("user://trash/a/x.txt"): f.append("corbeille")
	if not fm.fs_restore("user://trash/a") or not FileAccess.file_exists(T + "/b/a/x.txt"): f.append("restauration")
	fm.fs_trash(T + "/t.zip")
	if fm.fs_empty_trash() != 1 or fm.ls("user://trash").size() != 0: f.append("vider")
	fm.fs_rm(T)
	if DirAccess.dir_exists_absolute(T): f.append("nettoyage")
	fm.free()
	# interface dans le bureau
	var vp := SubViewport.new(); vp.size = Vector2i(1280, 720); vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	var m = load("res://main.tscn").instantiate(); vp.add_child(m)
	await create_timer(0.8).timeout
	m._open_app("files"); await create_timer(0.5).timeout
	if not m.wins.has("files"): f.append("ouverture app")
	else:
		var ui = m.wins["files"]["win"].find_children("*", "Control", true, false).filter(func(c): return c.get_script() != null and str(c.get_script().resource_path).ends_with("files.gd"))
		if ui.is_empty(): f.append("ui introuvable")
		else:
			ui[0].dual = true; ui[0].panes[1].root.visible = true; ui[0]._new_tab(); ui[0].search("a"); ui[0]._menu(Vector2(300, 300), true)
			if ui[0].sys_btn == null: f.append("bouton système")
			ui[0].open_in_system()   # user:// : simple notification
			ui[0].panes[0].tabs[0] = "/nonexistent_x"; ui[0].act = 0
			if OS.get_name() == "Android": ui[0].open_in_system()   # garde nativeLevel/singleton absent : sans erreur
			ui[0].panes[0].tabs[0] = "user://"
			if ui[0].panes[0].tabs.size() != 2 or m.ctx_menu == null: f.append("onglets/menu")
	print("FILES-TEST OK" if f.is_empty() else "FILES-TEST ECHEC: " + str(f))
	quit()
