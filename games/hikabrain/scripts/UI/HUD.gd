class_name HUD
extends CanvasLayer
## Interface minimaliste : score, vie, inventaire, compte à rebours, notifications, victoire, pause.

var game: GameManager
var _score_r: Label
var _score_b: Label
var _count: Label
var _banner: Label
var _hearts: HeartsBar
var _protect: Label
var _mine: ColorRect
var _cross: Control
var _vignette: ColorRect
var _victory: Control
var _victory_label: Label
var _pause: Control
var _feed: VBoxContainer
var _inv_ui: InventoryUI
var _hit_t := 0.0
var _netinfo: Label
var _lobby: ColorRect
var _lobby_title: Label
var _lobby_list: Label
var _lobby_btn: Button
var _touch := false

func _lbl(size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return l

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_vignette = ColorRect.new()
	_vignette.color = Color(1, 0, 0, 0)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_vignette)
	# Score
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 12
	top.add_theme_constant_override("separation", 18)
	root.add_child(top)
	_score_r = _lbl(44, Cfg.TEAM_COLORS[0])
	_score_b = _lbl(44, Cfg.TEAM_COLORS[1])
	var sep := _lbl(36)
	sep.text = ":"
	top.add_child(_score_r)
	top.add_child(sep)
	top.add_child(_score_b)
	# Réticule
	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_cross)
	for r in [Rect2(-8, -1, 16, 2), Rect2(-1, -8, 2, 16)]:
		var cr := ColorRect.new()
		cr.position = r.position
		cr.size = r.size
		cr.color = Color(1, 1, 1, 0.75)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cross.add_child(cr)
	_mine = ColorRect.new()
	_mine.position = Vector2(-20, 18)
	_mine.size = Vector2(0, 4)
	_mine.color = Color(1, 0.9, 0.3, 0.9)
	_cross.add_child(_mine)
	# Compte à rebours + bannière
	_count = _lbl(120)
	_count.set_anchors_preset(Control.PRESET_CENTER)
	_count.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_count.grow_vertical = Control.GROW_DIRECTION_BOTH
	_count.position.y = -120
	root.add_child(_count)
	_banner = _lbl(52)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position.y = 110
	root.add_child(_banner)
	# Vie : 10 coeurs façon Minecraft
	_hearts = HeartsBar.new()
	_hearts.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hearts.position = Vector2(24, -62)
	root.add_child(_hearts)
	_protect = _lbl(16, Color(0.6, 0.9, 1.0))
	_protect.text = "PROTÉGÉ"
	_protect.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_protect.position = Vector2(24, -92)
	root.add_child(_protect)
	# Inventaire
	_inv_ui = InventoryUI.new()
	_inv_ui.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_inv_ui.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_inv_ui.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_inv_ui.position.y = -16
	root.add_child(_inv_ui)
	# Journal d'événements
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.position = Vector2(-20, 14)
	root.add_child(_feed)
	# Scoreboard
	var sb := Scoreboard.new()
	sb.game = game
	sb.set_anchors_preset(Control.PRESET_CENTER)
	sb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sb.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(sb)
	# Victoire
	_victory = ColorRect.new()
	(_victory as ColorRect).color = Color(0, 0, 0, 0.6)
	_victory.set_anchors_preset(Control.PRESET_FULL_RECT)
	_victory.visible = false
	root.add_child(_victory)
	_victory_label = _lbl(64)
	_victory_label.set_anchors_preset(Control.PRESET_CENTER)
	_victory_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_victory_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_victory.add_child(_victory_label)
	var vb := HBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	vb.position.y = -60
	vb.add_theme_constant_override("separation", 12)
	_victory.add_child(vb)
	for it in [["Rejouer", func() -> void: game.restart_match()], ["Menu principal", func() -> void: game.exit_requested.emit()]]:
		var vbtn := Button.new()
		vbtn.text = it[0]
		vbtn.custom_minimum_size = Vector2(170, 52)
		vbtn.pressed.connect(it[1])
		vb.add_child(vbtn)
	# Salon d'attente réseau
	_lobby = ColorRect.new()
	_lobby.color = Color(0.05, 0.07, 0.12, 0.88)
	_lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lobby.visible = false
	root.add_child(_lobby)
	var lv := VBoxContainer.new()
	lv.set_anchors_preset(Control.PRESET_CENTER)
	lv.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lv.grow_vertical = Control.GROW_DIRECTION_BOTH
	lv.add_theme_constant_override("separation", 14)
	_lobby.add_child(lv)
	_lobby_title = _lbl(30)
	_lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(_lobby_title)
	_lobby_list = _lbl(20)
	_lobby_list.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(_lobby_list)
	_lobby_btn = Button.new()
	_lobby_btn.text = "Lancer"
	_lobby_btn.custom_minimum_size = Vector2(240, 52)
	_lobby_btn.pressed.connect(func() -> void: game.hnet.start_now())
	lv.add_child(_lobby_btn)
	var lq := Button.new()
	lq.text = "Quitter"
	lq.custom_minimum_size = Vector2(240, 46)
	lq.pressed.connect(func() -> void: game.exit_requested.emit())
	lv.add_child(lq)
	# Infos réseau (hôte : IP:port à donner aux autres joueurs)
	_netinfo = _lbl(15, Color(0.75, 0.85, 1.0))
	_netinfo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_netinfo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_netinfo.position.y = 66
	root.add_child(_netinfo)
	# Pause
	_pause = ColorRect.new()
	(_pause as ColorRect).color = Color(0, 0, 0, 0.65)
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	root.add_child(_pause)
	var pb := VBoxContainer.new()
	pb.set_anchors_preset(Control.PRESET_CENTER)
	pb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pb.grow_vertical = Control.GROW_DIRECTION_BOTH
	pb.add_theme_constant_override("separation", 12)
	_pause.add_child(pb)
	var pt := _lbl(48)
	pt.text = "PAUSE"
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pb.add_child(pt)
	var b1 := Button.new()
	b1.text = "Reprendre"
	b1.custom_minimum_size = Vector2(260, 46)
	b1.pressed.connect(_toggle_pause)
	pb.add_child(b1)
	var b2 := Button.new()
	b2.text = "Menu principal"
	b2.custom_minimum_size = Vector2(260, 46)
	b2.pressed.connect(func() -> void:
		get_tree().paused = false
		game.exit_requested.emit())
	pb.add_child(b2)

func _update_lobby() -> void:
	var on := game.hnet != null and game.match_manager.state == Cfg.State.LOBBY
	_lobby.visible = on
	if not on:
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # pour pouvoir cliquer « Lancer »
	var n := game.hnet.players.size()
	var s := ""
	for id in game.hnet.players:
		var q: PlayerController = game.hnet.players[id]
		s += "%s  —  %s%s\n" % [q.display_name, Cfg.TEAM_NAMES[q.team], "  (hôte)" if id == 1 else ""]
	_lobby_list.text = s
	var host := game.hnet.is_host()
	if n < 2:
		_lobby_title.text = "En attente de joueurs… (%d/%d)" % [n, HikaNet.MAX_PLAYERS]
	elif game.hnet.lobby_t >= 0.0:
		_lobby_title.text = "La partie démarre dans %d s… (%d/%d)" % [ceili(game.hnet.lobby_t), n, HikaNet.MAX_PLAYERS]
	else:
		_lobby_title.text = "En attente de l'hôte… (%d/%d)" % [n, HikaNet.MAX_PLAYERS]
	_lobby_btn.visible = host
	_lobby_btn.disabled = n < 2

func is_paused() -> bool:
	return _pause != null and _pause.visible

## Sur téléphone : coeurs et inventaire en haut (les contrôles occupent le bas), journal décalé pour laisser le bouton Pause.
func _touch_layout() -> void:
	_touch = true
	_hearts.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hearts.position = Vector2(12, 12)
	_protect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_protect.position = Vector2(12, 42)
	_inv_ui.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_inv_ui.grow_vertical = Control.GROW_DIRECTION_END
	_inv_ui.position = Vector2(12, 70)
	_inv_ui.scale = Vector2(0.7, 0.7)
	_feed.position = Vector2(-150, 14)

func bind(g: GameManager) -> void:
	game = g
	if g.touch != null:
		_touch_layout()
	for c in get_children():
		pass
	var mm := g.match_manager
	g.score_manager.score_changed.connect(_on_score)
	mm.countdown_tick.connect(func(n: int) -> void:
		_count.text = str(n)
		_count.modulate.a = 1.0)
	mm.state_changed.connect(_on_state)
	mm.point_scored.connect(func(team: int, scorer: PlayerController) -> void:
		_banner.text = "%s marque !" % Cfg.TEAM_NAMES[team]
		_banner.add_theme_color_override("font_color", Cfg.TEAM_COLORS[team]))
	mm.match_finished.connect(func(w: int) -> void:
		_victory.visible = true
		_victory_label.text = "%s GAGNE !" % Cfg.TEAM_NAMES[w]
		_victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_victory_label.add_theme_color_override("font_color", Cfg.TEAM_COLORS[w]))
	_on_score(-1, g.score_manager.scores)
	var h := g.human
	_inv_ui.bind(h.inv)
	h.health.damaged.connect(func(_a: float, _s: PlayerController) -> void: _vignette.color.a = 0.35)
	g.authority.attack_landed.connect(func(att: PlayerController, _v: PlayerController, _d: float) -> void:
		if att == h:
			_hit_t = 0.12)
	for n in get_children():
		if n is Control:
			pass
	# le Scoreboard a été créé avant bind : on lui donne le jeu
	for n in find_children("*", "Scoreboard", true, false):
		(n as Scoreboard).game = g

func _on_score(_team: int, s: Array) -> void:
	_score_r.text = str(s[0])
	_score_b.text = str(s[1])

func _on_state(s: int, _old: int) -> void:
	match s:
		Cfg.State.WAITING:
			_victory.visible = false
			_banner.text = ""
			_count.text = ""
		Cfg.State.COUNTDOWN:
			_banner.text = ""
		Cfg.State.PLAYING:
			_count.text = "GO !"
			var tw := create_tween()
			tw.tween_property(_count, "modulate:a", 0.0, 0.8)
			tw.tween_callback(func() -> void:
				_count.text = ""
				_count.modulate.a = 1.0)

func feed(text: String, color: Color) -> void:
	var l := _lbl(18, color)
	l.text = text
	_feed.add_child(l)
	get_tree().create_timer(4.0).timeout.connect(l.queue_free)

func _process(dt: float) -> void:
	if game == null:
		return
	var h := game.human
	var hp := h.health.hp
	_hearts.set_hp(hp, Tuning.max_health)
	_protect.visible = h.health.is_protected() and h.alive
	_mine.size.x = 40.0 * h.mine_progress
	_netinfo.text = game.hnet.info_text() if game.hnet else ""
	_update_lobby()
	_vignette.color.a = maxf(_vignette.color.a - dt * 1.5, 0.0)
	_hit_t = maxf(_hit_t - dt, 0.0)
	_cross.modulate = Color(1, 0.3, 0.3) if _hit_t > 0.0 else Color.WHITE

func _toggle_pause() -> void:
	var p := not _pause.visible
	if game.net.mode == NetworkManager.Mode.LOCAL:
		get_tree().paused = p   # en réseau la partie continue pour les autres : on affiche seulement le menu
	_pause.visible = p
	if p:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif game.touch == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_ESCAPE:
			if game.match_manager.state == Cfg.State.MATCH_FINISHED:
				game.exit_requested.emit()
			else:
				_toggle_pause()
		elif e.keycode == KEY_R and game.match_manager.state == Cfg.State.MATCH_FINISHED:
			game.restart_match()
