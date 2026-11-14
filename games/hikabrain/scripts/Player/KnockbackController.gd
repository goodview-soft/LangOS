class_name KnockbackController
extends Node
## Recul physique : remplace en grande partie la vitesse horizontale + impulsion verticale,
## puis réduit temporairement la friction/le contrôle pour que l'éjection se ressente.

signal knocked(dir: Vector3)

var p: PlayerController
var timer := 0.0

func apply(dir: Vector3, sprint_hit: bool = false, power: float = 1.0) -> void:
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = -p.flat_forward()
	dir = dir.normalized()
	var h := Tuning.kb_horizontal * power * (Tuning.kb_sprint_mult if sprint_hit else 1.0)
	var v := p.velocity
	p.velocity = Vector3(v.x * 0.4 + dir.x * h, Tuning.kb_vertical * power, v.z * 0.4 + dir.z * h)
	timer = Tuning.kb_lock_time
	knocked.emit(dir)

func tick(dt: float) -> void:
	timer = maxf(timer - dt, 0.0)

func active() -> bool:
	return timer > 0.0

func friction_scale() -> float:
	return Tuning.kb_ground_friction_scale if timer > 0.0 else 1.0
