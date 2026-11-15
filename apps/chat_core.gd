class_name ChatCore
extends Node
## Chat IA : modèles locaux qui tournent sur l'appareil (llama.cpp via GDLlama), sans réseau ni compte.
## Historique partagé entre l'application « Chat IA » et l'overlay. Option « Page web » : le modèle voit la page du navigateur.

signal changed
signal busy_changed(on: bool)

const PATH := "user://chat_ai.json"
const SYSTEM := "Tu es l'assistant IA de LangOS, il tourne sur l'appareil. Réponds en français, de façon brève et directe (2 à 4 phrases sauf si on demande plus). Pour « comment dit-on X en <langue> » : donne d'abord la phrase dans la langue demandée, puis la prononciation entre parenthèses si utile. Si tu n'es pas sûr, dis-le."
const PAGE_SYS := "\nLe navigateur de LangOS est ouvert. Tu vois le texte de la page affichée (tronqué) ci-dessous. Pour ouvrir un site, écris sur une ligne [[OUVRIR https://adresse]]."
## Modèles disponibles : id -> libellé, fichier, source, taille minimale attendue (octets).
const MODELS := {
	"qwen2.5-0.5b": {"label": "Rapide (Qwen 0,5B · 0,5 Go)", "file": "user://models/qwen2.5-0.5b-instruct-q4_k_m.gguf", "min": 400000000,
		"url": "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"},
	"qwen2.5-1.5b": {"label": "Équilibré (Qwen 1,5B · 1,1 Go)", "file": "user://models/qwen2.5-1.5b-instruct-q4_k_m.gguf", "min": 1000000000,
		"url": "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"},
	"qwen2.5-3b": {"label": "Plus fin (Qwen 3B · 2 Go)", "file": "user://models/qwen2.5-3b-instruct-q4_k_m.gguf", "min": 1900000000,
		"url": "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf"},
}
const DEFAULT := "qwen2.5-1.5b"

var model := DEFAULT
var available: Array = []           # ids des modèles proposés (toujours tous, si le moteur existe)
var messages: Array = []            # {role: user|assistant|tool, content}
var is_busy := false
var note := ""                      # état affiché (téléchargement, erreur)
var browser_hook: Object            # navigateur ouvert (get_page_text / current_url / open_url) ou null
var page_ctx := false               # « Page web » : le modèle voit la page du navigateur et peut ouvrir une adresse
var _llm: Object
var _llm_model := ""
var _dl: HTTPRequest


func _ready() -> void:
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			messages = d.get("messages", []); model = str(d.get("model", DEFAULT))
	if not MODELS.has(model): model = DEFAULT


func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"model": model, "messages": messages.slice(maxi(0, messages.size() - 80))})); f.close()


func clear() -> void:
	messages = []; _save(); changed.emit()


func set_model(m: String) -> void:
	if not MODELS.has(m): return
	model = m; _save(); changed.emit()


func engine_ok() -> bool: return ClassDB.class_exists("GDLlama")


func model_ready(m := "") -> bool:
	var info: Dictionary = MODELS.get(m if m != "" else model, {})
	if info.is_empty() or not FileAccess.file_exists(info["file"]): return false
	var f := FileAccess.open(info["file"], FileAccess.READ)
	return f != null and f.get_length() > int(info["min"])


func refresh_models() -> void:
	available = MODELS.keys() if engine_ok() else []
	note = "" if engine_ok() else "Le moteur d'IA sur l'appareil n'est pas disponible ici."
	changed.emit()


## Télécharge le modèle choisi (progression dans `note`).
func download_model() -> void:
	if _dl != null or not MODELS.has(model): return
	var info: Dictionary = MODELS[model]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://models"))
	_dl = HTTPRequest.new(); _dl.download_chunk_size = 1048576; _dl.timeout = 0.0; add_child(_dl)
	_dl.download_file = ProjectSettings.globalize_path("user://models/chat_model.tmp")
	var tm := Timer.new(); tm.wait_time = 0.7; add_child(tm)
	tm.timeout.connect(func():
		if _dl and _dl.get_body_size() > 0:
			note = "Téléchargement : %d %%  (%d / %d Mo)" % [100 * _dl.get_downloaded_bytes() / _dl.get_body_size(), _dl.get_downloaded_bytes() / 1048576, _dl.get_body_size() / 1048576]; changed.emit())
	tm.start()
	note = "Téléchargement…"; changed.emit()
	if _dl.request(info["url"]) != OK:
		note = "Téléchargement impossible (réseau ?)."; _dl.queue_free(); _dl = null; tm.queue_free(); changed.emit(); return
	var r = await _dl.request_completed
	tm.queue_free(); _dl.queue_free(); _dl = null
	var tmp := "user://models/chat_model.tmp"
	var ok: bool = r[0] == HTTPRequest.RESULT_SUCCESS and r[1] == 200 and FileAccess.file_exists(tmp)
	if ok:
		var f := FileAccess.open(tmp, FileAccess.READ); ok = f != null and f.get_length() > int(info["min"])
	if ok: DirAccess.rename_absolute(tmp, info["file"]); note = ""
	else: DirAccess.remove_absolute(tmp); note = "Échec du téléchargement, réessaie."
	changed.emit()


func downloading() -> bool: return _dl != null


## Historique pour le modèle : seulement user/assistant.
func _hist(n: int) -> Array:
	var out := []
	for m in messages.slice(maxi(0, messages.size() - n)):
		if m["role"] == "user" or m["role"] == "assistant": out.append(m)
	while not out.is_empty() and out[0]["role"] != "user": out.pop_front()
	return out


func ask(text: String) -> void:
	text = text.strip_edges()
	if text == "" or is_busy: return
	messages.append({"role": "user", "content": text}); changed.emit()
	_set_busy(true)
	if not engine_ok(): _reply("⚠ Le moteur d'IA sur l'appareil n'est pas disponible ici."); return
	if not model_ready(): _reply("⚠ Ce modèle n'est pas encore téléchargé : appuie sur « Télécharger » en haut."); return
	var sys := SYSTEM
	if page_ctx:
		if browser_hook != null and is_instance_valid(browser_hook):
			var pg: String = await browser_hook.get_page_text()
			sys += PAGE_SYS + "\nAdresse : " + browser_hook.current_url() + "\nTexte de la page :\n" + pg.substr(0, 2500)
		else:
			sys += "\nL'option « Page web » est activée mais le navigateur n'est pas ouvert : dis à l'utilisateur d'ouvrir Logiciels > Chromium."
	if _llm == null or _llm_model != model:
		if _llm: _llm.queue_free()
		_llm = ClassDB.instantiate("GDLlama"); add_child(_llm); _llm_model = model
		_llm.set("model_path", ProjectSettings.globalize_path(MODELS[model]["file"]))
		_llm.set("n_predict", 350); _llm.set("n_ctx", 4096)
		_llm.set("should_output_prompt", false); _llm.set("should_output_special", false)
		_llm.set("n_threads", maxi(2, OS.get_processor_count() / 2))
	var p := "<|im_start|>system\n%s<|im_end|>\n" % sys
	for m in _hist(6): p += "<|im_start|>%s\n%s<|im_end|>\n" % [m["role"], str(m["content"])]
	p += "<|im_start|>assistant\n"
	_llm.call("run_generate_text", p, "", "")
	var t: String = await _llm.generate_text_finished
	_finish(t.get_slice("<|im_end|>", 0).strip_edges())


## Fin de réponse : exécute l'éventuel [[OUVRIR url]] du navigateur puis affiche.
func _finish(c: String) -> void:
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
