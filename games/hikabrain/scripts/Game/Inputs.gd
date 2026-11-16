class_name Inputs
## Enregistre les actions d'entrée (touches physiques : WASD = ZQSD sur AZERTY).

static func setup() -> void:
	if InputMap.has_action("move_forward"):
		return
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("jump", KEY_SPACE)
	_key("sprint", KEY_SHIFT)
	_key("sneak", KEY_CTRL)
	_key("slot_1", KEY_1)
	_key("slot_2", KEY_2)
	_key("slot_3", KEY_3)
	_key("scoreboard", KEY_TAB)
	_key("auto_bridge", KEY_B)
	_mouse("attack", MOUSE_BUTTON_LEFT)
	_mouse("use", MOUSE_BUTTON_RIGHT)
	_mouse("scroll_up", MOUSE_BUTTON_WHEEL_UP)
	_mouse("scroll_down", MOUSE_BUTTON_WHEEL_DOWN)

static func _key(action: String, code: Key) -> void:
	InputMap.add_action(action)
	var e := InputEventKey.new()
	e.physical_keycode = code
	InputMap.action_add_event(action, e)

static func _mouse(action: String, btn: MouseButton) -> void:
	InputMap.add_action(action)
	var e := InputEventMouseButton.new()
	e.button_index = btn
	InputMap.action_add_event(action, e)
