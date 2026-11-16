class_name RecipeBook extends CanvasLayer
## Livre de recettes (touche I, ou F près d'une fonderie) : liste de ce qu'on sait fabriquer, avec les ingrédients.
## Les recettes « à la fonderie » ne marchent qu'à moins de 3 blocs d'une fonderie posée.

const FORGE_ST := "forge"
const PANEL_W := 560  # largeur de contenu : tient dans l'écran (640) avec les marges
var main: Node3D
var rows: Array = []  # [recette, -, bouton x1, bouton max]
var list: VBoxContainer
var worn_box: HBoxContainer
var worn_fx: Label
var msg: Label
var _prev_mouse: int = Input.MOUSE_MODE_VISIBLE
var station: Label

## Ingrédients -> produit. station : "" (partout) ou FORGE_ST. torches : le nombre dépend de l'espèce.
func recipes() -> Array:
	return [
		{"name": "Torches", "cost": {World.COAL: 1}, "out": {World.TORCH: main.player.torch_craft}, "station": "", "tip": "1 charbon donne %d torches (selon ton espèce). Touche J : fabrication rapide." % main.player.torch_craft},
		{"name": "Fonderie", "cost": {World.STONE: 8, World.COAL: 2}, "out": {World.FORGE: 1}, "station": "", "tip": "Pose-la par terre : il faut rester à moins de 3 blocs pour fabriquer lingots, pierre taillée et équipement."},
		{"name": "Pierre taillée", "cost": {World.STONE: 2}, "out": {World.BRICK: 2}, "station": FORGE_ST, "tip": "Taille 2 roches en 2 pierres taillées (briques), utiles pour bâtir."},
		{"name": "Lingot de fer", "cost": {World.IRON: 2, World.COAL: 1}, "out": {World.IRON_B: 1}, "station": FORGE_ST, "tip": "Fond 2 minerais de fer avec 1 charbon en un lingot de fer."},
		{"name": "Lingot de cuivre", "cost": {World.COPPER: 2, World.COAL: 1}, "out": {World.COPPER_B: 1}, "station": FORGE_ST, "tip": "Fond 2 minerais de cuivre avec 1 charbon en un lingot de cuivre."},
	] + Gear.recipes(main.gear)

static func _button(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(58, 22 if TouchControls.wanted() else 18)
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_stylebox_override("normal", Menu._sb(Color(0.14, 0.1, 0.1, 0.95), Color(0.7, 0.45, 0.2)))
	b.add_theme_stylebox_override("hover", Menu._sb(Color(0.3, 0.2, 0.1, 0.95), Color(1.0, 0.75, 0.3)))
	b.add_theme_stylebox_override("pressed", Menu._sb(Color(0.45, 0.3, 0.1, 0.95), Color(1.0, 0.75, 0.3)))
	b.add_theme_stylebox_override("disabled", Menu._sb(Color(0.08, 0.07, 0.08, 0.9), Color(0.25, 0.22, 0.2)))
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

func _ready() -> void:
	layer = 12
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.02, 0.55)
	root.add_child(dim)
	var center := CenterContainer.new()  # toujours centré : rien ne sort de l'écran
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Menu._sb(Color(0.07, 0.05, 0.06, 0.96), Color(0.85, 0.6, 0.25), 2))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var t := Menu._lbl("Livre de recettes", 13, Color(1.0, 0.8, 0.4))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	station = Menu._lbl("", 9, Color(0.85, 0.85, 0.92))
	station.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # à la ligne : un long texte ne doit jamais élargir le panneau
	station.custom_minimum_size = Vector2(PANEL_W, 0)
	vb.add_child(station)
	worn_box = HBoxContainer.new()  # équipement porté : une case par pièce
	worn_box.add_theme_constant_override("separation", 6)
	worn_box.custom_minimum_size = Vector2(PANEL_W, 0)
	vb.add_child(worn_box)
	worn_fx = Menu._lbl("", 10, Color(0.9, 0.95, 1.0))  # effets actuels, sur leur propre ligne
	worn_fx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	worn_fx.custom_minimum_size = Vector2(PANEL_W, 0)
	vb.add_child(worn_fx)
	var sc := ScrollContainer.new()  # la liste défile : on lit tout, même avec beaucoup de recettes
	sc.custom_minimum_size = Vector2(PANEL_W, 165)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # jamais de défilement horizontal : les lignes tiennent dans la largeur
	vb.add_child(sc)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	msg = Menu._lbl("", 10, Color(1.0, 0.95, 0.6))
	vb.add_child(msg)
	vb.add_child(_button("Fermer (Échap)", close))

## Pastille graphique : l'icône du bloc (agrandie, pixels nets) + un texte court ; le nom complet est dans l'infobulle.
func _chip(id: int, txt: String, col: Color) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	hb.tooltip_text = World.NAMES[id]
	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(22, 22)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_SCALE
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.texture = main.hud.icon(id)
	hb.add_child(ic)
	hb.add_child(Menu._lbl(txt, 10, col))
	return hb

func open() -> void:
	if main.state != "play":
		return
	main.state = "pause"
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # libère la souris capturée (vues 3/4 et FPS)
	msg.text = ""
	visible = true
	_refresh()

func close() -> void:
	if visible:
		visible = false
		Input.mouse_mode = _prev_mouse as Input.MouseMode
		main.state = "play"

func _unhandled_input(ev: InputEvent) -> void:
	if visible and ev is InputEventKey and ev.pressed and not ev.echo and (ev.keycode == KEY_ESCAPE or ev.keycode == KEY_I or ev.keycode == KEY_M):
		get_viewport().set_input_as_handled()
		close()

func _names(d: Dictionary) -> String:
	var parts: Array = []
	for id in d:
		parts.append("%d %s" % [d[id], World.NAMES[id].to_lower()])
	return " + ".join(parts)

## Combien de fois on peut fabriquer la recette (0 si ingrédients ou fonderie manquants).
func _can(r: Dictionary) -> int:
	if r.station == FORGE_ST and main._forge_near() == null:
		return 0
	if r.has("gear") and r.maxed:
		return 0
	var k := 999
	for id in r.cost:
		k = mini(k, int(main.inv.get(id, 0)) / int(r.cost[id]))
	return k

func _refresh() -> void:
	var near: bool = main._forge_near() != null
	station.text = "Fonderie à proximité : oui  (lingots, pierre taillée et équipement fabricables)" if near else "Pas de fonderie à moins de 3 blocs : lingots, pierre taillée et équipement sont bloqués. Fabrique une fonderie (8 roche + 2 charbon), pose-la et reste près d'elle."
	station.modulate = Color(0.7, 1.0, 0.7) if near else Color(1.0, 0.7, 0.55)
	_refresh_worn()
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	rows.clear()
	var rs := recipes()
	var gear_title := false
	var mat_title := false
	for i in rs.size():
		var r: Dictionary = rs[i]
		if not r.has("gear") and not mat_title:
			mat_title = true
			list.add_child(Menu._lbl("Matériaux", 10, Color(1.0, 0.8, 0.4)))
		if r.has("gear") and not gear_title:
			gear_title = true
			list.add_child(Menu._lbl("Équipement", 10, Color(1.0, 0.8, 0.4)))
		var k := _can(r)
		var panel := PanelContainer.new()
		var sb := Menu._sb(Color(0.10, 0.08, 0.10, 0.9), Color(0.3, 0.8, 0.45) if k > 0 else Color(0.28, 0.24, 0.22))
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		panel.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 5)
		panel.add_child(hb)
		var nm := Menu._lbl(r.name, 10, Color(1.0, 1.0, 1.0) if k > 0 else Color(0.7, 0.7, 0.75))
		nm.custom_minimum_size = Vector2(112, 14)
		nm.clip_text = true
		nm.tooltip_text = r.name
		nm.mouse_filter = Control.MOUSE_FILTER_PASS
		hb.add_child(nm)
		var ing := HBoxContainer.new()  # ingrédients : possédé / nécessaire, rouge si on en manque
		ing.add_theme_constant_override("separation", 6)
		ing.custom_minimum_size = Vector2(126, 0)
		for id in r.cost:
			var have := int(main.inv.get(id, 0))
			ing.add_child(_chip(id, "%d/%d" % [have, int(r.cost[id])], Color(0.7, 1.0, 0.7) if have >= int(r.cost[id]) else Color(1.0, 0.45, 0.4)))
		if r.has("gear") and r.maxed:
			ing.add_child(Menu._lbl("terminé", 10, Color(0.7, 0.9, 1.0)))
		hb.add_child(ing)
		hb.add_child(Menu._lbl("→", 12, Color(1.0, 0.8, 0.4)))
		var out := HBoxContainer.new()
		out.custom_minimum_size = Vector2(98, 0)
		for id in r.out:
			out.add_child(_chip(id, "x%d" % int(r.out[id]), Color.WHITE))
		if r.has("gear"):
			var inf := Menu._lbl(r.info, 9, Color(0.85, 0.9, 1.0))
			inf.custom_minimum_size = Vector2(98, 12)
			inf.clip_text = true
			inf.tooltip_text = r.info
			inf.mouse_filter = Control.MOUSE_FILTER_PASS
			out.add_child(inf)
		hb.add_child(out)
		if r.station == FORGE_ST:  # badge fonderie
			var fc := _chip(World.FORGE, "", Color.WHITE)
			fc.tooltip_text = "À faire près d'une fonderie"
			fc.modulate = Color.WHITE if near else Color(1.0, 0.6, 0.5)
			hb.add_child(fc)
		var forge_missing: bool = r.station == FORGE_ST and not near
		var b1 := _button("Fonderie !" if forge_missing and _afford(r) else "Fabriquer", Callable())
		var b2 := _button("Max", Callable())
		b1.custom_minimum_size.x = 62
		b2.custom_minimum_size.x = 34
		b1.disabled = k <= 0
		b2.disabled = k <= 1 or r.has("gear")
		b1.pressed.connect(_craft.bind(i, false))
		b2.pressed.connect(_craft.bind(i, true))
		hb.add_child(b1)
		hb.add_child(b2)
		var tip: String = r.get("tip", "")
		if forge_missing:
			tip += "\n(Demande une fonderie posée à moins de 3 blocs.)"
		panel.tooltip_text = tip
		list.add_child(panel)
		rows.append([r, null, b1, b2])

## Les ingrédients sont là (la fonderie, elle, est à part).
func _afford(r: Dictionary) -> bool:
	if r.has("gear") and r.maxed:
		return false
	for id in r.cost:
		if int(main.inv.get(id, 0)) < int(r.cost[id]):
			return false
	return true

const TIER_COL := [Color(0.85, 0.5, 0.25), Color(0.75, 0.8, 0.9), Color(0.3, 0.95, 1.0)]

## Équipement porté : une case par pièce (couleur et icône du palier), puis les effets actuels. Fabriquer une pièce l'équipe aussitôt.
func _refresh_worn() -> void:
	for c in worn_box.get_children():
		worn_box.remove_child(c)
		c.queue_free()
	var g: Dictionary = main.gear
	worn_box.add_child(Menu._lbl("Porté :", 10, Color(1.0, 0.8, 0.4)))
	for i in 4:
		var t: int = g.armor[i]
		var box := PanelContainer.new()
		var sb := Menu._sb(Color(0.10, 0.08, 0.10, 0.9), TIER_COL[t] if t >= 0 else Color(0.28, 0.24, 0.22), 2 if t >= 0 else 1)
		sb.set_content_margin_all(2)
		box.add_theme_stylebox_override("panel", sb)
		box.tooltip_text = "%s : %s" % [Gear.SLOT_NAMES[i], ("rien" if t < 0 else Gear.TIER_NAMES[t] + " (-%d %%)" % int(Gear.PIECE_PCT[t] * 100.0))]
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		box.add_child(v)
		if t >= 0:
			var ic := TextureRect.new()
			ic.custom_minimum_size = Vector2(20, 20)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_SCALE
			ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ic.texture = main.hud.icon(Gear.TIER_ORE[t])
			v.add_child(ic)
		else:
			v.add_child(Menu._lbl("-", 12, Color(0.5, 0.5, 0.55)))
		v.add_child(Menu._lbl((Gear.SLOT_NAMES[i] as String).substr(0, 4) + ".", 8, Color(0.85, 0.85, 0.9)))
		worn_box.add_child(box)
	worn_fx.text = "Armure -%d %%   Dégâts +%d %%   Recul x%s   Épines %s   Pommes %d" % [int(Gear.armor_pct(g) * 100.0), int((Gear.dmg_mult(g) - 1.0) * 100.0), String.num(Gear.KB_MULT[int(g.kb)], 1), "oui" if int(g.thorns) > 0 else "non", int(g.apples)]
	worn_fx.tooltip_text = "Fabriquer une pièce l'équipe tout de suite : il n'y a rien d'autre à faire.\nLes pommes se mangent avec la touche N."
	worn_fx.mouse_filter = Control.MOUSE_FILTER_PASS

func _craft(i: int, all: bool) -> void:
	var r: Dictionary = recipes()[i]
	var k := _can(r)
	if k <= 0:
		return
	if not all or r.has("gear"):
		k = 1
	for id in r.cost:
		main.inv[id] -= int(r.cost[id]) * k
	for id in r.out:
		main.inv[id] = main.inv.get(id, 0) + int(r.out[id]) * k
	if r.has("gear"):
		Gear.apply(main.gear, r.gear)
		main.apply_gear()
		msg.text = "+ %s" % r.name
	else:
		msg.text = "+ %s" % _names({r.out.keys()[0]: int(r.out.values()[0]) * k})
	_refresh()
