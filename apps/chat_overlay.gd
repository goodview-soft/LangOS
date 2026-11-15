class_name ChatOverlay
extends Node
const UI = preload("res://apps/ui.gd")
## Overlay chat IA : petite fenêtre en haut à droite de l'écran, par-dessus les jeux. Bascule avec « - » (ou le raccourci global).

var core: ChatCore
var win: Window
var msgs_box: VBoxContainer
var scroll: ScrollContainer
var input: LineEdit
var status: Label

const W := 470
const H := 400


func _ready() -> void:
	if OS.has_feature("mobile") or not DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS): return
	win = Window.new()
	win.visible = false
	win.force_native = true
	win.title = "LangOS chat"
	win.borderless = true; win.transparent = true; win.transparent_bg = true
	win.always_on_top = true; win.unresizable = true
	win.size = Vector2i(W, H)
	win.close_requested.connect(hide_chat)
	win.window_input.connect(_win_input)
	add_child(win)
	var root := PanelContainer.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(UI.p("menu"), 0.95); sb.set_corner_radius_all(UI.rad(4))
	sb.set_border_width_all(1); sb.border_color = UI.p("edge"); sb.set_content_margin_all(12)
	root.add_theme_stylebox_override("panel", sb); win.add_child(root)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); root.add_child(v)
	var head := HBoxContainer.new(); v.add_child(head)
	var t := Label.new(); t.text = "💬 IA locale"; t.add_theme_font_size_override("font_size", 14); t.add_theme_color_override("font_color", UI.accent_text()); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(t)
	status = Label.new(); status.add_theme_font_size_override("font_size", 12); status.theme_type_variation = "Muted"; head.add_child(status)
	var x := preload("res://apps/ui.gd").icon_btn("x", "Fermer"); x.pressed.connect(hide_chat); head.add_child(x)
	scroll = ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; v.add_child(scroll)
	msgs_box = VBoxContainer.new(); msgs_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; msgs_box.add_theme_constant_override("separation", 6); scroll.add_child(msgs_box)
	input = LineEdit.new(); input.placeholder_text = "Demande quelque chose… (Entrée, Échap pour fermer)"
	input.virtual_keyboard_enabled = false; input.text_submitted.connect(_submit); v.add_child(input)
	core.changed.connect(_rebuild); core.busy_changed.connect(func(on: bool): status.text = "réflexion…" if on else (core.model if core.model != "" else ""))
	_rebuild()


func _submit(t: String) -> void:
	input.text = ""
	core.ask(t)


func _win_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE: hide_chat()


func _rebuild() -> void:
	if win == null: return
	for c in msgs_box.get_children(): c.queue_free()
	var f: Font = ThemeDB.fallback_font
	var arr: Array = core.messages
	for m in arr.slice(maxi(0, arr.size() - 8)):
		msgs_box.add_child(ChatCore.bubble(m["role"], str(m["content"]), W - 80.0, 15, f))
	if core.is_busy:
		msgs_box.add_child(ChatCore.bubble("assistant", "…", 120.0, 15, f))
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scroll): scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func is_open() -> bool:
	return win != null and win.visible


func toggle() -> void:
	if win == null: return
	if win.visible: hide_chat()
	else: show_chat()


func show_chat() -> void:
	if win == null: return
	# Écran sous la souris (jeu sur un autre écran), coin haut droit
	var screen := DisplayServer.get_screen_from_rect(Rect2i(DisplayServer.mouse_get_position(), Vector2i(1, 1)))
	var r := DisplayServer.screen_get_usable_rect(screen)
	win.position = Vector2i(r.position.x + r.size.x - W - 14, r.position.y + 14)
	win.show()
	win.grab_focus()
	DisplayServer.window_move_to_foreground(win.get_window_id())
	input.grab_focus()
	core.refresh_models()
	_rebuild()


func hide_chat() -> void:
	if win: win.hide()
