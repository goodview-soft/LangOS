class_name SelfTest
extends Node
## Test headless : lancer avec  `scenes/game.tscn -- --hb-test`.

var game: GameManager
var fails: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + msg)
	if not cond:
		fails.append(msg)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	Engine.time_scale = 3.0
	var mm := game.match_manager
	while mm.state != Cfg.State.PLAYING:
		await get_tree().process_frame
	var a := game.team_manager.players[0]
	var b := game.team_manager.players[1]
	a.ai_paused = true
	b.ai_paused = true
	await get_tree().create_timer(0.3).timeout
	print("[test] blocs")
	a.inv.select(Cfg.Slot.BLOCKS)
	a.yaw = Cfg.SPAWN_YAW[0]
	var cell := Vector3i(12, 8, 9)
	_check(game.authority.request_place(a, cell), "placement valide")
	_check(game.blocks.get_block(cell) == Cfg.B_RED_PLACED, "bloc rouge présent")
	_check(a.inv.block_count == Tuning.start_blocks - 1, "inventaire décrémenté")
	_check(not game.authority.request_place(a, Vector3i(5, 8, 10)), "zone du lit interdite")
	_check(not game.authority.request_place(a, Vector3i(12, 30, 9)), "hors limite de hauteur refusé")
	_check(not game.authority.request_break(a, Vector3i(12, 7, 12)), "bloc de base indestructible")
	await get_tree().create_timer(0.2).timeout
	var t := a.blocks.raycast(Vector3(12.5, 12, 9.5), Vector3.DOWN, 10.0)
	_check(not t.is_empty() and t["cell"] == cell, "raycast voxel touche le bloc posé")
	_check(game.authority.request_break(a, cell), "destruction valide")
	_check(game.blocks.get_block(cell) == Cfg.B_AIR, "bloc détruit")
	print("[test] combat")
	b.global_position = a.global_position + a.flat_forward() * 2.0
	b.velocity = Vector3.ZERO
	await get_tree().create_timer(0.3).timeout
	var hit := game.authority.request_attack(a)
	_check(hit == b, "épée touche la cible")
	_check(b.health.hp == Tuning.max_health - Tuning.sword_damage, "dégâts appliqués")
	_check(Vector2(b.velocity.x, b.velocity.z).length() > 4.0 and b.velocity.y > 3.0, "knockback (v=%s)" % b.velocity)
	print("[test] chute dans le vide")
	b.global_position = Vector3(30, 8, 12)
	await get_tree().create_timer(3.0).timeout
	_check(b.deaths >= 1, "mort par chute détectée")
	_check(b.alive, "respawn effectué")
	print("[test] match complet (IA vs IA)")
	a.ai_paused = false
	b.ai_paused = false
	var elapsed := 0.0
	while mm.state != Cfg.State.MATCH_FINISHED and elapsed < 400.0:
		if int(elapsed) % 10 == 0 and elapsed < 60.0:
			print("  t=", elapsed, " a=", a.global_position.snapped(Vector3(0.1,0.1,0.1)), " b=", b.global_position.snapped(Vector3(0.1,0.1,0.1)), " ba=", a.inv.block_count, " bb=", b.inv.block_count, " st=", mm.state)
		await get_tree().create_timer(1.0).timeout
		elapsed += 1.0
	print("  K/D a=", a.kills, "/", a.deaths, " b=", b.kills, "/", b.deaths, " blocs a=", a.inv.block_count, " b=", b.inv.block_count)
	print("  scores: ", game.score_manager.scores, "  état=", mm.state, "  t=", elapsed)
	_check(game.score_manager.scores[0] + game.score_manager.scores[1] > 0, "au moins un point marqué")
	print("SELFTEST ", "OK" if fails.is_empty() else "ECHEC: " + str(fails))
	get_tree().quit(0 if fails.is_empty() else 1)
