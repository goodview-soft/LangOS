class_name CameraCtl
extends RefCounted
## Caméra latérale 2.5D : décalages lissés appliqués par main._update_camera (mode CUT).
## Ne modifie jamais player.pos ni le monde : seulement yaw / pitch / zoom / décalage vertical / plan visé.
## B profondeur (pivot de quelques degrés), C grande salle (recul), D puits (anticipation), E construction.

const MAX_YAW := 6.0        # degrés, pivot en profondeur
const MAX_PITCH := 4.0      # degrés, inclinaison en puits
const MAX_VY := 2.5         # unités, anticipation verticale
const MAX_ZOOM := 1.6       # recul max en grande salle
const RAYS := 8
const RAY_LEN := 12

var yaw := 0.0
var pitch := 0.0
var zoom := 1.0
var vy := 0.0
var plane_off := 0   # plan Z regardé/visé relatif au joueur (-2..2), le joueur ne bouge pas
var building := false
var free := 0.0      # espace libre moyen (cases)
var _t := 0.0

static func k(dt: float, rate: float) -> float:
	return 1.0 - exp(-dt * rate)

## Espace libre moyen (cases) autour de c dans le plan (right, up) : 8 rayons bornés.
static func free_space(w: World, c: Vector3, right: Vector3, up: Vector3) -> float:
	if w.get_v(Vector3i(floori(c.x), floori(c.y), floori(c.z))) != World.AIR:
		return 0.0
	var tot := 0
	for i in RAYS:
		var a := TAU * i / RAYS
		var d := right * cos(a) + up * sin(a)
		var n := 0
		while n < RAY_LEN:
			var p := c + d * (n + 1)
			if w.get_v(Vector3i(floori(p.x), floori(p.y), floori(p.z))) != World.AIR:
				break
			n += 1
		tot += n
	return float(tot) / RAYS

func update(dt: float, m: Node, is_building: bool) -> void:
	building = is_building
	if not building:
		pass
	else:
		plane_off = clampi(plane_off, -2, 2)
	if not building and plane_off != 0 and absf(m.player.vel.dot(m.view_dir)) > 0.1:
		plane_off = 0
	var v: Vector3 = m.player.vel
	var dv := v.dot(m.view_dir)
	var tyaw := 0.0 if building else clampf(dv * 3.0, -1.0, 1.0) * MAX_YAW
	yaw = lerpf(yaw, tyaw, k(dt, 2.5))
	var vv := v.y if absf(v.y) > 1.5 else 0.0
	vy = lerpf(vy, clampf(vv * 0.25, -MAX_VY, MAX_VY), k(dt, 3.0))
	pitch = lerpf(pitch, clampf(-vv * 0.4, -MAX_PITCH, MAX_PITCH), k(dt, 2.5))
	_t -= dt
	if _t <= 0.0:
		_t = 0.3
		free = free_space(m.world, m.player.center(), m.right, m.up_s)
	zoom = lerpf(zoom, 1.0 + (MAX_ZOOM - 1.0) * clampf((free - 5.0) / 5.0, 0.0, 1.0), k(dt, 1.5))
