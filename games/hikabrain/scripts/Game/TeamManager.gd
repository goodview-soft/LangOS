class_name TeamManager
extends Node

var players: Array[PlayerController] = []

func register(p: PlayerController) -> void:
	players.append(p)

func enemy(team: int) -> int:
	return 1 - team

func players_of(team: int) -> Array[PlayerController]:
	var out: Array[PlayerController] = []
	for p in players:
		if p.team == team:
			out.append(p)
	return out
