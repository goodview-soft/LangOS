extends Button
## Icône flottante « quitter le jeu » (coin haut droit d'un jeu). Prend les clics/touchers dans son rectangle
## AVANT le jeu hôte (qui lit _input à la main) ; n'intercepte rien ailleurs.
var _down := false

func _ready() -> void:
	flat = true; focus_mode = Control.FOCUS_NONE; mouse_filter = Control.MOUSE_FILTER_STOP
	modulate = Color(1, 1, 1, 0.55); z_index = 100; top_level = false

func _hit(p: Vector2) -> bool:
	return is_visible_in_tree() and get_global_rect().has_point(p)

func _input(ev: InputEvent) -> void:
	var p := Vector2.ZERO
	var pressed := false
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		p = ev.global_position; pressed = ev.pressed
	elif ev is InputEventScreenTouch:
		p = get_viewport().get_canvas_transform().affine_inverse() * ev.position; pressed = ev.pressed
	else:
		return
	if pressed and _hit(p):
		_down = true; get_viewport().set_input_as_handled()
	elif not pressed and _down:
		_down = false; get_viewport().set_input_as_handled()
		if _hit(p): pressed_exit.emit()

signal pressed_exit
