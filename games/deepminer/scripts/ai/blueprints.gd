class_name Blueprints
extends RefCounted
## Plans de base des IA, en ASCII par couche (de bas en haut). Les rangées sont les z, les colonnes les x.
## Couche 0 = sol (y-1), couche 1 = y0 (là où se trouve 'S', le point de spawn personnel), couche 2 = y1, couche 3 = toit.
## Légende : # pierre | D terre | B brique (pierre si pas de brique) | . vide creusé | S spawn | C coffre (le 1er = principal,
## les suivants = coffres de réserve posés quand le premier est plein) | T torche | d porte (vide) | w fenêtre (vide) | espace = ignoré.
## Hauteur intérieure 2 : tout se pose depuis le sol, à portée de bras.

const PLANS := {
	"cabane": {"traits": "sociable, loyal", "layers": [
		["#######", "#######", "#######", "#######", "#######"],
		["###d###", "#C....#", "#..S..#", "#.....#", "#######"],
		["###d###", "#T...T#", "#.....#", "#..T..#", "#######"],
		["BBBBBBB", "B#####B", "B#####B", "B#####B", "BBBBBBB"]]},
	"bunker": {"traits": "prudent", "layers": [
		["#####", "#####", "#####", "#####", "#####"],
		["#####", "#C.C#", "#.S.#", "#...#", "##d##"],
		["#####", "#T.T#", "#...#", "#...#", "##d##"],
		["#####", "#####", "#####", "#####", "#####"]]},
	"poste": {"traits": "courageux, agressif", "layers": [
		["#####", "#####", "#####", "#####", "#####"],
		["##w##", "#C..#", "w.S.w", "#...#", "##d##"],
		["##w##", "#T.T#", "w...w", "#...#", "##d##"],
		["BBBBB", "B###B", "B###B", "B###B", "BBBBB"]]},
	"piliers": {"traits": "loyal, honnête", "layers": [
		["#########", "#########", "#########", "#########", "#########", "#########", "#########"],
		["####d####", "#C.....C#", "#.#...#.#", "#...S...#", "#.#...#.#", "#.......#", "#########"],
		["####d####", "#T.....T#", "#.#...#.#", "#.......#", "#.#...#.#", "#...T...#", "#########"],
		["BBBBBBBBB", "B#######B", "B#######B", "B#######B", "B#######B", "B#######B", "BBBBBBBBB"]]},
	"atelier": {"traits": "avide", "layers": [
		["#######", "#######", "#######", "#######", "#######"],
		["#######", "#C...C#", "d..S..#", "#.B.B.#", "#######"],
		["#######", "#T...T#", "d.....#", "#.....#", "#######"],
		["#######", "#######", "#######", "#######", "#######"]]},
	"equerre": {"traits": "avide, prudent (2 sorties)", "layers": [
		["#######", "#######", "#######", "#######", "   ####", "   ####"],
		["###d###", "#C....#", "#.S...#", "####..#", "   #..#", "   #d##"],
		["###d###", "#T...T#", "#.....#", "####..#", "   #.T#", "   #d##"],
		["#######", "#######", "#######", "#######", "   ####", "   ####"]]},
	"deux_salles": {"traits": "loyal, prudent, avide", "layers": [
		["#########", "#########", "#########", "#########", "#########"],
		["##d######", "#C..#..C#", "#..S....#", "#...#...#", "######d##"],
		["##d######", "#T..#..T#", "#.......#", "#...#...#", "######d##"],
		["BBBBBBBBB", "B#######B", "B#######B", "B#######B", "BBBBBBBBB"]]},
	"relais": {"traits": "avant-poste (annexe)", "layers": [
		["#####", "#####", "#####", "#####"],
		["#####", "#C..#", "#.S.#", "##d##"],
		["#####", "#T..#", "#...#", "##d##"],
		["#####", "#####", "#####", "#####"]]},
	"terrier": {"traits": "discret", "layers": [
		["DDDDD", "DDDDD", "DDDDD", "DDDDD", "DDDDD"],
		["DDdDD", "DC..D", "D.S.D", "D...D", "DDDDD"],
		["DDdDD", "DT.TD", "D...D", "D...D", "DDDDD"],
		["DDDDD", "DDDDD", "DDDDD", "DDDDD", "DDDDD"]]},
}

const MATS := {"#": World.STONE, "D": World.DIRT, "B": World.BRICK}
const AIR_CHARS := ".STCdw"  # cases à vider (creusées si pleines)

static func names() -> Array:
	return PLANS.keys()

static func layers(name: String) -> Array:
	return PLANS[name].layers

## [largeur x, hauteur y, profondeur z]
static func size(name: String) -> Vector3i:
	var l: Array = layers(name)
	return Vector3i((l[0][0] as String).length(), l.size(), (l[0] as Array).size())

## Liste vide si le plan est valide : couches rectangulaires de même taille, un seul S (couche 1), un coffre au moins, une porte.
static func validate(name: String) -> Array:
	var errs: Array = []
	if not PLANS.has(name):
		return ["inconnu"]
	var l: Array = layers(name)
	var sz := size(name)
	var spawn := 0
	var chest := 0
	var door := 0
	for li in l.size():
		var rows: Array = l[li]
		if rows.size() != sz.z:
			errs.append("couche %d : %d rangées" % [li, rows.size()])
		for row in rows:
			if (row as String).length() != sz.x:
				errs.append("couche %d : largeur %d" % [li, (row as String).length()])
			for ch in (row as String):
				if ch == "S":
					spawn += 1
					if li != 1:
						errs.append("S hors de la couche 1")
				elif ch == "C":
					chest += 1
				elif ch == "d":
					door += 1
				elif not (ch in "#DB.TwS "):
					errs.append("caractère '%s'" % ch)
	if spawn != 1:
		errs.append("spawn : %d" % spawn)
	if chest < 1:
		errs.append("pas de coffre")
	if door < 1:
		errs.append("pas de porte")
	if sz.x < 5 or sz.x > 9 or sz.z < 4 or sz.z > 7 or sz.y < 3 or sz.y > 5:
		errs.append("dimensions %s" % str(sz))
	return errs

## Rotation de k quarts de tour autour du spawn (décalage x/z).
static func _rot(o: Vector3i, k: int) -> Vector3i:
	for i in (k & 3):
		o = Vector3i(-o.z, o.y, o.x)
	return o

## [[décalage depuis le spawn (S), caractère], ...] pour une orientation 0..3.
static func cells(name: String, rot := 0) -> Array:
	var out: Array = []
	var l: Array = layers(name)
	var s := Vector3i.ZERO
	for li in l.size():
		var rows: Array = l[li]
		for z in rows.size():
			var x := (rows[z] as String).find("S")
			if x >= 0:
				s = Vector3i(x, li, z)
	for li in l.size():
		var rows: Array = l[li]
		for z in rows.size():
			for x in (rows[z] as String).length():
				var ch: String = (rows[z] as String)[x]
				if ch != " ":
					out.append([_rot(Vector3i(x, li, z) - s - Vector3i(0, 1, 0), rot), ch])
	return out

## Préférence de personnalité (traits du Brain, 0-1) : plus haut = plus envie.
static func score(name: String, t: Dictionary, seed_v := 0) -> float:
	var g := func(k: String) -> float: return float(t.get(k, 0.5))
	var s := 0.0
	match name:
		"cabane": s = 0.5 + g.call("sociability") + 0.4 * g.call("loyalty")
		"bunker": s = 1.6 * g.call("caution") + 0.6 * (1.0 - g.call("courage"))
		"poste": s = g.call("courage") + 0.9 * g.call("aggression")
		"piliers": s = 0.8 * g.call("loyalty") + 0.5 * g.call("honesty") + 0.3 * g.call("sociability")
		"atelier": s = 1.8 * g.call("greed")
		"terrier": s = 0.7 * (1.0 - g.call("sociability")) + 0.6 * g.call("caution")
		"equerre": s = 0.3 + 0.6 * g.call("greed") + 0.4 * g.call("caution")
		"deux_salles": s = 0.3 + 0.5 * g.call("caution") + 0.5 * g.call("loyalty") + 0.3 * g.call("greed")
		"relais": s = -9.0  # réservé aux annexes
	return s + float(hash([seed_v, name]) % 100) / 500.0

## Plans classés pour une base principale (le relais est réservé aux annexes).
static func ranked(t: Dictionary, seed_v := 0) -> Array:
	var a := names()
	a.erase("relais")
	a.sort_custom(func(x, y): return score(x, t, seed_v) > score(y, t, seed_v))
	return a

## Tâches ordonnées [kind, cellule, bloc] : coffre, creuser, sol, murs puis toit (couche par couche), torches.
## Retourne {tasks, chests: [cellules de coffre, la 1re = principale], spawn}.
static func make_tasks(name: String, rot: int, base: Vector3i, brick := false) -> Dictionary:
	var dig: Array = []
	var floor_: Array = []
	var shell: Array = []
	var torch: Array = []
	var chests: Array = []
	for e in cells(name, rot):
		var o: Vector3i = e[0]
		var ch: String = e[1]
		var c := base + o
		if ch in "#DB":
			var id: int = MATS[ch]
			if id == World.BRICK and not brick:
				id = World.STONE
			(floor_ if o.y < 0 else shell).append([c, id, o])
		else:
			if ch == "C":
				chests.append(c)
			elif ch == "T":
				torch.append(c)
			dig.append([c, o])
	var by_dist := func(a, b): return Vector2(a[1].x, a[1].z).length() + absf(a[1].y) * 0.3 < Vector2(b[1].x, b[1].z).length() + absf(b[1].y) * 0.3
	dig.sort_custom(by_dist)
	floor_.sort_custom(func(a, b): return Vector2(a[2].x, a[2].z).length() < Vector2(b[2].x, b[2].z).length())
	shell.sort_custom(func(a, b): return a[2].y < b[2].y if a[2].y != b[2].y else Vector2(a[2].x, a[2].z).length() < Vector2(b[2].x, b[2].z).length())
	var tasks: Array = []
	if not chests.is_empty():
		tasks.append(["dig", chests[0], 0])
		tasks.append(["place", chests[0], World.CHEST])
	for d in dig:
		tasks.append(["dig", d[0], 0])
	for f in floor_:
		tasks.append(["place", f[0], f[1]])
	for s in shell:
		tasks.append(["place", s[0], s[1]])
	for c in torch:
		tasks.append(["place", c, World.TORCH])
	return {"tasks": tasks, "chests": chests, "spawn": base}
