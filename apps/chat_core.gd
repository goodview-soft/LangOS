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
const DEVICE_MODEL := "device:qwen2.5-1.5b"
const DEVICE_FILE := "user://models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
const DEVICE_URL := "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"
const DEVICE_MIN := 1000000000
const LABELS := {"device:qwen2.5-1.5b": "📱 Sur l'appareil (Qwen 1.5B, hors ligne)", "claude:claude-haiku-5-5": "☁ Claude Haiku 5.5 (économique)", "claude:claude-sonnet-5-5": "☁ Claude Sonnet 5.5", "claude:claude-opus-5-5": "☁ Claude Opus 5.5 (cher)"}
const TOOLS := [
	{"name": "lire_page", "description": "Lit la page affichée : adresse, texte et liste numérotée des éléments cliquables ou saisissables.", "input_schema": {"type": "object", "properties": {}}},
	{"name": "ouvrir", "description": "Ouvre une adresse web dans le navigateur.", "input_schema": {"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}},
	{"name": "cliquer", "description": "Clique sur l'élément numéro `index` (numéros donnés par lire_page).", "input_schema": {"type": "object", "properties": {"index": {"type": "integer"}}, "required": ["index"]}},
	{"name": "saisir", "description": "Écrit `texte` dans le champ numéro `index`, puis valide (Entrée) si `valider` est vrai.", "input_schema": {"type": "object", "properties": {"index": {"type": "integer"}, "texte": {"type": "string"}, "valider": {"type": "boolean"}}, "required": ["index", "texte"]}},
	{"name": "defiler", "description": "Fait défiler la page vers le bas ou le haut.", "input_schema": {"type": "object", "properties": {"sens": {"type": "string", "enum": ["bas", "haut"]}}, "required": ["sens"]}},
]
const AGENT_SYS := "\nTu peux piloter le navigateur de LangOS avec les outils (lire_page, ouvrir, cliquer, saisir, defiler). Commence par lire_page si besoin, agis par petites étapes, et arrête-toi dès que la demande est satisfaite. Demande confirmation à l'utilisateur avant tout achat, envoi de formulaire ou action irréversible, et ne saisis jamais de mot de passe ni de donnée bancaire."
const CLAUDE_MODELS := {"claude:claude-haiku-5-5": "☁ Claude Haiku 5.5 (économique)", "claude:claude-sonnet-5-5": "☁ Claude Sonnet 5.5", "claude:claude-opus-5-5": "☁ Claude Opus 5.5 (cher)"}
var available: Array = []
var messages: Array = []     # {role: user|assistant, content}
var is_busy := false
var note := ""                      # état affiché quand aucun modèle n'est disponible
var _scanning := false
var _llm: Object
var _dl: HTTPRequest
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
	if ClassDB.class_exists("GDLlama"): available.append(DEVICE_MODEL)
	if model == "" or not model in available:
		model = ""
		for p in PREFS:
			if p in available: model = p; break
		if model == "" and not names.is_empty(): model = names[0]
		if model == "" and api_key != "": model = "claude:claude-haiku-5-5"
		if model == "" and ClassDB.class_exists("GDLlama"): model = DEVICE_MODEL
	note = "" if not available.is_empty() else "Aucun modèle sur %s. Ollama doit tourner sur un PC du réseau (OLLAMA_HOST=0.0.0.0), ou ajoute une clé API Claude dans Paramètres, ou choisis « Sur l'appareil »." % ollama_url
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
	var hook_ok := browser_hook != null and is_instance_valid(browser_hook)
	if page_ctx:
		if not hook_ok:
			sys += "\nL'option « Page web » est activée mais le navigateur n'est pas ouvert : dis à l'utilisateur d'ouvrir Logiciels > Chromium."
		elif model.begins_with("claude:"):
			sys += AGENT_SYS + "\nAdresse actuelle : " + browser_hook.current_url()
		else:
			var pg: String = await browser_hook.get_page_text()
			if model == DEVICE_MODEL: pg = pg.substr(0, 2500)
			sys += PAGE_SYS + "\nAdresse : " + browser_hook.current_url() + "\nTexte de la page :\n" + pg
	var msgs := [{"role": "system", "content": sys}]
	msgs.append_array(_hist(20))
	var body := {"model": model, "stream": false, "think": false, "keep_alive": "3m",
		"options": {"temperature": 0.4, "num_predict": 600}, "messages": msgs}
	if model.begins_with("claude:"):
		await _ask_claude(sys, _hist(12), page_ctx and hook_ok)
		return
	if model == DEVICE_MODEL:
		await _ask_device(sys)
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


## API Claude (messages) : max_tokens bas, historique court. Avec `agent`, boucle d'outils qui pilote le navigateur (8 étapes max).
func _ask_claude(sys: String, hist: Array, agent := false) -> void:
	var msgs: Array = hist.duplicate(true)
	var hdr := ["content-type: application/json", "x-api-key: " + api_key, "anthropic-version: 2023-06-01"]
	for step in 8:
		var body := {"model": model.substr(7), "max_tokens": 800, "system": sys, "messages": msgs}
		if agent: body["tools"] = TOOLS
		var http := HTTPRequest.new(); http.timeout = 90; add_child(http)
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
		var content: Array = d.get("content", [])
		var txt := ""
		for blk in content:
			if blk.get("type", "") == "text": txt += str(blk.get("text", ""))
		if str(d.get("stop_reason", "")) != "tool_use":
			_finish(txt.strip_edges()); return
		if txt.strip_edges() != "": messages.append({"role": "tool", "content": txt.strip_edges()})
		msgs.append({"role": "assistant", "content": content})
		var results := []
		for blk in content:
			if blk.get("type", "") != "tool_use": continue
			var inp: Dictionary = blk.get("input", {})
			messages.append({"role": "tool", "content": "🔧 " + _tool_label(str(blk["name"]), inp)}); changed.emit()
			var out: String = await _run_tool(str(blk["name"]), inp)
			results.append({"type": "tool_result", "tool_use_id": blk["id"], "content": out})
		msgs.append({"role": "user", "content": results})
	_reply("⚠ Trop d'étapes : reformule ou découpe la demande.")


func _tool_label(n: String, i: Dictionary) -> String:
	match n:
		"ouvrir": return "ouvre " + str(i.get("url", ""))
		"cliquer": return "clique sur l'élément %d" % int(i.get("index", -1))
		"saisir": return "écrit « %s » dans le champ %d" % [str(i.get("texte", "")).substr(0, 40), int(i.get("index", -1))]
		"defiler": return "défile vers le " + str(i.get("sens", "bas"))
	return "lit la page"


func _run_tool(n: String, i: Dictionary) -> String:
	if browser_hook == null or not is_instance_valid(browser_hook): return "Navigateur fermé."
	var h: Object = browser_hook
	match n:
		"lire_page": return await h.tool_read()
		"ouvrir":
			h.open_url(str(i.get("url", ""))); await get_tree().create_timer(2.5).timeout
			return "Ouvert : " + h.current_url()
		"cliquer": return await h.tool_click(int(i.get("index", -1)))
		"saisir": return await h.tool_type(int(i.get("index", -1)), str(i.get("texte", "")), bool(i.get("valider", false)))
		"defiler": return await h.tool_scroll(str(i.get("sens", "bas")))
	return "Outil inconnu."


## Modèle sur l'appareil (llama.cpp via GDLlama), le même fichier que le Traducteur « sur l'appareil ».
func device_ready() -> bool:
	if not FileAccess.file_exists(DEVICE_FILE): return false
	var f := FileAccess.open(DEVICE_FILE, FileAccess.READ)
	return f != null and f.get_length() > DEVICE_MIN


func _ask_device(sys: String) -> void:
	if not ClassDB.class_exists("GDLlama"): _reply("⚠ Moteur local indisponible sur cet appareil."); return
	if not device_ready(): _reply("⚠ Le modèle « Sur l'appareil » n'est pas téléchargé (≈ 1,1 Go) : appuie sur « Télécharger le modèle » en haut."); return
	if _llm == null:
		_llm = ClassDB.instantiate("GDLlama"); add_child(_llm)
		_llm.set("model_path", ProjectSettings.globalize_path(DEVICE_FILE))
		_llm.set("n_predict", 350); _llm.set("n_ctx", 4096)
		_llm.set("should_output_prompt", false); _llm.set("should_output_special", false)
		_llm.set("n_threads", maxi(2, OS.get_processor_count() / 2))
	var p := "<|im_start|>system\n%s<|im_end|>\n" % sys
	for m in _hist(6): p += "<|im_start|>%s\n%s<|im_end|>\n" % [m["role"], str(m["content"])]
	p += "<|im_start|>assistant\n"
	_llm.call("run_generate_text", p, "", "")
	var t: String = await _llm.generate_text_finished
	_finish(t.get_slice("<|im_end|>", 0).strip_edges())


## Télécharge le modèle « Sur l'appareil » (progression dans `note`).
func download_device_model() -> void:
	if _dl != null: return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://models"))
	_dl = HTTPRequest.new(); _dl.download_chunk_size = 1048576; _dl.timeout = 0.0; add_child(_dl)
	_dl.download_file = ProjectSettings.globalize_path("user://models/chat_model.tmp")
	var tm := Timer.new(); tm.wait_time = 0.7; add_child(tm)
	tm.timeout.connect(func():
		if _dl and _dl.get_body_size() > 0:
			note = "Téléchargement du modèle : %d %%  (%d / %d Mo)" % [100 * _dl.get_downloaded_bytes() / _dl.get_body_size(), _dl.get_downloaded_bytes() / 1048576, _dl.get_body_size() / 1048576]; changed.emit())
	tm.start()
	note = "Téléchargement du modèle…"; changed.emit()
	if _dl.request(DEVICE_URL) != OK:
		note = "Téléchargement impossible (réseau ?)."; _dl.queue_free(); _dl = null; tm.queue_free(); changed.emit(); return
	var r = await _dl.request_completed
	tm.queue_free(); _dl.queue_free(); _dl = null
	var tmp := "user://models/chat_model.tmp"
	var ok: bool = r[0] == HTTPRequest.RESULT_SUCCESS and r[1] == 200 and FileAccess.file_exists(tmp)
	if ok:
		var f := FileAccess.open(tmp, FileAccess.READ); ok = f != null and f.get_length() > DEVICE_MIN
	if ok: DirAccess.rename_absolute(tmp, DEVICE_FILE); note = ""
	else: DirAccess.remove_absolute(tmp); note = "Échec du téléchargement, réessaie."
	changed.emit()


## Historique pour le modèle : seulement user/assistant (les lignes « outil » ne sont qu'affichées).
func _hist(n: int) -> Array:
	var out := []
	for m in messages.slice(maxi(0, messages.size() - n)):
		if m["role"] == "user" or m["role"] == "assistant": out.append(m)
	while not out.is_empty() and out[0]["role"] != "user": out.pop_front()
	return out


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
