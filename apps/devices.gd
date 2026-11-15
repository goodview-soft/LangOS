extends Control
const UI = preload("res://apps/ui.gd")
## Périphériques et raccourcis : écrans, manettes (test en direct), audio, clavier/souris, disques, imprimantes, performances, raccourcis clavier.
## Les sections indisponibles (Android, pas de /proc, pas de lpstat…) sont masquées. Les fonctions statiques servent aussi aux tests.
var m
var tabs: HBoxContainer
var body: VBoxContainer
var tab := "screens"
var live: Callable                    # mise à jour 1 fois par seconde de l'onglet courant
var hist_cpu: Array = []
var hist_tmp: Array = []
var prev_cpu: Array = []
var has_lp := false
const PAD_BTN := [["X", 2], ["Y", 3], ["Retour", 4], ["Start", 6], ["L1", 9], ["R1", 10]]
const BTN_NAMES := ["A", "B", "X", "Y", "Retour", "Guide", "Start", "L3", "R3", "L1", "R1", "Haut", "Bas", "Gauche", "Droite"]

# ------------------------------------------------------------------ lecture système (statique, testable)
static func rd(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null: return ""
	var s := ""
	while not f.eof_reached(): s += f.get_line() + "\n"
	return s

## /proc/mounts -> [{dev, mp, fs, removable}] : seulement les vrais disques (hors loop / squashfs / snap).
static func parse_mounts(t: String) -> Array:
	var out := []
	for l in t.split("\n"):
		var p := l.strip_edges().split(" ")
		if p.size() < 3 or not p[0].begins_with("/dev/") or p[0].begins_with("/dev/loop") or p[2] in ["squashfs", "swap"]: continue
		var mp: String = p[1].replace("\\040", " ")
		if mp.begins_with("/snap") or mp.begins_with("/boot") or mp.begins_with("/var/lib"): continue
		out.append({"dev": p[0], "mp": mp, "fs": p[2], "removable": mp.begins_with("/media") or mp.begins_with("/run/media")})
	return out

## /proc/bus/input/devices -> {"kbd": [noms], "mouse": [noms]}
static func parse_input(t: String) -> Dictionary:
	var r := {"kbd": [], "mouse": []}
	for blk in t.split("\n\n"):
		var name := ""; var h := ""
		for l in blk.split("\n"):
			if l.begins_with("N: Name="): name = l.substr(8).strip_edges().trim_prefix("\"").trim_suffix("\"")
			elif l.begins_with("H: Handlers="): h = l.substr(12)
		if name == "": continue
		if h.contains("mouse"): r["mouse"].append(name)
		elif h.contains("kbd") and not name.contains("Button") and not name.contains("Power") and not name.contains("Switch"): r["kbd"].append(name)
	return r

## /proc/stat -> [oisif, total] (premier « cpu »).
static func cpu_sample() -> Array:
	var l := rd("/proc/stat").split("\n")[0].split(" ", false)
	if l.size() < 5 or l[0] != "cpu": return []
	var tot := 0
	for i in range(1, mini(l.size(), 9)): tot += int(l[i])
	return [int(l[4]) + (int(l[5]) if l.size() > 5 else 0), tot]

static func cpu_pct(a: Array, b: Array) -> float:
	if a.size() < 2 or b.size() < 2 or b[1] <= a[1]: return 0.0
	return clampf(100.0 * (1.0 - float(b[0] - a[0]) / float(b[1] - a[1])), 0.0, 100.0)

## /proc/meminfo -> {"total": Ko, "avail": Ko} (vide si indisponible).
static func mem_info() -> Dictionary:
	var d := {}
	for l in rd("/proc/meminfo").split("\n"):
		if l.begins_with("MemTotal:"): d["total"] = int(l.split(" ", false)[1])
		elif l.begins_with("MemAvailable:"): d["avail"] = int(l.split(" ", false)[1])
	return d

## Température la plus élevée des zones thermiques (°C) ou -1.
static func temp() -> float:
	var best := -1.0
	for z in DirAccess.get_directories_at("/sys/class/thermal"):
		if z.begins_with("thermal_zone"):
			var t := rd("/sys/class/thermal/" + z + "/temp").strip_edges()
			if t.is_valid_int(): best = maxf(best, float(t.to_int()) / 1000.0)
	return best

static func sh(cmd: String, args: Array) -> Array:
	if OS.get_name() == "Android": return []
	var out := []
	if OS.execute(cmd, args, out, true) != 0 or out.is_empty(): return []
	return str(out[0]).strip_edges().split("\n")

# ------------------------------------------------------------------ interface
func _ready() -> void:
	has_lp = not sh("lpstat", ["-p"]).is_empty() if OS.get_name() == "Linux" else false
	var t := Timer.new(); t.wait_time = 1.0; t.autostart = true; t.timeout.connect(func(): if live.is_valid(): live.call()); add_child(t)

func build() -> void:
	var v := VBoxContainer.new(); v.set_anchors_preset(Control.PRESET_FULL_RECT); v.add_theme_constant_override("separation", 8); add_child(v)
	tabs = HBoxContainer.new(); var ts := ScrollContainer.new(); ts.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; ts.custom_minimum_size.y = 46
	tabs.add_theme_constant_override("separation", 6); ts.add_child(tabs); v.add_child(ts)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; v.add_child(sc)
	body = VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 8); sc.add_child(body)
	var linux := OS.get_name() == "Linux"
	var list := [["screens", "Écrans"], ["pads", "Manettes"], ["audio", "Audio"]]
	if linux and rd("/proc/bus/input/devices") != "": list.append(["input", "Clavier / souris"])
	if linux: list.append(["disks", "Disques"])
	if has_lp: list.append(["print", "Imprimantes"])
	list.append(["perf", "Performances"]); list.append(["keys", "Raccourcis"])
	for e in list:
		var b: Button = m._mk_btn(e[1], 0, 40); b.name = e[0]; b.pressed.connect(show_tab.bind(e[0])); tabs.add_child(b)
	show_tab(tab)

func show_tab(t: String) -> void:
	tab = t; live = Callable()
	for b in tabs.get_children(): b.modulate = m.ACCENT.lightened(0.3) if b.name == t else Color.WHITE
	for c in body.get_children(): c.queue_free()
	call("_t_" + t)

func _lbl(t: String, sz := 15, dim := false) -> Label:
	var l := Label.new(); l.text = t; l.add_theme_font_size_override("font_size", sz); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if dim: l.theme_type_variation = "Muted"
	body.add_child(l); return l

func _card() -> VBoxContainer:
	var pc := PanelContainer.new(); pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = m._box(m._p("field"), 12, m._p("edge"), 1); sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb); body.add_child(pc)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 4); pc.add_child(v); return v

func _line(c: Control, t: String, dim := false) -> Label:
	var l := Label.new(); l.text = t; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if dim: l.theme_type_variation = "Muted"
	c.add_child(l); return l

# --- Écrans
func _t_screens() -> void:
	var cur := DisplayServer.window_get_current_screen()
	for i in DisplayServer.get_screen_count():
		var c := _card(); var sz := DisplayServer.screen_get_size(i); var hz := DisplayServer.screen_get_refresh_rate(i)
		_line(c, "Écran %d%s" % [i + 1, "  (fenêtre ici)" if i == cur else ""])
		_line(c, "%d x %d px%s, échelle %.1f" % [sz.x, sz.y, (", %.0f Hz" % hz) if hz > 0 else "", DisplayServer.screen_get_scale(i)], true)
		if DisplayServer.get_screen_count() > 1 and i != cur:
			var b: Button = m._mk_btn("Placer la fenêtre ici", 0, 40); b.pressed.connect(func(): DisplayServer.window_set_current_screen(i); show_tab("screens")); c.add_child(b)

# --- Manettes (test en direct)
func _t_pads() -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty(): _lbl("Aucune manette connectée. Branchez-en une : elle apparaît ici.", 15, true); return
	var rows := []
	for id in pads:
		var c := _card(); _line(c, "%s (n° %d)" % [Input.get_joy_name(id), id])
		var bl := _line(c, "", true); var al := _line(c, "", true); rows.append([id, bl, al])
	live = func():
		for r in rows:
			var down := []
			for b in 15: if Input.is_joy_button_pressed(r[0], b): down.append(BTN_NAMES[b])
			r[1].text = "Boutons : " + (", ".join(down) if not down.is_empty() else "-")
			var ax := []
			for a in 6: ax.append("%d: %+.2f" % [a, Input.get_joy_axis(r[0], a)])
			r[2].text = "Axes  " + "   ".join(ax)
	live.call()

# --- Audio
func _t_audio() -> void:
	var c := _card(); _line(c, "Sorties (moteur de LangOS)")
	var oc := OptionButton.new(); oc.focus_mode = Control.FOCUS_NONE
	var outs := AudioServer.get_output_device_list()
	for i in outs.size(): oc.add_item(outs[i]); if outs[i] == AudioServer.output_device: oc.select(i)
	oc.item_selected.connect(func(i): AudioServer.output_device = outs[i]); c.add_child(oc)
	var ins := AudioServer.get_input_device_list()
	var c2 := _card(); _line(c2, "Entrées détectées")
	for n in ins: _line(c2, str(n), true)
	if ins.is_empty(): _line(c2, "Aucune", true)
	var sk := sh("pactl", ["list", "short", "sinks"])
	if not sk.is_empty():
		var c3 := _card(); _line(c3, "Sorties du système (pactl)")
		for l in sk: _line(c3, str(l.split("\t")[1]) if l.contains("\t") else l, true)
		var so := sh("pactl", ["list", "short", "sources"]).filter(func(l): return not l.contains(".monitor"))
		for l in so: _line(c3, "Entrée : " + (str(l.split("\t")[1]) if l.contains("\t") else l), true)

# --- Clavier / souris
func _t_input() -> void:
	var d := parse_input(rd("/proc/bus/input/devices"))
	var c := _card(); _line(c, "Claviers")
	for n in d["kbd"]: _line(c, str(n), true)
	var c2 := _card(); _line(c2, "Souris et pavés tactiles")
	for n in d["mouse"]: _line(c2, str(n), true)

# --- Disques et clés USB
func _t_disks() -> void:
	var mounts := parse_mounts(rd("/proc/mounts"))
	if mounts.is_empty(): _lbl("Aucun disque monté détecté.", 15, true)
	for e in mounts:
		var c := _card(); _line(c, ("Clé / disque externe : " if e["removable"] else "Disque : ") + str(e["mp"]))
		var free := ""
		var da := DirAccess.open(str(e["mp"]))
		if da != null and da.get_space_left() > 0: free = ", %.1f Go libres" % (da.get_space_left() / 1073741824.0)
		_line(c, "%s, %s%s" % [e["dev"], e["fs"], free], true)
		var b: Button = m._mk_btn("Ouvrir dans Fichiers", 0, 40); b.pressed.connect(open_in_files.bind(str(e["mp"]))); c.add_child(b)

func open_in_files(p: String) -> void:
	m._open_app("files")
	for n in m.wins["files"]["win"].find_children("*", "Control", true, false):
		if n.has_method("_go"): n._go(p); break

# --- Imprimantes
func _t_print() -> void:
	var l := sh("lpstat", ["-p"])
	if l.is_empty(): _lbl("Aucune imprimante.", 15, true)
	var c := _card()
	for x in l: _line(c, str(x), true)

# --- Performances
func _t_perf() -> void:
	var c := _card(); var l1 := _line(c, ""); var l2 := _line(c, ""); var l3 := _line(c, "")
	var g := Control.new(); g.custom_minimum_size = Vector2(0, 110); g.size_flags_horizontal = Control.SIZE_EXPAND_FILL; c.add_child(g)
	g.draw.connect(func():
		g.draw_rect(Rect2(Vector2.ZERO, g.size), Color(0, 0, 0, 0.15))
		for pair in [[hist_cpu, m.ACCENT, 100.0], [hist_tmp, UI.warn(), 100.0]]:
			var pts := PackedVector2Array(); var h: Array = pair[0]
			for i in h.size(): pts.append(Vector2(g.size.x * i / 59.0, g.size.y * (1.0 - clampf(float(h[i]) / pair[2], 0, 1))))
			if pts.size() > 1: g.draw_polyline(pts, pair[1], 2.0, true))
	_line(c, "Courbes : CPU (accent), température (jaune, 0 à 100 °C)", true)
	var tray = m.tray_node
	if tray != null:
		var c2 := _card()
		_line(c2, "Batterie : " + (("%d %%%s" % [int(tray.batt), " (en charge)" if tray.charging else ""]) if int(tray.batt) >= 0 else "aucune"))
		_line(c2, "Réseau : " + {"wifi": "Wi-Fi", "cell": "Mobile", "eth": "Filaire", "none": "déconnecté"}.get(str(tray.net), "?"))
	var step := func():
		var cur := cpu_sample(); var mi := mem_info(); var tp := temp()
		var p := cpu_pct(prev_cpu, cur) if not prev_cpu.is_empty() else 0.0
		prev_cpu = cur; hist_cpu.append(p); hist_tmp.append(maxf(tp, 0.0))
		if hist_cpu.size() > 60: hist_cpu.pop_front(); hist_tmp.pop_front()
		l1.text = ("CPU : %.0f %%" % p) if not cur.is_empty() else "CPU : indisponible"
		l2.text = ("Mémoire : %.1f / %.1f Go" % [(mi["total"] - mi["avail"]) / 1048576.0, mi["total"] / 1048576.0]) if mi.has("total") and mi.has("avail") else "Mémoire : indisponible"
		l3.text = ("Température : %.0f °C" % tp) if tp >= 0 else "Température : indisponible"
		g.queue_redraw()
	live = step; step.call()

# --- Raccourcis clavier
func _t_keys() -> void:
	var K = m.keysc
	_lbl("Cliquez sur une touche puis appuyez sur la nouvelle combinaison (Échap annule). Ctrl, Alt ou Méta obligatoire (ou F1-F12).", 14, true)
	var msg := _lbl("", 14)
	var d: Dictionary = K.actions()
	var cur_group := ""
	for a in d:
		var grp: String = "Fixes" if d[a][2] else ("Applications" if a.begins_with("app:") else ("Profils" if a.begins_with("prof:") else "Actions"))
		if grp != cur_group: cur_group = grp; var h := _lbl(grp.to_upper(), 13); h.add_theme_color_override("font_color", UI.accent_text())
		var row := HFlowContainer.new(); row.add_theme_constant_override("h_separation", 8); body.add_child(row)
		var n := Label.new(); n.text = d[a][0]; n.custom_minimum_size.x = 200; row.add_child(n)
		var b: Button = m._mk_btn(K.binding(a) if K.binding(a) != "" else "(aucune)", 190, 40); row.add_child(b)
		if d[a][2]: b.disabled = true; continue
		b.pressed.connect(func():
			b.text = "Appuyez sur une touche…"; msg.text = ""
			K.capture = func(s: String):
				if s == "": show_tab("keys"); return
				if not K.valid(s): _msg("Combinaison refusée : ajoutez Ctrl, Alt ou Méta."); show_tab("keys"); return
				var c: String = K.assign(a, s)
				if c != "": _msg("Déjà utilisée par : " + str(d[c][0]) + " (non modifié)")
				show_tab("keys"))
		var r: Button = m._mk_btn("Défaut", 70, 40); r.pressed.connect(func(): K.reset(a); show_tab("keys")); row.add_child(r)
		var x: Button = m._mk_btn("Aucune", 70, 40); x.pressed.connect(func(): K.assign(a, ""); show_tab("keys")); row.add_child(x)
	_lbl("MANETTE", 13).add_theme_color_override("font_color", UI.accent_text())
	var acts := [["", "(aucune)"]]
	for a in d: acts.append([a, d[a][0]])
	var pm: Dictionary = m.set_cfg["padmap"]
	for e in PAD_BTN:
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); body.add_child(row)
		var n := Label.new(); n.text = "Bouton " + str(e[0]); n.custom_minimum_size.x = 120; row.add_child(n)
		var ob := OptionButton.new(); ob.focus_mode = Control.FOCUS_NONE; ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(ob)
		for i in acts.size(): ob.add_item(acts[i][1]); if pm.get(str(e[1]), "") == acts[i][0]: ob.select(i)
		ob.item_selected.connect(func(i):
			if acts[i][0] == "": m.set_cfg["padmap"].erase(str(e[1]))
			else: m.set_cfg["padmap"][str(e[1])] = acts[i][0]
			m._save_settings())

func _msg(t: String) -> void: m.notify("Raccourcis", t)
