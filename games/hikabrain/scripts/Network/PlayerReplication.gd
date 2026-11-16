class_name PlayerReplication
extends Node
## Briques de réplication : tampon de commandes (prédiction client), snapshots d'état,
## application avec correction douce. Enregistre les commandes du joueur local à chaque tick.

const MAX_CMDS := 128
var _history: Array[Dictionary] = []

func record(p: PlayerController) -> void:
	_history.append({"seq": p.cmd.seq, "pos": p.global_position, "vel": p.velocity, "yaw": p.yaw, "pitch": p.pitch})
	if _history.size() > MAX_CMDS:
		_history.pop_front()

static func make_snapshot(p: PlayerController) -> Dictionary:
	return {"pos": p.global_position, "vel": p.velocity, "yaw": p.yaw, "pitch": p.pitch,
		"hp": p.health.hp, "alive": p.alive, "seq": p.cmd.seq}

## Réconciliation : compare l'état serveur avec l'état prédit au même numéro de séquence.
func reconcile(p: PlayerController, snap: Dictionary, threshold: float = 0.25) -> void:
	var seq: int = snap["seq"]
	for h in _history:
		if h["seq"] == seq:
			var err: float = (h["pos"] as Vector3).distance_to(snap["pos"])
			if err > threshold:
				p.global_position = p.global_position.lerp(p.global_position + (snap["pos"] - h["pos"]), 0.5)
				p.velocity = snap["vel"]
			break

static func apply_snapshot(p: PlayerController, snap: Dictionary, blend: float = 0.3) -> void:
	p.global_position = p.global_position.lerp(snap["pos"], blend)
	p.velocity = snap["vel"]
	p.yaw = lerp_angle(p.yaw, float(snap["yaw"]), blend)
	p.pitch = lerpf(p.pitch, float(snap["pitch"]), blend)

## Entrée de l'historique pour un numéro de séquence ({} si absente).
func find(seq: int) -> Dictionary:
	for h in _history:
		if h["seq"] == seq:
			return h
	return {}

## Décale tout l'historique (après une correction de position) pour que les comparaisons suivantes restent cohérentes.
func shift(delta: Vector3) -> void:
	for h in _history:
		h["pos"] = (h["pos"] as Vector3) + delta

func clear() -> void:
	_history.clear()
