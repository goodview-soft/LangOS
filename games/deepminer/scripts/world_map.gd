class_name WorldMap extends CanvasLayer
## Vraie carte : vue de dessus de la caverne autour de l'altitude du joueur, partagée par la mini-carte du HUD
## (coin haut droit) et la grande carte (touche B). Lacs et jardins n'y sont marqués qu'une fois découverts.

const BAND := 5  # on regarde de l'altitude du joueur + 5 vers le bas : les cavités ouvertes montrent leur sol, la roche reste sombre
var main: Node3D
var big: Canvas
var _prev_mouse: int = Input.MOUSE_MODE_VISIBLE

## Dessin commun (mini-carte et grande carte) : terrain + lieux découverts + mineurs + joueur.
class Canvas extends Control:
	var tex: ImageTexture
	var px := 1.0  # pixels d'écran par bloc
	var ppos := Vector3.ZERO
	var dots: Array = []
	var pois: Array = []
	var found: Array = []
	var labels := false
	var img: Image
	var key := -1
	var stamp := 0
	var edits := -1
	var nfound := -1
	var last_py := -999.0
	var job_z := -1  # recalcul en cours : prochaine rangée z à faire (-1 = aucun)
	var job_py := 0.0
	var job_pl: Array = []
	var job_fd: Array = []
	var job_img: Image

	func _draw() -> void:
		if tex == null:
			return
		draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(World.SX, World.SZ) * px), false)
		for i in pois.size():
			if i >= found.size() or not found[i]:
				continue
			var p: Dictionary = pois[i]
			var c := Vector2(p.pos.x, p.pos.z) * px
			var big := px >= 3.0
			if p.kind == "lac":
				var rr := maxf(float(p.r) * px, 3.0)
				draw_arc(c, rr, 0.0, TAU, 20, Color(0.45, 0.8, 1.0), 1.0 if not big else 2.0)
				if labels:
					_label(c + Vector2(rr + 3, 4), "Lac")
			elif p.kind == "chaud":
				var d2 := 3.0 if not big else 6.0
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d2), c + Vector2(d2, d2), c + Vector2(-d2, d2)]), Color(1.0, 0.7, 0.2))
				if labels:
					_label(c + Vector2(d2 + 3, 4), "Cavité chaude")
			elif p.kind == "mine":
				var d3 := 2.0 if not big else 5.0
				draw_rect(Rect2(c - Vector2(d3, d3), Vector2(d3, d3) * 2.0), Color(0.75, 0.5, 0.25))
				draw_rect(Rect2(c - Vector2(d3, d3), Vector2(d3, d3) * 2.0), Color(0.2, 0.1, 0.05), false, 1.0)
				if labels:
					_label(c + Vector2(d3 + 3, 4), "Ancienne mine")
			else:
				var d := 3.0 if not big else 6.0
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), Color(0.6, 1.0, 0.95))
				draw_polyline(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0), c + Vector2(0, -d)]), Color(0.75, 0.4, 1.0), 1.0)
				if labels:
					_label(c + Vector2(d + 3, 4), "Jardin de cristaux")
		for dt in dots:
			var q: Vector3 = dt[0]
			draw_rect(Rect2(Vector2(q.x, q.z) * px - Vector2(1, 1), Vector2(3, 3) if px < 3.0 else Vector2(5, 5)), dt[1])
		var pc := Vector2(ppos.x, ppos.z) * px
		draw_rect(Rect2(pc - Vector2(2, 2), Vector2(5, 5) if px < 3.0 else Vector2(8, 8)), Color(0, 0, 0))
		draw_rect(Rect2(pc - Vector2(1, 1), Vector2(3, 3) if px < 3.0 else Vector2(6, 6)), Color(1.0, 0.25, 0.25))

	func _label(p: Vector2, t: String) -> void:
		var f := ThemeDB.fallback_font
		draw_string(f, p + Vector2(1, 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0))
		draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1))

	## Décide s'il faut recalculer le terrain : l'altitude a changé d'au moins 3 blocs, un lieu est découvert, ou (rarement) des blocs ont changé.
	## Le calcul se fait par petits morceaux à chaque image (step), jamais d'un seul coup : pas d'à-coup.
	func refresh(w: World, pp: Vector3, pl: Array, fd: Array, dl: Array, force := false) -> void:
		ppos = pp
		pois = pl
		found = fd
		dots = dl
		var now := Time.get_ticks_msec()
		var nf := 0
		for f in fd:
			if f:
				nf += 1
		var need := img == null or force or nf != nfound or absf(pp.y - last_py) >= 3.0 or (w.edits != edits and now - stamp > 6000)
		if need and (job_z < 0 or force):
			nfound = nf
			last_py = pp.y
			edits = w.edits
			stamp = now
			if force or img == null:  # première fois / ouverture de la grande carte : tout de suite
				img = WorldMap.render(w, pp.y, pl, fd)
				_upload()
				job_z = -1
			else:
				job_py = pp.y
				job_pl = pl
				job_fd = fd.duplicate()
				job_img = Image.create(World.SX, World.SZ, false, Image.FORMAT_RGBA8)
				job_z = 0
		queue_redraw()

	## Une tranche de travail (2 ms au plus) du recalcul en cours.
	func step(w: World) -> void:
		if job_z < 0:
			return
		var t0 := Time.get_ticks_usec()
		var hide := WorldMap.hide_list(job_pl, job_fd)
		while job_z < World.SZ and Time.get_ticks_usec() - t0 < 2000:
			WorldMap.render_rows(w, job_py, hide, job_img, job_z, job_z + 4)
			job_z += 4
		if job_z >= World.SZ:
			img = job_img
			job_z = -1
			_upload()
			queue_redraw()

	func _upload() -> void:
		if tex == null:
			tex = ImageTexture.create_from_image(img)
		else:
			tex.update(img)

## Image SX x SZ : pour chaque colonne, premier bloc plein (ou eau) en descendant depuis l'altitude du joueur + BAND.
## Le terrain est toujours visible, mais l'eau, les cristaux et la mousse d'un lieu pas encore découvert sont masqués (roche ordinaire).
static func hide_list(pl: Array, fd: Array) -> Array:
	var hide: Array = []  # [x, z, rayon²]
	for i in pl.size():
		if i >= fd.size() or not fd[i]:
			var q: Dictionary = pl[i]
			var rr: float = float(q.r) + 2.0
			hide.append([q.pos.x, q.pos.z, rr * rr])
	return hide

static func render(w: World, py: float, pl: Array, fd: Array) -> Image:
	var img := Image.create(World.SX, World.SZ, false, Image.FORMAT_RGBA8)
	render_rows(w, py, hide_list(pl, fd), img, 0, World.SZ)
	return img

## Rangées z0..z1-1 de la vue de dessus (accès direct au tableau des blocs : c'est la boucle la plus chaude).
static func render_rows(w: World, py: float, hide: Array, img: Image, z0: int, z1: int) -> void:
	var top := mini(World.SY - 2, int(py) + BAND)
	var blocks := w.blocks
	var SX := World.SX
	var SY := World.SY
	for z in range(z0, mini(z1, World.SZ)):
		for x in SX:
			var col := Color(0.03, 0.03, 0.06)
			var base := x + SX * SY * z
			for y in range(top, 0, -1):
				var id: int = blocks[base + SX * y]
				if id == World.AIR:
					continue
				var kd: int = World.KIND[id]
				if kd == World.K_CROSS or kd == World.K_SIGN:
					continue
				if hide.size() > 0 and (id == World.WATER or id == World.CRYSTAL or id == World.MOSS or id == World.AMBER or id == World.WARMROCK or id == World.WOOD):
					for h in hide:
						if (x + 0.5 - h[0]) * (x + 0.5 - h[0]) + (z + 0.5 - h[1]) * (z + 0.5 - h[1]) < h[2]:
							id = World.STONE
							kd = World.K_CUBE
							break
				col = World.MAPCOL[id]
				if y == top and kd == World.K_CUBE:  # roche au niveau du plafond de vue : sombre (la carte montre les cavités)
					col = col.darkened(0.62)
				else:
					col = col.darkened(clampf(absf(float(y) - py) / 16.0, 0.0, 1.0) * 0.55)
				break
			img.set_pixel(x, z, col)

func _ready() -> void:
	layer = 13
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.02, 0.7)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Menu._sb(Color(0.05, 0.04, 0.08, 0.96), Color(0.55, 0.42, 0.25), 2))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	vb.add_child(Menu._lbl("Carte (vue de dessus, à ton altitude)", 12, Color(1.0, 0.85, 0.4)))
	big = Canvas.new()
	big.px = 3.0
	big.labels = true
	big.custom_minimum_size = Vector2(World.SX, World.SZ) * 3.0
	vb.add_child(big)
	vb.add_child(Menu._lbl("Rouge : toi   Clair : sol des cavités   Sombre : roche   B ou Échap : fermer", 9, Color(0.85, 0.85, 0.92)))

func open() -> void:
	if main.state != "play":
		return
	main.state = "pause"
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	main.refresh_big_map()

func close() -> void:
	if visible:
		visible = false
		Input.mouse_mode = _prev_mouse as Input.MouseMode
		main.state = "play"

func _unhandled_input(ev: InputEvent) -> void:
	if visible and ev is InputEventKey and ev.pressed and not ev.echo:
		get_viewport().set_input_as_handled()
		if ev.keycode == KEY_B or ev.keycode == KEY_ESCAPE:
			close()
