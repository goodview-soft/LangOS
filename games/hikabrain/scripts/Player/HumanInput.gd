class_name HumanInput
extends Node
## Entrées du joueur local : clavier/souris (souris capturée) et contrôles tactiles (HikaTouch) cumulables.

var p: PlayerController
var _jump_at := -1.0
var _attack_at := -1.0
var _scroll := 0

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _touch_on() -> bool:
	return p.game.touch != null and p.game.touch.on

func _unhandled_input(e: InputEvent) -> void:
	if p.game.is_paused():
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# un clic réel reprend la souris (les échos « souris » d'un toucher sont ignorés)
		if e is InputEventMouseButton and e.pressed and e.device != -1 and p.game.touch == null and p.game.match_manager.state != Cfg.State.LOBBY:
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
	elif e.is_action_pressed("auto_bridge"):
		p.auto_bridge = not p.auto_bridge
		p.game.announce("Pont automatique : " + ("activé" if p.auto_bridge else "désactivé") + "  (B)", Color(1, 0.9, 0.5))

func gather(c: InputCmd, _dt: float) -> void:
	c.clear()
	if p.game.is_paused():
		_scroll = 0
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		c.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		c.sprint = Input.is_action_pressed("sprint")
		c.sneak = Input.is_action_pressed("sneak")
		var now := _now()
		c.jump_pressed = now - _jump_at < 0.05
		c.attack_pressed = now - _attack_at < 0.05
		c.attack_held = Input.is_action_pressed("attack")
		c.use_held = Input.is_action_pressed("use")
		c.scroll = _scroll
		for i in 3:
			if Input.is_action_just_pressed("slot_%d" % (i + 1)):
				c.select_slot = i
	_scroll = 0
	if _touch_on():
		var t := p.game.touch
		if t.move.length() > 0.05:
			c.move = t.move
			if t.move.length() > 0.92 and t.move.y > 0.5:
				c.sprint = true
		c.jump_pressed = c.jump_pressed or t.take_jump() or t.jump_held
		c.attack_pressed = c.attack_pressed or t.take_hit()
		c.attack_held = c.attack_held or t.hit_held
		c.use_held = c.use_held or t.place_held
