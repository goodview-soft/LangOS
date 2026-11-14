class_name PlayerHealth
extends Node
## Vie, invulnérabilité brève après un coup, protection de respawn.

signal changed(hp: float, max_hp: float)
signal damaged(amount: float, source: PlayerController)

var p: PlayerController
var hp := Tuning.max_health
var invuln := 0.0
var protection := 0.0
var _since_hurt := 0.0

func is_protected() -> bool:
	return protection > 0.0

func reset() -> void:
	hp = Tuning.max_health
	invuln = 0.0
	protection = 0.0
	_since_hurt = 0.0
	changed.emit(hp, Tuning.max_health)

func protect(seconds: float) -> void:
	protection = seconds

func take_damage(amount: float, source: PlayerController) -> bool:
	if hp <= 0.0 or protection > 0.0 or invuln > 0.0 or not p.alive:
		return false
	hp = maxf(hp - amount, 0.0)
	invuln = Tuning.hurt_invuln
	_since_hurt = 0.0
	changed.emit(hp, Tuning.max_health)
	damaged.emit(amount, source)
	if hp <= 0.0:
		p.kill("combat")
	return true

func tick(dt: float) -> void:
	invuln = maxf(invuln - dt, 0.0)
	protection = maxf(protection - dt, 0.0)
	_since_hurt += dt
	if hp < Tuning.max_health and hp > 0.0 and _since_hurt > Tuning.regen_delay:
		hp = minf(hp + Tuning.regen_per_sec * dt, Tuning.max_health)
		changed.emit(hp, Tuning.max_health)
