extends Control
## Vue graphe des notes : disposition à forces calculée progressivement (grille spatiale), zoom, déplacement, voisins en surbrillance.
const UI = preload("res://apps/ui.gd")
signal open_requested(key: String)

var nodes: Array = []            # clés de notes
var edges: Array = []            # [i, j]
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var adj: Array = []              # voisins de chaque nœud
var deg: Array = []
var focus := -1                  # note courante
var hover := -1
var drag := -1
var pan := false
var moved := 0.0
var zoom := 1.0
var off := Vector2.ZERO
var iters := 0
const MAX_ITERS := 320
const REST := 70.0
const CELL := 140.0

func set_data(g: Dictionary, current := "") -> void:
	nodes = g["nodes"]; edges = g["edges"]; deg = g["deg"]
	var n := nodes.size()
	pos.resize(n); vel.resize(n); adj = []
	for i in n:
		adj.append([])
		var a := float(hash(str(nodes[i])) % 10000) / 10000.0 * TAU
		var r := 40.0 + 14.0 * sqrt(float(i)) * (1.0 + float(hash(str(nodes[i]) + "r") % 100) / 200.0)
		pos[i] = Vector2(cos(a), sin(a)) * r; vel[i] = Vector2.ZERO
	for e in edges: adj[e[0]].append(e[1]); adj[e[1]].append(e[0])
	focus = nodes.find(current); hover = -1; iters = 0
	set_process(n > 1); _fit(); queue_redraw()

func set_focus(key: String) -> void:
	focus = nodes.find(key); queue_redraw()

## Une itération de la simulation (répulsion locale par grille + ressorts + gravité).
func step() -> void:
	var n := nodes.size()
	if n < 2: return
	var f := PackedVector2Array(); f.resize(n)
	var grid := {}
	for i in n:
		var c := Vector2i(floori(pos[i].x / CELL), floori(pos[i].y / CELL))
		if not grid.has(c): grid[c] = []
		grid[c].append(i)
	for c: Vector2i in grid:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var o := Vector2i(c.x + dx, c.y + dy)
				if not grid.has(o): continue
				for i: int in grid[c]:
					for j: int in grid[o]:
						if i >= j: continue
						var d: Vector2 = pos[i] - pos[j]
						var l2 := maxf(d.length_squared(), 25.0)
						if l2 > CELL * CELL: continue
						var fr := d / l2 * 2600.0
						f[i] += fr; f[j] -= fr
	for e in edges:
		var d: Vector2 = pos[e[1]] - pos[e[0]]
		var l := maxf(d.length(), 0.01)
		var fs: Vector2 = d / l * (l - REST) * 0.04
		f[e[0]] += fs; f[e[1]] -= fs
	var cool := 1.0 - float(iters) / MAX_ITERS
	for i in n:
		f[i] += -pos[i] * 0.012
		vel[i] = (vel[i] + f[i]) * 0.8
		var mv := vel[i].limit_length(18.0 * maxf(cool, 0.1))
		if i != drag: pos[i] += mv
	iters += 1

func _process(_dt: float) -> void:
	if iters >= MAX_ITERS and drag < 0: set_process(false); _fit(); queue_redraw(); return
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 5000 and iters < MAX_ITERS: step()
	if iters % 20 < 6 and not pan: _fit()
	queue_redraw()

func _fit() -> void:
	if nodes.is_empty() or size.x < 10: return
	var r := Rect2(pos[0], Vector2.ZERO)
	for p in pos: r = r.expand(p)
	r = r.grow(40.0)
	zoom = clampf(minf(size.x / r.size.x, size.y / r.size.y), 0.2, 2.5)
	off = size / 2.0 - r.get_center() * zoom

func _w2s(p: Vector2) -> Vector2: return p * zoom + off
func _s2w(p: Vector2) -> Vector2: return (p - off) / zoom
func _rad(i: int) -> float: return 4.0 + sqrt(float(deg[i])) * 2.0

func node_at(sp: Vector2) -> int:
	var best := -1; var bd := 1e9
	for i in nodes.size():
		var d := _w2s(pos[i]).distance_to(sp)
		if d < _rad(i) * maxf(zoom, 0.8) + 6.0 and d < bd: best = i; bd = d
	return best

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var k := 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			var w := _s2w(mb.position); zoom = clampf(zoom * k, 0.15, 6.0); off = mb.position - w * zoom
			queue_redraw(); accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				moved = 0.0; drag = node_at(mb.position); pan = drag < 0
			else:
				if moved < 5.0 and drag >= 0: open_requested.emit(str(nodes[drag]))
				drag = -1; pan = false
			accept_event()
	elif ev is InputEventMouseMotion:
		var mm: InputEventMouseMotion = ev
		if drag >= 0 and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			moved += mm.relative.length(); pos[drag] += mm.relative / zoom; vel[drag] = Vector2.ZERO
			if moved >= 5.0 and iters >= MAX_ITERS: iters = MAX_ITERS - 40; set_process(true)
		elif pan and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			moved += mm.relative.length(); off += mm.relative
		else:
			var h := node_at(mm.position)
			if h != hover: hover = h
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: _fit(); queue_redraw()

func _draw() -> void:
	var bg := UI.p("field"); draw_rect(Rect2(Vector2.ZERO, size), bg)
	if nodes.is_empty():
		var fnt := get_theme_default_font()
		draw_string(fnt, Vector2(20, 40), "Aucune note.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.p("muted")); return
	var ac := UI.accent(); var edge := UI.p("muted"); var txt := UI.p("text")
	var sel := hover if hover >= 0 else focus
	var near: Array = adj[sel] if sel >= 0 else []
	for e in edges:
		var hi: bool = sel >= 0 and (e[0] == sel or e[1] == sel)
		draw_line(_w2s(pos[e[0]]), _w2s(pos[e[1]]), Color(ac, 0.9) if hi else Color(edge, 0.35 if sel < 0 else 0.15), 2.0 if hi else 1.0, true)
	var fnt := get_theme_default_font()
	for i in nodes.size():
		var p := _w2s(pos[i])
		if p.x < -20 or p.y < -20 or p.x > size.x + 20 or p.y > size.y + 20: continue
		var lit: bool = sel < 0 or i == sel or near.has(i)
		var col := ac if i == sel or i == focus else (Color(txt, 0.85) if lit else Color(edge, 0.5))
		draw_circle(p, _rad(i) * maxf(zoom, 0.7), col)
		if i == focus: draw_arc(p, _rad(i) * maxf(zoom, 0.7) + 4.0, 0, TAU, 24, ac, 2.0, true)
		if (lit and sel >= 0) or zoom > 0.9 or nodes.size() < 40:
			var nm := str(nodes[i]).get_file().get_basename()
			draw_string(fnt, p + Vector2(_rad(i) * maxf(zoom, 0.7) + 4.0, 5.0), nm.left(28), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, txt if lit else Color(txt, 0.4))
