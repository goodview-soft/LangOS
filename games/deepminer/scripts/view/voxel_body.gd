class_name VoxelBody extends Node3D
## Miner made of cubes (~1.7 tall), procedural pixel textures. +Z is the front of the body.
## API: set_colors(helmet, shirt), play(anim), face(dir).

static var enabled := true  # false: cut view keeps the billboard sprite
static var outline_on := true  # contour noir façon dessin animé (/contour on|off)
static var _outline_mat: StandardMaterial3D
const OUTLINE_W := 0.03  # épaisseur du contour (blocs)
static var hide_self: Node = null  # FPS: the player's own body is hidden

var anim := "idle"
var t := 0.0
var yaw_goal := 0.0
var upper: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var mats := {}
var crouch := 0.0

static func _tex(base: Color, var_amt: float, seed_v: int) -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for y in 8:
		for x in 8:
			var k := 1.0 + rng.randf_range(-var_amt, var_amt)
			img.set_pixel(x, y, Color(base.r * k, base.g * k, base.b * k, 1.0))
	return ImageTexture.create_from_image(img)

func _mat(key: String, col: Color, var_amt := 0.12, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(Color.WHITE.darkened(0.1), var_amt, key.hash())
	m.albedo_color = col
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON  # ombrage en aplats (cel-shading)
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	mats[key] = m
	return m

## Raw height of the built body (idle pose), from its boxes.
func _measure() -> float:
	var top := 0.0
	var stack: Array = [[self, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		for ch in (e[0] as Node).get_children():
			if ch is Node3D and not ch.is_in_group("body_outline"):
				var t: Transform3D = (e[1] as Transform3D) * (ch as Node3D).transform
				if ch is MeshInstance3D and (ch as MeshInstance3D).mesh:
					var bb: AABB = t * (ch as MeshInstance3D).mesh.get_aabb()
					top = maxf(top, bb.end.y)
				stack.append([ch, t])
	return top

## Uniform scale so the cube body matches the species hitbox height (hh).
func fit(hh: float) -> void:
	_apply_layers(self)
	var raw := _measure()
	if raw > 0.1:
		scale = Vector3.ONE * clampf(hh / raw, 0.6, 1.6)

static var _hit_mat: StandardMaterial3D
static func hit_overlay() -> Material:
	if _hit_mat == null:
		_hit_mat = StandardMaterial3D.new()
		_hit_mat.albedo_color = Color(1.0, 0.1, 0.1, 0.5)
		_hit_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _hit_mat

## Filtre rouge « coup reçu » sur tous les maillages sous root (corps en cubes, modèle de zombie...).
static func hit_tint(root: Node, on: bool) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_overlay = hit_overlay() if on else null

var tool_pick: Node3D
var tool_sword: Node3D
var _tool := "pick"

## Outil tenu : "sword" = épée, sinon la pioche.
func set_tool(id: String) -> void:
	if id == _tool or tool_pick == null:
		return
	_tool = id
	tool_pick.visible = id != "sword"
	tool_sword.visible = id == "sword"

var _tinted := false
func set_hit(on: bool) -> void:
	if on != _tinted:
		_tinted = on
		hit_tint(self, on)

var mesh_layers := ViewCtl.L_BODY_M  # render layer (ViewCtl): L_BODY_P for the player, L_BODY_M for miners

func _apply_layers(n: Node) -> void:
	for ch in n.get_children():
		if ch is VisualInstance3D:
			(ch as VisualInstance3D).layers = mesh_layers
		_apply_layers(ch)

func body_h() -> float:
	return _measure() * scale.y

func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_add_outline(mi, size)
	return mi

## Contour noir : même boîte, un peu plus grande, faces avant éliminées, noire non éclairée.
func _add_outline(mi: MeshInstance3D, size: Vector3) -> void:
	if _outline_mat == null:
		_outline_mat = StandardMaterial3D.new()
		_outline_mat.albedo_color = Color(0.03, 0.02, 0.04)
		_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	var o := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size + Vector3.ONE * (OUTLINE_W * 2.0)
	o.mesh = bm
	o.material_override = _outline_mat
	o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	o.visible = outline_on
	o.add_to_group("body_outline")
	mi.add_child(o)

func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

## Gabarits par espèce (même ordre que DMSettings.BODIES) : jambes, torse, tête, bras (hauteurs en blocs).
const SPECS := [
	{"L": 0.55, "T": 0.6, "W": 0.56, "D": 0.3, "H": 0.44, "AL": 0.55, "AW": 0.2, "LW": 0.24},  # humain
	{"L": 0.2, "T": 0.3, "W": 0.5, "D": 0.32, "H": 0.3, "AL": 0.3, "AW": 0.18, "LW": 0.22},  # nain
	{"L": 1.05, "T": 1.05, "W": 0.95, "D": 0.5, "H": 0.55, "AL": 1.0, "AW": 0.34, "LW": 0.4},  # géant
	{"L": 0.6, "T": 0.42, "W": 0.34, "D": 0.22, "H": 0.52, "AL": 0.5, "AW": 0.14, "LW": 0.15},  # gobelin
	{"L": 0.55, "T": 0.6, "W": 0.5, "D": 0.34, "H": 0.4, "AL": 0.55, "AW": 0.2, "LW": 0.22},  # robot
]
const KINDS := ["human", "dwarf", "giant", "goblin", "robot"]

var hip := 0.55  # hauteur des hanches (= longueur des jambes)
var kind := "human"

func _init() -> void:
	build({}, 0)

static func _col(look: Dictionary, key: String, def: Color) -> Color:
	var v: Variant = look.get(key, null)
	if v == null:
		return def
	return v if v is Color else Color.html(v)

## (Re)construit le corps : gabarit de l'espèce sp + apparence look (clés de DMSettings.look, vide = mineur par défaut).
func build(look: Dictionary, sp: int) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	mats = {}
	sp = clampi(sp, 0, SPECS.size() - 1)
	var S: Dictionary = SPECS[sp]
	kind = KINDS[sp]
	var L: float = S.L
	var T: float = S.T
	var W: float = S.W
	var D: float = S.D
	var H: float = S.H
	var AL: float = S.AL
	var AW: float = S.AW
	var lw: float = S.LW
	hip = L
	var robot := kind == "robot"
	var skin_c := _col(look, "skin", Color(0.93, 0.74, 0.58))
	var helmet_c := _col(look, "helmet", Color(1.0, 0.8, 0.1))
	if robot:
		skin_c = helmet_c.lerp(Color(0.72, 0.75, 0.8), 0.65)
	var skin := _mat("skin", skin_c)
	var skin_d := _mat("skin_d", skin_c.darkened(0.28), 0.1)
	var shirt := _mat("shirt", _col(look, "shirt", Color(0.3, 0.4, 0.7)))
	var pants := _mat("pants", _col(look, "overalls", Color(0.2, 0.22, 0.32)))
	var boots := _mat("boots", _col(look, "boots", Color(0.3, 0.2, 0.12)))
	var helmet := _mat("helmet", helmet_c, 0.08)
	var dark := _mat("dark", Color(0.05, 0.05, 0.07), 0.0)
	var lamp := _mat("lamp", Color(1.0, 0.95, 0.7), 0.0, 2.5)
	var wood := _mat("wood", Color(0.5, 0.33, 0.17), 0.18)
	var iron := _mat("iron", Color(0.65, 0.68, 0.72), 0.15)
	var hair := _mat("hair", _col(look, "hair_color", Color(0.23, 0.14, 0.08)), 0.15)
	var bone := _mat("bone", Color(0.93, 0.9, 0.78), 0.05)
	var eye_y := _mat("eye_y", Color(1.0, 0.9, 0.2), 0.0, 1.6)
	var visor := _mat("visor", Color(0.3, 0.9, 1.0), 0.0, 2.4)
	var led := _mat("led", Color(1.0, 0.4, 0.2), 0.0, 2.2)
	# --- jambes (hanches à y = L)
	leg_l = _pivot(self, Vector3(-W * 0.25, L, 0))
	leg_r = _pivot(self, Vector3(W * 0.25, L, 0))
	var bh := maxf(L * 0.28, 0.07)
	for l in [leg_l, leg_r]:
		_box(l, Vector3(lw, L, lw + 0.02), Vector3(0, -L * 0.5, 0), pants)
		_box(l, Vector3(lw + 0.02, bh, lw + 0.12), Vector3(0, -L + bh * 0.5, 0.05), boots)
		if robot:
			_box(l, Vector3(lw + 0.03, 0.05, lw + 0.05), Vector3(0, -L * 0.5, 0), dark)
	# --- torse
	upper = _pivot(self, Vector3.ZERO)
	_box(upper, Vector3(W, T, D), Vector3(0, L + T * 0.5, 0), shirt)
	if robot:
		_box(upper, Vector3(W * 0.62, T * 0.38, 0.03), Vector3(0, L + T * 0.6, D * 0.5 + 0.01), dark)
		_box(upper, Vector3(0.08, 0.08, 0.03), Vector3(-0.09, L + T * 0.6, D * 0.5 + 0.03), visor)
		_box(upper, Vector3(0.08, 0.08, 0.03), Vector3(0.09, L + T * 0.6, D * 0.5 + 0.03), led)
	else:
		_box(upper, Vector3(W + 0.01, T * 0.5, D + 0.01), Vector3(0, L + T * 0.25, 0), pants)  # salopette
		_box(upper, Vector3(W + 0.02, 0.04, D + 0.02), Vector3(0, L + T * 0.5, 0), wood)  # ceinture
	# --- tête
	head = _pivot(upper, Vector3(0, L + T, 0))
	_box(head, Vector3(H, H, H), Vector3(0, H * 0.5, 0), skin)
	var ey := H * 0.55
	var ex := H * 0.22
	var es := maxf(H * 0.16, 0.05)
	if kind == "goblin":
		_box(head, Vector3(es * 1.8, es * 1.8, 0.02), Vector3(ex, ey, H * 0.5 + 0.01), eye_y)
		_box(head, Vector3(es * 0.7, es * 0.7, 0.02), Vector3(ex, ey, H * 0.5 + 0.02), dark)
		_box(head, Vector3(es, es, 0.02), Vector3(-ex, ey, H * 0.5 + 0.01), dark)
	elif robot:
		_box(head, Vector3(H * 0.8, 0.1, 0.03), Vector3(0, H * 0.58, H * 0.5 + 0.01), visor)
		_box(head, Vector3(H * 0.5, 0.04, 0.02), Vector3(0, H * 0.2, H * 0.5 + 0.01), dark)
	else:
		_box(head, Vector3(es, es, 0.02), Vector3(-ex, ey, H * 0.5 + 0.005), dark)
		_box(head, Vector3(es, es, 0.02), Vector3(ex, ey, H * 0.5 + 0.005), dark)
	if robot:  # antenne-lampe à la place du casque
		_box(head, Vector3(0.04, 0.14, 0.04), Vector3(0.1, H + 0.07, 0), dark)
		_box(head, Vector3(0.09, 0.09, 0.09), Vector3(0.1, H + 0.18, 0), lamp)
	else:
		var hb := H + 0.08
		_box(head, Vector3(hb, 0.13, hb), Vector3(0, H + 0.02, 0), helmet)
		_box(head, Vector3(hb, 0.05, 0.14), Vector3(0, H - 0.03, H * 0.5 + 0.1), helmet)  # visière
		_box(head, Vector3(0.12, 0.1, 0.06), Vector3(0, H + 0.03, H * 0.5 + 0.08), lamp)
	# --- cheveux / barbe (humain et géant choisissent ; les autres ont leurs propres traits)
	if kind == "human" or kind == "giant":
		var hs := int(look.get("hair", 1)) if not look.is_empty() else 0
		if hs >= 1:
			for sgn in [-1.0, 1.0]:
				_box(head, Vector3(0.04, 0.16, H * 0.7), Vector3(sgn * (H * 0.5 + 0.01), H * 0.72, -0.02), hair)
			_box(head, Vector3(H + 0.02, 0.12 if hs == 1 else H * 0.85, 0.1), Vector3(0, H * 0.72 if hs == 1 else H * 0.45, -H * 0.5 - 0.02), hair)
		var bs := int(look.get("beard", 0)) if not look.is_empty() else 0
		if bs == 1:
			_box(head, Vector3(H * 0.6, 0.06, 0.06), Vector3(0, H * 0.3, H * 0.5 + 0.03), hair)
		elif bs >= 2:
			_box(head, Vector3(H * 0.9, H * 0.38, 0.08), Vector3(0, H * 0.18, H * 0.5 + 0.04), hair)
	match kind:
		"dwarf":  # grande barbe jusqu'à la ceinture, gros nez, cornes
			_box(head, Vector3(H * 0.95, H * 0.42, 0.08), Vector3(0, H * 0.2, H * 0.5 + 0.04), hair)
			_box(upper, Vector3(W * 0.78, T * 0.95, 0.09), Vector3(0, L + T * 0.5, D * 0.5 + 0.05), hair)
			_box(upper, Vector3(W * 0.4, 0.12, 0.09), Vector3(0, L + T * 0.02, D * 0.5 + 0.05), hair)
			_box(head, Vector3(0.08, 0.09, 0.1), Vector3(0, H * 0.48, H * 0.5 + 0.06), skin_d)
			for sgn in [-1.0, 1.0]:
				_box(head, Vector3(0.06, 0.16, 0.06), Vector3(sgn * (H * 0.5 + 0.03), H + 0.1, 0), bone)
				_box(head, Vector3(0.05, 0.1, 0.05), Vector3(sgn * (H * 0.5 + 0.09), H + 0.22, 0), bone)
		"giant":  # sourcils épais + défenses
			_box(head, Vector3(H * 0.85, 0.05, 0.05), Vector3(0, H * 0.7, H * 0.5 + 0.01), skin_d)
			for sgn in [-1.0, 1.0]:
				_box(head, Vector3(0.06, 0.13, 0.06), Vector3(sgn * H * 0.25, H * 0.15, H * 0.5 + 0.02), bone)
		"goblin":  # grandes oreilles pointues, long nez, dents
			for sgn in [-1.0, 1.0]:
				var ear := _box(head, Vector3(0.24, 0.07, 0.05), Vector3(sgn * (H * 0.5 + 0.11), H * 0.62, -0.02), skin)
				ear.rotation.z = sgn * deg_to_rad(28.0)
				_box(head, Vector3(0.04, 0.05, 0.02), Vector3(sgn * 0.07, H * 0.17, H * 0.5 + 0.01), bone)
			_box(head, Vector3(0.07, 0.07, 0.2), Vector3(0, H * 0.4, H * 0.5 + 0.09), skin_d)
	# --- bras (épaules en haut du torse)
	var sh_y := L + T - 0.08
	arm_l = _pivot(upper, Vector3(-(W * 0.5 + AW * 0.5 + 0.01), sh_y, 0))
	arm_r = _pivot(upper, Vector3(W * 0.5 + AW * 0.5 + 0.01, sh_y, 0))
	for a in [arm_l, arm_r]:
		_box(a, Vector3(AW, AL, AW + 0.02), Vector3(0, -AL * 0.5 + 0.06, 0), shirt)
		_box(a, Vector3(AW, 0.12, AW + 0.02), Vector3(0, -AL + 0.0, 0), skin)
	# pioche dans la main droite : le manche traverse le poing (prise à 0,15 du bas), tête vers l'avant et le haut
	var pk := _pivot(arm_r, Vector3(0, -AL + 0.02, 0.0))
	pk.rotation.x = deg_to_rad(-58.0)
	pk.scale = Vector3.ONE * clampf(AL / 0.55, 0.8, 1.7)
	_box(pk, Vector3(0.07, 0.07, 0.7), Vector3(0, 0, 0.2), wood)
	_box(pk, Vector3(0.45, 0.08, 0.1), Vector3(0, 0, 0.53), iron)
	tool_pick = pk
	# épée (sortie en combat) : poignée dans le poing, garde, longue lame vers l'avant
	var sw := _pivot(arm_r, Vector3(0, -AL + 0.02, 0.0))
	sw.rotation.x = deg_to_rad(-70.0)
	sw.scale = pk.scale
	_box(sw, Vector3(0.07, 0.07, 0.24), Vector3(0, 0, 0.0), wood)
	_box(sw, Vector3(0.3, 0.06, 0.06), Vector3(0, 0, 0.14), iron)
	_box(sw, Vector3(0.1, 0.035, 0.7), Vector3(0, 0, 0.51), iron)
	sw.visible = false
	tool_sword = sw

## Lueur d'une capacité : émission sur toutes les pièces (amt = 0 : retour à l'état d'origine).
func set_glow(c: Color, amt: float) -> void:
	for k in mats:
		var m: StandardMaterial3D = mats[k]
		if not m.has_meta("e0"):
			m.set_meta("e0", [m.emission_enabled, m.emission, m.emission_energy_multiplier])
		var e0: Array = m.get_meta("e0")
		if amt > 0.01:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = maxf(e0[2] if e0[0] else 0.0, amt * 1.8)
		else:
			m.emission_enabled = e0[0]
			m.emission = e0[1]
			m.emission_energy_multiplier = e0[2]

func set_colors(helmet: Color, shirt: Color) -> void:
	(mats["helmet"] as StandardMaterial3D).albedo_color = helmet
	(mats["shirt"] as StandardMaterial3D).albedo_color = shirt

func play(a: String) -> void:
	if a != anim:
		anim = a
		t = 0.0

func face(dir: Vector3) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() > 0.01:
		yaw_goal = atan2(d.x, d.z)

var phase := 0.0  # walk cycle phase, driven by the ground speed
var spd := 0.0

func _process(dt: float) -> void:
	if not visible:
		return
	t += dt
	rotation.y = lerp_angle(rotation.y, yaw_goal, 1.0 - exp(-dt * 9.0))
	var la := 0.0  # arm swing (x rotation), legs opposite
	var ar := 0.0
	var al := 0.0
	var lgl := 0.0
	var lgr := 0.0
	var cr := 0.0
	var hd := 0.0
	match anim:
		"walk":
			# the stride follows the ground speed (one full cycle = 2.6 blocks): no fast "hopping" at low speed
			phase += dt * spd / 2.6 * TAU
			var s := sin(phase)
			var amp := clampf(spd / 3.0, 0.45, 1.15)
			al = s * 0.65 * amp; ar = -s * 0.65 * amp
			lgl = -s * 0.7 * amp; lgr = s * 0.7 * amp
			hd = absf(s) * 0.018 * amp
		"mine":
			ar = -1.2 + sin(t * 12.0) * 0.9
			al = 0.2
		"jump":
			al = -2.4; ar = -2.4
			lgl = 0.5; lgr = -0.35
		"swim":  # brasse : bras en avant qui alternent, battement de jambes, corps un peu enfoncé
			var sw := sin(t * 5.0)
			al = -1.5 + sw * 0.9; ar = -1.5 - sw * 0.9
			lgl = sw * 0.5; lgr = -sw * 0.5
			hd = sin(t * 3.0) * 0.03
			cr = 0.14 * clampf(hip / 0.55, 0.35, 1.9)
		"crouch":
			cr = 0.28 * clampf(hip / 0.55, 0.35, 1.9)
			lgl = -1.0; lgr = -1.0
			al = -0.4; ar = -0.4
		_:
			al = sin(t * 2.0) * 0.05; ar = -al
			hd = sin(t * 2.0) * 0.01
	crouch = lerpf(crouch, cr, 1.0 - exp(-dt * 16.0))
	var k := 1.0 - exp(-dt * 20.0)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, al, k)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, ar, k)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, lgl, k)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, lgr, k)
	upper.position.y = hd - crouch
	leg_l.position.y = hip - crouch * 0.5
	leg_r.position.y = hip - crouch * 0.5

## Hook for Player._ready: attaches a body to p (sprite stays usable, hidden when the body is shown).
static func attach(p: Player) -> VoxelBody:
	var b := VoxelBody.new()
	b.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # turned in _process; parent is interpolated
	p.add_child(b)
	b.mesh_layers = ViewCtl.L_BODY_M if p is Miner else ViewCtl.L_BODY_P
	p.spr.layers = ViewCtl.L_SPR  # 2D sprites: main 2D view only
	var lk: Dictionary = p.pal if not p.pal.is_empty() else DMSettings.look
	b.build(lk, int(lk.get("body", 0)))
	b.fit(p.vis_hh)
	b.visible = enabled
	return b

## Hook for Player._animate: mirrors state onto the body and swaps sprite/body.
func sync(p: Player) -> void:
	visible = enabled and p != hide_self
	p.spr.visible = true  # 2D sprite on its own render layer (main 2D view only)
	if not enabled:
		return
	spd = Vector2(p.vel.x, p.vel.z).length()
	var a := "idle"
	if p.mining or p.swing_t > 0.0:
		a = "mine"
	elif not p.on_ground and not p.in_water:
		a = "jump"
	elif Vector2(p.vel.x, p.vel.z).length() > 0.5:
		a = "walk"
	if p.swimming:
		a = "swim"
	if p.crouching and a == "idle":
		a = "crouch"
	play(a)
	set_tool(p.held_tool)
	if Vector2(p.vel.x, p.vel.z).length() > 0.5:
		face(Vector3(p.vel.x, 0, p.vel.z))
