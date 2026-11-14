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

func bind(g: GameManager) -> void:
	game = g
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
		_victory_label.text = "%s GAGNE !\n\nR : rejouer   ·   Échap : menu" % Cfg.TEAM_NAMES[w]
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
	_vignette.color.a = maxf(_vignette.color.a - dt * 1.5, 0.0)
	_hit_t = maxf(_hit_t - dt, 0.0)
	_cross.modulate = Color(1, 0.3, 0.3) if _hit_t > 0.0 else Color.WHITE

func _toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	_pause.visible = p
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_ESCAPE:
			if game.match_manager.state == Cfg.State.MATCH_FINISHED:
				game.exit_requested.emit()
			else:
				_toggle_pause()
		elif e.keycode == KEY_R and game.match_manager.state == Cfg.State.MATCH_FINISHED:
			game.restart_match()
