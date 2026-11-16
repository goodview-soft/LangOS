class_name HikaTouch
extends CanvasLayer
## Contrôles tactiles (téléphone) : joystick virtuel flottant à gauche, regard au doigt sur la moitié droite,
## boutons Frapper/Casser, Saut, Poser, Objet (épée/pioche/blocs), Pont automatique et Pause.
## Affichés seulement sur mobile / écran tactile, ou avec --hb-touch (test PC : la souris joue un doigt).
## Mise en page recalculée selon la taille de la fenêtre (paysage ou portrait) ; boutons >= 44 px ;
## l'icône « quitter » du bureau (44 px, coin haut droit) et le bouton Pause sont placés sans chevauchement.

const EMU := -1             # InputEvent.DEVICE_ID_EMULATION : souris synthétisée depuis un toucher
const MOUSE_FINGER := 99
const EXIT_SZ := 44.0       # icône de sortie de main.gd (_game_chrome) : 44 px à 8 px des bords

var game: GameManager
var on := false             # visible et actif (en partie, hors pause)
var move := Vector2.ZERO    # joystick de marche, -1..1 (y vers l'avant)
var jump_held := false
var hit_held := false
var place_held := false
var look_sens := 0.0045     # rad par pixel
var u := 44.0               # unité de taille (diamètre minimal d'un bouton)
var buttons: Array = []     # {id, txt, c, r}
var stick_c := Vector2.ZERO
var stick_r := 56.0
var mouse_sim := false      # souris = doigt (PC avec --hb-touch)

var _canvas: Control
var _size := Vector2.ZERO
var _fingers := {}
var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _jump_pending := false
var _hit_pending := false

static func wanted() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() or "--hb-touch" in OS.get_cmdline_user_args()

func _ready() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_sim = not DisplayServer.is_touchscreen_available() and not OS.has_feature("mobile")
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_all)
	add_child(_canvas)
	visible = false

## Calcule les positions des boutons pour une fenêtre de taille `sz` (paysage ou portrait).
func layout(sz: Vector2) -> void:
	_size = sz
	u = clampf(minf(sz.x, sz.y) * 0.115, 44.0, 84.0)
	var m := 0.35 * u
	var r1 := 0.9 * u     # gros bouton Frapper
	var r2 := 0.62 * u    # boutons moyens (diamètre 1,24 u >= 44 px)
	var gap := 0.25 * u
	var hit := Vector2(sz.x - m - r1, sz.y - m - r1)
	var jump := Vector2(hit.x, hit.y - r1 - r2 - gap)
	var place := Vector2(hit.x - r1 - r2 - gap, sz.y - m - r2 - 0.1 * u)
	var swap := Vector2(place.x, place.y - 2.0 * r2 - gap)
	var bridge := Vector2(place.x, swap.y - 2.0 * r2 - gap)
	var pause := Vector2(sz.x - 8.0 - EXIT_SZ - 8.0 - 26.0, 8.0 + EXIT_SZ * 0.5)
	buttons = [
		{"id": "hit", "txt": "Frapper", "c": hit, "r": r1},
		{"id": "jump", "txt": "Saut", "c": jump, "r": r2},
		{"id": "place", "txt": "Poser", "c": place, "r": r2},
		{"id": "swap", "txt": "Objet", "c": swap, "r": r2},
		{"id": "bridge", "txt": "Pont", "c": bridge, "r": r2},
		{"id": "pause", "txt": "||", "c": pause, "r": 26.0},   # diamètre 52 px, collé au bouton de sortie
	]
	stick_r = 1.25 * u
	stick_c = Vector2(m + stick_r + 0.3 * u, sz.y - m - stick_r - 0.3 * u)
	if _stick_finger < 0:
		_stick_origin = stick_c

func _process(_dt: float) -> void:
	var sz := _canvas.size
	if sz != _size and sz.x > 8.0:
		layout(sz)
	var want: bool = game != null and game.human != null and game.human.alive and not game.is_paused() and game.match_manager.state != Cfg.State.MATCH_FINISHED and game.match_manager.state != Cfg.State.LOBBY
	if want != on:
		on = want
		visible = want
		if not want:
			release_all()
	if on:
		_canvas.queue_redraw()

func release_all() -> void:
	_fingers.clear()
	_stick_finger = -1
	_stick_origin = stick_c
	move = Vector2.ZERO
	jump_held = false
	hit_held = false
	place_held = false

func take_jump() -> bool:
	var j := _jump_pending
	_jump_pending = false
	return j

func take_hit() -> bool:
	var h := _hit_pending
	_hit_pending = false
	return h

# ---------------------------------------------------------------- événements
func _input(ev: InputEvent) -> void:
	if not on:
		return
	if ev is InputEventScreenTouch:
		_touch(ev.index, ev.position, ev.pressed)
		get_viewport().set_input_as_handled()
	elif ev is InputEventScreenDrag:
		_drag(ev.index, ev.position, ev.relative)
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.device == EMU:
			get_viewport().set_input_as_handled()   # écho « souris » d'un toucher déjà traité
		elif mouse_sim:
			_touch(MOUSE_FINGER, ev.position, ev.pressed)
			get_viewport().set_input_as_handled()
	elif ev is InputEventMouseMotion and mouse_sim and _fingers.has(MOUSE_FINGER):
		_drag(MOUSE_FINGER, ev.position, ev.relative)

func btn_at(p: Vector2) -> String:
	for b in buttons:
		if p.distance_to(b["c"]) <= float(b["r"]) + 4.0:
			return b["id"]
	return ""

func _touch(i: int, p: Vector2, down: bool) -> void:
	if not down:
		_release(i)
		return
	var id := btn_at(p)
	if id != "":
		_fingers[i] = {"role": "btn", "id": id}
		_press(id, true)
	elif p.x < _size.x * 0.5 and _stick_finger < 0:
		_fingers[i] = {"role": "stick"}
		_stick_finger = i
		_stick_origin = p.clamp(Vector2(stick_r, stick_r), _size - Vector2(stick_r, stick_r))
		move = Vector2.ZERO
	else:
		_fingers[i] = {"role": "look"}

func _drag(i: int, p: Vector2, rel: Vector2) -> void:
	if not _fingers.has(i):
		return
	match _fingers[i]["role"]:
		"stick":
			var v := ((p - _stick_origin) / stick_r).limit_length(1.0)
			move = Vector2(v.x, -v.y)
		"look":
			if game and game.human:
				game.human.yaw -= rel.x * look_sens
				game.human.pitch = clampf(game.human.pitch - rel.y * look_sens, -1.5, 1.5)

func _release(i: int) -> void:
	if not _fingers.has(i):
		return
	var f: Dictionary = _fingers[i]
	_fingers.erase(i)
	match f["role"]:
		"btn":
			_press(f["id"], false)
		"stick":
			_stick_finger = -1
			_stick_origin = stick_c
			move = Vector2.ZERO

func _press(id: String, down: bool) -> void:
	match id:
		"hit":
			hit_held = down
			if down:
				_hit_pending = true
		"jump":
			jump_held = down
			if down:
				_jump_pending = true
		"place":
			place_held = down
		"swap":
			if down and game and game.human:
				game.human.inv.scroll(1)
		"bridge":
			if down and game and game.human:
				toggle_bridge()
		"pause":
			if down and game and game.hud:
				game.hud._toggle_pause()

func toggle_bridge() -> void:
	var h := game.human
	h.auto_bridge = not h.auto_bridge
	game.announce("Pont automatique : " + ("activé" if h.auto_bridge else "désactivé"), Color(1, 0.9, 0.5))

# ---------------------------------------------------------------- dessin
func _draw_all() -> void:
	var font := ThemeDB.fallback_font
	_canvas.draw_circle(_stick_origin, stick_r, Color(0.05, 0.05, 0.1, 0.28))
	_canvas.draw_arc(_stick_origin, stick_r - 0.5, 0.0, TAU, 40, Color(1, 1, 1, 0.3), 2.0)
	_canvas.draw_circle(_stick_origin + Vector2(move.x, -move.y) * (stick_r - 0.4 * u), 0.42 * u, Color(1, 1, 1, 0.55 if _stick_finger >= 0 else 0.32))
	for b in buttons:
		var id: String = b["id"]
		var held: bool = (id == "hit" and hit_held) or (id == "jump" and jump_held) or (id == "place" and place_held) \
			or (id == "bridge" and game != null and game.human != null and game.human.auto_bridge)
		var c: Vector2 = b["c"]
		var r: float = b["r"]
		_canvas.draw_circle(c, r, Color(0.9, 0.7, 0.25, 0.6) if held else Color(0.05, 0.04, 0.08, 0.45))
		_canvas.draw_arc(c, r - 0.5, 0.0, TAU, 32, Color(1, 0.9, 0.6, 0.55), 2.0)
		var fs := int(clampf(r * 0.38, 12.0, 24.0))
		var w := font.get_string_size(b["txt"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_canvas.draw_string(font, c + Vector2(-w / 2.0, fs * 0.35), b["txt"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.92))
