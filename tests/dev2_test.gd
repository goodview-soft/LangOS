extends SceneTree
## Test presse-papiers, périphériques, raccourcis. flatpak run org.godotengine.Godot --headless --path . --script res://tests/dev2_test.gd

func _init() -> void:
	var f: Array = []
	var vp := SubViewport.new(); vp.size = Vector2i(1280, 720); vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	var m = load("res://main.tscn").instantiate(); vp.add_child(m)
	await create_timer(0.8).timeout
	# --- presse-papiers
	var C = load("res://apps/clipboard.gd").new(); C.path = "user://clip_test.json"; C.persist = true; C.skip_pw = true; root.add_child(C)
	C.items = []
	if not C.add("bonjour") or not C.add("deuxième texte"): f.append("ajout")
	if C.add("   ") : f.append("vide accepté")
	C.add("bonjour")
	if C.items.size() != 2 or C.items[0]["t"] != "bonjour": f.append("doublon / ordre")
	if C.add("Xk9#mP2$vLq8"): f.append("mot de passe enregistré")
	C.skip_pw = false
	if not C.add("Xk9#mP2$vLq8"): f.append("option mot de passe désactivée")
	C.skip_pw = true
	if C.looks_like_password("une phrase normale ici") or C.looks_like_password("https://exemple.org/a?b=1") or not C.looks_like_password("aB3$eFgh9!"): f.append("heuristique")
	C.toggle_pin(C.items.size() - 1)
	for i in 70: C.add("texte numéro %d" % i)
	if C.items.size() != 50: f.append("limite 50 : %d" % C.items.size())
	var pinned: Array = C.items.filter(func(e): return e["pin"])
	if pinned.size() != 1: f.append("épingle perdue")
	if C.search("NUMÉRO 6").is_empty() or C.search("zzz").size() != 0: f.append("recherche")
	if C.items[C.search("")[0]]["pin"] != true: f.append("épinglé pas en tête")
	var ld = load("res://apps/clipboard.gd").new(); ld.path = "user://clip_test.json"; ld.load_items()
	if ld.items.size() != 50: f.append("persistance")
	C.set_persist(false)
	if FileAccess.file_exists("user://clip_test.json"): f.append("persistance désactivée")
	C.clear()
	if C.items.size() != 1: f.append("vider garde les épingles")
	C.clear(true)
	if not C.items.is_empty(): f.append("vider tout")
	C.secret = "monSecret1!"
	if C.add("monSecret1!"): f.append("secret du coffre")
	C.secret = ""
	m._open_app("clipboard"); await create_timer(0.3).timeout
	if not m.wins.has("clipboard"): f.append("app presse-papiers")
	m.clip.toggle(); await create_timer(0.3).timeout
	if not m.clip.is_open(): f.append("panneau flottant")
	m.clip.close()
	# --- raccourcis
	var K = m.keysc
	m.set_cfg["keys"] = {}
	var ev := InputEventKey.new(); ev.pressed = true; ev.keycode = KEY_V; ev.ctrl_pressed = true; ev.shift_pressed = true
	if K.event_str(ev) != "Ctrl+Shift+V": f.append("event_str " + K.event_str(ev))
	if not K.handle(ev): f.append("Ctrl+Maj+V non déclenché")
	await create_timer(0.3).timeout
	if not m.clip.is_open(): f.append("Ctrl+Maj+V n'ouvre pas le panneau")
	m.clip.close()
	if K.assign("vd:1", "Ctrl+Shift+V") != "clip": f.append("conflit non détecté")
	if K.assign("vd:1", "Ctrl+Space") != "search": f.append("conflit avec verrouillé")
	if K.assign("vd:1", "Ctrl+Alt+K") != "" or K.binding("vd:1") != "Ctrl+Alt+K": f.append("assignation")
	var e2 := InputEventKey.new(); e2.pressed = true; e2.keycode = KEY_K; e2.ctrl_pressed = true; e2.alt_pressed = true
	m._goto_vd(0)
	if not K.handle(e2) or m.cur_vd != 1: f.append("déclenchement bureau 2")
	m._goto_vd(0)
	if K.assign("vd:0", "Ctrl+Alt+K", true) != "" or K.binding("vd:1") != "": f.append("force")
	if K.valid("A") or K.valid("Shift+A") or not K.valid("Ctrl+A") or not K.valid("F5"): f.append("valid")
	var e3 := InputEventKey.new(); e3.pressed = true; e3.keycode = KEY_SPACE; e3.ctrl_pressed = true
	if K.handle(e3): f.append("Ctrl+Espace ne doit pas passer par la table")
	m.set_cfg["padmap"] = {"2": "vd:1"}
	var jb := InputEventJoypadButton.new(); jb.button_index = JOY_BUTTON_X; jb.pressed = true
	if not K.handle(jb) or m.cur_vd != 1: f.append("manette")
	m._goto_vd(0); m.set_cfg["padmap"] = {}
	var got := ["?"]
	K.capture = func(s): got[0] = s
	var e4 := InputEventKey.new(); e4.pressed = true; e4.keycode = KEY_Q; e4.ctrl_pressed = true
	K.handle(e4)
	if got[0] != "Ctrl+Q": f.append("capture")
	K.assign("vd:0", "Ctrl+Alt+1"); K.reset("vd:1"); K.reset("vd:0")
	m._save_settings()
	# --- périphériques
	var D = load("res://apps/devices.gd")
	var mt: Array = D.parse_mounts("/dev/sda2 / ext4 rw 0 0\n/dev/loop3 /snap/x squashfs ro 0 0\ntmpfs /tmp tmpfs rw 0 0\n/dev/sdb1 /run/media/u/CLE\\040USB vfat rw 0 0\n/dev/sda1 /boot/efi vfat rw 0 0\n")
	if mt.size() != 2 or mt[1]["mp"] != "/run/media/u/CLE USB" or not mt[1]["removable"] or mt[0]["removable"]: f.append("parse /proc/mounts %s" % str(mt))
	var inp: Dictionary = D.parse_input("I: Bus=0011\nN: Name=\"AT Translated Set 2 keyboard\"\nH: Handlers=sysrq kbd event3 leds\n\nI: Bus=0003\nN: Name=\"Logitech Mouse\"\nH: Handlers=mouse0 event5\n\nN: Name=\"Power Button\"\nH: Handlers=kbd event0\n")
	if inp["kbd"].size() != 1 or inp["mouse"].size() != 1: f.append("parse input")
	if OS.get_name() == "Linux":
		var a: Array = D.cpu_sample(); await create_timer(0.3).timeout; var b: Array = D.cpu_sample()
		if a.size() != 2 or D.cpu_pct(a, b) < 0.0 or D.cpu_pct(a, b) > 100.0: f.append("CPU")
		var mi: Dictionary = D.mem_info()
		if not mi.has("total") or mi["total"] <= 0: f.append("RAM")
		D.temp()
	m._open_app("devices"); await create_timer(0.3).timeout
	if not m.wins.has("devices"): f.append("app Périphériques")
	else:
		var dv = null
		for n in m.wins["devices"]["win"].find_children("*", "Control", true, false): if n.has_method("show_tab"): dv = n; break
		if dv == null: f.append("devices introuvable")
		else:
			for t in ["screens", "pads", "audio", "disks", "perf", "keys"]:
				dv.show_tab(t); await create_timer(0.2).timeout
				if dv.live.is_valid(): dv.live.call()
	if f.is_empty(): print("DEV2-TEST OK")
	else: print("DEV2-TEST ECHEC: ", f)
	quit()
