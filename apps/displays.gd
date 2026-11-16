extends Control
## Test multi-écrans (Flip : écran de couverture + écran interne en même temps ?). Android seulement, plugin « LangDisplay ».
const UI = preload("res://apps/ui.gd")
var m
var lp: Object
var info: Label
var log_l: RichTextLabel
var _last := ""
var _t0 := 0

func _ready() -> void:
	var v := VBoxContainer.new(); v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); v.add_theme_constant_override("separation", 6); add_child(v)
	if not (OS.get_name() == "Android" and Engine.has_singleton("LangDisplay")):
		var l := Label.new(); l.text = "Test réservé à Android\n(avec l'APK récente de LangOS)."; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; l.theme_type_variation = "Muted"; v.add_child(l); return
	lp = Engine.get_singleton("LangDisplay")
	_t0 = Time.get_ticks_msec()
	info = Label.new(); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(info)
	var fl := HFlowContainer.new(); v.add_child(fl)
	_btn(fl, "Texte sur l'autre écran", func(): _on_other("showOn"))
	_btn(fl, "Fermer", func(): lp.hideOn(); _log("Contenu fermé"))
	_btn(fl, "Lancer LangOS sur l'autre écran", func(): _on_other("launchOn"))
	_btn(fl, "Écran toujours allumé", func(): lp.keepAwake(true); _log("Écran gardé allumé"))
	_btn(fl, "Normal", func(): lp.keepAwake(false); _log("Veille normale"))
	_btn(fl, "Effacer", func(): log_l.clear())
	log_l = RichTextLabel.new(); log_l.scroll_following = true; log_l.size_flags_vertical = Control.SIZE_EXPAND_FILL; log_l.selection_enabled = true; v.add_child(log_l)
	var t := Timer.new(); t.wait_time = 1.0; t.autostart = true; t.timeout.connect(_poll); add_child(t)
	_poll()

func _btn(p: Control, txt: String, f: Callable) -> void:
	var b := Button.new(); b.text = txt; b.custom_minimum_size = Vector2(0, 44); b.focus_mode = Control.FOCUS_NONE; b.pressed.connect(f); p.add_child(b)

func _log(s: String) -> void:
	log_l.append_text("[%5.1f s] %s\n" % [(Time.get_ticks_msec() - _t0) / 1000.0, s])

func _arr() -> Array:
	var a = JSON.parse_string(str(lp.listDisplays()))
	return a if a is Array else []

func _desc(d: Dictionary) -> String:
	return "écran %d « %s » : %s, %dx%d%s%s" % [d["id"], d["name"], d["state"], d["w"], d["h"], " [présentation OK]" if d["presentation"] else "", " (celui de LangOS)" if d["current"] else ""]

## Une ligne par changement d'état : permet de voir si l'autre écran reste allumé quand on ouvre ou ferme le téléphone.
func _poll() -> void:
	var a := _arr()
	var txt := ""
	for d in a: txt += _desc(d) + "\n"
	info.text = txt if txt != "" else "Aucun écran listé."
	if txt != _last:
		_log("Écrans (%d) :\n%s" % [a.size(), txt.strip_edges()]) if _last != "" else _log("Départ — %d écran(s)" % a.size())
		_last = txt

func _on_other(fn: String) -> void:
	var other := -1
	for d in _arr():
		if not d["current"]: other = int(d["id"]); break
	if other < 0: _log("Aucun autre écran visible pour l'appli (replie/ouvre le téléphone puis réessaie)"); return
	var r: String = str(lp.call(fn, other, "Test LangOS\nécran %d" % other, "#1d4ed8")) if fn == "showOn" else str(lp.call(fn, other))
	_log("%s sur écran %d : %s" % [fn, other, r])
