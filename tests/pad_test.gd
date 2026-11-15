extends SceneTree
## Tests logiques du pavé tactile, du curseur et de la détection du mode Flex.
## Lancer : flatpak run org.godotengine.Godot --headless --path . --script res://tests/pad_test.gd
## Sortie : « PAD-TEST OK » si tout passe, sinon la liste des échecs et un code de sortie 1.

var fails: Array = []
var checks := 0
var rig: Dictionary

class Spy extends Node:
	var left := 0
	var right := 0
	var wheel: Array = []
	func _input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			match ev.button_index:
				MOUSE_BUTTON_LEFT: left += 1
				MOUSE_BUTTON_RIGHT: right += 1
				_: wheel.append(ev.button_index)

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
	flex.set("top_h", 480.0); flex.set("touch_mode", true); flex.set("px_scale", 1.0)
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
	# relâchement perdu : le curseur ne reste pas figé
	p._input(mp); p._gesture_t = Time.get_ticks_msec() - 2000
	var mt2 := InputEventMouseMotion.new(); mt2.position = Vector2(120, 120); p._input(mt2)
	check("curseur: un relâchement perdu ne fige pas", p.pos == Vector2(120, 120), str(p.pos))
	await create_timer(0.4).timeout; rig["host"].queue_free(); rig["spy"].queue_free()

# ------------------------------------------------------------------ clics
func test_clics() -> void:
	rig = make_rig(); var f = rig["flex"]; var p = rig["pointer"]; var spy = rig["spy"]
	await settle()
	var warm := InputEventMouseMotion.new(); warm.position = Vector2(5, 5); Input.parse_input_event(warm); await settle()   # le tout premier événement injecté d'une fenêtre neuve peut être ignoré
	p.move_to(Vector2(200, 200))
	f._input(tch(padpos(), true)); await create_timer(0.1).timeout; f._input(tch(padpos(), false)); await settle()
	check("clic: appui bref = 1 clic gauche", spy.left == 1 and spy.right == 0, "g=%d d=%d" % [spy.left, spy.right])
	f._input(tch(padpos(), true)); await create_timer(0.7).timeout; f._input(tch(padpos(), false)); await settle()
	check("clic: appui long = 1 clic droit", spy.right == 1 and spy.left == 1, "g=%d d=%d" % [spy.left, spy.right])
	f._input(tch(padpos(), true)); f._input(drg(padpos(40, 0), Vector2(40, 0))); f._input(tch(padpos(40, 0), false)); await settle()
	check("clic: un glissé ne clique pas", spy.left == 1 and spy.right == 1, "g=%d d=%d" % [spy.left, spy.right])
	for i in 3: f._input(tch(padpos(), true)); f._input(tch(padpos(), false))
	await create_timer(0.6).timeout
	check("clic: 3 appuis rapides = 3 clics (sans mélange)", spy.left == 4, "g=%d" % spy.left)
	f._input(tch(padpos(), true)); await create_timer(0.1).timeout; f._input(tch(padpos(), false, 0, true)); await settle()
	check("clic: une annulation ne clique pas", spy.left == 4, "g=%d" % spy.left)
	await create_timer(0.4).timeout; rig["host"].queue_free(); spy.queue_free()

# ------------------------------------------------------------------ roulettes
func test_roulettes() -> void:
	rig = make_rig(); var f = rig["flex"]; var spy = rig["spy"]
	await settle()
	var wv: Rect2 = f._wv.get_global_rect(); var wh: Rect2 = f._wh.get_global_rect()
	var c := wv.get_center()
	f._input(tch(c, true)); f._input(drg(c + Vector2(0, 60), Vector2(0, 60))); f._input(tch(c + Vector2(0, 60), false)); await settle()
	check("roulette V: 60 px bas = 2 crans bas", spy.wheel == [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_DOWN], str(spy.wheel))
	spy.wheel.clear()
	f._input(tch(c, true)); f._input(drg(c + Vector2(0, -53), Vector2(0, -53))); f._input(tch(c, false)); await settle()
	check("roulette V: 53 px haut = 2 crans haut", spy.wheel == [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_UP], str(spy.wheel))
	spy.wheel.clear()
	var h := wh.get_center()
	f._input(tch(h, true)); f._input(drg(h + Vector2(-27, 0), Vector2(-27, 0))); f._input(tch(h, false)); await settle()
	check("roulette H: gauche = WHEEL_LEFT", spy.wheel == [MOUSE_BUTTON_WHEEL_LEFT], str(spy.wheel))
	spy.wheel.clear()
	f._input(tch(h, true)); f._input(drg(h + Vector2(30, 0), Vector2(30, 0))); f._input(tch(h, false)); await settle()
	check("roulette H: droite = WHEEL_RIGHT", spy.wheel == [MOUSE_BUTTON_WHEEL_RIGHT], str(spy.wheel))
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
