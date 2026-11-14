class_name MainMenu
extends Control

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	var title := Label.new()
	title.text = "HIKABRAIN"
	title.add_theme_font_size_override("font_size", 72)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Premier à %d points · atteins le lit adverse" % Cfg.WIN_SCORE
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var play := Button.new()
	play.text = "Jouer (contre l'IA)"
	play.custom_minimum_size = Vector2(320, 52)
	play.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://games/hikabrain/scenes/game.tscn"))
	box.add_child(play)
	var quit := Button.new()
	quit.text = "Retour à LangOS"
	quit.custom_minimum_size = Vector2(320, 44)
	quit.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://boot.tscn"))
	box.add_child(quit)
	var help := Label.new()
	help.text = "WASD/ZQSD : bouger · Espace : saut · Shift : sprint · Ctrl : s'accroupir · Souris : viser\nClic gauche : épée / miner · Clic droit : poser un bloc (maintenir)\n1 Épée · 2 Pioche · 3 Blocs · Molette : changer · Tab : scores · Échap : pause"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(0.75, 0.8, 0.9)
	box.add_child(help)
	play.grab_focus()
