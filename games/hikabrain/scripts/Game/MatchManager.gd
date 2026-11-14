class_name MatchManager
extends Node
## Machine à états : WAITING > COUNTDOWN > PLAYING > POINT_SCORED > ROUND_RESET > ... > MATCH_FINISHED

signal state_changed(new_state: int, old_state: int)
signal countdown_tick(seconds: int)
signal point_scored(team: int, scorer: PlayerController)
signal match_finished(winner: int)

var score: ScoreManager
var state: int = Cfg.State.WAITING
var timer := 0.0
var last_scorer: PlayerController
var _last_tick := -1

func start_match() -> void:
	score.reset()
	_set_state(Cfg.State.WAITING, 1.2)

func _set_state(s: int, t: float = 0.0) -> void:
	var old := state
	state = s
	timer = t
	_last_tick = -1
	state_changed.emit(s, old)

func on_bed_reached(player: PlayerController, _bed_team: int) -> void:
	if state != Cfg.State.PLAYING:
		return
	last_scorer = player
	score.add_point(player.team)
	_set_state(Cfg.State.POINT_SCORED, Tuning.point_banner_time)
	point_scored.emit(player.team, player)

func _process(dt: float) -> void:
	match state:
		Cfg.State.WAITING:
			timer -= dt
			if timer <= 0.0:
				_set_state(Cfg.State.COUNTDOWN, Tuning.countdown_time)
		Cfg.State.COUNTDOWN:
			timer -= dt
			var n := ceili(timer)
			if n != _last_tick and n > 0:
				_last_tick = n
				countdown_tick.emit(n)
			if timer <= 0.0:
				_set_state(Cfg.State.PLAYING)
		Cfg.State.POINT_SCORED:
			timer -= dt
			if timer <= 0.0:
				var w := score.winner()
				if w >= 0:
					_set_state(Cfg.State.MATCH_FINISHED)
					match_finished.emit(w)
				else:
					_set_state(Cfg.State.ROUND_RESET, 0.3)
		Cfg.State.ROUND_RESET:
			timer -= dt
			if timer <= 0.0:
				_set_state(Cfg.State.COUNTDOWN, Tuning.countdown_time)
