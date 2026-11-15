extends SceneTree
## Test du bureau étendu : redimensionnement, ancrage, bureaux virtuels, menus, glisser d'icône, notifications, thème.
## flatpak run org.godotengine.Godot --headless --path . --script res://tests/desk_test.gd

func _init() -> void:
	var vp := SubViewport.new(); vp.size = Vector2i(1280, 720); vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	var m = load("res://main.tscn").instantiate(); vp.add_child(m)
	await create_timer(0.8).timeout
	var f: Array = []
	m._open_app("calc"); m._open_app("units")
	await create_timer(0.7).timeout
	var w: PanelContainer = m.wins["calc"]["win"]
	# redimensionner : bord droit
	var r := Rect2(w.position, w.size); var gp: Vector2 = m.desk.global_position
	var press := InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true; press.position = gp + Vector2(r.end.x - 3, r.position.y + 200)
	m._input(press)
	var mv := InputEventMouseMotion.new(); mv.position = press.position + Vector2(60, 0); m._input(mv)
	var rel := InputEventMouseButton.new(); rel.button_index = MOUSE_BUTTON_LEFT; rel.pressed = false; rel.position = mv.position; m._input(rel)
	if w.size.x < r.size.x + 40 and w.position.x + r.size.x + 60 <= m.desk.size.x: f.append("redimensionnement : %s -> %s" % [r.size, w.size])
	# ancrage
	m._snap("calc", "l")
	if absf(w.size.x - m.desk.size.x / 2.0) > 2 or w.position.x != 0: f.append("ancrage gauche : " + str(Rect2(w.position, w.size)))
	m._snap("calc", "tr")
	if w.position.x < m.desk.size.x / 2.0 - 2: f.append("ancrage quart")
	m._tile_all()
	if w.size.x > m.desk.size.x * 0.6: f.append("disposition")
	# bureaux virtuels
	m._move_to_vd("units", 1)
	if m.wins["units"]["win"].visible or m.wins["units"]["task"].visible: f.append("units doit être caché sur le bureau 1")
	m._goto_vd(1)
	if not m.wins["units"]["win"].visible or w.visible: f.append("bureau 2 : mauvaise visibilité")
	m._goto_vd(0)
	if not w.visible: f.append("retour bureau 1")
	# menus contextuels
	m._desk_menu(Vector2(600, 300))
	var n1: int = m.ctx_menu.get_child(0).get_child_count(); m._hide_ctx()
	m._win_menu("calc", Vector2(300, 300)); var n2: int = m.ctx_menu.get_child(0).get_child_count(); m._hide_ctx()
	m._vd_menu(); m._hide_ctx()
	if n1 < 6 or n2 < 10: f.append("menus : %d / %d éléments" % [n1, n2])
	# icône : glisser
	var ic: Button = m.desk_icons[0]; var id := str(ic.get_meta("id"))
	var p0 := ic.position
	m._icon_input(_btn(true), ic, id)
	ic.position = Vector2(16 + 3 * 108, 16 + 108)
	m.idrag["moved"] = true
	m._icon_input(_btn(false), ic, id)
	if m.set_cfg["icons"].get(id, []) != [3, 1] or ic.position != Vector2(16 + 3 * 108, 16 + 108): f.append("glisser icône : %s %s" % [str(m.set_cfg["icons"]), str(ic.position)])
	m._reset_icons()
	if ic.position != p0: f.append("ranger icônes")
	# notifications
	m.notify("Test", "bonjour"); m.notify("Deux")
	m._toggle_notifs()
	if m.notifs.filter(func(n): return n["t"] in ["Test", "Deux"]).size() != 2 or m.unread != 0 or not is_instance_valid(m.np_panel): f.append("notifications %d %d %s" % [m.notifs.size(), m.unread, str(m.notifs.map(func(n): return n["t"]))])
	m._close_notifs()
	# thème
	m._set_light(true); await create_timer(0.2).timeout
	if m._p("win") != m.PAL_L["win"]: f.append("thème clair")
	m._set_light(false)
	# fond perso
	var img := Image.create(64, 32, false, Image.FORMAT_RGB8); img.fill(Color.RED); img.save_png("user://t_wall.png")
	if not m._set_wallpaper(ProjectSettings.globalize_path("user://t_wall.png")) or m.bg.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_COVERED: f.append("fond perso")
	m._set_gradient(0)
	# ne pas écraser la config réelle de l'utilisateur
	print("DESK-TEST OK" if f.is_empty() else "DESK-TEST ECHEC: " + str(f))
	quit()

func _btn(p: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = p; return e
