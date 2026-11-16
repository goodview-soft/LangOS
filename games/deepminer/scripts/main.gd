extends Node3D
## Deep Miner: orchestration (world meshes, multi-axis ortho camera, input, mining, lights, tests).

const REMESH_US := 4000  # --- PERF --- remesh budget per frame (µs)
const ZOOMS := [11.25, 15.0, 22.5, 30.0, 45.0, 60.0]
const ZOOM_DEFAULT := 1  # closer 2D view: blocks 1.5x bigger than the old default (22.5)
const REACH := 5.5
const ROT_TIME := 0.3
const CUT_SPEED := 8.0  # layers per second for the animated cut
const DEAD_ZONE := Vector2(1.2, 0.9)
const LOOK_AHEAD := 1.6
const TORCH_COL := Color(1.0, 0.62, 0.3)

var world: World
var atlas: Texture2D
var mat_s: ShaderMaterial
var mat_f: ShaderMaterial
var chunks := {}  # Vector3i -> MeshInstance3D
var cap: MeshInstance3D
var cap_old: MeshInstance3D  # previous layer's cap, kept while the cut animates
var cam: Camera3D
var cam_center := Vector3.ZERO
var cam_focus := Vector3.ZERO
var look := 0.0
var rot_from := Quaternion.IDENTITY
var rot_to := Quaternion.IDENTITY
var rot_t := 1.0
var cut_cur := -1000.0
var cut_goal := -1000.0
var player: Player
var hud: Hud
var touch: TouchControls  # contrôles tactiles (null sur PC)
signal exit_requested   # LangOS : fermer la fenêtre du jeu
signal restart_requested  # LangOS : reconstruire le jeu (nouvelle partie)
var ext_block := false  # LangOS : la fenêtre n'a pas le focus (clavier/souris ignorés)
var music: DMMusic
var extra_h := 0.0  # hauteur logique ajoutée sous les 360 px de base (fenêtre plus haute que 16:9)
var lamp: OmniLight3D
var lights: Array = []  # [OmniLight3D, base Vector3, cell Vector3i]
var torch_lights := {}  # Vector3i -> entry
var highlight: MeshInstance3D  # corner brackets + cracks on the aimed face
var preview: MeshInstance3D  # placement preview (right click)
var shadow: MeshInstance3D  # player's ground shadow
var part_mats: Array = []  # ShaderMaterials of the pixel particles (cut-plane aware)
var chip_pool: Array = []  # one-shot GPUParticles3D bursts
var chip_i := 0
var chip_t := 0.0
var step_d := 0.0  # distance parcourue depuis le dernier bruit de pas
var pick_n := 0
var dust: GPUParticles3D
var anim_t := 0.0
var hl_mat: ShaderMaterial
var hl_mat_fine: ShaderMaterial  # repère du mode fin : TESTE la profondeur (les blocs devant le cachent)
var diorama := false
const DIORAMA_YAW := 30.0

var yaw_k := 0
var top_view := false
var tilt := 32.0
var swap_dir := 1
var zoom_i := ZOOM_DEFAULT
var cam_offset := Vector2.ZERO
var view_dir := Vector3(0, 0, -1)
var right := Vector3(1, 0, 0)
var up_s := Vector3(0, 1, 0)
var cut_axis := 2
var cut_sign := -1
var cut_layer := -999

var inv := {}
var hotbar_n: Array = [1, 1, 0, 0, 0, 0, 0, 0]  # quantité de la pile de chaque case de la barre (Stacks)
var sac: Array = []  # piles du sac : Vector2i(id, quantité), id -2 = case vide
var cursor := Vector2i(-2, 0)  # pile tenue par la souris dans l'inventaire
var hotbar := [-1, -3, World.TORCH, World.DIRT, World.STONE, World.COAL, World.COPPER, World.IRON]  # 8 cases rapides (touches 1-8), réglables dans l'inventaire (I)
var sel := 0
var target := {}
var mine_cell := Vector3i(-1, -1, -1)
var mine_prog := 0.0
var map_t := 0.0
var world_map: WorldMap  # grande carte (B)
var builder: Builder  # chantier : placement de modules (C)
var build_menu: BuildMenu
var pois_found: Array = []  # lieux découverts (indices de world.pois, stables pour une graine)
var mid_drag := false
var r_drag := false  # right button held: camera drag
var r_dist := 0.0
var shot_path := ""
var shot_at := Vector2(-1, -1)
const SY_SHOT := 45
# --- PERF --- --dm-prof=SECONDS: auto-walk, per-section timings, frame-time report, then quit (no save)
var prof_s := 0.0
var prof := {}
var prof_frames := 0
var prof_t := 0.0
var prof_ft: Array = []
var frames := 0
var state := "play"  # menu | play | pause
var menu: Menu
var abilities: Abilities
var book: RecipeBook
var bag: Bag
var load_t := 0.0
var perf_on := true  # frame counter (F3 shows / hides it)
var perf_lbl: Label
var perf_t := 0.0
var perf_max := 0.0
var shake := 0.0  # tremblement d'écran (capacités)
var menu_t := 0.0
var testing := false
var real_paths := false  # --dm-realpaths : les tests utilisent le rythme et la limite de recherche du vrai jeu
var loaded := false  # partie chargee depuis la sauvegarde

# AI miners, chests, save
const SAVE_PATH := "user://deepminer/save.dat"
const TEST_SAVE_PATH := "user://deepminer/test_save.dat"
const AUTOSAVE := 60.0
## [pseudo, colour, personality, chat style, species (index of DMSettings.BODIES)] : one SocialAgent per miner, linked by the pseudo
const MINER_DEFS := [["kevin_mine", Color(0.31, 0.82, 1.0), "bavard", "écrit vite, abréviations partout, dit mdr", 3],
	["xX_Dark_Xx", Color(1.0, 0.42, 0.24), "raleur", "sec, se plaint du lag et des autres", 1],
	["LeaCraft", Color(0.91, 0.42, 0.85), "serviable", "sympa mais pas naïve", 0],
	["pioche_tranquille", Color(0.56, 0.94, 0.29), "discret", "répond en 1 à 4 mots", 4],
	["TomTom42", Color(1.0, 0.85, 0.3), "farceur", "blagues, ptdr, taquine", 2],
	["Zoe_Pickaxe", Color(0.65, 0.55, 1.0), "serviable", "enthousiaste, beaucoup de !!", 0],
	["gros_marcel", Color(0.95, 0.6, 0.2), "raleur", "grognon, phrases courtes, critique tout", 2],
	["nova_7", Color(0.35, 0.95, 0.75), "discret", "calme, peu de mots, parfois sarcastique", 4],
	["Jojo_le_nain", Color(0.85, 0.3, 0.3), "bavard", "raconte sa vie, dit mdr et lol", 1],
	["sk8er_boi", Color(0.95, 0.95, 0.4), "farceur", "ado, argot, troll gentiment", 3],
	["Marion_B", Color(0.4, 0.6, 1.0), "serviable", "polie, propose son aide", 0],
	["DarkVador_77", Color(0.55, 0.55, 0.65), "raleur", "menaçant pour rire, se prend pour un boss", 1]]
const PLAYER_NAME := "Clément"
static var auto_play := false  # après F9 / « Nouvelle partie » : on saute le menu
static var next_seed := 0  # set by F9 (new game) before reloading the scene
var miners: Array = []
var chests := {}  # Vector3i -> {block id: count}
const MINE_CHEST := "un ancien mineur"
var chest_owner := {}  # Vector3i -> miner name
var path_cd := 0.0
var path_budget := 0  # A* searches allowed this frame
var dirty := {}  # chunk keys to remesh at the end of the frame
var save_enabled := false
var nettest := false  # --dm-net-host=PORT / --dm-net-join=IP:PORT (tests/test_net.sh)
var save_t := 0.0
var seed_v := 1337
var f9_t := 0.0
var inspect: Variant = null  # Miner or chest cell shown in the info panel
var hub_n: HubGame  # --- SPAWN HUB ---
# --- social / combat
var social: SocialHub
var lava_was := false
var vis_hold := {}  # miner name -> seconds left visible (anti-blink)
var diag := false  # --dm-diag: loads the real save read-only, prints the state, quits
var aura: OmniLight3D
var layer_mem := {}  # axis -> last shown layer (survives camera rotations)
var front_y := -1000  # 2D: camera-side layers are cut at this height (player's ground level, stable)
var narrow_cut := false  # hysteresis: player in a tight spot
var amb := 2           # "ambiance" of the 2D view: 0 off, 1 subtle, 2 full (U cycles): far layers bigger + curved horizon + sway
var amb_speed := 0.0   # smoothed player speed (0..1): the effect swells when running / falling
var amb_t := 0.0
var grow_far := true
var persp_2d := true  # 2D view in light perspective (K toggles)
const PERSP_FOV := 30.0
# --- 2D depth intent: Z/S change layer only when held DEPTH_HOLD s; then glide to the next layer's centre
var depth_hold := 0.25
var depth_t := 0.0
var depth_goal := NAN
var depth_from := NAN
var depth_back := false
var depth_stall := 0.0
# --- 2D mouse yaw (L toggles): the view opens toward the mouse, movement axes stay aligned
const YAW_MAX := 8.0
const YAW_BIAS := 3.5
var yaw_on := true
var yaw_cur := 0.0  # degrees
var yaw_bias := 0.0
var yaw_cand := 0.0
var yaw_cand_t := 0.0
var yaw_scan_t := 0.0
var cam_ctl := CameraCtl.new()
var view: ViewCtl  # --- VIEW --- iso / coupe / FPS
var fog: FogOfWar  # voxel fog of war (seen now / explored / unknown)
var chat: ChatUI
var game_t := 0.0
var hits := {}  # attacker id -> {victim, t}
var hit_notified := {}  # "a>v" -> time of the last social notification
var drops: Array = []  # {node: Sprite3D, item, count, t}
var crouch_was := false
var nearby_t := 0.0
var base_warn := {}  # miner name -> time

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://deepminer")
	var args := OS.get_cmdline_user_args()
	DMSettings.init()
	DMSfx.host = self
	DMNet.setup(self)  # nœud réseau LAN + MultiplayerAPI dédié à ce jeu
	for a in args:
		if a.begins_with("--dm-net-"):
			nettest = true
		if a.begins_with("--dm-shot="):
			shot_path = a.substr(10)
		if a.begins_with("--dm-shot-at="):  # capture ailleurs : x,z (se pose sur le premier sol libre en descendant)
			var xz := a.substr(13).split(",")
			if xz.size() == 2:
				shot_at = Vector2(float(xz[0]), float(xz[1]))
		if a.begins_with("--dm-prof="):
			prof_s = float(a.substr(10))
	if "--dm-test" in args:
		DMSettings.look = DMSettings.DEFAULT_LOOK.duplicate()
	testing = "--dm-test" in args
	real_paths = "--dm-realpaths" in args
	Life.use_nn = ("--dm-nn" in args) if testing else not ("--dm-nonn" in args)  # réseau actif en jeu ; en test seulement avec --dm-nn
	amb = 0 if testing else 2  # tests were written for the perspective camera
	grow_far = amb > 0
	diag = "--dm-diag" in args
	save_enabled = not testing and not nettest and shot_path == "" and prof_s <= 0.0 and not diag
	var save_data: Variant = _read_save(SAVE_PATH) if (save_enabled or "--dm-prof-save" in args) else null
	atlas = Tex.build_atlas()
	mat_s = ShaderMaterial.new()
	mat_s.shader = load("res://games/deepminer/shaders/block.gdshader")
	mat_s.set_shader_parameter("atlas", atlas)
	mat_f = ShaderMaterial.new()
	mat_f.shader = load("res://games/deepminer/shaders/fluid.gdshader")
	mat_f.set_shader_parameter("atlas", atlas)
	mat_f.render_priority = 1
	var t0 := Time.get_ticks_msec()
	world = World.new()
	if save_data != null:
		seed_v = save_data.get("seed", seed_v)
	elif next_seed != 0:
		seed_v = next_seed
	# Génération hors du fil principal : le jeu (et la fenêtre « Chargement ») reste fluide pendant ~2 s.
	set_process(false); set_physics_process(false); set_process_unhandled_input(false)
	var gen_task := WorkerThreadPool.add_task(func(): world.generate(seed_v), false, "génération")
	while not WorkerThreadPool.is_task_completed(gen_task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(gen_task)
	print("[DM] génération : %d ms" % (Time.get_ticks_msec() - t0))
	var hub := SpawnHub.new()  # --- SPAWN HUB --- salle de spawn (déterministe pour une graine donnée)
	hub.build(world)
	if save_data != null:
		_apply_blocks(save_data)
	else:
		for lc in world.loot:  # coffres des anciennes mines (sauvegardés ensuite avec les coffres)
			chests[lc] = (world.loot[lc] as Dictionary).duplicate()
			chest_owner[lc] = MINE_CHEST
	var all_keys: Array = []
	for cz in ceili(World.SZ / float(World.CS)):
		for cy in ceili(World.SY / float(World.CS)):
			for cx in ceili(World.SX / float(World.CS)):
				all_keys.append(Vector3i(cx, cy, cz))
	# Maillage progressif : les morceaux proches du spawn tout de suite (en parallèle), le reste en tâche de fond,
	# appliqué par petites tranches dans _process (plus de gel au chargement).
	var spk := Vector3(world.spawn / float(World.CS))
	all_keys.sort_custom(func(a, b): return Vector3(a).distance_squared_to(spk) < Vector3(b).distance_squared_to(spk))
	for k in all_keys:
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		chunks[k] = mi
	var near_keys: Array = all_keys.slice(0, mini(NEAR_CHUNKS, all_keys.size()))
	var near_meshes := _mesh_chunks(near_keys)
	for i in near_keys.size():
		(chunks[near_keys[i]] as MeshInstance3D).mesh = near_meshes[i]
	_stream_start(all_keys.slice(near_keys.size()))
	print("[DM] monde généré + zone de départ maillée en %d ms (le reste en tâche de fond)" % (Time.get_ticks_msec() - t0))
	cap = MeshInstance3D.new()
	add_child(cap)
	cap_old = MeshInstance3D.new()
	add_child(cap_old)
	_setup_env()
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ZOOMS[zoom_i]
	cam.near = 0.05
	cam.far = 300.0
	add_child(cam)
	cam.current = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # --- PERF --- only bodies are interpolated
	player = Player.new()
	player.is_main = true
	player.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(player)
	player.pos = world.spawn
	player.position = player.pos
	lamp = OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.9, 0.72)
	lamp.light_energy = 1.55
	lamp.omni_range = 11.0
	lamp.omni_attenuation = 1.25
	add_child(lamp)
	aura = OmniLight3D.new()  # round light around the player: floor, steps and walls of big rooms stay readable
	aura.light_color = Color(1.0, 0.86, 0.66)
	aura.light_energy = 0.55  # the shader light (plight) does most of the round halo
	aura.omni_attenuation = 0.7
	aura.shadow_enabled = false
	add_child(aura)
	_fit_player()
	for s in world.light_spots:
		_add_light(s[0], s[1], s[2], 1.3)
	if save_data == null:  # nouveau monde : les torches des anciennes mines sont de vraies torches (un monde chargé les retrouve dans ses blocs)
		for tp in world.mine_lights:
			_add_torch_light(Vector3i(tp))
	_build_highlight()
	_setup_particles()
	inv = {World.TORCH: 20, World.DIRT: 10}
	# --- SPAWN HUB ---
	inv[World.SIGN] = 5
	# --- /SPAWN HUB ---
	hud = Hud.new()
	add_child(hud)
	hud.setup(atlas, hotbar)
	hud.hp_bar.max_value = player.max_hp
	fog = FogOfWar.new(world)
	hud.fog = fog
	_set_param("fow", fog.tex)
	_set_param("fow_on", FogOfWar.ENABLED)  # désactivé : sinon les cubes au-delà du rayon passent en « mémoire » grise (noir et blanc à l'horizon)
	_set_param("fow_r", float(FogOfWar.R))
	# --- SPAWN HUB ---
	hub_n = HubGame.new()
	add_child(hub_n)
	hub_n.setup(self, hub)
	# --- /SPAWN HUB ---
	_setup_social()
	var strat := Strategist.new()  # raisonnement LLM rare (buts + phrases d'intention) ; inactif en test
	strat.name = "Strategist"
	add_child(strat)
	strat.setup(self)
	if save_data != null:
		_apply_state(save_data)
		loaded = true
	else:
		_starter_torches()
		spawn_miners()
		_link_agents(true)
	view = ViewCtl.new()  # --- VIEW ---
	add_child(view)
	view.setup(self)
	fog.compute_now(player.feet_cell(), player.body_cells())
	print("[DM] brouillard de guerre : %d cellules vues, %.1f ms" % [fog.seen_now.size(), fog.last_us / 1000.0])
	if shot_path != "" and not miners.is_empty():  # capture: stand next to the first miner
		player.pos = (miners[0] as Miner).pos
		if shot_at.x >= 0.0:
			for yy in range(SY_SHOT, 2, -1):
				if world.get_b(int(shot_at.x), yy, int(shot_at.y)) == World.AIR and world.is_solid(world.get_b(int(shot_at.x), yy - 1, int(shot_at.y))):
					player.pos = Vector3(shot_at.x + 0.5, yy, shot_at.y + 0.5)
					break
		player.position = player.pos
	for a in OS.get_cmdline_user_args():  # --dm-pos=x,y,z : capture à cet endroit
		if a.begins_with("--dm-pos="):
			var pp := a.substr(9).split(",")
			if pp.size() == 3:
				player.pos = Vector3(float(pp[0]) + 0.5, float(pp[1]), float(pp[2]) + 0.5)
				player.position = player.pos
	_fit_player()
	_flush_remesh(true)  # the whole map is meshed before the first frame (no progressive pop-in)
	_apply_view()
	_update_camera(0.0, true)
	if TouchControls.wanted():
		touch = TouchControls.new()
		touch.main = self
		add_child(touch)
		hud.touch_layout()
		set_extra_h(extra_h)
	menu = Menu.new()
	add_child(menu)
	if not testing and shot_path == "":
		music = DMMusic.new()
		add_child(music)
	menu.play.connect(_start_play.bind(true))
	menu.resume.connect(_start_play.bind(false))
	menu.to_main.connect(func():
		if save_enabled:
			save_game(SAVE_PATH)
		restart_requested.emit())
	menu.new_game.connect(_new_game)
	menu.set_has_save(loaded)
	menu.species_locked = loaded  # partie existante : espèce figée
	abilities = Abilities.new()
	add_child(abilities)
	abilities.setup(self)
	book = RecipeBook.new()
	book.main = self
	add_child(book)
	world_map = WorldMap.new()
	world_map.main = self
	add_child(world_map)
	builder = Builder.new()
	add_child(builder)
	builder.setup(self)
	build_menu = BuildMenu.new()
	build_menu.main = self
	add_child(build_menu)
	bag = Bag.new()
	bag.main = self
	add_child(bag)
	menu.look_changed.connect(func():
		var old_max := player.max_hp
		player.apply_species()
		if absf(player.max_hp - old_max) > 0.1 and is_safe_zone(player.center()):
			player.health = player.max_hp  # changer de créature dans la salle de spawn : PV pleins de la nouvelle espèce
		player.refresh_look()
		_fit_player()
		abilities.refresh())
	menu.quit_requested.connect(func(): exit_requested.emit())
	menu.host_requested.connect(_net_host)
	menu.join_requested.connect(_net_join)
	DMNet.i.status.connect(menu.set_net_status)
	DMNet.i.world_received.connect(_net_joined)
	DMNet.i.lost.connect(func(): restart_requested.emit())
	if "--dm-test" in args or shot_path != "" or auto_play or prof_s > 0.0 or nettest:
		auto_play = false
		_start_play(true)
	else:
		state = "menu"
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # free mouse in menus
		hud.visible = false
		menu.open_main()
	if testing:
		call_deferred("_run_tests")  # defined by tests/main_tests.gd (test scene only)
	if nettest:
		DMNet.i.start_test.call_deferred(args)
	if diag:
		_start_play(false)
		get_tree().create_timer(4.0).timeout.connect(_diag_report)
	set_process(true); set_physics_process(true); set_process_unhandled_input(true)
	booting = false

## Displayed (interpolated) player centre: what the cameras follow between physics ticks.
func vis_center() -> Vector3:
	if testing or Engine.is_in_physics_frame() or not is_inside_tree():
		return player.center()
	return player.get_global_transform_interpolated().origin + (player.center() - player.pos)

## Applique la taille de l'espece : libere la place au spawn si besoin, lampe et PV max.
func _fit_player() -> void:
	lamp.omni_range = player.lamp_range * 1.3
	if aura:
		aura.omni_range = player.lamp_range * 1.7
	if hud:
		hud.hp_bar.max_value = player.max_hp
	_fit_body(player)

## Libère la place d'un corps (joueur ou IA) selon sa hitbox : le remonte, sinon creuse autour.
func _fit_body(b: Player) -> void:
	if not world.box_hits(b.pos, b.hw, b.hh):
		return
	for i in 4:
		var up := b.pos + Vector3(0, i, 0)
		if not world.box_hits(up, b.hw, b.hh):
			b.pos = up
			b.position = up
			return
	var p := Vector3i(b.pos.floor())
	for y in range(0, ceili(b.hh) + 1):
		for x in [-1, 0, 1]:
			var c := p + Vector3i(x, y, 0)
			if world.in_bounds(c) and world.get_v(c) != World.AIR and World.HARD[world.get_v(c)] >= 0.0:
				world.set_v(c, World.AIR)
				_remesh(c)

func _start_play(fresh: bool) -> void:
	state = "play"
	if view and view.mode == ViewCtl.FPS and not (chat and chat.is_open):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # 3rd person / FPS: mouse looks around
	player.reset_physics_interpolation()
	menu.species_locked = true  # la partie est commencée : plus de changement d'espèce
	menu.close()
	if social:
		social.system_message("Chat : appuie sur T ou Entrée pour écrire (@pseudo pour viser un joueur), P : liste des joueurs")
	hud.visible = true
	if fresh:
		cam_offset = Vector2.ZERO
		zoom_i = DMSettings.zoom
		if loaded:
			hud.toast("Partie chargée, %s  (F9 : nouvelle partie, H : aide)" % DMSettings.look.name)
		else:
			player.health = player.max_hp
			hud.toast("Bienvenue dans la caverne, %s !  (H : aide)" % DMSettings.look.name)

## Hauteur logique en plus des 360 px de base : le HUD du bas et les contrôles tactiles descendent d'autant.
func set_extra_h(dy: float) -> void:
	extra_h = dy
	if hud:
		hud.set_extra(dy)
	if touch:
		touch.dy = dy

func _pause() -> void:
	state = "pause"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # free mouse in menus
	hud.visible = false
	menu.species_locked = not is_safe_zone(player.center()) or player.tag_t > 0.0  # l'espèce se change dans la salle de spawn (zone sûre)
	menu.open_pause()

# ---------------------------------------------------------------- pixel particles / light animation
func _part_mat(glow: float, lit := false) -> ShaderMaterial:
	var sh: Shader = load("res://games/deepminer/shaders/pixel_particle.gdshader")
	if lit:
		var s2 := Shader.new()
		s2.code = sh.code.replace("unshaded, ", "")
		sh = s2
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("glow", glow)
	part_mats.append(m)
	return m

func _emitter(amount: int, lifetime: float, size: float, mat: ShaderMaterial, pm: ParticleProcessMaterial) -> GPUParticles3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	var g := GPUParticles3D.new()
	g.amount = amount
	g.lifetime = lifetime
	g.draw_pass_1 = q
	g.process_material = pm
	g.local_coords = false
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(World.SX + 40, World.SY + 40, World.SZ + 40))
	add_child(g)
	return g

static func _ramp(cols: Array, offs: Array) -> GradientTexture1D:
	var gr := Gradient.new()
	gr.colors = PackedColorArray(cols)
	gr.offsets = PackedFloat32Array(offs)
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	return gt

func _setup_particles() -> void:
	# mining chips (pool of one-shot bursts, colour set per burst)
	var chip_mat := _part_mat(1.0)
	for i in 8:
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.35, 0.35, 0.35)
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 75.0
		pm.initial_velocity_min = 1.5
		pm.initial_velocity_max = 3.2
		pm.gravity = Vector3(0, -12, 0)
		pm.damping_min = 0.5
		pm.damping_max = 1.5
		pm.scale_min = 1.0
		pm.scale_max = 1.8
		pm.color_ramp = _ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(0.7, 0.7, 0.7, 0.0)], [0.0, 0.6, 1.0])
		var g := _emitter(14, 0.7, 0.075, chip_mat, pm)
		g.one_shot = true
		g.explosiveness = 0.95
		g.emitting = false
		chip_pool.append(g)
	# embers above exposed lava (one emitter, emission points from the world)
	var pts: Array = world.lava_surface.duplicate()
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	if not pts.is_empty():
		var n := mini(pts.size(), 384)
		var img := Image.create(n, 1, false, Image.FORMAT_RGBF)
		for i in n:
			var p: Vector3 = pts[rng.randi_range(0, pts.size() - 1)]
			img.set_pixel(i, 0, Color(p.x + rng.randf_range(-0.5, 0.5), p.y, p.z + rng.randf_range(-0.5, 0.5)))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
		pm.emission_point_texture = ImageTexture.create_from_image(img)
		pm.emission_point_count = n
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 25.0
		pm.initial_velocity_min = 0.4
		pm.initial_velocity_max = 1.1
		pm.gravity = Vector3(0, 0.5, 0)
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.6
		pm.turbulence_noise_scale = 3.0
		pm.scale_min = 0.8
		pm.scale_max = 1.4
		pm.color_ramp = _ramp([Color(1.0, 0.95, 0.55, 1), Color(1.0, 0.55, 0.12, 1), Color(0.8, 0.18, 0.05, 0.0)], [0.0, 0.45, 1.0])
		_emitter(90, 2.6, 0.07, _part_mat(2.6), pm)
	# floating dust, lit by the scene lights (visible in torch / lamp light)
	var dm := ParticleProcessMaterial.new()
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dm.emission_box_extents = Vector3(11, 7, 11)
	dm.direction = Vector3(0, 1, 0)
	dm.spread = 180.0
	dm.initial_velocity_min = 0.03
	dm.initial_velocity_max = 0.15
	dm.gravity = Vector3(0, -0.02, 0)
	dm.turbulence_enabled = true
	dm.turbulence_noise_strength = 0.25
	dm.turbulence_noise_scale = 6.0
	dm.color = Color(1.0, 0.92, 0.8)
	dm.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)], [0.0, 0.5, 1.0])
	dust = _emitter(110, 7.0, 0.06, _part_mat(1.6, true), dm)
	dust.preprocess = 4.0

func chip_burst(c: Vector3i, id: int, ratio: float) -> void:
	var g: GPUParticles3D = chip_pool[chip_i]
	chip_i = (chip_i + 1) % chip_pool.size()
	var col: Color = World.MAPCOL[id]
	var pm: ParticleProcessMaterial = g.process_material
	pm.color = col.lightened(0.1)
	pm.hue_variation_min = -0.03
	pm.hue_variation_max = 0.03
	g.amount_ratio = ratio
	g.position = Vector3(c) + Vector3(0.5, 0.5, 0.5) - view_dir * 0.45
	g.restart()
	g.emitting = true

## Torches flicker (light energy), lava breathes, dust follows the view.
func _animate_lights(dt: float) -> void:
	anim_t += dt
	for c in torch_lights:
		var l: OmniLight3D = torch_lights[c][0]
		var h := float((c.x * 7 + c.y * 13 + c.z * 3) % 17)
		l.light_energy = 1.7 * (0.86 + 0.09 * sin(anim_t * 11.0 + h) + 0.06 * sin(anim_t * 23.0 + h * 2.0) + 0.04 * sin(anim_t * 5.3 + h))
	if dust:
		dust.position = cam_center + view_dir * 4.0

func _setup_env() -> void:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.008, 0.01, 0.024)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.52, 0.54, 0.68)
	e.ambient_light_energy = 0.62
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 5.0
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.glow_strength = 1.0
	e.glow_bloom = 0.02
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.set_glow_level(0, 0.0)
	e.set_glow_level(1, 1.0)
	e.set_glow_level(2, 0.6)
	e.set_glow_level(3, 0.3)
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 1.06
	var we := WorldEnvironment.new()
	we.environment = e
	add_child(we)

## --- PERF --- vue 3D en perspective (3e personne / FPS) : les morceaux de carte au-delà de PERSP_CULL blocs ne sont pas dessinés et les lumières
## lointaines s'éteignent (fondu). Vues à caméra reculée (2D / 3/4) : tout reste affiché (la caméra est à 80 blocs).
const PERSP_CULL := 72.0

func _light_fade(l: OmniLight3D, persp: bool) -> void:
	l.distance_fade_enabled = persp
	l.distance_fade_begin = 40.0
	l.distance_fade_length = 16.0

func apply_view_perf(persp: bool) -> void:
	for k in chunks:
		(chunks[k] as MeshInstance3D).visibility_range_end = PERSP_CULL if persp else 0.0
	for e in lights:
		_light_fade(e[0], persp)

func _add_light(p: Vector3, col: Color, rng_v: float, energy: float) -> Array:
	var l := OmniLight3D.new()
	l.light_color = col
	l.omni_range = rng_v
	l.light_energy = energy
	_light_fade(l, view == null or view.mode == ViewCtl.FPS)
	add_child(l)
	var entry := [l, p, Vector3i(floori(p.x), floori(p.y - 0.01), floori(p.z))]
	lights.append(entry)
	return entry

func _starter_torches() -> void:
	if hub_n:  # --- SPAWN HUB --- la salle a ses propres torches
		return
	var s := Vector3i(world.spawn)
	var placed := 0
	for dx in [-3, 3, -6, 6]:
		var c := Vector3i(s.x + dx, s.y + 1, s.z)
		if world.get_v(c) == World.AIR and placed < 2:
			world.set_v(c, World.TORCH)
			_add_torch_light(c)
			_remesh(c)
			placed += 1

func _overlay(m: int, mesh: Mesh) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://games/deepminer/shaders/overlay.gdshader")
	# (le repère de visée est testé en profondeur : il reste sur le bloc visé et disparaît derrière les blocs devant lui)
	mat.set_shader_parameter("mode", m)
	mat.render_priority = 2
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi

func _build_highlight() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(18.0, 18.0) / 16.0  # face + 1 texel of outline margin
	highlight = _overlay(0, q)
	hl_mat = highlight.material_override
	hl_mat.set_shader_parameter("cracks", _crack_tex())
	hl_mat_fine = ShaderMaterial.new()
	hl_mat_fine.shader = load("res://games/deepminer/shaders/overlay.gdshader")
	hl_mat_fine.set_shader_parameter("mode", 0)
	hl_mat_fine.set_shader_parameter("cracks", _crack_tex())
	hl_mat_fine.render_priority = 2
	preview = _overlay(1, q)
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	shadow = _overlay(2, pm)

## 4 crack stages (16x16 each, side by side); every stage extends the previous one.
static func _crack_tex() -> ImageTexture:
	var img := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var d8 := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
	var walks := []
	for w in [1, 5, 7, 3, 0, 4, 2]:  # main directions, most visible first
		var p := Vector2i(7 + rng.randi_range(-1, 1), 7 + rng.randi_range(-1, 1))
		var pts := [p]
		for i in 8:
			var k: int = w + (0 if rng.randf() < 0.6 else (1 if rng.randf() < 0.5 else -1))
			p = (p + d8[posmod(k, 8)]).clamp(Vector2i.ZERO, Vector2i(15, 15))
			pts.append(p)
		walks.append(pts)
	var counts := [2, 3, 5, 7]
	var lens := [3, 5, 7, 9]
	for k in 4:
		for w in counts[k]:
			for i in lens[k]:
				var p: Vector2i = walks[w][i]
				img.set_pixel(p.x + k * 16, p.y, Color(0, 0, 0, 1))
	return ImageTexture.create_from_image(img)

## Normal of the face hit by a raycast result (prev is the cell the ray came from).
static func target_face(r: Dictionary) -> Vector3i:
	if r.is_empty():
		return Vector3i.ZERO
	var n: Vector3i = r.prev - r.cell
	return n if absi(n.x) + absi(n.y) + absi(n.z) == 1 else Vector3i.ZERO

## Repère libre posé sur le point visé (suit la souris, pas la grille) : couvre la zone qu'un coup de pioche creuse.
func _put_reticle(mi: MeshInstance3D, hit: Vector3, n: Vector3) -> void:
	var x := Vector3(1, 0, 0) if absf(n.x) < 0.5 else Vector3(0, 0, 1)
	mi.basis = Basis(x, n.cross(x), n).scaled(Vector3(0.7, 0.7, 1.0))
	mi.position = hit + n * 0.02 + cam.basis.z * 0.04
	mi.visible = true

## Emplacements [cellule, bit] que la pose actuelle remplirait (taille 1 morceau / 4 = plaque / 8 = bloc entier).
func place_spots() -> Array:
	var out: Array = []
	if not target.has("piece") or target.pn == Vector3i.ZERO:
		return out
	var p: Vector3 = target.hit + Vector3(target.pn) * 0.25
	var c := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	var b := int(floorf((p.x - c.x) * 2.0)) + 2 * int(floorf((p.y - c.y) * 2.0)) + 4 * int(floorf((p.z - c.z) * 2.0))
	if not world.in_bounds(c):
		return out
	if place_size == 1:
		out.append([c, b])
		return out
	var a := 0
	for k in 3:
		if target.pn[k] != 0:
			a = k
	for q in 8:
		if place_size == 8 or ((q >> a) & 1) == ((b >> a) & 1):
			out.append([c, q])
	return out

## Fantôme de la pose (mode fin) : où les morceaux iront, avant de cliquer.
func _show_place_ghost() -> void:
	preview.visible = false
	var item: int = hotbar[sel]
	if item < 0 or World.KIND[item] != World.K_CUBE or (int(frac.get(item, 0)) <= 0 and inv.get(item, 0) <= 0):
		return
	var sp := place_spots()
	if sp.is_empty():
		return
	var c: Vector3i = sp[0][0]
	var cur := world.get_v(c)
	if not (cur == World.AIR or cur == item):
		return
	var n := Vector3(target.pn)
	var a := 0
	for k in 3:
		if n[k] != 0.0:
			a = k
	var sgn := n[a]
	var pos := Vector3(c) + Vector3(0.5, 0.5, 0.5)
	var sc := 1.0
	if place_size == 1:
		var b: int = sp[0][1]
		pos = Vector3(c) + (Vector3(b & 1, (b >> 1) & 1, (b >> 2) & 1) + Vector3(0.5, 0.5, 0.5)) * 0.5
		pos[a] += sgn * 0.25
		sc = 0.5
	elif place_size == 4:
		var b4: int = sp[0][1]
		pos[a] = c[a] + 0.5 * float((b4 >> a) & 1) + (0.5 if sgn > 0.0 else 0.0)
	else:
		pos[a] = c[a] + (1.0 if sgn > 0.0 else 0.0)
	var x := Vector3(1, 0, 0) if absf(n.x) < 0.5 else Vector3(0, 0, 1)
	preview.basis = Basis(x, n.cross(x), n).scaled(Vector3(sc, sc, 1.0))
	preview.position = pos + n * 0.003 + cam.basis.z * 0.04
	preview.visible = true

## Surcouche sur la face d'un morceau (1/2 bloc) du bloc c : b = bit du morceau, n = normale de la face.
func _put_on_piece(mi: MeshInstance3D, c: Vector3i, b: int, n: Vector3) -> void:
	var x := Vector3(1, 0, 0) if absf(n.x) < 0.5 else Vector3(0, 0, 1)
	mi.basis = Basis(x, n.cross(x), n).scaled(Vector3(0.5, 0.5, 1.0))
	mi.position = Vector3(c) + (Vector3(b & 1, (b >> 1) & 1, (b >> 2) & 1) + Vector3(0.5, 0.5, 0.5)) * 0.5 + n * 0.253 + cam.basis.z * 0.04
	mi.visible = true

## Places an overlay quad on the face of cell c with normal n, nudged toward the camera (ortho: depth only).
func _put_on_face(mi: MeshInstance3D, c: Vector3i, n: Vector3) -> void:
	var x := Vector3(1, 0, 0) if absf(n.x) < 0.5 else Vector3(0, 0, 1)
	mi.basis = Basis(x, n.cross(x), n)
	mi.position = Vector3(c) + Vector3(0.5, 0.5, 0.5) + n * 0.512 + cam.basis.z * 0.03
	mi.visible = true

# ---------------------------------------------------------------- view / camera
func view_label() -> String:
	if view and view.off_cut():  # --- VIEW ---
		return view.label()
	var n := ["X", "Y", "Z"]
	var ra := Hud._axis(right)
	var ua := Hud._axis(up_s)
	var va := Hud._axis(view_dir)
	var plane := "%s/%s" % [n[mini(ra, ua)], n[maxi(ra, ua)]]
	var kind := "dessus" if top_view else ("latérale" if va == 2 else "profil")
	return "Vue %s (%s)  regard %s%s" % [plane, kind, "+" if view_dir[va] > 0 else "-", n[va]]

func _apply_view() -> void:
	if view and view.off_cut():  # --- VIEW --- iso/FPS: never re-enable the cut or the lane lock
		view.set_mode(view.mode)
		return
	var rot := Basis(Vector3.UP, yaw_k * PI / 2.0)
	if top_view:
		view_dir = Vector3.DOWN
		up_s = (rot * Vector3(0, 0, -1)).round()
	else:
		view_dir = (rot * Vector3(0, 0, -1)).round()
		up_s = Vector3.UP
	right = (rot * Vector3(1, 0, 0)).round()
	var old_cut := Vector2i(cut_axis, cut_sign)
	cut_axis = Hud._axis(view_dir)
	cut_sign = 1 if view_dir[cut_axis] > 0 else -1
	var b := Basis(right, up_s, -view_dir)
	b = Basis(right, -deg_to_rad(minf(tilt, 10.0) if top_view else tilt)) * b
	if diorama and not top_view:  # extra yaw: tops and sides of the blocks; axes/cut stay aligned
		b = Basis(Vector3.UP, deg_to_rad(DIORAMA_YAW)) * b
	rot_from = (Basis(Vector3.UP, -turn_off) * cam.basis).get_rotation_quaternion()
	rot_to = b.get_rotation_quaternion()
	depth_goal = NAN
	rot_t = 0.0
	# (the view never touches the player: no lane lock, no re-centring; the shown layer derives from his position)
	_set_param("cut_dir", view_dir)
	for m in part_mats:
		m.set_shader_parameter("cut_dir", view_dir)
	_set_param("fog_len", 7.0 if top_view else 10.0)
	cut_layer = -999
	_update_cut()
	if old_cut != Vector2i(cut_axis, cut_sign):  # new cut plane: peel the front layers away
		cap_old.mesh = null
		cut_cur = cut_goal - 2.0
	cam_focus = player.center()
	map_t = 0.0

func _set_param(n: String, v: Variant) -> void:
	mat_s.set_shader_parameter(n, v)
	mat_f.set_shader_parameter(n, v)

## Un bloc constructible est en main (E : angle stable, molette = plan visé).
func is_building() -> bool:
	var item: int = hotbar[sel] if sel < hotbar.size() else -1
	return item >= 0 and World.KIND[item] == World.K_CUBE and inv.get(item, 0) > 0

func _player_layer() -> int:
	if cut_axis == 1:
		return floori(player.pos.y + 0.05)
	# free 3D movement: the shown layer derives from the position, with hysteresis (no flicker on a boundary)
	var p: float = player.pos[cut_axis]
	var off: int = cam_ctl.plane_off  # plan regardé décalé (construction) ; le joueur ne bouge pas
	var cur: int = (cut_layer - off) if cut_layer != -999 else int(layer_mem.get(cut_axis, -999))  # a rotation keeps the layer
	var L := floori(p)
	if cur != -999 and p >= cur - LAYER_HYST and p < cur + 1.0 + LAYER_HYST:
		L = cur
	layer_mem[cut_axis] = L
	return L + off

const LAYER_HYST := 0.35

func cut_depth_of(L: int) -> float:
	return float(L) if cut_sign > 0 else -float(L + 1)

func _update_cut() -> void:
	var L := _player_layer()
	if L == cut_layer:
		_cap_follow()
		return
	if cut_layer != -999:
		cap_old.mesh = cap.mesh
	cut_layer = L
	cut_goal = cut_depth_of(L)
	_set_param("fog_depth", cut_goal)
	_build_cap2d()
	_update_lights()

## --- PERF --- the 2D cap covers a window around the player (the 2D view shows ~40x22 blocks); rebuilt when
## the player has walked half of it, the layer changes, or an edit touches the layer.
const CAP_R := 34
var cap_at := Vector3i(-1000, -1000, -1000)

func _build_cap2d() -> void:
	cap_at = Vector3i(player.pos.floor())
	cap.mesh = world.build_cap(cut_axis, cut_sign, cut_layer, mat_s, mat_f, cap_at, CAP_R)

func _cap_follow() -> void:
	if cut_layer != -999 and Vector3(Vector3i(player.pos.floor()) - cap_at).length() > CAP_R / 2.0:
		_build_cap2d()

func _animate_cut(dt: float, instant := false) -> void:
	cut_cur = cut_goal if instant else move_toward(cut_cur, cut_goal, dt * maxf(CUT_SPEED, absf(cut_goal - cut_cur) * 6.0))
	_set_param("cut_depth", cut_cur)
	for m in part_mats:  # particles follow the 2D cut only when 2D is the main view
		m.set_shader_parameter("cut_depth", cut_cur if not (view and view.off_cut()) else -1000.0)
	if cut_cur == cut_goal:
		cap_old.mesh = null

func cell_visible(c: Vector3i) -> bool:
	if view and view.off_cut():  # --- VIEW ---
		return true
	if c[cut_axis] >= cut_layer if cut_sign > 0 else c[cut_axis] <= cut_layer:
		return true
	if cut_axis == 1:
		return false
	if c.y < front_y:  # camera side: below the player's ground level
		return true
	# camera side, above the feet: mirrors the shader (the 2 nearest layers, or all of them in a tight spot, are cut;
	# farther ones stay, except the blocks standing in the line of sight, which are see-through = not pickable)
	var fr: int = (cut_layer - c[cut_axis]) if cut_sign > 0 else (c[cut_axis] - cut_layer)
	if narrow_cut or fr <= 2 or fr > 64:
		return false
	var id := world.get_v(c)
	if not (id == World.BRICK or id == World.TORCH or id == World.CHEST or (id >= World.SIGN and id != World.WARMROCK and id != World.AMBER)):  # natural rock above the feet is hidden
		return false
	return not _in_line_of_sight(c)

## Same test as the shader's occludes(): the cell lies between the camera and the player (about 1 block around the line).
func _in_line_of_sight(c: Vector3i) -> bool:
	var cc := Vector3(c) + Vector3(0.5, 0.5, 0.5)
	var pc := Vector3(player.pos.x, player.pos.y + 0.9, player.pos.z)
	var cp := cam.global_position
	var ab := pc - cp
	var t := (cc - cp).dot(ab) / maxf(ab.dot(ab), 0.0001)
	if t <= 0.0 or t >= 1.0:
		return false
	return (cc - (cp + ab * t)).length() < 2.0 and (cc - pc).length() > 0.9  # a bit wider than the shader (1.15): aiming goes through to the floor

## Camera-side cut height: the player's ground level on the grid. Follows real climbs / descents when grounded,
## never rises during a jump or a swim (only goes down if the player drops below it).
func _update_front_y() -> void:
	mat_f.set_shader_parameter("pfeet", player.pos.y)
	var g := floori(player.pos.y + 0.05)
	if player.on_ground or front_y == -1000 or g < front_y:
		if g != front_y:
			front_y = g
			_set_param("feet_y", float(front_y))
			_update_lights()

func _update_lights() -> void:
	for e in lights:
		var l: OmniLight3D = e[0]
		l.position = e[1] - view_dir * 1.6
		l.visible = cell_visible(e[2]) and (fog == null or fog.is_seen(e[2]))  # light sources count only if seen

func _update_camera(dt: float, instant := false) -> void:
	if view and view.camera(dt, instant):  # --- VIEW ---
		return
	rot_t = 1.0 if instant else minf(rot_t + dt / ROT_TIME, 1.0)
	cam.basis = Basis(rot_from.slerp(rot_to, smoothstep(0.0, 1.0, rot_t)))
	if not testing:
		_update_yaw(dt, get_viewport().get_mouse_position() if touch == null else Vector2(320, 180))
	if absf(yaw_cur) > 0.01:  # mouse yaw: orbit around the focus (picking uses the real camera)
		cam.basis = Basis(Vector3.UP, deg_to_rad(yaw_cur)) * cam.basis
	if not testing:
		turn_step(float(int(Input.is_physical_key_pressed(KEY_Q)) - int(Input.is_physical_key_pressed(KEY_E))) - hud.joy.vec.x, dt)
		joy_pitch = clampf(joy_pitch + hud.joy.vec.y * 40.0 * dt, -25.0, 25.0)
	if turn_off != 0.0:
		cam.basis = Basis(Vector3.UP, turn_off) * cam.basis
	cam_ctl.update(0.0 if instant else dt, self, is_building())
	if cam_ctl.free < 4.5:  # tight spot (tunnel...): cut the front layers like before; open space: only the line of sight is ghosted
		narrow_cut = true
	elif cam_ctl.free > 6.0:
		narrow_cut = false
	_set_param("narrow", narrow_cut)
	var spd := clampf(player.vel.length() / 7.0, 0.0, 1.0)
	amb_speed = lerpf(amb_speed, spd, 1.0 - exp(-dt * 3.0))
	amb_t += dt
	var sway: float = sin(amb_t * 0.45) * 2.0 * (1.0 - clampf(spd * 3.0, 0.0, 1.0)) * [0.0, 0.6, 1.0][amb]  # idle drift: far layers slide faster than near ones
	if absf(sway) > 0.001:
		cam.basis = Basis(Vector3.UP, deg_to_rad(sway)) * cam.basis
	if absf(cam_ctl.yaw) > 0.001:  # CameraCtl: pivot de profondeur / inclinaison de puits (lissés)
		cam.basis = Basis(Vector3.UP, deg_to_rad(cam_ctl.yaw)) * cam.basis
	if absf(cam_ctl.pitch + joy_pitch) > 0.001:
		cam.basis = Basis(cam.basis.x, deg_to_rad(cam_ctl.pitch + joy_pitch)) * cam.basis
	var zt: float = ZOOMS[zoom_i] * cam_ctl.zoom
	cam.size = zt if instant else lerpf(cam.size, zt, 1.0 - exp(-dt * 14.0))
	_animate_cut(dt, instant)
	# dead zone: the focus only follows when the player leaves a small screen box
	var pc := vis_center()
	var d := pc - cam_focus
	var dx := d.dot(right)
	var dy := d.dot(up_s)
	cam_focus += right * (dx - clampf(dx, -DEAD_ZONE.x, DEAD_ZONE.x)) + up_s * (dy - clampf(dy, -DEAD_ZONE.y, DEAD_ZONE.y)) + view_dir * d.dot(view_dir)
	# look ahead in the walking direction
	if absf(player.vel.dot(right)) > 0.5:
		look = move_toward(look, player.facing * LOOK_AHEAD, dt * 3.0)
	if instant:
		cam_focus = pc
		look = 0.0
	var tgt := cam_focus + right * (cam_offset.x + look) + up_s * (cam_offset.y + cam_ctl.vy)
	cam_center = tgt if instant else cam_center.lerp(tgt, 1.0 - exp(-dt * 7.0))
	var px: float = cam.size / 360.0
	var bx := cam.basis.x
	var by := cam.basis.y
	var lv: float = [0.0, 0.6, 1.0][amb] if not (view and view.off_cut()) else 0.0
	_set_param("warp_k", 0.03 * (1.0 + 0.4 * amb_speed) * lv)
	_set_param("curve_k", 0.0012 * lv)
	_set_param("ppos_y", player.pos.y + 0.9)
	if persp_2d and not grow_far:  # light perspective: deeper layers shrink and converge, distance reads at a glance
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = PERSP_FOV
		cam.near = 0.1
		cam.far = 300.0
		cam.position = cam_center + cam.basis.z * (cam.size * 0.5 / tan(deg_to_rad(PERSP_FOV * 0.5)))
	else:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.position = place_cam(cam.basis, cam_center, px, cam_center.distance_to(tgt) > px * 0.5)
	if shake > 0.0:
		cam.position += (bx * randf_range(-1.0, 1.0) + by * randf_range(-1.0, 1.0)) * snappedf(shake * 0.35, px)

## --- PERF --- ortho camera 80 units back; snapped to the pixel grid only when it rests (crisp still image,
## smooth motion: snapping while moving made the scenery step against the sub-pixel player).
static func place_cam(b: Basis, c: Vector3, px: float, moving: bool) -> Vector3:
	var x := c.dot(b.x)
	var y := c.dot(b.y)
	if not moving:
		x = snappedf(x, px)
		y = snappedf(y, px)
	return b.x * x + b.y * y + b.z * (c.dot(b.z) + 80.0)

# ---------------------------------------------------------------- input
## Point visé à l'écran (canvas) : souris, ou dernier toucher sur téléphone (devant le joueur tant qu'on n'a rien touché).
func aim_pos() -> Vector2:
	if touch == null:
		return get_viewport().get_mouse_position()
	if touch.has_aim:
		return touch.aim
	return cam.unproject_position(player.center()) + Vector2(player.facing * 24.0, 0.0)

## Bouton de minage tenu : clic gauche, ou bouton « Miner » tactile (le toucher du monde ne mine pas, il vise).
func mine_pressed() -> bool:
	if touch != null and touch.mine:
		return true
	return not ext_block and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and (touch == null or touch.mouse_sim)

func input_blocked() -> bool:
	return ext_block or (chat != null and chat.is_open) or (hub_n != null and hub_n.typing())

func _key(k: Key) -> bool:
	return not input_blocked() and Input.is_physical_key_pressed(k)

## Movement keys: (mx, mz, jump). Nothing while the chat / a command / a sign is being typed.
func read_controls() -> Vector3:
	var c := Vector3.ZERO
	if prof_s > 0.0:  # --- PERF --- auto-walk: 2 s right, 2 s left, jump now and then
		c.x = 1.0 if fmod(prof_t, 4.0) < 2.0 else -1.0
		c.z = 1.0 if fmod(prof_t, 1.5) < 0.2 else 0.0
		return c
	if view and view.free_cam():  # free camera: the keys move the camera
		c.z = 1.0 if _key(KEY_SPACE) else 0.0
		return c
	if _key(KEY_D): c.x += 1.0
	if _key(KEY_A): c.x -= 1.0
	if _key(KEY_W): c.y += 1.0
	if _key(KEY_S): c.y -= 1.0
	if touch != null:  # joystick de marche (x : marche, y : changer de couche) + bouton saut
		if absf(touch.move.x) > 0.3: c.x += signf(touch.move.x)
		if absf(touch.move.y) > 0.55: c.y -= signf(touch.move.y)
		c.x = clampf(c.x, -1.0, 1.0)
		c.y = clampf(c.y, -1.0, 1.0)
	c.z = 1.0 if (_key(KEY_SPACE) or (touch != null and touch.jump)) else 0.0
	return c

func _unhandled_input(ev: InputEvent) -> void:
	if input_blocked() or state != "play":
		return
	if builder and builder.handle_input(ev):  # chantier : C, R, Échap, clic de confirmation
		return
	if view and view.input(ev):  # --- VIEW ---
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if not (view and view.off_cut()) and ev.physical_keycode in [KEY_Q, KEY_E]:  # A / E (AZERTY): turn 90°
			return  # held: continuous turn (turn_step in _update_camera)
		if view and view.off_cut() and ev.keycode in [KEY_C, KEY_R, KEY_TAB, KEY_T, KEY_Y]:  # --- VIEW --- cut-view keys only
			return
		match ev.keycode:
			KEY_C:
				if top_view:
					top_view = false
					yaw_k -= 1
				elif yaw_k % 2 == 0:
					yaw_k += 1
				else:
					top_view = true
				yaw_k = posmod(yaw_k, 4)
				_apply_view()
				hud.toast(view_label().split("  ")[0])
			KEY_R:  # alias of E
				turn_view(-1)
			KEY_TAB:
				# swap side <-> depth: turn 90° one way, then back the other way
				top_view = false
				yaw_k = posmod(yaw_k + swap_dir, 4)
				swap_dir = -swap_dir
				_apply_view()
				hud.toast("Bascule côté / profondeur  -  " + view_label().split("  ")[0])
			KEY_T:
				tilt = 12.0 if tilt > 20.0 else (0.0 if tilt > 0.0 else 32.0)
				_apply_view()
			KEY_Y:
				diorama = not diorama
				_apply_view()
				hud.toast("Mode diorama " + ("activé" if diorama else "désactivé") + ("  (vues de côté)" if top_view else ""))
			KEY_F3:
				perf_on = not perf_on
				if perf_lbl:
					perf_lbl.visible = perf_on
			KEY_U:
				amb = (amb + 1) % 3
				grow_far = amb > 0
				hud.toast("Ambiance de la vue : " + ["coupée", "discrète", "pleine"][amb] + "  (U)")
			KEY_K:
				persp_2d = not persp_2d
				hud.toast("Vue 2D : " + ("perspective" if persp_2d else "plate"))
			KEY_L:
				yaw_on = not yaw_on
				hud.toast("Inclinaison vers la souris : " + ("activée" if yaw_on else "coupée"))
			KEY_H:
				hud.toggle_help()
			KEY_I:  # inventaire
				bag.open()
			KEY_B:  # grande carte
				world_map.open()
			KEY_M:  # manuel : livre de recettes (F près d'une fonderie l'ouvre aussi)
				book.open()
			KEY_J:  # torches (F is the interaction now)
				if inv.get(World.COAL, 0) > 0:
					inv[World.COAL] -= 1
					inv[World.TORCH] = inv.get(World.TORCH, 0) + player.torch_craft
					hud.toast("%d torches fabriquées" % player.torch_craft)
				else:
					hud.toast("Il faut 1 charbon pour fabriquer des torches")
			KEY_F:
				_interact()
			KEY_G:
				abilities.trigger()
			KEY_N:
				use_apple()
			KEY_F4:
				set_fine(not fine_mode)
			KEY_F5:
				if fine_mode:
					place_size = {1: 4, 4: 8, 8: 1}[place_size]
					_fine_label()
			KEY_O:
				_drop_item()
			KEY_F9:
				if f9_t > 0.0:
					_new_game()
				else:
					f9_t = 3.0
					hud.toast("F9 encore une fois : nouvelle partie (la sauvegarde sera effacée)")
			KEY_ESCAPE:
				_pause()
		var pk: int = ev.physical_keycode
		if pk >= KEY_1 and pk <= KEY_8:
			sel = pk - KEY_1
	elif ev is InputEventMouseButton:
		if ev.pressed and is_building() and (not view or not view.off_cut()) and (ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			cam_ctl.plane_off = clampi(cam_ctl.plane_off + (1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else -1), -2, 2)
			cut_layer = -999  # le plan regardé change, le joueur reste
			_update_cut()
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_i = maxi(zoom_i - 1, 0)
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_i = mini(zoom_i + 1, ZOOMS.size() - 1)
		elif ev.button_index == MOUSE_BUTTON_MIDDLE:
			mid_drag = ev.pressed
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			if ev.pressed:  # right-drag turns / tilts the camera; a short right click still uses the item
				r_drag = true
				r_dist = 0.0
			else:
				r_drag = false
				if r_dist < 5.0:
					use_item()
	elif ev is InputEventMouseMotion and r_drag:
		r_dist += ev.relative.length()
		if r_dist >= 5.0 and not (view and view.off_cut()) and not top_view:
			turn_by(-ev.relative.x * 0.006)
			joy_pitch = clampf(joy_pitch + ev.relative.y * 0.12, -25.0, 25.0)
	elif ev is InputEventMouseMotion and mid_drag:
		var k: float = cam.size / 360.0
		cam_offset += Vector2(-ev.relative.x, ev.relative.y) * k

## Un lieu est découvert quand on passe près de lui (marqueur permanent sur la carte).
func _discover_pois() -> void:
	if pois_found.size() != world.pois.size():
		pois_found.resize(world.pois.size())
		pois_found.fill(false)
	var pc := player.center()
	for i in world.pois.size():
		var p: Dictionary = world.pois[i]
		if not pois_found[i] and pc.distance_to(p.pos) < float(p.r) + 14.0 and world.poi_exists(p):
			pois_found[i] = true
			if not testing:
				hud.toast("Lac découvert (marqué sur la carte)" if p.kind == "lac" else "Jardin de cristaux découvert (marqué sur la carte)")

## Grande carte : mêmes données que la mini-carte, en grand.
func refresh_big_map() -> void:
	_discover_pois()
	var dots: Array = []
	for m in miners:
		if (m as Miner).active:
			dots.append([(m as Miner).center(), (m as Miner).color])
	world_map.big.refresh(world, player.center(), world.pois, pois_found, dots, true)

func _pf(key: String, t0: int) -> int:
	var t := Time.get_ticks_usec()
	if prof_s > 0.0:
		prof[key] = prof.get(key, 0) + (t - t0)
		prof["max " + key] = maxi(prof.get("max " + key, 0), t - t0)
	return t

func _process(dt: float) -> void:
	_stream_tick()
	if perf_lbl == null and not testing and hud != null:
		perf_lbl = Label.new()
		perf_lbl.position = Vector2(250, 2)
		perf_lbl.add_theme_font_size_override("font_size", 9)
		perf_lbl.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
		hud.add_child(perf_lbl)
	if perf_on and perf_lbl:
		perf_max = maxf(perf_max, dt * 1000.0)
		perf_t += dt
		if perf_t >= 0.5:
			perf_lbl.text = "%d FPS  image %.1f ms  pire %.1f ms  physique %d Hz" % [Engine.get_frames_per_second(), dt * 1000.0, perf_max, Engine.physics_ticks_per_second]
			perf_t = 0.0
			perf_max = 0.0
	if not testing and view and view.off_cut():  # 3D views: the same shake (abilities decay it) as a small lens offset
		cam.h_offset = randf_range(-1.0, 1.0) * shake * 0.12
		cam.v_offset = randf_range(-1.0, 1.0) * shake * 0.12
	if state != "pause":  # --- PERF --- camera per rendered frame, on the interpolated player position
		_update_camera(dt)
	if prof_s > 0.0 and state == "play":
		prof_ft.append(dt * 1000.0)
		if dt > 0.02:
			print("[PROF] à-coup %.0f ms à t=%.2f s" % [dt * 1000.0, prof_t])

## --dm-prof: walk back and forth, then print the report.
func _prof_tick(dt: float) -> void:
	prof_frames += 1
	prof_t += dt
	if prof_t >= prof_s:
		var tot := 0
		for k in prof:
			if not k.begins_with("max "):
				tot += int(prof[k])
		var ks: Array = prof.keys()
		ks.sort_custom(func(x, y): return prof[x] > prof[y])
		print("[PROF] %d frames physiques, %.1f s ; temps script moyen %.2f ms/frame" % [prof_frames, prof_t, tot / 1000.0 / prof_frames])
		for k in ks:
			if not k.begins_with("max "):
				print("[PROF]   %-12s %6.2f ms/frame   max %6.1f ms" % [k, prof[k] / 1000.0 / prof_frames, prof["max " + k] / 1000.0])
		var ft: Array = prof_ft.duplicate()
		ft.sort()
		var n := ft.size()
		if n > 0:
			var avg := 0.0
			for x in ft:
				avg += x
			avg /= n
			var slow := ft.filter(func(x): return x > 20.0).size()
			print("[PROF] images : %d, moy %.1f ms (%.0f FPS), médiane %.1f, p95 %.1f, max %.1f ms, >20 ms : %d" % [n, avg, 1000.0 / avg, ft[n / 2], ft[int(n * 0.95)], ft[n - 1], slow])
		exit_requested.emit()

func _physics_process(dt: float) -> void:
	if state == "menu":  # fond du menu : le mineur au repos, la camera derive doucement
		menu_t += dt
		cam_offset = Vector2(sin(menu_t * 0.25) * 6.0, 1.5)
		move_player(dt, 0, 0, false)
		view.tick(dt)
		return
	if state == "pause":
		return
	var pt := Time.get_ticks_usec()
	if prof_s > 0.0:
		_prof_tick(dt)
	var busy := input_blocked()  # chat / command / sign: no game key at all
	var ctl := read_controls()
	var pan := Vector2.ZERO
	if _key(KEY_LEFT): pan.x -= 1
	if _key(KEY_RIGHT): pan.x += 1
	if _key(KEY_UP): pan.y += 1
	if _key(KEY_DOWN): pan.y -= 1
	cam_offset += pan * dt * cam.size * 0.6
	var crouch := _key(KEY_ALT) or _key(KEY_CTRL) or (touch != null and touch.crouch)  # Alt / Ctrl : s'accroupir (sneak)
	player.crouching = crouch
	var sw_on: bool = hotbar[sel] == -3 and int(gear.get("sword", 0)) > 0  # épée sélectionnée dans la barre : portée, dégâts et cadence de l'épée
	if sw_on != _sword_on:
		_sword_on = sw_on
		if DMNet.i.is_client():
			DMNet.i.send_gear(gear_active())
	player.sword = int(gear.get("sword", 0)) if sw_on else 0
	player.dmg_mult = Gear.dmg_mult(gear, sw_on)
	tool_mine = 0.35 if sw_on else 1.0  # l'épée creuse mal : la pioche pour miner
	player.set_held_tool("torch" if hotbar[sel] == World.TORCH else ("sword" if sw_on else "pick"))
	player.running = _key(KEY_SHIFT) and not crouch  # Shift: run (x1.0), Ctrl: crouch
	if crouch and not crouch_was:
		broadcast_action("player", player, "crouch")
	crouch_was = crouch
	if abilities.is_charging():
		ctl.x = float(player.facing)
		ctl.y = 0.0
	_update_load(dt)
	abilities.update(dt)
	pt = _pf("abil", pt)
	move_player(dt, ctl.x, ctl.y, ctl.z > 0.5)
	pt = _pf("move", pt)
	var fp := fog.passes
	fog.torches = torch_lights.keys()
	fog.tick(player.feet_cell(), player.body_cells())
	if fog.passes != fp:
		_update_lights()
	pt = _pf("fog", pt)
	_mining(dt, mine_pressed() and not busy and not builder.blocks_mining() and not goto_sel and not hud.joy.drag and not (view and (view.free_cam() or view.fps.cam_drag)))
	pt = _pf("mining", pt)
	tick_miners(dt)
	pt = _pf("miners", pt)
	_update_drops(dt)
	pt = _pf("drops", pt)
	_update_social(dt)
	pt = _pf("social", pt)
	_fluid_step(dt)
	pt = _pf("fluid", pt)
	_flush_remesh()
	pt = _pf("remesh", pt)
	view.tick(dt)
	pt = _pf("camera+iso", pt)
	pt = _pf("eyecam", pt)
	_update_inspect()
	pt = _pf("inspect", pt)
	f9_t -= dt
	save_t += dt
	if save_t >= AUTOSAVE:
		save_t = 0.0
		if save_game(SAVE_PATH):
			print("[DM] sauvegarde auto")
	_update_shadow()
	_animate_lights(dt)
	pt = _pf("lights", pt)
	map_t -= dt
	if map_t <= 0.0:
		map_t = 0.4
		var dots: Array = []
		for m in miners:
			if (m as Miner).active:  # online players always on the map; out of sight = dimmed
				var mc: Color = (m as Miner).color
				dots.append([(m as Miner).center(), mc if (m as Miner).visible else mc.darkened(0.55)])
		_discover_pois()
		hud.map_canvas.refresh(world, player.center(), world.pois, pois_found, dots)
		pt = _pf("minimap", pt)
	hud.set_ability(DMSettings.ability().name, abilities.ready_ratio(), abilities.cd, abilities.active_t > 0.0)
	Stacks.reconcile(self)
	hud.pick_style = [int(gear.sharp), int(gear.kb), int(gear.thorns)]
	hud.map_canvas.step(world)  # recalcul de la mini-carte réparti sur les images
	hud.refresh(player.health, player.pos, view_label(), hotbar, hotbar_n, sel, dt)
	hud.set_hurt(player.flash_t / 0.25, dt)  # vignette rouge quand on encaisse un coup
	pt = _pf("hud0", pt)
	hud.set_planes(cut_layer, cam_ctl.plane_off, not top_view and not (view and view.off_cut()))
	hud.set_depth(cut_layer, not top_view and not (view and view.off_cut()), player.lane_target(cut_sign, world) != null, player.lane_target(-cut_sign, world) != null)
	pt = _pf("hud", pt)
	if shot_path != "":
		frames += 1
		if frames == 150:
			get_viewport().get_texture().get_image().save_png(shot_path)
			print("[DM] capture: ", shot_path)
			exit_requested.emit()

## Fonderie posée à moins de 3 blocs du joueur (ou null).
func _forge_near() -> Variant:
	var p := Vector3i(player.center().floor())
	for dx in range(-3, 4):
		for dy in range(-2, 3):
			for dz in range(-3, 4):
				var c := p + Vector3i(dx, dy, dz)
				if world.in_bounds(c) and world.get_v(c) == World.FORGE:
					return c
	return null

## Charge du sac : recalculée 4 fois par seconde ; ralentit au-delà de la capacité de l'espèce.
func _update_load(dt: float) -> void:
	load_t -= dt
	if load_t > 0.0:
		return
	load_t = 0.25
	var wt := Carry.weight(inv)
	var cap := DMSettings.carry_cap()
	player.load_mult = Carry.speed_mult(wt, cap)
	hud.set_load(wt, cap)

## O : jeter 10 de l'objet sélectionné (pour alléger le sac).
func _drop_item() -> void:
	var item: int = hotbar[sel]
	if item < 0 or inv.get(item, 0) <= 0:
		return
	var n := mini(10, int(inv[item]))
	inv[item] -= n
	hud.toast("Jeté : %d %s" % [n, World.NAMES[item]])

var bubble_t := 0.0

## Éclaboussure en entrant / sortant de l'eau, bulles quand on plonge.
func _water_fx(dt: float) -> void:
	if chip_pool.is_empty():
		return
	if player.splash_flag:
		player.splash_flag = false
		DMSfx.play("splash", null, -2.0)
		chip_burst(Vector3i(floori(player.pos.x), floori(player.water_surface(world)) - 1, floori(player.pos.z)), World.WATER, 1.0)
	if player.swimming and player.dive:
		bubble_t -= dt
		if bubble_t <= 0.0:
			bubble_t = 0.35
			chip_burst(Vector3i(player.center().floor()) + Vector3i(0, 1, 0), World.WATER, 0.25)

## mz: continuous in top view; otherwise Z/S move one layer deeper/closer (W = into the screen).
var zombies: Array = []  # zombies lents (hôte / solo ; pas sauvegardés)
var zombie_t := 4.0
var zid_n := 0
var zpuppets := {}  # client : id réseau -> Zombie (suit l'hôte)
var zombies_off := false  # /zombies off
const ZOMBIE_MAX := 7
var pvp_last_hit := 0  # hôte : dernier coup PvP du joueur local (ms)
var place_size := 1  # mode fin, pose : 1 morceau, 4 (plaque) ou 8 (bloc entier) ; F5
var fine_mode := true  # creusage libre par défaut (F4 : mode bloc entier)  # F4 : mode fin, la pioche / la pose travaillent par morceaux de 1/8 de bloc
var frac := {}  # id de bloc -> morceaux (1/8) en poche, en plus des blocs entiers de l'inventaire
var gear := Gear.fresh()  # armures, enchantements, pommes (voir scripts/gear.gd)
var goto_sel := false  # Ctrl held: choosing an auto-walk destination
var go_path: Array = []  # click-to-walk cells (feet)
var go_stuck := 0.0

func move_player(dt: float, mx: float, mz: float, jump: bool) -> void:
	var wish := right * mx
	if view and view.off_cut():  # --- VIEW ---
		wish = view.wish(mx, mz)
	elif top_view:
		wish += up_s * mz
	else:  # 2D side view: Z/S held a moment = glide to the next layer's centre (the cut follows)
		wish += view_dir * _depth_intent(dt, mz)
	if player.running and not (view and view.off_cut()):  # Shift: run toward the mouse (diagonals across layers)
		var mp := aim_pos()
		var ro := cam.project_ray_origin(mp)
		var rd := cam.project_ray_normal(mp)
		if absf(rd.y) > 0.01:
			var tt := (player.pos.y + 0.05 - ro.y) / rd.y
			if tt > 0.0:
				var g := ro + rd * tt - player.pos
				g.y = 0.0
				if g.length() > 0.6:
					wish = g.normalized()
	if not go_path.is_empty():  # click-to-walk: follow the path cell by cell
		var nc: Vector3i = go_path[0]
		var dd := Vector3(nc.x + 0.5 - player.pos.x, 0.0, nc.z + 0.5 - player.pos.z)
		go_stuck += dt
		if dd.length() < 0.3 and absf(player.pos.y - nc.y) < 1.2:
			go_path.pop_front()
			go_stuck = 0.0
		elif go_stuck > 2.5 or mx != 0.0 or mz != 0.0:
			go_path = []  # blocked, or the player took the keys back
		else:
			wish = dd.normalized()
			jump = nc.y > floori(player.pos.y + 0.05) and dd.length() < 1.3
	var in_2d := not (view and view.off_cut()) and not top_view
	player.dive = player.in_water and (mz < -0.1 or player.crouching)
	Player.cut_n = view_dir if in_2d else Vector3.ZERO
	Player.cut_d = cut_goal
	var grounded := player.on_ground
	var dp0: float = player.pos.dot(view_dir)
	var vy_pre: float = player.vel.y
	var pp0 := player.pos
	player.step(dt, wish, jump, world)
	tick_grabs(dt)
	DMSfx.listener = player.pos
	if player.on_ground and not player.in_water:
		step_d += Vector2(player.pos.x - pp0.x, player.pos.z - pp0.z).length()
		if step_d > (1.1 if player.crouching else 1.7):
			step_d = 0.0
			DMSfx.play("step", null, -8.0 if player.crouching else -2.0, 0.15)
	if player.on_ground and not grounded and vy_pre < -5.0:
		DMSfx.play("step", null, 3.0, 0.2)
	if player.on_ground and not grounded and vy_pre < -8.0 and not testing:  # landing: dust burst + a short camera shake
		var below := Vector3i(floori(player.pos.x), floori(player.pos.y) - 1, floori(player.pos.z))
		var bid := world.get_v(below)
		chip_burst(below, bid if bid != World.AIR and bid != World.WATER else World.STONE, 0.45)
		shake = minf(shake + (-vy_pre - 8.0) * 0.012, 0.18)
	if is_safe_zone(player.center()):
		player.fall_safe_t = 6.0  # on quitte la salle de spawn sans se tuer : 6 s sans dégâts de chute
	_water_fx(dt)
	if in_2d:
		_depth_after(dt, dp0, mz)
	else:
		depth_goal = NAN
	if grounded and player.vel.y > Player.JUMP * 0.8:
		broadcast_action("player", player, "jump")
	if social and player.in_lava and not lava_was:
		social.world_event("danger")
	lava_was = player.in_lava
	player.aim_dx = aim_pos().x - cam.unproject_position(player.center()).x
	var sd := player.vel.dot(screen_right())  # facing = movement on SCREEN (any yaw / view)
	if absf(sd) > 0.3:
		player.facing = 1 if sd > 0 else -1
	_gear_tick(dt)
	if player.health <= 0.0:
		player.absorb = 0.0
		player.regen_t = 0.0
		player.apple_t = 0.0
		player.tag_t = 0.0
		var killer: Array = attacker_of("player", 4.0)
		if social:
			social.world_event("player_died")
			social.system_message("%s %s" % [PLAYER_NAME, ("a été tué par " + killer[0]) if not killer.is_empty() else "est mort"])
			if not killer.is_empty() and killer[0] != "zombie":
				social.say_intent(killer[0], {"intent": "killed", "target": "player"})
		for k in hits.keys():
			if hits[k].victim == "player":
				hits.erase(k)
		if DMNet.i.pvp_att.id != 0 and Time.get_ticks_msec() - int(DMNet.i.pvp_att.t) < 5000:
			DMNet.i.report_kill(int(DMNet.i.pvp_att.id))
			DMNet.i.pvp_att = {"id": 0, "t": 0}
		player.combat_t = 0.0
		player.pos = world.spawn
		player.position = player.pos
		player.reset_physics_interpolation()
		player.vel = Vector3.ZERO
		player.health = player.max_hp
		player.set_lane_axis(player.lane_axis)
		hud.toast("Vous êtes mort... retour au camp.")
	if not (view and view.off_cut()):
		_update_cut()
	_update_front_y()
	lamp.position = player.center() + Vector3(0, 0.6, 0) + right * player.facing * 0.4 - view_dir * 1.6
	if view:
		view.after_move()
	aura.position = player.center() + Vector3(0, 2.6, 0) - (Vector3.ZERO if view and view.off_cut() else view_dir * 1.4)
	_set_param("plight_pos", player.center())
	_set_param("plight_r", player.lamp_range * 1.25)

## Camera X projected on the horizontal: the screen's right (sprite facing, whatever the yaw / view).
func screen_right() -> Vector3:
	var x := cam.basis.x
	x.y = 0.0
	return x.normalized() if x.length() > 0.01 else right

## A / E (physical Q / E): the character turns 90° on himself, the view turns with him (old depth -> left/right).
## Position and layer unchanged; the shown layer is recomputed for the new axis.
const TURN_RATE := PI / 2.0  # rad/s while A / E is held
var turn_off := 0.0  # continuous extra yaw (|turn_off| <= 45° between two axis switches)

## Held A/E: smooth rotation; past 45° the cut plane flips to the other axis. Released: soft return (~0.3 s) to the nearest axis.
var joy_pitch := 0.0  # joystick tilt offset (degrees)

func turn_step(dir: float, dt: float) -> void:
	if (view and view.off_cut()) or top_view:
		turn_off = 0.0
		return
	if absf(dir) > 0.05:
		turn_by(dir * TURN_RATE * dt)

## Turns the camera around the player by `rad` (past 45 degrees the cut plane flips to the other axis).
func turn_by(rad: float) -> void:
	if (view and view.off_cut()) or top_view:
		return
	turn_off += rad
	if absf(turn_off) > PI / 4.0:
		var sg := 1 if turn_off > 0.0 else -1
		yaw_k = posmod(yaw_k + sg, 4)
		turn_off -= sg * PI / 2.0
		_apply_view()

func turn_view(d: int) -> void:
	top_view = false
	yaw_k = posmod(yaw_k + d, 4)
	_apply_view()
	hud.toast("Tourne à " + ("gauche" if d > 0 else "droite") + "  -  " + view_label().split("  ")[0])

## Depth intent (2D): returns the wish along view_dir. A short tap does nothing; a hold of depth_hold s starts
## a glide to the centre of the neighbouring layer; it chains while the key is held, stops when released.
func _depth_intent(dt: float, mz: float) -> float:
	depth_t = depth_t + dt if absf(mz) > 0.1 else 0.0
	if is_nan(depth_goal) and absf(mz) > 0.1 and depth_t >= depth_hold:
		var d: float = player.pos.dot(view_dir)
		depth_from = floorf(d) + 0.5
		depth_goal = depth_from + signf(mz)
		depth_back = false
		depth_stall = 0.0
	if is_nan(depth_goal):
		return 0.0
	return signf(depth_goal - player.pos.dot(view_dir))

func _depth_after(dt: float, d0: float, mz: float) -> void:
	if is_nan(depth_goal):
		return
	var d: float = player.pos.dot(view_dir)
	var r0 := depth_goal - d0
	var r := depth_goal - d
	if absf(r) < 0.03 or signf(r) != signf(r0):  # reached / crossed: snap on the centre
		var np: Vector3 = player.pos + view_dir * r
		if not world.box_hits(np, player.hw, player.hh):
			player.pos = np
			player.position = np
		var a := Hud._axis(view_dir)
		player.vel[a] = 0.0
		var held := absf(mz) > 0.1 and depth_t >= depth_hold and not depth_back
		depth_goal = NAN
		if held:  # still held: chain to the next layer
			depth_from = floorf(player.pos.dot(view_dir)) + 0.5
			depth_goal = depth_from + signf(mz)
			depth_stall = 0.0
		return
	depth_stall = depth_stall + dt if absf(d - d0) < 0.002 else 0.0
	if depth_stall > 0.12 and not depth_back:  # blocked: go back to the layer we left
		depth_goal = depth_from
		depth_back = true
		depth_stall = 0.0
	elif depth_stall > 0.5:
		depth_goal = NAN

## Mouse yaw target (degrees) from the mouse position relative to the player on screen.
func _yaw_target(mouse: Vector2) -> float:
	var vw := get_viewport().get_visible_rect().size.x
	var ps := cam.unproject_position(player.center())
	var m := clampf((mouse.x - ps.x) / maxf(vw * 0.5, 1.0), -1.0, 1.0)
	var k := clampf((absf(m) - 0.12) / 0.88, 0.0, 1.0)
	return signf(m) * k * YAW_MAX

## Mild bias toward the more open side (nearest wall on the other side), with 1 s hysteresis.
func _yaw_scan(dt: float) -> void:
	yaw_scan_t -= dt
	if yaw_scan_t > 0.0:
		return
	yaw_scan_t = 0.25
	var free := [0, 0]
	for si in 2:
		var dir := right * (1.0 if si == 0 else -1.0)
		for k in range(1, 7):
			var c := Vector3i((player.center() + dir * k).floor())
			if world.in_bounds(c) and World.KIND[world.get_v(c)] == World.K_CUBE:
				break
			free[si] = k
	var cand := 0.0
	if free[0] - free[1] >= 3:
		cand = YAW_BIAS
	elif free[1] - free[0] >= 3:
		cand = -YAW_BIAS
	if cand != yaw_cand:
		yaw_cand = cand
		yaw_cand_t = 0.0
	yaw_cand_t += 0.25
	if yaw_cand_t >= 1.0:
		yaw_bias = yaw_cand

func _update_yaw(dt: float, mouse: Vector2) -> void:
	var tgt := 0.0
	if yaw_on and not top_view and not (view and view.off_cut()):
		_yaw_scan(dt)
		tgt = clampf(_yaw_target(mouse) + yaw_bias * 0.6, -YAW_MAX, YAW_MAX)
	yaw_cur = lerpf(yaw_cur, tgt, 1.0 - exp(-dt * 5.0))

# ---------------------------------------------------------------- picking / mining
func raycast(o: Vector3, d: Vector3, max_steps := 500) -> Dictionary:
	var cell := Vector3i(floori(o.x), floori(o.y), floori(o.z))
	var stp := Vector3i.ZERO
	var tmax := Vector3(INF, INF, INF)
	var tdel := Vector3(INF, INF, INF)
	for i in 3:
		if absf(d[i]) > 1e-8:
			stp[i] = 1 if d[i] > 0 else -1
			var nb := float(cell[i] + (1 if d[i] > 0 else 0))
			tmax[i] = (nb - o[i]) / d[i]
			tdel[i] = absf(1.0 / d[i])
	var prev := cell
	for n in max_steps:
		if world.in_bounds(cell) and cell_visible(cell) and not (view and view.skip(cell)):
			var id := world.get_v(cell)
			if id != World.AIR and World.KIND[id] != World.K_FLUID:
				if World.KIND[id] == World.K_CUBE:  # morceau (1/8 de bloc) touché ; un bloc entamé laisse passer le rayon entre ses morceaux
					var rp := _ray_pieces(o, d, cell, world.pieces(cell))
					if rp.b >= 0:
						return {"cell": cell, "prev": prev, "piece": rp.b, "pn": rp.n, "hit": o + d * rp.t}
				else:
					return {"cell": cell, "prev": prev}
		prev = cell
		var a := 0
		if tmax.y < tmax[a]: a = 1
		if tmax.z < tmax[a]: a = 2
		cell[a] += stp[a]
		tmax[a] += tdel[a]
	return {}

## Premier morceau (2x2x2) de la cellule touché par le rayon : {b: bit, n: normale d'entrée, t: distance}, b = -1 si aucun.
func _ray_pieces(o: Vector3, d: Vector3, cell: Vector3i, mask: int) -> Dictionary:
	var best := {"b": -1, "n": Vector3i.ZERO, "t": INF}
	for b in 8:
		if (mask >> b) & 1 == 0:
			continue
		var lo := Vector3(cell) + Vector3(b & 1, (b >> 1) & 1, (b >> 2) & 1) * 0.5
		var hi := lo + Vector3(0.5, 0.5, 0.5)
		var t0 := 0.0
		var t1 := INF
		var nrm := Vector3i.ZERO
		var ok := true
		for a in 3:
			if absf(d[a]) < 1e-8:
				if o[a] < lo[a] or o[a] > hi[a]:
					ok = false
					break
				continue
			var ta := (lo[a] - o[a]) / d[a]
			var tb := (hi[a] - o[a]) / d[a]
			var na := -1 if d[a] > 0.0 else 1
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			if ta > t0:
				t0 = ta
				nrm = Vector3i.ZERO
				nrm[a] = na
			t1 = minf(t1, tb)
			if t0 > t1:
				ok = false
				break
		if ok and t0 < float(best.t):
			best = {"b": b, "n": nrm, "t": t0}
	return best

func pick_at(screen: Vector2) -> Dictionary:
	var r := view.pick(screen) if view and view.mode == ViewCtl.FPS else raycast(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
	if r.is_empty():
		return r
	if (Vector3(r.cell) + Vector3(0.5, 0.5, 0.5)).distance_to(player.center()) > player.reach:
		return {}
	# only blocks the miner can really see: clear line from his eyes to the air cell in front of the face
	var eye := player.center() + Vector3(0, 0.6, 0)
	var front := Vector3(r.prev) + Vector3(0.5, 0.5, 0.5)
	if r.has("hit") and r.pn != Vector3i.ZERO:
		front = r.hit + Vector3(r.pn) * 0.08  # le point réellement visé (le centre de la case d'air peut être dans une bosse)
	if Vector3i(eye.floor()) != r.prev and not los(eye, front):
		return {}
	return r

# ---- minage progressif : le bloc s'effrite par étapes (morceaux qui sautent côté joueur, ramassés aussitôt), puis casse
const MINE_SLOW := 0.42  # vitesse de minage globale (x0,42 : ~1,7 s une roche pour un humain)
var dmg_on := false
var dmg_cell := Vector3i.ZERO
var dmg_stage := 0

static func _bits(m: int) -> int:
	return (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1) + ((m >> 3) & 1) + ((m >> 4) & 1) + ((m >> 5) & 1) + ((m >> 6) & 1) + ((m >> 7) & 1)

func _chip_tick(_dt: float) -> void:
	pass

## Effritement : à 1/3 et 2/3 de la progression, deux morceaux (côté joueur) sautent pour de bon et sont ramassés
## tout de suite ; le bloc ne se reforme jamais. La casse finale ne donne que ce qui reste (le total fait 1 bloc).
func _chip_cell(c: Vector3i, prog: float) -> void:
	if DMNet.i.is_client() or World.KIND[world.get_v(c)] != World.K_CUBE:
		return  # (client : l'hôte seul modifie le monde)
	if dmg_on and dmg_cell != c:
		dmg_on = false
	if not dmg_on:
		dmg_on = true
		dmg_cell = c
		dmg_stage = 0
	if prog < 0.05:
		dmg_stage = 0  # nouvelle reprise sur ce bloc déjà entamé
	var stage := mini(int(prog * 3.0), 2)
	if stage <= dmg_stage:
		return
	dmg_stage = stage
	var id := world.get_v(c)
	var mask := world.pieces(c)
	var eye := player.center()
	var bits: Array = []
	for b in 8:
		if (mask >> b) & 1 == 1:
			bits.append(b)
	var n := mini(2, bits.size() - 2)  # il reste toujours au moins 2 morceaux : la casse finale est un vrai coup
	if n <= 0:
		return
	bits.sort_custom(func(a: int, b: int) -> bool:
		var pa := Vector3(c) + (Vector3(a & 1, (a >> 1) & 1, (a >> 2) & 1) + Vector3(0.5, 0.5, 0.5)) * 0.5
		var pb2 := Vector3(c) + (Vector3(b & 1, (b >> 1) & 1, (b >> 2) & 1) + Vector3(0.5, 0.5, 0.5)) * 0.5
		return pa.distance_to(eye) < pb2.distance_to(eye))
	for k in n:
		mask &= ~(1 << int(bits[k]))
	world.set_pieces(c, id, mask)
	_remesh(c)
	if DMNet.i.is_host():
		DMNet.i.broadcast_pieces(c)
	chip_burst(c, id, 0.9)
	DMSfx.play("break", Vector3(c) + Vector3(0.5, 0.5, 0.5), -3.0)
	shake = minf(shake + 0.02, 0.18)
	give_pieces(id, n)

func _chip_restore() -> void:
	dmg_on = false

func _mining(dt: float, held: bool) -> void:
	var mp := aim_pos()
	if shot_path != "":  # capture: aim at the floor just ahead of the player
		mp = cam.unproject_position(player.center() + right * 1.5 + Vector3(0, -1.3, 0))
	highlight.visible = false
	highlight.material_override = hl_mat
	preview.visible = false
	_chip_tick(dt)
	hit_sticky_t -= dt
	var pm := pick_miner(mp)  # a miner under the cursor takes priority over the blocks
	if pm:
		target = {}
		player.mining = false
		mine_prog = 0.0
		if held and try_hit("player", player, pm.mname, pm):
			chip_burst(Vector3i(pm.center()), World.DIRT, 0.4)
		return
	var rid := pick_remote(mp, held) if DMNet.i.mode != "solo" else 0
	if rid != 0:  # un joueur distant sous le curseur : coup PvP (l'hôte valide)
		target = {}
		player.mining = false
		mine_prog = 0.0
		if held and player.atk_cd <= 0.0 and player.health > 0.0 and _pvp_in_reach((DMNet.i.remotes[rid].node as Node3D).position) and DMNet.i.attack(rid):
			player.atk_cd = Player.HIT_CD * (Gear.SWORD_CD if player.sword > 0 else 1.0)
			player.swing_t = 0.25
			player.combat_t = 6.0
			player.tag_t = Gear.TAG_TIME
		return
	target = pick_at(mp)
	player.has_aim = not target.is_empty()
	if player.has_aim:
		player.aim_vec = Vector3(target.cell) + Vector3(0.5, 0.5, 0.5) - player.center()
	if target.is_empty():
		player.mining = false
		mine_prog = 0.0
		return
	var c: Vector3i = target.cell
	var n := target_face(target)
	var hard: bool = World.HARD[world.get_v(c)] < 0.0
	if hub_n and (hub_n.guard(c) if held else hub_n.is_protected(c)):  # --- SPAWN HUB ---
		hard = true
	if fine_mode and target.has("piece") and World.KIND[world.get_v(c)] == World.K_CUBE:  # mode fin : on creuse là où l'on vise
		var pb: int = target.piece
		var pn: Vector3 = Vector3(target.pn) if target.pn != Vector3i.ZERO else -view_dir
		highlight.material_override = hl_mat_fine
		_put_reticle(highlight, target.hit, pn)  # le repère suit le point visé (pas la grille)
		hl_mat_fine.set_shader_parameter("frame_col", Color(0.55, 0.55, 0.6) if hard else Color(1, 0.9, 0.4))
		_show_place_ghost()
		if not held or hard:
			player.mining = held
			mine_prog = 0.0
			hl_mat_fine.set_shader_parameter("crack", 0)
			return
		player.mining = true
		var pk := Vector3i(c.x * 2 + (pb & 1), c.y * 2 + ((pb >> 1) & 1), c.z * 2 + ((pb >> 2) & 1))
		if pk != mine_cell:
			mine_cell = pk
			mine_prog = 0.0
		mine_prog += dt * player.mine_mult * player.mine_boost * tool_mine * MINE_SLOW * 3.0 / maxf(World.HARD[world.get_v(c)], 0.05)
		chip_t -= dt
		if chip_t <= 0.0:
			chip_t = 0.14
			chip_burst(c, world.get_v(c), 0.15)
			_pick_sound(c)
		hl_mat_fine.set_shader_parameter("crack", clampi(int(mine_prog * 4.0) + 1, 1, 4))
		if mine_prog >= 1.0:
			break_brush(c, pb, target.hit, target.pn)
			_giant_sweep(c, Vector3i(target.pn) if target.pn != Vector3i.ZERO else n)
			mine_prog = 0.0
			hl_mat_fine.set_shader_parameter("crack", 0)
		return
	_put_on_face(highlight, c, Vector3(n) if n != Vector3i.ZERO else -view_dir)
	hl_mat.set_shader_parameter("frame_col", Color(0.55, 0.55, 0.6) if hard else Color(1, 1, 1))
	var item: int = hotbar[sel]
	if item >= 0 and (item == World.TORCH or item == World.SIGN or World.KIND[item] == World.K_CUBE) and inv.get(item, 0) > 0 and can_place(target.prev, item):  # --- SPAWN HUB --- SIGN
		_put_on_face(preview, target.prev, -view_dir)
	if not held or hard:
		player.mining = held
		mine_prog = 0.0
		hl_mat.set_shader_parameter("crack", 0)
		return
	player.mining = true
	if c != mine_cell:
		mine_cell = c
		mine_prog = 0.0
	mine_prog += dt * player.mine_mult * player.mine_boost * tool_mine * MINE_SLOW / (maxf(World.HARD[world.get_v(c)], 0.05) * maxf(float(_bits(world.pieces(c))) / 8.0, 0.3))
	_chip_cell(c, mine_prog)
	chip_t -= dt
	if chip_t <= 0.0:
		chip_t = 0.14
		chip_burst(c, world.get_v(c), 0.25)
		_pick_sound(c)
	hl_mat.set_shader_parameter("crack", clampi(int(mine_prog * 4.0) + 1, 1, 4))
	if mine_prog >= 1.0:
		break_block(c)
		_giant_sweep(c, n)
		mine_prog = 0.0
		hl_mat.set_shader_parameter("crack", 0)

## Pelle de géant : un coup de pioche brise aussi les blocs voisins (2 de large x 3 de haut sur une paroi, 2x2 en creusant vers le haut/bas),
## pour percer une cabane à sa taille sans se battre bloc par bloc.
func _giant_sweep(c: Vector3i, n: Vector3i) -> void:
	if int(DMSettings.look.get("body", 0)) != 2:
		return
	var cells: Array = []
	if n.y != 0:
		cells = [c + Vector3i(1, 0, 0), c + Vector3i(0, 0, 1), c + Vector3i(1, 0, 1)]
	else:
		var a := Vector3i(absi(n.z), 0, absi(n.x))  # axe horizontal perpendiculaire à la paroi
		if a == Vector3i.ZERO:
			return
		for dy in [-1, 0, 1]:
			for k in [0, 1]:
				if dy != 0 or k != 0:
					cells.append(c + a * k + Vector3i(0, dy, 0))
	var n_broken := 0
	for cc in cells:
		var id := world.get_v(cc)
		if World.KIND[id] != World.K_CUBE or World.HARD[id] < 0.0 or id == World.CHEST:
			continue
		if hub_n and hub_n.guard(cc):
			continue
		if break_block(cc):
			n_broken += 1
	if n_broken > 0:
		_pick_sound(c)

## Small pixel shadow on the real ground below the player.
func _update_shadow() -> void:
	var c := Vector3i(floori(player.pos.x), floori(player.pos.y + 0.01), floori(player.pos.z))
	shadow.visible = false
	for i in 6:
		var g := c - Vector3i(0, i, 0)
		if not world.in_bounds(g):
			return
		if world.is_solid(world.get_v(g)):
			if i == 0:
				return
			var h := player.pos.y - float(g.y + 1)
			shadow.position = Vector3(snappedf(player.pos.x, 1.0 / 16.0), g.y + 1.004, snappedf(player.pos.z, 1.0 / 16.0)) + cam.basis.z * 0.03
			shadow.material_override.set_shader_parameter("shadow_r", clampf(5.0 - h * 0.9, 2.5, 5.0))
			shadow.visible = true
			return

## Mode fin (F4 ou /fin on|off) : indicateur « MODE FIN » à l'écran tant qu'il est actif.
func set_fine(on: bool) -> void:
	fine_mode = on
	_fine_label()
	hud.toast(("Creusage libre : le coup de pioche creuse là où tu vises, clic droit = poser par morceaux (F5 : taille)" if on else "Mode bloc : on casse / pose des blocs entiers") + "  (F4)")

func _fine_label() -> void:
	hud.fine_lbl.visible = (not fine_mode) or place_size != 1
	hud.fine_lbl.text = ("MODE BLOC : blocs entiers  (F4 : creusage libre)" if not fine_mode else "Pose : %s  (F5 taille, F4 mode bloc)" % {1: "1 morceau", 4: "une plaque de 4", 8: "un bloc de 8"}[place_size])

## Morceaux (1/8) ramassés : 8 morceaux refont un bloc entier.
func give_pieces(id: int, n: int) -> void:
	frac[id] = int(frac.get(id, 0)) + n
	var got := 0
	while int(frac[id]) >= 8:
		frac[id] = int(frac[id]) - 8
		inv[id] = inv.get(id, 0) + 1
		got += 1
	hud.toast(("+%d %s" % [got, World.NAMES[id]]) if got > 0 else ("%d/8 %s" % [int(frac[id]), World.NAMES[id].to_lower()]))

## Mode fin : casse un morceau (bit b) du bloc c sans rien ramasser ; retourne la matière ou -1.
func _break_piece_raw(c: Vector3i, b: int) -> int:
	var id := world.get_v(c)
	if id == World.AIR or World.HARD[id] < 0.0 or World.KIND[id] != World.K_CUBE or (hub_n and hub_n.guard(c)):
		return -1
	if DMNet.i.is_client():
		if (world.pieces(c) >> b) & 1 == 1:
			DMNet.i.send_pbreak(c, b)
			return id
		return -1
	return edit_piece_break(c, b, true)

func break_piece(c: Vector3i, b: int) -> void:
	var id := _break_piece_raw(c, b)
	if id >= 0:
		give_pieces(id, 1)

const BRUSH_R := 0.55  # rayon (blocs) autour du point visé : le morceau visé + ceux qui sont tout proches

## Un coup de pioche en mode fin : le morceau visé et ses voisins proches du point visé (creusage moins « cube »).
func break_brush(c0: Vector3i, b0: int, hit: Vector3, nrm: Vector3i) -> void:
	var got := {}
	var id0 := _break_piece_raw(c0, b0)
	if id0 >= 0:
		got[id0] = 1
	var p := hit - Vector3(nrm) * 0.06
	var base := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				var c := base + Vector3i(dx, dy, dz)
				var mask := world.pieces(c)
				if mask == 0:
					continue
				for b in 8:
					if (mask >> b) & 1 == 0 or (c == c0 and b == b0):
						continue
					var ctr := Vector3(c) + (Vector3(b & 1, (b >> 1) & 1, (b >> 2) & 1) + Vector3(0.5, 0.5, 0.5)) * 0.5
					if ctr.distance_to(p) <= BRUSH_R and Vector3(c0).distance_to(Vector3(c)) < 2.5:
						var id := _break_piece_raw(c, b)
						if id >= 0:
							got[id] = int(got.get(id, 0)) + 1
	for id in got:
		give_pieces(id, int(got[id]))

func edit_piece_break(c: Vector3i, b: int, by_player := false) -> int:
	var id := world.get_v(c)
	if id == World.AIR or World.HARD[id] < 0.0 or World.KIND[id] != World.K_CUBE:
		return -1
	if hub_n and (hub_n.guard(c) if by_player else hub_n.is_protected(c)):
		return -1
	var mask := world.pieces(c)
	if b < 0 or b > 7 or (mask >> b) & 1 == 0:
		return -1
	if chip_pool.size() > 0:
		chip_burst(c, id, 0.5)
	DMSfx.play("break", Vector3(c) + Vector3(0.5, 0.5, 0.5), -6.0)
	world.set_pieces(c, id, mask & ~(1 << b))
	if mask & ~(1 << b) == 0 and hub_n:
		hub_n.on_broken(c, id)
	_remesh(c)
	if DMNet.i.is_host():
		DMNet.i.broadcast_pieces(c)
	return id

## Place un morceau (bit b) dans la cellule c : cellule vide ou bloc entamé de la même matière.
func edit_piece_place(c: Vector3i, b: int, item: int) -> bool:
	if b < 0 or b > 7 or not world.in_bounds(c) or World.KIND[item] != World.K_CUBE or World.HARD[item] < 0.0:
		return false
	if hub_n and hub_n.is_protected(c):
		return false
	var cur := world.get_v(c)
	var mask := 0
	if cur == World.AIR or World.KIND[cur] == World.K_FLUID:
		mask = 0
	elif cur == item:
		mask = world.pieces(c)
		if (mask >> b) & 1 == 1:
			return false
	else:
		return false
	if not _piece_free_of_bodies(c, b):
		return false
	world.set_pieces(c, item, mask | (1 << b))
	_remesh(c)
	if DMNet.i.is_host():
		DMNet.i.broadcast_pieces(c)
	return true

func _piece_free_of_bodies(c: Vector3i, b: int) -> bool:
	var bodies: Array = [player]
	for m in miners:
		if (m as Miner).active:
			bodies.append(m)
	for bd in bodies:
		var pl := bd as Player
		if world._pieces_hit(1 << b, c.x, c.y, c.z, pl.pos, pl.hw, pl.hh):
			return false
	return true

## Mode fin, clic droit : pose les morceaux du fantôme (1, plaque de 4 ou bloc de 8) contre la face visée.
func place_piece_at_target(item: int) -> void:
	var placed := 0
	for sp in place_spots():
		var c: Vector3i = sp[0]
		var b: int = sp[1]
		if hub_n and hub_n.guard(c):
			continue
		if int(frac.get(item, 0)) <= 0 and inv.get(item, 0) <= 0:
			hud.toast("Plus de " + World.NAMES[item])
			break
		if DMNet.i.is_client():
			var cur := world.get_v(c)
			if not (cur == World.AIR or cur == item) or (world.pieces(c) >> b) & 1 == 1 or not _piece_free_of_bodies(c, b):
				continue
			DMNet.i.send_pplace(c, b, item)
			world.set_pieces(c, item, world.pieces(c) | (1 << b))  # affichage immédiat ; l'hôte confirme ou corrige
			_remesh(c)
		elif not edit_piece_place(c, b, item):
			continue
		if int(frac.get(item, 0)) <= 0:
			inv[item] -= 1
			frac[item] = 8
		frac[item] = int(frac[item]) - 1
		placed += 1

func break_block(c: Vector3i) -> bool:
	if DMNet.i.is_client():  # l'hôte valide et diffuse ; on ne modifie rien localement
		return _net_break(c)
	var mask0 := world.pieces(c)
	var drop := edit_break(c, true)
	if drop < 0:
		return false
	if mask0 > 0 and mask0 < 255:  # bloc entamé : on ne récupère que les morceaux restants
		give_pieces(drop, (mask0 & 1) + ((mask0 >> 1) & 1) + ((mask0 >> 2) & 1) + ((mask0 >> 3) & 1) + ((mask0 >> 4) & 1) + ((mask0 >> 5) & 1) + ((mask0 >> 6) & 1) + ((mask0 >> 7) & 1))
		return true
	inv[drop] = inv.get(drop, 0) + 1
	hud.toast("+1 " + World.NAMES[drop])
	if social and drop in [World.IRON, World.CRYSTAL, World.COPPER]:
		social.world_event("player_found", {"item": drop})
	for m in miners:
		var mm: Miner = m
		if mm.active and mm.home_dist(Vector3(c)) < 6.0 and game_t - float(base_warn.get(mm.mname, -99.0)) > 15.0:
			base_warn[mm.mname] = game_t
			mm.brain.on_event("broke_near_base", "player", {}, game_t)
			sync_to_agent(mm)
			if social:
				social.notify_event(mm.mname, "block_broken", {"from": "player"})
	return true

# ---------------------------------------------------------------- shared world-edit API (player + AI miners)
## Breaks a block: particles, torch light removal, remesh. Returns the dropped item or -1. No toast.
func edit_break(c: Vector3i, by_player := false) -> int:
	var id := world.get_v(c)
	if id == World.AIR or World.HARD[id] < 0.0 or World.KIND[id] == World.K_FLUID:
		return -1
	if hub_n and (hub_n.guard(c) if by_player else hub_n.is_protected(c)):  # --- SPAWN HUB --- (silent for the AI)
		return -1
	var drop := id
	if id == World.MOSS or id == World.STALAG or id == World.STALACT or id == World.WARMROCK:
		drop = World.STONE
	elif id == World.GLOWPLANT:
		drop = World.MUSHROOM
	if chip_pool.size() > 0 and (by_player or (cut_layer != -999 and cell_visible(c))):
		chip_burst(c, id, 1.0 if by_player else 0.6)
		DMSfx.play("break", Vector3(c) + Vector3(0.5, 0.5, 0.5), 0.0 if by_player else -6.0)
	world.set_v(c, World.AIR)
	if hub_n: hub_n.on_broken(c, id)  # --- SPAWN HUB ---
	_remove_torch_light(c)
	_remesh(c)
	if DMNet.i.is_host():
		DMNet.i.broadcast_edit(c, World.AIR)
	return drop

# ---------------------------------------------------------------- réseau LAN (scripts/net/dm_net.gd)
func _net_host(port: int) -> void:
	if DMNet.i.host(port) == OK:
		_start_play(true)
		hud.toast("Hôte : %s:%d" % [DMNet.local_ip(), port])

func _net_join(ip: String, port: int) -> void:
	DMNet.i.join(ip, port)

func _net_joined() -> void:
	_start_play(true)
	apply_gear()  # envoie l'équipement à l'hôte
	hud.toast("Connecté à la partie de l'hôte")

## Client : casser = requête à l'hôte (rien n'est modifié ici avant sa diffusion).
func _net_break(c: Vector3i) -> bool:
	var id := world.get_v(c)
	if id == World.AIR or World.HARD[id] < 0.0 or World.KIND[id] == World.K_FLUID or (hub_n and hub_n.guard(c)):
		return false
	DMNet.i.send_break(c)
	var drop := World.STONE if id in [World.MOSS, World.STALAG, World.STALACT, World.WARMROCK] else (World.MUSHROOM if id == World.GLOWPLANT else id)
	inv[drop] = inv.get(drop, 0) + 1
	hud.toast("+1 " + World.NAMES[drop])
	return true

func net_item_ok(item: int) -> bool:
	return item > 0 and item < World.NAMES.size() and World.HARD[item] >= 0.0 \
			and (item == World.TORCH or item == World.SIGN or World.KIND[item] == World.K_CUBE)

func net_diggable(id: int) -> bool:
	return id != World.AIR and World.HARD[id] > 0.0 and World.KIND[id] == World.K_CUBE

func net_make_body(look: Dictionary) -> Node3D:
	var b := VoxelBody.new()
	add_child(b)  # (reparenté par l'appelant)
	b.build(look, int(look.get("body", 0)))
	b.fit(Player.HH)
	remove_child(b)
	return b

## Client : le monde de l'hôte remplace le monde local (blocs + eau), puis lumières et maillage.
func net_apply_world(blocks: PackedByteArray, fluid: PackedByteArray, spawn: Vector3, seed_n: int) -> void:
	_stream_stop()  # le maillage de fond lit l'ancien monde : on l'arrête avant de le remplacer
	world.blocks = blocks
	world.partial = DMNet.i.pending_partial.duplicate()
	world.compute_styles(seed_n)
	world.fluid_lvl = fluid
	world._fw.clear()
	world.spawn = spawn
	seed_v = seed_n
	world.signs.clear()
	world._collect_lights()
	for e in lights:
		(e[0] as Node).queue_free()
	lights.clear()
	torch_lights.clear()
	for s in world.light_spots:
		_add_light(s[0], s[1], s[2], 1.3)
	var i := blocks.find(World.TORCH)
	while i >= 0:
		_add_torch_light(Vector3i(i % World.SX, (i / World.SX) % World.SY, i / (World.SX * World.SY)))
		i = blocks.find(World.TORCH, i + 1)
	_update_lights()
	for k in chunks:
		dirty[k] = true
	world.edits += 1
	player.pos = spawn
	player.position = spawn
	player.reset_physics_interpolation()
	_flush_remesh(true)  # joined world: whole map at once

## Client : un bloc a changé chez l'hôte.
func net_apply_pieces(c: Vector3i, id: int, mask: int) -> void:
	if world.in_bounds(c):
		world.set_pieces(c, id, mask)
		_remesh(c)

func net_apply_edit(c: Vector3i, id: int) -> void:
	if not world.in_bounds(c):
		return
	if world.get_v(c) == World.TORCH:
		_remove_torch_light(c)
	world.set_v(c, id)
	if id == World.TORCH:
		_add_torch_light(c)
		_update_lights()
	_remesh(c)

## Client : cellules d'eau changées chez l'hôte.
func net_apply_cells(ii: PackedInt32Array, bb: PackedByteArray, ll: PackedByteArray) -> void:
	for n in ii.size():
		var i := ii[n]
		if i < 0 or i >= world.blocks.size():
			continue
		world.blocks[i] = bb[n]
		world.fluid_lvl[i] = ll[n]
		_remesh(Vector3i(i % World.SX, (i / World.SX) % World.SY, i / (World.SX * World.SY)))
	world.edits += 1

## Places a block (no inventory involved): torch light, remesh. Returns false if the cell is taken.
func edit_place(c: Vector3i, id: int) -> bool:
	if hub_n and hub_n.is_protected(c):
		return false
	if not world.in_bounds(c) or not cell_free_of_bodies(c, id):
		return false
	var cur := world.get_v(c)
	if cur != World.AIR and not (World.KIND[cur] == World.K_FLUID and id != World.TORCH):
		return false
	world.set_v(c, id)
	if id == World.TORCH:
		_add_torch_light(c)
		_update_lights()
	_remesh(c)
	if DMNet.i.is_host():
		DMNet.i.broadcast_edit(c, id)
	return true

## No player / miner body inside cell c (only solid blocks matter).
func cell_free_of_bodies(c: Vector3i, id: int) -> bool:
	if World.KIND[id] != World.K_CUBE:
		return true
	var bodies: Array = [player]
	for m in miners:
		if (m as Miner).active:
			bodies.append(m)
	for b in bodies:
		var p: Vector3 = (b as Player).pos
		var hw: float = (b as Player).hw
		if c.x < p.x + hw and c.x + 1 > p.x - hw and c.y < p.y + (b as Player).hh and c.y + 1 > p.y and c.z < p.z + hw and c.z + 1 > p.z - hw:
			return false
	return true

func _add_torch_light(c: Vector3i) -> void:
	torch_lights[c] = _add_light(Vector3(c) + Vector3(0.5, 0.7, 0.5), TORCH_COL, 9.0, 1.7)

func _remove_torch_light(c: Vector3i) -> void:
	if torch_lights.has(c):
		var e: Array = torch_lights[c]
		(e[0] as Node).queue_free()
		lights.erase(e)
		torch_lights.erase(c)

func use_item() -> void:
	var item: int = hotbar[sel]
	if item < 0:
		return
	if item == World.MUSHROOM:
		if inv.get(item, 0) > 0 and player.health < player.max_hp:
			inv[item] -= 1
			player.health = minf(player.max_hp, player.health + 25.0)
			hud.toast("Miam ! +25 PV")
		return
	if target.is_empty():
		return
	if fine_mode and World.KIND[item] == World.K_CUBE:
		place_piece_at_target(item)
		return
	place_block(target.prev, item)

func place_block(c: Vector3i, item: int) -> bool:
	if inv.get(item, 0) <= 0:
		hud.toast("Plus de " + World.NAMES[item])
		return false
	if hub_n and hub_n.guard(c):  # --- SPAWN HUB ---
		return false
	if not can_place(c, item):
		return false
	if DMNet.i.is_client():
		DMNet.i.send_place(c, item)
		inv[item] -= 1
		return true
	if not edit_place(c, item):
		return false
	inv[item] -= 1
	if hub_n: hub_n.on_placed(c, item)  # --- SPAWN HUB ---
	return true

func can_place(c: Vector3i, item: int) -> bool:
	if not world.in_bounds(c) or not cell_visible(c):
		return false
	if hub_n and hub_n.is_protected(c):  # --- SPAWN HUB ---
		return false
	var cur := world.get_v(c)
	if cur != World.AIR and not (World.KIND[cur] == World.K_FLUID and item != World.TORCH):
		return false
	return cell_free_of_bodies(c, item)

func _remesh(c: Vector3i) -> void:
	if fog:
		fog.notify_edit(c)
	for d in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var n: Vector3i = c + d
		var k := Vector3i(floori(n.x / float(World.CS)), floori(n.y / float(World.CS)), floori(n.z / float(World.CS)))
		if chunks.has(k):
			dirty[k] = true

const FLUID_HZ := 8.0
const FLUID_BUDGET_US := 1800
var fluid_t := 0.0
var fluid_max_us := 0

## Eau à niveaux : ~8 Hz, budget en µs, seules les cellules actives ; remesh des chunks touchés.
func _fluid_step(dt: float) -> void:
	fluid_t += dt
	if fluid_t < 1.0 / FLUID_HZ:
		return
	fluid_t = 0.0
	if DMNet.i.is_client():
		return  # l'eau est simulée chez l'hôte (cellules reçues via net_apply_cells)
	var t0 := Time.get_ticks_usec()
	var ch := world.fluid_tick(FLUID_BUDGET_US)
	if DMNet.i.is_host():
		DMNet.i.send_fluid(ch)
	fluid_max_us = maxi(fluid_max_us, Time.get_ticks_usec() - t0)
	var seen := {}
	for i in ch:
		var c := Vector3i(i % World.SX, (i / World.SX) % World.SY, i / (World.SX * World.SY))
		var k0 := Vector3i(c.x / World.CS, c.y / World.CS, c.z / World.CS)
		for d in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var n: Vector3i = c + d
			var k := Vector3i(floori(n.x / float(World.CS)), floori(n.y / float(World.CS)), floori(n.z / float(World.CS)))
			if not seen.has(k) and chunks.has(k):
				seen[k] = true
				dirty[k] = true
		if fog:
			fog.notify_edit(c)

## --- PERF --- maillage de fond (voir _ready) : calcul des tampons sur les cœurs, création des maillages au fil des images.
const NEAR_CHUNKS := 96
const STREAM_US := 3000
var bg_keys: Array = []
var bg_bufs: Array = []
var bg_ok := PackedByteArray()
var bg_pos := 0
var bg_gid := -1
var bg_cancel := false
var bg_pending := {}
var booting := true   # _ready pas fini (génération asynchrone)

func _stream_start(keys: Array) -> void:
	bg_keys = keys; bg_bufs = []; bg_bufs.resize(keys.size()); bg_ok = PackedByteArray(); bg_ok.resize(keys.size()); bg_pos = 0
	bg_pending = {}
	for k in keys: bg_pending[k] = true
	if keys.is_empty(): return
	var task := func(i: int) -> void:
		if bg_cancel: return
		bg_bufs[i] = world.chunk_bufs(bg_keys[i].x, bg_keys[i].y, bg_keys[i].z)
		bg_ok[i] = 1
	bg_gid = WorkerThreadPool.add_group_task(task, keys.size(), -1, false, "maillage de fond")

func _stream_stop() -> void:
	bg_cancel = true
	if bg_gid >= 0:
		WorkerThreadPool.wait_for_group_task_completion(bg_gid)
		bg_gid = -1
	bg_pending.clear(); bg_keys = []; bg_bufs = []; bg_ok = PackedByteArray(); bg_pos = 0
	bg_cancel = false

func stream_progress() -> float:
	return 1.0 if bg_keys.is_empty() else float(bg_pos) / float(bg_keys.size())

func _stream_tick() -> void:
	if bg_pos >= bg_keys.size(): return
	var t0 := Time.get_ticks_usec()
	while bg_pos < bg_keys.size() and bg_ok[bg_pos] == 1 and Time.get_ticks_usec() - t0 < STREAM_US:
		var k: Vector3i = bg_keys[bg_pos]
		if bg_pending.has(k) and not dirty.has(k):   # déjà remaillé / modifié entre-temps : on garde la version récente
			(chunks[k] as MeshInstance3D).mesh = world.chunk_mesh(bg_bufs[bg_pos], mat_s, mat_f)
		bg_pending.erase(k)
		bg_bufs[bg_pos] = null
		bg_pos += 1
	if bg_pos >= bg_keys.size():
		bg_gid = -1

func _exit_tree() -> void:
	_stream_stop()

## Rebuilds the chunks touched this frame (player + miners), then the cut cap once.
## Maille des morceaux : le calcul (le plus long) est réparti sur les cœurs, la création des maillages reste sur le fil principal.
## Ne s'utilise que quand rien ne modifie les blocs (chargement) ; pour quelques morceaux, un seul fil suffit.
func _mesh_chunks(keys: Array, min_par := 24) -> Array:
	var bufs: Array = []
	bufs.resize(keys.size())
	if keys.size() < min_par or OS.get_processor_count() < 2:
		for i in keys.size():
			bufs[i] = world.chunk_bufs(keys[i].x, keys[i].y, keys[i].z)
	else:
		var task := func(i: int) -> void: bufs[i] = world.chunk_bufs(keys[i].x, keys[i].y, keys[i].z)
		var gid := WorkerThreadPool.add_group_task(task, keys.size(), -1, true, "maillage")
		WorkerThreadPool.wait_for_group_task_completion(gid)
	var out: Array = []
	for b in bufs:
		out.append(world.chunk_mesh(b, mat_s, mat_f))
	return out

func _flush_remesh(all := false) -> void:  # all: no time budget (loading: the whole map at once)
	if dirty.is_empty():
		return
	# --- PERF --- nearest chunks first, ~4 ms per frame (at least one); the rest waits for the next frames
	var keys: Array = dirty.keys()
	var pk := Vector3(player.pos / float(World.CS))
	keys.sort_custom(func(a, b): return Vector3(a).distance_squared_to(pk) < Vector3(b).distance_squared_to(pk))
	var t0 := Time.get_ticks_usec()
	var done: Array = []
	if all and keys.size() >= 24:  # chargement : tout d'un coup, en parallèle
		var meshes := _mesh_chunks(keys)
		for i in keys.size():
			(chunks[keys[i]] as MeshInstance3D).mesh = meshes[i]
			dirty.erase(keys[i])
			done.append(keys[i])
	else:
		# --- PERF --- les morceaux trop loin pour être dessinés attendent (ils sont remaillés quand on s'en approche)
		var near_keys: Array = keys
		if not all and view and view.mode == ViewCtl.FPS and not testing:
			var lim := PERSP_CULL + 16.0
			near_keys = keys.filter(func(k): return (Vector3(k) * float(World.CS) + Vector3.ONE * 4.0).distance_to(player.pos) <= lim)
		for k in near_keys:  # un morceau au moins par image, puis dans la limite du temps alloué (REMESH_US)
			if not all and not done.is_empty() and Time.get_ticks_usec() - t0 > REMESH_US and not testing:
				break
			(chunks[k] as MeshInstance3D).mesh = world.build_chunk(k.x, k.y, k.z, mat_s, mat_f)
			dirty.erase(k)
			done.append(k)
	for k in done: bg_pending.erase(k)
	var pt := _pf("rm_chunks", t0)
	if view:  # --- VIEW --- block-id texture + caps of the 3/4 view
		view.iso.on_remesh(done)
	pt = _pf("rm_vox", pt)
	var near_cut := false  # --- PERF --- the 2D cap (a whole plane, ~12 ms) only when an edit touches its layers
	for k in done:
		var lo: int = (k as Vector3i)[cut_axis] * World.CS
		near_cut = near_cut or (cut_layer >= lo - 1 and cut_layer <= lo + World.CS)
	if cut_layer != -999 and near_cut:
		_build_cap2d()
	_pf("rm_cap2d", pt)

# ---------------------------------------------------------------- AI miners
## Zombies : apparition dans l'ombre, loin du joueur et hors de sa vue ; simulés seulement à moins de 50 blocs.
func _make_zombie(at: Vector3) -> Zombie:
	var z := Zombie.new()
	z.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	z.setup(at)
	zid_n += 1
	z.zid = zid_n
	add_child(z)
	_fit_body(z)
	zombies.append(z)
	return z

func _spawn_zombie() -> void:
	for k in 40:
		var c := Vector3i(randi_range(6, World.SX - 7), randi_range(10, 52), randi_range(5, World.SZ - 6))
		if not Pathfinder.standable(world, c, 2) or world.get_v(c + Vector3i(0, 2, 0)) != World.AIR or not _spot_dry(c) or _near_spawn_room(c):
			continue
		var at := Vector3(c.x + 0.5, c.y, c.z + 0.5)
		var d := at.distance_to(player.pos)
		if d < 26.0 or d > 70.0 or is_safe_zone(at):
			continue
		var tmp := _make_zombie(at)
		if sees(player, tmp):  # jamais sous les yeux du joueur
			zombies.erase(tmp)
			tmp.queue_free()
			continue
		return

## À zéro PV le zombie ne meurt pas sur place : il s'enfonce vite dans le sol (Zombie.tick) puis disparaît.
func zombie_died(z: Zombie) -> void:
	if z.burrowing:
		return
	DMSfx.play("giant", z.pos, -2.0, 0.15)
	if randf() < 0.5:
		drop_item(World.MUSHROOM, 1, z.pos + Vector3(0, 0.4, 0))
	chip_burst(Vector3i(z.center()), World.MOSS, 1.0)
	z.start_burrow()

## Zombie actif le plus proche (à moins de r blocs), ou null.
func nearest_zombie(p: Vector3, r: float) -> Zombie:
	var best: Zombie = null
	var bd := r
	for z in zombies:
		var zz: Zombie = z
		if zz.burrowing:
			continue
		var d := zz.center().distance_to(p)
		if d < bd:
			bd = d
			best = zz
	return best

func zombie_gone(z: Zombie) -> void:
	zombies.erase(z)
	z.queue_free()

## Client : les zombies suivent ce que l'hôte diffuse.
func _client_zombies(dt: float) -> void:
	var seen_ids := {}
	for zid in DMNet.i.zpup:
		var a: Array = DMNet.i.zpup[zid]
		seen_ids[zid] = true
		var z: Zombie = zpuppets.get(zid)
		if z == null:
			z = _make_zombie(a[0])
			z.zid = int(zid)
			zpuppets[zid] = z
		var tgt: Vector3 = a[0]
		var d: Vector3 = tgt - z.pos
		z.pos = tgt if d.length() > 6.0 else z.pos.lerp(tgt, 1.0 - exp(-dt * 10.0))
		z.position = z.pos
		z.vel = Vector3(d.x, 0.0, d.z) * 6.0
		z.health = float(a[1]) * z.max_hp
		z._bite_t = 0.5 if a[2] else 0.0
		if a[3] and not z.burrowing:
			z.start_burrow()
		if not z.burrowing:
			z._update_model(dt, player, bool(a[2]), 1.0 if a[2] else 6.0)
		z.visible = z.center().distance_to(player.center()) < 40.0 and (view and view.off_cut() or sees(player, z))
	for zid in zpuppets.keys():
		if not seen_ids.has(zid):
			var z: Zombie = zpuppets[zid]
			zpuppets.erase(zid)
			zombies.erase(z)
			z.queue_free()

func tick_zombies(dt: float) -> void:
	if DMNet.i.is_client() and state == "play" and not testing and not nettest:
		_client_zombies(dt)
		return
	if testing or nettest or DMNet.i.is_client() or state != "play" or zombies_off:
		return
	zombie_t -= dt
	if zombie_t <= 0.0:
		zombie_t = 6.0
		if zombies.size() < ZOMBIE_MAX:
			_spawn_zombie()
	for zz in zombies.duplicate():
		var z: Zombie = zz
		var d := z.center().distance_to(player.center())
		var dn := d  # en multijoueur : simulé aussi près d'un joueur distant
		for pid in DMNet.i.peers:
			dn = minf(dn, z.center().distance_to((DMNet.i.peers[pid].pos as Vector3) + Vector3(0, 0.9, 0)))
		if dn > 50.0:
			z.visible = false
			if dn > 90.0:  # trop loin : il disparaît (un autre apparaîtra près du joueur)
				zombies.erase(z)
				z.queue_free()
			continue
		z.tick(dt, self)
		if z.is_queued_for_deletion():
			continue
		z.visible = d < 40.0 and (view and view.off_cut() or sees(player, z))

func take_path_budget() -> bool:
	if path_budget <= 0:
		return false
	path_budget -= 1
	path_cd = 0.0 if testing and not real_paths else 0.25 * clampf(5.0 / maxf(float(miners.size()), 5.0), 0.4, 1.0)  # plus de mineurs : plus de recherches par seconde
	return true

## Is ore cell o already targeted by another miner?
func ore_claimed(o: Vector3i, who: Miner) -> bool:
	for m in miners:
		if m != who and m.active and (m.state == Miner.S.GOTO_ORE or m.state == Miner.S.MINE) and m.goal == o:
			return true
	return false

## One simulation step for every miner (at most one A* search per call), then cut visibility.
func tick_miners(dt: float) -> void:
	tick_zombies(dt)
	path_cd -= dt
	path_budget = 1 if path_cd <= 0.0 else 0  # at most one A* search every 0.15 s (they were running every frame)
	game_t += dt
	if DMNet.i.is_client():
		DMNet.i.puppet_tick(dt)  # mineurs IA simulés chez l'hôte
	else:
		for m in miners:
			if (m as Miner).active:
				(m as Miner).tick(dt, self)
	for m in miners:
		var mm: Miner = m
		if not mm.active:
			mm.visible = false
			continue
		# visible like the geometry: own layer and behind fully, up to 3 layers in front (camera side) semi-transparent
		var ahead := 0
		if cut_layer != -999 and not (view and view.off_cut()):
			var c: int = floori(mm.pos[cut_axis] + (0.05 if cut_axis == 1 else 0.0))
			ahead = (cut_layer - c) if cut_sign > 0 else (c - cut_layer)
		# ... and only if the player has a real voxel line of sight from his head (§3)
		var cc := Vector3i(mm.center().floor())
		var near := mm.center().distance_to(player.center()) < 40.0
		var seen_now := ahead <= 3 and near and (view and view.off_cut() or (sees(player, mm) \
				and (fog.is_seen(cc) or fog.is_seen(cc + Vector3i(0, 1, 0)) or fog.is_seen(Vector3i(mm.pos.floor())))))
		# hysteresis: shows at once, hides only after 0.4 s out of sight (no 1-frame blinks at grazing angles)
		var vt: float = vis_hold.get(mm.mname, 0.0)
		vt = 0.4 if seen_now else vt - dt
		vis_hold[mm.mname] = vt
		mm.visible = vt > 0.0
		mm.spr.modulate.a = 1.0  # alpha discard only: a blended sprite quad could draw as a black rectangle
		mm.spr.transparent = false
		mm.spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD

func _make_miner(d: Dictionary) -> Miner:
	var m := Miner.new()
	m.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	d = d.duplicate()
	if not d.has("personality"):
		d["personality"] = MINER_DEFS[miners.size() % MINER_DEFS.size()][2]
	if not d.has("species"):  # anciennes sauvegardes / miners créés à la volée
		var nm: String = d.get("name", "")
		d["species"] = absi(hash(nm)) % DMSettings.BODIES.size()  # stable d'après le nom
		for r in MINER_DEFS:
			if r[0] == nm:
				d["species"] = r[4]
	m.from_dict(d)
	add_child(m)
	_fit_body(m)  # un géant qui apparaît dans un passage bas : on lui fait de la place
	miners.append(m)
	return m

## Dry, safe spots far from the player and from each other, preferably near ore.
func find_miner_spots(n: int) -> Array:
	var cands: Array = []
	var ps := Vector3(world.spawn)
	for x in range(6, World.SX - 6, 2):
		for z in range(5, World.SZ - 5, 2):
			for y in range(52, 9, -1):
				var c := Vector3i(x, y, z)
				if not Pathfinder.standable(world, c) or world.get_v(c + Vector3i(0, 2, 0)) != World.AIR:
					continue
				if Vector3(c).distance_to(ps) < 14.0 or not _spot_dry(c) or _near_spawn_room(c):
					continue
				var far := Vector3(c).distance_to(ps) > 34.0 or absf(c.y - ps.y) > 12.0  # base trop loin du spawn : trajet interminable (grande carte)
				cands.append([_ore_score(c) - maxf(0.0, Vector3(c).distance_to(ps) - 20.0) * 2.0 - (1000.0 if far else 0.0), c])  # rich spots, but near the spawn
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array = []
	for gap in [13.0, 9.0, 6.0]:  # on resserre l'espacement plutôt que d'envoyer une base trop loin du spawn
		for e in cands:
			if out.size() >= n:
				break
			var c: Vector3i = e[1]
			if (e[0] as float) < -500.0 and gap > 6.0:
				continue  # candidat trop éloigné : en dernier recours seulement
			var ok := not (c in out)
			for o in out:
				if Vector3(c).distance_to(Vector3(o)) < gap:
					ok = false
					break
			if ok:
				out.append(c)
	return out

## Place i dans la salle de spawn (grille, évite le joueur et le panneau-poteau).
func _hub_start(i: int) -> Vector3:
	var h: SpawnHub = hub_n.hub
	var cols := 8
	var p := Vector3(h.ix0 + 2 + (i % cols) * 2 + 0.5, h.spawn_pos.y, h.iz0 + 2 + (i / cols) * 2 + (i % 2) * 2 + 0.5)
	if Vector3i(p) == Vector3i(h.spawn_pos) or not Pathfinder.standable(world, Vector3i(p)):
		p = h.spawn_pos + Vector3(2 + (i % 3), 0, 2 - (i % 3))
	return p

## Sortie de la salle de spawn la plus proche d'une base (cellule au bout du tunnel), (-1,-1,-1) sans salle.
func hub_exit_toward(b: Vector3i) -> Vector3i:
	var best := Vector3i(-1, -1, -1)
	var bd := INF
	if hub_n == null:
		return best
	for e in hub_n.hub.exits:
		for k in range(int(e[2]), 0, -1):  # dernière cellule praticable du tunnel
			var c: Vector3i = e[0] + e[1] * k
			if Pathfinder.standable(world, c):
				var d := Vector3(c).distance_to(Vector3(b))
				if d < bd:
					bd = d
					best = c
				break
	return best

func spawn_point() -> Vector3:
	return hub_n.hub.spawn_pos if hub_n else Vector3(world.spawn)

func _spot_dry(c: Vector3i) -> bool:
	for y in range(c.y, mini(c.y + 8, World.SY - 1)):  # nothing liquid above the head
		if World.KIND[world.get_b(c.x, y, c.z)] == World.K_FLUID:
			return false
	for x in range(c.x - 3, c.x + 4):
		for z in range(c.z - 2, c.z + 3):
			for y in range(c.y - 1, c.y + 4):
				var id := world.get_b(x, y, z)
				if World.KIND[id] == World.K_FLUID or id == World.CHEST or id == World.TORCH:
					return false
	return true

func _ore_score(c: Vector3i) -> int:
	var n := 0
	for x in range(c.x - 8, c.x + 9, 2):
		for y in range(c.y - 6, c.y + 7, 2):
			for z in range(c.z - 8, c.z + 9, 2):
				var id := world.get_b(x, y, z)
				if id == World.COAL or id == World.IRON or id == World.COPPER or id == World.CRYSTAL:
					n += 1
	return n

func spawn_miners() -> void:
	var spots := find_miner_spots(MINER_DEFS.size())
	for i in spots.size():
		var c: Vector3i = spots[i]
		var start := Vector3(c) + Vector3(0.5, 0, 0.5)
		if hub_n:  # nouvelle partie : tout le monde démarre dans la salle de spawn, puis part à son heure
			start = _hub_start(i)
		var m := _make_miner({"name": MINER_DEFS[i][0], "color": MINER_DEFS[i][1], "personality": MINER_DEFS[i][2], "species": MINER_DEFS[i][4], "pos": start, "base": c, "inv": {World.TORCH: 3}})
		m.plan_base(self)
		if hub_n:
			m.wait_t = randf_range(2.0, 40.0)  # départs étalés
	print("[DM] %d mineurs IA" % miners.size())

# ---------------------------------------------------------------- inspection (F)
## Coffre d'ancienne mine à portée (visé, sinon le plus proche) qui contient encore quelque chose.
func _lootable_chest() -> Variant:
	var best: Variant = null
	var bd := REACH
	for c in chests:
		if chest_owner.get(c, "") != MINE_CHEST or world.get_v(c) != World.CHEST or (chests[c] as Dictionary).is_empty():
			continue
		var d := (Vector3(c) + Vector3(0.5, 0.5, 0.5)).distance_to(player.center())
		if d < bd:
			bd = d
			best = c
	return best

func _take_loot(c: Vector3i) -> void:
	var parts: Array = []
	for id in chests[c]:
		inv[id] = inv.get(id, 0) + int(chests[c][id])
		parts.append("%d %s" % [int(chests[c][id]), World.NAMES[id]])
	chests[c] = {}
	hud.toast("Coffre d'ancien mineur : " + ", ".join(parts))

func _interact() -> void:
	if inspect != null:
		inspect = null
		hud.hide_panel()
		return
	var best: Miner = null
	var bd := 3.0
	for m in miners:
		var d := (m as Miner).center().distance_to(player.center())
		if d < bd and (m as Miner).visible and (m as Miner).active:
			bd = d
			best = m
	if best == null:
		var fc: Variant = _forge_near()
		if fc != null:
			book.open()
			return
	var lc: Variant = _lootable_chest()
	if best == null and lc != null:
		_take_loot(lc)
		return
	if best:
		inspect = best
	elif not target.is_empty() and world.get_v(target.cell) == World.CHEST:
		inspect = target.cell
	else:
		var bc: Variant = null
		var cd := REACH
		for c in chests:
			var d := (Vector3(c) + Vector3(0.5, 0.5, 0.5)).distance_to(player.center())
			if d < cd and world.get_v(c) == World.CHEST:
				cd = d
				bc = c
		inspect = bc
	if inspect == null:
		hud.toast("Approchez-vous d'un mineur ou d'un coffre (F)")
	_update_inspect()

static func _inv_text(d: Dictionary) -> String:
	var parts: Array = []
	for id in d:
		if d[id] > 0:
			parts.append("%s x%d" % [World.NAMES[id], d[id]])
	return "(vide)" if parts.is_empty() else ", ".join(parts)

func _update_inspect() -> void:
	if inspect == null:
		return
	var txt := ""
	var where: Vector3
	if inspect is Miner:
		var m: Miner = inspect
		where = m.center()
		var built: int = m.stats.built
		txt = "%s  -  %s   PV %d   (%s, %s, %s)\nSac : %s\nMinerai extrait : %d   déposé : %d   blocs posés : %d" % [m.mname, m.status, int(m.health), Brain.STATUS_NAMES[m.brain.status_of("player")], m.personality, DMSettings.BODIES[m.species], _inv_text(m.inv), m.stats.mined, m.stats.deposited, built]
		if chests.has(m.chest):
			txt += "\nCoffre : %s" % _inv_text(chests[m.chest])
	else:
		var c: Vector3i = inspect
		where = Vector3(c) + Vector3(0.5, 0.5, 0.5)
		txt = "Coffre de %s  (on regarde, on ne vole pas)\n%s" % [chest_owner.get(c, "?"), _inv_text(chests.get(c, {}))]
	if where.distance_to(player.center()) > 6.0:
		inspect = null
		hud.hide_panel()
		return
	hud.show_panel(txt)

# ---------------------------------------------------------------- save / load
func save_game(path: String) -> bool:
	if path == SAVE_PATH and not save_enabled:
		return false  # tests / captures never touch the real save
	var md: Array = []
	for m in miners:
		md.append((m as Miner).to_dict())
	var data := {"version": 1, "seed": seed_v, "size": world.blocks.size(),
		"blocks": world.blocks.compress(FileAccess.COMPRESSION_ZSTD), "fluid": world.fluid_lvl.compress(FileAccess.COMPRESSION_ZSTD), "spawn": world.spawn,
		"player": {"pos": player.pos, "health": player.health, "inv": inv.duplicate(), "sel": sel, "body": int(DMSettings.look.get("body", 0)), "hotbar": hotbar.duplicate(), "stacks": Stacks.to_dict(self), "gear": gear.duplicate(true), "pois_found": pois_found.duplicate()},
		"miners": md, "chests": chests.duplicate(true), "chest_owner": chest_owner.duplicate(), "torches": torch_lights.keys(),
		"partial": world.partial.duplicate(), "frac": frac.duplicate(), "signs": world.signs.duplicate(true), "home": hub_n.cmds.to_dict() if hub_n else {}, "social": social.to_dict() if social else {},
		"fow": fog.save_data() if fog else ""}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(data)
	f.close()
	return DirAccess.rename_absolute(tmp, path) == OK

func _read_save(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var d: Variant = f.get_var()
	if not (d is Dictionary) or d.get("version", 0) != 1 or not d.has("blocks"):
		push_warning("sauvegarde illisible : " + path)
		return null
	var raw: PackedByteArray = (d.blocks as PackedByteArray).decompress(int(d.size), FileAccess.COMPRESSION_ZSTD)
	if raw.size() != World.SX * World.SY * World.SZ:
		push_warning("sauvegarde incompatible (autre taille de carte) : " + path)
		if not path.ends_with(".old"):
			DirAccess.copy_absolute(path, path + ".old")  # l'ancienne partie est gardée à côté, la nouvelle ne l'écrase pas
		return null
	d.raw = raw
	d.fl = (d.fluid as PackedByteArray).decompress(raw.size(), FileAccess.COMPRESSION_ZSTD) if d.has("fluid") else null  # ancienne sauvegarde : eau pleine
	return d

func _apply_blocks(d: Dictionary) -> void:
	world.blocks = d.raw
	world.partial = (d.get("partial", {}) as Dictionary).duplicate()
	frac = (d.get("frac", {}) as Dictionary).duplicate()
	world.load_fluid(d.fl)
	world.spawn = d.get("spawn", world.spawn)
	seed_v = d.get("seed", 1337)
	world.compute_styles(seed_v)
	if d.has("signs"):
		world.signs = (d.signs as Dictionary).duplicate(true)
	world._collect_lights()

func _apply_state(d: Dictionary) -> void:
	if fog:
		fog.reset()
		fog.load_data(d.get("fow", ""))
	var pd: Dictionary = d.get("player", {})
	if pd.has("body") and int(pd.body) != int(DMSettings.look.get("body", 0)):  # l'espèce est celle de la partie
		DMSettings.look["body"] = int(pd.body)
		player.apply_species()
		player.refresh_look()
		_fit_player()
	player.pos = pd.get("pos", world.spawn)
	player.position = player.pos
	player.vel = Vector3.ZERO
	player.health = pd.get("health", 100.0)
	inv = (pd.get("inv", {}) as Dictionary).duplicate()
	gear = Gear.sanitize(pd.get("gear", {}))
	apply_gear()
	pois_found = (pd.get("pois_found", []) as Array).duplicate()
	if pd.has("hotbar") and (pd.hotbar as Array).size() == hotbar.size():  # barre rapide de la partie
		hotbar = (pd.hotbar as Array).duplicate()
		Stacks.from_dict(self, pd.get("stacks", {}))
		if hud:
			hud.sync_hotbar(hotbar)
	sel = clampi(int(pd.get("sel", 0)), 0, hotbar.size() - 1)
	player.set_lane_axis(player.lane_axis)
	chests = (d.get("chests", {}) as Dictionary).duplicate(true)
	chest_owner = (d.get("chest_owner", {}) as Dictionary).duplicate()
	for m in miners:
		(m as Node).queue_free()
	miners.clear()
	for md in d.get("miners", []):
		_make_miner(md)
	if hub_n and d.has("home") and not (d.home as Dictionary).is_empty():
		hub_n.cmds.from_dict(d.home)
	if social:
		if d.has("social") and not (d.social as Dictionary).is_empty():
			social.from_dict(d.social)
		_link_agents(false)
	# torch lights from the blocks themselves (source of truth)
	for c in torch_lights.keys():
		_remove_torch_light(c)
	var i := world.blocks.find(World.TORCH)
	while i >= 0:
		_add_torch_light(Vector3i(i % World.SX, (i / World.SX) % World.SY, i / (World.SX * World.SY)))
		i = world.blocks.find(World.TORCH, i + 1)
	_update_lights()

## Loads a save into the running scene (blocks, meshes, player, miners, chests, torches).
func load_game(path: String) -> bool:
	var d: Variant = _read_save(path)
	if d == null:
		return false
	world.blocks = d.raw
	world.partial = (d.get("partial", {}) as Dictionary).duplicate()
	frac = (d.get("frac", {}) as Dictionary).duplicate()
	world.load_fluid(d.fl)
	world.spawn = d.get("spawn", world.spawn)
	world.compute_styles(int(d.get("seed", seed_v)))
	if d.has("signs"):
		world.signs = (d.signs as Dictionary).duplicate(true)
		if hub_n:
			for c in hub_n.labels.keys():
				if not world.signs.has(c):
					(hub_n.labels[c] as Node).queue_free()
					hub_n.labels.erase(c)
			for c in world.signs:
				hub_n._make_label(c)
	for k in chunks:
		dirty[k] = true
	_apply_state(d)
	_flush_remesh()
	return true

func _new_game() -> void:
	if save_enabled and FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	next_seed = randi_range(1, 999999)
	save_enabled = false  # nothing from the old game gets written back
	auto_play = false  # on repasse par le menu : l'espèce se choisit avant de jouer
	restart_requested.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game(SAVE_PATH)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and not testing:  # bouton Retour Android = Échap (pause, fermer, revenir)
		var k := InputEventKey.new()
		k.keycode = KEY_ESCAPE
		k.physical_keycode = KEY_ESCAPE
		k.pressed = true
		Input.parse_input_event(k)

# ---------------------------------------------------------------- self-test (--dm-test)
var _fails := 0

# ---------------------------------------------------------------- social: chat, agents, Brain <-> SocialHub
func _setup_social() -> void:
	social = SocialHub.new()
	social.name = "SocialHub"
	social.player_name = PLAYER_NAME
	social.create_defaults = false
	social.simulate_network = not testing and not nettest and shot_path == ""
	social.voice = RuleVoice.new()  # voix 100 % locale (règles)
	social.voice.name = "RuleVoice"
	social.add_child(social.voice)
	add_child(social)
	social.responder = func(pseudo: String, heard: Dictionary) -> Dictionary:
		var m := miner_of(pseudo)
		return m.respond(heard, self) if m and m.active else {}
	social.command_handler = func(t: String) -> String:
		return hub_n.cmds.execute(t) if hub_n else "Pas de commandes ici"
	social.context_provider = func(pseudo: String) -> Dictionary:
		var m := miner_of(pseudo)
		if m == null:
			return {}
		return {"activite": m.status, "pv": int(m.health), "sac": _inv_text(m.inv).left(50)}
	social.agent_joined.connect(_on_agent_joined)
	social.agent_left.connect(_on_agent_left)
	social.agent_action.connect(_on_agent_action)
	chat = ChatUI.new()
	hud.add_child(chat)
	chat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # fill the screen (it sat in a 0-size box: entry at y=-21, off-screen)
	chat.size = get_viewport().get_visible_rect().size
	chat.bind_hub(social)
	chat.blocked = func() -> bool: return hub_n != null and hub_n.typing()
	Pathfinder.protected = func(c: Vector3i) -> bool: return hub_n != null and hub_n.is_protected(c)

## One SocialAgent per miner (same pseudo). fresh: new game -> most players already online.
func _link_agents(fresh: bool) -> void:
	var i := 0
	for m in miners:
		var mm: Miner = m
		var a := social.get_agent(mm.mname)
		if a == null:
			var row: Array = MINER_DEFS[i % MINER_DEFS.size()]
			for r in MINER_DEFS:
				if r[0] == mm.mname:
					row = r
			a = SocialAgent.new(mm.mname, mm.personality, row[3])
			social.add_agent(a)
			for o in miners:  # small friendships / rivalries between the AI players
				if o != m and not a.has_relation((o as Miner).mname):
					a.set_affinity((o as Miner).mname, randi_range(-35, 55))
			if fresh or not social.simulate_network:
				a.online = not social.simulate_network or i < miners.size() - 1
				a.next_change_at = social.now + (randf_range(240.0, 900.0) if a.online else randf_range(40.0, 120.0))
				if not social.simulate_network:
					a.next_change_at = 0.0
		mm.active = a.online
		mm.visible = a.online
		sync_from_agent(mm)
		i += 1

func miner_of(pseudo: String) -> Miner:
	for m in miners:
		if (m as Miner).mname == pseudo:
			return m
	return null

func _on_agent_joined(pseudo: String) -> void:
	var m := miner_of(pseudo)
	if m and not m.active:
		m.active = true
		m.respawn(self)  # appears at his base

func _on_agent_left(pseudo: String) -> void:
	var m := miner_of(pseudo)
	if m:
		m.active = false
		m.visible = false
		m.signal_q.clear()
		if inspect == m:
			inspect = null
			hud.hide_panel()

func _on_agent_action(pseudo: String, action: String, prm: Dictionary) -> void:
	var m := miner_of(pseudo)
	if m == null:
		return
	match action:
		"give":
			var id := Miner.item_id(String(prm.get("item", "")))
			var n := clampi(int(prm.get("count", 1)), 1, 16)
			if id >= 0 and m.has_item(id, n, self):
				m.take_item(id, n, self)
				inv[id] = inv.get(id, 0) + n
				hud.toast("%s vous donne %d %s" % [pseudo, n, World.NAMES[id]])
				m.queue_signal("crouch")
		"trade":
			do_trade(m, Miner._ids(prm.get("give", {})), Miner._ids(prm.get("want", {})))
		"follow":
			m.brain._rel("player").follow = true
		"stop_follow":
			m.brain._rel("player").follow = false
		"break_alliance":
			m.brain._rel("player").ally = false

## Exchange: the miner gives `ai_gives`, receives `ai_wants` (from the player's inventory).
func do_trade(m: Miner, ai_gives: Dictionary, ai_wants: Dictionary) -> bool:
	for id in ai_gives:
		if not m.has_item(id, ai_gives[id], self):
			return false
	for id in ai_wants:
		if inv.get(id, 0) < ai_wants[id]:
			return false
	for id in ai_gives:
		m.take_item(id, ai_gives[id], self)
		inv[id] = inv.get(id, 0) + ai_gives[id]
	for id in ai_wants:
		inv[id] -= ai_wants[id]
		m.inv[id] = m.inv.get(id, 0) + ai_wants[id]
	m.brain.on_event("helped", "player", {}, game_t)
	sync_to_agent(m)
	hud.toast("Échange avec %s : +%s  -%s" % [m.mname, SocialHub.items_text(ai_gives), SocialHub.items_text(ai_wants)])
	return true

## The player said "ok" to an offer the miner made earlier.
func accept_pending(m: Miner) -> Dictionary:
	var p: Dictionary = social.pending.get(m.mname, {})
	social.pending.erase(m.mname)
	if p.is_empty() or float(p.until) < social.now:
		return {"say": "generic", "action": "none", "affinity": 0}
	if p.kind == "alliance":
		if m.brain.accept_alliance("player"):
			m.queue_signal("crouch")
			return {"say": "alliance_yes", "action": "none", "affinity": 2}
		return {"say": "alliance_no", "action": "none", "affinity": 0}
	var ok := do_trade(m, Miner._ids(p.give), Miner._ids(p.want))
	return {"say": "deal" if ok else "trade_fail", "action": "none", "affinity": 1 if ok else 0}

## Agent (persistent, chat colours, gossip) -> Brain.
func sync_from_agent(m: Miner) -> void:
	var a := social.get_agent(m.mname) if social else null
	if a == null:
		return
	for id in a.relations:
		var r: Dictionary = a.relations[id]
		var b := m.brain._rel(id)
		b.aff = float(r.affinity)
		b.met = b.met or bool(r.met)
		b.ally = bool(r.allied)
		b.betrayed_me = bool(r.betrayed)

## Brain -> agent (after every Brain event).
func sync_to_agent(m: Miner) -> void:
	var a := social.get_agent(m.mname) if social else null
	if a == null:
		return
	for id in m.brain.rel:
		var b: Dictionary = m.brain.rel[id]
		if not b.met:
			continue
		var r := a._rel(id)
		r.met = true
		r.affinity = clampi(roundi(b.aff), -100, 100)
		r.allied = b.ally
		r.betrayed = b.betrayed_me
	social.relations_changed.emit(m.mname)

## Communication intent decided by the Brain: AI <-> AI effects, then the hub phrases it.
func miner_intent(m: Miner, it: Dictionary) -> void:
	var tgt: String = it.get("target", "")
	var o := miner_of(tgt)
	if o and o.active:
		match it.intent:
			"invite_alliance":
				if o.brain.accept_alliance(m.mname):
					m.brain.accept_alliance(tgt)
					social.say_intent(tgt, {"intent": "alliance_yes", "target": m.mname})
				else:
					social.say_intent(tgt, {"intent": "alliance_no", "target": m.mname})
				sync_to_agent(o)
				sync_to_agent(m)
			"propose_trade":
				var r := o.brain.evaluate_offer(m.mname, it.want, it.give, o.stock(self))
				if r.accept and o.has_item(it.want.keys()[0], it.want.values()[0], self) and m.has_item(it.give.keys()[0], it.give.values()[0], self):
					for id in it.give:
						m.take_item(id, it.give[id], self)
						o.inv[id] = o.inv.get(id, 0) + it.give[id]
					for id in it.want:
						o.take_item(id, it.want[id], self)
						m.inv[id] = m.inv.get(id, 0) + it.want[id]
					social.say_intent(tgt, {"intent": "trade_yes", "target": m.mname})
				elif randf() < 0.5:
					social.say_intent(tgt, {"intent": "trade_no", "target": m.mname})
	social.say_intent(m.mname, it)

func _update_social(dt: float) -> void:
	nearby_t -= dt
	if nearby_t > 0.0 or social == null:
		return
	nearby_t = 1.0
	var near: Array = []
	for m in miners:
		var mm: Miner = m
		if mm.active and mm.visible and mm.center().distance_to(player.center()) < 12.0:
			near.append(mm.mname)
	social.set_nearby(near)

# ---------------------------------------------------------------- perception: entities, line of sight
func entities() -> Array:
	var out: Array = [["player", player]]
	for m in miners:
		if (m as Miner).active:
			out.append([(m as Miner).mname, m])
	return out

func entity(id: String) -> Player:
	if id == "player":
		return player
	var m := miner_of(id)
	return m if m and m.active else null

func is_active(id: String) -> bool:
	return entity(id) != null

func display_name(id: String) -> String:
	return PLAYER_NAME if id == "player" else id

## Voxel line of sight: no solid block between a and b.
func los(a: Vector3, b: Vector3) -> bool:
	var d := b - a
	var n := ceili(d.length() / 0.2)
	var last := Vector3i(-9999, 0, 0)
	for i in range(1, n):
		var p := a + d * (float(i) / n)
		var c := Vector3i(floori(p.x), floori(p.y), floori(p.z))
		if c == last:
			continue
		last = c
		if World.KIND[world.get_v(c)] == World.K_CUBE:
			if not world.partial.is_empty() and world.in_bounds(c) and world.partial.has(world.cell_idx(c)):
				var pm: int = world.partial[world.cell_idx(c)]  # bloc entamé : seul un morceau plein bloque la vue
				var bit := (1 if p.x - c.x >= 0.5 else 0) + (2 if p.y - c.y >= 0.5 else 0) + (4 if p.z - c.z >= 0.5 else 0)
				if (pm >> bit) & 1 == 0:
					continue
			return false
	return true

## Can `a` see `b` (from a's head to b's head or body)?
func sees(a: Player, b: Player) -> bool:
	var eye := a.pos + Vector3(0, 1.1 if a.crouching else 1.5, 0)
	return los(eye, b.pos + Vector3(0, 1.45, 0)) or los(eye, b.pos + Vector3(0, 0.5, 0))

## Safe zone (spawn room): no combat, no AI mining.
func is_safe_zone(p: Vector3) -> bool:
	return hub_n != null and hub_n.is_safe_zone(p)

func _near_spawn_room(c: Vector3i) -> bool:
	if hub_n == null:
		return false
	var a: Vector3i = hub_n.hub.box_min() - Vector3i(6, 4, 6)
	var b: Vector3i = hub_n.hub.box_max() + Vector3i(6, 5, 6)
	return c.x >= a.x and c.x <= b.x and c.y >= a.y and c.y <= b.y and c.z >= a.z and c.z <= b.z

# ---------------------------------------------------------------- combat
func attacker_of(victim: String, window: float) -> Array:
	var out: Array = []
	for k in hits:
		if hits[k].victim == victim and game_t - float(hits[k].t) <= window:
			out.append(k)
	return out

func victim_of(id: String, window: float) -> String:
	var h: Dictionary = hits.get(id, {})
	return h.victim if not h.is_empty() and game_t - float(h.t) <= window else ""

## A pickaxe hit with the same rules for everyone: reach, line of sight, cooldown, no safe zone.
## Reporte l'équipement sur le joueur (réductions, bonus, recul, épines).
func apply_gear() -> void:
	player.armor = Gear.armor_pct(gear)
	player.dmg_mult = Gear.dmg_mult(gear, _sword_on)
	player.kb_idx = int(gear.kb)
	player.thorns = int(gear.thorns)
	player.sword = int(gear.get("sword", 0)) if _sword_on else 0
	if hud:
		hud.sword_lvl = int(gear.get("sword", 1))
		hud.sync_hotbar(hotbar)
	if DMNet.i.is_client():
		DMNet.i.send_gear(gear_active())

var _sword_on := false
var tool_mine := 1.0

## L'équipement tel qu'il compte maintenant en combat : l'épée seulement si elle est sélectionnée dans la barre.
func gear_active() -> Dictionary:
	var g: Dictionary = gear.duplicate(true)
	if not _sword_on:
		g.sword = 0
	return g

## Coup PvP reçu (validé par l'hôte) : armure, absorption, recul et iframes s'appliquent ici.
func pvp_hurt(dmg: float, from: Vector3, kb: float, att: int) -> void:
	if player.health <= 0.0:
		return
	var fresh_tag := player.tag_t <= 0.0
	if player.hurt(dmg, from, kb, "net%d" % att):
		DMNet.i.pvp_att = {"id": att, "t": Time.get_ticks_msec()}
		if fresh_tag:
			hud.toast("En combat (15 s) : plus de refuge en zone sûre")

## Joueur distant sous le curseur (même zone de clic qu'un mineur).
func pick_remote(screen: Vector2, assist := false) -> int:
	var k: float = 360.0 / cam.size
	var best := 0
	var bd := INF
	for id in DMNet.i.remotes:
		var node: Node3D = DMNet.i.remotes[id].node
		var c := node.position + Vector3(0, 0.9, 0)
		var sp := cam.unproject_position(c)
		# zone de visée généreuse ; en frappant (assist) un joueur à portée est touché même si le curseur dérive (au-dessus de lui, en mouvement...)
		var close := assist and c.distance_to(player.center()) <= PVP_ASSIST + (Gear.SWORD_REACH if player.sword > 0 else 0.0)
		if close or (absf(screen.x - sp.x) <= 0.8 * k and absf(screen.y - sp.y) <= 1.3 * k):
			var d := c.distance_to(player.center())
			if d < bd:
				bd = d
				best = id
	return best

const PVP_ASSIST := 3.2  # (+ portée de l'épée)  # un joueur distant plus près que ça est touché même si le curseur dérive
## Portée de frappe côté client : horizontale généreuse, verticale tolérante (au-dessus ou en dessous de la cible), de centre à centre.
func _pvp_in_reach(feet: Vector3) -> bool:
	var c := feet + Vector3(0, 0.9, 0)
	var dh := Vector2(c.x - player.center().x, c.z - player.center().z).length()
	return dh <= Player.MELEE + 0.9 + (Gear.SWORD_REACH if player.sword > 0 else 0.0) and absf(c.y - player.center().y) <= 2.8

## N : mange une pomme dorée (2 s sans être touché, puis soin + régénération + absorption).
func use_apple() -> void:
	if int(gear.apples) <= 0:
		hud.toast("Pas de pomme dorée (fonderie / livre de recettes)")
	elif player.apple_cd > 0.0 or player.apple_t > 0.0:
		return
	else:
		player.apple_t = Gear.APPLE_USE
		hud.toast("Pomme dorée... (ne te fais pas toucher pendant 2 s)")

func _gear_tick(dt: float) -> void:
	if player.apple_t > 0.0:
		player.apple_t -= dt
		if player.apple_t <= 0.0 and player.health > 0.0:
			gear.apples = int(gear.apples) - 1
			player.health = minf(player.health + Gear.APPLE_HEAL, player.max_hp)
			player.absorb = Gear.APPLE_ABS
			player.regen_t = Gear.APPLE_REGEN_T
			player.apple_cd = Gear.APPLE_CD
			hud.toast("Pomme dorée : +60 PV, régénération, absorption")

## Bruit de la pioche sur la roche (un coup sur deux, pour ne pas mitrailler).
func _pick_sound(c: Vector3i) -> void:
	pick_n += 1
	if pick_n % 2 == 0:
		DMSfx.play("pick", Vector3(c) + Vector3(0.5, 0.5, 0.5), -3.0, 0.12)

## Coup porté : sifflement de l'arme + choc ; cri de zombie ou de douleur selon qui frappe / qui reçoit.
func _hit_sound(att: Player, vic: Player) -> void:
	DMSfx.play("swing", att.pos, -8.0, 0.12)
	DMSfx.play("pick", vic.pos, 2.0, 0.1)
	if vic == player:
		DMSfx.play("hurt", null, 0.0, 0.1)
		if player.health <= 0.0:
			DMSfx.play("death", null, 0.0, 0.05)
	elif vic is Zombie:
		DMSfx.play("zombie", vic.pos, 0.0, 0.2)
	else:
		DMSfx.play("hurt", vic.pos, -2.0, 0.15)

func try_hit(att_id: String, att: Player, vic_id: String, vic: Player) -> bool:
	if att.atk_cd > 0.0 or vic.health <= 0.0 or att.health <= 0.0:
		return false
	# zone sûre : pas de combat, SAUF pour un joueur « en combat » (combat tag : pas de refuge)
	if (is_safe_zone(att.center()) and att.tag_t <= 0.0) or (is_safe_zone(vic.center()) and vic.tag_t <= 0.0):
		if att == player:
			hud.toast("Zone sûre : pas de combat")
		return false
	var reach := Player.MELEE + (Gear.SWORD_REACH if att == player and player.sword > 0 else 0.0)
	if att is Zombie:
		reach = Zombie.HIT_RANGE  # le zombie doit vraiment toucher
	elif vic is Zombie:
		reach += Zombie.PLAYER_BONUS  # le joueur frappe un peu plus loin
	var dist := att.center().distance_to(vic.center())
	if dist > reach:
		return false
	if not (att == player and dist <= 2.4) and not sees(att, vic):  # collé à la cible : pas de test de vue (au-dessus d'elle, contre un bord...)
		return false
	if att.held_by != null or att.holding != null or vic.held_by != null:
		return false  # tenu ou occupé à tenir : pas de coup de pioche
	if _try_grab(att, vic):
		return true
	var fresh_tag := (vic == player and player.tag_t <= 0.0) or (att == player and player.tag_t <= 0.0)
	var kbm: float = Gear.KB_MULT[att.kb_idx] * (0.45 if vic is Zombie else 1.0)  # un zombie touché reste à portée
	if not vic.hurt(Player.DMG * att.dmg_mult, att.pos, kbm, att_id):
		return false  # iframes de 0,25 s vis-à-vis du même attaquant
	att.atk_cd = Player.HIT_CD * (Gear.SWORD_CD if att == player and player.sword > 0 else 1.0)
	att.swing_t = 0.25
	att.combat_t = 6.0
	att.tag_t = Gear.TAG_TIME
	if att == player and vic is Zombie:
		hit_sticky = vic
		hit_sticky_t = 1.2
	_hit_sound(att, vic)
	var fd: float = (vic.pos - att.pos).dot(screen_right())
	if absf(fd) > 0.1:
		att.facing = 1 if fd > 0 else -1
	if vic.thorns > 0:  # épines : renvoie des dégâts, sans recul
		att.health = maxf(att.health - Gear.THORNS_DMG * vic.thorns, 0.0)
	hits[att_id] = {"victim": vic_id, "t": game_t}
	_on_hit(att_id, vic_id)
	if fresh_tag:
		hud.toast("En combat (15 s) : plus de refuge en zone sûre")
	if vic.health <= 0.0 and vic is Zombie:
		zombie_died(vic)
	elif vic.health <= 0.0 and vic is Miner:
		miner_died(vic, att_id)
	return true

## Combat feeds the relations: hitting an ally = betrayal, rumours, witnesses.
## --- SAISIE DU GÉANT : un géant au corps à corps attrape un petit (1 s en main), puis le lance contre un mur proche (dégâts d'impact).
const GRAB_HOLD := 1.0
const GRAB_CD := 9.0
var grabs: Array = []  # {g, v, t, dir} : victime tenue
var flying: Array = []  # victimes lancées, en attente de l'impact

func can_grab(g: Player, v: Player) -> bool:
	return g.hh >= 2.4 and v.hh <= g.hh * 0.7 and not (v is Zombie) and g.grab_cd <= 0.0 and g.health > 0.0 and v.health > 0.0 \
		and g.holding == null and g.held_by == null and v.held_by == null and v.holding == null and v.thrown_t <= 0.0

func _try_grab(g: Player, v: Player, force := false) -> bool:
	if DMNet.i.is_client() or not can_grab(g, v) or (not force and randf() > 0.55):
		return false
	var d := v.pos - g.pos
	d.y = 0.0
	var dir := d.normalized() if d.length() > 0.05 else screen_right() * float(g.facing)
	grabs.append({"g": g, "v": v, "t": GRAB_HOLD, "dir": dir})
	g.holding = v
	v.held_by = g
	g.atk_cd = GRAB_HOLD + 0.8
	g.swing_t = GRAB_HOLD
	g.combat_t = 6.0
	v.combat_t = 6.0
	g.tag_t = Gear.TAG_TIME
	v.tag_t = Gear.TAG_TIME
	DMSfx.play("giant", g.pos, -2.0, 0.15)
	if v == player:
		hud.toast("Un géant vous attrape !")
	return true

func _hand_pos(g: Player, dir: Vector3) -> Vector3:
	var p := g.pos + dir * 0.9 + Vector3(0, g.hh * 0.6, 0)
	return p if not world.box_hits(p, 0.28, 1.0) else g.pos + Vector3(0, g.hh * 0.6, 0)

## Distance jusqu'au premier bloc plein dans la direction dir (en partant de from), ou -1.
func _wall_dist(from: Vector3, dir: Vector3, maxd: float) -> float:
	var t := 0.5
	while t <= maxd:
		var p := from + dir * t
		for dy in [0.3, 1.2]:
			if world.is_solid(world.get_v(Vector3i(floori(p.x), floori(p.y + dy), floori(p.z)))):
				return t
		t += 0.4
	return -1.0

func tick_grabs(dt: float) -> void:
	for gr in grabs.duplicate():
		var g: Player = gr.g
		var v: Player = gr.v
		if not is_instance_valid(g) or not is_instance_valid(v) or g.health <= 0.0 or v.health <= 0.0:
			if is_instance_valid(g):
				g.holding = null
			if is_instance_valid(v):
				v.held_by = null
			grabs.erase(gr)
			continue
		gr.t -= dt
		var hp := _hand_pos(g, gr.dir)
		v.pos = hp
		v.position = hp
		v.vel = Vector3.ZERO
		v.fall_safe_t = 1.0
		if gr.t <= 0.0:
			grabs.erase(gr)
			_throw(g, v, gr.dir)
	for v in flying.duplicate():
		if not is_instance_valid(v) or v.thrown_t <= 0.0 and not v.wall_hit:
			flying.erase(v)
			continue
		if v.wall_hit:
			v.wall_hit = false
			flying.erase(v)
			DMSfx.play("giant", v.pos, 0.0, 0.2)
			var at := Vector3i(floori(v.center().x + v.vel.x * 0.05), floori(v.center().y), floori(v.center().z + v.vel.z * 0.05))
			chip_burst(at, world.get_v(at) if world.is_solid(world.get_v(at)) else World.STONE, 1.0)
			if v == player:
				shake = 0.35
				hud.toast("Écrasé contre le mur !")

func _throw(g: Player, v: Player, dir0: Vector3) -> void:
	var from := v.pos + Vector3(0, 0.5, 0)
	var best := dir0
	var best_d := 7.0
	var best_a := 1e9
	for k in 24:
		var a := TAU * float(k) / 24.0
		var dr := Vector3(cos(a), 0, sin(a))
		var dist := _wall_dist(from, dr, 10.0)
		if dist < 3.0:
			continue
		var ang := acos(clampf(dr.dot(dir0), -1.0, 1.0))
		if ang < best_a:
			best_a = ang
			best = dr
			best_d = dist
	var spd := clampf(best_d * 2.2, 9.0, 16.0)
	var t := best_d / spd
	g.holding = null
	v.held_by = null
	v.vel = best * spd + Vector3(0, 0.5 * Player.GRAV * t + 1.5, 0)
	v.thrown_v = spd
	v.thrown_age = 0.0
	v.thrown_t = t + 1.5
	v.on_ground = false
	g.grab_cd = GRAB_CD
	g.atk_cd = 0.8
	g.swing_t = 0.4
	flying.append(v)
	DMSfx.play("giant", g.pos, -1.0, 0.1)

func _on_hit(att_id: String, vic_id: String) -> void:
	if vic_id == "player" and social:
		social.world_event("player_hit")
	var vm := miner_of(vic_id)
	var key := att_id + ">" + vic_id
	if vm:
		var was_ally: bool = vm.brain.status_of(att_id) == Brain.Status.ALLIE
		vm.brain.on_event("hit_me", att_id, {}, game_t)
		sync_to_agent(vm)
		if was_ally:
			social.notify_event(vic_id, "betrayal", {"from": att_id})
		elif game_t - float(hit_notified.get(key, -99.0)) > 15.0:
			social.notify_event(vic_id, "attacked", {"from": att_id})
		hit_notified[key] = game_t
		sync_from_agent(vm)
	var am := miner_of(att_id)
	if am:
		am.brain._rel(vic_id).hurt_them = true
	var att := entity(att_id)
	for m in miners:
		var w: Miner = m
		if not w.active or w.mname == att_id or w.mname == vic_id or att == null:
			continue
		if w.center().distance_to(att.center()) < Miner.VIEW and sees(w, att) and w.brain.status_of(vic_id) in [Brain.Status.AMI, Brain.Status.ALLIE]:
			w.brain._aff(att_id, -4.0)
			sync_to_agent(w)

## Death of a miner (combat, lava, fall): part of the bag dropped, respawn at the base, chests kept.
var miner_deaths := 0
var death_log: Array = []

func miner_died(m: Miner, killer: String) -> void:
	miner_deaths += 1
	death_log.append([m.mname, snapped(game_t, 0.1), m.pos.snapped(Vector3(0.1, 0.1, 0.1)), killer])
	if killer == "":
		var a := attacker_of(m.mname, 4.0)
		killer = a[0] if not a.is_empty() else ""
	for id in m.inv.keys():
		var n: int = m.inv[id]
		if n <= 0:
			continue
		var k := ceili(n / 2.0)
		m.inv[id] = n - k
		drop_item(id, k, m.pos + Vector3(randf_range(-0.6, 0.6), 0.3, randf_range(-0.6, 0.6)))
	var by_zombie := killer == "zombie"
	if by_zombie:
		killer = ""
	if killer != "":
		m.brain.on_event("killed_me", killer, {}, game_t)
		sync_to_agent(m)
	if social:
		social.system_message("%s %s" % [m.mname, ("a été tué par " + display_name(killer)) if killer != "" else ("a été tué par un zombie" if by_zombie else "est mort")])
		social.say_intent(m.mname, {"intent": "died", "target": killer})
		var km := miner_of(killer)
		if km:
			social.say_intent(killer, {"intent": "killed", "target": m.mname})
	for k in hits.keys():
		if hits[k].victim == m.mname:
			hits.erase(k)
	m.respawn(self)

## A miner under the mouse (screen-space box around the sprite), the closest to the player.
var hit_sticky: Miner = null  # dernier zombie frappé (cible collante)
var hit_sticky_t := 0.0

func pick_miner(screen: Vector2) -> Miner:
	var k: float = 360.0 / cam.size
	var best: Miner = null
	var bd := INF
	for m in miners + zombies:
		var mm: Miner = m
		if not mm.active or not mm.visible or (mm is Zombie and (mm as Zombie).burrowing):
			continue
		var sp := cam.unproject_position(mm.center())
		var tx := 0.5
		var ty := 1.0
		if mm is Zombie:  # ennemi : zone de visée généreuse (on ne doit pas viser au pixel)
			tx = 0.95
			ty = 1.35
			if mm == hit_sticky and hit_sticky_t > 0.0:
				tx = 1.6  # déjà en train de le frapper : il reste ciblé même si le curseur dérive
				ty = 1.8
		if absf(screen.x - sp.x) <= tx * k and absf(screen.y - sp.y) <= ty * k:
			var d := mm.center().distance_to(player.center())
			if d < bd:
				bd = d
				best = mm
	return best

# ---------------------------------------------------------------- items on the ground
func drop_item(id: int, n: int, at: Vector3) -> void:
	var s := Sprite3D.new()
	var tex := AtlasTexture.new()
	tex.atlas = atlas
	var t: int = World.TILE[id]
	tex.region = Rect2((t % 4) * 16, (t / 4) * 16, 16, 16)
	s.texture = tex
	s.pixel_size = 1.0 / 32.0
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = true
	s.transparent = false
	s.double_sided = true
	add_child(s)
	s.position = at
	drops.append({"node": s, "item": id, "count": n, "t": 0.0, "base": at})

func _update_drops(dt: float) -> void:
	var i := 0
	while i < drops.size():
		var d: Dictionary = drops[i]
		var s: Sprite3D = d.node
		d.t += dt
		# fall to the ground
		var b: Vector3 = d.base
		if not world.is_solid(world.get_v(Vector3i(floori(b.x), floori(b.y - 0.3), floori(b.z)))) and b.y > 1.0:
			b.y -= dt * 6.0
			d.base = b
		s.position = b + Vector3(0, 0.35 + 0.08 * sin(d.t * 3.0), 0)
		s.visible = fog.is_seen(Vector3i(b.floor()))  # fog of war: only in the cells seen now
		s.rotation.y = d.t * 2.5
		s.visible = cut_layer == -999 or cell_visible(Vector3i(b))
		var taker: Player = null
		if player.center().distance_to(s.position) < 1.1:
			taker = player
		else:
			for m in miners:
				if (m as Miner).active and (m as Miner).center().distance_to(s.position) < 1.0:
					taker = m
					break
		if taker or d.t > 300.0:
			if taker == player:
				inv[d.item] = inv.get(d.item, 0) + d.count
				hud.toast("+%d %s" % [d.count, World.NAMES[d.item]])
			elif taker:
				(taker as Miner).inv[d.item] = (taker as Miner).inv.get(d.item, 0) + d.count
			s.queue_free()
			drops.remove_at(i)
			continue
		i += 1

# ---------------------------------------------------------------- non-verbal signs
## `actor` jumped / crouched: miners who see it may recognise a sign (x2) and answer it.
func broadcast_action(actor_id: String, actor: Player, kind: String) -> void:
	for m in miners:
		var mm: Miner = m
		if mm == actor or not mm.active or mm.center().distance_to(actor.center()) > Miner.VIEW or not sees(mm, actor):
			continue
		var ev := mm.brain.observe_action(actor_id, kind, game_t)
		if ev == "":
			continue
		sync_to_agent(mm)
		if mm.brain.status_of(actor_id) == Brain.Status.ENNEMI or not mm.brain._cool("echo:" + actor_id, game_t, 20.0):
			continue
		mm.queue_signal("jump" if ev == "signal_greet" else "crouch")
		if actor_id == "player" and ev == "signal_greet" and randf() < 0.4:
			social.say_intent(mm.mname, {"intent": "greet", "target": "player"})

func _diag_report() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.physical_keycode = KEY_ENTER
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[DIAG] après Entrée : chat_open=%s" % str(chat.is_open if chat else false))
	var fo := get_viewport().gui_get_focus_owner()
	print("[DIAG] focus=%s" % (str(fo.get_path()) if fo else "aucun"))
	for ch in "salut":
		var kv := InputEventKey.new()
		kv.keycode = OS.find_keycode_from_string(ch.to_upper())
		kv.unicode = ch.unicode_at(0)
		kv.pressed = true
		Input.parse_input_event(kv)
		await get_tree().process_frame
		var ku := kv.duplicate()
		ku.pressed = false
		Input.parse_input_event(ku)
		await get_tree().process_frame
	print("[DIAG] texte saisi='%s'" % (chat._entry.text if chat else "?"))
	var e: Control = chat._entry
	print("[DIAG] chat visible_tree=%s entry visible_tree=%s rect=%s vp=%s modulate=%s/%s hud_layer=%d" % [str(chat.is_visible_in_tree()), str(e.is_visible_in_tree()), str(e.get_global_rect()), str(get_viewport().get_visible_rect().size), str(chat.modulate), str(e.modulate), hud.layer])
	var n: Node = e
	while n:
		if n is CanvasItem and not (n as CanvasItem).visible:
			print("[DIAG] caché par : %s" % n.get_path())
		n = n.get_parent()
	var pc := player.pos
	for m in miners:
		var mm: Miner = m
		print("[DIAG] %s actif=%s dist=%.0f visible=%s" % [mm.mname, str(mm.active), mm.pos.distance_to(pc), str(mm.visible)])
		print("[DIAG]   espece=%d body=%s vis_hh=%.2f scale=%.2f" % [mm.species, str(mm.pal.get("body", "?")), mm.vis_hh, mm.vbody.scale.y if mm.vbody else -1.0])
	var act := 0
	for m in miners:
		if (m as Miner).active:
			act += 1
	var on: Array = social.online_agents() if social else []
	print("[DIAG] state=%s miners=%d actifs=%d en_ligne=%d chat_open=%s hub_typing=%s view=%s save_chargee=%s" % [state, miners.size(), act, on.size(), str(chat.is_open if chat else false), str(hub_n.typing() if hub_n else false), str(view.mode if view else -1), str(loaded)])
	for p in (social.agents.keys() if social else []):
		print("[DIAG] agent %s online=%s" % [p, str(social.agents[p].online)])
	exit_requested.emit()
