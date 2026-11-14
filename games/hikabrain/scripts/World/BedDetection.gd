class_name BedDetection
extends Node
## Détecte un joueur qui touche le lit adverse.

signal bed_reached(player: PlayerController, bed_team: int)

var game: GameManager

func _physics_process(_dt: float) -> void:
	if game.match_manager.state != Cfg.State.PLAYING:
		return
	for p in game.team_manager.players:
		if not p.alive:
			continue
		var enemy_team := 1 - p.team
		var bed: Vector3 = Cfg.BEDS[enemy_team]
		var flat := Vector2(p.global_position.x - bed.x, p.global_position.z - bed.z)
		var dy := p.global_position.y - bed.y
		if flat.length() < 1.7 and dy > -0.6 and dy < 2.2:
			bed_reached.emit(p, enemy_team)
			return
