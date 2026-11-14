extends SceneTree
func _init() -> void:
	var sl := Control.new(); sl.set_script(load("res://apps/soundlink.gd")); sl.size = Vector2(460, 800)
	root.add_child(sl)
	await create_timer(0.8).timeout
	sl._set_monitor(true)
	print("SM module=", sl.monitor_module)
	var o := []; OS.execute("pactl", ["list", "short", "modules"], o)
	print("SM present=", str(o[0]).contains("module-loopback"))
	sl._set_monitor(false)
	o = []; OS.execute("pactl", ["list", "short", "modules"], o)
	print("SM apres_off=", str(o[0]).contains("source=soundlink_mic"))
	quit()
