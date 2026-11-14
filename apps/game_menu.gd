class_name GameMenu
extends Control
## Menu commun des jeux : « Contre l'IA », « À deux (même écran) », « Multijoueur (réseau local) ».
## Gère aussi tout le réseau (balises UDP + TCP direct, sans serveur ni compte ; non chiffré : réseau de confiance).
## Un jeu l'utilise ainsi :
##   var m := GameMenu.new(); m.game_id = "chess"; m.title = "Échecs"; m.modes = ["ai", "local", "net"]
##   m.chosen.connect(...)       # "ai" ou "local"
##   m.net_started.connect(...)  # (slot 0|1, nom de l'adversaire) : la partie réseau commence
##   m.net_msg.connect(...)      # message reçu (Dictionary) ; m.send({...}) pour en envoyer
##   m.net_closed.connect(...)   # connexion perdue / adversaire parti
## Ports : UDP/TCP dérivés de l'identifiant du jeu (ou fixés par udp_port / tcp_port).

signal chosen(mode: String)
signal net_started(slot: int, peer_name: String)
signal net_msg(d: Dictionary)
signal net_closed(reason: String)

const MUTED := Color("8f9bb3")
const PORTS := {"chess": 4352, "hika": 4354}   # UDP = n, TCP = n + 1

var game_id := "game"
var title := "Jeu"
var modes: Array = ["ai", "local", "net"]
var disabled_modes := {}        # mode -> texte (ex. {"net": "bientôt"})
var udp_port := 0
var tcp_port := 0
var my_name := ""

var udp := PacketPeerUDP.new()
var server := TCPServer.new()
var conn: StreamPeerTCP
var buf := ""
var outq: Array = []
var state := "menu"             # menu | lobby | out | in | play
var my_id := str(randi())
var peers := {}                 # id -> {ip, port, name, busy, t}
var peer_name := ""
var inc_slot := 0
var beacon_t := 0.0
var sig := ""
var box: VBoxContainer
var head: Label
var inc_row: HBoxContainer

func _ready() -> void:
	if udp_port == 0: udp_port = PORTS.get(game_id, 4400 + game_id.hash() % 100 * 2)
	if tcp_port == 0: tcp_port = udp_port + 1
	if my_name == "": my_name = _device_name()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new(); bg.color = Color(0.09, 0.10, 0.15, 1.0); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var cc := CenterContainer.new(); cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(cc)
	box = VBoxContainer.new(); box.custom_minimum_size.x = 340; box.add_theme_constant_override("separation", 10); cc.add_child(box)
	_build_menu()

func _exit_tree() -> void: _net_stop()

func _device_name() -> String:
	var n := ""
	if OS.get_name() == "Android": n = OS.get_model_name()
	for k in ["HOSTNAME", "HOST", "COMPUTERNAME"]:
		if n == "": n = OS.get_environment(k)
	if n == "" and FileAccess.file_exists("/etc/hostname"): n = FileAccess.get_file_as_string("/etc/hostname").strip_edges()
	return n.substr(0, 24) if n != "" else "Joueur"

# ---------------------------------------------------------------- Écrans

func _clear() -> void:
	for c in box.get_children(): c.queue_free()

func _label(t: String, sz := 16, col := Color.WHITE) -> Label:
	var l := Label.new(); l.text = t; l.add_theme_font_size_override("font_size", sz); l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; return l

func _btn(t: String, cb: Callable, dis := false) -> Button:
	var b := Button.new(); b.text = t; b.custom_minimum_size.y = 50; b.disabled = dis; b.pressed.connect(cb); box.add_child(b); return b

## Affiche (ou réaffiche) le menu principal ; coupe toute connexion en cours.
func show_menu() -> void:
	_net_stop(); state = "menu"; visible = true; _build_menu()

func _build_menu() -> void:
	_clear()
	box.add_child(_label(title, 38))
	box.add_child(_label("Choisis un mode de jeu", 15, MUTED))
	var labels := {"ai": "Contre l'IA", "local": "À deux (même écran)", "net": "Multijoueur (réseau local)"}
	for m in modes:
		var dis := disabled_modes.has(m)
		_btn(labels.get(m, m) + ("  — " + disabled_modes[m] if dis else ""), _pick.bind(m), dis)

func _pick(m: String) -> void:
	if m == "net": _open_lobby(); return
	visible = false; chosen.emit(m)

func _open_lobby() -> void:
	if server.listen(tcp_port) != OK:
		_build_menu(); box.add_child(_label("Port %d indisponible : réseau impossible." % tcp_port, 14, Color("f87171"))); return
	state = "lobby"; peers = {}; sig = "x"; _build_lobby()

func _build_lobby() -> void:
	_clear()
	box.add_child(_label("Multijoueur — " + title, 28))
	head = _label("", 15, MUTED); box.add_child(head)
	if state == "lobby":
		for k in peers:
			var p: Dictionary = peers[k]
			_btn("Défier " + p["name"] + ("  (en partie)" if p["busy"] else ""), _challenge.bind(k), p["busy"])
	elif state == "in":
		box.add_child(_label("%s te défie !" % peer_name, 20))
		inc_row = HBoxContainer.new(); inc_row.add_theme_constant_override("separation", 8); box.add_child(inc_row)
		for it in [["Accepter", _accept], ["Refuser", _decline]]:
			var b := Button.new(); b.text = it[0]; b.custom_minimum_size.y = 46; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.pressed.connect(it[1]); inc_row.add_child(b)
	_btn("Retour", show_menu)
	_set_head()

func _set_head() -> void:
	if head == null: return
	match state:
		"lobby": head.text = "Joueurs trouvés sur le réseau local :" if not peers.is_empty() else "Recherche de joueurs sur le réseau local…\n(l'autre joueur doit ouvrir ce même jeu en mode Multijoueur)"
		"out": head.text = "Défi envoyé à %s… en attente de réponse." % peer_name
		"in": head.text = "Tu joueras les %s." % ("premiers" if inc_slot == 0 else "seconds")

# ---------------------------------------------------------------- Réseau

func _broadcast_addrs() -> PackedStringArray:
	var out: PackedStringArray = ["255.255.255.255"]
	for a in IP.get_local_addresses():
		if a.contains(".") and not a.begins_with("127.") and not a.begins_with("169.254"): out.append(a.substr(0, a.rfind(".")) + ".255")
	return out

func _net_stop() -> void:
	if conn:
		send({"t": "bye"}); conn.poll(); _flush(); conn.disconnect_from_host(); conn = null
	server.stop(); udp.close(); buf = ""; outq = []; peers = {}

func _flush() -> void:
	if conn and conn.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		while not outq.is_empty(): conn.put_data(outq.pop_front().to_utf8_buffer())

## Envoie un message à l'adversaire (Dictionary JSON).
func send(d: Dictionary) -> void:
	outq.append(JSON.stringify(d) + "\n")

## Connexion directe (aussi utilisée par les tests) : défie l'hôte ip:port.
func connect_to(ip: String, port: int, nm := "Adversaire") -> void:
	if conn != null: return
	conn = StreamPeerTCP.new(); buf = ""; outq = []
	if conn.connect_to_host(ip, port) != OK: conn = null; return
	peer_name = nm; state = "out"
	send({"t": "challenge", "name": my_name, "slot": randi() % 2})   # slot = place de l'adversaire ; la mienne est l'autre
	inc_slot = 1 - int(JSON.parse_string(outq[0])["slot"])
	_build_lobby()

func _challenge(id: String) -> void:
	connect_to(peers[id]["ip"], peers[id]["port"], peers[id]["name"])

func _accept() -> void:
	send({"t": "accept"}); _flush(); _begin()

func _decline() -> void:
	send({"t": "decline"}); _flush(); _drop("")

func _begin() -> void:
	state = "play"; visible = false; net_started.emit(inc_slot, peer_name)

func _drop(msg: String) -> void:
	if conn: conn.poll(); conn.disconnect_from_host()
	conn = null; buf = ""; outq = []
	state = "lobby"; sig = "x"; visible = true; _build_lobby()
	if msg != "": head.text = msg

func _process(delta: float) -> void:
	if state == "menu": return
	var now := Time.get_ticks_msec() / 1000.0
	if not udp.is_bound() and udp.bind(udp_port) == OK: udp.set_broadcast_enabled(true)
	beacon_t -= delta
	if beacon_t <= 0.0 and udp.is_bound():
		beacon_t = 2.0
		var msg := ("%s|%s|%d|%d|%s" % [game_id, my_id, tcp_port, 0 if state == "lobby" else 1, my_name.replace("|", " ")]).to_utf8_buffer()
		for a in _broadcast_addrs(): udp.set_dest_address(a, udp_port); udp.put_packet(msg)
	while udp.is_bound() and udp.get_available_packet_count() > 0:
		var parts := udp.get_packet().get_string_from_utf8().split("|", true, 4)
		var ip := udp.get_packet_ip()
		if parts.size() < 5 or parts[0] != game_id or parts[1] == my_id: continue
		peers[parts[1]] = {"ip": ip, "port": parts[2].to_int(), "busy": parts[3] == "1", "name": parts[4].substr(0, 24), "t": now}
	for k in peers.keys():
		if now - peers[k]["t"] > 7.0: peers.erase(k)
	var s := state
	for k in peers: s += "|" + k + peers[k]["name"] + str(peers[k]["busy"])
	if s != sig and state == "lobby": sig = s; _build_lobby()
	while server.is_connection_available():
		var p := server.take_connection()
		if conn == null and state == "lobby": conn = p; buf = ""; outq = []
		else: p.disconnect_from_host()
	if conn == null: return
	conn.poll()
	var st := conn.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTED:
		_flush()
		var n := conn.get_available_bytes()
		if n > 0: buf += conn.get_data(n)[1].get_string_from_utf8()
		while buf.contains("\n"):
			var i := buf.find("\n"); var line := buf.substr(0, i); buf = buf.substr(i + 1)
			var d = JSON.parse_string(line)
			if d is Dictionary: _on_msg(d)
			if conn == null: return
	elif st == StreamPeerTCP.STATUS_NONE or st == StreamPeerTCP.STATUS_ERROR:
		_lost()

func _on_msg(d: Dictionary) -> void:
	var t := str(d.get("t", ""))
	if state == "play":
		if t == "bye": _lost()
		else: net_msg.emit(d)
		return
	match t:
		"challenge":
			if state != "lobby": send({"t": "decline"}); return
			peer_name = str(d.get("name", "Joueur")).substr(0, 24); inc_slot = 1 if int(d.get("slot", 0)) == 1 else 0
			state = "in"; _build_lobby()
		"accept": if state == "out": _begin()
		"decline": if state == "out": _drop("%s a refusé le défi." % peer_name)
		"bye": _lost()

func _lost() -> void:
	if state == "play":
		if conn: conn.disconnect_from_host()
		conn = null; net_closed.emit("%s s'est déconnecté." % peer_name)
	else: _drop("Connexion perdue." if state == "out" else "")
