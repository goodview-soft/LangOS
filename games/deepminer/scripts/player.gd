class_name Player extends Node3D
## Miner with custom voxel AABB physics. pos = feet centre.

const HW := 0.3
const HH := 1.7
const SPEED := 5.0
const JUMP := 9.6
const GRAV := 28.0
const COYOTE := 0.1
const JUMP_BUFFER := 0.12
const LANE_TIME := 0.15
const WALK_MULT := 0.5  # global walk speed (all species, miners): you feel each block; running = x1.0
const ACC_T := 0.3      # time to reach full speed
const DEC_T := 0.2       # time to stop when no key is held (short glide, precise at a hole's edge)

# statistiques de l'espece (voir DMSettings.SPECIES)
var hw := HW
var hh := HH
var speed := SPEED
var jump_v := JUMP
var max_hp := 100.0
var mine_mult := 1.0
var glow := Color.WHITE  # teinte HDR du sprite (capacités), voir set_glow()
var vis_hh := HH  # hauteur du DESSIN (espèce) ; hh = hitbox (les IA gardent la hitbox humaine)
var fall_safe_t := 0.0  # > 0 : pas de dégâts de chute (sortie de la salle de spawn)
var load_mult := 1.0  # ralentissement dû à la charge du sac (Carry.speed_mult)
var mine_boost := 1.0  # capacités temporaires (Surchauffe)
var speed_boost := 1.0  # capacités temporaires (Charge)
var forced_dir := Vector3.ZERO  # direction imposée un court instant (Charge : toujours devant le personnage)
var forced_t := 0.0
var sword := 0  # niveau d'épée (0 = aucune) : portée, dégâts (via dmg_mult) et cadence
var big_jump := false  # géant : Espace maintenu = gros saut vers le haut
var hold_t := 0.0
var reach := 5.5
var lamp_range := 10.0
var lava_mult := 1.0
var torch_craft := 4
var sinks := false

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var on_ground := false
var step_off := 0.0  # visual lag after an automatic 1-block step-up
var in_water := false
var swimming := false  # assez d'eau pour flotter (>= 55 % de la taille du corps) ; sinon on patauge
var splash_flag := false  # entrée / sortie de l'eau : main lance une éclaboussure
var _was_swimming := false
var running := false  # Shift held: back to the full speed
var dive := false  # S / Ctrl in water: swim down instead of floating up
var is_main := false  # the human player (sprite pushed to the shown cut plane)
## --- VIEW --- 2D cut: sprites are pushed toward the camera, to the front plane of their layer (the main player:
## the shown cut plane), so blocks of their own layer or above never clip them. cut_n = ZERO: no push.
static var cut_n := Vector3.ZERO
static var cut_d := 0.0
var in_lava := false
var health := 100.0
var mining := false
var facing := 1
var spr: AnimatedSprite3D
var vbody: VoxelBody  # --- VIEW ---
var pal := {}  # sprite colours (see Tex.build_player_frames)
var coyote_t := 0.0
var buffer_t := 0.0
var jump_was := false
# layer ("lane") locking along the view depth axis: -1 = free (top view)
var lane_axis := -1
var lane_from := 0.0
var lane_to := 0.0
var lane_t := 1.0
# crouch + combat (shared by the player and the AI miners)
const MAX_HP := 100.0
const DMG := 12.0  # pickaxe hit
const MELEE := 2.5
const HIT_CD := 0.6
const WALL_DMG := 32.0  # impact d'un lancer contre un mur
var crouching := false
var wave_t := 0.0  # salut (double saut / double accroupissement)
var _last_jump := -9.0
var _last_crouch := -9.0
var _crouch_was := false
var held_tool := "pick"
var _last_jump_air := false
var flash_t := 0.0
var combat_t := 0.0  # > 0: health bar shown above the head
var atk_cd := 0.0
# --- SAISIE DU GÉANT : le géant attrape un petit (held_by), le tient, puis le lance contre un mur (thrown_t > 0 : vol libre)
var grab_cd := 0.0  # recharge du géant avant une nouvelle saisie
var holding: Player = null  # (géant) la victime qu'il tient
var held_by: Player = null  # (victime) le géant qui la tient
var thrown_t := 0.0  # > 0 : projeté, pas de contrôle horizontal
var thrown_v := 0.0  # vitesse horizontale de lancement (détecte l'impact : vitesse qui s'effondre)
var thrown_age := 0.0
var wall_hit := false  # impact contre un mur ce tick (lu par main pour le son/les débris)
# --- ESCALADE : les petits personnages (espèces « climb ») s'agrippent à un mur, même plus haut que 3 blocs
const CLIMB_MAX := 5.0  # secondes d'accroche, rechargées au sol
const CLIMB_SPEED := 3.2
var can_climb := false
var climb_t := CLIMB_MAX
var climbing := false
var _climb_dir := Vector3.ZERO
# --- ÉQUIPEMENT PvP (Gear) : renseigné par main.apply_gear() pour le joueur ; neutre pour les mineurs IA
var armor := 0.0  # réduction des dégâts reçus (0..0,35)
var dmg_mult := 1.0  # bonus de dégâts de la pioche (Tranchant)
var kb_idx := 0  # niveau de recul de la pioche (Recul)
var thorns := 0  # épines : renvoie des dégâts à l'attaquant
var absorb := 0.0  # absorption (pomme dorée) : PV en plus, consommés d'abord
var regen_t := 0.0  # régénération restante (s)
var tag_t := 0.0  # « en combat » : > 0 = pas de refuge en zone sûre, pas de changement d'espèce
var apple_t := 0.0  # pomme en cours de consommation (annulée par un coup)
var apple_cd := 0.0
var iframes := {}  # attaquant -> fin de l'invulnérabilité vis-à-vis de lui (s, horloge locale)
var _clock := 0.0
var swing_t := 0.0
var hpbar: Sprite3D
var _bar_hp := -1.0

func _ready() -> void:
	spr = AnimatedSprite3D.new()
	apply_species()
	health = max_hp if is_equal_approx(health, 100.0) else minf(health, max_hp)  # 100 = plein (sauvegarde d'IA : on garde les PV chargés)
	_apply_frames()
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.shaded = true
	spr.transparent = false  # discard seul : un quad blendé peut s'afficher en rectangle noir
	add_child(spr)
	spr.play("idle")
	hpbar = Sprite3D.new()
	hpbar.pixel_size = 1.0 / 10.0
	hpbar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hpbar.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hpbar.no_depth_test = true
	hpbar.render_priority = 4
	hpbar.position = Vector3(0, vis_hh + 0.5, 0)
	hpbar.visible = false
	add_child(hpbar)
	vbody = VoxelBody.attach(self)  # --- VIEW --- cube body (replaces spr in iso/FPS)

## Pickaxe hit: damage, knockback away from `from`, red flash, health bar.
func hurt(amount: float, from: Vector3, kb_mult := 1.0, att_id := "") -> bool:
	if att_id != "":
		if float(iframes.get(att_id, -1.0)) > _clock:
			return false  # encore invulnérable vis-à-vis de cet attaquant (0,25 s)
		iframes[att_id] = _clock + Gear.HIT_IFRAMES
	amount *= 1.0 - armor
	if absorb > 0.0:
		var a := minf(absorb, amount)
		absorb -= a
		amount -= a
	health = maxf(health - amount, 0.0)
	if apple_t > 0.0:
		apple_t = 0.0  # un coup reçu annule la pomme
	tag_t = Gear.TAG_TIME
	var d := pos - from
	d.y = 0.0
	d = d.normalized() if d.length() > 0.01 else Vector3(facing, 0, 0)
	if lane_axis >= 0:
		d[lane_axis] = 0.0
	vel += (d * 7.0 + Vector3(0, 5.0, 0)) * (0.8 * kb_mult)
	flash_t = 0.25
	combat_t = 6.0
	return true

func _update_bar() -> void:
	hpbar.visible = combat_t > 0.0 and visible
	if not hpbar.visible or is_equal_approx(_bar_hp, health):
		return
	_bar_hp = health
	var img := Image.create(18, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.03, 0.05))
	var n := int(round(16.0 * clampf(health / max_hp, 0.0, 1.0)))
	var col := Color(0.35, 0.9, 0.3) if health > 50.0 else (Color(1.0, 0.8, 0.2) if health > 25.0 else Color(1.0, 0.25, 0.2))
	for x in n:
		img.set_pixel(1 + x, 1, col)
	hpbar.texture = ImageTexture.create_from_image(img)

func refresh_look() -> void:
	var anim := spr.animation
	_apply_frames()
	spr.play(anim)
	if vbody and pal.is_empty():  # corps en cubes (vues 3/4 et FPS) : même espèce et mêmes couleurs
		vbody.build(DMSettings.look, int(DMSettings.look.get("body", 0)))
	if vbody:
		vbody.fit(vis_hh)

func _look() -> Dictionary:
	return pal if not pal.is_empty() else DMSettings.look

func apply_species() -> void:
	var s: Dictionary = DMSettings.SPECIES[clampi(int(pal.get("body", 0)), 0, DMSettings.SPECIES.size() - 1)] if not pal.is_empty() else DMSettings.species()
	vis_hh = s.hh
	hh = s.hh; hw = s.hw; speed = s.speed; jump_v = s.jump; max_hp = s.hp; mine_mult = s.mine
	big_jump = bool(s.get("bigjump", false))
	can_climb = bool(s.get("climb", false)) and pal.is_empty()  # pas pour les IA (leur chemin ne le prévoit pas)
	if pal.is_empty() and s.has("chh"):  # joueur : capsule de collision réduite (passages d'un demi-bloc des mini-blocs)
		hh = s.chh
		hw = s.chw
	reach = s.reach; lamp_range = s.lamp; lava_mult = s.lava; torch_craft = s.torch; sinks = s.sinks
	if not pal.is_empty():  # IA : largeur humaine (couloirs de 1 bloc) et pas de noyade au fond de l'eau
		hw = minf(hw, HW)
		sinks = false
	health = minf(health, max_hp)

func _apply_frames() -> void:
	spr.pixel_size = Tex.pixel_size(_look(), vis_hh)
	spr.sprite_frames = Tex.build_player_frames(_look(), held_tool)
	spr.offset = Vector2(0, spr.sprite_frames.get_frame_texture("idle", 0).get_height() / 2.0)

## Lueur d'une capacité : teinte HDR du sprite + émission du corps en cubes. amt = 0 : éteint.
func set_glow(tint: Color, amt: float) -> void:
	glow = Color.WHITE.lerp(Color(tint.r * 2.6, tint.g * 2.6, tint.b * 2.6), clampf(amt, 0.0, 1.0))
	if vbody:
		vbody.set_glow(tint, amt)

## Hauteur du corps en blocs entiers (humain 2, nain 1, géant 3) : sert au pathfinder des IA.
func body_cells() -> int:
	return maxi(1, ceili(hh - 0.01))

func feet_cell() -> Vector3i:
	return Vector3i(floori(pos.x), floori(pos.y + 0.05), floori(pos.z))

func center() -> Vector3:
	return pos + Vector3(0, hh * 0.53, 0)

## --- VIEW --- the layer lock is gone: movement is always free in 3D, views never move the player.
## Kept as a no-op for old callers (commands, loading, respawn).
func set_lane_axis(_a: int) -> void:
	lane_axis = -1
	lane_t = 1.0

func lane_layer() -> int:
	return floori(lane_to) if lane_t < 1.0 else floori(pos[lane_axis])

## Is the neighbouring layer free (dir = +1/-1 along lane_axis)? Returns the target feet position or null.
func lane_target(dir: int, w: World) -> Variant:
	if lane_axis < 0:
		return null
	var t := pos
	t[lane_axis] = floorf(pos[lane_axis]) + dir + 0.5
	if not w.box_hits(t, hw, hh):
		return t
	var up := t + Vector3(0, 1.02, 0)
	if on_ground and not w.box_hits(up, hw, hh) and not w.box_hits(pos + Vector3(0, 1.02, 0), hw, hh):
		return up
	return null

func try_lane(dir: int, w: World) -> bool:
	if lane_t >= 1.0:  # Only start new lane if current one is complete
		var t: Variant = lane_target(dir, w)
		if t == null:
			return false
		pos.y = (t as Vector3).y
		lane_from = pos[lane_axis]
		lane_to = (t as Vector3)[lane_axis]
		lane_t = 0.0
		return true
	return false

func _lane(dt: float, w: World) -> void:
	if lane_axis < 0 or lane_t >= 1.0:
		return
	lane_t = minf(lane_t + dt / LANE_TIME, 1.0)
	var np := pos
	np[lane_axis] = lerpf(lane_from, lane_to, smoothstep(0.0, 1.0, lane_t))
	if not w.box_hits(np, hw, hh):
		pos = np
	else:  # blocked mid-way (block placed, fall...): go back to the starting layer
		lane_t = 1.0  # Immediately stop and go back to start
		lane_from = pos[lane_axis]
		lane_to = floorf(pos[lane_axis]) + 0.5  # Start from current position back to nearest layer

## Assisted jump: the ledge right ahead in the wish direction (1..max_h blocks high, free headroom) -> the vertical
## speed that just clears it. 0 = no ledge ahead.
func _ledge_boost(wish: Vector3, w: World, max_h: float) -> float:
	var dn := Vector3(wish.x, 0.0, wish.z)
	if dn.length() < 0.1:
		return 0.0
	dn = dn.normalized()
	var y0 := floori(pos.y + 0.05)
	for dist in [0.5, 0.9, 1.3]:
		var p: Vector3 = pos + dn * dist
		var cx := floori(p.x)
		var cz := floori(p.z)
		if World.KIND[w.get_v(Vector3i(cx, y0, cz))] != World.K_CUBE:
			continue
		var h := 0
		while h <= ceili(max_h) and World.KIND[w.get_v(Vector3i(cx, y0 + h, cz))] == World.K_CUBE:
			h += 1
		if h > max_h:
			return 0.0
		for k in ceili(hh):
			if World.KIND[w.get_v(Vector3i(cx, y0 + h + k, cz))] == World.K_CUBE:
				return 0.0
		return sqrt(2.0 * GRAV * (float(h) + 0.45))
	return 0.0

func step(dt: float, wish: Vector3, jump: bool, w: World) -> void:
	if forced_t > 0.0:
		forced_t -= dt
		wish = forced_dir
	var mid := Vector3i(floori(pos.x), floori(pos.y + minf(0.8, hh * 0.5)), floori(pos.z))
	var wtop := _water_top(w)  # hauteur réelle de l'eau (niveau/8) ; sous 2/8 on marche dededans
	in_water = wtop - pos.y >= 0.25 and (w.get_v(mid) == World.WATER or wtop - pos.y >= minf(0.8, hh * 0.5))
	in_lava = w.get_v(mid) == World.LAVA or w.get_v(Vector3i(mid.x, floori(pos.y + 0.1), mid.z)) == World.LAVA
	var wd := 0.0  # profondeur d'eau au-dessus des pieds : distingue patauger (géant dans 1 bloc) et nager
	if in_water:
		wd = wtop - pos.y
	swimming = in_water and wd >= hh * 0.55
	if swimming != _was_swimming:
		_was_swimming = swimming
		splash_flag = true
	var spd := speed * (1.0 if running else WALK_MULT) * speed_boost * (0.6 if swimming or in_lava else (0.85 if in_water else 1.0)) * (0.35 if crouching else 1.0) * load_mult
	flash_t -= dt
	combat_t -= dt
	atk_cd -= dt
	grab_cd -= dt
	swing_t -= dt
	_clock += dt
	tag_t -= dt
	apple_cd -= dt
	if regen_t > 0.0:
		regen_t -= dt
		health = minf(health + Gear.APPLE_REGEN * dt, max_hp)
	var tgt := Vector3.ZERO
	if wish.length() > 0.1:
		tgt = wish.normalized() * spd
	# perceptible acceleration / deceleration (stronger braking when no key is held)
	var vmax := maxf(spd, 1.0)
	var acc := vmax / (ACC_T if tgt != Vector3.ZERO else DEC_T)
	if not on_ground:
		acc *= 0.6
	if thrown_t <= 0.0:  # projeté : la vitesse horizontale n'est pas freinée
		var hv := Vector2(vel.x, vel.z).move_toward(Vector2(tgt.x, tgt.z), acc * dt)
		vel.x = hv.x
		vel.z = hv.y
	if lane_axis >= 0:
		vel[lane_axis] = 0.0
	_lane(dt, w)
	# coyote time + jump buffer + variable height (release = shorter jump)
	if on_ground:
		coyote_t = COYOTE  # Reset coyote time when grounded
	else:
		coyote_t = maxf(0.0, coyote_t - dt)  # Decrease when airborne
	buffer_t = JUMP_BUFFER if jump and not jump_was else buffer_t - dt
	if in_water and sinks:  # le robot coule et marche au fond
		vel.y = maxf(vel.y - GRAV * 0.6 * dt, -5.0)
		if jump and on_ground:
			vel.y = 5.0
	elif swimming:  # buoyancy: rise gently to the surface and float, head out of the water
		if jump:
			vel.y = maxf(4.0, _ledge_boost(wish, w, 3.0))
		elif dive:
			vel.y = move_toward(vel.y, -2.6, 14.0 * dt)
		else:
			var target_y := water_surface(w) - hh * 0.72
			var err := target_y - pos.y
			var clamped_err := clampf(err * 3.0, -2.0, 2.2)
			vel.y = move_toward(vel.y, clamped_err, 9.0 * dt)
	elif _try_climb(wish, jump, dt, w):
		pass
	elif in_lava:
		vel.y = maxf(vel.y - GRAV * 0.3 * dt, -3.0)
		if jump:
			vel.y = 4.0
	else:
		vel.y -= GRAV * dt
		if in_water and jump:  # climbing out: at the surface, holding jump keeps the full jump impulse (ledge 1 block above the water)
			vel.y = maxf(vel.y, maxf(jump_v, _ledge_boost(wish, w, 3.0)))
		elif buffer_t > 0.0 and coyote_t > 0.0:
			vel.y = maxf(jump_v, _ledge_boost(wish, w, 2.0))
			buffer_t = 0.0
			coyote_t = 0.0
		elif not jump and jump_was and vel.y > 0.0:
			vel.y *= 0.45
		if big_jump and jump and vel.y > 2.0 and hold_t < 0.35:  # géant : Espace maintenu = poussée qui prolonge le saut (gros saut)
			vel.y += GRAV * 0.75 * dt
			hold_t += dt
	jump_was = jump
	vel.y = maxf(vel.y, -40.0)
	var vy0 := vel.y
	var grounded := on_ground
	on_ground = false
	if grounded:
		hold_t = 0.0
	var steps := maxi(1, ceili(vel.length() * dt / 0.3))
	var d := vel * dt / steps
	for s in steps:
		_move(0, d.x, w, grounded)
		_move(2, d.z, w, grounded)
		_move(1, d.y, w, grounded)
	if thrown_t > 0.0:
		thrown_age += dt
		thrown_t -= dt
		if thrown_age > 0.08 and Vector2(vel.x, vel.z).length() < thrown_v * 0.5:  # la vitesse s'est effondrée : mur
			wall_hit = true
			thrown_t = 0.0
			health = maxf(health - WALL_DMG, 0.0)
			flash_t = 0.3
			combat_t = 6.0
		elif on_ground and thrown_age > 0.15:  # retombé au sol sans mur
			thrown_t = 0.0
	fall_safe_t -= dt
	if on_ground and vy0 < -17.0 and fall_safe_t <= 0.0:
		health -= (-vy0 - 17.0) * 5.0
	if in_lava:
		health -= 30.0 * lava_mult * dt
	step_off = move_toward(step_off, 0.0, dt * 7.0)
	position = pos - Vector3(0, step_off, 0)
	_animate()

## Accroche au mur : en l'air, contre un mur dans la direction voulue, Espace = monte, sinon reste accroché.
## Au sommet (le mur finit), Espace donne un petit saut par-dessus le rebord. Endurance limitée (CLIMB_MAX), rechargée au sol.
func _try_climb(wish: Vector3, jump: bool, dt: float, w: World) -> bool:
	if not can_climb:
		return false
	if on_ground:
		climb_t = CLIMB_MAX
		climbing = false
		return false
	if (buffer_t > 0.0 and coyote_t > 0.0) or (not climbing and vel.y > 1.0):
		return false  # un saut normal passe d'abord ; on s'accroche en retombant
	var dirn := Vector3(wish.x, 0, wish.z)
	var wall := false
	if dirn.length() > 0.1:
		dirn = dirn.normalized()
		_climb_dir = dirn
		wall = w.box_hits(pos + dirn * 0.25, hw, hh)
	if climbing and not wall and jump and _climb_dir != Vector3.ZERO:  # rebord atteint : on se hisse
		climbing = false
		vel.y = 6.5
		vel.x = _climb_dir.x * 3.0
		vel.z = _climb_dir.z * 3.0
		return false
	if not wall or climb_t <= 0.0:
		climbing = false
		return false
	climbing = true
	climb_t -= dt
	vel.y = CLIMB_SPEED if jump else 0.0
	return true

## Height of the water surface above the body (top of the water column at the player's x/z).
func water_surface(w: World) -> float:
	var t := _water_top(w)
	return t if t > -1000.0 else float(floori(pos.y + minf(0.8, hh * 0.5)) + 1)

## Haut de la colonne d'eau (niveau réel) au x/z du joueur, à partir des pieds ; -1000 s'il n'y en a pas.
func _water_top(w: World) -> float:
	var x := floori(pos.x)
	var z := floori(pos.z)
	var y := floori(pos.y + 0.05)
	if w.get_b(x, y, z) != World.WATER:
		y = floori(pos.y + minf(0.8, hh * 0.5))
		if w.get_b(x, y, z) != World.WATER:
			return -1000.0
	var n := 0
	while n < 12 and w.get_b(x, y + 1, z) == World.WATER:
		y += 1
		n += 1
	return float(y) + w.water_h(x, y, z)

func _move(i: int, d: float, w: World, grounded: bool) -> void:
	if d == 0.0:
		return
	var np := pos
	np[i] += d
	if not w.box_hits(np, hw, hh):
		pos = np
		return
	var fine := w.partial_near(np, hw, hh)  # blocs entamés (mini-blocs) : marches de 1/2 bloc, collision précise
	# auto step-up of one block (Terraria-like) ; 1/2 bloc d'abord s'il y a des mini-blocs
	if i != 1 and grounded:
		for h in ([0.52, 1.02] if fine else [1.02]):
			var up := np + Vector3(0, h, 0)
			if not w.box_hits(up, hw, hh) and not w.box_hits(pos + Vector3(0, h, 0), hw, hh):
				pos = up
				step_off = minf(step_off + h, 1.3)  # the body is shown lower and rises smoothly (no pop)
				return
	if fine:  # collé contre le morceau par recherche dichotomique (les bords ne sont plus sur la grille)
		var lo := 0.0
		var hi := d
		for k in 9:
			var mid := (lo + hi) * 0.5
			var t := pos
			t[i] += mid
			if w.box_hits(t, hw, hh):
				hi = mid
			else:
				lo = mid
		pos[i] += lo
		if i == 1 and d < 0.0:
			on_ground = true
		vel[i] = 0.0
		return
	# snap against the obstacle
	var sp := pos
	if i == 1:
		if d < 0.0:  # landing: rest on top of the block below
			sp.y = floorf(np.y) + 1.0 + 0.001
			if not w.box_hits(sp, hw, hh):
				on_ground = true
		else:  # head against a ceiling
			sp.y = floorf(np.y + hh) - hh - 0.001
	else:
		if d > 0.0:
			sp[i] = floorf(np[i] + hw) - hw - 0.001
		else:
			sp[i] = floorf(np[i] - hw) + 1.0 + hw + 0.001
	if (d < 0.0 and sp[i] <= pos[i] + 0.0001) or (d > 0.0 and sp[i] >= pos[i] - 0.0001):
		if not w.box_hits(sp, hw, hh):
			pos = sp
	vel[i] = 0.0

## Direction d'affichage : "" = profil, "_front" = face, "_back" = dos.
## aim_dx : ecart de la souris au joueur sur l'ecran (px), NAN = inconnu.
var aim_dx := NAN
var has_aim := false  # a block is targeted: the miner turns toward it
var aim_vec := Vector3.ZERO  # target centre - player centre (world)
const FRONT_ZONE := 40.0

func pick_dir(sd: float, df: float, moving: bool) -> String:
	if moving:
		if absf(sd) >= absf(df) * 0.8:
			return ""
		return "_back" if df > 0.0 else "_front"
	if is_main and has_aim:  # look at the targeted block: behind = back, toward the camera = front, else profile
		var cam := get_viewport().get_camera_3d()
		if cam:
			var sr := cam.basis.x
			sr.y = 0.0
			var sf := -cam.basis.z
			sf.y = 0.0
			var asd := aim_vec.dot(sr.normalized())
			var adf := aim_vec.dot(sf.normalized())
			if absf(adf) > absf(asd) * 1.2 and absf(adf) > 0.4:
				return "_back" if adf > 0.0 else "_front"
			facing = 1 if asd > 0.0 else -1
			return ""
	if is_main and not is_nan(aim_dx):
		if absf(aim_dx) < FRONT_ZONE:
			return "_front"
		facing = 1 if aim_dx > 0.0 else -1
		return ""
	return ""

## Outil tenu ("pick" ou "torch") : reconstruit les images si besoin.
func moving_cancel_wave() -> bool:
	return Vector2(vel.x, vel.z).length() > 0.5 or mining

func set_held_tool(id: String) -> void:
	if id == held_tool:
		return
	held_tool = id
	var anim := spr.animation
	_apply_frames()
	spr.play(anim)

func _animate() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not on_ground and vel.y > 0.0 and _last_jump_air == false:
		if now - _last_jump < 0.45:
			wave_t = 1.6
		_last_jump = now
	_last_jump_air = not on_ground and vel.y > 0.0
	if crouching and not _crouch_was:
		if now - _last_crouch < 0.45:
			wave_t = 1.6
		_last_crouch = now
	_crouch_was = crouching
	wave_t = maxf(0.0, wave_t - get_process_delta_time())
	if moving_cancel_wave():
		wave_t = 0.0
	var a := "idle"
	var moving := Vector2(vel.x, vel.z).length() > 0.5
	if flash_t > 0.0:
		a = "hurt"
	elif mining or swing_t > 0.0:
		a = "mine"
	elif in_water:
		a = "swim"
	elif not on_ground:
		a = "jump" if vel.y > 0.0 else "fall"
	elif crouching:
		a = "crouch"
	elif wave_t > 0.0:
		a = "wave"
	elif moving:
		a = "run" if running else "walk"
	if a in ["idle", "walk", "crouch", "wave"]:
		var cam := get_viewport().get_camera_3d()
		var sd := 0.0
		var df := 0.0
		if cam:
			var sr := cam.basis.x
			sr.y = 0.0
			var sf := -cam.basis.z
			sf.y = 0.0
			sd = vel.dot(sr.normalized()) if sr.length() > 0.01 else vel.x
			df = vel.dot(sf.normalized()) if sf.length() > 0.01 else -vel.z
		else:
			sd = vel.x
			df = -vel.z
		var d := pick_dir(sd, df, a == "walk" or (a == "crouch" and moving))
		if d != "" and spr.sprite_frames.has_animation(a + d):
			a += d
	if spr.animation != a:
		spr.play(a)
	spr.flip_h = facing < 0
	if cut_n != Vector3.ZERO:
		var d := center().dot(cut_n)
		var tgt := (cut_d if is_main else floorf(d + 0.001)) - 0.06
		spr.position = cut_n * minf(tgt - d, 0.0)
	else:
		spr.position = Vector3.ZERO
	# walk cycle synced with the real speed; 1 px bob on every step (you feel the blocks)
	var hs := Vector2(vel.x, vel.z).length()
	spr.speed_scale = clampf(hs / (SPEED * WALK_MULT), 0.35, 1.8) if a == "walk" else 1.0
	var bob := 1.0 if a == "walk" and on_ground and spr.frame % 2 == 1 else 0.0
	spr.offset.y = 14.0 + bob  # crouched: sprite a bit lower
	if swimming:  # on flotte : le corps s'enfonce dans l'eau et ondule doucement
		spr.offset.y -= 3.0 + sin(Time.get_ticks_msec() * 0.005) * 1.2
	var a0 := spr.modulate.a
	spr.modulate = Color(1.0, 0.3, 0.3, a0) if flash_t > 0.0 else Color(glow.r, glow.g, glow.b, a0)
	_update_bar()
	if vbody:
		vbody.set_hit(flash_t > 0.0)  # filtre rouge sur le corps touché
	if vbody: vbody.sync(self)  # --- VIEW ---
