extends Control
# Bloc-notes avec clavier visuel, interface façon OS.

const VERSION: String = preload("res://version.gd").VERSION
const UPDATE_URL := "https://github.com/goodview-soft/LangOS/releases/latest/download/version.json"
const RELEASES_URL := "https://github.com/goodview-soft/LangOS/releases/latest"
const CHECK_UPDATES := true
const SAVE_PATH := "user://note.txt"
const ROWS_LOWER := [
	["²","&","é","\"","'","(","-","è","_","ç","à",")","="],
	["a","z","e","r","t","y","u","i","o","p","^","$"],
	["q","s","d","f","g","h","j","k","l","m","ù","*"],
	["<","w","x","c","v","b","n",",",";",":","!"],
]
const ROWS_UPPER := [
	["~","1","2","3","4","5","6","7","8","9","0","°","+"],
	["A","Z","E","R","T","Y","U","I","O","P","¨","£"],
	["Q","S","D","F","G","H","J","K","L","M","%","µ"],
	[">","W","X","C","V","B","N","?",".","/","§"],
]

var edit: TextEdit
var status: Label
var clock: Label
var title_lbl: Label
var shift := false
var caps := false
var char_btns: Array = []   # [Button, row, col]
var shift_btns: Array = []
var dirty := false

var desk: Control
var wins := {}   # id -> {win, task, maxed, saved}
var task_box: HBoxContainer
var start_btn: Button
var menu: PanelContainer
var catcher: Control
var bg: TextureRect
var upd_text := ""
var upd_avail := false
var apk_prompted := false
var upd_lbl: Label
const BG_GRADS := [["16213e","2f5fa8","7a4fb0"], ["0f1c26","1f4e5f","2e8b7a"], ["16161f","3a2a5c","b0507a"], ["12141a","2a2f3d","56607a"], ["1c120d","6b3a1f","e0873a"]]
var ACCENT := Color("5aa2ff")   # variable : couleur d'accent choisie dans Paramètres > Apparence
var fx            # apps/fx.gd : animations, aperçu d'ancrage, réglages d'apparence
var dock          # apps/dock.gd
var ccenter       # apps/control_center.gd
var prof          # apps/profiles.gd (logique)
var srch          # apps/search.gd
var cal           # apps/calendar.gd (agenda + rappels)
var clip          # apps/clipboard.gd (historique du presse-papiers)
var overview      # apps/overview.gd (vue d'ensemble Ctrl+Alt+Tab, aperçus au survol)
var keysc         # apps/shortcuts.gd (raccourcis clavier / manette)
var tray_node: Control
var menu_hi: TextureRect
var cc_btn: Button
## Jetons de couleur libadwaita : win = window_bg, field/view = view_bg, card = card_bg, tb_on/header = headerbar_bg, tb_off = headerbar backdrop,
## sidebar = sidebar_bg, popup/menu/pop = popover_bg, edge = bordure (15 %), muted = texte atténué, destructive = rouge.
const PAL_D := {"win": Color("222226"), "tb_on": Color("2e2e32"), "tb_off": Color("222226"), "field": Color("1d1d20"), "view": Color("1d1d20"), "header": Color("2e2e32"), "sidebar": Color("2e2e32"),
	"popup": Color("36363a"), "bar": Color(0.075, 0.075, 0.085, 0.92), "menu": Color(0.212, 0.212, 0.227, 0.98), "text": Color("ffffff"), "ov": Color(1, 1, 1), "edge": Color(1, 1, 1, 0.15),
	"card": Color("343438"), "muted": Color("a5a5a9"), "ok": Color("8ff0a4"), "warn": Color("f8e45c"), "err": Color("ff7b63"), "destructive": Color("c01c28"),
	"bub_me": Color("2b5fb8"), "bub_you": Color("3a3a3e"), "pop": Color(0.212, 0.212, 0.227, 0.98), "kb": Color(0.114, 0.114, 0.125, 0.97)}
const PAL_L := {"win": Color("fafafb"), "tb_on": Color("ffffff"), "tb_off": Color("fafafb"), "field": Color("ffffff"), "view": Color("ffffff"), "header": Color("ffffff"), "sidebar": Color("ebebed"),
	"popup": Color("ffffff"), "bar": Color(0.92, 0.92, 0.93, 0.94), "menu": Color(1, 1, 1, 0.98), "text": Color("333338"), "ov": Color(0, 0, 0.02), "edge": Color(0, 0, 0.02, 0.15),
	"card": Color("ffffff"), "muted": Color("626267"), "ok": Color("1b8553"), "warn": Color("9c6e03"), "err": Color("c01c28"), "destructive": Color("c01c28"),
	"bub_me": Color("2563eb"), "bub_you": Color("e6e6e9"), "pop": Color(1, 1, 1, 0.98), "kb": Color(0.92, 0.92, 0.93, 0.97)}
func _p(k: String):
	return (PAL_L if set_cfg.get("light", false) else PAL_D)[k]
const TEXT := Color("e5e9f0")
const UI = preload("res://apps/ui.gd")
var MUTED := Color("8f9bb3")   # mis à jour selon le thème (clair : plus foncé)
const APPS := {
	"notepad": ["Bloc-notes", "res://icons/app_notepad.svg"],
	"settings": ["Paramètres", "res://icons/app_settings.svg"],
	"system": ["Système", "res://icons/app_system.svg"],
	"translate": ["Traducteur", "res://icons/app_translate.svg"],
	"dict": ["Dictionnaire", "res://icons/app_dict.svg"],
	"messenger": ["Messenger", "res://icons/app_messenger.svg"],
	"remote": ["RemoteDesk", "res://icons/app_remote.svg"],
	"chat": ["Chat IA", "res://icons/app_chat.svg"],
	"music": ["Music", "res://icons/app_music.svg"],
	"soundlink": ["Sound Link", "res://icons/app_soundlink.svg"],
	"update": ["Mise à jour", "res://icons/app_update.svg"],
	"chess": ["Échecs", "res://icons/app_chess.svg"],
	"f_lang": ["Langue", "res://icons/app_f_lang.svg"],
	"f_games": ["Jeux", "res://icons/app_f_games.svg"],
	"f_comm": ["Communication", "res://icons/app_f_comm.svg"],
	"hika": ["Hikabrain", "res://icons/app_hika.svg"],
	"chromium": ["Chromium", "res://icons/app_chromium.svg"],
	"chromium2": ["Chromium 2", "res://icons/app_chromium.svg"],
	"chromium3": ["Chromium 3", "res://icons/app_chromium.svg"],
	"android_apps": ["Applis Android", "res://icons/app_android.svg"],
	"f_soft": ["Logiciels", "res://icons/app_f_soft.svg"],
	"f_tools": ["Outils", "res://icons/app_f_tools.svg"],
	"calc": ["Calculatrice", "res://icons/app_calc.svg"],
	"units": ["Convertisseur", "res://icons/app_units.svg"],
	"timer": ["Minuteur", "res://icons/app_timer.svg"],
	"todo": ["Listes", "res://icons/app_todo.svg"],
	"vault": ["Coffre-fort", "res://icons/app_vault.svg"],
	"cards": ["Cartes mémoire", "res://icons/app_cards.svg"],
	"files": ["Fichiers", "res://icons/app_files.svg"],
	"terminal": ["Terminal", "res://icons/app_terminal.svg"],
	"code": ["Éditeur de code", "res://icons/app_code.svg"],
	"profiles": ["Profils", "res://icons/app_profiles.svg"],
	"clipboard": ["Presse-papiers", "res://icons/app_clipboard.svg"],
	"devices": ["Périphériques", "res://icons/app_devices.svg"],
	"f_office": ["Bureautique", "res://icons/app_f_office.svg"],
	"sheet": ["Tableur", "res://icons/app_sheet.svg"],
	"imgview": ["Images", "res://icons/app_imgview.svg"],
	"pdf": ["Lecteur PDF", "res://icons/app_pdf.svg"],
	"calendar": ["Agenda", "res://icons/app_calendar.svg"],
	"notes": ["Notes", "res://icons/app_notes.svg"],
	"trash": ["Corbeille", ""],
	"market": ["Market", ""],
	"scanner": ["Scanner", ""],
	"gallery": ["Galerie", ""],
}
## Dossiers du bureau : id -> applications contenues (affichées seulement dans le dossier).
const FOLDERS := {
	"f_lang": ["translate", "dict", "music"],
	"f_games": ["chess", "hika"],
	"f_soft": ["chromium", "notes", "files", "terminal", "code", "profiles", "clipboard", "devices"],
	"f_comm": ["messenger", "remote", "chat", "soundlink"],
	"f_office": ["sheet", "imgview", "pdf", "calendar", "scanner", "gallery"],
	"f_tools": ["calc", "units", "timer", "todo", "vault", "cards"],
}

## Icône d'une appli. La Corbeille est dessinée depuis du SVG intégré (pas besoin d'import Godot).
const TRASH_SVG := '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 64 64"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#94a3b8"/><stop offset="1" stop-color="#475569"/></linearGradient></defs><rect x="2" y="2" width="60" height="60" rx="15" fill="url(#g)"/><g fill="#fff" fill-opacity=".93"><rect x="14" y="19" width="36" height="5" rx="2.5"/><rect x="25" y="13" width="14" height="6" rx="2.5"/><path d="M17 27h30l-2.2 21a4 4 0 0 1-4 3.6H23.2a4 4 0 0 1-4-3.6z"/></g><g stroke="#64748b" stroke-width="2.4" stroke-linecap="round"><path d="M26 32v14M32 32v14M38 32v14"/></g></svg>'
const SCANNER_SVG := '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 64 64"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fb923c"/><stop offset="1" stop-color="#c2410c"/></linearGradient></defs><rect x="2" y="2" width="60" height="60" rx="15" fill="url(#g)"/><path d="M19 12h20l8 8v32a2 2 0 0 1-2 2H19a2 2 0 0 1-2-2V14a2 2 0 0 1 2-2z" fill="#fff" fill-opacity=".95"/><path d="M24 28h16M24 34h16M24 40h10" stroke="#c2410c" stroke-width="2.6" stroke-linecap="round"/><path d="M8 32h48" stroke="#fde68a" stroke-width="3" stroke-linecap="round"/></svg>'
const GALLERY_SVG := '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 64 64"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#a78bfa"/><stop offset="1" stop-color="#6d28d9"/></linearGradient></defs><rect x="2" y="2" width="60" height="60" rx="15" fill="url(#g)"/><rect x="13" y="15" width="38" height="34" rx="5" fill="#fff" fill-opacity=".95"/><circle cx="24" cy="26" r="4.5" fill="#fbbf24"/><path d="M13 43l12-11 9 8 7-6 10 9v1a5 5 0 0 1-5 5H18a5 5 0 0 1-5-5z" fill="#7c3aed"/></svg>'
const MARKET_SVG := '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 64 64"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#34d399"/><stop offset="1" stop-color="#047857"/></linearGradient></defs><rect x="2" y="2" width="60" height="60" rx="15" fill="url(#g)"/><path d="M15 23h34l-2.6 24a4 4 0 0 1-4 3.5H21.6a4 4 0 0 1-4-3.5z" fill="#fff" fill-opacity=".93"/><path d="M24 27v-4a8 8 0 0 1 16 0v4" fill="none" stroke="#fff" stroke-width="3.2" stroke-linecap="round"/></svg>'
var _svg_tex := {}
func app_icon(id: String) -> Texture2D:
	if id == "trash" or id == "market" or id == "scanner" or id == "gallery":
		if not _svg_tex.has(id):
			var img := Image.new(); img.load_svg_from_buffer(({"trash": TRASH_SVG, "market": MARKET_SVG, "scanner": SCANNER_SVG, "gallery": GALLERY_SVG}[id]).to_utf8_buffer(), 1.0)
			_svg_tex[id] = ImageTexture.create_from_image(img)
		return _svg_tex[id]
	return load(APPS[id][1])

## Applis toujours installées ; les autres s'ajoutent depuis le Market.
const CORE := ["market", "settings", "system", "files", "trash", "update", "notepad"]
const HIDDEN := ["chromium2", "chromium3"]   # fenêtres supplémentaires du navigateur : jamais listées comme applis
func installed(id: String) -> bool:
	if HIDDEN.has(id): return installed("chromium")
	if FOLDERS.has(id): return FOLDERS[id].any(func(k): return installed(k))
	return CORE.has(id) or set_cfg["installed"].has(id)

func _top_ids() -> Array:
	var inside := []
	for f in FOLDERS: inside += FOLDERS[f]
	var android := OS.get_name() == "Android"
	return APPS.keys().filter(func(k): return not inside.has(k) and not HIDDEN.has(k) and (k != "android_apps" or android))
var active := ""
var menu_reset := Callable()
var menu_sc: ScrollContainer
var menu_search: LineEdit
var set_cfg := {"bg": 0, "font": 22, "ollama": "http://127.0.0.1:11434", "kb": "osk", "cursor": "auto", "pad": false, "pad_speed": 0.7, "zoom": 1.0, "model": "", "engine": -1, "src": "spa", "tgt": "fra", "light": false, "wall": false, "icons": {}, "layout": {}, "open": [], "accent": "5aa2ff", "anim": true, "wtrans": 1.0, "radius": 12, "isize": 56, "pins": ["notepad", "settings", "calc", "music"], "desk": ["trash", "market"], "mk_desk": true, "installed": [], "dock_hide": false, "keys": {}, "padmap": {}, "clip_save": true, "clip_nopw": true}
var kb: PanelContainer
var ui_root: VBoxContainer
var pointer: Control
var flex: PanelContainer
var fold_half := false
var fold_top := 0.0
var fold_bottom := 0.0
var fold_px_top := 0.0       # charnière en pixels écran (indépendant du zoom)
var fold_px_bottom := 0.0
var zoom_save := false
var fold_gen := 0
var kb_btn: Button
var upd_http: HTTPRequest
var upd_btn: Button
var upd_info := {}
var bar_h := 48.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # le bureau reste actif quand un jeu se met en pause
	_load_settings()
	OS.low_processor_usage_mode = true
	OS.low_processor_usage_mode_sleep_usec = 16000
	n_vd = clampi(int(set_cfg.get("nvd", 2)), 1, 6)
	_build_theme()
	_build_desktop()
	_setup_chat()
	if _real(): _restore_layout.call_deferred()
	var t := Timer.new(); t.wait_time = 1.0; t.autostart = true
	t.timeout.connect(_tick); add_child(t); _tick()
	_check_update()
	if "--pad-test" in OS.get_cmdline_user_args(): set_cfg["pad"] = true; _update_flex.call_deferred()
	if "--perf-test" in OS.get_cmdline_user_args():
		_perf_test(); return
	if "--ctl-test" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1.5).timeout
		var snd := PacketPeerUDP.new(); var tp := 4360
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--ctl-port="): tp = a.get_slice("=", 1).to_int()
		snd.set_dest_address("127.0.0.1", tp); snd.put_packet("toggle-chat".to_utf8_buffer())
		await get_tree().create_timer(0.6).timeout
		print("CTL ctl.bound=", ctl.is_bound(), " ouvert après toggle UDP: ", chat_ov != null and chat_ov.is_open(), " win=", chat_ov.win != null if chat_ov else "-")
		snd.put_packet("toggle-chat".to_utf8_buffer()); await get_tree().create_timer(0.6).timeout
		print("CTL fermé après 2e toggle: ", chat_ov != null and not chat_ov.is_open())
		get_tree().quit()
	if "--os-test" in OS.get_cmdline_user_args():
		set_cfg["installed"] = APPS.keys()
		for id in APPS: _open_app(id)
		_toggle_menu(); _toggle_menu(); _toggle_kb()
		await get_tree().create_timer(1.0).timeout
		_dic_search("casa")
		print("DICT: ", dic_list.get_item_text(0), " | ", dic_def.get_parsed_text().replace("\n", " ").substr(0, 70), " | ", dic_info.text)
		set_cfg["src"] = "fra"; set_cfg["tgt"] = "eng"; _apply_langs()
		await get_tree().create_timer(1.0).timeout
		print("LANGS: ", dic_note.text, " | ", dic_info.text, " | music=", music_node.get("src"), ">", music_node.get("tgt"), " | tr=", tr_pair.text)
		set_cfg["src"] = "spa"; set_cfg["tgt"] = "fra"; _apply_langs()
		await get_tree().create_timer(1.0).timeout
		print("LANGS2: ", dic_note.text)
		edit.text = "bonjour tout le monde"; edit.grab_focus(); _clip_action("all"); _clip_action("copy"); edit.text = ""; _clip_action("paste")
		print("CLIP: ", edit.text)
		_show_ctx(edit, Vector2(400, 300)); print("CTX: ", ctx_menu.visible, " ", ctx_menu.get_child(0).get_child_count(), " boutons"); _hide_ctx()
		print("OS-TEST OK wins=", wins.size())
		get_tree().quit()

# ---------------------------------------------------------------- Appui long : menu Copier / Coller

func _input(ev: InputEvent) -> void:
	if keysc != null and keysc.handle(ev): get_viewport().set_input_as_handled(); return
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.ctrl_pressed and ev.keycode == KEY_SPACE and srch:
		srch.toggle(); get_viewport().set_input_as_handled(); return
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_MINUS and chat_ov:
		var fo := get_viewport().gui_get_focus_owner()
		if not (fo is LineEdit or fo is TextEdit):
			chat_ov.toggle(); get_viewport().set_input_as_handled(); return
	if ev is InputEventKey and ev.pressed and ev.ctrl_pressed and ev.alt_pressed and (ev.keycode == KEY_LEFT or ev.keycode == KEY_RIGHT):
		_goto_vd(posmod(cur_vd + (1 if ev.keycode == KEY_RIGHT else -1), n_vd)); get_viewport().set_input_as_handled(); return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			if _begin_resize(ev.position): get_viewport().set_input_as_handled(); return
		elif not rs.is_empty():
			rs = {}; _save_layout(); get_viewport().set_input_as_handled(); return
	elif ev is InputEventMouseMotion and not rs.is_empty():
		_do_resize(ev.position); get_viewport().set_input_as_handled(); return
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		_context_here(ev.position); get_viewport().set_input_as_handled(); return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed: _raise_window_at(ev.position)
		lp_active = ev.pressed; lp_pos = ev.position; lp_t = Time.get_ticks_msec()
	elif ev is InputEventMouseMotion and lp_active and ev.position.distance_to(lp_pos) > 16.0:
		lp_active = false

## Un clic n'importe où dans une fenêtre la met au premier plan (la dernière sélectionnée passe devant).
func _raise_window_at(pos: Vector2) -> void:
	if desk == null or menu.visible: return
	var p := pos - desk.global_position
	var kids := desk.get_children()
	kids.reverse()
	for c in kids:
		if not (c is PanelContainer and c.visible and Rect2(c.position, c.size).has_point(p)): continue
		for id in wins:
			if wins[id]["win"] == c:
				if active != id: _show(id)
				return
		return

func _check_longpress() -> void:
	if lp_active and Time.get_ticks_msec() - lp_t > 550:
		lp_active = false
		_context_here(lp_pos)

func _context_here(pos: Vector2) -> void:
	var c := get_viewport().gui_get_hovered_control()
	while c and not (c is TextEdit or c is LineEdit or c is RichTextLabel): c = c.get_parent() as Control
	if c: _show_ctx(c, pos)
	else: _context_at(pos)

func _show_ctx(t: Control, at: Vector2) -> void:
	_hide_ctx()
	ctx_target = t
	var editable: bool = (t is TextEdit and t.editable) or (t is LineEdit and t.editable)
	if t is TextEdit and not t.has_selection(): t.select_word_under_caret()
	var has_sel := false
	if t is TextEdit or t is LineEdit: has_sel = t.has_selection() if t is TextEdit else t.has_selection()
	ctx_catcher = Control.new(); ctx_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctx_catcher.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: _hide_ctx())
	add_child(ctx_catcher)
	ctx_menu = PanelContainer.new()
	ctx_menu.add_theme_stylebox_override("panel", _box(_p("pop"), UI.rad(), _p("edge"), 1, 18, 6))
	add_child(ctx_menu)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 2); ctx_menu.add_child(h)
	var items := []
	if editable and has_sel: items.append(["Couper", "cut"])
	items.append(["Copier", "copy"])
	if editable: items.append(["Coller", "paste"])
	items.append(["Tout sélectionner", "all"])
	for e in items:
		var b := _mk_btn(e[0], 0, 40); b.theme_type_variation = "Nav"
		b.pressed.connect(func(): _ctx_do(e[1]))
		h.add_child(b)
	ctx_menu.size = ctx_menu.get_combined_minimum_size()
	ctx_menu.position = Vector2(clampf(at.x - ctx_menu.size.x / 2.0, 8, size.x - ctx_menu.size.x - 8), maxf(8, at.y - ctx_menu.size.y - 28))

func _ctx_do(a: String) -> void:
	var t := ctx_target
	if is_instance_valid(t):
		t.grab_focus()
		if t is RichTextLabel and a == "copy":
			var s: String = t.get_selected_text()
			DisplayServer.clipboard_set(s if s != "" else t.get_parsed_text()); _clip_seen()
		else: _clip_action(a)
	_hide_ctx()

func _hide_ctx() -> void:
	if is_instance_valid(ctx_menu): ctx_menu.queue_free()
	if is_instance_valid(ctx_catcher): ctx_catcher.queue_free()

func _process(_d: float) -> void:
	_check_longpress()
	_poll_ctl()

func _cpu_ticks() -> int:
	var out := []
	OS.execute("cat", ["/proc/%d/stat" % OS.get_process_id()], out)
	if out.is_empty(): return 0
	var f: String = out[0]
	var p := f.substr(f.rfind(")") + 2).split(" ")
	return int(p[11]) + int(p[12])

func _perf_sample(label: String, secs: float) -> void:
	var c0 := _cpu_ticks(); var t0 := Time.get_ticks_msec()
	var n := 0; var worst := 0.0; var dc := 0.0; var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec(); var dt := (now - last) / 1000.0; last = now
		worst = maxf(worst, dt); n += 1
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var wall := (Time.get_ticks_msec() - t0) / 1000.0
	var cpu := float(_cpu_ticks() - c0) / 100.0 / wall * 100.0
	print("PERF %-38s CPU=%5.1f%%  fps=%5.1f  pire image=%6.1f ms  draw_calls=%4.0f" % [label, cpu, n / wall, worst, dc / maxf(1, n)])

func _perf_test() -> void:
	await get_tree().create_timer(1.0).timeout
	await _perf_sample("bureau seul", 5.0)
	_open_app("music")
	await get_tree().create_timer(0.8).timeout
	var mu := music_node
	mu.set("tracks", [{"id": "perf", "title": "T", "artist": "A", "track": "Titre", "duration": 120.0, "file": OS.get_environment("HOME") + "/mtest/s.mp3", "lrc": "", "offset": 0.0, "no_lyrics": true, "video": OS.get_environment("HOME") + "/mtest/c.ogv" if "--perf-video" in OS.get_cmdline_user_args() else ""}])
	mu.call("_play", 0)
	var ls := []
	for i in 30: ls.append([i * 3.0, "Voy de buena onda, me invita a tu casa y ahora tú me dice' que yo me agacha %d" % i])
	mu.set("lines", ls)
	var tr := {}
	for i in 30: tr[i] = {"tr": "Je suis cool, il m'invite chez lui et maintenant tu me dis", "words": [{"w": "onda", "sens": "ambiance"}, {"w": "casa", "sens": "maison"}, {"w": "agacha", "sens": "me baisser"}]}
	mu.set("trans", tr)
	mu.get("kv").call("set_data", ls, tr)
	await _perf_sample("Music : lecteur karaoké (au 1er plan)", 6.0)
	mu.set("ov_mode", 1); mu.set("cw_mode", 2)
	await _perf_sample("+ overlay paroles + mot centre", 6.0)
	mu.set("ov_mode", 0); mu.set("cw_mode", 0)
	await get_tree().create_timer(2.0).timeout
	await _perf_sample("Music, overlays coupés (après 2 s)", 4.0)
	get_tree().quit()

func _notification(what: int) -> void:
	# Au premier plan : ~60 images/s ; en arrière-plan (jeu au premier plan) : ~30, les overlays suffisent.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: OS.low_processor_usage_mode_sleep_usec = 33000
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN: OS.low_processor_usage_mode_sleep_usec = 16000

func _tick() -> void:
	var d := Time.get_date_dict_from_system()
	clock.text = "%s\n%02d/%02d/%d" % [Time.get_datetime_string_from_system().substr(11, 5), d["day"], d["month"], d["year"]]

func _box(c: Color, r := 8, bc := Color(0, 0, 0, 0), bw := 0, sh := 0, m := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = c; s.set_corner_radius_all(r)
	if bw > 0: s.border_color = bc; s.set_border_width_all(bw)
	if sh > 0: s.shadow_color = Color(0, 0, 0, 0.45); s.shadow_size = sh; s.shadow_offset = Vector2(0, sh * 0.3)
	if m > 0: s.set_content_margin_all(m)
	return s

func _rad() -> int:
	return int(set_cfg.get("radius", 12))

## Style d'une fenêtre : ombre plus large quand elle est active, encore plus pendant le déplacement.
func _winbox(on: bool, drag := false) -> StyleBoxFlat:
	var c: Color = _p("win"); c.a = float(set_cfg.get("wtrans", 1.0))
	var s := _box(c, _rad(), _p("edge"), 1)
	s.set_content_margin_all(1)   # le contenu ne recouvre pas le filet de la fenêtre
	s.shadow_size = 52 if drag else (34 if on else 12)
	s.shadow_color = Color(0, 0, 0, 0.6 if drag else (0.45 if on else 0.2)); s.shadow_offset = Vector2(0, s.shadow_size * 0.3)
	return s

func _flat(c: Color, r := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = c; s.set_corner_radius_all(r)
	return s

func _ico(n: String) -> Texture2D:
	return load("res://icons/%s.svg" % n)

func _grad_tex(i: int, w := 512, h := 288) -> GradientTexture2D:
	var g := Gradient.new()
	var cols := PackedColorArray(); var offs := PackedFloat32Array()
	var arr: Array = BG_GRADS[i]
	for k in arr.size():
		cols.append(Color(arr[k])); offs.append(float(k) / (arr.size() - 1))
	g.colors = cols; g.offsets = offs
	var t := GradientTexture2D.new(); t.gradient = g; t.width = w; t.height = h
	t.fill_from = Vector2(0, 0); t.fill_to = Vector2(1, 1)
	return t

func _build_theme() -> void:
	UI.m = self; MUTED = _p("muted")
	var th := Theme.new()
	th.default_font = UI.font(); th.default_font_size = UI.T_BODY
	var tx: Color = _p("text"); var mu: Color = _p("muted"); var dis := Color(tx, 0.5)
	var rb := UI.rad_btn(); var ri := mini(6, rb)
	var none := Color(0, 0, 0, 0)
	var w := func(a: float) -> Color: return UI.veil(a)
	var mk := func(c: Color, r: int, mh: int, mv: int) -> StyleBoxFlat:
		var sb := _box(c, r); sb.content_margin_left = mh; sb.content_margin_right = mh; sb.content_margin_top = mv; sb.content_margin_bottom = mv
		return sb
	# États d'un type de bouton : [état, voile (float) ou couleur]
	var states := func(type: String, vals: Array, r: int, mh: int, mv: int) -> void:
		for st in vals: th.set_stylebox(st[0], type, mk.call(st[1] if st[1] is Color else UI.veil(st[1]), r, mh, mv))
		th.set_stylebox("focus", type, UI.focus_box(r))
	var colors := func(type: String, c: Color) -> void:
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color",
				"icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]: th.set_color(k, type, c)
		th.set_color("font_disabled_color", type, Color(c, 0.5)); th.set_color("icon_disabled_color", type, Color(c, 0.5))
	# Boutons (libadwaita : voile 10 %, 15 % au survol, 30 % enfoncé ; rayon 9)
	states.call("Button", [["normal", 0.1], ["hover", 0.15], ["pressed", 0.3], ["hover_pressed", 0.35], ["disabled", 0.05]], rb, 12, 7)
	colors.call("Button", tx)
	th.set_font("font", "Button", UI.font(600)); th.set_font_size("font_size", "Button", UI.T_BODY)
	th.set_constant("icon_max_width", "Button", 18); th.set_constant("h_separation", "Button", 6)
	for ty in ["OptionButton", "MenuButton"]:
		for st in ["normal", "hover", "pressed", "disabled"]: th.set_stylebox(st, ty, th.get_stylebox(st, "Button"))
		th.set_stylebox("focus", ty, UI.focus_box(rb)); colors.call(ty, tx)
		th.set_font("font", ty, UI.font()); th.set_font_size("font_size", ty, UI.T_BODY)
	th.set_icon("arrow", "OptionButton", UI.glyph("chevron-down", Color.WHITE)); th.set_constant("modulate_arrow", "OptionButton", 1); th.set_constant("arrow_margin", "OptionButton", 10)
	# Boutons plats (barres d'en-tête), plats cochés, lignes de navigation, ronds (contrôles de fenêtre)
	th.set_type_variation("Flat", "Button")
	states.call("Flat", [["normal", none], ["hover", 0.07], ["pressed", 0.16], ["hover_pressed", 0.19], ["disabled", none]], rb, 12, 7)
	th.set_type_variation("FlatOn", "Button")
	states.call("FlatOn", [["normal", 0.1], ["hover", 0.13], ["pressed", 0.19], ["hover_pressed", 0.19], ["disabled", 0.05]], rb, 12, 7)
	th.set_type_variation("Nav", "Button")
	states.call("Nav", [["normal", none], ["hover", 0.07], ["pressed", 0.1], ["hover_pressed", 0.13], ["disabled", none]], ri, 9, 7)
	th.set_font("font", "Nav", UI.font()); th.set_constant("h_separation", "Nav", 12)
	th.set_type_variation("Circular", "Button")
	states.call("Circular", [["normal", 0.1], ["hover", 0.15], ["pressed", 0.3], ["hover_pressed", 0.3], ["disabled", 0.05]], 99, 4, 4)
	th.set_type_variation("Close", "Button")
	states.call("Close", [["normal", none], ["hover", Color("e5484d")], ["pressed", Color("c0363b")]], ri, 8, 4)
	# « suggested » = accent, « destructive » = rouge
	var onacc: Color = UI.on(ACCENT)
	th.set_type_variation("Accent", "Button")
	states.call("Accent", [["normal", ACCENT], ["hover", ACCENT.lightened(0.1)], ["pressed", ACCENT.darkened(0.15)], ["hover_pressed", ACCENT.darkened(0.1)], ["disabled", Color(ACCENT, 0.5)]], rb, 16, 7)
	colors.call("Accent", onacc)
	var red: Color = _p("destructive")
	th.set_type_variation("Destructive", "Button")
	states.call("Destructive", [["normal", red], ["hover", red.lightened(0.1)], ["pressed", red.darkened(0.15)], ["hover_pressed", red.darkened(0.1)], ["disabled", Color(red, 0.5)]], rb, 16, 7)
	colors.call("Destructive", Color.WHITE)
	# Cases, interrupteurs, liens : pas de fond de bouton
	for ty in ["CheckBox", "CheckButton"]:
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "hover_disabled"]: th.set_stylebox(st, ty, mk.call(none, 0, 2, 4))
		th.set_stylebox("focus", ty, UI.focus_box(4))
		colors.call(ty, tx); th.set_font("font", ty, UI.font()); th.set_constant("h_separation", ty, 8)
	colors.call("LinkButton", UI.accent_text())
	for pr in [["checked", true, false], ["unchecked", false, false], ["checked_disabled", true, true], ["unchecked_disabled", false, true]]:
		th.set_icon(pr[0], "CheckButton", UI.switch_tex(pr[1], pr[2])); th.set_icon(pr[0] + "_mirrored", "CheckButton", UI.switch_tex(pr[1], pr[2]))
		th.set_icon(pr[0], "CheckBox", UI.check_tex(pr[1], false, pr[2])); th.set_icon("radio_" + pr[0], "CheckBox", UI.check_tex(pr[1], true, pr[2]))
	# Menus (popover)
	th.set_stylebox("panel", "PopupMenu", _box(_p("popup"), UI.rad(), _p("edge"), 1, 12, 6))
	th.set_stylebox("hover", "PopupMenu", _box(w.call(0.1), ri))
	for k in ["font_color", "font_hover_color", "font_accelerator_color"]: th.set_color(k, "PopupMenu", tx)
	th.set_color("font_disabled_color", "PopupMenu", dis); th.set_color("font_separator_color", "PopupMenu", mu)
	th.set_font_size("font_size", "PopupMenu", UI.T_BODY)
	th.set_constant("v_separation", "PopupMenu", 12); th.set_constant("h_separation", "PopupMenu", 8)
	th.set_constant("item_start_padding", "PopupMenu", 9); th.set_constant("item_end_padding", "PopupMenu", 9)
	var sl := StyleBoxLine.new(); sl.color = _p("edge"); sl.thickness = 1
	th.set_stylebox("separator", "PopupMenu", sl)
	th.set_icon("checked", "PopupMenu", UI.glyph("check", tx)); th.set_icon("unchecked", "PopupMenu", UI.blank())
	th.set_icon("radio_checked", "PopupMenu", UI.glyph("check", tx)); th.set_icon("radio_unchecked", "PopupMenu", UI.blank())
	th.set_icon("submenu", "PopupMenu", UI.glyph("chevron-right", tx))
	# Listes et arbres (vue : sélection teintée d'accent à 25 %)
	for ty in ["ItemList", "Tree"]:
		th.set_stylebox("panel", ty, _box(_p("field"), rb, _p("edge"), 1, 0, 6)); th.set_stylebox("focus", ty, StyleBoxEmpty.new())
		for st in ["selected", "selected_focus"]: th.set_stylebox(st, ty, _box(Color(ACCENT, 0.25), ri))
		for st in ["hovered_selected", "hovered_selected_focus"]: th.set_stylebox(st, ty, _box(Color(ACCENT, 0.32), ri))
		th.set_stylebox("hovered", ty, _box(w.call(0.07), ri))
		for st in ["cursor", "cursor_unfocused"]: th.set_stylebox(st, ty, StyleBoxEmpty.new())
		for k in ["font_color", "font_selected_color", "font_hovered_color", "font_hovered_selected_color"]: th.set_color(k, ty, tx)
		th.set_color("guide_color", ty, none); th.set_font_size("font_size", ty, UI.T_BODY)
	th.set_constant("v_separation", "ItemList", 10); th.set_constant("h_separation", "ItemList", 8)
	th.set_constant("v_separation", "Tree", 10); th.set_constant("draw_relationship_lines", "Tree", 0); th.set_constant("draw_guides", "Tree", 0)
	th.set_constant("inner_item_margin_left", "Tree", 6); th.set_constant("inner_item_margin_right", "Tree", 6)
	th.set_color("relationship_line_color", "Tree", none); th.set_color("font_disabled_color", "Tree", mu)
	th.set_icon("arrow", "Tree", UI.glyph("chevron-down", mu)); th.set_icon("arrow_collapsed", "Tree", UI.glyph("chevron-right", mu))
	# Texte
	th.set_color("font_color", "Label", tx); th.set_font_size("font_size", "Label", UI.T_BODY)
	th.set_color("default_color", "RichTextLabel", tx)
	th.set_font("bold_font", "RichTextLabel", UI.font(700)); th.set_font("italics_font", "RichTextLabel", UI.font(400, true))
	th.set_font("bold_italics_font", "RichTextLabel", UI.font(700, true)); th.set_font("mono_font", "RichTextLabel", UI.mono())
	th.set_color("font_color", "ProgressBar", tx)
	th.set_stylebox("background", "ProgressBar", mk.call(w.call(0.15), 99, 0, 0)); th.set_stylebox("fill", "ProgressBar", mk.call(ACCENT, 99, 0, 0))
	# Zones de texte (vue) et champs (voile 10 %, rayon 9, contour d'accent au focus)
	th.set_stylebox("normal", "TextEdit", _box(_p("field"), rb, _p("edge"), 1, 0, 12)); th.set_stylebox("read_only", "TextEdit", _box(_p("field"), rb, _p("edge"), 1, 0, 12))
	th.set_stylebox("focus", "TextEdit", _box(none, rb, Color(ACCENT, 0.6), 1))
	th.set_color("font_color", "TextEdit", tx); th.set_color("font_readonly_color", "TextEdit", tx); th.set_color("caret_color", "TextEdit", tx)
	th.set_color("font_placeholder_color", "TextEdit", Color(mu, 0.9)); th.set_color("font_placeholder_color", "LineEdit", Color(mu, 0.9))
	th.set_color("selection_color", "TextEdit", Color(ACCENT, 0.35)); th.set_color("current_line_color", "TextEdit", w.call(0.03))
	th.set_font_size("font_size", "TextEdit", UI.T_BODY + 1)
	th.set_stylebox("normal", "LineEdit", UI.entry_box()); th.set_stylebox("focus", "LineEdit", UI.entry_box(true))
	var ro := UI.entry_box(); ro.bg_color = w.call(0.05); th.set_stylebox("read_only", "LineEdit", ro)
	th.set_color("font_color", "LineEdit", tx); th.set_color("caret_color", "LineEdit", tx); th.set_color("font_uneditable_color", "LineEdit", Color(tx, 0.6))
	th.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35)); th.set_font_size("font_size", "LineEdit", UI.T_BODY)
	th.set_icon("clear", "LineEdit", UI.glyph("x", Color.WHITE)); th.set_color("clear_button_color", "LineEdit", mu); th.set_color("clear_button_color_pressed", "LineEdit", tx)
	# Curseurs : piste fine, partie remplie d'accent, bouton rond
	for ty in ["HSlider", "VSlider"]:
		var hz: bool = ty == "HSlider"
		th.set_stylebox("slider", ty, mk.call(w.call(0.15), 99, 0 if hz else 3, 3 if hz else 0))
		th.set_stylebox("grabber_area", ty, mk.call(ACCENT, 99, 0 if hz else 3, 3 if hz else 0)); th.set_stylebox("grabber_area_highlight", ty, mk.call(ACCENT, 99, 0 if hz else 3, 3 if hz else 0))
		th.set_icon("grabber", ty, UI.knob_tex()); th.set_icon("grabber_highlight", ty, UI.knob_tex(true)); th.set_icon("grabber_disabled", ty, UI.knob_tex())
	# Barres de défilement fines
	var sbw := 26 if UI.touch() else 14   # largeur de la barre (doigt : facile à saisir)
	var sbm := (sbw - 8) / 2              # marge de la piste : le curseur arrondi fait 8 px de large, la zone saisissable toute la barre
	for ty in ["VScrollBar", "HScrollBar"]:
		var vt: bool = ty == "VScrollBar"
		var sm := func(c: Color) -> StyleBoxFlat:
			var sb := _box(c, 99); sb.content_margin_left = sbm if vt else 4; sb.content_margin_right = sbm if vt else 4
			sb.content_margin_top = 4 if vt else sbm; sb.content_margin_bottom = 4 if vt else sbm
			return sb
		var track: StyleBoxFlat = sm.call(w.call(0.05)); track.set_content_margin_all(0)
		track.content_margin_left = sbm if vt else 0; track.content_margin_right = sbm if vt else 0; track.content_margin_top = 0 if vt else sbm; track.content_margin_bottom = 0 if vt else sbm
		track.bg_color = none
		th.set_stylebox("scroll", ty, track); th.set_stylebox("scroll_focus", ty, track)
		th.set_stylebox("grabber", ty, sm.call(Color(tx, 0.4))); th.set_stylebox("grabber_highlight", ty, sm.call(Color(tx, 0.6))); th.set_stylebox("grabber_pressed", ty, sm.call(ACCENT))
	# Filets, infobulles
	th.set_stylebox("separator", "HSeparator", sl); th.set_constant("separation", "HSeparator", 1)
	var vl := StyleBoxLine.new(); vl.color = _p("edge"); vl.thickness = 1; vl.vertical = true
	th.set_stylebox("separator", "VSeparator", vl)
	th.set_stylebox("panel", "TooltipPanel", mk.call(Color(0.08, 0.08, 0.09, 0.92), rb, 10, 6))
	th.set_color("font_color", "TooltipLabel", Color.WHITE); th.set_font_size("font_size", "TooltipLabel", UI.T_SMALL)
	UI.extend_theme(th)
	theme = th

func _mk_btn(txt: String, w := 56, h := 56) -> Button:
	var b := Button.new(); b.text = txt
	b.custom_minimum_size = Vector2(w, UI.tp(h))
	b.focus_mode = Control.FOCUS_NONE
	return b

func _icon_btn(icon: String, variation := "Flat", w := 40, h := 36, isz := 18) -> Button:
	var b := _mk_btn("", int(UI.tp(w)), int(UI.tp(h))); b.theme_type_variation = variation
	b.icon = _ico(icon); b.add_theme_constant_override("icon_max_width", isz)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b

func _build_desktop() -> void:
	bg = TextureRect.new(); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(bg); _apply_bg()
	# Halo lumineux
	var gl := Gradient.new(); gl.colors = PackedColorArray([Color(1, 1, 1, 0.14), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new(); gt.gradient = gl; gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.25, 0.2); gt.fill_to = Vector2(0.95, 0.2); gt.width = 256; gt.height = 256
	var halo := TextureRect.new(); halo.texture = gt; halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE; halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(halo)
	var root := VBoxContainer.new()
	ui_root = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	desk = Control.new(); desk.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desk.clip_contents = true; root.add_child(desk)
	for id in set_cfg["desk"]:
		if APPS.has(id): _desk_icon(id, Vector2.ZERO)
	desk.resized.connect(_layout_icons); desk.resized.connect(_clamp_windows); _layout_icons.call_deferred()
	# Barre des tâches
	var bar := PanelContainer.new()
	bar_panel = bar
	var bs := _box(_p("bar"), 0); bs.border_width_top = 1; bs.border_color = _p("edge")
	bs.content_margin_left = 8; bs.content_margin_right = 12; bs.content_margin_top = 5; bs.content_margin_bottom = 5
	bar.add_theme_stylebox_override("panel", bs)
	root.add_child(bar)
	var bh := HBoxContainer.new(); bh.add_theme_constant_override("separation", 6); bar.add_child(bh)
	start_btn = _mk_btn("LangOS", 112, 42); start_btn.theme_type_variation = "Flat"
	start_btn.icon = _ico("start"); start_btn.add_theme_constant_override("icon_max_width", 18); start_btn.add_theme_constant_override("h_separation", 8)
	start_btn.add_theme_color_override("icon_normal_color", ACCENT); start_btn.add_theme_color_override("icon_hover_color", ACCENT)
	start_btn.add_theme_font_override("font", UI.font(700))
	start_btn.pressed.connect(_toggle_menu); bh.add_child(start_btn)
	var vs := VSeparator.new(); bh.add_child(vs)
	task_box = HBoxContainer.new(); task_box.add_theme_constant_override("separation", 4); bh.add_child(task_box)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bh.add_child(sp)
	var sb_ := _icon_btn("search", "Flat", 42, 42, 18); sb_.tooltip_text = "Recherche (Ctrl+Espace)"; sb_.pressed.connect(func(): srch.toggle()); bh.add_child(sb_)
	vd_btn = _mk_btn("1/%d" % n_vd, 56, 42); vd_btn.theme_type_variation = "Flat"
	vd_btn.tooltip_text = "Bureaux virtuels (Ctrl+Alt+Gauche/Droite)"; vd_btn.pressed.connect(_vd_menu); bh.add_child(vd_btn)
	bell_btn = _icon_btn("bell", "Flat", 42, 42, 18); bell_btn.tooltip_text = "Notifications"; bell_btn.pressed.connect(_toggle_notifs); bh.add_child(bell_btn)
	pad_btn = _icon_btn("pad", "Flat", 42, 42, 18); pad_btn.tooltip_text = "Mode pavé tactile (Flex)"; pad_btn.pressed.connect(_toggle_pad); bh.add_child(pad_btn)
	kb_btn = _icon_btn("keyboard", "Flat", 42, 42, 18); kb_btn.tooltip_text = "Clavier visuel"; kb_btn.pressed.connect(_toggle_kb); bh.add_child(kb_btn)
	cc_btn = _icon_btn("ctrl", "Flat", 42, 42, 18); cc_btn.tooltip_text = "Centre de contrôle"; cc_btn.pressed.connect(func(): ccenter.toggle(cc_btn)); bh.add_child(cc_btn)
	var tray := Control.new(); tray.set_script(load("res://apps/systray.gd")); bh.add_child(tray); tray_node = tray
	clock = Label.new(); clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.add_theme_font_size_override("font_size", UI.T_SMALL); clock.add_theme_constant_override("line_spacing", 0); bh.add_child(clock)
	clock.mouse_filter = Control.MOUSE_FILTER_STOP; clock.tooltip_text = "Notifications et calendrier"
	clock.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: _toggle_notifs())
	bar_h = 54.0
	_build_keyboard()
	get_tree().node_added.connect(_on_node_added)
	pointer = Control.new(); pointer.set_script(load("res://apps/pointer.gd")); pointer.set("mode", set_cfg["cursor"]); add_child(pointer)
	flex = PanelContainer.new(); flex.set_script(load("res://apps/flex_pad.gd")); flex.set("pointer", pointer); flex.set("gain", set_cfg["pad_speed"]); flex.set("on_zoom", Callable(self, "_set_zoom")); flex.set("get_zoom", Callable(self, "_get_zoom")); flex.visible = false; add_child(flex)
	flex.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	if OS.get_name() == "Android" and Engine.has_singleton("LangLauncher") and int(Engine.get_singleton("LangLauncher").nativeLevel()) >= 7:
		var ll := Engine.get_singleton("LangLauncher")
		ll.connect("fold_changed", _on_fold); _on_fold(str(ll.foldState()))
	get_window().files_dropped.connect(_on_files)
	get_window().content_scale_factor = set_cfg["zoom"]
	resized.connect(_update_flex)
	_update_flex.call_deferred()
	_apply_kb.call_deferred()
	_build_menu()
	fx = load("res://apps/fx.gd").new(); fx.m = self; add_child(fx)
	ccenter = load("res://apps/control_center.gd").new(); ccenter.m = self; add_child(ccenter)
	overview = load("res://apps/overview.gd").new(); overview.m = self; add_child(overview)
	dock = load("res://apps/dock.gd").new(); add_child(dock); dock.setup(self)
	prof = load("res://apps/profiles.gd").new(); prof.m = self; prof.visible = false; add_child(prof)
	srch = load("res://apps/search.gd").new(); srch.m = self; add_child(srch)
	keysc = load("res://apps/shortcuts.gd").new(); keysc.m = self; add_child(keysc)
	clip = load("res://apps/clipboard.gd").new(); clip.m = self; add_child(clip)
	cal = load("res://apps/calendar.gd").new(); cal.m = self; add_child(cal); cal.start_timer()
	_restyle_icons()

## Range les icônes en colonnes ; passe à la colonne suivante quand la hauteur est atteinte.
## Après une rotation ou un changement de zone (mode Flex) : les fenêtres restent dans le bureau, les fenêtres agrandies le remplissent.
func _clamp_windows() -> void:
	for id in wins:
		var d: Dictionary = wins[id]
		var w: PanelContainer = d["win"]
		if d["maxed"]: w.position = Vector2.ZERO; w.size = desk.size; continue
		_keep_in(w, desk.size)

## Garde une fenêtre entièrement dans le bureau (barre de titre toujours atteignable) ; taille réduite si besoin.
func _keep_in(w: Control, ds: Vector2) -> void:
	var mn := w.get_combined_minimum_size()
	w.size = Vector2(minf(maxf(w.size.x, mn.x), maxf(ds.x - 8.0, 80.0)), minf(maxf(w.size.y, mn.y), maxf(ds.y - 8.0, 80.0)))
	w.position = Vector2(clampf(w.position.x, 0.0, maxf(0.0, ds.x - w.size.x)), clampf(w.position.y, 0.0, maxf(0.0, ds.y - w.size.y)))

func _layout_icons() -> void:
	var rows := maxi(1, int((desk.size.y - 16.0) / GRID)); var cols := maxi(1, int((desk.size.x - 16.0) / GRID))
	var taken := {}; var rest := []
	var saved: Dictionary = set_cfg["icons"]
	for b in desk_icons:
		var id := str(b.get_meta("id"))
		if saved.has(id):
			var c := Vector2i(int(saved[id][0]), int(saved[id][1]))
			if c.x < cols and c.y < rows and not taken.has(c):
				taken[c] = true; b.position = Vector2(16, 16) + Vector2(c) * GRID; continue
		rest.append(b)
	var i := 0
	for b in rest:
		var c := Vector2i(i / rows, i % rows)
		while taken.has(c): i += 1; c = Vector2i(i / rows, i % rows)
		taken[c] = true; i += 1; b.position = Vector2(16, 16) + Vector2(c) * GRID

func _desk_icon(id: String, pos: Vector2) -> void:
	var b := Button.new(); b.theme_type_variation = "Flat"; b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(100, 100); b.position = pos; b.size = Vector2(100, 100)
	var v := VBoxContainer.new(); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_FULL_RECT); v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6); b.add_child(v)
	var t := TextureRect.new(); t.texture = app_icon(id); t.custom_minimum_size = Vector2(56, 56)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(t)
	var l := Label.new(); l.text = APPS[id][0]; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14); l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1); l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(l)
	b.set_meta("id", id); b.gui_input.connect(_icon_input.bind(b, id))
	b.mouse_entered.connect(func(): fx.hover(b, true)); b.mouse_exited.connect(func(): fx.hover(b, false))
	desk.add_child(b); desk_icons.append(b)

## Taille des icônes du bureau (réglage « Taille des icônes »).
func _restyle_icons() -> void:
	var s := float(set_cfg.get("isize", 56))
	for b in desk_icons:
		var t: Control = b.get_child(0).get_child(0)
		t.custom_minimum_size = Vector2(s, s)

# ---------------------------------------------------------------- Menu Démarrer

func _menu_box() -> StyleBoxFlat:
	return _box(_p("menu"), UI.rad(3), _p("edge"), 1, 28, 9)

func _build_menu() -> void:
	catcher = Control.new(); catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.visible = false
	catcher.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: _toggle_menu())
	add_child(catcher)
	menu = PanelContainer.new(); menu.visible = false
	menu.add_theme_stylebox_override("panel", _menu_box())
	add_child(menu)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 2); menu.add_child(v)
	var hm := MarginContainer.new(); v.add_child(hm)
	for k in ["left", "right"]: hm.add_theme_constant_override("margin_" + k, 9)
	hm.add_theme_constant_override("margin_top", 6); hm.add_theme_constant_override("margin_bottom", 9)
	var head := HBoxContainer.new(); head.add_theme_constant_override("separation", 9); hm.add_child(head)
	var hi := TextureRect.new(); hi.texture = _ico("start"); hi.modulate = ACCENT; hi.custom_minimum_size = Vector2(18, 18); menu_hi = hi
	hi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; hi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; head.add_child(hi)
	var ht := UI.head("LangOS"); ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(ht)
	head.add_child(UI.small("v" + VERSION))
	var android := OS.get_name() == "Android"
	var all_ids: Array = APPS.keys().filter(func(k): return (k != "android_apps" or android) and not HIDDEN.has(k) and installed(k))
	all_ids.sort_custom(func(x, y): return str(APPS[x][0]).naturalnocasecmp_to(str(APPS[y][0])) < 0)
	var search := LineEdit.new(); search.placeholder_text = "Rechercher une application…"; search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(300, 38); v.add_child(search)
	var pin_box := VBoxContainer.new(); v.add_child(pin_box)
	var pt := UI.small("Épinglées"); pin_box.add_child(pt)
	var grid := GridContainer.new(); grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4); grid.add_theme_constant_override("v_separation", 4); pin_box.add_child(grid)
	for id in set_cfg["pins"]:
		if not APPS.has(id) or not installed(id): continue
		var g := _mk_btn(APPS[id][0], 92, 88); g.theme_type_variation = "Nav"
		g.icon = app_icon(id); g.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER; g.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		g.expand_icon = false; g.add_theme_constant_override("icon_max_width", 36); g.add_theme_font_size_override("font_size", 14)
		g.clip_text = true; g.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		for k in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]: g.add_theme_color_override(k, Color.WHITE)
		g.pressed.connect(func(): _toggle_menu(); _open_app(id))
		g.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT: _app_ctx(id))
		grid.add_child(g)
	var all_box := VBoxContainer.new(); all_box.visible = false; v.add_child(all_box)
	var sc := ScrollContainer.new(); menu_sc = sc; sc.custom_minimum_size = Vector2(380, 330); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; all_box.add_child(sc)
	var lst := VBoxContainer.new(); lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL; lst.add_theme_constant_override("separation", 2); sc.add_child(lst)
	var rows := {}
	for id in all_ids:
		var b := _mk_btn(APPS[id][0], 300, 42); b.theme_type_variation = "Nav"; b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = app_icon(id); b.add_theme_constant_override("icon_max_width", 28)
		for k in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]: b.add_theme_color_override(k, Color.WHITE)
		b.pressed.connect(func(): _toggle_menu(); _open_app(id))
		b.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT: _app_ctx(id))
		lst.add_child(b); rows[id] = b
	var toggle := _mk_btn("Toutes les applications  ›", 300, 38); toggle.theme_type_variation = "Nav"; toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT; v.add_child(toggle)
	var show_all := func(on: bool):
		pin_box.visible = not on; all_box.visible = on
		toggle.text = "‹  Retour" if on else "Toutes les applications  ›"
		_place_menu()
	toggle.pressed.connect(func(): show_all.call(not all_box.visible))
	search.focus_entered.connect(func(): if set_cfg["kb"] == "osk" and not kb.visible: _toggle_kb())
	menu_search = search
	search.text_changed.connect(func(t: String):
		var q := t.strip_edges().to_lower()
		if q != "" and not all_box.visible: show_all.call(true)
		for id in rows: rows[id].visible = q == "" or str(APPS[id][0]).to_lower().contains(q))
	menu_reset = func():
		search.text = ""; for id in rows: rows[id].visible = true
		show_all.call(false)
	var sep := HSeparator.new(); sep.add_theme_constant_override("separation", 13); v.add_child(sep)
	var pb := _mk_btn("Profils d'environnement…", 300, 38); pb.theme_type_variation = "Nav"; pb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	UI.set_icon(pb, "users"); pb.add_theme_constant_override("h_separation", 19)
	pb.pressed.connect(func(): _toggle_menu(); _profiles_menu()); v.add_child(pb)
	var q := _mk_btn("Quitter", 300, 38); q.theme_type_variation = "Nav"; q.alignment = HORIZONTAL_ALIGNMENT_LEFT
	UI.set_icon(q, "power"); q.add_theme_constant_override("h_separation", 19)
	q.pressed.connect(_quit); v.add_child(q)

func _toggle_menu() -> void:
	menu.visible = not menu.visible
	catcher.visible = menu.visible
	if menu.visible:
		if menu_reset.is_valid(): menu_reset.call()
		catcher.move_to_front(); menu.move_to_front()
		if kb.visible: kb.move_to_front()
		var end := _place_menu()
		menu.position = end + Vector2(0, 14); menu.modulate.a = 0.0
		var tw := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(menu, "position", end, 0.16); tw.tween_property(menu, "modulate:a", 1.0, 0.16)
	elif is_instance_valid(menu_search): menu_search.release_focus()

## Place le menu au-dessus de la barre, dans la zone utile : en mode Flex / écran plié l'interface n'occupe que la moitié haute
## (le bas est le pavé tactile) ; si le clavier tactile est ouvert, le menu se loge au-dessus de lui. Retourne la position finale.
func _place_menu() -> Vector2:
	var bottom := ui_root.size.y - bar_h - 10.0
	if kb.visible: bottom = minf(bottom, size.y - bar_h - kb.get_combined_minimum_size().y - 10.0)
	if is_instance_valid(menu_sc):
		menu_sc.custom_minimum_size.y = clampf(bottom - 250.0, 110.0, 330.0)
	menu.size = menu.get_combined_minimum_size()
	var end := Vector2(10, maxf(8.0, bottom - menu.size.y))
	menu.position = end
	return end

## Réinitialisation usine : confirmation, puis effacement de user:// (hors modèles IA et mises à jour) et fermeture.
func _factory_confirm() -> void:
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP; add_child(dim); dim.move_to_front()
	var cc := CenterContainer.new(); cc.set_anchors_preset(Control.PRESET_FULL_RECT); dim.add_child(cc)
	var pn := PanelContainer.new(); pn.add_theme_stylebox_override("panel", _menu_box()); cc.add_child(pn)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 14); v.custom_minimum_size.x = 380; pn.add_child(v)
	v.add_child(UI.head("Réinitialiser LangOS ?"))
	var t := Label.new(); t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.text = "Tous les réglages, notes, listes, coffre-fort, profils, corbeille et fichiers seront effacés définitivement. LangOS se fermera ensuite."
	v.add_child(t)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10); h.alignment = BoxContainer.ALIGNMENT_END; v.add_child(h)
	var no := _mk_btn("Annuler", 120, 42); no.pressed.connect(dim.queue_free); h.add_child(no)
	var yes := _mk_btn("Tout effacer", 140, 42)
	yes.add_theme_color_override("font_color", _p("err")); yes.pressed.connect(_factory_reset); h.add_child(yes)

func _factory_reset() -> void:
	var keep := ["models", "update.pck", "update.cfg"]
	var d := DirAccess.open("user://")
	if d:
		for f in d.get_files(): if not keep.has(f): DirAccess.remove_absolute("user://" + f)
		for sub in d.get_directories(): if not keep.has(sub): _rm_rf("user://" + sub)
	get_tree().quit()

func _rm_rf(p: String) -> void:
	var d := DirAccess.open(p)
	if d:
		for f in d.get_files(): DirAccess.remove_absolute(p + "/" + f)
		for s in d.get_directories(): _rm_rf(p + "/" + s)
	DirAccess.remove_absolute(p)

func _quit() -> void:
	if wins.has("notepad"): _save()
	get_tree().quit()

func _build_keyboard() -> void:
	kb = PanelContainer.new()
	var ks := _box(_p("kb"), _rad() + 4, _p("edge"), 1, 24, 12); ks.corner_radius_bottom_left = 0; ks.corner_radius_bottom_right = 0
	kb.add_theme_stylebox_override("panel", ks)
	kb.visible = false
	add_child(kb)
	kb.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	var kv := VBoxContainer.new(); kv.alignment = BoxContainer.ALIGNMENT_CENTER
	kv.add_theme_constant_override("separation", 6); kb.add_child(kv)
	var act := HBoxContainer.new(); act.alignment = BoxContainer.ALIGNMENT_CENTER
	act.add_theme_constant_override("separation", 6); kv.add_child(act)
	for e in [["Tout", "all"], ["Copier", "copy"], ["Couper", "cut"], ["Coller", "paste"], ["arrow-up", "up", "Haut"], ["arrow-down", "down", "Bas"], ["arrow-left-to-line", "home", "Début de ligne"], ["arrow-right-to-line", "end", "Fin de ligne"]]:
		var ab := _mk_btn(e[0] if e.size() == 2 else "", 92 if e.size() == 2 else 56, 44); ab.pressed.connect(_clip_action.bind(e[1])); act.add_child(ab)
		if e.size() > 2: UI.set_icon(ab, e[0], 20); ab.tooltip_text = e[2]
	for r in ROWS_LOWER.size():
		var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6); kv.add_child(row)
		if r == 3:
			var sh := _mk_btn("", 80); UI.set_icon(sh, "arrow-big-up", 22); sh.tooltip_text = "Majuscule"; sh.pressed.connect(_toggle_shift); row.add_child(sh); shift_btns.append(sh)
		for c in ROWS_LOWER[r].size():
			var k := _mk_btn(ROWS_LOWER[r][c], 50, 50); k.add_theme_font_size_override("font_size", 19); k.add_theme_font_override("font", UI.font())
			k.pressed.connect(_type_key.bind(r, c))
			row.add_child(k); char_btns.append([k, r, c])
		if r == 0:
			var bs := _mk_btn("", 80, 50); UI.set_icon(bs, "delete", 22); bs.tooltip_text = "Effacer"; bs.pressed.connect(func(): _bs()); row.add_child(bs)
		if r == 1:
			var en := _mk_btn("", 80, 50); UI.set_icon(en, "corner-down-left", 22); en.tooltip_text = "Entrée"; en.pressed.connect(func(): _ins("\n")); row.add_child(en)
		if r == 2:
			var cp := _mk_btn("Maj", 80, 50); cp.pressed.connect(_toggle_caps); row.add_child(cp); shift_btns.append(cp)
	var last := HBoxContainer.new(); last.alignment = BoxContainer.ALIGNMENT_CENTER
	last.add_theme_constant_override("separation", 6); kv.add_child(last)
	for p in [["arrow-left", -1], ["arrow-right", 1]]:
		var a := _mk_btn("", 70, 50); UI.set_icon(a, p[0], 20); a.pressed.connect(_move.bind(p[1])); last.add_child(a)
	var space := _mk_btn("Espace", 420, 50); space.pressed.connect(func(): _ins(" "))
	last.add_child(space)
	var tab := _mk_btn("Tab", 70, 50); tab.pressed.connect(func(): _ins("\t")); last.add_child(tab)
	_refresh_keys()

func _target() -> Control:
	var f := get_viewport().gui_get_focus_owner()
	return f if (f is TextEdit or f is LineEdit) else null

func _ins(t: String) -> void:
	var f := _target()
	if f: f.insert_text_at_caret(t)
	else:
		var r := get_viewport().gui_get_focus_owner()
		if r and r.has_meta("remote"): r.get_meta("remote").call("send_text", t)

func _bs() -> void:
	var f := _target()
	if f == null:
		var r := get_viewport().gui_get_focus_owner()
		if r and r.has_meta("remote"): r.get_meta("remote").call("send_key", KEY_BACKSPACE)
	if f is TextEdit: f.backspace()
	elif f is LineEdit and f.caret_column > 0: f.delete_text(f.caret_column - 1, f.caret_column)

func _clip_seen() -> void:
	if clip != null: clip.capture()

## Actions presse-papiers / curseur du clavier visuel (utile sur tablette, sans Ctrl+C / Ctrl+V).
func _clip_action(a: String) -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f is RichTextLabel:
		if a == "all": f.select_all()
		elif a == "copy" and f.get_selected_text() != "": DisplayServer.clipboard_set(f.get_selected_text()); _clip_seen()
		return
	if f is TextEdit:
		match a:
			"all": f.select_all()
			"copy": f.copy(); _clip_seen()
			"cut": if f.editable: f.cut(); _clip_seen()
			"paste": if f.editable: f.paste()
			"up": f.set_caret_line(maxi(0, f.get_caret_line() - 1))
			"down": f.set_caret_line(mini(f.get_line_count() - 1, f.get_caret_line() + 1))
			"home": f.set_caret_column(0)
			"end": f.set_caret_column(f.get_line(f.get_caret_line()).length())
	elif f is LineEdit:
		match a:
			"all": f.select_all()
			"copy": f.menu_option(LineEdit.MENU_COPY); _clip_seen()
			"cut": f.menu_option(LineEdit.MENU_CUT); _clip_seen()
			"paste": f.menu_option(LineEdit.MENU_PASTE)
			"home": f.caret_column = 0
			"end": f.caret_column = f.text.length()

## Clavier : « osk » = clavier visuel de LangOS (bouton de la barre), « system » = clavier normal du système, « none » = aucun (clavier physique ou secondaire).
## Mode Flex : appareil plié à moitié (charnière horizontale) → écran du haut = bureau, écran du bas = pavé tactile.
func _on_fold(json: String) -> void:
	var d = JSON.parse_string(json)
	# Mode Flex : charnière horizontale, soit état « mi-ouvert » de la bibliothèque, soit angle de charnière entre 25° et 160°
	var want: bool = d is Dictionary and FlexLogic.is_half(d, fold_half)
	if want:
		fold_px_top = float(d["top"]); fold_px_bottom = float(d["bottom"])
	fold_gen += 1
	var gen := fold_gen
	if want == fold_half: _update_flex(); return
	# le changement d'état ne s'applique qu'après 350 ms de stabilité (évite le clignotement du pavé quand la charnière vibre)
	get_tree().create_timer(0.35).timeout.connect(func():
		if gen == fold_gen: fold_half = want; _update_flex())

func _get_zoom() -> float: return float(set_cfg["zoom"])

## Zoom de l'interface (pincement à deux doigts sur le pavé, ou réglage) : 0,5 à 2,2.
func _set_zoom(z: float) -> void:
	z = clampf(snappedf(z, 0.02), 0.5, 2.2)
	if is_equal_approx(z, float(set_cfg["zoom"])): return
	set_cfg["zoom"] = z; get_window().content_scale_factor = z
	if not zoom_save:
		zoom_save = true
		get_tree().create_timer(0.8).timeout.connect(func(): zoom_save = false; _save_settings())

func _update_flex() -> void:
	if flex == null: return
	var on: bool = (fold_half and not pad_off) or bool(set_cfg["pad"])
	if fold_half:
		var inv := get_viewport().get_final_transform().affine_inverse()
		fold_top = (inv * Vector2(0, fold_px_top)).y; fold_bottom = (inv * Vector2(0, fold_px_bottom)).y
	var top := fold_top if fold_half else size.y * 0.55
	var bot := fold_bottom if fold_half else top
	var sc := get_viewport().get_final_transform().get_scale().y
	if on and (top * sc < 200.0 or (size.y - bot) * sc < 200.0): on = false   # zone trop petite (en pixels réels, donc indépendante du zoom)
	flex.visible = on
	if pad_btn: pad_btn.modulate = ACCENT.lightened(0.3) if on else Color.WHITE; pad_btn.visible = fold_half or OS.get_name() == "Android" or bool(set_cfg["pad"]) or pad_always
	pointer.set("pad_active", on); pointer.set("pad_top", bot if on else -1.0)
	flex.set("top_h", top)
	if on:
		flex.offset_left = 0.0; flex.offset_right = 0.0; flex.offset_top = -(size.y - bot); flex.offset_bottom = 0.0
		ui_root.offset_bottom = -(size.y - top)
		var cp: Vector2 = pointer.pos
		if cp.y < 0.0: cp = Vector2(size.x * 0.5, top * 0.5)              # première apparition : au centre de la moitié haute
		pointer.move_to(cp.clamp(Vector2.ZERO, Vector2(size.x - 1.0, maxf(1.0, top - 1.0))))   # sinon on garde la place (pas de saut quand la charnière bouge)
	else:
		ui_root.offset_bottom = 0.0
	if desk != null: _clamp_windows.call_deferred()

func _on_node_added(n: Node) -> void:
	if n is LineEdit or n is TextEdit: n.virtual_keyboard_enabled = set_cfg["kb"] == "system"
	elif n is ScrollContainer and UI.touch(): n.scroll_deadzone = 10   # défilement au doigt : un petit glissé n'active pas le bouton touché

func _apply_kb() -> void:
	var mode: String = set_cfg["kb"]
	kb_btn.visible = mode == "osk"
	if mode != "osk": kb.visible = false
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is LineEdit or n is TextEdit: n.virtual_keyboard_enabled = mode == "system"
		stack.append_array(n.get_children())

var pad_btn: Button
var pad_off := false
var pad_always := true

## Bouton de la barre : active/désactive le pavé tactile (mode Flex), y compris quand l'écran est plié.
func _toggle_pad() -> void:
	if fold_half: pad_off = not pad_off
	else: set_cfg["pad"] = not bool(set_cfg["pad"]); _save_settings()
	_update_flex()

func _toggle_kb() -> void:
	kb.visible = not kb.visible
	kb.offset_top = -(bar_h + kb.get_combined_minimum_size().y)
	kb.offset_bottom = -bar_h
	if menu.visible: _place_menu()

# ---------------------------------------------------------------- Fenêtres

func _dlbl(t: String, sz := 17) -> Label:
	var l := Label.new(); l.text = t
	l.add_theme_font_size_override("font_size", sz)
	return l

func _mlbl(t: String, sz := 14) -> Label:
	var l := _dlbl(t, sz); l.theme_type_variation = "Muted"
	return l

func _open_app(id: String) -> void:
	if not installed(id): return
	if wins.has(id):
		_show(id); return
	if FOLDERS.has(id): _app_folder(id); return
	match id:
		"chromium": _app_browser()
		"chromium2": _app_browser("chromium2")
		"chromium3": _app_browser("chromium3")
		"android_apps": _app_android_apps()
		"hika": _app_hika()
		"chess": _app_chess()
		"calc": _app_tool("calc", Vector2(620, 520))
		"units": _app_tool("units", Vector2(460, 560))
		"timer": _app_tool("timer", Vector2(460, 600))
		"todo": _app_tool("todo", Vector2(440, 600))
		"vault": _app_tool("vault", Vector2(440, 520))
		"cards": _app_tool("cards", Vector2(460, 640))
		"files": _app_files()
		"trash": _app_files("trash")
		"market": _app_market()
		"scanner": _app_scanner()
		"gallery": _app_gallery()
		"terminal": _app_dev("terminal", Vector2(760, 480))
		"code": _app_dev("code", Vector2(900, 620))
		"profiles": _app_profiles()
		"clipboard": _app_clipboard()
		"devices": _app_devices()
		"sheet": _app_office("sheet", Vector2(900, 620))
		"imgview": _app_office("imgview", Vector2(860, 640))
		"pdf": _app_office("pdf", Vector2(820, 680))
		"calendar": _app_office("calendar", Vector2(860, 640))
		"notepad": _app_notepad()
		"notes": _app_notes()
		"settings": _app_settings()
		"system": _app_system()
		"translate": _app_translate()
		"dict": _app_dict()
		"messenger": _app_messenger()
		"remote": _app_remote()
		"chat": _app_chat()
		"music": _app_music()
		"soundlink": _app_soundlink()
		"update": _app_update()

func _show(id: String) -> void:
	if int(wins[id]["vd"]) != cur_vd: _goto_vd(int(wins[id]["vd"]))
	var was_hidden: bool = not wins[id]["win"].visible or wins[id]["min"]
	wins[id]["min"] = false
	fx.reset_win(wins[id])
	wins[id]["win"].visible = true
	if was_hidden and wins[id].has("shown"): fx.open_win(wins[id]["win"])
	wins[id]["win"].move_to_front()
	if kb.visible: kb.move_to_front()
	_set_active(id)

func _set_active(id: String) -> void:
	active = id
	for k in wins:
		var on: bool = k == id
		var tb: PanelContainer = wins[k]["tb"]
		wins[k]["win"].add_theme_stylebox_override("panel", _winbox(on))
		var st := _box(_p("tb_on") if on else _p("tb_off"), maxi(0, _rad() - 1))
		st.corner_radius_bottom_left = 0; st.corner_radius_bottom_right = 0
		st.content_margin_left = 10; st.content_margin_right = 9; st.content_margin_top = 8; st.content_margin_bottom = 8
		tb.add_theme_stylebox_override("panel", st)
		wins[k]["title"].modulate = Color.WHITE if on else Color(1, 1, 1, 0.55)
		var t: Button = wins[k]["task"]
		if on:
			var sb := _box(Color(_p("ov"), 0.1), UI.rad_btn()); sb.border_width_bottom = 2; sb.border_color = ACCENT
			sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 7; sb.content_margin_bottom = 5
			t.add_theme_stylebox_override("normal", sb)
		else:
			t.remove_theme_stylebox_override("normal")
	if dock != null: dock.refresh()

## Crée une fenêtre déplaçable ; renvoie son conteneur vertical.
func _make_window(id: String, _title: String, sz: Vector2, pos: Vector2) -> VBoxContainer:
	var title: String = APPS[id][0]
	var w := PanelContainer.new()
	w.add_theme_stylebox_override("panel", _winbox(true))
	# Petits écrans : la fenêtre ne dépasse pas le bureau ; sur téléphone (bureau étroit) elle s'ouvre agrandie.
	var mem = set_cfg["layout"].get(id) if _real() else null
	if mem is Array and mem.size() > 3 and float(mem[2]) > 100.0: sz = Vector2(float(mem[2]), float(mem[3])); pos = Vector2(float(mem[0]), float(mem[1]))
	var ds := desk.size if desk.size.x > 100.0 else Vector2(1280, 740)
	if mem == null and _real():
		# Cascade : chaque nouvelle fenêtre est décalée pour ne pas se superposer exactement aux autres
		var n := 0
		for k in wins:
			if int(wins[k]["vd"]) == cur_vd and wins[k]["win"].visible: n += 1
		pos += Vector2(34, 30) * float(n % 6)
	w.size = sz; w.position = pos
	desk.add_child(w)
	_keep_in(w, ds)
	var wv := VBoxContainer.new(); wv.add_theme_constant_override("separation", 0)
	w.add_child(wv)
	var tb := PanelContainer.new()
	tb.gui_input.connect(_title_input.bind(id))
	wv.add_child(tb)
	# Barre de titre façon headerbar : icône à gauche, titre gras centré, contrôles ronds à droite
	var tbh := HBoxContainer.new(); tbh.add_theme_constant_override("separation", 6); tb.add_child(tbh)
	var lead := HBoxContainer.new(); lead.custom_minimum_size.x = UI.tp(26) * 3 + 8 * 2; tbh.add_child(lead)
	var ti := TextureRect.new(); ti.texture = app_icon(id); ti.custom_minimum_size = Vector2(20, 20)
	ti.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ti.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ti.size_flags_vertical = Control.SIZE_SHRINK_CENTER; ti.mouse_filter = Control.MOUSE_FILTER_PASS; lead.add_child(ti)
	var tl := UI.heading(title); tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; tl.custom_minimum_size.x = 10
	tl.mouse_filter = Control.MOUSE_FILTER_PASS
	tbh.add_child(tl)
	var ctl := HBoxContainer.new(); ctl.add_theme_constant_override("separation", 8); tbh.add_child(ctl)
	var mn := _icon_btn("minimize", "Circular", 26, 26, 12); mn.tooltip_text = "Réduire"; mn.pressed.connect(_toggle_win.bind(id)); ctl.add_child(mn)
	var mx := _icon_btn("maximize", "Circular", 26, 26, 12); mx.tooltip_text = "Agrandir"; mx.pressed.connect(_toggle_max.bind(id)); ctl.add_child(mx)
	var cl := _icon_btn("close", "Circular", 26, 26, 12); cl.tooltip_text = "Fermer"; cl.pressed.connect(_close_win.bind(id)); ctl.add_child(cl)
	for cb in [mn, mx, cl]: cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tk := _mk_btn(title, 140, 42); tk.theme_type_variation = "Flat"; tk.add_theme_font_override("font", UI.font(500))
	tk.icon = app_icon(id); tk.add_theme_constant_override("icon_max_width", 22); tk.add_theme_constant_override("h_separation", 8)
	tk.add_theme_color_override("icon_normal_color", Color.WHITE); tk.add_theme_color_override("icon_hover_color", Color.WHITE)
	tk.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tk.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT: _win_menu(id, Vector2(tk.global_position.x, tk.global_position.y - 6.0), true))
	tk.pressed.connect(func(): if active == id and w.visible: _toggle_win(id) else: (_show(id) if w.visible else _toggle_win(id)))
	if overview != null: overview.attach(tk, id)
	task_box.add_child(tk)
	tb.set_meta("wid", id)
	wins[id] = {"win": w, "task": tk, "tb": tb, "maxed": false, "saved": Rect2(), "title": tl, "vd": restore_vd if restore_vd >= 0 else cur_vd, "min": false, "snapped": false}
	tk.visible = int(wins[id]["vd"]) == cur_vd; w.visible = tk.visible
	_show(id)
	wins[id]["shown"] = true
	fx.open_win(w)
	_clamp_windows.call_deferred()
	get_tree().create_timer(0.3).timeout.connect(_clamp_windows)
	get_tree().create_timer(0.5).timeout.connect(_save_layout)   # après l'animation d'ouverture et la mise en place du contenu
	return wv

func _title_input(ev: InputEvent, id: String) -> void:
	var d: Dictionary = wins[id]
	var w: PanelContainer = d["win"]
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed: _title_release(id)
	elif ev is InputEventMouseButton and ev.pressed:
		_show(id)
		if ev.double_click: _toggle_max(id)
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) and not d["maxed"]:
		if not d.get("dragged", false): w.add_theme_stylebox_override("panel", _winbox(true, true))   # ombre étendue pendant le déplacement
		d["dragged"] = true
		if d.get("snapped", false):
			d["snapped"] = false
			if d["saved"].size.x > 0: w.size = d["saved"].size
		var p: Vector2 = w.position + ev.relative
		w.position = Vector2(clampf(p.x, 0.0, maxf(0.0, desk.size.x - w.size.x)), clampf(p.y, 0.0, maxf(0.0, desk.size.y - w.size.y)))
		fx.show_preview(fx.zone_at(get_viewport().get_mouse_position() - desk.global_position, desk.size))

## Fin du déplacement d'une fenêtre : au bord du bureau elle s'ancre (haut = agrandie, côtés = moitié, coins = quart).
func _title_release(id: String) -> void:
	var d: Dictionary = wins[id]
	if not d.get("dragged", false): return
	d["dragged"] = false
	d["win"].add_theme_stylebox_override("panel", _winbox(active == id))
	fx.hide_preview()
	var z: String = fx.zone_at(get_viewport().get_mouse_position() - desk.global_position, desk.size)
	if z == "max":
		if not d["maxed"]: _toggle_max(id)
	elif z != "": _snap(id, z)
	else: _save_layout()

func _toggle_win(id: String) -> void:
	var w: PanelContainer = wins[id]["win"]
	if w.visible and not wins[id]["min"]:
		wins[id]["min"] = true; fx.minimize(id); _set_active("")
	else: _show(id)

func _toggle_max(id: String) -> void:
	var d: Dictionary = wins[id]
	var w: PanelContainer = d["win"]
	if d["maxed"]:
		w.position = d["saved"].position; w.size = d["saved"].size; _keep_in(w, desk.size)
	else:
		d["saved"] = Rect2(w.position, w.size)
		w.position = Vector2.ZERO; w.size = desk.size
	d["maxed"] = not d["maxed"]; d["snapped"] = false
	_save_layout()

func _close_win(id: String) -> void:
	if id == "notepad": _save()
	fx.reset_win(wins[id]); fx.close_win(wins[id]["win"]); wins[id]["task"].queue_free()
	wins.erase(id)
	_set_active("")
	_save_layout()

# ---------------------------------------------------------------- Applications

func _app_notepad() -> void:
	var wv := _make_window("notepad", "", Vector2(900, 560), Vector2(150, 20))
	title_lbl = wins["notepad"]["title"]
	var hbar := UI.header_bar(); wv.add_child(hbar)
	for e in [["Nouveau", "file-plus", _new], ["Enregistrer", "save", _save]]:
		var bn := _mk_btn(e[0], 0, UI.BTN); bn.theme_type_variation = "Flat"; UI.set_icon(bn, e[1])
		bn.pressed.connect(e[2]); UI.bar_start(hbar).add_child(bn)
	edit = TextEdit.new(); edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.virtual_keyboard_enabled = false
	edit.placeholder_text = "Écrivez ici…"
	edit.add_theme_font_size_override("font_size", set_cfg["font"])
	edit.text_changed.connect(func(): dirty = true; _update_status())
	edit.caret_changed.connect(_update_status)
	var em := MarginContainer.new(); em.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top"]: em.add_theme_constant_override("margin_" + k, 12)
	em.add_child(edit); wv.add_child(em)
	status = UI.small("")
	var sm := MarginContainer.new()
	for k in ["left", "right"]: sm.add_theme_constant_override("margin_" + k, 18)
	for k in ["top", "bottom"]: sm.add_theme_constant_override("margin_" + k, 6)
	sm.add_child(status); wv.add_child(sm)
	if FileAccess.file_exists(SAVE_PATH):
		edit.text = FileAccess.get_file_as_string(SAVE_PATH)
	dirty = false
	edit.grab_focus()
	_update_status()

## ---- Paramètres : page de préférences (groupes titrés de lignes « libellé | réglage »), gabarits de apps/ui.gd.
func _s_card(parent: Control, title: String) -> VBoxContainer:
	return UI.prefs_group(parent, title)

## Une ligne de réglage : le libellé à gauche, le contrôle à droite.
func _s_row(card: Control, text: String, ctl: Control, min_ctl := 200.0, sub := "") -> void:
	ctl.custom_minimum_size.x = maxf(ctl.custom_minimum_size.x, min_ctl)
	UI.add_row(card, UI.row(text, sub, "", ctl))

func _s_note(card: Control, text: String) -> void:
	UI.group_note(card, text)

func _s_opt(items: Array, current: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new(); o.focus_mode = Control.FOCUS_NONE; o.clip_text = true; o.fit_to_longest_item = false
	for t in items: o.add_item(t)
	o.select(maxi(0, current)); o.item_selected.connect(cb); return o

func _s_slider(lo: float, hi: float, step: float, val: float, cb: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 6)
	var s := HSlider.new(); s.min_value = lo; s.max_value = hi; s.step = step; s.value = val; s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(110, UI.tp(32)); s.size_flags_horizontal = Control.SIZE_EXPAND_FILL; s.size_flags_vertical = Control.SIZE_SHRINK_CENTER; hb.add_child(s)
	var v := UI.small(""); v.custom_minimum_size.x = 48; v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; hb.add_child(v)
	s.value_changed.connect(func(x: float): cb.call(x, v)); cb.call(val, v)
	return hb

## Rangée de pastilles (fonds, couleurs) placée en suffixe d'une ligne : alignée à droite, passe à la ligne si besoin.
func _s_flow() -> HFlowContainer:
	var sw := HFlowContainer.new(); sw.add_theme_constant_override("h_separation", 6); sw.add_theme_constant_override("v_separation", 6)
	sw.alignment = FlowContainer.ALIGNMENT_END; sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sw.size_flags_stretch_ratio = 1.5
	return sw

func _s_switch(on: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new(); c.focus_mode = Control.FOCUS_NONE; c.button_pressed = on; c.toggled.connect(cb); return c

func _app_settings() -> void:
	var wv := _make_window("settings", "", Vector2(600, 700), Vector2(200, 20))
	var page := UI.prefs_page(wv)

	# --- Affichage
	var c := _s_card(page, "Affichage")
	var sw := _s_flow()
	for i in BG_GRADS.size():
		var b := _mk_btn("", 40, 28); b.tooltip_text = "Fond %d" % (i + 1)
		var st := StyleBoxTexture.new(); st.texture = _grad_tex(i, 64, 44)
		var sth := StyleBoxTexture.new(); sth.texture = st.texture; sth.modulate_color = Color(1.25, 1.25, 1.25)
		b.add_theme_stylebox_override("normal", st); b.add_theme_stylebox_override("hover", sth); b.add_theme_stylebox_override("pressed", sth)
		b.pressed.connect(func(): _set_gradient(i))
		sw.add_child(b)
	_s_row(c, "Fond d'écran", sw, 190)
	var pick := _mk_btn("Choisir…", 0, UI.BTN); UI.set_icon(pick, "image"); pick.pressed.connect(_pick_wallpaper)
	_s_row(c, "Image de fond", pick, 0, "Une image de l'appareil à la place du dégradé")
	_s_row(c, "Thème", _s_opt(["Sombre", "Clair"], 1 if set_cfg.get("light", false) else 0, func(i: int): _set_light(i == 1)))
	_s_row(c, "Zoom de l'interface", _s_slider(0.5, 2.2, 0.05, float(set_cfg["zoom"]), func(x: float, l: Label): _set_zoom(x); l.text = "%d %%" % int(float(set_cfg["zoom"]) * 100)))
	_s_row(c, "Texte du Bloc-notes", _s_slider(14, 40, 1, float(set_cfg["font"]), func(x: float, l: Label):
		l.text = "%d" % int(x); set_cfg["font"] = int(x)
		if edit and is_instance_valid(edit): edit.add_theme_font_size_override("font_size", int(x))
		_save_settings()))

	fx.appearance_card(page)

	# --- Souris et pavé tactile
	c = _s_card(page, "Souris et pavé tactile")
	var cmodes := ["auto", "on", "off"]
	_s_row(c, "Curseur", _s_opt(["Auto (écran tactile)", "Toujours visible", "Jamais"], cmodes.find(set_cfg["cursor"]),
		func(i: int): set_cfg["cursor"] = cmodes[i]; _save_settings(); pointer.set("mode", cmodes[i]); pointer.queue_redraw()))
	_s_row(c, "Pavé tactile", _s_switch(bool(set_cfg["pad"]), func(on: bool): set_cfg["pad"] = on; _save_settings(); _update_flex()), 0)
	_s_row(c, "Vitesse du curseur", _s_slider(0.2, 2.5, 0.1, float(set_cfg["pad_speed"]), func(x: float, l: Label): set_cfg["pad_speed"] = x; l.text = "%.1f" % x; flex.set("gain", x); _save_settings()))
	_s_note(c, "Le pavé s'affiche en bas de l'écran, et tout seul quand un téléphone pliable est plié à moitié. Deux doigts qui s'écartent ou se rapprochent dessus règlent le zoom.")

	# --- Clavier
	c = _s_card(page, "Clavier")
	var kmodes := ["osk", "system", "none"]
	_s_row(c, "Clavier", _s_opt(["Visuel LangOS", "Normal du système", "Aucun"], kmodes.find(set_cfg["kb"]), func(i: int): set_cfg["kb"] = kmodes[i]; _save_settings(); _apply_kb()))
	_s_note(c, "Visuel : bouton dans la barre des tâches. Aucun : pour un clavier physique ou secondaire.")

	# --- Langues
	c = _s_card(page, "Langues")
	_s_note(c, "Utilisées par le Traducteur, le Dictionnaire et Music.")
	var names: Array = GL.map(func(l): return l[0])
	var so := _s_opt(names, GL.find_custom(func(l): return l[1] == set_cfg["src"]), func(i: int): set_cfg["src"] = GL[i][1]; _apply_langs())
	var to := _s_opt(names, GL.find_custom(func(l): return l[1] == set_cfg["tgt"]), func(i: int): set_cfg["tgt"] = GL[i][1]; _apply_langs())
	_s_row(c, "Langue d'origine", so); _s_row(c, "Traduire vers", to)
	var swp := UI.icon_btn("arrow-left-right", "Inverser les deux langues", func():
		var t: String = set_cfg["src"]; set_cfg["src"] = set_cfg["tgt"]; set_cfg["tgt"] = t
		so.select(GL.find_custom(func(l): return l[1] == set_cfg["src"])); to.select(GL.find_custom(func(l): return l[1] == set_cfg["tgt"])); _apply_langs(), "")
	_s_row(c, "Inverser les deux langues", swp, 0)

	# --- Android : écran d'accueil
	if OS.get_name() == "Android" and Engine.has_singleton("LangLauncher"):
		c = _s_card(page, "Écran d'accueil")
		var hb := _mk_btn("Choisir", 0, UI.BTN); hb.pressed.connect(func(): Engine.get_singleton("LangLauncher").chooseHome())
		_s_row(c, "Écran d'accueil", hb, 0, "Android affiche la liste des écrans d'accueil : choisis LangOS pour l'utiliser, ou ton ancien pour y revenir.")

	# --- Serveur de traduction
	c = _s_card(page, "Serveur de traduction (Ollama)")
	var le := LineEdit.new(); le.text = set_cfg["ollama"]; le.virtual_keyboard_enabled = false; le.placeholder_text = "http://127.0.0.1:11434"
	le.text_changed.connect(func(t: String): set_cfg["ollama"] = t.strip_edges().rstrip("/"); _save_settings())
	_s_row(c, "Adresse", le, 240)
	_s_note(c, "Sur téléphone : adresse d'un PC qui fait tourner Ollama, par exemple http://192.168.1.20:11434. Sinon le Traducteur utilise le modèle sur l'appareil.")

	# --- À propos
	c = _s_card(page, "À propos")
	UI.add_row(c, UI.row("LangOS", "", "", UI.muted(UI.label("Version %s" % VERSION))))
	UI.add_row(c, UI.row("Police et icônes", "Inter (licence OFL) et Lucide (licence ISC)"))

	# --- Réinitialisation
	c = _s_card(page, "Réinitialisation")
	var rb := _mk_btn("Réinitialiser…", 150, 40); rb.pressed.connect(_factory_confirm)
	_s_row(c, "Réinitialisation usine", rb, 150, "Efface réglages, notes, coffre-fort, profils et fichiers de LangOS.")

const MARKET_DESC := {
	"translate": "Traduis du texte hors ligne avec un modèle local.", "dict": "Dictionnaire intégré avec définitions.", "music": "Lecteur de musique de ta bibliothèque.",
	"chess": "Joue aux échecs contre l'ordinateur.", "hika": "Jeu de combat en ligne Hikabrain.",
	"chromium": "Navigateur web avec onglets, favoris, historique et bloqueur de pubs.", "notes": "Prends des notes rapides, classées et recherchables.",
	"terminal": "Terminal de commandes intégré.", "code": "Éditeur de code avec coloration syntaxique.", "profiles": "Profils d'environnement : fenêtres et applis par contexte.",
	"clipboard": "Historique du presse-papiers.", "devices": "Liste des périphériques connectés.", "messenger": "Messagerie instantanée.",
	"remote": "Contrôle un autre ordinateur à distance.", "chat": "Discute avec une IA.", "soundlink": "Partage du son entre appareils.",
	"sheet": "Tableur : cellules, formules et calculs.", "imgview": "Visionneuse d'images.", "pdf": "Lecteur de documents PDF.", "calendar": "Agenda et rendez-vous.", "gallery": "Photos et vidéos de ton appareil en grille, avec visionneuse.", "scanner": "Photographie un document : bords détectés, page redressée, texte net, export PDF.",
	"calc": "Calculatrice simple et scientifique.", "units": "Convertis longueurs, poids, devises et plus.", "timer": "Minuteur et chronomètre.",
	"todo": "Listes de tâches.", "vault": "Coffre-fort chiffré pour tes mots de passe.", "cards": "Cartes mémoire pour réviser.", "android_apps": "Lance les applis Android installées.",
}

## Market façon Play Store : recherche, catégories, cartes, page de détail.
func _app_gallery() -> void:
	var wv := _make_window("gallery", "", Vector2(860, 640), Vector2(160, 20))
	var c := Control.new(); c.set_script(load("res://apps/gallery.gd")); c.m = self
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(minf(560.0, maxf(280.0, desk.size.x - 16.0)), 420); c.clip_contents = true
	wv.add_child(c)

func _app_scanner() -> void:
	var wv := _make_window("scanner", "", Vector2(760, 700), Vector2(170, 20))
	var c := Control.new(); c.set_script(load("res://apps/scanner.gd")); c.m = self
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(minf(560.0, maxf(280.0, desk.size.x - 16.0)), 460); c.clip_contents = true
	wv.add_child(c)

func _app_market() -> void:
	var wv := _make_window("market", "", Vector2(620, 680), Vector2(180, 30))
	var cat_of := {}
	var cats := ["Tout", "Installées"]
	var inside := []
	for f in FOLDERS:
		inside += FOLDERS[f]; cats.append(str(APPS[f][0]))
		for id in FOLDERS[f]: cat_of[id] = str(APPS[f][0])
	var ids: Array = APPS.keys().filter(func(k): return not FOLDERS.has(k) and not CORE.has(k) and not HIDDEN.has(k) and (k != "android_apps" or OS.get_name() == "Android"))
	for id in ids: if not cat_of.has(id): cat_of[id] = "Autres"
	if ids.any(func(k): return cat_of[k] == "Autres"): cats.append("Autres")
	ids.sort_custom(func(x, y): return str(APPS[x][0]).naturalnocasecmp_to(str(APPS[y][0])) < 0)
	var st := {"cat": "Tout", "q": "", "detail": ""}
	var top := MarginContainer.new(); for k in ["left", "right", "top"]: top.add_theme_constant_override("margin_" + k, 12)
	wv.add_child(top)
	var tv := VBoxContainer.new(); tv.add_theme_constant_override("separation", 8); top.add_child(tv)
	var search := LineEdit.new(); search.placeholder_text = "Rechercher dans le Market"; search.clear_button_enabled = true
	search.custom_minimum_size.y = 40; tv.add_child(search)
	var chip_sc := ScrollContainer.new(); chip_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; tv.add_child(chip_sc)
	var chips := HBoxContainer.new(); chips.add_theme_constant_override("separation", 6); chip_sc.add_child(chips)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var sm := MarginContainer.new(); sm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "bottom", "top"]: sm.add_theme_constant_override("margin_" + k, 12)
	wv.add_child(sc); sc.add_child(sm)
	var body := VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 10); sm.add_child(body)
	var action_btn := func(id: String, w: float) -> Button:
		var b := _mk_btn("", w, 38)
		b.text = "Ouvrir" if installed(id) else "Installer"
		b.theme_type_variation = "" if installed(id) else "FlatOn"
		b.pressed.connect(func():
			if installed(id): _open_app(id)
			else: _market_toggle(id); st["r"].call_deferred())
		return b
	var icon_of := func(id: String, sz: float) -> TextureRect:
		var t := TextureRect.new(); t.texture = app_icon(id); t.custom_minimum_size = Vector2(sz, sz)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return t
	var render := func():
		for c in body.get_children(): c.queue_free()
		for c in chips.get_children(): c.queue_free()
		chip_sc.visible = st["detail"] == "" and st["q"] == ""
		for cname in cats:
			var cb := _mk_btn(cname, 0, 34); cb.theme_type_variation = "FlatOn" if st["cat"] == cname else "Flat"
			cb.pressed.connect(func(): st["cat"] = cname; st["r"].call_deferred()); chips.add_child(cb)
		if st["detail"] != "":
			var id: String = st["detail"]
			var back := _mk_btn("‹  Retour", 110, 36); back.theme_type_variation = "Flat"; back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			back.pressed.connect(func(): st["detail"] = ""; st["r"].call_deferred()); body.add_child(back)
			var hd := HBoxContainer.new(); hd.add_theme_constant_override("separation", 16); body.add_child(hd)
			hd.add_child(icon_of.call(id, 84))
			var hv := VBoxContainer.new(); hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hd.add_child(hv)
			hv.add_child(UI.head(str(APPS[id][0]))); hv.add_child(UI.small(cat_of[id]))
			var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 8); body.add_child(hb)
			hb.add_child(action_btn.call(id, 140))
			if installed(id):
				var un := _mk_btn("Désinstaller", 140, 38); un.pressed.connect(func(): _market_toggle(id); st["r"].call_deferred()); hb.add_child(un)
			var d := Label.new(); d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; d.text = MARKET_DESC.get(id, "Application LangOS."); body.add_child(d)
			return
		var q: String = st["q"].to_lower()
		var shown := ids.filter(func(k):
			if q != "": return str(APPS[k][0]).to_lower().contains(q)
			if st["cat"] == "Installées": return installed(k)
			return st["cat"] == "Tout" or cat_of[k] == st["cat"])
		if shown.is_empty(): body.add_child(UI.small("Aucune application.")); return
		var grid := GridContainer.new(); grid.columns = 2; grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 10); body.add_child(grid)
		for id in shown:
			var card := PanelContainer.new(); card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.add_theme_stylebox_override("panel", _box(_p("menu"), UI.rad(), _p("edge"), 1, 12, 10))
			card.mouse_filter = Control.MOUSE_FILTER_PASS
			var cv := VBoxContainer.new(); cv.add_theme_constant_override("separation", 8); card.add_child(cv)
			var ch := HBoxContainer.new(); ch.add_theme_constant_override("separation", 10); cv.add_child(ch)
			ch.add_child(icon_of.call(id, 48))
			var nv := VBoxContainer.new(); nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; nv.mouse_filter = Control.MOUSE_FILTER_IGNORE; ch.add_child(nv)
			var nl := Label.new(); nl.text = str(APPS[id][0]); nl.clip_text = true; nl.mouse_filter = Control.MOUSE_FILTER_IGNORE; nv.add_child(nl)
			nv.add_child(UI.small(cat_of[id]))
			ch.add_child(UI.icon_btn("info", "Détails", func(): st["detail"] = id; st["r"].call_deferred(), "Flat", 40))
			cv.add_child(action_btn.call(id, 0))
			grid.add_child(card)
	st["r"] = render
	search.text_changed.connect(func(t: String): st["q"] = t.strip_edges(); st["detail"] = ""; st["r"].call_deferred())
	render.call()

func _market_toggle(id: String) -> void:
	if installed(id):
		set_cfg["installed"].erase(id); set_cfg["pins"].erase(id)
		if set_cfg["desk"].has(id): _desk_toggle(id)
		if wins.has(id): _close_win(id)
	else:
		set_cfg["installed"].append(id)
	_save_settings(); _rebuild_menu()

func _app_system() -> void:
	var wv := _make_window("system", "", Vector2(520, 520), Vector2(260, 80))
	var page := UI.prefs_page(wv)
	var gv := Engine.get_version_info()
	var mem := OS.get_memory_info()
	var rows := [
		["Application", "Bloc-notes v" + VERSION, "app-window"],
		["Système", "%s %s" % [OS.get_name(), OS.get_version()], "monitor"],
		["Moteur", "Godot %s" % gv["string"], "package"],
		["Processeur", "%s (%d cœurs)" % [OS.get_processor_name(), OS.get_processor_count()], "server"],
		["Carte graphique", RenderingServer.get_video_adapter_name(), "image"],
		["Mémoire", "%d Mo" % (int(mem.get("physical", 0)) / 1048576) if int(mem.get("physical", 0)) > 0 else "inconnue", "hard-drive"],
		["Écran", "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y], "maximize-2"],
		["Données", ProjectSettings.globalize_path("user://"), "folder"],
	]
	var c := UI.prefs_group(page, "Cet appareil")
	for r in rows: UI.add_row(c, UI.row(r[0], str(r[1]), r[2]))

func _app_update() -> void:
	var wv := _make_window("update", "", Vector2(480, 240), Vector2(280, 100))
	var m := MarginContainer.new(); m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 18)
	wv.add_child(m)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 14); m.add_child(v)
	v.add_child(_dlbl("Version installée : " + VERSION, 20))
	upd_lbl = _dlbl("", 16); upd_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(upd_lbl)
	upd_btn = _mk_btn("Vérifier", 240, 46); upd_btn.theme_type_variation = "Accent"; upd_btn.pressed.connect(_do_update); v.add_child(upd_btn)
	_set_upd(upd_lbl_text, upd_btn_text)
	if upd_http == null or upd_btn_text == "Vérifier": _check_update()

# ---------------------------------------------------------------- Traducteur (modèle local, sans API)

const GL := [["Français", "fra", "French"], ["English", "eng", "English"], ["Español", "spa", "Spanish"], ["Deutsch", "deu", "German"],
	["Italiano", "ita", "Italian"], ["Português", "por", "Portuguese"], ["Nederlands", "nld", "Dutch"], ["日本語", "jpn", "Japanese"]]
var music_node: Control
var desk_icons: Array = []
var lp_active := false
var lp_pos := Vector2.ZERO
var lp_t := 0
var ctx_menu: PanelContainer
var ctx_catcher: Control
var ctx_target: Control
var tr_pair: Label

func _gname(code: String, i := 0) -> String:
	for l in GL:
		if l[1] == code: return l[i if i != 2 else 2] if i != 1 else l[0]
	return code

func _pair_text() -> String:
	return "%s  →  %s" % [_gname(set_cfg["src"], 1), _gname(set_cfg["tgt"], 1)]

func _apply_langs() -> void:
	_save_settings()
	if wins.has("translate") and is_instance_valid(tr_pair): tr_pair.text = _pair_text()
	if wins.has("dict"): _dic_load()
	if wins.has("music") and is_instance_valid(music_node): music_node.call("set_langs", set_cfg["src"], set_cfg["tgt"])
const LOCAL_URL := "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"
const LOCAL_FILE := "user://models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
const LOCAL_MIN := 1000000000
var tr_http: HTTPRequest
var tr_dl: HTTPRequest
var tr_llm: Object
var tr_engine: OptionButton
var tr_srv: HBoxContainer
var tr_timer: Timer
var tr_tags: HTTPRequest
var tr_model: OptionButton
var tr_in: TextEdit
var tr_out: TextEdit
var tr_status: Label
var tr_btn: Button
var tr_t0 := 0

func _app_translate() -> void:
	var wv := _make_window("translate", "", Vector2(800, 520), Vector2(190, 36))
	var m := MarginContainer.new(); m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 14)
	wv.add_child(m)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); m.add_child(v)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); v.add_child(row)
	tr_pair = _dlbl(_pair_text(), 18)
	var sw := UI.icon_btn("arrow-left-right", "Inverser les langues", _tr_swap, "", 40)
	row.add_child(tr_pair); row.add_child(sw)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(sp)
	tr_engine = OptionButton.new(); tr_engine.focus_mode = Control.FOCUS_NONE
	tr_engine.add_item("Sur l'appareil"); tr_engine.add_item("Serveur Ollama")
	if set_cfg["engine"] < 0: set_cfg["engine"] = 0 if OS.has_feature("android") else 1
	tr_engine.select(set_cfg["engine"])
	tr_engine.item_selected.connect(func(i: int): set_cfg["engine"] = i; _save_settings(); _tr_engine_changed())
	row.add_child(tr_engine)
	tr_model = OptionButton.new(); tr_model.focus_mode = Control.FOCUS_NONE
	tr_model.item_selected.connect(func(i: int): set_cfg["model"] = tr_model.get_item_text(i); _save_settings())
	row.add_child(tr_model)
	var srv := HBoxContainer.new(); srv.add_theme_constant_override("separation", 8); v.add_child(srv); tr_srv = srv
	srv.add_child(_mlbl("Serveur"))
	var le := LineEdit.new(); le.text = set_cfg["ollama"]; le.virtual_keyboard_enabled = false
	le.placeholder_text = "http://IP-du-PC:11434"; le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srv.add_child(le)
	var cn := _mk_btn("Connecter", 120, 40); cn.theme_type_variation = "Flat"
	cn.pressed.connect(func():
		var t := le.text.strip_edges().rstrip("/")
		if not t.begins_with("http"): t = "http://" + t
		if not ":" in t.substr(7): t += ":11434"
		le.text = t; set_cfg["ollama"] = t; _save_settings(); _tr_models())
	srv.add_child(cn)
	var tx := HBoxContainer.new(); tx.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tx.add_theme_constant_override("separation", 10); v.add_child(tx)
	tr_in = TextEdit.new(); tr_out = TextEdit.new()
	for t in [tr_in, tr_out]:
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; t.virtual_keyboard_enabled = false
		t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; t.add_theme_font_size_override("font_size", 20); tx.add_child(t)
	tr_in.placeholder_text = "Texte à traduire…"; tr_out.editable = false; tr_out.placeholder_text = "Traduction"
	var bt := HBoxContainer.new(); bt.add_theme_constant_override("separation", 8); v.add_child(bt)
	tr_status = _mlbl("", 14); tr_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; bt.add_child(tr_status)
	var cp := _mk_btn("Copier", 90, 42); cp.theme_type_variation = "Flat"
	cp.pressed.connect(func(): DisplayServer.clipboard_set(tr_out.text)); bt.add_child(cp)
	tr_btn = _mk_btn("Traduire", 130, 42); tr_btn.theme_type_variation = "Accent"
	tr_btn.pressed.connect(_tr_translate); bt.add_child(tr_btn)
	tr_in.grab_focus()
	_tr_engine_changed()

func _tr_engine_changed() -> void:
	var local: bool = set_cfg["engine"] == 0
	tr_srv.visible = not local; tr_model.visible = not local
	tr_btn.text = "Traduire"; tr_btn.disabled = false
	if local: _tr_local_check()
	else: _tr_models()

func _tr_local_check() -> void:
	if not ClassDB.class_exists("GDLlama"):
		tr_status.text = "Moteur local indisponible sur cet appareil : utiliser « Serveur Ollama »."
		tr_btn.disabled = true
	elif not _tr_model_ok():
		tr_status.text = "Modèle local à télécharger une seule fois (≈ 1,1 Go, Wi-Fi conseillé)."
		tr_btn.text = "Télécharger le modèle"
	else:
		tr_status.text = "Prêt (sur l'appareil, hors ligne)."

func _tr_model_ok() -> bool:
	if not FileAccess.file_exists(LOCAL_FILE): return false
	var f := FileAccess.open(LOCAL_FILE, FileAccess.READ)
	return f != null and f.get_length() > LOCAL_MIN

func _tr_download() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://models"))
	if tr_dl == null:
		tr_dl = HTTPRequest.new(); tr_dl.download_chunk_size = 1048576; tr_dl.timeout = 0.0; add_child(tr_dl)
		tr_dl.request_completed.connect(_on_tr_dl)
		tr_timer = Timer.new(); tr_timer.wait_time = 0.5; add_child(tr_timer)
		tr_timer.timeout.connect(func():
			if is_instance_valid(tr_status) and tr_dl.get_body_size() > 0:
				tr_status.text = "Téléchargement du modèle : %d %%  (%d / %d Mo)" % [100 * tr_dl.get_downloaded_bytes() / tr_dl.get_body_size(), tr_dl.get_downloaded_bytes() / 1048576, tr_dl.get_body_size() / 1048576])
	tr_dl.download_file = ProjectSettings.globalize_path("user://models/model.tmp")
	tr_btn.disabled = true; tr_status.text = "Téléchargement du modèle…"
	tr_timer.start()
	var err := tr_dl.request(LOCAL_URL)
	if err != OK: tr_status.text = "Téléchargement impossible (réseau ?)."; tr_btn.disabled = false; tr_timer.stop()

func _on_tr_dl(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	tr_timer.stop()
	var tmp := "user://models/model.tmp"
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200 and FileAccess.file_exists(tmp)
	if ok:
		var f := FileAccess.open(tmp, FileAccess.READ); ok = f != null and f.get_length() > LOCAL_MIN
	if not ok:
		DirAccess.remove_absolute(tmp)
		if is_instance_valid(tr_status): tr_status.text = "Échec du téléchargement, réessayer."; tr_btn.disabled = false
		return
	DirAccess.rename_absolute(tmp, LOCAL_FILE)
	notify("Traduction", "Modèle local téléchargé.")
	if is_instance_valid(tr_status): _tr_engine_changed()

func _tr_local_translate(text: String) -> void:
	if tr_llm == null:
		tr_llm = ClassDB.instantiate("GDLlama")
		add_child(tr_llm)
		tr_llm.set("model_path", ProjectSettings.globalize_path(LOCAL_FILE))
		tr_llm.set("n_predict", 400); tr_llm.set("n_ctx", 2048)
		tr_llm.set("should_output_prompt", false); tr_llm.set("should_output_special", false)
		tr_llm.set("n_threads", maxi(2, OS.get_processor_count() / 2))
		tr_llm.connect("generate_text_finished", _on_tr_local_done)
	var from_part := "from %s " % _gname(set_cfg["src"], 2)
	var sys := "You are a translation engine. Translate the user's text %sinto %s. Output ONLY the translation: no notes, no quotes, no explanations." % [from_part, _gname(set_cfg["tgt"], 2)]
	var prompt := "<|im_start|>system\n%s<|im_end|>\n<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n" % [sys, text]
	tr_btn.disabled = true; tr_status.text = "Traduction sur l'appareil (le premier appel charge le modèle)…"
	tr_t0 = Time.get_ticks_msec()
	tr_llm.call("run_generate_text", prompt, "", "")

func _on_tr_local_done(t: String) -> void:
	if not is_instance_valid(tr_out): return
	tr_btn.disabled = false
	var out := t.get_slice("<|im_end|>", 0).strip_edges()
	tr_out.text = out
	tr_status.text = "%.1f s — traduit sur l'appareil" % ((Time.get_ticks_msec() - tr_t0) / 1000.0)

func _tr_swap() -> void:
	var s: String = set_cfg["src"]; set_cfg["src"] = set_cfg["tgt"]; set_cfg["tgt"] = s
	var t := tr_in.text; tr_in.text = tr_out.text; tr_out.text = t
	_apply_langs()

func _tr_models() -> void:
	if tr_tags == null: tr_tags = HTTPRequest.new(); tr_tags.timeout = 5.0; add_child(tr_tags)
	tr_status.text = "Connexion au modèle local…"
	if not tr_tags.request_completed.is_connected(_on_tr_tags): tr_tags.request_completed.connect(_on_tr_tags)
	tr_tags.request(set_cfg["ollama"] + "/api/tags")

func _on_tr_tags(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if not is_instance_valid(tr_model): return
	var info = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if not (info is Dictionary) or not info.has("models"):
		tr_status.text = ("Sur téléphone, « Serveur » = adresse du PC (ex. http://192.168.1.20:11434), Ollama lancé avec OLLAMA_HOST=0.0.0.0, même Wi-Fi." \
			if OS.has_feature("android") else "Modèle local introuvable : lancer « ollama serve » ou régler le serveur ci-dessus.")
		tr_btn.disabled = true; return
	tr_model.clear()
	var names: Array = []
	for mm in info["models"]: names.append(str(mm["name"]))
	names.sort_custom(func(a, b): return _tr_rank(a) < _tr_rank(b))
	for n in names: tr_model.add_item(n)
	var pick := names.find(set_cfg["model"])
	tr_model.select(maxi(pick, 0))
	tr_btn.disabled = names.is_empty()
	tr_status.text = "Prêt (local, hors ligne)." if not names.is_empty() else "Aucun modèle : « ollama pull gemma3:4b »."

## Petits modèles rapides en premier ; les modèles « raisonnement » en dernier.
func _tr_rank(n: String) -> int:
	if n.begins_with("gemma3:4b"): return 0
	if n.begins_with("llama3.2:3b"): return 1
	if n.begins_with("gemma"): return 2
	if n.begins_with("qwen3") or "coder" in n or "vision" in n: return 9
	return 5

func _tr_translate() -> void:
	if set_cfg["engine"] == 0:
		if not _tr_model_ok(): _tr_download(); return
		var lt := tr_in.text.strip_edges()
		if not lt.is_empty(): _tr_local_translate(lt)
		return
	var text := tr_in.text.strip_edges()
	if text.is_empty() or tr_model.item_count == 0: return
	if tr_http == null: tr_http = HTTPRequest.new(); tr_http.timeout = 180.0; add_child(tr_http)
	var from_part := "from %s " % _gname(set_cfg["src"], 2)
	var sys := "You are a translation engine. Translate the user's text %sinto %s. Output ONLY the translation: no notes, no quotes, no explanations." % [from_part, _gname(set_cfg["tgt"], 2)]
	var body := {"model": tr_model.get_item_text(tr_model.selected), "stream": false, "keep_alive": "10m",
		"options": {"temperature": 0.1, "num_predict": 1024},
		"messages": [{"role": "system", "content": sys}, {"role": "user", "content": text}]}
	tr_btn.disabled = true; tr_status.text = "Traduction…"; tr_t0 = Time.get_ticks_msec()
	if not tr_http.request_completed.is_connected(_on_tr_done): tr_http.request_completed.connect(_on_tr_done)
	tr_http.request(set_cfg["ollama"] + "/api/chat", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))

func _on_tr_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if not is_instance_valid(tr_out): return
	tr_btn.disabled = false
	var info = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if not (info is Dictionary) or not info.has("message"):
		tr_status.text = "Échec de la traduction (serveur local arrêté ?)."; return
	var rx := RegEx.create_from_string("(?s)<think>.*?</think>")
	tr_out.text = rx.sub(str(info["message"]["content"]), "", true).strip_edges()
	tr_status.text = "%.1f s — traduit localement" % ((Time.get_ticks_msec() - tr_t0) / 1000.0)

# ---------------------------------------------------------------- RemoteDesk (app intégrée)

func _app_remote() -> void:
	var wv := _make_window("remote", "", Vector2(940, 620), Vector2(130, 18))
	var rd := Control.new()
	rd.set_script(load("res://apps/remotedesk.gd"))
	rd.size_flags_vertical = Control.SIZE_EXPAND_FILL; rd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rd.custom_minimum_size = Vector2(320, 360); rd.clip_contents = true
	wv.add_child(rd)

# ---------------------------------------------------------------- Messenger (app intégrée)

func _app_messenger() -> void:
	var wv := _make_window("messenger", "", Vector2(960, 620), Vector2(120, 20))
	var ms := Control.new()
	ms.set_script(load("res://apps/messenger.gd"))
	ms.size_flags_vertical = Control.SIZE_EXPAND_FILL; ms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ms.custom_minimum_size = Vector2(320, 360); ms.clip_contents = true
	wv.add_child(ms)

# ---------------------------------------------------------------- Chat IA (app + overlay « - »)

var chat_core: ChatCore
var chat_ov: ChatOverlay
var ctl := PacketPeerUDP.new()

func _setup_chat() -> void:
	chat_core = ChatCore.new(); add_child(chat_core)
	if OS.has_feature("mobile"): return
	chat_ov = ChatOverlay.new(); chat_ov.core = chat_core; add_child(chat_ov)
	# Canal de commande local : le raccourci global du système envoie « toggle-chat » (voir langos-chat.sh)
	var cport := 4360
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ctl-port="): cport = a.get_slice("=", 1).to_int()
	var be := ctl.bind(cport, "127.0.0.1")
	if be != OK: push_warning("Port 4360 occupé : raccourci global du chat indisponible (%d)" % be)

func _poll_ctl() -> void:
	while ctl.is_bound() and ctl.get_available_packet_count() > 0:
		var cmd := ctl.get_packet().get_string_from_utf8().strip_edges()
		if cmd == "toggle-chat" and chat_ov: chat_ov.toggle()
		elif cmd == "show-chat" and chat_ov: chat_ov.show_chat()

func _app_chat() -> void:
	var wv := _make_window("chat", "", Vector2(820, 600), Vector2(160, 20))
	var c := Control.new()
	c.set_script(load("res://apps/chat.gd"))
	c.set("core", chat_core)
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(320, 360); c.clip_contents = true
	wv.add_child(c)

# ---------------------------------------------------------------- Music (app intégrée)

func _app_music() -> void:
	var big := Vector2(minf(1500.0, desk.size.x - 24.0), minf(900.0, desk.size.y - 16.0))
	var wv := _make_window("music", "", big, Vector2(12, 8))
	var mu := Control.new()
	mu.set_script(load("res://apps/music.gd"))
	mu.set("ollama_url", set_cfg["ollama"]); mu.set("src", set_cfg["src"]); mu.set("tgt", set_cfg["tgt"]); music_node = mu
	mu.size_flags_vertical = Control.SIZE_EXPAND_FILL; mu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mu.custom_minimum_size = Vector2(320, 360); mu.clip_contents = true
	wv.add_child(mu)

# ---------------------------------------------------------------- Dossiers et Échecs

func _app_folder(fid: String) -> void:
	var wv := _make_window(fid, "", Vector2(420, 300), Vector2(200 + randi() % 60, 60 + randi() % 40))
	var g := GridContainer.new(); g.columns = 3; g.size_flags_vertical = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 8); g.add_theme_constant_override("v_separation", 8)
	var m := MarginContainer.new(); m.add_theme_constant_override("margin_left", 12); m.add_theme_constant_override("margin_top", 12)
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL; m.add_child(g); wv.add_child(m)
	for id in FOLDERS[fid]:
		if not installed(id): continue
		var b := Button.new(); b.theme_type_variation = "Flat"; b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(120, 100)
		var v := VBoxContainer.new(); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_preset(Control.PRESET_FULL_RECT); v.alignment = BoxContainer.ALIGNMENT_CENTER; b.add_child(v)
		var t := TextureRect.new(); t.texture = app_icon(id); t.custom_minimum_size = Vector2(56, 56)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(t)
		var l := Label.new(); l.text = APPS[id][0]; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(l)
		b.pressed.connect(_open_app.bind(id)); g.add_child(b)

## Lance Chromium (ou, à défaut, Chrome / Chromium Flatpak) hors de LangOS ; sur Android, le navigateur par défaut.
func _launch_browser() -> void:
	if OS.get_name() == "Android": OS.shell_open("https://www.google.com"); return
	var sh := "for b in chromium chromium-browser google-chrome google-chrome-stable; do command -v $b >/dev/null 2>&1 && exec $b; done; flatpak info org.chromium.Chromium >/dev/null 2>&1 && exec flatpak run org.chromium.Chromium; exit 127"
	var args := ["-c", sh]
	var cmd := "sh"
	if FileAccess.file_exists("/.flatpak-info"): cmd = "flatpak-spawn"; args = ["--host", "sh", "-c", sh]   # Godot lancé en Flatpak
	if OS.create_process(cmd, args) < 0: status.text = "Impossible de lancer Chromium."
	else: status.text = "Chromium lancé (s'il est installé : sudo apt install chromium)."

func _app_android_apps() -> void:
	var big := Vector2(minf(900.0, desk.size.x - 24.0), minf(640.0, desk.size.y - 16.0))
	var wv := _make_window("android_apps", "", big, Vector2(30, 12))
	var c := Control.new(); c.set_script(load("res://apps/android_apps.gd"))
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(320, 360); c.clip_contents = true; wv.add_child(c)

## Nouvelle fenêtre de navigation (jusqu'à 3 fenêtres) ; sous Android un seul WebView existe : un onglet est ouvert à la place.
func _open_browser_window() -> void:
	for id in ["chromium2", "chromium3"]:
		if not wins.has(id): _app_browser(id); return
	notify("Navigateur", "Nombre maximal de fenêtres atteint")

func _app_browser(id := "chromium") -> void:
	var big := Vector2(minf(1100.0, desk.size.x - 24.0), minf(700.0, desk.size.y - 16.0))
	var wv := _make_window(id, "", big, Vector2(20 + (0 if id == "chromium" else 40), 10 + (0 if id == "chromium" else 30)))
	var br := Control.new(); br.set_script(load("res://apps/browser.gd")); br.set("external", Callable(self, "_launch_browser")); br.set_meta("win_id", id)
	br.size_flags_vertical = Control.SIZE_EXPAND_FILL; br.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.custom_minimum_size = Vector2(320, 360); br.clip_contents = true; wv.add_child(br)

func _app_hika() -> void:
	var big := Vector2(minf(1100.0, desk.size.x - 24.0), minf(700.0, desk.size.y - 16.0))
	var wv := _make_window("hika", "", big, Vector2(12, 8))
	var h := Control.new(); h.set_script(load("res://apps/hika_host.gd"))
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL; h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.custom_minimum_size = Vector2(320, 360); wv.add_child(h)

## Petits outils (dossier Outils) : un script apps/tool_<id>.gd par outil.
func _app_tool(id: String, sz: Vector2) -> void:
	var wv := _make_window(id, "", sz + Vector2(0, 60), Vector2(200 + randi() % 80, 20 + randi() % 40))
	var c := Control.new()
	c.set_script(load("res://apps/tool_%s.gd" % id))
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(minf(sz.x, maxf(280.0, desk.size.x - 16.0)), sz.y); c.clip_contents = true
	wv.add_child(c)

func _app_files(wid := "files") -> void:
	var wv := _make_window(wid, "", Vector2(860, 600), Vector2(160, 20))
	var c := Control.new(); c.set_script(load("res://apps/files.gd")); c.main = self
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(minf(560.0, maxf(280.0, desk.size.x - 16.0)), 400); c.clip_contents = true
	wv.add_child(c)
	if wid == "trash": c._go("user://trash", 0)

func _app_dev(id: String, sz: Vector2) -> void:
	var wv := _make_window(id, "", sz, Vector2(200, 30))
	var c := Control.new(); c.set_script(load("res://apps/terminal.gd" if id == "terminal" else "res://apps/code_editor.gd")); c.main = self
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(minf(520.0, maxf(280.0, desk.size.x - 16.0)), 360); c.clip_contents = true
	wv.add_child(c)

func _app_profiles() -> void:
	var wv := _make_window("profiles", "", Vector2(620, 560), Vector2(220, 40))
	var c := Control.new(); c.set_script(load("res://apps/profiles.gd")); c.m = self
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(minf(520.0, maxf(280.0, desk.size.x - 16.0)), 380); c.clip_contents = true
	wv.add_child(c); c.build()

func _app_clipboard() -> void:
	var wv := _make_window("clipboard", "", Vector2(460, 600), Vector2(240, 40))
	var c := Control.new(); c.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(minf(420.0, maxf(280.0, desk.size.x - 16.0)), 440); c.clip_contents = true
	wv.add_child(c); clip.build_ui(c)

var _nvault = null
func notes_vault():
	if _nvault == null:
		_nvault = load("res://apps/vault.gd").new(); _nvault.load_cfg(); _nvault.load_cache()
	return _nvault

func _app_notes() -> void:
	var wv := _make_window("notes", "", Vector2(1000, 660), Vector2(150 + randi() % 60, 20 + randi() % 30))
	var c := Control.new(); c.set_script(load("res://apps/notes.gd")); c.m = self
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(minf(560.0, maxf(280.0, desk.size.x - 16.0)), 420); c.clip_contents = true
	wv.add_child(c); c.build()

func _app_office(id: String, sz: Vector2) -> void:
	var wv := _make_window(id, "", sz + Vector2(0, 60), Vector2(160 + randi() % 80, 20 + randi() % 30))
	var c := Control.new(); c.set_script(load("res://apps/%s.gd" % {"sheet": "sheet", "imgview": "image_viewer", "pdf": "pdf_viewer", "calendar": "calendar_ui"}[id])); c.m = self
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(minf(sz.x, maxf(280.0, desk.size.x - 16.0)), sz.y); c.clip_contents = true
	wv.add_child(c); c.build()

## Ouvre un fichier dans une appli bureautique (imgview, pdf, sheet).
func open_with(id: String, path: String) -> void:
	_open_app(id)
	if not wins.has(id): return
	for n in wins[id]["win"].find_children("*", "Control", true, false):
		if n.has_method("open_path"): n.open_path(path); return

func _app_devices() -> void:
	var wv := _make_window("devices", "", Vector2(680, 640), Vector2(200, 30))
	var c := Control.new(); c.set_script(load("res://apps/devices.gd")); c.m = self
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(minf(520.0, maxf(280.0, desk.size.x - 16.0)), 420); c.clip_contents = true
	wv.add_child(c); c.build()

func _app_chess() -> void:
	var wv := _make_window("chess", "", Vector2(900, 680), Vector2(180, 10))
	var ch := Control.new()
	ch.set_script(load("res://apps/chess.gd"))
	ch.size_flags_vertical = Control.SIZE_EXPAND_FILL; ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.custom_minimum_size = Vector2(320, 360); ch.clip_contents = true
	wv.add_child(ch)

# ---------------------------------------------------------------- Sound Link (app intégrée)

func _app_soundlink() -> void:
	var wv := _make_window("soundlink", "", Vector2(500, 740), Vector2(240, 16))
	var sl := Control.new()
	sl.set_script(load("res://apps/soundlink.gd"))
	sl.size_flags_vertical = Control.SIZE_EXPAND_FILL; sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(320, 360); sl.clip_contents = true
	wv.add_child(sl)

# ---------------------------------------------------------------- Dictionnaire (hors ligne, données FreeDict)

const DIC_LANGS := {"fra": "Français", "eng": "English", "spa": "Español", "ita": "Italiano", "por": "Português", "nld": "Nederlands", "jpn": "日本語"}
const DIC_PAIRS := ["fra-eng", "eng-fra", "spa-eng", "eng-spa", "ita-eng", "eng-ita", "por-eng", "eng-por", "nld-eng", "eng-nld", "jpn-eng", "eng-jpn"]
const DIC_PAGE := 200
const ACC := {"à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a", "ç": "c", "è": "e", "é": "e", "ê": "e", "ë": "e",
	"ì": "i", "í": "i", "î": "i", "ï": "i", "ñ": "n", "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o", "ù": "u", "ú": "u", "û": "u", "ü": "u", "ý": "y", "ÿ": "y"}
var dic_note: Label
var dic_search: LineEdit
var dic_list: ItemList
var dic_def: RichTextLabel
var dic_info: Label
var dic_lines := PackedStringArray()
var dic_start := 0
var dic_loading := false

func _dkey(t: String) -> String:
	var o := ""
	for c in t.strip_edges().to_lower(): o += ACC.get(c, c)
	return o

func _app_dict() -> void:
	var wv := _make_window("dict", "", Vector2(920, 580), Vector2(170, 24))
	var mm := MarginContainer.new(); mm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]: mm.add_theme_constant_override("margin_" + k, 14)
	wv.add_child(mm)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); mm.add_child(v)
	dic_note = _mlbl("", 14); v.add_child(dic_note)
	dic_search = LineEdit.new(); dic_search.placeholder_text = "Rechercher un mot…"; dic_search.virtual_keyboard_enabled = false
	dic_search.clear_button_enabled = true; dic_search.add_theme_font_size_override("font_size", 20)
	dic_search.text_changed.connect(_dic_search); v.add_child(dic_search)
	var hb := HBoxContainer.new(); hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 10); v.add_child(hb)
	var left := VBoxContainer.new(); left.custom_minimum_size.x = 330; left.add_theme_constant_override("separation", 6); hb.add_child(left)
	dic_list = ItemList.new(); dic_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dic_list.item_selected.connect(_dic_show); left.add_child(dic_list)
	var pg := HBoxContainer.new(); pg.add_theme_constant_override("separation", 6); left.add_child(pg)
	var pv := UI.icon_btn("chevron-left", "Page précédente", _dic_page.bind(-1), "", 40); pg.add_child(pv)
	dic_info = _mlbl("", 13); dic_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dic_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; pg.add_child(dic_info)
	var nx := UI.icon_btn("chevron-right", "Page suivante", _dic_page.bind(1), "", 40); pg.add_child(nx)
	var pc := PanelContainer.new(); pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", _box(_p("field"), _rad(), _p("edge"), 1, 0, 16)); hb.add_child(pc)
	dic_def = RichTextLabel.new(); dic_def.bbcode_enabled = true; dic_def.selection_enabled = true; dic_def.context_menu_enabled = true
	dic_def.add_theme_font_size_override("normal_font_size", 20); dic_def.add_theme_font_size_override("bold_font_size", 28)
	pc.add_child(dic_def)
	_dic_load()

## Fichier à utiliser pour la paire des paramètres ; repli sur « langue → English » si pas de dictionnaire direct.
func _dic_pair() -> String:
	var s: String = set_cfg["src"]; var t: String = set_cfg["tgt"]
	if FileAccess.file_exists("res://dicts/%s-%s.tsv" % [s, t]): return "%s-%s" % [s, t]
	if s != "eng" and FileAccess.file_exists("res://dicts/%s-eng.tsv" % s): return "%s-eng" % s
	return ""

func _dic_load() -> void:
	var pair := _dic_pair()
	dic_list.clear(); dic_def.text = ""
	if pair == "":
		dic_lines = PackedStringArray(); dic_info.text = ""
		dic_note.text = "%s : pas de dictionnaire pour cette langue." % _pair_text(); return
	var real := "%s  →  %s" % [_gname(pair.get_slice("-", 0), 1), _gname(pair.get_slice("-", 1), 1)]
	dic_note.text = real if real == _pair_text() else "%s  (pas de dictionnaire direct vers %s : traductions en anglais)" % [real, _gname(set_cfg["tgt"], 1)]
	var path := "res://dicts/%s.tsv" % pair
	dic_info.text = "Chargement…"
	dic_loading = true
	await get_tree().process_frame
	if not is_instance_valid(dic_list): return
	dic_lines = FileAccess.get_file_as_string(path).split("\n", false)
	dic_loading = false
	dic_search.text = ""; dic_start = 0
	_dic_refresh(); dic_search.grab_focus()

func _dic_refresh() -> void:
	dic_list.clear()
	var n := dic_lines.size()
	dic_start = clampi(dic_start, 0, maxi(0, n - 1))
	var e := mini(n, dic_start + DIC_PAGE)
	for i in range(dic_start, e): dic_list.add_item(dic_lines[i].get_slice("\t", 1))
	dic_info.text = "%d–%d / %d mots" % [dic_start + 1, e, n]
	if dic_list.item_count > 0: dic_list.select(0); _dic_show(0)
	else: dic_def.text = ""

func _dic_page(d: int) -> void:
	if dic_loading: return
	dic_start += d * DIC_PAGE; _dic_refresh()

func _dic_search(t: String) -> void:
	if dic_loading: return
	var k := _dkey(t)
	if k.is_empty(): dic_start = 0
	else:
		var lo := 0; var hi := dic_lines.size()
		while lo < hi:
			var mid := (lo + hi) / 2
			if dic_lines[mid].get_slice("\t", 0) < k: lo = mid + 1
			else: hi = mid
		dic_start = lo
	_dic_refresh()

func _dic_show(i: int) -> void:
	var line := dic_lines[dic_start + i]
	var word := line.get_slice("\t", 1).replace("[", "[lb]")
	var out := "[b]%s[/b]\n\n" % word
	for d in line.get_slice("\t", 2).split("¶"):
		var t := d.replace("[", "[lb]")
		if t.begins_with("("):
			var e := t.find(")")
			out += "[color=#8f9bb3]%s[/color] %s\n\n" % [t.substr(0, e + 1), t.substr(e + 1)]
		else: out += t + "\n\n"
	dic_def.text = out

# ---------------------------------------------------------------- Réglages

func _load_settings() -> void:
	var c := ConfigFile.new()
	if c.load("user://settings.cfg") == OK:
		set_cfg["bg"] = clampi(int(c.get_value("ui", "bg", 0)), 0, BG_GRADS.size() - 1)
		set_cfg["font"] = clampi(int(c.get_value("ui", "font", 22)), 14, 40)
		set_cfg["ollama"] = str(c.get_value("translate", "server", set_cfg["ollama"]))
		set_cfg["model"] = str(c.get_value("translate", "model", ""))
		set_cfg["kb"] = str(c.get_value("ui", "kb", "osk")); set_cfg["cursor"] = str(c.get_value("ui", "cursor", "auto")); set_cfg["pad"] = bool(c.get_value("ui", "pad", false)); set_cfg["pad_speed"] = clampf(float(c.get_value("ui", "pad_speed", 0.7)), 0.2, 2.5); set_cfg["zoom"] = clampf(float(c.get_value("ui", "zoom", 1.0)), 0.5, 2.2)
		set_cfg["engine"] = int(c.get_value("translate", "engine", -1))
		set_cfg["src"] = str(c.get_value("lang", "src", "spa")); set_cfg["tgt"] = str(c.get_value("lang", "tgt", "fra"))
		set_cfg["light"] = bool(c.get_value("ui", "light", false)); set_cfg["wall"] = bool(c.get_value("ui", "wall", false)); set_cfg["nvd"] = int(c.get_value("ui", "nvd", 2))
		set_cfg["clip_save"] = bool(c.get_value("ui", "clip_save", true)); set_cfg["clip_nopw"] = bool(c.get_value("ui", "clip_nopw", true))
		for k in ["icons", "layout", "keys", "padmap"]:
			var v = c.get_value("ui", k, {}); set_cfg[k] = v if v is Dictionary else {}
		var o = c.get_value("ui", "open", []); set_cfg["open"] = o if o is Array else []
		set_cfg["accent"] = str(c.get_value("ui", "accent", "5aa2ff")); set_cfg["anim"] = bool(c.get_value("ui", "anim", true))
		set_cfg["wtrans"] = clampf(float(c.get_value("ui", "wtrans", 1.0)), 0.5, 1.0); set_cfg["radius"] = clampi(int(c.get_value("ui", "radius", 12)), 0, 28)
		set_cfg["isize"] = clampi(int(c.get_value("ui", "isize", 56)), 32, 96); set_cfg["dock_hide"] = bool(c.get_value("ui", "dock_hide", false))
		var pf = c.get_value("ui", "profiles", null)
		if pf is Array: set_cfg["profiles"] = pf
		var ins = c.get_value("ui", "installed", null); set_cfg["installed"] = ins if ins is Array else APPS.keys().filter(func(k): return not CORE.has(k))   # anciennes configs : tout reste installé
		var dk = c.get_value("ui", "desk", null); set_cfg["desk"] = dk if dk is Array else ["trash", "market"]
		if not bool(c.get_value("ui", "mk_desk", false)) and not set_cfg["desk"].has("market"): set_cfg["desk"].append("market")
		var pn = c.get_value("ui", "pins", set_cfg["pins"]); set_cfg["pins"] = pn if pn is Array else set_cfg["pins"]
	ACCENT = Color.html(str(set_cfg["accent"])) if str(set_cfg["accent"]).is_valid_html_color() else Color("5aa2ff")

func _save_settings() -> void:
	var c := ConfigFile.new()
	c.set_value("ui", "bg", set_cfg["bg"]); c.set_value("ui", "font", set_cfg["font"]); c.set_value("ui", "kb", set_cfg["kb"]); c.set_value("ui", "cursor", set_cfg["cursor"]); c.set_value("ui", "pad", set_cfg["pad"]); c.set_value("ui", "pad_speed", set_cfg["pad_speed"]); c.set_value("ui", "zoom", set_cfg["zoom"])
	c.set_value("translate", "server", set_cfg["ollama"]); c.set_value("translate", "model", set_cfg["model"]); c.set_value("translate", "engine", set_cfg["engine"])
	c.set_value("lang", "src", set_cfg["src"]); c.set_value("lang", "tgt", set_cfg["tgt"])
	for k in ["light", "wall", "icons", "layout", "open", "accent", "anim", "wtrans", "radius", "isize", "pins", "desk", "mk_desk", "installed", "dock_hide", "keys", "padmap", "clip_save", "clip_nopw"]: c.set_value("ui", k, set_cfg[k])
	c.set_value("ui", "nvd", n_vd)
	if set_cfg.has("profiles"): c.set_value("ui", "profiles", set_cfg["profiles"])
	c.save("user://settings.cfg")

func _type_key(r: int, c: int) -> void:
	var up := shift != caps
	_ins((ROWS_UPPER if up else ROWS_LOWER)[r][c])
	if shift: shift = false; _refresh_keys()

func _toggle_shift() -> void:
	shift = not shift; _refresh_keys()

func _toggle_caps() -> void:
	caps = not caps; _refresh_keys()

func _refresh_keys() -> void:
	var up := shift != caps
	for e in char_btns:
		e[0].text = (ROWS_UPPER if up else ROWS_LOWER)[e[1]][e[2]]
	shift_btns[0].modulate = ACCENT.lightened(0.3) if shift else Color.WHITE
	shift_btns[1].modulate = ACCENT.lightened(0.3) if caps else Color.WHITE

func _move(d: int) -> void:
	var f := _target()
	if f is TextEdit: f.set_caret_column(clampi(f.get_caret_column() + d, 0, f.get_line(f.get_caret_line()).length()))
	elif f is LineEdit: f.caret_column = clampi(f.caret_column + d, 0, f.text.length())

func _new() -> void:
	edit.text = ""; dirty = true; _update_status()

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f: f.store_string(edit.text); f.close()
	dirty = false; _update_status()

func _update_status() -> void:
	if not edit or not is_instance_valid(edit): return
	status.text = "  Ligne %d, Col %d   •   %d caractères   •   %s" % [
		edit.get_caret_line() + 1, edit.get_caret_column() + 1, edit.text.length(),
		"modifié" if dirty else "enregistré"]
	if title_lbl and is_instance_valid(title_lbl): title_lbl.text = "Bloc-notes" + (" •" if dirty else "")


# ---------------------------------------------------------------- Mise à jour

var upd_lbl_text := ""
var upd_btn_text := "Vérifier"

func _set_upd(label: String, btn: String, disabled := false) -> void:
	upd_lbl_text = label; upd_btn_text = btn
	if upd_lbl and is_instance_valid(upd_lbl): upd_lbl.text = label
	if upd_btn and is_instance_valid(upd_btn): upd_btn.text = btn; upd_btn.disabled = disabled
	upd_avail = btn.begins_with("Mettre") or btn.begins_with("Télécharger")
	start_btn.text = "LangOS" + (" ●" if upd_avail else "")

func _check_update() -> void:
	if not CHECK_UPDATES:
		_set_upd("Mises à jour désactivées.", "Vérifier"); return
	if upd_http == null:
		upd_http = HTTPRequest.new(); upd_http.timeout = 10.0; add_child(upd_http)
	if upd_http.request_completed.is_connected(_on_version_json): return
	_set_upd("Recherche de mises à jour…", "Vérifier", true)
	upd_http.request_completed.connect(_on_version_json, CONNECT_ONE_SHOT)
	upd_http.request(UPDATE_URL)

const APK_URL := "https://github.com/goodview-soft/LangOS/releases/latest/download/BlocNote.apk"

## Niveau de la partie native de l'APK installée (99 hors Android). 0 = très ancienne, 1 = WebView, 2+ = lanceur…
func _native_level() -> int:
	if OS.get_name() != "Android": return 99
	if Engine.has_singleton("LangLauncher"): return int(Engine.get_singleton("LangLauncher").nativeLevel())
	return 1 if Engine.has_singleton("LangWebView") else 0

func _apk_prompt() -> void:
	if apk_prompted: return
	apk_prompted = true
	var cc := CenterContainer.new(); cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(cc)
	var pc := PanelContainer.new(); pc.add_theme_stylebox_override("panel", _box(_p("pop"), _rad() + 4, _p("edge"), 1, 30, 18)); cc.add_child(pc)
	var v := VBoxContainer.new(); v.custom_minimum_size.x = 420; v.add_theme_constant_override("separation", 12); pc.add_child(v)
	v.add_child(_dlbl("Nouvelle APK à installer", 22))
	var l := _mlbl("Cette version de LangOS apporte des fonctions Android (navigateur, applis, écran d'accueil) qui demandent de réinstaller l'APK. La mise à jour légère ne suffit pas.", 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(l)
	var b1 := _mk_btn("Télécharger l'APK", 380, 50); b1.theme_type_variation = "Accent"; b1.pressed.connect(func(): OS.shell_open(APK_URL); cc.queue_free()); v.add_child(b1)
	var b2 := _mk_btn("Plus tard", 380, 44); b2.pressed.connect(func(): cc.queue_free()); v.add_child(b2)

func _on_version_json(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_set_upd("v%s (aucune version publiée)" % VERSION if code == 404 else "Vérification impossible (hors ligne ?).", "Vérifier")
		return
	var info = JSON.parse_string(body.get_string_from_utf8())
	if not (info is Dictionary) or not info.has("version"):
		_set_upd("Réponse invalide.", "Vérifier"); return
	if int(info.get("native", 0)) > _native_level():
		_set_upd("Nouvelle APK requise : la partie Android de cette version (niveau %d, installé %d) doit être réinstallée." % [int(info["native"]), _native_level()], "Télécharger l'APK")
		_apk_prompt(); return
	if not preload("res://boot.gd").newer(str(info["version"]), VERSION):
		_set_upd("À jour (v%s)" % VERSION, "Vérifier"); return
	upd_info = info
	notify("Mise à jour", "Version %s disponible." % info["version"])
	var v := Engine.get_version_info()
	var same: bool = str(info.get("godot", "")) == "%d.%d.%d" % [v.major, v.minor, v.patch]
	if same and info.has("pck"):
		_set_upd("Version %s disponible." % info["version"], "Mettre à jour")
	else:
		_set_upd("Version %s disponible (nouveau programme à télécharger)." % info["version"], "Télécharger")

func _do_update() -> void:
	match upd_btn_text:
		"Télécharger": OS.shell_open(RELEASES_URL)
		"Télécharger l'APK": OS.shell_open(APK_URL)
		"Redémarrer": OS.set_restart_on_exit(true); get_tree().quit()
		"Mettre à jour", "Réessayer":
			_set_upd("Téléchargement…", "Mettre à jour", true)
			upd_http.download_file = "user://update.tmp"
			upd_http.request_completed.connect(_on_pck, CONNECT_ONE_SHOT)
			upd_http.request(str(upd_info["pck"]))
		_: _check_update()

func _on_pck(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	upd_http.download_file = ""
	var tmp := "user://update.tmp"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or FileAccess.get_sha256(tmp) != str(upd_info.get("sha256", "")):
		DirAccess.remove_absolute(tmp); _set_upd("Échec du téléchargement.", "Réessayer"); return
	DirAccess.rename_absolute(tmp, "user://update.pck")
	var c := ConfigFile.new()
	c.set_value("update", "version", str(upd_info["version"])); c.save("user://update.cfg")
	if OS.has_feature("pc"): _set_upd("Mise à jour %s installée." % upd_info["version"], "Redémarrer")
	else: _set_upd("Mise à jour %s installée : fermer puis rouvrir l'appli." % upd_info["version"], "Redémarrer")

# ---------------------------------------------------------------- Bureau étendu : redimensionner, ancrer, bureaux virtuels, menus, notifications

var bar_panel: PanelContainer
var cur_vd := 0
var n_vd := 2
var restore_vd := -1
var vd_btn: Button
var bell_btn: Button
var notifs: Array = []
var unread := 0
var toast: PanelContainer
var np_panel: PanelContainer
var np_catcher: Control
var rs := {}       # redimensionnement en cours
var idrag := {}    # glisser d'une icône en cours
const GRID := 108.0
const NO_RESTORE := ["hika", "chromium", "chromium2", "chromium3", "update"]

func _real() -> bool:
	return get_tree().current_scene == self

func _restyle() -> void:
	_build_theme()
	(bar_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = _p("bar")
	(bar_panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color = _p("edge")
	menu.add_theme_stylebox_override("panel", _menu_box())
	for k in ["icon_normal_color", "icon_hover_color"]: start_btn.add_theme_color_override(k, ACCENT)
	if menu_hi: menu_hi.modulate = ACCENT
	if kb != null: var ks := _box(_p("kb"), _rad() + 4, _p("edge"), 1, 24, 12); ks.corner_radius_bottom_left = 0; ks.corner_radius_bottom_right = 0; kb.add_theme_stylebox_override("panel", ks)
	_restyle_icons()
	_set_active(active)   # styles des fenêtres, barres de titre, tâches et dock
	UI.refresh(get_tree())   # panneaux stylés à la construction par les applications (groupe « themed »)

func _set_light(on: bool) -> void:
	set_cfg["light"] = on; _restyle(); _save_settings()

func _apply_bg() -> void:
	if set_cfg.get("wall", false) and FileAccess.file_exists("user://wallpaper.png"):
		var img := Image.load_from_file("user://wallpaper.png")
		if img != null and not img.is_empty():
			bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; bg.texture = ImageTexture.create_from_image(img); return
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture = _grad_tex(set_cfg["bg"])

func _set_gradient(i: int) -> void:
	set_cfg["bg"] = i; set_cfg["wall"] = false; _apply_bg(); _save_settings()

func _set_wallpaper(path: String) -> bool:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		notify("Fond d'écran", "Image illisible."); return false
	var m := maxi(img.get_width(), img.get_height())
	if m > 2048: img.resize(img.get_width() * 2048 / m, img.get_height() * 2048 / m, Image.INTERPOLATE_BILINEAR)
	img.save_png("user://wallpaper.png"); set_cfg["wall"] = true; _apply_bg(); _save_settings()
	return true

func _pick_wallpaper() -> void:
	var fd := FileDialog.new(); fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE; fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true; fd.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp,*.bmp ; Images"])
	fd.file_selected.connect(func(p: String): _set_wallpaper(p); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	add_child(fd); fd.popup_centered_ratio(0.7)

## Fichiers glissés sur la fenêtre : image = fond d'écran, texte = Bloc-notes.
func _on_files(files: PackedStringArray) -> void:
	if files.is_empty(): return
	var f := files[0]; var e := f.get_extension().to_lower()
	if e in ["png", "jpg", "jpeg", "webp", "bmp"]:
		if _set_wallpaper(f): notify("Fond d'écran", "Image appliquée : " + f.get_file())
	elif e in ["mp4", "webm", "mkv", "mov", "ogv"] and installed("gallery"):
		_open_app("gallery"); notify("Galerie", f.get_file())
	elif e in ["mp3", "ogg", "lrc"]:
		_open_app("music")
		if is_instance_valid(music_node): music_node.call_deferred("import_files", files)
	elif e in ["txt", "md", "log"]:
		_open_app("notepad"); edit.text = FileAccess.get_file_as_string(f); notify("Bloc-notes", f.get_file() + " ouvert")

# --- Menu contextuel générique (items : [libellé, Callable] ou null pour un séparateur)
func _popup_menu(items: Array, at: Vector2, up := false) -> void:
	_hide_ctx()
	ctx_catcher = Control.new(); ctx_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctx_catcher.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: _hide_ctx())
	add_child(ctx_catcher)
	ctx_menu = PanelContainer.new(); ctx_menu.add_theme_stylebox_override("panel", _box(_p("menu"), UI.rad(), _p("edge"), 1, 18, 6))
	add_child(ctx_menu)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0); ctx_menu.add_child(v)
	for it in items:
		if it == null:
			var sep := HSeparator.new(); sep.add_theme_constant_override("separation", 7); v.add_child(sep); continue
		# un libellé préfixé « ✓ » est un élément coché : la coche devient une icône à droite
		var t := str(it[0]); var chk := t.begins_with("✓ ")
		var b := _mk_btn(t.trim_prefix("✓ "), 220, 36); b.theme_type_variation = "Nav"; b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if chk: UI.set_icon(b, "check"); b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.pressed.connect(func(): _hide_ctx(); it[1].call())
		v.add_child(b)
	ctx_menu.size = ctx_menu.get_combined_minimum_size()
	var y := at.y - ctx_menu.size.y if up else at.y
	ctx_menu.position = Vector2(clampf(at.x, 8, size.x - ctx_menu.size.x - 8), clampf(y, 8, maxf(8, size.y - ctx_menu.size.y - 8)))
	fx.popup_in(ctx_menu, up)

func _context_at(pos: Vector2) -> bool:
	if not desk.get_global_rect().has_point(pos): return false
	var p := pos - desk.global_position
	var kids := desk.get_children(); kids.reverse()
	for c in kids:
		if not (c is Control and c.visible): continue
		if not Rect2(c.position, c.size).has_point(p): continue
		if desk_icons.has(c): _icon_menu(str(c.get_meta("id")), pos); return true
		for id in wins:
			if wins[id]["win"] == c and p.y < c.position.y + 44.0: _win_menu(id, pos); return true
		return false
	_desk_menu(pos); return true

func _desk_menu(at: Vector2) -> void:
	var light: bool = set_cfg.get("light", false)
	_popup_menu([
		["Changer le fond d'écran", func(): _set_gradient((int(set_cfg["bg"]) + 1) % BG_GRADS.size())],
		["Image de fond…", _pick_wallpaper],
		["Thème sombre" if light else "Thème clair", func(): _set_light(not light)],
		null,
		["Ranger les icônes", _reset_icons],
		["Disposer les fenêtres", _tile_all],
		["Nouveau bureau virtuel", _vd_add],
		null,
		["Profils…", _profiles_menu],
		["Recherche", func(): srch.toggle()],
		["Presse-papiers", func(): clip.toggle()],
		["Paramètres", func(): _open_app("settings")]], at)

func _profiles_menu(at := Vector2(-1, -1)) -> void:
	var it := []
	for i in prof.all().size(): it.append([str(prof.all()[i]["name"]), prof.activate.bind(i)])
	it.append(null); it.append(["Gérer les profils", func(): _open_app("profiles")])
	_popup_menu(it, size / 2.0 - Vector2(115, 120) if at.x < 0 else at)

func _icon_menu(id: String, at: Vector2) -> void:
	_popup_menu([["Ouvrir", func(): _open_app(id)], _pin_item(id), ["Retirer du bureau", func(): _desk_toggle(id)], null, ["Ranger les icônes", _reset_icons]], at)

func _app_ctx(id: String) -> void:
	var on_desk: bool = set_cfg["desk"].has(id)
	_popup_menu([["Ouvrir", func(): _toggle_menu(); _open_app(id)], _pin_item(id),
		["Retirer du bureau" if on_desk else "Ajouter au bureau", func(): _desk_toggle(id)]], get_viewport().get_mouse_position())

func _pin_item(id: String) -> Array:
	var on: bool = set_cfg["pins"].has(id)
	return ["Détacher du menu Démarrer" if on else "Épingler au menu Démarrer", func():
		if on: set_cfg["pins"].erase(id)
		else: set_cfg["pins"].append(id)
		_save_settings(); _rebuild_menu()]

func _desk_toggle(id: String) -> void:
	if set_cfg["desk"].has(id):
		set_cfg["desk"].erase(id)
		for b in desk_icons:
			if str(b.get_meta("id")) == id: desk_icons.erase(b); b.queue_free(); break
	else:
		set_cfg["desk"].append(id); _desk_icon(id, Vector2.ZERO); _restyle_icons()
	_layout_icons(); _save_settings()

func _rebuild_menu() -> void:
	var was := menu.visible
	catcher.queue_free(); menu.queue_free()
	_build_menu()
	if was: _toggle_menu()

func _win_menu(id: String, at: Vector2, up := false) -> void:
	if not wins.has(id): return
	var d: Dictionary = wins[id]
	var it := [
		["Réduire", func(): if d["win"].visible: _toggle_win(id)],
		["Restaurer" if d["maxed"] else "Agrandir", func(): _toggle_max(id)], null,
		["Ancrer à gauche", func(): _snap(id, "l")], ["Ancrer à droite", func(): _snap(id, "r")],
		["Ancrer en haut", func(): _snap(id, "t")], ["Ancrer en bas", func(): _snap(id, "b")],
		["Quart haut gauche", func(): _snap(id, "tl")], ["Quart haut droite", func(): _snap(id, "tr")],
		["Quart bas gauche", func(): _snap(id, "bl")], ["Quart bas droite", func(): _snap(id, "br")],
		["Tiers gauche", func(): _snap(id, "3l")], ["Tiers centre", func(): _snap(id, "3c")], ["Tiers droite", func(): _snap(id, "3r")], null]
	for i in n_vd:
		if i != int(d["vd"]): it.append(["Déplacer vers le bureau %d" % (i + 1), func(): _move_to_vd(id, i)])
	it.append(null); it.append(["Fermer", func(): _close_win(id)])
	_popup_menu(it, at, up)

# --- Ancrage et disposition
func _snap(id: String, z: String) -> void:
	var d: Dictionary = wins[id]; var w: PanelContainer = d["win"]
	var keep: bool = d["maxed"] or d.get("snapped", false)
	d["maxed"] = false
	var s := desk.size; var h := s / 2.0; var t := s.x / 3.0
	var r: Rect2 = {"l": Rect2(0, 0, h.x, s.y), "r": Rect2(h.x, 0, h.x, s.y), "t": Rect2(0, 0, s.x, h.y), "b": Rect2(0, h.y, s.x, h.y),
		"tl": Rect2(0, 0, h.x, h.y), "tr": Rect2(h.x, 0, h.x, h.y), "bl": Rect2(0, h.y, h.x, h.y), "br": Rect2(h.x, h.y, h.x, h.y),
		"3l": Rect2(0, 0, t, s.y), "3c": Rect2(t, 0, t, s.y), "3r": Rect2(2 * t, 0, t, s.y)}[z]
	if not keep or d["saved"].size.x <= 0: d["saved"] = Rect2(w.position, w.size)
	d["snapped"] = true
	w.position = r.position; w.size = r.size; _clamp_windows(); _show(id); _save_layout()

func _tile_all() -> void:
	var ids := []
	for id in wins:
		if int(wins[id]["vd"]) == cur_vd and wins[id]["win"].visible: ids.append(id)
	if ids.is_empty(): return
	var k := ids.size(); var cols := k if k <= 3 else int(ceil(sqrt(k))); var rows := int(ceil(float(k) / cols))
	var cw := desk.size.x / cols; var ch := desk.size.y / rows
	for i in k:
		var d: Dictionary = wins[ids[i]]; d["maxed"] = false
		d["win"].position = Vector2((i % cols) * cw, (i / cols) * ch); d["win"].size = Vector2(cw, ch)
	_clamp_windows(); _save_layout()

# --- Redimensionnement par les bords
func _begin_resize(pos: Vector2) -> bool:
	if menu.visible or is_instance_valid(ctx_menu) or desk == null: return false
	var p := pos - desk.global_position
	var kids := desk.get_children(); kids.reverse()
	for c in kids:
		if not (c is PanelContainer and c.visible): continue
		var id := ""
		for k in wins:
			if wins[k]["win"] == c: id = k
		var eg := 24.0 if UI.touch() else 8.0   # poignée plus large au doigt
		if id == "" or not Rect2(c.position, c.size).grow(eg - 2.0).has_point(p): continue
		if wins[id]["maxed"]: return false
		var r := Rect2(c.position, c.size)
		var l := p.x < r.position.x + eg and p.y > r.position.y + 40
		var rr := p.x > r.end.x - eg and p.y > r.position.y + 40
		var b := p.y > r.end.y - eg
		if not (l or rr or b): return false
		rs = {"win": c, "id": id, "rect": r, "p0": p, "l": l, "r": rr, "b": b}
		lp_active = false
		return true
	return false

func _do_resize(pos: Vector2) -> void:
	var w: PanelContainer = rs["win"]
	var r: Rect2 = rs["rect"]; var dp: Vector2 = pos - desk.global_position - rs["p0"]
	if not rs.has("mn"): rs["mn"] = w.get_combined_minimum_size()   # calculé une seule fois par geste
	var mn: Vector2 = rs["mn"]
	var x0 := r.position.x; var x1 := r.end.x; var y1 := r.end.y
	if rs["l"]: x0 = maxf(minf(r.position.x + dp.x, x1 - mn.x), 0.0)
	if rs["r"]: x1 = minf(maxf(r.end.x + dp.x, x0 + mn.x), desk.size.x)
	if rs["b"]: y1 = minf(maxf(r.end.y + dp.y, r.position.y + mn.y), desk.size.y)
	w.position = Vector2(x0, clampf(r.position.y, 0.0, maxf(0.0, desk.size.y - 40.0))); w.size = Vector2(x1 - x0, y1 - w.position.y)
	wins[rs["id"]]["snapped"] = false

# --- Icônes : glisser-déposer sur une grille
func _icon_input(ev: InputEvent, b: Button, id: String) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			idrag = {"b": b, "p0": get_viewport().get_mouse_position(), "pos0": b.position, "moved": false}
		elif idrag.get("b") == b:
			var moved: bool = idrag["moved"]; var from: Vector2 = idrag["pos0"]; idrag = {}
			if moved: _drop_icon(b, id, from)
			elif Time.get_ticks_msec() - lp_t < 550: _open_app(id)
			else: _layout_icons()
	elif ev is InputEventMouseMotion and idrag.get("b") == b and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var dl: Vector2 = get_viewport().get_mouse_position() - idrag["p0"]
		if idrag["moved"] or dl.length() > 10.0:
			idrag["moved"] = true; lp_active = false
			b.position = (idrag["pos0"] + dl).clamp(Vector2.ZERO, desk.size - b.size)

func _cell_of(b: Control) -> Vector2i:
	return Vector2i(int(roundf((b.position.x - 16.0) / GRID)), int(roundf((b.position.y - 16.0) / GRID)))

func _drop_icon(b: Button, id: String, from: Vector2) -> void:
	var cols := maxi(1, int((desk.size.x - 16.0) / GRID)); var rows := maxi(1, int((desk.size.y - 16.0) / GRID))
	var c := _cell_of(b); c = Vector2i(clampi(c.x, 0, cols - 1), clampi(c.y, 0, rows - 1))
	var old := Vector2i(int(roundf((from.x - 16.0) / GRID)), int(roundf((from.y - 16.0) / GRID)))
	for o in desk_icons:
		if o != b and _cell_of(o) == c: set_cfg["icons"][str(o.get_meta("id"))] = [old.x, old.y]
	set_cfg["icons"][id] = [c.x, c.y]
	_layout_icons(); _save_settings()

func _reset_icons() -> void:
	set_cfg["icons"] = {}; _layout_icons(); _save_settings()

# --- Bureaux virtuels
func _goto_vd(i: int) -> void:
	if overview != null and _real() and i != cur_vd: overview.snap_all()
	var old_vd := cur_vd
	cur_vd = clampi(i, 0, n_vd - 1)
	for id in wins:
		var d: Dictionary = wins[id]; var on: bool = int(d["vd"]) == cur_vd
		d["win"].visible = on and not d["min"]; d["task"].visible = on
	if vd_btn: vd_btn.text = "%d/%d" % [cur_vd + 1, n_vd]
	_set_active("")
	if fx != null and _real() and cur_vd != old_vd: fx.vd_slide(1 if cur_vd > old_vd else -1)

func _move_to_vd(id: String, i: int) -> void:
	wins[id]["vd"] = i; _goto_vd(cur_vd); _save_layout()

func _vd_add() -> void:
	if n_vd >= 6: return
	n_vd += 1; _goto_vd(n_vd - 1)

func _vd_remove() -> void:
	if n_vd <= 1: return
	for id in wins:
		if int(wins[id]["vd"]) >= n_vd - 1: wins[id]["vd"] = n_vd - 2
	n_vd -= 1; _goto_vd(mini(cur_vd, n_vd - 1)); _save_layout()

func _vd_menu() -> void:
	var it := [["Vue d'ensemble (Ctrl+Alt+Tab)", func(): overview.open()], null]
	for i in n_vd: it.append(["%sBureau %d" % ["✓ " if i == cur_vd else "", i + 1], func(): _goto_vd(i)])
	it.append(null)
	if n_vd < 6: it.append(["Nouveau bureau", _vd_add])
	if n_vd > 1: it.append(["Supprimer le dernier bureau", _vd_remove])
	_popup_menu(it, Vector2(vd_btn.global_position.x - 90, vd_btn.global_position.y - 6), true)

# --- Mémoire des fenêtres
func _save_layout() -> void:
	if not _real(): return
	var cur: Dictionary = set_cfg["layout"]
	for id in wins:
		var d: Dictionary = wins[id]; var w: PanelContainer = d["win"]
		var r: Rect2 = d["saved"] if (d["maxed"] or d.get("snapped", false)) and d["saved"].size.x > 0 else Rect2(w.position, w.size)
		cur[id] = [r.position.x, r.position.y, r.size.x, r.size.y, int(d["vd"]), bool(d["maxed"])]
	set_cfg["layout"] = cur
	set_cfg["open"] = wins.keys().filter(func(k): return not NO_RESTORE.has(k))
	_save_settings()

func _restore_layout() -> void:
	for id in set_cfg["open"]:
		if not APPS.has(id) or wins.has(id): continue
		var a = set_cfg["layout"].get(id)
		restore_vd = int(a[4]) if a is Array and a.size() > 4 else 0
		n_vd = maxi(n_vd, restore_vd + 1)
		_open_app(id)
		if a is Array and a.size() > 5 and a[5] and wins.has(id): _toggle_max(id)
	restore_vd = -1
	_goto_vd(0)

# --- Notifications centralisées
func notify(title: String, text := "") -> void:
	notifs.push_front({"t": title, "x": text, "time": Time.get_datetime_string_from_system().substr(11, 5)})
	if notifs.size() > 30: notifs.resize(30)
	unread += 1; _upd_bell()
	if is_instance_valid(toast): toast.queue_free()
	toast = UI.toast(title, text, "bell", minf(280.0, size.x - 90.0))
	add_child(toast); toast.size = toast.get_combined_minimum_size()
	var end := Vector2(size.x - toast.size.x - 12.0, 12.0)
	toast.position = end + Vector2(toast.size.x + 20.0, 0)
	var tw := toast.create_tween()
	tw.tween_property(toast, "position", end, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(4.0); tw.tween_property(toast, "modulate:a", 0.0, 0.4); tw.tween_callback(toast.queue_free)

func _upd_bell() -> void:
	if bell_btn: bell_btn.text = str(unread) if unread > 0 else ""

func _close_notifs() -> void:
	if is_instance_valid(np_panel): np_panel.queue_free()
	if is_instance_valid(np_catcher): np_catcher.queue_free()

const MOIS := ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]

## Petit calendrier du mois (lundi en premier) avec navigation ; le jour courant est surligné.
func _np_calendar(parent: Control, y: int, mo: int) -> VBoxContainer:
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 4); parent.add_child(box)
	var now := Time.get_date_dict_from_system()
	var hd := HBoxContainer.new(); box.add_child(hd)
	var tl := UI.heading("%s %d" % [str(MOIS[mo - 1]).capitalize(), y]); tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hd.add_child(tl)
	var go := func(dm: int):
		var n := mo + dm; var yy := y
		if n < 1: n = 12; yy -= 1
		elif n > 12: n = 1; yy += 1
		var idx := box.get_index(); box.queue_free()
		parent.move_child(_np_calendar(parent, yy, n), idx)
	var pb := _icon_btn("chevron-left", "Flat", 32, 30, 14); pb.tooltip_text = "Mois précédent"; pb.pressed.connect(func(): go.call(-1)); hd.add_child(pb)
	var nb := _icon_btn("chevron-right", "Flat", 32, 30, 14); nb.tooltip_text = "Mois suivant"; nb.pressed.connect(func(): go.call(1)); hd.add_child(nb)
	var g := GridContainer.new(); g.columns = 7; g.add_theme_constant_override("h_separation", 2); g.add_theme_constant_override("v_separation", 2); box.add_child(g)
	for d in ["L", "M", "M", "J", "V", "S", "D"]:
		var l := UI.small(d); l.custom_minimum_size = Vector2(42, 20); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; g.add_child(l)
	var first := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_datetime_dict({"year": y, "month": mo, "day": 1, "hour": 12, "minute": 0, "second": 0})))
	var lead := posmod(int(first["weekday"]) - 1, 7)
	var dim := 31
	if mo == 2: dim = 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28
	elif mo in [4, 6, 9, 11]: dim = 30
	for i in lead + dim:
		var c := Label.new(); c.custom_minimum_size = Vector2(42, 28); c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		c.add_theme_font_size_override("font_size", UI.T_SMALL)
		if i >= lead:
			var dd := i - lead + 1; c.text = str(dd)
			if y == int(now["year"]) and mo == int(now["month"]) and dd == int(now["day"]):
				c.add_theme_stylebox_override("normal", _box(ACCENT, 14)); c.add_theme_color_override("font_color", UI.on(ACCENT))
		g.add_child(c)
	return box

func _toggle_notifs() -> void:
	if is_instance_valid(np_panel): _close_notifs(); return
	unread = 0; _upd_bell(); _hide_ctx()
	np_catcher = Control.new(); np_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	np_catcher.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: _close_notifs())
	add_child(np_catcher)
	var nb := _menu_box(); nb.set_content_margin_all(12)
	np_panel = PanelContainer.new(); np_panel.add_theme_stylebox_override("panel", nb); add_child(np_panel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6); np_panel.add_child(v)
	var h := HBoxContainer.new(); v.add_child(h)
	var t := UI.heading("Notifications"); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(t)
	var clr := _mk_btn("Tout effacer", 0, UI.BTN); clr.theme_type_variation = "Flat"; clr.visible = not notifs.is_empty()
	clr.pressed.connect(func(): notifs.clear(); _close_notifs()); h.add_child(clr)
	var cal_h := 0.0
	if size.y >= 620.0:
		var now := Time.get_date_dict_from_system()
		_np_calendar(v, int(now["year"]), int(now["month"])); cal_h = 235.0
		v.add_child(HSeparator.new())
	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var lw := minf(330.0, size.x - 40.0)
	sc.custom_minimum_size = Vector2(lw, maxf(110.0, minf(380.0, size.y - bar_h - 130.0 - cal_h))); v.add_child(sc)
	var list := VBoxContainer.new(); list.add_theme_constant_override("separation", 6); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; list.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.add_child(list)
	if notifs.is_empty(): list.add_child(UI.status_page("bell", "Aucune notification", "", null, true))
	for n in notifs:
		var c := UI.card(list, 9); c.add_theme_constant_override("separation", 2)
		var hh := HBoxContainer.new(); hh.add_theme_constant_override("separation", 6); c.add_child(hh)
		var l1 := UI.heading(str(n["t"])); l1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l1.custom_minimum_size.x = 10; l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hh.add_child(l1)
		var lt := UI.small(str(n["time"])); lt.size_flags_vertical = Control.SIZE_SHRINK_BEGIN; hh.add_child(lt)
		if n["x"] != "": c.add_child(UI.note(str(n["x"])))
	np_panel.size = np_panel.get_combined_minimum_size()
	np_panel.position = Vector2(size.x - np_panel.size.x - 10.0, size.y - bar_h - 10.0 - np_panel.size.y)
