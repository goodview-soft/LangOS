class_name HumanInput
extends Node
## Entrées clavier/souris du joueur local.

var p: PlayerController
var _jump_at := -1.0
var _attack_at := -1.0
var _scroll := 0

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _unhandled_input(e: InputEvent) -> void:
	if get_tree().paused:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if e is InputEventMouseButton and e.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if e is InputEventMouseMotion:
		p.yaw -= e.relative.x * Tuning.mouse_sens
		p.pitch = clampf(p.pitch - e.relative.y * Tuning.mouse_sens, -1.5, 1.5)
	elif e.is_action_pressed("jump"):
		_jump_at = _now()
	elif e.is_action_pressed("attack"):
		_attack_at = _now()
	elif e.is_action_pressed("scroll_up"):
		_scroll -= 1
	elif e.is_action_pressed("scroll_down"):
		_scroll += 1

func gather(c: InputCmd, _dt: float) -> void:
	c.clear()
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not captured:
		_scroll = 0
		return
	c.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	c.sprint = Input.is_action_pressed("sprint")
	c.sneak = Input.is_action_pressed("sneak")
	var now := _now()
	c.jump_pressed = now - _jump_at < 0.05
	c.attack_pressed = now - _attack_at < 0.05
	c.attack_held = Input.is_action_pressed("attack")
	c.use_held = Input.is_action_pressed("use")
	c.scroll = _scroll
	_scroll = 0
	for i in 3:
		if Input.is_action_just_pressed("slot_%d" % (i + 1)):
			c.select_slot = i
