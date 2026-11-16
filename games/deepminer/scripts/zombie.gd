class_name Zombie extends Miner
## Zombie lent (idée reprise d'AFTERWORLD, version Deep Miner) : erre dans les grottes, poursuit le joueur à vitesse réduite
## (il marche à ~1,5 bloc/s, le joueur 2,5 en marchant et 5 en courant : on peut toujours le semer) et frappe au contact.
## Même physique que le joueur (Player.step) et même suivi de chemin que les mineurs IA, mais sans cerveau social.

const WANDER_SPEED := 1.1  # Player.speed (x WALK_MULT 0,5 = blocs/s)
const CHASE_SPEED := 2.0
const SIGHT := 14.0
const LOSE_T := 4.0  # temps de poursuite après avoir perdu le joueur de vue
const ATTACK_CD := 1.5
const ZOMBIE_HP := 60.0
const HIT_RANGE := 1.35  # distance (centre à centre) à laquelle il touche vraiment
const PLAYER_BONUS := 0.9  # le joueur frappe un zombie à MELEE + ceci
const BITE_HIT_AT := 0.5  # la morsure touche quand il reste ce temps d'animation (coup à mi-animation)
const BURROW_TIME := 1.3

# --- modèle animé d'AFTERWORLD (Mixamo : assets/creatures/zombie/model) : marche, attente, morsure, ramper
const MODEL := "res://games/deepminer/assets/creatures/zombie/model/character.fbx"
const MODEL_DIR := "res://games/deepminer/assets/creatures/zombie/model/"
const ANIMS := ["idle", "walk", "run", "bite", "neckbite", "crawl"]
const ONE_SHOT := ["bite", "neckbite"]
const WALK_ANIM_SPEED := 1.1  # m/s correspondant à la marche jouée à 1x
const CRAWL_HP := 0.3  # sous cette fraction de PV : il rampe
const MODEL_SCALE := 0.85
const BLEND := 0.2
static var _scene: PackedScene
static var _lib: AnimationLibrary
static var _facets: Dictionary = {}  # maillage d'origine -> maillage à facettes (mis en cache)

var _rot: Node3D
var _anim: AnimationPlayer
var _bite_t := 0.0
var _z_tint := false
var _speed_var := 1.0
var zcd := 0.0
var groan_t := randf_range(2.0, 8.0)  # prochain grognement
var burrowing := false
var burrow_t := 0.0
var _burrow_fx := 0.0
var _hit_pending := false
var repath_t := 0.0
var wander_t := 0.0
var aggro_t := 0.0
var zid := 0  # identifiant réseau (hôte)
var tid := ""  # cible actuelle : "player", nom d'un mineur IA, ou "peer"
var tent: Player = null  # son corps (null pour un joueur distant)
var tpeer := 0  # id réseau du joueur distant visé
var tpos := Vector3.INF  # dernière position connue de la cible (centre)
var tfeet := Vector3i.ZERO

## Modèle et bibliothèque d'animations (mis en cache) ; null si les fichiers ne sont pas importés (repli : corps en cubes).
static func model_scene() -> PackedScene:
	if _scene == null and ResourceLoader.exists(MODEL):
		_scene = load(MODEL)
	return _scene

static func anim_library() -> AnimationLibrary:
	if _lib:
		return _lib
	var lib := AnimationLibrary.new()
	for key in ANIMS:
		var path: String = MODEL_DIR + key + ".fbx"
		if not ResourceLoader.exists(path):
			continue
		var sc: Node = (load(path) as PackedScene).instantiate()
		var ap: AnimationPlayer = sc.find_child("AnimationPlayer", true, false)
		if ap and ap.get_animation_list().size() > 0:
			var a: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
			a.loop_mode = Animation.LOOP_NONE if key in ONE_SHOT else Animation.LOOP_LINEAR
			_strip_root_motion(a)
			lib.add_animation(key, a)
		sc.free()
	_lib = lib
	return lib

## Aspect low-poly : normales par face (facettes visibles) sur tous les maillages du modèle ; la peau (os/poids) est conservée.
static func facet(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var src: Mesh = mi.mesh
		if src == null:
			continue
		if not _facets.has(src):
			var out := ArrayMesh.new()
			for si in src.get_surface_count():
				var st := SurfaceTool.new()
				st.create_from(src, si)
				st.deindex()
				st.generate_normals()
				var mat: Material = src.surface_get_material(si)
				if mat is StandardMaterial3D:
					mat = mat.duplicate()
					(mat as StandardMaterial3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				st.set_material(mat)
				st.commit(out)
			_facets[src] = out
		mi.mesh = _facets[src]

## Garde la hauteur des hanches mais fige leur avance horizontale (le code déplace le zombie).
static func _strip_root_motion(a: Animation) -> void:
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D or not str(a.track_get_path(t)).ends_with("Hips"):
			continue
		if a.track_get_key_count(t) == 0:
			continue
		var p0: Vector3 = a.track_get_key_value(t, 0)
		for k in a.track_get_key_count(t):
			var p: Vector3 = a.track_get_key_value(t, k)
			a.track_set_key_value(t, k, Vector3(p0.x, p.y, p0.z))

## Animation voulue : [nom, vitesse de lecture] (même logique qu'AFTERWORLD ; la poursuite lente reste une marche rapide).
static func anim_for(is_moving: bool, hp_frac: float, spd: float, contact: bool) -> Array:
	if contact and not is_moving:
		return ["bite", 1.6]
	if is_moving and hp_frac < CRAWL_HP:
		return ["crawl", clampf(spd / 1.0, 0.6, 2.5)]
	if is_moving:
		return ["walk", clampf(spd / WALK_ANIM_SPEED, 0.6, 2.5)]
	return ["idle", 1.0]

func _play(n: String, spd: float) -> void:
	if _anim == null or not _anim.has_animation(n):
		return
	if _anim.current_animation != n or (n in ONE_SHOT and not _anim.is_playing()):
		_anim.play(n, BLEND)
	_anim.speed_scale = spd * _speed_var

func setup(p: Vector3) -> void:
	mname = "Zombie"
	color = Color(0.42, 0.7, 0.32)
	species = 0
	pos = p
	position = p
	base = Vector3i(p.floor())
	dmg_mult = 0.65

func _ready() -> void:
	super._ready()
	max_hp = ZOMBIE_HP
	health = ZOMBIE_HP
	var pack := model_scene()
	if pack != null and not anim_library().get_animation_list().is_empty():  # modèle animé d'AFTERWORLD à la place du corps en cubes
		if vbody:
			vbody.queue_free()
			vbody = null
		spr.visible = false
		_rot = Node3D.new()
		add_child(_rot)
		var mdl: Node3D = pack.instantiate()
		mdl.scale = Vector3.ONE * MODEL_SCALE
		facet(mdl)
		_rot.add_child(mdl)
		_anim = AnimationPlayer.new()
		mdl.add_child(_anim)
		_anim.add_animation_library("", anim_library())
		_speed_var = randf_range(0.9, 1.1)
		_play("idle", 1.0)
		if _anim.current_animation == "idle":
			_anim.seek(randf() * _anim.current_animation_length, true)  # pas tous en chœur
	if label:
		label.text = "Zombie"
		label.modulate = Color(0.55, 0.85, 0.4)

func _label() -> void:
	if label:
		label.text = "Zombie"

## Plus de PV : il fuit en creusant, s'enfonce rapidement dans le sol et disparaît.
func start_burrow() -> void:
	burrowing = true
	burrow_t = 0.0
	_hit_pending = false
	vel = Vector3.ZERO
	_clear_path()
	if label:
		label.visible = false

func _tick_burrow(dt: float, m: Node) -> void:
	burrow_t += dt
	vel = Vector3.ZERO
	if _rot:
		var k := clampf(burrow_t / BURROW_TIME, 0.0, 1.0)
		_rot.position.y = -2.2 * k * k - 0.1 * k
		_play("crawl", 2.5)
	_burrow_fx -= dt
	if _burrow_fx <= 0.0:
		_burrow_fx = 0.22
		var below := Vector3i(floori(pos.x), floori(pos.y) - 1, floori(pos.z))
		var id: int = (m.world as World).get_v(below)
		m.chip_burst(below, id if id != World.AIR else World.DIRT, 0.6)
	if burrow_t >= BURROW_TIME:
		m.zombie_gone(self)

func tick(dt: float, m: Node) -> void:
	if burrowing:
		_tick_burrow(dt, m)
		return
	var w: World = m.world
	clock += dt
	zcd -= dt
	_bite_t -= dt
	groan_t -= dt
	repath_t -= dt
	wander_t -= dt
	var tg := _pick_target(m)
	var sees_p := not tg.is_empty()
	if sees_p:
		tid = tg.id
		tent = tg.ent
		tpeer = tg.peer
		tpos = tg.pos
		tfeet = tg.feet
	if tent != null and (tent.health <= 0.0 or m.is_safe_zone(tent.center())):
		aggro_t = 0.0
	else:
		aggro_t = LOSE_T if sees_p else aggro_t - dt
	var chasing: bool = aggro_t > 0.0 and tpos != Vector3.INF
	var dist: float = center().distance_to(tpos) if tpos != Vector3.INF else INF
	var p: Player = tent if tent != null else m.player
	speed = CHASE_SPEED if chasing else WANDER_SPEED
	if groan_t <= 0.0:
		groan_t = randf_range(3.0, 6.0) if chasing else randf_range(8.0, 15.0)
		DMSfx.play("zombie", pos, 2.0 if chasing else -2.0, 0.15)
	var wish := Vector3.ZERO
	var jump := false
	if chasing:
		if dist <= HIT_RANGE * 0.9:
			_clear_path()  # au contact : il s'arrête et mord (animation, le coup part à mi-animation)
			if zcd <= 0.0 and _bite_t <= 0.0:
				_bite_t = 0.9
				DMSfx.play("zhit", pos, 0.0, 0.1)
				_hit_pending = true
				zcd = ATTACK_CD
		elif repath_t <= 0.0 or path_i >= path_cells.size():
			repath_t = 0.8
			var r := Pathfinder.find(w, feet_cell(), Pathfinder.GOAL_REACH, tfeet, false, true, 450, body_cells())
			path_cells = r.cells
			path_clears = r.clears
			path_i = 0
			stuck_t = 0.0
	elif wander_t <= 0.0 and path_i >= path_cells.size():
		wander_t = randf_range(3.0, 7.0)
		for k in 6:  # une destination proche, au hasard
			var c := feet_cell() + Vector3i(randi_range(-6, 6), randi_range(-1, 1), randi_range(-6, 6))
			if Pathfinder.standable(w, c, body_cells()):
				var r2 := Pathfinder.find(w, feet_cell(), Pathfinder.GOAL_CELL, c, false, true, 250, body_cells())
				path_cells = r2.cells
				path_clears = r2.clears
				path_i = 0
				stuck_t = 0.0
				break
	if _hit_pending and _bite_t <= BITE_HIT_AT:
		_hit_pending = false
		if dist <= HIT_RANGE + 0.25 and atk_cd <= 0.0:
			if tent != null:
				m.try_hit("zombie", self, tid, tent)
			elif tpeer != 0 and DMNet.i.is_host():
				_bite_peer(m)
	if _hit_pending or (_bite_t > 0.0 and dist <= HIT_RANGE):
		wish = Vector3.ZERO  # il reste planté pendant la morsure
	elif path_i < path_cells.size():
		var fr := _follow(dt, m, w)
		wish = fr[0]
		jump = fr[1]
	if in_water and w.get_v(Vector3i(floori(pos.x), floori(pos.y + 1.4), floori(pos.z))) == World.WATER:
		jump = true
	running = false
	step(dt, wish, jump, w)
	var sr: Vector3 = m.screen_right()
	var sd: float = vel.dot(sr)
	if absf(sd) > 0.3:
		facing = 1 if sd > 0 else -1
	if chasing and dist < SIGHT:
		var fd: float = (tpos - pos).dot(sr)
		if absf(fd) > 0.1:
			facing = 1 if fd > 0 else -1

	_update_model(dt, p, chasing, dist)

## Cible la plus proche à portée de vue : le joueur local, un mineur IA, ou (hôte) un joueur distant ; jamais en zone sûre.
func _pick_target(m: Node) -> Dictionary:
	var best := {}
	var bd := INF
	var cands: Array = [["player", m.player]]
	for mi in m.miners:
		if (mi as Miner).active and (mi as Miner).health > 0.0:
			cands.append([(mi as Miner).mname, mi])
	for c in cands:
		var e: Player = c[1]
		if e.health <= 0.0 or m.is_safe_zone(e.center()):
			continue
		var d := center().distance_to(e.center())
		if d < bd and d < SIGHT and (d < 5.0 or bool(m.sees(self, e))):
			bd = d
			best = {"id": c[0], "ent": e, "pos": e.center(), "feet": e.feet_cell(), "peer": 0}
	if DMNet.i.is_host():
		for pid in DMNet.i.peers:
			var pp: Vector3 = (DMNet.i.peers[pid].pos as Vector3) + Vector3(0, 0.9, 0)
			var d2 := center().distance_to(pp)
			if d2 < bd and d2 < 9.0 and not m.is_safe_zone(pp):
				bd = d2
				best = {"id": "peer", "ent": null, "pos": pp, "feet": Vector3i(pp.floor()), "peer": pid}
	return best

## Morsure d'un joueur distant : l'hôte envoie les dégâts.
func _bite_peer(m: Node) -> void:
	if atk_cd > 0.0 or not DMNet.i.peers.has(tpeer):
		return
	atk_cd = Player.HIT_CD
	DMNet.i._deliver(tpeer, Player.DMG * dmg_mult, pos, 0.5, 0)

## Orientation et clip d'animation selon l'état.
func _update_model(dt: float, p: Player, chasing: bool, dist: float) -> void:
	if _rot == null:
		return
	var hit := flash_t > 0.0  # filtre rouge quand il encaisse un coup
	if hit != _z_tint:
		_z_tint = hit
		VoxelBody.hit_tint(_rot, hit)
	var hv := Vector2(vel.x, vel.z)
	var moving := hv.length() > 0.15
	var dir := Vector3(vel.x, 0.0, vel.z)
	if (chasing and dist < HIT_RANGE * 1.5) or _bite_t > 0.0:
		dir = Vector3(tpos.x - pos.x, 0.0, tpos.z - pos.z)  # au contact : face à sa cible
	if dir.length() > 0.05:
		_rot.rotation.y = lerp_angle(_rot.rotation.y, atan2(dir.x, dir.z), minf(dt * 6.0, 1.0))
	var a := anim_for(moving and _bite_t <= 0.0, health / max_hp, hv.length(), _bite_t > 0.0)
	var n: String = a[0]
	if n == "bite":
		if _anim.current_animation in ONE_SHOT and _anim.is_playing():
			n = _anim.current_animation
		else:
			n = "bite" if randf() < 0.5 else "neckbite"
	_play(n, a[1])
