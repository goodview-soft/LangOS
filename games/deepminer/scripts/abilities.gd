class_name Abilities extends Node
## Capacité spéciale de l'espèce (touche G) : temps de recharge, effet et retour visuel
## (halo, éclat du sprite, onde de choc, traînée, étincelles, tremblement). Voir DMSettings.ABILITIES.

const COLORS := {
	"heal": Color(0.4, 1.0, 0.5),
	"quake": Color(1.0, 0.55, 0.15),
	"charge": Color(1.0, 0.75, 0.35),
	"sniff": Color(0.4, 1.0, 0.7),
	"overheat": Color(1.0, 0.3, 0.08),
}
const FX_TIME := {"heal": 3.0, "quake": 0.7, "charge": 0.7, "sniff": 2.5, "overheat": 6.0}

var main: Node3D
var kind := ""
var cd_max := 20.0
var cd := 0.0  # temps de recharge restant
var active_t := 0.0  # temps restant de l'effet en cours
var fx_t := 0.0  # temps restant du halo / éclat sur le personnage
var fx_dur := 1.0
var t := 0.0
var rings: Array = []  # [MeshInstance3D, ShaderMaterial, temps, durée]
var aura: MeshInstance3D
var aura_mat: ShaderMaterial
var sniff_mm: MultiMeshInstance3D
var sniff_mat: ShaderMaterial
var sniff_total := 8.0
var sniff_labels: Array = []  # [Label3D, cellule, distance à l'origine de l'onde]
var sniff_origin := Vector3.ZERO
var label_t := 0.0
var ghost_t := 0.0
var spark_t := 0.0

func setup(m: Node3D) -> void:
	main = m
	aura_mat = ShaderMaterial.new()
	aura_mat.shader = load("res://games/deepminer/shaders/aura.gdshader")
	aura = _quad(aura_mat, 3.0)
	aura.visible = false
	main.player.add_child(aura)
	refresh()

## À rappeler quand l'espèce change : annule les effets en cours.
func refresh() -> void:
	_stop_all()
	var a: Dictionary = DMSettings.ability()
	kind = a.id
	cd_max = a.cd
	cd = 0.0
	var p: Player = main.player
	aura.position = Vector3(0, p.hh * 0.5, 0)
	(aura.mesh as QuadMesh).size = Vector2.ONE * clampf(p.hh * 1.5 + 1.0, 2.6, 5.5)

func ready_ratio() -> float:
	return 1.0 - cd / cd_max if cd_max > 0.0 else 1.0

func is_charging() -> bool:
	return kind == "charge" and active_t > 0.0

func _quad(mat: ShaderMaterial, size: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func trigger() -> void:
	if cd > 0.0:
		main.hud.toast("%s : prêt dans %d s" % [DMSettings.ability().name, ceili(cd)])
		return
	var ok := true
	match kind:
		"heal":
			if main.player.health >= main.player.max_hp - 1.0:
				main.hud.toast("Second souffle : déjà en pleine forme")
				ok = false
			else:
				active_t = 3.0
				_ring(main.player.center(), 2.5, 0.6)
				main.hud.toast("Second souffle !")
		"quake": ok = _quake()
		"charge":
			active_t = 0.6
			main.shake = maxf(main.shake, 0.5)
			_ring(main.player.center(), 2.5, 0.35)
			main.hud.toast("Charge !")
		"sniff": _sniff()
		"overheat":
			active_t = 6.0
			_ring(main.player.center(), 3.0, 0.5)
			main.hud.toast("Surchauffe ! Minage x2, mais ça brûle…")
	if ok:
		cd = cd_max
		fx_dur = FX_TIME[kind]
		fx_t = fx_dur

func update(dt: float) -> void:
	t += dt
	if cd > 0.0:
		cd = maxf(cd - dt, 0.0)
	main.shake = maxf(main.shake - dt * 2.5, 0.0)
	var p: Player = main.player
	if active_t > 0.0:
		active_t -= dt
		match kind:
			"heal":
				p.health = minf(p.health + 50.0 / 3.0 * dt, p.max_hp)
				p.speed_boost = 1.3
				spark_t -= dt
				if spark_t <= 0.0 and main.chip_pool.size() > 0:
					spark_t = 0.2
					main.chip_burst(Vector3i(p.center().floor()), World.MUSHROOM, 0.3)
			"charge":
				_charge_step(dt)
			"overheat":
				p.mine_boost = 2.0
				p.health = maxf(p.health - 4.0 * dt, 5.0)  # chauffe sans jamais tuer
				spark_t -= dt
				if p.mining and spark_t <= 0.0 and main.chip_pool.size() > 0:
					spark_t = 0.12
					main.chip_burst(Vector3i(p.center().floor()), World.LAVA, 0.3)
			"sniff":
				_sniff_step(dt)
		if active_t <= 0.0:
			_end_effect()
	_update_glow(dt)
	_update_rings(dt)

# ---------------------------------------------------------------- retour visuel
## Halo + sprite qui rayonne (HDR : le bloom du jeu s'en charge) tant que fx_t > 0.
func _update_glow(dt: float) -> void:
	var p: Player = main.player
	if fx_t <= 0.0:
		if aura.visible:
			aura.visible = false
			p.set_glow(Color.WHITE, 0.0)
		return
	fx_t -= dt
	var col: Color = COLORS[kind]
	var s := clampf(fx_t / 0.5, 0.0, 1.0)  # fondu de fin
	var pulse := 0.75 + 0.25 * sin(t * 14.0)
	aura.visible = true
	aura_mat.set_shader_parameter("color", col)
	aura_mat.set_shader_parameter("strength", s * (1.0 if kind != "sniff" else 0.7))
	aura_mat.set_shader_parameter("t", t)
	p.set_glow(col, s * pulse * 0.85)

func _ring(at: Vector3, radius: float, dur: float, col := Color(-1, 0, 0)) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://games/deepminer/shaders/ring.gdshader")
	mat.set_shader_parameter("color", COLORS[kind] if col.r < 0.0 else col)
	mat.set_shader_parameter("res", radius * 2.0 * 16.0)
	var mi := _quad(mat, radius * 2.0)
	main.add_child(mi)
	mi.global_position = at
	rings.append([mi, mat, 0.0, dur])

func _update_rings(dt: float) -> void:
	for r in rings.duplicate():
		r[2] += dt
		var pr: float = r[2] / r[3]
		(r[1] as ShaderMaterial).set_shader_parameter("prog", minf(pr, 1.0))
		if pr >= 1.0:
			(r[0] as Node).queue_free()
			rings.erase(r)

## Image fantôme du mineur qui s'efface (traînée de la charge).
func _ghost() -> void:
	var p: Player = main.player
	var tex: Texture2D = p.spr.sprite_frames.get_frame_texture(p.spr.animation, p.spr.frame)
	var g := Sprite3D.new()
	g.texture = tex
	g.pixel_size = p.spr.pixel_size
	g.offset = p.spr.offset
	g.flip_h = p.spr.flip_h
	g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	g.shaded = false
	g.transparent = true
	g.modulate = Color(2.0, 1.4, 0.6, 0.55)
	main.add_child(g)
	g.global_position = p.global_position
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.3)
	tw.tween_callback(g.queue_free)

# ---------------------------------------------------------------- effets
func _end_effect() -> void:
	var p: Player = main.player
	p.mine_boost = 1.0
	p.speed_boost = 1.0
	if sniff_mm:
		sniff_mm.queue_free()  # libère aussi les étiquettes (enfants)
		sniff_mm = null
	sniff_labels.clear()

func _stop_all() -> void:
	active_t = 0.0
	fx_t = 0.0
	if main:
		_end_effect()
		main.player.set_glow(Color.WHITE, 0.0)
	for r in rings:
		(r[0] as Node).queue_free()
	rings.clear()
	if aura:
		aura.visible = false

## 3x3 dans le plan de la vue, centré sur le mineur. Récupère les blocs cassés.
func _quake() -> bool:
	var base := Vector3i(main.player.center().floor())
	var r := Vector3i(main.right.round())
	var u := Vector3i(main.up_s.round())
	var got := {}
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var c: Vector3i = base + r * dx + u * dy
			if not main.world.in_bounds(c):
				continue
			var d: int = main.edit_break(c, true)
			if d >= 0:
				main.inv[d] = main.inv.get(d, 0) + 1
				got[d] = got.get(d, 0) + 1
	if got.is_empty():
		main.hud.toast("Frappe sismique : rien à briser ici")
		return false
	main.shake = 1.0
	_ring(main.player.center(), 4.5, 0.55)
	_ring(main.player.pos + Vector3(0, 0.1, 0), 3.0, 0.4, Color(1.0, 0.85, 0.5))
	var parts := []
	for d in got:
		parts.append("%d %s" % [got[d], World.NAMES[d]])
	main.hud.toast("Frappe sismique ! " + ", ".join(parts))
	return true

## Devant le personnage : son orientation réelle (corps 3D), sinon le côté regardé en vue 2D.
func _charge_dir() -> Vector3:
	var p: Player = main.player
	if p.vbody and main.view and main.view.off_cut():
		var r: float = p.vbody.rotation.y
		return Vector3(sin(r), 0.0, cos(r))
	return main.right * float(p.facing)

func _charge_step(dt: float) -> void:
	var p: Player = main.player
	p.speed_boost = 3.0
	var cdir := _charge_dir()
	p.forced_dir = cdir
	p.forced_t = 0.1
	if p.vbody:
		p.vbody.face(cdir)
	ghost_t -= dt
	if ghost_t <= 0.0:
		ghost_t = 0.04
		_ghost()
	var front: Vector3 = p.pos + cdir * (p.hw + 0.35)
	for k in ceili(p.hh):
		var c := Vector3i(floori(front.x), floori(p.pos.y + 0.05 + k), floori(front.z))
		if main.world.in_bounds(c):
			var d: int = main.edit_break(c, true)
			if d >= 0:
				main.inv[d] = main.inv.get(d, 0) + 1
				main.shake = maxf(main.shake, 0.3)

func _sniff() -> void:
	active_t = sniff_total
	var p := Vector3i(main.player.center().floor())
	var cells := []
	var counts := {}
	for x in range(-14, 15):
		for y in range(-12, 13):
			for z in range(-14, 15):
				var c := p + Vector3i(x, y, z)
				if not main.world.in_bounds(c):
					continue
				var id: int = main.world.get_v(c)
				if id == World.COAL or id == World.IRON or id == World.COPPER or id == World.CRYSTAL:
					cells.append([c, id])
					counts[id] = counts.get(id, 0) + 1
	_ring(main.player.center(), 13.0, 1.0)
	var place := _sniff_place()
	if cells.is_empty():
		main.hud.toast("Flair : aucun minerai à proximité" + ("  ·  " + place if place != "" else ""))
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 1.5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = cells.size()
	for i in cells.size():
		var id: int = cells[i][1]
		var tile: int = World.TILE[id]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(cells[i][0]) + Vector3(0.5, 0.5, 0.5)))
		mm.set_instance_color(i, (World.MAPCOL[id] as Color).lightened(0.2))
		mm.set_instance_custom_data(i, Color(float(tile % 4), float(tile / 4), 0, 0))
	sniff_mat = ShaderMaterial.new()
	sniff_mat.shader = load("res://games/deepminer/shaders/sniff.gdshader")
	sniff_mat.set_shader_parameter("atlas", main.atlas)
	sniff_mat.set_shader_parameter("tiles", Vector2(4, main.atlas.get_height() / 16.0))
	sniff_mat.set_shader_parameter("origin", main.player.center())
	sniff_mat.render_priority = 5
	sniff_mm = MultiMeshInstance3D.new()
	sniff_mm.multimesh = mm
	sniff_mm.material_override = sniff_mat
	sniff_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sniff_mm.custom_aabb = AABB(Vector3(-50, -50, -50), Vector3(World.SX + 100, World.SY + 100, World.SZ + 100))
	main.add_child(sniff_mm)
	var parts := []
	for id in counts:
		parts.append("%d %s" % [counts[id], World.NAMES[id]])
	# une étiquette par minerai : profondeur (vue 2D) ou distance (3/4, FPS)
	sniff_origin = main.player.center()
	sniff_labels.clear()
	for e in cells:
		var c: Vector3i = e[0]
		var lb := Label3D.new()
		lb.pixel_size = 1.0 / 16.0
		lb.font = UiTheme.font()
		lb.font_size = 10
		lb.outline_size = 3
		lb.outline_modulate = Color(0.05, 0.04, 0.08)
		lb.modulate = (World.MAPCOL[e[1]] as Color).lightened(0.5)
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		lb.no_depth_test = true
		lb.render_priority = 6
		lb.outline_render_priority = 5
		lb.position = Vector3(c) + Vector3(0.5, 1.2, 0.5)
		lb.visible = false
		sniff_mm.add_child(lb)
		sniff_labels.append([lb, c, sniff_origin.distance_to(Vector3(c) + Vector3(0.5, 0.5, 0.5))])
	_sniff_texts()
	var legend := "  |  chiffres : profondeur (couches)" if main.view.mode == ViewCtl.CUT else "  |  étiquettes : distance, niveau Y (comme en haut à gauche) et écart"
	main.hud.toast("Flair : " + "  ·  ".join(parts) + legend + ("\n" + place if place != "" else ""))

## Le flair repère aussi le lieu non découvert le plus proche (lac, jardin, cavité chaude, mine) : direction et distance, et il apparaît sur la carte.
func _sniff_place() -> String:
	var w: World = main.world
	var pc: Vector3 = main.player.center()
	if main.pois_found.size() != w.pois.size():
		main.pois_found.resize(w.pois.size())
		main.pois_found.fill(false)
	var best := -1
	var bd := 70.0
	for i in w.pois.size():
		if main.pois_found[i] or not w.poi_exists(w.pois[i]):
			continue
		var d := pc.distance_to(w.pois[i].pos)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return ""
	var p: Dictionary = w.pois[best]
	main.pois_found[best] = true  # le flair le révèle sur la carte (B)
	var dv: Vector3 = p.pos - pc
	var dir := ""
	if absf(dv.z) > absf(dv.x) * 0.4:
		dir += "sud" if dv.z > 0 else "nord"  # même orientation que la carte : haut = nord
	if absf(dv.x) > absf(dv.z) * 0.4:
		dir += ("-est" if dir != "" else "est") if dv.x > 0 else ("-ouest" if dir != "" else "ouest")
	var name: String = {"lac": "Lac", "jardin": "Jardin de cristaux", "chaud": "Cavité chaude", "mine": "Ancienne mine"}.get(p.kind, "Lieu")
	var vert := ""
	if dv.y <= -3.0:
		vert = ", %d plus bas" % roundi(-dv.y)
	elif dv.y >= 3.0:
		vert = ", %d plus haut" % roundi(dv.y)
	return "%s à %d blocs vers le %s%s (noté sur la carte B)" % [name, roundi(Vector2(dv.x, dv.z).length()), dir, vert]

## Texte de chaque étiquette. Vue 2D : couches de profondeur (+2 = 2 couches plus loin, -1 = une devant).
## Autres vues : distance en blocs, précédée de ^ (au-dessus) ou v (en dessous) si l'écart est d'au moins 2 blocs.
func _sniff_texts() -> void:
	var p := Vector3i(main.player.center().floor())
	var cut: bool = main.view.mode == ViewCtl.CUT
	for e in sniff_labels:
		var c: Vector3i = e[1]
		var t := ""
		if cut:
			var off: int = (c[main.cut_axis] - main.cut_layer) * main.cut_sign
			t = "%+d" % off if off != 0 else "0"
		else:
			var dy := c.y - p.y  # distance, niveau Y absolu (celui du HUD) et écart vertical : « 12m  Y17 (-4) »
			t = "%dm  Y%d" % [roundi(Vector3(c - p).length()), c.y] + (" (%+d)" % dy if absi(dy) >= 2 else "")
		(e[0] as Label3D).text = t

func _sniff_step(dt: float) -> void:
	label_t -= dt
	if label_t <= 0.0:
		label_t = 0.2
		_sniff_texts()
	var wave := (sniff_total - active_t) * 13.0
	var lfade := clampf(active_t / 1.5, 0.0, 1.0)
	for e in sniff_labels:
		var lb: Label3D = e[0]
		lb.visible = e[2] <= wave and lfade > 0.0
		lb.modulate.a = lfade
	if sniff_mat:
		var elapsed := sniff_total - active_t
		sniff_mat.set_shader_parameter("wave", elapsed * 13.0)
		sniff_mat.set_shader_parameter("fade", clampf(active_t / 1.5, 0.0, 1.0))
		sniff_mat.set_shader_parameter("t", t)
