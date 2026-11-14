class_name InputCmd
extends RefCounted
## Commande d'entrée d'un tick (clavier/souris ou IA). Base de la future prédiction réseau.

var seq := 0
var move := Vector2.ZERO        # x : droite, y : avant
var jump_pressed := false
var sprint := false
var sneak := false
var attack_pressed := false
var attack_held := false
var use_held := false
var select_slot := -1
var scroll := 0

func clear() -> void:
	move = Vector2.ZERO
	jump_pressed = false
	sprint = false
	sneak = false
	attack_pressed = false
	attack_held = false
	use_held = false
	select_slot = -1
	scroll = 0
