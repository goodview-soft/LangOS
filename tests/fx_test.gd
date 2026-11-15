extends SceneTree
## Test « Look & fluidité » : zones d'ancrage, aperçu, dock, réglages persistés, animations désactivables.
## flatpak run org.godotengine.Godot --headless --path . --script res://tests/fx_test.gd

func _init() -> void:
	var vp := SubViewport.new(); vp.size = Vector2i(1280, 720); vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	var m = load("res://main.tscn").instantiate(); vp.add_child(m)
	await create_timer(0.8).timeout
	var f: Array = []
	var fx = m.fx
	var s := Vector2(1280, 700)
	# zones d'ancrage
	var cases := {Vector2(0, 350): "l", Vector2(1279, 350): "r", Vector2(640, 0): "max", Vector2(2, 2): "tl", Vector2(1278, 2): "tr", Vector2(2, 698): "bl",
		Vector2(1279, 698): "br", Vector2(100, 699): "3l", Vector2(640, 699): "3c", Vector2(1200, 699): "3r", Vector2(640, 350): ""}
	for p in cases:
		if fx.zone_at(p, s) != cases[p]: f.append("zone %s : %s au lieu de %s" % [str(p), fx.zone_at(p, s), cases[p]])
	if fx.zone_rect("tr", s) != Rect2(640, 0, 640, 350) or absf(fx.zone_rect("3c", s).size.x - 1280.0 / 3.0) > 0.01: f.append("zone_rect")
	# aperçu (animations coupées : valeurs immédiates)
	fx.set_anim(false)
	fx.show_preview("l")
	if fx.prev == null or not fx.prev.visible or absf(fx.prev.size.x - (m.desk.size.x / 2.0 - 12.0)) > 1.0: f.append("aperçu gauche : " + str(fx.prev.size if fx.prev else "-"))
	fx.show_preview(""); if fx.prev.visible: f.append("aperçu non masqué")
	# glissement réel de titre -> aperçu puis ancrage au relâchement
	m._open_app("calc"); m._open_app("units")
	await create_timer(0.4).timeout
	# animations off : ouverture instantanée
	m._open_app("todo")
	var tw: PanelContainer = m.wins["todo"]["win"]
	if tw.modulate.a != 1.0 or tw.scale != Vector2.ONE: f.append("ouverture non instantanée avec animations off")
	# animations on : ouverture progressive
	fx.set_anim(true)
	m._open_app("timer")
	var tw2: PanelContainer = m.wins["timer"]["win"]
	if tw2.modulate.a >= 1.0: f.append("ouverture sans fondu avec animations on")
	await create_timer(0.4).timeout
	if tw2.modulate.a < 0.99: f.append("fondu inachevé")
	# dock
	if not m.dock.visible: f.append("dock invisible à 1280 px")
	var ids: Array = m.dock.ids()
	for k in ["calc", "units", "todo", "settings"]:
		if not ids.has(k): f.append("dock sans " + k)
	if not m.dock.items.has("calc"): f.append("bouton dock calc absent")
	m.dock.toggle_pin("calc"); m.dock.toggle_pin("calc")
	# épingler / désépingler
	m.dock.toggle_pin("units")
	if not m.dock.pins().has("units"): f.append("épingle")
	m.dock.toggle_pin("units")
	if m.dock.pins().has("units"): f.append("désépingle")
	# fermeture instantanée avec animations off
	fx.set_anim(false)
	m._close_win("todo")
	if m.wins.has("todo"): f.append("fermeture")
	# réglages persistés
	fx.set_accent(Color("ff5c7a")); fx.set_opt("radius", 20); fx.set_anim(false)
	await process_frame; await process_frame
	var c := ConfigFile.new(); c.load("user://settings.cfg")
	if str(c.get_value("ui", "accent", "")) != "ff5c7a" or bool(c.get_value("ui", "anim", true)) or int(c.get_value("ui", "radius", 0)) != 20: f.append("réglages non persistés")
	if m.ACCENT != Color("ff5c7a"): f.append("ACCENT non appliqué")
	if absf(m.wins["calc"]["win"].get_theme_stylebox("panel").corner_radius_top_left - 20.0) > 0.1: f.append("rayon non appliqué aux fenêtres")
	# écran étroit : pas de dock
	vp.size = Vector2i(600, 900)
	await create_timer(0.4).timeout
	if m.dock.visible or not m.task_box.visible: f.append("dock visible sur écran étroit")
	# centre de contrôle
	m.ccenter.toggle(m.cc_btn)
	if not m.ccenter.is_open(): f.append("centre de contrôle")
	m.ccenter.close()
	# remise à l'état par défaut (le fichier de réglages est partagé)
	fx.set_accent(Color("5aa2ff")); fx.set_opt("radius", 12); fx.set_anim(true)
	print("FX-TEST OK" if f.is_empty() else "FX-TEST ECHEC: " + str(f))
	quit(0 if f.is_empty() else 1)
