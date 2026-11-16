extends SceneTree
## Charge Deep Miner dans la fenêtre hôte (3 tailles dont portrait), joue quelques images. Sortie « DM-TEST OK ».
func _init() -> void:
	var fails := 0
	for sz in [Vector2(1100, 700), Vector2(500, 900), Vector2(1600, 600)]:
		var h := Control.new(); h.set_script(load("res://apps/dm_host.gd")); h.size = sz
		root.add_child(h)
		h.set_anchors_preset(Control.PRESET_TOP_LEFT); h.size = sz
		for i in 40: await process_frame
		var g: Node = h.game
		var tw := 0
		while g != null and g.booting and tw < 3000: await process_frame; tw += 1   # génération asynchrone
		for i in 10: await process_frame
		if g == null: print("pas de jeu ", sz); fails += 1
		else:
			g.menu.play.emit()
			for i in 60: await process_frame
			print(sz, " state=", g.state, " vp=", h.sv.size, " logique=", h.sv.size_2d_override, " extra=", g.extra_h)
			if g.state != "play": fails += 1
			g._pause(); g.menu.resume.emit()
			for i in 5: await process_frame
		h.queue_free()
		for i in 5: await process_frame
	print("DM-TEST OK" if fails == 0 else "DM-TEST FAIL")
	quit()
