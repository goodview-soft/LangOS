extends Control
## Fenêtre Deep Miner : le jeu 3D (games/deepminer) tourne dans un SubViewport 640x(360+) logique.
## Mise en page : fenêtre plus large que 16:9 -> bandes noires sur les côtés ; plus haute -> le jeu remplit la largeur
## et gagne de la hauteur (le HUD du bas et les contrôles tactiles descendent), plafonnée à 640x480.
## Entrées poussées à la main (clavier/souris seulement si la fenêtre est « active », tactile transformé).
## Clic dans le jeu = capture de la souris (vue FPS), Échap = pause du jeu qui la libère.

const SCENE := "res://games/deepminer/main.tscn"
const LW := 640.0
var on_exit: Callable   # fournie par main.gd : ferme la fenêtre LangOS
var sv: SubViewport
var view: TextureRect
var game: Node
var active := true      # dernier clic dans cette fenêtre ?
var _scale := 1.0       # pixels de la fenêtre par pixel logique
var _lh := 360.0

func _ready() -> void:
	clip_contents = true
	var bg := ColorRect.new(); bg.color = Color.BLACK; bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(bg)
	sv = SubViewport.new(); sv.own_world_3d = true; sv.msaa_3d = Viewport.MSAA_2X
	sv.handle_input_locally = false; sv.gui_embed_subwindows = true
	add_child(sv)
	view = TextureRect.new(); view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE; view.texture = sv.get_texture(); add_child(view)
	resized.connect(_layout)
	visibility_changed.connect(_vis)
	_layout()
	_start.call_deferred()

func _layout() -> void:
	if sv == null: return
	var w := maxf(64.0, size.x); var h := maxf(64.0, size.y)
	var vw := w; var vh := h
	_lh = 360.0
	if w / h >= LW / 360.0:        # plus large que 16:9 : bandes sur les côtés
		vw = h * LW / 360.0
	else:                          # plus haut : hauteur logique en plus, jusqu'à 480
		_lh = clampf(LW * h / w, 360.0, 480.0)
		vh = minf(h, w * _lh / LW)
		_lh = vh * LW / w
	_scale = vw / LW
	sv.size = Vector2i(maxi(64, int(vw)), maxi(64, int(vh)))
	sv.size_2d_override = Vector2i(int(LW), int(roundf(_lh)))
	sv.size_2d_override_stretch = true
	view.position = Vector2(roundf((w - vw) / 2.0), roundf((h - vh) / 2.0)); view.size = Vector2(vw, vh)
	if game and game.has_method("set_extra_h"): game.set_extra_h(maxf(0.0, roundf(_lh) - 360.0))

func _start() -> void:
	_stop()
	DirAccess.make_dir_recursive_absolute("user://deepminer")
	game = (load(SCENE) as PackedScene).instantiate()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.exit_requested.connect(func(): if on_exit.is_valid(): on_exit.call() else: _stop())
	game.restart_requested.connect(_start.call_deferred)
	sv.add_child(game)
	game.set_extra_h(maxf(0.0, roundf(_lh) - 360.0))
	OS.low_processor_usage_mode = false
	active = true

func _stop() -> void:
	if game and is_instance_valid(game):
		if game.has_method("save_game") and game.get("state") in ["play", "pause"]: game.save_game(game.SAVE_PATH)
		game.queue_free()
	game = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	OS.low_processor_usage_mode = true

func _exit_tree() -> void: _stop()

func _vis() -> void:
	if game and not is_visible_in_tree():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if game.get("state") == "play": game._pause()

func _recapture() -> void:
	# Clic dans le jeu : reprend la souris en vue FPS (après Échap ou un menu) — jamais ailleurs.
	if game == null or game.get("state") != "play" or game.view == null: return
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and game.view.mode == ViewCtl.FPS and not game.view.fps.third and not game.input_blocked():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(ev: InputEvent) -> void:
	if game == null or not is_visible_in_tree(): return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var inside := view.get_global_rect().has_point(get_global_mouse_position())
	if ev is InputEventMouseButton and ev.pressed:
		active = get_global_rect().has_point(get_global_mouse_position()) or captured
		if inside and ev.button_index == MOUSE_BUTTON_LEFT and not captured: _recapture()
	game.ext_block = not (active or captured)
	if not (active or captured): return
	if ev is InputEventMouse:
		if not (captured or inside): return
		var e: InputEvent = ev.duplicate()
		e.position = ev.position - view.global_position; e.global_position = e.position
		if e is InputEventMouseMotion: e.relative = ev.relative * (_scale / 3.0)   # même sensibilité que l'original (fenêtre 1920 = x3)
		sv.push_input(e)
	elif ev is InputEventScreenTouch or ev is InputEventScreenDrag:
		if not inside and not (ev is InputEventScreenTouch and not ev.pressed): return
		var e2: InputEvent = ev.duplicate()
		e2.position = ev.position - view.global_position
		sv.push_input(e2)
	else:
		sv.push_input(ev)
	get_viewport().set_input_as_handled()
