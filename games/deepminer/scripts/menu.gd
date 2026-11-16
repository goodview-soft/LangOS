class_name Menu extends CanvasLayer
## Menus pixel-art : principal, personnage, options, pause. Construit en code (viewport 640x360).

signal play
signal resume
signal to_main
signal look_changed
signal new_game
signal quit_requested
signal host_requested(port: int)
signal join_requested(ip: String, port: int)

const GOLD := Color(1.0, 0.85, 0.4)
const HERO_POS := Vector2(470, 300)  # pieds du mineur sur le fond du menu principal

## Fond du menu principal : grotte en pixel art 2D, torche, gemmes et poussieres.
class CaveBg extends Control:
	var spikes := []  # [x, largeur, hauteur]
	var ground := []  # hauteur du sol par colonne de 4 px
	var back := []  # relief du fond par colonne de 4 px
	var gems := []  # [pos, couleur, phase]
	var motes := []  # [pos, vitesse, phase]
	var t := 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var r := RandomNumberGenerator.new()
		r.seed = 7
		var x := 0
		while x < 640:
			var w := r.randi_range(10, 30)
			spikes.append([x, w, r.randi_range(12, 56)])
			x += w
		for i in 160:
			var cx := i * 4 + 2
			var g := 300.0 + sin(i * 0.21) * 7.0 + r.randf_range(-3, 3)
			if absf(cx - HERO_POS.x) < 90:
				g = HERO_POS.y
			ground.append(int(g))
			back.append(int(250.0 + sin(i * 0.09) * 18.0 + sin(i * 0.37) * 6.0))
		var gc := [Color("#5ce0ff"), Color("#ffd02a"), Color("#c86bff"), Color("#ff6b4a")]
		for i in 16:
			var top := r.randf() < 0.4
			var gx := r.randi_range(4, 630)
			var gy: int = r.randi_range(2, 10) if top else ground[gx / 4] + r.randi_range(10, 50)
			gems.append([Vector2(gx, gy), gc.pick_random(), r.randf() * TAU])
		for i in 45:
			motes.append([Vector2(r.randf() * 640, r.randf() * 360), r.randf_range(4, 14), r.randf() * TAU])

	func _process(dt: float) -> void:
		if not is_visible_in_tree():
			return
		t += dt
		for m in motes:
			m[0].y -= m[1] * dt
			m[0].x += sin(t + m[2]) * 4.0 * dt
			if m[0].y < -2:
				m[0] = Vector2(randf() * 640, 362)
		queue_redraw()

	func _draw() -> void:
		var top := Color("#06050c")
		var mid := Color("#1d1638")
		for i in 45:
			var k := 1.0 - absf(i / 44.0 - 0.55) * 1.8
			draw_rect(Rect2(0, i * 8, 640, 8), top.lerp(mid, clampf(k, 0.0, 1.0)))
		# relief du fond (parallaxe)
		for i in back.size():
			draw_rect(Rect2(i * 4, back[i], 4, 360 - back[i]), Color("#130f24"))
		# lueur de la torche
		var torch := Vector2(HERO_POS.x - 70, HERO_POS.y - 22)
		var fl := 1.0 + sin(t * 9.0) * 0.04 + sin(t * 23.0) * 0.03
		for rr in range(150, 10, -14):
			draw_circle(torch, rr * fl, Color(1.0, 0.6, 0.25, 0.03))
		# plafond + stalactites
		draw_rect(Rect2(0, 0, 640, 10), Color("#0a0814"))
		for sp in spikes:
			draw_colored_polygon(PackedVector2Array([Vector2(sp[0], 8), Vector2(sp[0] + sp[1], 8), Vector2(sp[0] + sp[1] / 2.0, sp[2])]), Color("#0a0814"))
		# sol
		for i in ground.size():
			draw_rect(Rect2(i * 4, ground[i], 4, 360 - ground[i]), Color("#0a0814"))
			draw_rect(Rect2(i * 4, ground[i], 4, 2), Color("#2c2244"))
		# gemmes qui scintillent
		for g in gems:
			var a := 0.55 + 0.45 * sin(t * 2.0 + g[2])
			var c: Color = g[1]
			draw_rect(Rect2(g[0] - Vector2(1, 1), Vector2(3, 3)), Color(c, a * 0.5))
			draw_rect(Rect2(g[0], Vector2(1, 1)), Color(c.lightened(0.5), a))
		# torche
		draw_rect(Rect2(torch.x - 1, torch.y, 2, 22), Color("#6b4220"))
		var fh := 5.0 + sin(t * 11.0) * 1.5
		draw_rect(Rect2(torch.x - 2, torch.y - fh, 4, fh), Color("#ff9a2a"))
		draw_rect(Rect2(torch.x - 1, torch.y - fh + 2, 2, fh - 2), Color("#fff27a"))
		# poussieres lumineuses
		for m in motes:
			var a := 0.25 + 0.25 * sin(t * 3.0 + m[2])
			draw_rect(Rect2(m[0].floor(), Vector2(1, 1)), Color(1.0, 0.8, 0.5, a))

var dim: ColorRect
var bg: CaveBg
var hero: AnimatedSprite2D
var hero_name: Label
var screens := {}
var back_to := "main"
var preview: AnimatedSprite2D
var anim_i := 0
var anim_t := 0.0
var name_edit: LineEdit
var look_rows := {}  # key -> Control (ColorRect ou Label)
var zoom_lbl: Label
var species_locked := false  # partie commencée : l'espèce ne peut plus changer (les couleurs oui)
var play_btn: Button
var new_btn: Button
var new_confirm := 0.0
var species_lbl: Label

func _ready() -> void:
	layer = 10
	dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	bg = CaveBg.new()
	add_child(bg)
	screens.main = _build_main()
	screens.pause = _build_pause()
	screens.character = _build_character()
	screens.options = _build_options()
	screens.net = _build_net()
	for s in screens.values():
		s.theme = UiTheme.theme()  # police lissée
		add_child(s)
	_refresh_previews()

# ---------------------------------------------------------------- navigation
func open_main() -> void:
	back_to = "main"
	bg.visible = true
	_show("main")

func open_pause() -> void:
	back_to = "pause"
	bg.visible = false
	dim.color = Color(0.0, 0.0, 0.02, 0.65)
	_show("pause")

func close() -> void:
	visible = false

func _show(n: String) -> void:
	visible = true
	for k in screens:
		screens[k].visible = k == n
	if n == "character":
		_sync_look()
	elif n == "options":
		_sync_options()
	var first := _first_button(screens[n])
	if first:
		first.grab_focus.call_deferred()

func _first_button(n: Node) -> Button:
	for c in n.get_children():
		if c is Button and c.focus_mode != Control.FOCUS_NONE:
			return c
		var b := _first_button(c)
		if b:
			return b
	return null

## Une sauvegarde existe : « Continuer » + « Nouvelle partie » (avec confirmation).
func set_has_save(on: bool) -> void:
	play_btn.text = "Continuer" if on else "Jouer"
	new_btn.visible = on

func _on_new_game() -> void:
	if new_confirm > 0.0:
		new_game.emit()
	else:
		new_confirm = 3.0
		new_btn.text = "Effacer la sauvegarde ?"

func _back() -> void:
	DMSettings.save_cfg()
	_show(back_to)

func _unhandled_input(ev: InputEvent) -> void:
	if not visible or not (ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE):
		return
	get_viewport().set_input_as_handled()
	if screens.net.visible:
		_show("main")
	elif screens.character.visible or screens.options.visible:
		_back()
	elif screens.pause.visible:
		resume.emit()

func _process(dt: float) -> void:
	if not visible:
		return
	if new_confirm > 0.0:
		new_confirm -= dt
		if new_confirm <= 0.0:
			new_btn.text = "Nouvelle partie"
	anim_t += dt
	if anim_t > 2.0:
		anim_t = 0.0
		anim_i = (anim_i + 1) % 4
		preview.play(["idle", "walk", "mine", "idle"][anim_i])
		hero.play(["idle", "idle", "mine", "idle"][anim_i])

## Reconstruit les images du mineur pour l'apercu et le heros du menu (pieds = position du sprite).
func _refresh_previews() -> void:
	var sf := Tex.build_player_frames(DMSettings.look)
	var h := sf.get_frame_texture("idle", 0).get_height()
	for spr in [preview, hero]:
		var anim: StringName = spr.animation if spr.sprite_frames else &"idle"
		spr.sprite_frames = sf
		spr.offset = Vector2(0, -h / 2.0)
		spr.play(anim)
	hero_name.text = DMSettings.look.name

# ---------------------------------------------------------------- widgets
static func _sb(bg: Color, border: Color, bw := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.anti_aliasing = false
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	return s

static func _lbl(txt: String, size := 10, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l

## Hauteur minimale d'un bouton : plus grande au doigt (téléphone).
static func btn_h() -> float:
	return 30.0 if TouchControls.wanted() else 20.0

static func _btn(txt: String, cb: Callable, w := 130) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(w, btn_h())
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_stylebox_override("normal", _sb(Color(0.12, 0.1, 0.16, 0.9), Color(0.55, 0.42, 0.25)))
	b.add_theme_stylebox_override("hover", _sb(Color(0.22, 0.17, 0.12, 0.95), GOLD))
	b.add_theme_stylebox_override("focus", _sb(Color(0, 0, 0, 0), GOLD, 2))
	b.add_theme_stylebox_override("pressed", _sb(Color(0.35, 0.25, 0.1, 0.95), GOLD))
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.pressed.connect(cb)
	return b

func _small_btn(txt: String, cb: Callable) -> Button:
	var b := _btn(txt, cb, 16)
	b.custom_minimum_size = Vector2(16, 14) if not TouchControls.wanted() else Vector2(26, 24)
	b.add_theme_font_size_override("font_size", 9)
	b.focus_mode = Control.FOCUS_NONE
	return b

func _panel(title: String) -> Array:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.04, 0.08, 0.88), Color(0.55, 0.42, 0.25), 2))
	root.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	var t := _lbl(title, 14, GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	return [root, pc, vb]

func _center(pc: Control, w: float, h: float) -> void:
	pc.position = Vector2((640 - w) / 2.0, (360 - h) / 2.0)
	pc.custom_minimum_size = Vector2(w, h)

# ---------------------------------------------------------------- ecrans
func _build_main() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var title := _lbl("DEEP MINER", 40, GOLD)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.04))
	title.position = Vector2(0, 34)
	title.size = Vector2(640, 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var sub := _lbl("Creuse toujours plus profond", 10, Color(0.8, 0.8, 0.9))
	sub.position = Vector2(0, 84)
	sub.size = Vector2(640, 12)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4 if TouchControls.wanted() else 6)
	vb.position = Vector2(110, 104 if TouchControls.wanted() else 150)
	root.add_child(vb)
	hero = AnimatedSprite2D.new()
	hero.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hero.scale = Vector2(5, 5)
	hero.position = HERO_POS
	root.add_child(hero)
	hero_name = _lbl("", 12, GOLD)
	hero_name.position = Vector2(HERO_POS.x - 100, HERO_POS.y + 12)
	hero_name.size = Vector2(200, 14)
	hero_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hero_name)
	play_btn = _btn("Jouer", func(): play.emit())
	vb.add_child(play_btn)
	new_btn = _btn("Nouvelle partie", _on_new_game)
	new_btn.visible = false
	vb.add_child(new_btn)
	vb.add_child(_btn("Personnage", func(): _show("character")))
	vb.add_child(_btn("Options", func(): _show("options")))
	vb.add_child(_btn("Multijoueur", func(): _show("net")))
	vb.add_child(_btn("Quitter", func(): quit_requested.emit()))
	var ver := _lbl("prototype", 8, Color(0.5, 0.5, 0.6))
	ver.position = Vector2(560, 344)
	ver.size = Vector2(74, 10)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(ver)
	return root

func _build_pause() -> Control:
	var p := _panel("Pause")
	_center(p[1], 160, 120)
	var vb: VBoxContainer = p[2]
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(_btn("Reprendre", func(): resume.emit(), 146))
	vb.add_child(_btn("Personnage", func(): _show("character"), 146))
	vb.add_child(_btn("Options", func(): _show("options"), 146))
	vb.add_child(_btn("Menu principal", func(): to_main.emit(), 146))
	return p[0]

func _build_character() -> Control:
	var p := _panel("Personnage")
	_center(p[1], 420, 360)
	var vb: VBoxContainer = p[2]
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	vb.add_child(hb)
	# apercu
	var pv := Control.new()
	pv.custom_minimum_size = Vector2(110, 200)
	hb.add_child(pv)
	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", _sb(Color(0.02, 0.02, 0.04, 0.9), Color(0.3, 0.25, 0.2)))
	bg.position = Vector2(0, 10)
	bg.size = Vector2(110, 180)
	pv.add_child(bg)
	preview = AnimatedSprite2D.new()
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.scale = Vector2(3, 3)
	preview.position = Vector2(55, 182)
	pv.add_child(preview)
	# reglages
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("v_separation", 3)
	g.add_theme_constant_override("h_separation", 8)
	hb.add_child(g)
	g.add_child(_lbl("Nom", 11))
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(110, 16)
	name_edit.max_length = 16
	name_edit.add_theme_font_size_override("font_size", 10)
	name_edit.add_theme_stylebox_override("normal", _sb(Color(0.1, 0.08, 0.12), Color(0.55, 0.42, 0.25)))
	name_edit.text_changed.connect(func(t):
		DMSettings.look.name = t
		hero_name.text = t)
	g.add_child(name_edit)
	_choice_row(g, "Corps", "body", DMSettings.BODIES)
	_color_row(g, "Peau", "skin", DMSettings.SKINS)
	_color_row(g, "Casque", "helmet", DMSettings.COLORS)
	_color_row(g, "Chemise", "shirt", DMSettings.COLORS)
	_color_row(g, "Salopette", "overalls", DMSettings.COLORS)
	_color_row(g, "Bottes", "boots", DMSettings.COLORS)
	_choice_row(g, "Cheveux", "hair", DMSettings.HAIRS)
	_color_row(g, "Couleur", "hair_color", DMSettings.HAIR_COLORS)
	_choice_row(g, "Barbe", "beard", DMSettings.BEARDS)
	species_lbl = _lbl("", 10, Color(0.92, 0.92, 1.0))
	species_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	species_lbl.custom_minimum_size = Vector2(400, 52)
	vb.add_child(species_lbl)
	var bb := HBoxContainer.new()
	bb.alignment = BoxContainer.ALIGNMENT_CENTER
	bb.add_theme_constant_override("separation", 8)
	vb.add_child(bb)
	bb.add_child(_btn("Retour", _back, 100))
	bb.add_child(_btn("Aléatoire", func():
		var keep: int = DMSettings.look.body
		DMSettings.randomize_look()
		if species_locked:
			DMSettings.look.body = keep
		_sync_look(), 100))
	return p[0]

func _cycle(key: String, values: Array, d: int) -> void:
	if key == "body" and species_locked:
		return
	var i := values.find(DMSettings.look[key])
	DMSettings.look[key] = values[posmod(i + d, values.size())]
	_sync_look()

func _color_row(g: GridContainer, txt: String, key: String, values: Array) -> void:
	g.add_child(_lbl(txt, 11))
	var hb := HBoxContainer.new()
	hb.add_child(_small_btn("<", func(): _cycle(key, values, -1)))
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(70, 12)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(sw)
	hb.add_child(_small_btn(">", func(): _cycle(key, values, 1)))
	g.add_child(hb)
	look_rows[key] = sw

func _choice_row(g: GridContainer, txt: String, key: String, names: Array) -> void:
	g.add_child(_lbl(txt, 11))
	var hb := HBoxContainer.new()
	var idx := range(names.size())
	hb.add_child(_small_btn("<", func(): _cycle(key, idx, -1)))
	var l := _lbl("", 11)
	l.custom_minimum_size = Vector2(70, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(l)
	hb.add_child(_small_btn(">", func(): _cycle(key, idx, 1)))
	g.add_child(hb)
	look_rows[key] = [l, names]

func _sync_look() -> void:
	if name_edit.text != DMSettings.look.name:
		name_edit.text = DMSettings.look.name
	for k in look_rows:
		var w = look_rows[k]
		if w is ColorRect:
			w.color = Color(DMSettings.look[k])
		else:
			w[0].text = w[1][int(DMSettings.look[k])]
	var s: Dictionary = DMSettings.species()
	var ab: Dictionary = DMSettings.ability()
	var base: Dictionary = DMSettings.SPECIES[0]
	var pct := func(v: float, b: float) -> String: return "%+d%%" % roundi((v / b - 1.0) * 100.0)
	species_lbl.text = "Taille %d bloc%s   PV %d   Vitesse %s   Minage %s   Portée %.1f\n%s\nCapacité (G) : %s, %s (recharge %d s)" % [
		ceili(s.hh), "s" if s.hh > 1.0 else "", s.hp, pct.call(s.speed, base.speed), pct.call(s.mine, base.mine), s.reach, s.desc, ab.name, ab.desc, int(ab.cd)]
	if species_locked:
		species_lbl.text += "\nEspèce figée hors de la salle de spawn : retourne à la zone sûre (ou Nouvelle partie) pour en changer."
	for c in (look_rows["body"][0] as Label).get_parent().get_children():
		if c is Button:
			c.disabled = species_locked
	_refresh_previews()
	look_changed.emit()

func _build_options() -> Control:
	var p := _panel("Options")
	_center(p[1], 420, 330)
	var vb: VBoxContainer = p[2]
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("v_separation", 4)
	g.add_theme_constant_override("h_separation", 12)
	vb.add_child(g)
	g.add_child(_lbl("Volume", 12))
	var vol := HSlider.new()
	vol.name = "volume"
	vol.custom_minimum_size = Vector2(110, 12)
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value_changed.connect(func(v):
		DMSettings.volume = v
		DMSettings.apply_video())
	g.add_child(vol)
	g.add_child(_lbl("Zoom par défaut", 12))
	var zh := HBoxContainer.new()
	zh.add_child(_small_btn("-", func(): _zoom(-1)))
	zoom_lbl = _lbl("", 12)
	zoom_lbl.custom_minimum_size = Vector2(30, 12)
	zoom_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zh.add_child(zoom_lbl)
	zh.add_child(_small_btn("+", func(): _zoom(1)))
	g.add_child(zh)
	vb.add_child(_lbl("Touches", 13, GOLD))
	var keys := GridContainer.new()
	keys.columns = 4
	keys.add_theme_constant_override("h_separation", 10)
	keys.add_theme_constant_override("v_separation", 1)
	vb.add_child(keys)
	for kv in [["ZQSD", "marcher"], ["Z / S", "changer de couche"], ["Espace", "sauter"], ["Clic G", "miner"],
			["Clic D", "poser"], ["1 - 9", "outil"], ["F", "torches"], ["C / R", "vue / pivoter"],
			["T", "relief"], ["Molette", "zoom"], ["Flèches", "caméra"], ["V", "recentrer"],
			["G", "capacité"], ["O", "jeter 10"], ["I", "inventaire"], ["M", "recettes"], ["H", "aide"], ["Échap", "pause"]]:
		keys.add_child(_lbl(kv[0], 11, GOLD))
		keys.add_child(_lbl(kv[1], 11, Color(0.92, 0.92, 1.0)))
	var b := _btn("Retour", _back, 100)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(b)
	return p[0]

func _zoom(d: int) -> void:
	DMSettings.zoom = clampi(DMSettings.zoom + d, 0, 5)
	_sync_options()

func _sync_options() -> void:
	var o: Control = screens.options
	(o.find_child("volume", true, false) as HSlider).set_value_no_signal(DMSettings.volume)
	zoom_lbl.text = "%d / 6" % (DMSettings.zoom + 1)

# ---------------------------------------------------------------- multijoueur LAN
var ip_edit: LineEdit
var port_edit: LineEdit
var net_status: Label

func _build_net() -> Control:
	var p := _panel("Multijoueur (LAN)")
	_center(p[1], 260, 190)
	var vb: VBoxContainer = p[2]
	vb.add_child(_lbl("Héberger : tes amis rejoignent ton IP", 9))
	port_edit = LineEdit.new()
	port_edit.text = "7777"
	port_edit.custom_minimum_size = Vector2(60, 16)
	port_edit.add_theme_font_size_override("font_size", 10)
	var row := HBoxContainer.new()
	row.add_child(_lbl("Port ", 10))
	row.add_child(port_edit)
	vb.add_child(row)
	vb.add_child(_btn("Héberger", func(): host_requested.emit(_port()), 146))
	net_status = _lbl("", 9, GOLD)
	vb.add_child(net_status)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "IP de l'hôte"
	ip_edit.text = "127.0.0.1"
	ip_edit.custom_minimum_size = Vector2(120, 16)
	ip_edit.add_theme_font_size_override("font_size", 10)
	vb.add_child(ip_edit)
	vb.add_child(_btn("Rejoindre", func(): join_requested.emit(ip_edit.text.strip_edges(), _port()), 146))
	vb.add_child(_btn("Retour", func(): _show("main"), 146))
	return p[0]

func _port() -> int:
	var n := port_edit.text.to_int() if port_edit else 7777
	return n if n > 0 and n < 65536 else 7777

func set_net_status(t: String) -> void:
	if net_status:
		net_status.text = t
