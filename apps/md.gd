extends RefCounted
## Markdown : conversion en BBCode (RichTextLabel) et analyse (liens [[...]], #tags, propriétés YAML, tâches).
## Fonctions statiques, sans interface : testées par tests/notes_test.gd.

const IMG_MARK := "\u0001"            # entoure « IMG:nom|largeur » dans la sortie BBCode (l'interface insère l'image)
const IMG_EXT := ["png", "jpg", "jpeg", "webp", "bmp", "svg", "gif"]
const PAT := {
	"code": "`+([^`\\n]+?)`+",
	"embed": "!\\[\\[([^\\]\\n]+?)\\]\\]",
	"mdimg": "!\\[([^\\]\\n]*)\\]\\(([^)\\s]+)\\)",
	"wl": "\\[\\[([^\\]\\n]+?)\\]\\]",
	"wl2": "(!?)\\[\\[([^\\]\\n]+?)\\]\\]",
	"mdlink": "\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)",
	"tag": "(?<![\\p{L}\\p{N}_#&/])#([\\p{L}_][\\p{L}\\p{N}_/\\-]*)",
	"b1": "\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*",
	"b2": "(?<![\\p{L}\\p{N}_])__(?=\\S)(.+?)(?<=\\S)__(?![\\p{L}\\p{N}_])",
	"i1": "(?<![\\p{L}\\p{N}_*])\\*(?=[^\\s*])(.+?)(?<=[^\\s*])\\*(?![\\p{L}\\p{N}_*])",
	"i2": "(?<![\\p{L}\\p{N}_])_(?=[^\\s_])(.+?)(?<=[^\\s_])_(?![\\p{L}\\p{N}_])",
	"st": "~~(?=\\S)(.+?)(?<=\\S)~~",
	"hl": "==(?=\\S)(.+?)(?<=\\S)==",
	"ph": "\u0002(\\d+)\u0003",
	"list": "^(\\s*)([-*+]|\\d+[.)])\\s+(.*)$",
	"task": "^\\[([ xX])\\]\\s+(.*)$",
	"callout": "^\\[!(\\w+)\\][+-]?\\s*(.*)$",
	"hr": "^(\\*{3,}|-{3,}|_{3,})$",
	"taskline": "^(\\s*[-*+]\\s+)\\[([ xX])\\]",
	"sep": "^\\s*\\|?\\s*:?-{2,}:?\\s*(\\|\\s*:?-{2,}:?\\s*)*\\|?\\s*$",
}
static var _re := {}

static func _rx(k: String) -> RegEx:
	if not _re.has(k):
		var r := RegEx.new(); r.compile(PAT[k]); _re[k] = r
	return _re[k]

## Précompile toutes les expressions (à appeler dans le fil principal avant d'utiliser Md dans un thread).
static func warm() -> void:
	for k in PAT: _rx(k)

static func esc(s: String) -> String:
	return s.replace("]", "\u0004").replace("[", "[lb]").replace("\u0004", "[rb]")

## Remplace chaque correspondance par fn(RegExMatch) -> String.
static func _sub(rx: RegEx, s: String, fn: Callable) -> String:
	var out := ""; var pos := 0
	for m in rx.search_all(s):
		out += s.substr(pos, m.get_start() - pos) + str(fn.call(m)); pos = m.get_end()
	return out + s.substr(pos)

# ------------------------------------------------------------------ analyse
static func _scalar(v: String) -> String:
	v = v.strip_edges()
	if v.length() >= 2 and ((v[0] == "\"" and v[-1] == "\"") or (v[0] == "'" and v[-1] == "'")): v = v.substr(1, v.length() - 2)
	return v

static func parse_yaml(lines: PackedStringArray) -> Dictionary:
	var d := {}; var key := ""
	for ln in lines:
		var st := ln.strip_edges()
		if st == "" or st.begins_with("#"): continue
		if st.begins_with("- ") or st == "-":
			if key != "":
				if not (d[key] is Array): d[key] = [] if str(d[key]) == "" else [str(d[key])]
				d[key].append(_scalar(st.substr(2)))
			continue
		var c := ln.find(":")
		if c <= 0 or ln[0] == " " or ln[0] == "\t": continue
		key = ln.substr(0, c).strip_edges(); var v := ln.substr(c + 1).strip_edges()
		if v.begins_with("[") and v.ends_with("]"):
			var arr := []
			for p in v.substr(1, v.length() - 2).split(","):
				if _scalar(p) != "": arr.append(_scalar(p))
			d[key] = arr
		else: d[key] = _scalar(v)
	return d

## Sépare l'en-tête YAML : {"front", "body", "offset" (nombre de lignes d'en-tête)}.
static func split_front(text: String) -> Dictionary:
	var lines := text.split("\n")
	if lines.size() >= 2 and lines[0].strip_edges() == "---":
		for i in range(1, lines.size()):
			var s := lines[i].strip_edges()
			if s == "---" or s == "...":
				return {"front": parse_yaml(lines.slice(1, i)), "body": "\n".join(lines.slice(i + 1)), "offset": i + 1}
	return {"front": {}, "body": text, "offset": 0}

## Cible d'un lien interne : « Note|alias », « Note#titre », « Note^bloc » -> « Note ».
static func link_target(raw: String) -> String:
	return raw.get_slice("|", 0).get_slice("#", 0).get_slice("^", 0).strip_edges()

static func fm_tags(front: Dictionary) -> Array:
	var out := []
	for k in ["tags", "tag"]:
		if not front.has(k): continue
		var v: Variant = front[k]
		var items: Array = v if v is Array else str(v).replace(",", " ").split(" ", false)
		for t in items:
			var s := str(t).strip_edges().trim_prefix("#")
			if s != "" and not out.has(s): out.append(s)
	return out

## Analyse d'une note : propriétés, titre (1er « # »), liens sortants, tags, tâches, mots, titres.
static func parse(text: String) -> Dictionary:
	text = text.replace("\r\n", "\n")
	var sp := split_front(text)
	var links := []; var tags: Array = fm_tags(sp["front"]); var heads := []
	var title := ""; var done := 0; var total := 0
	var fence := false
	for ln: String in str(sp["body"]).split("\n"):
		var s := ln.strip_edges()
		if s.begins_with("```") or s.begins_with("~~~"): fence = not fence; continue
		if fence: continue
		if ln.begins_with("#"):
			var lvl := 0
			while lvl < ln.length() and ln[lvl] == "#": lvl += 1
			if lvl <= 6 and ln.length() > lvl and ln[lvl] == " ":
				var h := ln.substr(lvl + 1).strip_edges()
				if title == "" and lvl == 1: title = h
				if heads.size() < 40: heads.append(h)
		var clean := _rx("code").sub(ln, "", true)
		for m in _rx("wl2").search_all(clean):
			var t := link_target(m.get_string(2))
			if t == "" or (m.get_string(1) == "!" and t.get_extension().to_lower() in IMG_EXT): continue
			if not links.has(t): links.append(t)
		clean = _rx("wl").sub(clean, "", true)
		clean = _rx("mdlink").sub(clean, "$1", true)
		for m in _rx("tag").search_all(clean):
			var t := m.get_string(1)
			if not tags.has(t): tags.append(t)
		var tm := _rx("taskline").search(ln)
		if tm:
			total += 1
			if tm.get_string(2) != " ": done += 1
	if title == "" and sp["front"].has("title"): title = str(sp["front"]["title"])
	return {"front": sp["front"], "title": title, "links": links, "tags": tags, "tasks": [done, total], "heads": heads,
		"words": str(sp["body"]).split(" ", false).size()}

## Coche / décoche la case de la ligne `line` (0 = première). Renvoie le texte modifié (inchangé si pas une tâche).
static func toggle_task(text: String, line: int) -> String:
	var lines := text.split("\n")
	if line < 0 or line >= lines.size(): return text
	var m := _rx("taskline").search(lines[line])
	if m == null: return text
	var nx := " " if m.get_string(2) != " " else "x"
	lines[line] = lines[line].substr(0, m.get_start(2)) + nx + lines[line].substr(m.get_end(2))
	return "\n".join(lines)

## Met à jour les liens [[old]] / [[old|alias]] / [[old#titre]] / ![[old]] vers `new_name` ; old_path = chemin sans .md (ex. « Dossier/Note »).
static func rename_links(text: String, old_name: String, old_path: String, new_name: String, new_path: String) -> String:
	var out := PackedStringArray(); var fence := false
	for ln in text.split("\n"):
		if ln.strip_edges().begins_with("```") or ln.strip_edges().begins_with("~~~"): fence = not fence
		if fence or not ln.contains("[["): out.append(ln); continue
		out.append(_sub(_rx("wl2"), ln, func(m: RegExMatch) -> String:
			var raw := m.get_string(2); var first := raw.get_slice("|", 0); var rest := raw.substr(first.length())
			var cut := first.length()
			for ch in ["#", "^"]:
				var ix := first.find(ch)
				if ix >= 0: cut = mini(cut, ix)
			var core := first.left(cut).strip_edges(); var sfx := first.substr(cut)
			var lc := core.to_lower()
			if lc == old_name.to_lower(): return "%s[[%s%s%s]]" % [m.get_string(1), new_name, sfx, rest]
			if lc == old_path.to_lower(): return "%s[[%s%s%s]]" % [m.get_string(1), new_path, sfx, rest]
			return m.get_string(0)))
	return "\n".join(out)

# ------------------------------------------------------------------ rendu BBCode
static func _hx(c: Variant) -> String:
	return c.to_html(false) if c is Color else str(c)

static func inline(s: String, c: Dictionary) -> String:
	var st: Array = []
	var put := func(b: String) -> String:
		st.append(b); return "\u0002%d\u0003" % (st.size() - 1)
	var ac: String = c["ac"]; var mu: String = c["mu"]; var cb: String = c["cb"]
	var exists: Callable = c["exists"]
	s = _sub(_rx("code"), s, func(m: RegExMatch) -> String: return put.call("[bgcolor=#%s][code]%s[/code][/bgcolor]" % [cb, esc(m.get_string(1))]))
	var link := func(raw: String) -> String:
		var t := link_target(raw)
		var alias := raw.get_slice("|", 1) if raw.contains("|") else raw
		if alias.strip_edges() == "": alias = t
		var ok: bool = not exists.is_valid() or bool(exists.call(t))
		return put.call("[color=#%s][url=note:%s]%s[/url][/color]" % [ac if ok else c["br"], t, esc(alias)])
	s = _sub(_rx("embed"), s, func(m: RegExMatch) -> String:
		var raw := m.get_string(1); var t := raw.get_slice("|", 0).strip_edges()
		if t.get_extension().to_lower() in IMG_EXT: return put.call(IMG_MARK + "IMG:" + raw + IMG_MARK)
		return link.call(raw))
	s = _sub(_rx("mdimg"), s, func(m: RegExMatch) -> String:
		var u := m.get_string(2)
		if u.begins_with("http"): return put.call("[color=#%s]%s[/color]" % [mu, esc("[" + (m.get_string(1) if m.get_string(1) != "" else "image") + "]")])
		return put.call(IMG_MARK + "IMG:" + u + IMG_MARK))
	s = _sub(_rx("wl"), s, func(m: RegExMatch) -> String: return link.call(m.get_string(1)))
	s = _sub(_rx("mdlink"), s, func(m: RegExMatch) -> String:
		return put.call("[color=#%s][url=%s]%s[/url][/color]" % [ac, m.get_string(2), esc(m.get_string(1))]))
	s = esc(s)
	s = _sub(_rx("tag"), s, func(m: RegExMatch) -> String:
		return put.call("[color=#%s][url=tag:%s]#%s[/url][/color]" % [ac, m.get_string(1), m.get_string(1)]))
	s = _rx("b1").sub(s, "[b]$1[/b]", true); s = _rx("b2").sub(s, "[b]$1[/b]", true)
	s = _rx("i1").sub(s, "[i]$1[/i]", true); s = _rx("i2").sub(s, "[i]$1[/i]", true)
	s = _rx("st").sub(s, "[s]$1[/s]", true)
	s = _rx("hl").sub(s, "[bgcolor=#%s]$1[/bgcolor]" % c["hl"], true)
	for _i in 6:
		if not s.contains("\u0002"): break
		s = _sub(_rx("ph"), s, func(m: RegExMatch) -> String: return st[int(m.get_string(1))])
	return s

static func _cells(row: String) -> PackedStringArray:
	var r := row.strip_edges()
	if r.begins_with("|"): r = r.substr(1)
	if r.ends_with("|"): r = r.left(r.length() - 1)
	var out := PackedStringArray()
	for p in r.split("|"): out.append(p.strip_edges())
	return out

## o : size (corps), accent / muted / code_bg / broken / hl (couleurs hex ou Color), exists (Callable cible -> bool).
static func to_bbcode(text: String, o := {}) -> String:
	text = text.replace("\r\n", "\n")
	var base: int = int(o.get("size", 16))
	var c := {"ac": _hx(o.get("accent", "5aa2ff")), "mu": _hx(o.get("muted", "8f9bb3")), "cb": _hx(o.get("code_bg", "2a3040")),
		"br": _hx(o.get("broken", "f87171")), "hl": _hx(o.get("hl", "7a6a1f")), "exists": o.get("exists", Callable())}
	var lines := text.split("\n"); var out := PackedStringArray(); var i := 0
	var sp := split_front(text)
	if int(sp["offset"]) > 0:
		for k in sp["front"]:
			var v: Variant = sp["front"][k]
			out.append("[color=#%s]%s :[/color] %s" % [c["mu"], esc(str(k)), esc(", ".join(v) if v is Array else str(v))])
		out.append("[color=#%s]────────────────────────[/color]" % c["mu"])
		i = int(sp["offset"])
	var sizes := [1.9, 1.6, 1.35, 1.2, 1.1, 1.0]
	while i < lines.size():
		var ln: String = lines[i]; var st := ln.strip_edges()
		if st.begins_with("```") or st.begins_with("~~~"):
			var fence := st.left(3); var buf := PackedStringArray(); i += 1
			while i < lines.size() and not lines[i].strip_edges().begins_with(fence): buf.append(esc(lines[i])); i += 1
			i += 1
			out.append("[bgcolor=#%s][code]%s[/code][/bgcolor]" % [c["cb"], "\n".join(buf)])
			continue
		if st.begins_with("|") and i + 1 < lines.size() and _rx("sep").search(lines[i + 1]) and lines[i + 1].contains("-"):
			var rows := [_cells(st)]; i += 2
			while i < lines.size() and lines[i].strip_edges().begins_with("|"): rows.append(_cells(lines[i])); i += 1
			var n := 0
			for r in rows: n = maxi(n, r.size())
			var t := "[table=%d]" % n
			for ri in rows.size():
				for ci in n:
					var cell: String = rows[ri][ci] if ci < rows[ri].size() else ""
					cell = inline(cell, c)
					t += "[cell padding=6,2,6,2]%s[/cell]" % (("[b]" + cell + "[/b]") if ri == 0 else cell)
			out.append(t + "[/table]")
			continue
		if st.begins_with("#"):
			var lvl := 0
			while lvl < st.length() and st[lvl] == "#": lvl += 1
			if lvl <= 6 and st.length() > lvl and st[lvl] == " ":
				out.append("[font_size=%d][b]%s[/b][/font_size]" % [int(base * sizes[lvl - 1]), inline(st.substr(lvl + 1).rstrip("# "), c)])
				i += 1; continue
		if _rx("hr").search(st.replace(" ", "")) and st != "":
			out.append("[color=#%s]────────────────────────────────[/color]" % c["mu"]); i += 1; continue
		if st.begins_with(">"):
			while i < lines.size() and lines[i].strip_edges().begins_with(">"):
				var q := lines[i].strip_edges().lstrip("> ").strip_edges()
				var cm := _rx("callout").search(q)
				if cm: q = "[b]%s[/b] %s" % [esc(cm.get_string(1).capitalize()), inline(cm.get_string(2), c)]
				else: q = inline(q, c)
				out.append("[color=#%s]▎[/color] [color=#%s]%s[/color]" % [c["ac"], c["mu"], q]); i += 1
			continue
		var lm := _rx("list").search(ln)
		if lm:
			var lv: int = lm.get_string(1).replace("\t", "  ").length() / 2
			var pre := " ".repeat(lv)
			var mark := lm.get_string(2); var body := lm.get_string(3)
			var tm := _rx("task").search(body)
			if tm:
				var done := tm.get_string(1) != " "
				var txt := inline(tm.get_string(2), c)
				if done: txt = "[color=#%s][s]%s[/s][/color]" % [c["mu"], txt]
				out.append("%s[url=task:%d][color=#%s]%s[/color][/url] %s" % [pre, i, c["ac"], "☑" if done else "☐", txt])
			else:
				out.append("%s%s %s" % [pre, ("•" if lv == 0 else "◦" if lv == 1 else "▪") if not mark[0].is_valid_int() else mark, inline(body, c)])
			i += 1; continue
		out.append(inline(ln, c)); i += 1
	return "\n".join(out)
