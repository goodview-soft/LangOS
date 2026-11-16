class_name CombatController
extends Node
## Traduit les commandes en actions : attaque épée, minage pioche, placement de blocs.
## Toute action est validée par ServerAuthority.

var p: PlayerController
var placement: BlockPlacement
var destruction: BlockDestruction
var bridge: AutoBridge
var _attack_cd := 0.0
var _attack_queue := 0.0
var _place_cd := 0.0

func reset() -> void:
	_attack_cd = 0.0
	_attack_queue = 0.0
	if destruction:
		destruction.cancel()

func tick(c: InputCmd, dt: float) -> void:
	_attack_cd = maxf(_attack_cd - dt, 0.0)
	_attack_queue = maxf(_attack_queue - dt, 0.0)
	_place_cd = maxf(_place_cd - dt, 0.0)
	if c.select_slot >= 0:
		p.inv.select(c.select_slot)
	if c.scroll != 0:
		p.inv.scroll(c.scroll)
	if c.attack_pressed:
		_attack_queue = 0.15
	match p.inv.selected:
		Cfg.Slot.SWORD:
			destruction.cancel()
			if (_attack_queue > 0.0 or c.attack_held) and _attack_cd <= 0.0:
				_attack_queue = 0.0
				_attack_cd = Tuning.attack_cooldown
				p.swing_arm()
				Sfx.play(p.game, "swing", p.global_position, randf_range(0.9, 1.15))
				p.authority.request_attack(p)
		Cfg.Slot.PICKAXE:
			if c.attack_held:
				destruction.hold(dt)
			else:
				destruction.cancel()
		_:
			destruction.cancel()
	if p.inv.selected == Cfg.Slot.BLOCKS and c.use_held and _place_cd <= 0.0:
		_place_cd = Tuning.place_cooldown
		if placement.try_place():
			p.swing_arm()
	if p.auto_bridge and bridge:
		bridge.tick(c, dt)
