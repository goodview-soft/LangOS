extends Control
## Messenger : discussion et échange de fichiers (images, vidéos, musique…) entre appareils du réseau local.
## Découverte : balises UDP en broadcast (port 4350). Échanges : TCP direct (port 4351), sans serveur ni compte.
## Les fichiers reçus demandent toujours une acceptation. Les échanges ne sont pas chiffrés : réseau de confiance seulement.

const BEACON := "LM1"
const CHUNK := 524288
const ACCENT := Color("5aa2ff")
const MUTED := Color("8f9bb3")
const STATUS := [["En ligne", "#34d399"], ["Absent", "#fbbf24"], ["Occupé", "#f87171"], ["Invisible", "#6b7488"]]
const IMG_EXT := ["png", "jpg", "jpeg", "webp", "bmp", "gif"]

var udp_port := 4350
var tcp_port := 4351
var data_dir := "user://chat"
var recv_dir := "user://received"
var my_id := ""
var my_name := ""
var my_status := 0
var udp := PacketPeerUDP.new()
var server := TCPServer.new()
var beacon_t := 0.0
var peers := {}      # id -> {ip, port, name, status, t}
var known := {}      # id -> nom (contacts déjà vus)
var conns := {}      # id -> conn
var pending: Array = []   # connexions entrantes sans identité
var msgs := {}       # id -> Array de messages
var unread := {}
var offers := {}     # fid -> {id, path, size, msg}
var cur := ""
var sig := ""
var shake_tw: Tween

var name_edit: LineEdit
var status_opt: OptionButton
var contacts_box: VBoxContainer
var head_lbl: Label
var chat_box: VBoxContainer
var scroll: ScrollContainer
var input: LineEdit
var note: Label
var player: AudioStreamPlayer
var dialog: FileDialog


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(data_dir); DirAccess.make_dir_recursive_absolute(recv_dir)
	var c := ConfigFile.new(); c.load(data_dir + "/profile.cfg")
	my_id = str(c.get_value("me", "id", "")); if my_id == "": my_id = str(randi())
	my_name = str(c.get_value("me", "name", _device_name()))
	my_status = int(c.get_value("me", "status", 0))
	if FileAccess.file_exists(data_dir + "/contacts.json"):
		var d = JSON.parse_string(FileAccess.get_file_as_string(data_dir + "/contacts.json"))
		if d is Dictionary: known = d
	player = AudioStreamPlayer.new(); add_child(player)
	_build_ui()
	if server.listen(tcp_port) != OK: note.text = "Port %d indisponible : réception impossible." % tcp_port
	_save_profile()
	_rebuild_contacts()


func _exit_tree() -> void:
	for id in conns.keys(): _drop(id)
	server.stop(); udp.close()
	_save_profile()


func _device_name() -> String:
	var n := ""
	if OS.get_name() == "Android": n = OS.get_model_name()
	for k in ["HOSTNAME", "HOST", "COMPUTERNAME"]:
		if n == "": n = OS.get_environment(k)
	if n == "" and FileAccess.file_exists("/etc/hostname"): n = FileAccess.get_file_as_string("/etc/hostname").strip_edges()
	return n if n != "" else "Mon appareil"


func _save_profile() -> void:
	var c := ConfigFile.new()
	c.set_value("me", "id", my_id); c.set_value("me", "name", my_name); c.set_value("me", "status", my_status)
	c.save(data_dir + "/profile.cfg")
	var f := FileAccess.open(data_dir + "/contacts.json", FileAccess.WRITE); f.store_string(JSON.stringify(known)); f.close()


# ---------------------------------------------------------------- UI

func _btn(t: String, cb: Callable, variation := "", w := 0) -> Button:
	var b := Button.new(); b.text = t; b.focus_mode = Control.FOCUS_NONE
	if variation != "": b.theme_type_variation = variation
	if w > 0: b.custom_minimum_size.x = w
	b.pressed.connect(cb)
	return b


func _build_ui() -> void:
	var m := MarginContainer.new(); m.set_anchors_preset(PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 12)
	add_child(m)
	var root := HBoxContainer.new(); root.add_theme_constant_override("separation", 12); m.add_child(root)
	# Gauche : profil + contacts
	var left := VBoxContainer.new(); left.custom_minimum_size.x = 250; left.add_theme_constant_override("separation", 8); root.add_child(left)
	var prof := PanelContainer.new(); prof.add_theme_stylebox_override("panel", _sb(Color("1d2330"), 12, 10)); left.add_child(prof)
	var pv := VBoxContainer.new(); pv.add_theme_constant_override("separation", 6); prof.add_child(pv)
	name_edit = LineEdit.new(); name_edit.text = my_name; name_edit.virtual_keyboard_enabled = false
	name_edit.max_length = 24; name_edit.text_changed.connect(func(t: String): my_name = t.strip_edges() if t.strip_edges() != "" else _device_name(); _save_profile())
	pv.add_child(name_edit)
	status_opt = OptionButton.new(); status_opt.focus_mode = Control.FOCUS_NONE
	for s in STATUS: status_opt.add_item(s[0])
	status_opt.select(my_status)
	status_opt.item_selected.connect(func(i: int): my_status = i; _save_profile(); beacon_t = 0.0; _broadcast_status())
	pv.add_child(status_opt)
	var cs := Label.new(); cs.text = "Contacts"; cs.add_theme_color_override("font_color", MUTED); left.add_child(cs)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; left.add_child(sc)
	contacts_box = VBoxContainer.new(); contacts_box.size_flags_horizontal = SIZE_EXPAND_FILL; contacts_box.add_theme_constant_override("separation", 2); sc.add_child(contacts_box)
	left.add_child(_btn("📂 Dossier reçu", func(): OS.shell_show_in_file_manager(ProjectSettings.globalize_path(recv_dir)), "Flat"))
	# Droite : conversation
	var right := VBoxContainer.new(); right.size_flags_horizontal = SIZE_EXPAND_FILL; right.add_theme_constant_override("separation", 8); root.add_child(right)
	head_lbl = Label.new(); head_lbl.add_theme_font_size_override("font_size", 20); head_lbl.text = "Choisis un contact"; right.add_child(head_lbl)
	var pc := PanelContainer.new(); pc.size_flags_vertical = SIZE_EXPAND_FILL; pc.add_theme_stylebox_override("panel", _sb(Color("171b25"), 12, 8)); right.add_child(pc)
	scroll = ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; pc.add_child(scroll)
	chat_box = VBoxContainer.new(); chat_box.size_flags_horizontal = SIZE_EXPAND_FILL; chat_box.add_theme_constant_override("separation", 6); scroll.add_child(chat_box)
	note = Label.new(); note.add_theme_font_size_override("font_size", 13); note.add_theme_color_override("font_color", MUTED); right.add_child(note)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6); right.add_child(row)
	row.add_child(_btn("📎", _pick_files, "", 48))
	input = LineEdit.new(); input.placeholder_text = "Écrire un message…"; input.size_flags_horizontal = SIZE_EXPAND_FILL
	input.virtual_keyboard_enabled = false; input.text_submitted.connect(func(_t): _send_text()); row.add_child(input)
	row.add_child(_btn("📳", _send_nudge, "", 48))
	row.add_child(_btn("Envoyer", _send_text, "Accent"))
	dialog = FileDialog.new(); dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES; dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true; dialog.title = "Envoyer des fichiers"
	dialog.files_selected.connect(func(ps: PackedStringArray): for p in ps: _send_file(cur, p))
	add_child(dialog)


func _sb(c: Color, r: int, m: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = c; s.set_corner_radius_all(r); s.set_content_margin_all(m)
	return s


func _status_color(id: String) -> Color:
	if peers.has(id): return Color(STATUS[clampi(peers[id]["status"], 0, 2)][1])
	return Color("4b5263")


func _rebuild_contacts() -> void:
	for c in contacts_box.get_children(): c.queue_free()
	var ids := {}
	for id in peers: ids[id] = true
	for id in known: ids[id] = true
	var arr := ids.keys()
	arr.sort_custom(func(a, b): return (peers.has(a) and not peers.has(b)) or (peers.has(a) == peers.has(b) and str(_nm(a)) < str(_nm(b))))
	for id in arr:
		var b := Button.new(); b.focus_mode = Control.FOCUS_NONE; b.theme_type_variation = "Flat"; b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var n: int = unread.get(id, 0)
		b.text = "● %s%s" % [_nm(id), ("  (%d)" % n) if n > 0 else ""]
		b.add_theme_color_override("font_color", _status_color(id)); b.add_theme_color_override("font_hover_color", _status_color(id))
		b.add_theme_font_size_override("font_size", 17)
		if id == cur:
			var sb := _sb(Color(1, 1, 1, 0.1), 8, 8); b.add_theme_stylebox_override("normal", sb)
		b.pressed.connect(_select.bind(id))
		contacts_box.add_child(b)
	if arr.is_empty():
		var l := Label.new(); l.text = "Aucun appareil trouvé sur le réseau.\nL'autre appareil doit aussi ouvrir Messenger."
		l.add_theme_color_override("font_color", MUTED); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; contacts_box.add_child(l)


func _nm(id: String) -> String:
	if peers.has(id): return peers[id]["name"]
	return str(known.get(id, id))


func _select(id: String) -> void:
	cur = id; unread.erase(id)
	_load_hist(id)
	head_lbl.text = _nm(id)
	_rebuild_contacts(); _rebuild_chat()


# ---------------------------------------------------------------- Historique + bulles

func _hist_path(id: String) -> String:
	return "%s/%s.json" % [data_dir, id.validate_filename()]


func _load_hist(id: String) -> void:
	if msgs.has(id): return
	msgs[id] = []
	if FileAccess.file_exists(_hist_path(id)):
		var d = JSON.parse_string(FileAccess.get_file_as_string(_hist_path(id)))
		if d is Array: msgs[id] = d


func _save_hist(id: String) -> void:
	var arr: Array = msgs.get(id, [])
	if arr.size() > 300: arr = arr.slice(arr.size() - 300)
	var clean := []
	for m in arr:
		var c: Dictionary = m.duplicate(); c.erase("_lbl"); clean.append(c)
	var f := FileAccess.open(_hist_path(id), FileAccess.WRITE); f.store_string(JSON.stringify(clean)); f.close()


func _add_msg(id: String, m: Dictionary) -> void:
	_load_hist(id)
	m["ts"] = Time.get_unix_time_from_system()
	msgs[id].append(m)
	_save_hist(id)
	known[id] = _nm(id); _save_profile()
	if id == cur: _add_bubble(m); _scroll_end()
	else:
		unread[id] = unread.get(id, 0) + 1; _rebuild_contacts()


func _rebuild_chat() -> void:
	for c in chat_box.get_children(): c.queue_free()
	var arr: Array = msgs.get(cur, [])
	for m in arr.slice(maxi(0, arr.size() - 100)): _add_bubble(m)
	_scroll_end()


func _scroll_end() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scroll): scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _add_bubble(m: Dictionary) -> void:
	var mine: bool = m.get("from", "them") == "me"
	var kind: String = m.get("kind", "text")
	var row := HBoxContainer.new(); chat_box.add_child(row)
	if kind == "sys":
		var l := Label.new(); l.text = str(m.get("text", "")); l.add_theme_color_override("font_color", MUTED); l.add_theme_font_size_override("font_size", 13)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.size_flags_horizontal = SIZE_EXPAND_FILL; row.add_child(l); return
	if mine:
		var sp := Control.new(); sp.size_flags_horizontal = SIZE_EXPAND_FILL; row.add_child(sp)
	var bub := PanelContainer.new()
	bub.add_theme_stylebox_override("panel", _sb(Color("2b5fb8") if mine else Color("2a3040"), 14, 10))
	row.add_child(bub)
	if not mine:
		var sp2 := Control.new(); sp2.size_flags_horizontal = SIZE_EXPAND_FILL; row.add_child(sp2)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6); bub.add_child(v)
	var ts := Time.get_datetime_dict_from_unix_time(int(m.get("ts", 0)))
	if kind == "text":
		v.add_child(_wrap_label(str(m.get("text", ""))))
	elif kind == "nudge":
		v.add_child(_wrap_label("📳 " + ("Tu as envoyé un nudge" if mine else "%s te secoue !" % _nm(cur))))
	elif kind == "file":
		_file_bubble(v, m, mine)
	var tl := Label.new(); tl.text = "%02d:%02d" % [ts["hour"], ts["minute"]]; tl.add_theme_font_size_override("font_size", 11)
	tl.add_theme_color_override("font_color", Color(1, 1, 1, 0.5)); tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; v.add_child(tl)


func _wrap_label(t: String) -> RichTextLabel:
	var l := RichTextLabel.new(); l.text = t; l.fit_content = true; l.scroll_active = false
	l.selection_enabled = true; l.context_menu_enabled = true; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("normal_font_size", 17)
	var f := get_theme_default_font()
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	l.custom_minimum_size.x = clampf(w + 8, 40, 380)
	return l


func _file_bubble(v: VBoxContainer, m: Dictionary, mine: bool) -> void:
	var path: String = m.get("path", "")
	var name: String = m.get("name", "fichier")
	var ext := name.get_extension().to_lower()
	if ext in IMG_EXT and path != "" and FileAccess.file_exists(path) and m.get("state", "") == "done":
		var img := Image.load_from_file(ProjectSettings.globalize_path(path) if path.begins_with("user://") else path)
		if img != null:
			if img.get_width() > 320: img.resize(320, int(img.get_height() * 320.0 / img.get_width()))
			var tr := TextureRect.new(); tr.texture = ImageTexture.create_from_image(img); tr.stretch_mode = TextureRect.STRETCH_KEEP; v.add_child(tr)
	var icon := "🖼" if ext in IMG_EXT else ("🎵" if ext in ["mp3", "ogg", "wav", "flac", "m4a"] else ("🎬" if ext in ["mp4", "mkv", "webm", "avi", "mov"] else "📄"))
	var l := _wrap_label("%s %s  (%s)" % [icon, name, _human(int(m.get("size", 0)))]); v.add_child(l)
	var st := Label.new(); st.add_theme_font_size_override("font_size", 13); st.add_theme_color_override("font_color", Color(1, 1, 1, 0.65)); v.add_child(st)
	m["_lbl"] = st
	var state: String = m.get("state", "")
	match state:
		"offer_in":
			var r := HBoxContainer.new(); r.add_theme_constant_override("separation", 6); v.add_child(r)
			r.add_child(_btn("Accepter", _accept.bind(str(m["fid"])), "Accent")); r.add_child(_btn("Refuser", _reject.bind(str(m["fid"]))))
			st.text = "Fichier proposé"
		"offer_out": st.text = "En attente d'acceptation…"
		"progress": st.text = "%d %%" % int(m.get("pct", 0))
		"rejected": st.text = "Refusé"
		"failed": st.text = "Échec du transfert"
		"done":
			st.text = "Terminé ✓" if not mine else "Envoyé ✓"
			var r2 := HBoxContainer.new(); r2.add_theme_constant_override("separation", 6); v.add_child(r2)
			if ext in ["mp3", "ogg", "wav"] and path != "": r2.add_child(_btn("▶ Écouter", _play.bind(path)))
			if path != "": r2.add_child(_btn("Ouvrir", func(): OS.shell_open(ProjectSettings.globalize_path(path) if path.begins_with("user://") else path)))


func _human(n: int) -> String:
	if n < 1024: return "%d o" % n
	if n < 1048576: return "%.0f Ko" % (n / 1024.0)
	if n < 1073741824: return "%.1f Mo" % (n / 1048576.0)
	return "%.2f Go" % (n / 1073741824.0)


func _play(path: String) -> void:
	var g := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	var s: AudioStream = null
	match path.get_extension().to_lower():
		"mp3": s = AudioStreamMP3.load_from_file(g)
		"ogg": s = AudioStreamOggVorbis.load_from_file(g)
	if s: player.stream = s; player.play()
	else: OS.shell_open(g)


# ---------------------------------------------------------------- Réseau : découverte

func _broadcast_addrs() -> PackedStringArray:
	var out: PackedStringArray = ["255.255.255.255"]
	for a in IP.get_local_addresses():
		if a.contains(".") and not a.begins_with("127.") and not a.begins_with("169.254"):
			out.append(a.substr(0, a.rfind(".")) + ".255")
	return out


func _broadcast_status() -> void:
	for id in conns: _send(id, {"t": "status", "s": my_status})


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_discovery(now, delta)
	while server.is_connection_available():
		var p := server.take_connection()
		pending.append({"p": p, "id": "", "buf": PackedByteArray(), "out": PackedByteArray(), "queue": [], "rx": {}, "tx": {}, "tx_wait": [], "ip": p.get_connected_host(), "t": now})
	for c in pending.duplicate():
		_pump(c, "")
		if c["id"] != "" or c["p"].get_status() == StreamPeerTCP.STATUS_NONE or c["p"].get_status() == StreamPeerTCP.STATUS_ERROR or now - c["t"] > 10.0:
			pending.erase(c)
			if c["id"] == "": c["p"].disconnect_from_host()
	for id in conns.keys():
		if conns.has(id): _pump(conns[id], id)


func _discovery(now: float, delta: float) -> void:
	if not udp.is_bound():
		if udp.bind(udp_port) != OK: return
		udp.set_broadcast_enabled(true)
	beacon_t -= delta
	if beacon_t <= 0.0:
		beacon_t = 2.0
		if my_status != 3:
			var msg := ("%s|%s|%d|%d|%s" % [BEACON, my_id, tcp_port, my_status, my_name.replace("|", " ")]).to_utf8_buffer()
			for b in _broadcast_addrs():
				udp.set_dest_address(b, udp_port); udp.put_packet(msg)
	while udp.get_available_packet_count() > 0:
		var parts := udp.get_packet().get_string_from_utf8().split("|", true, 4)
		var ip := udp.get_packet_ip()
		if parts.size() < 5 or parts[0] != BEACON or parts[1] == my_id: continue
		peers[parts[1]] = {"ip": ip, "port": parts[2].to_int(), "status": parts[3].to_int(), "name": parts[4].substr(0, 24), "t": now}
		known[parts[1]] = parts[4].substr(0, 24)
	for k in peers.keys():
		if now - peers[k]["t"] > 7.0: peers.erase(k)
	var s := "%s|%s" % [cur, unread]
	for k in peers: s += "|%s%s%s" % [k, peers[k]["name"], peers[k]["status"]]
	if s != sig:
		sig = s; _rebuild_contacts()
		if cur != "": head_lbl.text = _nm(cur) + ("" if peers.has(cur) else "  (hors ligne)")


# ---------------------------------------------------------------- Réseau : connexions et trames

func _frame(h: Dictionary, body := PackedByteArray()) -> PackedByteArray:
	var hb := JSON.stringify(h).to_utf8_buffer()
	var out := PackedByteArray(); out.resize(4); out.encode_u32(0, hb.size())
	out.append_array(hb); out.append_array(body)
	return out


func _conn_for(id: String):
	if conns.has(id): return conns[id]
	if not peers.has(id): return null
	var p := StreamPeerTCP.new()
	if p.connect_to_host(peers[id]["ip"], peers[id]["port"]) != OK: return null
	var c := {"p": p, "id": id, "buf": PackedByteArray(), "out": PackedByteArray(), "queue": [], "rx": {}, "tx": {}, "tx_wait": [], "ip": peers[id]["ip"], "hello": false, "t": 0.0}
	conns[id] = c
	return c


func _send(id: String, h: Dictionary) -> bool:
	var c = _conn_for(id)
	if c == null: return false
	if not c.get("hello", false): c["out"].append_array(_frame({"t": "hello", "id": my_id, "name": my_name, "s": my_status, "p": tcp_port})); c["hello"] = true
	var f := _frame(h)
	if c["tx"].is_empty(): c["out"].append_array(f)
	else: c["queue"].append(f)
	return true


func _drop(id: String) -> void:
	if not conns.has(id): return
	var c: Dictionary = conns[id]
	_close_rx(c, false); _close_tx(c)
	c["p"].disconnect_from_host()
	conns.erase(id)


func _close_rx(c: Dictionary, ok: bool) -> void:
	var rx: Dictionary = c["rx"]
	if rx.is_empty(): return
	if rx.get("f") != null: rx["f"].close()
	_set_state(rx["fid"], "done" if ok else "failed")
	c["rx"] = {}


func _close_tx(c: Dictionary) -> void:
	var tx: Dictionary = c["tx"]
	if tx.is_empty(): return
	if tx.get("f") != null: tx["f"].close()
	c["tx"] = {}


func _pump(c: Dictionary, id: String) -> void:
	var p: StreamPeerTCP = c["p"]
	p.poll()
	var st := p.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTING: return
	if st != StreamPeerTCP.STATUS_CONNECTED:
		if id != "": _drop(id)
		return
	if id == "" and not c.get("hello", false):
		c["out"].append_array(_frame({"t": "hello", "id": my_id, "name": my_name, "s": my_status, "p": tcp_port})); c["hello"] = true
	# Envoi : fichier en cours, puis tampon
	var tx: Dictionary = c["tx"]
	if not tx.is_empty() and c["out"].size() < CHUNK:
		var n := mini(CHUNK, tx["left"])
		if n > 0: c["out"].append_array(tx["f"].get_buffer(n)); tx["left"] -= n
		if tx["left"] <= 0:
			_set_state(tx["fid"], "done"); _close_tx(c)
			for f in c["queue"]: c["out"].append_array(f)
			c["queue"] = []
			if not c["tx_wait"].is_empty(): _start_tx(c, c["tx_wait"].pop_front())
		else: _set_pct(tx["fid"], 100.0 * (tx["total"] - tx["left"]) / maxf(1.0, tx["total"]))
	if c["out"].size() > 0:
		var r := p.put_partial_data(c["out"])
		if r[0] == OK and r[1] > 0: c["out"] = c["out"].slice(r[1])
	# Réception
	var avail := p.get_available_bytes()
	if avail > 0:
		var d := p.get_partial_data(mini(avail, 1048576))
		if d[0] == OK: c["buf"].append_array(d[1])
	_parse(c)


func _parse(c: Dictionary) -> void:
	while true:
		var buf: PackedByteArray = c["buf"]
		var rx: Dictionary = c["rx"]
		if not rx.is_empty():
			if buf.is_empty(): return
			var n := mini(buf.size(), rx["left"])
			rx["f"].store_buffer(buf.slice(0, n)); rx["left"] -= n
			c["buf"] = buf.slice(n)
			_set_pct(rx["fid"], 100.0 * (rx["total"] - rx["left"]) / maxf(1.0, rx["total"]))
			if rx["left"] <= 0: _close_rx(c, true)
			continue
		if buf.size() < 4: return
		var hl := buf.decode_u32(0)
		if hl > 65536: c["p"].disconnect_from_host(); c["buf"] = PackedByteArray(); return
		if buf.size() < 4 + hl: return
		var h = JSON.parse_string(buf.slice(4, 4 + hl).get_string_from_utf8())
		c["buf"] = buf.slice(4 + hl)
		if h is Dictionary: _handle(c, h)


func _handle(c: Dictionary, h: Dictionary) -> void:
	var t := str(h.get("t", ""))
	if t == "hello":
		var id := str(h.get("id", ""))
		if id == "" or id == my_id: return
		if conns.has(id) and conns[id] != c:
			conns[id]["p"].disconnect_from_host(); conns.erase(id)
		c["id"] = id; conns[id] = c
		if not peers.has(id): peers[id] = {"ip": c["ip"], "port": int(h.get("p", tcp_port)), "status": int(h.get("s", 0)), "name": str(h.get("name", id)).substr(0, 24), "t": Time.get_ticks_msec() / 1000.0}
		known[id] = str(h.get("name", id)).substr(0, 24)
		return
	var id: String = c["id"]
	if id == "": return
	match t:
		"status":
			if peers.has(id): peers[id]["status"] = int(h.get("s", 0))
		"msg":
			_add_msg(id, {"from": "them", "kind": "text", "text": str(h.get("text", "")).substr(0, 4000)})
		"nudge":
			_add_msg(id, {"from": "them", "kind": "nudge"})
			_shake()
		"offer":
			var fid := str(h.get("fid", ""))
			var nm := _safe_name(str(h.get("name", "fichier")))
			var m := {"from": "them", "kind": "file", "name": nm, "size": int(h.get("size", 0)), "fid": fid, "state": "offer_in", "path": ""}
			offers[fid] = {"id": id, "msg": m, "size": int(h.get("size", 0))}
			_add_msg(id, m)
		"accept":
			var fid := str(h.get("fid", ""))
			if offers.has(fid) and offers[fid]["id"] == id:
				if c["tx"].is_empty(): _start_tx(c, fid)
				else: c["tx_wait"].append(fid)
		"reject":
			var fid := str(h.get("fid", ""))
			if offers.has(fid): _set_state(fid, "rejected")
		"data":
			var fid := str(h.get("fid", ""))
			if not (offers.has(fid) and offers[fid].get("accepted", false) and offers[fid]["id"] == id): return
			var o: Dictionary = offers[fid]
			var size := int(h.get("size", 0))
			var f := FileAccess.open(o["path"], FileAccess.WRITE)
			if f == null: _set_state(fid, "failed"); return
			c["rx"] = {"fid": fid, "f": f, "left": size, "total": size}
			if size <= 0: _close_rx(c, true)


func _safe_name(n: String) -> String:
	n = n.get_file().validate_filename().strip_edges().lstrip(".")
	if n == "": n = "fichier"
	return n.substr(0, 120)


func _accept(fid: String) -> void:
	if not offers.has(fid): return
	var o: Dictionary = offers[fid]
	var name: String = o["msg"]["name"]
	var path := recv_dir.path_join(name)
	var i := 1
	while FileAccess.file_exists(path):
		path = recv_dir.path_join("%s (%d).%s" % [name.get_basename(), i, name.get_extension()] if name.get_extension() != "" else "%s (%d)" % [name, i]); i += 1
	o["path"] = path; o["accepted"] = true; o["msg"]["path"] = path
	_set_state(fid, "progress")
	_send(o["id"], {"t": "accept", "fid": fid})


func _reject(fid: String) -> void:
	if not offers.has(fid): return
	_set_state(fid, "rejected"); _send(offers[fid]["id"], {"t": "reject", "fid": fid})


func _start_tx(c: Dictionary, fid: String) -> void:
	var o: Dictionary = offers[fid]
	var f := FileAccess.open(o["path"], FileAccess.READ)
	if f == null: _set_state(fid, "failed"); return
	var size: int = f.get_length()
	c["tx"] = {"fid": fid, "f": f, "left": size, "total": size}
	c["out"].append_array(_frame({"t": "data", "fid": fid, "size": size}))
	_set_state(fid, "progress")


func _set_state(fid: String, state: String) -> void:
	if not offers.has(fid): return
	var m: Dictionary = offers[fid]["msg"]
	m["state"] = state
	if state == "done" or state == "failed" or state == "rejected":
		var id: String = offers[fid]["id"]
		_save_hist(id)
		if id == cur: _rebuild_chat()


func _set_pct(fid: String, pct: float) -> void:
	if not offers.has(fid): return
	var m: Dictionary = offers[fid]["msg"]
	m["pct"] = pct
	var l = m.get("_lbl")
	if l != null and is_instance_valid(l): l.text = "%d %%" % int(pct)


# ---------------------------------------------------------------- Actions

func _send_text() -> void:
	var t := input.text.strip_edges()
	if t == "" or cur == "": return
	if _send(cur, {"t": "msg", "text": t}):
		input.text = ""; _add_msg(cur, {"from": "me", "kind": "text", "text": t})
	else: note.text = "%s est hors ligne." % _nm(cur)


func _send_nudge() -> void:
	if cur == "": return
	if _send(cur, {"t": "nudge"}): _add_msg(cur, {"from": "me", "kind": "nudge"})
	else: note.text = "%s est hors ligne." % _nm(cur)


func _pick_files() -> void:
	if cur == "": note.text = "Choisis d'abord un contact."; return
	dialog.popup_centered_ratio(0.7)


func _send_file(id: String, path: String) -> void:
	if id == "" or not FileAccess.file_exists(path): return
	var f := FileAccess.open(path, FileAccess.READ)
	var size: int = f.get_length() if f else 0
	var fid := str(randi()) + str(Time.get_ticks_usec())
	var m := {"from": "me", "kind": "file", "name": path.get_file(), "size": size, "fid": fid, "state": "offer_out", "path": path}
	if not _send(id, {"t": "offer", "fid": fid, "name": path.get_file(), "size": size}):
		note.text = "%s est hors ligne." % _nm(id); return
	offers[fid] = {"id": id, "msg": m, "path": path, "size": size}
	_add_msg(id, m)


func _shake() -> void:
	var w := get_parent().get_parent() if get_parent() else null
	if not (w is Control): return
	if shake_tw and shake_tw.is_valid(): return
	var p0: Vector2 = w.position
	shake_tw = create_tween()
	for i in 8: shake_tw.tween_property(w, "position", p0 + Vector2(10 if i % 2 == 0 else -10, 0), 0.04)
	shake_tw.tween_property(w, "position", p0, 0.04)
