extends Control
## Calculatrice scientifique avec historique (hors ligne).

var expr := ""
var deg := true
var ans := 0.0
var disp: Label
var res: Label
var hist_box: VBoxContainer
var hist_arr: Array = []

# ---------- évaluateur (statique, testable) ----------
static func evaluate(s: String, use_deg := true, ans_v := 0.0) -> Variant:
	var p := {"s": s.replace("×", "*").replace("÷", "/").replace("−", "-").replace(",", ".").replace("π", "pi").replace("√", "sqrt").to_lower().replace(" ", ""), "i": 0, "deg": use_deg, "ans": ans_v, "err": ""}
	var v := _sum(p)
	if p.err != "" or p.i < p.s.length() or is_nan(v) or is_inf(v): return null
	return v

static func _peek(p: Dictionary) -> String:
	return p.s[p.i] if p.i < p.s.length() else ""

static func _sum(p: Dictionary) -> float:
	var v := _prod(p)
	while _peek(p) == "+" or _peek(p) == "-":
		var o := _peek(p); p.i += 1
		var r := _prod(p)
		v = v + r if o == "+" else v - r
	return v

static func _prod(p: Dictionary) -> float:
	var v := _unary(p)
	while true:
		var c := _peek(p)
		if c == "*" or c == "/":
			p.i += 1
			var r := _unary(p)
			if c == "/" and r == 0.0: p.err = "div0"; return 0.0
			v = v * r if c == "*" else v / r
		elif c == "(" or (c != "" and (c.is_valid_int() or c == "." or c.unicode_at(0) >= 97 and c.unicode_at(0) <= 122)):
			v *= _unary(p)   # multiplication implicite : 2pi, 3(4)
		else: break
	return v

static func _unary(p: Dictionary) -> float:
	if _peek(p) == "-": p.i += 1; return -_unary(p)
	if _peek(p) == "+": p.i += 1; return _unary(p)
	return _pow(p)

static func _pow(p: Dictionary) -> float:
	var b := _post(p)
	if _peek(p) == "^":
		p.i += 1
		var e := _unary(p)
		return pow(b, e)
	return b

static func _post(p: Dictionary) -> float:
	var v := _atom(p)
	while true:
		var c := _peek(p)
		if c == "!":
			p.i += 1
			if v < 0 or v > 170 or v != floor(v): p.err = "fact"; return 0.0
			var f := 1.0
			for k in range(2, int(v) + 1): f *= k
			v = f
		elif c == "%": p.i += 1; v /= 100.0
		else: break
	return v

static func _atom(p: Dictionary) -> float:
	var c := _peek(p)
	if c == "(":
		p.i += 1
		var v := _sum(p)
		if _peek(p) != ")": p.err = "paren"; return 0.0
		p.i += 1; return v
	if c != "" and (c.is_valid_int() or c == "."):
		var st: int = p.i
		while _peek(p) != "" and (_peek(p).is_valid_int() or _peek(p) == "."): p.i += 1
		# notation scientifique 1e5
		if _peek(p) == "e" and p.i + 1 < p.s.length() and (p.s[p.i + 1].is_valid_int() or ((p.s[p.i + 1] == "-" or p.s[p.i + 1] == "+") and p.i + 2 < p.s.length() and p.s[p.i + 2].is_valid_int())):
			p.i += 2
			while _peek(p) != "" and _peek(p).is_valid_int(): p.i += 1
		var t: String = p.s.substr(st, p.i - st)
		if not t.is_valid_float(): p.err = "num"; return 0.0
		return t.to_float()
	var st2: int = p.i
	while _peek(p) != "" and _peek(p).unicode_at(0) >= 97 and _peek(p).unicode_at(0) <= 122: p.i += 1
	var name: String = p.s.substr(st2, p.i - st2)
	match name:
		"pi": return PI
		"e": return exp(1.0)
		"ans": return p.ans
		"": p.err = "syn"; return 0.0
	if _peek(p) != "(": p.err = "fn"; return 0.0
	p.i += 1
	var a := _sum(p)
	if _peek(p) != ")": p.err = "paren"; return 0.0
	p.i += 1
	var k: float = PI / 180.0 if p.deg else 1.0
	match name:
		"sin": return sin(a * k)
		"cos": return cos(a * k)
		"tan": return tan(a * k)
		"asin": return asin(a) / k
		"acos": return acos(a) / k
		"atan": return atan(a) / k
		"ln": return log(a) if a > 0 else NAN
		"log": return log(a) / log(10.0) if a > 0 else NAN
		"sqrt": return sqrt(a) if a >= 0 else NAN
		"abs": return absf(a)
		"exp": return exp(a)
		"cbrt": return signf(a) * pow(absf(a), 1.0 / 3.0)
	p.err = "fn"; return 0.0

static func fmt(v: float) -> String:
	if v == floor(v) and absf(v) < 1e15: return str(int(v))
	var s := "%.10g" % v
	return s

# ---------- interface ----------
func _ready() -> void:
	var root := HBoxContainer.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8); add_child(root)
	var left := VBoxContainer.new(); left.size_flags_horizontal = Control.SIZE_EXPAND_FILL; left.add_theme_constant_override("separation", 4); root.add_child(left)
	disp = Label.new(); disp.add_theme_font_size_override("font_size", 22); disp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	disp.clip_text = true; disp.custom_minimum_size.y = 36; left.add_child(disp)
	res = Label.new(); res.add_theme_font_size_override("font_size", 34); res.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	res.clip_text = true; res.custom_minimum_size.y = 50; left.add_child(res)
	var g := GridContainer.new(); g.columns = 5; g.size_flags_vertical = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 4); g.add_theme_constant_override("v_separation", 4); left.add_child(g)
	var keys := ["sin(", "cos(", "tan(", "ln(", "log(",
		"asin(", "acos(", "atan(", "√(", "^",
		"(", ")", "π", "e", "!",
		"7", "8", "9", "÷", "C",
		"4", "5", "6", "×", "⌫",
		"1", "2", "3", "−", "Ans",
		"0", ".", "%", "+", "="]
	for k in keys:
		var b := Button.new(); b.text = k.trim_suffix("(") if k.length() > 1 and k != "Ans" else k
		b.custom_minimum_size = Vector2(44, 44); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_key.bind(k)); g.add_child(b)
	var mode := Button.new(); mode.text = "Degrés"; mode.toggle_mode = true; mode.button_pressed = true; mode.custom_minimum_size.y = 44; mode.focus_mode = Control.FOCUS_NONE
	mode.toggled.connect(func(on): deg = on; mode.text = "Degrés" if on else "Radians"; _live()); left.add_child(mode)
	var right := VBoxContainer.new(); right.custom_minimum_size.x = 170; root.add_child(right)
	var hl := Label.new(); hl.text = "Historique"; right.add_child(hl)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; right.add_child(sc)
	hist_box = VBoxContainer.new(); hist_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(hist_box)
	var cl := Button.new(); cl.text = "Effacer l'historique"; cl.custom_minimum_size.y = 44; cl.pressed.connect(func(): hist_arr.clear(); _save(); _rebuild_hist()); right.add_child(cl)
	_load(); _rebuild_hist(); _live()

func _key(k: String) -> void:
	match k:
		"C": expr = ""
		"⌫": expr = expr.substr(0, expr.length() - 1)
		"=": _equals(); return
		"Ans": expr += "ans"
		_: expr += k
	_live()

func _live() -> void:
	disp.text = expr
	var v: Variant = evaluate(expr, deg, ans) if expr != "" else null
	res.text = fmt(v) if v != null else ""

func _equals() -> void:
	var v: Variant = evaluate(expr, deg, ans)
	if v == null: res.text = "Erreur"; return
	ans = v
	hist_arr.append([expr, fmt(v)]); if hist_arr.size() > 60: hist_arr.pop_front()
	_save(); _rebuild_hist()
	expr = fmt(v); _live()

func _rebuild_hist() -> void:
	for c in hist_box.get_children(): c.queue_free()
	for i in range(hist_arr.size() - 1, -1, -1):
		var e: Array = hist_arr[i]
		var b := Button.new(); b.text = "%s\n= %s" % [e[0], e[1]]; b.alignment = HORIZONTAL_ALIGNMENT_RIGHT; b.clip_text = true
		b.custom_minimum_size.y = 44; b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): expr = e[1]; _live()); hist_box.add_child(b)

func _save() -> void:
	var f := FileAccess.open("user://calc_hist.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(hist_arr))

func _load() -> void:
	if not FileAccess.file_exists("user://calc_hist.json"): return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://calc_hist.json"))
	if d is Array: hist_arr = d
