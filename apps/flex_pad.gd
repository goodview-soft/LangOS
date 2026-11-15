extends PanelContainer
## Pavé tactile du bas de l'écran (mode Flex d'un pliable, ou réglage « pavé tactile »).
## - un doigt qui glisse : déplace le curseur dans la moitié haute ; appui bref = clic ; appui long = clic droit
## - roulette verticale (à droite) et horizontale (en dessous) : défilement
## - deux doigts qui s'écartent / se rapprochent : zoom de l'interface
## - boutons : clic gauche (maintenir = glisser) et clic droit

var pointer: Control
var on_zoom: Callable          # (facteur: float) -> void, fourni par le bureau
var get_zoom: Callable         # () -> float
var top_h := 400.0             # hauteur de la zone pilotée (haut de l'écran)
var gain := 0.7
var _t0 := 0
var _moved := 0.0
var _down := false
var _last := Vector2.ZERO      # dernière position du doigt (calcul du déplacement sans les sauts de Godot)
var _hold_left := false
var _pad: Control
var _wv: Wheel
var _wh: Wheel
var touch_mode := false          # écran tactile : gestes lus via les événements tactiles (pas de capture de souris par le pavé)
var _fing := {}                  # index -> {zone, last (px vue), t0, moved}
var touches := {}              # index -> position fenêtre (pixels)
var _pinching := false
var _d0 := 1.0
var _z0 := 1.0

## Roulette : un doigt qui glisse émet « step(+1/-1) » tous les `pitch` pixels.
class Wheel extends Control:
	signal step(dir: int)
	var horizontal := false
	var pitch := 26.0
	var _acc := 0.0
	var _off := 0.0
	var _drag := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
	func feed(d: float) -> void:
		_acc += d; _off += d
		while absf(_acc) >= pitch:
			step.emit(1 if _acc > 0.0 else -1); _acc -= pitch * signf(_acc)
		queue_redraw()
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			_drag = ev.pressed; _acc = 0.0; accept_event()
		elif ev is InputEventMouseMotion and _drag:
			feed((ev.position - _last_pos).x if horizontal else (ev.position - _last_pos).y); accept_event()
		if ev is InputEventMouse: _last_pos = ev.position
	var _last_pos := Vector2.ZERO
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("1d2230"), true)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.1), false, 1.0)
		var n := int((size.x if horizontal else size.y) / 14.0) + 2
		for i in n:
			var o := fposmod(_off, 14.0) + i * 14.0 - 14.0
			if horizontal: draw_line(Vector2(o, 8), Vector2(o, size.y - 8), Color(1, 1, 1, 0.25), 2.0)
			else: draw_line(Vector2(8, o), Vector2(size.x - 8, o), Color(1, 1, 1, 0.25), 2.0)

func _ready() -> void:
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("141824"); sb.border_color = Color(1, 1, 1, 0.12); sb.border_width_top = 1
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); add_child(v)
	var m := MarginContainer.new(); m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top"]: m.add_theme_constant_override("margin_" + k, 10)
	m.add_theme_constant_override("margin_bottom", 0)
	v.add_child(m)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 8); m.add_child(top)
	_pad = PanelContainer.new(); _pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ps := StyleBoxFlat.new(); ps.bg_color = Color("1d2230"); ps.set_corner_radius_all(14); ps.border_color = Color(1, 1, 1, 0.1); ps.set_border_width_all(1)
	_pad.add_theme_stylebox_override("panel", ps); top.add_child(_pad)
	var l := Label.new(); l.text = "Pavé tactile\nglisse · touche = clic · appui long = clic droit\n2 doigts = zoom"; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; l.add_theme_color_override("font_color", Color(1, 1, 1, 0.3)); l.mouse_filter = Control.MOUSE_FILTER_IGNORE; _pad.add_child(l)
	_pad.gui_input.connect(_pad_input)
	var wv := Wheel.new(); _wv = wv; wv.custom_minimum_size.x = 60; wv.step.connect(func(d: int): _wheel(MOUSE_BUTTON_WHEEL_DOWN if d > 0 else MOUSE_BUTTON_WHEEL_UP)); top.add_child(wv)
	var hr := HBoxContainer.new(); hr.add_theme_constant_override("separation", 8); hr.custom_minimum_size.y = 52; v.add_child(hr)
	var hm := MarginContainer.new(); hm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hm.add_theme_constant_override("margin_left", 10); hm.add_theme_constant_override("margin_right", 78); hr.add_child(hm)
	var wh := Wheel.new(); _wh = wh; wh.horizontal = true; wh.custom_minimum_size.y = 52; wh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wh.step.connect(func(d: int): _wheel(MOUSE_BUTTON_WHEEL_RIGHT if d > 0 else MOUSE_BUTTON_WHEEL_LEFT)); hm.add_child(wh)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); row.custom_minimum_size.y = 64; v.add_child(row)
	var bl := Button.new(); bl.text = "Clic gauche (maintenir = glisser)"; bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bl.focus_mode = Control.FOCUS_NONE
	bl.button_down.connect(func(): _hold_left = true; _btn(MOUSE_BUTTON_LEFT, true)); bl.button_up.connect(func(): _hold_left = false; _btn(MOUSE_BUTTON_LEFT, false)); row.add_child(bl)
	var br := Button.new(); br.text = "Clic droit"; br.size_flags_horizontal = Control.SIZE_EXPAND_FILL; br.focus_mode = Control.FOCUS_NONE
	br.pressed.connect(func(): _click(MOUSE_BUTTON_RIGHT)); row.add_child(br)
	touch_mode = DisplayServer.is_touchscreen_available()
	if touch_mode:
		# Sur écran tactile, ni le panneau, ni le pavé, ni les roulettes ne captent la souris émulée : les gestes passent par _input,
		# et les événements injectés dans la moitié haute ne sont plus détournés vers le pavé.
		mouse_filter = Control.MOUSE_FILTER_IGNORE; _pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_wv.mouse_filter = Control.MOUSE_FILTER_IGNORE; _wh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for n in [l]: n.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _px(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p

func _zone_at(pos: Vector2) -> String:
	if _wv.get_global_rect().has_point(pos): return "wv"
	if _wh.get_global_rect().has_point(pos): return "wh"
	if _pad.get_global_rect().has_point(pos): return "pad"
	return ""

func _input(ev: InputEvent) -> void:
	if not visible: return
	if ev is InputEventScreenTouch:
		if ev.pressed:
			var z := _zone_at(ev.position)
			if z != "": touches[ev.index] = _px(ev.position)
			if touch_mode and z != "": _fing[ev.index] = {"zone": z, "last": ev.position, "t0": Time.get_ticks_msec(), "moved": 0.0}
		else:
			if touch_mode and _fing.has(ev.index): _touch_release(_fing[ev.index])
			if touch_mode: _fing.erase(ev.index)
			touches.erase(ev.index)
		var pad_fingers := 0
		for k in _fing: if _fing[k]["zone"] == "pad": pad_fingers += 1
		if touches.size() == 2:
			var k: Array = touches.keys()
			_d0 = maxf(8.0, (touches[k[0]] - touches[k[1]]).length()); _z0 = float(get_zoom.call()) if get_zoom.is_valid() else 1.0
			_pinching = true; _down = false
		elif touches.size() < 2: _pinching = false
	elif ev is InputEventScreenDrag:
		if touches.has(ev.index): touches[ev.index] = _px(ev.position)
		if touches.size() == 2 and on_zoom.is_valid():
			var k: Array = touches.keys()
			on_zoom.call(_z0 * (touches[k[0]] - touches[k[1]]).length() / _d0)
		elif touch_mode and not _pinching and _fing.has(ev.index):
			var f: Dictionary = _fing[ev.index]
			var delta: Vector2 = ev.position - f["last"]
			f["last"] = ev.position
			match f["zone"]:
				"pad": f["moved"] += delta.length(); _move_pointer(delta * gain)
				"wv": _wv.feed(delta.y)
				"wh": _wh.feed(delta.x)

func _touch_release(f: Dictionary) -> void:
	if f["zone"] != "pad" or _pinching: return
	var dt: int = Time.get_ticks_msec() - int(f["t0"])
	if float(f["moved"]) < 12.0:
		if dt < 300: _click(MOUSE_BUTTON_LEFT)
		elif dt > 550: _click(MOUSE_BUTTON_RIGHT)

func _move_pointer(d: Vector2) -> void:
	var np: Vector2 = (pointer.pos + d).clamp(Vector2.ZERO, Vector2(get_viewport_rect().size.x - 1.0, maxf(1.0, top_h - 1.0)))
	pointer.move_to(np)
	var e := InputEventMouseMotion.new(); e.position = np; e.global_position = np; e.relative = d
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if _hold_left else 0
	Input.call_deferred("parse_input_event", e)

func _pad_input(ev: InputEvent) -> void:
	if pointer == null or _pinching or touch_mode: return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed: _down = true; _t0 = Time.get_ticks_msec(); _moved = 0.0; _last = ev.position
		elif _down:
			_down = false
			var dt := Time.get_ticks_msec() - _t0
			if _moved < 12.0:
				if dt < 300: _click(MOUSE_BUTTON_LEFT)
				elif dt > 550: _click(MOUSE_BUTTON_RIGHT)
		accept_event()
	elif ev is InputEventMouseMotion and _down:
		# déplacement calculé ici : le « relative » des événements émulés depuis le toucher saute au début de chaque geste
		var d: Vector2 = (ev.position - _last) * gain
		_last = ev.position
		_moved += d.length()
		_move_pointer(d)
		accept_event()

func _wheel(idx: int) -> void:
	var e := InputEventMouseButton.new(); e.button_index = idx; e.pressed = true; e.factor = 1.0; e.position = pointer.pos; e.global_position = pointer.pos
	Input.call_deferred("parse_input_event", e)
	var u := InputEventMouseButton.new(); u.button_index = idx; u.pressed = false; u.position = pointer.pos; u.global_position = pointer.pos
	Input.call_deferred("parse_input_event", u)

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
