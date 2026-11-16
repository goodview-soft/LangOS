class_name PlayerController
extends CharacterBody3D
## Joueur (humain ou IA) : assemble les composants et pilote le tick physique.

signal died(player: PlayerController, cause: String)
signal respawned(player: PlayerController)
signal swung
signal jumped
signal landed(speed: float)
signal knocked(dir: Vector3)

var game: GameManager
var authority: ServerAuthority
var blocks: BlockManager
var team := 0
var display_name := "Joueur"
var is_local := false

var cmd := InputCmd.new()
var provider: Node            # HumanInput ou BotBrain : gather(cmd, dt)
var ai_paused := false        # utilisé par les tests
var auto_bridge := false      # pose automatique d'un bloc sous les pieds (tactile : activée par défaut)
var net_puppet := false       # client réseau : joueur distant, position pilotée par les snapshots de l'hôte
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0
var pid := 0                  # identifiant réseau (1 = hôte)
var spawn_idx := 0            # place dans l'équipe (décale le point d'apparition)

var move: MovementController
var combat: CombatController
var knock: KnockbackController
var inv: InventoryController
var health: PlayerHealth
var view_model: ViewModel

var yaw := 0.0
var pitch := 0.0
var alive := true
var frozen := false
var kills := 0
var deaths := 0
var last_attacker: PlayerController
var last_attacker_time := -100.0
var mine_progress := 0.0

var head: Node3D
var camera: Camera3D
var body_root: Node3D
var _col: CollisionShape3D
var _mats: Array[StandardMaterial3D] = []
var _head_mesh: MeshInstance3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _highlight: MeshInstance3D
var _walk_t := 0.0
var _cam_dip := 0.0
var _cam_kick := 0.0
var _fov := Tuning.base_fov

func setup(p_game: GameManager, p_team: int, p_name: String, p_local: bool, puppet := false) -> void:
	game = p_game
	team = p_team
	display_name = p_name
	is_local = p_local
	net_puppet = puppet
	authority = game.authority
	blocks = game.blocks
	collision_layer = 2
	collision_mask = 3
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	_col.shape = cap
	_col.position.y = 0.9
	add_child(_col)
	head = Node3D.new()
	head.position.y = 1.62
	add_child(head)
	_build_body()
	if is_local:
		camera = Camera3D.new()
		camera.fov = Tuning.base_fov
		camera.near = 0.05
		camera.far = 300.0
		camera.current = true
		head.add_child(camera)
		view_model = ViewModel.new()
		camera.add_child(view_model)
		_highlight = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 1.01
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, 0.18)
		bm.material = m
		_highlight.mesh = bm
		_highlight.top_level = true
		_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_highlight)
	move = MovementController.new()
	move.p = self
	add_child(move)
	knock = KnockbackController.new()
	knock.p = self
	add_child(knock)
	inv = InventoryController.new()
	add_child(inv)
	health = PlayerHealth.new()
	health.p = self
	add_child(health)
	combat = CombatController.new()
	combat.p = self
	combat.placement = BlockPlacement.new(self)
	combat.destruction = BlockDestruction.new(self)
	combat.bridge = AutoBridge.new(self)
	add_child(combat)
	if view_model:
		view_model.setup(self)
	move.jumped.connect(func() -> void:
		jumped.emit()
		if is_local:
			Sfx.play(game, "jump"))
	move.landed.connect(func(s: float) -> void:
		landed.emit(s)
		Sfx.play(game, "land", global_position, 1.0, clampf(s / 12.0, 0.0, 1.0) * 6.0 - 6.0)
		_cam_dip = clampf(s * 0.012, 0.0, 0.18))
	knock.knocked.connect(func(d: Vector3) -> void:
		knocked.emit(d)
		_cam_kick = 0.05)
	respawn(Cfg.SPAWNS[team], Cfg.SPAWN_YAW[team])

func _build_body() -> void:
	body_root = Node3D.new()
	add_child(body_root)
	var col: Color = Cfg.TEAM_COLORS[team]
	var skin := Color(0.9, 0.74, 0.58)
	_add_part(body_root, Vector3(0.5, 0.7, 0.26), Vector3(0, 1.05, 0), col)
	_leg_l = _pivot(body_root, Vector3(-0.13, 0.7, 0), Vector3(0.22, 0.7, 0.24), col.darkened(0.45))
	_leg_r = _pivot(body_root, Vector3(0.13, 0.7, 0), Vector3(0.22, 0.7, 0.24), col.darkened(0.45))
	_arm_r = _pivot(body_root, Vector3(0.36, 1.35, 0), Vector3(0.16, 0.62, 0.16), skin)
	_add_part(_arm_r, Vector3(0.05, 0.05, 0.7), Vector3(0, -0.55, -0.35), Color(0.85, 0.88, 0.95))
	var arm_l := _pivot(body_root, Vector3(-0.36, 1.35, 0), Vector3(0.16, 0.62, 0.16), skin)
	arm_l.rotation.x = 0.0
	_head_mesh = _add_part(head, Vector3(0.42, 0.42, 0.42), Vector3(0, 0.05, 0), skin)
	_head_mesh.visible = not is_local
	body_root.visible = not is_local
	if not is_local:
		var tag := Label3D.new()
		tag.text = display_name
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.pixel_size = 0.006
		tag.modulate = col.lightened(0.3)
		tag.outline_size = 8
		tag.position.y = 2.15
		add_child(tag)

func _add_part(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission = Color.WHITE
	m.emission_energy_multiplier = 0.0
	m.emission_enabled = true
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	_mats.append(m)
	return mi

## Pivot en haut du membre ; le mesh pend sous le pivot.
func _pivot(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> Node3D:
	var pv := Node3D.new()
	pv.position = pos
	parent.add_child(pv)
	_add_part(pv, size, Vector3(0, -size.y * 0.5, 0), color)
	return pv

func eye_pos() -> Vector3:
	return global_position + Vector3(0, head.position.y, 0)

func aim_dir() -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))

func flat_forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))

func target_block() -> Dictionary:
	return blocks.raycast(eye_pos(), aim_dir(), Tuning.reach)

func _physics_process(dt: float) -> void:
	if net_puppet:
		# Joueur distant côté client : interpolation vers le dernier état reçu de l'hôte
		health.tick(dt)
		if alive:
			var k := clampf(dt * 14.0, 0.0, 1.0)
			global_position = global_position.lerp(net_pos + velocity * 0.04, k)
			yaw = lerp_angle(yaw, net_yaw, k)
			pitch = lerpf(pitch, net_pitch, k)
		return
	if not alive:
		return
	rotation.y = yaw
	if provider and not ai_paused:
		provider.gather(cmd, dt)
	else:
		cmd.clear()
	if frozen:
		cmd.clear()
	cmd.seq += 1
	knock.tick(dt)
	health.tick(dt)
	move.step(cmd, dt)
	combat.tick(cmd, dt)
	if global_position.y < Cfg.VOID_Y:
		kill("void")

func _process(dt: float) -> void:
	rotation.y = yaw
	head.rotation.x = pitch
	head.position.y = lerpf(head.position.y, 1.62 - (Tuning.sneak_eye_drop if move.sneaking else 0.0), clampf(dt * 14.0, 0.0, 1.0))
	# Animation du corps
	var spd := Vector2(velocity.x, velocity.z).length()
	_walk_t += dt * spd * 1.6
	var sw := sin(_walk_t) * clampf(spd / 6.0, 0.0, 1.0) * 0.8
	_leg_l.rotation.x = sw
	_leg_r.rotation.x = -sw
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, 0.0, clampf(dt * 12.0, 0.0, 1.0))
	body_root.visible = not is_local and alive and (not health.is_protected() or int(Time.get_ticks_msec() / 90) % 2 == 0)
	if is_local and camera:
		var sprinting := move.sprinting and spd > 3.0
		_fov = lerpf(_fov, Tuning.base_fov + (Tuning.sprint_fov_bonus if sprinting else 0.0), clampf(dt * 8.0, 0.0, 1.0))
		camera.fov = _fov
		_cam_dip = lerpf(_cam_dip, 0.0, clampf(dt * 10.0, 0.0, 1.0))
		_cam_kick = lerpf(_cam_kick, 0.0, clampf(dt * 9.0, 0.0, 1.0))
		camera.position.y = -_cam_dip
		camera.rotation.x = _cam_kick
		var t := target_block() if alive else {}
		_highlight.visible = not t.is_empty()
		if not t.is_empty():
			_highlight.global_position = Vector3(t["cell"]) + Vector3(0.5, 0.5, 0.5)
			_highlight.global_rotation = Vector3.ZERO

func swing_arm() -> void:
	if _arm_r:
		_arm_r.rotation.x = -1.6
	swung.emit()

func flash(color: Color = Color(1, 0.1, 0.1)) -> void:
	for m in _mats:
		m.emission = color
		m.emission_energy_multiplier = 1.5
		var tw := create_tween()
		tw.tween_property(m, "emission_energy_multiplier", 0.0, 0.25)

func kill(cause: String) -> void:
	if not alive:
		return
	alive = false
	deaths += 1
	velocity = Vector3.ZERO
	mine_progress = 0.0
	_col.set_deferred("disabled", true)
	body_root.visible = false
	if _highlight:
		_highlight.visible = false
	Sfx.play(game, "death", global_position)
	died.emit(self, cause)

func respawn(pos: Vector3, p_yaw: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	yaw = p_yaw
	pitch = 0.0
	alive = true
	_col.set_deferred("disabled", false)
	if health:
		health.reset()
		health.protect(Tuning.spawn_protection)
	if inv:
		inv.reset()
	if combat:
		combat.reset()
	if move:
		move.reset()
	respawned.emit(self)
