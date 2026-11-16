class_name Life
extends RefCounted
## « Vie » d'une IA : objectifs choisis selon ses besoins, sa personnalité et ce qu'elle a vécu, mémoire d'événements et réflexions.
## (idées de Generative Agents : flux de mémoire + réflexion ; de Voyager : objectifs qui suivent les besoins du moment).
## Logique pure : le Miner exécute (états existants), Life décide ce que l'IA « veut » faire maintenant.

const MEM_MAX := 40
const REFLECT_EVERY := 240.0
const NNC := preload("res://games/deepminer/scripts/ai/nn.gd")
const NN_GOALS := ["enrichir", "equiper", "explorer", "socialiser", "construire"]
static var use_nn := false   # le petit réseau (data/goal_net.json, voir nn_train.gd) choisit le but à la place des poids à la main
static var _net: NNC = null
static var _net_tried := false

var goal := ""
var arg := {}          # ore: id minerai visé ; target: Vector3i (exploration)
var goal_until := 0.0
var memory: Array = [] # {t, kind, who, pos, imp}
var spots: Array = []  # [Vector3i, poids] : endroits où elle a trouvé du bon minerai
var avoid: Array = []  # [Vector3i, jusqu'à] : lieux où elle est morte / a été attaquée
var grudge := {}       # id -> nombre d'agressions retenues
var visited := {}      # case de 8 blocs -> visites (pour explorer du neuf)
var next_reflect := REFLECT_EVERY
var next_hunt := 120.0   # pas de recherche avant cet instant
var thoughts: Array = []  # dernières réflexions (texte), pour l'info-bulle / le débogage
var _noise := RandomNumberGenerator.new()

func _init(seed_v := 0) -> void:
	_noise.seed = seed_v

static func chunk(c: Vector3i) -> Vector3i:
	return Vector3i(c.x / 8, c.y / 8, c.z / 8)

func visit(c: Vector3i) -> void:
	var k := chunk(c)
	visited[k] = int(visited.get(k, 0)) + 1

func remember(kind: String, who: String, pos: Vector3i, imp: float, now: float) -> void:
	memory.append({"t": now, "kind": kind, "who": who, "pos": pos, "imp": imp})
	if memory.size() > MEM_MAX:  # on garde le plus important / récent
		var worst := 0
		for i in memory.size():
			if float(memory[i].imp) - (now - float(memory[i].t)) / 600.0 < float(memory[worst].imp) - (now - float(memory[worst].t)) / 600.0:
				worst = i
		memory.remove_at(worst)

## Réflexion périodique : transforme les souvenirs en opinions et en lieux à retenir / éviter.
func reflect(brain: Brain, now: float) -> void:
	if now < next_reflect:
		return
	next_reflect = now + REFLECT_EVERY
	var hits := {}
	var ore_pos: Array = []
	for e in memory:
		match e.kind:
			"attacked", "wall_broken":
				hits[e.who] = int(hits.get(e.who, 0)) + 1
			"found":
				ore_pos.append(e)
			"died":
				avoid.append([e.pos, now + 600.0])
	for who in hits:
		if int(hits[who]) >= 2 and int(hits[who]) > int(grudge.get(who, 0)):
			grudge[who] = hits[who]
			brain._rel(who).aff -= 8.0 * float(hits[who])
			thoughts.append("%s m'embête (%d fois)" % [who, hits[who]])
	for e in ore_pos:  # on retient un lieu riche (fusionné avec un voisin à moins de 8 blocs)
		var merged := false
		for s in spots:
			if Vector3(s[0]).distance_to(Vector3(e.pos)) < 8.0:
				s[1] = float(s[1]) + float(e.imp)
				merged = true
				break
		if not merged:
			spots.append([e.pos, float(e.imp)])
	spots.sort_custom(func(a, b): return a[1] > b[1])
	if spots.size() > 5:
		spots.resize(5)
	avoid = avoid.filter(func(a): return float(a[1]) > now)
	if thoughts.size() > 6:
		thoughts = thoughts.slice(-6)
	memory = memory.filter(func(e): return now - float(e.t) < 900.0 or float(e.imp) >= 0.8)

func is_avoided(c: Vector3i, now: float) -> bool:
	for a in avoid:
		if float(a[1]) > now and Vector3(a[0]).distance_to(Vector3(c)) < 9.0:
			return true
	return false

## Courte phrase pour l'étiquette : ce qu'elle veut.
func label() -> String:
	match goal:
		"enrichir":
			return "veut du " + World.NAMES[int(arg.get("ore", World.COAL))].to_lower()
		"equiper":
			return "veut des torches"
		"construire":
			return "bâtit sa base"
		"explorer":
			return "explore du neuf"
		"chercher":
			return "cherche " + String(arg.get("who", "?"))
		"socialiser":
			return "cherche du monde"
		"expandre":
			return "veut s'agrandir"
	return ""

func ore_bonus(id: int) -> float:
	if goal != "enrichir":
		return 0.0
	return -8.0 if id == int(arg.get("ore", -1)) else 3.0  # le minerai voulu passe devant, les autres attendent

## But terminé ou périmé ?
func done(mi: Node, m: Node, now: float) -> bool:
	if now >= goal_until:
		return true
	var st: Dictionary = m.chests.get(mi.chest, {})
	match goal:
		"enrichir":
			var o: int = int(arg.get("ore", -1))
			return int(mi.inv.get(o, 0)) + int(st.get(o, 0)) >= (10 if o == World.COAL else 8)
		"equiper":
			return int(mi.inv.get(World.TORCH, 0)) + int(st.get(World.TORCH, 0)) >= 6
		"construire":
			return mi.tasks.is_empty()
	return false

## Choisit le prochain but d'après les besoins, la personnalité et la mémoire (Utility AI + bruit + inertie).
func choose(mi: Node, m: Node, now: float) -> void:
	if _choose_hunt(mi, now):
		return
	if use_nn and _choose_nn(mi, m, now):
		return
	_choose_hand(mi, m, now)

## Chercher quelqu'un : une rancune tenace (venger) ou un sociable qui s'ennuie (retrouver un ami). Jamais en zone sûre ni sans raison.
func _choose_hunt(mi: Node, now: float) -> bool:
	if now < next_hunt:
		return false
	var t: Dictionary = mi.brain.t
	var best := ""
	var bg := 0
	for id in grudge:
		if int(grudge[id]) > bg and mi.brain.status_of(id) == Brain.Status.ENNEMI:
			bg = int(grudge[id])
			best = id
	if best != "" and _noise.randf() < 0.15 + 0.5 * t.aggression * t.courage:
		goal = "chercher"
		arg = {"who": best, "mode": "attaquer"}
	elif t.sociability > 0.55 and mi.brain.boredom > 0.5 and mi.brain.status_of("player") in [Brain.Status.AMI, Brain.Status.ALLIE] and _noise.randf() < 0.3:
		goal = "chercher"
		arg = {"who": "player", "mode": "suivre" if _noise.randf() < 0.5 else "voir"}
	else:
		return false
	goal_until = now + 150.0
	next_hunt = now + _noise.randf_range(180.0, 400.0)
	return true

## But imposé par la couche stratégique (LLM) : liste fermée, vérifié comme les autres (faisable ou refusé).
func force(mi: Node, m: Node, g: String, ore_word: String, now: float) -> bool:
	var st: Dictionary = m.chests.get(mi.chest, {})
	var coal: int = int(mi.inv.get(World.COAL, 0)) + int(st.get(World.COAL, 0))
	match g:
		"construire":
			if not (mi.tasks.size() > 0 and mi.project == ""):
				return false
		"equiper":
			if coal <= 0:
				return false
		"enrichir", "explorer", "socialiser":
			pass
		"chercher":
			pass
		_:
			return false
	goal = g
	arg = {}
	if g == "enrichir":
		var oid: int = Miner.item_id(ore_word)
		arg = {"ore": oid if oid in [World.COAL, World.IRON, World.COPPER, World.CRYSTAL] else World.IRON}
	elif g == "explorer":
		arg = {"target": null}
	elif g == "chercher":
		arg = {"who": "player", "mode": ore_word if ore_word in ["attaquer", "suivre", "voir"] else "voir"}
	elif g == "socialiser":
		mi.brain.boredom = 1.0
		mi.brain.visit_cd = 0.0
	goal_until = now + _noise.randf_range(120.0, 240.0)
	return true

## Choix par le réseau : on prend le meilleur but réalisable (construire sans plan, s'équiper sans charbon -> on passe au suivant).
func _choose_nn(mi: Node, m: Node, now: float) -> bool:
	if not _net_tried:
		_net_tried = true
		_net = NNC.load_file("res://games/deepminer/data/goal_net.json")
	if _net == null:
		return false
	var t: Dictionary = mi.brain.t
	var st: Dictionary = m.chests.get(mi.chest, {})
	var torches: int = int(mi.inv.get(World.TORCH, 0)) + int(st.get(World.TORCH, 0))
	var coal: int = int(mi.inv.get(World.COAL, 0)) + int(st.get(World.COAL, 0))
	var base_p := 1.0 if mi.base_done else 1.0 - float(mi.tasks.size()) / float(maxi(mi.base_total, 1))
	var x := [torches / 10.0, coal / 10.0, clampf(mi.health / maxf(mi.max_hp, 1.0), 0.0, 1.0), base_p, mi.brain.boredom,
		0.6 * mi.brain.boredom, 0.1, minf(float(mi.stats.deposited) / 50.0, 1.0), t.greed, t.caution, t.sociability]
	var o: Array = _net.forward(x)
	var order := range(o.size())
	order.sort_custom(func(a, b): return o[a] > o[b])
	for i in order:
		var g: String = NN_GOALS[i]
		if g == "construire" and not (mi.tasks.size() > 0 and mi.project == ""):
			continue
		if g == "equiper" and coal <= 0:
			continue
		goal = g
		arg = {}
		if g == "enrichir":
			arg = {"ore": World.COAL if torches < 3 else (World.CRYSTAL if t.greed > 0.6 else World.IRON)}
		elif g == "explorer":
			arg = {"target": null}
		elif g == "socialiser":
			mi.brain.boredom = 1.0
			mi.brain.visit_cd = 0.0
		goal_until = now + _noise.randf_range(90.0, 220.0)
		return true
	return false

func _choose_hand(mi: Node, m: Node, now: float) -> void:
	var t: Dictionary = mi.brain.t
	var st: Dictionary = m.chests.get(mi.chest, {})
	var torches: int = int(mi.inv.get(World.TORCH, 0)) + int(st.get(World.TORCH, 0))
	var coal: int = int(mi.inv.get(World.COAL, 0)) + int(st.get(World.COAL, 0))
	var sc := {}
	var args := {}
	sc["construire"] = 0.9 * float(mi.tasks.size()) / float(maxi(mi.base_total, 1)) if (mi.tasks.size() > 0 and mi.project == "") else 0.0
	if torches < 3:
		if coal > 0:
			sc["equiper"] = 0.8
		else:
			sc["enrichir"] = 0.85
			args["enrichir"] = {"ore": World.COAL}
	var want_ore: int = World.CRYSTAL if t.greed > 0.6 and _noise.randf() < 0.7 else (World.IRON if _noise.randf() < 0.6 else World.COPPER)
	if not spots.is_empty():
		want_ore = World.CRYSTAL if t.greed > 0.5 else want_ore  # elle sait où il y en a
	if not sc.has("enrichir"):
		sc["enrichir"] = 0.3 + 0.45 * t.greed + (0.12 if not spots.is_empty() else 0.0)
		args["enrichir"] = {"ore": want_ore}
	sc["explorer"] = 0.12 + 0.4 * (1.0 - t.caution) + 0.25 * mi.brain.boredom
	sc["socialiser"] = 0.05 + 0.5 * t.sociability * mi.brain.boredom
	sc["expandre"] = (0.2 + 0.3 * (t.courage + t.greed) * 0.5) if (mi.tasks.is_empty() and mi.homes.size() < 2 and mi.stats.built >= 20) else 0.0
	var best := ""
	var bs := -1.0
	for g in sc:
		var s: float = sc[g] + _noise.randf_range(-0.08, 0.08) + (0.15 if g == goal and now < goal_until else 0.0)
		if s > bs:
			bs = s
			best = g
	goal = best
	arg = args.get(best, {})
	goal_until = now + _noise.randf_range(90.0, 220.0)
	if goal == "explorer":
		arg = {"target": null}
	if goal == "socialiser":
		mi.brain.boredom = 1.0
		mi.brain.visit_cd = 0.0
	if goal == "expandre":
		mi.project_t = 0.0

## Destination d'exploration : une case libre dans une zone peu visitée (rayon 25).
func explore_target(mi: Node, w: World) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var bv := 1 << 30
	var c: Vector3i = mi.feet_cell()
	for i in 24:
		var t := Vector3i(clampi(c.x + _noise.randi_range(-25, 25), 2, World.SX - 3), clampi(c.y + _noise.randi_range(-8, 8), 3, World.SY - 4), clampi(c.z + _noise.randi_range(-25, 25), 2, World.SZ - 3))
		if not Pathfinder.standable(w, t, mi.body_cells()):
			continue
		var v: int = int(visited.get(chunk(t), 0))
		if v < bv:
			bv = v
			best = t
	return best

func to_dict() -> Dictionary:
	return {"goal": goal, "arg": arg.duplicate(), "until": goal_until, "memory": memory.duplicate(true), "spots": spots.duplicate(true),
		"grudge": grudge.duplicate(), "thoughts": thoughts.duplicate(), "visited": visited.duplicate()}

func from_dict(d: Dictionary) -> void:
	goal = d.get("goal", "")
	arg = (d.get("arg", {}) as Dictionary).duplicate()
	goal_until = d.get("until", 0.0)
	memory = (d.get("memory", []) as Array).duplicate(true)
	spots = (d.get("spots", []) as Array).duplicate(true)
	grudge = (d.get("grudge", {}) as Dictionary).duplicate()
	thoughts = (d.get("thoughts", []) as Array).duplicate()
	visited = (d.get("visited", {}) as Dictionary).duplicate()
