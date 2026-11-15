extends Control
## Navigateur intégré (Chromium via l'extension gdCEF), affiché dans une fenêtre du bureau.
## L'extension (~1 Go, Linux x86_64) n'est pas livrée avec LangOS : elle est téléchargée une seule fois
## dans user://cef au premier lancement. Tant qu'elle n'est pas installée, la fenêtre propose l'installation
## ou l'ouverture du Chromium du système (`external`, fourni par le bureau).

const URL_ZIP := "https://github.com/Lecrapouille/gdcef/releases/download/v0.21.0-godot4/gdcef-0.21.0_godot-4.7.zip"
const DIR := "user://cef"
const HOME := "https://duckduckgo.com/"
const ACCENT := Color("5aa2ff")
const MUTED := Color("8f9bb3")

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

func _ready() -> void:
	if _installed() and _supported(): _start()
	else: _build_install()

func _exit_tree() -> void:
	if browser and is_instance_valid(browser): browser.close()
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
	info.add_theme_color_override("font_color", MUTED); box.add_child(info)
	if _supported():
		info.text = "Le navigateur intégré (Chromium) n'est pas encore installé.\nTéléchargement unique d'environ 1 Go, puis il s'ouvre dans cette fenêtre."
		inst_btn = Button.new(); inst_btn.text = "Télécharger et installer"; inst_btn.custom_minimum_size.y = 50; inst_btn.pressed.connect(_download); box.add_child(inst_btn)
		bar = ProgressBar.new(); bar.visible = false; bar.custom_minimum_size.y = 18; box.add_child(bar)
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
	if browser and is_instance_valid(browser):
		var u: String = browser.get_url()
		if u != last_url and not url_edit.has_focus(): last_url = u; url_edit.text = u

func _fail(msg: String) -> void:
	info.text = msg; inst_btn.disabled = false; if bar: bar.visible = false

func _on_downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: _fail("Échec du téléchargement (résultat %d, code HTTP %d). Réessaie." % [result, code]); DirAccess.remove_absolute(_zip()); return
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

# ---------------------------------------------------------------- Navigateur

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
		if not cef.initialize({"cache_path": _g("user://cef_cache"), "root_cache_path": _g("user://cef_cache"), "browser_subprocess_path": L + "/gdCefRenderProcess",
				"log_file": _g(DIR + "/debug.log"), "log_severity": "error", "use_gpu": false, "locale": "fr-FR"}):
			var e: String = cef.get_error(); cef.queue_free(); cef = null
			_build_install(); info.text = "Chromium n'a pas démarré : " + e; return
		Engine.set_meta("lang_cef", cef)
	OS.low_processor_usage_mode = false
	var v := VBoxContainer.new(); v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); v.add_theme_constant_override("separation", 0); add_child(v)
	var tb := HBoxContainer.new(); tb.add_theme_constant_override("separation", 4); v.add_child(tb)
	for it in [["◀", func(): if browser: browser.previous_page()], ["▶", func(): if browser: browser.next_page()], ["⟳", func(): if browser: browser.reload()]]:
		var b := Button.new(); b.text = it[0]; b.custom_minimum_size = Vector2(44, 38); b.focus_mode = Control.FOCUS_NONE; b.pressed.connect(it[1]); tb.add_child(b)
	url_edit = LineEdit.new(); url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; url_edit.placeholder_text = "Adresse ou recherche"
	url_edit.text_submitted.connect(_go); tb.add_child(url_edit)
	view = TextureRect.new(); view.size_flags_vertical = Control.SIZE_EXPAND_FILL; view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; view.focus_mode = Control.FOCUS_ALL; view.clip_contents = true
	view.gui_input.connect(_view_input); view.resized.connect(func(): if browser: browser.resize(view.size)); v.add_child(view)
	await get_tree().process_frame
	browser = cef.create_browser(HOME, view, {"javascript": true, "webgl": true, "enable_ad_block": true})
	if browser == null: _build_install(); info.text = "Impossible de créer le navigateur : " + str(cef.get_error()); return
	browser.resize(view.size)

func _go(t: String) -> void:
	t = t.strip_edges()
	if t == "" or browser == null: return
	if not (t.begins_with("http://") or t.begins_with("https://") or t.begins_with("file://")):
		t = "https://" + t if (t.contains(".") and not t.contains(" ")) else "https://duckduckgo.com/?q=" + t.uri_encode()
	browser.load_url(t); view.grab_focus()

func _view_input(ev: InputEvent) -> void:
	if browser == null: return
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
	if browser == null or not (ev is InputEventKey) or get_viewport().gui_get_focus_owner() != view: return
	browser.set_key_pressed(ev.unicode if ev.unicode != 0 else ev.keycode, ev.pressed, ev.shift_pressed, ev.alt_pressed, ev.is_command_or_control_pressed())
	get_viewport().set_input_as_handled()
