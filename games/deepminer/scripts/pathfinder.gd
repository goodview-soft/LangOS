class_name Pathfinder extends RefCounted
## Bounded A* on the voxel grid for the AI miners.
## A node is a feet cell: h free cells high (h = body height in blocks, 2 for a human, 1 dwarf, 3 giant) with a solid floor. Moves: walk, step up 1 block,
## fall up to 3 blocks, and (optionally) dig through dirt/rock at a higher cost. Never bedrock or
## chests (HARD < 0), never next to lava, never with the head under water.

enum {GOAL_CELL, GOAL_REACH, GOAL_SAFE}
const MAX_NODES := 500
const MAX_FALL := 3
static var max_up := 2     # marche haute franchissable en sautant (l'aide au saut du Player passe 2 blocs)
static var climb_up := 0   # espèces grimpeuses : hauteur de mur escaladable (0 = non)
static var max_fall := MAX_FALL  # chute maximale de la recherche en cours (plus grande quand la chute est sans dégâts : sortie du spawn)
const H_WEIGHT := 2.0  # weighted A*: greedier, far fewer nodes (fine for NPCs)
const DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const UP := Vector3i(0, 1, 0)
## Cells (relative to the feet) whose block a miner can mine from where he stands.
const REACH_OFF := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 1, 0), Vector3i(-1, 1, 0), Vector3i(0, 1, 1), Vector3i(0, 1, -1), Vector3i(0, 2, 0), Vector3i(0, -1, 0)]

static func solid(w: World, c: Vector3i) -> bool:
	return World.KIND[w.get_v(c)] == World.K_CUBE

static func passable(w: World, c: Vector3i) -> bool:
	var id := w.get_v(c)
	return World.KIND[id] != World.K_CUBE and id != World.LAVA

## Optional func(Vector3i) -> bool: cells the AI may never dig (spawn room).
static var protected: Callable

static func diggable(w: World, c: Vector3i) -> bool:
	var id := w.get_v(c)
	return w.in_bounds(c) and World.KIND[id] == World.K_CUBE and World.HARD[id] >= 0.0 and not (protected.is_valid() and protected.call(c))

static func lava_near(w: World, c: Vector3i) -> bool:
	if w.get_v(c) == World.LAVA or w.get_v(c + UP) == World.LAVA or w.get_v(c - UP) == World.LAVA:
		return true
	for d in DIRS:
		if w.get_v(c + d) == World.LAVA:
			return true
	return false

## Valid feet cell (floor, h free cells, safe).
static func standable(w: World, c: Vector3i, h := 2) -> bool:
	if not (c.x > 0 and c.z > 0 and c.y > 1 and c.x < World.SX - 1 and c.z < World.SZ - 1 and c.y + h < World.SY):
		return false
	for i in h:
		if not passable(w, c + UP * i):
			return false
	return solid(w, c - UP) and w.get_v(c + UP * (h - 1)) != World.WATER and not lava_near(w, c)

## Cost to make a cell free: 0 if already free, > 0 if it must be dug, -1 if impossible.
static func _clear_cost(w: World, c: Vector3i, dig: bool) -> float:
	var id := w.get_v(c)
	if World.KIND[id] != World.K_CUBE:
		if id == World.LAVA:
			return -1.0
		return 0.6 if id == World.WATER else 0.0
	if dig and diggable(w, c):
		return 2.0 + World.HARD[id] * 3.0
	return -1.0

static func _key(c: Vector3i) -> int:
	return c.x + World.SX * (c.y + World.SY * c.z)

static func _cell(k: int) -> Vector3i:
	return Vector3i(k % World.SX, (k / World.SX) % World.SY, k / (World.SX * World.SY))

static func _node_ok(w: World, c: Vector3i, h := 2) -> bool:
	return c.x > 0 and c.z > 0 and c.y > 1 and c.x < World.SX - 1 and c.z < World.SZ - 1 and c.y + h < World.SY \
		and w.get_v(c + UP * (h - 1)) != World.WATER and not lava_near(w, c)

## Cost to free the whole body column (h cells) above n, -1 if impossible.
static func _col_cost(w: World, n: Vector3i, dig: bool, h: int) -> float:
	var s := 0.0
	for i in h:
		var k := _clear_cost(w, n + UP * i, dig)
		if k < 0.0:
			return -1.0
		s += k
	return s

static func _col_cells(n: Vector3i, h: int) -> Array:
	var out: Array = []
	for i in h:
		out.append(n + UP * i)
	return out

static func _goal(w: World, c: Vector3i, mode: int, target: Vector3i, start: Vector3i, h := 2) -> bool:
	match mode:
		GOAL_CELL:
			return c == target
		GOAL_REACH:
			var o := target - c
			if o == -UP:  # mining under the feet: only if we land right below (no deep fall)
				return solid(w, target - UP)
			return o in REACH_OFF
		_:
			if c == start or not standable(w, c, h) or w.get_v(c) == World.WATER:
				return false
			for d in DIRS:
				if w.get_v(c + d) == World.WATER or w.get_v(c + d - UP) == World.LAVA:
					return false
			return true

## Returns {ok, cells: [Vector3i], clears: [[Vector3i]]} (start excluded). clears[i] = cells that must be
## free (dug if needed) before walking into cells[i]. partial: on failure, path to the closest node.
static func find(w: World, start: Vector3i, mode: int, target: Vector3i, dig := true, partial := false, max_nodes := MAX_NODES, h := 2) -> Dictionary:
	var sk := _key(start)
	var g := {sk: 0.0}
	var parent := {sk: -1}
	var clear := {sk: []}
	var closed := {}
	var hf: Array[float] = []
	var hk: Array[int] = []
	_push(hf, hk, 0.0, sk)
	var best := sk
	var best_h := INF
	var expanded := 0
	var found := -1
	var use_h := mode != GOAL_SAFE
	while not hk.is_empty() and expanded < max_nodes:
		var k := _pop(hf, hk)
		if closed.has(k):
			continue
		closed[k] = true
		expanded += 1
		var c := _cell(k)
		if _goal(w, c, mode, target, start, h):
			found = k
			break
		var h0 := float(absi(c.x - target.x) + absi(c.y - target.y) + absi(c.z - target.z))
		if h0 < best_h:
			best_h = h0
			best = k
		var gc: float = g[k]
		for e in _moves(w, c, dig, h):
			var n: Vector3i = e[0]
			var nk := _key(n)
			if closed.has(nk):
				continue
			var ng: float = gc + e[1]
			if ng < g.get(nk, INF):
				g[nk] = ng
				parent[nk] = k
				clear[nk] = e[2]
				var hc := H_WEIGHT * float(absi(n.x - target.x) + absi(n.y - target.y) + absi(n.z - target.z)) if use_h else 0.0
				_push(hf, hk, ng + hc, nk)
	var end := found
	if end < 0:
		if not partial or best == sk:
			return {"ok": false, "cells": [], "clears": [], "nodes": expanded}
		end = best
	var cells: Array = []
	var clears: Array = []
	var k2 := end
	while k2 != sk:
		cells.push_front(_cell(k2))
		clears.push_front(clear[k2])
		k2 = parent[k2]
	return {"ok": found >= 0, "cells": cells, "clears": clears, "nodes": expanded}

## [cell, cost, cells to clear]. h = body height in blocks (h = 2 gives the original human rules).
static func _moves(w: World, c: Vector3i, dig: bool, h := 2) -> Array:
	var out: Array = []
	for d in DIRS:
		var n: Vector3i = c + d
		var kc := _col_cost(w, n, dig, h)
		if kc >= 0.0:
			if solid(w, n - UP):
				if _node_ok(w, n, h):
					out.append([n, 1.0 + kc, _col_cells(n, h)])
			elif kc < 1.0:  # walk off the edge: fall up to MAX_FALL blocks
				for f in range(1, max_fall + 1):
					var m := n - UP * f
					if not passable(w, m) or w.get_v(m) == World.WATER:
						break
					if solid(w, m - UP):
						if _node_ok(w, m, h):
							out.append([m, 1.0 + 0.4 * f, _col_cells(n, h)])
						break
		# step up (1 .. max_up blocs en sautant, jusqu'à climb_up en escaladant) : n est un mur, on se retrouve au-dessus
		if solid(w, n):
			var top := _clear_cost(w, c + UP * h, dig)
			var lim := maxi(max_up, climb_up)
			var u := 1
			var head := 0.0   # coût de dégager la tête au fil des marches
			while u <= lim and top >= 0.0:
				if u > 1:
					if not solid(w, n + UP * (u - 1)):
						break  # le mur s'arrête : plus de marche plus haute (la marche u-1 était déjà proposée)
					var tk := _clear_cost(w, c + UP * (h + u - 1), dig)
					if tk < 0.0:
						break
					head += tk
				var nc := _col_cost(w, n + UP * u, dig, h)
				if nc >= 0.0 and _node_ok(w, n + UP * u, h):
					var cl: Array = []
					for j in u:
						cl.append(c + UP * (h + j))
					cl.append_array(_col_cells(n + UP * u, h))
					var extra := 0.0 if u == 1 else (0.9 * (u - 1) if u <= max_up else 1.6 * (u - 1))
					out.append([n + UP * u, 1.5 + top + head + nc + extra, cl])
				u += 1
	if dig:  # dig straight down
		var dn := c - UP
		if diggable(w, dn) and solid(w, dn - UP) and _node_ok(w, dn, h):
			out.append([dn, 2.5 + World.HARD[w.get_v(dn)] * 3.0, [dn]])
	return out

# ---- binary heap (parallel arrays)
static func _push(hf: Array[float], hk: Array[int], f: float, k: int) -> void:
	hf.append(f)
	hk.append(k)
	var i := hf.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if hf[p] <= hf[i]:
			break
		var tf := hf[p]; hf[p] = hf[i]; hf[i] = tf
		var tk := hk[p]; hk[p] = hk[i]; hk[i] = tk
		i = p

static func _pop(hf: Array[float], hk: Array[int]) -> int:
	var top := hk[0]
	var lf: float = hf.pop_back()
	var lk: int = hk.pop_back()
	if hf.is_empty():
		return top
	hf[0] = lf
	hk[0] = lk
	var i := 0
	var n := hf.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var s := i
		if l < n and hf[l] < hf[s]: s = l
		if r < n and hf[r] < hf[s]: s = r
		if s == i:
			break
		var tf := hf[s]; hf[s] = hf[i]; hf[i] = tf
		var tk := hk[s]; hk[s] = hk[i]; hk[i] = tk
		i = s
	return top
