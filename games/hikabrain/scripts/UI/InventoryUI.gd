class_name InventoryUI
extends HBoxContainer
## Barre d'inventaire : 3 emplacements, sélection mise en évidence.

var inv: InventoryController
var _panels: Array[Panel] = []
var _count: Label
const ICONS := ["ÉPÉE", "PIOCHE", "BLOCS"]

func _init() -> void:
	add_theme_constant_override("separation", 8)
	for i in 3:
		var pn := Panel.new()
		pn.custom_minimum_size = Vector2(78, 62)
		var l := Label.new()
		l.text = "%d" % (i + 1)
		l.position = Vector2(5, 2)
		l.modulate = Color(1, 1, 1, 0.6)
		pn.add_child(l)
		var n := Label.new()
		n.text = ICONS[i]
		n.set_anchors_preset(Control.PRESET_CENTER)
		n.position = Vector2(14, 22)
		n.add_theme_font_size_override("font_size", 14)
		pn.add_child(n)
		add_child(pn)
		_panels.append(pn)
	_count = Label.new()
	_count.position = Vector2(46, 40)
	_count.add_theme_font_size_override("font_size", 16)
	_count.add_theme_color_override("font_color", Color(1, 0.95, 0.5))
	_panels[2].add_child(_count)

func bind(i: InventoryController) -> void:
	inv = i
	inv.changed.connect(_refresh)
	inv.slot_selected.connect(func(_s: int) -> void: _refresh())
	_refresh()

func _refresh() -> void:
	_count.text = str(inv.block_count)
	for i in 3:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.45)
		sb.set_corner_radius_all(6)
		var sel := i == inv.selected
		sb.border_color = Color(1, 1, 1, 0.95) if sel else Color(1, 1, 1, 0.15)
		sb.set_border_width_all(3 if sel else 1)
		_panels[i].add_theme_stylebox_override("panel", sb)
