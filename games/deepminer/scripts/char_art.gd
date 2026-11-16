class_name CharArt extends RefCounted
## Personnages 2D en pixel-art : parties ASCII + squelette + animations par images cles d'angles.
## Chaque frame est rasterisee au lancement (rotation plus proche voisin, angles arrondis a 15 deg,
## aucun flou), puis un contour sombre est ajoute. Pieds sur la derniere ligne, fond alpha 0.
##
## Lettres de palette : H casque, h casque sombre, L lampe, S peau, s peau sombre, E oeil, W os/corne,
## M bouche, R cheveux, D barbe, T haut, t haut sombre, P bas, p bas sombre, K ceinture, Y boucle,
## B bottes, G manche d'outil, N metal, n metal sombre, C/c voyants du robot, F/f flamme, '.' vide.

const OUTLINE := Color(0.102, 0.078, 0.063)
const SNAP := 15.0

# ---------------------------------------------------------------- parties (profil p, face f, dos b)
# Tete 8x10 (ligne 0 libre : cornes / antenne), pivot = menton au centre.
const HEAD := {
	"p": ["........", "..HHHH..", ".HHHHHH.", "HHHHHHHL", "hhhhhhhL", ".SSSSSS.", ".SSSSES.", ".SSSSSSs", ".sSSSMS.", "..sSSs.."],
	"f": ["........", "..HHHH..", ".HHHHHH.", "HHHLLHHH", "hhhhhhhh", ".SSSSSS.", ".SESSES.", ".SSSSSS.", ".SSMMSS.", "..ssss.."],
	"b": ["........", "..HHHH..", ".HHHHHH.", "HHHHHHHH", "hhhhhhhh", ".SSSSSS.", ".SSSSSS.", ".SSSSSS.", ".SSSSSS.", "..ssss.."],
}
const HAIR1 := {"p": [[5, 1], [6, 1]], "f": [[5, 1], [5, 2], [5, 5], [5, 6]], "b": [[5, 1], [5, 2], [5, 3], [5, 4], [5, 5], [5, 6], [6, 1], [6, 2], [6, 3], [6, 4], [6, 5], [6, 6]]}
const HAIR2 := {"p": [[7, 1], [8, 1], [5, 2], [6, 0]], "f": [[5, 3], [5, 4], [6, 1], [6, 6], [7, 1], [7, 6], [8, 1], [8, 6]], "b": [[7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [7, 6], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5], [8, 6]]}
const BEARD1 := {"p": [[9, 3], [9, 4], [9, 5]], "f": [[9, 2], [9, 3], [9, 4], [9, 5]], "b": []}
const BEARD2 := {"p": [[8, 3], [8, 4], [8, 6], [9, 2], [9, 3], [9, 4], [9, 5], [7, 3], [7, 4]], "f": [[8, 1], [8, 2], [8, 5], [8, 6], [7, 1], [7, 6], [7, 2], [7, 5]], "b": []}

# Torse 6x8, pivot = hanches (3, 7).
const TORSO := {
	"p": [".TTTT.", "TTTTTt", "TTTTTt", "PPPPPp", "PPPPPp", "PPPPPp", "KKKKKK", "PPPPPp"],
	"f": ["TTTTTT", "TPTTPT", "TPTTPT", "PPPPPP", "PPPPPp", "PPPPPp", "KKYYKK", "PPPPPp"],
	"b": ["TTTTTT", "TTTTTt", "TPTTPt", "PPPPPP", "PPPPPp", "PPPPPp", "KKKKKK", "PPPPPp"],
}
const ARM := ["TT", "TT", "Tt", "Tt", "SS", "Ss"]  # pivot (1, 1)
const LEG := {
	"p": ["PPp.", "PPp.", "PPp.", "PPp.", "PPp.", "PPp.", "BBBB", "BBBB"],
	"f": ["PPp", "PPp", "PPp", "PPp", "PPp", "PPp", "BBB", "BBB"],
}  # pivot (1.5, 1)
# Outils tenus : ttournes vers +y (le long du bras), pivot = la main.
const TOOLS := {
	"pick": {"g": ["....G....", "....G....", "....G....", "....G....", "....G....", "....G....", "....G....", "N...G...N", ".NNNGNNN.", "....n...."], "pv": Vector2(4.5, 2.0)},
	"sword": {"g": ["....G....", "....G....", ".nNNGNNn.", "....N....", "....N....", "....N....", "....N....", "....N....", "....N....", "....n...."], "pv": Vector2(4.5, 1.5)},
	"torch": {"g": ["..G..", "..G..", "..G..", "..G..", "..G..", "..G..", ".FfF.", ".FfF.", "..F..", "..f.."], "pv": Vector2(2.5, 2.0)},
}
const HEAD_PV := Vector2(4, 10)
const TORSO_PV := Vector2(3, 7)
const ARM_PV := Vector2(1, 1)
const NECK := Vector2(0, -6.2)  # relatif aux hanches, avant echelle
const SHOULDER_Y := -5.5
const ARM_HAND := 4.0  # distance epaule -> main (cellules)

## Proportions par espece (indice = DMSettings.look.body) : tete, torse, bras, jambes (echelle x, y).
const SPECIES := [
	{"kind": "human", "hs": Vector2(1, 1), "ts": Vector2(1, 1), "as": Vector2(1, 1), "ls": Vector2(1, 1)},
	{"kind": "dwarf", "hs": Vector2(1, 1), "ts": Vector2(1.34, 0.65), "as": Vector2(1, 0.7), "ls": Vector2(1.34, 0.45)},
	{"kind": "giant", "hs": Vector2(1.25, 1.25), "ts": Vector2(1.67, 1.5), "as": Vector2(1.5, 1.5), "ls": Vector2(1.5, 1.35)},
	{"kind": "goblin", "hs": Vector2(1.12, 1.12), "ts": Vector2(0.84, 0.75), "as": Vector2(0.85, 0.85), "ls": Vector2(0.9, 0.6)},
	{"kind": "robot", "hs": Vector2(1, 1), "ts": Vector2(1.17, 1), "as": Vector2(1, 1), "ls": Vector2(1, 1)},
]

# ---------------------------------------------------------------- animations (images cles)
const PDEF := {"lean": 0.0, "hd": 0.0, "aF": 10.0, "aB": -8.0, "wr": 120.0, "lF": 0.0, "lB": 0.0, "tdy": 0.0, "lsq": 1.0, "tool": 1.0}
const FDEF := {"hd": 0.0, "aL": 6.0, "aR": 8.0, "wr": 172.0, "lL": 0.0, "lR": 0.0, "tdy": 0.0, "lsq": 1.0, "tool": 1.0}

const PROFILE := {
	"idle": {"fps": 3.0, "loop": true, "n": 2, "keys": [{}, {"tdy": -1, "aF": 16, "aB": -12, "hd": -4}]},
	"walk": {"fps": 9.0, "loop": true, "n": 6, "keys": [
		{"lF": 30, "lB": -30, "aF": -30, "aB": 30, "lean": 5}, {"lF": -10, "lB": 15, "aF": 0, "aB": 0, "lean": 5},
		{"lF": -30, "lB": 30, "aF": 30, "aB": -30, "lean": 5}, {"lF": 15, "lB": -10, "aF": 0, "aB": 0, "lean": 5}]},
	"run": {"fps": 12.0, "loop": true, "n": 6, "keys": [
		{"lF": 50, "lB": -45, "aF": -55, "aB": 55, "lean": 16, "wr": 90}, {"lF": -25, "lB": 35, "aF": 0, "aB": 10, "lean": 16, "wr": 90},
		{"lF": -45, "lB": 50, "aF": 55, "aB": -55, "lean": 16, "wr": 90}, {"lF": 35, "lB": -25, "aF": 10, "aB": 0, "lean": 16, "wr": 90}]},
	"mine": {"fps": 10.0, "loop": true, "n": 4, "keys": [
		{"aF": 165, "aB": 25, "wr": 0, "lean": -8, "lF": 18, "lB": -18, "hd": -5}, {"aF": 105, "aB": 15, "wr": 10, "lean": 6, "lF": 18, "lB": -18, "hd": 3},
		{"aF": 35, "aB": -10, "wr": 30, "lean": 20, "lF": 25, "lB": -18, "hd": 10}, {"aF": 80, "aB": 10, "wr": 15, "lean": 8, "lF": 20, "lB": -15}]},
	"jump": {"fps": 5.0, "loop": false, "n": 1, "keys": [{"aF": 150, "aB": 125, "wr": 20, "lean": -3, "lF": 40, "lB": -15}]},
	"fall": {"fps": 5.0, "loop": true, "n": 1, "keys": [{"aF": 70, "aB": 55, "wr": 60, "lean": -6, "lF": 12, "lB": -18}]},
	"crouch": {"fps": 3.0, "loop": true, "n": 2, "keys": [
		{"lean": 22, "lsq": 0.55, "lF": 25, "lB": -12, "aF": 30, "aB": 15, "hd": -8}, {"lean": 24, "lsq": 0.55, "lF": 25, "lB": -12, "aF": 34, "aB": 18, "hd": -10, "tdy": -1}]},
	"swim": {"fps": 5.0, "loop": true, "n": 4, "keys": [
		{"lean": 72, "aF": 150, "aB": 60, "lF": -60, "lB": -80, "hd": -50, "tool": 0}, {"lean": 72, "aF": 100, "aB": 100, "lF": -75, "lB": -65, "hd": -50, "tool": 0},
		{"lean": 72, "aF": 60, "aB": 150, "lF": -80, "lB": -60, "hd": -50, "tool": 0}, {"lean": 72, "aF": 100, "aB": 100, "lF": -65, "lB": -75, "hd": -50, "tool": 0}]},
	"hurt": {"fps": 8.0, "loop": false, "n": 2, "keys": [
		{"lean": -18, "hd": -12, "aF": 60, "aB": 75, "wr": 20, "lF": 12, "lB": -22, "tdy": -1}, {"lean": -24, "hd": -16, "aF": 75, "aB": 85, "wr": 20, "lF": 5, "lB": -28}]},
	"wave": {"fps": 6.0, "loop": true, "n": 4, "keys": [
		{"aF": 135, "tool": 0, "aB": -4}, {"aF": 170, "tool": 0, "aB": -4}, {"aF": 135, "tool": 0, "aB": -4}, {"aF": 170, "tool": 0, "aB": -4, "hd": -3}]},
}
# Face / dos (memes cles pour les deux) : suffixes _front et _back.
const FRONTAL := {
	"idle": {"fps": 3.0, "loop": true, "n": 2, "keys": [{}, {"tdy": -1, "aL": 9, "aR": 11, "hd": 0}]},
	"walk": {"fps": 8.0, "loop": true, "n": 4, "keys": [{"lL": 2, "lR": 0, "aL": 12, "aR": 4}, {"tdy": -1}, {"lL": 0, "lR": 2, "aL": 4, "aR": 12}, {"tdy": -1}]},
	"crouch": {"fps": 3.0, "loop": true, "n": 2, "keys": [{"lsq": 0.55, "aL": 20, "aR": 22}, {"lsq": 0.55, "aL": 22, "aR": 24, "tdy": -1}]},
	"wave": {"fps": 6.0, "loop": true, "n": 4, "keys": [
		{"aR": 150, "tool": 0, "aL": 8}, {"aR": 175, "tool": 0, "aL": 8}, {"aR": 150, "tool": 0, "aL": 8}, {"aR": 175, "tool": 0, "aL": 8}]},
}

static var _cache := {}


static func spec(look: Dictionary) -> Dictionary:
	return SPECIES[clampi(int(look.get("body", 0)), 0, SPECIES.size() - 1)]


static func _col(v: Variant, def: String) -> Color:
	if v is Color:
		return v
	if v is String and v != "":
		return Color.html(v)
	return Color.html(def)


## Palette lettre -> couleur depuis DMSettings.look (ou les couleurs IA).
static func palette(look: Dictionary) -> Dictionary:
	var kind: String = spec(look).kind
	var hel := _col(look.get("helmet"), "#ffd02a")
	var skin := _col(look.get("skin"), "#f0b98a")
	if kind == "robot":
		skin = hel.lerp(Color.html("#b8c0cc"), 0.65)
	var shirt := _col(look.get("shirt"), "#c8452f")
	var over := _col(look.get("overalls"), "#3d5fa8")
	var hair := _col(look.get("hair_color"), "#3a2414")
	var eye := Color.html("#1a1410")
	if kind == "robot":
		eye = Color.html("#5ce0ff")
	elif kind == "goblin":
		eye = Color.html("#ffe14a")
	return {
		"H": hel, "h": hel.darkened(0.25), "L": Color.html("#fff6a0"),
		"S": skin, "s": skin.darkened(0.18), "E": eye, "W": Color.html("#ece4cc"), "M": skin.darkened(0.35),
		"R": hair, "D": hair, "T": shirt, "t": shirt.darkened(0.25), "P": over, "p": over.darkened(0.22),
		"K": Color.html("#5a3a1c"), "Y": Color.html("#ffd02a"), "B": _col(look.get("boots"), "#6b4220"),
		"G": Color.html("#8a5a2b"), "N": Color.html("#c8d0da"), "n": Color.html("#8a94a2"),
		"C": Color.html("#5ce0ff"), "c": Color.html("#ff6b4a"), "F": Color.html("#ff9a2a"), "f": Color.html("#ffe14a"),
	}


static func _dark(pal: Dictionary) -> Dictionary:
	var d := {}
	for k in pal:
		d[k] = (pal[k] as Color).darkened(0.28)
	return d


static func _put(g: Array, cells: Array, ch: String) -> void:
	for c in cells:
		var row: String = g[c[0]]
		g[c[0]] = row.substr(0, c[1]) + ch + row.substr(c[1] + 1)


## Tete personnalisee (cheveux, barbe, signes d'espece) pour la vue v.
static func head_grid(look: Dictionary, v: String) -> Array:
	var g: Array = (HEAD[v] as Array).duplicate()
	var kind: String = spec(look).kind
	var hair := int(look.get("hair", 0))
	var beard := int(look.get("beard", 0))
	if kind == "robot":
		hair = 0
		beard = 0
		_put(g, [[0, 3]], "L")
	if kind == "dwarf":
		beard = 2
		_put(g, [[1, 1], [0, 0], [1, 6], [0, 7]], "W")
	if kind == "goblin":
		hair = 0
		_put(g, [[6, 0], [5, 0], [6, 7], [5, 7]] if v == "f" else ([[6, 0], [5, 0]] if v == "p" else [[6, 0], [6, 7]]), "S")
	if hair >= 1:
		_put(g, HAIR1[v], "R")
	if hair >= 2:
		_put(g, HAIR2[v], "R")
	if beard >= 1:
		_put(g, BEARD1[v], "D")
	if beard >= 2:
		_put(g, BEARD2[v], "D")
	return g


static func torso_grid(look: Dictionary, v: String) -> Array:
	var g: Array = (TORSO[v] as Array).duplicate()
	if spec(look).kind == "robot":
		if v == "f":
			_put(g, [[1, 2]], "C")
			_put(g, [[1, 3]], "c")
		elif v == "p":
			_put(g, [[1, 4]], "C")
	return g


# ---------------------------------------------------------------- rasterisation
static func _snap(a: float) -> float:
	return roundf(a / SNAP) * SNAP


static func _rot(v: Vector2, a_deg: float) -> Vector2:
	var a := deg_to_rad(a_deg)
	var s := sin(a)
	var c := cos(a)
	return Vector2(v.x * c + v.y * s, -v.x * s + v.y * c)


## Pose une partie : pivot (cellules) place en dest (pixels), rotation a_deg (avant positif), echelle sc.
static func _blit(img: Image, rows: Array, pv: Vector2, dest: Vector2, a_deg: float, sc: Vector2, pal: Dictionary) -> void:
	var a := _snap(a_deg)
	var w: int = (rows[0] as String).length()
	var h: int = rows.size()
	var r := ceili(maxf(w, h) * maxf(sc.x, sc.y) * 1.5) + 2
	var d := Vector2(roundf(dest.x), roundf(dest.y))
	var ar := deg_to_rad(a)
	var s := sin(ar)
	var c := cos(ar)
	for y in range(int(d.y) - r, int(d.y) + r + 1):
		if y < 0 or y >= img.get_height():
			continue
		for x in range(int(d.x) - r, int(d.x) + r + 1):
			if x < 0 or x >= img.get_width():
				continue
			var p := Vector2(x + 0.5 - d.x, y + 0.5 - d.y)
			var src := Vector2(p.x * c - p.y * s, p.x * s + p.y * c)  # rotation inverse
			var cx := floori(pv.x + src.x / sc.x + 0.0001)
			var cy := floori(pv.y + src.y / sc.y + 0.0001)
			if cx < 0 or cy < 0 or cx >= w or cy >= h:
				continue
			var ch: String = (rows[cy] as String)[cx]
			if ch != "." and pal.has(ch):
				img.set_pixel(x, y, pal[ch])


static func _outline(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var add: Array[Vector2i] = []
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.5:
				continue
			for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + dd.x
				var ny: int = y + dd.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and img.get_pixel(nx, ny).a > 0.5:
					add.append(Vector2i(x, y))
					break
	for p in add:
		img.set_pixel(p.x, p.y, OUTLINE)


## Dimensions du canevas et hauteur du corps (pixels) pour une espece.
static func layout(look: Dictionary) -> Dictionary:
	var sp := spec(look)
	var ls: Vector2 = sp.ls
	var ts: Vector2 = sp.ts
	var hs: Vector2 = sp.hs
	var as_: Vector2 = sp["as"]
	var leg := 7.0 * ls.y
	var body := leg + 6.2 * ts.y + 9.0 * hs.y
	var half := maxi(12, ceili(15.0 * maxf(as_.x, as_.y)) + 4)
	var top := 4 + maxi(0, ceili(15.0 * as_.y - 9.0 * hs.y - 1.0 * ts.y * 2.0))
	return {"w": half * 2, "h": ceili(body) + top + 3, "body": body, "leg": leg}


static func _lerp_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var o := {}
	for k in a:
		o[k] = lerpf(float(a[k]), float(b[k]), t)
	return o


## Echantillonne les images cles (boucle) a l'instant i/n.
static func pose_at(keys: Array, defaults: Dictionary, i: int, n: int, loop: bool) -> Dictionary:
	var full: Array = []
	for k in keys:
		var d := defaults.duplicate()
		d.merge(k, true)
		full.append(d)
	var m := full.size()
	var u := float(i) * float(m if loop else maxi(m - 1, 1)) / float(n if loop else maxi(n - 1, 1))
	var i0 := int(floor(u)) % m
	var i1 := (i0 + 1) % m if loop else mini(i0 + 1, m - 1)
	return _lerp_pose(full[i0], full[i1], u - floor(u))


static func render(look: Dictionary, pose: Dictionary, view: String, tool_id: String) -> Image:
	var sp := spec(look)
	var L := layout(look)
	var W: int = L.w
	var H: int = L.h
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pal := palette(look)
	var dk := _dark(pal)
	var ts: Vector2 = sp.ts
	var hs: Vector2 = sp.hs
	var as_: Vector2 = sp["as"]
	var ls: Vector2 = sp.ls
	var lsq: float = float(pose.lsq)
	var lsc := Vector2(ls.x, ls.y * lsq)
	var leg_len := 6.0 * lsc.y
	var tool_g: Dictionary = TOOLS.get(tool_id, TOOLS.pick)
	var tsc := Vector2(maxf(as_.x, as_.y), maxf(as_.x, as_.y))
	var cx := W / 2.0
	var tdy := float(pose.tdy)
	var show_tool: bool = float(pose.tool) > 0.5
	var head: Array = head_grid(look, view)
	var torso: Array = torso_grid(look, view)
	var neck_v := Vector2(NECK.x * ts.x, NECK.y * ts.y)
	var sh_y := SHOULDER_Y * ts.y
	var arm_hand := ARM_HAND * as_.y
	if view == "p":
		var lean := float(pose.lean)
		var at := -lean
		var hip := Vector2(cx, 0)
		var reach := leg_len * maxf(cos(deg_to_rad(float(pose.lF))), cos(deg_to_rad(float(pose.lB))))
		hip.y = H - 3.0 - reach
		var neck := hip + _rot(neck_v, at) + Vector2(0, tdy)
		var sh := hip + _rot(Vector2(0, sh_y), at) + Vector2(0, tdy)
		var aF := float(pose.aF)
		var hand := sh + _rot(Vector2(0, arm_hand), aF)
		_blit(img, ARM, ARM_PV, sh, float(pose.aB), as_, dk)
		_blit(img, LEG.p, Vector2(1.5, 1), hip, float(pose.lB), lsc, dk)
		_blit(img, LEG.p, Vector2(1.5, 1), hip, float(pose.lF), lsc, pal)
		_blit(img, torso, TORSO_PV, hip + Vector2(0, tdy), at, ts, pal)
		_blit(img, head, HEAD_PV, neck, at - float(pose.hd), hs, pal)
		if show_tool:
			_blit(img, tool_g.g, tool_g.pv, hand, aF + float(pose.wr), tsc, pal)
		_blit(img, ARM, ARM_PV, sh, aF, as_, pal)
	else:
		var hip := Vector2(cx, 0)
		hip.y = H - 3.0 - leg_len
		var neck := hip + neck_v + Vector2(0, tdy)
		var shy := hip.y + sh_y + tdy
		var hx := 1.5 * ts.x
		var sx := 3.0 * ts.x
		var aL := float(pose.aL)
		var aR := float(pose.aR)
		_blit(img, LEG.f, Vector2(1.5, 1), hip + Vector2(-hx, -float(pose.lL)), 0.0, lsc, pal)
		_blit(img, LEG.f, Vector2(1.5, 1), hip + Vector2(hx, -float(pose.lR)), 0.0, lsc, pal)
		_blit(img, torso, TORSO_PV, hip + Vector2(0, tdy), 0.0, ts, pal)
		_blit(img, head, HEAD_PV, neck, 0.0, hs, pal)
		_blit(img, ARM, ARM_PV, Vector2(cx - sx, shy), -aL, as_, pal)
		var shr := Vector2(cx + sx, shy)
		if show_tool:
			_blit(img, tool_g.g, tool_g.pv, shr + _rot(Vector2(0, arm_hand), aR), aR + float(pose.wr), tsc, pal)
		_blit(img, ARM, ARM_PV, shr, aR, as_, pal)
	# pieds sur la derniere ligne (le contour ajoute la derniere ligne)
	var low := -1
	for y in range(H - 1, -1, -1):
		for x in range(W):
			if img.get_pixel(x, y).a > 0.0:
				low = y
				break
		if low >= 0:
			break
	if low >= 0 and low != H - 2:
		var moved := Image.create(W, H, false, Image.FORMAT_RGBA8)
		moved.fill(Color(0, 0, 0, 0))
		moved.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(0, H - 2 - low))
		img = moved
	_outline(img)
	return img


## Toutes les images brutes : {nom: [Image]} et leurs parametres {nom: {fps, loop}}.
static func build_images(look: Dictionary, tool_id: String) -> Dictionary:
	var out := {}
	for name in PROFILE:
		var d: Dictionary = PROFILE[name]
		var arr: Array = []
		for i in int(d.n):
			arr.append(render(look, pose_at(d.keys, PDEF, i, int(d.n), bool(d.loop)), "p", tool_id))
		out[name] = {"frames": arr, "fps": d.fps, "loop": d.loop}
	for v in ["f", "b"]:
		for name in FRONTAL:
			var d: Dictionary = FRONTAL[name]
			var arr: Array = []
			for i in int(d.n):
				arr.append(render(look, pose_at(d.keys, FDEF, i, int(d.n), bool(d.loop)), v, tool_id))
			out[name + ("_front" if v == "f" else "_back")] = {"frames": arr, "fps": d.fps, "loop": d.loop}
	return out


static func build(look: Dictionary, tool_id: String = "pick") -> SpriteFrames:
	var key := var_to_str([look.get("body"), look.get("skin"), look.get("helmet"), look.get("shirt"), look.get("overalls"),
		look.get("boots"), look.get("hair"), look.get("hair_color"), look.get("beard"), tool_id])
	if _cache.has(key):
		return _cache[key]
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	var data := build_images(look, tool_id)
	for name in data:
		var e: Dictionary = data[name]
		sf.add_animation(name)
		sf.set_animation_speed(name, e.fps)
		sf.set_animation_loop(name, e.loop)
		for im in e.frames:
			sf.add_frame(name, ImageTexture.create_from_image(im))
	if _cache.size() > 24:
		_cache.clear()
	_cache[key] = sf
	return sf


## Taille d'un pixel du sprite en unites monde (le mineur fait la hauteur de sa hitbox).
static func pixel_size(look: Dictionary, hh: float) -> float:
	var L := layout(look)
	return (1.0 / 16.0) * (hh / 1.7) * (25.0 / float(L.body))
