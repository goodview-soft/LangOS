extends SceneTree
var fails := 0
func ok(c: bool, m: String) -> void:
	if not c: fails += 1; print("ECHEC: ", m)
	else: print("ok: ", m)
func mk(m := "ai", lvl := 1) -> Control:
	var g: Control = load("res://apps/airhockey.gd").new()
	g.size = Vector2(300, 640); root.add_child(g); await process_frame
	g._start(m); g.menu.visible = false; g.level = lvl; g.freeze = 0.0
	return g
func _init() -> void:
	# friction + rebond
	var g := await mk("local")
	g.pp = Vector2(200, 100); g.pv = Vector2(0, 150); g.mp[1] = Vector2(340, 200); g.mt[1] = g.mp[1]
	for i in 120: g.step(g.STEP)
	g.mp[1] = Vector2(340, 200); g.mt[1] = g.mp[1]
	ok(g.pv.length() < 150 and g.pv.length() > 70, "frottement léger (%.0f)" % g.pv.length())
	ok(g.pp.x >= g.PR and g.pp.x <= g.W - g.PR, "reste dans le terrain")
	g.pp = Vector2(g.PR + 5, 320); g.pv = Vector2(-500, 0); g.step(g.STEP * 3)
	ok(g.pv.x > 0, "rebond sur le bord")
	# mallet -> palet
	g.pp = Vector2(200, 400); g.pv = Vector2.ZERO; g.mp[0] = Vector2(200, 460); g.mt[0] = Vector2(200, 300)
	for i in 20: g.step(g.STEP)
	ok(g.pv.y < -300, "transfert de vitesse mallet->palet (%.0f)" % g.pv.y)
	g.pv = Vector2(0, -5000); g.step(g.STEP); ok(g.pv.length() <= g.PUCK_MAX + 1, "vitesse max")
	# limitation à sa moitié
	g.set_target(0, Vector2(200, 50)); for i in 600: g.step(g.STEP)
	ok(g.mp[0].y >= g.H / 2 + g.MR - 0.1, "mallet limité à sa moitié")
	# but avec encoche + score + victoire
	g = await mk("local"); g.mp[1] = Vector2(340, 200); g.mt[1] = g.mp[1]
	g.pp = Vector2(200, 100); g.pv = Vector2(0, -400); for i in 50: g.step(g.STEP)
	ok(g.score[0] == 1 and g.freeze > 0.0, "but marqué + remise en jeu")
	g.pp = Vector2(40, 100); g.pv = Vector2(0, -400); g.freeze = 0; for i in 100: g.step(g.STEP)
	ok(g.score[0] == 1, "pas de but hors de l'encoche")
	g.target_score = 2; g.pp = Vector2(200, 100); g.pv = Vector2(0, -400); g.freeze = 0; for i in 200: g.step(g.STEP)
	ok(g.winner == 0, "victoire au score cible")
	# IA marque contre mallet adverse inerte, aux 3 niveaux
	for lvl in 3:
		g = await mk("ai", lvl); g.target_score = 99
		g.pp = Vector2(200, 200); g.pv = Vector2.ZERO
		g.set_target(0, Vector2(40, 600))
		var t := 0.0
		while g.score[1] < 1 and t < 90.0 and g.score[0] == 0: g.step(g.STEP); t += g.STEP
		ok(g.score[1] >= 1, "IA niveau %d marque (%.1f s)" % [lvl, t])
	# IA défend : humain tire, IA difficile arrête au moins une partie
	g = await mk("ai", 2); g.target_score = 99; var conc := 0
	for k in 6:
		g.pp = Vector2(100 + k * 40, 380); g.pv = Vector2(0, -700); g.freeze = 0; g.mp[0] = Vector2(200, 560)
		var before: int = g.score[0]
		for i in 360: g.step(g.STEP)
		if g.score[0] > before: conc += 1
	ok(conc < 6, "IA difficile défend (%d/6 encaissés)" % conc)
	# sérialisation réseau
	var h := await mk("local"); h.pp = Vector2(123.4, 234.5); h.pv = Vector2(50, -60); h.score = [3, 2]; h.mp[0] = Vector2(150, 500)
	var snap: Dictionary = JSON.parse_string(JSON.stringify(h.snapshot()))
	var gu := await mk("ai"); gu._start("net", 1, "x"); gu.menu.visible = false
	gu.apply_snapshot(snap)
	ok(gu.guest and gu.pp.distance_to(Vector2(123.4, 234.5)) < 0.2 and gu.score == [3, 2] and gu.pv.x == 50.0, "snapshot aller-retour")
	for i in 30: gu._guest_frame(1.0 / 60.0)
	ok(gu.disp_m0.distance_to(Vector2(150, 500)) < 5.0, "interpolation invité")
	gu._geom(); ok(gu.to_logic(gu.xf * Vector2(100, 100)).distance_to(Vector2(100, 100)) < 0.01, "transformation retournée inversible")
	var hh := await mk("net"); hh._start("net", 0, "y"); hh.menu.visible = false
	hh._on_msg({"t": "m", "x": 200.0, "y": 60.0}); for i in 60: hh.step(hh.STEP)
	ok(hh.mp[1].distance_to(Vector2(200, 60)) < 2.0, "mallet invité reçu côté hôte")
	# dessin sans erreur, largeur 300 et 800
	for w in [300, 800]:
		g.size = Vector2(w, 640); g._geom()
		var s: float = g.xf.x.length()
		ok(g.xf.origin.x >= -1 and g.W * s <= w + 1, "terrain tient en largeur %d" % w)
	print("FINI échecs=", fails)
	quit(1 if fails > 0 else 0)
