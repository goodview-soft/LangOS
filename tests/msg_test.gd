extends SceneTree
## Test réseau local de Messenger : deux instances sur localhost, texte + fichier (SHA256).
var a: Control
var b: Control

func _init() -> void:
	DirAccess.make_dir_recursive_absolute("user://ta"); DirAccess.make_dir_recursive_absolute("user://tb")
	a = _mk(5350, 5351, "user://ta/chat", "user://ta/recv", "Alice")
	b = _mk(5360, 5361, "user://tb/chat", "user://tb/recv", "Bob")
	root.add_child(a); root.add_child(b)
	_go()

func _go() -> void:
	await process_frame
	await process_frame
	a.peers[b.my_id] = {"ip": "127.0.0.1", "port": 5361, "status": 0, "name": "Bob", "t": 1e12}
	b.peers[a.my_id] = {"ip": "127.0.0.1", "port": 5351, "status": 0, "name": "Alice", "t": 1e12}
	_run()

func _mk(u: int, t: int, d: String, r: String, n: String) -> Control:
	var c := Control.new(); c.set_script(load("res://apps/messenger.gd"))
	c.set("udp_port", u); c.set("tcp_port", t); c.set("data_dir", d); c.set("recv_dir", r)
	c.set("my_id", n + str(randi())); c.set("size", Vector2(900, 600))
	return c

func _run() -> void:
	await create_timer(0.5).timeout
	# fichier test 3 Mo
	var f := FileAccess.open("user://ta/src.bin", FileAccess.WRITE)
	var buf := PackedByteArray(); buf.resize(3000000)
	for i in buf.size(): buf[i] = i % 251
	f.store_buffer(buf); f.close()
	var h0 := FileAccess.get_sha256("user://ta/src.bin")
	a.cur = b.my_id
	a.input.text = "salut Bob"; a._send_text()
	a._send_file(b.my_id, "user://ta/src.bin")
	await create_timer(1.0).timeout
	var offer := ""
	for fid in b.offers: offer = fid
	print("TEST texte reçu: ", b.msgs.get(a.my_id, []).size() > 0 and b.msgs[a.my_id][0].get("text", "") == "salut Bob", " | offre: ", offer != "")
	if offer != "": b._accept(offer)
	await create_timer(3.0).timeout
	var path: String = b.offers[offer]["path"] if offer != "" else ""
	print("TEST fichier: ", path, " sha ok=", path != "" and FileAccess.get_sha256(path) == h0, " état=", b.offers[offer]["msg"]["state"] if offer != "" else "-")
	for id in a.offers: print("TEST état expéditeur: ", a.offers[id]["msg"]["state"])
	quit()
