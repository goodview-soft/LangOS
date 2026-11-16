class_name HubGame extends Node
## Colle « spawn hub » côté jeu : protection, panneaux (Label3D + saisie), ligne de commande (/),
## indicateur « Zone sûre », tests. main.gd n'a que de courts points d'accroche.

const PROTECT_MSG := "Zone protégée (spawn)"
const SIGN_MAX := 40
const LABEL_DIST := 8.0

var main  # main.gd
var hub: SpawnHub
var cmds: Commands
var labels := {}  # Vector3i -> Label3D
var carried: Array = []  # textes des panneaux ramassés (restitués à la pose suivante)
var safe_lbl: Label
var panel: PanelContainer
var prompt_lbl: Label
var edit: LineEdit
var mode := ""  # "", "cmd", "sign"
var edit_cell := Vector3i.ZERO
var quiet := false  # tests : pas d'ouverture automatique de la saisie

func setup(m, h: SpawnHub) -> void:
	main = m
	hub = h
	cmds = Commands.new(m, h.spawn_pos)
	cmds.on_teleport = _tp_fx
	for c in hub.torches:
		main.torch_lights[c] = main._add_light(Vector3(c) + Vector3(0.5, 0.7, 0.5), Color(1.0, 0.62, 0.3), 9.0, 1.7)
	for c in main.world.signs:
		_make_label(c)
	_build_ui()

func typing() -> bool:
	return mode != ""

## Protection silencieuse (aperçu de pose).
func is_protected(c: Vector3i) -> bool:
	return hub.is_protected(c)

func is_safe_zone(pos: Vector3) -> bool:
	return hub.is_safe_zone(pos)

## Protection avec message (casse, pose).
func guard(c: Vector3i) -> bool:
	if hub.is_protected(c):
		main.hud.toast(PROTECT_MSG)
		return true
	return false

# ---------------------------------------------------------------- panneaux
func on_placed(c: Vector3i, item: int) -> void:
	if item != World.SIGN:
		return
	var w: World = main.world
	var face := Vector3i(0, 0, 1)
	var wall := false
	var t: Dictionary = main.target
	if not t.is_empty() and t.prev == c:
		var n: Vector3i = c - t.cell
		if n.y == 0 and absi(n.x) + absi(n.z) == 1:
			face = n; wall = true
	if not wall:
		for d in [Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(-1, 0, 0)]:
			if t.is_empty() and w.is_solid(w.get_v(c + d)) and not w.is_solid(w.get_v(c - Vector3i(0, 1, 0))):
				face = -d; wall = true
				break
	if not wall:
		var v: Vector3 = -main.view_dir
		v.y = 0.0
		if v.length() > 0.5:
			face = Vector3i(v.round())
	w.signs[c] = {"text": carried.pop_back() if not carried.is_empty() else "", "face": face, "wall": wall}
	_make_label(c)
	if not quiet:
		open_sign_editor(c)

func on_broken(c: Vector3i, id: int) -> void:
	if id != World.SIGN:
		return
	var w: World = main.world
	var txt: String = w.signs.get(c, {}).get("text", "")
	if txt != "":
		carried.append(txt)
	w.signs.erase(c)
	if labels.has(c):
		(labels[c] as Node).queue_free()
		labels.erase(c)

func set_sign_text(c: Vector3i, txt: String) -> void:
	var w: World = main.world
	if not w.signs.has(c):
		return
	w.signs[c]["text"] = txt.strip_edges().left(SIGN_MAX)
	_make_label(c)

func _make_label(c: Vector3i) -> void:
	var l: Label3D = labels.get(c)
	if l == null:
		l = Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.render_priority = 4
		l.outline_render_priority = 3
		l.font_size = 8
		l.outline_size = 2
		l.outline_modulate = Color(0, 0, 0, 0.9)
		l.modulate = Color(1.0, 0.93, 0.68)
		l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.width = 84.0
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		l.position = Vector3(c) + Vector3(0.5, 1.05, 0.5)
		l.visible = false
		add_child(l)
		labels[c] = l
	l.text = main.world.signs.get(c, {}).get("text", "")

func _sign_near() -> Variant:
	var w: World = main.world
	var t: Dictionary = main.target
	if not t.is_empty() and w.get_v(t.cell) == World.SIGN:
		return t.cell
	var best: Variant = null
	var bd := 2.6
	for c in w.signs:
		var d: float = (Vector3(c) + Vector3(0.5, 0.5, 0.5)).distance_to(main.player.center())
		if d < bd and main.cell_visible(c):
			bd = d
			best = c
	return best

# ---------------------------------------------------------------- interface : saisie
func _build_ui() -> void:
	safe_lbl = Label.new()
	safe_lbl.text = "Zone sûre  -  Échap > Personnage : changer de créature"
	safe_lbl.add_theme_font_size_override("font_size", 9)
	safe_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	safe_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	safe_lbl.add_theme_constant_override("outline_size", 3)
	safe_lbl.position = Vector2(0, 4)
	safe_lbl.size = Vector2(640, 12)
	safe_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	safe_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe_lbl.visible = false
	main.hud.add_child(safe_lbl)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.08, 0.9)
	sb.border_color = Color(0.55, 0.42, 0.25)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(3)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(160, 290)
	panel.custom_minimum_size = Vector2(320, 0)
	panel.visible = false
	layer.add_child(panel)
	var hb := HBoxContainer.new()
	panel.add_child(hb)
	prompt_lbl = Label.new()
	prompt_lbl.add_theme_font_size_override("font_size", 9)
	prompt_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	hb.add_child(prompt_lbl)
	edit = LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", 10)
	edit.text_submitted.connect(_on_submit)
	edit.focus_exited.connect(close_prompt)
	hb.add_child(edit)

func open_cmd() -> void:
	_open("cmd", "Commande", 60, "/")

func open_sign_editor(c: Vector3i) -> void:
	edit_cell = c
	_open("sign", "Panneau (%d max)" % SIGN_MAX, SIGN_MAX, main.world.signs.get(c, {}).get("text", ""))

func _open(m: String, title: String, maxlen: int, txt: String) -> void:
	mode = m
	prompt_lbl.text = title
	edit.max_length = maxlen
	edit.text = txt
	panel.visible = true
	edit.grab_focus()
	edit.caret_column = txt.length()

func close_prompt() -> void:
	if mode == "":
		return
	mode = ""
	panel.visible = false
	if edit.has_focus():
		edit.release_focus()

func _on_submit(txt: String) -> void:
	var m := mode
	var c := edit_cell
	close_prompt()
	if m == "cmd":
		main.hud.toast(cmds.execute(txt))
	elif m == "sign":
		set_sign_text(c, txt)
		main.hud.toast("Panneau écrit")

func _tp_fx(from: Vector3, to: Vector3) -> void:
	if main.chip_pool.is_empty():
		return
	for p in [from, to]:
		main.chip_burst(Vector3i((p as Vector3) + Vector3(0, 0.6, 0)), World.CRYSTAL, 1.0)

# ---------------------------------------------------------------- entrées / image
func _input(ev: InputEvent) -> void:
	if mode != "" and ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		close_prompt()
		get_viewport().set_input_as_handled()

func _unhandled_input(ev: InputEvent) -> void:
	if mode != "" or main.state != "play" or not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	if ev.unicode == 47 or ev.keycode == KEY_SLASH or ev.keycode == KEY_KP_DIVIDE:
		open_cmd()
		get_viewport().set_input_as_handled()
	elif ev.physical_keycode == KEY_F:
		var c: Variant = _sign_near()
		if c == null:
			return
		if hub.is_protected(c):
			main.hud.toast(PROTECT_MSG)
		else:
			open_sign_editor(c)
		get_viewport().set_input_as_handled()
	elif ev.physical_keycode == KEY_0 and main.hotbar.size() > 9:
		main.sel = 9

func _process(_dt: float) -> void:
	var pc: Vector3 = main.player.center()
	safe_lbl.visible = hub.is_safe_zone(pc) and main.state == "play"
	var cut_ok: bool = main.cut_layer != -999
	var ps: float = main.cam.size / 360.0
	for c in labels:
		var l: Label3D = labels[c]
		l.pixel_size = ps
		l.visible = cut_ok and l.text != "" and main.cell_visible(c) and absi(c[main.cut_axis] - main.cut_layer) <= 3 \
				and (Vector3(c) + Vector3(0.5, 0.5, 0.5)).distance_to(pc) < LABEL_DIST

# ---------------------------------------------------------------- tests (--dm-test)
func run_tests() -> void:
	var m = main
	var w: World = m.world
	quiet = true
	var dt := 1.0 / 60.0
	var floor_c := Vector3i(hub.spawn_pos) - Vector3i(0, 1, 0)
	var bricks := 0
	var a := hub.box_min()
	var b := hub.box_max()
	for z in range(a.z, b.z + 1):
		for y in range(a.y, b.y + 1):
			for x in range(a.x, b.x + 1):
				if w.get_b(x, y, z) == World.BRICK:
					bricks += 1
	var open := 0
	for e in hub.exits:
		if e[3]:
			open += 1
	m._check("cirque de spawn (%d briques, sol %s, %d/%d sorties ouvertes)" % [bricks, World.NAMES[w.get_v(floor_c)], open, hub.exits.size()], bricks > 80 and w.get_v(floor_c) == World.BRICK and open >= 2 and w.spawn == hub.spawn_pos)
	m._check("joueur au spawn de la salle", m.player.pos.distance_to(hub.spawn_pos) < 0.01 and not w.box_hits(m.player.pos, Player.HW, Player.HH))
	m._check("panneau titre « %s »" % w.signs.get(hub.title_cell, {}).get("text", "?"), w.get_v(hub.title_cell) == World.SIGN and w.signs[hub.title_cell].text == SpawnHub.TITLE and labels.has(hub.title_cell))
	m.hud.toast("")
	var ok_break: bool = not m.break_block(floor_c) and w.get_v(floor_c) == World.BRICK and m.hud.toast_lbl.text == PROTECT_MSG
	var ok_sign: bool = not m.break_block(hub.title_cell) and w.get_v(hub.title_cell) == World.SIGN
	var air_c := Vector3i(hub.ix0 + SpawnHub.IW / 2 + 2, hub.fy + 4, hub.iz0 + SpawnHub.ID / 2)
	m.inv[World.DIRT] = m.inv.get(World.DIRT, 0) + 1
	m.hud.toast("")
	var ok_place: bool = not m.place_block(air_c, World.DIRT) and w.get_v(air_c) == World.AIR and m.hud.toast_lbl.text == PROTECT_MSG
	m._check("zone protégée : casse %s, panneau %s, pose %s" % [ok_break, ok_sign, ok_place], ok_break and ok_sign and ok_place)
	m._check("is_safe_zone (salle oui, caverne non)", is_safe_zone(hub.spawn_pos + Vector3(0, 0.9, 0)) and not is_safe_zone(hub.cave_spot + Vector3(0, 0.9, 0)) and not is_safe_zone(Vector3(3, 3, 3)))
	_process(dt)
	m._check("indicateur Zone sûre affiché", safe_lbl.visible)
	m._check("/aide", cmds.execute("/aide").contains("/sethome"))
	# /sethome dans une caverne, puis /spawn, puis /home
	cmds.teleport(hub.cave_spot)
	for i in 40: m.move_player(dt, 0, 0, false)
	var r1 := cmds.execute("/sethome")
	var homep: Vector3 = cmds.home
	m._check("/sethome : %s" % r1, r1.begins_with("Base") and homep.distance_to(m.player.pos) < 0.6)
	var r2 := cmds.execute("/spawn")
	m._check("/spawn : %s" % r2, m.player.pos.distance_to(hub.spawn_pos) < 0.01 and is_safe_zone(m.player.center()))
	m.player.combat_t = 5.0
	var rc := cmds.execute("/spawn")
	m._check("/spawn refusé en combat : %s" % rc, rc.contains("combat"))
	m.player.combat_t = 0.0
	var r3 := cmds.execute("/home")
	m._check("/home : %s" % r3, m.player.pos.distance_to(homep) < 0.01)
	var saved := cmds.to_dict()
	var c2 := Commands.new(m, hub.spawn_pos)
	c2.from_dict(saved)
	m._check("base dans to_dict/from_dict", c2.home == homep)
	# refus : en l'air, dans la lave
	var keep: Vector3 = m.player.pos
	m.player.pos = Vector3(keep.x, keep.y + 3.5, keep.z)
	m.player.on_ground = false
	var r4 := cmds.execute("/sethome")
	var lava_ok := true
	var r5 := ""
	for i in w.lava_surface.size():
		var lp: Vector3 = w.lava_surface[i]
		m.player.pos = lp - Vector3(0, 0.5, 0)
		m.player.on_ground = true
		r5 = cmds.execute("/sethome")
		lava_ok = r5.contains("lave")
		break
	m._check("/sethome refusé en l'air (%s) et dans la lave (%s)" % [r4, r5], r4.begins_with("Impossible") and lava_ok and cmds.home == homep)
	cmds.teleport(homep)
	for i in 30: m.move_player(dt, 0, 0, false)
	# saisie : le jeu est bloqué pendant l'écriture
	open_cmd()
	m._check("ligne de commande ouverte (/), saisie active", typing() and edit.text == "/")
	_on_submit("/spawn")
	m._check("commande via l'interface -> /spawn", not typing() and m.player.pos.distance_to(hub.spawn_pos) < 0.01)
	cmds.teleport(homep)
	for i in 30: m.move_player(dt, 0, 0, false)
	# panneau : pose, texte, casse (ramassé), repose (texte conservé)
	var feet := Vector3i(floori(m.player.pos.x), floori(m.player.pos.y + 0.05), floori(m.player.pos.z))
	var sc := Vector3i(-1, -1, -1)
	for dx in [2, -2, 1, -1, 3, -3]:
		var c := feet + Vector3i(dx, 0, 0)
		if w.get_v(c) == World.AIR and m.cell_visible(c) and not hub.is_protected(c):
			sc = c
			break
	m.target = {}
	var n0: int = m.inv.get(World.SIGN, 0)
	var placed: bool = sc.x >= 0 and m.place_block(sc, World.SIGN)
	m._check("pose d'un panneau %s (stock %d -> %d)" % [str(sc), n0, m.inv.get(World.SIGN, 0)], placed and w.get_v(sc) == World.SIGN and w.signs.has(sc) and m.inv[World.SIGN] == n0 - 1)
	open_sign_editor(sc)
	var maxl := edit.max_length
	_on_submit("Bonjour mineur ! Ce texte est bien trop long pour tenir ici")
	var txt: String = w.signs.get(sc, {}).get("text", "")
	m._check("texte du panneau (%d car.) « %s »" % [txt.length(), txt], maxl == SIGN_MAX and txt.length() == SIGN_MAX and txt.begins_with("Bonjour mineur") and labels.has(sc) and labels[sc].text == txt)
	var broke: bool = m.break_block(sc)
	m._check("casse du panneau : ramassé", broke and w.get_v(sc) == World.AIR and not w.signs.has(sc) and not labels.has(sc) and m.inv[World.SIGN] == n0)
	var again: bool = m.place_block(sc, World.SIGN)
	m._check("repose : texte conservé", again and w.signs.get(sc, {}).get("text", "") == txt)
	m.break_block(sc)
	carried.clear()
	m.inv[World.SIGN] = 5
	Stacks.reconcile(m)
	var sign_stack := false
	for sv in m.sac:
		sign_stack = sign_stack or sv.x == World.SIGN
	sign_stack = sign_stack or (m.hotbar as Array).has(World.SIGN)
	m._check("objet Panneau dans l'inventaire (I) : une pile dans le sac ou la barre rapide", sign_stack)
	# les tests suivants (déplacement, minage) se font dans la caverne, hors zone protégée
	cmds.teleport(hub.cave_spot)
	quiet = false
