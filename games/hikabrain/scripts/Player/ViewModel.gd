class_name ViewModel
extends Node3D
## Objet tenu en première personne (épée / pioche / bloc) avec balancement et animation de coup.

var p: PlayerController
var _items: Array[Node3D] = []
var _swing := 0.0
var _t := 0.0
const BASE_POS := Vector3(0.34, -0.3, -0.55)

func _mesh(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func setup(player: PlayerController) -> void:
	p = player
	position = BASE_POS
	var sword := Node3D.new()
	_mesh(sword, Vector3(0.05, 0.05, 0.6), Vector3(0, 0, -0.3), Color(0.85, 0.9, 1.0))
	_mesh(sword, Vector3(0.2, 0.04, 0.05), Vector3(0, 0, -0.01), Color(0.5, 0.4, 0.2))
	_mesh(sword, Vector3(0.04, 0.04, 0.18), Vector3(0, 0, 0.1), Color(0.4, 0.25, 0.12))
	var pick := Node3D.new()
	_mesh(pick, Vector3(0.04, 0.04, 0.55), Vector3(0, 0, -0.2), Color(0.4, 0.25, 0.12))
	_mesh(pick, Vector3(0.36, 0.07, 0.07), Vector3(0, 0, -0.45), Color(0.7, 0.72, 0.78))
	var blk := Node3D.new()
	_mesh(blk, Vector3.ONE * 0.24, Vector3(0, 0, -0.1), Cfg.TEAM_COLORS[p.team])
	_items = [sword, pick, blk]
	for it in _items:
		it.rotation_degrees = Vector3(8, 18, 0)
		add_child(it)
	sword.rotation_degrees = Vector3(38, 22, -12)
	p.inv.slot_selected.connect(_on_slot)
	_on_slot(p.inv.selected)
	p.swung.connect(func() -> void: _swing = 1.0)

func _on_slot(i: int) -> void:
	for k in _items.size():
		_items[k].visible = (k == i)
	_swing = 0.0

func _process(dt: float) -> void:
	_swing = maxf(_swing - dt / 0.28, 0.0)
	var prog := 1.0 - _swing                       # 0 -> 1 pendant le coup
	var active := _swing > 0.0
	var sw := sin(sqrt(prog) * PI) if active else 0.0       # formule du swing Minecraft
	var sw2 := sin(prog * prog * PI) if active else 0.0
	var spd := Vector2(p.velocity.x, p.velocity.z).length()
	_t += dt * spd * 1.5
	var bob := clampf(spd / 6.0, 0.0, 1.0)
	position = BASE_POS + Vector3(sin(_t * 0.5) * 0.012 * bob - 0.3 * sw, absf(sin(_t)) * 0.015 * bob + 0.12 * sin(sqrt(prog) * PI * 2.0) * (1.0 if active else 0.0), -0.2 * sw)
	rotation = Vector3(-0.4 * sw2 - 0.5 * sw, 0.9 * sw, -1.1 * sw2)
