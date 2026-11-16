extends Node
## Vue d'ensemble des fenêtres (Ctrl+Alt+Tab) avec miniatures et bureaux virtuels, et aperçu au survol des boutons de tâches / du dock.
## Les miniatures sont recadrées dans la capture de la fenêtre principale (dernière image connue conservée pour les fenêtres masquées).

var m
var layer: ColorRect
var sel := 0
var ids_now: Array = []
var thumbs := {}            # id -> ImageTexture
var peek: PanelContainer
var peek_gen := 0
var peek_hover := false
const TW := 230.0
const TH := 140.0

func is_open() -> bool:
	return is_instance_valid(layer)

# ---------------------------------------------------------------- Miniatures
func _can_grab() -> bool:
	return DisplayServer.get_name() != "headless" and m != null and m.get_viewport() != null

## Capture l'écran une fois et recadre chaque fenêtre visible (« only » : un seul id).
func snap_all(only := "") -> void:
	if not _can_grab(): return
	var vis := []
	for id in m.wins:
		if only != "" and id != only: continue
		var d: Dictionary = m.wins[id]
		if d["win"].visible and not d["min"] and int(d["vd"]) == m.cur_vd: vis.append(id)
	if vis.is_empty(): return
	var tex: Texture2D = m.get_viewport().get_texture()
	if tex == null: return
	var img: Image = tex.get_image()
	if img == null or img.is_empty(): return
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	if vs.x < 1.0 or vs.y < 1.0: return
	var k := Vector2(img.get_width() / vs.x, img.get_height() / vs.y)
	for id in vis:
		var w: Control = m.wins[id]["win"]
		var r := Rect2(w.global_position * k, w.size * k).intersection(Rect2(Vector2.ZERO, img.get_size()))
		if r.size.x < 8.0 or r.size.y < 8.0: continue
		var part: Image = img.get_region(Rect2i(r))
		thumbs[id] = ImageTexture.create_from_image(part)

func _thumb_box(id: String, sz: Vector2) -> Control:
	var pc := PanelContainer.new(); pc.custom_minimum_size = sz; pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", m._box(m._p("field"), maxi(4, m._rad() - 3)))
	pc.clip_contents = true
	if thumbs.has(id) and m.wins.has(id):
		var tr := TextureRect.new(); tr.texture = thumbs[id]; tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; tr.mouse_filter = Control.MOUSE_FILTER_IGNORE; pc.add_child(tr)
	else:
		var cc := CenterContainer.new(); cc.mouse_filter = Control.MOUSE_FILTER_IGNORE; pc.add_child(cc)
		var ic := TextureRect.new(); ic.texture = m.app_icon(id); ic.custom_minimum_size = Vector2(56, 56)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; ic.mouse_filter = Control.MOUSE_FILTER_IGNORE; cc.add_child(ic)
	return pc

func _title_of(id: String) -> String:
	var l = m.wins[id]["title"] if m.wins.has(id) else null
	return str(l.text) if l is Label else str(m.APPS[id][0])

# ---------------------------------------------------------------- Vue d'ensemble
func toggle() -> void:
	if is_open(): close()
	else: open()

func order() -> Array:
	var r := []
	for i in m.n_vd:
		var inv := []
		for id in m.wins:
			if int(m.wins[id]["vd"]) == i: inv.append(id)
		inv.sort_custom(func(a, b): return m.desk.get_children().find(m.wins[a]["win"]) > m.desk.get_children().find(m.wins[b]["win"]))
		if i == m.cur_vd: r = inv + r
		else: r += inv
	return r

func open() -> void:
	if is_open() or m == null or m.desk == null: return
	peek_hide()
	snap_all()
	m._hide_ctx()
	layer = ColorRect.new(); layer.color = Color(0, 0, 0, 0.62); layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: close())
	m.add_child(layer)
	ids_now = order(); sel = 0
	_build()
	if m.fx.on():
		layer.modulate.a = 0.0; layer.create_tween().tween_property(layer, "modulate:a", 1.0, 0.12)

func close() -> void:
	if is_open(): layer.queue_free()
	layer = null

func _build() -> void:
	for c in layer.get_children(): c.queue_free()
	var mg := MarginContainer.new(); mg.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]: mg.add_theme_constant_override("margin_" + k, 24)
	layer.add_child(mg)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 18); mg.add_child(v)
	# Bureaux virtuels
	var pills := HBoxContainer.new(); pills.alignment = BoxContainer.ALIGNMENT_CENTER; pills.add_theme_constant_override("separation", 8); v.add_child(pills)
	for i in m.n_vd:
		var n := 0
		for id in m.wins: if int(m.wins[id]["vd"]) == i: n += 1
		var b := Button.new(); b.text = "Bureau %d  ·  %d" % [i + 1, n]; b.focus_mode = Control.FOCUS_NONE; b.custom_minimum_size = Vector2(0, 38)
		var on: bool = i == m.cur_vd
		b.add_theme_stylebox_override("normal", m._box(Color(m.ACCENT, 0.9) if on else Color(m._p("menu"), 0.9), 19, m._p("edge"), 0 if on else 1, 0, 10))
		b.add_theme_stylebox_override("hover", m._box(Color(m.ACCENT, 0.9) if on else Color(m._p("tb_on"), 1.0), 19, m._p("edge"), 0 if on else 1, 0, 10))
		b.add_theme_stylebox_override("pressed", b.get_theme_stylebox("hover"))
		b.add_theme_color_override("font_color", UI_on(m.ACCENT) if on else m._p("text"))
		b.add_theme_color_override("font_hover_color", UI_on(m.ACCENT) if on else m._p("text"))
		b.pressed.connect(func(): m._goto_vd(i); ids_now = order(); sel = 0; _build())
		pills.add_child(b)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; v.add_child(sc)
	var fl := HFlowContainer.new(); fl.alignment = FlowContainer.ALIGNMENT_CENTER; fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fl.add_theme_constant_override("h_separation", 16); fl.add_theme_constant_override("v_separation", 16); sc.add_child(fl)
	if ids_now.is_empty():
		var l := Label.new(); l.text = "Aucune fenêtre ouverte"; l.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; fl.add_child(l)
	for i in ids_now: fl.add_child(_card(i, ids_now.find(i) == sel))

func UI_on(bg: Color) -> Color:
	return Color.BLACK if bg.get_luminance() > 0.5 else Color.WHITE

func _card(id: String, on: bool) -> Control:
	var c := PanelContainer.new(); c.custom_minimum_size.x = TW
	var edge: Color = m.ACCENT if on else m._p("edge")
	var st: StyleBoxFlat = m._box(Color(m._p("menu"), 0.96), m._rad() + 2, edge, 3 if on else 1, 14, 8)
	c.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; c.add_child(v)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 6); h.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(h)
	var ic := TextureRect.new(); ic.texture = m.app_icon(id); ic.custom_minimum_size = Vector2(20, 20); ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER; ic.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(ic)
	var t := Label.new(); t.text = _title_of(id); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.custom_minimum_size.x = 10; t.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(t)
	var vd := int(m.wins[id]["vd"])
	if m.n_vd > 1:
		var bl := Label.new(); bl.text = "B%d" % (vd + 1); bl.add_theme_font_size_override("font_size", 12); bl.modulate = Color(1, 1, 1, 0.6); bl.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(bl)
	var cl: Button = m._icon_btn("close", "Circular", 24, 24, 11); cl.tooltip_text = "Fermer"
	cl.pressed.connect(func():
		m._close_win(id); ids_now = order(); sel = clampi(sel, 0, maxi(0, ids_now.size() - 1))
		if ids_now.is_empty(): close()
		else: _build.call_deferred())
	h.add_child(cl)
	v.add_child(_thumb_box(id, Vector2(TW - 16.0, TH)))
	c.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _activate(id))
	c.mouse_entered.connect(func(): m.fx.hover(c, true, 1.04)); c.mouse_exited.connect(func(): m.fx.hover(c, false))
	return c

func _activate(id: String) -> void:
	close()
	if m.wins.has(id): m._show(id)

func _input(ev: InputEvent) -> void:
	if not is_open() or not (ev is InputEventKey) or not ev.pressed: return
	var n := ids_now.size()
	match ev.keycode:
		KEY_ESCAPE: close()
		KEY_TAB: sel = posmod(sel + (-1 if ev.shift_pressed else 1), maxi(1, n)); _build()
		KEY_RIGHT, KEY_DOWN: sel = posmod(sel + 1, maxi(1, n)); _build()
		KEY_LEFT, KEY_UP: sel = posmod(sel - 1, maxi(1, n)); _build()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if n > 0: _activate(ids_now[clampi(sel, 0, n - 1)])
			else: close()
		_: return
	get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- Aperçu au survol (barre des tâches / dock)
func peek_show(id: String, anchor: Control) -> void:
	peek_gen += 1; var g := peek_gen
	var delay := 0.05 if is_instance_valid(peek) else 0.4
	get_tree().create_timer(delay).timeout.connect(func():
		if g != peek_gen or not is_instance_valid(anchor) or not m.wins.has(id) or is_open() or m.menu.visible or is_instance_valid(m.ctx_menu): return
		if not anchor.get_global_rect().has_point(anchor.get_global_mouse_position()): return
		_peek_build(id, anchor))

func peek_hide_soon() -> void:
	peek_gen += 1; var g := peek_gen
	get_tree().create_timer(0.25).timeout.connect(func(): if g == peek_gen and not peek_hover: peek_hide())

func peek_hide() -> void:
	peek_gen += 1; peek_hover = false
	if is_instance_valid(peek): peek.queue_free()
	peek = null

func _peek_build(id: String, anchor: Control) -> void:
	if is_instance_valid(peek): peek.free()
	snap_all(id)
	peek = PanelContainer.new(); peek.add_theme_stylebox_override("panel", m._box(Color(m._p("menu"), 0.97), m._rad() + 2, m._p("edge"), 1, 18, 8))
	m.add_child(peek)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6); peek.add_child(v)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 6); v.add_child(h)
	var ic := TextureRect.new(); ic.texture = m.app_icon(id); ic.custom_minimum_size = Vector2(18, 18); ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER; h.add_child(ic)
	var t := Label.new(); t.text = _title_of(id); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; t.custom_minimum_size.x = 80; h.add_child(t)
	var cl: Button = m._icon_btn("close", "Circular", 24, 24, 11); cl.tooltip_text = "Fermer la fenêtre"
	cl.pressed.connect(func(): peek_hide(); if m.wins.has(id): m._close_win(id))
	h.add_child(cl)
	var tb := _thumb_box(id, Vector2(200, 120)); tb.mouse_filter = Control.MOUSE_FILTER_STOP
	tb.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: peek_hide(); if m.wins.has(id): m._show(id))
	v.add_child(tb)
	peek.mouse_entered.connect(func(): peek_hover = true); peek.mouse_exited.connect(func(): peek_hover = false; peek_hide_soon())
	peek.size = peek.get_combined_minimum_size()
	var x := anchor.global_position.x + anchor.size.x / 2.0 - peek.size.x / 2.0
	peek.position = Vector2(clampf(x, 8.0, m.size.x - peek.size.x - 8.0), anchor.global_position.y - peek.size.y - 10.0)
	if m.fx.on():
		peek.modulate.a = 0.0; peek.create_tween().tween_property(peek, "modulate:a", 1.0, 0.1)

## Branche l'aperçu sur un bouton (tâche ou dock).
func attach(b: Control, id: String) -> void:
	b.mouse_entered.connect(func(): peek_show(id, b))
	b.mouse_exited.connect(peek_hide_soon)
	if b is BaseButton: (b as BaseButton).pressed.connect(peek_hide)
