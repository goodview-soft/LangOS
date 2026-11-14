class_name ArenaManager
extends Node3D
## Génère l'arène symétrique (deux îles, ponts de départ, lits), l'environnement et les zones interdites.

const FORBID_RADIUS := 3.5   # zone protégée autour de chaque lit (en blocs)

var blocks: BlockManager

func build() -> void:
	_island(2, 15, 5, 18, Cfg.B_RED_FLOOR)
	_island(48, 61, 5, 18, Cfg.B_BLUE_FLOOR)
	# Ponts de départ (le vide au milieu doit être comblé par les joueurs)
	blocks.fill_box(Vector3i(16, 6, 10), Vector3i(21, 7, 13), Cfg.B_BRIDGE)
	blocks.fill_box(Vector3i(42, 6, 10), Vector3i(47, 7, 13), Cfg.B_BRIDGE)
	# Rebords (dos et côtés de chaque base)
	blocks.fill_box(Vector3i(2, 8, 5), Vector3i(2, 8, 18), Cfg.B_STONE)
	blocks.fill_box(Vector3i(61, 8, 5), Vector3i(61, 8, 18), Cfg.B_STONE)
	for x in [Vector2i(2, 15), Vector2i(48, 61)]:
		blocks.fill_box(Vector3i(x.x, 8, 5), Vector3i(x.y, 8, 5), Cfg.B_STONE)
		blocks.fill_box(Vector3i(x.x, 8, 18), Vector3i(x.y, 8, 18), Cfg.B_STONE)
	# Piliers décoratifs d'angle
	for cx in [2, 15, 48, 61]:
		for cz in [5, 18]:
			blocks.fill_box(Vector3i(cx, 8, cz), Vector3i(cx, 10, cz), Cfg.B_STONE)
	blocks.commit_base()
	blocks.rebuild_all()
	_build_beds()
	_build_environment()

func _island(x0: int, x1: int, z0: int, z1: int, floor_id: int) -> void:
	blocks.fill_box(Vector3i(x0, 6, z0), Vector3i(x1, 7, z1), floor_id)
	for i in range(1, 5):
		blocks.fill_box(Vector3i(x0 + i, 6 - i, z0 + i), Vector3i(x1 - i, 6 - i, z1 - i), Cfg.B_STONE)

func _box(size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	return mi

func _build_beds() -> void:
	for team in 2:
		var bed := Node3D.new()
		bed.name = "Bed_" + Cfg.TEAM_NAMES[team]
		var c: Vector3 = Cfg.BEDS[team]
		bed.position = c
		bed.add_child(_box(Vector3(2.0, 0.25, 1.2), Color(0.35, 0.22, 0.12), Vector3(0, 0.125, 0)))
		bed.add_child(_box(Vector3(1.9, 0.3, 1.1), Cfg.TEAM_COLORS[team], Vector3(0, 0.4, 0)))
		var pil_x := -0.7 if team == Cfg.TEAM_RED else 0.7
		bed.add_child(_box(Vector3(0.5, 0.15, 0.85), Color(0.95, 0.95, 0.95), Vector3(pil_x, 0.62, 0)))
		var light := OmniLight3D.new()
		light.light_color = Cfg.TEAM_COLORS[team]
		light.light_energy = 1.2
		light.omni_range = 6.0
		light.position = Vector3(0, 1.2, 0)
		bed.add_child(light)
		add_child(bed)

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.18, 0.3, 0.6)
	psm.sky_horizon_color = Color(0.65, 0.75, 0.9)
	psm.ground_bottom_color = Color(0.05, 0.06, 0.12)
	psm.ground_horizon_color = Color(0.3, 0.38, 0.55)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.5, 0.6, 0.8)
	env.fog_density = 0.0025
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

## Zones où construire/détruire est interdit (autour des lits, des spawns, limites de la carte).
func is_build_forbidden(cell: Vector3i) -> bool:
	if cell.y > Tuning.build_height_limit or cell.y < 2:
		return true
	if cell.x < 1 or cell.x > 62 or cell.z < 2 or cell.z > 21:
		return true
	var cx := cell.x + 0.5
	var cz := cell.z + 0.5
	for team in 2:
		var b: Vector3 = Cfg.BEDS[team]
		if absf(cx - b.x) <= FORBID_RADIUS and absf(cz - b.z) <= FORBID_RADIUS:
			return true
		var s: Vector3 = Cfg.SPAWNS[team]
		if absf(cx - s.x) <= 1.6 and absf(cz - s.z) <= 1.6 and cell.y >= 8 and cell.y <= 10:
			return true
	return false
