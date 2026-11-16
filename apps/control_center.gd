extends Node
const UI = preload("res://apps/ui.gd")
## Control Center : panneau rapide depuis la barre (volume, luminosité si disponibles, thème, animations, bureaux, batterie).
var m
var panel: PanelContainer
var catcher: Control

func is_open() -> bool: return panel != null and is_instance_valid(panel)

func toggle(anchor: Control) -> void:
	if is_open(): close(); return
	catcher = Control.new(); catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: close())
	m.add_child(catcher)
	var pb_: StyleBoxFlat = m._menu_box(); pb_.set_content_margin_all(UI.S3)
	panel = PanelContainer.new(); panel.add_theme_stylebox_override("panel", pb_)
	m.add_child(panel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", UI.S3); panel.add_child(v)
	v.add_child(UI.heading("Centre de contrôle"))
	var vol := volume()
	if vol >= 0: v.add_child(_slider("volume-2", "Volume", vol, func(x: float): OS.create_process("pactl", ["set-sink-volume", "@DEFAULT_SINK@", "%d%%" % int(x)])))
	var br := brightness()
	if br >= 0: v.add_child(_slider("sun", "Luminosité", br, func(x: float): OS.create_process("brightnessctl", ["set", "%d%%" % int(x)])))
	var tg := HBoxContainer.new(); tg.add_theme_constant_override("separation", UI.S2); v.add_child(tg)
	var light: bool = m.set_cfg.get("light", false)
	var b1: Button = m._mk_btn("Thème sombre" if light else "Thème clair", 0, 42); b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.set_icon(b1, "moon" if light else "sun")
	b1.pressed.connect(func(): m._set_light(not bool(m.set_cfg.get("light", false))); close()); tg.add_child(b1)
	var b2: Button = m._mk_btn("Animations", 0, 42); b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b2.tooltip_text = "Activer ou couper les animations"
	UI.set_icon(b2, "sparkles"); b2.theme_type_variation = "Accent" if m.fx.on() else ""
	b2.pressed.connect(func(): m.fx.set_anim(not m.fx.on()); b2.theme_type_variation = "Accent" if m.fx.on() else ""); tg.add_child(b2)
	v.add_child(UI.small("Bureaux"))
	var vd := HBoxContainer.new(); vd.add_theme_constant_override("separation", UI.S2); v.add_child(vd)
	for i in m.n_vd:
		var b: Button = m._mk_btn(str(i + 1), 42, UI.TOUCH)
		if i == m.cur_vd: b.theme_type_variation = "Accent"
		b.pressed.connect(func(): m._goto_vd(i); close())
		vd.add_child(b)
	v.add_child(UI.small("Profils"))
	var pf := HFlowContainer.new(); pf.add_theme_constant_override("h_separation", UI.S2); pf.add_theme_constant_override("v_separation", UI.S2); v.add_child(pf)
	for i in m.prof.all().size():
		var pb: Button = m._mk_btn(str(m.prof.all()[i]["name"]), 0, UI.TOUCH); pb.pressed.connect(func(): close(); m.prof.activate(i)); pf.add_child(pb)
	var tray = m.tray_node
	if tray != null and int(tray.batt) >= 0:
		var bl := HBoxContainer.new(); bl.add_theme_constant_override("separation", UI.S2); v.add_child(bl)
		bl.add_child(UI.icon_rect("battery", 16, true)); bl.add_child(UI.small("Batterie : %d %%%s" % [int(tray.batt), " (en charge)" if tray.charging else ""]))
	panel.size = panel.get_combined_minimum_size()
	panel.size.x = maxf(panel.size.x, 300.0)
	var x := clampf(anchor.global_position.x + anchor.size.x - panel.size.x, 8.0, m.size.x - panel.size.x - 8.0)
	panel.position = Vector2(x, m.size.y - m.bar_h - panel.size.y - 10.0)
	m.fx.popup_in(panel, true)

func close() -> void:
	if is_instance_valid(panel): panel.queue_free()
	if is_instance_valid(catcher): catcher.queue_free()

func _slider(icon_name: String, label: String, val: float, cb: Callable) -> Control:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", UI.S3)
	var ic := UI.icon_rect(icon_name, 16); ic.tooltip_text = label; ic.mouse_filter = Control.MOUSE_FILTER_PASS; h.add_child(ic)
	var s := HSlider.new(); s.min_value = 0; s.max_value = 100; s.step = 1; s.value = val; s.focus_mode = Control.FOCUS_NONE; s.tooltip_text = label
	s.custom_minimum_size = Vector2(200, UI.tp(30)); s.size_flags_horizontal = Control.SIZE_EXPAND_FILL; s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(cb); h.add_child(s); return h

## Volume en % (Linux, PulseAudio/PipeWire) ou -1 si indisponible (le curseur est alors masqué).
func volume() -> float:
	if OS.get_name() == "Android": return -1.0
	var out := []
	if OS.execute("pactl", ["get-sink-volume", "@DEFAULT_SINK@"], out, true) != 0 or out.is_empty(): return -1.0
	var r := RegEx.new(); r.compile("(\\d+)%")
	var mt := r.search(str(out[0]))
	return float(mt.get_string(1)) if mt else -1.0

func brightness() -> float:
	if OS.get_name() == "Android": return -1.0
	var out := []
	if OS.execute("brightnessctl", ["-m"], out, true) != 0 or out.is_empty(): return -1.0
	var parts := str(out[0]).strip_edges().split(",")
	return float(parts[3].trim_suffix("%")) if parts.size() > 3 else -1.0
