class_name Bag extends CanvasLayer
## Inventaire (touche I) : piles (Stacks) dans la barre rapide (touches 1-8) et dans le sac, façon « pile au curseur ».
## Clic gauche : prendre toute la pile / la poser (fusion si même objet, échange sinon). Clic droit : prendre la moitié /
## poser un seul objet. Maj + clic gauche : choisir combien prendre. Survoler une pile et taper 1-8 : l'envoyer dans la barre.

const EMPTY := -2  # case vide (-1 = la pioche)
const CELL := 36    # côté d'une case
const COL_GAP := 3
const MIN_CELLS := 24  # le sac montre au moins 3 lignes de 8
var main: Node3D
var slot_btns: Array = []
var grid: GridContainer
var title: Label
var charge: Label
var hint: Label
var tip: PanelContainer
var tip_lbl: Label
var _prev_mouse: int = Input.MOUSE_MODE_VISIBLE
var special_row: HBoxContainer
var hover := Vector2i(-1, -1)  # case survolée : (0 = barre / 1 = sac, indice)
var cur_icon: TextureRect  # pile tenue par la souris
var cur_qty: Label
var qty_panel: PanelContainer  # « Prendre combien ? »
var qty_slider: HSlider
var qty_lbl: Label
var qty_cell := Vector2i(-1, -1)

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
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Menu._sb(Color(0.06, 0.05, 0.07, 0.95), Color(0.55, 0.42, 0.25), 2))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	panel.add_child(vb)
	var top := HBoxContainer.new()
	vb.add_child(top)
	title = Menu._lbl("Sac", 13, Color(1.0, 0.85, 0.4))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	charge = Menu._lbl("", 10, Color(0.8, 0.8, 0.9))
	top.add_child(charge)
	var row := HBoxContainer.new()  # barre rapide : 8 cases carrées (icône + quantité), numéro en coin
	row.add_theme_constant_override("separation", COL_GAP)
	vb.add_child(row)
	for i in 8:
		var b := _cell(Color(0.45, 0.35, 0.25))
		var num := Label.new()
		num.text = str(i + 1)
		num.add_theme_font_size_override("font_size", 8)
		num.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		num.add_theme_color_override("font_outline_color", Color.BLACK)
		num.add_theme_constant_override("outline_size", 3)
		num.position = Vector2(2, -2)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(num)
		_wire(b, Vector2i(0, i))
		row.add_child(b)
		slot_btns.append(b)
	vb.add_child(HSeparator.new())
	grid = GridContainer.new()  # sac : grille de cases carrées, 8 par ligne comme la barre
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", COL_GAP)
	grid.add_theme_constant_override("v_separation", COL_GAP)
	vb.add_child(grid)
	vb.add_child(HSeparator.new())
	special_row = HBoxContainer.new()  # objets d'équipement (pas des blocs) : pommes dorées + pièces portées
	special_row.add_theme_constant_override("separation", COL_GAP)
	vb.add_child(special_row)
	hint = Menu._lbl("", 9, Color(0.85, 0.85, 0.92))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(8 * (CELL + COL_GAP), 0)
	vb.add_child(hint)
	var rb := Button.new()  # accès visible au livre de recettes
	rb.text = "Recettes (R)"
	rb.custom_minimum_size = Vector2(110, maxf(22.0, Menu.btn_h()))
	rb.add_theme_font_size_override("font_size", 10)
	rb.add_theme_stylebox_override("normal", Menu._sb(Color(0.14, 0.1, 0.1, 0.95), Color(0.85, 0.6, 0.25)))
	rb.add_theme_stylebox_override("hover", Menu._sb(Color(0.3, 0.2, 0.1, 0.95), Color(1.0, 0.75, 0.3)))
	rb.add_theme_stylebox_override("pressed", Menu._sb(Color(0.45, 0.3, 0.1, 0.95), Color(1.0, 0.75, 0.3)))
	rb.pressed.connect(func():
		close()
		main.book.open())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	vb.add_child(foot)
	foot.add_child(rb)
	var cb := Menu._btn("Fermer", close, 90)  # fermer au doigt (sinon seulement I / Échap)
	cb.custom_minimum_size.y = maxf(22.0, Menu.btn_h())
	foot.add_child(cb)
	# infobulle qui suit la souris (au-dessus de tout)
	tip = PanelContainer.new()
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	tip.add_theme_stylebox_override("panel", Menu._sb(Color(0.03, 0.02, 0.05, 0.95), Color(1.0, 0.85, 0.3)))
	tip_lbl = Menu._lbl("", 10, Color(0.95, 0.95, 1.0))
	tip.add_child(tip_lbl)
	root.add_child(tip)
	cur_icon = TextureRect.new()  # pile tenue par la souris
	cur_icon.size = Vector2(CELL - 10, CELL - 10)
	cur_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cur_icon.stretch_mode = TextureRect.STRETCH_SCALE
	cur_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cur_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cur_icon.visible = false
	cur_qty = Menu._lbl("", 10, Color.WHITE)
	cur_qty.position = Vector2(8, 14)
	cur_qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cur_icon.add_child(cur_qty)
	root.add_child(cur_icon)
	qty_panel = PanelContainer.new()  # choix de la quantité (Maj + clic)
	qty_panel.visible = false
	qty_panel.add_theme_stylebox_override("panel", Menu._sb(Color(0.04, 0.03, 0.06, 0.98), Color(1.0, 0.85, 0.3), 2))
	var qv := VBoxContainer.new()
	qv.add_theme_constant_override("separation", 4)
	qty_panel.add_child(qv)
	qty_lbl = Menu._lbl("", 11, Color(1.0, 0.85, 0.4))
	qv.add_child(qty_lbl)
	qty_slider = HSlider.new()
	qty_slider.custom_minimum_size = Vector2(150, 14)
	qty_slider.step = 1
	qty_slider.value_changed.connect(func(v: float): qty_lbl.text = "Prendre : %d / %d" % [int(v), int(qty_slider.max_value)])
	qv.add_child(qty_slider)
	var qb := HBoxContainer.new()
	qb.add_theme_constant_override("separation", 4)
	qv.add_child(qb)
	qb.add_child(Menu._btn("Prendre", _qty_ok, 70))
	qb.add_child(Menu._btn("Annuler", func(): qty_panel.visible = false, 70))
	center.add_child(qty_panel)

func open() -> void:
	if main.state != "play":
		return
	main.state = "pause"
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # en vue 3/4 et FPS la souris est capturée : on la libère
	qty_panel.visible = false
	visible = true
	_refresh()

func close() -> void:
	if visible:
		if main.cursor.x != EMPTY:  # la pile tenue retourne au sac
			Stacks.add_sac(main, main.cursor)
			main.cursor = Stacks.NONE
		visible = false
		qty_panel.visible = false
		_hide_tip()
		Input.mouse_mode = _prev_mouse as Input.MouseMode
		main.state = "play"

func _process(_dt: float) -> void:
	if not visible:
		return
	var m := get_viewport().get_mouse_position()
	if tip.visible:
		var sz := tip.get_combined_minimum_size()
		tip.position = Vector2(clampf(m.x + 12.0, 2.0, 638.0 - sz.x), clampf(m.y + 16.0, 2.0, 358.0 - sz.y))
	cur_icon.visible = main.cursor.x != EMPTY
	if cur_icon.visible:
		cur_icon.position = m + Vector2(-(CELL - 10) / 2.0, -(CELL - 10) / 2.0)

func _unhandled_input(ev: InputEvent) -> void:
	if not (visible and ev is InputEventKey and ev.pressed and not ev.echo):
		return
	get_viewport().set_input_as_handled()
	var k: int = ev.keycode
	if k == KEY_ESCAPE or k == KEY_I:
		if qty_panel.visible:
			qty_panel.visible = false
		else:
			close()
	elif k == KEY_R:
		close()
		main.book.open()
	elif ev.physical_keycode >= KEY_1 and ev.physical_keycode <= KEY_8 and hover.x >= 0 and main.cursor.x == EMPTY:
		_to_slot(hover, ev.physical_keycode - KEY_1)
	elif (k == KEY_DELETE or k == KEY_BACKSPACE) and hover.x == 0 and main.cursor.x == EMPTY:
		_to_slot(hover, -1)

# ---------------------------------------------------------------- cases
## Case carrée : icône agrandie (pixels nets) + quantité en bas à droite. Le nom n'est que dans l'infobulle.
func _cell(border: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(CELL, CELL)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", Menu._sb(Color(0.12, 0.1, 0.16, 0.9), border))
	b.add_theme_stylebox_override("hover", Menu._sb(Color(0.25, 0.2, 0.12, 0.95), Color(1.0, 0.85, 0.3)))
	b.add_theme_stylebox_override("pressed", Menu._sb(Color(0.4, 0.3, 0.1, 0.95), Color(1.0, 0.85, 0.3)))
	var ic := TextureRect.new()
	ic.position = Vector2(5, 4)
	ic.size = Vector2(CELL - 10, CELL - 10)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_SCALE
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	var q := Menu._lbl("", 9, Color.WHITE)
	q.position = Vector2(CELL - 24, CELL - 14)
	q.size = Vector2(22, 12)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(q)
	b.set_meta("ic", ic)
	b.set_meta("q", q)
	return b

func _fill(b: Button, st: Vector2i) -> void:
	(b.get_meta("ic") as TextureRect).texture = main.hud.icon(st.x) if st.x != EMPTY else null
	(b.get_meta("q") as Label).text = str(st.y) if st.x >= 0 else ""

# ---------------------------------------------------------------- piles
func _stack(c: Vector2i) -> Vector2i:
	if c.x == 0:
		return Vector2i(main.hotbar[c.y], main.hotbar_n[c.y]) if main.hotbar_n[c.y] > 0 or Stacks.is_held_tool(main.hotbar[c.y]) else Stacks.NONE
	if c.y >= main.sac.size():
		return Stacks.NONE
	return main.sac[c.y]

func _put_stack(c: Vector2i, v: Vector2i) -> void:
	if v.y <= 0 and not Stacks.is_held_tool(v.x):
		v = Stacks.NONE
	if c.x == 0:
		main.hotbar[c.y] = v.x
		main.hotbar_n[c.y] = v.y
	else:
		Stacks.ensure(main, c.y)
		main.sac[c.y] = v

static func _f(x: float) -> String:
	return String.num(x, 2).replace(".", ",")

func _stack_tip(id: int, n: int) -> String:
	if id == -1:
		return _weapon_tip()
	if id == Stacks.SWORD:
		return _sword_tip()
	var w := Carry.weight_of(id)
	return "%s  x%d\nPoids %s chacun, %s au total\nClic droit : moitié   Maj + clic : choisir" % [World.NAMES[id], n, _f(w), _f(w * n)]

func _sword_tip() -> String:
	var sw: int = int(main.gear.get("sword", 0))
	return "Épée en %s : dégâts x%s, portée +%s bloc, coup %d %% plus rapide.\nSélectionne-la dans la barre (touche du numéro) pour te battre ; la pioche creuse bien mieux.\nAméliorations : fonderie (cuivre, fer, cristal)." % [Gear.SWORD_NAMES[maxi(sw, 1)], String.num(Gear.SWORD_MULT[maxi(sw, 1)], 2), String.num(Gear.SWORD_REACH, 1), int((1.0 - Gear.SWORD_CD) * 100.0)]

## Description de l'arme : la pioche et ses améliorations (tranchante, recul, épines).
func _weapon_tip() -> String:
	var g: Dictionary = main.gear
	var t := "Pioche : creuse et frappe, toujours avec toi.\n"
	var sw: int = int(g.get("sword", 0))
	t += "Épée : %s\n" % ("aucune (fonderie)" if sw == 0 else "%s, dégâts x%s, portée +%s" % [Gear.SWORD_NAMES[sw], String.num(Gear.SWORD_MULT[sw], 2), String.num(Gear.SWORD_REACH, 1)])
	t += "Tranchante %s : dégâts +%d %%\n" % [["aucune", "I", "II", "III"][int(g.sharp)], int(minf(Gear.SHARP_PCT[int(g.sharp)], Gear.DMG_CAP) * 100.0)]
	t += "Recul %s : x%s\n" % [["aucun", "I", "II"][int(g.kb)], String.num(Gear.KB_MULT[int(g.kb)], 1)]
	t += "Épines : %s" % ("renvoie %d dégâts" % int(Gear.THORNS_DMG) if int(g.thorns) > 0 else "aucune")
	t += "\n(améliorations : fonderie, livre de recettes R)"
	return t

func _wire(b: Button, c: Vector2i) -> void:
	b.gui_input.connect(_cell_input.bind(c))
	b.mouse_entered.connect(func():
		hover = c
		var st := _stack(c)
		_show_tip(_stack_tip(st.x, st.y) if st.x != EMPTY else ("Case %d : vide" % (c.y + 1) if c.x == 0 else "")))
	b.mouse_exited.connect(func():
		if hover == c:
			hover = Vector2i(-1, -1)
		_hide_tip())

func _show_tip(t: String) -> void:
	if t == "":
		return
	tip_lbl.text = t
	tip.reset_size()
	tip.visible = true

func _hide_tip() -> void:
	tip.visible = false

func _cell_input(ev: InputEvent, c: Vector2i) -> void:
	if not (ev is InputEventMouseButton and ev.pressed):
		return
	var cur: Vector2i = main.cursor
	var st := _stack(c)
	if ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.shift_pressed and cur.x == EMPTY and st.x >= 0 and st.y > 1:
			_ask_qty(c, st)
			return
		if cur.x == EMPTY:  # tout prendre
			main.cursor = st
			_put_stack(c, Stacks.NONE)
		elif st.x == EMPTY:  # tout poser
			_put_stack(c, cur)
			main.cursor = Stacks.NONE
		elif st.x == cur.x and st.x >= 0:  # même objet : on fusionne jusqu'à la limite
			var t := mini(Stacks.CAP - st.y, cur.y)
			_put_stack(c, Vector2i(st.x, st.y + t))
			main.cursor = Vector2i(cur.x, cur.y - t) if cur.y - t > 0 else Stacks.NONE
		else:  # objets différents : échange
			_put_stack(c, cur)
			main.cursor = st
	elif ev.button_index == MOUSE_BUTTON_RIGHT:
		if cur.x == EMPTY:  # prendre la moitié
			if st.x >= 0:
				var h := (st.y + 1) / 2
				main.cursor = Vector2i(st.x, h)
				_put_stack(c, Vector2i(st.x, st.y - h))
			elif Stacks.is_held_tool(st.x):
				main.cursor = st
				_put_stack(c, Stacks.NONE)
		elif cur.x >= 0 and (st.x == EMPTY or (st.x == cur.x and st.y < Stacks.CAP)):  # poser un seul objet
			_put_stack(c, Vector2i(cur.x, st.y + 1))
			main.cursor = Vector2i(cur.x, cur.y - 1) if cur.y > 1 else Stacks.NONE
		elif Stacks.is_held_tool(cur.x) and st.x == EMPTY:
			_put_stack(c, cur)
			main.cursor = Stacks.NONE
	else:
		return
	_refresh()

## Envoie la pile survolée dans la case k de la barre (échange ou fusion) ; k = -1 : la renvoyer au sac.
func _to_slot(from: Vector2i, k: int) -> void:
	var st := _stack(from)
	if k < 0:
		if st.x != EMPTY and from.x == 0:
			_put_stack(from, Stacks.NONE)
			Stacks.add_sac(main, st)
	else:
		var dst := Vector2i(0, k)
		if dst != from:
			var o := _stack(dst)
			if st.x >= 0 and o.x == st.x:
				var t := mini(Stacks.CAP - o.y, st.y)
				_put_stack(dst, Vector2i(o.x, o.y + t))
				_put_stack(from, Vector2i(st.x, st.y - t))
			else:
				_put_stack(dst, st)
				_put_stack(from, o)
	_refresh()

func _ask_qty(c: Vector2i, st: Vector2i) -> void:
	qty_cell = c
	qty_slider.min_value = 1
	qty_slider.max_value = st.y
	qty_slider.value = (st.y + 1) / 2
	qty_lbl.text = "Prendre : %d / %d" % [int(qty_slider.value), st.y]
	qty_panel.visible = true

func _qty_ok() -> void:
	var st := _stack(qty_cell)
	var k := clampi(int(qty_slider.value), 1, maxi(st.y, 1))
	if st.x >= 0 and main.cursor.x == EMPTY:
		main.cursor = Vector2i(st.x, k)
		_put_stack(qty_cell, Vector2i(st.x, st.y - k))
	_refresh()

const TIER_COL := [Color(0.85, 0.5, 0.25), Color(0.75, 0.8, 0.9), Color(0.3, 0.95, 1.0)]

## Ligne « Équipement » : la pomme dorée (clic = la manger, comme la touche N) puis les 4 pièces portées (couleur du palier).
## Ces objets ne sont pas des blocs : ils vivent dans main.gear, on les affiche ici pour tout voir au même endroit.
func _refresh_special() -> void:
	for c in special_row.get_children():
		special_row.remove_child(c)
		c.queue_free()
	var g: Dictionary = main.gear
	var wp := _cell(Color(0.75, 0.8, 0.9))  # l'arme : la pioche et son niveau
	(wp.get_meta("ic") as TextureRect).texture = main.hud.icon(-1)
	(wp.get_meta("q") as Label).text = ["", "I", "II", "III"][int(g.sharp)]
	wp.tooltip_text = _weapon_tip()
	special_row.add_child(wp)
	var n := int(g.apples)
	var ap := _cell(Color(0.95, 0.75, 0.2))
	(ap.get_meta("ic") as TextureRect).texture = Tex.apple_icon()
	(ap.get_meta("q") as Label).text = str(n)
	ap.modulate = Color.WHITE if n > 0 else Color(1, 1, 1, 0.45)
	ap.tooltip_text = "Pomme dorée x%d\nClic ou touche N : la manger (soin +%d PV, régénération, absorption).\nSe fabrique dans le livre de recettes (R)." % [n, int(Gear.APPLE_HEAL)]
	ap.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close()
			main.use_apple())
	special_row.add_child(ap)
	special_row.add_child(Menu._lbl(" Porté :", 9, Color(1.0, 0.8, 0.4)))
	for i in 4:
		var t: int = g.armor[i]
		var sl := _cell(TIER_COL[t] if t >= 0 else Color(0.28, 0.24, 0.22))
		if t >= 0:
			(sl.get_meta("ic") as TextureRect).texture = main.hud.icon(Gear.TIER_ORE[t])
		sl.modulate = Color.WHITE if t >= 0 else Color(1, 1, 1, 0.45)
		(sl.get_meta("q") as Label).text = (Gear.SLOT_NAMES[i] as String).substr(0, 1)
		sl.tooltip_text = "%s : %s" % [Gear.SLOT_NAMES[i], ("rien (se fabrique à la fonderie)" if t < 0 else Gear.TIER_NAMES[t] + ", -%d %% de dégâts" % int(Gear.PIECE_PCT[t] * 100.0))]
		special_row.add_child(sl)
	var fx := Menu._lbl("  Armure -%d %%  Dégâts +%d %%" % [int(Gear.armor_pct(g) * 100.0), int((Gear.dmg_mult(g) - 1.0) * 100.0)], 9, Color(0.9, 0.95, 1.0))
	special_row.add_child(fx)

func _refresh() -> void:
	hover = Vector2i(-1, -1)
	qty_panel.visible = false
	_hide_tip()
	Stacks.reconcile(main)
	var wt := Carry.weight(main.inv)
	charge.text = "Charge %d / %d" % [roundi(wt), roundi(DMSettings.carry_cap())]
	charge.modulate = Color(1.0, 0.35, 0.3) if wt > DMSettings.carry_cap() else Color.WHITE
	for i in 8:
		var b: Button = slot_btns[i]
		_fill(b, _stack(Vector2i(0, i)))
		b.modulate = Color(1.0, 1.0, 0.7) if i == main.sel else Color.WHITE
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	var total := maxi(MIN_CELLS, ceili(main.sac.size() / 8.0) * 8)
	for k in total:
		var st := _stack(Vector2i(1, k))
		var b := _cell(Color(0.22, 0.19, 0.17) if st.x == EMPTY else Color(0.35, 0.3, 0.25))
		if st.x == EMPTY:
			b.modulate = Color(1, 1, 1, 0.55)
		_fill(b, st)
		_wire(b, Vector2i(1, k))
		grid.add_child(b)
	_refresh_special()
	if main.cursor.x != EMPTY:
		cur_icon.texture = main.hud.icon(main.cursor.x)
		cur_qty.text = str(main.cursor.y) if main.cursor.x >= 0 else ""
		hint.text = "Clique une case pour poser la pile (clic droit : un seul)."
	else:
		hint.text = "Clic : prendre / poser.  Clic droit : moitié.  Maj + clic : choisir.  I : fermer"
