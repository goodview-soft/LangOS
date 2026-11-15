extends Control
## Music : YouTube (yt-dlp, PC) -> MP3 (+ clip optionnel en fond), paroles synchronisées (LRCLIB), karaoké mot par mot,
## traduction ligne par ligne (Ollama local), mots utiles traduits sous le mot, vocabulaire à apprendre, dictionnaire hors ligne.

const MUSIC_DIR := "user://music"
const LIB_PATH := "user://library.json"
const VOCAB_PATH := "user://vocab.json"
const PRINT_TPL := "TRACK\t%(id)s\t%(title)s\t%(artist|NA)s\t%(track|NA)s\t%(uploader|NA)s\t%(duration|0)s"
const UI = preload("res://apps/ui.gd")
const LANGS := [["Español", "spa", "Spanish", "espagnol"], ["English", "eng", "English", "anglais"], ["Français", "fra", "French", "français"],
	["Italiano", "ita", "Italian", "italien"], ["Português", "por", "Portuguese", "portugais"], ["Nederlands", "nld", "Dutch", "néerlandais"], ["日本語", "jpn", "Japanese", "japonais"]]
const ACC := {"à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a", "ç": "c", "è": "e", "é": "e", "ê": "e", "ë": "e",
	"ì": "i", "í": "i", "î": "i", "ï": "i", "ñ": "n", "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o", "ù": "u", "ú": "u", "û": "u", "ü": "u", "ý": "y", "ÿ": "y"}
## Mots trop courants pour mériter une traduction affichée (espagnol, italien, portugais, anglais, néerlandais).
const STOP := ["el", "la", "los", "las", "un", "una", "unos", "unas", "de", "del", "al", "a", "en", "y", "e", "o", "u", "que", "no", "yo", "tu", "tú", "mi", "me", "te", "se",
	"lo", "le", "les", "nos", "es", "soy", "eres", "son", "era", "fue", "ser", "estar", "esta", "está", "estoy", "más", "mas", "muy", "ya", "si", "sí", "con", "por", "para", "pa", "pa'",
	"sin", "como", "cuando", "qué", "que", "mis", "tus", "su", "sus", "y", "ni", "pero", "hay", "ha", "he", "han", "il", "lo", "di", "da", "per", "il", "the", "a", "an", "to", "of", "and", "i", "you", "it", "is", "in", "on", "my", "me"]
const SCHEMA := {"type": "object", "properties": {"lines": {"type": "array", "items": {"type": "object", "properties": {
	"tr": {"type": "string"},
	"words": {"type": "array", "items": {"type": "object", "properties": {"w": {"type": "string"}, "sens": {"type": "string"}}, "required": ["w", "sens"]}}},
	"required": ["tr", "words"]}}}, "required": ["lines"]}

var ollama_url := "http://127.0.0.1:11434"
var tracks: Array = []
var current := -1
var lines: Array = []
var trans := {}
var vocab := {}
var lyr: Lyrics
var player: AudioStreamPlayer
var vplayer: VideoStreamPlayer
var vwrap: Control
var _paused := false
var _pause_pos := 0.0
var _vsync_t := 0.0
var url_edit: LineEdit
var clip_chk: Button
var status: Label
var list: ItemList
var now_lbl: Label
var kv
var overlay: Window
var ov_kv
var cw: Window
var cw_lbl: Label
var cw_mode := 1          # mot au centre : 0 non, 1 auto, 2 toujours
var cw_menu: MenuButton
var cw_op := 0            # opacité : 0 discret, 1 normal, 2 fort
var cw_size := 1          # taille : 0 petit, 1 moyen, 2 grand
var cw_pos := 0           # 0 centre, 1 plus bas, 2 plus haut
var _cw_tw: Tween
var wk: KaraokeView
var _cw_text := ""
var _cw_sig := -1
var ov_frame: PanelContainer
var ov_pix: TextureRect
var ov_mode := 0          # 0 auto, 1 toujours, 2 non
var ov_opt: OptionButton
var _ov_data_sig := -1
var left: PanelContainer
var stage: PanelContainer
var word_view: RichTextLabel
var star_btn: Button
var vocab_btn: Button
var vocab_panel: PanelContainer
var vocab_list: ItemList
var seek: HSlider
var time_lbl: Label
var play_btn: Button
var off_lbl: Label
var src := "spa"
var tgt := "fra"
var tr_btn: Button
var dl_btn: Button
var _seeking := false
var _threads: Array = []
var _pids: Array = []
var _jobs: Array = []        # conversions ffmpeg en cours : {pid, id, src, dst}
var _lyr_queue: Array = []
var _lyr_busy := false
var _tr_busy := false
var _tr_queue: Array = []
var _tr_warned := false
var _model_cache := ""
var _dicts := {}
var _card := {}              # mot affiché dans la carte : {word, lemma, sens, key}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(MUSIC_DIR)
	lyr = Lyrics.new(); add_child(lyr)
	player = AudioStreamPlayer.new(); add_child(player)
	player.finished.connect(func(): if not _paused: _play(_wrap(current + 1)))
	_load_vocab()
	_build_ui()
	_load_lib()


func _exit_tree() -> void:
	for p in _pids: OS.kill(p)
	for j in _jobs: OS.kill(j["pid"])
	for th in _threads:
		if th.is_started(): th.wait_to_finish()


func _input(ev: InputEvent) -> void:
	# Espace = pause / reprise (sans toucher à la position), sauf pendant la saisie de texte.
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_SPACE and is_visible_in_tree():
		var f := get_viewport().gui_get_focus_owner()
		if f is LineEdit or f is TextEdit: return
		_toggle(); get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- UI

func _ico(n: String) -> Texture2D:
	return load("res://icons/%s.svg" % n)


func _btn(t: String, cb: Callable, variation := "", w := 0) -> Button:
	var b := Button.new(); b.text = t; b.focus_mode = Control.FOCUS_NONE
	if variation != "": b.theme_type_variation = variation
	if w > 0: b.custom_minimum_size.x = w
	b.pressed.connect(cb)
	return b


func _ibtn(icon: String, cb: Callable, w := 44, h := 44, isz := 20) -> Button:
	var b := _btn("", cb, "Flat", w)
	b.custom_minimum_size = Vector2(w, h); b.icon = _ico(icon); b.add_theme_constant_override("icon_max_width", isz)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b


func _panel(c: Color, r := 14, m := 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new(); sb.bg_color = c; sb.set_corner_radius_all(r); sb.set_content_margin_all(m)
	return sb


func _build_ui() -> void:
	var m := MarginContainer.new(); m.set_anchors_preset(PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 12)
	add_child(m)
	var root := VBoxContainer.new(); root.add_theme_constant_override("separation", 10); m.add_child(root)
	var hbar := UI.header_bar("Musique", false); root.add_child(hbar)
	var en := UI.bar_end(hbar)
	url_edit = LineEdit.new(); url_edit.custom_minimum_size = Vector2(100, UI.BTN); url_edit.placeholder_text = "Colle un lien YouTube / YouTube Music (vidéo ou playlist)…"
	url_edit.virtual_keyboard_enabled = false; url_edit.text_submitted.connect(func(_t): _download()); UI.bar_center(hbar, url_edit)
	clip_chk = UI.bar_act(hbar, en, "monitor", "Télécharger avec le clip vidéo", func(): clip_chk.theme_type_variation = "FlatOn" if clip_chk.button_pressed else "Flat")
	clip_chk.toggle_mode = true
	dl_btn = UI.bar_act(hbar, en, "download", "Télécharger", _download)
	status = Label.new(); status.add_theme_font_size_override("font_size", 13)
	status.theme_type_variation = "Muted"; status.clip_text = true; root.add_child(status)
	var hb := HBoxContainer.new(); hb.size_flags_vertical = SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 12); root.add_child(hb)
	# Bibliothèque
	left = PanelContainer.new(); left.custom_minimum_size.x = 220; UI.style(left, "panel", func(): return _panel(UI.p("card"), UI.rad(2), 10)); hb.add_child(left)
	var lv := VBoxContainer.new(); lv.add_theme_constant_override("separation", 8); left.add_child(lv)
	var lt := Label.new(); lt.text = "Bibliothèque"; lt.add_theme_font_size_override("font_size", 18); lv.add_child(lt)
	list = ItemList.new(); list.size_flags_vertical = SIZE_EXPAND_FILL
	list.add_theme_stylebox_override("panel", _panel(Color(0, 0, 0, 0), 0, 0))
	list.item_clicked.connect(func(i, _p, b): if b == MOUSE_BUTTON_LEFT: _list_pick(i)); lv.add_child(list)
	var br := HBoxContainer.new(); br.add_theme_constant_override("separation", 4); lv.add_child(br)
	br.add_child(_btn("Paroles", func(): _fetch_lyrics(current, true)))
	tr_btn = _btn("Retraduire", _retranslate); br.add_child(tr_btn)
	br.add_child(_btn("Clip", _get_clip_selected))
	br.add_child(_ibtn("trash", _delete, 40, 40, 18))
	# Scène : clip (optionnel) + voile + karaoké
	var right := VBoxContainer.new(); right.size_flags_horizontal = SIZE_EXPAND_FILL; right.add_theme_constant_override("separation", 8); hb.add_child(right)
	stage = PanelContainer.new(); stage.size_flags_vertical = SIZE_EXPAND_FILL; stage.clip_contents = true
	stage.add_theme_stylebox_override("panel", _stage_style(0.62)); right.add_child(stage)
	vwrap = Control.new(); vwrap.clip_contents = true; vwrap.mouse_filter = Control.MOUSE_FILTER_IGNORE; vwrap.visible = false; stage.add_child(vwrap)
	vplayer = VideoStreamPlayer.new(); vplayer.expand = true; vplayer.mouse_filter = Control.MOUSE_FILTER_IGNORE; vplayer.volume_db = -80.0; vwrap.add_child(vplayer)
	var shade := ColorRect.new(); shade.color = Color(0, 0, 0, 0.55); shade.mouse_filter = Control.MOUSE_FILTER_IGNORE; shade.set_anchors_preset(PRESET_FULL_RECT); vwrap.add_child(shade)
	var sv := VBoxContainer.new(); sv.add_theme_constant_override("separation", 0); stage.add_child(sv)
	now_lbl = Label.new(); now_lbl.add_theme_font_size_override("font_size", 17); now_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	now_lbl.text = "Ajoute un morceau pour commencer"; now_lbl.clip_text = true; now_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sv.add_child(now_lbl)
	kv = KaraokeView.new(); kv.size_flags_vertical = SIZE_EXPAND_FILL; kv.clip_contents = true
	kv.known = _known_forms()
	kv.word_clicked.connect(_word_clicked); kv.gloss_fn = Callable(self, "_quick_gloss"); kv.seek_requested.connect(func(t0: float): _seek_to(maxf(0.0, t0 - (float(tracks[current].get("offset", 0.0)) if current >= 0 else 0.0))))
	sv.add_child(kv)
	# Vocabulaire (remplace les paroles quand ouvert)
	vocab_panel = PanelContainer.new(); vocab_panel.visible = false; vocab_panel.size_flags_vertical = SIZE_EXPAND_FILL
	vocab_panel.add_theme_stylebox_override("panel", _panel(Color(0.05, 0.06, 0.1, 0.96), 12, 14)); stage.add_child(vocab_panel)
	var vv := VBoxContainer.new(); vv.add_theme_constant_override("separation", 8); vocab_panel.add_child(vv)
	var vh := HBoxContainer.new(); vv.add_child(vh)
	var vt := Label.new(); vt.text = "★ Mes mots à apprendre"; vt.add_theme_font_size_override("font_size", 20); vt.size_flags_horizontal = SIZE_EXPAND_FILL; vh.add_child(vt)
	vh.add_child(_btn("Supprimer", _vocab_delete, "Flat")); vh.add_child(_btn("Fermer", _toggle_vocab, "Flat"))
	vocab_list = ItemList.new(); vocab_list.size_flags_vertical = SIZE_EXPAND_FILL; vv.add_child(vocab_list)
	# Carte mot
	var wp := PanelContainer.new(); wp.custom_minimum_size.y = 128; UI.style(wp, "panel", func(): return _panel(UI.p("card"), UI.rad(), 10)); right.add_child(wp)
	var wh := HBoxContainer.new(); wh.add_theme_constant_override("separation", 10); wp.add_child(wh)
	word_view = RichTextLabel.new(); word_view.bbcode_enabled = true; word_view.selection_enabled = true; word_view.context_menu_enabled = true
	word_view.size_flags_horizontal = SIZE_EXPAND_FILL; word_view.add_theme_font_size_override("normal_font_size", 17)
	word_view.text = "[color=#8f9bb3]Touche un mot : sa traduction s'affiche ici, avec ★ pour le garder. Les mots utiles de la ligne en cours sont traduits sous le mot. Touche une ligne : la musique y saute.[/color]"
	wh.add_child(word_view)
	star_btn = _btn("★ Apprendre", _toggle_star, "Accent", 150); star_btn.visible = false; wh.add_child(star_btn)
	# Transport
	var tbar := PanelContainer.new(); UI.style(tbar, "panel", func(): return _panel(UI.p("card"), UI.rad(2), 8)); root.add_child(tbar)
	var tp := UI.toolbar(); tbar.add_child(tp)
	tp.add_child(_ibtn("prev", func(): _play(_wrap(current - 1)), 44, 44, 20))
	play_btn = _btn("", _toggle); play_btn.custom_minimum_size = Vector2(56, 56)
	for st in ["normal", "hover", "pressed"]:
		UI.style(play_btn, st, func(): var ps := StyleBoxFlat.new(); ps.bg_color = UI.accent() if st != "hover" else UI.accent().lightened(0.2); ps.set_corner_radius_all(28); return ps)
	play_btn.icon = _ico("play"); play_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER; play_btn.add_theme_constant_override("icon_max_width", 24)
	UI.on_theme(play_btn, func(): for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]: play_btn.add_theme_color_override(c, UI.on(UI.accent())))
	tp.add_child(play_btn)
	tp.add_child(_ibtn("next", func(): _play(_wrap(current + 1)), 44, 44, 20))
	time_lbl = Label.new(); time_lbl.text = "0:00 / 0:00"; time_lbl.custom_minimum_size.x = 96; tp.add_child(time_lbl)
	seek = HSlider.new(); seek.custom_minimum_size = Vector2(180, UI.TOUCH); seek.size_flags_horizontal = SIZE_EXPAND_FILL; seek.size_flags_vertical = SIZE_SHRINK_CENTER
	seek.focus_mode = Control.FOCUS_NONE; seek.step = 0.1
	seek.drag_started.connect(func(): _seeking = true)
	seek.drag_ended.connect(func(_c): _seeking = false; _seek_to(seek.value))
	tp.add_child(seek)
	var trb := CheckButton.new(); trb.text = "Traduction"; trb.button_pressed = true; trb.focus_mode = Control.FOCUS_NONE
	trb.toggled.connect(func(on: bool): kv.show_tr = on; kv.queue_redraw()); tp.add_child(trb)
	vocab_btn = UI.icon_btn("star", "Mes mots à apprendre", _toggle_vocab); tp.add_child(vocab_btn); _update_vocab_btn()
	tp.add_child(UI.icon_btn("panel-left", "Afficher ou masquer la bibliothèque", func(): left.visible = not left.visible))
	if _overlay_ok():
		ov_opt = OptionButton.new(); ov_opt.focus_mode = Control.FOCUS_NONE
		for it in ["Overlay : auto", "Overlay : toujours", "Overlay : non"]: ov_opt.add_item(it)
		ov_opt.tooltip_text = "Paroles flottantes en bas de l'écran. Auto : quand LangOS n'est pas au premier plan ou que Music est réduit."
		var c := ConfigFile.new(); c.load("user://music.cfg"); ov_mode = int(c.get_value("ui", "overlay", 0))
		ov_opt.select(ov_mode); ov_opt.item_selected.connect(func(i: int): ov_mode = i; var c2 := ConfigFile.new(); c2.load("user://music.cfg"); c2.set_value("ui", "overlay", i); c2.save("user://music.cfg"))
		tp.add_child(ov_opt)
		cw_mode = int(c.get_value("ui", "center", 1)); cw_op = int(c.get_value("ui", "c_op", 0)); cw_size = int(c.get_value("ui", "c_size", 1)); cw_pos = int(c.get_value("ui", "c_pos", 0))
		cw_menu = MenuButton.new(); cw_menu.icon = UI.icon("type"); cw_menu.custom_minimum_size = Vector2(UI.BTN, UI.BTN); cw_menu.focus_mode = Control.FOCUS_NONE; cw_menu.flat = false
		cw_menu.tooltip_text = "Affiche le mot chanté, seul, au centre de l'écran (par-dessus un jeu)."
		var pm := cw_menu.get_popup()
		pm.add_separator("Affichage")
		for i in 3: pm.add_radio_check_item(["Non", "Auto (LangOS en arrière-plan)", "Toujours"][i], i)
		pm.add_separator("Opacité")
		for i in 3: pm.add_radio_check_item(["Discret", "Normal", "Fort"][i], 10 + i)
		pm.add_separator("Taille")
		for i in 3: pm.add_radio_check_item(["Petit", "Moyen", "Grand"][i], 20 + i)
		pm.add_separator("Position")
		for i in 3: pm.add_radio_check_item(["Centre exact", "Un peu plus bas", "Un peu plus haut"][i], 30 + i)
		pm.id_pressed.connect(_cw_menu_pick); _cw_menu_sync()
		tp.add_child(cw_menu)
		_build_overlay(); _build_center()
	tp.add_child(UI.icon_btn("minus", "Retarder les paroles", func(): _nudge(-0.5)))
	off_lbl = Label.new(); off_lbl.text = "sync 0.0 s"; off_lbl.custom_minimum_size.x = 76; tp.add_child(off_lbl)
	tp.add_child(UI.icon_btn("plus", "Avancer les paroles", func(): _nudge(0.5)))
	if OS.has_feature("android"):
		dl_btn.disabled = true; clip_chk.disabled = true
		status.text = "Le téléchargement YouTube (yt-dlp) n'est disponible que sur PC."


# ---------------------------------------------------------------- Overlay (paroles flottantes, bas de l'écran)

func _overlay_ok() -> bool:
	return not OS.has_feature("mobile") and DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS)


func _build_overlay() -> void:
	overlay = Window.new()
	overlay.visible = false              # doit être caché avant de changer force_native
	overlay.force_native = true          # vraie fenêtre système, même si LangOS intègre ses sous-fenêtres
	overlay.title = "LangOS paroles"
	overlay.borderless = true; overlay.transparent = true; overlay.transparent_bg = true
	overlay.always_on_top = true; overlay.unfocusable = true; overlay.unresizable = true
	overlay.mouse_passthrough = true     # les clics traversent (jeu en dessous)
	overlay.size = Vector2i(1000, 240)
	ov_kv = KaraokeView.new(); ov_kv.compact = true; ov_kv.redraw_hz = 24.0; ov_kv.clip_contents = true; ov_kv.gloss_fn = Callable(self, "_quick_gloss"); ov_kv.set_anchors_preset(PRESET_FULL_RECT); ov_kv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(ov_kv)
	# Petit cadre discret : le clip en pixel art (pixellisé + peu de couleurs)
	ov_frame = PanelContainer.new(); ov_frame.visible = false; ov_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := StyleBoxFlat.new(); fs.bg_color = Color(0, 0, 0, 0.85); fs.set_border_width_all(2); fs.border_color = Color(1, 1, 1, 0.55)
	fs.set_content_margin_all(2); ov_frame.add_theme_stylebox_override("panel", fs)
	ov_frame.position = Vector2(14, 90); ov_frame.modulate = Color(1, 1, 1, 0.9)
	ov_pix = TextureRect.new(); ov_pix.custom_minimum_size = Vector2(112, 63); ov_pix.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ov_pix.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; ov_pix.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ov_pix.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform vec2 res = vec2(56.0, 32.0);\nuniform float levels = 5.0;\nvoid fragment() {\n\tvec2 uv = (floor(UV * res) + 0.5) / res;\n\tvec4 c = texture(TEXTURE, uv);\n\tc.rgb = floor(c.rgb * levels + 0.5) / levels;\n\tCOLOR = vec4(c.rgb, 1.0);\n}\n"
	var mat := ShaderMaterial.new(); mat.shader = sh; ov_pix.material = mat
	ov_frame.add_child(ov_pix); overlay.add_child(ov_frame)
	add_child(overlay)


func _is_behind() -> bool:
	return not is_visible_in_tree() or not DisplayServer.window_is_focused() or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED


func _update_overlay() -> void:
	if overlay == null: return
	var behind: bool = _is_behind()
	var want: bool = ov_mode != 2 and player.playing and not lines.is_empty() and (ov_mode == 1 or behind)
	if want:
		var sig := lines.size() * 1000 + trans.size()
		if sig != _ov_data_sig: _ov_data_sig = sig; ov_kv.set_data(lines, trans)
		ov_kv.set_time(_pos() + float(tracks[current].get("offset", 0.0)))
		want = ov_kv.idx >= 0
		# cadre pixel art : seulement si un clip est chargé
		var tex := vplayer.get_video_texture() if vplayer.stream != null else null
		var show_pix: bool = tex != null and vplayer.is_playing()
		if show_pix: ov_pix.texture = tex
		ov_frame.visible = show_pix
		ov_frame.position = Vector2(14, (overlay.size.y - ov_frame.size.y) / 2.0)
		ov_kv.offset_left = 150.0 if show_pix else 0.0
	if want and not overlay.visible:
		var r := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		var w := mini(1100, r.size.x - 80)
		overlay.size = Vector2i(w, 240)
		overlay.position = Vector2i(r.position.x + (r.size.x - w) / 2, r.position.y + r.size.y - 240 - 6)
	if overlay.visible != want: overlay.visible = want


# ---------------------------------------------------------------- Mot au centre de l'écran (un seul mot, en temps réel)

func _build_center() -> void:
	wk = KaraokeView.new()      # sert seulement à calculer le mot courant (pas affiché)
	cw = Window.new()
	cw.visible = false
	cw.force_native = true
	cw.title = "LangOS mot"
	cw.borderless = true; cw.transparent = true; cw.transparent_bg = true
	cw.always_on_top = true; cw.unfocusable = true; cw.unresizable = true
	cw.mouse_passthrough = true
	cw.size = Vector2i(1000, 220)
	var root := Control.new(); root.set_anchors_preset(PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE; cw.add_child(root)
	cw_lbl = Label.new(); cw_lbl.set_anchors_preset(PRESET_FULL_RECT)
	cw_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; cw_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cw_lbl.add_theme_font_size_override("font_size", 104)
	cw_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	cw_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	cw_lbl.add_theme_constant_override("outline_size", 16)
	cw_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cw_lbl)
	add_child(cw)


func _cw_menu_sync() -> void:
	var pm := cw_menu.get_popup()
	for i in pm.item_count:
		var id := pm.get_item_id(i)
		if pm.is_item_separator(i): continue
		var on: bool = (id < 10 and id == cw_mode) or (id >= 10 and id < 20 and id - 10 == cw_op) or (id >= 20 and id < 30 and id - 20 == cw_size) or (id >= 30 and id - 30 == cw_pos)
		pm.set_item_checked(i, on)


func _cw_menu_pick(id: int) -> void:
	if id < 10: cw_mode = id
	elif id < 20: cw_op = id - 10
	elif id < 30: cw_size = id - 20
	else: cw_pos = id - 30
	_cw_menu_sync()
	var c := ConfigFile.new(); c.load("user://music.cfg")
	c.set_value("ui", "center", cw_mode); c.set_value("ui", "c_op", cw_op); c.set_value("ui", "c_size", cw_size); c.set_value("ui", "c_pos", cw_pos); c.save("user://music.cfg")
	_cw_text = ""; cw.visible = false   # reposition + restyle au prochain mot


func _update_center() -> void:
	if cw == null: return
	var want: bool = cw_mode != 0 and player.playing and not lines.is_empty() and (cw_mode == 2 or _is_behind())
	var txt := ""
	if want:
		var sig := lines.size() * 1000 + trans.size()
		if sig != _cw_sig: _cw_sig = sig; wk.set_data(lines, trans)
		wk.set_time(_pos() + float(tracks[current].get("offset", 0.0)))
		txt = wk.current_word_text()
		want = txt != ""
	if want and not cw.visible:
		var screen := DisplayServer.get_screen_from_rect(Rect2i(DisplayServer.mouse_get_position(), Vector2i(1, 1)))
		var r := DisplayServer.screen_get_position(screen)
		var sz := DisplayServer.screen_get_size(screen)
		var dy: int = [0, int(sz.y * 0.14), -int(sz.y * 0.14)][cw_pos]
		cw.position = Vector2i(r.x + (sz.x - cw.size.x) / 2, r.y + (sz.y - cw.size.y) / 2 + dy)
	if cw.visible != want: cw.visible = want
	if want and txt != _cw_text:
		_cw_text = txt; cw_lbl.text = txt
		var base: int = [64, 92, 124][cw_size]
		var fs: int = base if txt.length() <= 9 else (int(base * 0.8) if txt.length() <= 13 else int(base * 0.62))
		cw_lbl.add_theme_font_size_override("font_size", fs)
		cw_lbl.add_theme_constant_override("outline_size", int(fs * 0.12))
		# Effet : le mot apparaît net puis s'estompe vite (peu gênant), jusqu'au mot suivant
		var peak: float = [0.5, 0.78, 1.0][cw_op]
		if _cw_tw and _cw_tw.is_valid(): _cw_tw.kill()
		cw_lbl.modulate.a = 0.0
		_cw_tw = create_tween()
		_cw_tw.tween_property(cw_lbl, "modulate:a", peak, 0.05)
		_cw_tw.tween_property(cw_lbl, "modulate:a", peak * 0.38, 0.45).set_ease(Tween.EASE_OUT)


func _stage_style(hue: float) -> StyleBoxTexture:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color.from_hsv(hue, 0.55, 0.26), Color.from_hsv(fposmod(hue + 0.07, 1.0), 0.6, 0.12), Color.from_hsv(fposmod(hue + 0.12, 1.0), 0.5, 0.07)])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var tx := GradientTexture2D.new(); tx.gradient = g; tx.fill_from = Vector2(0.2, 0); tx.fill_to = Vector2(0.8, 1); tx.width = 256; tx.height = 256
	var st := StyleBoxTexture.new(); st.texture = tx
	st.set_content_margin_all(12)
	return st


func _lyric_hue(t: Dictionary) -> float:
	return float(abs(hash(str(t.get("id", "")))) % 1000) / 1000.0


func _name(code: String, i: int) -> String:
	for l in LANGS:
		if l[1] == code: return l[i]
	return code


## Appelé par LangOS quand les langues des Paramètres changent.
func set_langs(s: String, t: String) -> void:
	src = s; tgt = t
	kv.known = _known_forms(); kv._fb.clear()
	if ov_kv: ov_kv._fb.clear()
	if current >= 0: _load_lines(); _auto_translate(current)
	_ov_data_sig = -1


# ---------------------------------------------------------------- Lecture (pause fiable)

func _wrap(i: int) -> int:
	return posmod(i, tracks.size()) if tracks.size() > 0 else -1


func _list_pick(i: int) -> void:
	if i == current and player.stream != null: _toggle()
	else: _play(i)


func _play(i: int) -> void:
	if i < 0 or i >= tracks.size(): return
	var t: Dictionary = tracks[i]
	var s := AudioStreamMP3.load_from_file(ProjectSettings.globalize_path(t.file))
	if s == null:
		status.text = "Fichier illisible : " + t.file; return
	current = i; _paused = false; _pause_pos = 0.0
	list.select(i)
	player.stream = s; player.play()
	seek.max_value = s.get_length()
	now_lbl.text = "%s — %s" % [t.artist, t.track]
	stage.add_theme_stylebox_override("panel", _stage_style(_lyric_hue(t)))
	_load_video(t)
	_load_lines()
	if lines.is_empty(): _fetch_lyrics(i, false)
	else: _auto_translate(i)


func _raw_pos() -> float:
	return maxf(0.0, player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())


func _pos() -> float:
	if _paused: return _pause_pos
	if not player.playing: return seek.value
	return _raw_pos()


func _toggle() -> void:
	if player.stream == null:
		_play(0 if current < 0 else current); return
	if player.playing:
		_pause_pos = _raw_pos(); player.stop(); _paused = true
		if vplayer.is_playing(): vplayer.paused = true
	elif _paused:
		player.play(_pause_pos); _paused = false
		vplayer.paused = false
		_render_card()
	else:
		player.play(0.0)   # morceau terminé : on repart du début
		_vseek(0.0)


func _seek_to(t: float) -> void:
	if player.stream == null: return
	t = clampf(t, 0.0, maxf(0.0, seek.max_value - 0.05))
	if _paused: _pause_pos = t
	elif player.playing: player.seek(t)
	else: player.play(t)
	seek.value = t
	_vseek(t)


func _fmt(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


func _nudge(d: float) -> void:
	if current < 0: return
	tracks[current]["offset"] = snappedf(float(tracks[current].get("offset", 0.0)) + d, 0.1)
	_save_lib(false); _update_off()


func _update_off() -> void:
	off_lbl.text = "sync %+.1f s" % float(tracks[current].get("offset", 0.0)) if current >= 0 else "sync 0.0 s"


func _process(d: float) -> void:
	_poll_jobs()
	_update_overlay()
	_update_center()
	if not is_visible_in_tree(): return
	play_btn.icon = _ico("pause" if player.playing else "play")
	if vwrap.visible: _cover_video()
	if player.stream == null: return
	var p := _pos()
	if not _seeking: seek.value = p
	time_lbl.text = "%s / %s" % [_fmt(p), _fmt(seek.max_value)]
	kv.set_time(p + float(tracks[current].get("offset", 0.0)))
	# Clip : recalage si dérive
	if vplayer.stream != null and vplayer.is_playing() and not _paused:
		_vsync_t -= d
		if _vsync_t <= 0.0:
			_vsync_t = 1.0
			if absf(vplayer.stream_position - p) > 0.4: vplayer.stream_position = p


# ---------------------------------------------------------------- Clip en fond (Theora)

func _load_video(t: Dictionary) -> void:
	vplayer.stop(); vplayer.stream = null; vwrap.visible = false
	var v: String = t.get("video", "")
	if v == "" or not FileAccess.file_exists(v): return
	var s := VideoStreamTheora.new(); s.file = v
	vplayer.stream = s; vplayer.play()
	vwrap.visible = true


func _vseek(t: float) -> void:
	if vplayer.stream != null: vplayer.stream_position = t


## Remplit la scène en gardant le rapport d'aspect (recadrage centré).
func _cover_video() -> void:
	var tex := vplayer.get_video_texture()
	vwrap.set_anchors_preset(PRESET_FULL_RECT)
	if tex == null: return
	var vs := tex.get_size()
	if vs.x <= 0 or vs.y <= 0: return
	var sc := maxf(vwrap.size.x / vs.x, vwrap.size.y / vs.y)
	vplayer.size = vs * sc
	vplayer.position = (vwrap.size - vplayer.size) / 2.0


# ---------------------------------------------------------------- Paroles + traductions

func _clean(w: String) -> String:
	return w.strip_edges().trim_prefix("¡").trim_prefix("¿").lstrip("\"'(").rstrip(".,;:!?\"')…").to_lower()


func _tr_path(t: Dictionary) -> String:
	return MUSIC_DIR.path_join("%s.%s.v3.json" % [t.id, tgt])


## Cache des traductions : {"_c": terminé?, "<ligne>": {tr, words}}. Sans "_c" = ancien format, considéré terminé.
func _read_tr(path: String) -> Dictionary:
	var res := {"lines": {}, "done": false}
	if not FileAccess.file_exists(path): return res
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		res["done"] = bool(d.get("_c", true))
		for k in d:
			if k != "_c": res["lines"][int(k)] = d[k]
	return res


func _write_tr(path: String, entries: Dictionary, done: bool) -> void:
	var o := {"_c": done}
	for k in entries: o[str(k)] = entries[k]
	var f := FileAccess.open(path, FileAccess.WRITE); f.store_string(JSON.stringify(o)); f.close()


func _load_lines() -> void:
	lines = []; trans = {}
	kv.set_data([], {})
	if current < 0: return
	var t: Dictionary = tracks[current]
	_update_off()
	if t.get("lrc", "") != "" and FileAccess.file_exists(t.lrc):
		lines = Lyrics.parse(FileAccess.get_file_as_string(t.lrc))
		trans = _read_tr(_tr_path(t))["lines"]
	kv.known = _known_forms()
	kv.set_data(lines, trans)


func _fetch_lyrics(i: int, manual: bool) -> void:
	if i < 0: return
	var t: Dictionary = tracks[i]
	if t.get("no_lyrics", false) and not manual: return
	status.text = "Recherche des paroles : %s — %s…" % [t.artist, t.track]
	var lrc: String = await lyr.fetch(t.artist, t.track, t.duration)
	if lrc == "":
		t.no_lyrics = true
		status.text = "Aucune parole synchronisée trouvée pour « %s »." % t.track
	else:
		t.erase("no_lyrics")
		t.lrc = MUSIC_DIR.path_join(t.id + ".lrc")
		var f := FileAccess.open(t.lrc, FileAccess.WRITE); f.store_string(lrc); f.close()
		status.text = "Paroles trouvées ✓"
	_save_lib()
	if i == current: _load_lines()
	_auto_translate(i)


func _drain_lyr_queue() -> void:
	_lyr_busy = true
	while not _lyr_queue.is_empty():
		var id: String = _lyr_queue.pop_front()
		for i in tracks.size():
			if tracks[i].id == id:
				await _fetch_lyrics(i, false); break
	_lyr_busy = false


# ---------------------------------------------------------------- Traduction fiable (Ollama local)

func _pick_model() -> String:
	var http := HTTPRequest.new(); http.timeout = 8; add_child(http)
	if http.request(ollama_url + "/api/tags") != OK: http.queue_free(); return ""
	var r = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200: return ""
	var d = JSON.parse_string(r[3].get_string_from_utf8())
	var names := []
	if d is Dictionary: for m in d.get("models", []): names.append(str(m["name"]))
	# llama3.1:8b : rapide et fidèle ; les petits modèles (3-4B) inventent des mots et des numéros.
	for pref in ["qwen3:8b", "llama3.1:8b", "qwen3:14b", "gemma3:4b", "llama3.2:3b"]:
		if pref in names: return pref
	return names[0] if not names.is_empty() else ""


## Traduction automatique : lancée toute seule quand un morceau avec paroles est joué ou quand ses paroles arrivent.
func _auto_translate(i: int) -> void:
	if i < 0 or i >= tracks.size(): return
	var t: Dictionary = tracks[i]
	if t.get("lrc", "") == "" or not FileAccess.file_exists(t.lrc) or _read_tr(_tr_path(t))["done"] or t.id in _tr_queue: return
	if i == current: _tr_queue.push_front(t.id)
	else: _tr_queue.append(t.id)
	if not _tr_busy: _drain_tr_queue()


func _retranslate() -> void:
	if current < 0: status.text = "Ouvre d'abord un morceau avec paroles."; return
	var p := _tr_path(tracks[current])
	if FileAccess.file_exists(p): DirAccess.remove_absolute(p)
	trans = {}; kv.set_data(lines, trans)
	_auto_translate(current)


func _drain_tr_queue() -> void:
	_tr_busy = true; tr_btn.disabled = true
	while not _tr_queue.is_empty():
		var id: String = _tr_queue.pop_front()
		for i in tracks.size():
			if tracks[i].id == id:
				await _translate_track(i); break
	_tr_busy = false; tr_btn.disabled = false


func _is_current(tid: String) -> bool:
	return current >= 0 and current < tracks.size() and tracks[current].id == tid


func _translate_track(i: int) -> void:
	var t: Dictionary = tracks[i]
	var tid: String = t.id
	var path := _tr_path(t)
	var ls: Array = Lyrics.parse(FileAccess.get_file_as_string(t.lrc))
	var model: String = _model_cache if _model_cache != "" else await _pick_model()
	if model == "":
		_tr_queue.clear()
		if not _tr_warned: status.text = "Traduction automatique impossible : Ollama introuvable (Traducteur / Paramètres : serveur)."; _tr_warned = true
		return
	_model_cache = model; _tr_warned = false
	var idxs := []
	for j in ls.size():
		if str(ls[j][1]).strip_edges() != "": idxs.append(j)
	var out: Dictionary = _read_tr(path)["lines"]   # reprise d'une traduction interrompue
	var todo := []
	for j in idxs:
		if not out.has(j): todo.append(j)
	idxs = todo
	var k := 0
	var failed := 0
	while k < idxs.size():
		var group: Array = idxs.slice(k, k + 10)
		var texts := []
		for j in group: texts.append(str(ls[j][1]))
		var res = await _ask(model, texts)
		if res == null or res.size() != texts.size(): res = await _ask(model, texts)
		if res == null or res.size() != texts.size():
			res = []   # repli sûr : ligne par ligne, jamais de décalage
			for tx in texts:
				var one = await _ask(model, [tx])
				res.append(one[0] if one != null and one.size() == 1 else null)
		for n in group.size():
			var r = res[n]
			if r == null or not (r is Dictionary): failed += 1; continue
			var entry := {"tr": str(r.get("tr", "")).strip_edges(), "words": _valid_words(texts[n], r.get("words", []))}
			out[group[n]] = entry
			if _is_current(tid): trans[group[n]] = entry
		k += 10
		_write_tr(path, out, false)
		if _is_current(tid):
			kv.set_data(lines, trans)
			if not _card.is_empty() and trans.has(_card["line"]): _refresh_card_gloss()
			status.text = "Traduction automatique (%s) : %d %%" % [model, int(100.0 * minf(1.0, float(k) / idxs.size()))]
	_write_tr(path, out, true)
	if _is_current(tid): status.text = "Traduction terminée ✓" + ("  (%d ligne(s) non traduite(s))" % failed if failed > 0 else "")


func _refresh_card_gloss() -> void:
	var g := _gloss_for(_card["word"])
	if not g.is_empty():
		_card["gloss"] = str(g.get("sens", "")); _card["lemma"] = str(g.get("lemma", _card["lemma"]))
	_render_card()


## Garde seulement les mots qui sont vraiment dans la ligne, utiles (pas de mots outils) et avec un sens plausible.
func _valid_words(line: String, ws: Array) -> Array:
	var toks := {}
	for tok in line.split(" ", false): toks[_dkey(_clean(tok))] = _clean(tok)
	var out := []
	var seen := {}
	for w in ws:
		if not (w is Dictionary): continue
		var raw := _clean(str(w.get("w", "")))
		var key := _dkey(raw)
		var sens := str(w.get("sens", "")).strip_edges()
		if raw == "" or not toks.has(key) or seen.has(key) or sens == "" or _dkey(sens) == key: continue
		if raw in STOP or sens.length() > 28: continue
		seen[key] = true
		out.append({"w": toks[key], "lemma": str(w.get("lemma", raw)).strip_edges().to_lower(), "sens": sens})
	return out


## Les mots à traduire sont listés explicitement (hors mots-outils) : aucun oubli possible, couverture complète.
func _tokens(text: String) -> Array:
	var toks := []
	for tok in text.split(" ", false):
		var c := _clean(tok)
		if c != "" and not c in STOP and not _dkey(c) in STOP and not c in toks: toks.append(c)
	return toks


func _ask(model: String, texts: Array):
	var n := texts.size()
	var blocks := PackedStringArray()
	for i in n: blocks.append("%d. %s\n   MOTS: %s" % [i + 1, texts[i], ", ".join(PackedStringArray(_tokens(texts[i])))])
	var sn := _name(src, 3); var tn := _name(tgt, 3)
	var prompt := "Tu es traducteur %s→%s pour paroles de chansons (argot compris).\nJe te donne %d ligne(s) numérotée(s), chacune suivie de la liste « MOTS ». Réponds en JSON avec \"lines\" : EXACTEMENT %d élément(s), dans le MÊME ORDRE.\nPour chaque ligne :\n- \"tr\" : traduction naturelle de la ligne entière en %s (le sens de l'argot, pas du mot à mot).\n- \"words\" : UNE entrée pour CHAQUE mot de la liste MOTS (aucun oublié, même ordre) : \"w\" = le mot tel que dans la liste ; \"sens\" = sa traduction en %s dans CE contexte, 1 à 3 mots.\nLignes :\n%s" % [sn, tn, n, n, tn, tn, "\n".join(blocks)]
	var body := {"model": model, "stream": false, "think": false, "keep_alive": "20s", "format": SCHEMA, "options": {"temperature": 0.1},
		"messages": [{"role": "user", "content": prompt}]}
	var http := HTTPRequest.new(); http.timeout = 240; add_child(http)
	if http.request(ollama_url + "/api/chat", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		http.queue_free(); return null
	var r = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200: return null
	var d = JSON.parse_string(r[3].get_string_from_utf8())
	if d == null: return null
	var c = JSON.parse_string(d.get("message", {}).get("content", ""))
	return c.get("lines") if c is Dictionary else null


# ---------------------------------------------------------------- Mots : carte, dictionnaire, vocabulaire

func _dkey(t: String) -> String:
	var o := ""
	for c in t.strip_edges().to_lower(): o += ACC.get(c, c)
	return o


func _dic(pair: String) -> PackedStringArray:
	if not _dicts.has(pair):
		var p := "res://dicts/%s.tsv" % pair
		_dicts[pair] = FileAccess.get_file_as_string(p).split("\n", false) if FileAccess.file_exists(p) else PackedStringArray()
	return _dicts[pair]


func _find(pair: String, word: String) -> String:
	var d := _dic(pair)
	var k := _dkey(word)
	var lo := 0; var hi := d.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if d[mid].get_slice("\t", 0) < k: lo = mid + 1
		else: hi = mid
	var out := PackedStringArray()
	while lo < d.size() and d[lo].get_slice("\t", 0) == k and out.size() < 4:
		out.append(d[lo].get_slice("\t", 2).replace("¶", "  |  ")); lo += 1
	return "  |  ".join(out)


func _first_en(def: String) -> Array:
	var res := []
	for part in def.replace("  |  ", ";").split(";", false):
		var s := part.strip_edges()
		if s.begins_with("("): s = s.substr(s.find(")") + 1).strip_edges()
		s = s.trim_prefix("to ").strip_edges()
		if s != "" and not s in res: res.append(s)
		if res.size() >= 3: break
	return res


func _gloss_for(w: String) -> Dictionary:
	var key := _dkey(w)
	var best := {}
	for k in trans:
		for g in trans[k].get("words", []):
			if _dkey(_clean(str(g.get("w", "")))) == key:
				if k == kv.idx: return g
				best = g
	return best


func _word_clicked(w: String, line: int) -> void:
	# Pause automatique pour avoir le temps de lire (Espace ou ▶ pour reprendre).
	if player.playing: _toggle()
	var g := _gloss_for(w)
	var lemma: String = str(g.get("lemma", w)) if not g.is_empty() else w
	var sens: String = str(g.get("sens", "")) if not g.is_empty() else ""
	var dict_txt := _dict_text(lemma if lemma != "" else w, w)
	_card = {"word": w, "line": line, "lemma": lemma, "sens": sens if sens != "" else (dict_txt.get_slice("  |  ", 0).substr(0, 40)), "dict": dict_txt, "gloss": sens}
	star_btn.visible = true; _update_star()
	_render_card()
	if not trans.has(line) or str(trans[line].get("tr", "")) == "": _ensure_line_tr(line)


func _render_card() -> void:
	if _card.is_empty(): return
	var w: String = _card["word"]
	var k: int = _card["line"]
	var txt := ""
	if k >= 0 and k < lines.size():
		var parts := PackedStringArray()
		for tok in str(lines[k][1]).split(" ", false):
			var e: String = tok.replace("[", "[lb]")
			parts.append("[color=#ffd040][b]%s[/b][/color]" % e if _clean(tok) == w else e)
		txt += " ".join(parts) + "\n"
		var tl: String = str(trans.get(k, {}).get("tr", ""))
		if tl != "": txt += "[color=#6fcf97]%s[/color]\n" % tl.replace("[", "[lb]")
		else: txt += "[color=#8f9bb3]traduction de la phrase…[/color]\n"
	txt += "[b][font_size=22]%s[/font_size][/b]" % w.replace("[", "[lb]")
	if _card["lemma"] != "" and _dkey(_card["lemma"]) != _dkey(w): txt += "  [color=#8f9bb3]← %s[/color]" % str(_card["lemma"]).replace("[", "[lb]")
	if _card["gloss"] != "": txt += "   [color=#7dd3fc][b]%s[/b][/color]" % str(_card["gloss"]).replace("[", "[lb]")
	if _card["dict"] != "": txt += "\n[color=#8f9bb3]Dictionnaire :[/color] %s" % str(_card["dict"]).replace("[", "[lb]")
	elif _card["gloss"] == "": txt += "\n[color=#8f9bb3]Pas de traduction connue pour ce mot.[/color]"
	txt += "\n[color=#8f9bb3][i]⏸ En pause : Espace ou ▶ pour reprendre.[/i][/color]" if not player.playing else ""
	word_view.text = txt


## Traduit à la demande la phrase cliquée si elle n'a pas encore été traduite.
func _ensure_line_tr(k: int) -> void:
	if k < 0 or k >= lines.size() or _tr_busy: return
	var model := _model_cache
	if model == "": model = await _pick_model()
	if model == "": _render_card(); return
	_model_cache = model
	var res = await _ask(model, [str(lines[k][1])])
	if res != null and res.size() == 1 and res[0] is Dictionary:
		trans[k] = {"tr": str(res[0].get("tr", "")).strip_edges(), "words": _valid_words(str(lines[k][1]), res[0].get("words", []))}
		kv.set_data(lines, trans)
		if current >= 0:
			var p := _tr_path(tracks[current])
			var prev := _read_tr(p)
			var merged: Dictionary = prev["lines"]; merged[k] = trans[k]
			_write_tr(p, merged, prev["done"])
		if not _card.is_empty() and _card["line"] == k:
			var g := _gloss_for(_card["word"])
			if not g.is_empty(): _card["gloss"] = str(g.get("sens", "")); _card["lemma"] = str(g.get("lemma", _card["lemma"]))
			_render_card()


## Traduction courte d'un mot par le dictionnaire hors ligne (mots sans traduction IA). "" si inconnu.
func _quick_gloss(w: String) -> String:
	if src == tgt or w.length() < 3 or w in STOP or _dkey(w) in STOP: return ""
	var t := _dict_text(w, w)
	if t == "": return ""
	var first: String = t.split("  ·  ")[0]
	var r: String = first.get_slice("→", 1).strip_edges() if "→" in first else first
	r = r.split(";")[0].split("  |  ")[0].strip_edges()
	if r.begins_with("("): r = r.substr(r.find(")") + 1).strip_edges()
	return r.substr(0, 22)


func _dict_text(primary: String, alt: String) -> String:
	if src == tgt: return ""
	for cand in [primary, alt]:
		var out := ""
		if src == "eng" or tgt == "eng":
			out = _find("%s-%s" % [src, tgt], cand)
		else:
			var d1 := _find("%s-eng" % src, cand)
			if d1 != "":
				var parts := []
				for e in _first_en(d1):
					var d2 := _find("eng-%s" % tgt, e)
					parts.append("%s → %s" % [e, "; ".join(_first_en(d2))] if d2 != "" else e)
				out = "  ·  ".join(parts)
		if out != "": return out
	return ""


func _vkey(lemma: String) -> String:
	return "%s:%s" % [src, _dkey(lemma)]


func _update_star() -> void:
	if _card.is_empty(): return
	var saved := vocab.has(_vkey(_card["lemma"]))
	star_btn.text = "★ Appris" if saved else "☆ Apprendre"
	star_btn.icon = _ico("star" if saved else "star_o"); star_btn.add_theme_constant_override("icon_max_width", 16)
	star_btn.text = "Dans mes mots" if saved else "Apprendre"


func _toggle_star() -> void:
	if _card.is_empty(): return
	var k := _vkey(_card["lemma"])
	if vocab.has(k): vocab.erase(k)
	else:
		var forms := [_dkey(_clean(_card["word"])), _dkey(_clean(_card["lemma"]))]
		vocab[k] = {"w": _card["word"], "lemma": _card["lemma"], "sens": _card["sens"], "lang": src, "forms": forms,
			"song": tracks[current].track if current >= 0 else "", "ts": Time.get_unix_time_from_system()}
	_save_vocab(); _update_star(); kv.known = _known_forms(); kv.queue_redraw(); _update_vocab_btn(); _fill_vocab()


func _known_forms() -> Dictionary:
	var o := {}
	for k in vocab:
		if vocab[k].get("lang", "") == src:
			for f in vocab[k].get("forms", []): o[f] = true
	return o


func _load_vocab() -> void:
	if FileAccess.file_exists(VOCAB_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(VOCAB_PATH))
		if d is Dictionary: vocab = d


func _save_vocab() -> void:
	var f := FileAccess.open(VOCAB_PATH, FileAccess.WRITE); f.store_string(JSON.stringify(vocab)); f.close()


func _update_vocab_btn() -> void:
	vocab_btn.text = str(vocab.size()); vocab_btn.tooltip_text = "Mes mots à apprendre (%d)" % vocab.size()


func _toggle_vocab() -> void:
	vocab_panel.visible = not vocab_panel.visible
	kv.visible = not vocab_panel.visible
	if vocab_panel.visible: _fill_vocab()


func _fill_vocab() -> void:
	vocab_list.clear()
	var arr := vocab.keys()
	arr.sort_custom(func(a, b): return float(vocab[a].get("ts", 0)) > float(vocab[b].get("ts", 0)))
	for k in arr:
		var v: Dictionary = vocab[k]
		vocab_list.add_item("%s  —  %s      (%s)" % [v.get("lemma", v.get("w", "")), v.get("sens", ""), v.get("song", "")])
		vocab_list.set_item_metadata(vocab_list.item_count - 1, k)


func _vocab_delete() -> void:
	var sel := vocab_list.get_selected_items()
	if sel.is_empty(): return
	vocab.erase(vocab_list.get_item_metadata(sel[0]))
	_save_vocab(); _fill_vocab(); _update_vocab_btn(); kv.known = _known_forms(); kv.queue_redraw(); _update_star()


# ---------------------------------------------------------------- Téléchargement (yt-dlp + ffmpeg, PC)

func _host(cmd: String) -> Array:
	if FileAccess.file_exists("/.flatpak-info"):
		return ["flatpak-spawn", ["--host", "--env=PYTHONUNBUFFERED=1", cmd]]
	for p in [OS.get_environment("HOME") + "/.local/bin/" + cmd, "/usr/local/bin/" + cmd, "/usr/bin/" + cmd]:
		if FileAccess.file_exists(p): return [p, []]
	return [cmd, []]


func _spawn(cmd: String, args: Array, kind: String) -> Dictionary:
	var y := _host(cmd)
	var info := OS.execute_with_pipe(y[0], PackedStringArray(y[1] + args))
	if info.is_empty(): return {}
	_pids.append(info["pid"])
	for key in ["stdio", "stderr"]:
		var th := Thread.new(); th.start(_read_pipe.bind(info[key], kind)); _threads.append(th)
	return info


func _download() -> void:
	var url := url_edit.text.strip_edges()
	if url == "" or OS.has_feature("android"): return
	url_edit.text = ""
	var out := ProjectSettings.globalize_path(MUSIC_DIR)
	var args := ["-x", "--audio-format", "mp3", "--audio-quality", "0", "--ignore-errors", "--progress", "--newline",
		"--no-simulate", "-o", out + "/%(id)s.%(ext)s", "--print", "after_move:" + PRINT_TPL]
	if not "playlist?list=" in url: args.append("--no-playlist")
	args.append(url)
	if _spawn("yt-dlp", args, "clip" if clip_chk.button_pressed else "mp3").is_empty():
		status.text = "Impossible de lancer yt-dlp (installé ? ffmpeg aussi)."; return
	status.text = "Téléchargement…"


func _get_clip_selected() -> void:
	var sel := list.get_selected_items()
	if sel.is_empty() and current >= 0: sel = PackedInt32Array([current])
	if sel.is_empty() or OS.has_feature("android"):
		status.text = "Choisis un morceau de la bibliothèque (téléchargement du clip : PC seulement)."; return
	_clip_job(tracks[sel[0]].id)


## Télécharge le clip en basse définition puis le convertit en Theora (seul format vidéo lu par Godot).
func _clip_job(id: String) -> void:
	var out := ProjectSettings.globalize_path(MUSIC_DIR)
	var args := ["-f", "bv*[height<=360]/bv*[height<=480]/b[height<=480]", "--no-playlist", "--newline",
		"-o", out + "/" + id + ".clip.%(ext)s", "--print", "after_move:CLIP\t" + id + "\t%(filepath)s",
		"https://www.youtube.com/watch?v=" + id]
	if _spawn("yt-dlp", args, "video").is_empty(): status.text = "Impossible de lancer yt-dlp."; return
	status.text = "Téléchargement du clip…"


func _read_pipe(f: FileAccess, kind: String) -> void:
	while f.is_open() and f.get_error() == OK:
		var line := f.get_line()
		if line != "": _on_line.call_deferred(line, kind)


func _on_line(line: String, kind: String) -> void:
	if line.begins_with("TRACK\t"):
		var p := line.split("\t")
		if p.size() < 7: return
		var g := Lyrics.guess(p[2], p[3], p[4], p[5])
		for t in tracks:
			if t.id == p[1]: status.text = "Déjà dans la bibliothèque : " + p[2]; return
		tracks.append({"id": p[1], "title": p[2], "artist": g[0], "track": g[1], "duration": p[6].to_float(),
			"file": MUSIC_DIR.path_join(p[1] + ".mp3"), "lrc": "", "offset": 0.0})
		_save_lib(); status.text = "Ajouté : " + p[2]
		_lyr_queue.append(p[1])
		if not _lyr_busy: _drain_lyr_queue()
		if kind == "clip": _clip_job(p[1])
	elif line.begins_with("CLIP\t"):
		var p2 := line.split("\t")
		if p2.size() >= 3: _convert_clip(p2[1], p2[2])
	elif line.begins_with("[download]") and "%" in line:
		status.text = ("Clip : " if kind == "video" else "") + line
	elif line.begins_with("ERROR"): status.text = line


func _convert_clip(id: String, srcfile: String) -> void:
	var dst := ProjectSettings.globalize_path(MUSIC_DIR) + "/" + id + ".ogv"
	var y := _host("ffmpeg")
	var info := OS.execute_with_pipe(y[0], PackedStringArray(y[1] + ["-y", "-loglevel", "error", "-nostats", "-i", srcfile, "-an",
		"-vf", "scale=-2:360,fps=24", "-c:v", "libtheora", "-q:v", "5", dst]))
	if info.is_empty(): status.text = "ffmpeg introuvable : clip non converti."; return
	_pids.append(info["pid"])
	_jobs.append({"pid": info["pid"], "id": id, "src": srcfile, "dst": dst})
	status.text = "Conversion du clip…"


func _poll_jobs() -> void:
	for j in _jobs.duplicate():
		if OS.is_process_running(j["pid"]): continue
		_jobs.erase(j)
		var ok := FileAccess.file_exists(j["dst"]) and FileAccess.open(j["dst"], FileAccess.READ).get_length() > 10000
		if ok:
			for t in tracks:
				if t.id == j["id"]: t["video"] = MUSIC_DIR.path_join(j["id"] + ".ogv")
			status.text = "Clip prêt ✓ (relance le morceau pour l'avoir en fond)"
			if current >= 0 and tracks[current].id == j["id"]:
				var pos := _pos(); _load_video(tracks[current]); _vseek(pos)
				if _paused: vplayer.paused = true
		else: status.text = "Conversion du clip impossible."
		if FileAccess.file_exists(j["src"]): DirAccess.remove_absolute(j["src"])
		_save_lib()


# ---------------------------------------------------------------- Bibliothèque

func _delete() -> void:
	var sel := Array(list.get_selected_items())
	if sel.is_empty(): return
	var i: int = sel[0]
	var t: Dictionary = tracks[i]
	if i == current:
		player.stop(); player.stream = null; _paused = false; vplayer.stop(); vplayer.stream = null; vwrap.visible = false
		current = -1; lines = []; trans = {}; now_lbl.text = "Aucun morceau"; kv.set_data([], {})
	for f in [t.file, t.get("lrc", ""), _tr_path(t), t.get("video", "")]:
		if f != "" and FileAccess.file_exists(f): DirAccess.remove_absolute(f)
	tracks.remove_at(i)
	if current > i: current -= 1
	_save_lib()


func _refresh_list() -> void:
	list.clear()
	for t in tracks:
		list.add_item("%s%s — %s%s" % ["♪ " if t.get("lrc", "") != "" else "   ", t.artist, t.track, "  • clip" if t.get("video", "") != "" else ""])
	if current >= 0: list.select(current)


func _load_lib() -> void:
	if FileAccess.file_exists(LIB_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(LIB_PATH))
		if d is Array: tracks = d
	_refresh_list()
	if status.text == "": status.text = "%d morceaux. Clique un morceau pour le jouer ; Espace = pause." % tracks.size()


func _save_lib(refresh := true) -> void:
	var f := FileAccess.open(LIB_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(tracks, "\t")); f.close()
	if refresh: _refresh_list()
