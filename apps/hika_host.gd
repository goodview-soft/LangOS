extends Control
## Fenêtre Hikabrain : menu commun (GameMenu) puis le jeu 3D dans un SubViewport.
## Les entrées sont transmises à la main (la souris est capturée pendant la partie, Échap = pause).

const SCENE := "res://games/hikabrain/scenes/game.tscn"
var menu: GameMenu
var sv: SubViewport
var view: TextureRect
var game: Node

func _ready() -> void:
	clip_contents = true
	sv = SubViewport.new(); sv.own_world_3d = true; sv.msaa_3d = Viewport.MSAA_2X
	sv.size = Vector2i(maxi(64, int(size.x)), maxi(64, int(size.y))); add_child(sv)
	view = TextureRect.new(); view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; view.stretch_mode = TextureRect.STRETCH_SCALE
	view.set_anchors_preset(Control.PRESET_FULL_RECT); view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.texture = sv.get_texture(); add_child(view)
	menu = GameMenu.new(); menu.game_id = "hika"; menu.title = "Hikabrain"; menu.modes = ["ai", "local", "net"]
	menu.disabled_modes = {"local": "bientôt", "net": "bientôt"}
	add_child(menu)
	menu.chosen.connect(_start)
	resized.connect(func(): sv.size = Vector2i(maxi(64, int(size.x)), maxi(64, int(size.y))))
	visibility_changed.connect(_vis)

func _start(_mode: String) -> void:
	_stop(false)
	game = (load(SCENE) as PackedScene).instantiate()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE   # la pause du jeu ne gèle que lui
	game.exit_requested.connect(func(): _stop(true))
	sv.add_child(game)
	OS.low_processor_usage_mode = false

func _stop(show_menu: bool) -> void:
	if game:
		game.queue_free(); game = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	OS.low_processor_usage_mode = true
	if show_menu: menu.show_menu()

func _exit_tree() -> void: _stop(false)

func _vis() -> void:
	if game and not is_visible_in_tree():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if not get_tree().paused and game.get("hud"): game.hud._toggle_pause()

func _input(ev: InputEvent) -> void:
	if game == null or not is_visible_in_tree(): return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var inside := get_global_rect().has_point(get_global_mouse_position())
	if not (captured or inside): return
	if ev is InputEventMouse:
		if not (captured or inside): return
		var e = ev.duplicate()
		e.position = ev.position - global_position; e.global_position = e.position
		sv.push_input(e)
	else:
		sv.push_input(ev)
	get_viewport().set_input_as_handled()
