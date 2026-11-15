extends Control
## Éditeur de code : CodeEdit, coloration par extension, onglets, recherche/remplacement, sauvegarde auto en user://.

const SESSION := "user://code_session.json"
var main: Node = null
var docs: Array = []     # {path, ce, saved, name}
var cur := 0
var fsize := 17
var tabbar: HBoxContainer
var stack: Control
var pathe: LineEdit
var find_bar: HBoxContainer
var find_in: LineEdit
var rep_in: LineEdit
var status: Label
var mono: SystemFont
var dirty_session := false
var _timer: Timer

const KW := {
	"gd": "func var const class extends class_name signal enum if elif else for while match return pass break continue await static self null true false and or not in is as void int float bool String Array Dictionary preload load @export @onready",
	"py": "def class import from as if elif else for while try except finally with return pass break continue lambda yield None True False and or not in is global nonlocal raise assert async await del",
	"js": "function var let const class extends new if else for while do switch case break continue return try catch finally throw async await import export from default null undefined true false typeof instanceof this super in of",
	"html": "html head body div span a p ul ol li h1 h2 h3 h4 img script style link meta title table tr td th form input button nav section header footer main br",
	"css": "color background margin padding border display flex grid position width height font-size font-family top left right bottom none auto important",
	"json": "true false null",
	"md": "",
	"sh": "if then else elif fi for while do done case esac function return exit echo cd export local in source alias unset read",
	"php": "function class extends new if else elseif for foreach while switch case break continue return try catch finally throw echo print public private protected static namespace use null true false array isset empty",
}
const ALIAS := {"gdscript": "gd", "pyw": "py", "mjs": "js", "ts": "js", "htm": "html", "markdown": "md", "bash": "sh", "zsh": "sh", "phtml": "php", "scss": "css"}

func _col(k: String, fb: Color) -> Color: return main._p(k) if main else fb
func lang_for(path: String) -> String:
	var e := path.get_extension().to_lower(); e = ALIAS.get(e, e)
	return e if KW.has(e) else ""

func make_hl(lang: String) -> CodeHighlighter:
	var h := CodeHighlighter.new()
	var light: bool = main != null and main.set_cfg.get("light", false)
	h.number_color = Color("b45309") if light else Color("f59e0b")
	h.symbol_color = Color("475569") if light else Color("94a3b8")
	h.function_color = Color("1d4ed8") if light else Color("7dd3fc")
	h.member_variable_color = Color("0f766e") if light else Color("5eead4")
	var kc := Color("7c3aed") if light else Color("c4b5fd")
	for k in str(KW.get(lang, "")).split(" ", false): h.add_keyword_color(k, kc)
	var sc := Color("15803d") if light else Color("86efac"); var cc := Color("64748b") if light else Color("6b7a99")
	match lang:
		"gd", "py", "sh":
			h.add_color_region("#", "", cc, true)
			h.add_color_region("\"\"\"", "\"\"\"", sc); h.add_color_region("\"", "\"", sc); h.add_color_region("'", "'", sc)
		"js", "php":
			h.add_color_region("//", "", cc, true); h.add_color_region("/*", "*/", cc)
			if lang == "php": h.add_color_region("#", "", cc, true)
			h.add_color_region("\"", "\"", sc); h.add_color_region("'", "'", sc); h.add_color_region("`", "`", sc)
		"css": h.add_color_region("/*", "*/", cc); h.add_color_region("\"", "\"", sc); h.add_color_region("'", "'", sc)
		"html": h.add_color_region("<!--", "-->", cc); h.add_color_region("\"", "\"", sc); h.add_color_region("'", "'", sc)
		"json": h.add_color_region("\"", "\"", sc)
		"md": h.add_color_region("```", "```", sc); h.add_color_region("#", "", kc, true); h.add_color_region("`", "`", sc)
	return h

# ------------------------------------------------------------------ documents
func _new_ce() -> CodeEdit:
	var ce := CodeEdit.new(); ce.set_anchors_preset(Control.PRESET_FULL_RECT)
	ce.gutters_draw_line_numbers = true; ce.indent_automatic = true; ce.auto_brace_completion_enabled = true
	ce.line_folding = false; ce.draw_tabs = false; ce.minimap_draw = false
	ce.indent_use_spaces = true; ce.indent_size = 4
	ce.add_theme_font_override("font", mono); ce.add_theme_font_size_override("font_size", fsize)
	ce.add_theme_color_override("background_color", _col("field", Color("171b25"))); ce.add_theme_color_override("font_color", _col("text", Color("e5e9f0")))
	ce.add_theme_color_override("line_number_color", _col("muted", Color("6b7a99")))
	ce.gui_input.connect(_key)
	return ce

func new_doc(path := "", text := "") -> Dictionary:
	var ce := _new_ce()
	var lang := lang_for(path)
	ce.syntax_highlighter = make_hl(lang)
	if lang == "gd": ce.indent_use_spaces = false
	ce.text = text; ce.clear_undo_history()
	var d := {"path": path, "ce": ce, "saved": text, "lang": lang}
	ce.text_changed.connect(func(): dirty_session = true; _rebuild_tabs())
	if stack: stack.add_child(ce)
	docs.append(d); _select(docs.size() - 1)
	return d

func doc_name(d: Dictionary) -> String:
	var n: String = d["path"].get_file() if d["path"] != "" else "Sans titre"
	return n + ("*" if is_dirty(d) else "")

func is_dirty(d: Dictionary) -> bool: return (d["ce"] as CodeEdit).text != d["saved"]

func open_path(path: String) -> bool:
	for i in docs.size():
		if docs[i]["path"] == path: _select(i); return true
	if not FileAccess.file_exists(path): _msg("Introuvable : " + path); return false
	new_doc(path, FileAccess.get_file_as_string(path)); dirty_session = true; return true

func save_doc(d: Dictionary, path := "") -> bool:
	if path != "": d["path"] = path
	if d["path"] == "": _msg("Saisissez un chemin puis Enregistrer"); return false
	var f := FileAccess.open(d["path"], FileAccess.WRITE)
	if f == null: _msg("Écriture impossible : " + str(d["path"])); return false
	var t: String = (d["ce"] as CodeEdit).text
	f.store_string(t); f.close(); d["saved"] = t
	d["lang"] = lang_for(d["path"]); (d["ce"] as CodeEdit).syntax_highlighter = make_hl(d["lang"])
	dirty_session = true; _rebuild_tabs(); _msg("Enregistré : " + str(d["path"])); return true

func close_doc(i: int) -> void:
	if i < 0 or i >= docs.size(): return
	(docs[i]["ce"] as Node).queue_free(); docs.remove_at(i)
	if docs.is_empty(): new_doc()
	dirty_session = true; _select(mini(cur, docs.size() - 1))

func _msg(t: String) -> void:
	if status: status.text = t

# ------------------------------------------------------------------ recherche
func find_next(q: String, back := false) -> bool:
	if q == "" or docs.is_empty(): return false
	var ce: CodeEdit = docs[cur]["ce"]
	var line := ce.get_caret_line(); var col := ce.get_caret_column()
	if ce.has_selection(): col = ce.get_selection_to_column() if not back else ce.get_selection_from_column(); line = ce.get_selection_to_line() if not back else ce.get_selection_from_line()
	var r := ce.search(q, TextEdit.SEARCH_BACKWARDS if back else 0, line, col)
	if r.x < 0: r = ce.search(q, TextEdit.SEARCH_BACKWARDS if back else 0, ce.get_line_count() - 1 if back else 0, ce.get_line(ce.get_line_count() - 1).length() if back else 0)
	if r.x < 0: _msg("Introuvable : " + q); return false
	ce.select(r.y, r.x, r.y, r.x + q.length()); ce.center_viewport_to_caret(); return true

func replace_one(q: String, by: String) -> bool:
	var ce: CodeEdit = docs[cur]["ce"]
	if ce.has_selection() and ce.get_selected_text() == q: ce.insert_text_at_caret(by); dirty_session = true; _rebuild_tabs()
	return find_next(q)

func replace_all(q: String, by: String) -> int:
	if q == "": return 0
	var ce: CodeEdit = docs[cur]["ce"]
	var n := ce.text.count(q)
	if n > 0:
		var ln := ce.get_caret_line(); ce.begin_complex_operation(); ce.text = ce.text.replace(q, by); ce.end_complex_operation()
		ce.set_caret_line(mini(ln, ce.get_line_count() - 1)); dirty_session = true; _rebuild_tabs()
	_msg("%d remplacement(s)" % n); return n

func set_font_size(n: int) -> void:
	fsize = clampi(n, 8, 48)
	for d in docs: (d["ce"] as CodeEdit).add_theme_font_size_override("font_size", fsize)

# ------------------------------------------------------------------ sauvegarde auto
func autosave() -> void:
	var arr: Array = []
	for d in docs:
		var dirty := is_dirty(d)
		arr.append({"path": d["path"], "text": (d["ce"] as CodeEdit).text if (dirty or d["path"] == "") else null, "dirty": dirty})
	var f := FileAccess.open(SESSION, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"docs": arr, "cur": cur, "fsize": fsize}))
	dirty_session = false

func restore() -> bool:
	if not FileAccess.file_exists(SESSION): return false
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(SESSION))
	if not (j is Dictionary) or not (j.get("docs") is Array) or j["docs"].is_empty(): return false
	fsize = int(j.get("fsize", fsize))
	for e in j["docs"]:
		var p := str(e.get("path", ""))
		var disk := FileAccess.get_file_as_string(p) if p != "" and FileAccess.file_exists(p) else ""
		var d := new_doc(p, disk)
		if e.get("text") != null:
			(d["ce"] as CodeEdit).text = str(e["text"])
	_select(clampi(int(j.get("cur", 0)), 0, docs.size() - 1)); return true

# ------------------------------------------------------------------ interface
func _btn(t: String, w: float, f: Callable) -> Button:
	var b := Button.new(); b.text = t; b.custom_minimum_size = Vector2(w, 40); b.focus_mode = Control.FOCUS_NONE; b.pressed.connect(f); return b

func _ready() -> void:
	mono = SystemFont.new(); mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Noto Sans Mono", "monospace"])
	var vb := VBoxContainer.new(); vb.set_anchors_preset(Control.PRESET_FULL_RECT); vb.add_theme_constant_override("separation", 4); add_child(vb)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 4); vb.add_child(top)
	top.add_child(_btn("Nouveau", 74, func(): new_doc()))
	pathe = LineEdit.new(); pathe.size_flags_horizontal = Control.SIZE_EXPAND_FILL; pathe.custom_minimum_size.y = 38; pathe.placeholder_text = "Chemin du fichier (user://note.gd, /home/...)"
	pathe.text_submitted.connect(func(t): open_path(t.strip_edges())); top.add_child(pathe)
	top.add_child(_btn("Ouvrir", 64, func(): open_path(pathe.text.strip_edges())))
	top.add_child(_btn("Enregistrer", 96, func(): _save_cur()))
	top.add_child(_btn("A-", 38, func(): set_font_size(fsize - 1)))
	top.add_child(_btn("A+", 38, func(): set_font_size(fsize + 1)))
	top.add_child(_btn("Chercher", 76, func(): toggle_find()))
	var sc := ScrollContainer.new(); sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; sc.custom_minimum_size.y = 42; vb.add_child(sc)
	tabbar = HBoxContainer.new(); tabbar.add_theme_constant_override("separation", 4); sc.add_child(tabbar)
	find_bar = HBoxContainer.new(); find_bar.visible = false; find_bar.add_theme_constant_override("separation", 4); vb.add_child(find_bar)
	find_in = LineEdit.new(); find_in.placeholder_text = "Rechercher"; find_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL; find_in.custom_minimum_size.y = 38
	find_in.text_submitted.connect(func(t): find_next(t)); find_bar.add_child(find_in)
	rep_in = LineEdit.new(); rep_in.placeholder_text = "Remplacer par"; rep_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL; rep_in.custom_minimum_size.y = 38; find_bar.add_child(rep_in)
	find_bar.add_child(_btn("Préc.", 56, func(): find_next(find_in.text, true)))
	find_bar.add_child(_btn("Suiv.", 56, func(): find_next(find_in.text)))
	find_bar.add_child(_btn("Remplacer", 86, func(): replace_one(find_in.text, rep_in.text)))
	find_bar.add_child(_btn("Tout", 50, func(): replace_all(find_in.text, rep_in.text)))
	stack = Control.new(); stack.size_flags_vertical = Control.SIZE_EXPAND_FILL; stack.clip_contents = true; vb.add_child(stack)
	status = Label.new(); status.theme_type_variation = "Muted"; status.add_theme_font_size_override("font_size", 14); vb.add_child(status)
	if not restore(): new_doc()
	_timer = Timer.new(); _timer.wait_time = 5.0; _timer.autostart = true
	_timer.timeout.connect(func(): if dirty_session: autosave())
	add_child(_timer)

func _save_cur() -> void:
	var d: Dictionary = docs[cur]
	save_doc(d, pathe.text.strip_edges() if d["path"] == "" else "")

func toggle_find() -> void:
	find_bar.visible = not find_bar.visible
	if find_bar.visible: find_in.grab_focus()

func _rebuild_tabs() -> void:
	if tabbar == null: return
	for c in tabbar.get_children(): c.queue_free()
	for i in docs.size():
		var b := Button.new(); b.text = doc_name(docs[i]); b.toggle_mode = true; b.button_pressed = i == cur; b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 34; b.pressed.connect(_select.bind(i)); tabbar.add_child(b)
	var x := Button.new(); x.text = "✕"; x.custom_minimum_size = Vector2(34, 34); x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(func(): close_doc(cur)); tabbar.add_child(x)

func _select(i: int) -> void:
	cur = clampi(i, 0, docs.size() - 1)
	for k in docs.size(): (docs[k]["ce"] as Control).visible = k == cur
	if pathe and not docs.is_empty(): pathe.text = docs[cur]["path"]
	_rebuild_tabs()

func _key(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.ctrl_pressed:
		if ev.keycode == KEY_S: _save_cur(); accept_event()
		elif ev.keycode == KEY_F: toggle_find(); accept_event()
		elif ev.keycode == KEY_EQUAL or ev.keycode == KEY_PLUS: set_font_size(fsize + 1); accept_event()
		elif ev.keycode == KEY_MINUS: set_font_size(fsize - 1); accept_event()

func _exit_tree() -> void:
	if dirty_session and not docs.is_empty(): autosave()
