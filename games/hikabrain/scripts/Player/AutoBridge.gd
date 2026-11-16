class_name AutoBridge
extends RefCounted
## Construction automatique sous les pieds (pont de Hikabrain) : quand le joueur avance ou saute dans le vide,
## un bloc est posé sous lui avec le bloc sélectionné, via ServerAuthority.request_place (même chemin que la pose
## manuelle : stock consommé, cadence, portée, zones interdites, et relais réseau côté client).
## Pas de pose sur le sol plein, ni accroupi, ni si la case est occupée.

const NONE := Vector3i(-1, -1, -1)
const AHEAD := 0.55          # distance (m) devant les pieds où l'on anticipe le vide
var p: PlayerController
var ref_y := -999            # niveau (entier) du dessus du dernier sol plein foulé
var cd := 0.0

func _init(player: PlayerController) -> void:
	p = player

## Case à combler pour cette commande, ou NONE.
func plan(c: InputCmd) -> Vector3i:
	var pos := p.global_position
	if p.is_on_floor():
		ref_y = roundi(pos.y)
	if ref_y < 0 or c.sneak:
		return NONE
	if not (c.move.length() > 0.1 or c.jump_pressed or p.velocity.y > 0.5):
		return NONE   # ni marche ni saut : on ne construit pas
	if pos.y < ref_y - 0.5 or pos.y > ref_y + 1.4:
		return NONE   # trop bas (chute) ou plus haut qu'un saut depuis le bord
	var fwd := p.flat_forward()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var dir := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if dir.length() < 0.5:
		dir = right * c.move.x + fwd * c.move.y
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	for pt in [pos, pos + dir * AHEAD]:
		var cell := Vector3i(floori(pt.x), ref_y - 1, floori(pt.z))
		if not p.blocks.is_solid(cell):
			return cell
	return NONE

## Appelé à chaque tick par CombatController. Retourne vrai si un bloc a été demandé et accepté.
func tick(c: InputCmd, dt: float) -> bool:
	cd = maxf(cd - dt, 0.0)
	var cell := plan(c)
	if cell == NONE or cd > 0.0:
		return false
	if p.inv.selected != Cfg.Slot.BLOCKS or p.inv.block_count <= 0:
		return false
	cd = Tuning.place_cooldown
	if p.authority.request_place(p, cell):
		p.swing_arm()
		return true
	return false
