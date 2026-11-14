extends SceneTree
func _init() -> void:
	var sl := Control.new(); sl.set_script(load("res://apps/soundlink.gd")); sl.size = Vector2(460, 800)
	root.add_child(sl)
	await create_timer(1.0).timeout
	print("SL liste: ", AudioServer.get_input_device_list()); print("SL appareil son: ", sl.dev_opt.get_item_text(sl.dev_opt.selected), " | micro: ", sl.mic_opt.get_item_text(sl.mic_opt.selected))
	var rx := PacketPeerUDP.new(); rx.bind(0); rx.set_dest_address("127.0.0.1", 5252)
	rx.put_packet("SUB|test".to_utf8_buffer())
	await create_timer(0.5).timeout
	sl._on_share("snd", true)
	await create_timer(1.0).timeout
	OS.create_process("sh", ["-c", "for i in 1 2 3; do paplay --volume=50000 /usr/share/sounds/freedesktop/stereo/message.oga; done"])
	var peak := 0.0; var n := 0
	for i in 150:
		await create_timer(0.02).timeout
		rx.put_packet("SUB|test".to_utf8_buffer()) if i % 50 == 0 else null
		while rx.get_available_packet_count() > 0:
			var p := rx.get_packet()
			if p.size() > 12 and p.slice(0, 4).get_string_from_ascii() == "SND1" or p.slice(0, 3).get_string_from_ascii().begins_with("SN"):
				n += 1
				for k in range(12, p.size() - 1, 2):
					peak = maxf(peak, absf(p.decode_s16(k)) / 32768.0)
	print("SL paquets=", n, " crete=", snappedf(peak, 0.001), " PS=", OS.get_environment("PULSE_SOURCE"), " tag=", sl.SND_TAG)
	quit()
