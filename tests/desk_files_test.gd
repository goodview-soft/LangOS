extends SceneTree
## Test des fichiers/dossiers du bureau : création, renommage, déplacement, collisions, noms invalides.
## flatpak run org.godotengine.Godot --headless --path . --script res://tests/desk_files_test.gd
const DF = preload("res://apps/desk_files.gd")

func _init() -> void:
	var f: Array = []
	var d := "user://desk_files_test"
	DF._rm(d); DirAccess.make_dir_recursive_absolute(d)
	# création + collisions
	var a = DF.create(d, "Nouveau fichier.txt", false)
	var a2 = DF.create(d, "Nouveau fichier.txt", false)
	var fo = DF.create(d, "Nouveau dossier", true)
	var fo2 = DF.create(d, "Nouveau dossier", true)
	if a == "" or not FileAccess.file_exists(a): f.append("création fichier")
	if a2 == a or not FileAccess.file_exists(a2) or not a2.ends_with(".txt"): f.append("collision fichier : " + a2)
	if fo == "" or not DirAccess.dir_exists_absolute(fo) or fo2 == fo or not DirAccess.dir_exists_absolute(fo2): f.append("création dossier")
	# noms invalides
	for bad in ["", "  ", ".", "..", "a/b", "a\\b", "x:y", "a*b", "a?b", "a|b", "a<b", "q\"q", "n".repeat(130)]:
		if DF.check_name(bad) == "": f.append("nom accepté à tort : '%s'" % bad.left(10))
		if DF.create(d, bad, false) != "": f.append("création avec nom invalide")
	if DF.check_name("Mon fichier (1).txt") != "": f.append("nom valide refusé")
	# renommage
	var r = DF.rename(a, "notes.txt")
	if r != d + "/notes.txt" or not FileAccess.file_exists(r) or FileAccess.file_exists(a): f.append("renommage : " + r)
	if DF.rename(r, a2.get_file()) != "": f.append("renommage vers un nom existant accepté")
	if DF.rename(r, "a/b") != "" or DF.rename(r, "") != "": f.append("renommage invalide accepté")
	if DF.rename(r, "notes.txt") != r: f.append("renommage identique")
	if DF.rename(fo, "Docs") != d + "/Docs" or not DirAccess.dir_exists_absolute(d + "/Docs"): f.append("renommage dossier")
	# déplacement
	var docs := d + "/Docs"
	var m = DF.move_into(r, docs)
	if m != docs + "/notes.txt" or FileAccess.file_exists(r) or not FileAccess.file_exists(m): f.append("déplacement : " + m)
	DF.create(d, "notes.txt", false)
	var m2 = DF.move_into(d + "/notes.txt", docs)
	if m2 == m or m2 == "" or not FileAccess.file_exists(m2) or not m2.ends_with(".txt"): f.append("déplacement avec collision : " + m2)
	if DF.move_into(docs, docs) != "" or DF.move_into(d + "/Docs", docs + "/x") != "": f.append("déplacement dans soi-même accepté")
	DirAccess.make_dir_recursive_absolute(docs + "/sub")
	if DF.move_into(docs, docs + "/sub") != "": f.append("dossier déplacé dans son sous-dossier")
	if DF.move_into(m, docs) != "": f.append("déplacement dans le même dossier")
	# dossier non vide déplacé
	var big = DF.move_into(docs, fo2)
	if big != fo2 + "/Docs" or not FileAccess.file_exists(big + "/notes.txt"): f.append("déplacement dossier non vide : " + big)
	# liste : dossiers d'abord, sans cachés
	var h := FileAccess.open(d + "/.cache", FileAccess.WRITE); h.close()
	var zz = DF.create(d, "zz.txt", false); var aa = DF.create(d, "aa.txt", false)
	var names = DF.list(d).map(func(e): return e["name"])
	if names.has(".cache") or names.find("Nouveau dossier") > names.find("aa.txt") or names.find("aa.txt") > names.find("zz.txt"): f.append("liste : " + str(names))
	DF._rm(d)
	# intégration main : icônes
	var vp := SubViewport.new(); vp.size = Vector2i(1280, 720); vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	var mn = load("res://main.tscn").instantiate(); mn.desk_dir_override = d; DirAccess.make_dir_recursive_absolute(d); vp.add_child(mn)
	await create_timer(0.8).timeout
	mn._desk_new(true); await create_timer(0.2).timeout
	mn._desk_new(false); await create_timer(0.2).timeout
	var ids: Array = mn.desk_icons.map(func(b): return str(b.get_meta("id")))
	if not ids.has("f:Nouveau dossier") or not ids.has("f:Nouveau fichier.txt"): f.append("icônes absentes : " + str(ids))
	var bf = mn._desk_icon_of("Nouveau fichier.txt"); var bd = mn._desk_icon_of("Nouveau dossier")
	if bf == null or bd == null: f.append("icône introuvable")
	else:
		bf.position = Vector2(300, 300) # sur la grille, puis glisser dans le dossier
		var before: int = mn.desk_icons.size()
		mn.set_cfg["icons"]["f:Nouveau fichier.txt"] = [3, 3]
		mn._layout_icons()
		if not mn._desk_icon_of("Nouveau fichier.txt").position == Vector2(16, 16) + Vector2(3, 3) * mn.GRID: f.append("position sauvegardée non respectée")
		if mn.DeskFiles.move_into(d + "/Nouveau fichier.txt", d + "/Nouveau dossier") == "": f.append("déplacement dans le dossier")
		mn._scan_desk()
		if mn._desk_icon_of("Nouveau fichier.txt") != null or mn.desk_icons.size() != before - 1: f.append("icône non retirée après déplacement")
	mn.DeskFiles._rm(d)
	print("DESK_FILES: ", "OK" if f.is_empty() else "ECHEC " + str(f))
	quit(0 if f.is_empty() else 1)
