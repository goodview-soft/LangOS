class_name SpawnHub extends RefCounted
## Spawn : cirque rond à ciel ouvert (disque plat central, puis gradins qui descendent d'un bloc par anneau), sans eau,
## taillé après la génération, protégé (ni casse ni pose), zone sûre (pas de PvP).
## Contient aussi les tuiles pixel-art (pierre taillée, panneaux) et le maillage des panneaux.

const IW := 20  # intérieur : largeur X
const IH := 7   # intérieur : hauteur d'air
const ID := 9   # intérieur : profondeur Z
const TILE_BRICK := 17
const TILE_SIGN := 18       # panneau sur poteau (icône d'inventaire)
const TILE_SIGN_WALL := 19  # panneau mural
const R_FLAT := 9.0   # rayon du disque plat central (large : le sol reste continu autour du joueur)
const RINGS := 4      # anneaux de gradins (chacun 1 bloc plus bas)
const RING_W := 3.0   # largeur d'un anneau
const R_ALL := R_FLAT + RINGS * RING_W  # rayon total (21)
const HEAD := 9       # hauteur d'air au-dessus du disque central
const NO_WATER_R := 32.0
const TITLE := "Spawn de Deep Miner"

var ix0 := 0  # coin intérieur min (x)
var fy := 0   # y du sol (dalle)
var iz0 := 0  # coin intérieur min (z)
var spawn_pos := Vector3.ZERO
var cave_spot := Vector3.ZERO  # point libre dans les cavernes, hors de la salle
var torches: Array = []        # Vector3i des torches de la salle
var exits: Array = []          # [start Vector3i, dir Vector3i, longueur, débouche sur une caverne]
var title_cell := Vector3i.ZERO

# ---------------------------------------------------------------- requêtes
func center_cell() -> Vector2i:
	return Vector2i(ix0 + IW / 2, iz0 + ID / 2)

func box_min() -> Vector3i:
	var c := center_cell()
	return Vector3i(c.x - int(R_ALL) - 1, fy - RINGS - 1, c.y - int(R_ALL) - 1)

func box_max() -> Vector3i:  # inclus
	var c := center_cell()
	return Vector3i(c.x + int(R_ALL) + 1, fy + HEAD, c.y + int(R_ALL) + 1)

## Anneau d'une cellule : 0 = disque plat, 1..RINGS = gradins, -1 = hors du cirque.
func ring_of(x: int, z: int) -> int:
	var c := center_cell()
	var d := Vector2(x - c.x, z - c.y).length()
	if d <= R_FLAT:
		return 0
	if d <= R_ALL:
		return ceili((d - R_FLAT) / RING_W)
	return -1

## Cellule du cirque (sol, air, mur de bord) : ni cassable ni posable.
func is_protected(c: Vector3i) -> bool:
	var ce := center_cell()
	return c.y >= fy - RINGS - 1 and c.y <= fy + HEAD and Vector2(c.x - ce.x, c.z - ce.y).length() <= R_ALL + 1.5

## Zone sûre : pas d'attaque ni de minage (combat, PNJ).
func is_safe_zone(pos: Vector3) -> bool:
	var ce := center_cell()
	return pos.y >= fy - RINGS - 1 and pos.y < fy + HEAD + 1 and Vector2(pos.x - ce.x - 0.5, pos.z - ce.y - 0.5).length() <= R_ALL + 0.5

# ---------------------------------------------------------------- construction
func build(w: World) -> void:
	var cave0 := w.spawn  # point trouvé par World._find_spawn (dans les cavernes)
	ix0 = World.SX / 2 - IW / 2
	iz0 = World.SZ / 2 - ID / 2
	fy = 30
	var ce := center_cell()
	# plus d'eau autour du spawn (rayon NO_WATER_R, toute la hauteur)
	var nr := int(NO_WATER_R)
	for z in range(maxi(ce.y - nr, 1), mini(ce.y + nr, World.SZ - 2) + 1):
		for x in range(maxi(ce.x - nr, 1), mini(ce.x + nr, World.SX - 2) + 1):
			if Vector2(x - ce.x, z - ce.y).length() > NO_WATER_R:
				continue
			for y in range(1, World.SY - 1):
				if w.get_b(x, y, z) == World.WATER:
					w.set_v(Vector3i(x, y, z), World.AIR)
	# le cirque : disque plat puis gradins (sol à fy - anneau), air au-dessus, mur de roche sur le bord
	var rr := int(R_ALL) + 2
	for z in range(ce.y - rr, ce.y + rr + 1):
		for x in range(ce.x - rr, ce.x + rr + 1):
			var k := ring_of(x, z)
			if k >= 0:
				var fl := fy - k
				for y in range(fl + 1, fy + HEAD + 1):
					w.set_v(Vector3i(x, y, z), World.AIR)
				w.set_v(Vector3i(x, fl, z), World.BRICK if k == 0 else World.STONE)
				for y in [fl - 1, fl - 2]:
					if not w.is_solid(w.get_b(x, y, z)):
						w.set_v(Vector3i(x, y, z), World.STONE)
			elif is_protected(Vector3i(x, fy, z)):  # mur de bord (2 blocs) : l'eau et les cavernes ne coulent pas dedans
				for y in range(fy - RINGS - 1, fy + HEAD + 1):
					if World.KIND[w.get_b(x, y, z)] != World.K_CUBE:
						w.set_v(Vector3i(x, y, z), World.STONE)
	# sorties : ouest, est, nord, au niveau du dernier gradin
	exits.clear()
	var ey := fy - RINGS + 1
	_tunnel(w, Vector3i(ce.x - int(R_ALL), ey, ce.y), Vector3i(-1, 0, 0), Vector3i(0, 0, 1))
	_tunnel(w, Vector3i(ce.x + int(R_ALL), ey, ce.y), Vector3i(1, 0, 0), Vector3i(0, 0, 1))
	_tunnel(w, Vector3i(ce.x - 1, ey, ce.y - int(R_ALL)), Vector3i(0, 0, -1), Vector3i(1, 0, 0))
	# torches sur piédestaux autour du disque plat
	torches.clear()
	for i in 8:
		var an := TAU * i / 8.0 + 0.2
		var tx := ce.x + roundi(cos(an) * (R_FLAT - 1.0))
		var tz := ce.y + roundi(sin(an) * (R_FLAT - 1.0))
		w.set_v(Vector3i(tx, fy + 1, tz), World.BRICK)
		var t := Vector3i(tx, fy + 2, tz)
		w.set_v(t, World.TORCH)
		torches.append(t)
	for lx in [-2, 2]:  # herbes luisantes près du centre
		w.set_v(Vector3i(ce.x + lx, fy + 1, ce.y + 2), World.GLOWPLANT)
	# panneaux (sur pied)
	w.signs.clear()
	title_cell = Vector3i(ce.x, fy + 1, ce.y - 3)
	_sign(w, title_cell, Vector3i(0, 0, 1), false, TITLE)
	_sign(w, Vector3i(ce.x - 3, fy + 1, ce.y - 3), Vector3i(0, 0, 1), false, "Clic G : miner   Clic D : poser")
	_sign(w, Vector3i(ce.x + 3, fy + 1, ce.y - 3), Vector3i(0, 0, 1), false, "/home /sethome /spawn /aide")
	spawn_pos = Vector3(ce.x + 0.5, fy + 1, ce.y + 0.5)
	var c0 := Vector3i(cave0)
	var far := true
	for d in [Vector3i(-6, -2, -3), Vector3i(6, -2, -3), Vector3i(-6, 3, 3), Vector3i(6, 3, 3), Vector3i(0, 0, 0)]:
		far = far and not is_protected(c0 + d)
	cave_spot = cave0 if far and w.get_v(c0) == World.AIR else _find_cave_spot(w)
	w.spawn = spawn_pos

func _sign(w: World, c: Vector3i, face: Vector3i, wall: bool, text: String) -> void:
	w.set_v(c, World.SIGN)
	w.signs[c] = {"text": text, "face": face, "wall": wall}

## Site proche du centre, le plus possible dans la roche, sans fluide.
func _choose_site(w: World) -> void:
	var best := -1e9
	var center := Vector3(World.SX * 0.5, 33.0, World.SZ * 0.5)
	for ccx in range(32, 65, 2):
		for f in range(20, 37, 2):
			for ccz in range(16, 33, 2):
				var x0 := ccx - IW / 2
				var z0 := ccz - ID / 2
				if x0 - 1 < 2 or x0 + IW > World.SX - 3 or z0 - 1 < 2 or z0 + ID > World.SZ - 3 or f + IH + 1 > World.SY - 3:
					continue
				var solid := 0
				var fluid := 0
				var n := 0
				for z in range(z0 - 1, z0 + ID + 1, 2):
					for y in range(f, f + IH + 2, 2):
						for x in range(x0 - 1, x0 + IW + 1, 2):
							var k: int = World.KIND[w.get_b(x, y, z)]
							n += 1
							if k == World.K_CUBE:
								solid += 1
							elif k == World.K_FLUID:
								fluid += 1
				var sc := float(solid) / n - 0.02 * Vector3(ccx, f + 4, ccz).distance_to(center) - 0.05 * fluid
				if sc > best:
					best = sc
					ix0 = x0; fy = f; iz0 = z0

## Galerie 2 de large x 3 de haut, jusqu'à déboucher sur une caverne (2 tranches déjà libres).
func _tunnel(w: World, start: Vector3i, dir: Vector3i, side: Vector3i) -> void:
	var free_run := 0
	var reached := false
	var steps := 0
	for s in 32:
		var base := start + dir * s
		var all_free := true
		for k in 2:
			for h in 3:
				var c := base + side * k + Vector3i(0, h, 0)
				if World.KIND[w.get_v(c)] == World.K_CUBE or World.KIND[w.get_v(c)] == World.K_FLUID:
					all_free = false
		if s >= 2 and all_free:
			free_run += 1
			if free_run >= 2:
				reached = true
				break
		else:
			free_run = 0
		var stop := false
		for k in 2:
			var col := base + side * k
			if not w.in_bounds(col + dir) or w.get_v(col + dir) == World.BEDROCK:
				stop = true
			for h in 3:
				w.set_v(col + Vector3i(0, h, 0), World.AIR)
			var top := col + Vector3i(0, 3, 0)
			if World.KIND[w.get_v(top)] == World.K_CROSS or World.KIND[w.get_v(top)] == World.K_FLUID:
				w.set_v(top, World.AIR)
			var fl := col - Vector3i(0, 1, 0)
			if not w.is_solid(w.get_v(fl)):
				w.set_v(fl, World.STONE)
		steps = s + 1
		if stop:
			break
	exits.append([start, dir, steps, reached])

func _find_cave_spot(w: World) -> Vector3:
	for r in range(0, 44):
		for sgn in [1, -1]:
			var x: int = World.SX / 2 + r * sgn
			for dz in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 8, -8, 10, -10, 12, -12]:
				var z: int = World.SZ / 2 + dz
				for y in range(50, 10, -1):
					var c := Vector3i(x, y, z)
					if is_protected(c) or absi(x - (ix0 + IW / 2)) < IW / 2 + 4 and absi(z - (iz0 + ID / 2)) < ID / 2 + 4 and y >= fy - 3 and y <= fy + IH + 4:
						continue
					if w.get_v(c) == World.AIR and w.get_b(x, y + 1, z) == World.AIR and w.get_b(x, y + 2, z) == World.AIR and w.is_solid(w.get_b(x, y - 1, z)) \
							and w.get_b(x + 1, y, z) == World.AIR and w.get_b(x - 1, y, z) == World.AIR:
						if _clear_around(w, c):
							_tidy(w, c)
							return Vector3(x + 0.5, y, z + 0.5)
	return spawn_pos

## Pas de roche ni de fluide autour (couches voisines comprises) : place nette pour bouger.
func _clear_around(w: World, c: Vector3i) -> bool:
	for dz in range(-1, 2):
		for dx in range(-5, 6):
			for dy in range(0, 4 if dz == 0 else 3):
				var k: int = World.KIND[w.get_b(c.x + dx, c.y + dy, c.z + dz)]
				if k == World.K_CUBE or k == World.K_FLUID:
					return false
	return true

## Retire le petit décor (stalagmites, plantes) autour du point de caverne.
func _tidy(w: World, c: Vector3i) -> void:
	for dz in range(-1, 2):
		for dx in range(-4, 5):
			for dy in range(0, 3):
				var p := c + Vector3i(dx, dy, dz)
				if World.KIND[w.get_v(p)] == World.K_CROSS and w.get_v(p) != World.TORCH:
					w.set_v(p, World.AIR)

# ---------------------------------------------------------------- maillage des panneaux
static func mesh_sign(buf, x: int, y: int, z: int, info: Dictionary) -> void:
	var face: Vector3i = info.get("face", Vector3i(0, 0, 1))
	if face.y != 0 or face == Vector3i.ZERO:
		face = Vector3i(0, 0, 1)
	var n := Vector3(face)
	var u := Vector3.UP.cross(n)
	var c := Vector3(x + 0.5, y + 0.5, z + 0.5)
	var col := Color(1.0, 0.0, 0.0, 1.0)
	var colb := Color(0.75, 0.0, 0.0, 1.0)
	if info.get("wall", false):
		var p := c - n * (0.5 - 1.5 / 16.0)
		buf.quad(p + n * 0.01, u, Vector3.UP, n, TILE_SIGN_WALL, col)
		buf.quad(p - n * 0.01, -u, Vector3.UP, -n, TILE_SIGN_WALL, colb)
	else:
		buf.quad(c + n * 0.03, u, Vector3.UP, n, TILE_SIGN, col)
		buf.quad(c - n * 0.03, -u, Vector3.UP, -n, TILE_SIGN, colb)

# ---------------------------------------------------------------- tuiles (atlas 4x8, index 16+)
static func draw_tiles(img: Image, rng: RandomNumberGenerator) -> void:
	_tile_brick(img, (TILE_BRICK % 4) * 16, (TILE_BRICK / 4) * 16, rng)
	_tile_sign(img, (TILE_SIGN % 4) * 16, (TILE_SIGN / 4) * 16, true)
	_tile_sign(img, (TILE_SIGN_WALL % 4) * 16, (TILE_SIGN_WALL / 4) * 16, false)

static func _tile_brick(img: Image, ox: int, oy: int, rng: RandomNumberGenerator) -> void:
	var base := [Color.html("#4c5680"), Color.html("#454e76"), Color.html("#535e8a")]
	var hi := Color.html("#7a88bc")
	var lo := Color.html("#323a62")
	var mortar := Color.html("#1b2038")
	for y in 16:
		var row := y / 4
		var shift := 0 if row % 2 == 0 else 4
		for x in 16:
			var lx := posmod(x + shift, 8)
			var ly := y % 4
			var c: Color = base[rng.randi_range(0, 2)] if rng.randf() < 0.35 else base[0]
			if ly == 3 or lx == 7:
				c = mortar
			elif ly == 0 or lx == 0:
				c = hi
			elif ly == 2 and lx >= 5 or lx == 6:
				c = lo
			img.set_pixel(ox + x, oy + y, c)

static func _tile_sign(img: Image, ox: int, oy: int, post: bool) -> void:
	var wood := Color.html("#b07d43")
	var wood_l := Color.html("#c99a5c")
	var wood_d := Color.html("#8a5b2c")
	var edge := Color.html("#4e3017")
	var ink := Color.html("#3a2412")
	var y0 := 2 if post else 3
	var y1 := 10 if post else 12
	if post:
		for y in range(y1 + 1, 16):
			for x in [7, 8]:
				img.set_pixel(ox + x, oy + y, wood_d if x == 8 else wood)
	for y in range(y0, y1 + 1):
		for x in range(1, 15):
			var c := wood
			if y == y0 or y == y1 or x == 1 or x == 14:
				c = edge
			elif y == y0 + 1:
				c = wood_l
			elif (y - y0) % 3 == 0:
				c = wood_d
			img.set_pixel(ox + x, oy + y, c)
	# lignes d'écriture
	for ly in [y0 + 2, y0 + 4, y0 + 6]:
		if ly >= y1:
			continue
		for x in range(3, 13 if ly != y0 + 6 else 9):
			if (x * 7 + ly) % 5 != 0:
				img.set_pixel(ox + x, oy + ly, ink)
	if not post:  # clous
		for p in [Vector2i(2, y0 + 1), Vector2i(13, y0 + 1)]:
			img.set_pixel(ox + p.x, oy + p.y, Color.html("#d8d8e0"))
