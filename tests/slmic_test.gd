extends SceneTree
func _init() -> void:
	var sl := Control.new(); sl.set_script(load("res://apps/soundlink.gd")); sl.size = Vector2(460, 800)
	root.add_child(sl)
	await create_timer(1.0).timeout
	var tab := PacketPeerUDP.new(); tab.bind(5260); tab.set_dest_address("127.0.0.1", 5252)
	var seq := 0; var ph := 0.0
	for i in 700:
		sl.peers["tab"] = {"ip": "127.0.0.1", "port": 5260, "snd": false, "mic": true, "name": "tab", "t": Time.get_ticks_msec() / 1000.0}
		sl.listening["tab"] = true
		var pkt := "MIC1".to_ascii_buffer(); pkt.resize(12 + 960)
		pkt.encode_u32(4, seq); pkt.encode_u32(8, 48000); seq += 1
		for k in 480:
			pkt.encode_s16(12 + k * 2, int(sin(ph) * 12000)); ph += TAU * 440.0 / 48000.0
		tab.put_packet(pkt)
		await create_timer(0.01).timeout
	print("SM pcfg=", sl._pcfg("tab"), " bus=", sl.rxs["127.0.0.1:5260"]["bus"], " mute=", AudioServer.is_bus_mute(AudioServer.get_bus_index(sl.rxs["127.0.0.1:5260"]["bus"])), " lost=", sl.rxs["127.0.0.1:5260"]["mic"].lost, " q=", sl.rxs["127.0.0.1:5260"]["mic"].queue.size(), " rate=", sl.rxs["127.0.0.1:5260"]["mic"].rate); print("SM sortie=", AudioServer.output_device, " vsink_exists=", sl.vsink_exists, " rxs=", sl.rxs.keys())
	quit()
