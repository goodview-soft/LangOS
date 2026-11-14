extends SceneTree
## Test RemoteDesk : hôte + client sur localhost (fenêtre réelle requise pour la capture).
var host: Control
var cli: Control
var btn: Button
var pressed := 0

func _init() -> void:
	root.size = Vector2i(800, 600)
	btn = Button.new(); btn.text = "CIBLE"; btn.position = Vector2(100, 100); btn.size = Vector2(200, 80)
	btn.pressed.connect(func(): pressed += 1)
	root.add_child(btn)
	host = _mk(); cli = _mk()
	cli.set("my_id", "client"); host.set("my_id", "host")
	root.add_child(host); root.add_child(cli)
	_go()

func _mk() -> Control:
	var c := Control.new(); c.set_script(load("res://apps/remotedesk.gd"))
	c.set("udp_port", 5353); c.set("tcp_port", 5352); c.size = Vector2(300, 200)
	c.position = Vector2(400, 300)
	return c

func _go() -> void:
	await create_timer(0.8).timeout
	host.call("_toggle_share")
	var code: String = host.get("code")
	print("RD code: ", code.length() == 6)
	# mauvais code d'abord
	cli.get("ip_edit").text = "127.0.0.1"; cli.get("code_edit").text = "000000" if code != "000000" else "111111"
	cli.call("_connect_pressed")
	await create_timer(1.0).timeout
	print("RD refus: ", cli.get("cconn") == null, " | hôte: ", host.get("host_state").text)
	cli.get("code_edit").text = code
	cli.call("_connect_pressed")
	await create_timer(2.0).timeout
	var cc = cli.get("cconn")
	print("RD auth: ", cc != null and cc["auth"], " | taille distante: ", cli.get("rem_w"), "x", cli.get("rem_h"))
	print("RD image reçue: ", cli.get("viewer").texture != null)
	# clic à distance sur le bouton CIBLE (centre = 200,140 sur 800x600 de l'hôte)
	var vs: Vector2 = root.get_visible_rect().size
	var n := Vector2(200.0 / vs.x, 140.0 / vs.y)
	cli.call("send_mouse", n, 1, true); await create_timer(0.2).timeout
	cli.call("send_mouse", n, 1, false); await create_timer(0.6).timeout
	print("RD clic rejoué: pressed=", pressed, " injected=", host.get("injected"))
	cli.call("_client_close")
	await create_timer(0.5).timeout
	host.call("_toggle_share")
	quit()
