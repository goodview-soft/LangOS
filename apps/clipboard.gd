extends Node
const UI = preload("res://apps/ui.gd")
## Presse-papiers universel local : historique des 50 derniers textes, épingles, recherche, panneau flottant (Ctrl+Maj+V).
## Surveille DisplayServer.clipboard_get toutes les secondes + copies faites via main._clip_action. Tout reste sur l'appareil (user://clipboard.json).
signal changed
const MAX := 50
static var secret := ""            # dernier mot de passe copié depuis le coffre : jamais enregistré
var m
var items: Array = []               # [{"t": texte, "pin": bool}]  (le plus récent en premier)
var path := "user://clipboard.json"
var persist := true
var skip_pw := true
var last := ""
var own: Array = []                 # champs de recherche de l'interface (jamais cibles du collage)
var panel: PanelContainer
var catcher: Control

func _ready() -> void:
	if m != null: persist = bool(m.set_cfg.get("clip_save", true)); skip_pw = bool(m.set_cfg.get("clip_nopw", true))
	load_items()
	var t := Timer.new(); t.wait_time = 1.0; t.autostart = true; t.timeout.connect(poll); add_child(t)

## Heuristique : un seul mot de 8 à 64 caractères mêlant au moins 3 types (minuscule, majuscule, chiffre, symbole).
static func looks_like_password(s: String) -> bool:
	if s.length() < 8 or s.length() > 64 or s.contains(" ") or s.contains("\n") or s.contains("\t") or s.contains("://"): return false
	var k := 0
	for r in ["[a-z]", "[A-Z]", "[0-9]", "[^a-zA-Z0-9]"]:
		var re := RegEx.create_from_string(r)
		if re.search(s) != null: k += 1
	return k >= 3 or s == secret

func poll() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD): return
	capture()

## Lit le presse-papiers système et l'ajoute s'il a changé.
func capture() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD): return
	var s := DisplayServer.clipboard_get()
	if s != last: last = s; add(s)

## Ajoute un texte ; renvoie false s'il est ignoré (vide, mot de passe probable).
func add(s: String) -> bool:
	if s.strip_edges() == "" or s.length() > 20000: return false
	if s == secret and s != "": return false
	if skip_pw and looks_like_password(s): return false
	var pin := false
	for i in items.size():
		if items[i]["t"] == s: pin = bool(items[i]["pin"]); items.remove_at(i); break
	items.push_front({"t": s, "pin": pin})
	_trim(); save_items(); changed.emit(); return true

func _trim() -> void:
	while items.size() > MAX:
		var k := -1
		for i in range(items.size() - 1, -1, -1):
			if not items[i]["pin"]: k = i; break
		if k < 0: break
		items.remove_at(k)

func toggle_pin(i: int) -> void:
	if i < 0 or i >= items.size(): return
	items[i]["pin"] = not items[i]["pin"]; save_items(); changed.emit()

func remove(i: int) -> void:
	if i >= 0 and i < items.size(): items.remove_at(i); save_items(); changed.emit()

## Vide l'historique (les éléments épinglés restent sauf si all).
func clear(all := false) -> void:
	items = [] if all else items.filter(func(e): return e["pin"])
	save_items(); changed.emit()

func search(q: String) -> Array:
	var r := []
	for i in items.size():
		if q == "" or items[i]["t"].to_lower().contains(q.to_lower()): r.append(i)
	r.sort_custom(func(a, b): return (items[a]["pin"] and not items[b]["pin"]) or (items[a]["pin"] == items[b]["pin"] and a < b))
	return r

func save_items() -> void:
	if not persist:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(items))

func load_items() -> void:
	if not persist or not FileAccess.file_exists(path): return
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	if j is Array:
		items = []
		for e in j: if e is Dictionary and e.has("t"): items.append({"t": str(e["t"]), "pin": bool(e.get("pin", false))})
		_trim()

func set_persist(on: bool) -> void:
	persist = on
	if m != null: m.set_cfg["clip_save"] = on; m._save_settings()
	save_items()

func set_skip_pw(on: bool) -> void:
	skip_pw = on
	if m != null: m.set_cfg["clip_nopw"] = on; m._save_settings()

## Recolle l'élément : le place dans le presse-papiers puis le colle dans le champ actif.
func paste(i: int) -> void:
	if i < 0 or i >= items.size(): return
	var s: String = items[i]["t"]
	last = s; DisplayServer.clipboard_set(s)
	if m != null:
		var f = m.get_viewport().gui_get_focus_owner()
		if (f is TextEdit or f is LineEdit) and not own.has(f): m._clip_action("paste")
		else: m.notify("Presse-papiers", "Copié : " + s.substr(0, 40).replace("\n", " "))

# ------------------------------------------------------------------ interface
func is_open() -> bool: return panel != null and is_instance_valid(panel)

func toggle() -> void:
	if is_open(): close(); return
	catcher = Control.new(); catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: close())
	m.add_child(catcher)
	panel = PanelContainer.new(); panel.add_theme_stylebox_override("panel", m._box(m._p("menu"), m._rad() + 4, m._p("edge"), 1, 28, 14))
	m.add_child(panel)
	var host := Control.new(); host.custom_minimum_size = Vector2(minf(420.0, m.size.x - 40.0), minf(480.0, m.size.y - 120.0)); panel.add_child(host)
	build_ui(host, true)
	panel.size = panel.get_combined_minimum_size()
	panel.position = ((m.size - panel.size) / 2.0).round()
	m.fx.popup_in(panel, true)

func close() -> void:
	if is_instance_valid(panel): panel.queue_free()
	if is_instance_valid(catcher): catcher.queue_free()
	panel = null; catcher = null

## Construit l'interface (fenêtre d'app ou panneau flottant) dans « host ».
func build_ui(host: Control, floating := false) -> void:
	var v := VBoxContainer.new(); v.set_anchors_preset(Control.PRESET_FULL_RECT); v.add_theme_constant_override("separation", 8); host.add_child(v)
	var q := LineEdit.new(); q.placeholder_text = "Rechercher dans l'historique…"; q.clear_button_enabled = true; v.add_child(q); own.append(q)
	host.tree_exiting.connect(func(): own.erase(q))
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; v.add_child(sc)
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; list.add_theme_constant_override("separation", 4); sc.add_child(list)
	var fill := func():
		for c in list.get_children(): c.queue_free()
		var idx := search(q.text)
		if idx.is_empty():
			list.add_child(UI.empty_state("Historique vide" if items.is_empty() else "Aucun résultat"))
		for i in idx:
			var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 4); list.add_child(row)
			var b: Button = m._mk_btn(str(items[i]["t"]).replace("\n", " / ").substr(0, 90), 0, 40)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.alignment = HORIZONTAL_ALIGNMENT_LEFT; b.clip_text = true; b.tooltip_text = "Recoller"
			b.pressed.connect(func(): paste(i); if floating: close())
			row.add_child(b)
			var p: Button = m._mk_btn("Fixé" if items[i]["pin"] else "Fixer", 56, 40); p.pressed.connect(toggle_pin.bind(i))
			if items[i]["pin"]: p.modulate = m.ACCENT.lightened(0.3)
			row.add_child(p)
			var d: Button = UI.icon_btn("x", "Supprimer"); d.pressed.connect(remove.bind(i)); row.add_child(d)
	q.text_changed.connect(func(_t): fill.call())
	changed.connect(fill); host.tree_exiting.connect(func(): if changed.is_connected(fill): changed.disconnect(fill))
	fill.call()
	var o := HFlowContainer.new(); o.add_theme_constant_override("h_separation", 10); v.add_child(o)
	var cl: Button = m._mk_btn("Vider", 0, 40); cl.pressed.connect(func(): clear()); o.add_child(cl)
	var c1 := CheckBox.new(); c1.text = "Enregistrer sur l'appareil"; c1.button_pressed = persist; c1.focus_mode = Control.FOCUS_NONE; c1.toggled.connect(set_persist); o.add_child(c1)
	var c2 := CheckBox.new(); c2.text = "Ignorer les mots de passe"; c2.button_pressed = skip_pw; c2.focus_mode = Control.FOCUS_NONE; c2.toggled.connect(set_skip_pw); o.add_child(c2)
