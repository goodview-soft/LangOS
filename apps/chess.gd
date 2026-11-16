extends Control
## Échecs à deux joueurs (même écran). Clique une pièce : ses coups légaux s'affichent (points / cercles).
## Règles complètes : roque, prise en passant, promotion, échec, mat, pat.

const UI = preload("res://apps/ui.gd")
const LIGHT := Color("e8d9b5")
const DARK := Color("a9794f")
const SEL := Color(0.35, 0.65, 1.0, 0.55)
const LAST := Color(1.0, 0.9, 0.2, 0.35)

var b: Array = []            # 64 cases : "" ou "wP".."bK" (index = r*8+c, r=0 en haut = rang 8)
var turn := "w"
var castle := {"wK": true, "wQ": true, "bK": true, "bQ": true}
var ep := -1                 # case de prise en passant
var sel := -1
var moves: Array = []        # coups légaux depuis sel : {to, kind}
var hist: Array = []         # snapshots pour annuler
var san: Array = []
var last := Vector2i(-1, -1)
var flipped := false
var over := ""
var over_msg := ""
var promo := {}              # coup en attente de choix de promotion
var cap := {"w": [], "b": []}
var bs := 0.0
var org := Vector2.ZERO

var status: Label
var list: Label

var menu: GameMenu
var net := false             # partie réseau en cours
var ai := ""                 # couleur jouée par l'IA ("" = pas d'IA)
const LEVELS := ["Débutant", "Facile", "Moyen", "Fort"]
var level := 1
var lvl_btn: Button
var my_col := ""
var peer_name := ""
var resign_btn: Button
const VAL := {"P": 100, "N": 320, "B": 330, "R": 500, "Q": 900, "K": 0}

func _ready() -> void:
	var side := VBoxContainer.new(); side.custom_minimum_size = Vector2(190, 0)
	side.set_anchors_preset(Control.PRESET_RIGHT_WIDE); side.offset_left = -200; side.offset_right = -10; side.offset_top = 10; side.offset_bottom = -10
	add_child(side)
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status.add_theme_font_size_override("font_size", 18); side.add_child(status)
	for it in [["Nouvelle partie", func(): if not net: _new()], ["Annuler le coup", _undo], ["Retourner", func(): flipped = not flipped; queue_redraw()]]:
		var bt := Button.new(); bt.text = it[0]; bt.custom_minimum_size.y = 40; bt.pressed.connect(it[1]); side.add_child(bt)
	var mb := Button.new(); mb.text = "Menu"; mb.custom_minimum_size.y = 40; mb.pressed.connect(func(): net = false; ai = ""; menu.show_menu()); side.add_child(mb)
	lvl_btn = Button.new(); lvl_btn.custom_minimum_size.y = 40; lvl_btn.visible = false; lvl_btn.pressed.connect(func(): level = (level + 1) % 4; _refresh()); side.add_child(lvl_btn)
	resign_btn = Button.new(); resign_btn.text = "Abandonner"; resign_btn.custom_minimum_size.y = 40; resign_btn.visible = false
	resign_btn.pressed.connect(func(): menu.send({"t": "resign"}); over = "fin"; over_msg = "Tu as abandonné."; _refresh()); side.add_child(resign_btn)
	list = Label.new(); list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_theme_color_override("font_color", UI.muted_c()); list.size_flags_vertical = Control.SIZE_EXPAND_FILL; side.add_child(list)
	resized.connect(queue_redraw)
	_new()
	menu = GameMenu.new(); menu.game_id = "chess"; menu.title = "Échecs"; add_child(menu)
	menu.chosen.connect(func(m: String): net = false; flipped = false; ai = "b" if m == "ai" else ""; _new())
	menu.net_started.connect(func(slot: int, nm: String): net = true; ai = ""; my_col = "w" if slot == 0 else "b"; peer_name = nm; flipped = my_col == "b"; _new())
	menu.net_msg.connect(_on_msg)
	menu.net_closed.connect(func(r: String): if over == "": over = "fin"; over_msg = r; _refresh())

func _new() -> void:
	b = []; b.resize(64); b.fill("")
	var back := ["R", "N", "B", "Q", "K", "B", "N", "R"]
	for c in 8:
		b[c] = "b" + back[c]; b[8 + c] = "bP"; b[48 + c] = "wP"; b[56 + c] = "w" + back[c]
	turn = "w"; castle = {"wK": true, "wQ": true, "bK": true, "bQ": true}; ep = -1
	sel = -1; moves = []; hist = []; san = []; last = Vector2i(-1, -1); over = ""; over_msg = ""; promo = {}
	cap = {"w": [], "b": []}
	_refresh()

# ---------------------------------------------------------------- Règles

func _inb(r: int, c: int) -> bool: return r >= 0 and r < 8 and c >= 0 and c < 8

## Cases attaquées par la couleur `by` sur le plateau `bd`.
func _attacked(bd: Array, sq: int, by: String) -> bool:
	var r := sq / 8; var c := sq % 8
	var pd := 1 if by == "w" else -1     # un pion blanc attaque vers r-1 : il se trouve donc en r+1
	for dc in [-1, 1]:
		if _inb(r + pd, c + dc) and bd[(r + pd) * 8 + c + dc] == by + "P": return true
	for d in [[1, 2], [2, 1], [-1, 2], [-2, 1], [1, -2], [2, -1], [-1, -2], [-2, -1]]:
		if _inb(r + d[0], c + d[1]) and bd[(r + d[0]) * 8 + c + d[1]] == by + "N": return true
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0: continue
			if _inb(r + dr, c + dc) and bd[(r + dr) * 8 + c + dc] == by + "K": return true
			var rr: int = r + dr; var cc: int = c + dc
			while _inb(rr, cc):
				var p: String = bd[rr * 8 + cc]
				if p != "":
					if p[0] == by and (p[1] == "Q" or (p[1] == "R" and (dr == 0 or dc == 0)) or (p[1] == "B" and dr != 0 and dc != 0)): return true
					break
				rr += dr; cc += dc
	return false

func _king(bd: Array, col: String) -> int: return bd.find(col + "K")

func _in_check(bd: Array, col: String) -> bool:
	return _attacked(bd, _king(bd, col), "b" if col == "w" else "w")

## Coups pseudo-légaux depuis `from` (sans test d'échec, sauf roque).
func _pseudo(from: int) -> Array:
	var out: Array = []
	var p: String = b[from]; var col := p[0]; var t := p[1]
	var r := from / 8; var c := from % 8
	var foe := "b" if col == "w" else "w"
	match t:
		"P":
			var d := -1 if col == "w" else 1
			var start := 6 if col == "w" else 1
			if _inb(r + d, c) and b[(r + d) * 8 + c] == "":
				out.append({"to": (r + d) * 8 + c, "kind": "move"})
				if r == start and b[(r + 2 * d) * 8 + c] == "": out.append({"to": (r + 2 * d) * 8 + c, "kind": "double"})
			for dc in [-1, 1]:
				if not _inb(r + d, c + dc): continue
				var to: int = (r + d) * 8 + c + dc
				if b[to] != "" and b[to][0] == foe: out.append({"to": to, "kind": "move"})
				elif to == ep: out.append({"to": to, "kind": "ep"})
		"N":
			for dd in [[1, 2], [2, 1], [-1, 2], [-2, 1], [1, -2], [2, -1], [-1, -2], [-2, -1]]:
				if _inb(r + dd[0], c + dd[1]):
					var to: int = (r + dd[0]) * 8 + c + dd[1]
					if b[to] == "" or b[to][0] == foe: out.append({"to": to, "kind": "move"})
		"K":
			for dr in [-1, 0, 1]:
				for dc in [-1, 0, 1]:
					if (dr != 0 or dc != 0) and _inb(r + dr, c + dc):
						var to: int = (r + dr) * 8 + c + dc
						if b[to] == "" or b[to][0] == foe: out.append({"to": to, "kind": "move"})
			var home := 60 if col == "w" else 4
			if from == home and not _in_check(b, col):
				if castle[col + "K"] and b[home + 1] == "" and b[home + 2] == "" and b[home + 3] == col + "R" \
						and not _attacked(b, home + 1, foe) and not _attacked(b, home + 2, foe):
					out.append({"to": home + 2, "kind": "castleK"})
				if castle[col + "Q"] and b[home - 1] == "" and b[home - 2] == "" and b[home - 3] == "" and b[home - 4] == col + "R" \
						and not _attacked(b, home - 1, foe) and not _attacked(b, home - 2, foe):
					out.append({"to": home - 2, "kind": "castleQ"})
		_:
			var dirs: Array = []
			if t != "B": dirs += [[1, 0], [-1, 0], [0, 1], [0, -1]]
			if t != "R": dirs += [[1, 1], [1, -1], [-1, 1], [-1, -1]]
			for dd in dirs:
				var rr: int = r + dd[0]; var cc: int = c + dd[1]
				while _inb(rr, cc):
					var to := rr * 8 + cc
					if b[to] == "": out.append({"to": to, "kind": "move"})
					else:
						if b[to][0] == foe: out.append({"to": to, "kind": "move"})
						break
					rr += dd[0]; cc += dd[1]
	return out

func _apply(bd: Array, from: int, m: Dictionary) -> void:
	var p: String = bd[from]; var to: int = m["to"]
	bd[to] = p; bd[from] = ""
	match m["kind"]:
		"ep": bd[from / 8 * 8 + to % 8] = ""
		"castleK": bd[to - 1] = bd[to + 1]; bd[to + 1] = ""
		"castleQ": bd[to + 1] = bd[to - 2]; bd[to - 2] = ""
	if m.has("promo"): bd[to] = p[0] + m["promo"]

func _legal(from: int) -> Array:
	var out: Array = []
	var col: String = b[from][0]
	for m in _pseudo(from):
		var tmp := b.duplicate(); _apply(tmp, from, m)
		if _in_check(tmp, col): continue
		out.append(m)
	return out

func _has_move(col: String) -> bool:
	for i in 64:
		if b[i] != "" and b[i][0] == col and not _legal(i).is_empty(): return true
	return false

# ---------------------------------------------------------------- Jeu

func _name(i: int) -> String: return "abcdefgh"[i % 8] + str(8 - i / 8)

func _play(from: int, m: Dictionary, remote := false) -> void:
	if net and not remote:
		menu.send({"t": "move", "f": from, "to": m["to"], "p": m.get("promo", "")})
	hist.append({"b": b.duplicate(), "turn": turn, "castle": castle.duplicate(), "ep": ep, "last": last, "cap": {"w": cap["w"].duplicate(), "b": cap["b"].duplicate()}, "n": san.size()})
	var p: String = b[from]; var to: int = m["to"]
	var taken: String = b[to] if m["kind"] != "ep" else b[from / 8 * 8 + to % 8]
	if taken != "": cap[p[0]].append(taken)
	_apply(b, from, m)
	# droits de roque
	if p[1] == "K": castle[p[0] + "K"] = false; castle[p[0] + "Q"] = false
	for pair in [[56, "wQ"], [63, "wK"], [0, "bQ"], [7, "bK"]]:
		if from == pair[0] or to == pair[0]: castle[pair[1]] = false
	ep = (from + to) / 2 if m["kind"] == "double" else -1
	var foe := "b" if turn == "w" else "w"
	var txt := ""
	match m["kind"]:
		"castleK": txt = "O-O"
		"castleQ": txt = "O-O-O"
		_: txt = ("" if p[1] == "P" else p[1]) + ("x" if taken != "" else "") + _name(to) + ("=" + m["promo"] if m.has("promo") else "")
	if p[1] == "P" and taken != "" and not m["kind"] in ["castleK", "castleQ"]: txt = "abcdefgh"[from % 8] + txt
	last = Vector2i(from, to)
	turn = foe
	var chk := _in_check(b, turn)
	if not _has_move(turn):
		over = "mat" if chk else "pat"
		txt += "#" if chk else ""
	elif chk: txt += "+"
	san.append(txt)
	sel = -1; moves = []
	_refresh()
	if ai != "" and turn == ai and over == "": get_tree().create_timer(0.4).timeout.connect(_ai_move)

func _undo() -> void:
	if hist.is_empty() or net: return
	_undo_one()
	if ai != "" and turn == ai and not hist.is_empty(): _undo_one()

func _undo_one() -> void:
	var h: Dictionary = hist.pop_back()
	b = h["b"]; turn = h["turn"]; castle = h["castle"]; ep = h["ep"]; last = h["last"]; cap = h["cap"]
	san.resize(h["n"]); over = ""; sel = -1; moves = []; promo = {}
	_refresh()

func _refresh() -> void:
	resign_btn.visible = net and over == ""
	lvl_btn.visible = ai != "" and not net; lvl_btn.text = "Niveau : " + LEVELS[level]
	var who := "Blancs" if turn == "w" else "Noirs"
	if over == "mat": status.text = "Échec et mat ! %s gagnent." % ("Noirs" if turn == "w" else "Blancs")
	elif over == "pat": status.text = "Pat : partie nulle."
	else: status.text = "Au tour des %s%s" % [who, "\nÉchec !" if _in_check(b, turn) else ""]
	if net:
		status.text = ("Tu joues les %s contre %s\n" % ["Blancs" if my_col == "w" else "Noirs", peer_name]) + status.text
		if over == "" and turn == my_col: status.text += "\nÀ toi de jouer."
	elif ai != "": status.text = "Contre l'IA – %s (tu joues les Blancs)\n" % LEVELS[level] + status.text
	if over != "" and over_msg != "": status.text = over_msg + "\n" + status.text
	var s := ""
	for i in san.size():
		if i % 2 == 0: s += "%d. " % (i / 2 + 1)
		s += san[i] + ("  " if i % 2 == 0 else "\n")
	list.text = s
	queue_redraw()

func _geom() -> void:
	var w := size.x - 210.0
	bs = maxf(8.0, minf(w, size.y - 20.0) / 8.0)
	org = Vector2(10.0 + (w - bs * 8.0) / 2.0, (size.y - bs * 8.0) / 2.0)

func _cell(i: int) -> Vector2:
	var r := i / 8; var c := i % 8
	if flipped: r = 7 - r; c = 7 - c
	return org + Vector2(c, r) * bs

func _gui_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT): return
	_geom()
	if not promo.is_empty():
		_pick_promo(ev.position); return
	if over != "": return
	if (net and turn != my_col) or (ai != "" and turn == ai): return
	var rel: Vector2 = (ev.position - org) / bs
	if rel.x < 0 or rel.y < 0 or rel.x >= 8 or rel.y >= 8: sel = -1; moves = []; queue_redraw(); return
	var c := int(rel.x); var r := int(rel.y)
	if flipped: r = 7 - r; c = 7 - c
	var i := r * 8 + c
	for m in moves:
		if m["to"] == i:
			if b[sel][1] == "P" and (i / 8 == 0 or i / 8 == 7):
				promo = {"from": sel, "m": m}; queue_redraw(); return
			_play(sel, m); return
	if b[i] != "" and b[i][0] == turn:
		sel = i; moves = _legal(i)
	else:
		sel = -1; moves = []
	queue_redraw()

func _pick_promo(pos: Vector2) -> void:
	var to: int = promo["m"]["to"]
	var o := _cell(to)
	var opts := ["Q", "R", "B", "N"]
	var dir := 1.0 if (to / 8 == 0) != flipped else -1.0
	for k in 4:
		var rc := Rect2(o + Vector2(0, dir * bs * k), Vector2(bs, bs))
		if rc.has_point(pos):
			var m: Dictionary = promo["m"].duplicate(); m["promo"] = opts[k]
			var f: int = promo["from"]; promo = {}
			_play(f, m); return
	promo = {}; queue_redraw()

# ---------------------------------------------------------------- Dessin

func _draw() -> void:
	_geom()
	draw_rect(Rect2(org - Vector2(4, 4), Vector2(bs * 8 + 8, bs * 8 + 8)), Color("2b2f3a"))
	var kc := _king(b, turn) if over == "" or over == "mat" else -1
	for i in 64:
		var r := i / 8; var c := i % 8
		var o := _cell(i)
		draw_rect(Rect2(o, Vector2(bs, bs)), LIGHT if (r + c) % 2 == 0 else DARK)
		if i == last.x or i == last.y: draw_rect(Rect2(o, Vector2(bs, bs)), LAST)
		if i == sel: draw_rect(Rect2(o, Vector2(bs, bs)), SEL)
		if i == kc and _in_check(b, turn): draw_circle(o + Vector2(bs, bs) / 2, bs * 0.46, Color(1, 0.15, 0.15, 0.45))
		var f := ThemeDB.fallback_font
		var cx: int = (7 - c) if flipped else c
		var rx: int = (7 - r) if flipped else r
		if rx == 7: draw_string(f, o + Vector2(bs - 12, bs - 4), "abcdefgh"[c], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.45))
		if cx == 0: draw_string(f, o + Vector2(3, 13), str(8 - r), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.45))
	for i in 64:
		if b[i] != "": _piece(_cell(i), b[i])
	for m in moves:
		var o := _cell(m["to"]) + Vector2(bs, bs) / 2
		if b[m["to"]] != "" or m["kind"] == "ep": draw_arc(o, bs * 0.43, 0, TAU, 40, Color(0.2, 0.2, 0.2, 0.55), bs * 0.08)
		else: draw_circle(o, bs * 0.16, Color(0.2, 0.2, 0.2, 0.5))
	var capy := org.y + bs * 8 + 6
	if not promo.is_empty():
		var to: int = promo["m"]["to"]; var o := _cell(to)
		var dir := 1.0 if (to / 8 == 0) != flipped else -1.0
		for k in 4:
			var p := o + Vector2(0, dir * bs * k)
			draw_rect(Rect2(p, Vector2(bs, bs)), Color(0.95, 0.95, 0.98))
			draw_rect(Rect2(p, Vector2(bs, bs)), Color(0.2, 0.3, 0.6), false, 2)
			_piece(p, turn + ["Q", "R", "B", "N"][k])

func _piece(o: Vector2, code: String) -> void:
	var white := code[0] == "w"
	var fill := Color("f7f7f2") if white else Color("2a2a30")
	var line := Color("1a1a1f") if white else Color("e8e8e8")
	var u := bs / 100.0
	var P := func(pts: Array) -> PackedVector2Array:
		var a := PackedVector2Array()
		for q in pts: a.append(o + Vector2(q[0], q[1]) * u)
		return a
	var shapes: Array = []   # polygones remplis
	var base: Array = [[24, 86], [30, 74], [70, 74], [76, 86]]
	match code[1]:
		"P":
			shapes = [base, [[38, 74], [44, 50], [56, 50], [62, 74]]]
			_disc(o + Vector2(50, 36) * u, 14 * u, fill, line)
		"R":
			shapes = [base, [[32, 74], [36, 36], [64, 36], [68, 74]], [[28, 36], [28, 20], [38, 20], [38, 26], [46, 26], [46, 20], [54, 20], [54, 26], [62, 26], [62, 20], [72, 20], [72, 36]]]
		"N":
			shapes = [base, [[34, 74], [40, 50], [30, 44], [32, 36], [50, 18], [56, 24], [66, 22], [70, 40], [66, 74]]]
		"B":
			shapes = [base, [[38, 74], [44, 46], [56, 46], [62, 74]], [[50, 16], [64, 36], [60, 48], [40, 48], [36, 36]]]
		"Q":
			shapes = [base, [[30, 74], [22, 30], [38, 48], [44, 22], [50, 46], [56, 22], [62, 48], [78, 30], [70, 74]]]
		"K":
			shapes = [base, [[32, 74], [30, 46], [40, 38], [60, 38], [70, 46], [68, 74]], [[46, 10], [54, 10], [54, 18], [62, 18], [62, 26], [54, 26], [54, 38], [46, 38], [46, 26], [38, 26], [38, 18], [46, 18]]]
	for s in shapes:
		var pts: PackedVector2Array = P.call(s)
		draw_colored_polygon(pts, fill)
		var cl := pts.duplicate(); cl.append(pts[0])
		draw_polyline(cl, line, maxf(1.5, 3.0 * u), true)
	if code[1] == "N": _disc(o + Vector2(56, 30) * u, 3 * u, line, line)

func _disc(c: Vector2, r: float, fill: Color, line: Color) -> void:
	draw_circle(c, r, fill); draw_arc(c, r, 0, TAU, 24, line, 2.5)

# ---------------------------------------------------------------- Réseau (via GameMenu) et IA

func _on_msg(d: Dictionary) -> void:
	match str(d.get("t", "")):
		"move":
			if not net or over != "" or turn == my_col: return
			var f := int(d.get("f", -1)); var to := int(d.get("to", -1))
			if f < 0 or f > 63 or b[f] == "" or b[f][0] != turn: return
			for m in _legal(f):
				if m["to"] == to:
					var mm: Dictionary = m.duplicate(); var pr := str(d.get("p", ""))
					if b[f][1] == "P" and (to / 8 == 0 or to / 8 == 7): mm["promo"] = pr if pr in ["Q", "R", "B", "N"] else "Q"
					_play(f, mm, true); return
		"resign":
			if net and over == "": over = "fin"; over_msg = "%s a abandonné." % peer_name; _refresh()

func _eval(bd: Array, col: String) -> int:
	var sc := 0
	for i in 64:
		if bd[i] == "": continue
		var v: int = VAL[bd[i][1]]
		if bd[i][1] in ["P", "N", "B"]: v += 12 - int(absf(i / 8 - 3.5) + absf(i % 8 - 3.5)) * 3
		sc += v if bd[i][0] == col else -v
	return sc

## IA à 4 niveaux : Débutant (surtout au hasard), Facile (1 coup, bruit fort), Moyen (2 coups, quelques erreurs), Fort (2 coups, presque sans bruit).
func _ai_move() -> void:
	if ai == "" or over != "" or turn != ai or net: return
	var foe := "w" if ai == "b" else "b"
	var saved := b; var saved_ep := ep
	var cands: Array = []   # {i, m, s1 (après mon coup), s2 (après la meilleure réponse adverse)}
	for i in 64:
		if b[i] == "" or b[i][0] != ai: continue
		for m in _legal(i):
			var m2: Dictionary = m.duplicate()
			if b[i][1] == "P" and (m["to"] / 8 == 0 or m["to"] / 8 == 7): m2["promo"] = "Q"
			var nb := saved.duplicate(); _apply(nb, i, m2)
			var s2 := float(_eval(nb, ai))
			if level >= 2:
				b = nb; ep = -1
				var worst := INF; var any := false
				for j in 64:
					if nb[j] == "" or nb[j][0] != foe: continue
					for r in _legal(j):
						any = true
						var nb2 := nb.duplicate(); _apply(nb2, j, r)
						worst = minf(worst, _eval(nb2, ai))
				if not any: worst = 100000.0 if _in_check(nb, foe) else 0.0
				b = saved; ep = saved_ep
				s2 = worst
			cands.append({"i": i, "m": m2, "s": s2})
	if cands.is_empty(): return
	var pick: Dictionary
	match level:
		0:
			if randf() < 0.65: pick = cands[randi() % cands.size()]   # coup au hasard
			else: pick = _best_of(cands, 0.0)
		1: pick = _best_of(cands, 110.0)
		2:
			cands.sort_custom(func(x, y): return x["s"] > y["s"])
			pick = cands[1] if cands.size() > 1 and randf() < 0.25 else _best_of(cands, 50.0)
		_: pick = _best_of(cands, 6.0)
	_play(pick["i"], pick["m"])

func _best_of(cands: Array, noise: float) -> Dictionary:
	var best: Dictionary = cands[0]; var best_s := -INF
	for c in cands:
		var sc: float = c["s"] + (randf() * 2.0 - 1.0) * noise if noise > 6.0 else c["s"] + randf() * noise
		if sc > best_s: best_s = sc; best = c
	return best
