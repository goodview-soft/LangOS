extends Control
## Cartes mémoire à répétition espacée (système de Leitner), plusieurs paquets.

const PATH := "user://cards.json"
const DAYS := [0, 1, 2, 4, 8, 16]
var data := {"Vocabulaire": []}      # paquet -> [{f, b, box, due}]
var cur := "Vocabulaire"
var ui: VBoxContainer
var queue: Array = []
var shown := false

static func today() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)

## Cartes à réviser aujourd'hui.
static func due_cards(deck: Array, day: int) -> Array:
	return deck.filter(func(c): return c.due <= day)

## Applique une réponse : réussite = boîte suivante, échec = boîte 0.
static func answer(c: Dictionary, ok: bool, day: int) -> void:
	c.box = mini(c.box + 1, DAYS.size() - 1) if ok else 0
	c.due = day + DAYS[c.box] if ok else day

func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary and not d.is_empty(): data = d
	cur = data.keys()[0]
	ui = VBoxContainer.new(); ui.set_anchors_preset(Control.PRESET_FULL_RECT); ui.add_theme_constant_override("separation", 8); add_child(ui)
	_home()

func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(data))

func _clear() -> void:
	for c in ui.get_children(): c.queue_free()

func _btn(t: String, f: Callable) -> Button:
	var b := Button.new(); b.text = t; b.custom_minimum_size.y = 52; b.pressed.connect(f); return b

func _lbl(t: String, sz := 18) -> Label:
	var l := Label.new(); l.text = t; l.add_theme_font_size_override("font_size", sz); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; return l

func _home() -> void:
	_clear()
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6); ui.add_child(row)
	var opt := OptionButton.new(); opt.custom_minimum_size.y = 48; opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in data: opt.add_item(k); if k == cur: opt.select(opt.item_count - 1)
	opt.item_selected.connect(func(i): cur = opt.get_item_text(i); _home()); row.add_child(opt)
	var nm := LineEdit.new(); nm.placeholder_text = "Nom d'un nouveau paquet"; nm.custom_minimum_size.y = 48; ui.add_child(nm)
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 6); ui.add_child(hb)
	var nb := _btn("Créer le paquet", func():
		var n := nm.text.strip_edges()
		if n != "" and not data.has(n): data[n] = []; cur = n; _save(); _home())
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hb.add_child(nb)
	var db := _btn("Supprimer le paquet", func():
		if data.size() > 1: data.erase(cur); cur = data.keys()[0]; _save(); _home())
	db.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hb.add_child(db)
	var deck: Array = data[cur]
	var due := due_cards(deck, today())
	ui.add_child(_lbl("%d carte(s), %d à réviser aujourd'hui" % [deck.size(), due.size()], 22))
	var st := _btn("Réviser (%d)" % due.size(), func(): _study())
	st.disabled = due.is_empty(); ui.add_child(st)
	ui.add_child(_lbl("Ajouter une carte"))
	var fr := LineEdit.new(); fr.placeholder_text = "Recto (ex. casa)"; fr.custom_minimum_size.y = 48; ui.add_child(fr)
	var bk := LineEdit.new(); bk.placeholder_text = "Verso (ex. maison)"; bk.custom_minimum_size.y = 48; ui.add_child(bk)
	var add := func():
		if fr.text.strip_edges() == "" or bk.text.strip_edges() == "": return
		deck.append({"f": fr.text.strip_edges(), "b": bk.text.strip_edges(), "box": 0, "due": today()}); _save(); _home()
	ui.add_child(_btn("Ajouter la carte", add))
	bk.text_submitted.connect(func(_t): add.call())
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; ui.add_child(sc)
	var box := VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(box)
	for c in deck:
		var r := HBoxContainer.new(); box.add_child(r)
		var l := _lbl("%s  →  %s   [boîte %d]" % [c.f, c.b, c.box], 16); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r.add_child(l)
		var x := Button.new(); x.text = "✕"; x.custom_minimum_size = Vector2(48, 48); x.pressed.connect(func(): deck.erase(c); _save(); _home()); r.add_child(x)

func _study() -> void:
	queue = due_cards(data[cur], today()); queue.shuffle(); shown = false; _card()

func _card() -> void:
	_clear()
	if queue.is_empty():
		ui.add_child(_lbl("Révision terminée, bravo !", 26)); ui.add_child(_btn("Retour", _home)); return
	var c: Dictionary = queue[0]
	ui.add_child(_lbl("%d restante(s)" % queue.size()))
	var f := _lbl(c.f, 40); f.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; f.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; f.size_flags_vertical = Control.SIZE_EXPAND_FILL; ui.add_child(f)
	if not shown:
		ui.add_child(_btn("Afficher la réponse", func(): shown = true; _card()))
	else:
		var b := _lbl(c.b, 32); b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; b.modulate = Color("5aa2ff"); ui.add_child(b)
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); ui.add_child(row)
		var no := _btn("À revoir", func(): _ans(false)); no.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(no)
		var yes := _btn("Je savais", func(): _ans(true)); yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(yes)
	ui.add_child(_btn("Arrêter", _home))

func _ans(ok: bool) -> void:
	var c: Dictionary = queue.pop_front()
	answer(c, ok, today())
	if not ok: queue.append(c)
	_save(); shown = false; _card()
