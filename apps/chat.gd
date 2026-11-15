extends Control
const UI = preload("res://apps/ui.gd")
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
	var hbar := UI.header_bar("Assistant IA", false); v.add_child(hbar)
	var en := UI.bar_end(hbar)
	status = Label.new(); status.theme_type_variation = "Muted"; en.add_child(status)
	model_opt = OptionButton.new(); model_opt.focus_mode = Control.FOCUS_NONE; model_opt.custom_minimum_size.y = UI.BTN; model_opt.item_selected.connect(func(i: int): core.set_model(str(core.available[i]))); en.add_child(model_opt)
	var pg := UI.bar_act(hbar, en, "globe", "Page web : le modèle voit la page du navigateur et peut ouvrir un site", func(): pass)
	for c in pg.pressed.get_connections(): pg.pressed.disconnect(c["callable"])
	pg.toggle_mode = true; pg.button_pressed = core.page_ctx
	pg.toggled.connect(func(on: bool): core.page_ctx = on; pg.theme_type_variation = "FlatOn" if on else "Flat")
	core.changed.connect(func(): pg.set_pressed_no_signal(core.page_ctx); pg.theme_type_variation = "FlatOn" if core.page_ctx else "Flat")
	dl_btn = UI.bar_act(hbar, en, "download", "Télécharger le modèle", func(): core.download_model())
	dl_btn.visible = false
	UI.bar_act(hbar, en, "plus", "Nouvelle discussion", func(): core.clear())
	var pc := PanelContainer.new(); pc.size_flags_vertical = SIZE_EXPAND_FILL
	UI.style(pc, "panel", func(): return UI.box(UI.p("field"), UI.rad(), Color(0, 0, 0, 0), 0, 10)); v.add_child(pc)
	scroll = ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; pc.add_child(scroll)
	box = VBoxContainer.new(); box.size_flags_horizontal = SIZE_EXPAND_FILL; box.add_theme_constant_override("separation", 8); scroll.add_child(box)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); v.add_child(row)
	input = LineEdit.new(); input.placeholder_text = "Pose ta question… (astuce : « - » ouvre l'overlay chat par-dessus un jeu)"
	input.size_flags_horizontal = SIZE_EXPAND_FILL; input.virtual_keyboard_enabled = false; input.text_submitted.connect(func(q: String): input.text = ""; core.ask(q)); row.add_child(input)
	send_btn = UI.icon_btn("send", "Envoyer", Callable(), "Accent")
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
	for n in core.available: model_opt.add_item(str(ChatCore.MODELS[n]["label"]) + ("" if core.model_ready(n) else "  ↓"))
	if not core.is_busy: status.text = core.note
	dl_btn.visible = core.engine_ok() and not core.model_ready() and not core.downloading()
	var i := core.available.find(core.model)
	if i >= 0: model_opt.select(i)
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scroll): scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
