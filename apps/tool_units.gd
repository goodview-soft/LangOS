extends Control
## Convertisseur d'unités hors ligne.

const T := "température"
# catégorie -> {unité: facteur vers l'unité de base}
const CATS := {
	"Longueur": {"mm": 0.001, "cm": 0.01, "m": 1.0, "km": 1000.0, "pouce": 0.0254, "pied": 0.3048, "yard": 0.9144, "mile": 1609.344, "mille marin": 1852.0},
	"Masse": {"mg": 0.000001, "g": 0.001, "kg": 1.0, "tonne": 1000.0, "once": 0.028349523, "livre": 0.45359237},
	"Volume": {"mL": 0.001, "cL": 0.01, "L": 1.0, "m³": 1000.0, "cuill. à café": 0.005, "cuill. à soupe": 0.015, "tasse": 0.25, "gallon US": 3.785411784, "pinte US": 0.473176473},
	"Surface": {"cm²": 0.0001, "m²": 1.0, "ha": 10000.0, "km²": 1000000.0, "pied²": 0.09290304, "acre": 4046.8564224},
	"Vitesse": {"m/s": 1.0, "km/h": 0.2777777778, "mph": 0.44704, "nœud": 0.5144444444},
	"Durée": {"s": 1.0, "min": 60.0, "h": 3600.0, "jour": 86400.0, "semaine": 604800.0},
	"Données": {"octet": 1.0, "Ko": 1000.0, "Mo": 1e6, "Go": 1e9, "To": 1e12, "Kio": 1024.0, "Mio": 1048576.0, "Gio": 1073741824.0},
	"Énergie": {"J": 1.0, "kJ": 1000.0, "cal": 4.184, "kcal": 4184.0, "Wh": 3600.0, "kWh": 3600000.0},
	"Température": {"°C": 1.0, "°F": 1.0, "K": 1.0},
}

static func convert_val(cat: String, v: float, from: String, to: String) -> float:
	if cat == "Température":
		var c := v
		if from == "°F": c = (v - 32.0) * 5.0 / 9.0
		elif from == "K": c = v - 273.15
		if to == "°F": return c * 9.0 / 5.0 + 32.0
		if to == "K": return c + 273.15
		return c
	var u: Dictionary = CATS[cat]
	return v * u[from] / u[to]

var cat_opt: OptionButton
var from_opt: OptionButton
var to_opt: OptionButton
var inp: LineEdit
var out: Label
var all: Label

func _ready() -> void:
	var vb := VBoxContainer.new(); vb.set_anchors_preset(Control.PRESET_FULL_RECT); vb.add_theme_constant_override("separation", 8); add_child(vb)
	cat_opt = OptionButton.new(); cat_opt.custom_minimum_size.y = 48
	for c in CATS: cat_opt.add_item(c)
	cat_opt.item_selected.connect(func(_i): _fill_units()); vb.add_child(cat_opt)
	inp = LineEdit.new(); inp.text = "1"; inp.custom_minimum_size.y = 52; inp.placeholder_text = "Valeur"
	inp.add_theme_font_size_override("font_size", 24); inp.text_changed.connect(func(_t): _calc()); vb.add_child(inp)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6); vb.add_child(row)
	from_opt = OptionButton.new(); to_opt = OptionButton.new()
	for o in [from_opt, to_opt]: o.custom_minimum_size.y = 48; o.size_flags_horizontal = Control.SIZE_EXPAND_FILL; o.item_selected.connect(func(_i): _calc())
	var sw := Button.new(); sw.text = "⇄"; sw.custom_minimum_size = Vector2(48, 48)
	sw.pressed.connect(func():
		var a := from_opt.selected; from_opt.select(to_opt.selected); to_opt.select(a); _calc())
	row.add_child(from_opt); row.add_child(sw); row.add_child(to_opt)
	out = Label.new(); out.add_theme_font_size_override("font_size", 30); out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; vb.add_child(out)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; vb.add_child(sc)
	all = Label.new(); all.size_flags_horizontal = Control.SIZE_EXPAND_FILL; all.add_theme_color_override("font_color", Color("8f9bb3")); sc.add_child(all)
	_fill_units()

func _fill_units() -> void:
	var cat := cat_opt.get_item_text(cat_opt.selected)
	from_opt.clear(); to_opt.clear()
	for u in CATS[cat]: from_opt.add_item(u); to_opt.add_item(u)
	from_opt.select(0); to_opt.select(mini(1, to_opt.item_count - 1))
	if cat == "Longueur": from_opt.select(2); to_opt.select(4)
	_calc()

func _calc() -> void:
	var cat := cat_opt.get_item_text(cat_opt.selected)
	var t := inp.text.replace(",", ".")
	if not t.is_valid_float(): out.text = ""; all.text = ""; return
	var v := t.to_float()
	var fu := from_opt.get_item_text(from_opt.selected); var tu := to_opt.get_item_text(to_opt.selected)
	out.text = "%s %s = %s %s" % [_f(v), fu, _f(convert_val(cat, v, fu, tu)), tu]
	var lines := []
	for u in CATS[cat]: lines.append("%s %s" % [_f(convert_val(cat, v, fu, u)), u])
	all.text = "\n".join(lines)

static func _f(v: float) -> String:
	if v == floor(v) and absf(v) < 1e15: return str(int(v))
	return String.num(v, 8) if absf(v) >= 1e-4 else String.num_scientific(v)
