extends SceneTree
## Test Chat : moteur Ollama, overlay natif en haut à droite, canal de commande UDP.
func _init() -> void:
	var core := ChatCore.new(); root.add_child(core)
	var ov := ChatOverlay.new(); ov.core = core; root.add_child(ov)
	_run(core, ov)

func _run(core: ChatCore, ov: ChatOverlay) -> void:
	await process_frame; await process_frame
	ov.toggle()
	await create_timer(0.8).timeout
	print("CHAT overlay visible=", ov.is_open(), " pos=", ov.win.position, " size=", ov.win.size, " winid=", ov.win.get_window_id())
	core.ask("Comment dit-on bonjour en espagnol ?")
	var t0 := Time.get_ticks_msec()
	while core.is_busy and Time.get_ticks_msec() - t0 < 120000: await create_timer(0.5).timeout
	print("CHAT réponse (", snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1), " s, modèle ", core.model, "): ", core.messages[-1]["content"].replace("\n", " "))
	await create_timer(0.5).timeout
	print("CHAT bulles=", ov.msgs_box.get_child_count())
	ov.toggle(); await create_timer(0.3).timeout
	print("CHAT après 2e toggle visible=", ov.is_open())
	core.messages = []; core._save()
	quit()
