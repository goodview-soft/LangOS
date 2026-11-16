class_name FpsView extends Node
## First person view (key 9): perspective camera at eye height, captured mouse, held pickaxe, pixel crosshair.

const EYE := 1.55

## Hauteur des yeux : suit la capsule du joueur (nain = tout près du sol), jamais au-dessus de la tête du personnage.
func eye() -> float:
	return clampf(m.player.hh - 0.1, 0.25, EYE)

## Hauteur du point d'orbite en 3e personne (au moins le milieu du dessin du personnage).
func pivot_h() -> float:
	return maxf(eye() * 0.9, m.player.vis_hh * 0.5)
const RANGE := 5.0
const SENS := 0.0027

var m: Node  # main
var yaw := 0.0
var pitch := 0.0
var held: Node3D
var swing := 0.0
var layer: CanvasLayer
var third := true   # third person (default view): camera behind the shoulder on a voxel-colliding arm
var arm := 5.5      # PgUp/PgDn
var arm_cur := 5.5
var focus := Vector3.INF  # smoothed orbit centre
var entered := false
var free := false   # free camera (Tab): ZQSD pan the camera, the character stands still
var free_pos := Vector3.ZERO
var rdrag := false  # right-drag turns the camera (a short right click still places a block)
var rdist := 0.0
var ldist := 0.0
var press_set := false
var press_block := false  # the left click started on a block: dragging keeps mining
var cam_drag := false  # left button dragged: turning the camera, no mining

func setup(main: Node) -> void:
	m = main
	layer = CanvasLayer.new()
	layer.visible = false
	add_child(layer)
	var cx := 320
	var cy := 180
	for r in [Rect2(cx - 4, cy, 3, 1), Rect2(cx + 2, cy, 3, 1), Rect2(cx, cy - 4, 1, 3), Rect2(cx, cy + 2, 1, 3)]:
		var c := ColorRect.new()
		c.position = (r as Rect2).position
		c.size = (r as Rect2).size
		c.color = Color(1, 1, 1, 0.9)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(c)
	held = Node3D.new()
	held.visible = false
	var wood := _mat(Color(0.5, 0.33, 0.17))
	var iron := _mat(Color(0.7, 0.72, 0.78))
	_box(held, Vector3(0.06, 0.06, 0.62), Vector3(0, 0, -0.1), wood)
	_box(held, Vector3(0.42, 0.07, 0.09), Vector3(0, 0, -0.42), iron)
	m.cam.add_child(held)
	held.position = Vector3(0.32, -0.28, -0.55)

func _mat(c: Color) -> StandardMaterial3D:
	var s := StandardMaterial3D.new()
	s.albedo_color = c
	s.roughness = 1.0
	s.no_depth_test = true
	s.render_priority = 5
	s.emission_enabled = true
	s.emission = c
	s.emission_energy_multiplier = 0.35
	return s

func _box(p: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)

func enter() -> void:
	yaw = PI / 4.0
	if third and not entered:  # first time: look along the world's depth axis, side-on with a gentle tilt (like the 2D view)
		yaw = 0.0
		entered = true
	pitch = -0.4 if third else 0.0  # 3rd person: look down at the character like an RTS camera
	var cam: Camera3D = m.cam
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 58.0 if third else 78.0  # 3rd person: gentler perspective (near blocks no longer look huge)
	cam.near = 0.05
	cam.far = 300.0
	if m.state == "play" and not third:  # FPS only: 3rd person keeps a free cursor to aim
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	layer.visible = not third  # crosshair: FPS only
	held.visible = not third
	arm_cur = arm
	focus = Vector3.INF
	free_pos = m.player.pos + Vector3(0, pivot_h(), 0)

func leave() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	layer.visible = false
	held.visible = false

func look(rel: Vector2) -> void:
	yaw -= rel.x * SENS
	pitch = clampf(pitch - rel.y * SENS, -1.4, 0.25) if third else clampf(pitch - rel.y * SENS, -1.5, 1.5)

func camera(dt: float) -> void:
	var cam: Camera3D = m.cam
	if third and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:  # 3rd person: free cursor (aim with the mouse)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if third and m.state == "play" and not m.input_blocked():  # A/E: turn the camera around the character
		var turn := int(Input.is_physical_key_pressed(KEY_Q)) - int(Input.is_physical_key_pressed(KEY_E))
		yaw += turn * 2.2 * dt
		yaw -= m.hud.joy.vec.x * 2.2 * dt  # joystick (bottom left)
		pitch = clampf(pitch + m.hud.joy.vec.y * 1.5 * dt, -1.4, 0.25)
	cam.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	cam.position = m.player.get_global_transform_interpolated().origin + Vector3(0, eye(), 0)
	if third:  # orbit around the CENTRE of the character; the arm shortens when a block gets in between (nothing is cut)
		var tgt: Vector3 = m.player.get_global_transform_interpolated().origin + Vector3(0, pivot_h(), 0)
		if free and m.state == "play" and not m.input_blocked():  # DwarfCorp style: the camera flies on its own
			var mv := Vector2(int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A)), int(Input.is_physical_key_pressed(KEY_W)) - int(Input.is_physical_key_pressed(KEY_S)))
			var spd := (6.0 + arm * 1.2) * (2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
			free_pos += ViewCtl.ground_wish(yaw, mv.x, mv.y) * spd * dt
			free_pos.x = clampf(free_pos.x, 0.5, World.SX - 0.5)
			free_pos.z = clampf(free_pos.z, 0.5, World.SZ - 0.5)
		if free:
			tgt = free_pos
		focus = tgt if focus == Vector3.INF else focus.lerp(tgt, 1.0 - exp(-dt * 10.0))  # the camera trails the character slightly
		var pivot := focus
		var back := cam.basis.z
		var free_d := arm
		free_d = arm_clear(pivot, back, arm)
		arm_cur = lerpf(arm_cur, free_d, 1.0 - exp(-dt * (18.0 if free_d < arm_cur else 4.0)))  # quick but never a pop at wall corners; slow, gentle return
		cam.position = pivot + back * arm_cur
		# tight spot: the camera is squeezed against the walls, so the character's head would fill the screen.
		# Like most games, hide the own body when the camera is that close (hysteresis: no flicker).
		var close := arm_cur < (1.5 if VoxelBody.hide_self == m.player else 1.1) and not free
		VoxelBody.hide_self = m.player if close else null
		return
	swing = move_toward(swing, 1.0 if m.player.mining else 0.0, dt * 8.0)
	var s := sin(Time.get_ticks_msec() / 1000.0 * 14.0) * swing
	held.rotation = Vector3(-0.3 - s * 0.9, 0.25, -0.15)
	held.position = Vector3(0.32, -0.28 + s * 0.05, -0.55 - s * 0.08)

## Distance libre (<= want) derrière le pivot dans la direction back : la même boîte que la caméra d'orbite.
func arm_clear(pivot: Vector3, back: Vector3, want: float) -> float:
	var t := 0.2
	while t <= want:  # a small box around the camera, not just a thin line: it never enters a block
		var q := pivot + back * t
		for o in [Vector3.ZERO, Vector3(0.22, 0, 0), Vector3(-0.22, 0, 0), Vector3(0, 0.22, 0), Vector3(0, -0.22, 0), Vector3(0, 0, 0.22), Vector3(0, 0, -0.22)]:
			if World.KIND[m.world.get_v(Vector3i((q + o).floor()))] == World.K_CUBE and not m.view.skip(Vector3i((q + o).floor())):
				return maxf(t - 0.35, 0.0)
		t += 0.1
	return want

func wish(mx: float, mz: float) -> Vector3:
	return ViewCtl.ground_wish(yaw, mx, mz)

## Voxel ray from the screen centre, range 5.
func pick(screen := Vector2(-1, -1)) -> Dictionary:
	var cam: Camera3D = m.cam
	var r: Dictionary
	if third and screen.x >= 0.0:  # 3rd person: aim with the mouse cursor
		r = m.raycast(cam.project_ray_origin(screen), cam.project_ray_normal(screen), 120)
	else:
		r = m.raycast(cam.position, -cam.basis.z, 80)
	if r.is_empty():
		return r
	if (Vector3(r.cell) + Vector3(0.5, 0.5, 0.5)).distance_to(m.player.center() if third else cam.position) > RANGE + 0.87:
		return {}
	return r
