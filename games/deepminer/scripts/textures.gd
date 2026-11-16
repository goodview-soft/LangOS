class_name Tex extends RefCounted
## Textures 100% procedurales (atlas de blocs, icone de pioche, sprites du mineur).

const T := 16
const CLEAR := Color(0, 0, 0, 0)


static func _c(h: String) -> Color:
	return Color.html(h)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_px(img, x, y, c)


static func _line(img: Image, a: Vector2i, b: Vector2i, c: Color) -> void:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while true:
		_px(img, p.x, p.y, c)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy


# Tuile: coordonnees locales 0..15 -> pixel de l'atlas.
static func _t(img: Image, ox: int, oy: int, x: int, y: int, c: Color) -> void:
	img.set_pixel(ox + posmod(x, T), oy + posmod(y, T), c)


static func _speckle(img: Image, ox: int, oy: int, pal: Array, rng: RandomNumberGenerator, weights: Array) -> void:
	# base: tire dans la palette selon des poids (0 dominant), avec regroupement horizontal.
	var total := 0.0
	for w in weights:
		total += w
	for y in range(T):
		for x in range(T):
			var r := rng.randf() * total
			var k := 0
			for i in range(weights.size()):
				r -= weights[i]
				if r <= 0.0:
					k = i
					break
			img.set_pixel(ox + x, oy + y, pal[k])
	# lissage leger: un pixel isole identique a son voisin gauche une fois sur deux
	for y in range(T):
		for x in range(1, T):
			if rng.randf() < 0.25:
				img.set_pixel(ox + x, oy + y, img.get_pixel(ox + x - 1, oy + y))


static func _bevel(img: Image, ox: int, oy: int, amount: float) -> void:
	for i in range(T):
		var top := img.get_pixel(ox + i, oy)
		img.set_pixel(ox + i, oy, top.lightened(amount))
		var left := img.get_pixel(ox, oy + i)
		img.set_pixel(ox, oy + i, left.lightened(amount))
		var bot := img.get_pixel(ox + i, oy + 15)
		img.set_pixel(ox + i, oy + 15, bot.darkened(amount * 1.2))
		var right := img.get_pixel(ox + 15, oy + i)
		img.set_pixel(ox + 15, oy + i, right.darkened(amount * 1.2))


static func _rock_base(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, dark := false, variant := 0) -> void:
	var pal: Array
	if dark:
		pal = [_c("#2a2f5c"), _c("#232850"), _c("#343a6a"), _c("#181b3a")]  # socle / roche profonde : indigo très sombre
	elif variant == 2:  # roche chaude : brun brûlé / rouille sombre
		pal = [_c("#4a3030"), _c("#402828"), _c("#5a3c3a"), _c("#2a1a1e")]
	elif variant == 1:  # roche froide : indigo / ardoise violette (le gris a disparu)
		pal = [_c("#2b2d52"), _c("#25274a"), _c("#363a64"), _c("#1b1d39")]
	else:
		pal = [_c("#2a3355"), _c("#242c4d"), _c("#364068"), _c("#1a2039")]
	_speckle(img, ox, oy, pal, rng, [5, 3, 2, 1.5])
	if not dark:
		# galets facon Terraria: blocs clairs, reflet haut-gauche, ombre bas-droite
		var n := 4 if variant == 0 else 3
		for k in range(n):
			var cx := rng.randi_range(1, 14)
			var cy := rng.randi_range(1, 14)
			var rw := rng.randi_range(2, 3)
			var rh := rng.randi_range(1, 2)
			for y in range(-rh, rh + 1):
				for x in range(-rw, rw + 1):
					if absf(x) / (rw + 0.5) + absf(y) / (rh + 0.5) > 1.15:
						continue
					var col: Color = pal[2]
					if y == -rh or x == -rw:
						col = pal[2].lightened(0.12)
					elif y == rh or x == rw:
						col = pal[1]
					_t(img, ox, oy, cx + x, cy + y, col)
			_t(img, ox, oy, cx + rw + 1, cy + 1, pal[3])
			_t(img, ox, oy, cx, cy + rh + 1, pal[3])
		if variant == 1:
			# strate sombre en travers
			var y0 := rng.randi_range(5, 10)
			for x in range(T):
				_t(img, ox, oy, x, y0 + int(round(sin(x * 0.7) * 1.2)), pal[3].darkened(0.1))
	# fissures sombres
	for n2 in range(2):
		var x := rng.randi_range(2, 13)
		var y := rng.randi_range(2, 13)
		for s in range(rng.randi_range(2, 4)):
			img.set_pixel(ox + x, oy + y, pal[3])
			x = clampi(x + rng.randi_range(-1, 1), 0, 15)
			y = clampi(y + 1, 0, 15)


## Veine lumineuse : une fissure qui serpente d'un bord à l'autre (marche aléatoire), coeur très clair (qui brille) et halo sombre.
static func _vein(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, core: Color, mid: Color, halo: Color) -> void:
	var y := rng.randi_range(3, 12)
	var drift := rng.randi_range(-1, 1)
	for x in range(T):
		_t(img, ox, oy, x, y - 1, halo)
		_t(img, ox, oy, x, y + 1, halo)
		_t(img, ox, oy, x, y, core if x % 4 != 2 else mid)
		var r := rng.randf()
		var step := 0
		if r < 0.28:
			step = -1
		elif r < 0.56:
			step = 1
		if rng.randf() < 0.35:
			step += drift
		step = clampi(step, -1, 1)
		if step != 0:  # pas en diagonale : on comble le coin pour garder un trait continu
			_t(img, ox, oy, x, y + step, mid)
		y = clampi(y + step, 2, 13)
		if rng.randf() < 0.1:
			_t(img, ox, oy, x, y + 2, mid)  # petite branche


## Roche chaude (cavités ambrées) : plain, ou avec une veine de braise.
static func _tile_warm(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, vein: bool) -> void:
	_rock_base(img, ox, oy, rng, false, 2)
	if vein:
		_vein(img, ox, oy, rng, _c("#ffe9a8"), _c("#ffa040"), _c("#7a3210"))
	else:
		for k in range(3):
			var px := rng.randi_range(1, 13)
			var py := rng.randi_range(1, 13)
			_t(img, ox, oy, px, py, _c("#ffd27a"))
			_t(img, ox, oy, px + 1, py, _c("#c8601c"))
			_t(img, ox, oy, px, py + 1, _c("#7a3210"))
	_bevel(img, ox, oy, 0.07)


## Ambre : bloc de cristal orangé lumineux.
static func _tile_amber(img: Image, ox: int, oy: int, rng: RandomNumberGenerator) -> void:
	_speckle(img, ox, oy, [_c("#2a1a1a"), _c("#221515"), _c("#33201e"), _c("#1a1010")], rng, [5, 3, 2, 1])
	var a1 := [_c("#ffb030"), _c("#ffe08a"), _c("#b86a10"), _c("#fff6d0"), _c("#4a2606")]
	var a2 := [_c("#ff7a30"), _c("#ffc090"), _c("#a03a0a"), _c("#fff0e0"), _c("#3f1404")]
	for sh in [[3, 15, 9, 3, a2], [12, 15, 7, 3, a1], [8, 15, 13, 5, a1], [5, 7, 4, 2, a1], [13, 6, 4, 2, a2]]:
		_shard(img, ox, oy, sh[0], sh[1], sh[2], sh[3], sh[4])
	for p in [Vector2i(10, 3), Vector2i(2, 4)]:
		_t(img, ox, oy, p.x, p.y, _c("#ffffff"))
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			_t(img, ox, oy, p.x + d.x, p.y + d.y, _c("#ffd890"))
	_bevel(img, ox, oy, 0.05)


## Poutre : planches verticales de bois vieilli.
static func _tile_wood(img: Image, ox: int, oy: int, rng: RandomNumberGenerator) -> void:
	var cols := [_c("#7a5230"), _c("#6b4624"), _c("#86603a"), _c("#5c3c1e")]
	for x in range(T):
		var board := x / 4
		var base: Color = cols[(board * 3 + 1) % 4]
		for y in range(T):
			var c := base
			if x % 4 == 3:
				c = _c("#3a2410")  # joint entre planches
			elif rng.randf() < 0.12:
				c = base.darkened(0.18)  # veine
			_t(img, ox, oy, x, y, c)
	for p in [Vector2i(1, 2), Vector2i(1, 13), Vector2i(5, 2), Vector2i(5, 13), Vector2i(9, 2), Vector2i(9, 13), Vector2i(13, 2), Vector2i(13, 13)]:
		_t(img, ox, oy, p.x, p.y, _c("#b0a090"))  # clous
	_bevel(img, ox, oy, 0.08)


## Roche + décor lumineux : 0 = veine turquoise, 1 = veine violette, 2 = éclats de cristal.
static func _tile_rock_lit(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, kind: int) -> void:
	_rock_base(img, ox, oy, rng, false, kind % 2)
	if kind == 0:
		_vein(img, ox, oy, rng, _c("#6ff5e8"), _c("#2cc8c0"), _c("#126070"))
	elif kind == 1:
		_vein(img, ox, oy, rng, _c("#c093ff"), _c("#8f5cf0"), _c("#3a2278"))
	else:
		for k in range(4):
			var px := rng.randi_range(1, 13)
			var py := rng.randi_range(1, 13)
			_t(img, ox, oy, px, py, _c("#7ff8ea"))
			_t(img, ox, oy, px + 1, py, _c("#1f9fb0"))
			_t(img, ox, oy, px, py + 1, _c("#126070"))
	_bevel(img, ox, oy, 0.07)


static func _ore(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, main: Color, hi: Color, lo: Color, alt: Color) -> void:
	# filons cristallins : amas de facettes (clair en haut à gauche, sombre en bas à droite) + éclats vifs qui brillent
	var spots := [Vector2i(3, 3), Vector2i(10, 2), Vector2i(6, 9), Vector2i(12, 11), Vector2i(2, 12)]
	for i in range(spots.size()):
		var p: Vector2i = spots[i] + Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
		var col := main if (i % 2 == 0 or alt == main) else alt
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)]:
			_t(img, ox, oy, p.x + d.x, p.y + d.y, col)
		_t(img, ox, oy, p.x + 2, p.y + 1, lo)
		_t(img, ox, oy, p.x + 2, p.y + 2, lo)
		_t(img, ox, oy, p.x, p.y + 2, lo)
		_t(img, ox, oy, p.x, p.y, hi)
		_t(img, ox, oy, p.x + 1, p.y, hi.darkened(0.15))
		if rng.randf() < 0.6:
			_t(img, ox, oy, p.x - 1, p.y + 1, lo)
			_t(img, ox, oy, p.x + 3, p.y, col)


static func _tile_moss(img: Image, ox: int, oy: int, rng: RandomNumberGenerator) -> void:
	# la meme tuile sert aux dessus et aux flancs : plaques de mousse irregulieres (bruit periodique, sans couture)
	# sur la roche, bords sombres et ourles clairs, sans bande en haut de l'image
	_rock_base(img, ox, oy, rng)
	var g := [_c("#1f5f66"), _c("#2f9a94"), _c("#163f4a"), _c("#62e8d0"), _c("#c2fff2")]
	var tau := TAU / float(T)
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var cov := []
	for y in range(T):
		for x in range(T):
			var v := sin(x * tau * 2.0 + p1 + sin(y * tau * 1.0 + p2) * 1.5) + sin(y * tau * 2.0 + p2 + sin(x * tau * 3.0 + p1) * 1.2) + sin((x + y) * tau * 3.0 + p1) * 0.5
			v += rng.randf_range(-0.25, 0.25)
			cov.append(v)
	for y in range(T):
		for x in range(T):
			var v: float = cov[x + y * T]
			if v < 0.2:
				continue
			var k := 1
			if v < 0.5:
				k = 2  # lisiere sombre
			elif v > 1.5:
				k = 3 if (x * 3 + y * 5) % 4 == 0 else 1
			elif (x + y * 3) % 5 == 0:
				k = 0
			_t(img, ox, oy, x, y, g[k])
	# ourle clair sur le bord haut de chaque plaque
	for y in range(1, T):
		for x in range(T):
			if cov[x + (y - 1) * T] < 0.2 and cov[x + y * T] >= 0.5:
				_t(img, ox, oy, x, y, g[3])
	# spores lumineuses
	for i in range(4):
		_t(img, ox, oy, rng.randi_range(0, 15), rng.randi_range(0, 15), g[4])
	_bevel(img, ox, oy, 0.06)


static func _tile_dirt(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, variant := 0) -> void:
	var pal := [_c("#4b3b56"), _c("#40324b"), _c("#5a4866"), _c("#2e2338")]  # limon mauve sombre
	if variant == 1:
		pal = [_c("#463a58"), _c("#3a3050"), _c("#54476a"), _c("#2a2138")]
	_speckle(img, ox, oy, pal, rng, [5, 3, 2, 1])
	# petits cailloux
	for i in range(4 if variant == 0 else 2):
		var x := rng.randi_range(1, 13)
		var y := rng.randi_range(1, 13)
		_t(img, ox, oy, x, y, _c("#9aa4c8"))
		_t(img, ox, oy, x + 1, y, _c("#7882a8"))
		_t(img, ox, oy, x, y + 1, _c("#7882a8"))
		_t(img, ox, oy, x + 1, y + 1, _c("#2a2440"))
	if variant == 1:
		# racine sinueuse
		var x := rng.randi_range(3, 12)
		for y in range(T):
			_t(img, ox, oy, x, y, _c("#7f95c9"))
			_t(img, ox, oy, x + 1, y, _c("#2e3a66"))
			if rng.randf() < 0.35:
				x += rng.randi_range(-1, 1)
	for i in range(3):
		_t(img, ox, oy, rng.randi_range(0, 15), rng.randi_range(0, 15), _c("#7f95c9"))
	_bevel(img, ox, oy, 0.07)


static func _shard(img: Image, ox: int, oy: int, bx: int, by: int, h: int, w: int, p: Array) -> void:
	# prisme a facettes: face gauche claire, arete centrale blanche, face droite sombre, pointe
	for j in range(h):
		var ww := w
		var tip := h - j
		if tip <= w:
			ww = maxi(tip, 1)
		var x0 := bx - ww / 2
		for i in range(ww):
			var col: Color = p[0]
			var rel := float(i) / maxf(ww - 1, 1)
			if rel < 0.34:
				col = p[1]
			elif rel > 0.67:
				col = p[2]
			if i == ww / 2 and j % 3 != 1:
				col = p[3]
			_t(img, ox, oy, x0 + i, by - j, col)
		# contour sombre
		_t(img, ox, oy, x0 - 1, by - j, p[4])
		_t(img, ox, oy, x0 + ww, by - j, p[4])
	_t(img, ox, oy, bx, by - h, p[4])
	_t(img, ox, oy, bx - w / 2, by - h / 3, _c("#ffffff"))


## Éclat de cristal : trois petites aiguilles (bloc en croix, fond transparent).
static func _tile_shard(img: Image, ox: int, oy: int) -> void:
	var cy := [_c("#2fd9ee"), _c("#a8f8ff"), _c("#0b84a8"), _c("#f2ffff"), _c("#06303f")]
	var vi := [_c("#a463ff"), _c("#ddb3ff"), _c("#5426a8"), _c("#fbf0ff"), _c("#22103f")]
	_shard(img, ox, oy, 5, 15, 7, 3, cy)
	_shard(img, ox, oy, 10, 15, 10, 3, vi)
	_shard(img, ox, oy, 8, 15, 5, 2, cy)


static func _tile_crystal(img: Image, ox: int, oy: int, rng: RandomNumberGenerator) -> void:
	var pal := [_c("#1d1830"), _c("#171326"), _c("#272040"), _c("#120f1e")]
	_speckle(img, ox, oy, pal, rng, [5, 3, 2, 1])
	var cy := [_c("#2fd9ee"), _c("#a8f8ff"), _c("#0b84a8"), _c("#f2ffff"), _c("#06303f")]
	var vi := [_c("#a463ff"), _c("#ddb3ff"), _c("#5426a8"), _c("#fbf0ff"), _c("#22103f")]
	var pk := [_c("#ff5fc8"), _c("#ffb3e8"), _c("#a8207a"), _c("#fff0fa"), _c("#3f0a2c")]
	# (x centre, y base, hauteur, largeur, palette)
	var shards := [[3, 15, 9, 3, pk], [12, 15, 7, 3, vi], [8, 15, 13, 5, cy], [5, 7, 4, 2, cy], [13, 6, 4, 2, vi]]
	for s in shards:
		_shard(img, ox, oy, s[0], s[1], s[2], s[3], s[4])
	# etincelles en croix
	for p in [Vector2i(10, 3), Vector2i(2, 4)]:
		_t(img, ox, oy, p.x, p.y, _c("#ffffff"))
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			_t(img, ox, oy, p.x + d.x, p.y + d.y, _c("#9fe8ff"))
	_bevel(img, ox, oy, 0.05)


static func _tile_water(img: Image, ox: int, oy: int, rng: RandomNumberGenerator) -> void:
	# motif periodique sur 16 px: la tuile peut defiler dans le shader sans couture
	var pal := [_c("#2c6fd1"), _c("#3a82e0"), _c("#2559b0"), _c("#7cc0ff")]
	for y in range(T):
		for x in range(T):
			var w := sin((x + 2 * y) * TAU / 16.0) + sin((2 * x - y) * TAU / 16.0 + 1.0)
			var k := 0
			if w > 1.1:
				k = 1
			elif w < -1.1:
				k = 2
			img.set_pixel(ox + x, oy + y, pal[k])
	for y in [3, 8, 13]:
		var x0 := rng.randi_range(0, 15)
		for i in range(3):
			_t(img, ox, oy, x0 + i, y, pal[3] if i != 1 else _c("#c8ecff"))
	for i in range(4):
		_t(img, ox, oy, rng.randi_range(0, 15), rng.randi_range(0, 15), pal[2])


static func _tile_lava(img: Image, ox: int, oy: int, rng: RandomNumberGenerator) -> void:
	var pal := [_c("#7a1208"), _c("#c52a0c"), _c("#f06a10"), _c("#ffb52e"), _c("#fff08a")]
	for y in range(T):
		for x in range(T):
			var v := sin(x * TAU / 16.0 * 1.0 + sin(y * TAU / 16.0 * 2.0) * 1.3)
			v += sin(y * TAU / 16.0 + sin(x * TAU / 16.0 * 2.0) * 1.1)
			v += rng.randf_range(-0.25, 0.25)
			var k := clampi(int((v + 2.2) / 4.4 * 5.0), 0, 4)
			img.set_pixel(ox + x, oy + y, pal[k])
	# lisere sombre en croute
	for i in range(5):
		_t(img, ox, oy, rng.randi_range(0, 15), rng.randi_range(0, 15), _c("#4a0c06"))


static func _tile_bedrock(img: Image, ox: int, oy: int, rng: RandomNumberGenerator) -> void:
	_rock_base(img, ox, oy, rng, true)
	# plaques / rivets
	for i in range(T):
		_t(img, ox, oy, i, 0, _c("#0a0b1c"))
		_t(img, ox, oy, i, 15, _c("#0a0b1c"))
		_t(img, ox, oy, 0, i, _c("#0a0b1c"))
		_t(img, ox, oy, 15, i, _c("#0a0b1c"))
		_t(img, ox, oy, i, 1, _c("#2c3466"))
		_t(img, ox, oy, 1, i, _c("#2c3466"))
	for p in [Vector2i(3, 3), Vector2i(12, 3), Vector2i(3, 12), Vector2i(12, 12)]:
		_t(img, ox, oy, p.x, p.y, _c("#4a5a9a"))
		_t(img, ox, oy, p.x + 1, p.y + 1, _c("#0c0d20"))
	for i in range(3):
		_t(img, ox, oy, rng.randi_range(4, 11), rng.randi_range(4, 11), _c("#0c0d22"))


static func _tile_torch(img: Image, ox: int, oy: int) -> void:
	var wood := [_c("#8a5a2b"), _c("#6b4220"), _c("#a9763a")]
	for y in range(6, 16):
		_t(img, ox, oy, 7, y, wood[2])
		_t(img, ox, oy, 8, y, wood[1] if y % 3 != 0 else wood[0])
	# bande metal
	_t(img, ox, oy, 7, 7, _c("#9aa0aa"))
	_t(img, ox, oy, 8, 7, _c("#5d626c"))
	# flamme en goutte (7 de haut), le shader la fait onduler
	var fl := {
		0: ".......",
		1: "...o...",
		2: "..oyo..",
		3: "..oyo..",
		4: ".oyYyo.",
		5: ".oyYYo.",
		6: ".orYyro",
		7: "..rrr..",
	}
	var cols := {"o": _c("#ff7a1a"), "y": _c("#ffc034"), "Y": _c("#fff2a0"), "r": _c("#d93a10")}
	for j in fl.keys():
		var row: String = fl[j]
		for i in range(row.length()):
			if row[i] != ".":
				_t(img, ox, oy, 4 + i, j, cols[row[i]])
	for p in [Vector2i(4, 4), Vector2i(11, 3), Vector2i(10, 1)]:
		_t(img, ox, oy, p.x, p.y, Color(1.0, 0.7, 0.2, 0.6))


static func _tile_mushroom(img: Image, ox: int, oy: int) -> void:
	var rows := [
		"................",
		"................",
		"................",
		"......tttt......",
		"....ttWccctt....",
		"...tcWcccccct...",
		"..tcccccgccccd..",
		"..tcgccccccccd..",
		"..dddddddddddd..",
		"......sSs.......",
		"......sSs.......",
		".....gsSsg......",
		"....g.sSs..g....",
		"...gg.sSs.ggg...",
		"..ggggggggggggg.",
		"................",
	]
	var cols := {
		"t": _c("#0a8fa0"), "c": _c("#2fe0e0"), "W": _c("#d6ffff"), "g": _c("#9bffb0"),
		"d": _c("#0b6e86"), "s": _c("#7ec9b8"), "S": _c("#c8fff0"),
	}
	# les 'g' du bas sont de l'herbe lumineuse sombre
	for y in range(T):
		for x in range(T):
			var ch: String = rows[y][x]
			if ch == ".":
				continue
			var col: Color = cols[ch]
			if y >= 11 and ch == "g":
				col = _c("#2c8a4f") if (x + y) % 2 == 0 else _c("#46b86a")
			_t(img, ox, oy, x, y, col)
	for p in [Vector2i(7, 4), Vector2i(11, 6)]:
		_t(img, ox, oy, p.x, p.y, _c("#ffffff"))


static func _tile_stalagmite(img: Image, ox: int, oy: int) -> void:
	# cone de roche, pointe en haut (retourne par l'UV pour les stalactites)
	var pal := [_c("#4d5a8c"), _c("#3a4575"), _c("#2c3558"), _c("#1d2340"), _c("#8fa0e0")]
	for y in range(2, T):
		var hw := int((y - 1) * 0.42) + 1
		for x in range(8 - hw, 8 + hw):
			var rel := float(x - (8 - hw)) / maxf(2 * hw - 1, 1)
			var col: Color = pal[1]
			if rel < 0.3:
				col = pal[0]
			elif rel > 0.7:
				col = pal[2]
			if (y * 5 + x * 3) % 11 == 0:
				col = pal[3]
			_t(img, ox, oy, x, y, col)
		_t(img, ox, oy, 8 - hw - 1, y, pal[3])
		_t(img, ox, oy, 8 + hw, y, pal[3])
	for y in range(3, 12, 3):
		_t(img, ox, oy, 7, y, pal[4])
	# goutte claire a la pointe
	_t(img, ox, oy, 7, 1, _c("#9fd6ff"))


static func _tile_glowplant(img: Image, ox: int, oy: int) -> void:
	var stem := _c("#1f7a5a")
	var leaf := [_c("#2fbf7f"), _c("#5ff0a8"), _c("#167050")]
	var bulb := [_c("#7dfff0"), _c("#e0fffa"), _c("#2fc8c8")]
	var stems := [[4, 6], [8, 3], [12, 7]]
	for s in stems:
		var x: int = s[0]
		for y in range(s[1], T):
			_t(img, ox, oy, x + (1 if (y + x) % 5 == 0 else 0), y, stem)
		# feuilles
		for y in range(s[1] + 3, T - 1, 3):
			_t(img, ox, oy, x - 1, y, leaf[0])
			_t(img, ox, oy, x - 2, y - 1, leaf[1])
			_t(img, ox, oy, x + 1, y + 1, leaf[2])
			_t(img, ox, oy, x + 2, y, leaf[0])
		# bulbe lumineux
		var by: int = s[1]
		_t(img, ox, oy, x, by - 1, bulb[0])
		_t(img, ox, oy, x - 1, by, bulb[2])
		_t(img, ox, oy, x + 1, by, bulb[0])
		_t(img, ox, oy, x, by, bulb[1])
		_t(img, ox, oy, x, by - 2, bulb[2])
	for x in range(1, 15):
		if x % 3 != 0:
			_t(img, ox, oy, x, 15, leaf[2] if x % 2 == 0 else leaf[0])


## Wooden chest with iron bands and a gold lock (tile 16).
static func _tile_chest(img: Image, ox: int, oy: int) -> void:
	var wood := [_c("#8a5a2b"), _c("#a9763a"), _c("#6b4220"), _c("#4f3017")]
	for y in range(T):
		for x in range(T):
			var c: Color = wood[0] if (y % 4) != 3 else wood[2]
			if (x * 7 + y * 3) % 11 == 0:
				c = wood[1]
			_t(img, ox, oy, x, y, c)
	for x in range(T):
		_t(img, ox, oy, x, 0, wood[3]); _t(img, ox, oy, x, 15, wood[3])
		_t(img, ox, oy, x, 6, _c("#5d626c")); _t(img, ox, oy, x, 7, _c("#9aa0aa"))
	for y in range(T):
		_t(img, ox, oy, 0, y, wood[3]); _t(img, ox, oy, 15, y, wood[3])
		for x in [1, 14]:
			_t(img, ox, oy, x, y, _c("#9aa0aa") if y % 5 != 0 else _c("#d8dde6"))
	_rect(img, ox + 6, oy + 5, ox + 9, oy + 9, _c("#c8941a"))
	_rect(img, ox + 7, oy + 6, ox + 8, oy + 7, _c("#ffd02a"))
	_px(img, ox + 7, oy + 8, _c("#1a1410")); _px(img, ox + 8, oy + 8, _c("#1a1410"))


## Bloc de métal : plaques rivetées (pal = 4 teintes, seam = joints).
static func _tile_metal(img: Image, ox: int, oy: int, pal: Array, seam: Color, seed_v: int) -> void:
	# lingots empilés : 4 rangées de barres biseautées (clair en haut, sombre en bas), décalées une rangée sur deux
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for y in range(T):
		for x in range(T):
			_t(img, ox, oy, x, y, seam)
	for row in range(4):
		var y0 := row * 4
		var shift := 0 if row % 2 == 0 else 4
		for k in range(-1, 3):
			var x0 := k * 8 + shift
			var base: Color = pal[(row + k + 1) % pal.size()]
			for yy in range(1, 4):
				for xx in range(1, 7):
					var col := base
					if yy == 1:
						col = pal[2].lightened(0.35)  # arête haute brillante
					elif yy == 3:
						col = base.darkened(0.3)
					elif xx == 1:
						col = base.lightened(0.15)
					elif xx == 6:
						col = base.darkened(0.15)
					elif rng.randf() < 0.1:
						col = base.lightened(0.1)
					_t(img, ox, oy, x0 + xx, y0 + yy, col)
	_bevel(img, ox, oy, 0.12)


## Fonderie : pierre sombre, bouche de four avec braises.
static func _tile_forge(img: Image, ox: int, oy: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	_rock_base(img, ox, oy, rng, true)
	for y in range(3, 5):
		for x in range(2, 14):
			_t(img, ox, oy, x, y, _c("#55555f"))  # linteau
	for y in range(5, 14):
		for x in range(3, 13):
			var arch := y == 5 and (x == 3 or x == 12)
			if not arch:
				_t(img, ox, oy, x, y, _c("#150f0b"))  # bouche sombre
	for x in range(4, 12):
		for y in range(9, 13):
			var k := float(12 - y) / 3.0
			_t(img, ox, oy, x, y, _c("#d8431a").lerp(_c("#ffb030"), k))  # braises
	for p in [Vector2i(6, 8), Vector2i(8, 7), Vector2i(9, 9), Vector2i(5, 10), Vector2i(10, 11)]:
		_t(img, ox, oy, p.x, p.y, _c("#ffe27a"))  # flammèches
	_bevel(img, ox, oy, 0.1)


static func build_atlas() -> ImageTexture:
	var img := Image.create(64, 16 * World.AROWS, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	_tile_chest(img, 0, 64)
	for i in range(16):
		var ox := (i % 4) * T
		var oy := (i / 4) * T
		match i:
			0: _tile_moss(img, ox, oy, rng)
			1: _tile_dirt(img, ox, oy, rng)
			2:
				_rock_base(img, ox, oy, rng)
				_bevel(img, ox, oy, 0.07)
			3:
				_rock_base(img, ox, oy, rng)
				_ore(img, ox, oy, rng, _c("#15162a"), _c("#b8c4ff"), _c("#07070f"), _c("#232547"))
				_bevel(img, ox, oy, 0.07)
			4:
				_rock_base(img, ox, oy, rng)
				_ore(img, ox, oy, rng, _c("#9fb0e8"), _c("#f4f8ff"), _c("#4c5a99"), _c("#c9d4ff"))
				_bevel(img, ox, oy, 0.07)
			5:
				_rock_base(img, ox, oy, rng)
				_ore(img, ox, oy, rng, _c("#e0813a"), _c("#ffd49a"), _c("#8f4318"), _c("#3fe0c0"))
				_bevel(img, ox, oy, 0.07)
			6: _tile_crystal(img, ox, oy, rng)
			7: _tile_water(img, ox, oy, rng)
			8: _tile_lava(img, ox, oy, rng)
			9: _tile_bedrock(img, ox, oy, rng)
			10: _tile_torch(img, ox, oy)
			11: _tile_mushroom(img, ox, oy)
			12:
				_rock_base(img, ox, oy, rng, false, 1)
				_bevel(img, ox, oy, 0.07)
			13: _tile_dirt(img, ox, oy, rng, 1)
			14: _tile_stalagmite(img, ox, oy)
			15: _tile_glowplant(img, ox, oy)
	_tile_shard(img, (25 % 4) * T, (25 / 4) * T)
	_tile_warm(img, (26 % 4) * T, (26 / 4) * T, rng, false)
	_tile_amber(img, (27 % 4) * T, (27 / 4) * T, rng)
	_tile_wood(img, (28 % 4) * T, (28 / 4) * T, rng)
	_tile_warm(img, (29 % 4) * T, (29 / 4) * T, rng, true)
	for k in 3:  # variantes lumineuses de la roche (tuiles 22-24)
		_tile_rock_lit(img, ((22 + k) % 4) * T, ((22 + k) / 4) * T, rng, k)
	_tile_forge(img, (19 % 4) * T, (19 / 4) * T)
	_tile_metal(img, (20 % 4) * T, (20 / 4) * T, [_c("#8d939d"), _c("#7d838e"), _c("#9aa0aa"), _c("#6f7580")], _c("#4a4f58"), 2020)
	_tile_metal(img, (21 % 4) * T, (21 / 4) * T, [_c("#c8763c"), _c("#b5662f"), _c("#d98a4a"), _c("#9c5226")], _c("#6a3414"), 2121)
	SpawnHub.draw_tiles(img, rng)  # --- SPAWN HUB --- tuiles 16+ (pierre taillée, panneaux)
	return ImageTexture.create_from_image(img)


static var _pick_cache := {}

## Pioche : la tête change avec le niveau « tranchante » (acier, bleu, cyan, cristal lumineux) ; recul = pommeau orange au bout du manche ;
## épines = deux pointes rouges sur la tête. Mis en cache par combinaison.
static func pickaxe_icon(sharp := 0, kb := 0, thorns := 0) -> ImageTexture:
	var key := sharp * 100 + kb * 10 + thorns
	if _pick_cache.has(key):
		return _pick_cache[key]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	var outline := _c("#1a1410")
	var heads := [[_c("#c8d0da"), _c("#8a94a2")], [_c("#b8d0f0"), _c("#6f8fc0")], [_c("#80e8ff"), _c("#30a8d0")], [_c("#c8fff8"), _c("#2fd9ee")]]
	var hc: Array = heads[clampi(sharp, 0, 3)]
	# manche
	_line(img, Vector2i(3, 13), Vector2i(11, 5), _c("#8a5a2b"))
	_line(img, Vector2i(4, 13), Vector2i(12, 5), _c("#6b4220"))
	if kb > 0:  # pommeau de recul
		_px(img, 2, 14, _c("#ff9a3c") if kb == 1 else _c("#ffd27a"))
		_px(img, 3, 14, _c("#ff9a3c"))
		_px(img, 2, 13, _c("#c8601c"))
	# tete (arc)
	var head := [Vector2i(6, 3), Vector2i(8, 2), Vector2i(10, 2), Vector2i(12, 3), Vector2i(13, 5), Vector2i(13, 7)]
	for i in range(head.size() - 1):
		_line(img, head[i], head[i + 1], hc[0])
		_line(img, head[i] + Vector2i(0, 1), head[i + 1] + Vector2i(0, 1), hc[1])
	_px(img, 8, 2, _c("#ffffff"))
	_px(img, 10, 2, _c("#eef2f6"))
	if sharp >= 3:  # étincelle de cristal
		_px(img, 14, 2, _c("#ffffff"))
		_px(img, 14, 1, _c("#9fe8ff"))
		_px(img, 15, 2, _c("#9fe8ff"))
	if thorns > 0:  # épines
		_px(img, 6, 2, _c("#ff4a3a"))
		_px(img, 13, 8, _c("#ff4a3a"))
	_outline(img, outline)
	var tex := ImageTexture.create_from_image(img)
	_pick_cache[key] = tex
	return tex


static var _sword_cache := {}

## Épée (objet d'équipement) : lame en diagonale dont la couleur suit le palier (1 cuivre, 2 fer, 3 cristal), garde et poignée brunes.
static func sword_icon(level := 1) -> ImageTexture:
	var lv := clampi(level, 1, 3)
	if _sword_cache.has(lv):
		return _sword_cache[lv]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	var blades := [[_c("#e0925a"), _c("#a8582c")], [_c("#dfe6ee"), _c("#8a94a2")], [_c("#b8fbff"), _c("#2fd0e8")]]
	var bc: Array = blades[lv - 1]
	_line(img, Vector2i(5, 10), Vector2i(13, 2), bc[0])  # lame
	_line(img, Vector2i(6, 10), Vector2i(13, 3), bc[1])
	_px(img, 13, 2, _c("#ffffff"))
	_line(img, Vector2i(4, 8), Vector2i(8, 12), _c("#6b4220"))  # garde
	_line(img, Vector2i(5, 8), Vector2i(8, 11), _c("#8a5a2b"))
	_line(img, Vector2i(3, 13), Vector2i(6, 10), _c("#8a5a2b"))  # poignée
	_px(img, 2, 14, _c("#c8a040"))  # pommeau
	_outline(img, _c("#1a1410"))
	var tex := ImageTexture.create_from_image(img)
	_sword_cache[lv] = tex
	return tex

## Pomme dorée (objet d'équipement, pas un bloc) : pomme ronde dorée, queue brune, feuille verte.
static func apple_icon() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	for y in range(16):
		for x in range(16):
			var dx := (x - 7.5) / 5.6
			var dy := (y - 9.0) / 5.4
			if dx * dx + dy * dy <= 1.0:
				var c := _c("#f2b82e")
				if dx + dy > 0.5:
					c = _c("#c98d17")  # ombre bas-droite
				elif dx + dy < -0.55:
					c = _c("#ffe27a")  # reflet haut-gauche
				_px(img, x, y, c)
	_px(img, 5, 7, _c("#ffffff"))
	_px(img, 6, 7, _c("#fff4b8"))
	_px(img, 5, 8, _c("#fff4b8"))
	_line(img, Vector2i(8, 4), Vector2i(8, 2), _c("#6b4220"))  # queue
	_px(img, 9, 3, _c("#4fbf4a"))  # feuille
	_px(img, 10, 3, _c("#3a9a3a"))
	_px(img, 10, 2, _c("#4fbf4a"))
	_outline(img, _c("#3a2410"))
	return ImageTexture.create_from_image(img)


static func _outline(img: Image, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var add: Array[Vector2i] = []
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and img.get_pixel(nx, ny).a > 0.5:
					add.append(Vector2i(x, y))
					break
	for p in add:
		img.set_pixel(p.x, p.y, col)


# ---------------------------------------------------------------- joueur (voir char_art.gd)

static func pixel_size(lk: Dictionary, hh: float) -> float:
	return CharArt.pixel_size(lk, hh)


## lk : apparence (DMSettings.look) ; les mineurs IA passent juste {"helmet", "shirt"} en Color.
static func build_player_frames(lk: Dictionary = {}, tool_id: String = "pick") -> SpriteFrames:
	return CharArt.build(lk, tool_id)
