class_name HeartsBar
extends Control
## Barre de vie façon Minecraft : 10 cœurs (2 PV chacun), demi-cœurs, tremblement à faible vie.

static var HEART := PackedVector2Array([
	Vector2(0.5, 0.95), Vector2(0.08, 0.5), Vector2(0.02, 0.3), Vector2(0.12, 0.1), Vector2(0.3, 0.02),
	Vector2(0.5, 0.2), Vector2(0.7, 0.02), Vector2(0.88, 0.1), Vector2(0.98, 0.3), Vector2(0.92, 0.5)])
const SIZE := 26.0
const GAP := 2.0
var hp := 20.0
var max_hp := 20.0
var _flash := 0.0

func _init() -> void:
	custom_minimum_size = Vector2(10 * (SIZE + GAP), SIZE + 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_hp(v: float, m: float) -> void:
	if v < hp:
		_flash = 0.25
	hp = v
	max_hp = m
	queue_redraw()

func _process(dt: float) -> void:
	_flash = maxf(_flash - dt, 0.0)
	if hp <= 6.0 or _flash > 0.0:
		queue_redraw()

func _poly(origin: Vector2, color: Color, clip_half: bool = false) -> void:
	var pts := PackedVector2Array()
	for v in HEART:
		pts.append(origin + v * SIZE)
	if clip_half:
		var clipped := PackedVector2Array()
		for v in HEART:
			clipped.append(origin + Vector2(minf(v.x, 0.5), v.y) * SIZE)
		pts = Geometry2D.convex_hull(clipped)
	if pts.size() >= 3:
		draw_colored_polygon(pts, color)

func _draw() -> void:
	var n := int(max_hp / 2.0)
	for i in n:
		var jitter := Vector2(0, randf_range(-2, 2)) if hp <= 6.0 else Vector2.ZERO
		var o := Vector2(i * (SIZE + GAP), 3) + jitter
		_poly(o - Vector2(1, 1) * 1.5, Color(0, 0, 0, 0.6))      # contour
		_poly(o, Color(0.22, 0.05, 0.07, 0.85))                    # cœur vide
		var v := hp - i * 2.0
		var full := Color(1, 1, 1) if _flash > 0.0 else Color(0.92, 0.12, 0.18)
		if v >= 2.0:
			_poly(o, full)
		elif v >= 1.0:
			_poly(o, full, true)
