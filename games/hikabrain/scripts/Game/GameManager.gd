class_name GameManager
extends Node3D
## Racine de la partie : assemble les systèmes, les joueurs et relie les signaux.

var blocks: BlockManager
var arena: ArenaManager
var team_manager: TeamManager
var score_manager: ScoreManager
var match_manager: MatchManager
var authority: ServerAuthority
var bed_detection: BedDetection
var net: NetworkManager
var hnet: HikaNet                # réseau LAN (null en solo)
var replication: PlayerReplication
var human: PlayerController
var bot: PlayerController
var hud: HUD
var touch: HikaTouch             # contrôles tactiles (null sur PC)
var test_mode := false
signal exit_requested   # demandé par le HUD : l'hôte (fenêtre) ferme la partie
signal net_failed(msg: String)   # connexion impossible / hôte parti : l'hôte (fenêtre) revient au menu réseau

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	test_mode = "--hb-test" in args
	var cfg: Dictionary = get_meta("net", {})   # {"mode": "host"|"client", "ip", "port", "name"} fourni par la fenêtre hôte
	var test_role := ""
	for a in args:   # lancement de test réseau (tests/hika_net_test.sh)
		if a.begins_with("--hb-net-host="):
			cfg = {"mode": "host", "port": a.substr(14).to_int(), "name": "Hote"}
			test_role = "host"
		elif a.begins_with("--hb-net-join="):
			var hp := a.substr(14).split(":")
			cfg = {"mode": "client", "ip": hp[0], "port": hp[1].to_int(), "name": "Client"}
			test_role = "client"
	Inputs.setup()
	name = "HikaGame"   # nom fixe : base des chemins RPC (voir HikaNet)
	net = NetworkManager.new()
	add_child(net)
	replication = PlayerReplication.new()
	add_child(replication)
	blocks = BlockManager.new()
	add_child(blocks)
	arena = ArenaManager.new()
	arena.blocks = blocks
	add_child(arena)
	arena.build()
	team_manager = TeamManager.new()
	add_child(team_manager)
	score_manager = ScoreManager.new()
	add_child(score_manager)
	match_manager = MatchManager.new()
	match_manager.score = score_manager
	add_child(match_manager)
	authority = ServerAuthority.new()
	authority.game = self
	add_child(authority)
	bed_detection = BedDetection.new()
	bed_detection.game = self
	add_child(bed_detection)
	bed_detection.bed_reached.connect(match_manager.on_bed_reached)
	if HikaTouch.wanted() and not test_mode and test_role == "":
		touch = HikaTouch.new()
		touch.game = self
		add_child(touch)

	match_manager.state_changed.connect(_on_state)
	match_manager.countdown_tick.connect(func(_n: int) -> void: Sfx.play(self, "beep"))
	match_manager.point_scored.connect(func(_t: int, _p: PlayerController) -> void: Sfx.play(self, "score"))

	if cfg.is_empty():
		human = _make_player(Cfg.TEAM_RED, "Toi", "bot" if test_mode else "human")
		bot = _make_player(Cfg.TEAM_BLUE, "Bot", "bot")
		if test_mode:
			human.display_name = "BotRouge"
		start_local(human)
		match_manager.start_match()
		if test_mode and not has_meta("manual"):
			var st := SelfTest.new()
			st.game = self
			add_child(st)
	else:
		_net_start(cfg, test_role)

## Mode réseau : SceneMultiplayer dédié au sous-arbre du jeu (chemins RPC relatifs à la racine « HikaGame »).
func _net_start(cfg: Dictionary, test_role: String) -> void:
	get_tree().set_multiplayer(SceneMultiplayer.new(), get_path())
	hnet = HikaNet.new()
	hnet.name = "Net"
	hnet.game = self
	hnet.my_name = str(cfg.get("name", "Joueur"))
	add_child(hnet)
	var mode := str(cfg.get("mode", "host"))
	if mode == "host":
		var e := hnet.start_host(int(cfg.get("port", NetworkManager.DEFAULT_PORT)))
		if e != OK:
			net_failed.emit.call_deferred("Impossible d'héberger sur le port %d" % int(cfg.get("port", 0)))
			return
		var me := add_net_player(1, hnet.my_name, Cfg.TEAM_RED, 0, "human")
		hnet.players[1] = me
		start_local(me)
		match_manager.net_apply(Cfg.State.LOBBY, 0.0)   # jamais de partie seul : attente d'au moins 2 joueurs
	else:
		match_manager.net_client = true
		bed_detection.set_physics_process(false)
		var e := hnet.start_client(str(cfg.get("ip", "127.0.0.1")), int(cfg.get("port", NetworkManager.DEFAULT_PORT)))
		if e != OK:
			net_failed.emit.call_deferred("Adresse invalide")
	if test_role != "":
		var nt := HikaNetTest.new()
		nt.game = self
		nt.role = test_role
		add_child(nt)

## Interface et entrées du joueur local (créées dès qu'il existe : tout de suite en solo/hôte, à la réponse de l'hôte en client).
func start_local(p: PlayerController) -> void:
	human = p
	p.auto_bridge = touch != null   # pont automatique : activé par défaut sur téléphone, touche B sur PC
	hud = HUD.new()
	add_child(hud)
	hud.bind(self)
	if not test_mode and touch == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func is_net_client() -> bool:
	return net != null and net.mode == NetworkManager.Mode.CLIENT

func is_paused() -> bool:
	return get_tree().paused or (hud != null and hud.is_paused())

func announce(text: String, color: Color) -> void:
	if hud:
		hud.feed(text, color)

func _exit_tree() -> void:
	if net and net.mode != NetworkManager.Mode.LOCAL and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()   # self est encore dans l'arbre (contrairement à ses enfants)

func _physics_process(_dt: float) -> void:
	if human and human.is_local:
		replication.record(human)
		if is_net_client() and human.alive:
			hnet.send_cmd(human)

## kind : "human" (local), "bot" (IA), "remote" (hôte : joueur piloté par les commandes d'un client), "puppet" (client : autre joueur).
func _make_player(team: int, pname: String, kind: String, nname := "") -> PlayerController:
	var p := PlayerController.new()
	p.name = nname if nname != "" else pname
	add_child(p)
	p.setup(self, team, pname, kind == "human", kind == "puppet")
	var prov: Node = null
	match kind:
		"human":
			var h := HumanInput.new()
			h.p = p
			prov = h
		"bot":
			var b := BotBrain.new()
			b.p = p
			prov = b
		"remote":
			var r := RemoteInput.new()
			r.p = p
			prov = r
	if prov:
		p.provider = prov
		p.add_child(prov)
	team_manager.register(p)
	p.died.connect(_on_player_died)
	return p

func _on_player_died(p: PlayerController, cause: String) -> void:
	var killer: PlayerController = null
	if p.last_attacker and Time.get_ticks_msec() / 1000.0 - p.last_attacker_time < 6.0:
		killer = p.last_attacker
		killer.kills += 1
	announce("%s %s" % [p.display_name, ("a été tué par " + killer.display_name) if killer else ("est tombé" if cause == "void" else "est mort")], Cfg.TEAM_COLORS[p.team])
	if is_net_client():
		return   # c'est l'hôte qui fait réapparaître (p_resp)
	get_tree().create_timer(Tuning.respawn_delay).timeout.connect(func() -> void:
		if is_instance_valid(p) and not p.alive and is_inside_tree():
			respawn_player(p))

func respawn_player(p: PlayerController) -> void:
	p.respawn(Cfg.spawn_pos(p.team, p.spawn_idx), Cfg.SPAWN_YAW[p.team])
	p.frozen = match_manager.state != Cfg.State.PLAYING
	if hnet:
		hnet.on_respawn(p)

func add_net_player(id: int, pname: String, team: int, idx: int, kind: String) -> PlayerController:
	var p := _make_player(team, pname, kind, "P%d" % id)
	p.pid = id
	p.spawn_idx = idx
	respawn_player(p)
	return p

func remove_net_player(p: PlayerController) -> void:
	team_manager.unregister(p)
	p.queue_free()

func _reset_round() -> void:
	blocks.reset_to_base()
	for p in team_manager.players:
		p.last_attacker = null
		respawn_player(p)

func restart_match() -> void:
	if is_net_client():
		hnet.send_restart()
	else:
		match_manager.start_match()

func _on_state(s: int, _old: int) -> void:
	match s:
		Cfg.State.WAITING, Cfg.State.ROUND_RESET:
			_reset_round()
			for p in team_manager.players:
				p.frozen = true
		Cfg.State.COUNTDOWN, Cfg.State.POINT_SCORED, Cfg.State.MATCH_FINISHED, Cfg.State.LOBBY:
			for p in team_manager.players:
				p.frozen = true
		Cfg.State.PLAYING:
			for p in team_manager.players:
				p.frozen = false
			Sfx.play(self, "go")
