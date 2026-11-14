extends Control
## Échecs à deux joueurs (même écran). Clique une pièce : ses coups légaux s'affichent (points / cercles).
## Règles complètes : roque, prise en passant, promotion, échec, mat, pat.

const LIGHT := Color("e8d9b5")
const DARK := Color("a9794f")
const SEL := Color(0.35, 0.65, 1.0, 0.55)
const LAST := Color(1.0, 0.9, 0.2, 0.35)
const MUTED := Color("8f9bb3")

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

# --- Réseau local (balises UDP + TCP direct, sans serveur ni compte ; non chiffré : réseau de confiance)
const BEACON := "CH1"
var udp_port := 4352
var tcp_port := 4353
var udp := PacketPeerUDP.new()
var server := TCPServer.new()
var conn: StreamPeerTCP
var buf := ""
var outq: Array = []
var net := ""                # "" (local) | "lobby" | "out" | "in" | "play"
var my_col := ""             # couleur jouée en réseau
var my_id := str(randi())
var my_name := ""
var peers := {}              # id -> {ip, port, name, busy, t}
var beacon_t := 0.0
var inc := {}                # défi reçu : {name, col}
var peer_name := ""
var lobby: VBoxContainer
var net_btn: Button
var resign_btn: Button
var inc_box: HBoxContainer
var lobby_sig := ""

func _ready() -> void:
	var side := VBoxContainer.new(); side.custom_minimum_size = Vector2(190, 0)
	side.set_anchors_preset(Control.PRESET_RIGHT_WIDE); side.offset_left = -200; side.offset_right = -10; side.offset_top = 10; side.offset_bottom = -10
	add_child(side)
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status.add_theme_font_size_override("font_size", 18); side.add_child(status)
	for it in [["Nouvelle partie", func(): if net == "" or net == "lobby": _new()], ["Annuler le coup", _undo], ["Retourner", func(): flipped = not flipped; queue_redraw()]]:
		var bt := Button.new(); bt.text = it[0]; bt.custom_minimum_size.y = 40; bt.pressed.connect(it[1]); side.add_child(bt)
	net_btn = Button.new(); net_btn.custom_minimum_size.y = 40; net_btn.pressed.connect(_toggle_net); side.add_child(net_btn)
	resign_btn = Button.new(); resign_btn.text = "Abandonner"; resign_btn.custom_minimum_size.y = 40; resign_btn.visible = false
	resign_btn.pressed.connect(func(): _send({"t": "resign"}); _end_net(my_col, "Tu as abandonné.")); side.add_child(resign_btn)
	inc_box = HBoxContainer.new(); inc_box.visible = false; side.add_child(inc_box)
	for it in [["Accepter", _accept], ["Refuser", _decline]]:
		var ib := Button.new(); ib.text = it[0]; ib.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ib.pressed.connect(it[1]); inc_box.add_child(ib)
	lobby = VBoxContainer.new(); lobby.visible = false; side.add_child(lobby)
	list = Label.new(); list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_theme_color_override("font_color", MUTED); list.size_flags_vertical = Control.SIZE_EXPAND_FILL; side.add_child(list)
	resized.connect(queue_redraw)
	my_name = _device_name()
	_new()

func _exit_tree() -> void: _net_stop()

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
	if net == "play" and not remote:
		_send({"t": "move", "f": from, "to": m["to"], "p": m.get("promo", "")})
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

func _undo() -> void:
	if hist.is_empty() or net != "": return
	var h: Dictionary = hist.pop_back()
	b = h["b"]; turn = h["turn"]; castle = h["castle"]; ep = h["ep"]; last = h["last"]; cap = h["cap"]
	san.resize(h["n"]); over = ""; sel = -1; moves = []; promo = {}
	_refresh()

func _refresh() -> void:
	net_btn.text = "Mode local" if net != "" else "Jouer en réseau"
	resign_btn.visible = net == "play" and over == ""
	var who := "Blancs" if turn == "w" else "Noirs"
	if over == "mat": status.text = "Échec et mat ! %s gagnent." % ("Noirs" if turn == "w" else "Blancs")
	elif over == "pat": status.text = "Pat : partie nulle."
	else: status.text = "Au tour des %s%s" % [who, "\nÉchec !" if _in_check(b, turn) else ""]
	if net == "play":
		status.text = ("Tu joues les %s contre %s\n" % ["Blancs" if my_col == "w" else "Noirs", peer_name]) + status.text
		if over == "" and turn == my_col: status.text += "\nÀ toi de jouer."
	elif net == "out": status.text = "Défi envoyé à %s… en attente de réponse." % peer_name
	elif net == "lobby": status.text = "Joueurs trouvés sur le réseau local :" if not peers.is_empty() else "Recherche de joueurs sur le réseau local…"
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
	if net == "play" and turn != my_col: return
	if net in ["lobby", "out", "in"]: return
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

# ---------------------------------------------------------------- Réseau

func _device_name() -> String:
	var n := ""
	if OS.get_name() == "Android": n = OS.get_model_name()
	for k in ["HOSTNAME", "HOST", "COMPUTERNAME"]:
		if n == "": n = OS.get_environment(k)
	if n == "" and FileAccess.file_exists("/etc/hostname"): n = FileAccess.get_file_as_string("/etc/hostname").strip_edges()
	return n.substr(0, 24) if n != "" else "Joueur"

func _toggle_net() -> void:
	if net == "":
		if server.listen(tcp_port) != OK: status.text = "Port %d indisponible : réseau impossible." % tcp_port; return
		net = "lobby"; lobby.visible = true; peers = {}; lobby_sig = "x"; _new()
		net = "lobby"; _refresh()
	else:
		_net_stop(); net = ""; lobby.visible = false; inc_box.visible = false; _new()

func _net_stop() -> void:
	if conn: _send({"t": "bye"}); conn.poll(); _flush(); conn.disconnect_from_host(); conn = null
	server.stop(); udp.close(); buf = ""; outq = []

func _broadcast_addrs() -> PackedStringArray:
	var out: PackedStringArray = ["255.255.255.255"]
	for a in IP.get_local_addresses():
		if a.contains(".") and not a.begins_with("127.") and not a.begins_with("169.254"): out.append(a.substr(0, a.rfind(".")) + ".255")
	return out

func _flush() -> void:
	if conn and conn.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		while not outq.is_empty(): conn.put_data(outq.pop_front().to_utf8_buffer())

func _send(d: Dictionary) -> void:
	outq.append(JSON.stringify(d) + "\n")

func _process(delta: float) -> void:
	if net == "": return
	var now := Time.get_ticks_msec() / 1000.0
	if not udp.is_bound():
		if udp.bind(udp_port) == OK: udp.set_broadcast_enabled(true)
	beacon_t -= delta
	if beacon_t <= 0.0 and udp.is_bound():
		beacon_t = 2.0
		var msg := ("%s|%s|%d|%d|%s" % [BEACON, my_id, tcp_port, 0 if net == "lobby" else 1, my_name.replace("|", " ")]).to_utf8_buffer()
		for a in _broadcast_addrs(): udp.set_dest_address(a, udp_port); udp.put_packet(msg)
	while udp.is_bound() and udp.get_available_packet_count() > 0:
		var parts := udp.get_packet().get_string_from_utf8().split("|", true, 4)
		var ip := udp.get_packet_ip()
		if parts.size() < 5 or parts[0] != BEACON or parts[1] == my_id: continue
		peers[parts[1]] = {"ip": ip, "port": parts[2].to_int(), "busy": parts[3] == "1", "name": parts[4].substr(0, 24), "t": now}
	for k in peers.keys():
		if now - peers[k]["t"] > 7.0: peers.erase(k)
	_rebuild_lobby()
	while server.is_connection_available():
		var p := server.take_connection()
		if conn == null and net == "lobby": conn = p; buf = ""; outq = []
		else: p.disconnect_from_host()
	if conn == null: return
	conn.poll()
	var st := conn.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTED:
		while not outq.is_empty():
			conn.put_data(outq.pop_front().to_utf8_buffer())
		var n := conn.get_available_bytes()
		if n > 0: buf += conn.get_data(n)[1].get_string_from_utf8()
		while buf.contains("\n"):
			var i := buf.find("\n"); var line := buf.substr(0, i); buf = buf.substr(i + 1)
			var d = JSON.parse_string(line)
			if d is Dictionary: _on_msg(d)
			if conn == null: return
	elif st == StreamPeerTCP.STATUS_NONE or st == StreamPeerTCP.STATUS_ERROR:
		_lost()

func _rebuild_lobby() -> void:
	var sig := str(net)
	for k in peers: sig += "|" + k + peers[k]["name"] + str(peers[k]["busy"])
	if sig == lobby_sig: return
	lobby_sig = sig
	for c in lobby.get_children(): c.queue_free()
	if net != "lobby": return
	for k in peers:
		var pr: Dictionary = peers[k]
		var bt := Button.new(); bt.text = "Défier " + pr["name"] + (" (en partie)" if pr["busy"] else ""); bt.disabled = pr["busy"]
		bt.custom_minimum_size.y = 40; bt.pressed.connect(_challenge.bind(k)); lobby.add_child(bt)
	_refresh()

func connect_to(ip: String, port: int, nm := "Adversaire") -> void:
	conn = StreamPeerTCP.new(); buf = ""; outq = []
	if conn.connect_to_host(ip, port) != OK: conn = null; status.text = "Connexion impossible."; return
	peer_name = nm; net = "out"
	var theirs := "w" if randi() % 2 == 0 else "b"
	my_col = "b" if theirs == "w" else "w"
	_send({"t": "challenge", "name": my_name, "col": theirs}); _refresh()

func _challenge(id: String) -> void:
	if conn != null: return
	connect_to(peers[id]["ip"], peers[id]["port"], peers[id]["name"])

func _on_msg(d: Dictionary) -> void:
	match str(d.get("t", "")):
		"challenge":
			if net != "lobby": _send({"t": "decline"}); return
			inc = {"name": str(d.get("name", "Joueur")).substr(0, 24), "col": "b" if str(d.get("col", "w")) == "b" else "w"}
			peer_name = inc["name"]; net = "in"; inc_box.visible = true; lobby.visible = false
			status.text = "%s te défie ! Tu jouerais les %s." % [peer_name, "Blancs" if inc["col"] == "w" else "Noirs"]
		"accept":
			if net == "out": _start_net()
		"decline":
			if net == "out": _drop_conn("%s a refusé le défi." % peer_name)
		"move":
			if net != "play" or over != "" or turn == my_col: return
			var f := int(d.get("f", -1)); var to := int(d.get("to", -1))
			if f < 0 or f > 63 or b[f] == "" or b[f][0] != turn: return
			for m in _legal(f):
				if m["to"] == to:
					var mm: Dictionary = m.duplicate()
					var pr := str(d.get("p", ""))
					if b[f][1] == "P" and (to / 8 == 0 or to / 8 == 7): mm["promo"] = pr if pr in ["Q", "R", "B", "N"] else "Q"
					_play(f, mm, true); return
		"resign":
			if net == "play": _end_net("b" if my_col == "w" else "w", "%s a abandonné." % peer_name)
		"bye": _lost()

func _accept() -> void:
	my_col = inc["col"]   # couleur que le challenger m'attribue
	inc_box.visible = false; _send({"t": "accept"}); _start_net()

func _decline() -> void:
	inc_box.visible = false; _send({"t": "decline"}); _flush(); _drop_conn("")

func _start_net() -> void:
	net = "lobby"; _new(); net = "play"; flipped = my_col == "b"; lobby.visible = false; _refresh()

func _end_net(winner: String, msg: String) -> void:
	over = "fin"; over_msg = msg if winner != "" else msg; _refresh()

func _drop_conn(msg: String) -> void:
	if conn: conn.poll(); conn.disconnect_from_host()
	conn = null; buf = ""; outq = []; inc_box.visible = false
	net = "lobby"; lobby.visible = true; lobby_sig = "x"; _new(); net = "lobby"; _refresh()
	if msg != "": status.text = msg

func _lost() -> void:
	if net == "play" and over == "":
		if conn: conn.disconnect_from_host()
		conn = null; over = "fin"; over_msg = "%s s'est déconnecté." % peer_name; net = "play"; _refresh()
		net = "play"
	elif net == "play":
		if conn: conn.disconnect_from_host()
		conn = null
	else: _drop_conn("Connexion perdue." if net == "out" else "")
