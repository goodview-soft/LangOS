class_name BlockPlacement
extends RefCounted
## Côté joueur : vise une face et demande le placement à l'autorité.

var p: PlayerController

func _init(player: PlayerController) -> void:
	p = player

func try_place() -> bool:
	var t := p.target_block()
	if t.is_empty():
		return false
	var cell: Vector3i = t["cell"] + t["normal"]
	return p.authority.request_place(p, cell)
