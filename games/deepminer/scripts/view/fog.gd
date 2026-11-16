class_name FogOfWar extends RefCounted
## Voxel fog of war. A BFS from the player's cells through the non-solid cells (air, water, plants...) within R
## gives the cells "seen now"; the solid cells next to them are the walls seen. Everything ever seen is
## "explored" (memory, saved with the game). The shaders read the R8 3D texture `fow`:
## 0 = unknown (pure black), 128 = explored (dim memory), 255 = seen now.
## --- PERF --- the BFS is time-sliced (BUDGET_US per frame) and only restarts when the player changes cell or
## a nearby block changes; the texture is uploaded once per finished pass.

static var ENABLED := false  # fog of war off (player: it spoiled the map); true to bring it back
const R := 20
const BUDGET_US := 6000  # faster reveal while walking (~0.15 s instead of ~0.35 s)
const UNKNOWN := 0
const MEMORY := 128
const SEEN := 255

var w: World
var state := PackedByteArray()     # texture data (per cell)
var explored := PackedByteArray()  # 1 = explored (saved)
var stamp := PackedInt32Array()    # BFS visit stamp
var gen := 0
var solid := PackedByteArray()     # per block id: 1 = blocks the sight
var seen_now := PackedInt32Array() # cells seen by the last finished pass
var cur := PackedInt32Array()      # cells seen by the running pass
var q := PackedInt32Array()
var qh := 0
var running := false
var dirty := true
var origin := Vector3i(-999, -999, -999)
var tex: ImageTexture3D
var imgs: Array[Image] = []
var passes := 0
var torches: Array = []  # Vector3i of placed torches: each lights (reveals) its surroundings
const TORCH_R := 6
var last_us := 0  # cost of the last finished pass (µs, all slices)

func _init(world: World) -> void:
	w = world
	var n := World.SX * World.SY * World.SZ
	state.resize(n)
	explored.resize(n)
	stamp.resize(n)
	if not ENABLED:
		state.fill(SEEN)  # everything visible
	solid.resize(256)
	for id in World.KIND.size():
		solid[id] = 1 if World.KIND[id] == World.K_CUBE else 0
	for z in World.SZ:
		imgs.append(_slice(z))
	tex = ImageTexture3D.new()
	tex.create(Image.FORMAT_R8, World.SX, World.SY, World.SZ, false, imgs)

func _slice(z: int) -> Image:
	var n := World.SX * World.SY
	return Image.create_from_data(World.SX, World.SY, false, Image.FORMAT_R8, state.slice(z * n, (z + 1) * n))

static func idx(c: Vector3i) -> int:
	return c.x + World.SX * (c.y + World.SY * c.z)

func value(c: Vector3i) -> int:
	return state[idx(c)] if w.in_bounds(c) else SEEN

func is_seen(c: Vector3i) -> bool:
	return not ENABLED or value(c) == SEEN

func is_explored(c: Vector3i) -> bool:
	return w.in_bounds(c) and explored[idx(c)] == 1

## A block changed near c: the sight may have opened / closed.
func notify_edit(c: Vector3i) -> void:
	if (c - origin).length_squared() <= (R + 2) * (R + 2):
		dirty = true

## Call every frame with the player's feet cell and body height (in cells).
func tick(feet: Vector3i, body: int) -> void:
	if not ENABLED:
		return
	if feet != origin:
		origin = feet
		dirty = true
	if not running and dirty:
		_start(feet, body)
	if running:
		_run(BUDGET_US)

## Synchronous full pass (load, tests).
func compute_now(feet: Vector3i, body: int) -> void:
	if not ENABLED:
		return
	origin = feet
	_start(feet, body)
	_run(1 << 30)

var t_acc := 0
var center := Vector3i.ZERO

func _start(feet: Vector3i, body: int) -> void:
	dirty = false
	running = true
	gen += 1
	q.resize(0)
	cur.resize(0)
	qh = 0
	t_acc = 0
	center = feet
	for dy in maxi(body, 1):
		var c := feet + Vector3i(0, dy, 0)
		if w.in_bounds(c):
			var i := idx(c)
			stamp[i] = gen
			cur.append(i)
			if solid[w.blocks[i]] == 0:
				q.append(i)

func _run(budget: int) -> void:
	var t0 := Time.get_ticks_usec()
	var sx := World.SX
	var sxy := World.SX * World.SY
	var r2 := R * R
	var cx := center.x
	var cy := center.y
	var cz := center.z
	var n := 0
	while qh < q.size():
		var i := q[qh]
		qh += 1
		var x := i % sx
		var y := (i / sx) % World.SY
		var z := i / sxy
		for k in 6:
			var nx := x
			var ny := y
			var nz := z
			match k:
				0: nx += 1
				1: nx -= 1
				2: ny += 1
				3: ny -= 1
				4: nz += 1
				_: nz -= 1
			if nx < 0 or ny < 0 or nz < 0 or nx >= sx or ny >= World.SY or nz >= World.SZ:
				continue
			var dx := nx - cx
			var dy := ny - cy
			var dz := nz - cz
			if dx * dx + dy * dy + dz * dz > r2:
				continue
			var j := nx + sx * (ny + World.SY * nz)
			if stamp[j] == gen:
				continue
			stamp[j] = gen
			cur.append(j)
			if solid[w.blocks[j]] == 0:
				q.append(j)
		n += 1
		if (n & 255) == 0 and Time.get_ticks_usec() - t0 > budget:
			t_acc += Time.get_ticks_usec() - t0
			return
	t_acc += Time.get_ticks_usec() - t0
	_finish()

func _finish() -> void:
	running = false
	var t0 := Time.get_ticks_usec()
	# torches the player knows about light up their surroundings: those cells are seen too
	var lim := (R + TORCH_R + 2) * (R + TORCH_R + 2)
	for t in torches:
		var tc: Vector3i = t
		if not w.in_bounds(tc) or (tc - center).length_squared() > lim:
			continue
		var ti := idx(tc)
		if explored[ti] == 0 and stamp[ti] != gen:
			continue  # unknown torch: reveals nothing
		_light(tc)
	# --- PERF --- only the z slices that really changed are rebuilt (was: all 48, ~15 ms spikes)
	var sxy := World.SX * World.SY
	var zmin := World.SZ
	var zmax := -1
	for i in seen_now:
		state[i] = MEMORY
		var z := i / sxy
		zmin = mini(zmin, z)
		zmax = maxi(zmax, z)
	for i in cur:
		state[i] = SEEN
		explored[i] = 1
		var z := i / sxy
		zmin = mini(zmin, z)
		zmax = maxi(zmax, z)
	seen_now = cur.duplicate()
	if zmax >= zmin:
		for z in range(zmin, zmax + 1):
			imgs[z] = _slice(z)
		tex.update(imgs)
	last_us = t_acc + Time.get_ticks_usec() - t0
	passes += 1

## Saved data: the explored mask, compressed.
func save_data() -> String:
	return Marshalls.raw_to_base64(explored.compress(FileAccess.COMPRESSION_ZSTD))

func load_data(s: String) -> void:
	if not ENABLED:
		return
	if s == "":
		return
	var raw := Marshalls.base64_to_raw(s).decompress(explored.size(), FileAccess.COMPRESSION_ZSTD)
	if raw.size() != explored.size():
		return
	explored = raw
	for i in explored.size():
		state[i] = MEMORY if explored[i] == 1 else UNKNOWN
	seen_now.resize(0)
	dirty = true
	for z in World.SZ:
		imgs[z] = _slice(z)
	tex.update(imgs)

func reset() -> void:
	if not ENABLED:
		return
	explored.fill(0)
	state.fill(0)
	seen_now.resize(0)
	dirty = true

## Small flood fill from a torch through non-solid cells (+ the walls around them).
func _light(tc: Vector3i) -> void:
	var seen := {}
	var lq: Array[Vector3i] = [tc]
	seen[tc] = true
	var h := 0
	var r2 := TORCH_R * TORCH_R
	while h < lq.size():
		var c: Vector3i = lq[h]
		h += 1
		cur.append(idx(c))
		if c != tc and solid[w.get_v(c)] == 1:
			continue
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var n: Vector3i = c + d
			if seen.has(n) or not w.in_bounds(n) or (n - tc).length_squared() > r2:
				continue
			seen[n] = true
			lq.append(n)
