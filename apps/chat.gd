extends Control
## Application « Chat IA » : même conversation que l'overlay (partagée via ChatCore).

var core: ChatCore
var scroll: ScrollContainer
var box: VBoxContainer
var input: LineEdit
var model_opt: OptionButton
var dl_btn: Button
var status: Label
var send_btn: Button


func _ready() -> void:
	var m := MarginContainer.new(); m.set_anchors_preset(PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 14)
	add_child(m)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); m.add_child(v)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 8); v.add_child(top)
	var ttl := Label.new(); ttl.text = "Assistant IA local"; ttl.add_theme_font_size_override("font_size", 20); ttl.size_flags_horizontal = SIZE_EXPAND_FILL; top.add_child(ttl)
	status = Label.new(); status.add_theme_color_override("font_color", Color("8f9bb3")); top.add_child(status)
	model_opt = OptionButton.new(); model_opt.focus_mode = Control.FOCUS_NONE; model_opt.item_selected.connect(func(i: int): core.set_model(str(core.available[i]))); top.add_child(model_opt)
	var pg := CheckButton.new(); pg.text = "Page web"; pg.focus_mode = Control.FOCUS_NONE; pg.tooltip_text = "Le modèle voit la page du navigateur et peut ouvrir un site"
	pg.button_pressed = core.page_ctx; pg.toggled.connect(func(on: bool): core.page_ctx = on); top.add_child(pg)
	core.changed.connect(func(): pg.set_pressed_no_signal(core.page_ctx))
	dl_btn = Button.new(); dl_btn.text = "Télécharger le modèle (1,1 Go)"; dl_btn.theme_type_variation = "Flat"; dl_btn.focus_mode = Control.FOCUS_NONE
	dl_btn.visible = false; dl_btn.pressed.connect(func(): core.download_device_model()); top.add_child(dl_btn)
	var cw := Button.new(); cw.text = "Claude.ai"; cw.theme_type_variation = "Flat"; cw.focus_mode = Control.FOCUS_NONE
	cw.tooltip_text = "Ouvre claude.ai dans le navigateur intégré : connecte-toi avec ton abonnement, sans clé API"
	cw.pressed.connect(func(): get_tree().current_scene.open_browser("https://claude.ai/")); top.add_child(cw)
	var nb := Button.new(); nb.text = "Nouvelle discussion"; nb.theme_type_variation = "Flat"; nb.focus_mode = Control.FOCUS_NONE; nb.pressed.connect(func(): core.clear()); top.add_child(nb)
	var pc := PanelContainer.new(); pc.size_flags_vertical = SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("171b25"); sb.set_corner_radius_all(12); sb.set_content_margin_all(10); pc.add_theme_stylebox_override("panel", sb); v.add_child(pc)
	scroll = ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; pc.add_child(scroll)
	box = VBoxContainer.new(); box.size_flags_horizontal = SIZE_EXPAND_FILL; box.add_theme_constant_override("separation", 8); scroll.add_child(box)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); v.add_child(row)
	input = LineEdit.new(); input.placeholder_text = "Pose ta question… (astuce : « - » ouvre l'overlay chat par-dessus un jeu)"
	input.size_flags_horizontal = SIZE_EXPAND_FILL; input.virtual_keyboard_enabled = false; input.text_submitted.connect(func(q: String): input.text = ""; core.ask(q)); row.add_child(input)
	send_btn = Button.new(); send_btn.text = "Envoyer"; send_btn.theme_type_variation = "Accent"; send_btn.focus_mode = Control.FOCUS_NONE
	send_btn.pressed.connect(func(): var q := input.text; input.text = ""; core.ask(q)); row.add_child(send_btn)
	core.changed.connect(_rebuild); core.busy_changed.connect(func(on: bool): send_btn.disabled = on; status.text = "réflexion…" if on else "")
	core.refresh_models()
	_rebuild()
	input.grab_focus()


func _rebuild() -> void:
	for c in box.get_children(): c.queue_free()
	var f := get_theme_default_font()
	var w := maxf(300.0, size.x * 0.7)
	for m in core.messages: box.add_child(ChatCore.bubble(m["role"], str(m["content"]), w, 17, f))
	if core.is_busy: box.add_child(ChatCore.bubble("assistant", "…", 120.0, 17, f))
	model_opt.clear()
	for n in core.available: model_opt.add_item(str(ChatCore.LABELS.get(n, n)))
	if not core.is_busy: status.text = core.note
	dl_btn.visible = core.model == ChatCore.DEVICE_MODEL and not core.device_ready() and core._dl == null
	var i := core.available.find(core.model)
	if i >= 0: model_opt.select(i)
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scroll): scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
