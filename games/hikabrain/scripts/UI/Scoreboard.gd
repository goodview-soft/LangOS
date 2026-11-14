class_name Scoreboard
extends PanelContainer
## Tableau des scores (maintenir Tab).

var game: GameManager
var _label: Label
var _acc := 0.0

func _init() -> void:
	visible = false
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 20)
	add_child(_label)

func _process(dt: float) -> void:
	visible = Input.is_action_pressed("scoreboard")
	_acc += dt
	if visible and _acc > 0.2 and game:
		_acc = 0.0
		var s := "ROUGE %d  -  %d BLEU\n\n" % [game.score_manager.scores[0], game.score_manager.scores[1]]
		for p in game.team_manager.players:
			s += "%-10s %-6s  K %d   D %d\n" % [p.display_name, Cfg.TEAM_NAMES[p.team], p.kills, p.deaths]
		_label.text = s
