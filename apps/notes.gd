extends Control
## Notes façon Obsidian : coffre de fichiers .md, édition + aperçu Markdown, liens [[...]], rétroliens, tags, graphe, note du jour.
## Logique dans apps/vault.gd (index, liens) et apps/md.gd (Markdown) ; graphe dans apps/notes_graph.gd.
const UI = preload("res://apps/ui.gd")
const Md = preload("res://apps/md.gd")
const Vault = preload("res://apps/vault.gd")
const Graph = preload("res://apps/notes_graph.gd")

var m
var vault
var cur := ""
var tabs: Array = []
var hist: Array = []
var hpos := -1
var mode := 2                 # 0 édition, 1 aperçu, 2 les deux
var left_on := true
var right_on := false
var show_graph := false
var side_mode := 0            # 0 notes, 1 étiquettes
var tag_focus := ""
var dirty := false
var loading := false
var sel_dir := ""
var open_dirs := {}
var img_cache := {}
var items := {}               # clé -> TreeItem
var lock_tree := false
var ac_start := -1

var edit: CodeEdit
var hl
var prev: RichTextLabel
var edit_box: PanelContainer
var prev_box: PanelContainer
var graph
var empty: Control
var left_p: PanelContainer
var right_p: PanelContainer
var center: VBoxContainer
var tree: Tree
var search: LineEdit
var tabs_sc: ScrollContainer
var tabs_box: HBoxContainer
var links_box: VBoxContainer
var status: Label
var mode_opt: OptionButton
var b_back: Button
var b_fwd: Button
var b_graph: Button
var b_left: Button
var b_right: Button
var b_side0: Button
var b_side1: Button
var ov: Control
var dlg_host: CenterContainer
var ac: PanelContainer
var ac_list: ItemList
var save_t: Timer
var prev_t: Timer
var srch_t: Timer
var poll_t: Timer
var tree_sc_top := 0.0

# ------------------------------------------------------------------ coloration Markdown de l'éditeur
class MdHL extends SyntaxHighlighter:
	var c_text := Color.WHITE
	var c_head := Color.CYAN
	var c_link := Color.CYAN
	var c_code := Color.GREEN
	var c_quote := Color.GRAY
	var c_tag := Color.ORANGE
	var fence: Array = []
	var rx_code := RegEx.new()
	var rx_wl := RegEx.new()
	var rx_tag := RegEx.new()
	var rx_list := RegEx.new()
	func _init() -> void:
		rx_code.compile("`[^`\\n]+`"); rx_wl.compile("!?\\[\\[[^\\]\\n]*\\]?\\]?"); rx_list.compile("^\\s*([-*+]|\\d+[.)])\\s")
		rx_tag.compile("(?<![\\p{L}\\p{N}_#&/\\[])#[\\p{L}_][\\p{L}\\p{N}_/\\-]*")
	func _clear_highlighting_cache() -> void:
		fence = []
	func _scan(te: TextEdit) -> void:
		fence = []; var f := false
		for i in te.get_line_count():
			var s := te.get_line(i).strip_edges()
			if s.begins_with("```") or s.begins_with("~~~"): f = not f; fence.append(true)
			else: fence.append(f)
	func _paint(cols: PackedColorArray, a: int, b: int, c: Color) -> void:
		for i in range(a, mini(b, cols.size())): cols[i] = c
	func _get_line_syntax_highlighting(line: int) -> Dictionary:
		var te := get_text_edit()
		var s := te.get_line(line); var n := s.length()
		if n == 0: return {}
		if fence.size() != te.get_line_count(): _scan(te)
		var cols := PackedColorArray(); cols.resize(n); cols.fill(c_text)
		if fence[line]: cols.fill(c_code)
		else:
			var lv := 0
			while lv < n and s[lv] == "#": lv += 1
			if lv > 0 and lv <= 6 and n > lv and s[lv] == " ": cols.fill(c_head)
			elif s.begins_with(">"): cols.fill(c_quote)
			else:
				var lm := rx_list.search(s)
				if lm: _paint(cols, lm.get_start(1), lm.get_end(1), c_head)
			for r in [[rx_code, c_code], [rx_wl, c_link], [rx_tag, c_tag]]:
				for mt in r[0].search_all(s): _paint(cols, mt.get_start(), mt.get_end(), r[1])
		var d := {}
		for i in n:
			if i == 0 or cols[i] != cols[i - 1]: d[i] = {"color": cols[i]}
		return d

# ------------------------------------------------------------------ construction
func _btn(t: String, cb: Callable, tip := "", primary := false, w := 0) -> Button:
	var b := UI.button(t, primary, w); b.pressed.connect(cb); b.tooltip_text = tip; b.clip_text = true; return b

func build() -> void:
	vault = m.notes_vault() if m != null and m.has_method("notes_vault") else Vault.new()
	if m == null or not m.has_method("notes_vault"): vault.load_cfg(); vault.load_cache()
	vault.ensure_root()
	if vault.notes.is_empty() and vault.list_notes().size() < 200: vault.reindex()
	else: vault.start_scan()
	vault.changed.connect(_on_index)
	var root_v := VBoxContainer.new(); root_v.set_anchors_preset(Control.PRESET_FULL_RECT); root_v.add_theme_constant_override("separation", UI.S1); add_child(root_v)
	# barre d'outils
	var tb := UI.toolbar(); root_v.add_child(tb)
	b_left = _btn("☰", func(): _toggle_left(), "Dossiers et étiquettes", false, 40); tb.add_child(b_left)
	b_back = _btn("◀", func(): _nav(-1), "Retour", false, 40); tb.add_child(b_back)
	b_fwd = _btn("▶", func(): _nav(1), "Avant", false, 40); tb.add_child(b_fwd)
	tb.add_child(_btn("+ Note", func(): _new_flow(), "Nouvelle note (Ctrl+N)", true, 0))
	tb.add_child(_btn("Aujourd'hui", func(): open_daily(), "Note du jour (Ctrl+D)"))
	mode_opt = OptionButton.new(); mode_opt.custom_minimum_size = Vector2(110, UI.TOUCH)
	for t in ["Édition", "Aperçu", "Les deux"]: mode_opt.add_item(t)
	mode_opt.select(mode); mode_opt.item_selected.connect(func(i: int): mode = i; _layout()); tb.add_child(mode_opt)
	b_graph = _btn("Graphe", func(): _toggle_graph(), "Vue graphe (Ctrl+G)"); tb.add_child(b_graph)
	b_right = _btn("Liens", func(): _toggle_right(), "Rétroliens et liens sortants"); tb.add_child(b_right)
	# zone principale
	var row := HBoxContainer.new(); row.size_flags_vertical = Control.SIZE_EXPAND_FILL; row.add_theme_constant_override("separation", UI.S2); root_v.add_child(row)
	left_p = PanelContainer.new(); left_p.add_theme_stylebox_override("panel", UI.card_box(UI.S2)); row.add_child(left_p)
	_build_left()
	center = VBoxContainer.new(); center.size_flags_horizontal = Control.SIZE_EXPAND_FILL; center.add_theme_constant_override("separation", UI.S1); row.add_child(center)
	_build_center()
	right_p = PanelContainer.new(); right_p.add_theme_stylebox_override("panel", UI.card_box(UI.S2)); right_p.custom_minimum_size.x = 250; row.add_child(right_p)
	var rs := ScrollContainer.new(); rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; right_p.add_child(rs)
	links_box = VBoxContainer.new(); links_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; links_box.add_theme_constant_override("separation", UI.S2); rs.add_child(links_box)
	# fenêtre de dialogue et autocomplétion
	ov = Control.new(); ov.set_anchors_preset(Control.PRESET_FULL_RECT); ov.visible = false; add_child(ov)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.45); dim.set_anchors_preset(Control.PRESET_FULL_RECT); ov.add_child(dim)
	dim.gui_input.connect(func(e: InputEvent): if e is InputEventMouseButton and e.pressed: _close_dialog())
	dlg_host = CenterContainer.new(); dlg_host.set_anchors_preset(Control.PRESET_FULL_RECT); dlg_host.mouse_filter = Control.MOUSE_FILTER_IGNORE; ov.add_child(dlg_host)
	ac = PanelContainer.new(); ac.visible = false; ac.z_index = 20; add_child(ac)
	ac_list = ItemList.new(); ac_list.custom_minimum_size = Vector2(220, 150); ac_list.item_clicked.connect(func(i: int, _p: Vector2, _b: int): _ac_accept(i)); ac.add_child(ac_list)
	# minuteries
	save_t = _timer(0.8, _save_now); prev_t = _timer(0.25, _render); srch_t = _timer(0.15, _fill_tree)
	poll_t = Timer.new(); poll_t.wait_time = 0.3; poll_t.timeout.connect(func(): vault.poll()); add_child(poll_t); poll_t.start()
	resized.connect(_layout)
	_apply_theme(); _fill_tree(); _refresh_all()
	if tabs.is_empty() and vault.notes.has("Bienvenue.md"): open_note("Bienvenue.md")

func _timer(t: float, cb: Callable) -> Timer:
	var tm := Timer.new(); tm.wait_time = t; tm.one_shot = true; tm.timeout.connect(cb); add_child(tm); return tm

func _build_left() -> void:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", UI.S2); left_p.add_child(v)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", UI.S1); v.add_child(top)
	var vb := _btn("Coffre", func(): _vault_menu(), "Dossier du coffre, import, réindexation"); vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(vb)
	search = UI.search_field("Chercher dans le coffre…"); search.custom_minimum_size.x = 60
	search.text_changed.connect(func(_t: String): srch_t.start()); v.add_child(search)
	var mrow := HBoxContainer.new(); mrow.add_theme_constant_override("separation", UI.S1); v.add_child(mrow)
	b_side0 = _btn("Notes", func(): side_mode = 0; _fill_tree(); _side_btns(), "", true); b_side0.size_flags_horizontal = Control.SIZE_EXPAND_FILL; mrow.add_child(b_side0)
	b_side1 = _btn("Étiquettes", func(): side_mode = 1; _fill_tree(); _side_btns()); b_side1.size_flags_horizontal = Control.SIZE_EXPAND_FILL; mrow.add_child(b_side1)
	tree = Tree.new(); tree.hide_root = true; tree.size_flags_vertical = Control.SIZE_EXPAND_FILL; tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size = Vector2(120, 120); tree.item_selected.connect(_tree_selected); tree.item_collapsed.connect(_tree_collapsed)
	tree.set_drag_forwarding(_tree_drag, _tree_can_drop, _tree_drop); v.add_child(tree)
	var ft := UI.toolbar(); v.add_child(ft)
	for e in [["+ Dossier", func(): _new_dir()], ["Renommer", func(): _rename_target()], ["★", func(): _fav_target()], ["Supprimer", func(): _delete_target()]]:
		var b := _btn(e[0], e[1], "", false, 0); b.custom_minimum_size.x = 40; ft.add_child(b)

func _side_btns() -> void:
	b_side0.theme_type_variation = "Accent" if side_mode == 0 else "Flat"
	b_side1.theme_type_variation = "Accent" if side_mode == 1 else "Flat"

func _build_center() -> void:
	tabs_sc = ScrollContainer.new(); tabs_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; tabs_sc.custom_minimum_size.y = UI.TOUCH + 6; center.add_child(tabs_sc)
	tabs_box = HBoxContainer.new(); tabs_box.add_theme_constant_override("separation", UI.S1); tabs_sc.add_child(tabs_box)
	var stack := HBoxContainer.new(); stack.size_flags_vertical = Control.SIZE_EXPAND_FILL; stack.add_theme_constant_override("separation", UI.S2); center.add_child(stack)
	edit_box = PanelContainer.new(); edit_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; edit_box.size_flags_stretch_ratio = 1.0; stack.add_child(edit_box)
	edit = CodeEdit.new(); edit.size_flags_vertical = Control.SIZE_EXPAND_FILL; edit.custom_minimum_size = Vector2(100, 100)
	edit.gutters_draw_line_numbers = false; edit.line_folding = false; edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.virtual_keyboard_enabled = false; edit.highlight_current_line = true; edit.scroll_smooth = true; edit.indent_automatic = false
	edit.auto_brace_completion_enabled = true; edit.auto_brace_completion_pairs = {"[": "]", "(": ")", "`": "`"}
	edit.placeholder_text = "Écrivez en Markdown… [[ pour lier une note, #étiquette"
	hl = MdHL.new(); edit.syntax_highlighter = hl
	edit.text_changed.connect(_on_changed); edit.gui_input.connect(_edit_input)
	edit_box.add_child(edit)
	prev_box = PanelContainer.new(); prev_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; stack.add_child(prev_box)
	prev = RichTextLabel.new(); prev.bbcode_enabled = true; prev.selection_enabled = true; prev.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prev.custom_minimum_size = Vector2(100, 100); prev.meta_clicked.connect(_meta); prev.context_menu_enabled = true; prev_box.add_child(prev)
	graph = Graph.new(); graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL; graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.custom_minimum_size = Vector2(100, 100); graph.clip_contents = true; graph.visible = false
	graph.open_requested.connect(func(k: String): open_note(k)); stack.add_child(graph)
	empty = UI.empty_state("Aucune note ouverte", "Créez une note, ouvrez la note du jour ou choisissez un fichier dans la liste.")
	var eb := UI.button("Nouvelle note", true); eb.pressed.connect(func(): _new_flow()); empty.add_child(eb)
	var ed := UI.button("Note du jour"); ed.pressed.connect(func(): open_daily()); empty.add_child(ed)
	stack.add_child(empty)
	status = UI.small(""); status.clip_text = true; center.add_child(status)

func _apply_theme() -> void:
	var tx := UI.p("text"); var ac_c := UI.accent_text()
	var fld := UI.box(UI.p("field"), UI.rad(), UI.p("edge"), 1, UI.S3)
	edit_box.add_theme_stylebox_override("panel", UI.box(UI.p("field"), UI.rad(), UI.p("edge"), 1, 0))
	prev_box.add_theme_stylebox_override("panel", UI.box(UI.p("field"), UI.rad(), UI.p("edge"), 1, 0))
	var nb := UI.box(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, UI.S3)
	for st in ["normal", "focus", "read_only"]: edit.add_theme_stylebox_override(st, nb)
	prev.add_theme_stylebox_override("normal", nb); prev.add_theme_stylebox_override("focus", nb)
	fld = fld
	edit.add_theme_color_override("font_color", tx); edit.add_theme_color_override("caret_color", ac_c)
	edit.add_theme_color_override("current_line_color", Color(UI.accent(), 0.08)); edit.add_theme_color_override("selection_color", Color(UI.accent(), 0.35))
	edit.add_theme_color_override("font_placeholder_color", UI.p("muted"))
	edit.add_theme_font_size_override("font_size", 17)
	prev.add_theme_color_override("default_color", tx)
	for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]: prev.add_theme_font_size_override(k, 16)
	hl.c_text = tx; hl.c_head = ac_c; hl.c_link = ac_c; hl.c_code = UI.p("ok"); hl.c_quote = UI.p("muted"); hl.c_tag = UI.p("warn")
	hl.fence = []; edit.queue_redraw(); _side_btns()

# ------------------------------------------------------------------ disposition
func _toggle_left() -> void:
	left_on = not left_on
	if left_on and size.x < 700: right_on = false
	_layout()

func _toggle_right() -> void:
	right_on = not right_on
	if right_on and size.x < 700: left_on = false
	if right_on: _fill_links()
	_layout()

func _toggle_graph() -> void:
	show_graph = not show_graph
	if show_graph:
		_save_now(); graph.set_data(vault.graph(300), cur)
	_layout(); _fill_tabs()

func both_visible() -> bool:
	var cw := size.x - (230.0 if left_on else 0.0) - (250.0 if right_on else 0.0)
	return mode == 2 and size.x >= 700.0 and cw >= 520.0

func _layout() -> void:
	if left_p == null: return
	var narrow := size.x < 700.0
	left_p.visible = left_on
	right_p.visible = right_on and not (narrow and left_on)
	center.visible = not (narrow and (left_on or right_on))
	left_p.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL
	left_p.custom_minimum_size.x = 0 if narrow else 230
	right_p.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL
	var has := cur != ""
	var both := both_visible()
	edit_box.visible = has and not show_graph and (mode == 0 or both or mode == 2)
	prev_box.visible = has and not show_graph and (mode == 1 or both)
	graph.visible = show_graph
	empty.visible = not has and not show_graph
	tabs_sc.visible = not tabs.is_empty()
	b_back.disabled = hpos <= 0; b_fwd.disabled = hpos >= hist.size() - 1
	b_left.theme_type_variation = "Accent" if left_on else "Flat"; b_right.theme_type_variation = "Accent" if right_on else "Flat"
	b_graph.theme_type_variation = "Accent" if show_graph else "Flat"
	mode_opt.select(mode)
	if prev_box.visible: prev_t.start()

# ------------------------------------------------------------------ ouverture, enregistrement
func open_path(p: String) -> void:
	open_note(vault.key_for(p))

func open_note(key: String, push := true) -> void:
	if key == "": return
	if not FileAccess.file_exists(vault.abs_path(key)): _notify("Note introuvable", key); return
	_save_now()
	show_graph = false
	cur = key
	if not tabs.has(key): tabs.append(key)
	if push:
		hist = hist.slice(0, hpos + 1)
		if hist.is_empty() or hist.back() != key: hist.append(key)
		hpos = hist.size() - 1
	loading = true; edit.text = vault.read(key); edit.clear_undo_history(); edit.set_caret_line(0); edit.set_caret_column(0); loading = false
	dirty = false; hl.fence = []
	sel_dir = "" if vault.is_ext(key) else key.get_base_dir()
	_refresh_all()
	if edit.is_visible_in_tree(): edit.grab_focus()

func _notify(t: String, x := "") -> void:
	if m != null: m.notify(t, x)

func _save_now() -> void:
	if not dirty or cur == "": return
	dirty = false
	if not vault.write(cur, edit.text): _notify("Notes", "Enregistrement impossible : " + cur)
	_fill_links(); _update_status()

func _on_changed() -> void:
	if loading: return
	dirty = true; hl.fence = []; save_t.start(); prev_t.start(); _ac_update(); _update_status()

func _on_index() -> void:
	_fill_tree(); _fill_links(); _update_status()
	if show_graph: graph.set_data(vault.graph(300), cur)

func _refresh_all() -> void:
	_apply_theme(); _fill_tabs(); _select_in_tree(); _fill_links(); _render(); _update_status(); _layout()

func _update_status() -> void:
	if status == null: return
	if cur == "": status.text = "%d notes dans le coffre" % vault.notes.size(); return
	var p := Md.parse(edit.text)
	var s := "%s · %d mots" % [vault.name_of(cur), int(p["words"])]
	if int(p["tasks"][1]) > 0: s += " · tâches %d/%d" % [int(p["tasks"][0]), int(p["tasks"][1])]
	s += " · %d rétrolien(s)" % vault.backlinks(cur).size()
	s += " · modifié…" if dirty else " · enregistré"
	if vault.is_ext(cur): s += " · hors coffre"
	status.text = s

# ------------------------------------------------------------------ onglets, historique
func _fill_tabs() -> void:
	for c in tabs_box.get_children(): tabs_box.remove_child(c); c.queue_free()
	for k in tabs:
		var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 0); tabs_box.add_child(hb)
		var b := _btn(vault.name_of(k).left(22), func(): open_note(k), k, k == cur and not show_graph); hb.add_child(b)
		hb.add_child(_btn("×", func(): _close_tab(k), "Fermer", false, 32))

func _close_tab(k: String) -> void:
	if k == cur: _save_now()
	var i := tabs.find(k); tabs.erase(k)
	if k == cur:
		if tabs.is_empty(): cur = ""; loading = true; edit.text = ""; loading = false; dirty = false; _refresh_all()
		else: open_note(tabs[clampi(i, 0, tabs.size() - 1)])
	else: _fill_tabs()

func _nav(d: int) -> void:
	var i := hpos + d
	if i < 0 or i >= hist.size(): return
	hpos = i; open_note(hist[i], false)

# ------------------------------------------------------------------ liens internes
func open_link(target: String) -> void:
	var r: String = vault.resolve(target)
	if r == "":
		var nm := target.get_file()
		r = vault.create(target.get_base_dir() if target.contains("/") else "", nm, "# %s\n\n" % nm)
		if r == "": return
		_notify("Notes", "Note créée : " + vault.name_of(r))
		_fill_tree()
	open_note(r)

func open_daily(date := "") -> void:
	var r: String = vault.daily(date)
	_fill_tree(); open_note(r)

func show_tag(t: String) -> void:
	left_on = true; side_mode = 1; tag_focus = t
	if size.x < 700: right_on = false
	search.text = ""; _fill_tree(); _side_btns(); _layout()

func _meta(meta: Variant) -> void:
	var s := str(meta)
	if s.begins_with("note:"): open_link(s.substr(5))
	elif s.begins_with("task:"): _toggle_task(int(s.substr(5)))
	elif s.begins_with("tag:"): show_tag(s.substr(4))
	elif s.begins_with("http") and m != null and m._real(): OS.shell_open(s)

func _toggle_task(line: int) -> void:
	var t := Md.toggle_task(edit.text, line)
	if t == edit.text: return
	edit.set_line(line, t.split("\n")[line]); _on_changed(); _render()

## Lien [[...]] sous le curseur de l'éditeur (Ctrl+clic ou Ctrl+Entrée).
func link_at_caret() -> String:
	var s := edit.get_line(edit.get_caret_line()); var c := edit.get_caret_column()
	var a := s.rfind("[[", c); var b := s.find("]]", maxi(a, 0))
	if a < 0 or b < 0 or c > b + 1: return ""
	return Md.link_target(s.substr(a + 2, b - a - 2))

func _follow_caret() -> void:
	var t := link_at_caret()
	if t != "": open_link(t)

# ------------------------------------------------------------------ aperçu
func _md_opts() -> Dictionary:
	return {"size": 16, "accent": UI.accent_text(), "muted": UI.p("muted"), "code_bg": UI.p("win").lerp(UI.p("text"), 0.12), "broken": UI.err(),
		"hl": UI.p("win").lerp(UI.p("warn"), 0.4), "exists": func(t: String) -> bool: return vault.resolve(t) != ""}

func _tex(name: String) -> Texture2D:
	var p: String = vault.find_image(name.get_slice("|", 0), cur)
	if p == "": return null
	var mt := FileAccess.get_modified_time(p)
	if img_cache.has(p) and img_cache[p][0] == mt: return img_cache[p][1]
	var im := Image.load_from_file(p)
	if im == null or im.is_empty(): return null
	var t := ImageTexture.create_from_image(im); img_cache[p] = [mt, t]; return t

func _render() -> void:
	if prev == null or not prev_box.visible: return
	var keep := prev.get_v_scroll_bar().value
	var parts := Md.to_bbcode(edit.text, _md_opts()).split(Md.IMG_MARK)
	prev.clear()
	var maxw := maxi(120, int(prev.size.x) - 40)
	for i in parts.size():
		if i % 2 == 0: prev.append_text(parts[i]); continue
		var spec: String = parts[i].substr(4)
		var tex := _tex(spec)
		if tex == null: prev.append_text("[color=#%s][img introuvable : %s][/color]" % [UI.err().to_html(false), Md.esc(spec.get_slice("|", 0)).replace("[lb]", "(").replace("[rb]", ")")]); continue
		var w := mini(tex.get_width(), maxw)
		if spec.contains("|") and spec.get_slice("|", 1).strip_edges().is_valid_int(): w = mini(int(spec.get_slice("|", 1)), maxw)
		prev.add_image(tex, w, int(float(tex.get_height()) * w / tex.get_width()))
	prev.get_v_scroll_bar().value = keep
	prev.call_deferred("scroll_to_line", 0) if false else null

# ------------------------------------------------------------------ éditeur : touches, liste, autocomplétion
func _edit_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and ev.ctrl_pressed:
		call_deferred("_follow_caret"); return
	if not (ev is InputEventKey and ev.pressed): return
	var k: InputEventKey = ev
	if ac.visible:
		match k.keycode:
			KEY_DOWN: _ac_move(1); edit.accept_event(); return
			KEY_UP: _ac_move(-1); edit.accept_event(); return
			KEY_ENTER, KEY_KP_ENTER, KEY_TAB: _ac_accept(maxi(0, ac_list.get_selected_items()[0] if not ac_list.get_selected_items().is_empty() else 0)); edit.accept_event(); return
			KEY_ESCAPE: ac.visible = false; edit.accept_event(); return
	if (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
		if k.ctrl_pressed and link_at_caret() != "": _follow_caret(); edit.accept_event(); return
		if not k.shift_pressed and _list_continue(): edit.accept_event()

func _list_continue() -> bool:
	var ln := edit.get_caret_line(); var s := edit.get_line(ln)
	if edit.get_caret_column() != s.length() or edit.has_selection(): return false
	var rx := RegEx.create_from_string("^(\\s*)([-*+] \\[[ xX]\\] |[-*+] |(\\d+)\\. )(.*)$")
	var mt := rx.search(s)
	if mt == null: return false
	if mt.get_string(4).strip_edges() == "":
		edit.set_line(ln, ""); edit.set_caret_column(0); _on_changed(); return true
	var mk := mt.get_string(2)
	if mt.get_string(3) != "": mk = "%d. " % (int(mt.get_string(3)) + 1)
	elif mk.contains("["): mk = mk.substr(0, 2) + "[ ] "
	edit.insert_text_at_caret("\n" + mt.get_string(1) + mk); return true

func _ac_update() -> void:
	var ln := edit.get_caret_line(); var col := edit.get_caret_column()
	var pre := edit.get_line(ln).left(col); var i := pre.rfind("[[")
	if i < 0 or pre.substr(i).contains("]") or pre.substr(i + 2).contains("|") or pre.substr(i + 2).contains("#"): ac.visible = false; return
	var names: Array = vault.suggest(pre.substr(i + 2))
	if names.is_empty(): ac.visible = false; return
	ac_start = i + 2
	ac_list.clear()
	for n in names: ac_list.add_item(str(n))
	ac_list.select(0)
	ac_list.custom_minimum_size.y = mini(names.size(), 6) * 30 + 8
	ac.size = Vector2.ZERO
	var cp := edit.get_global_position() + edit.get_caret_draw_pos() - get_global_position() + Vector2(0, 8)
	cp.x = clampf(cp.x, 4.0, maxf(4.0, size.x - 240.0))
	if cp.y + ac_list.custom_minimum_size.y + 12 > size.y: cp.y -= ac_list.custom_minimum_size.y + 44
	ac.position = cp; ac.visible = true

func _ac_move(d: int) -> void:
	var cnt := ac_list.item_count
	if cnt == 0: return
	var sel := ac_list.get_selected_items(); var i: int = sel[0] if not sel.is_empty() else 0
	i = posmod(i + d, cnt); ac_list.select(i); ac_list.ensure_current_is_visible()

func _ac_accept(i: int) -> void:
	if i < 0 or i >= ac_list.item_count: ac.visible = false; return
	var name := ac_list.get_item_text(i)
	var ln := edit.get_caret_line(); var col := edit.get_caret_column()
	var after := edit.get_line(ln).substr(col)
	edit.begin_complex_operation()
	edit.remove_text(ln, ac_start, ln, col); edit.set_caret_column(ac_start)
	edit.insert_text_at_caret(name + ("" if after.begins_with("]]") else "]]"))
	if after.begins_with("]]"): edit.set_caret_column(edit.get_caret_column() + 2)
	edit.end_complex_operation()
	ac.visible = false; _on_changed(); edit.grab_focus()

# ------------------------------------------------------------------ arborescence
func _note_item(parent: TreeItem, p: String, label := "") -> TreeItem:
	var it := tree.create_item(parent); it.set_text(0, label if label != "" else vault.name_of(p)); it.set_metadata(0, {"k": "note", "p": p}); it.set_tooltip_text(0, p)
	if vault.is_fav(p): it.set_text(0, "★ " + it.get_text(0))
	items[p] = it; return it

func _add_dir(parent: TreeItem, rel: String, depth: int) -> void:
	var base: String = vault.root.path_join(rel) if rel != "" else vault.root
	var dirs := Array(DirAccess.get_directories_at(base)).filter(func(d): return not d.begins_with("."))
	dirs.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	for d in dirs:
		var p: String = rel.path_join(d) if rel != "" else d
		var it := tree.create_item(parent); it.set_text(0, "📁 " + d); it.set_metadata(0, {"k": "dir", "p": p})
		it.collapsed = not open_dirs.has(p) and not cur.begins_with(p + "/")
		items[p] = it
		if depth < 10: _add_dir(it, p, depth + 1)
	var files := Array(DirAccess.get_files_at(base)).filter(func(f): return f.get_extension().to_lower() == "md")
	files.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	for f in files: _note_item(parent, rel.path_join(f) if rel != "" else f)

func _fill_tree() -> void:
	if tree == null: return
	lock_tree = true
	tree.clear(); items = {}
	var rt := tree.create_item()
	var q := search.text.strip_edges()
	if q != "":
		for r in vault.search(q, 40):
			var it := _note_item(rt, r["p"], "%s — %s" % [vault.name_of(r["p"]), str(r["l"])] if str(r["l"]) != "" else vault.name_of(r["p"]))
			it.set_tooltip_text(0, r["p"])
		if rt.get_child_count() == 0:
			var e := tree.create_item(rt); e.set_text(0, "Aucun résultat"); e.set_selectable(0, false)
	elif side_mode == 1:
		var tg: Dictionary = vault.tags(); var ks := tg.keys(); ks.sort()
		if ks.is_empty():
			var e := tree.create_item(rt); e.set_text(0, "Aucune étiquette (#mot dans une note)"); e.set_selectable(0, false)
		for t in ks:
			var it := tree.create_item(rt); it.set_text(0, "#%s  (%d)" % [t, tg[t].size()]); it.set_metadata(0, {"k": "tag", "p": t})
			it.collapsed = t != tag_focus
			for p in tg[t]:
				var c := tree.create_item(it); c.set_text(0, vault.name_of(p)); c.set_metadata(0, {"k": "note", "p": p}); c.set_tooltip_text(0, p)
	else:
		var fv: Array = vault.favs().filter(func(p): return vault.notes.has(p))
		if not fv.is_empty():
			var h := tree.create_item(rt); h.set_text(0, "★ Favoris"); h.set_selectable(0, false)
			for p in fv: _note_item(h, p)
			var saved := items.duplicate(); items = {}
			_add_dir(rt, "", 0)
			for k in saved: if not items.has(k): items[k] = saved[k]
		else: _add_dir(rt, "", 0)
	lock_tree = false
	_select_in_tree()

func _select_in_tree() -> void:
	if tree == null or cur == "" or not items.has(cur): return
	lock_tree = true
	var it: TreeItem = items[cur]
	var par := it.get_parent()
	while par != null and par != tree.get_root(): par.collapsed = false; par = par.get_parent()
	it.select(0); lock_tree = false

func _tree_selected() -> void:
	var it := tree.get_selected()
	if it == null or lock_tree: return
	var d: Variant = it.get_metadata(0)
	if not (d is Dictionary): return
	match str(d["k"]):
		"note": open_note(str(d["p"]))
		"dir": sel_dir = str(d["p"]); it.collapsed = not it.collapsed
		"tag": tag_focus = str(d["p"]); it.collapsed = not it.collapsed

func _tree_collapsed(it: TreeItem) -> void:
	var d: Variant = it.get_metadata(0)
	if d is Dictionary and d["k"] == "dir":
		if it.collapsed: open_dirs.erase(d["p"])
		else: open_dirs[d["p"]] = true

func _tree_drag(pos: Vector2) -> Variant:
	var it := tree.get_item_at_position(pos)
	if it == null: return null
	var d: Variant = it.get_metadata(0)
	if not (d is Dictionary) or not (d["k"] == "note" or d["k"] == "dir"): return null
	var l := Label.new(); l.text = str(d["p"]).get_file(); tree.set_drag_preview(l)
	return {"notes_p": d["p"]}

func _drop_dir(pos: Vector2) -> Variant:
	var it := tree.get_item_at_position(pos)
	if it == null: return ""
	var d: Variant = it.get_metadata(0)
	if not (d is Dictionary): return null
	if d["k"] == "dir": return str(d["p"])
	if d["k"] == "note": return str(d["p"]).get_base_dir()
	return null

func _tree_can_drop(pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("notes_p") and _drop_dir(pos) != null

func _tree_drop(pos: Vector2, data: Variant) -> void:
	var dest: Variant = _drop_dir(pos)
	if dest == null: return
	_move_item(str(data["notes_p"]), str(dest))

func _move_item(p: String, dest: String) -> void:
	_save_now()
	var is_dir := DirAccess.dir_exists_absolute(vault.root.path_join(p))
	var np: String = vault.move(p, dest)
	if np == "": _notify("Notes", "Déplacement impossible (nom déjà pris ?)"); return
	if not is_dir:
		tabs = tabs.map(func(k): return np if k == p else k); hist = hist.map(func(k): return np if k == p else k)
		if cur == p: cur = np
	else:
		var f := func(k: String) -> String: return np + k.substr(p.length()) if k.begins_with(p + "/") else k
		tabs = tabs.map(f); hist = hist.map(f); cur = f.call(cur)
	_refresh_all(); _fill_tree()

# ------------------------------------------------------------------ actions sur l'élément choisi
func _target() -> Dictionary:
	var it := tree.get_selected() if tree != null else null
	if it != null and it.get_metadata(0) is Dictionary and it.get_metadata(0)["k"] in ["note", "dir"]: return it.get_metadata(0)
	if cur != "" and not vault.is_ext(cur): return {"k": "note", "p": cur}
	return {}

func _new_dir() -> void:
	_prompt("Nouveau dossier", "", func(n: String):
		var d: String = vault.mkdir(sel_dir, n)
		if d == "": _notify("Notes", "Nom de dossier invalide"); return
		open_dirs[d] = true; open_dirs[sel_dir] = true; _fill_tree())

func _rename_target() -> void:
	var t := _target()
	if t.is_empty(): return
	var p: String = t["p"]
	var isd: bool = t["k"] == "dir"
	_prompt("Renommer (les liens sont mis à jour)" if not isd else "Renommer le dossier", p.get_file().get_basename() if not isd else p.get_file(), func(n: String):
		_save_now()
		if isd:
			var np: String = vault.rename_dir(p, n)
			if np == "": _notify("Notes", "Renommage impossible"); return
			var f := func(k: String) -> String: return np + k.substr(p.length()) if k.begins_with(p + "/") else k
			tabs = tabs.map(f); hist = hist.map(f); cur = f.call(cur)
		else:
			var r: Dictionary = vault.rename(p, n)
			if r["p"] == "": _notify("Notes", "Renommage impossible (nom déjà pris ?)"); return
			var np2: String = r["p"]
			tabs = tabs.map(func(k): return np2 if k == p else k); hist = hist.map(func(k): return np2 if k == p else k)
			if cur == p:
				cur = np2
				loading = true; edit.text = vault.read(cur); loading = false
			elif cur != "":
				loading = true; var cl := edit.get_caret_line(); edit.text = vault.read(cur); edit.set_caret_line(cl); loading = false
			_notify("Notes", "%d note(s) mise(s) à jour" % int(r["n"]))
		_refresh_all(); _fill_tree())

func _delete_target() -> void:
	var t := _target()
	if t.is_empty(): return
	var p: String = t["p"]
	_confirm("Supprimer « %s » ? (placé dans .trash du coffre)" % p.get_file(), func():
		dirty = false if cur == p else dirty
		if vault.delete(p):
			for k in tabs.duplicate(): if k == p or k.begins_with(p + "/"): tabs.erase(k)
			hist = hist.filter(func(k): return k != p and not k.begins_with(p + "/"))
			hpos = hist.size() - 1
			if cur == p or cur.begins_with(p + "/"):
				cur = ""; loading = true; edit.text = ""; loading = false
				if not tabs.is_empty(): open_note(tabs.back())
			_refresh_all(); _fill_tree())

func _fav_target() -> void:
	var t := _target()
	if t.is_empty() or t["k"] != "note": return
	vault.toggle_fav(t["p"]); _fill_tree()

# ------------------------------------------------------------------ dialogues
func _dialog(title: String, wmin := 380) -> VBoxContainer:
	for c in dlg_host.get_children(): dlg_host.remove_child(c); c.queue_free()
	var pc := PanelContainer.new(); pc.add_theme_stylebox_override("panel", UI.card_box(UI.S4)); pc.custom_minimum_size.x = minf(float(wmin), maxf(200.0, size.x - 24.0))
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", UI.S3); pc.add_child(v)
	var h := UI.head(title); h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; h.custom_minimum_size.x = 10; v.add_child(h)
	dlg_host.add_child(pc); ov.visible = true; return v

func _close_dialog() -> void:
	ov.visible = false
	for c in dlg_host.get_children(): dlg_host.remove_child(c); c.queue_free()
	if cur != "" and edit.is_visible_in_tree(): edit.grab_focus()

func _prompt(title: String, def: String, cb: Callable) -> void:
	var v := _dialog(title)
	var le := LineEdit.new(); le.text = def; le.custom_minimum_size.y = UI.TOUCH; v.add_child(le)
	var go := func(): var t := le.text.strip_edges(); _close_dialog(); if t != "": cb.call(t)
	le.text_submitted.connect(func(_t: String): go.call())
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", UI.S2); v.add_child(hb)
	hb.add_child(_btn("Annuler", func(): _close_dialog())); hb.add_child(_btn("OK", go, "", true, 80))
	le.grab_focus(); le.select_all()

func _confirm(msg: String, cb: Callable) -> void:
	var v := _dialog("Confirmer"); v.add_child(UI.body(msg))
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", UI.S2); v.add_child(hb)
	hb.add_child(_btn("Annuler", func(): _close_dialog())); hb.add_child(_btn("Supprimer", func(): _close_dialog(); cb.call(), "", true, 100))

func _new_flow() -> void:
	var v := _dialog("Nouvelle note")
	var le := LineEdit.new(); le.placeholder_text = "Titre de la note"; le.custom_minimum_size.y = UI.TOUCH; v.add_child(le)
	var dir := sel_dir
	var mk := func(tpl: String):
		var t := le.text.strip_edges()
		if t == "": t = "Sans titre"
		_close_dialog()
		var r: String = vault.create(dir, t) if tpl == "" else vault.create_from_template(dir, t, tpl)
		if r != "": _fill_tree(); open_note(r)
	le.text_submitted.connect(func(_t: String): mk.call(""))
	v.add_child(UI.small("Modèle :"))
	var fl := UI.toolbar(); v.add_child(fl)
	fl.add_child(_btn("Vide", func(): mk.call(""), "", true))
	for t in vault.templates(): fl.add_child(_btn(str(t), func(): mk.call(t)))
	v.add_child(_btn("Annuler", func(): _close_dialog()))
	le.grab_focus()

func _vault_menu() -> void:
	var v := _dialog("Coffre")
	v.add_child(UI.note(vault.root + "  ·  %d notes" % vault.notes.size()))
	var add := func(t: String, cb: Callable):
		var b := _btn(t, func(): _close_dialog(); cb.call()); b.alignment = HORIZONTAL_ALIGNMENT_LEFT; v.add_child(b)
	add.call("Importer le Bloc-notes (Bloc-notes.md)", func():
		var r: String = vault.import_notepad()
		if r == "": _notify("Notes", "Aucun Bloc-notes à importer")
		else: _fill_tree(); open_note(r))
	add.call("Changer de coffre…", func(): _prompt("Dossier du coffre", vault.root, func(p: String): _set_vault(p)))
	add.call("Coffre par défaut (application)", func(): _set_vault(vault.default_root()))
	if OS.get_name() == "Linux": add.call("Utiliser ~/Notes", func(): _set_vault("~/Notes"))
	add.call("Réindexer", func(): vault.start_scan(); _notify("Notes", "Indexation en cours…"))
	add.call("Notes non liées", func(): _orphans())
	v.add_child(_btn("Fermer", func(): _close_dialog()))

func _set_vault(p: String) -> void:
	_save_now()
	if not vault.set_root(p): _notify("Notes", "Dossier inaccessible : " + p); return
	tabs = []; hist = []; hpos = -1; cur = ""; open_dirs = {}; loading = true; edit.text = ""; loading = false; dirty = false
	_fill_tree(); _refresh_all()
	if vault.notes.has("Bienvenue.md"): open_note("Bienvenue.md")

func _orphans() -> void:
	var v := _dialog("Notes non liées")
	var o: Array = vault.orphans()
	if o.is_empty(): v.add_child(UI.note("Toutes les notes sont liées."))
	var sc := ScrollContainer.new(); sc.custom_minimum_size.y = mini(o.size(), 8) * 44; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; v.add_child(sc)
	var lb := VBoxContainer.new(); lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(lb)
	for p in o:
		var b := _btn(vault.name_of(p), func(): _close_dialog(); open_note(p), p); b.alignment = HORIZONTAL_ALIGNMENT_LEFT; lb.add_child(b)
	v.add_child(_btn("Fermer", func(): _close_dialog()))

# ------------------------------------------------------------------ panneau des liens
func _fill_links() -> void:
	if links_box == null: return
	for c in links_box.get_children(): links_box.remove_child(c); c.queue_free()
	if cur == "":
		links_box.add_child(UI.note("Aucune note ouverte.")); return
	var info := Md.parse(edit.text)
	var fr: Dictionary = info["front"]
	if not fr.is_empty():
		var s := UI.section(links_box, "Propriétés")
		for k in fr: s.add_child(UI.note("%s : %s" % [k, ", ".join(fr[k]) if fr[k] is Array else str(fr[k])]))
	if not info["tags"].is_empty():
		var s := UI.section(links_box, "Étiquettes"); var fl := UI.toolbar(); s.add_child(fl)
		for t in info["tags"]: var b := _btn("#" + str(t), func(): show_tag(str(t))); fl.add_child(b)
	var bl: Array = vault.backlinks(cur)
	var sb := UI.section(links_box, "Rétroliens (%d)" % bl.size())
	if bl.is_empty(): sb.add_child(UI.note("Aucune note ne renvoie ici."))
	for p in bl:
		var b := _btn(vault.name_of(p), func(): open_note(p), p); b.alignment = HORIZONTAL_ALIGNMENT_LEFT; sb.add_child(b)
		var ctx: String = vault.link_context(p, vault.name_of(cur))
		if ctx != "": sb.add_child(UI.note(ctx))
	var ol: Array = info["links"]
	var so := UI.section(links_box, "Liens sortants (%d)" % ol.size())
	if ol.is_empty(): so.add_child(UI.note("Aucun lien [[...]]."))
	for t in ol:
		var ok: bool = vault.resolve(str(t)) != ""
		var b := _btn(str(t).get_file() + ("" if ok else "  (à créer)"), func(): open_link(str(t)), str(t)); b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if not ok: b.add_theme_color_override("font_color", UI.err())
		so.add_child(b)
	var orp: Array = vault.orphans()
	var sn := UI.section(links_box, "Non liées (%d)" % orp.size())
	for p in orp.slice(0, 8):
		var b := _btn(vault.name_of(p), func(): open_note(p), p); b.alignment = HORIZONTAL_ALIGNMENT_LEFT; sn.add_child(b)

# ------------------------------------------------------------------ raccourcis
func _input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed) or not is_visible_in_tree(): return
	if m != null and m.active != "notes": return
	var k: InputEventKey = ev
	if ov.visible:
		if k.keycode == KEY_ESCAPE: _close_dialog(); get_viewport().set_input_as_handled()
		return
	if not k.ctrl_pressed: return
	match k.keycode:
		KEY_D: open_daily()
		KEY_N: _new_flow()
		KEY_F: left_on = true; _layout(); search.grab_focus()
		KEY_G: _toggle_graph()
		KEY_E: mode = (mode + 1) % 3; _layout()
		KEY_S: _save_now()
		_: return
	get_viewport().set_input_as_handled()
