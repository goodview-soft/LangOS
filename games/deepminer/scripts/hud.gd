class_name Hud extends CanvasLayer

var fog: FogOfWar  # minimap shows only the explored cells
## Pixel-art French HUD: health, info, minimap, hotbar, toasts, help.

var atlas: Texture2D
var hp_bar: ProgressBar
var info: Label
var view_lbl: Label
var map_canvas: WorldMap.Canvas
var pick_style := [0, 0, 0]  # [tranchante, recul, épines] : l'icône de la pioche suit ses améliorations
var slots: Array = []
var sel_lbl: Label
var toast_lbl: Label
var toast_t := 0.0
var help: Label
var depth: DepthGauge
var planes: PlanePanel
var joy: JoyPad
var bar_box: HBoxContainer
var ab_panel: Panel
var ab_fill: ColorRect
var ab_lbl: Label
var load_lbl: Label
var panel: PanelContainer
var panel_lbl: Label

## Layer indicator: "Couche N" + two arrows (lit = a free layer exists deeper / closer).
class PlanePanel extends Control:
	var layer := 0
	var off := 0
	func _draw() -> void:
		var font := get_theme_default_font()
		for i in 5:
			var dz := 2 - i  # Z+2 en haut ... Z-2 en bas, relatif au plan du joueur
			var r := Rect2(0, i * 14, 46, 13)
			var cur := dz == off
			draw_rect(r, Color(1.0, 0.85, 0.4, 0.85) if cur else Color(0.05, 0.04, 0.08, 0.6))
			draw_string(font, Vector2(4, i * 14 + 10), "Z%+d  %d" % [dz, layer - off + dz] if dz != 0 else "Z%+d  %d" % [0, layer - off], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.BLACK if cur else Color(0.8, 0.8, 0.9, 0.8 - 0.15 * absi(dz)))

## Disposition tactile : barre d'objets agrandie (cases tapables) et joystick caméra décalé à droite du joystick de marche.
func touch_layout() -> void:
	bar_box.scale = Vector2(1.4, 1.4)
	var w := bar_box.get_combined_minimum_size().x
	bar_box.pivot_offset = Vector2(w / 2.0, 22.0)
	bar_box.position = Vector2(320 - w / 2.0, 360 - 8 - 22)
	sel_lbl.position.y = 360 - 57
	joy.position = Vector2(122, 360 - 8 - 44)
	help.offset_bottom = -60.0
	help.offset_top = -60.0

## Fenêtre plus haute que 16:9 : les éléments collés en bas descendent de dy (px logiques).
var _dy := 0.0
func set_extra(dy: float) -> void:
	var d := dy - _dy
	_dy = dy
	for c in [bar_box, sel_lbl, ab_panel, load_lbl, joy]:
		if c: c.position.y += d

## Small discreet joystick (bottom left): drag = turn the camera around the player (left/right) and tilt it (up/down).
class JoyPad extends Control:
	const R := 22.0
	var vec := Vector2.ZERO  # -1..1
	var drag := false
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			drag = ev.pressed
			if not drag:
				vec = Vector2.ZERO
			else:
				_aim(ev.position)
			queue_redraw()
			accept_event()
		elif ev is InputEventMouseMotion and drag:
			_aim(ev.position)
			accept_event()
	func _aim(p: Vector2) -> void:
		vec = ((p - Vector2(R, R)) / R).limit_length(1.0)
		queue_redraw()
	func _draw() -> void:
		draw_circle(Vector2(R, R), R, Color(0.05, 0.05, 0.1, 0.28))
		draw_arc(Vector2(R, R), R - 0.5, 0.0, TAU, 32, Color(1, 1, 1, 0.22), 1.0)
		draw_circle(Vector2(R, R) + vec * (R - 7.0), 6.0, Color(1, 1, 1, 0.55 if drag else 0.3))

class DepthGauge extends Control:
	var layer := 0
	var active := true
	var fwd := false
	var back := false

	func _draw() -> void:
		var on := Color(0.45, 1.0, 0.55)
		var off := Color(0.3, 0.3, 0.36)
		if not active:
			return
		var font := get_theme_default_font()
		draw_string_outline(font, Vector2(0, 9), "Couche %d" % layer, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 3, Color.BLACK)
		draw_string(font, Vector2(0, 9), "Couche %d" % layer, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.85, 0.4))
		if not active:
			return
		var x := 62.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, 5), Vector2(x + 4, 1), Vector2(x + 8, 5)]), on if fwd else off)
		draw_colored_polygon(PackedVector2Array([Vector2(x, 7), Vector2(x + 8, 7), Vector2(x + 4, 11)]), on if back else off)
		draw_string_outline(font, Vector2(x + 11, 9), "profondeur", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, Color.BLACK)
		draw_string(font, Vector2(x + 11, 9), "profondeur", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.8, 0.8, 0.9))

func _sb(bg: Color, border: Color, bw := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.anti_aliasing = false
	return s

var top_root: Control

## Pixel-art panel of the top bar (1 px brown border, no padding), same look as the HP panel.
func top_panel(pos: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _sb(Color(0.05, 0.04, 0.08, 0.85), Color(0.55, 0.42, 0.25))
	sb.set_content_margin_all(1)
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_root.add_child(p)
	return p

## Short title in the top-left corner of a top-bar panel, on a dark tab.
func top_title(parent: Control) -> Label:
	var l := _lbl("", 9)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.08, 0.8)
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	l.add_theme_stylebox_override("normal", sb)
	l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	l.position = Vector2(0, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _lbl(txt: String, size := 10) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	return l

func setup(atlas_tex: Texture2D, hotbar: Array) -> void:
	atlas = atlas_tex
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.theme()  # police lissée
	add_child(root)
	top_root = root
	# --- top-left panel
	var tl := PanelContainer.new()
	tl.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.04, 0.08, 0.75), Color(0.55, 0.42, 0.25)))
	tl.position = Vector2(6, 6)
	root.add_child(tl)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	tl.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	hb.add_child(_lbl("PV", 11))
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(90, 9)
	hp_bar.show_percentage = false
	hp_bar.max_value = 100
	hp_bar.add_theme_stylebox_override("background", _sb(Color(0.15, 0.03, 0.03), Color(0, 0, 0)))
	hp_bar.add_theme_stylebox_override("fill", _sb(Color(0.85, 0.12, 0.15), Color(1, 0.5, 0.5)))
	hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(hp_bar)
	info = _lbl("", 10)
	vb.add_child(info)
	view_lbl = _lbl("", 10)
	view_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vb.add_child(view_lbl)
	depth = DepthGauge.new()
	depth.custom_minimum_size = Vector2(120, 12)
	vb.add_child(depth)
	# --- top bar, right: minimap
	var mp := top_panel(Vector2(640 - 4 - 98, 4))
	var mbox := Control.new()
	mbox.custom_minimum_size = Vector2(96, 96.0 * World.SZ / World.SX)
	mbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mp.add_child(mbox)
	map_canvas = WorldMap.Canvas.new()
	map_canvas.px = 96.0 / World.SX  # la mini-carte garde sa taille : toute la carte dans 96 px de large
	map_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mbox.add_child(map_canvas)
	top_title(mbox).text = "Carte (B)"
	# --- hotbar
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	var n := hotbar.size()
	bar.position = Vector2(320 - (n * 24) / 2.0, 360 - 30)
	root.add_child(bar)
	bar_box = bar
	for i in n:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(22, 22)
		bar.add_child(p)
		var ic := TextureRect.new()
		ic.position = Vector2(3, 3)
		ic.size = Vector2(16, 16)
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.texture = icon(hotbar[i])
		p.add_child(ic)
		var key := _lbl(str(i + 1), 8)
		key.position = Vector2(1, -3)
		p.add_child(key)
		var cnt := _lbl("", 9)
		cnt.position = Vector2(8, 10)
		cnt.size = Vector2(13, 10)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		p.add_child(cnt)
		slots.append([p, cnt, ic])
	sel_lbl = _lbl("", 12)
	sel_lbl.position = Vector2(0, 360 - 47)
	sel_lbl.size = Vector2(640, 14)
	sel_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sel_lbl)
	# --- capacité spéciale (touche G)
	ab_panel = Panel.new()
	ab_panel.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.04, 0.08, 0.8), Color(0.55, 0.42, 0.25)))
	ab_panel.position = Vector2(640 - 6 - 128, 360 - 30)
	ab_panel.size = Vector2(128, 24)
	root.add_child(ab_panel)
	ab_fill = ColorRect.new()
	ab_fill.position = Vector2(1, 1)
	ab_fill.size = Vector2(0, 22)
	ab_panel.add_child(ab_fill)
	ab_lbl = _lbl("", 10)
	ab_lbl.position = Vector2(4, 4)
	ab_lbl.size = Vector2(120, 14)
	ab_panel.add_child(ab_lbl)
	load_lbl = _lbl("", 10)  # charge du sac, au-dessus de la capacité
	load_lbl.position = Vector2(640 - 6 - 128, 360 - 46)
	load_lbl.size = Vector2(128, 14)
	load_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(load_lbl)
	planes = PlanePanel.new()
	planes.position = Vector2(640 - 52, 110)
	planes.size = Vector2(46, 70)
	root.add_child(planes)
	joy = JoyPad.new()
	joy.position = Vector2(8, 360 - 8 - 44)
	joy.size = Vector2(44, 44)
	root.add_child(joy)
	toast_lbl = _lbl("", 12)
	toast_lbl.position = Vector2(0, 250)
	toast_lbl.size = Vector2(640, 14)
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	root.add_child(toast_lbl)
	fine_lbl = _lbl("MODE FIN : 1/8 de bloc  (F4)", 10)
	fine_lbl.position = Vector2(0, 236)
	fine_lbl.size = Vector2(640, 12)
	fine_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fine_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	fine_lbl.visible = false
	root.add_child(fine_lbl)
	help = _lbl("ZQSD : marcher   Espace : sauter   Souris : viser   Clic G : miner/frapper   Clic D : poser   Alt / Ctrl : accroupi (sneak)   Maj : courir vers la souris   Molette : zoom (au plus près = FPS, reculer = 3e personne)   Ctrl+molette : objet   Clic D + glisser : tourner/incliner la caméra\nV : 3e personne / FPS / 2D   Souris : regarder   PgUp/PgDn : distance caméra   B : grande carte   A/E : tourner de 90°\n1-8 : objet   J : torches   I : inventaire   M : recettes   C : chantier (plans)   B : carte   F : parler/lire   G : capacité   N : pomme dorée   F4 : creusage libre / blocs entiers   F5 : taille de pose   O : jeter 10   T/Entrée : chat   P : joueurs   / : commandes   H : aide\nVue 2D : Z/S maintenus = couche voisine   K perspective   L inclinaison souris   Eau : Espace nager, S/Alt/Ctrl plonger   Nain/Agile : Espace contre un mur = escalade", 8)
	help.visible = false  # chat lives bottom-left: help only on H
	# l'aide (H) revient à la ligne, grandit vers le haut depuis le bas de l'écran et a un fond sombre
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 10)
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0.03, 0.02, 0.05, 0.85)
	hsb.set_content_margin_all(4)
	help.add_theme_stylebox_override("normal", hsb)
	help.anchor_left = 0.0
	help.anchor_right = 0.0
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 6.0
	help.offset_right = 634.0
	help.offset_top = -40.0
	help.offset_bottom = -40.0
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	root.add_child(help)
	# --- info panel (miner / chest, key E)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.04, 0.08, 0.88), Color(0.55, 0.42, 0.25)))
	panel.position = Vector2(6, 64)
	panel.visible = false
	root.add_child(panel)
	panel_lbl = _lbl("", 10)
	panel_lbl.custom_minimum_size = Vector2(300, 0)
	panel_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	panel.add_child(panel_lbl)

## Charge du sac : discrète tant qu'on est loin de la limite, jaune près de la limite, rouge au-dessus (on ralentit).
## Icône d'un objet (-1 = pioche) : tuile de l'atlas, réutilisée par l'inventaire.
var sword_lvl := 1
func icon(item: int) -> Texture2D:
	if item == -2:  # case vide
		return null
	if item == -3:  # l'épée (la couleur de la lame suit son palier)
		return Tex.sword_icon(maxi(sword_lvl, 1))
	if item < 0:
		return Tex.pickaxe_icon(int(pick_style[0]), int(pick_style[1]), int(pick_style[2]))
	var at := AtlasTexture.new()
	at.atlas = atlas
	var t: int = World.TILE[item]
	at.region = Rect2((t % 4) * 16, (t / 4) * 16, 16, 16)
	return at

## Met à jour les icônes de la barre rapide après un changement d'affectation.
func sync_hotbar(hb: Array) -> void:
	for i in mini(slots.size(), hb.size()):
		(slots[i][2] as TextureRect).texture = icon(hb[i])

var fine_lbl: Label

func set_load(wt: float, cap: float) -> void:
	var r := wt / cap
	load_lbl.text = "Sac %d / %d" % [roundi(wt), roundi(cap)]
	load_lbl.modulate = Color(0.75, 0.75, 0.8, 0.0 if r < 0.4 else 0.8) if r < 0.85 else (Color(1.0, 0.85, 0.3) if r <= 1.0 else Color(1.0, 0.35, 0.3))

func set_ability(ab_name: String, ratio: float, cd: float, active: bool) -> void:
	var ready := ratio >= 1.0
	ab_fill.size.x = 126.0 * ratio
	ab_fill.color = Color(0.3, 0.8, 0.4, 0.55) if ready else Color(0.5, 0.35, 0.15, 0.6)
	if active:
		ab_fill.color = Color(1.0, 0.8, 0.2, 0.7)
	ab_lbl.text = "G  %s" % ab_name if ready else "G  %s  %ds" % [ab_name, ceili(cd)]
	ab_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6) if ready else Color(0.75, 0.75, 0.8))

func toast(t: String) -> void:
	toast_lbl.text = t
	toast_t = 2.0

func set_planes(l: int, o: int, on: bool) -> void:
	if planes.layer != l or planes.off != o or planes.visible != on:
		planes.layer = l; planes.off = o; planes.visible = on
		planes.queue_redraw()

func set_depth(layer: int, active: bool, fwd: bool, back: bool) -> void:
	if depth.layer != layer or depth.active != active or depth.fwd != fwd or depth.back != back:
		depth.layer = layer; depth.active = active; depth.fwd = fwd; depth.back = back
		depth.queue_redraw()

func show_panel(t: String) -> void:
	if panel_lbl.text != t:
		panel_lbl.text = t
		panel.reset_size()
	panel.visible = true

func hide_panel() -> void:
	panel.visible = false

func toggle_help() -> void:
	help.visible = not help.visible

var hurt_vig: TextureRect

## Vignette rouge quand le joueur encaisse un coup (a : 0-1).
var _hurt_v := 0.0
func set_hurt(a: float, dt: float) -> void:
	_hurt_v = maxf(a, _hurt_v - dt * 1.6)
	if hurt_vig == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 0, 0, 0.0), Color(1, 0.05, 0.05, 0.0), Color(1, 0.05, 0.05, 0.55)])
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 128
		gt.height = 128
		hurt_vig = TextureRect.new()
		hurt_vig.texture = gt
		hurt_vig.set_anchors_preset(Control.PRESET_FULL_RECT)
		hurt_vig.stretch_mode = TextureRect.STRETCH_SCALE
		hurt_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hurt_vig.modulate.a = 0.0
		add_child(hurt_vig)
	hurt_vig.modulate.a = clampf(_hurt_v, 0.0, 1.0)

func refresh(health: float, ppos: Vector3, view_txt: String, hotbar: Array, hn: Array, sel: int, dt: float) -> void:
	hp_bar.value = health
	info.text = "X %d   Y %d   Z %d" % [floori(ppos.x), floori(ppos.y), floori(ppos.z)]
	view_lbl.text = view_txt
	for i in slots.size():
		var item: int = hotbar[i]
		var p: Panel = slots[i][0]
		var cnt: Label = slots[i][1]
		var have: bool = item == -1 or (item >= 0 and int(hn[i]) > 0)  # pile épuisée : la case se vide
		cnt.text = str(hn[i]) if item >= 0 and have else ""
		(slots[i][2] as TextureRect).texture = icon(item) if have else null
		p.add_theme_stylebox_override("panel", _sb(Color(0.12, 0.1, 0.16, 0.85), Color(1.0, 0.85, 0.3) if i == sel else Color(0.4, 0.32, 0.22), 2 if i == sel else 1))
	var it: int = hotbar[sel]
	sel_lbl.text = "" if it == -2 or (it >= 0 and int(hn[sel]) <= 0) else ("Pioche" if it < 0 else World.NAMES[it])
	if toast_t > 0.0:
		toast_t -= dt
		toast_lbl.modulate.a = clampf(toast_t, 0.0, 1.0)

static func _axis(v: Vector3) -> int:
	if absf(v.x) > 0.5: return 0
	if absf(v.y) > 0.5: return 1
	return 2
