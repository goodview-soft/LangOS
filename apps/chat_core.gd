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
var api_key := ""                   # clé API Claude (optionnelle) : ajoute les modèles « claude:… » (Haiku par défaut, le moins cher)
const CLAUDE_MODELS := {"claude:claude-haiku-5-5": "☁ Claude Haiku 5.5 (économique)", "claude:claude-sonnet-5-5": "☁ Claude Sonnet 5.5", "claude:claude-opus-5-5": "☁ Claude Opus 5.5 (cher)"}
var available: Array = []
var messages: Array = []     # {role: user|assistant, content}
var is_busy := false
var note := ""                      # état affiché quand aucun modèle n'est disponible
var _scanning := false
var _scan_t := -100000
signal server_found(url: String)
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


## Liste des modèles d'un serveur Ollama ([] si injoignable).
func _tags(url: String) -> Array:
	var http := HTTPRequest.new(); http.timeout = 4; add_child(http)
	if http.request(url + "/api/tags") != OK: http.queue_free(); return []
	var r = await http.request_completed
	http.queue_free()
	var out := []
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200: return out
	var d = JSON.parse_string(r[3].get_string_from_utf8())
	if d is Dictionary:
		for m in d.get("models", []):
			var n := str(m["name"])
			if not "embed" in n: out.append(n)
	return out


## Cherche un serveur Ollama (port 11434) sur le réseau local : renvoie son adresse ou "".
func _discover() -> String:
	var bases := []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and (a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172.")): bases.append(a.substr(0, a.rfind(".") + 1))
	var peers := []
	for b in bases.slice(0, 2):
		for i in range(1, 255):
			var p := StreamPeerTCP.new()
			if p.connect_to_host(b + str(i), 11434) == OK: peers.append([p, b + str(i)])
	var found := []
	var t0 := Time.get_ticks_msec()
	while not peers.is_empty() and Time.get_ticks_msec() - t0 < 2500:
		await get_tree().process_frame
		for e in peers.duplicate():
			e[0].poll()
			var st: int = e[0].get_status()
			if st == StreamPeerTCP.STATUS_CONNECTED: found.append(e[1]); e[0].disconnect_from_host(); peers.erase(e)
			elif st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE: peers.erase(e)
	for e in peers: e[0].disconnect_from_host()
	for ip in found:
		var u: String = "http://" + str(ip) + ":11434"
		if not (await _tags(u)).is_empty(): return u
	return ""


func refresh_models() -> void:
	var names: Array = await _tags(ollama_url)
	if names.is_empty() and api_key == "" and not _scanning and Time.get_ticks_msec() - _scan_t > 60000:
		_scanning = true; _scan_t = Time.get_ticks_msec(); note = "Recherche d'Ollama sur le réseau local…"; changed.emit()
		var u: String = await _discover()
		_scanning = false
		if u != "":
			ollama_url = u; names = await _tags(u); server_found.emit(u)
	available = names.duplicate()
	if api_key != "": available.append_array(CLAUDE_MODELS.keys())
	if model == "" or not model in available:
		model = ""
		for p in PREFS:
			if p in available: model = p; break
		if model == "" and not names.is_empty(): model = names[0]
		if model == "" and api_key != "": model = "claude:claude-haiku-5-5"
	note = "" if not available.is_empty() else "Aucun modèle sur %s. Ollama doit tourner sur un PC du réseau (OLLAMA_HOST=0.0.0.0), ou ajoute une clé API Claude dans Paramètres." % ollama_url
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
	if model.begins_with("claude:"):
		await _ask_claude(sys, messages.slice(maxi(0, messages.size() - 12)))
		return
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
	_finish(c)


## Fin de réponse : exécute l'éventuel [[OUVRIR url]] du navigateur puis affiche.
func _finish(c: String) -> void:
	if page_ctx and browser_hook != null and is_instance_valid(browser_hook):
		var m := RegEx.create_from_string("\\[\\[OUVRIR\\s+([^\\]\\s]+)\\]\\]").search(c)
		if m:
			c = c.replace(m.get_string(), "").strip_edges() + "\n(ouverture de %s)" % m.get_string(1); browser_hook.open_url(m.get_string(1))
	_reply(c if c != "" else "(réponse vide)")


## API Claude (messages) : max_tokens bas, historique court.
func _ask_claude(sys: String, hist: Array) -> void:
	var body := {"model": model.substr(7), "max_tokens": 600, "system": sys, "messages": hist}
	var http := HTTPRequest.new(); http.timeout = 90; add_child(http)
	var hdr := ["content-type: application/json", "x-api-key: " + api_key, "anthropic-version: 2023-06-01"]
	if http.request("https://api.anthropic.com/v1/messages", hdr, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		http.queue_free(); _reply("⚠ Requête impossible."); return
	var r = await http.request_completed
	http.queue_free()
	var d = JSON.parse_string(r[3].get_string_from_utf8()) if r[0] == HTTPRequest.RESULT_SUCCESS else null
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200 or not (d is Dictionary):
		var why := "pas de connexion"
		if d is Dictionary and d.has("error"): why = str(d["error"].get("message", "erreur"))
		elif r[1] == 401: why = "clé API refusée"
		_reply("⚠ Claude : " + why); return
	var txt := ""
	for blk in d.get("content", []):
		if blk.get("type", "") == "text": txt += str(blk.get("text", ""))
	_finish(txt.strip_edges())


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
