extends PanelContainer
## Pavé tactile du bas de l'écran (mode Flex d'un téléphone pliable, ou réglage « pavé tactile ») : un doigt qui glisse déplace
## le curseur dans la moitié haute, un appui bref clique, un appui long fait un clic droit. Boutons gauche (maintenir = glisser) / droit.

var pointer: Control
var top_h := 400.0            # hauteur de la zone pilotée (haut de l'écran)
var gain := 0.7
var _t0 := 0
var _moved := 0.0
var _down := false
var _hold_left := false

func _ready() -> void:
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("141824"); sb.border_color = Color(1, 1, 1, 0.12); sb.border_width_top = 1
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); add_child(v)
	var m := MarginContainer.new(); m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 10)
	v.add_child(m)
	var pad := PanelContainer.new(); pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ps := StyleBoxFlat.new(); ps.bg_color = Color("1d2230"); ps.set_corner_radius_all(14); ps.border_color = Color(1, 1, 1, 0.1); ps.set_border_width_all(1)
	pad.add_theme_stylebox_override("panel", ps); m.add_child(pad)
	var l := Label.new(); l.text = "Pavé tactile\nglisse · touche = clic · appui long = clic droit"; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; l.add_theme_color_override("font_color", Color(1, 1, 1, 0.3)); l.mouse_filter = Control.MOUSE_FILTER_IGNORE; pad.add_child(l)
	pad.gui_input.connect(_pad_input)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); row.custom_minimum_size.y = 64; v.add_child(row)
	var bl := Button.new(); bl.text = "Clic gauche (maintenir = glisser)"; bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bl.focus_mode = Control.FOCUS_NONE
	bl.button_down.connect(func(): _hold_left = true; _btn(MOUSE_BUTTON_LEFT, true)); bl.button_up.connect(func(): _hold_left = false; _btn(MOUSE_BUTTON_LEFT, false)); row.add_child(bl)
	var br := Button.new(); br.text = "Clic droit"; br.size_flags_horizontal = Control.SIZE_EXPAND_FILL; br.focus_mode = Control.FOCUS_NONE
	br.pressed.connect(func(): _click(MOUSE_BUTTON_RIGHT)); row.add_child(br)

func _pad_input(ev: InputEvent) -> void:
	if pointer == null: return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed: _down = true; _t0 = Time.get_ticks_msec(); _moved = 0.0
		elif _down:
			_down = false
			var dt := Time.get_ticks_msec() - _t0
			if _moved < 12.0:
				if dt < 300: _click(MOUSE_BUTTON_LEFT)
				elif dt > 550: _click(MOUSE_BUTTON_RIGHT)
		accept_event()
	elif ev is InputEventMouseMotion and _down:
		var d: Vector2 = ev.relative * gain
		_moved += d.length()
		var np: Vector2 = (pointer.pos + d).clamp(Vector2.ZERO, Vector2(get_viewport_rect().size.x - 1.0, maxf(1.0, top_h - 1.0)))
		pointer.move_to(np)
		var e := InputEventMouseMotion.new(); e.position = np; e.global_position = np; e.relative = d
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if _hold_left else 0
		Input.call_deferred("parse_input_event", e)
		accept_event()

func _btn(idx: int, down: bool) -> void:
	var e := InputEventMouseButton.new(); e.button_index = idx; e.pressed = down; e.position = pointer.pos; e.global_position = pointer.pos
	e.button_mask = (1 << (idx - 1)) if down else 0
	pointer.pressed = down; pointer.queue_redraw()
	Input.call_deferred("parse_input_event", e)

func _click(idx: int) -> void:
	var mv := InputEventMouseMotion.new(); mv.position = pointer.pos; mv.global_position = pointer.pos; Input.call_deferred("parse_input_event", mv)
	_btn(idx, true)
	await get_tree().create_timer(0.05).timeout
	_btn(idx, false)
