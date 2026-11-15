extends SceneTree
## Tests logiques du pavé tactile, du curseur et de la détection du mode Flex.
## Lancer (sans fenêtre, c'est le mode normal) : flatpak run org.godotengine.Godot --headless --path . --script res://tests/pad_test.gd
## Les vérifications qui exigent une vraie fenêtre (zoom, survol) sont ignorées en mode sans fenêtre.
## Sortie : « PAD-TEST OK » si tout passe, sinon la liste des échecs et un code de sortie 1.

var fails: Array = []
var checks := 0
var rig: Dictionary

class Spy extends Node:
	var left := 0
	var right := 0
	var wheel: Array = []
	var left_pos: Array = []
	func _input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			match ev.button_index:
				MOUSE_BUTTON_LEFT: left += 1; left_pos.append(ev.position)
				MOUSE_BUTTON_RIGHT: right += 1
				_: wheel.append(ev.button_index)

class MotionSpy extends Node:
	var cnt: Dictionary
	func _input(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion and ev.device == 4242: cnt["n"] += 1

func check(name: String, cond: bool, info := "") -> void:
	checks += 1
	if not cond: fails.append("%s %s" % [name, info])

func tch(pos: Vector2, down: bool, idx := 0, canceled := false) -> InputEventScreenTouch:
	var t := InputEventScreenTouch.new(); t.index = idx; t.pressed = down; t.position = pos; t.canceled = canceled; return t

func drg(pos: Vector2, rel: Vector2, idx := 0) -> InputEventScreenDrag:
	var d := InputEventScreenDrag.new(); d.index = idx; d.position = pos; d.relative = rel; return d

func make_rig() -> Dictionary:
	var host := Control.new(); host.size = Vector2(1280, 800); root.add_child(host)
	var pointer := Control.new(); pointer.set_script(load("res://apps/pointer.gd")); pointer.set("mode", "on"); host.add_child(pointer)
	var flex := PanelContainer.new(); flex.set_script(load("res://apps/flex_pad.gd")); flex.set("pointer", pointer)
	var zooms: Array = []
	flex.set("on_zoom", func(z: float): zooms.append(z)); flex.set("get_zoom", func(): return 1.0)
	host.add_child(flex)
	flex.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	flex.offset_left = 0.0; flex.offset_right = 0.0; flex.offset_top = -320.0; flex.offset_bottom = 0.0
	flex.set("top_h", 480.0); flex.set("px_scale", 1.0); flex.call("set_touch_mode", true)
	pointer.set("pad_active", true); pointer.set("pad_top", 480.0)
	var spy := Spy.new(); root.add_child(spy)
	return {"host": host, "pointer": pointer, "flex": flex, "spy": spy, "zooms": zooms}

func settle() -> void:
	await create_timer(0.3).timeout

func padpos(dx := 0.0, dy := 0.0) -> Vector2:
	var r: Rect2 = rig["flex"]._pad.get_global_rect()
	return r.get_center() + Vector2(dx, dy)

func _init() -> void:
	root.size = Vector2i(1280, 800); root.content_scale_size = Vector2i(1280, 800)     # la fenêtre headless est minuscule : on lui donne la taille de base
	await process_frame
	await process_frame
	await test_formule_flex()
	await test_deplacement()
	await test_clics()
	await test_roulettes()
	await test_pincement()
	await test_annulation_et_nettoyage()
	await test_fuzz()
	await test_echelle()
	await test_survol()
	await test_zoom_stable()
	print("PAD-TEST %s : %d vérifications, %d échec(s)" % ["OK" if fails.is_empty() else "ECHEC", checks, fails.size()])
	for f in fails: print("  ✗ ", f)
	quit(0 if fails.is_empty() else 1)

# ------------------------------------------------------------------ détection du pli
func test_formule_flex() -> void:
	var L = load("res://apps/flex_logic.gd")
	var hz := {"orientation": "horizontal", "bottom": 440, "state": "flat"}
	check("flex: bibliothèque « half » suffit", L.is_half({"orientation": "horizontal", "bottom": 440, "state": "half"}, false))
	check("flex: plat à 180° = pas de flex", not L.is_half(hz.merged({"angle": 180}), false))
	check("flex: 90° = flex", L.is_half(hz.merged({"angle": 90}), false))
	check("flex: charnière verticale = pas de flex", not L.is_half({"orientation": "vertical", "bottom": 440, "state": "half"}, true))
	check("flex: pas de charnière = pas de flex", not L.is_half({"orientation": "", "bottom": 0, "state": "none"}, true))
	check("flex: sans capteur ni état = pas de flex", not L.is_half(hz.merged({"angle": -1}), false))
	# hystérésis : l'angle vibre autour de 25° ; l'état ne doit changer qu'une fois
	var was := false; var flips := 0
	for a in [24, 26, 24, 25, 23, 26, 24, 27, 22]:
		var now: bool = L.is_half(hz.merged({"angle": a}), was)
		if now != was: flips += 1
		was = now
	check("flex: hystérésis (vibration à 25°)", flips <= 1, "bascules=%d" % flips)
	# sortie à plat : 172° garde, 175° sort
	check("flex: sortie après 172°", L.is_half(hz.merged({"angle": 170}), true) and not L.is_half(hz.merged({"angle": 175}), true))

# ------------------------------------------------------------------ déplacement
func test_deplacement() -> void:
	rig = make_rig(); var p = rig["pointer"]; var f = rig["flex"]
	await settle()
	p.move_to(Vector2(300, 100))
	f._input(tch(padpos(), true)); f._input(drg(padpos(20, 0), Vector2(20, 0)))
	check("deplacement: part de la position de base", absf(p.pos.x - (300 + 20 * f.gain)) < 0.01 and p.pos.y == 100.0, str(p.pos))
	f._input(drg(padpos(20, 50), Vector2(0, 50)))
	check("deplacement: vertical", absf(p.pos.y - (100 + 50 * f.gain)) < 0.01, str(p.pos))
	var before: Vector2 = p.pos
	f._input(tch(padpos(20, 50), false))
	check("deplacement: reste en place au relâchement", p.pos == before, str(p.pos))
	# nouveau geste : repart de là, pas de saut
	f._input(tch(padpos(-200, -30), true)); f._input(drg(padpos(-170, -30), Vector2(30, 0)))
	check("deplacement: pas de saut au geste suivant", absf(p.pos.x - (before.x + 30 * f.gain)) < 0.01, str(p.pos))
	f._input(tch(padpos(-170, -30), false))
	# bornes
	for i in 200: f._input(tch(padpos(), true)); f._input(drg(padpos(400, -400), Vector2(400, -400))); f._input(tch(padpos(), false))
	check("deplacement: reste dans la zone haute", p.pos.x <= 1279.0 and p.pos.y >= 0.0 and p.pos.y <= 479.0, str(p.pos))
	# dépasser le bord haut du pavé : le curseur ignore les événements souris émulés
	p.move_to(Vector2(300, 100))
	var mp := InputEventMouseButton.new(); mp.button_index = MOUSE_BUTTON_LEFT; mp.pressed = true; mp.position = Vector2(640, 600); p._input(mp)
	var mm := InputEventMouseMotion.new(); mm.position = Vector2(640, 200); p._input(mm)
	check("curseur: ignore un geste du pavé qui dépasse le bord", p.pos == Vector2(300, 100), str(p.pos))
	var mr := InputEventMouseButton.new(); mr.button_index = MOUSE_BUTTON_LEFT; mr.pressed = false; mr.position = Vector2(640, 200); p._input(mr)
	var mt := InputEventMouseMotion.new(); mt.position = Vector2(90, 90); p._input(mt)
	check("curseur: suit un vrai toucher en haut après le relâchement", p.pos == Vector2(90, 90), str(p.pos))
	# un événement injecté « en retard » (ancienne position) ne ramène jamais le curseur en arrière
	p.move_to(Vector2(400, 150))
	var late := InputEventMouseMotion.new(); late.device = 4242; late.position = Vector2(50, 50); p._input(late)
	check("curseur: un ancien événement injecté ne le ramène pas en arrière", p.pos == Vector2(400, 150), str(p.pos))
	# relâchement perdu : le curseur ne reste pas figé
	p._input(mp); p._gesture_t = Time.get_ticks_msec() - 2000; p._swz_t = Time.get_ticks_msec() - 2000
	var mt2 := InputEventMouseMotion.new(); mt2.position = Vector2(120, 120); p._input(mt2)
	check("curseur: un relâchement perdu ne fige pas", p.pos == Vector2(120, 120), str(p.pos))
	await create_timer(0.4).timeout; rig["host"].queue_free(); rig["spy"].queue_free()

# ------------------------------------------------------------------ clics
func test_clics() -> void:
	rig = make_rig(); var f = rig["flex"]; var p = rig["pointer"]; var spy = rig["spy"]
	await settle()
	var warm := InputEventMouseMotion.new(); warm.position = Vector2(5, 5); Input.parse_input_event(warm); await settle()   # le tout premier événement injecté d'une fenêtre neuve peut être ignoré
	p.move_to(Vector2(200, 200))
	var L := func() -> int: return f.sent.filter(func(x): return x[0] == MOUSE_BUTTON_LEFT and x[1]).size()
	var R := func() -> int: return f.sent.filter(func(x): return x[0] == MOUSE_BUTTON_RIGHT and x[1]).size()
	f._input(tch(padpos(), true)); await create_timer(0.1).timeout; f._input(tch(padpos(), false)); await settle()
	check("clic: appui bref = 1 clic gauche", L.call() == 1 and R.call() == 0, "g=%d d=%d" % [L.call(), R.call()])
	f._input(tch(padpos(), true)); await create_timer(0.7).timeout; f._input(tch(padpos(), false)); await settle()
	check("clic: appui long = 1 clic droit", R.call() == 1 and L.call() == 1, "g=%d d=%d" % [L.call(), R.call()])
	f._input(tch(padpos(), true)); f._input(drg(padpos(40, 0), Vector2(40, 0))); f._input(tch(padpos(40, 0), false)); await settle()
	check("clic: un glissé ne clique pas", L.call() == 1 and R.call() == 1, "g=%d d=%d" % [L.call(), R.call()])
	for i in 3: f._input(tch(padpos(), true)); f._input(tch(padpos(), false))
	await create_timer(0.6).timeout
	check("clic: 3 appuis rapides = 3 clics (sans mélange)", L.call() == 4, "g=%d" % L.call())
	var seq: Array = f.sent.filter(func(x): return x[0] == MOUSE_BUTTON_LEFT).map(func(x): return x[1])
	check("clic: appuis et relâchements alternent", seq == [true, false, true, false, true, false, true, false], str(seq))
	f._input(tch(padpos(), true)); await create_timer(0.1).timeout; f._input(tch(padpos(), false, 0, true)); await settle()
	check("clic: une annulation ne clique pas", L.call() == 4, "g=%d" % L.call())
	await create_timer(0.4).timeout; rig["host"].queue_free(); spy.queue_free()

# ------------------------------------------------------------------ roulettes
func test_roulettes() -> void:
	rig = make_rig(); var f = rig["flex"]; var spy = rig["spy"]
	await settle()
	var wv: Rect2 = f._wv.get_global_rect(); var wh: Rect2 = f._wh.get_global_rect()
	var c := wv.get_center()
	f._input(tch(c, true)); f._input(drg(c + Vector2(0, 60), Vector2(0, 60))); f._input(tch(c + Vector2(0, 60), false)); await settle()
	check("roulette V: 60 px bas = 2 crans bas", f.sent.map(func(x): return x[0]) == [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_DOWN], str(f.sent))
	f.sent.clear()
	f._input(tch(c, true)); f._input(drg(c + Vector2(0, -53), Vector2(0, -53))); f._input(tch(c, false)); await settle()
	check("roulette V: 53 px haut = 2 crans haut", f.sent.map(func(x): return x[0]) == [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_UP], str(f.sent))
	f.sent.clear()
	var h := wh.get_center()
	f._input(tch(h, true)); f._input(drg(h + Vector2(-27, 0), Vector2(-27, 0))); f._input(tch(h, false)); await settle()
	check("roulette H: gauche = WHEEL_LEFT", f.sent.map(func(x): return x[0]) == [MOUSE_BUTTON_WHEEL_LEFT], str(f.sent))
	f.sent.clear()
	f._input(tch(h, true)); f._input(drg(h + Vector2(30, 0), Vector2(30, 0))); f._input(tch(h, false)); await settle()
	check("roulette H: droite = WHEEL_RIGHT", f.sent.map(func(x): return x[0]) == [MOUSE_BUTTON_WHEEL_RIGHT], str(f.sent))
	await create_timer(0.4).timeout; rig["host"].queue_free(); spy.queue_free()

# ------------------------------------------------------------------ pincement
func test_pincement() -> void:
	rig = make_rig(); var f = rig["flex"]; var p = rig["pointer"]; var zooms: Array = rig["zooms"]
	await settle()
	p.move_to(Vector2(300, 100))
	var a := padpos(-50, 0); var b := padpos(50, 0)
	f._input(tch(a, true, 0)); f._input(tch(b, true, 1))
	check("pincement: détecté à 2 doigts", f._pinching)
	f._input(drg(padpos(-100, 0), Vector2(-50, 0), 0)); f._input(drg(padpos(100, 0), Vector2(50, 0), 1))
	check("pincement: écarter = zoom > 1", not zooms.is_empty() and zooms[-1] > 1.5, str(zooms))
	f._input(drg(padpos(-20, 0), Vector2(80, 0), 0)); f._input(drg(padpos(20, 0), Vector2(-80, 0), 1))
	check("pincement: rapprocher = zoom < 1", zooms[-1] < 0.6, str(zooms))
	check("pincement: le curseur ne bouge pas pendant", p.pos == Vector2(300, 100), str(p.pos))
	f._input(tch(padpos(20, 0), false, 1))
	check("pincement: fini quand un doigt se lève", not f._pinching)
	# le doigt restant continue : pas de saut (position « last » à jour)
	f._input(drg(padpos(-15, 0), Vector2(5, 0), 0))
	check("pincement: pas de saut du doigt restant", p.pos.distance_to(Vector2(300, 100)) <= 5.0 * f.gain + 0.01, str(p.pos))
	f._input(tch(padpos(-15, 0), false, 0))
	check("pincement: nettoyage", f._fing.is_empty() and f.touches.is_empty() and not f._pinching)
	await create_timer(0.4).timeout; rig["host"].queue_free(); rig["spy"].queue_free()

# ------------------------------------------------------------------ annulation / nettoyage
func test_annulation_et_nettoyage() -> void:
	rig = make_rig(); var f = rig["flex"]
	await settle()
	f._input(tch(padpos(), true, 0)); f._input(tch(padpos(30, 0), true, 1))
	f._input(tch(padpos(), false, 0, true)); f._input(tch(padpos(30, 0), false, 1, true))
	check("annulation: tout est nettoyé", f._fing.is_empty() and f.touches.is_empty() and not f._pinching)
	f._input(tch(padpos(), true, 0)); f.reset_touches()
	check("reset: efface les doigts", f._fing.is_empty() and f.touches.is_empty())
	f._input(tch(padpos(), true, 0)); f._fing[0]["seen"] = Time.get_ticks_msec() - 25000; f._process(0.0)
	check("doigt muet 20 s: oublié", f._fing.is_empty() and f.touches.is_empty())
	await create_timer(0.4).timeout; rig["host"].queue_free(); rig["spy"].queue_free()

# ------------------------------------------------------------------ fuzz
func test_fuzz() -> void:
	rig = make_rig(); var f = rig["flex"]; var p = rig["pointer"]
	await settle()
	var rng := RandomNumberGenerator.new(); rng.seed = 12345
	var bad := 0
	for seq in 400:
		p.move_to(Vector2(rng.randf_range(0, 1279), rng.randf_range(0, 479)))
		var down := {}                     # index -> position
		for step in rng.randi_range(5, 80):
			var op := rng.randi() % 10
			var idx := rng.randi() % 3
			var pos := Vector2(rng.randf_range(-50, 1330), rng.randf_range(-50, 850))
			var before: Vector2 = p.pos
			if op < 3 and not down.has(idx): f._input(tch(pos, true, idx)); down[idx] = pos
			elif op < 7 and down.has(idx):
				var rel: Vector2 = pos - down[idx]; down[idx] = pos
				var pinch_before: bool = f._pinching
				f._input(drg(pos, rel, idx))
				if f._pinching or pinch_before:
					if p.pos != before: bad += 1; fails.append("fuzz: le curseur bouge pendant un pincement (seq %d)" % seq)
				elif p.pos.distance_to(before) > rel.length() * f.gain + 0.01:
					bad += 1; fails.append("fuzz: saut %f > %f (seq %d)" % [p.pos.distance_to(before), rel.length() * f.gain, seq])
			elif op < 9 and down.has(idx): f._input(tch(down[idx], false, idx)); down.erase(idx)
			elif down.has(idx): f._input(tch(down[idx], false, idx, true)); down.erase(idx)
			if not (p.pos.x >= 0.0 and p.pos.x <= 1279.0 and p.pos.y >= 0.0 and p.pos.y <= 479.0):
				bad += 1; fails.append("fuzz: curseur hors zone %s (seq %d)" % [str(p.pos), seq])
			if bad > 5: break
		for idx in down.keys(): f._input(tch(down[idx], false, idx))
		check("fuzz: aucun doigt fantôme (seq %d)" % seq, f._fing.is_empty() and f.touches.is_empty() and not f._pinching)
		if bad > 5: break
		if seq % 40 == 0: await create_timer(0.1).timeout
	check("fuzz: 400 séquences sans anomalie", bad == 0, "anomalies=%d" % bad)
	await create_timer(0.4).timeout; rig["host"].queue_free(); rig["spy"].queue_free()

# ------------------------------------------------------------------ le zoom ne fait pas disparaître le pavé
func test_zoom_stable() -> void:
	if DisplayServer.get_name() == "headless":
		print("PAD-TEST (zoom ignoré en headless : la fenêtre est minuscule ; lancer sans --headless avec --resolution 1280x800)"); return
	var m = load("res://main.tscn").instantiate(); root.add_child(m)
	await create_timer(1.0).timeout
	m.set_cfg["pad"] = true
	var hidden := []
	for z in [1.0, 0.5, 0.7, 1.5, 2.0, 2.2, 1.0]:
		m._set_zoom(z); await create_timer(0.3).timeout
		if not m.flex.visible: hidden.append(z)
		check("zoom %.1f: la zone haute reste valide" % z, m.pointer.pos.y < m.size.y and m.pointer.pos.x < m.size.x, str(m.pointer.pos))
	check("zoom: le pavé reste affiché à tous les zooms", hidden.is_empty(), str(hidden))
	m._set_zoom(1.0)
	await create_timer(1.0).timeout
	m.queue_free()

# ------------------------------------------------------------------ les clics tombent là où le curseur est dessiné, quelle que soit l'échelle
func test_echelle() -> void:
	for sc in [1.0, 1.5, 2.0, 0.6]:
		root.content_scale_factor = sc
		await create_timer(0.3).timeout
		rig = make_rig(); var f = rig["flex"]; var p = rig["pointer"]; var spy = rig["spy"]
		f.set("px_scale", -1.0)            # vraie transformation
		await settle()
		var warm := InputEventMouseMotion.new(); warm.position = Vector2(5, 5); Input.parse_input_event(warm); await settle()
		var target := Vector2(321, 123)
		p.move_to(target)
		var c: Vector2 = f._pad.get_global_rect().get_center()
		f._input(tch(c, true)); await create_timer(0.1).timeout; f._input(tch(c, false)); await settle()
		var ok: bool = spy.left_pos.size() == 1 and (spy.left_pos[0] as Vector2).distance_to(target) < 1.5
		check("échelle %.1f: le clic tombe sur le curseur" % sc, ok, "clic=%s curseur=%s" % [str(spy.left_pos), str(target)])
		check("échelle %.1f: le curseur ne saute pas à cause de ses propres clics" % sc, p.pos.distance_to(target) < 1.5, str(p.pos))
		await create_timer(0.4).timeout; rig["host"].queue_free(); spy.queue_free()
	root.content_scale_factor = 1.0

# ------------------------------------------------------------------ la surbrillance sous le curseur reste quand on lève le doigt du pavé
func test_survol() -> void:
	if DisplayServer.get_name() == "headless": return
	rig = make_rig(); var f = rig["flex"]; var p = rig["pointer"]; var host: Control = rig["host"]
	await settle()
	var btn := Button.new(); btn.text = "dossier"; btn.position = Vector2(100, 100); btn.size = Vector2(120, 60); host.add_child(btn)
	host.move_child(btn, 0)
	await settle()
	var warm := InputEventMouseMotion.new(); warm.position = Vector2(5, 5); Input.parse_input_event(warm); await settle()
	var c: Vector2 = f._pad.get_global_rect().get_center()
	p.move_to(Vector2(130, 120))
	# le doigt se pose, glisse un peu, se lève : les vrais événements (toucher + souris émulée) arrivent à l'endroit du doigt
	var t := InputEventScreenTouch.new(); t.index = 0; t.pressed = true; t.position = c; Input.parse_input_event(t); await create_timer(0.1).timeout
	var d := InputEventScreenDrag.new(); d.index = 0; d.position = c + Vector2(8, 0); d.relative = Vector2(8, 0); Input.parse_input_event(d); await create_timer(0.1).timeout
	check("survol: le bouton est survolé pendant le glissé", btn.is_hovered() or p.pos.x > 100)
	var u := InputEventScreenTouch.new(); u.index = 0; u.pressed = false; u.position = c + Vector2(8, 0); Input.parse_input_event(u)
	# Android envoie aussi les événements souris « émulés » à l'endroit du doigt (device -1)
	var em_mv := InputEventMouseMotion.new(); em_mv.position = c + Vector2(8, 0); em_mv.global_position = em_mv.position; em_mv.device = -1; em_mv.button_mask = 1; Input.parse_input_event(em_mv)
	var em_up := InputEventMouseButton.new(); em_up.button_index = MOUSE_BUTTON_LEFT; em_up.pressed = false; em_up.position = c + Vector2(8, 0); em_up.global_position = em_up.position; em_up.device = -1; Input.parse_input_event(em_up)
	await create_timer(0.5).timeout
	# le curseur a bougé de 8 * gain : il reste au-dessus du bouton (100..220 x 100..160)
	var over: bool = p.pos.x > 100 and p.pos.x < 220 and p.pos.y > 100 and p.pos.y < 160
	check("survol: le curseur est toujours sur le bouton", over, str(p.pos))
	check("survol: la surbrillance reste après le relâchement", btn.is_hovered(), "hover=%s pos=%s" % [str(btn.is_hovered()), str(p.pos)])
	await create_timer(1.0).timeout
	check("survol: et reste ensuite sans bouger", btn.is_hovered())
	# un événement souris émulé qui retombe sur le pavé (le doigt) ne doit pas retirer la surbrillance
	var stray := InputEventMouseMotion.new(); stray.position = c; stray.global_position = c; stray.device = -1; Input.parse_input_event(stray)
	await create_timer(0.1).timeout
	check("survol: un événement parasite sur le pavé ne retire pas la surbrillance", btn.is_hovered())
	# réaffirmation périodique : au repos, la position du curseur est renvoyée à l'interface (la surbrillance se répare seule)
	var cnt := {"n": 0}
	var spy2 := MotionSpy.new(); spy2.cnt = cnt; root.add_child(spy2)
	await create_timer(1.0).timeout
	check("survol: la position est réaffirmée au repos", cnt["n"] >= 2, "n=%d" % cnt["n"])
	var tt := InputEventScreenTouch.new(); tt.index = 0; tt.pressed = true; tt.position = c; Input.parse_input_event(tt); await create_timer(0.1).timeout
	cnt["n"] = 0; await create_timer(0.7).timeout
	check("survol: pas de réaffirmation pendant un geste du pavé", cnt["n"] == 0, "n=%d" % cnt["n"])
	var tu := InputEventScreenTouch.new(); tu.index = 0; tu.pressed = false; tu.position = c; Input.parse_input_event(tu); await create_timer(0.2).timeout
	spy2.queue_free()
	await create_timer(0.3).timeout; host.queue_free(); rig["spy"].queue_free()
