extends Control
## Fenêtre Hikabrain : menu commun (GameMenu) puis le jeu 3D dans un SubViewport.
## Les entrées sont transmises à la main (la souris est capturée pendant la partie, Échap = pause).

const SCENE := "res://games/hikabrain/scenes/game.tscn"
var menu: GameMenu
var sv: SubViewport
var view: TextureRect
var game: Node
var _conn: Control          # « Connexion… » (client, avant la réponse de l'hôte)
var _touch := false

func _ready() -> void:
	clip_contents = true
	sv = SubViewport.new(); sv.own_world_3d = true; sv.msaa_3d = Viewport.MSAA_2X
	sv.size = Vector2i(maxi(64, int(size.x)), maxi(64, int(size.y))); add_child(sv)
	view = TextureRect.new(); view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; view.stretch_mode = TextureRect.STRETCH_SCALE
	view.set_anchors_preset(Control.PRESET_FULL_RECT); view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.texture = sv.get_texture(); add_child(view)
	_touch = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	menu = GameMenu.new(); menu.game_id = "hika"; menu.title = "Hikabrain"; menu.modes = ["ai", "local", "net"]
	menu.disabled_modes = {"local": "non disponible"}   # à deux sur le même appareil : pas de partage d'écran en 3D
	menu.multi = true; menu.adv_port = NetworkManager.DEFAULT_PORT   # découverte LAN + lobby du menu commun, 2 à 8 joueurs
	add_child(menu)
	menu.chosen.connect(func(_m: String): _start({}))
	menu.net_multi.connect(_net_go)
	_build_conn()
	resized.connect(func(): sv.size = Vector2i(maxi(64, int(size.x)), maxi(64, int(size.y))))
	visibility_changed.connect(_vis)

func _start(cfg: Dictionary) -> void:
	_stop(false)
	game = (load(SCENE) as PackedScene).instantiate()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE   # la pause du jeu ne gèle que lui
	if not cfg.is_empty(): game.set_meta("net", cfg)
	game.exit_requested.connect(func(): _stop(true))
	game.net_failed.connect(func(msg: String): _stop(false); menu.show_lobby(msg))
	sv.add_child(game)
	OS.low_processor_usage_mode = false

func _stop(show_menu: bool) -> void:
	if game:
		sv.remove_child(game)   # libère tout de suite le nom fixe « HikaGame » (chemins RPC identiques chez tous les pairs)
		game.queue_free(); game = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	OS.low_processor_usage_mode = true
	if show_menu: menu.show_menu()

func _exit_tree() -> void: _stop(false)

# ---------------------------------------------------------------- Réseau local (découverte et lobby : GameMenu en mode multi)
func _lbl(t: String, sz := 16) -> Label:
	var l := Label.new(); l.text = t; l.add_theme_font_size_override("font_size", sz)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; return l

func _build_conn() -> void:
	_conn = Control.new(); _conn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _conn.visible = false
	var cc2 := CenterContainer.new(); cc2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _conn.add_child(cc2)
	var vb2 := VBoxContainer.new(); vb2.add_theme_constant_override("separation", 12); cc2.add_child(vb2)
	vb2.add_child(_lbl("Connexion à l'hôte…", 22))
	var b := Button.new(); b.text = "Annuler"; b.custom_minimum_size.y = 50
	b.pressed.connect(func(): _stop(false); menu.show_lobby(""))
	vb2.add_child(b)
	add_child(_conn)

func _net_go(role: String, ip: String, port: int) -> void:
	_start({"mode": role, "ip": ip, "port": port, "name": menu.my_name})

func _process(_dt: float) -> void:
	_conn.visible = game != null and game.get("human") == null and game.get("hnet") != null

func _vis() -> void:
	if game and not is_visible_in_tree():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if not game.is_paused() and game.get("hud"): game.hud._toggle_pause()

func _input(ev: InputEvent) -> void:
	if game == null or game.get("human") == null or not is_visible_in_tree(): return   # pas de jeu (ou connexion en cours) : l'interface normale reçoit tout
	if ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		var tin := get_global_rect().has_point(ev.position)
		if not tin and not (ev is InputEventScreenTouch and not ev.pressed): return
		var e2: InputEvent = ev.duplicate()
		e2.position = ev.position - global_position
		sv.push_input(e2)
		get_viewport().set_input_as_handled()
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var inside := get_global_rect().has_point(get_global_mouse_position())
	if not (captured or inside): return
	if ev is InputEventMouse:
		var e = ev.duplicate()
		e.position = ev.position - global_position; e.global_position = e.position
		sv.push_input(e)
	else:
		sv.push_input(ev)
	get_viewport().set_input_as_handled()
