class_name World extends RefCounted
## 3D voxel world: data, procedural cave generation, chunk meshing, cut-plane cap.

const SX := 160  # ATTENTION : à garder identique dans shaders/view_cut.gdshaderinc (WORLD_SIZE)
const SY := 64
const SZ := 80
const AREA_K := float(SX * SZ) / 4608.0  # taille relative à l'ancienne carte 96x48 : sert à garder la même densité de lieux
const CS := 8  # --- PERF --- small chunks: a block edit rebuilds 8x fewer cells

enum {AIR, DIRT, STONE, COAL, IRON, COPPER, CRYSTAL, WATER, LAVA, BEDROCK, TORCH, MUSHROOM, MOSS, STALAG, STALACT, GLOWPLANT, CHEST, BRICK, SIGN, FORGE, IRON_B, COPPER_B, SHARD, WARMROCK, AMBER, WOOD}  # --- SPAWN HUB ---: BRICK, SIGN
const AROWS := 8  # atlas: 4 columns x AROWS rows of 16x16 tiles
const K_AIR := 0
const K_CUBE := 1
const K_FLUID := 2
const K_CROSS := 3
const K_SIGN := 4  # --- SPAWN HUB --- (non solide, maillé par SpawnHub.mesh_sign)
const KIND := [0, 1, 1, 1, 1, 1, 1, 2, 2, 1, 3, 3, 1, 3, 3, 3, 1, 1, 4, 1, 1, 1, 3, 1, 1, 1]
const TILE := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 0, 14, 14, 15, 16, 17, 18, 19, 20, 21, 25, 26, 27, 28]
const EMIT := [0.0, 0.0, 0.12, 0.3, 0.3, 0.3, 1.0, 0.0, 1.0, 0.0, 1.0, 0.8, 0.22, 0.0, 0.0, 0.9, 0.0, 0.0, 0.0, 0.35, 0.0, 0.0, 0.9, 0.2, 1.0, 0.0]
## shader animation flag (vertex colour B): 0.25 crystal sparkle, 0.5 torch flicker, 0.75 slow glow pulse, 0.15 luminous veins (rock, ores, moss: only the bright texels glow)
const ANIM := [0.0, 0.0, 0.15, 0.15, 0.15, 0.15, 0.25, 0.0, 0.0, 0.0, 0.5, 0.75, 0.15, 0.0, 0.0, 0.75, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.25, 0.15, 0.25, 0.0]
## < 0: unbreakable (bedrock, chests: the player can look inside but not steal)
const HARD := [0.0, 0.3, 0.7, 0.8, 1.2, 1.0, 0.9, 0.0, 0.0, -1.0, 0.05, 0.05, 0.7, 0.15, 0.15, 0.05, -1.0, 1.5, 0.2, 1.2, 1.6, 1.6, 0.05, 0.9, 0.9, 0.5]
const NAMES := ["Air", "Terre", "Roche", "Charbon", "Fer", "Cuivre", "Cristal", "Eau", "Lave", "Socle", "Torche", "Champignon", "Roche moussue", "Stalagmite", "Stalactite", "Herbe luisante", "Coffre", "Pierre taillée", "Panneau", "Fonderie", "Lingot de fer", "Lingot de cuivre", "Éclat de cristal", "Roche ambrée", "Ambre", "Poutre"]
const MAPCOL := [Color(0.05, 0.05, 0.08), Color(0.33, 0.26, 0.4), Color(0.25, 0.3, 0.5), Color(0.15, 0.15, 0.17), Color(0.75, 0.6, 0.55), Color(0.85, 0.5, 0.25), Color(0.3, 0.95, 1.0), Color(0.2, 0.4, 0.9), Color(1.0, 0.45, 0.1), Color(0.18, 0.17, 0.2), Color(1.0, 0.85, 0.3), Color(0.3, 1.0, 0.7), Color(0.3, 0.5, 0.3), Color(0.55, 0.57, 0.62), Color(0.55, 0.57, 0.62), Color(0.4, 1.0, 0.8), Color(0.72, 0.48, 0.22), Color(0.62, 0.6, 0.66), Color(0.75, 0.55, 0.3), Color(0.9, 0.45, 0.15), Color(0.62, 0.66, 0.72), Color(0.85, 0.5, 0.28), Color(0.5, 0.95, 1.0), Color(0.5, 0.3, 0.26), Color(1.0, 0.7, 0.2), Color(0.5, 0.35, 0.2)]
var blocks := PackedByteArray()
var fluid_lvl := PackedByteArray()  # 1..8 (8 = plein) pour chaque cellule d'EAU, 0 ailleurs
var _fw := {}  # cellules d'eau actives (index) : seules elles sont simulées
var fluid_ticks := 0
var spawn := Vector3(48.5, 30.0, 24.5)
var light_spots: Array = []  # [Vector3 pos, Color col, float range]
var loot := {}  # Vector3i (coffre d'ancienne mine) -> {id: quantité}, copié dans main.chests à la création du monde
var mine_lights: Array = []  # torches posées par la génération (anciennes mines) : le jeu en fait de vraies torches (lumière + sauvegarde)
var pois: Array = []  # lieux à découvrir : {kind: "lac"|"jardin"|..., pos: Vector3, r: float}
var lava_surface: Array = []  # Vector3 points just above exposed lava (embers)
var faces: Array = []
var signs := {}  # --- SPAWN HUB --- Vector3i -> {text, face: Vector3i, wall: bool}
var off: Array = []
## --- MINI-BLOCS : un bloc peut être « entamé » en 8 morceaux (2x2x2). partial : index de cellule -> masque (1..254,
## bit = ox + 2*oy + 4*oz). L'id du bloc reste la matière ; une cellule absente de partial est un bloc entier.
var partial := {}

func _init() -> void:
	blocks.resize(SX * SY * SZ)
	fluid_lvl.resize(SX * SY * SZ)
	# normal, u, v, shade  (u x v = normal -> clockwise winding p0..p3)
	faces = [
		[Vector3i(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0), 0.8],
		[Vector3i(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0), 0.8],
		[Vector3i(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), 1.0],
		[Vector3i(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), 0.55],
		[Vector3i(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0), 0.9],
		[Vector3i(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0), 0.9],
	]
	off = [1, -1, SX, -SX, SX * SY, -SX * SY]

static func size_of(axis: int) -> int:
	return [SX, SY, SZ][axis]

func in_bounds(c: Vector3i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.z >= 0 and c.x < SX and c.y < SY and c.z < SZ

func get_b(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= SX or y >= SY or z >= SZ:
		return BEDROCK
	return blocks[x + SX * (y + SY * z)]

func get_v(c: Vector3i) -> int:
	return get_b(c.x, c.y, c.z)

var edits := 0  # bumped on every block change (minimap cache)

func set_v(c: Vector3i, id: int) -> void:
	edits += 1
	if in_bounds(c):
		var i := c.x + SX * (c.y + SY * c.z)
		blocks[i] = id
		partial.erase(i)
		fluid_lvl[i] = 8 if id == WATER else 0
		_wake(i)

func cell_idx(c: Vector3i) -> int:
	return c.x + SX * (c.y + SY * c.z)

## Masque des morceaux présents (255 = entier, 0 = vide / pas un cube).
func pieces(c: Vector3i) -> int:
	if not in_bounds(c) or KIND[get_v(c)] != K_CUBE:
		return 0
	return int(partial.get(cell_idx(c), 255))

## Fixe les morceaux d'un bloc : 0 = air, 255 = bloc entier, sinon bloc entamé de matière id.
func set_pieces(c: Vector3i, id: int, mask: int) -> void:
	if not in_bounds(c):
		return
	if mask <= 0:
		set_v(c, AIR)
	elif mask >= 255:
		set_v(c, id)
	else:
		set_v(c, id)
		partial[cell_idx(c)] = mask
		edits += 1

## Le morceau (ox,oy,oz) de la cellule c est-il plein ? (cellules hors monde = socle)
func piece_at(c: Vector3i, ox: int, oy: int, oz: int) -> bool:
	if not in_bounds(c):
		return true
	if KIND[get_v(c)] != K_CUBE:
		return false
	if partial.is_empty():
		return true
	var m: int = partial.get(cell_idx(c), 255)
	return (m >> (ox + 2 * oy + 4 * oz)) & 1 == 1

## Cube plein qui cache la face voisine (un bloc entamé ne cache rien).
func occludes(x: int, y: int, z: int) -> bool:
	if KIND[get_b(x, y, z)] != K_CUBE:
		return false
	if partial.is_empty() or x < 0 or y < 0 or z < 0 or x >= SX or y >= SY or z >= SZ:
		return true
	return not partial.has(x + SX * (y + SY * z))

## Pose de l'eau avec un niveau 1..8 (0 = air).
func set_water(c: Vector3i, lvl: int) -> void:
	if not in_bounds(c):
		return
	var i := c.x + SX * (c.y + SY * c.z)
	edits += 1
	blocks[i] = WATER if lvl > 0 else AIR
	fluid_lvl[i] = clampi(lvl, 0, 8)
	_wake(i)

## Hauteur (0..1) de l'eau dans la cellule ; pleine si de l'eau la surmonte.
func water_h(x: int, y: int, z: int) -> float:
	if get_b(x, y, z) != WATER:
		return 0.0
	if get_b(x, y + 1, z) == WATER:
		return 1.0
	return float(_lv(x + SX * (y + SY * z))) / 8.0

## Après génération / ancienne sauvegarde : toute l'eau existante est pleine.
func init_fluid() -> void:
	fluid_lvl.resize(blocks.size())
	fluid_lvl.fill(0)
	var i := blocks.find(WATER)
	while i >= 0:
		fluid_lvl[i] = 8
		i = blocks.find(WATER, i + 1)
	_fw.clear()

func load_fluid(lv: Variant) -> void:
	if lv is PackedByteArray and (lv as PackedByteArray).size() == blocks.size():
		fluid_lvl = lv
		_fw.clear()
		for v in range(1, 8):  # eau en mouvement au moment de la sauvegarde : on la réveille
			var i := fluid_lvl.find(v)
			while i >= 0:
				_fw[i] = true
				i = fluid_lvl.find(v, i + 1)
	else:
		init_fluid()

# ---------------------------------------------------------------- eau à niveaux (automate cellulaire)
func _lv(i: int) -> int:
	if blocks[i] != WATER:
		return 0
	var l := fluid_lvl[i]
	return l if l > 0 else 8

func _wake(i: int) -> void:
	var n := blocks.size()
	if blocks[i] == WATER:
		_fw[i] = true
	for o in off:
		var j: int = i + o
		if j >= 0 and j < n and blocks[j] == WATER:
			_fw[j] = true

func _put(i: int, l: int) -> void:
	blocks[i] = WATER if l > 0 else AIR
	fluid_lvl[i] = l
	if l <= 0:
		_fw.erase(i)
	_changed[i] = true
	_wake(i)

var _changed := {}

func _holds(i: int) -> bool:
	var b := blocks[i]
	return b == AIR or b == WATER

## Un pas de simulation, limité à `budget_us` microsecondes. Renvoie les indices de cellules modifiées.
func fluid_tick(budget_us: int) -> Array:
	_changed = {}
	if _fw.is_empty():
		return []
	fluid_ticks += 1
	var t0 := Time.get_ticks_usec()
	var keys: Array = _fw.keys()
	_fw = {}
	var rot := fluid_ticks & 3
	var hoff := [1, -1, SX * SY, -SX * SY]
	var n := keys.size()
	for k in n:
		if (k & 7) == 7 and Time.get_ticks_usec() - t0 > budget_us:
			for r in range(k, n):
				_fw[keys[r]] = true
			break
		var i: int = keys[k]
		var l := _lv(i)
		if l == 0:
			continue
		var x := i % SX
		var y := (i / SX) % SY
		var z := i / (SX * SY)
		if x < 1 or y < 1 or z < 1 or x >= SX - 1 or y >= SY - 1 or z >= SZ - 1:
			continue
		var b := i - SX
		if _holds(b):
			var lb := _lv(b)
			if lb < 8:
				var t := mini(l, 8 - lb)
				_put(b, lb + t)
				l -= t
				_put(i, l)
				if l == 0:
					continue
		var moved := false
		for q in 4:
			if l == 0:
				break
			var j: int = i + hoff[(q + rot) & 3]
			if not _holds(j):
				continue
			var lj := _lv(j)
			var d := l - lj
			var drop := lj < l and _holds(j - SX) and _lv(j - SX) < 8
			if d >= 2 or drop:
				var amt := maxi(1, d / 2)
				l -= amt
				_put(j, lj + amt)
				moved = true
		if moved:
			_put(i, l)
	return _changed.keys()

func total_water() -> int:
	var s := 0
	var i := blocks.find(WATER)
	while i >= 0:
		s += _lv(i)
		i = blocks.find(WATER, i + 1)
	return s

func is_solid(id: int) -> bool:
	return KIND[id] == K_CUBE

func count(id: int) -> int:
	return blocks.count(id)

func box_hits(p: Vector3, hw: float, hh: float) -> bool:
	for x in range(floori(p.x - hw), floori(p.x + hw - 0.0001) + 1):
		for y in range(floori(p.y), floori(p.y + hh - 0.0001) + 1):
			for z in range(floori(p.z - hw), floori(p.z + hw - 0.0001) + 1):
				if KIND[get_b(x, y, z)] == K_CUBE:
					if not partial.is_empty():
						var pi := x + SX * (y + SY * z)
						if partial.has(pi):
							if _pieces_hit(int(partial[pi]), x, y, z, p, hw, hh):
								return true
							continue
					return true
	return false

func _pieces_hit(mask: int, x: int, y: int, z: int, p: Vector3, hw: float, hh: float) -> bool:
	for b in 8:
		if (mask >> b) & 1 == 0:
			continue
		var bx := x + 0.5 * (b & 1)
		var by := y + 0.5 * ((b >> 1) & 1)
		var bz := z + 0.5 * ((b >> 2) & 1)
		if p.x - hw < bx + 0.5 and p.x + hw - 0.0001 > bx and p.y < by + 0.5 and p.y + hh - 0.0001 > by and p.z - hw < bz + 0.5 and p.z + hw - 0.0001 > bz:
			return true
	return false

## Y a-t-il un bloc entamé dans la boîte (pour la collision précise du joueur) ?
func partial_near(p: Vector3, hw: float, hh: float) -> bool:
	if partial.is_empty():
		return false
	for x in range(floori(p.x - hw) - 1, floori(p.x + hw) + 2):
		for y in range(floori(p.y) - 1, floori(p.y + hh) + 2):
			for z in range(floori(p.z - hw) - 1, floori(p.z + hw) + 2):
				if in_bounds(Vector3i(x, y, z)) and partial.has(x + SX * (y + SY * z)):
					return true
	return false

# ---------------------------------------------------------------- generation
func generate(seed_v: int) -> void:
	pois.clear()
	loot.clear()
	mine_lights.clear()
	partial.clear()
	var nc := FastNoiseLite.new(); nc.seed = seed_v; nc.frequency = 0.045
	var t1 := FastNoiseLite.new(); t1.seed = seed_v + 1; t1.frequency = 0.028
	var t2 := FastNoiseLite.new(); t2.seed = seed_v + 2; t2.frequency = 0.028
	var no := FastNoiseLite.new(); no.seed = seed_v + 3; no.frequency = 0.13
	var no2 := FastNoiseLite.new(); no2.seed = seed_v + 4; no2.frequency = 0.11
	var nm := FastNoiseLite.new(); nm.seed = seed_v + 5; nm.frequency = 0.06
	var ncr := FastNoiseLite.new(); ncr.seed = seed_v + 6; ncr.frequency = 0.09
	var cx := SX * 0.5; var cy := 33.0; var cz := SZ * 0.5
	var rng := RandomNumberGenerator.new(); rng.seed = seed_v
	# stone columns inside the main cavern (kept away from the spawn search start)
	var cols: Array = []
	while cols.size() < roundi(7 * AREA_K):
		var px := rng.randf_range(10.0, SX - 10.0)
		if absf(px - cx) < 6.0:
			continue
		cols.append(Vector3(px, rng.randf_range(10.0, SZ - 10.0), rng.randf_range(1.0, 1.8)))
	var slabs: Array = []
	slabs.resize(SZ)
	var gen_slab := func(z: int) -> void:  # une tranche en z (calcul pur : sûr sur plusieurs fils)
		var slab := PackedByteArray()
		slab.resize(SX * SY)
		for y in SY:
			for x in SX:
				var i := x + SX * y
				if x == 0 or y == 0 or z == 0 or x == SX - 1 or y == SY - 1 or z == SZ - 1:
					slab[i] = BEDROCK
					continue
				var dx := (x - cx) / (SX * 0.4375); var dy := (y - cy) / 14.0; var dz := (z - cz) / (SZ * 0.4167)
				var e := dx * dx + dy * dy + dz * dz + nc.get_noise_3d(x, y, z) * 0.5
				var air := e < 1.0
				if air:
					var fl := 1.0 + 2.2 * dy * dy
					for cl in cols:
						var ddx: float = x + 0.5 - cl.x
						var ddz: float = z + 0.5 - cl.y
						var rr: float = cl.z * fl + nc.get_noise_3d(x * 3.0, y, z * 3.0) * 0.5
						if ddx * ddx + ddz * ddz < rr * rr:
							air = false
							break
				if not air:
					var a := t1.get_noise_3d(x, y * 1.4, z); var b := t2.get_noise_3d(x, y * 1.4, z)
					air = absf(a) < 0.075 and absf(b) < 0.075
				if not air:
					air = nc.get_noise_3d(x * 1.3 + 100.0, y * 1.7, z * 1.3) > 0.42
				if air:
					slab[i] = AIR
					continue
				var id := STONE
				if y > 52 or nm.get_noise_3d(x, y, z) > 0.38:
					id = DIRT
				var o := no.get_noise_3d(x, y, z)
				if o > 0.55 and y > 14:
					id = COAL
				elif o < -0.6:
					id = COPPER
				elif no2.get_noise_3d(x, y, z) > 0.585 and y < 46:  # fer : filons plus fréquents (les recettes en demandent beaucoup)
					id = IRON
				slab[i] = id
		slabs[z] = slab
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(gen_slab, SZ, -1, true, "génération"))
	blocks = PackedByteArray()
	for z in SZ:
		blocks.append_array(slabs[z])
	_lakes(seed_v)
	init_fluid()
	_fill_floor_holes()
	# decoration: crystals, moss, mushrooms, speleothems, glowing plants
	for z in range(1, SZ - 1):
		for y in range(1, SY - 1):
			for x in range(1, SX - 1):
				var i := x + SX * (y + SY * z)
				var id := blocks[i]
				if id == STONE or id == DIRT:
					var exposed := false
					for o2 in off:
						if blocks[i + o2] == AIR:
							exposed = true
							break
					if not exposed:
						continue
					if ncr.get_noise_3d(x, y, z) > 0.55 and y < 46:
						blocks[i] = CRYSTAL
					elif id == STONE and y < 46 and no2.get_noise_3d(x * 1.3, y * 1.3, z * 1.3) > 0.5 and rng.randf() < 0.35:
						blocks[i] = IRON  # filons de fer affleurant sur les parois des cavernes : on en trouve sans creuser à l'aveugle
					elif id == STONE and blocks[i + SX] == AIR and nm.get_noise_3d(x * 2.0, 0, z * 2.0) > 0.1:
						blocks[i] = MOSS
				elif id == AIR and y < 58:
					var below := blocks[i - SX]
					var above := blocks[i + SX]
					var r := rng.randf()
					if KIND[above] == K_CUBE and above != BEDROCK and blocks[i - SX] == AIR:
						if r < 0.07 + 0.08 * maxf(ncr.get_noise_3d(x * 2.0, y, z * 2.0), 0.0):
							blocks[i] = STALACT
					elif below == STONE or below == MOSS or below == DIRT:
						var wetz := nm.get_noise_3d(x * 1.7, y, z * 1.7) > 0.15
						if r < 0.035:
							blocks[i] = MUSHROOM
						elif wetz and r < 0.09:
							blocks[i] = GLOWPLANT
						elif r < 0.13 and below != DIRT:
							blocks[i] = STALAG
	_gardens(seed_v)
	_warm_caves(seed_v)
	_mines(seed_v)
	_formations(seed_v)
	compute_styles(seed_v)
	_roughen(seed_v)
	# fluids, bottom-up so they rest on something -- PLACÉS APRÈS le relief (_roughen) : sinon les sols changent sous l'eau et elle coule ~500 pas (remaillage permanent, lag)
	for z in range(1, SZ - 1):
		for x in range(1, SX - 1):
			var wet := nm.get_noise_2d(x * 1.5, z * 1.5) > 0.05
			for y in range(1, SY - 1):
				var i := x + SX * (y + SY * z)
				if blocks[i] != AIR:
					continue
				var below := blocks[i - SX]
				if KIND[below] == K_AIR:
					continue
				if y <= 7:
					blocks[i] = LAVA
				elif wet and y <= 23 and y >= 16 and Vector2(x + 0.5 - SX * 0.5, z + 0.5 - SZ * 0.5).length() > SpawnHub.NO_WATER_R + 2.0:  # pas d'eau autour du spawn (la salle de départ la retirerait et ce qui reste coulerait)
					blocks[i] = WATER
	init_fluid()
	_find_spawn()
	_collect_lights()

## Comble les puits de 1-2 cases de large dans le sol des cavernes (case d'air isolee sous une salle ouverte).
## Un bout de tunnel (le dessus est lui aussi etroit), un liquide voisin ou un lac ne sont pas touches.
func _fill_floor_holes() -> void:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for z in range(2, SZ - 2):
		for y in range(9, 60):
			for x in range(2, SX - 2):
				var i := x + SX * (y + SY * z)
				if blocks[i] != AIR or blocks[i + SX] != AIR or not _open_room(x, y + 1, z):
					continue
				var cells := [Vector2i(x, z)]
				var ok := true
				# une 2e case d'air voisine (puits de 2 de large) ?
				for d in dirs:
					var nx: int = x + d.x
					var nz: int = z + d.y
					if blocks[nx + SX * (y + SY * nz)] == AIR and blocks[nx + SX * (y + 1 + SY * nz)] == AIR:
						cells.append(Vector2i(nx, nz))
				if cells.size() > 2:
					continue
				for c in cells:
					if c.x < 2 or c.y < 2 or c.x >= SX - 2 or c.y >= SZ - 2:
						ok = false
						break
					if KIND[blocks[c.x + SX * (y - 1 + SY * c.y)]] == K_FLUID:
						ok = false
					for d in dirs:
						var q := Vector2i(c.x + d.x, c.y + d.y)
						if q in cells:
							continue
						var b := blocks[q.x + SX * (y + SY * q.y)]
						if b == AIR or KIND[b] != K_CUBE:
							ok = false
					if not _open_room(c.x, y + 1, c.y):
						ok = false
				if ok:
					for c in cells:
						blocks[c.x + SX * (y + SY * c.y)] = STONE

## Vrai si la case (air) est dans une salle : au moins 2 voisines horizontales non pleines.
func _open_room(x: int, y: int, z: int) -> bool:
	var n := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if KIND[blocks[(x + d.x) + SX * (y + SY * (z + d.y))]] != K_CUBE:
			n += 1
	return n >= 2

## ---- STYLES DE ZONE : un bruit à très grande échelle découpe la grotte en zones à la règle propre (génération + rendu).
const STY_NORMAL := 0
const STY_DALLES := 1   # gros blocs réguliers 2x2x2, motif étiré, sol en grandes terrasses
const STY_STRATES := 2  # bandes horizontales de roche fine, parois en gradins
const STY_GRAVATS := 3  # éboulis : petits morceaux partout, grain fin
var styles := PackedByteArray()  # un octet par cellule (déterministe à partir de la graine : pas sauvegardé)

func compute_styles(seed_v: int) -> void:
	styles.resize(SX * SY * SZ)
	var nz := FastNoiseLite.new()
	nz.seed = seed_v + 9
	nz.frequency = 0.03
	var cx := SX * 0.5
	var cz := SZ * 0.5
	for z in SZ:
		for y in SY:
			for x in SX:
				var v := 0
				if Vector2(x + 0.5 - cx, z + 0.5 - cz).length() >= ROUGH_SKIP_R:
					var n := nz.get_noise_3d(x, y * 1.6, z)
					v = STY_STRATES if n < -0.22 else (STY_NORMAL if n < 0.12 else (STY_DALLES if n < 0.38 else STY_GRAVATS))
				styles[x + SX * (y + SY * z)] = v

func style_at(x: int, y: int, z: int) -> int:
	if styles.size() != SX * SY * SZ or x < 0 or y < 0 or z < 0 or x >= SX or y >= SY or z >= SZ:
		return 0
	return styles[x + SX * (y + SY * z)]

## Relief « moins cube » : sols aplatis (demi-dalles), bosses et creux sur les parois, bosses au sol / au plafond / sur les côtés
## qui rétrécissent parfois un passage (il faut alors miner un peu pour passer). Pur déterministe (graine) ; loin de la salle centrale.
const ROUGH_SKIP_R := 24.0  # rayon (blocs, horizontal) autour du centre épargné : salle de spawn, bases des IA
const MASK_BOT := 0b00110011  # moitié basse (oy = 0)
const MASK_TOP := 0b11001100  # moitié haute (oy = 1)
const MASK_XP := 0b10101010
const MASK_XN := 0b01010101
const MASK_ZP := 0b11110000
const MASK_ZN := 0b00001111

func _rnd(x: int, y: int, z: int, salt: int, seed_v: int) -> float:
	return float((_hash(x + seed_v * 7 + salt * 131, y + salt, z - seed_v) >> 4) & 1023) / 1024.0

## Sous-ensemble aléatoire non vide d'un masque (au moins 1 morceau, pas tout si possible).
func _subset(mask: int, r: float) -> int:
	var bits: Array = []
	for b in 8:
		if (mask >> b) & 1 == 1:
			bits.append(b)
	var m := 0
	var k := 1 + int(r * float(bits.size() - 1))  # 1 .. n-1 morceaux
	for j in k:
		m |= 1 << int(bits[(int(r * 977.0) + j * 3) % bits.size()])
	return m if m != 0 else mask

func _roughen(seed_v: int) -> void:
	var cx := SX * 0.5
	var cz := SZ * 0.5
	var sides := [[1, 0, MASK_XP], [-1, 0, MASK_XN], [0, 1, MASK_ZP], [0, -1, MASK_ZN]]
	for z in range(2, SZ - 2):
		for y in range(2, SY - 2):
			for x in range(2, SX - 2):
				if Vector2(x + 0.5 - cx, z + 0.5 - cz).length() < ROUGH_SKIP_R:
					continue
				var i := x + SX * (y + SY * z)
				var id := blocks[i]
				if id != AIR and id != STONE and id != DIRT:
					continue
				var st := int(styles[i])
				var c3 := Vector3i(x, y, z)
				var r := _rnd(x, y, z, 1, seed_v)
				var r2 := _rnd(x, y, z, 2, seed_v)
				if id == AIR:
					var below := blocks[i - SX]
					var above := blocks[i + SX]
					var solid_below: bool = (below == STONE or below == DIRT) and int(partial.get(i - SX, 255)) == 255
					var solid_above: bool = (above == STONE or above == DIRT) and int(partial.get(i + SX, 255)) == 255
					if st == STY_GRAVATS:
						if solid_below and r < 0.45:  # éboulis : 1 à 3 petits morceaux sur le sol
							set_pieces(c3, below, _subset(MASK_BOT, r2))
						elif solid_above and r > 0.93:
							set_pieces(c3, above, _subset(MASK_TOP, r2))
					elif st == STY_STRATES:
						if solid_above and (y & 1) == 1 and r < 0.16 and above_free(x, y, z):  # corniche : dalle fine sous le plafond
							set_pieces(c3, above, MASK_TOP)
						elif solid_below and r > 0.93:
							set_pieces(c3, below, MASK_BOT)
					elif st == STY_DALLES:
						if solid_below and ((x >> 1) + (z >> 1)) % 2 == 1 and r < 0.12 and blocks[i + SX] == AIR and blocks[i + 2 * SX] == AIR and blocks[i + 3 * SX] == AIR:  # grandes marches (jamais dans un passage bas)
							set_v(c3, below)
					else:
						if solid_below and r < 0.06:
							set_pieces(c3, below, MASK_BOT if r2 < 0.6 else _subset(MASK_BOT, r2))
						elif solid_above and r < 0.10 and above_free(x, y, z):
							set_pieces(c3, above, MASK_TOP if r2 < 0.6 else _subset(MASK_TOP, r2))
						elif r < 0.14:
							for sd in sides:
								var nb := get_b(x + sd[0], y, z + sd[1])
								if (nb == STONE or nb == DIRT) and not partial.has(i + sd[0] + SX * SY * sd[1]):
									set_pieces(c3, nb, sd[2] if r2 < 0.5 else _subset(sd[2], r2))
									break
				else:
					var top_air := blocks[i + SX] == AIR
					var side_air := -1
					for q in 4:
						if get_b(x + sides[q][0], y, z + sides[q][1]) == AIR:
							side_air = q
							break
					if st == STY_DALLES:
						if top_air and ((x >> 1) + (z >> 1)) % 2 == 1 and r < 0.75:
							set_pieces(c3, id, MASK_BOT)  # grandes dalles basses (2x2)
						elif side_air >= 0 and ((x >> 1) + (y >> 1) + (z >> 1)) % 2 == 1 and r < 0.85:
							set_pieces(c3, id, 255 & ~sides[side_air][2])  # grosse encoche 2x2x2
					elif st == STY_STRATES:
						if top_air and r < 0.55:
							set_pieces(c3, id, MASK_BOT)
						elif side_air >= 0 and (y & 1) == 1 and r < 0.92:
							set_pieces(c3, id, 255 & ~sides[side_air][2])  # gradins : une couche sur deux est en retrait
					elif st == STY_GRAVATS:
						if top_air and r < 0.55:
							set_pieces(c3, id, 255 & ~_subset(MASK_TOP, _rnd(x, y, z, 3, seed_v)))
						elif side_air >= 0 and r < 0.6:
							set_pieces(c3, id, 255 & ~_subset(sides[side_air][2], _rnd(x, y, z, 4, seed_v)))
					else:
						if top_air and r < 0.30:  # sol aplati : demi-dalle
							set_pieces(c3, id, MASK_BOT)
						elif top_air and r < 0.42:
							set_pieces(c3, id, 255 & ~_subset(MASK_TOP, _rnd(x, y, z, 3, seed_v)))
						elif r > 0.82 and side_air >= 0:
							set_pieces(c3, id, 255 & ~_subset(sides[side_air][2], _rnd(x, y, z, 4, seed_v)))

## Pas de bosse de plafond juste au-dessus d'un sol plat : il resterait un passage < 1 bloc partout.
func above_free(x: int, y: int, z: int) -> bool:
	return get_b(x, y - 1, z) == AIR or not partial.has(x + SX * ((y - 1) + SY * z))

## Lacs de cavité : une cuvette arrondie creusée dans un sol plat, remplie d'eau au ras du sol (la berge reste de la roche).
func _lakes(seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v + 201
	var made := 0
	for _try in roundi(2000 * AREA_K):
		if made >= roundi(7 * AREA_K):
			break
		var r := rng.randi_range(2, 5)
		var x := rng.randi_range(r + 3, SX - r - 4)
		var z := rng.randi_range(r + 3, SZ - r - 4)
		var y0 := _floor_y(x, z, 12, 50)
		if y0 < 0 or get_b(x, y0 + 2, z) != AIR or Vector2(x - SX * 0.5, z - SZ * 0.5).length() < SpawnHub.NO_WATER_R + r + 4.0:
			continue
		var maxd := rng.randi_range(2, 3)
		var wet := false
		for dz in range(-r - 1, r + 2):  # on évite de mordre sur de l'eau ou de la lave existantes
			for dx in range(-r - 1, r + 2):
				var c1 := get_b(x + dx, y0, z + dz)
				var c2 := get_b(x + dx, y0 - 1, z + dz)
				if c1 == WATER or c1 == LAVA or c2 == WATER or c2 == LAVA or c2 == BEDROCK:
					wet = true
		if wet:
			continue
		_carve_pool(x, y0, z, r, maxd, WATER)
		pois.append({"kind": "lac", "pos": Vector3(x + 0.5, y0, z + 0.5), "r": float(r)})
		made += 1

## Cuvette arrondie (r, profondeur maxd) remplie de liquide au ras du sol y0 ; lit et berge en roche.
func _carve_pool(x: int, y0: int, z: int, r: int, maxd: int, liquid: int) -> void:
	for dz in range(-r - 1, r + 2):
		for dx in range(-r - 1, r + 2):
			var q := float(dx * dx + dz * dz) / float(r * r)
			if q > float((r + 1) * (r + 1)) / float(r * r):
				continue
			var X := x + dx
			var Z := z + dz
			for k in range(0, maxd + 3):  # lit solide : on comble les trous sous la cuvette et la berge
				var yy := y0 - 1 - k
				if KIND[get_b(X, yy, Z)] != K_CUBE and yy > 1:
					blocks[X + SX * (yy + SY * Z)] = STONE
			if q > 1.0:
				continue  # berge : reste de la roche
			for yy in range(y0, y0 + 3):  # bosses et décor gênants au-dessus du liquide
				var c0 := get_b(X, yy, Z)
				if c0 != AIR and c0 != BEDROCK and KIND[c0] != K_FLUID:
					blocks[X + SX * (yy + SY * Z)] = AIR
			var d := maxi(1, roundi((1.0 - q) * maxd + 0.4))
			for k in d:
				blocks[X + SX * ((y0 - 1 - k) + SY * Z)] = liquid

## Le lieu existe-t-il vraiment dans les blocs actuels ? (une vieille sauvegarde a une carte sans lacs ni jardins)
func poi_exists(p: Dictionary) -> bool:
	var c := Vector3i(p.pos)
	if p.kind == "lac":
		return get_b(c.x, c.y - 1, c.z) == WATER
	var want := CRYSTAL if p.kind == "jardin" else (AMBER if p.kind == "chaud" else WOOD)
	var rr := 4 if p.kind != "mine" else 6
	for dz in range(-rr, rr + 1, 2):
		for dx in range(-rr, rr + 1, 2):
			for dy in range(-1, 4):
				if get_b(c.x + dx, c.y + dy, c.z + dz) == want:
					return true
	return false

## Premier sol libre (air sur un bloc plein) en descendant de y_hi à y_lo, ou -1.
func _floor_y(x: int, z: int, y_lo: int, y_hi: int) -> int:
	for y in range(y_hi, y_lo, -1):
		if get_b(x, y, z) == AIR and KIND[get_b(x, y - 1, z)] == K_CUBE and get_b(x, y - 1, z) != BEDROCK and get_b(x, y + 1, z) == AIR:
			return y
	return -1

## Jardins de cristaux : un bosquet de grandes aiguilles de cristal (hautes, effilées) au sol et au plafond, sur un lit de mousse.
## Les cristaux éclairent seuls (voir _collect_lights).
func _gardens(seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v + 303
	var made := 0
	for _try in roundi(400 * AREA_K):
		if made >= roundi(5 * AREA_K):
			break
		var cx := rng.randi_range(12, SX - 13)
		var cz := rng.randi_range(10, SZ - 11)
		var cy := _floor_y(cx, cz, 14, 48)
		if cy < 0:
			continue
		var open := 0  # il faut une vraie salle : de l'air autour et au-dessus
		for dz in range(-4, 5, 2):
			for dx in range(-4, 5, 2):
				for dy in range(0, 5, 2):
					if get_b(cx + dx, cy + dy, cz + dz) == AIR:
						open += 1
		if open < 30:
			continue
		var R := rng.randf_range(6.0, 8.0)
		var tint := rng.randi_range(0, 2)  # variété : turquoise, violet, rose (couleurs des lumières choisies ensuite)
		for dz in range(-int(R), int(R) + 1):
			for dx in range(-int(R), int(R) + 1):
				var dd := sqrt(float(dx * dx + dz * dz))
				if dd > R:
					continue
				var x := cx + dx
				var z := cz + dz
				if x < 2 or z < 2 or x > SX - 3 or z > SZ - 3:
					continue
				var fy := _floor_y(x, z, cy - 4, cy + 4)
				if fy >= 0:
					if get_b(x, fy - 1, z) == STONE or get_b(x, fy - 1, z) == DIRT:
						blocks[x + SX * ((fy - 1) + SY * z)] = MOSS  # lit de mousse bioluminescente
					if rng.randf() < 0.09 * (1.0 - dd / (R + 1.0)) + 0.012:
						_spire(x, fy, z, 1, rng.randi_range(3, 7))
				# aiguilles au plafond
				var cyy := fy if fy >= 0 else cy
				for yy in range(cyy + 2, mini(cyy + 14, SY - 3)):
					if get_b(x, yy, z) == AIR and KIND[get_b(x, yy + 1, z)] == K_CUBE and get_b(x, yy + 1, z) != BEDROCK:
						if rng.randf() < 0.05 * (1.0 - dd / (R + 1.0)):
							_spire(x, yy, z, -1, rng.randi_range(2, 5))
						break
		pois.append({"kind": "jardin", "pos": Vector3(cx + 0.5, cy, cz + 0.5), "r": R})
		made += 1
	_shards(rng)

## Petits éclats de cristal (blocs en croix, lumineux) : au sol, un peu partout dans les cavernes, plus denses autour des jardins.
func _shards(rng: RandomNumberGenerator) -> void:
	for _i in roundi(900 * AREA_K):
		var x := rng.randi_range(3, SX - 4)
		var z := rng.randi_range(3, SZ - 4)
		var y := _floor_y(x, z, 10, 52)
		if y < 0 or get_b(x, y, z) != AIR:
			continue
		var near := 0.0
		for p in pois:
			if p.kind == "jardin":
				near = maxf(near, 1.0 - Vector3(x, y, z).distance_to(p.pos) / (p.r + 6.0))
		if rng.randf() < 0.03 + 0.5 * near:
			blocks[x + SX * (y + SY * z)] = SHARD

## Zone du spawn : on n'y met ni cavité chaude ni mine (le départ reste dans la roche froide). Ellipse autour du centre de la carte.
func _near_spawn(x: float, z: float) -> bool:
	var a := (x - SX * 0.5) / 44.0
	var b := (z - SZ * 0.5) / 30.0
	return a * a + b * b < 1.0

## Cavités chaudes : roche ambrée, aiguilles d'ambre lumineuses, parfois une petite mare de lave douce. Contraste avec la roche froide.
func _warm_caves(seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v + 404
	var made := 0
	for _try in roundi(600 * AREA_K):
		if made >= roundi(2 * AREA_K):  # peu nombreuses, et réservées aux profondeurs (sol sous y 23) : on ne les voit pas depuis le niveau du spawn
			break
		var cx := rng.randi_range(12, SX - 13)
		var cz := rng.randi_range(10, SZ - 11)
		var cy := _floor_y(cx, cz, 13, 22)
		if cy < 0:
			continue
		if _near_spawn(cx, cz):
			continue
		var far := true
		for q in pois:
			if Vector2(cx, cz).distance_to(Vector2(q.pos.x, q.pos.z)) < float(q.r) + 5.0:
				far = false
		if not far:
			continue
		var open := 0
		for dz in range(-4, 5, 2):
			for dx in range(-4, 5, 2):
				for dy in range(0, 5, 2):
					if get_b(cx + dx, cy + dy, cz + dz) == AIR:
						open += 1
		if open < 26:
			continue
		var R := rng.randf_range(6.0, 8.5)
		for dz in range(-int(R) - 2, int(R) + 3):
			for dx in range(-int(R) - 2, int(R) + 3):
				var dd := sqrt(float(dx * dx + dz * dz))
				if dd > R + 2.0:
					continue
				var x := cx + dx
				var z := cz + dz
				if x < 2 or z < 2 or x > SX - 3 or z > SZ - 3:
					continue
				for y in range(cy - 6, mini(cy + 9, SY - 2)):
					var id := blocks[x + SX * (y + SY * z)]
					if (id == STONE or id == DIRT or id == MOSS) and rng.randf() < 0.9 * (1.0 - dd / (R + 3.0)) + 0.05:
						for o in off:
							if blocks[x + SX * (y + SY * z) + o] == AIR:
								blocks[x + SX * (y + SY * z)] = WARMROCK
								break
				if dd > R:
					continue
				var fy := _floor_y(x, z, cy - 4, cy + 4)
				if fy >= 0 and rng.randf() < 0.07 * (1.0 - dd / (R + 1.0)) + 0.01:
					_spire(x, fy, z, 1, rng.randi_range(2, 5), AMBER)
				var cyy := fy if fy >= 0 else cy
				for yy in range(cyy + 2, mini(cyy + 12, SY - 3)):
					if get_b(x, yy, z) == AIR and KIND[get_b(x, yy + 1, z)] == K_CUBE and get_b(x, yy + 1, z) != BEDROCK:
						if rng.randf() < 0.045 * (1.0 - dd / (R + 1.0)):
							_spire(x, yy, z, -1, rng.randi_range(2, 4), AMBER)
						break
		if rng.randf() < 0.5:  # mare de lave au centre (bord de roche)
			_carve_pool(cx, cy, cz, 2, 1, LAVA)
		pois.append({"kind": "chaud", "pos": Vector3(cx + 0.5, cy, cz + 0.5), "r": R})
		made += 1

## Anciennes mines : une galerie étayée de poutres qui s'enfonce dans la roche depuis une caverne, éboulis, torches, et un coffre au fond.
func _mines(seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v + 505
	var made := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for _try in roundi(500 * AREA_K):
		if made >= roundi(1.2 * AREA_K):
			break
		var x := rng.randi_range(10, SX - 11)
		var z := rng.randi_range(10, SZ - 11)
		var y0 := _floor_y(x, z, 13, 22)
		if y0 < 0:
			continue
		var d: Vector2i = dirs[rng.randi_range(0, 3)]
		var s0 := -1
		for st in range(1, 14):  # la paroi : premier mur plein au niveau du sol
			if KIND[get_b(x + d.x * st, y0 + 1, z + d.y * st)] == K_CUBE:
				s0 = st
				break
		if s0 < 0:
			continue
		var L := rng.randi_range(16, 24)
		var ex := x + d.x * (s0 + L + 5)
		var ez := z + d.y * (s0 + L + 5)
		if ex < 8 or ez < 8 or ex > SX - 9 or ez > SZ - 9 or _near_spawn(x, z) or _near_spawn(ex, ez) or _near_spawn((x + ex) * 0.5, (z + ez) * 0.5):
			continue
		var solid := 0
		for i in L:  # la galerie doit traverser de la vraie roche
			if KIND[get_b(x + d.x * (s0 + i), y0 + 1, z + d.y * (s0 + i))] == K_CUBE:
				solid += 1
		if solid < L * 6 / 10:
			continue
		var near := false
		for q in pois:
			if Vector2(x, z).distance_to(Vector2(q.pos.x, q.pos.z)) < float(q.r) + 4.0:
				near = true
		if near:
			continue
		var pr := Vector2i(d.y, d.x)  # perpendiculaire horizontale
		for i in range(0, L + 7):
			var bx := x + d.x * (s0 + i)
			var bz := z + d.y * (s0 + i)
			var room := i >= L  # salle du fond : plus large
			var hw := 3 if room else 2
			for w in range(-hw, hw + 1):
				var cx := bx + pr.x * w
				var cz := bz + pr.y * w
				if get_b(cx, y0 - 1, cz) != BEDROCK and KIND[get_b(cx, y0 - 1, cz)] != K_CUBE:
					blocks[cx + SX * ((y0 - 1) + SY * cz)] = STONE  # sol plein
				for h in range(0, 4):
					if get_b(cx, y0 + h, cz) != BEDROCK:
						blocks[cx + SX * ((y0 + h) + SY * cz)] = AIR
			if not room and i % 4 == 0:  # cadre de poutres : deux montants et un linteau
				for w in [-2, 2]:
					for h in range(0, 3):
						blocks[(bx + pr.x * w) + SX * ((y0 + h) + SY * (bz + pr.y * w))] = WOOD
				for w in range(-2, 3):
					blocks[(bx + pr.x * w) + SX * ((y0 + 3) + SY * (bz + pr.y * w))] = WOOD
				if i % 8 == 0 and rng.randf() < 0.75:  # torche au pied d'un montant
					var tc := Vector3i(bx + pr.x, y0, bz + pr.y)
					blocks[tc.x + SX * (tc.y + SY * tc.z)] = TORCH
					mine_lights.append(Vector3(tc.x + 0.5, tc.y + 0.5, tc.z + 0.5))
			elif not room and i > 2 and i < L - 3 and rng.randf() < 0.1:  # éboulis
				var w2 := rng.randi_range(-1, 1)
				blocks[(bx + pr.x * w2) + SX * (y0 + SY * (bz + pr.y * w2))] = STONE
				if rng.randf() < 0.5:
					blocks[(bx + pr.x * w2) + SX * ((y0 + 1) + SY * (bz + pr.y * w2))] = STONE
		var cc := Vector3i(x + d.x * (s0 + L + 4), y0, z + d.y * (s0 + L + 4))
		blocks[cc.x + SX * (cc.y + SY * cc.z)] = CHEST
		var items := {TORCH: rng.randi_range(6, 14), COAL: rng.randi_range(3, 8), (IRON if rng.randf() < 0.5 else COPPER): rng.randi_range(3, 7)}
		if rng.randf() < 0.4:
			items[SHARD] = rng.randi_range(1, 3)
		loot[cc] = items
		pois.append({"kind": "mine", "pos": Vector3(x + d.x * s0 + 0.5, y0, z + d.y * s0 + 0.5), "r": 8.0})
		made += 1

## Aiguille de cristal : colonne de cristal qui s'effile (base épaisse d'un bloc autour, pointe seule), dir = 1 vers le haut, -1 vers le bas.
func _spire(x: int, y: int, z: int, dir: int, h: int, blk: int = 6) -> void:  # 6 = CRYSTAL
	for l in h:
		var yy := y + dir * l
		if yy < 2 or yy > SY - 3:
			return
		var c := get_b(x, yy, z)
		if c != AIR and KIND[c] != K_CROSS:
			return
		blocks[x + SX * (yy + SY * z)] = blk
		if l < h / 2 and h >= 4:  # base plus large
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if get_b(x + o.x, yy, z + o.y) == AIR and (l == 0 or get_b(x + o.x, yy - dir, z + o.y) != AIR):
					blocks[(x + o.x) + SX * (yy + SY * (z + o.y))] = blk

## Cones de roche (stalagmites montantes, stalactites descendantes) : des silhouettes variées pour se repérer.
func _formations(seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v + 77
	for z in range(3, SZ - 3):
		for y in range(3, SY - 8):
			for x in range(3, SX - 3):
				if blocks[x + SX * (y + SY * z)] != AIR or rng.randf() > 0.006:
					continue
				var up := is_solid(get_b(x, y - 1, z)) and get_b(x, y + 1, z) == AIR
				var down := is_solid(get_b(x, y + 1, z)) and get_b(x, y - 1, z) == AIR
				if not up and not down:
					continue
				var dir := 1 if up else -1
				_cone(x, y, z, dir, rng.randi_range(3, 5), rng.randf() < 0.2)

func _cone(x: int, y: int, z: int, dir: int, h: int, tip: bool) -> void:
	var cells: Array = []
	for l in h:
		var yy := y + dir * l
		var r := 1 if l < h - 2 else 0
		cells.append(Vector3i(x, yy, z))
		if r == 1:
			for o in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				cells.append(Vector3i(x, yy, z) + o)
	for c in cells:  # only into free air, never into walls or water
		if get_b(c.x, c.y, c.z) != AIR:
			return
	for c in cells:
		set_v(c, STONE)
	if tip:
		set_v(Vector3i(x, y + dir * (h - 1), z), CRYSTAL)

func _find_spawn() -> void:
	var cz := SZ / 2
	for r in range(0, 40):
		for sgn in [1, -1]:
			var x: int = SX / 2 + r * sgn
			for dz in [0, 2, -2, 4, -4]:
				var z: int = cz + dz
				for y in range(44, 27, -1):
					var c := Vector3i(x, y, z)
					if get_v(c) == AIR and get_b(x, y + 1, z) == AIR and get_b(x, y + 2, z) == AIR and is_solid(get_b(x, y - 1, z)):
						spawn = Vector3(x + 0.5, y, z + 0.5)
						return
	# fallback: carve a room
	var c0 := Vector3i(SX / 2, 32, cz)
	for x in range(c0.x - 3, c0.x + 4):
		for y in range(c0.y, c0.y + 4):
			for z in range(c0.z - 2, c0.z + 3):
				set_v(Vector3i(x, y, z), AIR)
		for z in range(c0.z - 2, c0.z + 3):
			set_v(Vector3i(x, c0.y - 1, z), STONE)
	spawn = Vector3(c0.x + 0.5, c0.y, c0.z + 0.5)

func _collect_lights() -> void:
	light_spots.clear()
	var crys: Array = []
	var lava: Array = []
	var glow: Array = []
	for z in range(1, SZ - 1):
		for y in range(1, SY - 1):
			for x in range(1, SX - 1):
				var id := blocks[x + SX * (y + SY * z)]
				if id == CRYSTAL:
					crys.append(Vector3(x + 0.5, y + 0.5, z + 0.5))
				elif id == LAVA and get_b(x, y + 1, z) == AIR:
					lava.append(Vector3(x + 0.5, y + 1.0, z + 0.5))
				elif id == GLOWPLANT:
					glow.append(Vector3(x + 0.5, y + 0.5, z + 0.5))
	_spread(crys, 6.0, 45, [Color(0.3, 0.9, 1.0), Color(0.75, 0.4, 1.0)], 7.0)
	_spread(lava, 8.0, 25, [Color(1.0, 0.42, 0.1)], 9.0)
	_spread(glow, 8.0, 14, [Color(0.3, 1.0, 0.65), Color(0.35, 0.9, 1.0)], 5.5)
	lava_surface = lava
	var amb: Array = []
	for z2 in range(1, SZ - 1):
		for y2 in range(1, SY - 1):
			for x2 in range(1, SX - 1):
				if blocks[x2 + SX * (y2 + SY * z2)] == AMBER:
					amb.append(Vector3(x2 + 0.5, y2 + 0.5, z2 + 0.5))
	_spread(amb, 6.0, 30, [Color(1.0, 0.65, 0.2), Color(1.0, 0.5, 0.15)], 7.0)
	for p in pois:  # les lacs luisent doucement (bleu froid) : repérables de loin
		if p.kind == "lac":
			light_spots.append([p.pos + Vector3(0.0, 0.9, 0.0), Color(0.25, 0.6, 1.0), float(p.r) + 5.0])

func _spread(pts: Array, min_d: float, cap: int, cols: Array, rng_v: float) -> void:
	var placed: Array = []
	for p in pts:
		if placed.size() >= cap:
			break
		var ok := true
		for q in placed:
			if p.distance_to(q) < min_d:
				ok = false
				break
		if ok:
			placed.append(p)
			light_spots.append([p, cols[placed.size() % cols.size()], rng_v])

# ---------------------------------------------------------------- meshing
class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	var uv2 := PackedVector2Array()
	var style_cur := 0.0  # style de zone des sommets poussés (lu par le shader via UV2.x)

	func quad(center: Vector3, u: Vector3, w: Vector3, nrm: Vector3, tile: int, col: Color, flip := false) -> void:
		var b := v.size()
		var hu := u * 0.5
		var hw := w * 0.5
		v.push_back(center - hu - hw); v.push_back(center - hu + hw)
		v.push_back(center + hu + hw); v.push_back(center + hu - hw)
		var tx := float(tile % 4) * 0.25
		var th := 1.0 / AROWS
		var ty := float(tile / 4) * th
		var e := 0.001
		var y0 := ty + th - e
		var y1 := ty + e
		if flip:
			var t := y0; y0 = y1; y1 = t
		uv.push_back(Vector2(tx + e, y0)); uv.push_back(Vector2(tx + e, y1))
		uv.push_back(Vector2(tx + 0.25 - e, y1)); uv.push_back(Vector2(tx + 0.25 - e, y0))
		for k in 4:
			n.push_back(nrm)
			c.push_back(col)
			uv2.push_back(Vector2(style_cur, 0.0))
		idx.push_back(b); idx.push_back(b + 1); idx.push_back(b + 2)
		idx.push_back(b); idx.push_back(b + 2); idx.push_back(b + 3)

	## Polygone convexe (sommets dans l'ordre horaire vu de l'extérieur), éventail de triangles.
	func poly(pts: PackedVector3Array, uvs: PackedVector2Array, nrm: Vector3, col: Color) -> void:
		var b := v.size()
		for k in pts.size():
			v.push_back(pts[k])
			uv.push_back(uvs[k])
			n.push_back(nrm)
			c.push_back(col)
			uv2.push_back(Vector2(style_cur, 0.0))
		for k in range(1, pts.size() - 1):
			idx.push_back(b); idx.push_back(b + k); idx.push_back(b + k + 1)

	func commit(mesh: ArrayMesh, mat: Material) -> void:
		if v.is_empty():
			return
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)

static func _hash(x: int, y: int, z: int) -> int:
	return (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)

static func _vary(x: int, y: int, z: int) -> float:
	return 0.9 + 0.1 * float(_hash(x, y, z) & 255) / 255.0

## Per-block tile: stone and dirt pick one of two variants from a position hash.
static func tile_at(id: int, x: int, y: int, z: int) -> int:
	if id == STONE:  # roche : unie ou striée la plupart du temps, parfois une veine turquoise / violette ou des éclats
		var k := ((_hash(x, y, z) * 2654435761) >> 16) & 15
		if k < 5:
			return 2
		if k < 10:
			return 12
		return [24, 24, 22, 22, 23, 24][k - 10]
	if id == WARMROCK:
		return 26 if ((_hash(x, y, z) * 2654435761) >> 16) & 15 < 11 else 29
	if id == DIRT and (_hash(x, y, z) >> 9) & 1 == 1:
		return 13
	return TILE[id]

func _face(buf: Buf, x: int, y: int, z: int, f: int, id: int) -> void:
	var fd: Array = faces[f]
	var nrm: Vector3 = Vector3(fd[0])
	var center := Vector3(x + 0.5, y + 0.5, z + 0.5) + nrm * 0.5
	var em: float = EMIT[id]
	var shade: float = 1.0 if em > 0.0 and ANIM[id] != 0.15 else float(fd[3]) * _vary(x, y, z)
	buf.quad(center, fd[1], fd[2], nrm, tile_at(id, x, y, z), Color(shade, em, ANIM[id], 1.0))

## ---- RELIEF DU SOL : les dessus de roche / terre sont découpés en 4x4 facettes dont les sommets intérieurs montent ou descendent
## (les bords restent droits : aucune fissure avec les voisins). Chaque triangle a sa normale : ombrage « polygone ».
const RELIEF_N := 4
const RELIEF_AMP := 0.10
var relief := true

func _face_relief(buf: Buf, x: int, y: int, z: int, id: int) -> void:
	var n := RELIEF_N
	var tile := tile_at(id, x, y, z)
	var tx := float(tile % 4) * 0.25
	var th := 1.0 / AROWS
	var ty := float(tile / 4) * th
	var vary := _vary(x, y, z)
	var em: float = EMIT[id]
	var pos: Array = []
	for j in n + 1:
		for i in n + 1:
			var py := y + 1.0
			if i > 0 and i < n and j > 0 and j < n:
				py += (float((_hash(x * n + i, y, z * n + j) >> 5) & 1023) / 1023.0 - 0.5) * 2.0 * RELIEF_AMP
			pos.append(Vector3(x + float(i) / n, py, z + float(j) / n))
	for j in n:
		for i in n:
			var p00: Vector3 = pos[j * (n + 1) + i]
			var p10: Vector3 = pos[j * (n + 1) + i + 1]
			var p01: Vector3 = pos[(j + 1) * (n + 1) + i]
			var p11: Vector3 = pos[(j + 1) * (n + 1) + i + 1]
			var flip := ((i + j + x + z) & 1) == 1  # diagonale alternée : pas de motif en croix
			var tris: Array = [[p00, p10, p11], [p00, p11, p01]] if not flip else [[p00, p10, p01], [p10, p11, p01]]
			for t in tris:
				var a: Vector3 = t[0]
				var b: Vector3 = t[1]
				var c: Vector3 = t[2]
				var cr := (b - a).cross(c - a)
				var nrm := cr.normalized()
				if nrm.y > 0.0:  # sens horaire vu du dessus : le produit vectoriel doit regarder vers le bas
					var tmp := b
					b = c
					c = tmp
					nrm = -nrm
				nrm = -nrm  # normale vers le haut
				var pts := PackedVector3Array([a, b, c])
				var uvs := PackedVector2Array()
				for q in pts:
					uvs.push_back(Vector2(tx + 0.25 * clampf(q.x - x, 0.004, 0.996), ty + th * clampf(q.z - z, 0.004, 0.996)))
				var shade := (1.0 if em > 0.0 else 1.0 * vary * (0.62 + 0.38 * nrm.y))
				buf.poly(pts, uvs, nrm, Color(shade, em, ANIM[id], 1.0))

## ---- BISEAUX : les arêtes convexes de la roche sont coupées à 45° (facettes « polygone »). Rendu seulement : les collisions restent cubiques.
const BEVEL := 0.25
const EDGE_PAIRS := [[0, 2], [0, 3], [1, 2], [1, 3], [0, 4], [0, 5], [1, 4], [1, 5], [2, 4], [2, 5], [3, 4], [3, 5]]  # (faces voisines) de chacune des 12 arêtes
var _tpl := {}  # (masque d'arêtes | faces exposées << 12) -> polygones du cube biseauté
var chamfer := true

static func chamferable(id: int) -> bool:
	return id == STONE or id == DIRT or id == COAL or id == IRON or id == COPPER or id == MOSS

func _convex(x: int, y: int, z: int, e: int) -> bool:
	var na: Vector3i = faces[EDGE_PAIRS[e][0]][0]
	var nb: Vector3i = faces[EDGE_PAIRS[e][1]][0]
	return not occludes(x + na.x, y + na.y, z + na.z) and not occludes(x + nb.x, y + nb.y, z + nb.z) and not occludes(x + na.x + nb.x, y + na.y + nb.y, z + na.z + nb.z)

## L'arête e du bloc est-elle biseautée ? Il faut qu'elle soit convexe sur tout son tracé (jusqu'à l'air) : pas de trou aux jonctions.
func _edge_flag(x: int, y: int, z: int, e: int) -> bool:
	if not _convex(x, y, z, e):
		return false
	var na: Vector3i = faces[EDGE_PAIRS[e][0]][0]
	var nb: Vector3i = faces[EDGE_PAIRS[e][1]][0]
	var ax := Vector3i(absi(na.y * nb.z - na.z * nb.y), absi(na.z * nb.x - na.x * nb.z), absi(na.x * nb.y - na.y * nb.x))
	for dir in [1, -1]:
		for k in range(1, 10):
			var qx: int = x + ax.x * dir * k
			var qy: int = y + ax.y * dir * k
			var qz: int = z + ax.z * dir * k
			if not occludes(qx, qy, qz):
				break  # fin de l'arête : l'air
			if not chamferable(get_b(qx, qy, qz)) or not _convex(qx, qy, qz, e):
				return false
	return true

static func _clip(poly: Array, n: Vector3, d: float) -> Array:
	var out: Array = []
	var cnt := poly.size()
	for i in cnt:
		var a: Vector3 = poly[i]
		var b: Vector3 = poly[(i + 1) % cnt]
		var da := n.dot(a) - d
		var db := n.dot(b) - d
		if da <= 1e-6:
			out.append(a)
		if (da < -1e-6 and db > 1e-6) or (da > 1e-6 and db < -1e-6):
			out.append(a + (b - a) * (da / (da - db)))
	var clean: Array = []
	for q in out:
		if clean.is_empty() or (clean[clean.size() - 1] as Vector3).distance_to(q) > 1e-5:
			clean.append(q)
	if clean.size() > 1 and (clean[0] as Vector3).distance_to(clean[clean.size() - 1]) <= 1e-5:
		clean.pop_back()
	return clean

## Cube biseauté (coordonnées locales 0..1) : liste de [sommets, normale, face de projection de la texture, est_biseau].
func _template(mask: int, expo: int) -> Array:
	var key := mask | (expo << 12)
	if _tpl.has(key):
		return _tpl[key]
	var polys: Array = []
	for f in 6:
		var fd: Array = faces[f]
		var n := Vector3(fd[0])
		var u := Vector3(fd[1])
		var w := Vector3(fd[2])
		var c := Vector3(0.5, 0.5, 0.5) + n * 0.5
		polys.append([[c - u * 0.5 - w * 0.5, c - u * 0.5 + w * 0.5, c + u * 0.5 + w * 0.5, c + u * 0.5 - w * 0.5], n, f])
	var planes: Array = []
	for e in 12:
		if (mask >> e) & 1 == 0:
			continue
		var na := Vector3(faces[EDGE_PAIRS[e][0]][0])
		var nb := Vector3(faces[EDGE_PAIRS[e][1]][0])
		var pn := (na + nb).normalized()
		var edge_pt := Vector3(0.5, 0.5, 0.5) + (na + nb) * 0.5
		planes.append([pn, pn.dot(edge_pt) - BEVEL * 0.7071068, int(EDGE_PAIRS[e][0])])
	for pl in planes:
		var np: Array = []
		for poly in polys:
			var cl := _clip(poly[0], pl[0], pl[1])
			if cl.size() >= 3:
				np.append([cl, poly[1], poly[2]])
		polys = np
	var out: Array = []
	for poly in polys:
		if (expo >> int(poly[2])) & 1 == 1:  # faces cachées par un voisin plein : omises
			out.append([poly[0], poly[1], poly[2], false])
	for pl in planes:
		var pts: Array = []
		for poly in polys:
			for q in poly[0]:
				if absf((pl[0] as Vector3).dot(q) - float(pl[1])) < 1e-4:
					var dup := false
					for o in pts:
						if (o as Vector3).distance_to(q) < 1e-4:
							dup = true
							break
					if not dup:
						pts.append(q)
		if pts.size() >= 3:
			var cen := Vector3.ZERO
			for q in pts:
				cen += q
			cen /= float(pts.size())
			var ax := ((pts[0] as Vector3) - cen).normalized()
			var ay := (pl[0] as Vector3).cross(ax)
			pts.sort_custom(func(a: Vector3, b: Vector3) -> bool:
				return atan2((a - cen).dot(ay), (a - cen).dot(ax)) < atan2((b - cen).dot(ay), (b - cen).dot(ax)))
			out.append([pts, pl[0], pl[2], true])
	for o in out:  # sens horaire vu de l'extérieur (comme Buf.quad)
		var pp: Array = o[0]
		if ((pp[1] as Vector3) - (pp[0] as Vector3)).cross((pp[2] as Vector3) - (pp[0] as Vector3)).dot(o[1]) > 0.0:
			pp.reverse()
	_tpl[key] = out
	return out

func _emit_chamfer(buf: Buf, x: int, y: int, z: int, id: int, mask: int, expo: int) -> void:
	var em: float = EMIT[id]
	var vary := _vary(x, y, z)
	var tile := tile_at(id, x, y, z)
	var tx := float(tile % 4) * 0.25
	var th := 1.0 / AROWS
	var ty := float(tile / 4) * th
	var org := Vector3(x, y, z)
	for o in _template(mask, expo):
		var pts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var fd: Array = faces[int(o[2])]
		var nrm: Vector3 = o[1]
		for q in o[0]:
			var qv: Vector3 = q
			pts.push_back(org + qv)
			var cq := qv - Vector3(0.5, 0.5, 0.5)
			uvs.push_back(Vector2(tx + 0.25 * clampf(cq.dot(Vector3(fd[1])) + 0.5, 0.004, 0.996), ty + th * clampf(0.5 - cq.dot(Vector3(fd[2])), 0.004, 0.996)))
		var shade: float
		if em > 0.0:
			shade = 1.0
		elif o[3]:  # facette : mélange des ombrages des deux faces
			var sy := 1.0 if nrm.y > 0.0 else 0.55
			shade = (absf(nrm.x) * 0.8 + absf(nrm.y) * sy + absf(nrm.z) * 0.9) / (absf(nrm.x) + absf(nrm.y) + absf(nrm.z)) * vary
		else:
			shade = float(fd[3]) * vary
		buf.poly(pts, uvs, nrm, Color(shade, em, ANIM[id], 1.0))

## Bloc entamé : chaque morceau présent est un mini-cube de 0,5 ; on ne dessine que les faces non cachées par un autre morceau.
func _partial_mesh(buf: Buf, x: int, y: int, z: int, id: int, mask: int) -> void:
	var em: float = EMIT[id]
	for b in 8:
		if (mask >> b) & 1 == 0:
			continue
		var ox := b & 1
		var oy := (b >> 1) & 1
		var oz := (b >> 2) & 1
		for f in 6:
			var fd: Array = faces[f]
			var d: Vector3i = fd[0]
			var nx := ox + d.x
			var ny := oy + d.y
			var nz := oz + d.z
			var present: bool
			if nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 and nz >= 0 and nz <= 1:
				present = (mask >> (nx + 2 * ny + 4 * nz)) & 1 == 1
			else:
				present = piece_at(Vector3i(x + d.x if nx < 0 or nx > 1 else x, y + d.y if ny < 0 or ny > 1 else y, z + d.z if nz < 0 or nz > 1 else z), posmod(nx, 2), posmod(ny, 2), posmod(nz, 2))
			if present:
				continue
			var nrm := Vector3(d)
			var center := Vector3(x, y, z) + (Vector3(ox, oy, oz) + Vector3(0.5, 0.5, 0.5)) * 0.5 + nrm * 0.25
			var shade: float = 1.0 if em > 0.0 else float(fd[3]) * _vary(x, y, z)
			buf.quad(center, Vector3(fd[1]) * 0.5, Vector3(fd[2]) * 0.5, nrm, tile_at(id, x, y, z), Color(shade, em, ANIM[id], 1.0))

## Eau à niveaux : hauteur = niveau / 8 (dessus et côtés), pas de dessus sous une autre eau.
func _water(buf: Buf, x: int, y: int, z: int) -> void:
	var h := water_h(x, y, z)
	for f in 6:
		var fd: Array = faces[f]
		var d: Vector3i = fd[0]
		var nb := get_b(x + d.x, y + d.y, z + d.z)
		if nb == WATER and f != 2 and f != 3:
			var nh := water_h(x + d.x, y + d.y, z + d.z)
			if nh >= h:
				continue
			_wside(buf, x, y, z, f, nh, h)
			continue
		if KIND[nb] == K_CUBE or nb == WATER:
			continue
		if f == 2:
			var cen := Vector3(x + 0.5, y + h, z + 0.5)
			buf.quad(cen, fd[1], fd[2], Vector3(fd[0]), TILE[WATER], Color(float(fd[3]) * _vary(x, y, z), 0.0, 0.0, 1.0))
		elif f == 3:
			_face(buf, x, y, z, f, WATER)
		else:
			_wside(buf, x, y, z, f, 0.0, h)

func _wside(buf: Buf, x: int, y: int, z: int, f: int, y0: float, y1: float) -> void:
	var fd: Array = faces[f]
	var nrm := Vector3(fd[0])
	var cen := Vector3(x + 0.5, y + (y0 + y1) * 0.5, z + 0.5) + nrm * 0.5
	buf.quad(cen, fd[1], Vector3(fd[2]) * (y1 - y0), nrm, TILE[WATER], Color(float(fd[3]) * _vary(x, y, z), 0.0, 0.0, 1.0))

func _cross(buf: Buf, x: int, y: int, z: int, id: int) -> void:
	var c := Vector3(x + 0.5, y + 0.5, z + 0.5)
	var col := Color(0.9 if id == STALAG or id == STALACT else 1.0, EMIT[id], ANIM[id], 1.0)
	var up := Vector3.UP
	var t: int = TILE[id]
	for u in [Vector3(0.7, 0, 0.7), Vector3(-0.7, 0, -0.7), Vector3(0.7, 0, -0.7), Vector3(-0.7, 0, 0.7)]:
		buf.quad(c, u, up, u.cross(up).normalized(), t, col, id == STALACT)

func build_chunk(cx: int, cy: int, cz: int, mat_s: Material, mat_f: Material) -> ArrayMesh:
	return chunk_mesh(chunk_bufs(cx, cy, cz), mat_s, mat_f)

## Étape de calcul pure (aucun nœud, aucune ressource) : sûre à lancer sur plusieurs fils tant que les blocs ne changent pas.
func chunk_bufs(cx: int, cy: int, cz: int) -> Array:
	var bs := Buf.new()
	var bf := Buf.new()
	var has_part := not partial.is_empty()
	for z in range(cz * CS, mini(cz * CS + CS, SZ)):
		for y in range(cy * CS, mini(cy * CS + CS, SY)):
			var base := SX * (y + SY * z)
			for x in range(cx * CS, mini(cx * CS + CS, SX)):
				var id := blocks[base + x]
				if id == AIR:
					continue
				var k: int = KIND[id]
				bs.style_cur = float(styles[base + x]) if (k == K_CUBE and not styles.is_empty()) else 0.0
				if k == K_CROSS:
					_cross(bs, x, y, z, id)
					continue
				if k == K_SIGN:  # --- SPAWN HUB ---
					SpawnHub.mesh_sign(bs, x, y, z, signs.get(Vector3i(x, y, z), {}))
					continue
				if id == WATER:
					_water(bf, x, y, z)
					continue
				if has_part and partial.has(base + x):
					_partial_mesh(bs, x, y, z, id, int(partial[base + x]))
					continue
				if chamfer and k == K_CUBE and chamferable(id):
					var expo := 0
					var nexp := 0
					for f in 6:
						var d0: Vector3i = faces[f][0]
						if not occludes(x + d0.x, y + d0.y, z + d0.z):
							expo |= 1 << f
							nexp += 1
					if nexp >= 2:
						var emask := 0
						for e in 12:
							if _edge_flag(x, y, z, e):
								emask |= 1 << e
						if emask != 0:
							_emit_chamfer(bs, x, y, z, id, emask, expo)
							continue
				var interior := x > 0 and y > 0 and z > 0 and x < SX - 1 and y < SY - 1 and z < SZ - 1
				for f in 6:
					var nb: int
					if interior:
						nb = blocks[base + x + off[f]]
					else:
						var d: Vector3i = faces[f][0]
						nb = get_b(x + d.x, y + d.y, z + d.z)
					var nk: int = KIND[nb]
					if k == K_CUBE:
						if nk == K_CUBE and (not has_part or occludes(x + faces[f][0].x, y + faces[f][0].y, z + faces[f][0].z)):
							continue
						if f == 2 and relief and chamferable(id):
							_face_relief(bs, x, y, z, id)
						else:
							_face(bs, x, y, z, f, id)
					else:
						if nk == K_CUBE or nb == id:
							continue
						_face(bf, x, y, z, f, id)
	return [bs, bf]

## Étape finale (fil principal) : crée la ressource maillage.
func chunk_mesh(bufs: Array, mat_s: Material, mat_f: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	(bufs[0] as Buf).commit(mesh, mat_s)
	(bufs[1] as Buf).commit(mesh, mat_f)
	return mesh

## Cap faces on the cut plane: solid cells of layer L whose camera-side neighbour is solid
## (those have no regular face because the neighbour is hidden by the shader).
func build_cap(axis: int, s: int, layer: int, mat_s: Material, mat_f: Material, around := Vector3i(-1, -1, -1), r := 10000) -> ArrayMesh:
	var bs := Buf.new()
	var bf := Buf.new()
	var f := 0
	for i in 6:
		var d: Vector3i = faces[i][0]
		if d[axis] == -s:
			f = i
	var a1 := (axis + 1) % 3
	var a2 := (axis + 2) % 3
	if layer >= 0 and layer < size_of(axis):  # --- PERF --- optionally only a window of radius r around a cell
		for i in range(maxi(0, around[a1] - r), mini(size_of(a1), around[a1] + r + 1)):
			for j in range(maxi(0, around[a2] - r), mini(size_of(a2), around[a2] + r + 1)):
				var p := Vector3i()
				p[axis] = layer; p[a1] = i; p[a2] = j
				var id := get_v(p)
				var k: int = KIND[id]
				if k != K_CUBE and k != K_FLUID:
					continue
				var q := p
				q[axis] = layer - s
				var need := true
				if in_bounds(q):
					var nb := get_v(q)
					need = KIND[nb] == K_CUBE if k == K_CUBE else (KIND[nb] == K_CUBE or nb == id)
				if need:
					_face(bs if k == K_CUBE else bf, p.x, p.y, p.z, f, id)
	var mesh := ArrayMesh.new()
	bs.commit(mesh, mat_s)
	bf.commit(mesh, mat_f)
	return mesh
