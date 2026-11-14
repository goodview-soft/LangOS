class_name BlockManager
extends Node3D
## Grille de voxels 3D (PackedByteArray) + meshes/collisions regroupés par sections 16³.
## Chaque modification ne reconstruit que la section concernée (instantané visuellement).

signal block_changed(cell: Vector3i, old_id: int, new_id: int)

const CHUNK := 16
const COLORS := {
	Cfg.B_STONE: Color(0.40, 0.42, 0.47),
	Cfg.B_RED_FLOOR: Color(0.72, 0.30, 0.30),
	Cfg.B_BLUE_FLOOR: Color(0.30, 0.43, 0.76),
	Cfg.B_BRIDGE: Color(0.78, 0.74, 0.62),
	Cfg.B_RED_PLACED: Color(0.95, 0.28, 0.28),
	Cfg.B_BLUE_PLACED: Color(0.28, 0.52, 0.98),
}
const FACE_SHADE := [0.8, 0.8, 1.0, 0.5, 0.7, 0.7]  # +x -x +y -y +z -z
const FACE_N := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var size := Cfg.MAP_SIZE
var grid := PackedByteArray()
var base_grid := PackedByteArray()
var _chunks := {}  # Vector3i -> {"mi": MeshInstance3D, "cs": CollisionShape3D}
var _material: StandardMaterial3D
var _face_quads: Array = []

func _ready() -> void:
	grid.resize(size.x * size.y * size.z)
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.92
	for n in FACE_N:
		_face_quads.append(_make_quad(n))

func _make_quad(n: Vector3i) -> Array:
	var nf := Vector3(n)
	var a: Vector3
	var b: Vector3
	if n.x != 0:
		a = Vector3(0, 1, 0); b = Vector3(0, 0, 1)
	elif n.y != 0:
		a = Vector3(1, 0, 0); b = Vector3(0, 0, 1)
	else:
		a = Vector3(1, 0, 0); b = Vector3(0, 1, 0)
	var o := Vector3(1 if n.x > 0 else 0, 1 if n.y > 0 else 0, 1 if n.z > 0 else 0)
	var v: Array = [o, o + a, o + a + b, o + b]
	# Godot : face avant = sens horaire vu de l'extérieur
	var cr: Vector3 = (v[1] - v[0]).cross(v[2] - v[0])
	if cr.dot(nf) > 0.0:
		v = [o, o + b, o + a + b, o + a]
	return v

func _idx(c: Vector3i) -> int:
	return c.x + size.x * (c.z + size.z * c.y)

func in_bounds(c: Vector3i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.z >= 0 and c.x < size.x and c.y < size.y and c.z < size.z

func get_block(c: Vector3i) -> int:
	if not in_bounds(c):
		return Cfg.B_AIR
	return grid[_idx(c)]

func is_solid(c: Vector3i) -> bool:
	return get_block(c) != Cfg.B_AIR

func is_destructible(c: Vector3i) -> bool:
	var id := get_block(c)
	return id == Cfg.B_RED_PLACED or id == Cfg.B_BLUE_PLACED

## Modification autoritaire d'un bloc (appelée par ServerAuthority / ArenaManager).
func set_block(c: Vector3i, id: int, rebuild: bool = true) -> void:
	if not in_bounds(c):
		return
	var old := grid[_idx(c)]
	if old == id:
		return
	grid[_idx(c)] = id
	if rebuild:
		_rebuild_around(c)
	block_changed.emit(c, old, id)

func fill_box(a: Vector3i, b: Vector3i, id: int) -> void:
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
			for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				set_block(Vector3i(x, y, z), id, false)

func commit_base() -> void:
	base_grid = grid.duplicate()

func reset_to_base() -> void:
	grid = base_grid.duplicate()
	rebuild_all()

func rebuild_all() -> void:
	for cy in ceili(float(size.y) / CHUNK):
		for cz in ceili(float(size.z) / CHUNK):
			for cx in ceili(float(size.x) / CHUNK):
				_rebuild_chunk(Vector3i(cx, cy, cz))

func _rebuild_around(c: Vector3i) -> void:
	var cc := Vector3i(floori(float(c.x) / CHUNK), floori(float(c.y) / CHUNK), floori(float(c.z) / CHUNK))
	var todo := {cc: true}
	for n in FACE_N:
		var nb: Vector3i = c + n
		if in_bounds(nb):
			todo[Vector3i(floori(float(nb.x) / CHUNK), floori(float(nb.y) / CHUNK), floori(float(nb.z) / CHUNK))] = true
	for k in todo:
		_rebuild_chunk(k)

func _get_chunk(cc: Vector3i) -> Dictionary:
	if _chunks.has(cc):
		return _chunks[cc]
	var body := StaticBody3D.new()
	body.name = "Chunk_%d_%d_%d" % [cc.x, cc.y, cc.z]
	var mi := MeshInstance3D.new()
	var cs := CollisionShape3D.new()
	body.add_child(mi)
	body.add_child(cs)
	add_child(body)
	var d := {"mi": mi, "cs": cs}
	_chunks[cc] = d
	return d

func _rebuild_chunk(cc: Vector3i) -> void:
	var ch := _get_chunk(cc)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var x0 := cc.x * CHUNK
	var y0 := cc.y * CHUNK
	var z0 := cc.z * CHUNK
	for y in range(y0, mini(y0 + CHUNK, size.y)):
		for z in range(z0, mini(z0 + CHUNK, size.z)):
			for x in range(x0, mini(x0 + CHUNK, size.x)):
				var c := Vector3i(x, y, z)
				var id := grid[_idx(c)]
				if id == 0:
					continue
				var base: Color = COLORS[id]
				var h := float(((x * 73856093) ^ (y * 19349663) ^ (z * 83492791)) & 255) / 255.0
				base = base * (0.94 + 0.06 * h)
				if (x + z) % 2 == 0:
					base = base * 0.95
				base.a = 1.0
				for f in 6:
					if is_solid(c + FACE_N[f]):
						continue
					var col: Color = base * float(FACE_SHADE[f])
					col.a = 1.0
					var q: Array = _face_quads[f]
					var nf := Vector3(FACE_N[f])
					for i in [0, 1, 2, 0, 2, 3]:
						verts.append(Vector3(x, y, z) + q[i])
						norms.append(nf)
						cols.append(col)
	var mi: MeshInstance3D = ch["mi"]
	var cs: CollisionShape3D = ch["cs"]
	if verts.is_empty():
		mi.mesh = null
		cs.shape = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	mi.mesh = mesh
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(verts)
	cs.shape = shape

## Raycast voxel (DDA). Retourne {} ou {cell, normal, dist}.
func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var d := dir.normalized()
	var cell := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	if is_solid(cell):
		return {"cell": cell, "normal": Vector3i.ZERO, "dist": 0.0}
	var step := Vector3i(signi(int(signf(d.x))), signi(int(signf(d.y))), signi(int(signf(d.z))))
	var t_delta := Vector3(INF, INF, INF)
	var t_max := Vector3(INF, INF, INF)
	for a in 3:
		if d[a] != 0.0:
			t_delta[a] = absf(1.0 / d[a])
			var boundary: float = (cell[a] + 1) if d[a] > 0.0 else cell[a]
			t_max[a] = (boundary - origin[a]) / d[a]
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_dist:
		if t_max.x < t_max.y and t_max.x < t_max.z:
			cell.x += step.x
			t = t_max.x
			t_max.x += t_delta.x
			normal = Vector3i(-step.x, 0, 0)
		elif t_max.y < t_max.z:
			cell.y += step.y
			t = t_max.y
			t_max.y += t_delta.y
			normal = Vector3i(0, -step.y, 0)
		else:
			cell.z += step.z
			t = t_max.z
			t_max.z += t_delta.z
			normal = Vector3i(0, 0, -step.z)
		if t > max_dist:
			break
		if is_solid(cell):
			return {"cell": cell, "normal": normal, "dist": t}
	return {}
