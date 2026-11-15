extends Control
## Curseur de souris affiché là où le doigt touche (écrans tactiles), et cible des clics du pavé tactile (apps/flex_pad.gd).

var pos := Vector2(-200, -200)
var pressed := false
var mode := "auto"            # auto (écrans tactiles) | on | off
var pad_active := false       # pavé tactile affiché : le curseur reste visible et suit le pavé
var pad_top := -1.0           # y (vue) à partir duquel commence le pavé : les vrais doigts y sont ignorés
var _last := 0
var swallow := false          # écran tactile : les événements souris émulés sur le pavé sont avalés
var reassert_fn: Callable
var zone_fn: Callable         # position → "pad" | "wv" | "wh" | "" (fourni par le pavé)
var _swz := false
var _swz_t := 0
const INJ := 4242
var _gesture_t := 0
var _gesture := false        # geste commencé sur le pavé : ignoré tant que le doigt n'est pas levé, même s'il dépasse le bord haut du pavé

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 4000
	var t := Timer.new(); t.wait_time = 0.5; t.autostart = true; t.timeout.connect(queue_redraw); add_child(t)

func _wanted() -> bool:
	if mode == "off": return false
	return mode == "on" or pad_active or DisplayServer.is_touchscreen_available()

func _input(ev: InputEvent) -> void:
	if not _wanted() or not (ev is InputEventMouse): return
	if swallow and ev.device != INJ and zone_fn.is_valid():
		if _swz and Time.get_ticks_msec() - _swz_t > 1500: _swz = false          # un relâchement perdu ne fige pas le curseur
		var inpad: bool = str(zone_fn.call(ev.position)) != ""
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed: _swz = inpad; _swz_t = Time.get_ticks_msec()
			elif _swz: _swz = false; get_viewport().set_input_as_handled(); return
		if inpad or _swz:
			_swz_t = Time.get_ticks_msec()
			get_viewport().set_input_as_handled()      # ni le curseur ni la surbrillance ne sont touchés par le doigt sur le pavé
			if reassert_fn.is_valid(): reassert_fn.call()
			return
	if pad_top < 0.0 or (_gesture and Time.get_ticks_msec() - _gesture_t > 1500): _gesture = false   # un relâchement perdu ne fige pas le curseur
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed: _gesture = pad_top >= 0.0 and ev.position.y >= pad_top; _gesture_t = Time.get_ticks_msec()
		elif _gesture: _gesture = false; return
	if _gesture: _gesture_t = Time.get_ticks_msec(); return
	if pad_top >= 0.0 and ev.position.y >= pad_top: return        # doigt sur le pavé : c'est le pavé qui déplace le curseur
	pos = ev.position
	if ev is InputEventMouseButton: pressed = ev.pressed
	_last = Time.get_ticks_msec(); queue_redraw()

## Déplace le curseur (appelé par le pavé tactile).
func move_to(p: Vector2) -> void:
	pos = p; _last = Time.get_ticks_msec(); queue_redraw()

func _draw() -> void:
	if not _wanted(): return
	if not pad_active and Time.get_ticks_msec() - _last > 3000: return
	var k := 1.4
	var pts := PackedVector2Array()
	for q in [Vector2(0, 0), Vector2(0, 17), Vector2(4.5, 13), Vector2(8, 20.5), Vector2(11, 19), Vector2(7.6, 12), Vector2(13, 12)]: pts.append(pos + q * k)
	if pressed: draw_circle(pos, 16, Color(0.35, 0.65, 1.0, 0.35))
	draw_colored_polygon(pts, Color.WHITE)
	var o := pts.duplicate(); o.append(pts[0])
	draw_polyline(o, Color.BLACK, 1.8, true)
