extends Control
## Navigateur intégré (Chromium via l'extension gdCEF), affiché dans une fenêtre du bureau.
## L'extension (~1 Go, Linux x86_64) n'est pas livrée avec LangOS : elle est téléchargée une seule fois
## dans user://cef au premier lancement. Tant qu'elle n'est pas installée, la fenêtre propose l'installation
## ou l'ouverture du Chromium du système (`external`, fourni par le bureau).

const URL_ZIP := "https://github.com/Lecrapouille/gdcef/releases/download/v0.21.0-godot4/gdcef-0.21.0_godot-4.7.zip"
const DIR := "user://cef"
const HOME := "https://duckduckgo.com/"
const UI = preload("res://apps/ui.gd")

var external: Callable                 # ouvre le navigateur du système (donné par le bureau)
var cef: Object
var browser: Object
var view: TextureRect
var url_edit: LineEdit
var info: Label
var bar: ProgressBar
var inst_btn: Button
var http: HTTPRequest
var thread: Thread
var last_url := ""
var box: VBoxContainer

func _g(p: String) -> String: return ProjectSettings.globalize_path(p)
func _zip() -> String: return _g(DIR + "/gdcef.zip")
func _lib() -> String: return _g(DIR + "/linux/libgdcef.so")
func _supported() -> bool: return OS.get_name() == "Linux" and Engine.get_architecture_name() == "x86_64"
func _installed() -> bool: return FileAccess.file_exists(_lib()) and FileAccess.file_exists(_g(DIR + "/linux/libcef.so"))

var wv: Object                         # plugin Android « LangWebView » (WebView du système)
var wv_rect := Rect2i()
var wv_shown := false
var shade: ColorRect                   # voile affiché à la place du WebView quand la fenêtre n'est pas au premier plan

func _android() -> bool: return OS.get_name() == "Android" and Engine.has_singleton("LangWebView")

func _ready() -> void:
	core = Core.new(); core.primary = str(get_meta("win_id", "chromium")) == "chromium"; core.load_all()
	if _android(): _start_android()
	elif _installed() and _supported(): _start()
	else: _build_install()

func _exit_tree() -> void:
	if core: core.save()
	if wv: wv.close()
	for b in brs.values(): if is_instance_valid(b): b.close()
	if thread and thread.is_started(): thread.wait_to_finish()
	OS.low_processor_usage_mode = true

# ---------------------------------------------------------------- Installation

func _clear() -> void:
	for c in get_children(): c.queue_free()

func _build_install() -> void:
	_clear()
	var cc := CenterContainer.new(); cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(cc)
	box = VBoxContainer.new(); box.custom_minimum_size.x = 420; box.add_theme_constant_override("separation", 12); cc.add_child(box)
	var t := Label.new(); t.text = "Navigateur Chromium"; t.add_theme_font_size_override("font_size", 30); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(t)
	info = Label.new(); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.theme_type_variation = "Muted"; box.add_child(info)
	if _supported():
		info.text = "Le navigateur intégré (Chromium) n'est pas encore installé.\nTéléchargement unique d'environ 1 Go, puis il s'ouvre dans cette fenêtre."
		inst_btn = Button.new(); inst_btn.text = "Télécharger et installer"; inst_btn.custom_minimum_size.y = 50; inst_btn.pressed.connect(_download); box.add_child(inst_btn)
		bar = ProgressBar.new(); bar.visible = false; bar.custom_minimum_size.y = 18; box.add_child(bar)
	elif OS.get_name() == "Android":
		info.text = "Le plugin WebView est absent de cette APK (la mise à jour légère ne met pas à jour la partie native).\nInstalle l'APK la plus récente puis rouvre ce navigateur."
		var ap := Button.new(); ap.text = "Télécharger l'APK récente"; ap.custom_minimum_size.y = 50
		ap.pressed.connect(func(): OS.shell_open("https://github.com/goodview-soft/LangOS/releases/latest/download/BlocNote.apk")); box.add_child(ap)
	else:
		info.text = "Le navigateur intégré n'est disponible que sur Linux (x86_64)."
	if external.is_valid():
		var e := Button.new(); e.text = "Ouvrir le Chromium du système"; e.custom_minimum_size.y = 44; e.pressed.connect(external); box.add_child(e)

func _download() -> void:
	DirAccess.make_dir_recursive_absolute(_g(DIR))
	inst_btn.disabled = true; bar.visible = true; bar.value = 0
	info.text = "Téléchargement en cours…"
	http = HTTPRequest.new(); http.download_file = _zip(); http.use_threads = true; http.max_redirects = 8
	add_child(http); http.request_completed.connect(_on_downloaded)
	if http.request(URL_ZIP) != OK: _fail("Impossible de lancer le téléchargement.")

func _process(_d: float) -> void:
	if http and bar and bar.visible and http.get_body_size() > 0:
		bar.max_value = http.get_body_size(); bar.value = http.get_downloaded_bytes()
		info.text = "Téléchargement : %d / %d Mo" % [http.get_downloaded_bytes() / 1048576, http.get_body_size() / 1048576]
	if wv: _sync_wv()
	if core: _poll_downloads()
	if browser and is_instance_valid(browser):
		var u: String = browser.get_url()
		if u != last_url: _sync_url(u)

func _fail(msg: String, detail := "") -> void:
	info.text = msg; info.tooltip_text = detail; info.mouse_filter = Control.MOUSE_FILTER_PASS; inst_btn.disabled = false; if bar: bar.visible = false

func _on_downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: _fail("Le téléchargement de Chromium a échoué. Vérifie ta connexion puis réessaie.", "Résultat %d, code HTTP %d" % [result, code]); DirAccess.remove_absolute(_zip()); return
	info.text = "Installation (extraction, un instant)…"; bar.value = bar.max_value
	thread = Thread.new(); thread.start(_extract)

## Extrait seulement la partie Linux de l'archive (commande `unzip`), rend les binaires exécutables, écrit le .gdextension.
func _extract() -> void:
	var tmp := _g(DIR + "/tmp")
	var pre: Array = ["flatpak-spawn", "--host"] if FileAccess.file_exists("/.flatpak-info") else []
	var out := []
	var cmd: Array = pre + ["unzip", "-o", "-q", _zip(), "gdcef/cef_artifacts/linux/*", "-d", tmp]
	var rc := OS.execute(cmd[0], cmd.slice(1), out, true)
	var src := tmp + "/gdcef/cef_artifacts/linux"
	if rc == 0 and DirAccess.dir_exists_absolute(src):
		DirAccess.remove_absolute(_g(DIR + "/linux"))
		DirAccess.rename_absolute(src, _g(DIR + "/linux"))
		for f in ["libgdcef.so", "libcef.so", "gdCefRenderProcess", "libvk_swiftshader.so", "libvulkan.so.1"]:
			OS.execute("chmod", ["+x", _g(DIR + "/linux/" + f)])
		var fe := FileAccess.open(_g(DIR + "/gdcef.gdextension"), FileAccess.WRITE)
		var L := _g(DIR + "/linux")
		fe.store_string("[configuration]\nentry_symbol = \"gdcef_library_init\"\ncompatibility_minimum = 4.2\n\n[libraries]\nlinux.x86_64.debug = \"%s/libgdcef.so\"\nlinux.x86_64.release = \"%s/libgdcef.so\"\n\n[dependencies]\nlinux.x86_64 = {\"%s/libcef.so\": \"\"}\n" % [L, L, L])
		fe.close()
	OS.execute("rm", ["-rf", tmp]); DirAccess.remove_absolute(_zip())
	call_deferred("_after_extract", rc == 0 and _installed())

func _after_extract(ok: bool) -> void:
	thread.wait_to_finish(); thread = null
	if ok: _start()
	else: _fail("Extraction impossible (la commande « unzip » est-elle installée ?).")

# ---------------------------------------------------------------- Navigateur (interface commune : onglets, favoris, menus)

const Core := preload("res://apps/browser_core.gd")
var core
var tab_row: HBoxContainer
var bm_bar: HBoxContainer
var star: Button
var panel: PanelContainer              # panneau modal (favoris, historique, téléchargements, mots de passe)
var views := {}                        # id d'onglet -> TextureRect (Linux)
var brs := {}                          # id d'onglet -> navigateur gdCEF (Linux)
var dl_reqs := {}                      # id de téléchargement -> HTTPRequest
var vault_pw := ""
var vault_entries: Array = []

func _main() -> Object: return get_tree().current_scene
func _pal(k: String, d: Color) -> Color:
	var m := _main()
	return m._p(k) if m and m.has_method("_p") else d
func _toast(t: String, x := "") -> void:
	var m := _main()
	if m and m.has_method("notify"): m.notify(t, x)

func _build_ui(bh: int) -> void:
	var v := VBoxContainer.new(); v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); v.add_theme_constant_override("separation", 0); add_child(v)
	tab_row = HBoxContainer.new(); tab_row.add_theme_constant_override("separation", 2); v.add_child(tab_row)
	var hbar := UI.header_bar(); v.add_child(hbar)
	var st := UI.bar_start(hbar); var en := UI.bar_end(hbar)
	UI.bar_act(hbar, st, "chevron-left", "Page précédente", func(): _nav("back"))
	UI.bar_act(hbar, st, "chevron-right", "Page suivante", func(): _nav("fwd"))
	UI.bar_act(hbar, st, "refresh-cw", "Actualiser", func(): _nav("reload"))
	url_edit = LineEdit.new(); url_edit.custom_minimum_size = Vector2(100, UI.BTN); url_edit.placeholder_text = "Adresse ou recherche"
	url_edit.text_submitted.connect(_go); UI.bar_center(hbar, url_edit)
	star = UI.bar_act(hbar, en, "star", "Ajouter aux favoris", _toggle_bookmark)
	_hook_chat(hbar)
	var mb := UI.bar_act(hbar, en, "ellipsis-vertical", "Menu", func(): pass)
	for c in mb.pressed.get_connections(): mb.pressed.disconnect(c["callable"])
	mb.pressed.connect(func(): _menu(mb.get_global_rect().position + Vector2(0, bh)))
	bm_bar = HBoxContainer.new(); bm_bar.add_theme_constant_override("separation", 2); v.add_child(bm_bar)
	var body := HBoxContainer.new(); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 0); v.add_child(body)
	view = TextureRect.new(); view.size_flags_vertical = Control.SIZE_EXPAND_FILL; view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; view.clip_contents = true; body.add_child(view)

func _nav(what: String) -> void:
	if wv:
		if what == "back": wv.back()
		elif what == "fwd": wv.forward()
		else: wv.reload()
	elif browser and is_instance_valid(browser):
		if what == "back": browser.previous_page()
		elif what == "fwd": browser.next_page()
		else: browser.reload()

func _start() -> void:
	_clear()
	if not ClassDB.class_exists("GdCEF"):
		var r := GDExtensionManager.load_extension(_g(DIR + "/gdcef.gdextension"))
		if not ClassDB.class_exists("GdCEF"):
			_build_install(); info.text = "Impossible de charger l'extension Chromium (statut %d). Supprime le dossier « cef » des données de LangOS pour réinstaller." % r; return
	if Engine.has_meta("lang_cef"): cef = Engine.get_meta("lang_cef")
	else:
		cef = ClassDB.instantiate("GdCEF"); get_tree().root.add_child(cef)
		var L := _g(DIR + "/linux")
		var cfg := {"cache_path": _g("user://cef_cache"), "root_cache_path": _g("user://cef_cache"), "browser_subprocess_path": L + "/gdCefRenderProcess",
				"log_file": _g(DIR + "/debug.log"), "log_severity": "error", "use_gpu": false, "locale": "fr-FR"}
		if core.desktop_mode: cfg["user_agent"] = Core.UA_DESKTOP
		if not cef.initialize(cfg):
			var e: String = cef.get_error(); cef.queue_free(); cef = null
			_build_install(); info.text = "Chromium n'a pas pu démarrer sur cet appareil."; info.tooltip_text = e; info.mouse_filter = Control.MOUSE_FILTER_PASS; return
		Engine.set_meta("lang_cef", cef)
	OS.low_processor_usage_mode = false
	_build_ui(38)
	view.focus_mode = Control.FOCUS_ALL
	view.gui_input.connect(_view_input); view.resized.connect(func(): for b in brs.values(): if is_instance_valid(b): b.resize(view.size))
	await get_tree().process_frame
	_activate(core.active)

## Affiche l'onglet i (crée son navigateur Chromium à la demande).
func _activate(i: int) -> void:
	if i < 0 or i >= core.tabs.size(): return
	core.active = i
	var t: Dictionary = core.tabs[i]
	if wv:
		wv_pending = str(t["url"])
		if wv_opened: wv.load(wv_pending)
	else:
		for k in views: views[k].visible = false
		var id: int = t["id"]
		if not brs.has(id):
			var tv := TextureRect.new(); tv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			view.add_child(tv); views[id] = tv
			var b = cef.create_browser(str(t["url"]), tv, {"javascript": true, "webgl": true, "enable_ad_block": core.adblock, "incognito": bool(t["private"])})
			if b == null: _build_install(); info.text = "Impossible d'ouvrir une page pour le moment. Réessaie."; info.tooltip_text = str(cef.get_error()); info.mouse_filter = Control.MOUSE_FILTER_PASS; return
			brs[id] = b; b.resize(view.size)
			for sg in ["on_download_updated", "on_download_started"]:
				if b.has_signal(sg): b.connect(sg, _on_cef_download)
			for sg in ["on_before_resource_load", "on_resource_request"]:
				if b.has_signal(sg): b.connect(sg, func(u = "", _a = null): core.should_block(str(u)))
		views[id].visible = true
		browser = brs[id]; last_url = ""
		if browser.has_method("set_user_agent") and core.desktop_mode: browser.call("set_user_agent", Core.UA_DESKTOP)
	_refresh_tabs(); _sync_url(str(t["url"]))

func _new_tab(url := Core.HOME, priv := false) -> void:
	core.open_tab(url, priv); _activate(core.active); core.save()

func _close_tab(i: int) -> void:
	var id: int = core.tabs[i]["id"]
	if brs.has(id):
		if is_instance_valid(brs[id]): brs[id].close()
		brs.erase(id); views[id].queue_free(); views.erase(id); browser = null
	core.close_tab(i); _activate(core.active); core.save()

func _refresh_tabs() -> void:
	for c in tab_row.get_children(): c.queue_free()
	for i in core.tabs.size():
		var t: Dictionary = core.tabs[i]
		var b := Button.new(); b.toggle_mode = true; b.button_pressed = i == core.active; b.focus_mode = Control.FOCUS_NONE
		var tt := str(t["title"]); b.text = tt.substr(0, 18) + "…" if tt.length() > 19 else tt
		if t["private"]: UI.set_icon(b, "glasses")
		b.custom_minimum_size.x = 120; b.tooltip_text = str(t["url"])
		b.pressed.connect(func(): _activate(i))
		b.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT: _tab_menu(i, ev.global_position)
			elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_MIDDLE: _close_tab(i))
		tab_row.add_child(b)
		tab_row.add_child(UI.icon_btn("x", "Fermer l'onglet", func(): _close_tab(i), "Flat", 28))
	tab_row.add_child(UI.icon_btn("plus", "Nouvel onglet", func(): _new_tab(), "Flat", 28))
	_refresh_bm()

func _tab_menu(i: int, at: Vector2) -> void:
	var m := _main()
	if m == null or not m.has_method("_popup_menu"): return
	var items: Array = [["Fermer l'onglet", func(): _close_tab(i)]]
	if i > 0: items.append(["Déplacer à gauche", func(): core.move_tab(i, i - 1); _refresh_tabs(); core.save()])
	if i < core.tabs.size() - 1: items.append(["Déplacer à droite", func(): core.move_tab(i, i + 1); _refresh_tabs(); core.save()])
	m._popup_menu(items, at)

func _refresh_bm() -> void:
	for c in bm_bar.get_children(): c.queue_free()
	for it in core.bookmarks:
		var b := Button.new(); b.flat = true; b.focus_mode = Control.FOCUS_NONE
		if it["t"] == "b":
			b.text = str(it["name"]).substr(0, 16); b.pressed.connect(func(): _go(str(it["url"])))
		else:
			b.text = str(it["name"]).substr(0, 14); UI.set_icon(b, "folder")
			b.pressed.connect(func():
				var items := []
				for s in it["items"]:
					if s["t"] == "b": items.append([str(s["name"]), func(): _go(str(s["url"]))])
				if not items.is_empty(): _main()._popup_menu(items, b.get_global_rect().position + Vector2(0, b.size.y)))
		bm_bar.add_child(b)
	bm_bar.visible = not core.bookmarks.is_empty()
	if star: UI.set_icon(star, "star"); star.theme_type_variation = "FlatOn" if core.find_bookmark(current_url()) else "Flat"

func _sync_url(u: String) -> void:
	last_url = u
	if url_edit and not url_edit.has_focus(): url_edit.text = u
	var i: int = core.active
	if i < core.tabs.size():
		var changed: bool = core.tabs[i]["url"] != u
		core.navigated(i, u, _title_of(u) if changed else "")
		if changed: _refresh_tabs()
	if star: star.theme_type_variation = "FlatOn" if core.find_bookmark(u) else "Flat"

func _title_of(u: String) -> String:
	var h: String = Core.host_of(u)
	return h if h != "" else u

func _toggle_bookmark() -> void:
	var u := current_url()
	if u == "": return
	if core.find_bookmark(u): _toast("Déjà dans les favoris"); return
	core.add_bookmark(str(core.current()["title"]), u); core.save(); _refresh_bm(); _toast("Favori ajouté", u)

func _go(t: String) -> void:
	t = t.strip_edges()
	if t == "" or (browser == null and wv == null): return
	if not (t.begins_with("http://") or t.begins_with("https://") or t.begins_with("file://")):
		t = "https://" + t if (t.contains(".") and not t.contains(" ")) else "https://duckduckgo.com/?q=" + t.uri_encode()
	if core.should_block(t): _toast("Adresse bloquée par le bloqueur de publicités"); return
	if wv: wv.load(t)
	else: browser.load_url(t); view.grab_focus()

func _view_input(ev: InputEvent) -> void:
	if browser == null or not is_instance_valid(browser): return
	if ev is InputEventMouseMotion: browser.set_mouse_moved(int(ev.position.x), int(ev.position.y))
	elif ev is InputEventMouseButton:
		view.grab_focus()
		browser.set_mouse_moved(int(ev.position.x), int(ev.position.y))
		match ev.button_index:
			MOUSE_BUTTON_LEFT: browser.call("set_mouse_left_" + ("down" if ev.pressed else "up"))
			MOUSE_BUTTON_RIGHT: browser.call("set_mouse_right_" + ("down" if ev.pressed else "up"))
			MOUSE_BUTTON_MIDDLE: browser.call("set_mouse_middle_" + ("down" if ev.pressed else "up"))
			MOUSE_BUTTON_WHEEL_UP: browser.set_mouse_wheel_vertical(2, ev.shift_pressed, ev.ctrl_pressed, ev.alt_pressed)
			MOUSE_BUTTON_WHEEL_DOWN: browser.set_mouse_wheel_vertical(-2, ev.shift_pressed, ev.ctrl_pressed, ev.alt_pressed)

func _input(ev: InputEvent) -> void:
	if browser == null or not is_instance_valid(browser) or not (ev is InputEventKey) or get_viewport().gui_get_focus_owner() != view: return
	browser.set_key_pressed(ev.unicode if ev.unicode != 0 else ev.keycode, ev.pressed, ev.shift_pressed, ev.alt_pressed, ev.is_command_or_control_pressed())
	get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- Menu, fenêtres, impression

func _can_print() -> bool: return browser != null and is_instance_valid(browser) and (browser.has_method("print_to_pdf") or browser.has_method("print"))

func _menu(at: Vector2) -> void:
	var m := _main()
	if m == null or not m.has_method("_popup_menu"): return
	var items: Array = [
		["Nouvel onglet", func(): _new_tab()],
		["Onglet privé", func(): _new_tab(Core.HOME, true)],
		["Nouvelle fenêtre", _new_window],
		null,
		["Favoris…", func(): _show_panel("Favoris", _page_bookmarks)],
		["Historique…", func(): _show_panel("Historique", _page_history)],
		["Téléchargements…", func(): _show_panel("Téléchargements", _page_downloads)],
		["Mots de passe…", func(): _show_panel("Mots de passe", _page_vault)],
		null,
		[("✓ " if core.desktop_mode else "") + "Mode ordinateur", _toggle_desktop],
		[("✓ " if core.adblock else "") + "Bloqueur de pub (%d bloquées)" % core.blocked, func(): core.adblock = not core.adblock; core.save()],
	]
	if _can_print(): items.append(["Imprimer / PDF", _print_pdf])
	m._popup_menu(items, at)

func _toggle_desktop() -> void:
	core.desktop_mode = not core.desktop_mode; core.save()
	if wv and wv.has_method("setDesktopMode"): wv.setDesktopMode(core.desktop_mode)
	elif browser and browser.has_method("set_user_agent"): browser.call("set_user_agent", Core.UA_DESKTOP if core.desktop_mode else "")
	_nav("reload")

func _new_window() -> void:
	var m := _main()
	if m and m.has_method("_open_browser_window"): m._open_browser_window()

func _print_pdf() -> void:
	var out := _g("user://downloads"); DirAccess.make_dir_recursive_absolute(out)
	var f := out + "/page_%d.pdf" % int(Time.get_unix_time_from_system())
	if browser.has_method("print_to_pdf"): browser.call("print_to_pdf", f)
	else: browser.call("print", f)
	_toast("Export PDF demandé", f)

# ---------------------------------------------------------------- Panneaux modaux

func _show_panel(title: String, builder: Callable) -> void:
	if panel and is_instance_valid(panel): panel.queue_free()
	panel = PanelContainer.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new(); sb.bg_color = _pal("popup", Color("1b1f2a")); sb.set_content_margin_all(12); panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); panel.add_child(v)
	var h := HBoxContainer.new(); v.add_child(h)
	var l := Label.new(); l.text = title; l.add_theme_font_size_override("font_size", 22); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(l)
	var x := Button.new(); x.text = "Fermer"; x.pressed.connect(func(): panel.queue_free(); panel = null; core.save()); h.add_child(x)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; v.add_child(sc)
	var body := VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 4); sc.add_child(body)
	builder.call(body)

func _row(body: Control, text: String, buttons: Array, muted := false) -> void:
	var h := HBoxContainer.new(); body.add_child(h)
	var l := Label.new(); l.text = text; l.clip_text = true; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if muted: l.theme_type_variation = "Muted"
	h.add_child(l)
	for b in buttons:
		var bt := Button.new(); bt.text = b[0]; bt.pressed.connect(b[1]); h.add_child(bt)

func _redo(builder: Callable, body: Control) -> void:
	for c in body.get_children(): c.queue_free()
	builder.call(body)

func _page_bookmarks(body: Control) -> void:
	var h := HBoxContainer.new(); body.add_child(h)
	var ne := LineEdit.new(); ne.placeholder_text = "Nom du dossier"; ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(ne)
	var nb := Button.new(); nb.text = "Créer un dossier"; h.add_child(nb)
	nb.pressed.connect(func():
		if ne.text.strip_edges() != "": core.add_folder(ne.text.strip_edges()); core.save(); _refresh_bm(); _redo(_page_bookmarks, body))
	var cb := Button.new(); cb.text = "Ajouter la page actuelle"; h.add_child(cb)
	cb.pressed.connect(func(): if current_url() != "": core.add_bookmark(str(core.current()["title"]), current_url()); core.save(); _refresh_bm(); _redo(_page_bookmarks, body))
	_bm_list(body, core.bookmarks, [], 0)

func _bm_list(body: Control, l: Array, path: Array, depth: int) -> void:
	for i in l.size():
		var it: Dictionary = l[i]; var pre := "      ".repeat(depth)
		var del: Array = ["Supprimer", func(): core.remove_item(i, path); core.save(); _refresh_bm(); _redo(_page_bookmarks, body)]
		if it["t"] == "f":
			var np := path + [i]
			_row(body, pre + str(it["name"]), [["Ajouter la page", func(): core.add_bookmark(str(core.current()["title"]), current_url(), np); core.save(); _redo(_page_bookmarks, body)], del])
			_bm_list(body, it["items"], np, depth + 1)
		else:
			_row(body, pre + str(it["name"]) + "  " + str(it["url"]), [["Ouvrir", func(): _go(str(it["url"])); panel.queue_free(); panel = null], del])

func _page_history(body: Control) -> void:
	var h := HBoxContainer.new(); body.add_child(h)
	var q := LineEdit.new(); q.placeholder_text = "Rechercher"; q.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(q)
	var cl := Button.new(); cl.text = "Tout effacer"; cl.pressed.connect(func(): core.history.clear(); core.save(); _redo(_page_history, body)); h.add_child(cl)
	var lst := VBoxContainer.new(); body.add_child(lst)
	var fill := func(t: String):
		for c in lst.get_children(): c.queue_free()
		for e in core.search_history(t).slice(0, 100):
			_row(lst, "%s  %s" % [Time.get_datetime_string_from_unix_time(int(e["time"])).replace("T", " ").substr(0, 16), e["title"] if str(e["title"]) != "" else e["url"]],
				[["Ouvrir", func(): _go(str(e["url"])); panel.queue_free(); panel = null]])
	q.text_changed.connect(fill); fill.call("")

func _page_downloads(body: Control) -> void:
	var h := HBoxContainer.new(); body.add_child(h)
	var ue := LineEdit.new(); ue.placeholder_text = "Adresse du fichier à télécharger"; ue.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(ue)
	var go := Button.new(); go.text = "Télécharger"; go.pressed.connect(func(): _download_url(ue.text.strip_edges()); _redo(_page_downloads, body)); h.add_child(go)
	var fo := Button.new(); fo.text = "Ouvrir le dossier"; fo.pressed.connect(_open_dl_dir); h.add_child(fo)
	for d in core.downloads:
		var pb := ProgressBar.new(); pb.value = Core.dl_percent(d); pb.custom_minimum_size.y = 10; pb.show_percentage = false
		_row(body, "%s  (%s, %d%%)" % [d["name"], {"run": "en cours", "done": "terminé", "fail": "échec"}[d["state"]], Core.dl_percent(d)], [])
		body.add_child(pb)
	if core.downloads.is_empty(): _row(body, "Aucun téléchargement.", [], true)

func _dl_dir() -> String:
	var d := _g("user://downloads"); DirAccess.make_dir_recursive_absolute(d); return d

func _open_dl_dir() -> void: OS.shell_open(_dl_dir())

func _download_url(u: String) -> void:
	if not u.begins_with("http"): return
	var name := u.get_file().get_slice("?", 0)
	if name == "": name = "telechargement_%d" % int(Time.get_unix_time_from_system())
	var path := _dl_dir() + "/" + name
	var id: int = core.dl_start(u, path)
	var r := HTTPRequest.new(); r.download_file = path; r.use_threads = true; r.max_redirects = 8; add_child(r); dl_reqs[id] = r
	r.request_completed.connect(func(res: int, code: int, _h, _b):
		var ok := res == HTTPRequest.RESULT_SUCCESS and code == 200
		var fin: bool = core.dl_update(id, r.get_downloaded_bytes(), r.get_body_size(), ok, not ok)
		if fin: _toast("Téléchargement terminé", name)
		elif not ok: _toast("Échec du téléchargement", name)
		dl_reqs.erase(id); r.queue_free())
	if r.request(u) != OK: core.dl_update(id, 0, -1, false, true); dl_reqs.erase(id); r.queue_free()

## Signal éventuel du moteur (si gdCEF l'expose) : mêmes mises à jour que ci-dessus.
func _on_cef_download(a = null, b = null, c = null, d = null) -> void:
	var name := str(a) if a is String else "fichier"
	var id: int = core.dl_start("", _dl_dir() + "/" + name)
	if c is int or c is float: core.dl_update(id, int(b) if b is int else 0, int(c), bool(d))

func _poll_downloads() -> void:
	for id in dl_reqs:
		var r: HTTPRequest = dl_reqs[id]
		if is_instance_valid(r): core.dl_update(id, r.get_downloaded_bytes(), r.get_body_size())

func _page_vault(body: Control) -> void:
	if vault_pw == "":
		var l := Label.new(); body.add_child(l)
		l.text = "Coffre chiffré (AES-256). Le mot de passe maître n'est jamais enregistré." if not core.vault_exists() else "Entre le mot de passe maître pour déverrouiller."
		var pe := LineEdit.new(); pe.secret = true; pe.placeholder_text = "Mot de passe maître"; body.add_child(pe)
		var ok := Button.new(); ok.text = "Créer le coffre" if not core.vault_exists() else "Déverrouiller"; body.add_child(ok)
		var go := func():
			if pe.text == "": return
			if core.vault_exists():
				var r = core.vault_load(pe.text)
				if r == null: l.text = "Mot de passe maître incorrect."; return
				vault_entries = r
			else:
				vault_entries = []; core.vault_save(vault_entries, pe.text)
			vault_pw = pe.text; _redo(_page_vault, body)
		ok.pressed.connect(go); pe.text_submitted.connect(func(_t): go.call()); return
	var h := HBoxContainer.new(); body.add_child(h)
	var fs := []
	for ph in ["Site", "Identifiant", "Mot de passe"]:
		var e := LineEdit.new(); e.placeholder_text = ph; e.size_flags_horizontal = Control.SIZE_EXPAND_FILL; e.secret = ph == "Mot de passe"; h.add_child(e); fs.append(e)
	var ad := Button.new(); ad.text = "Ajouter"; h.add_child(ad)
	ad.pressed.connect(func():
		if fs[0].text != "": vault_entries.append({"site": fs[0].text, "user": fs[1].text, "pw": fs[2].text}); core.vault_save(vault_entries, vault_pw); _redo(_page_vault, body))
	var lk := Button.new(); lk.text = "Verrouiller"; lk.pressed.connect(func(): vault_pw = ""; vault_entries = []; _redo(_page_vault, body)); h.add_child(lk)
	for i in vault_entries.size():
		var e: Dictionary = vault_entries[i]
		_row(body, "%s  —  %s" % [e["site"], e["user"]], [["Copier le mot de passe", func(): DisplayServer.clipboard_set(str(e["pw"])); _toast("Mot de passe copié")],
			["Supprimer", func(): vault_entries.remove_at(i); core.vault_save(vault_entries, vault_pw); _redo(_page_vault, body)]])

# ---------------------------------------------------------------- Android : WebView natif superposé

var wv_pending := ""
var wv_opened := false

func _start_android() -> void:
	_clear()
	wv = Engine.get_singleton("LangWebView")
	wv.connect("url_changed", func(u: String): _sync_url(u))
	_build_ui(44)
	shade = ColorRect.new(); shade.color = UI.p("popup"); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); shade.visible = false; view.add_child(shade)
	var sl := Label.new(); sl.text = "Navigateur en arrière-plan\nClique ici pour le remettre au premier plan"; sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.theme_type_variation = "Muted"; sl.set_anchors_and_offsets_preset(Control.PRESET_CENTER); sl.grow_horizontal = Control.GROW_DIRECTION_BOTH; sl.grow_vertical = Control.GROW_DIRECTION_BOTH; shade.add_child(sl)
	shade.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed: get_tree().current_scene._show("chromium"))
	_refresh_tabs()
	await get_tree().process_frame; await get_tree().process_frame
	wv_rect = _screen_rect()
	wv.open(str(core.current()["url"]), wv_rect.position.x, wv_rect.position.y, wv_rect.size.x, wv_rect.size.y); wv_shown = true; wv_opened = true
	if wv.has_method("setDesktopMode"): wv.setDesktopMode(core.desktop_mode)

## Zone de la page en pixels d'écran (la fenêtre Godot occupe tout l'écran sous Android).
func _screen_rect() -> Rect2i:
	var r: Rect2 = get_viewport().get_final_transform() * view.get_global_rect()
	return Rect2i(Vector2i(r.position), Vector2i(r.size))

## Le WebView est une vue native au-dessus de Godot : on la cale sur la fenêtre et on la cache si celle-ci n'est pas visible
## (fenêtre réduite ou menu Démarrer ouvert).
func _sync_wv() -> void:
	if view == null: return
	var main := get_tree().current_scene
	var shown := is_visible_in_tree()
	if main:
		# Le WebView est une vue native toujours au-dessus de Godot : il ne doit apparaître que si cette fenêtre est au premier plan
		# et qu'aucun menu (Démarrer, copier/coller) ne la recouvre.
		if str(main.get("active")) != str(get_meta("win_id", "chromium")): shown = false
		if panel and is_instance_valid(panel): shown = false
		if main.get("menu") and main.menu.visible: shown = false
		var cm = main.get("ctx_menu")
		if cm != null and is_instance_valid(cm) and cm.visible: shown = false
	if shade: shade.visible = is_visible_in_tree() and not shown
	if shown != wv_shown: wv_shown = shown; wv.setShown(shown)
	if not shown: return
	var r := _screen_rect()
	# Le clavier visuel de LangOS passe devant : le WebView s'arrête à son bord supérieur.
	if main and main.get("kb") and main.kb.visible:
		var top := int((get_viewport().get_final_transform() * main.kb.get_global_rect()).position.y)
		r.size.y = maxi(1, mini(r.end.y, top) - r.position.y)
	if r != wv_rect: wv_rect = r; wv.place(r.position.x, r.position.y, r.size.x, r.size.y)

# ---------------------------------------------------------------- Lien avec Chat IA
## Le navigateur se déclare auprès de ChatCore (browser_hook) : Chat IA peut alors lire la page affichée et ouvrir une adresse.

func _chat_core() -> Object:
	var m := get_tree().current_scene
	return m.get("chat_core") if m else null

func _hook_chat(bar: Control) -> void:
	UI.bar_act(bar, UI.bar_end(bar), "message-circle", "Discuter de cette page avec Chat IA", func():
		var core = _chat_core()
		if core: core.page_ctx = true; core.changed.emit()
		get_tree().current_scene._open_app("chat"))
	var core = _chat_core()
	if core: core.browser_hook = self
	tree_exiting.connect(func():
		var c = _chat_core()
		if c and c.browser_hook == self: c.browser_hook = null; c.page_ctx = false)

## Texte visible de la page (tronqué), vide si indisponible.
func get_page_text() -> String:
	var t := ""
	if wv:
		wv.getText()
		var r = await Signal(wv, "page_text")
		var j = JSON.parse_string(str(r))
		t = str(j) if j != null else str(r)
	elif browser and is_instance_valid(browser):
		browser.request_html_content()
		var a = await browser.on_html_content_requested
		var html: String = a[0] if a is Array else str(a)
		for rx in ["(?s)<(script|style|noscript)[^>]*>.*?</\\1>", "<[^>]+>", "&nbsp;", "[ \\t\\r\\n]+"]:
			html = RegEx.create_from_string(rx).sub(html, " ", true)
		t = html.strip_edges()
	return t.substr(0, 5000)

func current_url() -> String: return last_url

func open_url(u: String) -> void: _go(u)
