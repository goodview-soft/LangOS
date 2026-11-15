extends RefCounted
## Coffre de notes (dossier de fichiers .md) : index des liens / tags / titres, rétroliens, renommage, note du jour, modèles, recherche, graphe.
## Aucune interface : l'application « Notes » (apps/notes.gd) s'appuie dessus ; testé par tests/notes_test.gd.
const Md = preload("res://apps/md.gd")
signal changed
const TPL_DIR := "Modèles"
const DAILY_DIR := "Journal"
const MAX_NOTES := 5000
const MAX_DEPTH := 10
const MAX_TEXT := 40000

var root := "user://vault"
var cfg_path := "user://notes_cfg.json"
var cache_path := "user://notes_index.json"
var cfg := {"root": "", "favs": {}}
var notes := {}          # rel (« Dossier/Note.md ») -> {m, t, l, g, f, x, w, k, h}
var imgs := {}           # nom d'image en minuscules -> rel
var by_path := {}        # « dossier/note » en minuscules -> rel
var by_name := {}        # « note » en minuscules -> rel
var backs := {}          # rel -> [rel des notes qui y renvoient]
var stamp := 0
var th: Thread = null
var fresh := {}
var fresh_imgs := {}
var done := false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and th != null: th.wait_to_finish()

# ------------------------------------------------------------------ configuration
func default_root() -> String:
	return "user://vault"

func load_cfg() -> void:
	if FileAccess.file_exists(cfg_path):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(cfg_path))
		if j is Dictionary: cfg = j
	if not (cfg.get("favs") is Dictionary): cfg["favs"] = {}
	root = str(cfg.get("root", "")) if str(cfg.get("root", "")) != "" else default_root()

func save_cfg() -> void:
	cfg["root"] = root
	var f := FileAccess.open(cfg_path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(cfg))

## Change de coffre (crée le dossier au besoin).
func set_root(p: String) -> bool:
	p = p.strip_edges()
	if p == "": return false
	if p.begins_with("~"): p = OS.get_environment("HOME") + p.substr(1)
	if DirAccess.make_dir_recursive_absolute(p) != OK and not DirAccess.dir_exists_absolute(p): return false
	root = p.rstrip("/") if p != "/" else p
	notes = {}; imgs = {}; save_cfg(); load_cache(); ensure_root(); reindex(); return true

## Crée le coffre s'il n'existe pas ; premier lancement : note d'accueil et modèles.
func ensure_root() -> void:
	var fresh_dir := not DirAccess.dir_exists_absolute(root)
	DirAccess.make_dir_recursive_absolute(root)
	if fresh_dir or (DirAccess.get_files_at(root).is_empty() and DirAccess.get_directories_at(root).is_empty()):
		var w := "---\ntags: [accueil]\n---\n# Bienvenue\n\nVos notes sont des fichiers Markdown dans ce dossier.\n\n- Liez des notes avec [[Idées]] (tapez `[[` pour l'autocomplétion)\n- Ajoutez des #étiquettes\n- [ ] Cochez une tâche dans l'aperçu\n- Ctrl+D : note du jour\n\n> Le graphe montre les liens entre vos notes.\n"
		write("Bienvenue.md", w); write("Idées.md", "# Idées\n\nRetour à [[Bienvenue]].\n")
		DirAccess.make_dir_recursive_absolute(root.path_join(TPL_DIR))
		write(TPL_DIR + "/Réunion.md", "---\ntitle: {{title}}\ndate: {{date}}\ntags: [réunion]\n---\n# {{title}}\n\n## Participants\n\n## Ordre du jour\n\n## Décisions\n\n- [ ] \n")
		write(TPL_DIR + "/Journal.md", "# {{date}}\n\n## À faire\n- [ ] \n\n## Notes\n\n")
		write(TPL_DIR + "/Projet.md", "---\ntitle: {{title}}\ntags: [projet]\n---\n# {{title}}\n\n## Objectif\n\n## Tâches\n- [ ] \n")

func abs_path(key: String) -> String:
	return key if is_ext(key) else root.path_join(key)

func is_ext(key: String) -> bool:
	return key.begins_with("/") or key.contains("://") or (key.length() > 2 and key[1] == ":")

## Clé de note (relative au coffre) pour un chemin quelconque ; chemin absolu inchangé s'il est hors du coffre.
func key_for(path: String) -> String:
	var a := ProjectSettings.globalize_path(path); var r := ProjectSettings.globalize_path(root).rstrip("/")
	if a.begins_with(r + "/"): return a.substr(r.length() + 1)
	return a

func name_of(key: String) -> String:
	return key.get_file().get_basename()

func safe_name(n: String) -> String:
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "#", "^", "[", "]"]: n = n.replace(ch, "-")
	n = n.strip_edges().lstrip(".")
	return n.left(120)

static func fold(s: String) -> String:
	s = s.to_lower()
	for p in [["é", "e"], ["è", "e"], ["ê", "e"], ["ë", "e"], ["à", "a"], ["â", "a"], ["î", "i"], ["ï", "i"], ["ô", "o"], ["ù", "u"], ["û", "u"], ["ç", "c"]]: s = s.replace(p[0], p[1])
	return s

func read(key: String) -> String:
	var p := abs_path(key)
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""

func write(key: String, text: String) -> bool:
	if not is_ext(key) and (key.contains("..") or key == ""): return false
	var p := abs_path(key)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null: return false
	f.store_string(text); f.close()
	if not is_ext(key) and key.ends_with(".md"): touch(key, text)
	return true

# ------------------------------------------------------------------ index
func _entry(rel: String, text: String, mt: int) -> Dictionary:
	var p := Md.parse(text)
	return {"m": mt, "t": p["title"], "l": p["links"], "g": p["tags"], "f": p["front"], "x": fold(text.left(MAX_TEXT)), "w": p["words"], "k": p["tasks"], "h": p["heads"]}

func touch(rel: String, text: String) -> void:
	notes[rel] = _entry(rel, text, int(FileAccess.get_modified_time(abs_path(rel))))
	_rebuild_maps()

func _walk(dir: String, rel: String, depth: int, out: Array, im: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null or out.size() >= MAX_NOTES: return
	for f in d.get_files():
		var e := f.get_extension().to_lower()
		if e == "md": out.append(rel + f)
		elif e in Md.IMG_EXT: im[f.to_lower()] = rel + f
	if depth < MAX_DEPTH:
		for sub in d.get_directories():
			if not sub.begins_with("."): _walk(dir.path_join(sub), rel + sub + "/", depth + 1, out, im)

## Liste des notes (chemins relatifs).
func list_notes() -> Array:
	var out := []; _walk(root, "", 0, out, {}); return out

func _build(old: Dictionary, im: Dictionary) -> Dictionary:
	var files := []; _walk(root, "", 0, files, im)
	var res := {}
	for rel: String in files:
		var mt := int(FileAccess.get_modified_time(root.path_join(rel)))
		var o: Variant = old.get(rel)
		if o is Dictionary and int(o.get("m", -1)) == mt: res[rel] = o
		else: res[rel] = _entry(rel, FileAccess.get_file_as_string(root.path_join(rel)), mt)
	return res

## Reconstruction synchrone (tests, changement de coffre).
func reindex() -> void:
	var im := {}
	notes = _build(notes, im); imgs = im
	_rebuild_maps(); stamp = int(Time.get_unix_time_from_system()); save_cache(); changed.emit()

## Reconstruction en arrière-plan : poll() récupère le résultat.
func start_scan() -> void:
	if th != null: return
	Md.warm(); done = false
	th = Thread.new(); th.start(_job.bind(notes.duplicate()))

func _job(old: Dictionary) -> void:
	var im := {}
	fresh = _build(old, im); fresh_imgs = im; done = true

func scanning() -> bool:
	return th != null

func poll() -> bool:
	if th == null or not done: return false
	th.wait_to_finish(); th = null
	notes = fresh; imgs = fresh_imgs; fresh = {}; fresh_imgs = {}
	_rebuild_maps(); stamp = int(Time.get_unix_time_from_system()); save_cache(); changed.emit()
	return true

func stale() -> bool:
	return notes.is_empty() or Time.get_unix_time_from_system() - stamp > 300

func load_cache() -> void:
	if not notes.is_empty() or not FileAccess.file_exists(cache_path): return
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache_path))
	if j is Dictionary and str(j.get("root", "")) == root and j.get("n") is Dictionary:
		notes = j["n"]; stamp = int(j.get("t", 0)); _rebuild_maps()

func save_cache() -> void:
	var f := FileAccess.open(cache_path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"root": root, "t": stamp, "n": notes}))

func _rebuild_maps() -> void:
	by_path = {}; by_name = {}; backs = {}
	var keys := notes.keys(); keys.sort()
	for rel: String in keys:
		var p := rel.trim_suffix(".md").to_lower(); by_path[p] = rel
		var n := p.get_file()
		if not by_name.has(n) or rel.count("/") < str(by_name[n]).count("/"): by_name[n] = rel
	for rel: String in keys:
		for t in notes[rel].get("l", []):
			var r := resolve(str(t))
			if r != "":
				if not backs.has(r): backs[r] = []
				if not backs[r].has(rel): backs[r].append(rel)

## Cible d'un lien -> clé de note existante, ou "".
func resolve(target: String) -> String:
	var t := target.strip_edges().trim_suffix(".md").to_lower()
	if t == "": return ""
	if by_path.has(t): return by_path[t]
	return by_name.get(t.get_file(), "") if not t.contains("/") else ""

func find_image(name: String, from_key := "") -> String:
	var n := name.get_slice("|", 0).strip_edges()
	for cand in [from_key.get_base_dir().path_join(n) if from_key != "" and not is_ext(from_key) else "", n]:
		if cand != "" and FileAccess.file_exists(root.path_join(cand)): return root.path_join(cand)
	if is_ext(n) and FileAccess.file_exists(n): return n
	var r: String = imgs.get(n.get_file().to_lower(), "")
	return root.path_join(r) if r != "" else ""

# ------------------------------------------------------------------ requêtes
func backlinks(rel: String) -> Array:
	return backs.get(rel, []).filter(func(r): return r != rel)

func outlinks(rel: String) -> Array:
	var out := []
	for t in notes.get(rel, {}).get("l", []): out.append({"t": str(t), "p": resolve(str(t))})
	return out

func orphans() -> Array:
	var out := []
	for rel in notes:
		if backlinks(rel).is_empty() and not outlinks(rel).any(func(o): return o["p"] != "" and o["p"] != rel): out.append(rel)
	out.sort(); return out

func tags() -> Dictionary:
	var d := {}
	for rel in notes:
		for t in notes[rel].get("g", []):
			if not d.has(t): d[t] = []
			d[t].append(rel)
	for t in d: d[t].sort()
	return d

func title_of(rel: String) -> String:
	return name_of(rel)

## Recherche plein texte (tous les mots, sans accents ni casse). Renvoie [{p, s (score), l (extrait)}], meilleurs d'abord.
func search(q: String, limit := 30, with_snippet := true) -> Array:
	var words := fold(q.strip_edges()).split(" ", false)
	if words.is_empty(): return []
	var res := []
	for rel: String in notes:
		var nm := fold(name_of(rel)); var x: String = str(notes[rel].get("x", ""))
		var ok := true; var score := 0
		for w in words:
			if nm.contains(w): score += 5 + (3 if nm.begins_with(w) else 0)
			elif x.contains(w): score += 1
			else: ok = false; break
		if ok: res.append({"p": rel, "s": score, "l": ""})
	res.sort_custom(func(a, b): return a["s"] > b["s"] or (a["s"] == b["s"] and a["p"] < b["p"]))
	res = res.slice(0, limit)
	if with_snippet:
		for r in res: r["l"] = snippet(r["p"], words[0])
	return res

func snippet(rel: String, word: String) -> String:
	var w := fold(word)
	for ln in read(rel).split("\n"):
		if fold(ln).contains(w): return ln.strip_edges().left(90)
	return ""

## Complétion de [[ : noms de notes commençant par / contenant le préfixe.
func suggest(prefix: String, limit := 8) -> Array:
	var f := fold(prefix.strip_edges()); var a := []; var b := []
	for rel: String in notes:
		var n := name_of(rel); var fn := fold(n)
		if f == "" or fn.begins_with(f): a.append(n)
		elif fn.contains(f): b.append(n)
	a.sort(); b.sort()
	return (a + b).slice(0, limit)

## Contexte d'un lien dans la note `src` vers `target` (ligne contenant [[target...]]).
func link_context(src: String, target: String) -> String:
	var t := target.to_lower()
	for ln in read(src).split("\n"):
		if ln.to_lower().contains("[[" + t) or ln.to_lower().contains("[[" + t.get_file()): return ln.strip_edges().left(100)
	return ""

## Graphe : {nodes: [rel], edges: [[i, j]], deg: [int]} ; au plus max_nodes notes (les plus liées d'abord).
func graph(max_nodes := 300) -> Dictionary:
	var deg := {}
	var pairs := {}
	for rel: String in notes:
		for t in notes[rel].get("l", []):
			var r := resolve(str(t))
			if r == "" or r == rel: continue
			var k := rel + "\n" + r if rel < r else r + "\n" + rel
			if pairs.has(k): continue
			pairs[k] = [rel, r]; deg[rel] = int(deg.get(rel, 0)) + 1; deg[r] = int(deg.get(r, 0)) + 1
	var keys := notes.keys(); keys.sort()
	keys.sort_custom(func(a, b): return int(deg.get(a, 0)) > int(deg.get(b, 0)) or (int(deg.get(a, 0)) == int(deg.get(b, 0)) and a < b))
	keys = keys.slice(0, max_nodes)
	var idx := {}
	for i in keys.size(): idx[keys[i]] = i
	var edges := []; var dg := []
	dg.resize(keys.size()); dg.fill(0)
	for k in pairs:
		var pr: Array = pairs[k]
		if idx.has(pr[0]) and idx.has(pr[1]):
			edges.append([idx[pr[0]], idx[pr[1]]]); dg[idx[pr[0]]] += 1; dg[idx[pr[1]]] += 1
	return {"nodes": keys, "edges": edges, "deg": dg}

# ------------------------------------------------------------------ opérations
func unique(dir: String, name: String, ext := ".md") -> String:
	var base := dir.path_join(name) if dir != "" else name
	var p := base + ext; var k := 2
	while FileAccess.file_exists(root.path_join(p)) or DirAccess.dir_exists_absolute(root.path_join(p)):
		p = "%s %d%s" % [base, k, ext]; k += 1
	return p

func create(dir: String, name: String, text := "") -> String:
	var n := safe_name(name)
	if n == "": n = "Sans titre"
	var rel := unique(dir, n)
	return rel if write(rel, text if text != "" else "# %s\n\n" % n) else ""

func mkdir(parent: String, name: String) -> String:
	var n := safe_name(name)
	if n == "": return ""
	var rel := unique(parent, n, "")
	return rel if DirAccess.make_dir_recursive_absolute(root.path_join(rel)) == OK else ""

## Met à la corbeille du coffre (.trash, ignorée par l'index).
func delete(rel: String) -> bool:
	var src := root.path_join(rel)
	if not (FileAccess.file_exists(src) or DirAccess.dir_exists_absolute(src)): return false
	var td := root.path_join(".trash"); DirAccess.make_dir_recursive_absolute(td)
	var dst := td.path_join("%d_%s" % [int(Time.get_unix_time_from_system()), rel.get_file()])
	if DirAccess.rename_absolute(src, dst) != OK: return false
	for k in notes.keys(): if k == rel or k.begins_with(rel + "/"): notes.erase(k)
	_rebuild_maps(); _fav_replace(rel, ""); return true

func _fav_replace(old: String, new: String) -> void:
	var fv: Array = favs()
	for i in range(fv.size() - 1, -1, -1):
		if fv[i] == old or str(fv[i]).begins_with(old + "/"):
			if new == "": fv.remove_at(i)
			else: fv[i] = new + str(fv[i]).substr(old.length())
	cfg["favs"][root] = fv; save_cfg()

## Renomme une note (nom sans extension) et met à jour les liens des autres notes. {p: nouvelle clé ("" si échec), n: notes modifiées}
func rename(rel: String, new_name: String) -> Dictionary:
	var nn := safe_name(new_name.trim_suffix(".md"))
	var res := {"p": "", "n": 0}
	if nn == "" or not FileAccess.file_exists(root.path_join(rel)): return res
	var dst := rel.get_base_dir().path_join(nn + ".md") if rel.contains("/") else nn + ".md"
	if dst == rel: res["p"] = rel; return res
	if (FileAccess.file_exists(root.path_join(dst)) or DirAccess.dir_exists_absolute(root.path_join(dst))) and dst.to_lower() != rel.to_lower(): return res
	var old_name := name_of(rel); var old_path := rel.trim_suffix(".md")
	var srcs: Array = backs.get(rel, []).duplicate()
	if DirAccess.rename_absolute(root.path_join(rel), root.path_join(dst)) != OK: return res
	notes.erase(rel)
	var new_path := dst.trim_suffix(".md")
	for s: String in srcs:
		var sk := dst if s == rel else s
		var t := read(sk); var u := Md.rename_links(t, old_name, old_path, nn, new_path)
		if u != t and write(sk, u): res["n"] += 1
	if not notes.has(dst): touch(dst, read(dst))
	reindex(); _fav_replace(rel, dst)
	res["p"] = dst; return res

func rename_dir(rel: String, new_name: String) -> String:
	var nn := safe_name(new_name)
	if nn == "" or not DirAccess.dir_exists_absolute(root.path_join(rel)): return ""
	var dst := rel.get_base_dir().path_join(nn) if rel.contains("/") else nn
	if dst == rel: return rel
	if FileAccess.file_exists(root.path_join(dst)) or DirAccess.dir_exists_absolute(root.path_join(dst)): return ""
	if DirAccess.rename_absolute(root.path_join(rel), root.path_join(dst)) != OK: return ""
	reindex(); _fav_replace(rel, dst); return dst

## Déplace une note ou un dossier dans `dest` ("" = racine). Renvoie la nouvelle clé ou "".
func move(rel: String, dest: String) -> String:
	if dest == rel or dest.begins_with(rel + "/") or rel.get_base_dir() == dest: return ""
	var dst := dest.path_join(rel.get_file()) if dest != "" else rel.get_file()
	if FileAccess.file_exists(root.path_join(dst)) or DirAccess.dir_exists_absolute(root.path_join(dst)): return ""
	DirAccess.make_dir_recursive_absolute(root.path_join(dest))
	if DirAccess.rename_absolute(root.path_join(rel), root.path_join(dst)) != OK: return ""
	reindex(); _fav_replace(rel, dst); return dst

func favs() -> Array:
	var f: Variant = cfg["favs"].get(root, [])
	return f if f is Array else []

func is_fav(rel: String) -> bool: return favs().has(rel)

func toggle_fav(rel: String) -> bool:
	var f := favs().duplicate()
	if f.has(rel): f.erase(rel)
	else: f.append(rel)
	cfg["favs"][root] = f; save_cfg(); return f.has(rel)

# ------------------------------------------------------------------ note du jour, modèles
func daily(date := "") -> String:
	if date == "": date = Time.get_date_string_from_system()
	var rel := DAILY_DIR + "/" + date + ".md"
	if not FileAccess.file_exists(root.path_join(rel)):
		var tpl := read(TPL_DIR + "/Journal.md")
		write(rel, fill_template(tpl, date, date) if tpl != "" else "# %s\n\n" % date)
	return rel

func templates() -> Array:
	var out := []
	for f in DirAccess.get_files_at(root.path_join(TPL_DIR)):
		if f.get_extension() == "md": out.append(f.get_basename())
	out.sort(); return out

func fill_template(tpl: String, title: String, date := "") -> String:
	if date == "": date = Time.get_date_string_from_system()
	return tpl.replace("{{title}}", title).replace("{{date}}", date).replace("{{time}}", Time.get_time_string_from_system().left(5))

func create_from_template(dir: String, name: String, tpl_name: String) -> String:
	var n := safe_name(name)
	if n == "": n = "Sans titre"
	return create(dir, n, fill_template(read(TPL_DIR + "/" + tpl_name + ".md"), n))

## Importe le Bloc-notes simple (user://note.txt) en « Bloc-notes.md ». Renvoie la clé ou "".
func import_notepad(src := "user://note.txt") -> String:
	if not FileAccess.file_exists(src): return ""
	return create("", "Bloc-notes", FileAccess.get_file_as_string(src))
