class_name BotBrain
extends Node
## IA simple : va vers le lit adverse en construisant le pont, combat les joueurs proches,
## défend son lit. Utilise les mêmes commandes/autorité qu'un joueur humain.

var p: PlayerController
var turn_speed := 9.0
var react_time := 0.3
var _react := 0.0
var _place_cd := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _was_fighting := false

func _nearest_enemy() -> PlayerController:
	var best: PlayerController = null
	var bd := 1e9
	for o in p.game.team_manager.players:
		if o == p or o.team == p.team or not o.alive:
			continue
		var d := o.global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = o
	return best

func gather(c: InputCmd, dt: float) -> void:
	c.clear()
	if not p.alive:
		return
	_place_cd = maxf(_place_cd - dt, 0.0)
	_strafe_t -= dt
	if _strafe_t <= 0.0:
		_strafe = -_strafe if randf() < 0.5 else _strafe
		_strafe_t = randf_range(0.4, 1.0)
	var my_bed: Vector3 = Cfg.BEDS[p.team]
	var target: Vector3 = Cfg.BEDS[1 - p.team]
	var enemy := _nearest_enemy()
	var fight := false
	var dist := 99.0
	if enemy:
		dist = Vector2(enemy.global_position.x - p.global_position.x, enemy.global_position.z - p.global_position.z).length()
		var threat := enemy.global_position.distance_to(my_bed) < 14.0
		if dist < 9.0 or threat:
			fight = true
			target = enemy.global_position
	if fight and not _was_fighting:
		_react = react_time
	_was_fighting = fight
	_react = maxf(_react - dt, 0.0)

	# Orientation
	var d := target - p.global_position
	var want_yaw := atan2(-d.x, -d.z)
	p.yaw = lerp_angle(p.yaw, want_yaw, clampf(dt * turn_speed, 0.0, 1.0))
	if fight and enemy:
		var chest := enemy.global_position + Vector3(0, 1.0, 0) - p.eye_pos()
		var flat := Vector2(chest.x, chest.z).length()
		p.pitch = lerpf(p.pitch, atan2(chest.y, maxf(flat, 0.01)), clampf(dt * turn_speed, 0.0, 1.0))
	else:
		p.pitch = lerpf(p.pitch, 0.0, clampf(dt * 5.0, 0.0, 1.0))

	# Déplacement
	c.move = Vector2(0, 1)
	c.sprint = true
	if fight and dist < 2.5:
		c.move = Vector2(_strafe * 0.8, 0.5 if dist > 1.3 else 0.0)

	# Pont / obstacles
	if p.is_on_floor():
		var pos := p.global_position
		var fwd := p.flat_forward()
		var ahead := pos + fwd * 0.8
		var base_y := floori(pos.y - 0.1)
		var cell_below := Vector3i(floori(ahead.x), base_y, floori(ahead.z))
		if not p.blocks.is_solid(cell_below):
			var placed := false
			if p.inv.block_count > 0 and not (fight and dist < 2.5):
				p.inv.select(Cfg.Slot.BLOCKS)
				if _place_cd <= 0.0:
					var mine := Vector3i(floori(pos.x), base_y, floori(pos.z))
					var cands: Array[Vector3i] = [cell_below,
						mine + Vector3i(int(signf(fwd.x)) if absf(fwd.x) > 0.3 else 0, 0, 0),
						mine + Vector3i(0, 0, int(signf(fwd.z)) if absf(fwd.z) > 0.3 else 0)]
					for cc in cands:
						if p.authority.request_place(p, cc):
							placed = true
							break
					_place_cd = Tuning.place_cooldown
			if not placed:
				c.move = Vector2.ZERO
				c.sprint = false
		var wall := Vector3i(floori(ahead.x), floori(pos.y + 0.1), floori(ahead.z))
		if p.blocks.is_solid(wall):
			c.jump_pressed = true

	# Combat
	if fight and enemy and dist < 3.2:
		p.inv.select(Cfg.Slot.SWORD)
		if _react <= 0.0:
			c.attack_held = true
	elif p.inv.selected == Cfg.Slot.SWORD and not fight:
		p.inv.select(Cfg.Slot.BLOCKS)
