class_name TouchControls extends CanvasLayer
## Contrôles tactiles (téléphone). Affichés seulement sur mobile / écran tactile, ou avec --dm-touch (test PC :
## la souris joue alors le rôle d'un doigt). Les touches clavier/souris ne sont jamais désactivées.
## Disposition (canvas 640x360) : joystick de marche à gauche, caméra (JoyPad du HUD) à sa droite, boutons à droite,
## barre d'objets tapable, pincer = zoom, toucher le monde = viser (la visée reste jusqu'au prochain toucher).

const STICK_C0 := Vector2(62, 276)   # centre par défaut du joystick de marche (360 px de haut ; + dy)
const STICK_R := 34.0
const STICK_ZONE0 := Rect2(0, 150, 172, 210)  # un doigt posé ici déplace le joystick sous lui
const EMU := -1  # InputEvent.DEVICE_ID_EMULATION : souris synthétisée depuis un toucher
const MOUSE_FINGER := 99  # --dm-touch sur PC : le bouton gauche de la souris joue un doigt

var main: Node
var enabled := true     # false : tout est caché et ignoré (menus, sac, chat, pause...)
var move := Vector2.ZERO  # joystick de marche, -1..1 (y vers le haut)
var jump := false
var mine := false       # bouton « miner » tenu
var crouch := false     # bascule
var aim := Vector2.ZERO # dernier point visé (coordonnées canvas 640x360)
var has_aim := false
var mouse_sim := false  # souris = doigt (PC avec --dm-touch)

var _fingers := {}      # index -> {"role": String, ...}
var dy := 0.0:  # hauteur logique ajoutée sous les 360 px de base
	set(v):
		dy = v
		if _stick_finger < 0:
			_stick_origin = STICK_C()
var _stick_origin := STICK_C0
var _stick_finger := -1
var _pinch_ref := 0.0
var _canvas: Control
## Boutons : id, libellé, centre, rayon, "hold" (tenu) ou "tap"
var buttons: Array = [
	{"id": "mine", "txt": "Miner", "c": Vector2(590, 268), "r": 29.0, "hold": true},
	{"id": "jump", "txt": "Saut", "c": Vector2(532, 300), "r": 23.0, "hold": true},
	{"id": "place", "txt": "Poser", "c": Vector2(534, 236), "r": 21.0, "hold": false},
	{"id": "crouch", "txt": "Accr.", "c": Vector2(482, 304), "r": 20.0, "hold": false},
	{"id": "inv", "txt": "Sac", "c": Vector2(604, 200), "r": 17.0, "hold": false},
	{"id": "use", "txt": "Agir", "c": Vector2(562, 200), "r": 17.0, "hold": false},
	{"id": "abil", "txt": "Pouv.", "c": Vector2(520, 200), "r": 17.0, "hold": false},
	{"id": "pause", "txt": "||", "c": Vector2(622, 100), "r": 14.0, "hold": false},
]

func STICK_C() -> Vector2:
	return STICK_C0 + Vector2(0, dy)

func STICK_ZONE() -> Rect2:
	return Rect2(STICK_ZONE0.position + Vector2(0, dy), STICK_ZONE0.size)

## Centre d'un bouton (le bouton pause reste en haut).
func _bc(b: Dictionary) -> Vector2:
	return b.c if b.id == "pause" else b.c + Vector2(0, dy)

static func wanted() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() or "--dm-touch" in OS.get_cmdline_user_args()

func _ready() -> void:
	layer = 4
	mouse_sim = not DisplayServer.is_touchscreen_available() and not OS.has_feature("mobile")
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_all)
	add_child(_canvas)

## Les contrôles ne sont actifs qu'en jeu (ni menu, ni sac, ni livre, ni chat).
func _active() -> bool:
	if main == null:
		return true
	return main.state == "play" and not main.input_blocked()

func _process(_dt: float) -> void:
	var on := _active()
	if on != visible:
		visible = on
		if not on:
			release_all()
	if on:
		_canvas.queue_redraw()

func release_all() -> void:
	_fingers.clear()
	_stick_finger = -1
	move = Vector2.ZERO
	jump = false
	mine = false
	if main != null and main.hud != null:
		main.hud.joy.drag = false
		main.hud.joy.vec = Vector2.ZERO

# ---------------------------------------------------------------- événements
func _input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev is InputEventScreenTouch:
		_touch((ev as InputEventScreenTouch).index, (ev as InputEventScreenTouch).position, (ev as InputEventScreenTouch).pressed)
		get_viewport().set_input_as_handled()
	elif ev is InputEventScreenDrag:
		_drag((ev as InputEventScreenDrag).index, (ev as InputEventScreenDrag).position)
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		if mb.device == EMU:  # le toucher a déjà été traité ci-dessus : on avale son écho « souris » sur nos contrôles
			if _on_controls(mb.position) or not mb.pressed:
				get_viewport().set_input_as_handled()
		elif mouse_sim:
			_touch(MOUSE_FINGER, mb.position, mb.pressed)
			if _fingers.has(MOUSE_FINGER) and _fingers[MOUSE_FINGER].role != "world" or not mb.pressed:
				get_viewport().set_input_as_handled()
	elif ev is InputEventMouseMotion and mouse_sim and _fingers.has(MOUSE_FINGER):
		_drag(MOUSE_FINGER, (ev as InputEventMouseMotion).position)

func _btn_at(p: Vector2) -> Dictionary:
	for b in buttons:
		if p.distance_to(_bc(b)) <= b.r + 5.0:
			return b
	return {}

func _hotbar_at(p: Vector2) -> int:
	if main == null or main.hud == null:
		return -1
	for i in main.hud.slots.size():
		var s: Control = main.hud.slots[i][0]
		var t := s.get_global_transform()
		if Rect2(t.origin, t.basis_xform(s.size)).grow(2.0).has_point(p):
			return i
	return -1

func _on_controls(p: Vector2) -> bool:
	return not _btn_at(p).is_empty() or _hotbar_at(p) >= 0 or _in_cam_pad(p) or STICK_ZONE().has_point(p)

func _in_cam_pad(p: Vector2) -> bool:
	if main == null or main.hud == null:
		return false
	return Rect2(main.hud.joy.position, main.hud.joy.size).grow(6.0).has_point(p)

func _touch(i: int, p: Vector2, down: bool) -> void:
	if not down:
		_release(i, p)
		return
	var b := _btn_at(p)
	if not b.is_empty():
		_fingers[i] = {"role": "btn", "id": b.id}
		_press_button(b.id, true)
		return
	var h := _hotbar_at(p)
	if h >= 0:
		_fingers[i] = {"role": "hotbar"}
		select_slot(h)
		return
	if _in_cam_pad(p):
		_fingers[i] = {"role": "cam"}
		_cam_aim(p)
		return
	if STICK_ZONE().has_point(p) and _stick_finger < 0:
		_fingers[i] = {"role": "stick"}
		_stick_finger = i
		_stick_origin = p.clamp(STICK_ZONE().position + Vector2(STICK_R, STICK_R), STICK_ZONE().end - Vector2(STICK_R, STICK_R))
		move = Vector2.ZERO
		return
	_fingers[i] = {"role": "world", "pos": p}
	set_aim(p)
	_pinch_ref = _world_dist()

func _drag(i: int, p: Vector2) -> void:
	if not _fingers.has(i):
		return
	match _fingers[i].role:
		"stick":
			move = ((p - _stick_origin) / STICK_R).limit_length(1.0)
		"cam":
			_cam_aim(p)
		"world":
			_fingers[i]["pos"] = p
			if _world_count() >= 2:
				_pinch()
			else:
				set_aim(p)

func _release(i: int, _p: Vector2) -> void:
	if not _fingers.has(i):
		return
	var f: Dictionary = _fingers[i]
	_fingers.erase(i)
	match f.role:
		"btn":
			_press_button(f.id, false)
		"stick":
			_stick_finger = -1
			move = Vector2.ZERO
			_stick_origin = STICK_C()
		"cam":
			if main != null and main.hud != null:
				main.hud.joy.drag = false
				main.hud.joy.vec = Vector2.ZERO
				main.hud.joy.queue_redraw()
	_pinch_ref = 0.0

func _cam_aim(p: Vector2) -> void:
	if main == null or main.hud == null:
		return
	var j: Control = main.hud.joy
	j.drag = true
	j._aim(p - j.position)
	j.queue_redraw()

func set_aim(p: Vector2) -> void:
	aim = p
	has_aim = true

func select_slot(i: int) -> void:
	if main != null:
		main.sel = clampi(i, 0, main.hotbar.size() - 1)

# ---------------------------------------------------------------- boutons
func _press_button(id: String, down: bool) -> void:
	match id:
		"mine":
			mine = down
		"jump":
			jump = down
		"crouch":
			if down:
				crouch = not crouch
		_:
			if down and main != null:
				match id:
					"place": main.use_item()
					"inv": main.bag.open()
					"use": main._interact()
					"abil": main.abilities.trigger()
					"pause": main._pause()

# ---------------------------------------------------------------- pincer = zoom
func _world_count() -> int:
	var n := 0
	for k in _fingers:
		if _fingers[k].role == "world":
			n += 1
	return n

func _world_dist() -> float:
	var ps: Array = []
	for k in _fingers:
		if _fingers[k].role == "world" and _fingers[k].has("pos"):
			ps.append(_fingers[k].pos)
	return (ps[0] as Vector2).distance_to(ps[1]) if ps.size() >= 2 else 0.0

func _pinch() -> void:
	var d := _world_dist()
	if d < 8.0:
		return
	if _pinch_ref <= 0.0:
		_pinch_ref = d
		return
	var r := d / _pinch_ref
	if r > 1.3:  # écarter = zoom avant (comme la molette vers le haut)
		_zoom(-1)
		_pinch_ref = d
	elif r < 0.77:
		_zoom(1)
		_pinch_ref = d

func _zoom(step: int) -> void:
	if main != null:
		main.zoom_i = clampi(main.zoom_i + step, 0, main.ZOOMS.size() - 1)

# ---------------------------------------------------------------- dessin
func _draw_all() -> void:
	var font := ThemeDB.fallback_font
	var oc := _stick_origin
	_canvas.draw_circle(oc, STICK_R, Color(0.05, 0.05, 0.1, 0.30))
	_canvas.draw_arc(oc, STICK_R - 0.5, 0.0, TAU, 32, Color(1, 1, 1, 0.30), 1.0)
	_canvas.draw_circle(oc + move * (STICK_R - 10.0), 11.0, Color(1, 1, 1, 0.55 if _stick_finger >= 0 else 0.32))
	for b in buttons:
		var held: bool = (b.id == "mine" and mine) or (b.id == "jump" and jump) or (b.id == "crouch" and crouch)
		_canvas.draw_circle(_bc(b), b.r, Color(0.9, 0.7, 0.25, 0.55) if held else Color(0.05, 0.04, 0.08, 0.42))
		_canvas.draw_arc(_bc(b), b.r - 0.5, 0.0, TAU, 28, Color(1, 0.9, 0.6, 0.5), 1.0)
		var sz := 10 if b.r < 22.0 else 11
		var w := font.get_string_size(b.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		_canvas.draw_string(font, _bc(b) + Vector2(-w / 2.0, 4), b.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(1, 1, 1, 0.9))
	if has_aim:  # petite croix : le point visé
		_canvas.draw_arc(aim, 5.0, 0.0, TAU, 16, Color(1, 0.95, 0.5, 0.7), 1.0)
