extends PanelContainer
const UI = preload("res://apps/ui.gd")
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
var _click_busy := false
var sent: Array = []            # journal des clics/défilements envoyés (tests) : [bouton, appuyé]
const INJ := 4242              # marque des événements injectés par le pavé (ils ne sont jamais avalés)
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
	func reset() -> void:
		_acc = 0.0
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
		draw_rect(Rect2(Vector2.ZERO, size), UI.p("card"), true)
		draw_rect(Rect2(Vector2.ZERO, size), UI.p("edge"), false, 1.0)
		var n := int((size.x if horizontal else size.y) / 14.0) + 2
		for i in n:
			var o := fposmod(_off, 14.0) + i * 14.0 - 14.0
			if horizontal: draw_line(Vector2(o, 8), Vector2(o, size.y - 8), Color(UI.p("ov"), 0.25), 2.0)
			else: draw_line(Vector2(8, o), Vector2(size.x - 8, o), Color(UI.p("ov"), 0.25), 2.0)

func _ready() -> void:
	var sb := StyleBoxFlat.new(); sb.bg_color = UI.p("bar"); sb.border_color = UI.p("edge"); sb.border_width_top = 1
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); add_child(v)
	var m := MarginContainer.new(); m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top"]: m.add_theme_constant_override("margin_" + k, 10)
	m.add_theme_constant_override("margin_bottom", 0)
	v.add_child(m)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 8); m.add_child(top)
	_pad = PanelContainer.new(); _pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ps := StyleBoxFlat.new(); ps.bg_color = UI.p("card"); ps.set_corner_radius_all(UI.rad(2)); ps.border_color = UI.p("edge"); ps.set_border_width_all(1)
	_pad.add_theme_stylebox_override("panel", ps); top.add_child(_pad)
	var l := Label.new(); l.text = "Pavé tactile\nglisse · touche = clic · appui long = clic droit\n2 doigts = zoom"; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; l.add_theme_color_override("font_color", Color(UI.p("muted"), 0.7)); l.mouse_filter = Control.MOUSE_FILTER_IGNORE; _pad.add_child(l)
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
	set_touch_mode(DisplayServer.is_touchscreen_available())
	var ka := Timer.new(); ka.wait_time = 0.2; ka.autostart = true; ka.timeout.connect(_keepalive); add_child(ka)

## Sur écran tactile, ni le panneau, ni le pavé, ni les roulettes ne captent la souris émulée : les gestes passent par _input,
## les événements souris émulés tombant sur le pavé sont avalés (sinon l'interface croit que la souris est sous le doigt et
## retire la surbrillance de ce qui est sous le curseur), et les événements injectés dans la moitié haute ne sont plus détournés vers le pavé.
func set_touch_mode(on: bool) -> void:
	touch_mode = on
	var f := Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP
	mouse_filter = f; _pad.mouse_filter = f; _wv.mouse_filter = f; _wh.mouse_filter = f
	if pointer != null:
		pointer.set("swallow", on); pointer.set("zone_fn", Callable(self, "_zone_at")); pointer.set("reassert_fn", Callable(self, "reassert"))

var _re_pending := false
## Renvoie tout de suite la position du curseur virtuel : l'interface suit la dernière position de souris connue, y compris celle d'un
## événement parasite (doigt sur le pavé) ; une fois par image au plus, juste après l'événement, la surbrillance n'a pas le temps de partir.
func reassert() -> void:
	if _re_pending or pointer == null: return
	_re_pending = true
	await get_tree().process_frame
	_re_pending = false
	var e := InputEventMouseMotion.new(); e.device = INJ; e.position = _inj(pointer.pos); e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if _hold_left else 0
	Input.parse_input_event(e)

## Réaffirme la position du curseur virtuel (survol) : une perte de survol par n'importe quel événement parasite se répare en 250 ms.
func _keepalive() -> void:
	if not visible or pointer == null or _fing.size() > 0 or _down: return
	var e := InputEventMouseMotion.new(); e.device = INJ; e.position = _inj(pointer.pos); e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if _hold_left else 0
	Input.call_deferred("parse_input_event", e)

## Position « interface » → pixels fenêtre : les événements injectés dans Input sont lus en pixels, puis ramenés à l'interface par la fenêtre.
func _inj(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p

var px_scale := -1.0           # tests : échelle fixe (la fenêtre headless est minuscule) ; sinon transformation réelle vue → pixels
func _px(p: Vector2) -> Vector2:
	return p * px_scale if px_scale > 0.0 else get_viewport().get_final_transform() * p

func _zone_at(pos: Vector2) -> String:
	if _wv.get_global_rect().has_point(pos): return "wv"
	if _wh.get_global_rect().has_point(pos): return "wh"
	if _pad.get_global_rect().has_point(pos): return "pad"
	return ""

func _input(ev: InputEvent) -> void:
	if not visible: return
	if ev is InputEventScreenTouch:
		if ev.pressed and not ev.canceled:
			var z := _zone_at(ev.position)
			if z != "": touches[ev.index] = _px(ev.position)
			if z == "wv": _wv.reset()          # le reste d'un geste précédent ne fausse pas le premier cran
			if z == "wh": _wh.reset()
			if touch_mode and z != "": _fing[ev.index] = {"zone": z, "last": ev.position, "t0": Time.get_ticks_msec(), "moved": 0.0, "seen": Time.get_ticks_msec()}
		else:
			# relâchement ou annulation (geste système d'Android, fenêtre perdue…) : jamais de clic sur une annulation
			if touch_mode and _fing.has(ev.index) and not ev.canceled: _touch_release(_fing[ev.index])
			_fing.erase(ev.index); touches.erase(ev.index)
			# doigt levé : Android peut signaler « la souris est sortie » -> on réaffirme tout de suite la position du curseur virtuel
			get_tree().create_timer(0.04).timeout.connect(_keepalive)
			get_tree().create_timer(0.15).timeout.connect(_keepalive)
		_pinching = touches.size() >= 2
		if _pinching:
			var k: Array = touches.keys()
			_d0 = maxf(8.0, (touches[k[0]] - touches[k[1]]).length()); _z0 = float(get_zoom.call()) if get_zoom.is_valid() else 1.0
	elif ev is InputEventScreenDrag:
		if touches.has(ev.index): touches[ev.index] = _px(ev.position)
		var f = _fing.get(ev.index)
		var delta := Vector2.ZERO
		if f != null:
			delta = ev.position - f["last"]; f["last"] = ev.position; f["seen"] = Time.get_ticks_msec()   # toujours mis à jour (pas de saut à la fin d'un pincement)
		if _pinching:
			if touches.size() == 2 and on_zoom.is_valid():
				var k: Array = touches.keys()
				on_zoom.call(_z0 * (touches[k[0]] - touches[k[1]]).length() / _d0)
		elif touch_mode and f != null:
			match f["zone"]:
				"pad": f["moved"] += delta.length(); _move_pointer(delta * gain)
				"wv": _wv.feed(delta.y)
				"wh": _wh.feed(delta.x)

## Oublie tous les doigts (fenêtre masquée, perte de focus, doigt perdu).
func reset_touches() -> void:
	_fing.clear(); touches.clear(); _pinching = false; _down = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: reset_touches()

func _process(_d: float) -> void:
	# un « relâchement » perdu ne doit pas bloquer le pavé : un doigt muet depuis plus de 20 s est oublié
	if _fing.is_empty(): return
	var now := Time.get_ticks_msec()
	for k in _fing.keys():
		if now - int(_fing[k]["seen"]) > 20000: _fing.erase(k); touches.erase(k)
	_pinching = touches.size() >= 2

func _touch_release(f: Dictionary) -> void:
	if f["zone"] != "pad" or _pinching: return
	var dt: int = Time.get_ticks_msec() - int(f["t0"])
	if float(f["moved"]) < 12.0:
		if dt < 300: _click(MOUSE_BUTTON_LEFT)
		elif dt > 550: _click(MOUSE_BUTTON_RIGHT)

func _move_pointer(d: Vector2) -> void:
	var np: Vector2 = (pointer.pos + d).clamp(Vector2.ZERO, Vector2(get_viewport_rect().size.x - 1.0, maxf(1.0, top_h - 1.0)))
	pointer.move_to(np)
	var e := InputEventMouseMotion.new(); e.device = INJ; e.position = _inj(np); e.global_position = e.position; e.relative = d
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
	sent.append([idx, true]); if sent.size() > 200: sent.pop_front()
	var e := InputEventMouseButton.new(); e.device = INJ; e.button_index = idx; e.pressed = true; e.factor = 1.0; e.position = _inj(pointer.pos); e.global_position = e.position
	Input.call_deferred("parse_input_event", e)
	var u := InputEventMouseButton.new(); u.device = INJ; u.button_index = idx; u.pressed = false; u.position = _inj(pointer.pos); u.global_position = u.position
	Input.call_deferred("parse_input_event", u)

func _btn(idx: int, down: bool) -> void:
	var e := InputEventMouseButton.new(); e.device = INJ; e.button_index = idx; e.pressed = down; e.position = _inj(pointer.pos); e.global_position = e.position
	e.button_mask = (1 << (idx - 1)) if down else 0
	pointer.pressed = down; pointer.queue_redraw()
	sent.append([idx, down]); if sent.size() > 200: sent.pop_front()
	Input.call_deferred("parse_input_event", e)

func _click(idx: int) -> void:
	while _click_busy: await get_tree().process_frame     # deux appuis rapprochés ne se mélangent pas
	_click_busy = true
	var mv := InputEventMouseMotion.new(); mv.device = INJ; mv.position = _inj(pointer.pos); mv.global_position = mv.position; Input.call_deferred("parse_input_event", mv)
	_btn(idx, true)
	await get_tree().create_timer(0.05).timeout
	_btn(idx, false)
	_click_busy = false
