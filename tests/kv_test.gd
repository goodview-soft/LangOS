extends SceneTree
func _init() -> void:
	var kv := KaraokeView.new(); kv.size = Vector2(900, 420); kv.position = Vector2.ZERO
	root.add_child(kv)
	var lines := [[0.0, "Ando en la mía, no me copies"], [4.0, "Dime si tú quieres bailar conmigo esta noche"], [8.0, ""], [10.0, "Hoy no pienso en mañana"]]
	var tr := {0: {"tr": "Je fais mon truc, ne me copie pas", "words": [{"w": "Ando", "sens": "je suis"}]}, 1: {"tr": "Dis-moi si tu veux danser avec moi ce soir", "words": []}}
	kv.set_data(lines, tr)
	_run(kv)

func _run(kv: KaraokeView) -> void:
	var clicked := []
	kv.word_clicked.connect(func(w, l): clicked.append([w, l]))
	kv.seek_requested.connect(func(t): clicked.append("seek%s" % t))
	for t in [-1.0, 0.3, 1.2, 3.9, 4.5, 6.0, 8.5, 11.0]:
		kv.set_time(t)
		await process_frame; await process_frame
	kv.set_time(0.6); await process_frame; await process_frame
	print("KV idx=", kv.idx, " hits=", kv._hits.size(), " lignes=", kv._line_rects.size(), " wt=", kv._wt.size())
	var h = kv._hits[1]["rect"].get_center() if kv._hits.size() > 1 else Vector2.ZERO
	var ev := InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true; ev.position = h
	kv._gui_input(ev)
	print("KV clic mot: ", clicked)
	quit()
