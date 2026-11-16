extends PanelContainer
## Dock flottant en bas (bureau seulement, écran >= 700 px) : favoris épinglés + apps ouvertes avec point d'activité.
## Remplace visuellement la liste de la barre des tâches (task_box est masquée, les boutons existent toujours).

var m
var box: HBoxContainer
var items := {}          # id -> Button
var shown := true
var _was_empty := true
const DEFAULT_PINS := ["notepad", "settings", "calc", "music"]

func setup(main) -> void:
	m = main
	box = HBoxContainer.new(); box.add_theme_constant_override("separation", 6); add_child(box)
	m.resized.connect(refresh)
	refresh()

func enabled() -> bool:
	return OS.get_name() != "Android" and m.size.x >= 700.0 and not m.immersive

func pins() -> Array:
	var p = m.set_cfg.get("pins", DEFAULT_PINS)
	return (p if p is Array else DEFAULT_PINS).filter(func(k): return m.APPS.has(k) and m.installed(k))

## Identifiants affichés : épinglés d'abord, puis apps ouvertes non épinglées.
func ids() -> Array:
	var r := pins()
	for k in m.wins:
		if not r.has(k): r.append(k)
	return r

func refresh() -> void:
	if m == null or not is_instance_valid(box): return
	var on: bool = enabled()
	visible = on; m.task_box.visible = not on
	set_process(on and bool(m.set_cfg.get("dock_hide", false)))
	if not on: return
	add_theme_stylebox_override("panel", m._box(Color(m._p("menu"), 0.9), m._rad() + 9, m._p("edge"), 1, 18, 6))
	for c in box.get_children():
		box.remove_child(c); c.queue_free()
	items.clear()
	var s := int(float(m.set_cfg.get("isize", 56)) * 0.8)
	for id in ids():
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 1)
		var b: Button = m._mk_btn("", s + 10, s + 10); b.theme_type_variation = "Nav"
		b.icon = m.app_icon(id); b.add_theme_constant_override("icon_max_width", s)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for k in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]: b.add_theme_color_override(k, Color.WHITE)
		b.tooltip_text = m.APPS[id][0]
		b.pressed.connect(_click.bind(id))
		b.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT: _menu(id, b))
		b.mouse_entered.connect(func(): m.fx.hover(b, true, 1.15)); b.mouse_exited.connect(func(): m.fx.hover(b, false))
		if m.overview != null: m.overview.attach(b, id)
		v.add_child(b)
		var cc := CenterContainer.new(); cc.custom_minimum_size.y = 5; v.add_child(cc)
		var dot := Panel.new(); dot.custom_minimum_size = Vector2(14 if m.active == id else 5, 4); dot.visible = m.wins.has(id)
		dot.add_theme_stylebox_override("panel", m._box(m.ACCENT if m.active == id else Color(m._p("text"), 0.6), 2))
		cc.add_child(dot)
		box.add_child(v); items[id] = b
	place(true)

func _click(id: String) -> void:
	if m.wins.has(id):
		var w: Control = m.wins[id]["win"]
		if m.active == id and w.visible: m._toggle_win(id)
		elif w.visible: m._show(id)
		else: m._toggle_win(id)
	else: m._open_app(id)

func _menu(id: String, b: Control) -> void:
	var it := []
	it.append(["Désépingler" if pins().has(id) else "Épingler", func(): toggle_pin(id)])
	if m.wins.has(id): it.append(["Fermer", func(): m._close_win(id)])
	m._popup_menu(it, Vector2(b.global_position.x, b.global_position.y - 8.0), true)

func toggle_pin(id: String) -> void:
	var p := pins()
	if p.has(id): p.erase(id)
	else: p.append(id)
	m.set_cfg["pins"] = p; m._save_settings(); refresh()

func center_of(id: String):
	return (items[id].global_position + items[id].size / 2.0) if items.has(id) else null

func place(instant := false) -> void:
	size = get_combined_minimum_size()
	var x: float = (m.size.x - size.x) / 2.0
	var hide_it: bool = bool(m.set_cfg.get("dock_hide", false)) and not shown and not _desk_empty()
	var y: float = m.size.y + 10.0 if hide_it else m.size.y - m.bar_h - size.y - 10.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE if hide_it else Control.MOUSE_FILTER_STOP
	if instant or not m.fx.on():
		position = Vector2(x, y); modulate.a = 0.0 if hide_it else 1.0; return
	var tw := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "position", Vector2(x, y), 0.18); tw.tween_property(self, "modulate:a", 0.0 if hide_it else 1.0, 0.18)

## Vrai quand aucune fenêtre n'est visible : le dock reste alors affiché sur le bureau (il ne gêne ni jeu ni appli).
func _desk_empty() -> bool:
	for id in m.wins:
		var w: Control = m.wins[id]["win"]
		if is_instance_valid(w) and w.visible and not m.wins[id].get("min", false): return false
	return true

## Masquage automatique : le dock réapparaît quand le pointeur touche le bas de l'écran.
func _process(_d: float) -> void:
	var my: float = m.get_global_mouse_position().y
	var want: bool = my >= m.size.y - m.bar_h - 14.0 if not shown else my >= m.size.y - m.bar_h - size.y - 40.0
	var empty := _desk_empty()
	if want != shown or empty != _was_empty:
		shown = want; _was_empty = empty; place()
