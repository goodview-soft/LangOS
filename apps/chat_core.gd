class_name ChatCore
extends Node
## Moteur du chat IA local (Ollama) : historique partagé entre l'application « Chat IA » et l'overlay.

signal changed
signal busy_changed(on: bool)

const PATH := "user://chat_ai.json"
const SYSTEM := "Tu es l'assistant IA local de LangOS. Réponds en français, de façon brève et directe (2 à 4 phrases sauf si on demande plus). Pour « comment dit-on X en <langue> » : donne d'abord la phrase dans la langue demandée, puis la prononciation entre parenthèses si utile. Si tu n'es pas sûr, dis-le."
const PREFS := ["gemma3:4b", "llama3.1:8b", "qwen3:8b", "llama3.2:3b", "qwen3:14b"]

var ollama_url := "http://127.0.0.1:11434"
var model := ""
var available: Array = []
var messages: Array = []     # {role: user|assistant, content}
var is_busy := false
var browser_hook: Object            # navigateur ouvert (get_page_text / current_url / open_url) ou null
var page_ctx := false               # « Page web » : le modèle voit la page du navigateur et peut ouvrir une adresse
const PAGE_SYS := "\nLe navigateur de LangOS est ouvert. Tu vois le texte de la page affichée (tronqué) ci-dessous. Pour ouvrir un site, écris sur une ligne [[OUVRIR https://adresse]]."


func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			messages = d.get("messages", []); model = str(d.get("model", ""))


func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"model": model, "messages": messages.slice(maxi(0, messages.size() - 80))})); f.close()


func clear() -> void:
	messages = []; _save(); changed.emit()


func set_model(m: String) -> void:
	model = m; _save()


func refresh_models() -> void:
	var http := HTTPRequest.new(); http.timeout = 8; add_child(http)
	if http.request(ollama_url + "/api/tags") != OK: http.queue_free(); return
	var r = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200: return
	var d = JSON.parse_string(r[3].get_string_from_utf8())
	available = []
	if d is Dictionary:
		for m in d.get("models", []):
			var n := str(m["name"])
			if not "embed" in n: available.append(n)
	if model == "" or not model in available:
		model = ""
		for p in PREFS:
			if p in available: model = p; break
		if model == "" and not available.is_empty(): model = available[0]
	changed.emit()


func ask(text: String) -> void:
	text = text.strip_edges()
	if text == "" or is_busy: return
	messages.append({"role": "user", "content": text}); changed.emit()
	_set_busy(true)
	if model == "": await refresh_models()
	if model == "":
		_reply("⚠ Ollama introuvable. Lance-le sur le PC (ou règle l'adresse du serveur dans Paramètres).")
		return
	var sys := SYSTEM
	if page_ctx:
		if browser_hook != null and is_instance_valid(browser_hook):
			var pg: String = await browser_hook.get_page_text()
			sys += PAGE_SYS + "\nAdresse : " + browser_hook.current_url() + "\nTexte de la page :\n" + pg
		else:
			sys += "\nL'option « Page web » est activée mais le navigateur n'est pas ouvert : dis à l'utilisateur d'ouvrir Logiciels > Chromium."
	var msgs := [{"role": "system", "content": sys}]
	msgs.append_array(messages.slice(maxi(0, messages.size() - 20)))
	var body := {"model": model, "stream": false, "think": false, "keep_alive": "3m",
		"options": {"temperature": 0.4, "num_predict": 600}, "messages": msgs}
	var http := HTTPRequest.new(); http.timeout = 180; add_child(http)
	if http.request(ollama_url + "/api/chat", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		http.queue_free(); _reply("⚠ Requête impossible."); return
	var r = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		_reply("⚠ Pas de réponse du modèle (Ollama arrêté ou modèle absent ?)."); return
	var d = JSON.parse_string(r[3].get_string_from_utf8())
	var c := str(d.get("message", {}).get("content", "")) if d is Dictionary else ""
	c = RegEx.create_from_string("(?s)<think>.*?</think>").sub(c, "", true).strip_edges()
	if page_ctx and browser_hook != null and is_instance_valid(browser_hook):
		var m := RegEx.create_from_string("\\[\\[OUVRIR\\s+([^\\]\\s]+)\\]\\]").search(c)
		if m:
			c = c.replace(m.get_string(), "").strip_edges() + "\n(ouverture de %s)" % m.get_string(1); browser_hook.open_url(m.get_string(1))
	_reply(c if c != "" else "(réponse vide)")


func _reply(t: String) -> void:
	messages.append({"role": "assistant", "content": t}); _save(); _set_busy(false); changed.emit()


func _set_busy(on: bool) -> void:
	is_busy = on; busy_changed.emit(on)


## Bulle de conversation (texte sélectionnable).
static func bubble(role: String, text: String, maxw: float, fs: int, font: Font) -> Control:
	var row := HBoxContainer.new()
	var mine := role == "user"
	if mine:
		var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(sp)
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("2b5fb8") if mine else Color("2a3040"); sb.set_corner_radius_all(12); sb.set_content_margin_all(9)
	pc.add_theme_stylebox_override("panel", sb); row.add_child(pc)
	var l := RichTextLabel.new(); l.text = text; l.fit_content = true; l.scroll_active = false; l.selection_enabled = true; l.context_menu_enabled = true
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.add_theme_font_size_override("normal_font_size", fs)
	var w := font.get_string_size(text.get_slice("\n", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font else maxw
	l.custom_minimum_size.x = clampf(w + 10, 60, maxw)
	pc.add_child(l)
	if not mine:
		var sp2 := Control.new(); sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(sp2)
	return row
