extends Control
## Air Hockey : contre l'IA (3 niveaux), à deux sur le même écran (multi-touch) ou en réseau local (via GameMenu).
## Réseau : l'hôte (slot 0, en bas) simule ; l'invité (slot 1, vue retournée) envoie son mallet et reçoit l'état à ~30 Hz.
## Physique en unités logiques (terrain W x H, joueur 0 en bas, joueur 1 en haut), dessin mis à l'échelle.

const UI = preload("res://apps/ui.gd")
const W := 400.0
const H := 640.0
const PR := 16.0               # rayon du palet
const MR := 30.0               # rayon des mallets
const GW := 150.0              # largeur des buts
const NOTCH := 34.0            # profondeur de l'encoche des buts
const FRICTION := 0.55         # frottement du palet (par seconde, exponentiel)
const WALL_E := 0.92
const MALLET_E := 0.75
const PUCK_MAX := 1100.0
const STEP := 1.0 / 120.0
const SEND_DT := 1.0 / 30.0
const LEVELS := ["Facile", "Moyen", "Difficile"]
# vitesse max du mallet IA, délai de réaction, erreur de visée, prédiction des rebonds
const AI_CFG := [{"spd": 400.0, "react": 0.28, "err": 46.0, "pred": false}, {"spd": 650.0, "react": 0.13, "err": 20.0, "pred": true}, {"spd": 950.0, "react": 0.04, "err": 6.0, "pred": true}]

var mode := "ai"               # ai | local | net
var level := 1
var target_score := 7
var me := 0                    # joueur local (0 = bas) ; 1 pour l'invité réseau
var guest := false
var peer_name := ""
var sound_on := true

var pp := Vector2(W / 2, H * 0.7)   # palet
var pv := Vector2.ZERO
var mp: Array = [Vector2(W / 2, H - 90), Vector2(W / 2, 90)]
var mv: Array = [Vector2.ZERO, Vector2.ZERO]
var mt: Array = [Vector2(W / 2, H - 90), Vector2(W / 2, 90)]
var score := [0, 0]
var winner := -1
var freeze := 1.0
var over_msg := ""
var acc := 0.0
var send_t := 0.0
var ai_t := 0.0
var ai_off := Vector2.ZERO
var ai_goal_x := W / 2
var flash := 0.0
var flash_side := 0
var trail: Array = []
var ptrs := {}                  # id de doigt -> joueur
var disp_puck := Vector2.ZERO   # affichage invité (interpolé)
var disp_m0 := Vector2.ZERO
var rx_t := 0.0
var xf := Transform2D.IDENTITY
var rng := RandomNumberGenerator.new()

var menu: GameMenu
var header: HFlowContainer
var btn_level: Button
var btn_sound: Button
var btn_new: Button
var player: AudioStreamPlayer
var pb: AudioStreamGeneratorPlayback
var tone := [0.0, 0, 0.0]       # fréquence, échantillons restants, phase

func _ready() -> void:
	rng.randomize()
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	header = HFlowContainer.new(); header.set_anchors_preset(Control.PRESET_TOP_WIDE); header.offset_left = 4; header.offset_right = -4; header.offset_top = 4
	header.add_theme_constant_override("h_separation", 4); header.add_theme_constant_override("v_separation", 4); add_child(header)
	_hbtn("Menu", func(): _to_menu())
	btn_new = _hbtn("Rejouer", _restart_pressed)
	btn_level = _hbtn("", func(): level = (level + 1) % 3; _refresh())
	_hbtn("À 7", func(): pass)   # remplacé dans _refresh
	btn_sound = _hbtn("", func(): sound_on = not sound_on; _refresh())
	header.get_child(3).pressed.connect(func(): if mode != "net": target_score = {3: 5, 5: 7, 7: 11, 11: 3}[target_score]; _refresh())
	header.resized.connect(queue_redraw); resized.connect(queue_redraw)
	var gen := AudioStreamGenerator.new(); gen.mix_rate = 22050.0; gen.buffer_length = 0.2
	player = AudioStreamPlayer.new(); player.stream = gen; add_child(player)
	menu = GameMenu.new(); menu.game_id = "airhockey"; menu.title = "Air Hockey"; add_child(menu)
	menu.chosen.connect(func(m: String): _start(m))
	menu.net_started.connect(func(slot: int, nm: String): _start("net", slot, nm))
	menu.net_msg.connect(_on_msg)
	menu.net_closed.connect(func(r: String): if winner < 0 and over_msg == "": over_msg = r; _refresh())
	_new_game()

func _hbtn(t: String, cb: Callable) -> Button:
	var b := Button.new(); b.text = t; b.custom_minimum_size = Vector2(0, 30); b.add_theme_font_size_override("font_size", 13)
	b.focus_mode = Control.FOCUS_NONE; b.pressed.connect(cb); header.add_child(b); return b

func _to_menu() -> void:
	mode = "ai"; guest = false; menu.show_menu()

func _start(m: String, slot := 0, nm := "") -> void:
	mode = m; guest = m == "net" and slot == 1; me = 1 if guest else 0; peer_name = nm
	if m == "net": target_score = 7
	_new_game()

func _restart_pressed() -> void:
	if guest: menu.send({"t": "rematch"}); return
	_new_game()

func _new_game() -> void:
	score = [0, 0]; winner = -1; over_msg = ""; acc = 0.0
	mp = [Vector2(W / 2, H - 90), Vector2(W / 2, 90)]; mt = mp.duplicate(); mv = [Vector2.ZERO, Vector2.ZERO]
	_serve(rng.randi() % 2); freeze = 1.2
	disp_puck = pp; disp_m0 = mp[0]; ptrs = {}
	_refresh()

func _refresh() -> void:
	if btn_level == null: return
	btn_level.visible = mode == "ai"; btn_level.text = "IA : " + LEVELS[level]
	header.get_child(3).visible = mode != "net"; header.get_child(3).text = "À %d" % target_score
	btn_sound.text = "Son : " + ("oui" if sound_on else "non")
	btn_new.disabled = false; btn_new.text = "Rejouer" if winner >= 0 or over_msg != "" or not guest else "Revanche"
	queue_redraw()

func _serve(conceder: int) -> void:
	pp = Vector2(W / 2, H * 0.68 if conceder == 0 else H * 0.32); pv = Vector2.ZERO; freeze = 1.0; trail = []

# ---------------------------------------------------------------- Géométrie / entrée

func _geom() -> void:
	var top := header.size.y + 8.0 if header else 0.0
	var aw := size.x - 12.0; var ah := size.y - top - 6.0
	var s := maxf(0.05, minf(aw / W, ah / (H + 2 * NOTCH)))
	var o := Vector2((size.x - W * s) / 2.0, top + (ah - (H + 2 * NOTCH) * s) / 2.0 + NOTCH * s)
	if guest: xf = Transform2D(Vector2(-s, 0), Vector2(0, -s), o + Vector2(W, H) * s)
	else: xf = Transform2D(Vector2(s, 0), Vector2(0, s), o)

func to_logic(p: Vector2) -> Vector2:
	_geom(); return xf.affine_inverse() * p

func _clamp_mallet(i: int, p: Vector2) -> Vector2:
	var x := clampf(p.x, MR, W - MR)
	var y := clampf(p.y, H / 2 + MR, H - MR) if i == 0 else clampf(p.y, MR, H / 2 - MR)
	return Vector2(x, y)

func set_target(i: int, lp: Vector2) -> void:
	mt[i] = _clamp_mallet(i, lp)

func _player_at(lp: Vector2) -> int:
	if mode == "local": return 0 if lp.y > H / 2 else 1
	return me

func pointer(id: int, pos: Vector2, pressed: bool, move := false) -> void:
	var lp := to_logic(pos)
	if id == -10:   # souris : suit sans clic
		set_target(_player_at(lp), lp); return
	if pressed and not move: ptrs[id] = _player_at(lp)
	elif not pressed: ptrs.erase(id); return
	if ptrs.has(id): set_target(ptrs[id], lp)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch: pointer(ev.index, ev.position, ev.pressed)
	elif ev is InputEventScreenDrag: pointer(ev.index, ev.position, true, true)
	elif ev is InputEventMouseMotion and ev.device != InputEvent.DEVICE_ID_EMULATION: pointer(-10, ev.position, true, true)
	elif ev is InputEventMouseButton and ev.device != InputEvent.DEVICE_ID_EMULATION and ev.pressed: pointer(-10, ev.position, true)

# ---------------------------------------------------------------- Simulation

func _process(delta: float) -> void:
	if not visible or menu.visible: return
	delta = minf(delta, 0.05)
	if guest: _guest_frame(delta)
	else:
		acc += delta
		while acc >= STEP:
			acc -= STEP; step(STEP)
		if mode == "net":
			send_t -= delta
			if send_t <= 0.0: send_t = SEND_DT; menu.send(snapshot())
	if guest and (mode == "net"):
		send_t -= delta
		if send_t <= 0.0: send_t = SEND_DT; menu.send({"t": "m", "x": snappy(mp[1].x), "y": snappy(mp[1].y)})
	if flash > 0.0: flash = maxf(0.0, flash - delta * 1.6)
	var shown := disp_puck if guest else pp
	if trail.is_empty() or trail[-1].distance_to(shown) > 4.0: trail.append(shown)
	while trail.size() > 16: trail.pop_front()
	_audio()
	queue_redraw()

static func snappy(v: float) -> float: return snappedf(v, 0.1)

func _ai_think() -> void:
	var c: Dictionary = AI_CFG[level]
	ai_off = Vector2(rng.randfn(0.0, c["err"] * 0.5), rng.randfn(0.0, c["err"] * 0.5))
	ai_goal_x = W / 2 + rng.randf_range(-GW * 0.4, GW * 0.4)

func _predict_x(y_line: float, c: Dictionary) -> float:
	if not c["pred"] or pv.y >= -20.0: return pp.x
	var t := (y_line - pp.y) / pv.y
	if t < 0.0: return pp.x
	var x := pp.x + pv.x * t
	var lo := PR; var span := W - 2 * PR
	var m := fposmod(x - lo, span * 2.0)
	return lo + (m if m <= span else span * 2.0 - m)

func _ai_update(dt: float) -> void:
	var c: Dictionary = AI_CFG[level]
	ai_t -= dt
	if ai_t > 0.0: return
	ai_t = c["react"]; _ai_think()
	var m: Vector2 = mp[1]
	var def_y := 80.0
	var tgt := Vector2(W / 2, def_y)
	var in_my_half := pp.y < H / 2
	var slow := pv.length() < 260.0
	if pp.y < MR * 1.4 and absf(pp.x - W / 2) < GW / 2 + PR: slow = false   # palet dans le but : rien à faire
	if in_my_half and (slow or pv.y > 0.0) and freeze <= 0.0 or (in_my_half and freeze > 0.0 and pp.y < H / 2):
		# attaque : se placer derrière le palet puis frapper vers le but adverse
		var aim := Vector2(ai_goal_x, H + 20.0)
		var dir := (aim - pp).normalized()
		var behind := pp - dir * (PR + MR + 8.0)
		if (m - pp).dot(dir) < -(PR + MR) * 0.6 and m.distance_to(pp) < 140.0 and absf((m - pp).cross(dir)) < MR * 0.9:
			tgt = pp + dir * 60.0   # aligné : frappe
		else:
			tgt = behind
			if tgt.y < MR: tgt.y = MR
	elif pv.y < -20.0 or not in_my_half:
		tgt = Vector2(_predict_x(def_y, c), def_y)
		if c["pred"] == false: tgt.x = pp.x
		if level == 2 and not in_my_half and pv.y > -20.0: tgt = Vector2(lerpf(W / 2, pp.x, 0.45), 100.0)
	else:
		tgt = Vector2(clampf(pp.x, GW * 0.5 + 40, W - GW * 0.5 - 40), 90.0)
	mt[1] = _clamp_mallet(1, tgt + ai_off)

func step(dt: float) -> void:
	if mode == "ai": _ai_update(dt)
	for i in 2:
		var spd := 1300.0
		if i == 1 and mode == "ai": spd = AI_CFG[level]["spd"]
		var d: Vector2 = (mt[i] - mp[i]).limit_length(spd * dt)
		var np: Vector2 = _clamp_mallet(i, mp[i] + d)
		mv[i] = (np - mp[i]) / dt; mp[i] = np
	if winner >= 0: pv = Vector2.ZERO; return
	if freeze > 0.0:
		freeze -= dt; return
	pp += pv * dt
	pv *= exp(-FRICTION * dt)
	_walls()
	for i in 2: _hit(i)
	if pv.length() > PUCK_MAX: pv = pv.normalized() * PUCK_MAX
	if pp.y < -4.0: _goal(0)
	elif pp.y > H + 4.0: _goal(1)

func _walls() -> void:
	var cx := W / 2
	if pp.x < PR: pp.x = PR; pv.x = absf(pv.x) * WALL_E; _ev("w")
	elif pp.x > W - PR: pp.x = W - PR; pv.x = -absf(pv.x) * WALL_E; _ev("w")
	for top in [true, false]:
		var y: float = pp.y if top else H - pp.y   # distance au fond de ce côté
		var sgn := 1.0 if top else -1.0
		if absf(pp.x - cx) >= GW / 2:
			if y < PR:
				pp.y = PR if top else H - PR
				pv.y = sgn * absf(pv.y) * WALL_E; _ev("w")
		else:
			for px in [cx - GW / 2, cx + GW / 2]:
				var post := Vector2(px, 0.0 if top else H)
				var dd := pp - post
				if dd.length() < PR and y < PR + 2.0:
					var n := dd.normalized() if dd.length() > 0.001 else Vector2(0, sgn)
					pp = post + n * PR
					if pv.dot(n) < 0.0: pv = pv.bounce(n) * WALL_E
					_ev("w")
			if y < 0.0:   # dans l'encoche : parois latérales
				if pp.x < cx - GW / 2 + PR: pp.x = cx - GW / 2 + PR; pv.x = absf(pv.x) * WALL_E
				elif pp.x > cx + GW / 2 - PR: pp.x = cx + GW / 2 - PR; pv.x = -absf(pv.x) * WALL_E

func _hit(i: int) -> void:
	var d: Vector2 = pp - mp[i]
	var dist := d.length()
	if dist >= PR + MR: return
	var n := d / dist if dist > 0.001 else Vector2(0, -1.0 if i == 0 else 1.0)
	pp = mp[i] + n * (PR + MR)
	var mvi: Vector2 = mv[i]
	var rel: Vector2 = pv - mvi
	var vn: float = rel.dot(n)
	if vn < 0.0:
		pv -= (1.0 + MALLET_E) * vn * n
		if pv.length() < 120.0: pv += n * 120.0   # petit coup minimum
		_ev("h")

func _goal(scorer: int) -> void:
	score[scorer] += 1; flash = 1.0; flash_side = scorer; _ev("g"); trail = []
	if score[scorer] >= target_score:
		winner = scorer; pv = Vector2.ZERO; pp = Vector2(W / 2, H / 2)
	else: _serve(1 - scorer)
	_refresh()

# ---------------------------------------------------------------- Réseau

var evs := ""

func snapshot() -> Dictionary:
	var d := {"t": "s", "p": [snappy(pp.x), snappy(pp.y), snappy(pv.x), snappy(pv.y)], "m": [snappy(mp[0].x), snappy(mp[0].y), snappy(mp[1].x), snappy(mp[1].y)],
		"sc": score.duplicate(), "w": winner, "f": snappedf(freeze, 0.01), "e": evs, "fl": flash_side if flash > 0.5 else -1}
	evs = ""; return d

func apply_snapshot(d: Dictionary) -> void:
	var p: Array = d.get("p", []); var m: Array = d.get("m", []); var sc: Array = d.get("sc", [])
	if p.size() < 4 or m.size() < 4 or sc.size() < 2: return
	pp = Vector2(float(p[0]), float(p[1])); pv = Vector2(float(p[2]), float(p[3]))
	mp[0] = Vector2(float(m[0]), float(m[1]))
	rx_t = Time.get_ticks_msec() / 1000.0
	if int(sc[0]) != score[0] or int(sc[1]) != score[1]:
		flash = 1.0; flash_side = 0 if int(sc[0]) != score[0] else 1; trail = []; disp_puck = pp
	score = [int(sc[0]), int(sc[1])]; winner = int(d.get("w", -1)); freeze = float(d.get("f", 0.0))
	for ch in str(d.get("e", "")): _ev(ch)
	if winner >= 0: _refresh()

func _guest_frame(delta: float) -> void:
	var d: Vector2 = (mt[1] - mp[1]).limit_length(1300.0 * delta)
	var np := _clamp_mallet(1, mp[1] + d); mv[1] = (np - mp[1]) / delta; mp[1] = np
	var age := minf(Time.get_ticks_msec() / 1000.0 - rx_t, 0.1)
	var k := 1.0 - exp(-24.0 * delta)
	disp_puck = disp_puck.lerp(pp + (pv * age if freeze <= 0.0 else Vector2.ZERO), k)
	disp_m0 = disp_m0.lerp(mp[0], k)

func _on_msg(d: Dictionary) -> void:
	match str(d.get("t", "")):
		"s": if guest: apply_snapshot(d)
		"m": if mode == "net" and not guest: mt[1] = _clamp_mallet(1, Vector2(float(d.get("x", W / 2)), float(d.get("y", 90.0))))
		"rematch": if mode == "net" and not guest: _new_game()

# ---------------------------------------------------------------- Son

func _ev(c: String) -> void:
	if not guest: evs += c
	match c:
		"h": _beep(520.0, 0.05)
		"w": _beep(300.0, 0.03)
		"g": _beep(180.0, 0.35)

func _beep(f: float, dur: float) -> void:
	if sound_on: tone = [f, int(dur * 22050.0), 0.0]; if not player.playing: player.play()

func _audio() -> void:
	if not sound_on or tone[1] <= 0: return
	if pb == null:
		if not player.playing: player.play()
		var pl := player.get_stream_playback()
		if pl is AudioStreamGeneratorPlayback: pb = pl
		else: return
	var n := mini(int(tone[1]), pb.get_frames_available())
	for k in n:
		var env := minf(1.0, float(tone[1] - k) / 600.0)
		var v := sin(tone[2]) * 0.18 * env
		tone[2] += TAU * tone[0] / 22050.0
		pb.push_frame(Vector2(v, v))
	tone[1] -= n

# ---------------------------------------------------------------- Dessin

func _draw() -> void:
	_geom()
	var acc_c := UI.accent(); var txt := UI.p("text")
	var light := UI.light()
	var table := UI.p("field").lerp(acc_c, 0.10 if not light else 0.14)
	var line := Color(acc_c, 0.55)
	draw_set_transform_matrix(xf)
	var gx0 := W / 2 - GW / 2; var gx1 := W / 2 + GW / 2
	# encoches des buts
	for top in [true, false]:
		var y0 := -NOTCH if top else H
		draw_rect(Rect2(gx0, y0, GW, NOTCH), UI.p("view").darkened(0.25 if not light else 0.1))
		draw_rect(Rect2(gx0, y0, GW, NOTCH), Color(acc_c, 0.5), false, 3.0)
	draw_rect(Rect2(0, 0, W, H), table)
	# flash de but (côté qui a marqué : on illumine le but attaqué)
	if flash > 0.0:
		var top_goal := flash_side == 0
		var fy := -NOTCH if top_goal else H - 0.0
		draw_rect(Rect2(gx0, fy, GW, NOTCH), Color(UI.warn(), flash * 0.8))
		draw_rect(Rect2(0, 0 if top_goal else H / 2, W, H / 2), Color(UI.warn(), flash * 0.12))
	# marquages
	draw_line(Vector2(0, H / 2), Vector2(W, H / 2), line, 3.0)
	draw_arc(Vector2(W / 2, H / 2), 70.0, 0, TAU, 48, line, 3.0)
	draw_circle(Vector2(W / 2, H / 2), 6.0, line)
	draw_arc(Vector2(W / 2, 0), GW / 2 + 28.0, 0, PI, 32, Color(acc_c, 0.3), 3.0)
	draw_arc(Vector2(W / 2, H), GW / 2 + 28.0, PI, TAU, 32, Color(acc_c, 0.3), 3.0)
	# bords (avec ouverture des buts)
	var edge := Color(acc_c, 0.9)
	for y in [0.0, H]:
		draw_line(Vector2(0, y), Vector2(gx0, y), edge, 5.0); draw_line(Vector2(gx1, y), Vector2(W, y), edge, 5.0)
	draw_line(Vector2(0, 0), Vector2(0, H), edge, 5.0); draw_line(Vector2(W, 0), Vector2(W, H), edge, 5.0)
	# trail
	var shown := disp_puck if guest else pp
	for k in trail.size():
		var a := float(k) / maxf(1.0, trail.size())
		draw_circle(trail[k], PR * (0.35 + 0.55 * a), Color(txt, 0.28 * a))
	# palet + mallets
	draw_circle(shown + Vector2(3, 4), PR, Color(0, 0, 0, 0.3))
	draw_circle(shown, PR, txt); draw_circle(shown, PR * 0.55, table)
	var cols := [acc_c, UI.err() if not light else UI.err().darkened(0.1)]
	for i in 2:
		var p: Vector2 = mp[i]
		if guest and i == 0: p = disp_m0
		draw_circle(p + Vector2(3, 5), MR, Color(0, 0, 0, 0.3))
		draw_circle(p, MR, cols[i]); draw_circle(p, MR * 0.62, Color(cols[i]).lightened(0.25)); draw_circle(p, MR * 0.22, Color(cols[i]).darkened(0.25))
	# score, texte (non retourné)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var f := UI.font(700); var s := xf.x.length()
	var fs := int(clampf(64.0 * s, 20.0, 96.0))
	var tl := xf * Vector2(W - 14, H / 2 - 10); var bl := xf * Vector2(W - 14, H / 2 + 10 + 0)
	var upper := 1 if not guest else 0   # joueur affiché en haut de l'écran
	var lower := 1 - upper
	var col_hi := Color(txt, 0.5)
	var ts := str(score[upper]); var bs := str(score[lower])
	var tsz := f.get_string_size(ts, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(f, Vector2(minf(tl.x, bl.x) - tsz.x, minf(tl.y, bl.y) - fs * 0.15 - 4), ts, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col_hi)
	draw_string(f, Vector2(minf(tl.x, bl.x) - f.get_string_size(bs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, maxf(tl.y, bl.y) + fs * 0.85 + 4), bs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col_hi)
	var mid := xf * Vector2(W / 2, H / 2)
	if winner < 0 and over_msg == "" and freeze > 0.0 and score[0] + score[1] == 0:
		_centered(f, "Prêt ?", mid + Vector2(0, -100.0 * s), int(30 * s + 8), txt)
	if winner >= 0 or over_msg != "":
		var m := over_msg
		if m == "":
			var won := winner == me if mode != "local" else true
			m = ("Joueur %d gagne !" % (winner + 1)) if mode == "local" else ("Gagné !" if won else "Perdu…")
		var r := Rect2(mid - Vector2(W * s * 0.4, 40), Vector2(W * s * 0.8, 80))
		draw_rect(r, Color(UI.p("win"), 0.92)); draw_rect(r, Color(acc_c, 0.9), false, 2.0)
		_centered(f, m, mid + Vector2(0, 10), int(clampf(30 * s + 6, 16, 36)), txt, r.size.x - 16)

func _centered(f: Font, t: String, p: Vector2, fs: int, c: Color, wmax := -1.0) -> void:
	var sz := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(f, p - Vector2(sz.x / 2, 0), t, HORIZONTAL_ALIGNMENT_LEFT, wmax, fs, c)
