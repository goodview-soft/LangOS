extends Control
const UI = preload("res://apps/ui.gd")
## RemoteDesk : voir et piloter le LangOS d'un autre appareil du réseau local.
## L'hôte capture l'image de sa fenêtre LangOS (JPEG) ; le client renvoie souris, clavier et toucher, rejoués dans l'hôte.
## Accès protégé par un code à 6 chiffres affiché sur l'hôte. Flux non chiffré : réseau de confiance seulement.

const BEACON := "RD1"
const MAX_W := 1280

var udp_port := 4353
var tcp_port := 4352
var my_id := str(randi())
var my_name := ""
var udp := PacketPeerUDP.new()
var server := TCPServer.new()
var sharing := false
var code := ""
var hconn = null            # connexion cliente authentifiée côté hôte
var pend: Array = []        # connexions entrantes pas encore authentifiées
var bad := {}               # ip -> [essais, bloqué jusqu'à]
var cconn = null            # connexion côté client
var found := {}             # id -> {ip, port, name, t}
var beacon_t := 0.0
var frame_t := 0.0
var last_hash := 0
var last_sent := 0.0
var rem_w := 0
var rem_h := 0
var injected := 0
var cursor_pos := Vector2.ZERO
var mask := 0
var move_pending := false
var move_norm := Vector2.ZERO
var move_t := 0.0
var overlay: Control
var cur_host_name := ""

var home: Control
var view_box: Control
var viewer: TextureRect
var status: Label
var share_btn: Button
var code_lbl: Label
var host_state: Label
var found_box: VBoxContainer
var ip_edit: LineEdit
var code_edit: LineEdit
var conn_btn: Button
var tex: ImageTexture
var sig := ""


func _ready() -> void:
	my_name = _device_name()
	_build_ui()


func _exit_tree() -> void:
	_stop_share(); _client_close()
	udp.close()


func _device_name() -> String:
	var n := ""
	if OS.get_name() == "Android": n = OS.get_model_name()
	for k in ["HOSTNAME", "HOST", "COMPUTERNAME"]:
		if n == "": n = OS.get_environment(k)
	if n == "" and FileAccess.file_exists("/etc/hostname"): n = FileAccess.get_file_as_string("/etc/hostname").strip_edges()
	return n if n != "" else "Appareil"


# ---------------------------------------------------------------- UI

func _sb(c: Color, r := 12, m := 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = c; s.set_corner_radius_all(r); s.set_content_margin_all(m)
	return s


func _btn(t: String, cb: Callable, variation := "", w := 0, h := 0) -> Button:
	var b := Button.new(); b.text = t; b.focus_mode = Control.FOCUS_NONE
	if variation != "": b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(w, h); b.pressed.connect(cb)
	return b


func _build_ui() -> void:
	var m := MarginContainer.new(); m.set_anchors_preset(PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 14)
	add_child(m)
	var root := VBoxContainer.new(); root.add_theme_constant_override("separation", 10); m.add_child(root)
	status = Label.new(); status.add_theme_font_size_override("font_size", 14); status.theme_type_variation = "Muted"; root.add_child(status)
	home = HBoxContainer.new(); home.size_flags_vertical = SIZE_EXPAND_FILL; home.add_theme_constant_override("separation", 14); root.add_child(home)
	# Carte hôte
	var c1 := PanelContainer.new(); c1.size_flags_horizontal = SIZE_EXPAND_FILL; UI.style(c1, "panel", func(): return _sb(UI.p("card"), UI.rad(), 16)); home.add_child(c1)
	var v1 := VBoxContainer.new(); v1.add_theme_constant_override("separation", 12); c1.add_child(v1)
	var t1 := Label.new(); t1.text = "Partager cet écran"; t1.add_theme_font_size_override("font_size", 22); v1.add_child(t1)
	var d1 := Label.new(); d1.text = "Un autre appareil pourra voir et piloter LangOS ici, avec le code ci-dessous."
	d1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; d1.theme_type_variation = "Muted"; v1.add_child(d1)
	code_lbl = Label.new(); code_lbl.text = "— — —   — — —"; code_lbl.add_theme_font_size_override("font_size", 40)
	code_lbl.add_theme_color_override("font_color", UI.accent()); code_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v1.add_child(code_lbl)
	host_state = Label.new(); host_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; host_state.theme_type_variation = "Muted"; v1.add_child(host_state)
	share_btn = _btn("Activer le partage", _toggle_share, "Accent", 0, 48); v1.add_child(share_btn)
	# Carte client
	var c2 := PanelContainer.new(); c2.size_flags_horizontal = SIZE_EXPAND_FILL; UI.style(c2, "panel", func(): return _sb(UI.p("card"), UI.rad(), 16)); home.add_child(c2)
	var v2 := VBoxContainer.new(); v2.add_theme_constant_override("separation", 10); c2.add_child(v2)
	var t2 := Label.new(); t2.text = "Se connecter à un appareil"; t2.add_theme_font_size_override("font_size", 22); v2.add_child(t2)
	found_box = VBoxContainer.new(); found_box.add_theme_constant_override("separation", 4); v2.add_child(found_box)
	var l3 := Label.new(); l3.text = "ou adresse IP"; l3.theme_type_variation = "Muted"; v2.add_child(l3)
	ip_edit = LineEdit.new(); ip_edit.placeholder_text = "192.168.1.20"; ip_edit.virtual_keyboard_enabled = false; v2.add_child(ip_edit)
	var l4 := Label.new(); l4.text = "Code à 6 chiffres affiché sur l'appareil"; l4.theme_type_variation = "Muted"; v2.add_child(l4)
	code_edit = LineEdit.new(); code_edit.placeholder_text = "123456"; code_edit.max_length = 6; code_edit.virtual_keyboard_enabled = false
	code_edit.add_theme_font_size_override("font_size", 26); v2.add_child(code_edit)
	conn_btn = _btn("Se connecter", _connect_pressed, "Accent", 0, 48); v2.add_child(conn_btn)
	# Vue distante
	view_box = VBoxContainer.new(); view_box.size_flags_vertical = SIZE_EXPAND_FILL; view_box.visible = false; root.add_child(view_box)
	var tb := HBoxContainer.new(); tb.add_theme_constant_override("separation", 8); view_box.add_child(tb)
	var tl := Label.new(); tl.text = "Contrôle à distance"; tl.size_flags_horizontal = SIZE_EXPAND_FILL; tb.add_child(tl)
	tb.add_child(_btn("Déconnecter", _client_close, "Close", 140, 40))
	var pc := PanelContainer.new(); pc.size_flags_vertical = SIZE_EXPAND_FILL; pc.add_theme_stylebox_override("panel", _sb(Color.BLACK, 8, 2)); view_box.add_child(pc)
	viewer = TextureRect.new(); viewer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; viewer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	viewer.focus_mode = Control.FOCUS_ALL; viewer.mouse_filter = Control.MOUSE_FILTER_STOP
	viewer.set_meta("remote", self); viewer.gui_input.connect(_viewer_input); pc.add_child(viewer)


func _set_status(t: String) -> void:
	if status: status.text = t


func _rebuild_found() -> void:
	for c in found_box.get_children(): c.queue_free()
	for id in found:
		var f: Dictionary = found[id]
		var b := _btn("🖥  %s   (%s)" % [f["name"], f["ip"]], func(): ip_edit.text = f["ip"]; code_edit.grab_focus(), "Flat")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT; found_box.add_child(b)
	if found.is_empty():
		found_box.add_child(UI.empty_state("Aucun appareil en partage trouvé"))


# ---------------------------------------------------------------- Hôte

func _toggle_share() -> void:
	if sharing: _stop_share()
	else: _start_share()


func _start_share() -> void:
	if server.listen(tcp_port) != OK:
		_set_status("Port %d indisponible." % tcp_port); return
	code = "%06d" % randi_range(0, 999999)
	sharing = true
	code_lbl.text = code.substr(0, 3) + "   " + code.substr(3)
	share_btn.text = "Arrêter le partage"; host_state.text = "En attente d'une connexion…"
	beacon_t = 0.0


func _stop_share() -> void:
	if not sharing: return
	sharing = false
	_host_drop()
	for c in pend: c["p"].disconnect_from_host()
	pend.clear(); server.stop()
	if share_btn:
		share_btn.text = "Activer le partage"; code_lbl.text = "— — —   — — —"; host_state.text = ""


func _host_drop() -> void:
	if hconn: hconn["p"].disconnect_from_host()
	hconn = null
	if is_instance_valid(overlay): overlay.queue_free()
	if sharing and host_state: host_state.text = "En attente d'une connexion…"


func _show_overlay(name: String) -> void:
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	overlay = Control.new(); overlay.set_anchors_preset(Control.PRESET_FULL_RECT); overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 4000
	host.add_child(overlay)
	var bar := PanelContainer.new(); bar.add_theme_stylebox_override("panel", _sb(Color("b3261e"), UI.rad(), 8))
	bar.theme = UI.bubble_theme(true); overlay.add_child(bar)
	var h := HBoxContainer.new(); bar.add_child(h)
	var l := Label.new(); l.text = "🔴  Contrôlé à distance par %s" % name; h.add_child(l)
	h.add_child(_btn("Couper", _host_drop, "Flat", 90, 40))
	bar.position = Vector2(20, 8)
	overlay.draw.connect(func():
		var p := cursor_pos
		overlay.draw_colored_polygon(PackedVector2Array([p, p + Vector2(0, 20), p + Vector2(5, 15), p + Vector2(11, 24), p + Vector2(15, 22), p + Vector2(9, 13), p + Vector2(16, 13)]), Color(1, 1, 1))
		overlay.draw_polyline(PackedVector2Array([p, p + Vector2(0, 20), p + Vector2(5, 15), p + Vector2(11, 24), p + Vector2(15, 22), p + Vector2(9, 13), p + Vector2(16, 13), p]), Color.BLACK, 1.5))


func _capture() -> void:
	if hconn == null or not hconn.get("auth", false): return
	var now := Time.get_ticks_msec() / 1000.0
	if now - frame_t < 0.09 or hconn["out"].size() > 600000: return
	frame_t = now
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty(): return
	var w := img.get_width(); var h := img.get_height()
	if w > MAX_W: img.resize(MAX_W, int(h * float(MAX_W) / w), Image.INTERPOLATE_BILINEAR)
	if img.get_format() != Image.FORMAT_RGB8: img.convert(Image.FORMAT_RGB8)
	var hs: int = hash(img.get_data())
	if hs == last_hash and now - last_sent < 1.0: return
	last_hash = hs; last_sent = now
	var jpg := img.save_jpg_to_buffer(0.6)
	_send(hconn, {"t": "frame", "w": w, "h": h}, jpg)


func _inject(h: Dictionary) -> void:
	var vs := get_viewport().get_visible_rect().size
	var t := str(h.get("t", ""))
	if t == "move" or t == "btn":
		var pos := Vector2(float(h.get("x", 0)) * vs.x, float(h.get("y", 0)) * vs.y)
		var ev: InputEvent
		if t == "move":
			var mv := InputEventMouseMotion.new(); mv.relative = pos - cursor_pos; mv.button_mask = mask; ev = mv
		else:
			var b := InputEventMouseButton.new(); b.button_index = int(h.get("b", 1)); b.pressed = bool(h.get("p", false)); b.double_click = bool(h.get("dc", false))
			var bit := 1 << (b.button_index - 1)
			if b.button_index <= 3: mask = (mask | bit) if b.pressed else (mask & ~bit)
			b.button_mask = mask; b.factor = 1.0; ev = b
		ev.position = pos; ev.global_position = pos
		cursor_pos = pos
		Input.parse_input_event(ev)
		if is_instance_valid(overlay): overlay.queue_redraw()
		injected += 1
	elif t == "key":
		var k := InputEventKey.new(); k.keycode = int(h.get("k", 0)) as Key; k.physical_keycode = k.keycode
		k.unicode = int(h.get("u", 0)); k.pressed = bool(h.get("p", false))
		k.shift_pressed = bool(h.get("s", false)); k.ctrl_pressed = bool(h.get("c", false)); k.alt_pressed = bool(h.get("a", false))
		Input.parse_input_event(k); injected += 1
	elif t == "text":
		for ch in str(h.get("s", "")).substr(0, 200):
			var code_pt := ch.unicode_at(0)
			var kk := InputEventKey.new()
			if ch == "\n": kk.keycode = KEY_ENTER; kk.unicode = 0
			else: kk.keycode = code_pt as Key; kk.unicode = code_pt
			for pr in [true, false]:
				kk = kk.duplicate(); kk.pressed = pr; Input.parse_input_event(kk)
		injected += 1


# ---------------------------------------------------------------- Client

func _connect_pressed() -> void:
	var ip := ip_edit.text.strip_edges()
	if not ip.is_valid_ip_address() or code_edit.text.length() != 6:
		_set_status("Adresse IP et code à 6 chiffres requis."); return
	_client_close()
	var p := StreamPeerTCP.new()
	if p.connect_to_host(ip, tcp_port) != OK: _set_status("Connexion impossible."); return
	cconn = {"p": p, "buf": PackedByteArray(), "out": PackedByteArray(), "hello": false, "auth": false, "t": Time.get_ticks_msec() / 1000.0}
	_set_status("Connexion à %s…" % ip)


func _client_close() -> void:
	if cconn: cconn["p"].disconnect_from_host()
	cconn = null
	if view_box:
		view_box.visible = false; home.visible = true


func _viewer_to_norm(pos: Vector2) -> Vector2:
	if rem_w <= 0 or rem_h <= 0: return Vector2(-1, -1)
	var sc := minf(viewer.size.x / rem_w, viewer.size.y / rem_h)
	var off := (viewer.size - Vector2(rem_w, rem_h) * sc) / 2.0
	var n := (pos - off) / (Vector2(rem_w, rem_h) * sc)
	return n


func _viewer_input(ev: InputEvent) -> void:
	if cconn == null or not cconn["auth"]: return
	if ev is InputEventMouseMotion:
		var n := _viewer_to_norm(ev.position)
		if n.x >= 0 and n.x <= 1 and n.y >= 0 and n.y <= 1: move_norm = n; move_pending = true
	elif ev is InputEventMouseButton:
		viewer.grab_focus()
		var n := _viewer_to_norm(ev.position)
		if n.x < 0 or n.x > 1 or n.y < 0 or n.y > 1: return
		send_mouse(n, ev.button_index, ev.pressed, ev.double_click)
	elif ev is InputEventKey:
		viewer.accept_event()
		_send(cconn, {"t": "key", "k": ev.keycode, "u": ev.unicode, "p": ev.pressed, "s": ev.shift_pressed, "c": ev.ctrl_pressed, "a": ev.alt_pressed})


func send_mouse(n: Vector2, b: int, pressed: bool, dc := false) -> void:
	if cconn == null: return
	_send(cconn, {"t": "move", "x": n.x, "y": n.y})
	_send(cconn, {"t": "btn", "x": n.x, "y": n.y, "b": b, "p": pressed, "dc": dc})


## Appelés par le clavier visuel de LangOS quand la vue distante a le focus.
func send_text(s: String) -> void:
	if cconn and cconn["auth"]: _send(cconn, {"t": "text", "s": s})


func send_key(k: int) -> void:
	if cconn and cconn["auth"]:
		for pr in [true, false]: _send(cconn, {"t": "key", "k": k, "u": 0, "p": pr})


# ---------------------------------------------------------------- Réseau commun

func _frame(h: Dictionary, body := PackedByteArray()) -> PackedByteArray:
	h["n"] = body.size()
	var hb := JSON.stringify(h).to_utf8_buffer()
	var out := PackedByteArray(); out.resize(4); out.encode_u32(0, hb.size())
	out.append_array(hb); out.append_array(body)
	return out


func _send(c: Dictionary, h: Dictionary, body := PackedByteArray()) -> void:
	c["out"].append_array(_frame(h, body))


func _pump(c: Dictionary) -> bool:
	var p: StreamPeerTCP = c["p"]
	p.poll()
	var st := p.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTING: return true
	if st != StreamPeerTCP.STATUS_CONNECTED: return false
	if c["out"].size() > 0:
		var r := p.put_partial_data(c["out"])
		if r[0] == OK and r[1] > 0: c["out"] = c["out"].slice(r[1])
	var avail := p.get_available_bytes()
	if avail > 0:
		var d := p.get_partial_data(mini(avail, 1048576))
		if d[0] == OK: c["buf"].append_array(d[1])
	return true


func _frames(c: Dictionary) -> Array:
	var out := []
	while true:
		var buf: PackedByteArray = c["buf"]
		if buf.size() < 4: break
		var hl := buf.decode_u32(0)
		if hl > 65536: c["p"].disconnect_from_host(); c["buf"] = PackedByteArray(); break
		if buf.size() < 4 + hl: break
		var h = JSON.parse_string(buf.slice(4, 4 + hl).get_string_from_utf8())
		var n := int(h.get("n", 0)) if h is Dictionary else 0
		if n < 0 or n > 4000000: c["p"].disconnect_from_host(); c["buf"] = PackedByteArray(); break
		if buf.size() < 4 + hl + n: break
		var body := buf.slice(4 + hl, 4 + hl + n)
		c["buf"] = buf.slice(4 + hl + n)
		if h is Dictionary: out.append([h, body])
	return out


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_discovery(now, delta)
	# Hôte : nouvelles connexions
	if sharing:
		while server.is_connection_available():
			var p := server.take_connection()
			pend.append({"p": p, "buf": PackedByteArray(), "out": PackedByteArray(), "auth": false, "t": now, "ip": p.get_connected_host()})
		for c in pend.duplicate():
			var alive := _pump(c)
			for f in _frames(c): _host_hello(c, f[0])
			if c.get("done", false) or not alive or now - c["t"] > 10.0:
				pend.erase(c)
				if not c.get("keep", false): c["p"].disconnect_from_host()
		if hconn:
			if not _pump(hconn): _host_drop()
			else:
				for f in _frames(hconn): _inject(f[0])
				_capture()
	# Client
	if cconn:
		if not _pump(cconn):
			var was: bool = cconn["auth"]
			cconn = null; home.visible = true; view_box.visible = false
			_set_status("Connexion perdue." if was else "Connexion impossible (partage actif sur l'autre appareil ?).")
		else:
			if cconn["p"].get_status() == StreamPeerTCP.STATUS_CONNECTED and not cconn["hello"]:
				cconn["hello"] = true
				_send(cconn, {"t": "hello", "code": code_edit.text, "name": my_name})
			for f in _frames(cconn): _client_handle(f[0], f[1])
			if move_pending and now - move_t > 0.033 and cconn["auth"]:
				move_pending = false; move_t = now
				_send(cconn, {"t": "move", "x": move_norm.x, "y": move_norm.y})


func _host_hello(c: Dictionary, h: Dictionary) -> void:
	if str(h.get("t", "")) != "hello" or c.get("done", false): return
	var ip: String = c["ip"]
	var b: Array = bad.get(ip, [0, 0.0])
	var now := Time.get_ticks_msec() / 1000.0
	var ok: bool = str(h.get("code", "")) == code and now >= b[1] and hconn == null
	if ok:
		c["auth"] = true; c["done"] = true; c["keep"] = true
		hconn = c; bad.erase(ip)
		var vs := get_viewport().get_visible_rect().size
		_send(c, {"t": "ok", "w": int(vs.x), "h": int(vs.y)})
		cur_host_name = str(h.get("name", "?")).substr(0, 24)
		host_state.text = "Contrôlé par %s" % cur_host_name
		_show_overlay(cur_host_name)
	else:
		b[0] += 1
		if b[0] >= 3: b = [0, now + 60.0]
		bad[ip] = b
		_send(c, {"t": "deny"}); c["done"] = true
		c["p"].poll(); c["p"].put_data(c["out"]); c["out"] = PackedByteArray()
		host_state.text = "Tentative refusée depuis %s" % ip


func _client_handle(h: Dictionary, body: PackedByteArray) -> void:
	match str(h.get("t", "")):
		"ok":
			cconn["auth"] = true
			rem_w = int(h.get("w", 0)); rem_h = int(h.get("h", 0))
			home.visible = false; view_box.visible = true
			_set_status("Connecté. Clique dans l'image pour piloter ; le clavier visuel de LangOS tape à distance.")
		"deny":
			_set_status("Code refusé (ou trop d'essais : attendre 1 minute).")
			cconn["p"].disconnect_from_host(); cconn = null
		"frame":
			var img := Image.new()
			if img.load_jpg_from_buffer(body) == OK:
				rem_w = int(h.get("w", rem_w)); rem_h = int(h.get("h", rem_h))
				if tex == null or Vector2i(tex.get_size()) != img.get_size():
					tex = ImageTexture.create_from_image(img); viewer.texture = tex
				else: tex.update(img)


# ---------------------------------------------------------------- Découverte

func _broadcast_addrs() -> PackedStringArray:
	var out: PackedStringArray = ["255.255.255.255"]
	for a in IP.get_local_addresses():
		if a.contains(".") and not a.begins_with("127.") and not a.begins_with("169.254"):
			out.append(a.substr(0, a.rfind(".")) + ".255")
	return out


func _discovery(now: float, delta: float) -> void:
	if not udp.is_bound():
		if udp.bind(udp_port) != OK: return
		udp.set_broadcast_enabled(true)
	beacon_t -= delta
	if beacon_t <= 0.0:
		beacon_t = 2.0
		if sharing:
			var msg := ("%s|%s|%d|%s" % [BEACON, my_id, tcp_port, my_name.replace("|", " ")]).to_utf8_buffer()
			for b in _broadcast_addrs():
				udp.set_dest_address(b, udp_port); udp.put_packet(msg)
	while udp.get_available_packet_count() > 0:
		var parts := udp.get_packet().get_string_from_utf8().split("|", true, 3)
		var ip := udp.get_packet_ip()
		if parts.size() < 4 or parts[0] != BEACON or parts[1] == my_id: continue
		found[parts[1]] = {"ip": ip, "port": parts[2].to_int(), "name": parts[3].substr(0, 24), "t": now}
	for k in found.keys():
		if now - found[k]["t"] > 7.0: found.erase(k)
	var s := ""
	for k in found: s += "%s%s" % [k, found[k]["name"]]
	if s != sig: sig = s; _rebuild_found()
