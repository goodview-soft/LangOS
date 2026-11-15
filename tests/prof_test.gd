extends SceneTree
## Test profils + recherche. flatpak run org.godotengine.Godot --headless --path . --script res://tests/prof_test.gd

func _init() -> void:
	var f: Array = []
	var vp := SubViewport.new(); vp.size = Vector2i(1280, 720); vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	var m = load("res://main.tscn").instantiate(); vp.add_child(m)
	await create_timer(0.8).timeout
	var P = m.prof; var S = m.srch
	if P.all().size() < 5 or P.find("Gaming") < 0: f.append("profils par défaut")
	for p in P.all(): for e in p["apps"]: if not m.APPS.has(e["id"]): f.append("app inconnue " + e["id"])
	# création depuis l'état actuel
	m._open_app("calc"); m._open_app("notepad"); await create_timer(0.4).timeout
	m._move_to_vd("calc", 1); m._snap("notepad", "r")
	var n0: int = P.all().size()
	var i: int = P.save_current("Test", false, 2)
	if P.all().size() != n0 + 1 or P.all()[i]["apps"].size() != 2: f.append("création")
	P.rename(i, "Test2")
	if P.find("Test2") < 0: f.append("renommage")
	# activation : ferme les autres
	m._open_app("todo"); await create_timer(0.3).timeout
	m._close_win("calc"); await create_timer(0.3).timeout
	P.activate(P.find("Test2")); await create_timer(0.4).timeout
	if not m.wins.has("calc") or not m.wins.has("notepad"): f.append("ouverture des apps")
	if m.wins.has("todo"): f.append("autres fenêtres non fermées")
	elif m.wins.has("calc") and int(m.wins["calc"]["vd"]) != 1: f.append("bureau virtuel")
	if m.wins.has("notepad") and absf(m.wins["notepad"]["win"].position.x - m.desk.size.x / 2.0) > 4.0: f.append("disposition")
	# persistance
	m._save_settings()
	var c := ConfigFile.new(); c.load("user://settings.cfg")
	var pf = c.get_value("ui", "profiles", [])
	if not (pf is Array) or pf.filter(func(p): return p["name"] == "Test2").is_empty(): f.append("persistance")
	# fenêtre de gestion
	m._open_app("profiles"); await create_timer(0.3).timeout
	if not m.wins.has("profiles"): f.append("app Profils")
	P.remove(P.find("Test2"))
	if P.find("Test2") >= 0 or P.all().size() != n0: f.append("suppression")
	m._goto_vd(0)
	# recherche
	var tmp := "user://zzprofneedle.txt"
	FileAccess.open(tmp, FileAccess.WRITE).store_string("x")
	S.index = []; S.reindex()
	var t0 := Time.get_ticks_msec()
	while S.scanning and Time.get_ticks_msec() - t0 < 60000: await process_frame
	await create_timer(0.3).timeout
	var r: Array = S.query("calcul", false)
	if r.is_empty() or r[0][0] != "Application": f.append("recherche app")
	r = S.query("zzprofneedle", true)
	if r.is_empty() or r[0][0] != "Fichier": f.append("recherche fichier (index " + str(S.index.size()) + ")")
	r = S.query("theme clair", false)
	if r.is_empty() or r[0][0] != "Commande": f.append("recherche commande")
	else:
		r[0][3].call()
		if not m.set_cfg["light"]: f.append("commande thème")
		m._set_light(false)
	r = S.query("bureau 2", false)
	if r.is_empty() or r[0][1] != "Aller au bureau 2": f.append("commande bureau")
	if S.query("travail", false).filter(func(x): return x[0] == "Profil").is_empty(): f.append("recherche profil")
	# interface clavier
	S.toggle(); await create_timer(0.3).timeout
	S.field.text = "calcul"; S._changed("calcul"); S._key(_k(KEY_DOWN)); S._key(_k(KEY_UP))
	if not S.is_open() or S.res.is_empty(): f.append("ui recherche")
	else:
		S._key(_k(KEY_ENTER)); await create_timer(0.3).timeout
		if S.is_open() or not m.wins.has("calc"): f.append("entrée ouvre l'app")
	DirAccess.remove_absolute(tmp); DirAccess.remove_absolute(S.CACHE)
	print("PROF-TEST OK" if f.is_empty() else "PROF-TEST ECHEC: " + str(f))
	quit()

func _k(code: int) -> InputEventKey:
	var e := InputEventKey.new(); e.keycode = code; e.pressed = true; return e
