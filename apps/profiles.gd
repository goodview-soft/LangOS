extends Control
## Profils d'environnement : liste d'apps + bureau virtuel + disposition (+ fond/thème). Instance sans interface = logique (main.prof) ; avec build() = écran de gestion.
var m
var list: VBoxContainer
var inc_theme: CheckBox
var mode_btn: OptionButton
const MODES := ["Conserver les autres fenêtres", "Réduire les autres fenêtres", "Fermer les autres fenêtres"]

static func defaults() -> Array:
	var P := func(n: String, ids: Array, zones: Array, mode := 0) -> Dictionary:
		var a := []
		for i in ids.size(): a.append({"id": ids[i], "vd": 0, "zone": zones[i]})
		return {"name": n, "apps": a, "mode": mode, "bg": -1, "light": -1}
	return [P.call("Travail", ["chromium", "notepad", "messenger"], ["3l", "3c", "3r"]),
		P.call("Développement", ["terminal", "code", "files"], ["bl", "l", "tr"]),
		P.call("Multimédia", ["music", "files"], ["l", "r"]),
		P.call("Études", ["notepad", "dict", "chromium"], ["3l", "3c", "3r"]),
		P.call("Gaming", ["f_games", "chess"], ["l", "r"])]

func all() -> Array:
	if not m.set_cfg.has("profiles"): m.set_cfg["profiles"] = defaults()
	return m.set_cfg["profiles"]

func find(n: String) -> int:
	for i in all().size(): if str(all()[i]["name"]) == n: return i
	return -1

## Capture l'environnement courant (fenêtres, bureaux, positions en fractions du bureau).
func capture(n: String, theme := false, mode := 0) -> Dictionary:
	var ds: Vector2 = m.desk.size; var a := []
	for id in m.wins:
		var d: Dictionary = m.wins[id]; var w: PanelContainer = d["win"]
		var r := Rect2(w.position, w.size)
		if d["maxed"] and d["saved"].size.x > 0: r = d["saved"]
		a.append({"id": id, "vd": int(d["vd"]), "rect": [r.position.x / ds.x, r.position.y / ds.y, r.size.x / ds.x, r.size.y / ds.y], "max": bool(d["maxed"])})
	var p := {"name": n, "apps": a, "mode": mode, "bg": -1, "light": -1}
	if theme: p["light"] = 1 if m.set_cfg.get("light", false) else 0; p["bg"] = -1 if m.set_cfg.get("wall", false) else int(m.set_cfg["bg"])
	return p

func save_current(n := "", theme := false, mode := 0) -> int:
	if n == "": n = "Profil %d" % (all().size() + 1)
	var p := capture(n, theme, mode)
	var i := find(n)
	if i >= 0: all()[i] = p
	else: all().append(p)
	m._save_settings(); return find(n)

func rename(i: int, n: String) -> void:
	n = n.strip_edges()
	if i >= 0 and i < all().size() and n != "": all()[i]["name"] = n; m._save_settings()

func remove(i: int) -> void:
	if i >= 0 and i < all().size(): all().remove_at(i); m._save_settings()

func reset_defaults() -> void:
	m.set_cfg["profiles"] = defaults(); m._save_settings()

func activate(i: int) -> void:
	if i < 0 or i >= all().size(): return
	var p: Dictionary = all()[i]; var ids := []
	for e in p["apps"]: if m.APPS.has(e["id"]): ids.append(e["id"])
	var mode := int(p.get("mode", 0))
	for id in m.wins.keys():
		if ids.has(id) or mode == 0: continue
		if mode == 2: m._close_win(id)
		elif not m.wins[id]["min"]: m._toggle_win(id)
	if int(p.get("light", -1)) >= 0 and bool(p["light"] == 1) != bool(m.set_cfg.get("light", false)): m._set_light(p["light"] == 1)
	if int(p.get("bg", -1)) >= 0: m._set_gradient(clampi(int(p["bg"]), 0, m.BG_GRADS.size() - 1))
	for e in p["apps"]:
		var id: String = e["id"]
		if not m.APPS.has(id): continue
		var vd := clampi(int(e.get("vd", 0)), 0, 5)
		m.n_vd = maxi(m.n_vd, vd + 1)
		if m.wins.has(id): m._move_to_vd(id, vd)
		else: m.restore_vd = vd; m._open_app(id); m.restore_vd = -1
		if not m.wins.has(id): continue
		var d: Dictionary = m.wins[id]
		if d["min"] or not d["win"].visible: m.wins[id]["min"] = false
		m._goto_vd(vd); m._show(id)
		if d["maxed"]: m._toggle_max(id)
		if e.has("zone"): m._snap(id, e["zone"])
		elif e.has("rect"):
			var r: Array = e["rect"]; var ds: Vector2 = m.desk.size; var w: PanelContainer = d["win"]
			d["snapped"] = false; w.position = Vector2(r[0] * ds.x, r[1] * ds.y); w.size = Vector2(r[2] * ds.x, r[3] * ds.y)
			m._clamp_windows()
			if e.get("max", false): m._toggle_max(id)
	if not p["apps"].is_empty() and m.wins.has(p["apps"][0]["id"]): m._goto_vd(int(m.wins[p["apps"][0]["id"]]["vd"]))
	m._save_layout(); m.notify("Profil activé", str(p["name"]))

# ------------------------------------------------------------------ interface
func build() -> void:
	var mg := MarginContainer.new(); mg.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]: mg.add_theme_constant_override("margin_" + k, 14)
	add_child(mg)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); mg.add_child(v)
	var t := Label.new(); t.text = "Profils d'environnement"; t.add_theme_font_size_override("font_size", 24); v.add_child(t)
	var h := HFlowContainer.new(); h.add_theme_constant_override("h_separation", 8); h.add_theme_constant_override("v_separation", 6); v.add_child(h)
	var sv: Button = m._mk_btn("Enregistrer l'environnement actuel", 0, 42); h.add_child(sv)
	inc_theme = CheckBox.new(); inc_theme.text = "avec fond et thème"; h.add_child(inc_theme)
	mode_btn = OptionButton.new(); for s in MODES: mode_btn.add_item(s)
	h.add_child(mode_btn)
	sv.pressed.connect(func(): save_current("", inc_theme.button_pressed, mode_btn.selected); _fill())
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; v.add_child(sc)
	list = VBoxContainer.new(); list.add_theme_constant_override("separation", 8); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(list)
	var rs: Button = m._mk_btn("Restaurer les profils par défaut", 0, 38); rs.pressed.connect(func(): reset_defaults(); _fill()); v.add_child(rs)
	_fill()

func _fill() -> void:
	for c in list.get_children(): list.remove_child(c); c.queue_free()
	for i in all().size():
		var p: Dictionary = all()[i]
		var card := PanelContainer.new(); card.add_theme_stylebox_override("panel", m._box(m._p("field"), 10, m._p("edge"), 1, 0, 10)); list.add_child(card)
		var cv := VBoxContainer.new(); cv.add_theme_constant_override("separation", 6); card.add_child(cv)
		var r := HBoxContainer.new(); r.add_theme_constant_override("separation", 6); cv.add_child(r)
		var le := LineEdit.new(); le.text = str(p["name"]); le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.text_submitted.connect(func(s): rename(i, s)); le.focus_exited.connect(func(): rename(i, le.text)); r.add_child(le)
		var ba: Button = m._mk_btn("Activer", 0, 38); ba.pressed.connect(func(): activate(i)); r.add_child(ba)
		var bd: Button = m._mk_btn("Supprimer", 0, 38); bd.pressed.connect(func(): remove(i); _fill()); r.add_child(bd)
		var names := []
		for e in p["apps"]: if m.APPS.has(e["id"]): names.append("%s (%d)" % [m.APPS[e["id"]][0], int(e.get("vd", 0)) + 1])
		var l: Label = m._mlbl(", ".join(names) + "  ·  " + MODES[clampi(int(p.get("mode", 0)), 0, 2)], 14); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; cv.add_child(l)
