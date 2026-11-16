class_name HikaNet
extends Node
## Réseau LAN Hikabrain (2 à 8 joueurs, équipes rouge/bleu équilibrées). Nœud « Net » enfant de la racine « HikaGame »,
## qui porte un SceneMultiplayer dédié : les chemins RPC sont relatifs à la racine, donc identiques chez tous les pairs
## malgré les noms auto-générés des fenêtres LangOS. L'hôte fait autorité : il simule tous les joueurs (le client envoie
## ses commandes à chaque tick, l'hôte les rejoue), valide poser/casser/frapper et diffuse blocs, état de manche, scores.
## Le client prédit son propre joueur (réconciliation douce sur les snapshots 20 Hz) et interpole les autres.

const SNAP_HZ := 20.0
const MAX_PLAYERS := 8
const LOBBY_SECS := 3.0   # compte à rebours du salon dès que 2 joueurs sont là

var game: GameManager
var players := {}        # id réseau (1 = hôte) -> PlayerController
var my_name := "Joueur"
var port := NetworkManager.DEFAULT_PORT
var lobby_t := -1.0      # salon : secondes avant le départ (-1 : pas de compte à rebours)
var _snap_t := 0.0
var _wired := false

func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	multiplayer.connected_to_server.connect(func() -> void: c_hello.rpc_id(1, my_name))
	multiplayer.connection_failed.connect(func() -> void: game.net_failed.emit("Connexion impossible"))
	multiplayer.server_disconnected.connect(func() -> void: game.net_failed.emit("L'hôte a quitté la partie"))

func is_host() -> bool:
	return game.net.mode == NetworkManager.Mode.HOST

func is_client() -> bool:
	return game.net.mode == NetworkManager.Mode.CLIENT

static func local_ip() -> String:
	var fallback := "127.0.0.1"
	for a in IP.get_local_addresses():
		if a.count(".") != 3 or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
		fallback = a
	return fallback

func info_text() -> String:
	if is_host():
		return "Hôte %s:%d  ·  %d joueur(s)" % [local_ip(), port, players.size()]
	if is_client():
		return "Connecté à l'hôte  ·  %d joueur(s)" % players.size()
	return ""

# ---------------------------------------------------------------- démarrage
func start_host(p_port: int) -> Error:
	port = p_port
	var e := game.net.host(p_port, MAX_PLAYERS - 1)
	if e != OK:
		return e
	_wire_host()
	return OK

func start_client(ip: String, p_port: int) -> Error:
	port = p_port
	return game.net.join(ip, p_port)

## L'hôte relaie à tous les clients blocs, état de manche et scores.
func _wire_host() -> void:
	if _wired:
		return
	_wired = true
	var mm := game.match_manager
	game.blocks.block_changed.connect(func(cell: Vector3i, _o: int, n: int) -> void: b_set.rpc(cell, n))
	mm.state_changed.connect(func(s: int, _o: int) -> void: m_state.rpc(s, mm.timer))
	mm.countdown_tick.connect(func(n: int) -> void: m_tick.rpc(n))
	mm.point_scored.connect(func(t: int, who: PlayerController) -> void: m_point.rpc(t, who.pid if who else 0))
	mm.match_finished.connect(func(w: int) -> void: m_finish.rpc(w))
	game.score_manager.score_changed.connect(func(_t: int, s: Array) -> void: m_score.rpc(s[0], s[1]))

func _balanced_team() -> int:
	return 0 if game.team_manager.players_of(0).size() <= game.team_manager.players_of(1).size() else 1

# ---------------------------------------------------------------- joueurs
@rpc("any_peer", "call_remote", "reliable")
func c_hello(pname: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id) or players.size() >= MAX_PLAYERS:
		return
	pname = pname.strip_edges().left(16)
	if pname.is_empty():
		pname = "Joueur%d" % id
	var team := _balanced_team()
	var idx := game.team_manager.players_of(team).size()
	var raw := game.blocks.grid
	w_full.rpc_id(id, raw.compress(FileAccess.COMPRESSION_ZSTD), raw.size(), game.match_manager.state, game.match_manager.timer,
		game.score_manager.scores[0], game.score_manager.scores[1])
	for o in players:
		var q: PlayerController = players[o]
		p_add.rpc_id(id, o, q.display_name, q.team, q.spawn_idx)
	var p := game.add_net_player(id, pname, team, idx, "remote")
	players[id] = p
	p_add.rpc_id(id, id, pname, team, idx)
	for o in players:
		if o != 1 and o != id:
			p_add.rpc_id(o, id, pname, team, idx)
	game.announce("%s a rejoint la partie" % pname, Cfg.TEAM_COLORS[team])

@rpc("authority", "call_remote", "reliable")
func p_add(id: int, pname: String, team: int, idx: int) -> void:
	if players.has(id):
		return
	if id == multiplayer.get_unique_id():
		var me := game.add_net_player(id, pname, team, idx, "human")
		players[id] = me
		game.start_local(me)
	else:
		var p := game.add_net_player(id, pname, team, idx, "puppet")
		p.net_pos = p.global_position
		players[id] = p
		game.announce("%s a rejoint la partie" % pname, Cfg.TEAM_COLORS[team])

@rpc("authority", "call_remote", "reliable")
func p_del(id: int) -> void:
	_remove(id)

func _remove(id: int) -> void:
	var p: PlayerController = players.get(id)
	players.erase(id)
	if p:
		game.announce("%s a quitté la partie" % p.display_name, Cfg.TEAM_COLORS[p.team])
		game.authority._last_attack.erase(p)
		game.authority._last_place.erase(p)
		game.remove_net_player(p)

func _on_peer_gone(id: int) -> void:
	if is_host() and players.has(id):
		_remove(id)
		p_del.rpc(id)

# ---------------------------------------------------------------- monde et manche
@rpc("authority", "call_remote", "reliable")
func w_full(comp: PackedByteArray, raw_size: int, state: int, timer: float, s0: int, s1: int) -> void:
	game.match_manager.net_apply(state, timer)   # d'abord (WAITING/ROUND_RESET remettent le décor de base), puis la grille
	var raw := comp.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() == game.blocks.grid.size():
		game.blocks.grid = raw
		game.blocks.rebuild_all()
	m_score(s0, s1)

@rpc("authority", "call_remote", "reliable")
func b_set(cell: Vector3i, id: int) -> void:
	var old := game.blocks.get_block(cell)
	game.blocks.set_block(cell, id)
	if old != id:
		Sfx.play(game, "place" if id != Cfg.B_AIR else "break", Vector3(cell) + Vector3(0.5, 0.5, 0.5), randf_range(0.95, 1.1))

@rpc("authority", "call_remote", "reliable")
func m_state(s: int, t: float) -> void:
	game.match_manager.net_apply(s, t)

@rpc("authority", "call_remote", "reliable")
func m_tick(n: int) -> void:
	game.match_manager.countdown_tick.emit(n)

@rpc("authority", "call_remote", "reliable")
func m_score(s0: int, s1: int) -> void:
	game.score_manager.scores = [s0, s1]
	game.score_manager.score_changed.emit(-1, game.score_manager.scores)

@rpc("authority", "call_remote", "reliable")
func m_point(team: int, who: int) -> void:
	game.match_manager.point_scored.emit(team, players.get(who))

@rpc("authority", "call_remote", "reliable")
func m_finish(w: int) -> void:
	game.match_manager.match_finished.emit(w)

func send_restart() -> void:
	c_restart.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func c_restart() -> void:
	if is_host() and players.has(multiplayer.get_remote_sender_id()) and game.match_manager.state == Cfg.State.MATCH_FINISHED:
		game.restart_match()

# ---------------------------------------------------------------- commandes client -> hôte
func send_cmd(p: PlayerController) -> void:
	c_cmd.rpc_id(1, p.cmd.seq, p.cmd.move, p.cmd.jump_pressed, p.cmd.sprint, p.cmd.sneak, p.yaw, p.pitch)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_cmd(seq: int, mv: Vector2, jump: bool, sprint: bool, sneak: bool, yaw: float, pitch: float) -> void:
	if not is_host():
		return
	var p: PlayerController = players.get(multiplayer.get_remote_sender_id())
	if p and p.provider is RemoteInput:
		(p.provider as RemoteInput).push(seq, mv, jump, sprint, sneak, yaw, pitch)

func send_place(cell: Vector3i) -> void:
	c_place.rpc_id(1, cell)

func send_break(cell: Vector3i) -> void:
	c_break.rpc_id(1, cell)

func send_attack() -> void:
	c_attack.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func c_place(cell: Vector3i) -> void:
	var p: PlayerController = players.get(multiplayer.get_remote_sender_id()) if is_host() else null
	if p:
		game.authority.request_place(p, cell)

@rpc("any_peer", "call_remote", "reliable")
func c_break(cell: Vector3i) -> void:
	var p: PlayerController = players.get(multiplayer.get_remote_sender_id()) if is_host() else null
	if p:
		game.authority.request_break(p, cell)

@rpc("any_peer", "call_remote", "reliable")
func c_attack() -> void:
	var p: PlayerController = players.get(multiplayer.get_remote_sender_id()) if is_host() else null
	if p:
		game.authority.request_attack(p)

# ---------------------------------------------------------------- effets hôte -> clients
func on_hit(att: PlayerController, vic: PlayerController, dmg: float, kdir: Vector3, sprint: bool) -> void:
	if is_host():
		fx_hit.rpc(att.pid, vic.pid, dmg, kdir, sprint)

@rpc("authority", "call_remote", "reliable")
func fx_hit(att: int, vic: int, dmg: float, kdir: Vector3, sprint: bool) -> void:
	var a: PlayerController = players.get(att)
	var v: PlayerController = players.get(vic)
	if a == null or v == null:
		return
	v.last_attacker = a
	v.last_attacker_time = Time.get_ticks_msec() / 1000.0
	if v.is_local:
		v.knock.apply(kdir, sprint)   # le client prédit son propre joueur : il applique le recul lui-même
		v.health.damaged.emit(dmg, a)
		Sfx.play(game, "hurt")
	v.flash()
	Sfx.play(game, "hit", v.global_position, randf_range(0.9, 1.1))
	game.authority.attack_landed.emit(a, v, dmg)

func on_respawn(p: PlayerController) -> void:
	if is_host():
		p_resp.rpc(p.pid, p.global_position, p.yaw)

@rpc("authority", "call_remote", "reliable")
func p_resp(id: int, pos: Vector3, yaw: float) -> void:
	var p: PlayerController = players.get(id)
	if p == null:
		return
	p.respawn(pos, yaw)
	p.net_pos = pos
	p.frozen = game.match_manager.state != Cfg.State.PLAYING
	if p.is_local:
		game.replication.clear()

# ---------------------------------------------------------------- snapshots 20 Hz
func _physics_process(dt: float) -> void:
	if not is_host():
		return
	if game.match_manager.state == Cfg.State.LOBBY:
		if players.size() >= 2:
			if lobby_t < 0.0:
				lobby_t = LOBBY_SECS
			lobby_t -= dt
			if lobby_t <= 0.0:
				start_now()
		else:
			lobby_t = -1.0   # un joueur est parti : le compte à rebours s'annule
	_snap_t += dt
	if _snap_t < 1.0 / SNAP_HZ:
		return
	_snap_t = 0.0
	var arr: Array = []
	for id in players:
		var p: PlayerController = players[id]
		var seq := (p.provider as RemoteInput).last_seq if p.provider is RemoteInput else 0
		arr.append([id, p.global_position, p.velocity, p.yaw, p.pitch, p.health.hp, p.alive, seq, p.inv.block_count, p.kills, p.deaths])
	for id in players:
		if id != 1:
			s_snap.rpc_id(id, arr)
			l_cd.rpc_id(id, lobby_t)

## Hôte : lance la partie maintenant avec les joueurs présents (au moins 2).
func start_now() -> void:
	if is_host() and game.match_manager.state == Cfg.State.LOBBY and players.size() >= 2:
		lobby_t = -1.0
		game.match_manager.start_match()

@rpc("authority", "call_remote", "unreliable_ordered")
func l_cd(t: float) -> void:
	lobby_t = t

@rpc("authority", "call_remote", "unreliable_ordered")
func s_snap(arr: Array) -> void:
	for e in arr:
		var p: PlayerController = players.get(int(e[0]))
		if p == null:
			continue
		p.kills = int(e[9])
		p.deaths = int(e[10])
		p.health.hp = float(e[5])
		if p.inv.block_count != int(e[8]):
			p.inv.block_count = int(e[8])
			p.inv.changed.emit()
		if not bool(e[6]):
			if p.alive:
				p.kill("net")
			continue
		if not p.alive:
			continue   # la réapparition arrive par p_resp
		if p.is_local:
			_reconcile(p, e)
		else:
			p.net_pos = e[1]
			p.velocity = e[2]
			p.net_yaw = float(e[3])
			p.net_pitch = float(e[4])

## Réconciliation du joueur local : compare l'état de l'hôte au même numéro de séquence que notre historique prédit.
func _reconcile(p: PlayerController, e: Array) -> void:
	var pos: Vector3 = e[1]
	var h := game.replication.find(int(e[7]))
	if h.is_empty():
		if p.global_position.distance_to(pos) > 3.0:
			p.global_position = pos
			p.velocity = e[2]
			game.replication.clear()
		return
	var diff := pos - (h["pos"] as Vector3)
	var err := diff.length()
	if err > 2.0:
		p.global_position += diff
		p.velocity = e[2]
		game.replication.shift(diff)
	elif err > 0.3:
		p.global_position += diff * 0.35
		game.replication.shift(diff * 0.35)
