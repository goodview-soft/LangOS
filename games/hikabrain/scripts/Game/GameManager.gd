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
var replication: PlayerReplication
var human: PlayerController
var bot: PlayerController
var hud: HUD
var test_mode := false
signal exit_requested   # demandé par le HUD : l'hôte (fenêtre) ferme la partie

func _ready() -> void:
	test_mode = "--hb-test" in OS.get_cmdline_user_args()
	Inputs.setup()
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

	human = _make_player(Cfg.TEAM_RED, "Toi", not test_mode)
	bot = _make_player(Cfg.TEAM_BLUE, "Bot", false)
	if test_mode:
		human.display_name = "BotRouge"

	hud = HUD.new()
	add_child(hud)
	hud.bind(self)

	match_manager.state_changed.connect(_on_state)
	match_manager.countdown_tick.connect(func(_n: int) -> void: Sfx.play(self, "beep"))
	match_manager.point_scored.connect(func(_t: int, _p: PlayerController) -> void: Sfx.play(self, "score"))
	if not test_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	match_manager.start_match()
	if test_mode:
		var st := SelfTest.new()
		st.game = self
		add_child(st)

func _physics_process(_dt: float) -> void:
	if human and human.is_local:
		replication.record(human)

func _make_player(team: int, pname: String, local: bool) -> PlayerController:
	var p := PlayerController.new()
	p.name = pname
	add_child(p)
	p.setup(self, team, pname, local)
	if local:
		var h := HumanInput.new()
		h.p = p
		p.provider = h
		p.add_child(h)
	else:
		var b := BotBrain.new()
		b.p = p
		p.provider = b
		p.add_child(b)
	team_manager.register(p)
	p.died.connect(_on_player_died)
	return p

func _on_player_died(p: PlayerController, cause: String) -> void:
	var killer: PlayerController = null
	if p.last_attacker and Time.get_ticks_msec() / 1000.0 - p.last_attacker_time < 6.0:
		killer = p.last_attacker
		killer.kills += 1
	hud.feed("%s %s" % [p.display_name, ("a été tué par " + killer.display_name) if killer else ("est tombé" if cause == "void" else "est mort")], Cfg.TEAM_COLORS[p.team])
	get_tree().create_timer(Tuning.respawn_delay).timeout.connect(func() -> void:
		if not p.alive and is_inside_tree():
			respawn_player(p))

func respawn_player(p: PlayerController) -> void:
	p.respawn(Cfg.SPAWNS[p.team], Cfg.SPAWN_YAW[p.team])
	p.frozen = match_manager.state != Cfg.State.PLAYING

func _reset_round() -> void:
	blocks.reset_to_base()
	for p in team_manager.players:
		p.last_attacker = null
		respawn_player(p)

func restart_match() -> void:
	match_manager.start_match()

func _on_state(s: int, _old: int) -> void:
	match s:
		Cfg.State.WAITING, Cfg.State.ROUND_RESET:
			_reset_round()
			for p in team_manager.players:
				p.frozen = true
		Cfg.State.COUNTDOWN, Cfg.State.POINT_SCORED, Cfg.State.MATCH_FINISHED:
			for p in team_manager.players:
				p.frozen = true
		Cfg.State.PLAYING:
			for p in team_manager.players:
				p.frozen = false
			Sfx.play(self, "go")
