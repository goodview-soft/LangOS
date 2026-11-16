class_name Stacks
## Piles de l'inventaire. `main.inv` (id -> total) reste la référence pour le craft, le poids et le jeu ; les piles
## (barre rapide, sac, objet tenu par le curseur) ne font que RÉPARTIR ce total. reconcile() les remet d'accord :
## ce qui est consommé sort d'abord de la barre, ce qui est ramassé complète les piles existantes (barre d'abord).
## Une pile est un Vector2i(id, quantité) ; id EMPTY = case vide ; la pioche (-1) est une pile de 1, jamais fusionnée.

const EMPTY := -2
const SWORD := -3  # l'épée : pile de 1 comme la pioche (-1), jamais fusionnée
const CAP := 64
const NONE := Vector2i(EMPTY, 0)

static func is_held_tool(item: int) -> bool:
	return item == -1 or item == SWORD

static func reconcile(m: Node) -> void:
	var hb: Array = m.hotbar
	var hn: Array = m.hotbar_n
	var sac: Array = m.sac
	var ids := {}
	for id in m.inv:
		if id != World.AIR and int(m.inv[id]) > 0:
			ids[id] = true
	for i in hb.size():
		if hb[i] >= 0:
			ids[hb[i]] = true
	for s in sac:
		if s.x >= 0:
			ids[s.x] = true
	if m.cursor.x >= 0:
		ids[m.cursor.x] = true
	for id in ids:
		_fix(m, id, maxi(int(m.inv.get(id, 0)), 0))
	# la pioche est toujours quelque part
	var has_pick: bool = hb.has(-1) or m.cursor.x == -1
	for s in sac:
		has_pick = has_pick or s.x == -1
	if not has_pick:
		add_sac(m, Vector2i(-1, 1))
	if int(m.gear.get("sword", 0)) > 0:  # l'épée est toujours quelque part (barre, sac ou curseur)
		var has_sw: bool = hb.has(SWORD) or m.cursor.x == SWORD
		for s in sac:
			has_sw = has_sw or s.x == SWORD
		if not has_sw:  # anciennes sauvegardes : l'épée prend la case 2 de la barre, l'objet qui y était passe dans le sac
			if hb.size() > 1:
				if hb[1] != EMPTY and (hn[1] > 0 or is_held_tool(hb[1])):
					add_sac(m, Vector2i(hb[1], hn[1]))
				hb[1] = SWORD
				hn[1] = 1
			else:
				add_sac(m, Vector2i(SWORD, 1))
	# une case de la barre épuisée se recharge depuis le sac (sinon elle reste vide : l'objet disparaît)
	for i in hb.size():
		if hb[i] >= 0 and hn[i] <= 0:
			for k in sac.size():
				if sac[k].x == hb[i] and hn[i] <= 0:
					hn[i] = sac[k].y
					sac[k] = NONE
	while sac.size() > 0 and (sac[sac.size() - 1] as Vector2i).x == EMPTY:
		sac.pop_back()

static func _fix(m: Node, id: int, total: int) -> void:
	if id < 0:
		return
	var hb: Array = m.hotbar
	var hn: Array = m.hotbar_n
	var sac: Array = m.sac
	var cur := 0
	for i in hb.size():
		if hb[i] == id:
			cur += hn[i]
	for s in sac:
		if s.x == id:
			cur += s.y
	if m.cursor.x == id:
		cur += m.cursor.y
	if cur > total:  # consommé : barre d'abord, puis le sac depuis la fin
		var ex: int = cur - total
		for i in hb.size():
			if hb[i] == id and ex > 0:
				var t := mini(ex, hn[i])
				hn[i] -= t
				ex -= t
		for k in range(sac.size() - 1, -1, -1):
			if sac[k].x == id and ex > 0:
				var t := mini(ex, sac[k].y)
				sac[k] = Vector2i(id, sac[k].y - t) if sac[k].y - t > 0 else NONE
				ex -= t
		if ex > 0 and m.cursor.x == id:
			var t := mini(ex, m.cursor.y)
			m.cursor = Vector2i(id, m.cursor.y - t) if m.cursor.y - t > 0 else NONE
	elif cur < total:  # ramassé : on complète les piles de la barre, puis du sac, puis une nouvelle pile
		var add: int = total - cur
		for i in hb.size():
			if hb[i] == id and add > 0:
				var t := mini(add, CAP - hn[i])
				hn[i] += t
				add -= t
		for k in sac.size():
			if sac[k].x == id and add > 0:
				var t := mini(add, CAP - sac[k].y)
				sac[k] = Vector2i(id, sac[k].y + t)
				add -= t
		while add > 0:
			var t := mini(add, CAP)
			add_sac(m, Vector2i(id, t))
			add -= t

## Met la pile dans la première case vide du sac (ou à la fin).
static func add_sac(m: Node, st: Vector2i) -> void:
	var sac: Array = m.sac
	for k in sac.size():
		if sac[k].x == EMPTY:
			sac[k] = st
			return
	sac.append(st)

## Le sac a une taille variable : on s'assure que la case k existe.
static func ensure(m: Node, k: int) -> void:
	while m.sac.size() <= k:
		m.sac.append(NONE)

static func to_dict(m: Node) -> Dictionary:
	var s: Array = []
	for v in m.sac:
		s.append([v.x, v.y])
	return {"hotbar_n": m.hotbar_n.duplicate(), "sac": s}

static func from_dict(m: Node, d: Dictionary) -> void:
	m.hotbar_n = (d.get("hotbar_n", []) as Array).duplicate() if (d.get("hotbar_n", []) as Array).size() == m.hotbar.size() else _zeros(m.hotbar.size())
	m.sac = []
	for v in (d.get("sac", []) as Array):
		m.sac.append(Vector2i(int(v[0]), int(v[1])))
	m.cursor = NONE
	reconcile(m)

static func _zeros(n: int) -> Array:
	var a: Array = []
	a.resize(n)
	a.fill(0)
	return a
