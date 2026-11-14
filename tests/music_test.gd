extends SceneTree
## Test Music : pause/reprise sans retour à 0, seek, traduction (Ollama) avec validation.
func _init() -> void:
	var m := Control.new(); m.set_script(load("res://apps/music.gd")); m.size = Vector2(1000, 600)
	root.add_child(m)
	_run(m)

func _run(m: Control) -> void:
	await process_frame; await process_frame
	var home := OS.get_environment("HOME")
	m.tracks = [{"id": "t1", "title": "Test", "artist": "Art", "track": "Titre", "duration": 20.0, "file": home + "/mtest/s.mp3", "lrc": "", "offset": 0.0, "no_lyrics": true}]
	m._refresh_list()
	m.lines = [[0.0, "Ando en la mía, no me copies"], [4.0, "Dime si tú quieres bailar conmigo"], [8.0, "Hoy no pienso en mañana, vamos a perrear"],
		[12.0, "Mami, no me llames más"], [16.0, "Tú eres la que me tiene enamorado"]]
	m._play(0)
	m.lines = [[0.0, "Ando en la mía, no me copies"], [4.0, "Dime si tú quieres bailar conmigo"], [8.0, "Hoy no pienso en mañana, vamos a perrear"], [12.0, "Mami, no me llames más"], [16.0, "Tú eres la que me tiene enamorado"]]
	m.lines = [[0.0, "Ando en la mía, no me copies"], [4.0, "Dime si tú quieres bailar conmigo"], [8.0, "Hoy no pienso en mañana, vamos a perrear"],
		[12.0, "Mami, no me llames más"], [16.0, "Tú eres la que me tiene enamorado"]]
	# traduction réelle
	m.set("src", "spa"); m.set("tgt", "fra")
	m.tracks[0]["lrc"] = "user://music/t1.lrc"
	var lf := FileAccess.open("user://music/t1.lrc", FileAccess.WRITE); lf.store_string("[00:00.00]Voy de buena onda, me invita'a tu casa,\n[00:04.00]Y ahora tú me dice' que yo me agacha, dime qué te pasa\n[00:08.00]Es que el papi está de guasa, no me cuente' cuento' que no me la gasta'\n[00:12.00]Soy una princesa y no una guarra\n"); lf.close()
	var pc := "user://music/t1.fra.v3.json"
	if FileAccess.file_exists(pc): DirAccess.remove_absolute(pc)
	m._load_lines()
	print("MUSIC avant: lignes=", m.lines.size(), " current=", m.current)
	m._auto_translate(0)
	await create_timer(2.0).timeout
	print("MUSIC statut: ", m.status.text)
	await create_timer(70.0).timeout
	for k in m.trans: print("MUSIC trad ", k, ": ", m.trans[k]["tr"], " | ", m.trans[k]["words"])
	print("MUSIC trad lignes=", m.trans.size(), "/", m.lines.size())
	m._word_clicked("perrear", 2)
	print("MUSIC clic mot -> pause=", m._paused, " carte=", m.word_view.get_parsed_text().replace("\n", " | "))
	print("MUSIC glose dico bailar=", m._quick_gloss("casa"), " / ", m._quick_gloss("mañana"))
	quit()
