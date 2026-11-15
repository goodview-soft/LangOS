extends SceneTree
func _mods() -> bool:
	var o := []; OS.execute("pactl", ["list", "short", "modules"], o)
	return str(o[0]).contains("source=soundlink_mic")
func _init() -> void:
	var sl := Control.new(); sl.set_script(load("res://apps/soundlink.gd")); sl.size = Vector2(460, 800)
	root.add_child(sl)
	await create_timer(0.8).timeout
	sl._set_monitor(true)
	print("SM actif=", _mods())
	OS.execute("pactl", ["unload-module", sl.monitor_module], [])  # simule la disparition spontanée
	print("SM apres_coupure=", _mods())
	await create_timer(3.0).timeout
	print("SM remis=", _mods())
	sl._set_monitor(false)
	await create_timer(2.5).timeout
	print("SM apres_off=", _mods())
	quit()
