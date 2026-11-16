class_name Miner extends Player
## Autonomous AI miner: local state machine (decisions 5x/s) + bounded A* (Pathfinder).
## Same physics as the player (Player.step). World edits go through main's shared API
## (edit_break / edit_place: remesh, lights, particles), never with toasts.

const THINK := 0.2
const MINE_K := 1.6  # mining time = HARD * MINE_K seconds
const CARRY_MAX := 6  # ores carried before going home
const KEEP_MAX := 60  # max stone/dirt kept from digging
const BUILD_REACH := 4.7
const ORES := [World.COAL, World.IRON, World.COPPER, World.CRYSTAL]
const ORE_R := 11
const ORE_RY := 6
const TASK_GAP := 0.22
const ACT_R := 2.3  # portée réelle pour poser/casser un bloc de construction (blocs, depuis le centre du corps)
const PLACE_T := 0.2  # durée du geste de pose
const CHEST_CAP := 90  # objets : au-delà, l'IA ouvre un coffre de réserve
const ROAM := 16  # max distance from the base (Manhattan, y counted 1.5x)

enum S {IDLE, SEEK, GOTO_ORE, MINE, EXPLORE, GO_HOME, BUILD, FLEE, RUN, HIDE, FIGHT, FOLLOW, SOCIAL, PAUSE, QUARRY, SEARCH}
const SOCIAL_STATES := [S.RUN, S.HIDE, S.FIGHT, S.FOLLOW, S.SOCIAL, S.PAUSE, S.SEARCH]
const VIEW := 16.0  # sight range (blocks)
const ITEM_WORDS := {"terre": World.DIRT, "roche": World.STONE, "pierre": World.STONE, "charbon": World.COAL, "fer": World.IRON,
	"cuivre": World.COPPER, "cristal": World.CRYSTAL, "cristaux": World.CRYSTAL, "diamant": World.CRYSTAL, "diamants": World.CRYSTAL,
	"torche": World.TORCH, "torches": World.TORCH, "champignon": World.MUSHROOM, "champignons": World.MUSHROOM}

var mname := ""
var color := Color.WHITE
var base := Vector3i.ZERO
var chest := Vector3i(-1, -1, -1)
var inv := {}
var tasks: Array = []  # [kind "dig"/"place", Vector3i, block id]
var state := S.IDLE
var status := "arrive"
var stats := {"mined": 0, "deposited": 0, "built": 0, "dug": 0}
var label: Label3D
var think_t := 0.0
var path_cells: Array = []
var path_clears: Array = []
var path_i := 0
var goal := Vector3i.ZERO
var digging := false
var dig_cell := Vector3i.ZERO
var dig_t := 0.0
var dig_need := 1.0
var stuck_t := 0.0
var stuck_n := 0
var banned := {}  # cell -> clock time until which it is ignored
var clock := 0.0
var build_budget := 0
var task_t := 0.0
var flee_t := 0.0
var home_fail := 0
var wait_t := 0.0  # > 0 : attend dans la salle de spawn avant de partir
# --- brain (docs/AI_DESIGN.md): the Brain decides, the state machine executes
var personality := "bavard"
var brain: Brain
var brain_t := 0.0
var decision := {}
var active := true  # false = "disconnected" (hidden, not simulated; base and chest stay)
var fight_id := ""  # target entity of RUN/FIGHT/FOLLOW/SOCIAL
var last_known := Vector3.INF
var search_n := 0
var replan_t := 0.0
var pause_t := 0.0
var react_t := 0.0
var hidden := false
var regen_idle := 0.0
var signal_q: Array = []  # [time, "jump"|"crouch"]
var sig_hold := 0.0
var sig_kind := ""
var seen := {}  # entity id -> visible (last tactical tick)
var ore_t := 0.0
var ore_near := false
var base_total := 1
var bp := ""  # plan de base choisi (Blueprints)
var bp_rot := 0
var spare_chests: Array = []  # emplacements de coffres supplémentaires du plan
var extra_chests: Array = []  # coffres supplémentaires déjà posés
var pend: Array = []  # pose en cours [cellule, bloc, tâche] pendant le geste
var pend_t := 0.0
var build_dist_max := 0.0  # plus grande distance corps -> bloc au moment d'une pose/casse de construction (tests)
const NOWHERE := Vector3i(-1, -1, -1)
const VALUABLES := [World.CRYSTAL, World.IRON, World.COPPER]
var homes: Array = []  # autres maisons (inactives) : {base, chest, extra, spare, bp, rot, total} ; base/chest = la maison active
var project := ""  # "", "annexe" (2e base) ou "cache" (coffre enterré)
var project_t := 0.0  # pas de nouveau projet avant cette heure
var site := NOWHERE  # lieu du chantier en cours (cache) ; sinon la base
var proj_fail := 0
var caches: Array = []  # {chest, mouth, ids: [[cellule, bloc d'origine]], visit}
var visit_t := 0.0
var refuge_ban := 0.0
var inside_t := 0.0
var threat_pos := Vector3.INF  # menace sans corps d'entité (zombie)
var zombie_t := 0.0
var skill_mem := Skills.new_mem()  # réussites/échecs par compétence (voir Skills)
var proj_skill := ""
var proj_task_fail := 0
var base_done := false
var _climb_want := false
var sightings := {}      # id -> [position, instant] : où il a vu quelqu'un pour la dernière fois (perception honnête)
var search_mode := "voir"   # attaquer | suivre | voir : ce qu'il fera en le trouvant
var search_pts: Array = []  # étapes de recherche (positions)
var search_until := 0.0
var sp_done := false
var flee_until := 0.0   # engagement dans la fuite : le cerveau ne l'interrompt pas avant
var flee_goal := Vector3i(-1, -1, -1)  # destination de fuite gardée (évite de tourner en rond)
var flee_fail := 0
var life: Life
var life_t := 0.0
var last_attacked := {}
var quarry_t := 0.0  # pas de carrière avant cette heure
var walked := 0.0  # distance parcourue depuis la dernière torche posée
var torch_spots: Array = []  # torches posées récemment (pour les espacer)
var species := 0  # index de DMSettings.BODIES : dessin FIXE par espèce (voir DMSettings.ai_look)

func _ready() -> void:
	pal = DMSettings.ai_look(species, color)
	super._ready()
	label = Label3D.new()
	label.pixel_size = 1.0 / 16.0
	label.font = UiTheme.font()
	label.font_size = 10
	label.outline_size = 3
	label.outline_modulate = Color(0.05, 0.04, 0.08)
	label.modulate = color.lightened(0.25)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.no_depth_test = true
	label.render_priority = 3
	label.outline_render_priority = 2
	label.position = Vector3(0, vis_hh + 0.85, 0)
	label.line_spacing = -2
	label.visible = false  # pas de texte au-dessus de la tête (IA et zombies)
	add_child(label)
	_label()

func _label() -> void:
	if label:
		label.text = "%s\n%s" % [mname, status]

const PERSO_TRAITS := {
	"bavard": {"sociability": 0.8}, "serviable": {"sociability": 0.75, "loyalty": 0.8, "aggression": 0.2, "honesty": 0.8},
	"raleur": {"aggression": 0.75, "sociability": 0.35, "courage": 0.7}, "discret": {"sociability": 0.2, "caution": 0.8, "courage": 0.35},
	"farceur": {"sociability": 0.7, "aggression": 0.5, "honesty": 0.4}}

func make_brain() -> void:
	life = Life.new(hash(mname))
	brain = Brain.new(hash(mname), PERSO_TRAITS.get(personality, {}))
	brain_t = randf() * 0.4

static func item_id(word: String) -> int:
	return ITEM_WORDS.get(word.to_lower().strip_edges(), -1)

static func item_word(id: int) -> String:
	return (World.NAMES[id] as String).to_lower() if id >= 0 and id < World.NAMES.size() else "?"

func _set_status(s: String) -> void:
	if s != status:
		status = s
		_label()

static func ore_word(id: int) -> String:
	return (World.NAMES[id] as String).to_lower()

func carry() -> int:
	var n := 0
	for id in ORES:
		n += inv.get(id, 0)
	return n

func _add(id: int, n := 1) -> void:
	if (id == World.STONE or id == World.DIRT) and inv.get(id, 0) >= KEEP_MAX:
		return
	inv[id] = inv.get(id, 0) + n

func at_base() -> bool:
	return Vector2(pos.x - base.x - 0.5, pos.z - base.z - 0.5).length() < 0.45 and absf(pos.y - base.y) < 0.6

func _in_reach(c: Vector3i, r := 2.8) -> bool:
	return (Vector3(c) + Vector3(0.5, 0.5, 0.5)).distance_to(center()) <= r

# ---------------------------------------------------------------- per frame
func tick(dt: float, m: Node) -> void:
	var w: World = m.world
	clock += dt
	if m.is_safe_zone(center()):
		fall_safe_t = 6.0  # sortie du spawn : pas de dégâts de chute (comme le joueur)
	task_t -= dt
	think_t -= dt
	if think_t <= 0.0:
		think_t = THINK
		_think(m, w)
	brain_t -= dt
	if brain_t <= 0.0:
		brain_t = randf_range(0.3, 0.5)  # 2-3 Hz, never a regular timer
		brain_tick(m, w)
	_regen(dt)
	var wish := Vector3.ZERO
	var jump := false
	_climb_want = false
	_reflexes(dt, m)
	if digging:
		_dig_step(dt, m, w)
	elif pend_t > 0.0:
		_pend_step(dt, m, w)
	elif path_i < path_cells.size():
		var r := _follow(dt, m, w)
		wish = r[0]
		jump = r[1]
	if in_water and w.get_v(Vector3i(floori(pos.x), floori(pos.y + 1.4), floori(pos.z))) == World.WATER:
		jump = true  # swim up
	jump = jump or _signals(dt, m)
	mining = digging or pend_t > 0.0
	can_climb = bool(DMSettings.SPECIES[clampi(species, 0, DMSettings.SPECIES.size() - 1)].get("climb", false)) and _climb_want
	var p0 := pos
	step(dt, wish, jump, w)
	walked += Vector2(pos.x - p0.x, pos.z - p0.z).length()
	if walked > 14.0 and on_ground and not digging and pend_t <= 0.0:
		_lay_torch(m, w)
	var sr: Vector3 = m.screen_right()
	var sd: float = vel.dot(sr)
	var foe: Player = m.entity(fight_id) if state in [S.FIGHT, S.SOCIAL, S.FOLLOW] else null
	if foe and center().distance_to(foe.center()) < 4.0:
		var fd: float = (foe.pos - pos).dot(sr)
		if absf(fd) > 0.1:
			facing = 1 if fd > 0 else -1
	elif absf(sd) > 0.3:
		facing = 1 if sd > 0 else -1
	if health <= 0.0:
		m.miner_died(self, "")

## Returns [wish, jump].
func _follow(dt: float, m: Node, w: World) -> Array:
	var nxt: Vector3i = path_cells[path_i]
	for cc in path_clears[path_i]:
		if Pathfinder.solid(w, cc):
			if Pathfinder.diggable(w, cc) and _in_reach(cc, 3.0):
				_start_dig(cc, w)
				_set_status("creuse")
			else:
				_clear_path()  # path no longer valid: think again
				think_t = 0.0
			return [Vector3.ZERO, false]
	# lissage : il vise la case la plus lointaine (4 max) atteignable en ligne droite sur du plat, au lieu de suivre l'escalier de la grille
	var look := path_i
	while look + 1 < path_cells.size() and look - path_i < 4:
		var nc: Vector3i = path_cells[look + 1]
		if nc.y != nxt.y or absf(pos.y - nxt.y) > 0.3:
			break
		var blocked := false
		for cc in path_clears[look + 1]:
			if Pathfinder.solid(w, cc):
				blocked = true
		if blocked or not _line_clear(w, pos, Vector3(nc.x + 0.5, nxt.y, nc.z + 0.5), nxt.y):
			break
		look += 1
	var tc: Vector3i = path_cells[look]
	var tgt := Vector3(tc.x + 0.5, tc.y, tc.z + 0.5)
	var d := tgt - pos
	d.y = 0.0
	if d.length() < (0.22 if look == path_i else 0.45) and absf(pos.y - tc.y) < 0.55:
		path_i = look + 1
		stuck_t = 0.0
		if path_i >= path_cells.size():
			vel.x = 0.0
			vel.z = 0.0
		return [Vector3.ZERO, false]
	stuck_t += dt
	if stuck_t > 2.5:
		_on_stuck(m, w, nxt)
	var jump := nxt.y > floori(pos.y + 0.05) and stuck_t > 0.35
	_climb_want = nxt.y - floori(pos.y + 0.05) >= 3  # mur trop haut pour sauter : les grimpeurs s'agrippent
	return [d.normalized() if d.length() > 0.05 else Vector3.ZERO, jump]

## Il éclaire sa route en profondeur : une torche tous les ~14 blocs de marche, loin des maisons et de la zone sûre.
func _lay_torch(m: Node, w: World) -> void:
	walked = 8.0  # nouvel essai dans ~6 blocs si ce n'est pas possible ici
	if inv.get(World.TORCH, 0) < 2 or not (state in [S.GOTO_ORE, S.EXPLORE, S.SEEK, S.GO_HOME]) or home_dist(pos) < 7.0 or m.is_safe_zone(center()):
		return
	var c := feet_cell()
	if w.get_v(c) != World.AIR:
		return
	for t in torch_spots:
		if Vector3(c).distance_to(Vector3(t)) < 9.0:
			return
	if m.edit_place(c, World.TORCH):
		inv[World.TORCH] -= 1
		walked = 0.0
		torch_spots.append(c)
		if torch_spots.size() > 40:
			torch_spots.pop_front()

## Segment a -> b à hauteur y : le corps (largeur hw) passe partout, avec un sol plein dessous et pas de lave ni d'eau à la tête.
func _line_clear(w: World, a: Vector3, b: Vector3, y: int) -> bool:
	var h := body_cells()
	var n := int(a.distance_to(b) / 0.3) + 1
	for i in range(1, n + 1):
		var p := a.lerp(b, float(i) / float(n))
		for ox in [-hw, hw]:
			for oz in [-hw, hw]:
				var cx := floori(p.x + ox)
				var cz := floori(p.z + oz)
				if not Pathfinder.solid(w, Vector3i(cx, y - 1, cz)):
					return false
				for j in h:
					var id := w.get_v(Vector3i(cx, y + j, cz))
					if World.KIND[id] == World.K_CUBE or id == World.LAVA or (j == h - 1 and id == World.WATER):
						return false
				if w.get_v(Vector3i(cx, y, cz)) == World.WATER or Pathfinder.lava_near(w, Vector3i(cx, y, cz)):
					return false
	return true

func _on_stuck(m: Node, w: World, nxt: Vector3i) -> void:
	stuck_t = 0.0
	stuck_n += 1
	if stuck_n >= 3:  # give up this goal
		banned[goal] = clock + 40.0
		stuck_n = 0
		_clear_path()
		state = S.EXPLORE
		think_t = 0.0
		return
	# dig whatever blocks the way, else plan again
	var c := feet_cell()
	var dir := Vector3i(signi(nxt.x - c.x), 0, signi(nxt.z - c.z))
	var blockers: Array = []
	for i in body_cells():
		blockers.append(c + dir + Vector3i(0, i, 0))
	blockers.append(c + Vector3i(0, body_cells(), 0))  # au-dessus de la tête
	for cc in blockers:
		if dir != Vector3i.ZERO and Pathfinder.diggable(w, cc):
			_start_dig(cc, w)
			return
	_clear_path()
	think_t = 0.0
	_set_status("bloqué")

func _clear_path() -> void:
	path_cells = []
	path_clears = []
	path_i = 0
	stuck_t = 0.0

func path_done() -> bool:
	return path_i >= path_cells.size()

func _start_dig(c: Vector3i, w: World) -> void:
	digging = true
	dig_cell = c
	dig_t = 0.0
	dig_need = maxf(World.HARD[w.get_v(c)], 0.05) * MINE_K / mine_mult  # le nain creuse vite, le gobelin moins
	vel.x = 0.0
	vel.z = 0.0

func _dig_step(dt: float, m: Node, w: World) -> void:
	var id := w.get_v(dig_cell)
	if id == World.AIR or World.KIND[id] == World.K_FLUID or World.HARD[id] < 0.0:
		digging = false
		return
	dig_t += dt
	if dig_t >= dig_need:
		digging = false
		var drop: int = m.edit_break(dig_cell, false)
		if drop >= 0:
			if drop in ORES:
				stats.mined += 1
				if drop in [World.CRYSTAL, World.IRON]:
					life.remember("found", "", dig_cell, 0.9 if drop == World.CRYSTAL else 0.5, clock)
			else:
				stats.dug += 1
			_add(drop)

## Path request: 1 = path ready, 0 = no budget this frame (retry), -1 = no path.
func _request(m: Node, w: World, mode: int, target: Vector3i, partial := false) -> int:
	if not m.take_path_budget():
		think_t = 0.0
		return 0
	Pathfinder.max_fall = 9 if fall_safe_t > 0.0 else Pathfinder.MAX_FALL  # il saute sans crainte quand la chute ne fait pas mal
	var sp: Dictionary = DMSettings.SPECIES[clampi(species, 0, DMSettings.SPECIES.size() - 1)]
	Pathfinder.max_up = 3 if sp.get("bigjump", false) else 2
	Pathfinder.climb_up = 6 if sp.get("climb", false) else 0
	var r := Pathfinder.find(w, feet_cell(), mode, target, true, partial, Pathfinder.MAX_NODES * (4 if m.testing and not m.real_paths else 1), body_cells())
	Pathfinder.max_fall = Pathfinder.MAX_FALL
	Pathfinder.max_up = 2
	Pathfinder.climb_up = 0
	if r.cells.is_empty() and not r.ok:
		return -1
	path_cells = r.cells
	path_clears = r.clears
	path_i = 0
	stuck_t = 0.0
	goal = target
	return 1

# ---------------------------------------------------------------- decisions
func _think(m: Node, w: World) -> void:
	var c := feet_cell()
	life_t += THINK
	life.visit(c)
	life.reflect(brain, clock)
	var inside := false  # pris dans un bloc (apparition dans un mur, bloc posé sur lui...)
	for i in body_cells():
		inside = inside or Pathfinder.solid(w, c + Vector3i(0, i, 0))
	if inside:
		inside_t += THINK
		if inside_t > 1.2:
			inside_t = 0.0
			_unstuck(m, w, c)
		return
	inside_t = 0.0
	var head_wet := w.get_v(Vector3i(floori(pos.x), floori(pos.y + 1.4), floori(pos.z))) == World.WATER
	if (in_lava or head_wet or Pathfinder.lava_near(w, c)) and state != S.FLEE:
		state = S.FLEE
		digging = false
		_clear_path()
	if state in [S.SEEK, S.EXPLORE, S.GOTO_ORE] and not digging and home_dist(Vector3(c)) > ROAM + 10 + (22 if life.goal == "explorer" else 0):
		state = S.GO_HOME  # wandered too far
		_clear_path()
	if get("zid") == null and state != S.FLEE and m.get("zombies") != null:  # (le zombie, qui hérite de Miner, n'a pas cette réaction)
		var zn: Variant = m.nearest_zombie(center(), 8.0)
		if zn != null and not m.is_safe_zone(center()):  # un zombie approche : il détale vers sa maison (le zombie est lent)
			threat_pos = zn.pos as Vector3
			zombie_t = clock + 4.0
			if state != S.RUN:
				_enter(S.RUN, "")
	if state in SOCIAL_STATES:
		_think_social(m, w)
		return
	if wait_t > 0.0:  # départ différé : il discute / attend au spawn
		wait_t -= THINK
		_set_status("au spawn")
		if wait_t <= 0.0:
			state = S.GO_HOME  # part à pied vers sa base
			_clear_path()
		return
	# perdu loin de tout (ou envie de socialiser) : /spawn, hors combat seulement
	if state in [S.SEEK, S.EXPLORE, S.IDLE] and not digging and can_use_spawn() and m.spawn_point().distance_to(pos) > 30.0 and randf() < 0.002:
		use_spawn(m)
		return
	match state:
		S.FLEE:
			_set_status("fuit !")
			if path_done():
				if not (in_lava or head_wet or Pathfinder.lava_near(w, c)) and on_ground:
					state = S.IDLE
				elif _request(m, w, Pathfinder.GOAL_SAFE, c) < 0:
					flee_t += THINK
					if flee_t > 3.0:  # trapped: emergency return home
						flee_t = 0.0
						pos = Vector3(base) + Vector3(0.5, 0, 0.5)
						position = pos
						state = S.IDLE
		S.IDLE:
			stuck_n = 0
			state = S.GO_HOME if _has_build_work(m, w) else S.SEEK
		S.SEEK:
			_set_status("cherche" if life.goal != "enrichir" else "cherche " + life.label().replace("veut ", ""))
			if carry() >= CARRY_MAX:
				state = S.GO_HOME
				return
			_nearest_home_swap()
			if _life_goal(m, w):
				return
			if _needs_stone(m) and clock >= quarry_t:  # chantier en attente de matériaux : il va prendre de la pierre
				state = S.QUARRY
				_clear_path()
				return
			var ore := _find_ore(m, w)
			if ore.x < 0:
				if _richer_home_swap(m):  # plus rien près d'ici : va miner autour de son autre base
					state = S.GO_HOME
					return
				state = S.GO_HOME if _has_build_work(m, w) else S.EXPLORE
				_clear_path()
				return
			var r := _request(m, w, Pathfinder.GOAL_REACH, ore)
			if r > 0:
				state = S.GOTO_ORE
				stuck_n = 0
			elif r < 0:
				banned[ore] = clock + 30.0
		S.GOTO_ORE:
			if digging:
				return
			if not (w.get_v(goal) in ORES):
				state = S.SEEK
				_clear_path()
				return
			_set_status("va au " + ore_word(w.get_v(goal)))
			if path_done():
				if _in_reach(goal, 3.0):
					state = S.MINE
					_set_status("mine du " + ore_word(w.get_v(goal)))
					_start_dig(goal, w)
				else:
					banned[goal] = clock + 30.0
					state = S.SEEK
		S.QUARRY:
			_set_status("prend de la pierre")
			if digging:
				return
			if not _needs_stone(m) or _blocks() >= 36:
				if _blocks() >= 36:
					Skills.success(skill_mem, "carriere", clock)
				_clear_path()
				state = S.GO_HOME if _has_build_work(m, w) else S.SEEK
				return
			if path_done():
				if goal.x >= 0 and w.get_v(goal) in [World.STONE, World.DIRT] and _in_reach(goal, 3.0):
					_start_dig(goal, w)
					return
				var qc := _find_stone(m, w)
				if qc.x < 0:
					Skills.failure(skill_mem, "carriere", clock)
					quarry_t = clock + 40.0
					state = S.SEEK
					return
				var qr := _request(m, w, Pathfinder.GOAL_REACH, qc)
				if qr < 0:
					banned[qc] = clock + 30.0
		S.MINE:
			if not digging:
				state = S.GO_HOME if carry() >= CARRY_MAX else S.SEEK
		S.EXPLORE:
			_set_status("explore")
			if digging:
				return
			if path_done():
				if not path_cells.is_empty():  # arrived somewhere new
					_clear_path()
					state = S.IDLE
					return
				var t := life.explore_target(self, w) if life.goal == "explorer" else _random_target(w, c)
				if t.x < 0 or _request(m, w, Pathfinder.GOAL_CELL, t, true) < 0:
					banned[t] = clock + 20.0
		S.GO_HOME:
			if digging:
				return
			_set_status("rentre")
			if at_base():
				_clear_path()
				_deposit(m, w)
				state = S.BUILD
				build_budget = 30
				return
			if path_done():
				if not path_cells.is_empty() and feet_cell() == base:
					_clear_path()
					return
				_nearest_home_swap()
				var before := feet_cell()
				var r := 0
				var ex: Vector3i = m.hub_exit_toward(base) if m.is_safe_zone(center()) else Vector3i(-1, -1, -1)
				if ex.x >= 0:  # dans la salle de spawn : d'abord la sortie la plus proche de la base
					r = _request(m, w, Pathfinder.GOAL_CELL, ex, true)
				else:
					r = _request(m, w, Pathfinder.GOAL_CELL, base, true)
				if r < 0 or (r > 0 and (path_cells.is_empty() or path_cells[-1] == before)):
					home_fail += 1
				elif r > 0:
					home_fail = 0
				if home_fail >= 2 and Vector3(feet_cell()).distance_to(Vector3(base)) <= 8.0 and not (home_fail >= 4 and tasks.is_empty()):
					# case de base inatteignable de tout près (sol manquant, mur...) : il reprend la construction sur place
					if not Pathfinder.solid(w, base - Vector3i(0, 1, 0)) and not tasks.any(func(t): return t[0] == "place" and t[1] == base - Vector3i(0, 1, 0)):
						tasks.push_front(["place", base - Vector3i(0, 1, 0), World.STONE])
					if not tasks.is_empty():
						home_fail = 0
						_clear_path()
						state = S.BUILD
						build_budget = 30
						return
				if home_fail >= 4:  # really lost: /spawn (hors combat), sinon retour direct (dernier recours)
					home_fail = 0
					_clear_path()
					if project == "annexe":  # site injoignable : il renonce et reste chez lui
						_abort_project()
						return
					if can_use_spawn() and m.spawn_point().distance_to(pos) > 25.0 and not m.is_safe_zone(center()):
						use_spawn(m)
					elif Pathfinder.standable(w, base, body_cells()):
						pos = Vector3(base) + Vector3(0.5, 0, 0.5)
						position = pos
						vel = Vector3.ZERO
					else:  # base sans sol : on ne se téléporte pas dans le vide (il tomberait en boucle)
						tasks.push_front(["place", base - Vector3i(0, 1, 0), World.STONE])
		S.BUILD:
			if digging:
				return
			if pend_t > 0.0:
				return
			var anchor := site if site.x >= 0 else base
			if Vector3(feet_cell()).distance_to(Vector3(anchor)) > 12.0:
				if anchor == base:
					state = S.GO_HOME
					return
				if path_i < path_cells.size():
					return
				if _request(m, w, Pathfinder.GOAL_CELL, anchor, true) < 0:  # chantier injoignable
					proj_fail += 1
					if proj_fail >= 3:
						_abort_project()
				return
			var has_work := _has_build_work(m, w)
			if not has_work and tasks.is_empty():
				if project != "":
					_finish_project()
				elif not base_done and stats.built >= 20:
					base_done = true
					Skills.success(skill_mem, "fonder_base", clock)
				if _try_project(m, w):
					return
			if (build_budget <= 0 and project == "") or not has_work:
				_clear_path()
				state = S.SEEK
				return
			if path_i < path_cells.size():
				return  # il marche vers le point d'accès
			if task_t <= 0.0:
				_do_task(m, w)

func _find_ore(m: Node, w: World) -> Vector3i:
	var c := feet_cell()
	var best := Vector3i(-1, -1, -1)
	var best_s := INF
	for z in range(maxi(c.z - ORE_R, 1), mini(c.z + ORE_R, World.SZ - 2) + 1):
		for y in range(maxi(c.y - ORE_RY, 1), mini(c.y + ORE_RY, World.SY - 2) + 1):
			var row := World.SX * (y + World.SY * z)
			for x in range(maxi(c.x - ORE_R, 1), mini(c.x + ORE_R, World.SX - 2) + 1):
				var id: int = w.blocks[row + x]
				if id != World.COAL and id != World.IRON and id != World.COPPER and id != World.CRYSTAL:
					continue
				var o := Vector3i(x, y, z)
				if absi(x - base.x) + absi(z - base.z) + absi(y - base.y) * 1.5 > ROAM:
					continue
				if banned.get(o, -1.0) > clock or m.ore_claimed(o, self):
					continue
				var s := float(absi(x - c.x) + absi(z - c.z)) + absi(y - c.y) * 1.5 + life.ore_bonus(id)
				if life.is_avoided(o, clock):
					s += 12.0  # il y est mort récemment
				if s >= best_s:
					continue
				var exposed := false
				for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
					if World.KIND[w.get_v(o + d)] == World.K_AIR:
						exposed = true
						break
				if not exposed:
					s += 5.0
				if Pathfinder.lava_near(w, o):
					continue
				if s < best_s:
					best_s = s
					best = o
	return best

func _random_target(w: World, c: Vector3i) -> Vector3i:
	for i in 14:
		var x := clampi(base.x + randi_range(-14, 14), 2, World.SX - 3)
		var z := clampi(base.z + randi_range(-10, 10), 2, World.SZ - 3)
		for y in range(mini(base.y + 5, World.SY - 3), maxi(base.y - 7, 2), -1):
			var t := Vector3i(x, y, z)
			if Pathfinder.standable(w, t, body_cells()) and banned.get(t, -1.0) <= clock:
				return t
	return Vector3i(-1, -1, -1)

# ---------------------------------------------------------------- base
## Choisit un plan (personnalité + terrain) et une orientation, puis liste les tâches de construction.
## Sans `m` (anciens appels) : cabane orientée par défaut, sans test de terrain.
func plan_base(m: Node = null) -> void:
	tasks.clear()
	spare_chests.clear()
	extra_chests.clear()
	var t: Dictionary = brain.t if brain else {}
	var choice := {"name": "cabane", "rot": 0}
	if m != null:
		var found := false
		for nm in Blueprints.ranked(t, hash(mname)):
			var best_cost := 1e9
			for rot in 4:
				var cost := _site_cost(m, m.world, nm, rot)
				if cost >= 0.0 and cost + float(((rot + hash(mname)) & 3)) * 0.1 < best_cost:
					best_cost = cost + float(((rot + hash(mname)) & 3)) * 0.1
					choice = {"name": nm, "rot": rot}
					found = true
			if found:
				break
	bp = choice.name
	bp_rot = choice.rot
	var plan := Blueprints.make_tasks(bp, bp_rot, base, inv.get(World.BRICK, 0) > 0)
	tasks = plan.tasks
	spare_chests = plan.chests.slice(1)
	base_total = maxi(tasks.size(), 1)

## Coût de construction d'un plan à cet endroit, ou -1 si le terrain ne convient pas (lave, eau, coffre, zone sûre, hors monde).
func _site_cost(m: Node, w: World, nm: String, rot: int, at := NOWHERE) -> float:
	var cost := 0.0
	var origin := base if at.x < 0 else at
	for e in Blueprints.cells(nm, rot):
		var c: Vector3i = origin + (e[0] as Vector3i)
		if not w.in_bounds(c) or c.y < 2 or c.y > World.SY - 3:
			return -1.0
		var id := w.get_v(c)
		if id == World.LAVA or id == World.BEDROCK or id == World.CHEST or World.KIND[id] == World.K_FLUID:
			return -1.0
		if m.is_safe_zone(Vector3(c)) or (m.hub_n and m.hub_n.is_protected(c)):
			return -1.0
		var ch: String = e[1]
		if ch in "#DB":
			cost += 1.0 if id == World.AIR else 0.0
		elif World.KIND[id] == World.K_CUBE:
			cost += 0.5
	return cost

## Coincé dans un bloc : il casse ce qui l'entoure, ou se replace sur la case libre la plus proche.
func _unstuck(m: Node, w: World, c: Vector3i) -> void:
	_clear_path()
	digging = false
	var best := NOWHERE
	var bd := INF
	for dy in range(-2, 4):
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				var t := c + Vector3i(dx, dy, dz)
				var d := float(dx * dx + dz * dz + dy * dy * 2)
				if d < bd and Pathfinder.standable(w, t, body_cells()):
					bd = d
					best = t
	if best.x >= 0:
		pos = Vector3(best) + Vector3(0.5, 0.0, 0.5)
		position = pos
		vel = Vector3.ZERO
		return
	for i in body_cells():  # aucune case libre : il se dégage
		var cc := c + Vector3i(0, i, 0)
		if Pathfinder.solid(w, cc) and Pathfinder.diggable(w, cc):
			m.edit_break(cc, false)

## Le but du moment décide de ce qu'il fait ensuite ; renvoie true s'il a changé d'état.
func _life_goal(m: Node, w: World) -> bool:
	if life.goal == "" or life.done(self, m, clock):
		life.choose(self, m, clock)
		_set_status(life.label())
	var st: Dictionary = m.chests.get(chest, {})
	match life.goal:
		"construire":
			if _has_build_work(m, w):
				state = S.GO_HOME
				_clear_path()
				return true
		"equiper":
			if int(st.get(World.COAL, 0)) + int(st.get(World.TORCH, 0)) > 0 and not at_base():  # il rentre fabriquer des torches
				state = S.GO_HOME
				_clear_path()
				return true
		"explorer":
			if state != S.EXPLORE:
				state = S.EXPLORE
				_clear_path()
				return true
		"chercher":
			if state != S.SEARCH:
				_start_search(String(life.arg.get("who", "player")), String(life.arg.get("mode", "voir")), w)
				return true
	return false

## Part à la recherche de quelqu'un : dernier endroit où il l'a vu, puis le spawn, puis des zones au hasard.
func _start_search(id: String, mode: String, w: World) -> void:
	search_mode = mode
	search_pts = []
	if sightings.has(id) and clock - float(sightings[id][1]) < 600.0:
		search_pts.append(sightings[id][0])
	search_pts.append(w.spawn)
	for i in 4:
		var t := _random_target(w, feet_cell())
		if t.x >= 0:
			search_pts.append(Vector3(t))
	search_until = clock + 180.0
	last_known = Vector3.INF
	_enter(S.SEARCH, id)

## Il manque de pierre pour le chantier en cours (sac + coffre < besoin, 30 max).
func _needs_stone(m: Node) -> bool:
	if tasks.size() < 6 or project == "cache":
		return false
	var need := 0
	for t in tasks:
		if t[0] == "place" and t[2] in [World.STONE, World.DIRT, World.BRICK]:
			need += 1
	var st: Dictionary = m.chests.get(chest, {})
	var have := _blocks() + int(st.get(World.STONE, 0)) + int(st.get(World.DIRT, 0))
	return have < mini(need, 30)

## Pierre exposée toute proche (rayon 7), hors des murs de ses maisons et de la zone sûre.
func _find_stone(m: Node, w: World) -> Vector3i:
	var c := feet_cell()
	var best := NOWHERE
	var bd := INF
	for x in range(c.x - 7, c.x + 8):
		for z in range(c.z - 7, c.z + 8):
			for y in range(c.y - 3, c.y + 4):
				var o := Vector3i(x, y, z)
				if w.get_v(o) != World.STONE or banned.get(o, -1.0) > clock:
					continue
				var d := absf(x - c.x) + absf(z - c.z) + absf(y - c.y) * 1.5
				if d >= bd or home_dist(Vector3(o)) < 6.0:
					continue
				var exposed := false
				for dd in Pathfinder.DIRS + [Vector3i(0, 1, 0)]:
					if World.KIND[w.get_v(o + dd)] == World.K_AIR:
						exposed = true
						break
				if not exposed or not Pathfinder.diggable(w, o) or Pathfinder.lava_near(w, o) or m.is_safe_zone(Vector3(o)):
					continue
				bd = d
				best = o
	return best

## Cellule où se tenir pour agir sur c (à <= 1,9 bloc du centre de la case, debout, chemin possible), ou (-1,-1,-1).
func _stand_for(w: World, c: Vector3i, placing: bool) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var bd := 1e9
	var f := feet_cell()
	var tc := Vector3(c) + Vector3(0.5, 0.5, 0.5)
	var h := body_cells()
	for dy in range(-2, 2):
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				var s := c + Vector3i(dx, dy, dz)
				if placing and (s == c or s + Vector3i(0, 1, 0) == c):
					continue
				if (Vector3(s) + Vector3(0.5, hh * 0.53, 0.5)).distance_to(tc) > 1.9:
					continue
				if not Pathfinder.standable(w, s, h):
					continue
				var d := float(absi(s.x - f.x) + absi(s.z - f.z) + absi(s.y - f.y) * 2)
				if d < bd:
					bd = d
					best = s
	return best

func _task_fail() -> void:
	var t: Array = tasks.pop_front()
	var n: int = t[3] if t.size() > 3 else 0
	if project != "" and n >= 2:
		proj_task_fail += 1
		if proj_task_fail >= 6:  # trop de tâches impossibles : il abandonne le projet (et recule avant de réessayer)
			tasks.append(t)
			call_deferred("_abort_project")
			return
	if n < 2:
		t = [t[0], t[1], t[2], n + 1]
		tasks.append(t)

func _face(m: Node, c: Vector3i) -> void:
	var sd: float = (Vector3(c) + Vector3(0.5, 0.5, 0.5) - pos).dot(m.screen_right())
	if absf(sd) > 0.05:
		facing = 1 if sd > 0 else -1

func _material(m: Node, id: int, take: bool) -> int:
	var store: Dictionary = m.chests.get(chest, {})
	var opts := [World.TORCH] if id == World.TORCH else ([World.BRICK, World.STONE, World.DIRT] if id == World.BRICK else ([World.DIRT, World.STONE] if id == World.DIRT else [World.STONE, World.DIRT]))
	for o in opts:
		if inv.get(o, 0) > 0:
			if take: inv[o] -= 1
			return o
		if store.get(o, 0) > 0:
			if take: store[o] -= 1
			return o
	if id == World.TORCH:  # craft 4 torches from 1 coal
		for src in [inv, store]:
			if src.get(World.COAL, 0) > 0:
				if take:
					src[World.COAL] -= 1
					inv[World.TORCH] = inv.get(World.TORCH, 0) + 3
				return World.TORCH
	return -1

## Is the next useful task doable now? Drops the tasks already done.
func _has_build_work(m: Node, w: World) -> bool:
	var n := 0
	while not tasks.is_empty() and n < 400:
		n += 1
		var t: Array = tasks[0]
		var c: Vector3i = t[1]
		var id := w.get_v(c)
		if t[0] == "stash":
			if id != World.CHEST:
				tasks.pop_front()
				continue
			return true
		if t[0] == "dig":
			if World.KIND[id] == World.K_AIR or World.KIND[id] == World.K_FLUID or id == World.TORCH or World.HARD[id] < 0.0:
				tasks.pop_front()
				continue
			return true
		if World.KIND[id] == World.K_CUBE or id == World.TORCH or id == World.LAVA:
			if t[2] == World.CHEST and id == World.CHEST:
				_own_chest(m, w, c)
			tasks.pop_front()
			continue
		if t[2] == World.CHEST:
			return true
		if _material(m, t[2], false) >= 0:
			return true
		# no material: try a later task (e.g. torches when only coal is missing)
		for i in range(1, tasks.size()):
			var t2: Array = tasks[i]
			if t2[0] == "place" and t2[2] != t[2] and _material(m, t2[2], false) >= 0 and w.get_v(t2[1]) == World.AIR:
				tasks.remove_at(i)
				tasks.push_front(t2)
				return true
		return false
	return false

## Un coffre posé : le premier devient le coffre principal, les autres des coffres de réserve.
func _own_chest(m: Node, w: World, c: Vector3i) -> void:
	for k in caches:
		if k.chest == c:  # coffre enterré : ne devient jamais le coffre principal
			if not m.chests.has(c):
				m.chests[c] = {}
			m.chest_owner[c] = mname
			return
	if w.get_v(chest) != World.CHEST or chest == c:
		chest = c
	elif not (c in extra_chests):
		extra_chests.append(c)
	spare_chests.erase(c)
	if not m.chests.has(c):
		m.chests[c] = {}
	m.chest_owner[c] = mname

## Une tâche à la fois : d'abord se placer à portée réelle (chemin vers une case d'accès), se tourner, puis creuser / poser.
func _do_task(m: Node, w: World) -> void:
	var t: Array = tasks[0]
	var c: Vector3i = t[1]
	task_t = TASK_GAP
	var placing: bool = t[0] == "place"
	var in_body: bool = placing and (feet_cell() == c or feet_cell() + Vector3i(0, 1, 0) == c) and World.KIND[t[2]] == World.K_CUBE
	if in_body or not _in_reach(c, ACT_R):
		var s := _stand_for(w, c, placing)
		if s.x < 0:
			_task_fail()
			return
		if s == feet_cell() and not in_body:
			_task_fail()  # déjà sur la case d'accès mais encore trop loin : on réessaie plus tard
			return
		var r := _request(m, w, Pathfinder.GOAL_CELL, s)
		if r == 0:
			task_t = 0.0
		elif r < 0 or path_cells.is_empty():
			_task_fail()
		return
	_face(m, c)
	build_dist_max = maxf(build_dist_max, (Vector3(c) + Vector3(0.5, 0.5, 0.5)).distance_to(center()))
	if t[0] == "stash":
		_set_status("cache son butin")
		var st: Dictionary = m.chests.get(c, {})
		for id in VALUABLES:
			if inv.get(id, 0) > 0:
				st[id] = st.get(id, 0) + inv[id]
				inv[id] = 0
		m.chests[c] = st
		tasks.pop_front()
		pend_t = 0.3
		return
	if t[0] == "dig":
		_set_status("creuse la base")
		build_budget -= 1
		var id := w.get_v(c)
		if World.KIND[id] == World.K_CROSS:
			var drop: int = m.edit_break(c, false)
			if drop >= 0:
				_add(drop)
			pend_t = 0.2  # geste
		else:
			_start_dig(c, w)
		tasks.pop_front()
		return
	_set_status("construit")
	var cur := w.get_v(c)
	if World.KIND[cur] == World.K_CROSS:
		m.edit_break(c, false)
	if not m.cell_free_of_bodies(c, t[2]):
		var f := feet_cell()  # souvent son propre corps qui déborde de 2 cm : il se recentre sur sa case
		pos.x = f.x + 0.5
		pos.z = f.z + 0.5
		position = pos
		if not m.cell_free_of_bodies(c, t[2]):
			_task_fail()
			return
	if t[2] != World.CHEST and _material(m, t[2], false) < 0:
		return
	pend = [c, t[2]]
	pend_t = PLACE_T
	vel.x = 0.0
	vel.z = 0.0

## Fin du geste de pose : le bloc n'est posé que si le mineur est toujours à portée.
func _pend_step(dt: float, m: Node, w: World) -> void:
	pend_t -= dt
	if pend_t > 0.0 or pend.is_empty():
		pend_t = maxf(pend_t, 0.0) if not pend.is_empty() else 0.0
		return
	pend_t = 0.0
	var c: Vector3i = pend[0]
	var want: int = pend[1]
	pend = []
	if tasks.is_empty() or tasks[0][1] != c or not _in_reach(c, ACT_R + 0.1):
		return
	build_budget -= 1
	var item := want
	if item != World.CHEST:
		item = _material(m, want, true)
		if item < 0:
			return
	build_dist_max = maxf(build_dist_max, (Vector3(c) + Vector3(0.5, 0.5, 0.5)).distance_to(center()))
	if m.edit_place(c, item):
		tasks.pop_front()
		stats.built += 1
		if item == World.CHEST:
			_own_chest(m, w, c)
	elif item != World.CHEST:
		_add(item)  # rend le matériau

static func _fill(store: Dictionary) -> int:
	var n := 0
	for k in store:
		n += int(store[k])
	return n

func _deposit(m: Node, w: World) -> void:
	if w.get_v(chest) != World.CHEST or not m.chests.has(chest):
		return
	_set_status("dépose")
	var store: Dictionary = m.chests[chest]
	if _fill(store) >= CHEST_CAP:  # plein : coffre de réserve (déjà posé, sinon on prévoit d'en poser un)
		var other := false
		for c in extra_chests:
			if w.get_v(c) == World.CHEST and m.chests.has(c) and _fill(m.chests[c]) < CHEST_CAP:
				store = m.chests[c]
				other = true
				break
		if not other and not spare_chests.is_empty() and not tasks.any(func(x): return x[2] == World.CHEST and x[1] == spare_chests[0]):
			var c: Vector3i = spare_chests[0]
			tasks.push_front(["place", c, World.CHEST])
			tasks.push_front(["dig", c, 0])
	for id in inv.keys():
		var n: int = inv[id]
		if n <= 0 or (project == "cache" and id in VALUABLES):
			continue
		store[id] = store.get(id, 0) + n
		if id in ORES:
			stats.deposited += n
	for id in inv.keys():
		if not (project == "cache" and id in VALUABLES):
			inv.erase(id)
	var coal: int = int(store.get(World.COAL, 0))  # il refait le plein de torches (1 charbon = 4)
	var tk: int = int(store.get(World.TORCH, 0))
	while inv.get(World.TORCH, 0) < 8 and (tk > 0 or coal > 0):
		if tk > 0:
			var k := mini(tk, 8 - inv.get(World.TORCH, 0))
			tk -= k
			inv[World.TORCH] = inv.get(World.TORCH, 0) + k
		else:
			coal -= 1
			inv[World.TORCH] = inv.get(World.TORCH, 0) + 4
	store[World.COAL] = coal
	store[World.TORCH] = tk

# ---------------------------------------------------------------- plusieurs maisons, caches enterrées, refuge
func all_bases() -> Array:
	var a: Array = [base]
	for h in homes:
		a.append(h.base)
	return a

## Distance à la maison la plus proche (active ou non).
func home_dist(p: Vector3) -> float:
	var d := INF
	for b in all_bases():
		d = minf(d, p.distance_to(Vector3(b)))
	return d

func _home_dict() -> Dictionary:
	return {"base": base, "chest": chest, "extra": extra_chests.duplicate(), "spare": spare_chests.duplicate(), "bp": bp, "rot": bp_rot, "total": base_total}

func _load_home(h: Dictionary) -> void:
	base = h.base
	chest = h.chest
	extra_chests = (h.extra as Array).duplicate()
	spare_chests = (h.spare as Array).duplicate()
	bp = h.bp
	bp_rot = h.rot
	base_total = h.total

func _swap_home(i: int) -> void:
	var cur := _home_dict()
	_load_home(homes[i])
	homes[i] = cur
	_clear_path()

## Passe sur la maison la plus proche (hors chantier) : dépôt, rayon d'action et minage se font autour d'elle.
func _nearest_home_swap() -> void:
	if homes.is_empty() or not tasks.is_empty() or project != "":
		return
	var me := Vector3(feet_cell())
	var best := -1
	var bd := me.distance_to(Vector3(base)) - 6.0
	for i in homes.size():
		var d := me.distance_to(Vector3(homes[i].base))
		if d < bd:
			bd = d
			best = i
	if best >= 0:
		_swap_home(best)

## Plus de minerai autour de la maison active : il part travailler autour de l'autre maison (la plus riche).
func _richer_home_swap(m: Node) -> bool:
	if homes.is_empty() or not tasks.is_empty() or project != "":
		return false
	var bs: int = m._ore_score(base)
	var best := -1
	for i in homes.size():
		var sc: int = m._ore_score(homes[i].base)
		if sc > bs:
			bs = sc
			best = i
	if best < 0:
		return false
	_swap_home(best)
	return true

## Maison vers laquelle fuir : plus proche de moi que de la menace (sinon on fuit au hasard).
func _refuge_cell(from: Vector3) -> Vector3i:
	if clock < refuge_ban:
		return NOWHERE
	var best := NOWHERE
	var bs := -INF
	for b in all_bases():
		var hc := Vector3(b) + Vector3(0.5, 0.5, 0.5)
		var dme := center().distance_to(hc)
		var dth := from.distance_to(hc)
		if dme > 40.0 or (dme > 3.0 and dth < dme * 1.1 + 2.0):
			continue
		if dth - dme > bs:
			bs = dth - dme
			best = b
	return best

func _arrive_refuge(m: Node, rf: Vector3i) -> void:
	if rf != base and tasks.is_empty() and project == "":
		for i in homes.size():
			if homes[i].base == rf:
				_swap_home(i)
				break
	_take_blocks(m, 12)
	if _blocks() >= 5:
		Skills.success(skill_mem, "refuge", clock)
		_enter(S.HIDE, fight_id)
	else:
		Skills.failure(skill_mem, "refuge", clock)
		refuge_ban = clock + 15.0  # pas de blocs : inutile de rester ici

## Prend des blocs dans le coffre de la maison (jusqu'à n en tout dans le sac).
func _take_blocks(m: Node, n: int) -> void:
	var st: Dictionary = m.chests.get(chest, {})
	for id in [World.STONE, World.DIRT]:
		var k: int = mini(int(st.get(id, 0)), n - _blocks())
		if k > 0:
			st[id] -= k
			inv[id] = inv.get(id, 0) + k

static func _valuables(st: Dictionary) -> int:
	return int(st.get(World.CRYSTAL, 0)) * 3 + int(st.get(World.IRON, 0))

## Sort du coffre le butin à cacher (tout le cristal, 60 % du fer et du cuivre).
func _withdraw_loot(m: Node) -> void:
	var st: Dictionary = m.chests.get(chest, {})
	for id in VALUABLES:
		var k := int(st.get(id, 0)) if id == World.CRYSTAL else int(ceil(float(st.get(id, 0)) * 0.6))
		if k > 0:
			st[id] -= k
			inv[id] = inv.get(id, 0) + k

func _abort_project() -> void:
	if project == "annexe" and not homes.is_empty():
		_load_home(homes.pop_back())
		tasks.clear()
	elif project == "cache":
		tasks.clear()
	_finish_project(false)
	project_t = clock + 150.0
	_clear_path()
	state = S.SEEK

func _finish_project(ok := true) -> void:
	if proj_skill != "":
		if ok:
			Skills.success(skill_mem, proj_skill, clock, 60.0)
		else:
			Skills.failure(skill_mem, proj_skill, clock)
	proj_skill = ""
	proj_task_fail = 0
	project = ""
	site = NOWHERE
	proj_fail = 0
	project_t = maxf(project_t, clock + randf_range(90.0, 200.0))

## Décide d'un nouveau projet à la maison, quand tout est construit : cacher du butin, ou fonder une annexe.
func _try_project(m: Node, w: World) -> bool:
	if project != "" or clock < project_t or stats.built < 20 or not tasks.is_empty():
		return false
	if Vector3(feet_cell()).distance_to(Vector3(base)) > 8.0 or w.get_v(chest) != World.CHEST or not m.chests.has(chest):
		return false
	project_t = clock + randf_range(30.0, 70.0)  # pas de nouvelle tentative tout de suite
	var t: Dictionary = brain.t if brain else {}
	var st: Dictionary = m.chests[chest]
	var val := _valuables(st)
	var max_c := 1 + (1 if t.get("greed", 0.5) > 0.6 else 0) + (1 if t.get("caution", 0.5) > 0.7 else 0)
	if val >= 6:
		if caches.size() < max_c and randf() < 0.7 and Skills.ready(skill_mem, "cacher_butin", clock):
			if _skill_try("cacher_butin", plan_cache(m, w)):
				return true
		elif not caches.is_empty() and clock >= visit_t and Skills.ready(skill_mem, "visiter_cache", clock):
			if _skill_try("visiter_cache", plan_visit(m, w)):
				return true
	var max_h := 1 + (1 if (t.get("courage", 0.5) > 0.6 or t.get("greed", 0.5) > 0.6) else 0)
	if homes.size() < max_h and int(st.get(World.STONE, 0)) + int(st.get(World.DIRT, 0)) + _blocks() >= 40 and randf() < 0.6 and Skills.ready(skill_mem, "annexe", clock):
		return _skill_try("annexe", plan_annex(m, w))
	return false

## Enregistre le démarrage d'une compétence (ou son échec immédiat : aucun site, aucun emplacement) ; renvoie ok.
func _skill_try(name: String, ok: bool) -> bool:
	if ok:
		proj_skill = name
		Skills.start(skill_mem, name, clock)
	else:
		Skills.failure(skill_mem, name, clock)
	return ok

## Annexe : 2e base à 14-32 blocs, près d'un riche filon ; le sac se remplit de pierre dans le coffre principal.
func plan_annex(m: Node, w: World) -> bool:
	var t: Dictionary = brain.t if brain else {}
	var nm := "bunker" if t.get("caution", 0.5) > 0.65 else "relais"
	var others: Array = all_bases()
	for o in m.miners:
		if o != self:
			others.append_array((o as Miner).all_bases())
	var best := {}
	var bs := -INF
	var found := 0
	for i in 1500:
		var ang := randf() * TAU
		var rr := randf_range(14.0, 30.0)
		var x := clampi(base.x + int(cos(ang) * rr), 8, World.SX - 9)
		var z := clampi(base.z + int(sin(ang) * rr * 0.75), 8, World.SZ - 9)
		var dd := Vector2(x - base.x, z - base.z).length()
		if dd < 14.0 or dd > 32.0:
			continue
		var near := false
		for b in others:  # distance horizontale d'abord (bon marché)
			if Vector2(x - b.x, z - b.z).length() < 6.0:
				near = true
				break
		if near:
			continue
		var c := NOWHERE
		var bdy := 99
		for y in range(52, 9, -1):  # toutes les hauteurs : on garde la cavité la plus proche du niveau de la base
			var tc := Vector3i(x, y, z)
			if absi(y - base.y) < bdy and Pathfinder.standable(w, tc, body_cells()) and w.get_v(tc + Vector3i(0, 2, 0)) == World.AIR:
				c = tc
				bdy = absi(y - base.y)
		if c.x < 0 or not _dry_around(w, c) or m.is_safe_zone(Vector3(c)) or m._near_spawn_room(c):
			continue
		var rot_best := -1
		var cb := 1e9
		for rot in 4:
			var cost := _site_cost(m, w, nm, rot, c)
			if cost >= 0.0 and cost < cb:
				cb = cost
				rot_best = rot
		if rot_best < 0:
			continue
		var sc := float(m._ore_score(c)) - cb * 0.5 - dd * 0.2 - float(bdy) * 0.5
		found += 1
		if sc > bs:
			bs = sc
			best = {"c": c, "rot": rot_best}
		if found >= 6:
			break
	if best.is_empty():
		return false
	_take_blocks(m, 70)
	homes.append(_home_dict())
	base = best.c
	chest = NOWHERE
	extra_chests = []
	bp = nm
	bp_rot = best.rot
	var plan := Blueprints.make_tasks(bp, bp_rot, base, inv.get(World.BRICK, 0) > 0)
	tasks = plan.tasks
	spare_chests = plan.chests.slice(1)
	base_total = maxi(tasks.size(), 1)
	project = "annexe"
	site = NOWHERE
	proj_fail = 0
	state = S.GO_HOME
	_clear_path()
	_set_status("part fonder un avant-poste")
	return true

## Pas de liquide dans un volume de 7x5x5 autour de c.
func _dry_around(w: World, c: Vector3i) -> bool:
	for x in range(c.x - 3, c.x + 4):
		for z in range(c.z - 3, c.z + 4):
			for y in range(c.y - 1, c.y + 5):
				var id := w.get_b(x, y, z)
				if World.KIND[id] == World.K_FLUID:
					return false
	return true

## Le tunnel est-il creusable ? a = cellule debout (accès), d = direction, n = longueur ; coffre à a + d*(n+1).
func _cache_ok(m: Node, w: World, a: Vector3i, d: Vector3i, n: int, h: int) -> bool:
	for k in range(1, n + 2):
		var t := a + d * k
		for j in (h if k <= n else 1):
			var c := t + Vector3i(0, j, 0)
			var id := w.get_v(c)
			if World.KIND[id] != World.K_CUBE or World.HARD[id] < 0.0 or id == World.CHEST:
				return false
			if m.is_safe_zone(Vector3(c)) or (m.hub_n and m.hub_n.is_protected(c)):
				return false
		if k <= n and World.KIND[w.get_v(t + Vector3i(0, -1, 0))] != World.K_CUBE:
			return false  # il faut un sol dans le tunnel
		for dx in range(-1, 2):
			for dy in range(-1, h + 1):
				for dz in range(-1, 2):
					var q := t + Vector3i(dx, dy, dz)
					var qid := w.get_v(q)
					if World.KIND[qid] == World.K_FLUID or qid == World.CHEST or qid == World.TORCH or qid == World.LAVA:
						return false
	var cc := a + d * (n + 1)  # le coffre ne doit toucher aucun vide (sinon il se verrait)
	for dd in [d, Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(-d.z, 0, d.x), Vector3i(d.z, 0, -d.x)]:
		if World.KIND[w.get_v(cc + dd)] != World.K_CUBE:
			return false
	return true

## Coffre enterré : tunnel de 3-5 blocs dans la roche, coffre au fond, butin rangé, puis tunnel rebouché à l'identique.
func plan_cache(m: Node, w: World) -> bool:
	var h := body_cells()
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	var spots: Array = all_bases()
	for k in caches:
		spots.append(k.chest)
	for i in 400:
		var x := clampi(base.x + randi_range(-16, 16), 4, World.SX - 5)
		var z := clampi(base.z + randi_range(-12, 12), 4, World.SZ - 5)
		var a := NOWHERE
		for y in range(mini(base.y + 6, World.SY - 4), maxi(base.y - 8, 3), -1):
			var tc := Vector3i(x, y, z)
			if Pathfinder.standable(w, tc, h):
				a = tc
				break
		if a.x < 0 or Vector2(a.x - base.x, a.z - base.z).length() < 5.0:
			continue
		dirs.shuffle()
		for d in dirs:
			var n := randi_range(3, 5)
			var cc: Vector3i = a + d * (n + 1)
			var near := false
			for b in spots:
				if Vector3(cc).distance_to(Vector3(b)) < 5.0:
					near = true
			if near or not _cache_ok(m, w, a, d, n, h):
				continue
			_start_cache(m, w, a, d, n, h, cc)
			return true
	return false

func _start_cache(m: Node, w: World, a: Vector3i, d: Vector3i, n: int, h: int, cc: Vector3i) -> void:
	var ids: Array = []
	for k in range(1, n + 1):
		for j in h:
			var c := a + d * k + Vector3i(0, j, 0)
			var id := w.get_v(c)
			ids.append([c, id if id == World.STONE or id == World.DIRT else World.STONE])
	caches.append({"chest": cc, "mouth": a, "ids": ids, "visit": clock})
	_take_blocks(m, 16)
	_withdraw_loot(m)
	var tk: Array = []
	for e in ids:
		tk.append(["dig", e[0], 0])
	tk.append(["dig", cc, 0])
	tk.append(["place", cc, World.CHEST])
	tk.append(["stash", cc, 0])
	for i in range(ids.size() - 1, -1, -1):
		tk.append(["place", ids[i][0], ids[i][1]])
	tasks = tk
	base_total = maxi(base_total, 1)
	project = "cache"
	site = a
	proj_fail = 0
	_set_status("va cacher du butin")

## Revisite une cache : rouvre le tunnel, range le butin, rebouche.
func plan_visit(m: Node, w: World) -> bool:
	var ok: Array = caches.filter(func(k): return w.get_v(k.chest) == World.CHEST)
	if ok.is_empty():
		return false
	var k: Dictionary = ok[randi() % ok.size()]
	k.visit = clock
	visit_t = clock + randf_range(120.0, 240.0)
	_take_blocks(m, 16)
	_withdraw_loot(m)
	var tk: Array = []
	for e in k.ids:
		tk.append(["dig", e[0], 0])
	tk.append(["stash", k.chest, 0])
	for i in range((k.ids as Array).size() - 1, -1, -1):
		tk.append(["place", k.ids[i][0], k.ids[i][1]])
	tasks = tk
	project = "cache"
	site = k.mouth
	proj_fail = 0
	_set_status("va voir sa cache")
	return true

# ---------------------------------------------------------------- save
func to_dict() -> Dictionary:
	return {"name": mname, "color": color, "pos": pos, "base": base, "chest": chest, "inv": inv.duplicate(),
		"tasks": tasks.duplicate(true), "health": health, "stats": stats.duplicate(),
		"personality": personality, "species": species, "base_total": base_total, "bp": bp, "bp_rot": bp_rot,
		"spare_chests": spare_chests.duplicate(), "extra_chests": extra_chests.duplicate(),
		"homes": homes.duplicate(true), "caches": caches.duplicate(true), "project": project, "site": site, "visit_t": visit_t, "skills": skill_mem.duplicate(true), "life": life.to_dict(), "brain": brain.to_dict() if brain else {}}

func from_dict(d: Dictionary) -> void:
	mname = d.get("name", "Mineur")
	color = d.get("color", Color.WHITE)
	pos = d.get("pos", Vector3.ZERO)
	position = pos
	base = d.get("base", Vector3i.ZERO)
	chest = d.get("chest", Vector3i(-1, -1, -1))
	inv = d.get("inv", {}).duplicate()
	tasks = d.get("tasks", []).duplicate(true)
	health = d.get("health", 100.0)
	stats.merge(d.get("stats", {}), true)
	personality = d.get("personality", personality)
	species = d.get("species", 0)
	base_total = d.get("base_total", maxi(tasks.size(), 1))
	bp = d.get("bp", "")
	bp_rot = d.get("bp_rot", 0)
	spare_chests = d.get("spare_chests", []).duplicate()
	extra_chests = d.get("extra_chests", []).duplicate()
	homes = d.get("homes", []).duplicate(true)
	caches = d.get("caches", []).duplicate(true)
	project = d.get("project", "")
	site = d.get("site", NOWHERE)
	visit_t = d.get("visit_t", 0.0)
	if d.has("skills"):
		skill_mem = (d.skills as Dictionary).duplicate(true)
	make_brain()
	if d.has("life"):
		life.from_dict(d.life)
	if d.has("brain") and not (d.brain as Dictionary).is_empty():
		brain.from_dict(d.brain)

# ---------------------------------------------------------------- brain: perception -> decision -> behaviour
## Honest perception (same rules as the player: voxel line of sight, limited range).
func percept(m: Node, w: World) -> Dictionary:
	var others: Array = []
	var now: float = m.game_t
	for e in m.entities():
		var id: String = e[0]
		var n: Player = e[1]
		if n == self:
			continue
		var dist := center().distance_to(n.center())
		var vis: bool = dist < VIEW and m.sees(self, n)
		var atk_me: bool = m.attacker_of(mname, 3.0).has(id)
		if atk_me and clock - float(last_attacked.get(id, -99.0)) > 6.0:
			last_attacked[id] = clock
			life.remember("attacked", id, feet_cell(), 0.6, clock)
		if atk_me:
			vis = true  # you feel the hit
		seen[id] = vis
		if vis:
			brain.on_event("seen", id, {"pos": n.pos}, now)
			sightings[id] = [n.pos, clock]
		var victim: String = m.victim_of(id, 3.0)
		others.append({"id": id, "visible": vis, "dist": dist, "hp": n.health, "dmg": Player.DMG, "attacking_me": atk_me,
			"attacking": "me" if victim == mname else victim, "near_my_base": home_dist(n.pos) < 7.0,
			"in_safe_zone": m.is_safe_zone(n.center()), "danger_near": n.in_lava or Pathfinder.lava_near(w, n.feet_cell()), "pos": n.pos})
	ore_t -= 0.4
	if ore_t <= 0.0:
		ore_t = 2.0
		ore_near = _find_ore(m, w).x >= 0
	var c := feet_cell()
	var danger := 1.0 if in_lava else (0.5 if Pathfinder.lava_near(w, c) else 0.0)
	var built := 1.0 if project == "cache" else 1.0 - float(tasks.size()) / float(maxi(base_total, 1))
	return {"hp": health, "dmg": Player.DMG, "inv": inv, "inv_fill": clampf(float(carry()) / CARRY_MAX, 0.0, 1.0),
		"at_base": at_base(), "base_built": clampf(built, 0.0, 1.0), "ore_near": ore_near, "danger": danger,
		"in_safe_zone": m.is_safe_zone(center()), "others": others}

func brain_tick(m: Node, w: World) -> void:
	m.sync_from_agent(self)
	if not sp_done:
		sp_done = true
		_species_traits()
	decision = brain.decide(percept(m, w), m.game_t)
	_apply_opt(decision)
	for sg in decision.signals:
		queue_signal("jump" if sg.signal == "jump_twice" else "crouch")
	for it in decision.intents:
		m.miner_intent(self, it)

func _enter(s: int, tgt: String) -> void:
	if state == s and fight_id == tgt:
		return
	if state == S.HIDE and s != S.HIDE:
		hidden = false
	state = s
	fight_id = tgt
	digging = false
	search_n = 0
	replan_t = 0.0
	react_t = randf_range(0.2, 0.4)
	_clear_path()
	think_t = 0.0

func _apply_opt(d: Dictionary) -> void:
	if state == S.FLEE:
		return  # lava / water reflex first
	if clock < zombie_t:
		return  # il fuit un zombie : le cerveau ne le rappelle pas
	var tgt: String = d.target
	var o: int = d.opt
	if state == S.RUN and clock < flee_until and o != Brain.Opt.ATTACK and o != Brain.Opt.DEFEND:
		return  # il a décidé de fuir : il court jusqu'au bout au lieu de changer d'avis à chaque réflexion
	if state == S.FIGHT and (o == Brain.Opt.ATTACK or o == Brain.Opt.DEFEND) and tgt != fight_id and focus_ok:
		return  # focus : il garde sa cible tant qu'elle est vivante et pas perdue de vue
	match d.opt:
		Brain.Opt.FLEE:
			_start_run(tgt)
		Brain.Opt.HIDE:
			if state == S.HIDE or _blocks() >= 5:
				_enter(S.HIDE, tgt)
			else:
				_start_run(tgt)
		Brain.Opt.ATTACK, Brain.Opt.DEFEND:
			_enter(S.FIGHT, tgt)
			focus_t = clock
		Brain.Opt.FOLLOW:
			_enter(S.FOLLOW, tgt)
		Brain.Opt.VISIT:
			if state != S.SOCIAL or fight_id != tgt:
				if digging:
					digging = false
				_enter(S.SOCIAL, tgt)
		Brain.Opt.SOCIALIZE, Brain.Opt.TRADE:
			_enter(S.SOCIAL, tgt)
		Brain.Opt.IDLE:
			if state in [S.SEEK, S.EXPLORE] and not digging:
				_enter(S.PAUSE, "")
				pause_t = randf_range(1.5, 4.0)
		Brain.Opt.RETURN_BASE, Brain.Opt.BUILD:
			if state in SOCIAL_STATES:
				_enter(S.GO_HOME, "")
			elif state in [S.SEEK, S.EXPLORE, S.IDLE] and not digging:
				state = S.GO_HOME
				_clear_path()
		_:
			if state in SOCIAL_STATES and state != S.PAUSE:
				_enter(S.IDLE, "")

## Le caractère dépend aussi du corps : le costaud ose, le fragile se méfie, le rapide fuit en confiance, le lent évite la bagarre.
func _species_traits() -> void:
	var sp: Dictionary = DMSettings.SPECIES[clampi(species, 0, DMSettings.SPECIES.size() - 1)]
	var t: Dictionary = brain.t
	var hp: float = sp.hp
	t.courage = clampf(t.courage + (hp - 100.0) / 500.0, 0.0, 1.0)
	t.aggression = clampf(t.aggression + (hp - 100.0) / 700.0 + (0.1 if sp.reach >= 6.0 else 0.0), 0.0, 1.0)
	t.caution = clampf(t.caution + (100.0 - hp) / 400.0 + (0.1 if float(sp.speed) < 4.5 else 0.0), 0.0, 1.0)
	t.greed = clampf(t.greed + (float(sp.mine) - 1.0) * 0.2, 0.0, 1.0)

func _start_run(tgt: String) -> void:
	if state != S.RUN:
		flee_until = clock + 5.0
		flee_goal = Vector3i(-1, -1, -1)
		flee_fail = 0
	_enter(S.RUN, tgt)

## Focus valide : cible encore active et vue il y a moins de 8 s.
var focus_t := 0.0
var focus_ok: bool:
	get:
		return fight_id != "" and clock - focus_t < 8.0

func _blocks() -> int:
	return inv.get(World.STONE, 0) + inv.get(World.DIRT, 0)

func _cell_of(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x), floori(p.y + 0.05), floori(p.z))

func _think_social(m: Node, w: World) -> void:
	var e: Player = m.entity(fight_id)
	var nm: String = m.display_name(fight_id)
	var vis: bool = e != null and seen.get(fight_id, false)
	if vis:
		last_known = e.pos
	replan_t -= THINK
	match state:
		S.PAUSE:
			_set_status("traîne")
			pause_t -= THINK
			if pause_t <= 0.0:
				state = S.IDLE
		S.FIGHT:
			if e == null or e.health <= 0.0:
				_enter(S.IDLE, "")
				return
			var d := center().distance_to(e.center())
			if vis:
				focus_t = clock
			if vis and d <= Player.MELEE - 0.3:
				_set_status("frappe " + nm)
				_clear_path()
				return
			if not vis and last_known == Vector3.INF:
				_enter(S.IDLE, "")
				return
			_set_status(("attaque " if vis else "cherche ") + nm)
			if digging:
				return
			if not vis and path_done() and pos.distance_to(last_known) < 1.5:
				# lost: search around the last known position, then give up
				search_n += 1
				if search_n > 3:
					last_known = Vector3.INF
					_enter(S.IDLE, "")
					return
				last_known += Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
				replan_t = 0.0
			if path_done() or replan_t <= 0.0:
				replan_t = randf_range(0.7, 1.1)
				_request(m, w, Pathfinder.GOAL_CELL, _cell_of(last_known), true)
		S.SEARCH:
			if e == null or e.health <= 0.0 or clock > search_until or search_pts.is_empty():
				life.goal_until = clock
				_enter(S.IDLE, "")
				return
			if vis:  # trouvé : il fait ce qu'il voulait (attaquer hors zone sûre, suivre, ou simplement venir à lui)
				life.goal_until = clock
				focus_t = clock
				if search_mode == "attaquer" and not m.is_safe_zone(e.center()):
					_enter(S.FIGHT, fight_id)
				elif search_mode == "suivre":
					_enter(S.FOLLOW, fight_id)
				else:
					_enter(S.SOCIAL, fight_id)
				return
			_set_status("cherche " + nm)
			if digging:
				return
			var tp: Vector3 = search_pts[0]
			if path_done() and (pos.distance_to(tp) < 4.0 or replan_t <= 0.0 and pos.distance_to(tp) < 8.0):
				search_pts.pop_front()  # arrivé (ou assez près) : étape suivante
				replan_t = 0.0
			elif path_done() or replan_t <= 0.0:
				replan_t = randf_range(1.5, 2.5)
				if _request(m, w, Pathfinder.GOAL_CELL, _cell_of(tp), true) < 0:
					search_pts.pop_front()  # inaccessible : on passe à la suivante
		S.RUN:
			_set_status("fuit !")
			if digging:
				return
			var from: Vector3 = e.pos if e else (threat_pos if threat_pos != Vector3.INF and clock < zombie_t else pos)
			if e == null and clock >= zombie_t and threat_pos != Vector3.INF:
				threat_pos = Vector3.INF
				_enter(S.IDLE, "")
				return
			var rf := _refuge_cell(from)
			if rf.x >= 0 and Vector2(pos.x - rf.x - 0.5, pos.z - rf.z - 0.5).length() < 1.6 and absf(pos.y - rf.y) < 1.5:
				_arrive_refuge(m, rf)  # arrivé chez lui : prend des blocs et s'enferme
				return
			var near := e != null and center().distance_to(e.center()) < 2.2
			if near and flee_fail >= 3 and brain.t.courage > 0.2:
				_enter(S.FIGHT, fight_id)  # acculé : il se retourne et se bat
				focus_t = clock
				return
			var reached := flee_goal.x >= 0 and Vector2(pos.x - flee_goal.x - 0.5, pos.z - flee_goal.z - 0.5).length() < 1.5
			if reached or (path_done() and replan_t <= 0.0):
				flee_goal = Vector3i(-1, -1, -1)
			if flee_goal.x < 0 and (path_done() or replan_t <= 0.0):
				replan_t = 0.4
				if rf.x >= 0:
					_set_status("fuit vers sa base")
					if _request(m, w, Pathfinder.GOAL_CELL, rf, true) >= 0:
						flee_goal = rf
						return
				for _i in 4:  # destination lointaine ; on en essaie plusieurs si le chemin est impossible
					var t := _away_cell(w, from)
					if t.x >= 0 and _request(m, w, Pathfinder.GOAL_CELL, t, true) >= 0:
						flee_goal = t
						flee_fail = 0
						return
				flee_fail += 1
				flee_until = clock + 5.0 if flee_fail < 3 else flee_until
		S.HIDE:
			_set_status("se cache")
			if digging:
				return
			if hidden:
				return
			if task_t > 0.0:
				return
			task_t = 0.2
			var c := feet_cell()
			var cells := []
			for dd in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				cells.append(c + dd)
				cells.append(c + dd + Vector3i(0, 1, 0))
			cells.append(c + Vector3i(0, 2, 0))
			for cc in cells:
				if World.KIND[w.get_v(cc)] == World.K_CUBE:
					continue
				var it := World.STONE if inv.get(World.STONE, 0) > 0 else World.DIRT
				if inv.get(it, 0) <= 0:
					_enter(S.RUN, fight_id)
					return
				if m.edit_place(cc, it):
					inv[it] -= 1
					return
				elif World.KIND[w.get_v(cc)] != World.K_CUBE:
					_enter(S.RUN, fight_id)  # cannot wall in here (body, protected...)
					return
			hidden = true
		S.FOLLOW, S.SOCIAL:
			if e == null or not m.is_active(fight_id):
				_enter(S.IDLE, "")
				return
			var keep := 3.0 if state == S.FOLLOW else 3.2
			_set_status(("suit " if state == S.FOLLOW else "regarde ") + nm)
			if digging:
				return
			if center().distance_to(e.center()) > keep + 1.0:
				if path_done() or replan_t <= 0.0:
					replan_t = randf_range(0.8, 1.4)
					_request(m, w, Pathfinder.GOAL_CELL, _cell_of(last_known if last_known != Vector3.INF else e.pos), true)
			else:
				_clear_path()
				vel.x = 0.0
				vel.z = 0.0

## A standable cell 6-10 blocks away from `from` (fleeing).
func _away_cell(w: World, from: Vector3) -> Vector3i:
	var dir := pos - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	var best := Vector3i(-1, -1, -1)
	var bd := -1.0
	for i in 10:
		var a := randf_range(-0.9, 0.9)
		var p := pos + dir.rotated(Vector3.UP, a) * randf_range(12.0, 20.0)
		var c := Vector3i(clampi(floori(p.x), 2, World.SX - 3), floori(pos.y), clampi(floori(p.z), 2, World.SZ - 3))
		for dy in [0, 1, -1, 2, -2, 3, -3]:
			var t := c + Vector3i(0, dy, 0)
			if w.in_bounds(t) and Pathfinder.standable(w, t, body_cells()):
				var dd := Vector3(t).distance_to(from)
				if dd > bd:
					bd = dd
					best = t
				break
	return best

## Per-frame reflexes: hit the target in melee range (reaction delay, sometimes a miss).
func _reflexes(dt: float, m: Node) -> void:
	if state != S.FIGHT:
		return
	var e: Player = m.entity(fight_id)
	if e == null or not seen.get(fight_id, false):
		return
	if center().distance_to(e.center()) > Player.MELEE:
		react_t = randf_range(0.2, 0.4)
		return
	react_t -= dt
	if react_t > 0.0 or atk_cd > 0.0:
		return
	if randf() < 0.18:  # credible miss
		atk_cd = Player.HIT_CD
		swing_t = 0.25
		return
	if m.try_hit(mname, self, fight_id, e):
		atk_cd += randf_range(0.05, 0.35)

func _regen(dt: float) -> void:
	if health >= max_hp or health <= 0.0:
		return
	regen_idle += dt
	if combat_t > 0.0 and not hidden:
		regen_idle = 0.0
		return
	health = minf(max_hp, health + dt * (6.0 if hidden else (1.5 if regen_idle > 4.0 else 0.0)))

func queue_signal(kind: String) -> void:
	if not signal_q.is_empty():
		return
	signal_q = [[0.0, kind], [0.4, kind]]
	sig_hold = 0.0

## Visible signs: double jump (hello), double crouch (peace). Returns the jump input for this frame.
func _signals(dt: float, m: Node) -> bool:
	if sig_hold > 0.0:
		sig_hold -= dt
		if sig_hold <= 0.0:
			crouching = false
		return sig_kind == "jump"
	if signal_q.is_empty():
		crouching = false
		return false
	signal_q[0][0] -= dt
	for i in range(1, signal_q.size()):
		signal_q[i][0] -= dt
	if signal_q[0][0] > 0.0:
		return false
	var s: Array = signal_q.pop_front()
	sig_kind = s[1]
	if sig_kind == "jump" and not on_ground:
		signal_q.push_front([0.1, sig_kind])
		return false
	sig_hold = 0.18
	crouching = sig_kind == "crouch"
	m.broadcast_action(mname, self, sig_kind)
	return sig_kind == "jump"

func has_item(id: int, n: int, m: Node) -> bool:
	return inv.get(id, 0) + (m.chests.get(chest, {}) as Dictionary).get(id, 0) >= n

func take_item(id: int, n: int, m: Node) -> void:
	var a: int = mini(inv.get(id, 0), n)
	inv[id] = inv.get(id, 0) - a
	if a < n:
		var st: Dictionary = m.chests.get(chest, {})
		st[id] = st.get(id, 0) - (n - a)

func stock(m: Node) -> Dictionary:
	var d := inv.duplicate()
	for id in (m.chests.get(chest, {}) as Dictionary):
		d[id] = d.get(id, 0) + m.chests[chest][id]
	return d

## The player's message, interpreted by the "ear" ({intent, item, count, give, want}); the Brain decides.
## Returns {say, action, item, count, affinity, give, want} for the hub (the "mouth" only phrases `say`).
func respond(h: Dictionary, m: Node) -> Dictionary:
	var now: float = m.game_t
	var who := "player"
	m.sync_from_agent(self)
	var st := brain.status_of(who)
	var friend := st == Brain.Status.AMI or st == Brain.Status.ALLIE
	var out := {"say": "generic", "action": "none", "affinity": 0}
	var it: String = h.get("intent", "generic")
	match it:
		"greet":
			brain.on_event("signal_greet", who, {}, now)
			out.say = "greet_enemy" if st == Brain.Status.ENNEMI else "greet"
			if st != Brain.Status.ENNEMI and randf() < 0.5:
				queue_signal("jump")
		"insult", "threat":
			brain.on_event("insult", who, {}, now)
			out.say = "taunt" if brain.t.aggression > 0.55 or brain.t.courage > 0.7 else ("scared" if it == "threat" else "insult")
		"compliment":
			brain._aff(who, 3.0)
			out.say = "compliment"
		"apology":
			brain._good(who)
			brain._aff(who, 4.0)
			out.say = "apology_no" if brain.status_of(who) == Brain.Status.ENNEMI else "apology_ok"
		"alliance":
			if brain.accept_alliance(who):
				out.action = "accept_alliance"
				out.say = "alliance_yes"
				queue_signal("crouch")
			else:
				out.action = "refuse"
				out.say = "alliance_no"
		"request_follow", "request_mine", "request_build":
			if friend or (st == Brain.Status.NEUTRE and brain.t.sociability > 0.6):
				brain._rel(who).follow = true
				out.action = "follow"
				out.say = {"request_follow": "follow", "request_mine": "mine_with", "request_build": "build_with"}[it]
			else:
				out.say = "follow_no"
		"request_stop":
			brain._rel(who).follow = false
			out.action = "stop_follow"
			out.say = "stop"
		"request_give":
			var id := _first_item(h.get("want", {}), h.get("item", ""))
			var n := clampi(int(h.get("count", 1)), 1, 64)
			if id < 0 or not has_item(id, 1, m):
				out.say = "give_no"
			elif friend and brain.t.greed < 0.75:
				out.action = "give"
				out.item = item_word(id)
				out.count = mini(mini(n, 3), stock(m).get(id, 0))
				out.say = "give"
			else:
				out.say = "trade_ask"
		"request_trade", "offer":
			var give: Dictionary = _ids(h.get("give", {}))  # what the player gives me
			var want: Dictionary = _ids(h.get("want", {}))  # what the player wants from me
			if give.is_empty() or want.is_empty():
				out.say = "trade_ask" if st != Brain.Status.ENNEMI else "trade_no"
			else:
				var r := brain.evaluate_offer(who, give, want, stock(m), 1.0 - float(tasks.size()) / maxi(base_total, 1))
				if r.accept:
					out.action = "trade"
					out.give = want
					out.want = give
					out.say = "trade_yes"
				elif not (r.counter as Dictionary).is_empty():
					out.say = "trade_counter"
					out.give = r.counter.want  # I give less
					out.want = r.counter.give
					out.pending = "trade"
				else:
					out.say = "trade_no"
		"accept":
			out = m.accept_pending(self)
		"refuse":
			m.social.pending.erase(mname)
			out.say = "too_bad"
		"question":
			out.say = "question"
	m.sync_to_agent(self)
	return out

func _first_item(d: Variant, word: String) -> int:
	if d is Dictionary:
		for k in d:
			var id: int = k if k is int else item_id(str(k))
			if id >= 0:
				return id
	return item_id(word)

static func _ids(d: Variant) -> Dictionary:
	var out := {}
	if d is Dictionary:
		for k in d:
			var id: int = k if k is int else item_id(str(k))
			if id >= 0 and int(d[k]) > 0:
				out[id] = int(d[k])
	return out

## /spawn des IA : mêmes règles que le joueur (refusé en combat).
func can_use_spawn() -> bool:
	return combat_t <= 0.0 and not (state in SOCIAL_STATES) and state != S.FLEE and not in_lava

func use_spawn(m: Node) -> void:
	pos = m.spawn_point()
	position = pos
	vel = Vector3.ZERO
	_clear_path()
	digging = false
	state = S.IDLE
	wait_t = randf_range(6.0, 25.0)  # revient socialiser un moment

var last_death_t := -999.0
var last_death_pos := Vector3.INF

## Apparaît dans une case libre près de sa maison (jamais dans un bloc) ; après une mort répétée au même endroit : retour au spawn.
func respawn(m: Node = null) -> void:
	var at := Vector3(base) + Vector3(0.5, 0.0, 0.5)
	life.remember("died", "", Vector3i(pos.floor()), 1.0, clock)
	if m != null:
		var w: World = m.world
		var loop: bool = clock - last_death_t < 25.0 and last_death_pos.distance_to(pos) < 4.0
		last_death_t = clock
		last_death_pos = pos
		var h := body_cells()
		var best := NOWHERE
		var bd := INF
		for dy in range(-2, 4):
			for dx in range(-3, 4):
				for dz in range(-3, 4):
					var c := base + Vector3i(dx, dy, dz)
					var d := float(dx * dx + dz * dz + dy * dy * 2)
					if d < bd and Pathfinder.standable(w, c, h) and not Pathfinder.lava_near(w, c):
						bd = d
						best = c
		if best.x < 0:  # base murée / sans sol : on la dégage
			for i in h:
				var cc := base + Vector3i(0, i, 0)
				if Pathfinder.solid(w, cc) and Pathfinder.diggable(w, cc):
					m.edit_break(cc, false)
			if not Pathfinder.solid(w, base - Vector3i(0, 1, 0)):
				m.edit_place(base - Vector3i(0, 1, 0), World.STONE)
			best = base
		at = Vector3(best) + Vector3(0.5, 0.0, 0.5)
		if loop and m.hub_n != null:
			at = m.spawn_point()
	pos = at
	position = pos
	vel = Vector3.ZERO
	health = max_hp
	combat_t = 0.0
	hidden = false
	_clear_path()
	digging = false
	state = S.IDLE
	fight_id = ""
