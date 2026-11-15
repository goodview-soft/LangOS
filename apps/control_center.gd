extends Node
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
	panel = PanelContainer.new(); panel.add_theme_stylebox_override("panel", m._box(m._p("menu"), m._rad() + 4, m._p("edge"), 1, 22, 14))
	m.add_child(panel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); panel.add_child(v)
	var t := Label.new(); t.text = "Centre de contrôle"; t.add_theme_font_size_override("font_size", 18); v.add_child(t)
	var vol := volume()
	if vol >= 0: v.add_child(_slider("Volume", vol, func(x: float): OS.create_process("pactl", ["set-sink-volume", "@DEFAULT_SINK@", "%d%%" % int(x)])))
	var br := brightness()
	if br >= 0: v.add_child(_slider("Luminosité", br, func(x: float): OS.create_process("brightnessctl", ["set", "%d%%" % int(x)])))
	var tg := HBoxContainer.new(); tg.add_theme_constant_override("separation", 8); v.add_child(tg)
	var light: bool = m.set_cfg.get("light", false)
	var b1: Button = m._mk_btn("Thème sombre" if light else "Thème clair", 0, 42); b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b1.pressed.connect(func(): m._set_light(not bool(m.set_cfg.get("light", false))); close()); tg.add_child(b1)
	var b2: Button = m._mk_btn("Animations : " + ("oui" if m.fx.on() else "non"), 0, 42); b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b2.pressed.connect(func(): m.fx.set_anim(not m.fx.on()); b2.text = "Animations : " + ("oui" if m.fx.on() else "non")); tg.add_child(b2)
	var dl := Label.new(); dl.text = "Bureaux"; dl.add_theme_font_size_override("font_size", 14); v.add_child(dl)
	var vd := HBoxContainer.new(); vd.add_theme_constant_override("separation", 6); v.add_child(vd)
	for i in m.n_vd:
		var b: Button = m._mk_btn(str(i + 1), 44, 38)
		if i == m.cur_vd: b.modulate = m.ACCENT.lightened(0.3)
		b.pressed.connect(func(): m._goto_vd(i); close())
		vd.add_child(b)
	var pl := Label.new(); pl.text = "Profils"; pl.add_theme_font_size_override("font_size", 14); v.add_child(pl)
	var pf := HFlowContainer.new(); pf.add_theme_constant_override("h_separation", 6); pf.add_theme_constant_override("v_separation", 6); v.add_child(pf)
	for i in m.prof.all().size():
		var pb: Button = m._mk_btn(str(m.prof.all()[i]["name"]), 0, 36); pb.pressed.connect(func(): close(); m.prof.activate(i)); pf.add_child(pb)
	var tray = m.tray_node
	if tray != null and int(tray.batt) >= 0:
		var bl := Label.new(); bl.text = "Batterie : %d %%%s" % [int(tray.batt), " (en charge)" if tray.charging else ""]; v.add_child(bl)
	panel.size = panel.get_combined_minimum_size()
	panel.size.x = maxf(panel.size.x, 300.0)
	var x := clampf(anchor.global_position.x + anchor.size.x - panel.size.x, 8.0, m.size.x - panel.size.x - 8.0)
	panel.position = Vector2(x, m.size.y - m.bar_h - panel.size.y - 10.0)
	m.fx.popup_in(panel, true)

func close() -> void:
	if is_instance_valid(panel): panel.queue_free()
	if is_instance_valid(catcher): catcher.queue_free()

func _slider(label: String, val: float, cb: Callable) -> Control:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10)
	var l := Label.new(); l.text = label; l.custom_minimum_size.x = 90; h.add_child(l)
	var s := HSlider.new(); s.min_value = 0; s.max_value = 100; s.step = 1; s.value = val; s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(160, 30); s.size_flags_horizontal = Control.SIZE_EXPAND_FILL; s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
