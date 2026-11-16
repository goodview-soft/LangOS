class_name KaraokeView
extends Control
## Paroles façon éditeur vidéo : ligne en cours centrée en grand, mot par mot surligné (balayage de lettres),
## traduction sous chaque ligne, défilement fluide. Clic sur un mot : dictionnaire ; clic ailleurs sur une ligne : aller à cette ligne.

signal word_clicked(word: String, line: int)
signal seek_requested(t: float)

const UI = preload("res://apps/ui.gd")
# Couleurs suivant le thème (clair ou sombre)
var GOLD: Color:
	get: return UI.p("warn")
var GREEN: Color:
	get: return UI.p("ok")
var CYAN: Color:
	get: return UI.accent()

var lines: Array = []
var trans: Dictionary = {}
var show_tr := true
var compact := false   # mode overlay : seulement la ligne en cours + traduction, sur fond translucide
var gloss_fn: Callable = Callable()   # mot -> traduction courte (dictionnaire hors ligne) pour les mots sans traduction IA
var _fb := {}
var known := {}   # mots déjà sauvegardés (formes nettoyées) : soulignés en or
var t := 0.0
var idx := -1
var title := ""
var scroll_y := 0.0
var _cache := {}
var _hits: Array = []        # {rect, word, line}
var _line_rects: Array = []  # {rect, line}
var _wt: Array = []          # [début, fin] par mot de la ligne courante
var _wt_idx := -2
var _csize := Vector2.ZERO


func set_data(l: Array, tr: Dictionary) -> void:
	lines = l; trans = tr; _cache.clear(); _wt_idx = -2; _ver += 1
	queue_redraw()


func set_time(time: float) -> void:
	t = time
	var i := -1
	for k in lines.size():
		if lines[k][0] <= t: i = k
		else: break
	idx = i


var redraw_hz := 30.0       # le dessin est limité (économie de CPU) : 30 images/s suffisent pour le karaoké
var _acc := 0.0
var _ver := 0
var _sig := ""
var _blocks: Array = []
var _pill := StyleBoxFlat.new()
var _chip := StyleBoxFlat.new()
var _bgbox := StyleBoxFlat.new()


func _process(d: float) -> void:
	if not is_visible_in_tree(): return
	_acc += d
	if _acc < 1.0 / redraw_hz: return
	scroll_y += (_target - scroll_y) * minf(1.0, _acc * 7.0)
	_acc = 0.0
	queue_redraw()


var _target := 0.0


func _font() -> Font:
	return get_theme_default_font()


func _big() -> int:
	if compact: return int(clampf(size.y / 9.5, 16, 28))
	return int(clampf(minf(size.y / 7.5, size.x / 14.0), 26, 66))


func _sz(rel: int) -> int:
	var b := _big()
	if rel == 0: return b
	return int(b * (0.62 if abs(rel) == 1 else 0.52))


## Découpe en lignes d'affichage : Array de Array d'indices de mots.
func _wrap(words: PackedStringArray, fs: int, maxw: float) -> Array:
	var f := _font()
	var rows := []; var cur := []; var w := 0.0
	var sp := f.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	for i in words.size():
		var ww := f.get_string_size(words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if not cur.is_empty() and w + sp + ww > maxw:
			rows.append(cur); cur = []; w = 0.0
		cur.append(i); w += ww + (sp if not cur.is_empty() and cur.size() > 1 else 0.0)
	if not cur.is_empty(): rows.append(cur)
	return rows


func _word_times(k: int) -> void:
	if _wt_idx == k: return
	_wt_idx = k; _wt = []
	var txt: String = str(lines[k][1])
	var words := txt.split(" ", false)
	var t0: float = lines[k][0]
	var t1: float = lines[k + 1][0] if k + 1 < lines.size() else t0 + 5.0
	var span := minf(t1 - t0, maxf(1.0, txt.length() * 0.095 + 0.6))
	var tot := 0.0
	for w in words: tot += maxf(2.0, float(w.length()))
	var acc := 0.0
	for w in words:
		var l := maxf(2.0, float(w.length()))
		_wt.append([t0 + span * acc / tot, t0 + span * (acc + l) / tot]); acc += l


## Mot en cours de chant (selon le temps estimé de chaque mot de la ligne). "" si rien.
func current_word_text() -> String:
	if idx < 0 or idx >= lines.size(): return ""
	_word_times(idx)
	var words := str(lines[idx][1]).split(" ", false)
	var w := ""
	for i in words.size():
		if i < _wt.size() and t >= _wt[i][0]: w = words[i]
	if w == "" and not words.is_empty(): w = words[0]
	return w.strip_edges().lstrip("¡¿\"'(").rstrip(".,;:!?\"')…")


func _clean(w: String) -> String:
	return w.strip_edges().trim_prefix("¡").trim_prefix("¿").lstrip("\"'(").rstrip(".,;:!?\"')…").to_lower()


## Mise en page (coûteuse : mesure de tous les mots) : recalculée seulement quand la ligne, la taille ou les données changent.
func _layout() -> void:
	var f := _font()
	_blocks = []
	var cur := maxi(idx, 0)
	var k0 := maxi(cur - 2, 0)
	var k1 := mini(lines.size() - 1, cur + 6)
	if compact:
		k0 = maxi(cur - 1, 0); k1 = mini(lines.size() - 1, cur + 2)
	var maxw := size.x * 0.9
	var y := 0.0
	var cur_center := 0.0
	for k in range(k0, k1 + 1):
		var rel := k - idx if idx >= 0 else k
		var fs := _sz(0 if k == cur else rel)
		var txt: String = str(lines[k][1])
		if txt == "": txt = "♪"
		var words := txt.split(" ", false)
		var rows: Array = _wrap(words, fs, maxw)
		var lh := fs * 1.28
		var glm := {}
		for w in trans.get(k, {}).get("words", []):
			var cw := _clean(str(w.get("w", "")))
			if cw != "" and str(w.get("sens", "")) != "": glm[cw] = str(w.get("sens", ""))
		if gloss_fn.is_valid():
			for tok in words:
				var c2 := _clean(tok)
				if c2 == "" or glm.has(c2): continue
				if not _fb.has(c2): _fb[c2] = str(gloss_fn.call(c2))
				if _fb[c2] != "": glm[c2] = "~" + _fb[c2]
		var gfs := maxi(12, int(fs * 0.42))
		var extra := gfs * 1.45 if not glm.is_empty() else 0.0
		var bh := rows.size() * (lh + extra)
		var spw := f.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var rws := []   # largeurs de mots par rangée
		for row in rows:
			var wl := []
			for i in row: wl.append(f.get_string_size(words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
			rws.append(wl)
		var trs := ""
		var tfs := int(fs * 0.62)
		var trows := []
		var tws := PackedStringArray()
		var twidths := {}
		var tsp := 0.0
		if show_tr:
			trs = str(trans.get(k, {}).get("tr", ""))
			if trs != "":
				tws = trs.split(" ", false)
				trows = _wrap(tws, tfs, maxw)
				tsp = f.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
				for i in tws.size(): twidths[i] = f.get_string_size(tws[i], HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
				bh += trows.size() * tfs * 1.3 + 4
		_blocks.append({"k": k, "fs": fs, "words": words, "rows": rows, "rws": rws, "spw": spw, "lh": lh, "y": y, "h": bh,
			"tr": trs, "tfs": tfs, "trows": trows, "tws": tws, "twidths": twidths, "tsp": tsp, "glm": glm, "gfs": gfs, "extra": extra})
		if k == cur: cur_center = y + bh / 2.0
		y += bh + fs * 0.55
	_target = cur_center - size.y * (0.5 if compact else 0.46)
	if absf(scroll_y - _target) > size.y * 2: scroll_y = _target


func _draw() -> void:
	_hits.clear(); _line_rects.clear()
	var f := _font()
	if lines.is_empty():
		var msg := "♪  Pas de paroles synchronisées  ♪"
		var s := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		draw_string(f, Vector2((size.x - s.x) / 2, size.y / 2), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(UI.p("text"), 0.5)); return
	if compact:
		_bgbox.bg_color = Color(0.04, 0.05, 0.09, 0.62); _bgbox.set_corner_radius_all(18)
		draw_style_box(_bgbox, Rect2(Vector2.ZERO, size))
		if idx < 0: return
	var sig := "%d|%d|%d|%d|%d|%d|%d" % [idx, int(size.x), int(size.y), _ver, int(show_tr), int(compact), known.size()]
	if sig != _sig or _blocks.is_empty(): _sig = sig; _layout()
	if idx >= 0: _word_times(idx)
	for b in _blocks:
		var k: int = b["k"]
		var fs: int = b["fs"]
		var by: float = b["y"] - scroll_y
		if by + b["h"] < -40 or by > size.y + 40: continue
		var is_cur: bool = k == idx
		var dist := absi(k - maxi(idx, 0))
		var alpha := 1.0 if is_cur else clampf(0.62 - 0.18 * (dist - 1), 0.18, 0.62)
		if compact and not is_cur: alpha = clampf(0.5 - 0.12 * (dist - 1), 0.25, 0.5) if k < idx else clampf(0.85 - 0.15 * (dist - 1), 0.45, 0.85)
		var spw: float = b["spw"]
		var yy := by
		var line_top := by
		var glm: Dictionary = b["glm"]
		var ri := 0
		for row in b["rows"]:
			var widths: Array = b["rws"][ri]; ri += 1
			var tw := 0.0
			for ww in widths: tw += ww
			tw += spw * (row.size() - 1)
			var x := (size.x - tw) / 2.0
			var base := yy + fs * 1.0
			for j in row.size():
				var i: int = row[j]
				var word: String = b["words"][i]
				var ww: float = widths[j]
				var cw := _clean(word)
				var rect := Rect2(x - 4, yy, ww + 8, b["lh"] + b["extra"])
				if is_cur and i < _wt.size():
					var w0: float = _wt[i][0]; var w1: float = _wt[i][1]
					var prog := clampf((t - w0) / maxf(0.05, w1 - w0), 0.0, 1.0)
					if t >= w0 and t < w1:
						_pill.bg_color = Color(GOLD, 0.2); _pill.set_corner_radius_all(int(fs * 0.3))
						draw_style_box(_pill, Rect2(x - 8, yy + fs * 0.08, ww + 16, b["lh"] - fs * 0.1))
					_draw_sweep(f, Vector2(x, base), word, fs, prog if t < w1 else 1.0, t >= w0)
				else:
					if is_cur or alpha > 0.5: draw_string(f, Vector2(x + 2, base + 2), word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, alpha * 0.45))
					draw_string(f, Vector2(x, base), word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UI.p("text"), alpha))
				if glm.has(cw):
					var gs: String = glm[cw]
					var weak := gs.begins_with("~")
					if weak: gs = gs.substr(1)
					var gfs: int = b["gfs"]
					var gw := f.get_string_size(gs, HORIZONTAL_ALIGNMENT_LEFT, -1, gfs).x
					var maxg := maxf(ww + spw * 1.6, 60.0)
					var gsz := gfs if gw <= maxg else maxi(11, int(gfs * maxg / gw))
					if gsz != gfs: gw = f.get_string_size(gs, HORIZONTAL_ALIGNMENT_LEFT, -1, gsz).x
					var gx: float = x + ww / 2.0 - gw / 2.0
					var gy: float = yy + b["lh"] + gsz * 0.9
					_chip.bg_color = Color(CYAN, (0.07 if weak else 0.18) * (1.0 if is_cur else 0.75)); _chip.set_corner_radius_all(6)
					draw_style_box(_chip, Rect2(gx - 6, gy - gsz * 1.0, gw + 12, gsz * 1.35))
					draw_string(f, Vector2(gx, gy), gs, HORIZONTAL_ALIGNMENT_LEFT, -1, gsz, Color(CYAN, (0.62 if weak else 1.0) * (1.0 if is_cur else 0.8)))
					if not weak: draw_line(Vector2(x, base + 6), Vector2(x + ww, base + 6), Color(CYAN, 0.9 if is_cur else 0.5), 2.0)
				if known.has(cw):
					draw_dashed_line(Vector2(x, base + 9), Vector2(x + ww, base + 9), GOLD, 2.0, 4.0)
				_hits.append({"rect": rect, "word": cw, "line": k})
				x += ww + spw
			yy += b["lh"] + b["extra"]
		if b["tr"] != "":
			var tfs: int = b["tfs"]
			var tsp: float = b["tsp"]
			var tws: PackedStringArray = b["tws"]
			var twd: Dictionary = b["twidths"]
			yy += 4
			for row in b["trows"]:
				var tw2 := 0.0
				for i in row: tw2 += twd[i]
				tw2 += tsp * (row.size() - 1)
				var x2 := (size.x - tw2) / 2.0
				for i in row:
					var col2 := Color(GREEN, 1.0 if is_cur else alpha * 0.85)
					if is_cur: draw_string(f, Vector2(x2 + 1, yy + tfs + 1), tws[i], HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(0, 0, 0, 0.4))
					draw_string(f, Vector2(x2, yy + tfs), tws[i], HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, col2)
					x2 += twd[i] + tsp
				yy += tfs * 1.3
		_line_rects.append({"rect": Rect2(0, line_top - 4, size.x, b["h"] + 8), "line": k})


## Mot dessiné lettre par lettre : lettres déjà chantées en or, les autres en blanc.
func _draw_sweep(f: Font, pos: Vector2, word: String, fs: int, prog: float, started: bool) -> void:
	var n := word.length()
	var lit := int(floor(prog * n)) if started else 0
	var frac := prog * n - lit
	var x := pos.x
	draw_string(f, pos + Vector2(2, 2), word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5))
	for c in n:
		var ch := word[c]
		var col := Color(UI.p("text"), 0.95)
		if c < lit: col = GOLD
		elif c == lit and started: col = Color(UI.p("text"), 0.95).lerp(GOLD, frac)
		draw_string(f, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		for h in _hits:
			if h["rect"].has_point(ev.position) and h["word"] != "":
				word_clicked.emit(h["word"], h["line"]); accept_event(); return
		for r in _line_rects:
			if r["rect"].has_point(ev.position):
				seek_requested.emit(float(lines[r["line"]][0])); accept_event(); return
