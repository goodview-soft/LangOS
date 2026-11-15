extends Control
## Lanceur Android : grille des applications installées (icônes + recherche). Un appui lance l'application.
## Utilise le plugin natif « LangLauncher » (absent sur PC : un message l'indique).

const MUTED := Color("8f9bb3")
var lp: Object
var flow: HFlowContainer
var search: LineEdit
var tiles: Array = []   # [Button, label minuscule]

func _ready() -> void:
	var v := VBoxContainer.new(); v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); v.add_theme_constant_override("separation", 8); add_child(v)
	if not (OS.get_name() == "Android" and Engine.has_singleton("LangLauncher")):
		var l := Label.new(); l.text = "Les applications Android ne sont disponibles que sur Android\n(avec l'APK récente de LangOS)."; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; l.add_theme_color_override("font_color", MUTED); v.add_child(l); return
	lp = Engine.get_singleton("LangLauncher")
	search = LineEdit.new(); search.placeholder_text = "Rechercher une application…"; search.text_changed.connect(_filter); v.add_child(search)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; v.add_child(sc)
	flow = HFlowContainer.new(); flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 6); flow.add_theme_constant_override("v_separation", 6); sc.add_child(flow)
	await get_tree().process_frame
	_load()

func _load() -> void:
	var arr = JSON.parse_string(str(lp.listApps(96)))
	if not (arr is Array): return
	for a in arr:
		var b := Button.new(); b.theme_type_variation = "Flat"; b.focus_mode = Control.FOCUS_NONE; b.custom_minimum_size = Vector2(104, 112)
		var col := VBoxContainer.new(); col.mouse_filter = Control.MOUSE_FILTER_IGNORE; col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER; col.add_theme_constant_override("separation", 4); b.add_child(col)
		var t := TextureRect.new(); t.custom_minimum_size = Vector2(56, 56); t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var img := Image.new()
		if str(a.get("icon", "")) != "" and img.load_png_from_buffer(Marshalls.base64_to_raw(str(a["icon"]))) == OK: t.texture = ImageTexture.create_from_image(img)
		col.add_child(t)
		var l := Label.new(); l.text = str(a["label"]); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.clip_text = true
		l.add_theme_font_size_override("font_size", 13); l.mouse_filter = Control.MOUSE_FILTER_IGNORE; col.add_child(l)
		var pkg := str(a["pkg"])
		b.pressed.connect(func(): lp.launchApp(pkg))
		flow.add_child(b); tiles.append([b, str(a["label"]).to_lower()])

func _filter(q: String) -> void:
	q = q.strip_edges().to_lower()
	for t in tiles: t[0].visible = q == "" or t[1].contains(q)
