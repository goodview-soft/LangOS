class_name RemoteInput
extends Node
## Fournisseur d'entrées d'un joueur distant, côté hôte : rejoue en ordre, une par tick, les commandes reçues du client
## (l'hôte simule le joueur avec le même code de mouvement que le client, qui prédit de son côté).

var p: PlayerController
var last_seq := 0           # dernière commande rejouée (renvoyée au client pour la réconciliation)
var _q: Array = []
var _cur := {}

func push(seq: int, mv: Vector2, jump: bool, sprint: bool, sneak: bool, yaw: float, pitch: float) -> void:
	if not (is_finite(mv.x) and is_finite(mv.y) and is_finite(yaw) and is_finite(pitch)):
		return
	_q.append({"seq": seq, "move": mv.limit_length(1.0), "jump": jump, "sprint": sprint, "sneak": sneak, "yaw": yaw, "pitch": clampf(pitch, -1.5, 1.5)})
	while _q.size() > 6:
		_q.pop_front()

func gather(c: InputCmd, _dt: float) -> void:
	c.clear()
	if _q.size() > 3:
		_q = _q.slice(_q.size() - 3)   # rattrapage si le client a de l'avance
	if not _q.is_empty():
		_cur = _q.pop_front()
	elif not _cur.is_empty():
		_cur["jump"] = false          # plus de nouvelle commande : on garde la marche, pas de saut répété
	if _cur.is_empty():
		return
	c.move = _cur["move"]
	c.jump_pressed = _cur["jump"]
	c.sprint = _cur["sprint"]
	c.sneak = _cur["sneak"]
	p.yaw = _cur["yaw"]
	p.pitch = _cur["pitch"]
	last_seq = _cur["seq"]
