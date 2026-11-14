class_name ScoreManager
extends Node

signal score_changed(team: int, scores: Array)

var scores: Array[int] = [0, 0]

func reset() -> void:
	scores = [0, 0]
	score_changed.emit(-1, scores)

func add_point(team: int) -> void:
	scores[team] += 1
	score_changed.emit(team, scores)

func winner() -> int:
	for t in 2:
		if scores[t] >= Cfg.WIN_SCORE:
			return t
	return -1
