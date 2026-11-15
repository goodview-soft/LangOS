extends Node
## Look & fluidité : animations (désactivables), aperçu d'ancrage, réglages d'apparence en direct.
## Branché depuis main.gd (variable « fx »). Aucun relayout pendant les déplacements : seulement des tweens sur scale/modulate.

var m                    # main.gd
var prev: Panel          # rectangle d'aperçu de l'ancrage
var prev_zone := ""
var pend := false
const ACCENTS := ["5aa2ff", "7c5cff", "2ec4b6", "3ddc84", "ffb02e", "ff5c7a"]

func on() -> bool:
	return bool(m.set_cfg.get("anim", true))

# ---------------------------------------------------------------- Zones d'ancrage (fonctions pures, testables)
## Zone visée quand le pointeur p est près d'un bord du bureau de taille s ; "" si loin des bords.
static func zone_at(p: Vector2, s: Vector2) -> String:
	var e := 12.0; var c := minf(80.0, s.y / 4.0)
	var l := p.x <= e; var r := p.x >= s.x - e; var t := p.y <= e; var b := p.y >= s.y - e
	if not (l or r or t or b): return ""
	var side := "l" if p.x < s.x / 2.0 else "r"
	if t:
		if l or r or p.x <= c or p.x >= s.x - c: return "t" + side
		return "max"
	if l or r:
		if p.y <= c: return "t" + side
		if p.y >= s.y - c: return "b" + side
		return side
	if s.x >= 900.0:
		return "3l" if p.x < s.x / 3.0 else ("3r" if p.x > 2.0 * s.x / 3.0 else "3c")
	return "b"

static func zone_rect(z: String, s: Vector2) -> Rect2:
	var h := s / 2.0; var t := s.x / 3.0
	return {"max": Rect2(Vector2.ZERO, s), "l": Rect2(0, 0, h.x, s.y), "r": Rect2(h.x, 0, h.x, s.y), "t": Rect2(0, 0, s.x, h.y), "b": Rect2(0, h.y, s.x, h.y),
		"tl": Rect2(0, 0, h.x, h.y), "tr": Rect2(h.x, 0, h.x, h.y), "bl": Rect2(0, h.y, h.x, h.y), "br": Rect2(h.x, h.y, h.x, h.y),
		"3l": Rect2(0, 0, t, s.y), "3c": Rect2(t, 0, t, s.y), "3r": Rect2(2 * t, 0, t, s.y)}.get(z, Rect2())

func show_preview(z: String) -> void:
	if z == "": hide_preview(); return
	if z == prev_zone and prev != null and prev.visible: return
	var r := zone_rect(z, m.desk.size).grow(-6.0)
	if prev == null or not is_instance_valid(prev):
		prev = Panel.new(); prev.mouse_filter = Control.MOUSE_FILTER_IGNORE; m.desk.add_child(prev)
	var st: StyleBoxFlat = m._box(Color(m.ACCENT, 0.22), m._rad() + 2, Color(m.ACCENT, 0.85), 2)
	prev.add_theme_stylebox_override("panel", st)
	var was := prev.visible
	prev.visible = true; m.desk.move_child(prev, -1); prev_zone = z
	if on() and was:
		var tw := prev.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(prev, "position", r.position, 0.1); tw.tween_property(prev, "size", r.size, 0.1)
	else:
		prev.position = r.position; prev.size = r.size
		if on(): prev.modulate.a = 0.0; prev.create_tween().tween_property(prev, "modulate:a", 1.0, 0.1)
		else: prev.modulate.a = 1.0

func hide_preview() -> void:
	prev_zone = ""
	if prev != null and is_instance_valid(prev): prev.visible = false

# ---------------------------------------------------------------- Animations de fenêtre
func open_win(w: Control) -> void:
	w.scale = Vector2.ONE; w.modulate.a = 1.0
	if not on(): return
	w.pivot_offset = w.size / 2.0; w.scale = Vector2(0.94, 0.94); w.modulate.a = 0.0
	var tw := w.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(w, "scale", Vector2.ONE, 0.18); tw.tween_property(w, "modulate:a", 1.0, 0.16)

func close_win(w: Control) -> void:
	if not on() or not w.visible: w.queue_free(); return
	w.pivot_offset = w.size / 2.0
	var tw := w.create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(w, "scale", Vector2(0.92, 0.92), 0.12); tw.tween_property(w, "modulate:a", 0.0, 0.12)
	tw.chain().tween_callback(w.queue_free)

## Remet une fenêtre en état normal (annule une réduction ou un glissement en cours).
func reset_win(d: Dictionary) -> void:
	var tw = d.get("tw")
	if tw is Tween and tw.is_valid(): tw.kill()
	d.erase("tw")
	var w: Control = d["win"]
	w.scale = Vector2.ONE; w.modulate.a = 1.0
	if d.has("fx_pos"): w.position = d["fx_pos"]; d.erase("fx_pos")

func minimize(id: String) -> void:
	var d: Dictionary = m.wins[id]; var w: Control = d["win"]
	if not on(): w.visible = false; return
	reset_win(d)
	var target: Vector2 = d["task"].global_position + d["task"].size / 2.0
	if m.dock != null and m.dock.visible:
		var c = m.dock.center_of(id)
		if c != null: target = c
	target -= m.desk.global_position
	d["fx_pos"] = w.position
	w.pivot_offset = w.size / 2.0
	var tw := w.create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(w, "scale", Vector2(0.2, 0.2), 0.18); tw.tween_property(w, "modulate:a", 0.0, 0.18)
	tw.tween_property(w, "position", target - w.size / 2.0, 0.18)
	tw.chain().tween_callback(func():
		if is_instance_valid(w) and m.wins.has(id) and m.wins[id]["min"]: w.visible = false
		if is_instance_valid(w): d.erase("tw"); reset_win(d))
	d["tw"] = tw

func popup_in(c: Control, up: bool) -> void:
	if not on(): return
	c.pivot_offset = Vector2(0, c.size.y if up else 0.0); c.scale = Vector2(0.96, 0.88); c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(c, "scale", Vector2.ONE, 0.13); tw.tween_property(c, "modulate:a", 1.0, 0.1)

func hover(c: Control, over: bool, amount := 1.08) -> void:
	if not on():
		c.scale = Vector2.ONE; return
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween(); tw.tween_property(c, "scale", Vector2(amount, amount) if over else Vector2.ONE, 0.1).set_ease(Tween.EASE_OUT)

## Transition latérale entre bureaux virtuels : les fenêtres du nouveau bureau glissent depuis le côté.
func vd_slide(dir: int) -> void:
	if not on() or dir == 0: return
	for id in m.wins:
		var d: Dictionary = m.wins[id]; var w: Control = d["win"]
		if not w.visible: continue
		reset_win(d)
		var end: Vector2 = w.position
		d["fx_pos"] = end
		w.position = end + Vector2(70.0 * dir, 0); w.modulate.a = 0.0
		var tw := w.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(w, "position", end, 0.22); tw.tween_property(w, "modulate:a", 1.0, 0.2)
		tw.chain().tween_callback(func(): d.erase("fx_pos"); d.erase("tw"))
		d["tw"] = tw

# ---------------------------------------------------------------- Réglages d'apparence (persistés, appliqués en direct)
func queue_apply() -> void:
	if pend: return
	pend = true; _apply.call_deferred()

func _apply() -> void:
	pend = false; m._restyle()

func set_accent(c: Color) -> void:
	m.ACCENT = c; m.set_cfg["accent"] = c.to_html(false); m._save_settings(); queue_apply()

func set_anim(b: bool) -> void:
	m.set_cfg["anim"] = b; m._save_settings()

func set_opt(key: String, v) -> void:
	m.set_cfg[key] = v; m._save_settings(); queue_apply()

func appearance_card(page: Control) -> void:
	var c: VBoxContainer = m._s_card(page, "Apparence")
	var sw := HFlowContainer.new(); sw.add_theme_constant_override("h_separation", 8); sw.add_theme_constant_override("v_separation", 8)
	for h in ACCENTS:
		var b: Button = m._mk_btn("", 36, 36)
		for s in ["normal", "hover", "pressed"]: b.add_theme_stylebox_override(s, m._box(Color(h), 18, Color(1, 1, 1, 0.5 if s != "normal" else 0.0), 2))
		b.pressed.connect(func(): set_accent(Color(h)))
		sw.add_child(b)
	var cp := ColorPickerButton.new(); cp.custom_minimum_size = Vector2(56, 36); cp.color = m.ACCENT; cp.edit_alpha = false; cp.focus_mode = Control.FOCUS_NONE
	cp.color_changed.connect(set_accent); sw.add_child(cp)
	m._s_row(c, "Couleur d'accent", sw, 200)
	m._s_row(c, "Transparence fenêtres", m._s_slider(0.6, 1.0, 0.02, float(m.set_cfg.get("wtrans", 1.0)), func(x: float, l: Label): l.text = "%d %%" % int(x * 100); set_opt("wtrans", x)))
	m._s_row(c, "Taille des icônes", m._s_slider(40, 80, 2, float(m.set_cfg.get("isize", 56)), func(x: float, l: Label): l.text = "%d" % int(x); set_opt("isize", int(x))))
	m._s_row(c, "Rayon des coins", m._s_slider(0, 24, 1, float(m.set_cfg.get("radius", 12)), func(x: float, l: Label): l.text = "%d" % int(x); set_opt("radius", int(x))))
	var an := CheckButton.new(); an.focus_mode = Control.FOCUS_NONE; an.button_pressed = on(); an.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	an.toggled.connect(set_anim); m._s_row(c, "Animations", an, 60)
	var dh := CheckButton.new(); dh.focus_mode = Control.FOCUS_NONE; dh.button_pressed = bool(m.set_cfg.get("dock_hide", false)); dh.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	dh.toggled.connect(func(b: bool): set_opt("dock_hide", b)); m._s_row(c, "Masquer le dock auto", dh, 60)
