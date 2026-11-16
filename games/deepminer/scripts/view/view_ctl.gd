class_name ViewCtl extends Node
## View mode manager. Main view: CUT = 2D side view with the custom sprites, FPS (3rd person by default, or 1st person; V cycles).
## Per-view meshes (2D caps, level-cut caps, sprites, cube bodies) live on their own render layers.
## Hooks in main.gd call into this.

enum { CUT, FPS }

var m: Node  # main
var mode := CUT
var iso: IsoView
var fps: FpsView

# render layers (bits)
const L_CAPS_ISO := 1 << 1  # level-cut caps (X, 3rd person)
const L_BODY_P := 1 << 2    # the player's cube body
const L_CAP_2D := 1 << 3    # 2D cut caps
const L_SPR := 1 << 4       # 2D sprites
const L_BODY_M := 1 << 5    # miners' cube bodies
const ALL := 0xFFFFF
const MASK := {
	CUT: ALL & ~(L_CAPS_ISO | L_SPR),  # cube bodies too (no pixel sprites)
	FPS: ALL & ~(L_CAP_2D | L_SPR | L_CAPS_ISO | L_BODY_P),
}

static func ground_wish(yaw: float, mx: float, mz: float) -> Vector3:
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	return right * mx + fwd * mz

func off_cut() -> bool:
	return mode != CUT

func setup(main: Node) -> void:
	m = main
	iso = IsoView.new(m)
	fps = FpsView.new()
	add_child(fps)
	fps.setup(m)
	m.cap.layers = L_CAP_2D
	m.cap_old.layers = L_CAP_2D
	iso.enter_state()
	if m.testing:
		set_mode(CUT)  # tests were written for the 2D view
	else:
		fps.third = true
		set_mode(FPS)  # default: real 3D perspective camera, side-on angle (V: first person, then the 2D cut view)

func set_mode(nm: int) -> void:
	var old := mode
	if old == FPS and nm != FPS:
		fps.leave()
	mode = nm
	VoxelBody.hide_self = null
	m.apply_view_perf(nm == FPS)
	VoxelBody.enabled = true  # bodies and sprites coexist: render layers pick them per camera
	m.cam.cull_mask = MASK[nm] if not (nm == FPS and fps.third) else (ALL & ~(L_CAP_2D | L_SPR | L_CAPS_ISO))  # 3rd person: own body visible
	m._set_param("slice_main", false)
	m._set_param("ao_main", nm != CUT)
	m._set_param("cut_main", nm == CUT)
	m._set_param("jitter", 0.0 if nm == CUT else DMSettings.tordu)  # sommets décalés (roche taillée, pas de grille) : en 3D seulement
	if nm == CUT:
		m._apply_view()
		m.cut_cur = m.cut_goal - 2.0
		m.cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		m.cam.near = 0.05
		m.cam.far = 300.0
		m.cam.size = m.ZOOMS[m.zoom_i]
	else:
		for pm in m.part_mats:
			pm.set_shader_parameter("cut_depth", -1000.0)
		fps.enter()
		_sync_axes()
		m._update_lights()
	m._update_camera(0.0, true)
	for p in [m.player] + m.miners:
		if p.vbody:
			p.vbody.sync(p)

## Every physics frame, whatever the main view: level-cut state (cut, caps) and shared shader state.
func tick(dt: float) -> void:
	_auto_view(dt)
	if free_cam():
		m.hud.toast("CAMÉRA LIBRE : ZQSD déplace la caméra, pas le personnage  (Tab pour revenir)")
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		fps.ldist = 0.0
		fps.cam_drag = false
		fps.press_set = false
	elif not fps.press_set:  # click start: on a block (mining: the drag follows the cursor from block to block) or on nothing (drag turns the camera)
		fps.press_set = true
		fps.press_block = not m.target.is_empty() or m.player.mining
	if mode == FPS and fps.third:
		apply_slice()
	m._set_param("ppos_y", m.player.pos.y + 0.9)
	m._set_param("occl_3d", mode == FPS and fps.third)
	m._set_param("bend_k", 0.0 * [0.0, 0.6, 1.0][m.amb] if mode == FPS and fps.third else 0.0)  # curved horizon (U: ambiance level)
	iso.update_state(dt)
	if mode != CUT:  # keep the 2D cut plane following the player's layer
		m._update_cut()
		m._animate_cut(dt)

# ---- vue automatique : passage étroit -> FPS, retour en 3e personne quand il y a la place
var auto_fps := false  # /vue auto on|off (désactivé par défaut : la molette passe de la 3e personne au FPS)
var _auto_on := false  # le FPS en cours a été mis par l'automatisme
var _narrow_t := 0.0
var _wide_t := 0.0
var _sw_cd := 0.0
const NARROW_MIN := 1.4  # bras libre en dessous de (blocs) : trop étroit
const WIDE_MIN := 3.0  # bras libre au-dessus de (blocs) : assez de place pour revenir (hystérésis avec NARROW_MIN)

func switch_third(on: bool) -> void:
	var yw := fps.yaw
	fps.third = on
	set_mode(FPS)
	fps.yaw = yw  # on garde l'orientation (enter() la réinitialise)
	_sw_cd = 1.5
	_narrow_t = 0.0
	_wide_t = 0.0

func _auto_view(dt: float) -> void:
	_sw_cd -= dt
	if not auto_fps or mode != FPS or fps.free or m.state != "play" or m.input_blocked() or m.player.health <= 0.0:
		_narrow_t = 0.0
		_wide_t = 0.0
		return
	var pivot: Vector3 = m.player.pos + Vector3(0, fps.pivot_h(), 0)
	if fps.third:
		var back: Vector3 = (Basis(Vector3.UP, fps.yaw) * Basis(Vector3.RIGHT, fps.pitch)).z
		var d := fps.arm_clear(pivot, back, fps.arm)
		_narrow_t = _narrow_t + dt if d < minf(fps.arm * 0.4, NARROW_MIN) else 0.0
		if _narrow_t > 0.4 and _sw_cd <= 0.0:  # tolérance : étroit pendant 0,4 s (pas un simple coin de mur)
			switch_third(false)
			_auto_on = true
			m.hud.toast("Passage étroit : vue FPS (retour automatique en 3e personne)")
	elif _auto_on:
		var back2: Vector3 = (Basis(Vector3.UP, fps.yaw) * Basis(Vector3.RIGHT, -0.4)).z
		var need := minf(fps.arm, WIDE_MIN + 1.0)
		var d2 := fps.arm_clear(pivot, back2, need)
		_wide_t = _wide_t + dt if d2 >= minf(WIDE_MIN, need) else 0.0
		if _wide_t > 0.8 and _sw_cd <= 0.0:  # il y a la place depuis 0,8 s : on revient
			switch_third(true)
			_auto_on = false

func label() -> String:
	return "Vue 3e personne" if fps.third else "Vue FPS"  # (2D: main.view_label)


## Keeps main's axis-aligned view vars coherent (minimap, lamp offset, depth readout) in non-cut modes.
func _sync_axes() -> void:
	var ref := fps.yaw
	var rot := Basis(Vector3.UP, roundi(ref / (PI / 2.0)) * PI / 2.0)
	m.view_dir = (rot * Vector3(0, 0, -1)).round()
	m.right = (rot * Vector3(1, 0, 0)).round()
	m.up_s = Vector3.UP
	m.top_view = false
	var ax := Hud._axis(m.view_dir)
	var sg := 1 if m.view_dir[ax] > 0 else -1
	if ax != m.cut_axis or sg != m.cut_sign:  # new 2D plane (for the 2D frame): rebuild the cut
		m.cut_axis = ax
		m.cut_sign = sg
		m.cut_layer = -999
		m._set_param("cut_dir", m.view_dir)

# ---- hooks called from main.gd
func camera(dt: float, instant: bool) -> bool:
	if mode == CUT:
		return false
	fps.camera(dt)
	_sync_axes()
	return true

func wish(mx: float, mz: float) -> Vector3:
	return fps.wish(mx, mz)

func skip(cell: Vector3i) -> bool:
	return slice_on() and iso.skip(cell)

func free_cam() -> bool:
	return mode == FPS and fps.third and fps.free

## Free camera: left click = the character walks there (A* on the voxel grid).
func click_go(screen: Vector2) -> void:
	var r: Dictionary = m.raycast(m.cam.project_ray_origin(screen), m.cam.project_ray_normal(screen), 400)  # no reach limit: go as far as the eye sees
	if r.is_empty():
		return
	var c: Vector3i = r.cell
	var start: Vector3i = m.player.feet_cell()
	var far := 6000  # one-shot search (not per frame): far destinations need many nodes
	var res := Pathfinder.find(m.world, start, Pathfinder.GOAL_CELL, c + Vector3i.UP, false, true, far) if Pathfinder.standable(m.world, c + Vector3i.UP) else Pathfinder.find(m.world, start, Pathfinder.GOAL_REACH, c, false, true, far)
	m.go_path = res.cells
	m.go_stuck = 0.0
	if res.cells.is_empty():
		m.hud.toast("Aucun chemin jusque-là")

## 3rd person: horizontal slice (X) hides everything above a level, like DwarfCorp's Z-level view.
func slice_on() -> bool:
	return mode == FPS and fps.third and iso.cut_mode == 1

func apply_slice() -> void:
	m._set_param("slice_main", slice_on())
	if mode == FPS and fps.third:
		m.cam.cull_mask = (ALL & ~(L_CAP_2D | L_SPR)) if slice_on() else (ALL & ~(L_CAP_2D | L_SPR | L_CAPS_ISO))
	iso.slice_y = (floori(fps.free_pos.y) + 2) if (fps.free and slice_on()) else -1

func pick(screen: Vector2) -> Dictionary:
	return fps.pick(screen)

func after_move() -> void:
	if mode == CUT:
		if m.player.vbody and m.player.has_aim:  # the cube miner turns toward the targeted block
			m.player.vbody.face(Vector3(m.player.aim_vec.x, 0, m.player.aim_vec.z))
		return
	_sync_axes()
	if mode == FPS:
		m.player.facing = 1
		if fps.third and m.player.vbody:  # the character looks where he walks (left = left), else at the aimed block
			var v := Vector3(m.player.vel.x, 0, m.player.vel.z)
			if v.length() > 0.4:
				m.player.vbody.face(v)
			elif m.player.has_aim:
				m.player.vbody.face(Vector3(m.player.aim_vec.x, 0, m.player.aim_vec.z))
		m.lamp.position = m.player.pos + Vector3(0, fps.eye(), 0) + fps.wish(0, 0.5)
		return

## V: 3rd person <-> 2D (original side view, custom sprites).
func cycle_view() -> void:
	if mode == CUT:
		fps.third = true
		set_mode(FPS)
		m.hud.toast("Vue 3e personne : molette = zoom, clic molette + glisser ou A/E = tourner  (V : vue 2D)")
	else:
		set_mode(CUT)
		m.hud.toast("Vue 2D  (V : vue 3e personne)")

func cycle_sel(d: int) -> void:
	m.sel = posmod(m.sel + d, m.hotbar.size())

## Returns true when the event is consumed.
func input(ev: InputEvent) -> bool:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_V:
			cycle_view()
			return true
		if mode == FPS and fps.third and ev.keycode == KEY_TAB:
			fps.free = not fps.free
			fps.free_pos = m.player.pos + Vector3(0, fps.pivot_h(), 0) if not fps.free else fps.focus
			m.hud.toast("Caméra libre : ZQSD déplace, PgUp/PgDn monte/descend, clic gauche = le personnage y va, X = coupe par niveau  (Tab : revenir au personnage)" if fps.free else "Caméra sur le personnage  (Tab : caméra libre)")
			return true
		if mode == FPS and fps.third and fps.free and (ev.keycode == KEY_PAGEUP or ev.keycode == KEY_PAGEDOWN):
			fps.free_pos.y = clampf(fps.free_pos.y + (1.0 if ev.keycode == KEY_PAGEUP else -1.0), 1.0, World.SY - 1.0)
			return true
		if mode == FPS and fps.third and ev.keycode == KEY_X:
			iso.cut_mode = 0 if iso.cut_mode == 1 else 1
			iso.caps_dirty = true
			m.hud.toast("Coupe par niveau : " + ("active (monte/descends avec PgUp/PgDn en caméra libre)" if iso.cut_mode == 1 else "désactivée") + "  (X)")
			return true
		if mode == FPS and fps.third and (ev.keycode == KEY_PAGEUP or ev.keycode == KEY_PAGEDOWN):
			fps.arm = clampf(fps.arm + (0.6 if ev.keycode == KEY_PAGEDOWN else -0.6), 1.5, 14.0)
			m.hud.toast("Distance caméra : %.1f  (PgUp/PgDn)" % fps.arm)
			return true
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and free_cam():
		click_go(ev.position)
		return true
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and mode == FPS and fps.third:
		if ev.pressed:
			fps.rdrag = true
			fps.rdist = 0.0
		else:
			fps.rdrag = false
			if fps.rdist < 5.0:  # a short click still uses the item
				m.use_item()
		return true
	elif ev is InputEventMouseButton and ev.pressed:
		var up: bool = ev.button_index == MOUSE_BUTTON_WHEEL_UP
		if up or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mode == FPS and fps.third and not ev.ctrl_pressed:  # DwarfCorp style: the wheel zooms the orbit camera
				if up and fps.arm <= 1.55 and not fps.free:  # tout contre le personnage : un cran de plus = vue FPS
					switch_third(false)
					m.hud.toast("Vue FPS  (molette arrière : retour en 3e personne)")
					return true
				fps.arm = clampf(fps.arm + (-0.7 if up else 0.7), 1.5, 14.0)
				return true
			if mode == FPS and not fps.third and not ev.ctrl_pressed:  # FPS : molette arrière = la caméra recule en 3e personne
				if not up:
					fps.arm = 1.5
					switch_third(true)
					m.hud.toast("Vue 3e personne  (molette = zoom ; avant au maximum = FPS)")
				return true
			if ev.ctrl_pressed or mode == FPS:
				cycle_sel(-1 if up else 1)
				return true
	elif ev is InputEventMouseMotion and mode == FPS and fps.third and not free_cam() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not fps.rdrag:
		if fps.press_block:  # started on a block: keep mining, move the cursor to the next block without turning
			return false
		fps.ldist += ev.relative.length()  # left-drag from empty space (beyond a few pixels) turns the camera
		if fps.ldist > 8.0:
			fps.cam_drag = true
			fps.look(ev.relative)
			return true
		return false
	elif ev is InputEventMouseMotion and mode == FPS and (not fps.third or fps.rdrag or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)):
		fps.rdist += ev.relative.length()  # 3rd person: middle-drag turns
		fps.look(ev.relative)
		return true
	return false
