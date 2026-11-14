class_name ServerAuthority
extends Node
## Couche autoritaire : TOUTE action de jeu (dégâts, blocs, score) est validée ici.
## En local elle tourne dans le même processus ; sur un serveur dédié, les clients
## enverront seulement des requêtes (InputCmd / intentions) qui arriveront à ces fonctions.

signal attack_landed(attacker: PlayerController, victim: PlayerController, damage: float)
signal block_placed(player: PlayerController, cell: Vector3i)
signal block_broken(player: PlayerController, cell: Vector3i)

var game: GameManager
var _last_attack := {}
var _last_place := {}

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _can_act(p: PlayerController) -> bool:
	return p.alive and not p.frozen and game.match_manager.state == Cfg.State.PLAYING

## Retourne le joueur touché (ou null).
func request_attack(att: PlayerController) -> PlayerController:
	if not _can_act(att):
		return null
	var t := _now()
	if t - float(_last_attack.get(att, -10.0)) < Tuning.attack_cooldown * 0.9:
		return null
	_last_attack[att] = t
	var eye := att.eye_pos()
	var dir := att.aim_dir()
	var best: PlayerController = null
	var best_ang := 999.0
	for o in game.team_manager.players:
		if o == att or not o.alive:
			continue
		var tp := Vector3(o.global_position.x, clampf(eye.y, o.global_position.y + 0.2, o.global_position.y + 1.6), o.global_position.z)
		var to := tp - eye
		var dist := to.length()
		if dist - 0.3 > Tuning.attack_range:
			continue
		var ang := acos(clampf(to.normalized().dot(dir), -1.0, 1.0))
		var tol := deg_to_rad(Tuning.attack_cone_deg) + atan(0.3 / maxf(dist, 0.1))
		if ang > tol or ang >= best_ang:
			continue
		var los := game.blocks.raycast(eye, to.normalized(), dist)
		if not los.is_empty() and float(los["dist"]) < dist - 0.35:
			continue
		best = o
		best_ang = ang
	if best == null:
		return null
	if best.health.take_damage(Tuning.sword_damage, att):
		var kdir := best.global_position - att.global_position
		kdir.y = 0.0
		kdir = (kdir.normalized() * 0.7 + att.flat_forward() * 0.3)
		best.knock.apply(kdir, att.move.sprinting)
		best.last_attacker = att
		best.last_attacker_time = t
		best.flash()
		Sfx.play(game, "hit", best.global_position, randf_range(0.9, 1.1))
		if best.is_local:
			Sfx.play(game, "hurt")
		attack_landed.emit(att, best, Tuning.sword_damage)
	return best

func _reach_ok(p: PlayerController, cell: Vector3i) -> bool:
	var eye := p.eye_pos()
	var cmin := Vector3(cell)
	var closest := Vector3(clampf(eye.x, cmin.x, cmin.x + 1.0), clampf(eye.y, cmin.y, cmin.y + 1.0), clampf(eye.z, cmin.z, cmin.z + 1.0))
	return eye.distance_to(closest) <= Tuning.reach + 0.5

func _cell_blocked_by_player(cell: Vector3i) -> bool:
	var cmin := Vector3(cell)
	var cmax := cmin + Vector3.ONE
	for o in game.team_manager.players:
		if not o.alive:
			continue
		var pmin := o.global_position + Vector3(-0.3, 0.0, -0.3)
		var pmax := o.global_position + Vector3(0.3, 1.8, 0.3)
		const E := 0.02
		if pmin.x < cmax.x - E and pmax.x > cmin.x + E and pmin.y < cmax.y - E and pmax.y > cmin.y + E and pmin.z < cmax.z - E and pmax.z > cmin.z + E:
			return true
	return false

func request_place(p: PlayerController, cell: Vector3i) -> bool:
	if not _can_act(p):
		return false
	var t := _now()
	if t - float(_last_place.get(p, -10.0)) < Tuning.place_cooldown * 0.8:
		return false
	var b := game.blocks
	if not b.in_bounds(cell) or b.is_solid(cell) or p.inv.block_count <= 0:
		return false
	if game.arena.is_build_forbidden(cell) or not _reach_ok(p, cell):
		return false
	var has_neighbor := false
	for n in BlockManager.FACE_N:
		if b.is_solid(cell + n):
			has_neighbor = true
			break
	if not has_neighbor or _cell_blocked_by_player(cell):
		return false
	_last_place[p] = t
	p.inv.consume_block()
	b.set_block(cell, Cfg.placed_block(p.team))
	Sfx.play(game, "place", Vector3(cell) + Vector3(0.5, 0.5, 0.5), randf_range(0.95, 1.1))
	block_placed.emit(p, cell)
	return true

func request_break(p: PlayerController, cell: Vector3i) -> bool:
	if not _can_act(p):
		return false
	var b := game.blocks
	if not b.is_destructible(cell) or game.arena.is_build_forbidden(cell) or not _reach_ok(p, cell):
		return false
	b.set_block(cell, Cfg.B_AIR)
	Sfx.play(game, "break", Vector3(cell) + Vector3(0.5, 0.5, 0.5), randf_range(0.9, 1.1))
	block_broken.emit(p, cell)
	return true
