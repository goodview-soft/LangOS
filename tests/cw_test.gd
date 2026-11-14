extends SceneTree
func _init() -> void:
	var m := Control.new(); m.set_script(load("res://apps/music.gd")); m.size = Vector2(1000, 600)
	root.add_child(m)
	_run(m)

func _run(m: Control) -> void:
	await process_frame; await process_frame
	m.tracks = [{"id": "cwt", "title": "T", "artist": "A", "track": "Titre", "duration": 120.0, "file": OS.get_environment("HOME") + "/mtest/s.mp3", "lrc": "", "offset": 0.0, "no_lyrics": true}]
	m._play(0)
	m.lines = [[0.0, "Voy de buena onda, me invita a tu casa"], [6.0, "Soy una princesa y no una guarra"]]
	m.cw_mode = 2; m.cw_op = 1; m.cw_size = 1
	var seen := []
	for t in [0.2, 0.7, 1.2, 1.9, 2.6, 3.4, 4.2, 5.0, 6.5, 8.0]:
		m._seek_to(t)
		await create_timer(0.25).timeout
		seen.append("%s=%s" % [t, m.cw_lbl.text])
	print("CW mots: ", seen)
	m._seek_to(0.5); await create_timer(0.08).timeout
	var a1: float = m.cw_lbl.modulate.a
	await create_timer(0.7).timeout
	var a2: float = m.cw_lbl.modulate.a
	print("CW opacité: pic≈", snappedf(a1, 0.01), " repos≈", snappedf(a2, 0.01), "  police=", m.cw_lbl.get_theme_font_size("font_size"))
	m.cw_pos = 1; m._cw_menu_pick(31); await create_timer(0.4).timeout
	print("CW position plus bas: ", m.cw.position, " menu items=", m.cw_menu.get_popup().item_count)
	print("CW visible=", m.cw.visible, " pos=", m.cw.position, " size=", m.cw.size, " winid=", m.cw.get_window_id(), " écran=", DisplayServer.screen_get_size())
	m.cw_mode = 0
	await create_timer(0.3).timeout
	print("CW mode non -> visible=", m.cw.visible)
	quit()
