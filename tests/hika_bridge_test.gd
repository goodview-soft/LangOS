extends SceneTree
## Test headless du pont automatique (Hikabrain) et de la mise en page tactile.
## Lancer : flatpak run org.godotengine.Godot --headless --path . --script res://tests/hika_bridge_test.gd
## Sortie : « HIKA-BRIDGE OK » si tout passe, sinon la liste des échecs (code 1).

var fails: Array = []

class Walk extends Node:
	var on := true
	var jump := false
	func gather(c: InputCmd, _dt: float) -> void:
		c.clear()
		if on:
			c.move = Vector2(0, 1)
			c.jump_pressed = jump

func _check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + msg)
	if not cond:
		fails.append(msg)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	# ---- mise en page tactile (pure) : portée, taille mini, pas de chevauchement, icône de sortie dégagée
	for sz in [Vector2(1280, 720), Vector2(800, 360), Vector2(360, 740), Vector2(412, 915)]:
		var t := HikaTouch.new()
		t.layout(sz)
		var ok := true
		for i in t.buttons.size():
			var b: Dictionary = t.buttons[i]
			var c: Vector2 = b["c"]
			var r: float = b["r"]
			if r * 2.0 < 44.0 or c.x - r < 0.0 or c.y - r < 0.0 or c.x + r > sz.x or c.y + r > sz.y:
				ok = false
				print("    bouton hors limites/trop petit ", b["id"], " ", c, " ", r)
			for j in range(i + 1, t.buttons.size()):
				var o: Dictionary = t.buttons[j]
				if c.distance_to(o["c"]) < r + float(o["r"]):
					ok = false
					print("    chevauchement ", b["id"], "/", o["id"])
			if b["id"] != "pause":
				var exit_rect := Rect2(sz.x - 8.0 - 44.0, 8.0, 44.0, 44.0)
				if exit_rect.grow(4.0).intersects(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)):
					ok = false
					print("    chevauche l'icône de sortie ", b["id"])
		var pause_b: Dictionary = t.buttons[5]
		if Rect2(sz.x - 52.0, 8.0, 44.0, 44.0).intersects(Rect2((pause_b["c"] as Vector2) - Vector2(pause_b["r"], pause_b["r"]), Vector2(pause_b["r"], pause_b["r"]) * 2.0)):
			ok = false
		if t.stick_c.x - t.stick_r < 0.0 or t.stick_c.y + t.stick_r > sz.y:
			ok = false
		_check(ok, "mise en page tactile %dx%d" % [sz.x, sz.y])
		t.free()
	# ---- pont automatique : jeu complet (mode test, sans SelfTest)
	var scn: PackedScene = load("res://games/hikabrain/scenes/game.tscn")
	var game: GameManager = scn.instantiate()
	game.set_meta("manual", true)
	root.add_child(game)
	Engine.time_scale = 1.0   # ServerAuthority limite la cadence sur l'horloge murale : pas d'accéléré ici
	while game.match_manager.state != Cfg.State.PLAYING:
		await process_frame
	var a := game.team_manager.players[0]
	var b := game.team_manager.players[1]
	b.ai_paused = true
	a.inv.select(Cfg.Slot.BLOCKS)
	var w := Walk.new()
	a.add_child(w)
	a.provider = w
	a.yaw = Cfg.SPAWN_YAW[0]   # vers l'est : îlot rouge, pont de départ (x 16..21), puis le vide
	a.ai_paused = false
	await create_timer(0.3).timeout
	var stock := a.inv.block_count
	# 1) sans l'option : on avance jusqu'au bout du pont et on tombe, aucun bloc posé
	a.auto_bridge = false
	await create_timer(3.0).timeout
	_check(a.inv.block_count == stock, "option désactivée : aucun bloc posé (%d)" % a.inv.block_count)
	_check(a.global_position.x > 21.0, "le joueur est bien sorti du pont (x=%.1f)" % a.global_position.x)
	while not a.alive:
		await process_frame
	await create_timer(2.5).timeout   # réapparition + fin de la protection de manche éventuelle
	while game.match_manager.state != Cfg.State.PLAYING:
		await process_frame
	# 2) avec l'option : sur le sol plein (île + pont) rien n'est posé, dans le vide un pont se construit
	a.global_position = Cfg.SPAWNS[0]
	a.velocity = Vector3.ZERO
	a.yaw = Cfg.SPAWN_YAW[0]
	a.inv.reset()
	stock = a.inv.block_count
	a.auto_bridge = true
	w.on = true
	await create_timer(1.5).timeout
	_check(a.global_position.x > 12.0 and a.global_position.x < 20.0 and a.inv.block_count == stock, "sol plein : rien posé (x=%.1f, stock=%d)" % [a.global_position.x, a.inv.block_count])
	await create_timer(4.0).timeout
	var placed := 0
	for x in range(22, 45):
		if game.blocks.get_block(Vector3i(x, 7, 12)) == Cfg.B_RED_PLACED:
			placed += 1
	_check(placed >= 6, "pont construit dans le vide (%d blocs au niveau du sol)" % placed)
	_check(a.inv.block_count == stock - placed or a.inv.block_count < stock, "stock consommé (%d -> %d)" % [stock, a.inv.block_count])
	_check(a.alive and a.global_position.y > 7.5, "le joueur ne tombe pas (y=%.2f)" % a.global_position.y)
	_check(a.global_position.x > 24.0, "il a traversé le vide (x=%.1f)" % a.global_position.x)
	# 3) cadence : jamais plus d'un bloc par cooldown de pose
	_check(placed <= int(7.0 / (Tuning.place_cooldown * 0.8)), "cadence limitée")
	# 4) sans stock : rien ne se pose, la case occupée n'est pas rejouée
	w.on = false
	var cell := Vector3i(floori(a.global_position.x), 7, floori(a.global_position.z))
	_check(game.blocks.is_solid(cell), "la case sous les pieds est occupée")
	var ab := AutoBridge.new(a)
	ab.ref_y = 8
	var c := InputCmd.new()
	c.move = Vector2(0, 1)
	_check(ab.plan(c) == AutoBridge.NONE or not game.blocks.is_solid(ab.plan(c)), "plan() ne vise jamais une case occupée")
	# 5) arme sélectionnée ou accroupi : pas de pose
	a.inv.select(Cfg.Slot.SWORD)
	_check(not ab.tick(c, 1.0), "épée en main : pas de pose")
	a.inv.select(Cfg.Slot.BLOCKS)
	c.sneak = true
	_check(ab.plan(c) == AutoBridge.NONE, "accroupi : pas de pose")
	print("HIKA-BRIDGE ", "OK" if fails.is_empty() else "ECHEC: " + str(fails))
	quit(0 if fails.is_empty() else 1)
