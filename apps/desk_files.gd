extends RefCounted
## Éléments du bureau : fichiers/dossiers réels (logique pure, testable).
## Dossier : ~/Bureau sur PC (s'il existe ou peut être créé), sinon user://Bureau.

static func dir() -> String:
	var d := "user://Bureau"
	if OS.get_name() in ["Linux", "Windows", "macOS"]:
		var h := OS.get_environment("HOME" if OS.get_name() != "Windows" else "USERPROFILE")
		if h != "":
			var p := h.path_join("Bureau")
			if DirAccess.dir_exists_absolute(p) or DirAccess.make_dir_recursive_absolute(p) == OK: d = p
	DirAccess.make_dir_recursive_absolute(d)
	return d

## Message d'erreur si le nom est invalide, "" sinon.
static func check_name(n: String) -> String:
	var t := n.strip_edges()
	if t == "": return "Nom vide"
	if t == "." or t == "..": return "Nom invalide"
	for c in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		if t.contains(c): return "Caractère interdit : " + c
	if t.length() > 120: return "Nom trop long"
	return ""

static func exists(p: String) -> bool: return FileAccess.file_exists(p) or DirAccess.dir_exists_absolute(p)

static func uniq(d: String, name: String) -> String:
	var p := d.path_join(name)
	var k := 2
	var ext := name.get_extension(); var base := name.get_basename() if ext != "" else name
	while exists(p):
		p = d.path_join("%s (%d)%s" % [base, k, "." + ext if ext != "" else ""]); k += 1
	return p

## Crée un fichier texte vide ou un dossier ; renvoie le chemin ("" si échec).
static func create(d: String, name: String, folder: bool) -> String:
	if check_name(name) != "": return ""
	var p := uniq(d, name.strip_edges())
	if folder: return p if DirAccess.make_dir_recursive_absolute(p) == OK else ""
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null: return ""
	f.close(); return p

## Renomme ; renvoie le nouveau chemin, "" si refus (nom invalide ou déjà pris).
static func rename(p: String, name: String) -> String:
	var t := name.strip_edges()
	if check_name(t) != "": return ""
	var dst := p.get_base_dir().path_join(t)
	if dst == p: return p
	if exists(dst): return ""
	return dst if DirAccess.rename_absolute(p, dst) == OK else ""

static func _copy(src: String, dst: String) -> bool:
	if DirAccess.dir_exists_absolute(src):
		DirAccess.make_dir_recursive_absolute(dst)
		for s in DirAccess.get_directories_at(src): if not _copy(src.path_join(s), dst.path_join(s)): return false
		for f in DirAccess.get_files_at(src): if not _copy(src.path_join(f), dst.path_join(f)): return false
		return true
	return DirAccess.copy_absolute(src, dst) == OK

static func _rm(p: String) -> void:
	if DirAccess.dir_exists_absolute(p):
		for s in DirAccess.get_directories_at(p): _rm(p.path_join(s))
		for f in DirAccess.get_files_at(p): DirAccess.remove_absolute(p.path_join(f))
	DirAccess.remove_absolute(p)

## Déplace p dans le dossier dst_dir (nom adapté en cas de collision) ; renvoie le chemin final ou "".
static func move_into(p: String, dst_dir: String) -> String:
	if not DirAccess.dir_exists_absolute(dst_dir) or p.get_base_dir() == dst_dir: return ""
	if dst_dir == p or dst_dir.begins_with(p + "/"): return ""
	var t := uniq(dst_dir, p.get_file())
	if DirAccess.rename_absolute(p, t) == OK: return t
	if _copy(p, t): _rm(p); return t
	return ""

## Entrées [{name, path, dir}] : dossiers d'abord, tri alphabétique, sans fichiers cachés.
static func list(d: String) -> Array:
	var out := []
	for s in DirAccess.get_directories_at(d): if not s.begins_with("."): out.append({"name": s, "path": d.path_join(s), "dir": true})
	for f in DirAccess.get_files_at(d): if not f.begins_with("."): out.append({"name": f, "path": d.path_join(f), "dir": false})
	out.sort_custom(func(a, b): return str(a["name"]).to_lower() < str(b["name"]).to_lower() if a["dir"] == b["dir"] else bool(a["dir"]))
	return out
