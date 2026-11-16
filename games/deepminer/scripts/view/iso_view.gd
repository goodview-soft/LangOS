class_name IsoView extends RefCounted
## Level cut of the 3rd person view (X) + state shared with the shaders (player position, narrow spot).
## ONE global roof cut on the grid (cells at y >= cut_y hidden), identical everywhere. It follows the player's
## floor down at once, up with a 2-block hysteresis (no change on a jump or a step), drops right above the head
## under a low ceiling, and slides one layer at a time when it does change. Caps are rebuilt only when the cut
## changes (or on edits).
## vox: 3D texture of the block ids, also used by the shader for per-texel AO and edge outlines.

const ROOF := 4      # cut height above the reference floor
const HYST := 2       # the reference floor moves only when the player's floor differs by this much
const STEP_T := 0.07  # seconds per layer when the cut slides

var m: Node  # main
var ground_y := -1000  # player's floor (stable during a jump)
var level := -1000     # reference floor, with hysteresis
var cut_y := 100000    # current (sliding) cut
var step_t := 0.0
var slice_y := -1     # free camera (3rd person): absolute cut height, -1 = automatic rule
var cut_mode := 0      # 0 none (default: whole map, no height limit), 1 roof (X)
var caps: MeshInstance3D
var cap_key := []
var caps_dirty := true
var vox: ImageTexture3D
var vox_imgs: Array[Image] = []

func _init(main: Node) -> void:
	m = main
	caps = MeshInstance3D.new()
	caps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	caps.layers = ViewCtl.L_CAPS_ISO  # only the level-cut view sees them
	m.add_child(caps)
	build_vox()

# ---------------------------------------------------------------- block ids texture
func build_vox() -> void:
	vox_imgs.clear()
	for z in World.SZ:
		vox_imgs.append(_slice(z))
	vox = ImageTexture3D.new()
	vox.create(Image.FORMAT_R8, World.SX, World.SY, World.SZ, false, vox_imgs)
	m._set_param("vox", vox)

func _slice(z: int) -> Image:
	var n := World.SX * World.SY
	return Image.create_from_data(World.SX, World.SY, false, Image.FORMAT_R8, m.world.blocks.slice(z * n, (z + 1) * n))

## Chunks were remeshed: refresh their z slices of the id texture and the caps.
func on_remesh(chunk_keys: Array) -> void:
	var zs := {}
	for key in chunk_keys:
		for z in range(key.z * World.CS, mini(key.z * World.CS + World.CS, World.SZ)):
			zs[z] = true
	for z in zs:
		vox_imgs[z] = _slice(z)
	vox.update(vox_imgs)
	caps_dirty = true

# ---------------------------------------------------------------- cutaway rule (same as the shader)
func roof_on() -> bool:
	return cut_mode == 1

func hidden(c: Vector3i) -> bool:
	return roof_on() and c.y >= cut_y

## Picking follows the rendering exactly.
func skip(c: Vector3i) -> bool:
	return hidden(c)

# ---------------------------------------------------------------- level cut
## Snap the cut state (level) to the player now.
func enter_state() -> void:
	ground_y = -1000
	level = -1000
	caps_dirty = true
	update_state(0.0, true)

## Floor level with hysteresis, sliding cut, uniforms; caps only when the cut changed.
func update_state(dt := 0.0, instant := false) -> void:
	var p: Vector3 = m.player.pos
	var fy := floori(p.y + 0.05)
	if m.player.on_ground or ground_y < -999:
		ground_y = fy
	var snap := level < -999 or instant
	if snap or ground_y < level or ground_y - level >= HYST:  # down: at once; up: only after 2+ blocks
		level = ground_y
	var head := maxi(2, ceili(m.player.hh - 0.05))
	var goal := level + maxi(ROOF, head)
	var col := Vector3i(floori(p.x), 0, floori(p.z))
	for yy in range(ground_y + head, goal):  # low ceiling over the head: cut right above the head
		col.y = yy
		if m.world.in_bounds(col) and _cube(m.world.get_v(col)):
			goal = ground_y + head
			break
	if slice_y >= 0:
		goal = slice_y
	if snap or cut_y > 99999 or goal < cut_y:  # going down is immediate: never stuck above a ceiling
		step_t = 0.0
		cut_y = goal
	elif cut_y != goal:
		step_t += dt
		if step_t >= STEP_T:
			step_t = 0.0
			cut_y += signi(goal - cut_y)
	m._set_param("cut_y", cut_y if roof_on() else 100000)
	m._set_param("lvl_y", level)
	m._set_param("pxz", Vector2(p.x, p.z))
	var key := [cut_y if roof_on() else 0]
	if caps_dirty or cap_key != key:
		cap_key = key
		caps_dirty = false
		_build_caps()

# ---------------------------------------------------------------- caps
func _cap_face(buf: World.Buf, c: Vector3i, f: int, id: int) -> void:
	var fd: Array = m.world.faces[f]
	var nrm := Vector3(fd[0])
	buf.quad(Vector3(c) + Vector3(0.5, 0.5, 0.5) + nrm * 0.5, fd[1], fd[2], nrm, World.tile_at(id, c.x, c.y, c.z), Color(fd[3], 0.0, 0.0, 0.0))

func _cube(id: int) -> bool:
	return World.KIND[id] == World.K_CUBE

## Caps over the whole world (roof layer, cheap): rebuilt only when a cut moves.
func _build_caps() -> void:
	var w: World = m.world
	var buf := World.Buf.new()
	var y := cut_y - 1
	if roof_on() and y >= 0 and y < World.SY - 1:
		for z in World.SZ:
			for x in World.SX:
				var id := w.get_b(x, y, z)
				if _cube(id) and _cube(w.get_b(x, y + 1, z)):
					_cap_face(buf, Vector3i(x, y, z), 2, id)
	var mesh := ArrayMesh.new()
	buf.commit(mesh, m.mat_s)
	caps.mesh = mesh
