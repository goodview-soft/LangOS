class_name BlockDestruction
extends RefCounted
## Côté joueur : progression de minage (pioche) puis demande de destruction à l'autorité.

var p: PlayerController
var cell := Vector3i(-1, -1, -1)
var progress := 0.0

func _init(player: PlayerController) -> void:
	p = player

func hold(dt: float) -> void:
	var t := p.target_block()
	if t.is_empty() or not p.blocks.is_destructible(t["cell"]):
		cancel()
		return
	if t["cell"] != cell:
		cell = t["cell"]
		progress = 0.0
	progress += dt / Tuning.mine_time
	p.mine_progress = clampf(progress, 0.0, 1.0)
	if progress >= 1.0:
		p.authority.request_break(p, cell)
		cancel()
		p.swung.emit()

func cancel() -> void:
	progress = 0.0
	cell = Vector3i(-1, -1, -1)
	p.mine_progress = 0.0
