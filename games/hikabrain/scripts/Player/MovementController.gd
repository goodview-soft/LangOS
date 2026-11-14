class_name MovementController
extends Node
## Déplacement FPS : accélération/décélération, contrôle aérien, coyote time, jump buffering.

signal jumped
signal landed(speed: float)

var p: PlayerController
var sprinting := false
var sneaking := false
var _coyote := 0.0
var _buffer := 0.0
var _was_on_floor := false
var _pre_vy := 0.0

func reset() -> void:
	_coyote = 0.0
	_buffer = 0.0
	sprinting = false

func step(c: InputCmd, dt: float) -> void:
	var on_floor := p.is_on_floor()
	_coyote = Tuning.coyote_time if on_floor else maxf(_coyote - dt, 0.0)
	_buffer = Tuning.jump_buffer if c.jump_pressed else maxf(_buffer - dt, 0.0)

	var fwd := p.flat_forward()
	var right := Vector3(fwd.z * -1.0, 0, fwd.x)   # fwd tourné de -90° autour de Y
	var wish := right * c.move.x + fwd * c.move.y
	if wish.length() > 1.0:
		wish = wish.normalized()
	sneaking = c.sneak and on_floor
	sprinting = c.sprint and c.move.y > 0.1 and not c.sneak
	var top_speed := Tuning.sneak_speed if sneaking else (Tuning.sprint_speed if sprinting else Tuning.walk_speed)

	var hv := Vector3(p.velocity.x, 0, p.velocity.z)
	var kb_active := p.knock.active()
	if wish.length() > 0.01:
		var wd := wish.normalized()
		var scale := Tuning.kb_control_scale if kb_active else 1.0
		if on_floor:
			hv = hv.move_toward(wish * top_speed, Tuning.ground_accel * scale * dt)
		else:
			var cur := hv.dot(wd)
			var add := clampf(top_speed * wish.length() - cur, 0.0, Tuning.air_accel * scale * dt)
			hv += wd * add
	else:
		if on_floor:
			hv = hv.move_toward(Vector3.ZERO, Tuning.ground_decel * p.knock.friction_scale() * dt)
		else:
			hv = hv.move_toward(Vector3.ZERO, Tuning.air_drag * dt)
	if not kb_active:
		hv = hv.limit_length(Tuning.sprint_speed * Tuning.max_air_speed_mult)

	if sneaking:
		# Accroupi : on ne peut pas tomber du bord (comme Minecraft)
		var pos := p.global_position
		if not _supported(pos + Vector3(hv.x * dt, 0, 0)):
			hv.x = 0.0
		if not _supported(pos + Vector3(hv.x * dt, 0, hv.z * dt)):
			hv.z = 0.0

	var vy := p.velocity.y
	if on_floor and vy <= 0.0:
		vy = 0.0
	else:
		vy = maxf(vy - Tuning.gravity * dt, -Tuning.max_fall_speed)
	if _buffer > 0.0 and _coyote > 0.0:
		vy = Tuning.jump_velocity
		_buffer = 0.0
		_coyote = 0.0
		jumped.emit()

	_pre_vy = vy
	p.velocity = Vector3(hv.x, vy, hv.z)
	p.move_and_slide()
	var now_floor := p.is_on_floor()
	if now_floor and not _was_on_floor and _pre_vy < -5.0:
		landed.emit(-_pre_vy)
	_was_on_floor = now_floor

func _supported(pos: Vector3) -> bool:
	var y := floori(pos.y - 0.1)
	for ox in [-0.3, 0.3]:
		for oz in [-0.3, 0.3]:
			if p.blocks.is_solid(Vector3i(floori(pos.x + ox), y, floori(pos.z + oz))):
				return true
	return false
