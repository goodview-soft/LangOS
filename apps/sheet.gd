extends Control
const UI = preload("res://apps/ui.gd")
## Tableur : grille virtualisée (dessin des cellules visibles), formules avec parseur maison (aucun eval), CSV, graphique.
## Le moteur (set_cell / value / to_csv / from_csv) fonctionne sans interface ; build() ajoute l'UI.
var m
const COLS := 26
const ROWS := 200
const CW := 96.0
const RH := 30.0
const HW := 46.0
var cells := {}            # "A1" -> texte brut
var cache := {}
var _stack := []
var _cyc := false
# parseur
var _t: Array = []
var _i := 0
var _err := false
# interface
var sel := Vector2i(0, 0)
var off := Vector2i(0, 0)
var grid: Control
var fbar: LineEdit
var fname: LineEdit
var chart_box: Control
var chart_rng: LineEdit
var chart_kind := 0
var info: Label

# ------------------------------------------------------------------ moteur
static func col_name(c: int) -> String: return char(65 + c)
static func key(c: int, r: int) -> String: return "%s%d" % [col_name(c), r + 1]
## "B12" -> Vector2i(col, ligne) ou (-1,-1)
static func parse_ref(s: String) -> Vector2i:
	var u := s.to_upper()
	if u.length() < 2 or u.length() > 4: return Vector2i(-1, -1)
	var c := u.unicode_at(0) - 65
	var n := u.substr(1)
	if c < 0 or c >= COLS or not n.is_valid_int(): return Vector2i(-1, -1)
	var r := int(n) - 1
	if r < 0 or r >= ROWS: return Vector2i(-1, -1)
	return Vector2i(c, r)

func set_cell(k: String, raw: String) -> void:
	if raw == "": cells.erase(k)
	else: cells[k] = raw
	cache.clear()

## Valeur affichable/numérique d'une cellule (float, String ou "#ERR", "#CYCLE").
func value(k: String) -> Variant:
	if cache.has(k): return cache[k]
	var raw: String = cells.get(k, "")
	var v: Variant
	if raw.begins_with("="):
		if _stack.has(k): _cyc = true; return "#CYCLE"
		_stack.append(k)
		v = calc(raw.substr(1))
		_stack.pop_back()
		if _stack.is_empty(): _cyc = false
	elif raw.is_valid_float() and raw.strip_edges() != "": v = float(raw)
	else: v = raw
	cache[k] = v
	return v

## Évalue une expression (sans le « = »). Retourne float / String / bool, ou "#ERR".
func calc(expr: String) -> Variant:
	var saved := [_t, _i, _err]
	_t = _tokens(expr); _i = 0; _err = false
	var v: Variant = "#ERR"
	if not _t.is_empty():
		v = _cmp()
		if _err: v = v if v is String and v.begins_with("#") else "#ERR"
		elif _i < _t.size() or v is Array: v = "#ERR"
	if v is String and v == "#ERR" and _cyc: v = "#CYCLE"
	_t = saved[0]; _i = saved[1]; _err = saved[2]
	return v

func _tokens(s: String) -> Array:
	var out := []
	var i := 0
	var n := s.length()
	while i < n:
		var ch := s[i]
		if ch == " " or ch == "\t": i += 1; continue
		var j := i
		if ch >= "0" and ch <= "9" or ch == ".":
			while j < n and (s[j] >= "0" and s[j] <= "9" or s[j] == "."): j += 1
			var ns := s.substr(i, j - i)
			if not ns.is_valid_float(): return []
			out.append(["n", float(ns)])
		elif ch == '"':
			j = s.find('"', i + 1)
			if j < 0: return []
			out.append(["s", s.substr(i + 1, j - i - 1)]); j += 1
		elif ch.to_upper() >= "A" and ch.to_upper() <= "Z" and ch.unicode_at(0) < 128:
			while j < n and (s[j].unicode_at(0) < 128 and (s[j].to_upper() >= "A" and s[j].to_upper() <= "Z" or s[j] >= "0" and s[j] <= "9")): j += 1
			out.append(["i", s.substr(i, j - i).to_upper()])
		elif i + 1 < n and s.substr(i, 2) in ["<>", "<=", ">="]:
			out.append(["o", s.substr(i, 2)]); j = i + 2
		elif ch in "+-*/^()<>=,:&;":
			out.append(["o", ch]); j = i + 1
		else: return []
		i = j
	return out

func _peek_op(o: String) -> bool: return _i < _t.size() and _t[_i][0] == "o" and _t[_i][1] == o
func _num(v: Variant) -> float:
	if v is bool: return 1.0 if v else 0.0
	if v is float or v is int: return float(v)
	if v is String:
		if v.begins_with("#"): _err = true
		elif v == "": return 0.0
		elif v.is_valid_float(): return float(v)
		else: _err = true
	else: _err = true
	return 0.0

func _cmp() -> Variant:
	var a: Variant = _add()
	while not _err and _i < _t.size() and _t[_i][0] == "o" and _t[_i][1] in ["=", "<>", "<", ">", "<=", ">="]:
		var o: String = _t[_i][1]; _i += 1
		var b: Variant = _add()
		if a is Array or b is Array: _err = true; return "#ERR"
		var x: Variant = a; var y: Variant = b
		if (a is String) != (b is String): x = str(a); y = str(b)
		match o:
			"=": a = x == y
			"<>": a = x != y
			"<": a = x < y
			">": a = x > y
			"<=": a = x <= y
			">=": a = x >= y
	return a

func _add() -> Variant:
	var a: Variant = _mul()
	while not _err and (_peek_op("+") or _peek_op("-") or _peek_op("&")):
		var o: String = _t[_i][1]; _i += 1
		var b: Variant = _mul()
		if a is Array or b is Array: _err = true; return "#ERR"
		if o == "&": a = _txt(a) + _txt(b)
		else:
			var x := _num(a); var y := _num(b)
			a = x + y if o == "+" else x - y
	return a

func _txt(v: Variant) -> String:
	if v is float and v == floorf(v) and absf(v) < 1e15: return str(int(v))
	return str(v)

func _mul() -> Variant:
	var a: Variant = _pow()
	while not _err and (_peek_op("*") or _peek_op("/")):
		var o: String = _t[_i][1]; _i += 1
		var b: Variant = _pow()
		if a is Array or b is Array: _err = true; return "#ERR"
		var x := _num(a); var y := _num(b)
		if o == "/":
			if y == 0.0: _err = true; return "#DIV/0"
			a = x / y
		else: a = x * y
	return a

func _pow() -> Variant:
	var a: Variant = _unary()
	if not _err and _peek_op("^"):
		_i += 1
		var b: Variant = _pow()
		if a is Array or b is Array: _err = true; return "#ERR"
		var r := pow(_num(a), _num(b))
		if is_nan(r) or is_inf(r): _err = true; return "#ERR"
		return r
	return a

func _unary() -> Variant:
	if _peek_op("-"):
		_i += 1
		var v: Variant = _unary()
		if v is Array: _err = true; return "#ERR"
		return -_num(v)
	if _peek_op("+"): _i += 1; return _unary()
	return _atom()

func _atom() -> Variant:
	if _i >= _t.size(): _err = true; return "#ERR"
	var tk: Array = _t[_i]; _i += 1
	match tk[0]:
		"n", "s": return tk[1]
		"o":
			if tk[1] == "(":
				var v: Variant = _cmp()
				if not _peek_op(")"): _err = true; return "#ERR"
				_i += 1; return v
			_err = true; return "#ERR"
		"i":
			var id: String = tk[1]
			if _peek_op("("): _i += 1; return _func(id)
			if id == "TRUE": return true
			if id == "FALSE": return false
			var p := parse_ref(id)
			if p.x < 0: _err = true; return "#ERR"
			if _peek_op(":"):
				_i += 1
				if _i >= _t.size() or _t[_i][0] != "i": _err = true; return "#ERR"
				var q := parse_ref(_t[_i][1]); _i += 1
				if q.x < 0: _err = true; return "#ERR"
				var out := []
				for r in range(mini(p.y, q.y), maxi(p.y, q.y) + 1):
					for c in range(mini(p.x, q.x), maxi(p.x, q.x) + 1):
						var cv: Variant = value(key(c, r))
						if cv is String and cv.begins_with("#"): _err = true; return cv
						out.append(cv)
				return out
			var cv: Variant = value(id)
			if cv is String and cv.begins_with("#"): _err = true
			return cv if not _err else "#ERR"
	_err = true; return "#ERR"

func _func(name: String) -> Variant:
	var args := []
	if not _peek_op(")"):
		while true:
			args.append(_cmp())
			if _err: return "#ERR"
			if _peek_op(",") or _peek_op(";"): _i += 1; continue
			break
	if not _peek_op(")"): _err = true; return "#ERR"
	_i += 1
	if name == "IF":
		if args.size() < 2 or args.size() > 3 or args[0] is Array: _err = true; return "#ERR"
		var c = args[0]
		var ok: bool = (_num(c) != 0.0) if not (c is String) else c != ""
		return args[1] if ok else (args[2] if args.size() > 2 else false)
	var nums := []
	var cnt := 0
	for a in args:
		for v in (a if a is Array else [a]):
			if v is String:
				if v == "": continue
				if v.is_valid_float(): nums.append(float(v)); cnt += 1
				elif a is Array: continue      # texte dans une plage : ignoré
				else: _err = true; return "#ERR"
			else: nums.append(_num(v)); cnt += 1
	match name:
		"SUM": return nums.reduce(func(s, x): return s + x, 0.0)
		"AVG", "AVERAGE":
			if nums.is_empty(): _err = true; return "#DIV/0"
			return nums.reduce(func(s, x): return s + x, 0.0) / nums.size()
		"MIN": return nums.min() if not nums.is_empty() else 0.0
		"MAX": return nums.max() if not nums.is_empty() else 0.0
		"COUNT": return float(cnt)
	_err = true; return "#ERR"

func show_val(k: String) -> String:
	var v: Variant = value(k)
	if v is float: return str(snappedf(v, 0.0001)) if v != floorf(v) else str(int(v)) if absf(v) < 1e15 else str(v)
	if v is bool: return "VRAI" if v else "FAUX"
	return str(v)

# ---- CSV (valeurs brutes, séparateur « , »)
func to_csv() -> String:
	var mr := 0; var mc := 0
	for k in cells:
		var p := parse_ref(k); mr = maxi(mr, p.y + 1); mc = maxi(mc, p.x + 1)
	var lines := []
	for r in mr:
		var row := []
		for c in mc:
			var t: String = cells.get(key(c, r), "")
			if t.contains(",") or t.contains('"') or t.contains("\n"): t = '"' + t.replace('"', '""') + '"'
			row.append(t)
		lines.append(",".join(row))
	return "\n".join(lines)

func from_csv(s: String) -> void:
	cells.clear(); cache.clear()
	var r := 0; var c := 0; var f := ""; var q := false; var i := 0
	var n := s.length()
	while i < n:
		var ch := s[i]
		if q:
			if ch == '"':
				if i + 1 < n and s[i + 1] == '"': f += '"'; i += 1
				else: q = false
			else: f += ch
		elif ch == '"': q = true
		elif ch == "," or ch == "\n":
			if f != "" and r < ROWS and c < COLS: cells[key(c, r)] = f
			f = ""
			if ch == ",": c += 1
			else: r += 1; c = 0
		elif ch != "\r": f += ch
		i += 1
	if f != "" and r < ROWS and c < COLS: cells[key(c, r)] = f

func save_json(p: String) -> bool:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(cells)); return true

func load_json(p: String) -> bool:
	if not FileAccess.file_exists(p): return false
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not d is Dictionary: return false
	cells.clear(); cache.clear()
	for k in d: if parse_ref(k).x >= 0: cells[k] = str(d[k])
	return true

## Valeurs numériques d'une plage "A1:A5" pour le graphique.
func range_nums(rng: String) -> Array:
	var v: Variant = calc(rng.strip_edges().to_upper())
	var out := []
	if v is float: return [v]
	var parts := rng.strip_edges().to_upper().split(":")
	if parts.size() != 2: return out
	var p := parse_ref(parts[0]); var q := parse_ref(parts[1])
	if p.x < 0 or q.x < 0: return out
	for r in range(mini(p.y, q.y), maxi(p.y, q.y) + 1):
		for c in range(mini(p.x, q.x), maxi(p.x, q.x) + 1):
			var x: Variant = value(key(c, r))
			if x is float: out.append(x)
	return out

# ------------------------------------------------------------------ interface
func _c(k: String) -> Color: return m._p(k) if m else Color("232834")

func build() -> void:
	var vb := VBoxContainer.new(); vb.set_anchors_preset(Control.PRESET_FULL_RECT); vb.add_theme_constant_override("separation", 6); add_child(vb)
	var top := UI.toolbar(); vb.add_child(top)
	fname = LineEdit.new(); fname.text = "tableau"; fname.custom_minimum_size = Vector2(120, 40); top.add_child(fname)
	for b in [["Enreg.", _save], ["Ouvrir", _open], ["Export CSV", _exp], ["Import CSV", _imp], ["Graphique", _toggle_chart]]:
		var bt := Button.new(); bt.text = b[0]; bt.custom_minimum_size.y = 40; bt.pressed.connect(b[1]); top.add_child(bt)
	fbar = LineEdit.new(); fbar.placeholder_text = "Valeur ou formule (=SUM(A1:A5))"; fbar.custom_minimum_size.y = 40
	fbar.text_submitted.connect(_commit); vb.add_child(fbar)
	grid = Control.new(); grid.size_flags_vertical = Control.SIZE_EXPAND_FILL; grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.clip_contents = true; grid.focus_mode = Control.FOCUS_CLICK
	grid.draw.connect(_draw_grid); grid.gui_input.connect(_grid_input); grid.resized.connect(grid.queue_redraw); vb.add_child(grid)
	var cr := HBoxContainer.new(); cr.add_theme_constant_override("separation", 4); vb.add_child(cr)
	chart_rng = LineEdit.new(); chart_rng.text = "A1:A10"; chart_rng.custom_minimum_size.y = 36; chart_rng.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart_rng.text_submitted.connect(func(_t): chart_box.queue_redraw()); cr.add_child(chart_rng)
	var kb := Button.new(); kb.text = "Barres / courbe"; kb.pressed.connect(func(): chart_kind = 1 - chart_kind; chart_box.queue_redraw()); cr.add_child(kb)
	info = Label.new(); cr.add_child(info)
	chart_box = Control.new(); chart_box.custom_minimum_size.y = 170; chart_box.draw.connect(_draw_chart); vb.add_child(chart_box)
	chart_box.visible = false; cr.visible = false; chart_rng.set_meta("row", cr)
	_sel(Vector2i(0, 0))

func _toggle_chart() -> void:
	chart_box.visible = not chart_box.visible; chart_rng.get_meta("row").visible = chart_box.visible
	chart_box.queue_redraw()

func _path() -> String: return "user://%s" % fname.text.strip_edges().get_file().get_basename()
func _msg(t: String) -> void: info.text = t; if m: m.notify("Tableur", t)
func _save() -> void: _msg("Enregistré : " + _path() + ".json" if save_json(_path() + ".json") else "Échec de l'enregistrement")
func _open() -> void:
	if load_json(_path() + ".json"): _msg("Ouvert"); _sel(Vector2i(0, 0)); grid.queue_redraw()
	else: _msg("Fichier introuvable")
func _exp() -> void:
	var f := FileAccess.open(_path() + ".csv", FileAccess.WRITE)
	if f: f.store_string(to_csv()); _msg("CSV : " + _path() + ".csv")
func _imp() -> void:
	if not FileAccess.file_exists(_path() + ".csv"): _msg("CSV introuvable"); return
	from_csv(FileAccess.get_file_as_string(_path() + ".csv")); _msg("CSV importé"); grid.queue_redraw()

## Ouvre un .csv / .json (depuis Fichiers).
func open_path(p: String) -> void:
	if p.get_extension().to_lower() == "csv": from_csv(FileAccess.get_file_as_string(p))
	else: load_json(p)
	grid.queue_redraw()

func _sel(p: Vector2i) -> void:
	sel = Vector2i(clampi(p.x, 0, COLS - 1), clampi(p.y, 0, ROWS - 1))
	var vc := int((grid.size.x - HW) / CW); var vr := int((grid.size.y - RH) / RH)
	if sel.x < off.x: off.x = sel.x
	elif sel.x >= off.x + vc and vc > 0: off.x = sel.x - vc + 1
	if sel.y < off.y: off.y = sel.y
	elif sel.y >= off.y + vr and vr > 0: off.y = sel.y - vr + 1
	fbar.text = cells.get(key(sel.x, sel.y), ""); grid.queue_redraw()

func _commit(t: String) -> void:
	set_cell(key(sel.x, sel.y), t); _sel(sel + Vector2i(0, 1)); chart_box.queue_redraw()

func _grid_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_DOWN: off.y = clampi(off.y + (3 if not e.shift_pressed else 0), 0, ROWS - 1); off.x = clampi(off.x + (1 if e.shift_pressed else 0), 0, COLS - 1); grid.queue_redraw()
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP: off.y = clampi(off.y - (3 if not e.shift_pressed else 0), 0, ROWS - 1); off.x = clampi(off.x - (1 if e.shift_pressed else 0), 0, COLS - 1); grid.queue_redraw()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			grid.grab_focus()
			var c := off.x + int((e.position.x - HW) / CW); var r := off.y + int((e.position.y - RH) / RH)
			if e.position.x >= HW and e.position.y >= RH: _sel(Vector2i(c, r))
	elif e is InputEventKey and e.pressed:
		var d := Vector2i.ZERO
		match e.keycode:
			KEY_UP: d = Vector2i(0, -1)
			KEY_DOWN: d = Vector2i(0, 1)
			KEY_LEFT: d = Vector2i(-1, 0)
			KEY_RIGHT, KEY_TAB: d = Vector2i(1, 0)
			KEY_DELETE: set_cell(key(sel.x, sel.y), ""); _sel(sel); return
			KEY_F2, KEY_ENTER: fbar.grab_focus(); return
		if d != Vector2i.ZERO: _sel(sel + d); grid.accept_event()

func _draw_grid() -> void:
	var f := get_theme_default_font(); var fs := 15
	var sz := grid.size
	grid.draw_rect(Rect2(Vector2.ZERO, sz), _c("field"))
	var edge: Color = _c("edge"); var txt: Color = _c("text"); var head := _c("win")
	var vc := int(ceil((sz.x - HW) / CW)); var vr := int(ceil((sz.y - RH) / RH))
	for ci in vc:
		var c := off.x + ci
		if c >= COLS: break
		var x := HW + ci * CW
		grid.draw_rect(Rect2(x, 0, CW, RH), head)
		grid.draw_string(f, Vector2(x + CW / 2 - 4, RH - 9), col_name(c), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt)
		grid.draw_line(Vector2(x, 0), Vector2(x, sz.y), edge)
	for ri in vr:
		var r := off.y + ri
		if r >= ROWS: break
		var y := RH + ri * RH
		grid.draw_rect(Rect2(0, y, HW, RH), head)
		grid.draw_string(f, Vector2(6, y + RH - 9), str(r + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt)
		grid.draw_line(Vector2(0, y), Vector2(sz.x, y), edge)
		for ci in vc:
			var c := off.x + ci
			if c >= COLS: break
			var k := key(c, r)
			if not cells.has(k): continue
			var v: Variant = value(k)
			var col := txt
			if v is String and v.begins_with("#"): col = _c("err")
			var s := show_val(k)
			var al := HORIZONTAL_ALIGNMENT_RIGHT if v is float else HORIZONTAL_ALIGNMENT_LEFT
			grid.draw_string(f, Vector2(HW + ci * CW + 4, y + RH - 9), s, al, CW - 8, fs, col)
	var sx := HW + (sel.x - off.x) * CW; var sy := RH + (sel.y - off.y) * RH
	grid.draw_rect(Rect2(sx, sy, CW, RH), Color(m.ACCENT if m else Color("5aa2ff")), false, 2.0)
	grid.draw_rect(Rect2(0, 0, HW, RH), head)

func _draw_chart() -> void:
	var sz := chart_box.size
	chart_box.draw_rect(Rect2(Vector2.ZERO, sz), _c("field"))
	var vals := range_nums(chart_rng.text)
	if vals.is_empty(): return
	var mx := 0.0; var mn := 0.0
	for v in vals: mx = maxf(mx, v); mn = minf(mn, v)
	if mx == mn: mx = mn + 1.0
	var n := vals.size(); var w := (sz.x - 20.0) / n
	var col: Color = m.ACCENT if m else Color("5aa2ff")
	var base := 10.0 + (sz.y - 20.0) * mx / (mx - mn)
	var pts := PackedVector2Array()
	for i in n:
		var y: float = 10.0 + (sz.y - 20.0) * (mx - vals[i]) / (mx - mn)
		if chart_kind == 0: chart_box.draw_rect(Rect2(10 + i * w + 2, minf(y, base), maxf(w - 4, 1.0), absf(base - y)), col)
		else: pts.append(Vector2(10 + (i + 0.5) * w, y))
	if chart_kind == 1 and pts.size() > 1: chart_box.draw_polyline(pts, col, 2.5, true)
	if chart_kind == 1: for p in pts: chart_box.draw_circle(p, 3.5, col)
	chart_box.draw_line(Vector2(10, base), Vector2(sz.x - 10, base), _c("edge"))
