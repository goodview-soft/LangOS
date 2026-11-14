extends SceneTree
func _init() -> void:
	var m := Control.new(); m.set_script(load("res://apps/music.gd")); m.size = Vector2(1000, 600)
	root.add_child(m)
	_run(m)

func _run(m: Control) -> void:
	await process_frame; await process_frame
	m.tracks = [{"id": "ovt", "title": "T", "artist": "A", "track": "Titre", "duration": 120.0, "file": OS.get_environment("HOME") + "/mtest/s.mp3", "lrc": "", "offset": 0.0, "no_lyrics": true, "video": OS.get_environment("HOME") + "/mtest/c.ogv"}]
	m._play(0)
	m.lines = [[0.0, "Voy de buena onda, me invita a tu casa"], [6.0, "Soy una princesa y no una guarra"], [12.0, "Chupa, chupa, mmm"], [16.0, "Es que el papi está de guasa"], [20.0, "Dime qué te pasa, sube y baja"]]
	m.trans = {0: {"tr": "Je suis cool, il m'invite chez lui", "words": [{"w": "onda", "sens": "ambiance"}, {"w": "casa", "sens": "maison"}]}, 1: {"tr": "Je suis une princesse", "words": [{"w": "guarra", "sens": "garce"}]}}
	m.ov_mode = 1
	m._seek_to(13.0); await create_timer(1.5).timeout
	var o: Window = m.overlay
	print("OV existe=", o != null, " visible=", o.visible if o else "-", " pos=", o.position if o else "-", " size=", o.size if o else "-", " winid=", o.get_window_id() if o else "-")
	print("OV pixel: cadre visible=", m.ov_frame.visible, " tex=", m.ov_pix.texture != null, " kv.offset_left=", m.ov_kv.offset_left, " cadre pos=", m.ov_frame.position)
	print("OV lignes=", m.ov_kv._line_rects.size(), " chips possibles; hits=", m.ov_kv._hits.size())
	print("OV idx=", m.ov_kv.idx, " transparent=", o.transparent if o else "-")
	m.ov_mode = 0
	await create_timer(0.5).timeout
	print("OV mode auto (LangOS au premier plan) visible=", o.visible, "  focus=", DisplayServer.window_is_focused())
	quit()
