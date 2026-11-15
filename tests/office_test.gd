extends SceneTree
## Test bureautique : tableur, images, agenda, PDF. flatpak run org.godotengine.Godot --headless --path . --script res://tests/office_test.gd

func _init() -> void:
	var f: Array = []
	# --- tableur
	var S = load("res://apps/sheet.gd").new()
	S.set_cell("A1", "2"); S.set_cell("A2", "3"); S.set_cell("A3", "5")
	S.set_cell("B1", "=A1+A2*2"); S.set_cell("B2", "=SUM(A1:A3)"); S.set_cell("B3", "=AVG(A1:A3)")
	S.set_cell("B4", "=IF(A1>1,\"grand\",\"petit\")"); S.set_cell("B5", "=MAX(A1:A3)-MIN(A1:A3)+COUNT(A1:A3)")
	S.set_cell("B6", "=2^3^2"); S.set_cell("B7", "=-A1+(A2-1)"); S.set_cell("B8", "=A1<>A2"); S.set_cell("B9", "=1/0")
	if S.value("B1") != 8.0: f.append("A1+A2*2 = %s" % str(S.value("B1")))
	if S.value("B2") != 10.0: f.append("SUM plage")
	if absf(S.value("B3") - 10.0 / 3.0) > 1e-6: f.append("AVG")
	if S.value("B4") != "grand": f.append("IF")
	if S.value("B5") != 6.0: f.append("MIN/MAX/COUNT %s" % str(S.value("B5")))
	if S.value("B6") != 512.0: f.append("puissance droite-assoc")
	if S.value("B7") != 0.0: f.append("unaire")
	if S.value("B8") != true: f.append("comparaison")
	if S.value("B9") != "#DIV/0": f.append("division par zéro")
	S.set_cell("C1", "=C2+1"); S.set_cell("C2", "=C1+1"); S.set_cell("D1", "=D1")
	if S.value("C1") != "#CYCLE" or S.value("D1") != "#CYCLE": f.append("cycle non détecté : %s" % str(S.value("C1")))
	S.set_cell("E1", "=A1+1"); if S.value("E1") != 3.0: f.append("moteur cassé après cycle")
	for bad in ["=OS.execute(\"ls\")", "=load(\"res://x\")", "=A1;;", "=1+", "=)(", "=\"abc", "=$A$1", "=A1.free()", "=Z999", "=A1:B", "=SUM(", "=1 2", "=SUM(A1:A3"]:
		S.set_cell("F1", bad)
		var v: Variant = S.value("F1")
		if not (v is String and v.begins_with("#")): f.append("injection acceptée : " + bad)
	S.set_cell("G1", "x,\"y\""); S.set_cell("G2", "ligne"); S.set_cell("H2", "=A1*2")
	var csv: String = S.to_csv()
	var S2 = load("res://apps/sheet.gd").new(); S2.from_csv(csv)
	if S2.cells != S.cells: f.append("CSV aller-retour")
	if not S.save_json("user://office_test_sheet.json"): f.append("sauvegarde")
	var S3 = load("res://apps/sheet.gd").new()
	if not S3.load_json("user://office_test_sheet.json") or S3.cells != S.cells: f.append("JSON aller-retour")
	if S.range_nums("A1:A3") != [2.0, 3.0, 5.0]: f.append("range_nums")
	if load("res://apps/sheet.gd").COLS < 26 or load("res://apps/sheet.gd").ROWS < 200: f.append("taille grille")
	# --- images
	var im := Image.create(40, 20, false, Image.FORMAT_RGBA8); im.fill(Color.RED)
	var tmp := OS.get_temp_dir().path_join("office_test_dir"); DirAccess.make_dir_recursive_absolute(tmp)
	for old in DirAccess.get_files_at(tmp): DirAccess.remove_absolute(tmp.path_join(old))
	im.save_png(tmp.path_join("a.png")); im.save_png(tmp.path_join("b.png"))
	var V = load("res://apps/image_viewer.gd").new()
	if not V.load_image(tmp.path_join("a.png")): f.append("ouverture image")
	if V.siblings.size() != 2: f.append("navigation dossier")
	V.rotate(true)
	if V.img.get_size() != Vector2i(20, 40): f.append("rotation")
	if not V.crop(Rect2i(0, 0, 10, 10)) or V.img.get_size() != Vector2i(10, 10): f.append("recadrage")
	if V.crop(Rect2i(500, 500, 5, 5)): f.append("recadrage hors image accepté")
	for e in ["png", "jpg", "webp"]:
		var o: String = tmp.path_join("out." + e)
		if not V.save_as(o) or Image.load_from_file(o) == null: f.append("conversion " + e)
	if V.save_as(tmp.path_join("x.xyz")): f.append("format inconnu accepté")
	if V.load_image(tmp.path_join("nexiste.png")): f.append("image absente acceptée")
	# --- agenda
	var C = load("res://apps/calendar.gd").new(); C.path = "user://cal_test.json"
	var e1: Dictionary = C.add("Quotidien", "2026-03-01", "08:00", "daily", 10)
	var e2: Dictionary = C.add("Hebdo", "2026-03-02", "10:30", "weekly")
	var e3: Dictionary = C.add("Mensuel", "2026-01-31", "12:00", "monthly")
	var e4: Dictionary = C.add("Unique", "2026-03-05", "09:00")
	if not C.occurs(e1, "2026-04-10") or C.occurs(e1, "2026-02-28"): f.append("quotidien")
	if not C.occurs(e2, "2026-03-16") or C.occurs(e2, "2026-03-17"): f.append("hebdo")
	if not C.occurs(e3, "2026-03-31") or C.occurs(e3, "2026-03-30"): f.append("mensuel")
	if not C.occurs(e4, "2026-03-05") or C.occurs(e4, "2026-03-06"): f.append("unique")
	var now := int(Time.get_unix_time_from_datetime_string("2026-03-10T07:55:00"))
	var d1: Array = C.due(now)
	if d1.size() != 1 or d1[0]["e"]["t"] != "Quotidien": f.append("rappel dû : %d" % d1.size())
	if not C.due(now).is_empty(): f.append("rappel répété")
	if not C.due(now - 3600).is_empty(): f.append("rappel trop tôt")
	var ics: String = C.to_ics()
	var C2 = load("res://apps/calendar.gd").new(); C2.path = "user://cal_test2.json"
	if C2.from_ics(ics) != 4: f.append("ics import")
	var q: Dictionary = C2.events.filter(func(e): return e["t"] == "Quotidien")[0]
	if q["rep"] != "daily" or q["rem"] != 10 or q["tm"] != "08:00" or q["d"] != "2026-03-01": f.append("ics aller-retour : " + str(q))
	var C3 = load("res://apps/calendar.gd").new(); C3.path = "user://cal_test.json"; C3.load_data()
	if C3.events.size() != 4: f.append("persistance agenda")
	# --- PDF absent géré
	var P = load("res://apps/pdf_viewer.gd").new()
	P._avail = 0
	if P.load_pdf("/tmp/inexistant.pdf"): f.append("PDF sans moteur accepté")
	if not P.search("x").is_empty(): f.append("recherche sans moteur")
	P._avail = -1
	if P.engine_ok():
		if P.load_pdf("/tmp/inexistant.pdf"): f.append("PDF absent accepté")
	# --- applis dans le bureau
	var vp := SubViewport.new(); vp.size = Vector2i(1280, 720); vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	var m = load("res://main.tscn").instantiate(); vp.add_child(m)
	await create_timer(0.8).timeout
	for id in ["sheet", "imgview", "pdf", "calendar"]:
		m._open_app(id); await create_timer(0.3).timeout
		if not m.wins.has(id): f.append("app " + id)
	m.open_with("imgview", tmp.path_join("b.png")); await create_timer(0.2).timeout
	m.open_with("pdf", "/tmp/inexistant.pdf"); await create_timer(0.2).timeout
	print("OFFICE: ", "OK" if f.is_empty() else "ÉCHEC " + str(f))
	quit(0 if f.is_empty() else 1)
