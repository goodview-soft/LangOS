class_name DMNet
extends Node
## Réseau LAN v1 (nœud « Net » enfant de la racine du jeu, qui porte un MultiplayerAPI dédié : chemins RPC relatifs à la racine). L'hôte fait autorité : il simule le monde (blocs, eau, mineurs IA,
## sauvegarde). Les clients reçoivent le monde compressé par morceaux fiables, envoient leur position
## (15 Hz, non fiable) et des requêtes casser/poser/chat ; l'hôte diffuse blocs, eau, mineurs (10 Hz), chat.
## Patterns repris de afterworld-game (ENet, signaux de pairs, RPC), en version courte.

signal world_received
signal status(text: String)
signal lost

const DEFAULT_PORT := 7777
const MAX_PEERS := 4
const CHUNK := 16000
const STATE_HZ := 15.0
const MINER_HZ := 10.0
const REACH := 12.0  # distance max (blocs) entre le joueur et un bloc qu'il demande à casser/poser

var main: Node  # scripts/main.gd
var mode := "solo"  # solo | host | client
var joined := false  # client : monde reçu
var peers := {}  # hôte : id -> {name, look, pos}
var remotes := {}  # id -> {node, body, label, target}
var puppets := {}  # client : nom de mineur -> [actif, pos, anim, facing]
var host_sum := ""  # client : somme annoncée par l'hôte
var chat_seen: Array = []  # entrées de chat reçues (tests)
var pending_partial := {}  # client : blocs entamés reçus avec le monde
var pvp_att := {"id": 0, "t": 0}  # dernier joueur qui m'a frappé (pour l'annonce de mort)
var _asm := PackedByteArray()
var _meta := {}
var _t_state := 0.0
var _t_min := 0.0

static var i: DMNet   # instance courante (créée par setup() dans main.gd)

## Racine fixe + MultiplayerAPI propre au sous-arbre du jeu : les chemins RPC sont relatifs à la racine,
## donc identiques chez les deux pairs malgré les noms auto-générés des fenêtres LangOS.
static func setup(game: Node) -> DMNet:
	game.name = "DMGame"
	game.get_tree().set_multiplayer(SceneMultiplayer.new(), game.get_path())
	var n := DMNet.new()
	n.name = "Net"
	n.main = game
	game.add_child(n)
	i = n
	return n

func _exit_tree() -> void:
	if mode != "solo" and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	if i == self:
		i = null

func _ready() -> void:
	multiplayer.peer_connected.connect(func(_id: int): pass)
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func():
		status.emit("Connexion impossible")
		reset())
	multiplayer.server_disconnected.connect(func():
		status.emit("Hôte déconnecté")
		reset()
		lost.emit())

func is_client() -> bool:
	return mode == "client"

func is_host() -> bool:
	return mode == "host"

## Remet tout à zéro (changement de scène, retour au menu).
func reset() -> void:
	if mode == "solo":
		return  # rien à fermer (évite de toucher à `multiplayer` en solo)
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for id in remotes.keys():
		_drop_remote(id)
	mode = "solo"
	joined = false
	peers.clear()
	pending_partial.clear()
	puppets.clear()
	_asm.clear()

static func local_ip() -> String:
	var fallback := "127.0.0.1"
	for a in IP.get_local_addresses():
		if a.count(".") != 3 or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
		fallback = a
	return fallback

static func checksum(raw: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(raw)
	return h.finish().hex_encode()

static func world_sum(w) -> String:
	return checksum(w.blocks + w.fluid_lvl)

# ---------------------------------------------------------------- connexion
func host(port: int) -> Error:
	reset()
	var p := ENetMultiplayerPeer.new()
	var e := p.create_server(port, MAX_PEERS)
	if e != OK:
		status.emit("Impossible d'héberger sur le port %d" % port)
		return e
	multiplayer.multiplayer_peer = p
	mode = "host"
	if main.social:
		main.social.chat_message.connect(_on_chat_host)
	status.emit("Hébergé sur %s:%d" % [local_ip(), port])
	return OK

func join(ip: String, port: int) -> Error:
	reset()
	var p := ENetMultiplayerPeer.new()
	var e := p.create_client(ip, port)
	if e != OK:
		status.emit("Adresse invalide")
		return e
	multiplayer.multiplayer_peer = p
	mode = "client"
	main.save_enabled = false  # un client n'écrit jamais la vraie sauvegarde
	main.social.auto_process = false  # l'IA est simulée chez l'hôte
	main.social.net_send = func(t: String): c_chat.rpc_id(1, t)
	status.emit("Connexion à %s:%d..." % [ip, port])
	return OK

func _on_connected() -> void:
	c_hello.rpc_id(1, String(DMSettings.look.get("name", "Mineur")), DMSettings.look.duplicate())

func _on_peer_gone(id: int) -> void:
	if mode != "host" or not peers.has(id):
		return
	var n: String = peers[id].name
	peers.erase(id)
	_drop_remote(id)
	for o in peers:
		p_leave.rpc_id(o, id)
	main.social.system_message("%s a quitté la partie" % n)

# ---------------------------------------------------------------- PvP (l'hôte valide chaque coup)
func send_gear(g: Dictionary) -> void:
	if mode == "client":
		c_gear.rpc_id(1, g)

@rpc("any_peer", "call_remote", "reliable")
func c_gear(g: Dictionary) -> void:
	var id: int = multiplayer.get_remote_sender_id()
	if mode == "host" and peers.has(id):
		peers[id].gear = Gear.sanitize(g)  # bornes vérifiées : un client ne peut pas se donner plus que le maximum

## Le joueur local frappe le joueur distant `vic`. Retourne vrai si le coup part (la validation finale est à l'hôte).
func attack(vic: int) -> bool:
	show_bar(vic)  # on voit sa vie dès qu'on le frappe
	if mode == "host":
		return _host_pvp(1, vic)
	if mode == "client":
		c_hit.rpc_id(1, vic)
		return true
	return false

@rpc("any_peer", "call_remote", "reliable")
func c_hit(vic: int) -> void:
	if mode == "host":
		_host_pvp(multiplayer.get_remote_sender_id(), vic)

func _pos_of(id: int) -> Vector3:
	return main.player.pos if id == 1 else (peers[id].pos as Vector3)

func _gear_of(id: int) -> Dictionary:
	return main.gear_active() if id == 1 else peers[id].get("gear", Gear.fresh())

func _tagged(id: int) -> bool:
	return main.player.tag_t > 0.0 if id == 1 else Time.get_ticks_msec() < int(peers[id].get("tag_until", 0))

func _in_safe(id: int) -> bool:
	return main.is_safe_zone(_pos_of(id) + Vector3(0, 1.0, 0)) and not _tagged(id)

## Validation hôte : portée, cadence, zones sûres (sauf combat tag), iframes 0,25 s par attaquant, plafonds d'équipement.
func _host_pvp(att: int, vic: int) -> bool:
	if att == vic or (att != 1 and not peers.has(att)) or (vic != 1 and not peers.has(vic)):
		return false
	var now := Time.get_ticks_msec()
	var ap := _pos_of(att)
	var vp := _pos_of(vic)
	var sword_att: int = int(_gear_of(att).get("sword", 0))
	if absf(ap.y - vp.y) > 3.8 or Vector2(ap.x - vp.x, ap.z - vp.z).length() > Player.MELEE + 1.5 + (Gear.SWORD_REACH if sword_att > 0 else 0.0):
		return false  # trop loin (portée du coup + marge de latence ; tolérance verticale pour les hauteurs de corps)
	var last: int = main.pvp_last_hit if att == 1 else int(peers[att].get("hit_ms", 0))
	if now - last < int(Player.HIT_CD * 700.0 * (Gear.SWORD_CD if sword_att > 0 else 1.0)):
		return false  # cadence
	if _in_safe(att) or _in_safe(vic):
		return false
	var key := "%d>%d" % [att, vic]
	if now < int(_iframes.get(key, 0)):
		return false  # iframes du même attaquant
	_iframes[key] = now + int(Gear.HIT_IFRAMES * 1000.0)
	if att == 1:
		main.pvp_last_hit = now
		main.player.tag_t = Gear.TAG_TIME
		main.player.swing_t = 0.25
	else:
		peers[att].hit_ms = now
		peers[att].tag_until = now + int(Gear.TAG_TIME * 1000.0)
	if vic != 1:
		peers[vic].tag_until = now + int(Gear.TAG_TIME * 1000.0)
	var ag := _gear_of(att)
	var dmg := Player.DMG * Gear.dmg_mult(ag) * Gear.PVP_MULT
	var kb: float = Gear.KB_MULT[clampi(int(ag.kb), 0, 2)]
	_deliver(vic, dmg, ap, kb, att)
	var th := int(_gear_of(vic).thorns)
	if th > 0:
		_deliver(att, Gear.THORNS_DMG * th, vp, 0.0, vic)
	return true

var _iframes := {}

func _deliver(vic: int, dmg: float, from: Vector3, kb: float, att: int) -> void:
	if vic == 1:
		main.pvp_hurt(dmg, from, kb, att)
	else:
		p_hurt.rpc_id(vic, dmg, from, kb, att)

@rpc("authority", "call_remote", "reliable")
func p_hurt(dmg: float, from: Vector3, kb: float, att: int) -> void:
	main.pvp_hurt(dmg, from, kb, att)

## Annonce de mort PvP (le client mort la signale ; l'hôte l'écrit dans le chat).
func report_kill(att: int) -> void:
	if mode == "host":
		_announce_kill(1, att)
	elif mode == "client":
		c_killed.rpc_id(1, att)

@rpc("any_peer", "call_remote", "reliable")
func c_killed(att: int) -> void:
	if mode == "host" and peers.has(multiplayer.get_remote_sender_id()):
		_announce_kill(multiplayer.get_remote_sender_id(), att)

func _announce_kill(vic: int, att: int) -> void:
	var an: String = String(DMSettings.look.get("name", "Mineur")) if att == 1 else String(peers.get(att, {}).get("name", "?"))
	var vn: String = String(DMSettings.look.get("name", "Mineur")) if vic == 1 else String(peers.get(vic, {}).get("name", "?"))
	main.social.system_message("%s a tué %s" % [an, vn])

# ---------------------------------------------------------------- monde
@rpc("any_peer", "call_remote", "reliable")
func c_hello(pname: String, look: Dictionary) -> void:
	if mode != "host":
		return
	var id: int = multiplayer.get_remote_sender_id()
	pname = pname.strip_edges().left(16)
	if pname.is_empty():
		pname = "Joueur%d" % id
	var w = main.world
	var raw: PackedByteArray = w.blocks + w.fluid_lvl
	var comp := raw.compress(FileAccess.COMPRESSION_ZSTD)
	w_begin.rpc_id(id, raw.size(), w.spawn, int(main.seed_v), checksum(raw))
	var i := 0
	while i < comp.size():
		w_chunk.rpc_id(id, comp.slice(i, i + CHUNK))
		i += CHUNK
	w_partial.rpc_id(id, w.partial)
	w_end.rpc_id(id)
	p_join.rpc_id(id, 1, String(DMSettings.look.get("name", "Mineur")), DMSettings.look.duplicate())
	for o in peers:
		p_join.rpc_id(id, o, peers[o].name, peers[o].look)
		p_join.rpc_id(o, id, pname, look)
	peers[id] = {"name": pname, "look": look, "pos": w.spawn}
	_make_remote(id, pname, look)
	main.social.system_message("%s a rejoint la partie" % pname)

@rpc("authority", "call_remote", "reliable")
func w_begin(raw_size: int, spawn: Vector3, seed_v: int, sum: String) -> void:
	_meta = {"size": raw_size, "spawn": spawn, "seed": seed_v}
	host_sum = sum
	_asm = PackedByteArray()

@rpc("authority", "call_remote", "reliable")
func w_chunk(part: PackedByteArray) -> void:
	_asm.append_array(part)

@rpc("authority", "call_remote", "reliable")
func w_partial(d: Dictionary) -> void:
	pending_partial = d

@rpc("authority", "call_remote", "reliable")
func w_end() -> void:
	var raw := _asm.decompress(int(_meta.size), FileAccess.COMPRESSION_ZSTD)
	_asm = PackedByteArray()
	if raw.size() != int(_meta.size) or checksum(raw) != host_sum:
		status.emit("Monde reçu corrompu")
		reset()
		return
	var half := raw.size() / 2
	main.net_apply_world(raw.slice(0, half), raw.slice(half), _meta.spawn, int(_meta.seed))
	joined = true
	status.emit("Connecté")
	world_received.emit()

# ---------------------------------------------------------------- blocs
func broadcast_edit(c: Vector3i, id: int) -> void:
	for p in peers:
		b_edit.rpc_id(p, c, id)

## Mini-blocs : l'hôte diffuse le masque de morceaux d'une cellule (0 = air, 255 = entier).
func broadcast_pieces(c: Vector3i) -> void:
	var w = main.world
	var id: int = w.get_v(c)
	var mask: int = w.pieces(c)
	for p in peers:
		b_part.rpc_id(p, c, id, mask)

@rpc("authority", "call_remote", "reliable")
func b_part(c: Vector3i, id: int, mask: int) -> void:
	main.net_apply_pieces(c, id, mask)

func send_pbreak(c: Vector3i, b: int) -> void:
	c_pbreak.rpc_id(1, c, b)

func send_pplace(c: Vector3i, b: int, item: int) -> void:
	c_pplace.rpc_id(1, c, b, item)

@rpc("any_peer", "call_remote", "reliable")
func c_pbreak(c: Vector3i, b: int) -> void:
	if mode != "host":
		return
	var id: int = multiplayer.get_remote_sender_id()
	if not _near(id, c) or main.edit_piece_break(c, b, true) < 0:
		_refuse_pieces(id, c)

@rpc("any_peer", "call_remote", "reliable")
func c_pplace(c: Vector3i, b: int, item: int) -> void:
	if mode != "host":
		return
	var id: int = multiplayer.get_remote_sender_id()
	if not main.net_item_ok(item) or not _near(id, c) or not main.edit_piece_place(c, b, item):
		_refuse_pieces(id, c)

func _refuse_pieces(id: int, c: Vector3i) -> void:
	b_part.rpc_id(id, c, main.world.get_v(c), main.world.pieces(c))

func send_fluid(idx: Array) -> void:
	if peers.is_empty() or idx.is_empty():
		return
	var w = main.world
	var ii := PackedInt32Array()
	var bb := PackedByteArray()
	var ll := PackedByteArray()
	for i in idx:
		ii.append(i)
		bb.append(w.blocks[i])
		ll.append(w.fluid_lvl[i])
	for p in peers:
		f_cells.rpc_id(p, ii, bb, ll)

@rpc("authority", "call_remote", "reliable")
func b_edit(c: Vector3i, id: int) -> void:
	main.net_apply_edit(c, id)

@rpc("authority", "call_remote", "reliable")
func f_cells(ii: PackedInt32Array, bb: PackedByteArray, ll: PackedByteArray) -> void:
	main.net_apply_cells(ii, bb, ll)

func send_break(c: Vector3i) -> void:
	c_break.rpc_id(1, c)

func send_place(c: Vector3i, item: int) -> void:
	c_place.rpc_id(1, c, item)

func _near(id: int, c: Vector3i) -> bool:
	return peers.has(id) and (peers[id].pos as Vector3).distance_to(Vector3(c) + Vector3(0.5, 0.5, 0.5)) <= REACH

func _refuse(id: int, c: Vector3i) -> void:
	b_edit.rpc_id(id, c, main.world.get_v(c))  # le client revient à l'état de l'hôte

@rpc("any_peer", "call_remote", "reliable")
func c_break(c: Vector3i) -> void:
	if mode != "host":
		return
	var id: int = multiplayer.get_remote_sender_id()
	if not _near(id, c) or main.edit_break(c, true) < 0:  # edit_break diffuse le changement
		_refuse(id, c)
	else:
		_tcell_host = c

@rpc("any_peer", "call_remote", "reliable")
func c_place(c: Vector3i, item: int) -> void:
	if mode != "host":
		return
	var id: int = multiplayer.get_remote_sender_id()
	if not main.net_item_ok(item) or not _near(id, c) or not main.edit_place(c, item):
		_refuse(id, c)

# ---------------------------------------------------------------- chat
func _on_chat_host(entry: Dictionary) -> void:
	for p in peers:
		chat_in.rpc_id(p, entry)

@rpc("any_peer", "call_remote", "reliable")
func c_chat(text: String) -> void:
	var id: int = multiplayer.get_remote_sender_id()
	if mode == "host" and peers.has(id):
		_host_chat = text == "bonjour de test" or _host_chat
		main.social.remote_player_message(peers[id].name, text)

@rpc("authority", "call_remote", "reliable")
func chat_in(entry: Dictionary) -> void:
	chat_seen.append(entry)
	main.social._push(entry)

# ---------------------------------------------------------------- joueurs distants + mineurs
@rpc("authority", "call_remote", "reliable")
func p_join(id: int, pname: String, look: Dictionary) -> void:
	_make_remote(id, pname, look)

@rpc("authority", "call_remote", "reliable")
func p_leave(id: int) -> void:
	_drop_remote(id)

@rpc("any_peer", "call_remote", "unreliable")
func c_state(pos: Vector3, yaw: float, anim: String, hp := 1.0) -> void:
	var id: int = multiplayer.get_remote_sender_id()
	if mode != "host" or not peers.has(id):
		return
	peers[id].pos = pos
	_set_remote(id, pos, yaw, anim, hp)
	for o in peers:
		if o != id:
			p_state.rpc_id(o, id, pos, yaw, anim, hp)

@rpc("authority", "call_remote", "unreliable")
func p_state(id: int, pos: Vector3, yaw: float, anim: String, hp := 1.0) -> void:
	_set_remote(id, pos, yaw, anim, hp)

@rpc("authority", "call_remote", "unreliable")
func m_state(d: Dictionary) -> void:
	puppets = d

## Zombies (simulés par l'hôte) : id -> [position, PV (0-1), morsure en cours, s'enterre].
var zpup := {}

@rpc("authority", "call_remote", "unreliable")
func z_state(d: Dictionary) -> void:
	zpup = d

func _make_remote(id: int, pname: String, look: Dictionary) -> void:
	_drop_remote(id)
	var n := Node3D.new()
	var b: Node3D = main.net_make_body(look)
	n.add_child(b)
	var l := Label3D.new()
	l.text = pname
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.006
	l.font_size = 48
	l.outline_size = 12
	l.position = Vector3(0, 2.15, 0)
	n.add_child(l)
	main.add_child(n)
	var bar := Sprite3D.new()  # barre de vie (visible quelques secondes après un changement ou un coup)
	bar.pixel_size = 1.0 / 10.0
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bar.no_depth_test = true
	bar.render_priority = 4
	bar.position = Vector3(0, 2.5, 0)
	bar.visible = false
	n.add_child(bar)
	remotes[id] = {"node": n, "body": b, "label": l, "target": Vector3.ZERO, "name": pname, "seen": false, "bar": bar, "hp": 1.0, "bar_t": 0.0}

func _drop_remote(id: int) -> void:
	if remotes.has(id):
		(remotes[id].node as Node).queue_free()
		remotes.erase(id)

func _set_remote(id: int, pos: Vector3, yaw: float, anim: String, hp := 1.0) -> void:
	if not remotes.has(id):
		return
	var r: Dictionary = remotes[id]
	if absf(hp - float(r.hp)) > 0.004:
		r.hp = hp
		r.bar_t = 6.0
		_draw_bar(r)
	r.target = pos
	if not r.seen:
		r.seen = true
		(r.node as Node3D).position = pos
	r.body.yaw_goal = yaw
	r.body.play(anim)

## Dessine la barre de vie d'un joueur distant (vert > jaune > rouge).
func _draw_bar(r: Dictionary) -> void:
	var hp: float = clampf(float(r.hp), 0.0, 1.0)
	var img := Image.create(18, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.03, 0.05))
	var col := Color(0.35, 0.9, 0.3) if hp > 0.5 else (Color(1.0, 0.8, 0.2) if hp > 0.25 else Color(1.0, 0.25, 0.2))
	for x in int(round(16.0 * hp)):
		img.set_pixel(1 + x, 1, col)
	(r.bar as Sprite3D).texture = ImageTexture.create_from_image(img)

## Appelé quand le joueur local frappe un joueur distant : sa barre de vie s'affiche.
func show_bar(id: int) -> void:
	if remotes.has(id):
		remotes[id].bar_t = 6.0
		_draw_bar(remotes[id])

func _process(dt: float) -> void:
	if mode == "solo" or main == null or not is_instance_valid(main):
		return
	for id in remotes:
		var rr: Dictionary = remotes[id]
		rr.bar_t = float(rr.bar_t) - dt
		(rr.bar as Sprite3D).visible = float(rr.bar_t) > 0.0
		var n: Node3D = remotes[id].node
		n.position = n.position.lerp(remotes[id].target, 1.0 - exp(-dt * 14.0))
	if main.state != "play" or (mode == "client" and not joined):
		return
	_t_state += dt
	if _t_state >= 1.0 / STATE_HZ:
		_t_state = 0.0
		var p = main.player
		var anim: String = p.vbody.anim if p.vbody else "idle"
		var yaw: float = p.vbody.yaw_goal if p.vbody else 0.0
		if mode == "client":
			c_state.rpc_id(1, p.pos, yaw, anim, p.health / p.max_hp)
		else:
			for o in peers:
				p_state.rpc_id(o, 1, p.pos, yaw, anim, p.health / p.max_hp)
	if mode == "host" and not peers.is_empty():
		_t_min += dt
		if _t_min >= 1.0 / MINER_HZ:
			_t_min = 0.0
			var d := {}
			for m in main.miners:
				var mm = m
				d[mm.mname] = [mm.active, mm.pos, mm.vbody.anim if mm.vbody else "idle", mm.facing, mm.health, mm.status]
			var zd := {}
			for z in main.zombies:
				var zz = z
				zd[zz.zid] = [zz.pos, zz.health / zz.max_hp, zz._bite_t > 0.0, zz.burrowing]
			for o in peers:
				m_state.rpc_id(o, d)
				z_state.rpc_id(o, zd)

## Client : les mineurs IA ne sont pas simulés, ils suivent ce que l'hôte diffuse (appelé à la place de Miner.tick).
func puppet_tick(dt: float) -> void:
	for nm in puppets:
		var m = main.miner_of(nm)
		if m == null:
			continue
		var a: Array = puppets[nm]
		m.active = a[0]
		var tgt: Vector3 = a[1]
		var d: Vector3 = tgt - m.pos
		m.pos = tgt if d.length() > 6.0 else m.pos.lerp(tgt, 1.0 - exp(-dt * 12.0))
		m.position = m.pos
		m.vel = Vector3(d.x, 0.0, d.z) * 8.0
		var an: String = a[2]
		m.mining = an == "mine"
		m.swimming = an == "swim"
		m.in_water = an == "swim"
		m.crouching = an == "crouch"
		m.on_ground = an != "jump" and an != "swim"
		m.facing = int(a[3])
		if a.size() > 5:
			m.health = float(a[4])
			m._set_status(String(a[5]))

# ---------------------------------------------------------------- test de bouclage (voir tests/test_net.sh)
## Lancé avec : -- --dm-net-host=PORT  ou  -- --dm-net-join=127.0.0.1:PORT
var _tcase := ""
var _tstep := 0
var _tt := 0.0
var _tcell := Vector3i.ZERO
var _fails := 0

func _tcheck(name: String, ok: bool) -> void:
	print("[NETTEST] %s : %s" % ["OK  " if ok else "ECHEC", name])
	if not ok:
		_fails += 1

func start_test(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--dm-net-host="):
			_tcase = "host"
			host(int(a.substr(14)))
		elif a.begins_with("--dm-net-join="):
			_tcase = "client"
			var hp := a.substr(14).split(":")
			world_received.connect(func(): _tstep = 1)
			join(hp[0], int(hp[1]))
	set_physics_process(_tcase != "")

func _physics_process(dt: float) -> void:
	if _tcase == "":
		return
	_tt += dt
	if _tt > 90.0:
		_tcheck("délai dépassé", false)
		_finish()
	if _tcase == "host":
		if _tstep == 0 and not peers.is_empty():
			_tstep = 1
			_tt = 0.0
		elif _tstep == 1 and peers.is_empty():  # le client est parti : on vérifie notre côté
			_tcheck("hôte : bloc demandé par le client appliqué chez l'hôte", main.world.get_v(_tcell_host) == 0)
			_tcheck("hôte : message du client reçu et diffusé", _host_chat)
			_finish()
	elif _tcase == "client":
		match _tstep:
			1:  # monde reçu
				_tcheck("client : somme de contrôle du monde identique à l'hôte", world_sum(main.world) == host_sum and host_sum != "")
				_tcheck("client : l'hôte apparaît comme joueur distant", remotes.has(1))
				_tcell = _find_cell()
				_tcheck("client : bloc cassable trouvé près du spawn", _tcell.x >= 0)
				_tt = 0.0
				_tstep = 2
			2:
				if _tt > 1.0:  # laisse partir une position
					c_break.rpc_id(1, _tcell)  # (la même requête que break_block)
					_tstep = 3
					_tt = 0.0
			3:
				if main.world.get_v(_tcell) == 0:
					_tcheck("client : bloc cassé appliqué par l'hôte puis renvoyé", true)
					main.social.net_send.call("bonjour de test")
					_tstep = 4
					_tt = 0.0
				elif _tt > 8.0:
					_tcheck("client : bloc cassé appliqué par l'hôte puis renvoyé", false)
					_finish()
			4:
				var got := false
				for e in chat_seen:
					if e.get("text", "") == "bonjour de test" and e.get("from", "") == DMSettings.look.name:
						got = true
				if got:
					_tcheck("client : chat aller-retour (via l'hôte)", true)
					_finish()
				elif _tt > 8.0:
					_tcheck("client : chat aller-retour (via l'hôte)", false)
					_finish()

var _tcell_host := Vector3i.ZERO
var _host_chat := false

func _find_cell() -> Vector3i:
	var s := Vector3i(main.world.spawn)
	for r in range(1, 14):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				for dz in range(-r, r + 1):
					var c := s + Vector3i(dx, dy, dz)
					var id: int = main.world.get_v(c)
					if Vector3(c).distance_to(Vector3(s)) <= 10.5 and main.net_diggable(id) \
							and not (main.hub_n and main.hub_n.is_protected(c)):
						return c
	return Vector3i(-1, 0, 0)

func _finish() -> void:
	print("[NETTEST] %s : %s (%d échec(s))" % [_tcase.to_upper(), "SUCCES" if _fails == 0 else "ECHEC", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
