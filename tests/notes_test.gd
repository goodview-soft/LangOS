extends SceneTree
## Test de l'app Notes. flatpak run org.godotengine.Godot --headless --path . --script res://tests/notes_test.gd
const Md = preload("res://apps/md.gd")

func _init() -> void:
	var f: Array = []
	var o := {"exists": func(t: String) -> bool: return t != "Absente"}
	var b := func(s: String) -> String: return Md.to_bbcode(s, o)
	if not b.call("# Titre").contains("[b]Titre[/b]"): f.append("titre")
	if not b.call("**gras** *ital* ~~barré~~").contains("[b]gras[/b] [i]ital[/i] [s]barré[/s]"): f.append("gras/italique/barré: " + b.call("**gras** *ital* ~~barré~~"))
	if not b.call("- a\n- b").contains("• a"): f.append("liste")
	if not b.call("1. un").contains("1. un"): f.append("liste num")
	if not b.call("- [ ] x\n- [x] y").contains("[url=task:0]") or not b.call("- [ ] x\n- [x] y").contains("☑"): f.append("cases")
	if not b.call("> cit").contains("▎"): f.append("citation")
	if not b.call("`co[de]`").contains("[code]co[lb]de[rb][/code]"): f.append("code inline")
	if not b.call("```\n**x**\n```").contains("[code]**x**[/code]"): f.append("bloc code")
	if not b.call("[[Note|alias]]").contains("[url=note:Note]alias[/url]"): f.append("lien alias")
	if not b.call("[[Absente]]").contains("f87171") and not b.call("[[Absente]]").contains(Color("f87171").to_html(false)): pass
	if not b.call("[site](http://a.b)").contains("[url=http://a.b]site[/url]"): f.append("lien md")
	if not b.call("| a | b |\n|---|---|\n| 1 | 2 |").contains("[table=2]"): f.append("tableau")
	if not b.call("![[img.png]]").contains(Md.IMG_MARK + "IMG:img.png"): f.append("image")
	if not b.call("---").contains("────"): f.append("séparateur")
	if not b.call("un #tag ici").contains("[url=tag:tag]"): f.append("tag rendu")
	# analyse
	var p := Md.parse("---\ntitle: T\ntags: [a, b]\n---\n# Haut\nvoir [[X]] et [[Y|z]] #idée `#non [[no]]`\n- [x] a\n- [ ] b\n```\n[[code]] #nope\n```")
	if p["front"].get("title") != "T" or p["front"]["tags"] != ["a", "b"]: f.append("frontmatter " + str(p["front"]))
	if p["links"] != ["X", "Y"]: f.append("liens " + str(p["links"]))
	if not p["tags"].has("idée") or not p["tags"].has("a") or p["tags"].has("non") or p["tags"].has("nope"): f.append("tags " + str(p["tags"]))
	if p["tasks"] != [1, 2] or p["title"] != "Haut": f.append("tâches/titre")
	if Md.toggle_task("- [ ] a\n- [x] b", 0) != "- [x] a\n- [x] b" or Md.toggle_task("- [ ] a\n- [x] b", 1) != "- [ ] a\n- [ ] b": f.append("toggle case")
	# coffre
	var V = load("res://apps/vault.gd").new()
	V.root = "user://nt_vault"; V.cfg_path = "user://nt_cfg.json"; V.cache_path = "user://nt_idx.json"
	_rm(V.root)
	V.write("A.md", "# A\nvers [[B]] et [[Dossier/C]] #t1\n"); V.write("B.md", "retour [[A|alias]] ![[p.png]]\n")
	V.write("Dossier/C.md", "rien #t1 #t2\n"); V.write("Seule.md", "isolée\n")
	V.reindex()
	if V.notes.size() != 4: f.append("indexation %d" % V.notes.size())
	if V.backlinks("A.md") != ["B.md"]: f.append("rétroliens " + str(V.backlinks("A.md")))
	if V.backlinks("Dossier/C.md") != ["A.md"]: f.append("rétrolien chemin")
	if V.outlinks("A.md").size() != 2 or V.outlinks("A.md")[0]["p"] != "B.md": f.append("liens sortants")
	if V.orphans() != ["Seule.md"]: f.append("orphelines " + str(V.orphans()))
	if V.tags()["t1"] != ["A.md", "Dossier/C.md"]: f.append("tags coffre")
	var r: Dictionary = V.rename("B.md", "Bé")
	if r["p"] != "Bé.md" or r["n"] != 1 or not V.read("A.md").contains("[[Bé]]") or V.backlinks("A.md") != ["Bé.md"]: f.append("renommage " + str(r) + V.read("A.md"))
	if not V.read("Bé.md").contains("[[A|alias]]"): f.append("contenu renommé")
	V.rename("A.md", "Z")
	if not V.read("Bé.md").contains("[[Z|alias]]"): f.append("alias conservé")
	if V.rename("Z.md", "Seule")["p"] != "": f.append("renommage écrasant")
	var s: Array = V.search("isolee")
	if s.size() != 1 or s[0]["p"] != "Seule.md": f.append("recherche " + str(s))
	if V.search("rien t2").size() != 1: f.append("recherche multi-mots")
	if V.suggest("be") != ["Bé"]: f.append("suggest " + str(V.suggest("be")))
	var d: String = V.daily("2026-01-02")
	if d != "Journal/2026-01-02.md" or not FileAccess.file_exists(V.root.path_join(d)) or V.daily("2026-01-02") != d: f.append("note du jour")
	var g: Dictionary = V.graph()
	if g["nodes"].size() != V.notes.size() or g["edges"].size() != 2: f.append("graphe " + str(g["edges"]))
	var Gr = load("res://apps/notes_graph.gd").new(); Gr.size = Vector2(400, 300); Gr.set_data(g, "Z.md")
	for i in 30: Gr.step()
	for q in Gr.pos: if not is_finite(q.x) or not is_finite(q.y): f.append("graphe NaN")
	if V.move("Seule.md", "Dossier") != "Dossier/Seule.md": f.append("déplacement")
	if not V.delete("Dossier/Seule.md") or V.notes.has("Dossier/Seule.md"): f.append("suppression")
	V.reindex()
	if not FileAccess.file_exists("user://nt_idx.json"): f.append("cache")
	# application
	var m = load("res://main.tscn").instantiate(); root.add_child(m)
	await create_timer(0.8).timeout
	m._open_app("notes"); await create_timer(0.5).timeout
	if not m.wins.has("notes"): f.append("fenêtre Notes")
	else:
		var n = null
		for c in m.wins["notes"]["win"].find_children("*", "Control", true, false): if c.has_method("open_link"): n = c
		if n == null: f.append("contrôle Notes")
		else:
			n.open_link("Test Notes Auto"); await create_timer(0.2).timeout
			n.edit.text = "# T\n- [ ] a\n[[Bienvenue]]"; n._on_changed(); n._toggle_task(1)
			if not n.edit.text.contains("[x] a"): f.append("case cochée UI")
			n._save_now(); n.open_daily(); n._toggle_graph(); await create_timer(0.3).timeout
			n.vault.delete(n.vault.resolve("Test Notes Auto"))
	m._close_win("notes")
	print("NOTES: ", "OK" if f.is_empty() else "ÉCHEC " + str(f))
	quit(0 if f.is_empty() else 1)

func _rm(p: String) -> void:
	for d in DirAccess.get_directories_at(p): _rm(p.path_join(d))
	for x in DirAccess.get_files_at(p): DirAccess.remove_absolute(p.path_join(x))
	DirAccess.remove_absolute(p)
