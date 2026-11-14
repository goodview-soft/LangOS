extends Control
## Music : télécharge depuis YouTube (yt-dlp), paroles synchronisées (LRCLIB), karaoké avec
## traduction par ligne (Ollama local), mots difficiles surlignés et dictionnaire hors ligne au clic.

const MUSIC_DIR := "user://music"
const LIB_PATH := "user://library.json"
const PRINT_TPL := "TRACK\t%(id)s\t%(title)s\t%(artist|NA)s\t%(track|NA)s\t%(uploader|NA)s\t%(duration|0)s"
const ACCENT := Color("5aa2ff")
const LANGS := [["Español", "spa", "Spanish"], ["English", "eng", "English"], ["Français", "fra", "French"],
	["Italiano", "ita", "Italian"], ["Português", "por", "Portuguese"], ["Nederlands", "nld", "Dutch"], ["日本語", "jpn", "Japanese"]]
const ACC := {"à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a", "ç": "c", "è": "e", "é": "e", "ê": "e", "ë": "e",
	"ì": "i", "í": "i", "î": "i", "ï": "i", "ñ": "n", "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o", "ù": "u", "ú": "u", "û": "u", "ü": "u", "ý": "y", "ÿ": "y"}
const SCHEMA := {"type": "object", "properties": {"lines": {"type": "array", "items": {"type": "object", "properties": {
	"i": {"type": "integer"}, "tr": {"type": "string"},
	"words": {"type": "array", "items": {"type": "object", "properties": {"w": {"type": "string"}, "sens": {"type": "string"}}, "required": ["w", "sens"]}}},
	"required": ["i", "tr", "words"]}}}, "required": ["lines"]}

var ollama_url := "http://127.0.0.1:11434"
var tracks: Array = []
var current := -1
var lines: Array = []
var trans := {}
var lyr: Lyrics
var player: AudioStreamPlayer
var url_edit: LineEdit
var status: Label
var list: ItemList
var now_lbl: Label
var lyrics_view: RichTextLabel
var trans_view: RichTextLabel
var word_view: RichTextLabel
var seek: HSlider
var time_lbl: Label
var play_btn: Button
var off_lbl: Label
var src := "spa"
var tgt := "fra"
var tr_btn: Button
var dl_btn: Button
var _seeking := false
var _threads: Array = []
var _pids: Array = []
var _lyr_queue: Array = []
var _lyr_busy := false
var _tr_busy := false
var _last_idx := -2
var _dicts := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(MUSIC_DIR)
	lyr = Lyrics.new(); add_child(lyr)
	player = AudioStreamPlayer.new(); add_child(player)
	player.finished.connect(func(): _play(_wrap(current + 1)))
	_build_ui()
	_load_lib()


func _exit_tree() -> void:
	for p in _pids: OS.kill(p)
	for th in _threads:
		if th.is_started(): th.wait_to_finish()


# ---------------------------------------------------------------- UI

func _btn(t: String, cb: Callable, variation := "", w := 0) -> Button:
	var b := Button.new(); b.text = t; b.focus_mode = Control.FOCUS_NONE
	if variation != "": b.theme_type_variation = variation
	if w > 0: b.custom_minimum_size.x = w
	b.pressed.connect(cb)
	return b


func _build_ui() -> void:
	var m := MarginContainer.new(); m.set_anchors_preset(PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 12)
	add_child(m)
	var root := VBoxContainer.new(); root.add_theme_constant_override("separation", 8); m.add_child(root)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 8); root.add_child(top)
	url_edit = LineEdit.new(); url_edit.placeholder_text = "Lien YouTube / YouTube Music (vidéo ou playlist)…"
	url_edit.size_flags_horizontal = SIZE_EXPAND_FILL; url_edit.virtual_keyboard_enabled = false
	url_edit.text_submitted.connect(func(_t): _download()); top.add_child(url_edit)
	dl_btn = _btn("Télécharger", _download, "Accent"); top.add_child(dl_btn)
	status = Label.new(); status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override("font_color", Color("8f9bb3")); status.clip_text = true; root.add_child(status)
	var hb := HBoxContainer.new(); hb.size_flags_vertical = SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 12); root.add_child(hb)
	# Colonne gauche : bibliothèque
	var left := VBoxContainer.new(); left.custom_minimum_size.x = 290; left.add_theme_constant_override("separation", 6); hb.add_child(left)
	list = ItemList.new(); list.size_flags_vertical = SIZE_EXPAND_FILL
	list.item_activated.connect(_play); left.add_child(list)
	var br := HBoxContainer.new(); br.add_theme_constant_override("separation", 6); left.add_child(br)
	br.add_child(_btn("Paroles", func(): _fetch_lyrics(current, true), "", 0))
	tr_btn = _btn("Traduire", _translate_current, "", 0); br.add_child(tr_btn)
	br.add_child(_btn("🗑", _delete, "Flat", 44))
	# Colonne droite : karaoké
	var right := VBoxContainer.new(); right.size_flags_horizontal = SIZE_EXPAND_FILL; right.add_theme_constant_override("separation", 8); hb.add_child(right)
	now_lbl = Label.new(); now_lbl.add_theme_font_size_override("font_size", 20); now_lbl.text = "Aucun morceau"; now_lbl.clip_text = true; right.add_child(now_lbl)
	var two := HBoxContainer.new(); two.size_flags_vertical = SIZE_EXPAND_FILL
	two.add_theme_constant_override("separation", 10); right.add_child(two)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("171b25"); sb.set_corner_radius_all(12); sb.set_content_margin_all(16)
	lyrics_view = _lyric_panel(two, sb)
	trans_view = _lyric_panel(two, sb)
	var wp := PanelContainer.new(); wp.custom_minimum_size.y = 96
	var sb2 := sb.duplicate(); sb2.bg_color = Color("1d2330"); sb2.set_content_margin_all(12); wp.add_theme_stylebox_override("panel", sb2); right.add_child(wp)
	word_view = RichTextLabel.new(); word_view.bbcode_enabled = true; word_view.add_theme_font_size_override("normal_font_size", 17)
	word_view.text = "[color=#8f9bb3]Clique un mot des paroles pour voir sa traduction (dictionnaire hors ligne).[/color]"; wp.add_child(word_view)
	# Transport
	var tp := HBoxContainer.new(); tp.add_theme_constant_override("separation", 8); root.add_child(tp)
	tp.add_child(_btn("⏮", func(): _play(_wrap(current - 1)), "", 48))
	play_btn = _btn("▶", _toggle, "", 56); tp.add_child(play_btn)
	tp.add_child(_btn("⏭", func(): _play(_wrap(current + 1)), "", 48))
	time_lbl = Label.new(); time_lbl.text = "0:00 / 0:00"; time_lbl.custom_minimum_size.x = 100; tp.add_child(time_lbl)
	seek = HSlider.new(); seek.size_flags_horizontal = SIZE_EXPAND_FILL; seek.size_flags_vertical = SIZE_SHRINK_CENTER
	seek.focus_mode = Control.FOCUS_NONE; seek.step = 0.1
	seek.drag_started.connect(func(): _seeking = true)
	seek.drag_ended.connect(func(_c): _seeking = false; if player.stream: player.seek(seek.value))
	tp.add_child(seek)
	tp.add_child(_btn("−", func(): _nudge(-0.5), "Flat", 40))
	off_lbl = Label.new(); off_lbl.text = "sync 0.0 s"; off_lbl.custom_minimum_size.x = 80; tp.add_child(off_lbl)
	tp.add_child(_btn("+", func(): _nudge(0.5), "Flat", 40))
	if OS.has_feature("android"):
		dl_btn.disabled = true
		status.text = "Le téléchargement YouTube (yt-dlp) n'est disponible que sur PC."


func _lyric_panel(parent: Control, sb: StyleBoxFlat) -> RichTextLabel:
	var pc := PanelContainer.new(); pc.size_flags_vertical = SIZE_EXPAND_FILL; pc.size_flags_horizontal = SIZE_EXPAND_FILL
	pc.size_flags_stretch_ratio = 1.0; pc.add_theme_stylebox_override("panel", sb); parent.add_child(pc)
	var r := RichTextLabel.new(); r.bbcode_enabled = true; r.scroll_active = false; r.meta_underlined = false
	r.add_theme_font_size_override("normal_font_size", 19); r.add_theme_font_size_override("bold_font_size", 24)
	r.meta_clicked.connect(_word_clicked); pc.add_child(r)
	return r


func _name(code: String, i: int) -> String:
	for l in LANGS:
		if l[1] == code: return l[i]
	return code


## Appelé par LangOS quand les langues des Paramètres changent.
func set_langs(s: String, t: String) -> void:
	src = s; tgt = t
	if current >= 0: _load_lines()


# ---------------------------------------------------------------- Lecture

func _wrap(i: int) -> int:
	return posmod(i, tracks.size()) if tracks.size() > 0 else -1


func _play(i: int) -> void:
	if i < 0 or i >= tracks.size(): return
	var t: Dictionary = tracks[i]
	var s := AudioStreamMP3.load_from_file(ProjectSettings.globalize_path(t.file))
	if s == null:
		status.text = "Fichier illisible : " + t.file; return
	current = i
	list.select(i)
	player.stream = s; player.play()
	seek.max_value = s.get_length()
	now_lbl.text = "%s — %s" % [t.artist, t.track]
	_load_lines()
	if lines.is_empty(): _fetch_lyrics(i, false)


func _toggle() -> void:
	if player.stream == null: _play(0 if current < 0 else current)
	else: player.stream_paused = not player.stream_paused


func _pos() -> float:
	if not player.playing: return seek.value
	return player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()


func _fmt(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


func _nudge(d: float) -> void:
	if current < 0: return
	tracks[current]["offset"] = snappedf(float(tracks[current].get("offset", 0.0)) + d, 0.1)
	_save_lib(false); _update_off()


func _update_off() -> void:
	off_lbl.text = "sync %+.1f s" % float(tracks[current].get("offset", 0.0)) if current >= 0 else "sync 0.0 s"


func _process(_d: float) -> void:
	if not is_visible_in_tree(): return
	var playing := player.playing and not player.stream_paused
	play_btn.text = "⏸" if playing else "▶"
	if player.stream == null: return
	var p := _pos()
	if not _seeking: seek.value = p
	time_lbl.text = "%s / %s" % [_fmt(p), _fmt(seek.max_value)]
	var t := p + float(tracks[current].get("offset", 0.0))
	var idx := -1
	for k in lines.size():
		if lines[k][0] <= t: idx = k
		else: break
	if idx != _last_idx:
		_last_idx = idx; _render(idx)


# ---------------------------------------------------------------- Karaoké

func _clean(w: String) -> String:
	return w.strip_edges().trim_prefix("¡").trim_prefix("¿").lstrip("\"'(").rstrip(".,;:!?\"')…").to_lower()


func _line_bb(text: String, glossed: Dictionary, links := true) -> String:
	var out := PackedStringArray()
	for tok in text.split(" ", false):
		var c := _clean(tok)
		var safe: String = tok.replace("[", "[lb]")
		var item := safe
		if links and c != "" and not "[" in c and not "]" in c:
			item = "[url=%s]%s[/url]" % [c, safe]
		if glossed.has(c): item = "[color=#7dd3fc]%s[/color]" % item
		out.append(item)
	return " ".join(out)


func _render(idx: int) -> void:
	if lines.is_empty():
		lyrics_view.text = "[center][color=#8f9bb3]Pas de paroles synchronisées.[/color][/center]"
		trans_view.text = ""; return
	var a := "[color=#8f9bb3][font_size=14]%s[/font_size][/color]\n\n" % _name(src, 0)
	var b := "[color=#8f9bb3][font_size=14]%s[/font_size][/color]\n\n" % _name(tgt, 0)
	if trans.is_empty(): b += "[color=#6b7488]Clique « Traduire » pour afficher la traduction ici.[/color]"
	for k in range(maxi(idx - 3, 0), mini(lines.size(), idx + 9)):
		var txt: String = str(lines[k][1])
		if txt == "": txt = "♪"
		var tl: Dictionary = trans.get(k, {})
		var ft := str(tl.get("tr", "")).replace("[", "[lb]")
		if ft == "" and txt == "♪": ft = "♪"
		if k == idx:
			var gl := {}
			for w in tl.get("words", []): gl[_clean(str(w.get("w", "")))] = str(w.get("sens", ""))
			a += "[b][color=#ffd040]%s[/color][/b]\n" % _line_bb(txt, gl)
			if not gl.is_empty():
				var g := []
				for w in tl.get("words", []): g.append("[color=#7dd3fc]%s[/color] = %s" % [str(w.get("w", "")).replace("[", "[lb]"), str(w.get("sens", "")).replace("[", "[lb]")])
				a += "[font_size=14]%s[/font_size]\n" % "   ".join(g)
			a += "\n"
			if not trans.is_empty(): b += "[b][color=#6fcf97]%s[/color][/b]\n\n" % (ft if ft != "" else "…")
		else:
			a += "[color=%s]%s[/color]\n" % ["#6b7488" if k < idx else "#aab2c5", _line_bb(txt, {}, true)]
			if not trans.is_empty(): b += "[color=%s]%s[/color]\n" % ["#6b7488" if k < idx else "#aab2c5", ft if ft != "" else "…"]
	lyrics_view.text = a
	trans_view.text = b


func _load_lines() -> void:
	lines = []; trans = {}; _last_idx = -2
	if current < 0: return
	var t: Dictionary = tracks[current]
	_update_off()
	if t.get("lrc", "") != "" and FileAccess.file_exists(t.lrc):
		lines = Lyrics.parse(FileAccess.get_file_as_string(t.lrc))
		var tp := _tr_path(t)
		if FileAccess.file_exists(tp):
			var d = JSON.parse_string(FileAccess.get_file_as_string(tp))
			if d is Dictionary:
				for k in d: trans[int(k)] = d[k]
	_render(-1)


# ---------------------------------------------------------------- Dictionnaire hors ligne (au clic)

func _dkey(t: String) -> String:
	var o := ""
	for c in t.strip_edges().to_lower(): o += ACC.get(c, c)
	return o


func _dic(pair: String) -> PackedStringArray:
	if not _dicts.has(pair):
		var p := "res://dicts/%s.tsv" % pair
		_dicts[pair] = FileAccess.get_file_as_string(p).split("\n", false) if FileAccess.file_exists(p) else PackedStringArray()
	return _dicts[pair]


func _find(pair: String, word: String) -> String:
	var d := _dic(pair)
	var k := _dkey(word)
	var lo := 0; var hi := d.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if d[mid].get_slice("\t", 0) < k: lo = mid + 1
		else: hi = mid
	var out := PackedStringArray()
	while lo < d.size() and d[lo].get_slice("\t", 0) == k and out.size() < 4:
		out.append(d[lo].get_slice("\t", 2).replace("¶", "  |  ")); lo += 1
	return "  |  ".join(out)


func _first_en(def: String) -> Array:
	var res := []
	for part in def.replace("  |  ", ";").split(";", false):
		var s := part.strip_edges()
		if s.begins_with("("): s = s.substr(s.find(")") + 1).strip_edges()
		s = s.trim_prefix("to ").strip_edges()
		if s != "" and not s in res: res.append(s)
		if res.size() >= 3: break
	return res


func _word_clicked(meta: Variant) -> void:
	var w := str(meta)
	var gloss := ""
	for k in trans:
		for g in trans[k].get("words", []):
			if _clean(str(g.get("w", ""))) == w: gloss = str(g.get("sens", ""))
	var txt := "[b][font_size=22]%s[/font_size][/b]" % w.replace("[", "[lb]")
	if gloss != "": txt += "   [color=#7dd3fc]→ %s[/color]" % gloss.replace("[", "[lb]")
	var found := false
	if src != tgt:
		if src == "eng" or tgt == "eng":
			var pair := "%s-%s" % [src, tgt]
			var d := _find(pair, w)
			if d != "": txt += "\n%s" % d.replace("[", "[lb]"); found = true
		else:
			var d1 := _find("%s-eng" % src, w)
			if d1 != "":
				found = true
				txt += "\n[color=#8f9bb3]EN :[/color] %s" % d1.replace("[", "[lb]")
				var tr := []
				for e in _first_en(d1):
					var d2 := _find("eng-%s" % tgt, e)
					if d2 != "": tr.append("%s → %s" % [e, "; ".join(_first_en(d2))])
				if not tr.is_empty(): txt += "\n[color=#6fcf97]%s :[/color] %s" % [_name(tgt, 0), "  ·  ".join(tr).replace("[", "[lb]")]
	if not found and gloss == "": txt += "\n[color=#8f9bb3]Pas dans le dictionnaire hors ligne (formes conjuguées : essayer l'infinitif).[/color]"
	word_view.text = txt


# ---------------------------------------------------------------- Paroles (LRCLIB)

func _fetch_lyrics(i: int, manual: bool) -> void:
	if i < 0: return
	var t: Dictionary = tracks[i]
	if t.get("no_lyrics", false) and not manual: return
	status.text = "Recherche des paroles : %s — %s…" % [t.artist, t.track]
	var lrc: String = await lyr.fetch(t.artist, t.track, t.duration)
	if lrc == "":
		t.no_lyrics = true
		status.text = "Aucune parole synchronisée trouvée pour « %s »." % t.track
	else:
		t.erase("no_lyrics")
		t.lrc = MUSIC_DIR.path_join(t.id + ".lrc")
		var f := FileAccess.open(t.lrc, FileAccess.WRITE); f.store_string(lrc); f.close()
		status.text = "Paroles trouvées ✓"
	_save_lib()
	if i == current: _load_lines()


func _drain_lyr_queue() -> void:
	_lyr_busy = true
	while not _lyr_queue.is_empty():
		var id: String = _lyr_queue.pop_front()
		for i in tracks.size():
			if tracks[i].id == id:
				await _fetch_lyrics(i, false); break
	_lyr_busy = false


# ---------------------------------------------------------------- Traduction des paroles (Ollama local)

func _tr_path(t: Dictionary) -> String:
	return MUSIC_DIR.path_join("%s.%s.json" % [t.id, tgt])


func _pick_model() -> String:
	var http := HTTPRequest.new(); http.timeout = 8; add_child(http)
	if http.request(ollama_url + "/api/tags") != OK: http.queue_free(); return ""
	var r = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200: return ""
	var d = JSON.parse_string(r[3].get_string_from_utf8())
	var names := []
	if d is Dictionary: for m in d.get("models", []): names.append(str(m["name"]))
	for pref in ["gemma3:4b", "qwen3:8b", "llama3.1:8b", "qwen3:14b", "llama3.2:3b"]:
		if pref in names: return pref
	return names[0] if not names.is_empty() else ""


func _translate_current() -> void:
	if current < 0 or lines.is_empty() or _tr_busy:
		status.text = "Ouvre un morceau avec paroles d'abord."; return
	_tr_busy = true; tr_btn.disabled = true
	status.text = "Connexion au modèle local…"
	var model: String = await _pick_model()
	if model == "":
		status.text = "Ollama introuvable (réglage du serveur dans Traducteur / Paramètres)."
		_tr_busy = false; tr_btn.disabled = false; return
	var t: Dictionary = tracks[current]
	var src_n := _name(src, 2)
	var tgt_n := _name(tgt, 2)
	var out := {}
	trans = {}
	var k := 0
	while k < lines.size():
		var chunk := []
		for j in range(k, mini(k + 10, lines.size())):
			if str(lines[j][1]).strip_edges() != "": chunk.append("%d: %s" % [j, lines[j][1]])
		var res = await _ask(model, src_n, tgt_n, chunk) if not chunk.is_empty() else []
		if res == null and not chunk.is_empty(): res = await _ask(model, src_n, tgt_n, chunk)
		if res == null:
			status.text = "Échec de la traduction (modèle %s trop lent ou arrêté ?)." % model; _tr_busy = false; tr_btn.disabled = false; return
		for r in res:
			out[int(r.get("i", -1))] = {"tr": str(r.get("tr", "")), "words": r.get("words", [])}
			trans[int(r.get("i", -1))] = out[int(r.get("i", -1))]
		_last_idx = -2
		k += 10
		status.text = "Traduction (%s) : %d %%  — les lignes apparaissent au fur et à mesure" % [model, int(100.0 * minf(1.0, float(k) / lines.size()))]
	var f := FileAccess.open(_tr_path(t), FileAccess.WRITE); f.store_string(JSON.stringify(out)); f.close()
	_tr_busy = false; tr_btn.disabled = false
	status.text = "Traduction terminée ✓"
	_load_lines()


func _ask(model: String, src: String, tgt: String, chunk: Array):
	var prompt := "IMPORTANT: every \"tr\" and every \"sens\" MUST be written in %s (never in English unless %s is English).\nSong lyrics in %s (slang possible), for a learner whose language is %s. For EACH numbered line give:\n- \"tr\": natural %s translation of THIS line (meaning of slang, not word-for-word).\n- \"words\": 0 to 3 words of THIS line a beginner would not know (slang, rare verbs). \"w\" = the word as written in the line; \"sens\" = its %s translation in 1-3 words, DIFFERENT from the original word. Ignore basic words and words identical in %s.\nAnswer in JSON, one entry per line (\"i\" = line number).\n\n%s" % [tgt, tgt, src, tgt, tgt, tgt, tgt, "\n".join(chunk)]
	var body := {"model": model, "stream": false, "think": false, "format": SCHEMA, "options": {"temperature": 0.2},
		"messages": [{"role": "user", "content": prompt}]}
	var http := HTTPRequest.new(); http.timeout = 240; add_child(http)
	if http.request(ollama_url + "/api/chat", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		http.queue_free(); return null
	var r = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200: return null
	var d = JSON.parse_string(r[3].get_string_from_utf8())
	if d == null: return null
	var c = JSON.parse_string(d.get("message", {}).get("content", ""))
	return c.get("lines") if c is Dictionary else null


# ---------------------------------------------------------------- Téléchargement (yt-dlp, PC)

func _ytdlp() -> Array:
	if FileAccess.file_exists("/.flatpak-info"):
		return ["flatpak-spawn", ["--host", "--env=PYTHONUNBUFFERED=1", "yt-dlp"]]
	for p in [OS.get_environment("HOME") + "/.local/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]:
		if FileAccess.file_exists(p): return [p, []]
	return ["yt-dlp", []]


func _download() -> void:
	var url := url_edit.text.strip_edges()
	if url == "" or OS.has_feature("android"): return
	url_edit.text = ""
	var out := ProjectSettings.globalize_path(MUSIC_DIR)
	var args := ["-x", "--audio-format", "mp3", "--audio-quality", "0", "--ignore-errors", "--progress", "--newline",
		"--no-simulate", "-o", out + "/%(id)s.%(ext)s", "--print", "after_move:" + PRINT_TPL]
	if not "playlist?list=" in url: args.append("--no-playlist")
	args.append(url)
	var y := _ytdlp()
	var info := OS.execute_with_pipe(y[0], PackedStringArray(y[1] + args))
	if info.is_empty():
		status.text = "Impossible de lancer yt-dlp (installé ? ffmpeg aussi)."; return
	_pids.append(info["pid"])
	status.text = "Téléchargement…"
	for key in ["stdio", "stderr"]:
		var th := Thread.new(); th.start(_read_pipe.bind(info[key])); _threads.append(th)


func _read_pipe(f: FileAccess) -> void:
	while f.is_open() and f.get_error() == OK:
		var line := f.get_line()
		if line != "": _on_line.call_deferred(line)


func _on_line(line: String) -> void:
	if line.begins_with("TRACK\t"):
		var p := line.split("\t")
		if p.size() < 7: return
		var g := Lyrics.guess(p[2], p[3], p[4], p[5])
		for t in tracks:
			if t.id == p[1]: status.text = "Déjà dans la bibliothèque : " + p[2]; return
		tracks.append({"id": p[1], "title": p[2], "artist": g[0], "track": g[1], "duration": p[6].to_float(),
			"file": MUSIC_DIR.path_join(p[1] + ".mp3"), "lrc": "", "offset": 0.0})
		_save_lib(); status.text = "Ajouté : " + p[2]
		_lyr_queue.append(p[1])
		if not _lyr_busy: _drain_lyr_queue()
	elif line.begins_with("[download]") and "%" in line: status.text = line
	elif line.begins_with("ERROR"): status.text = line


# ---------------------------------------------------------------- Bibliothèque

func _delete() -> void:
	var sel := Array(list.get_selected_items())
	if sel.is_empty(): return
	var i: int = sel[0]
	var t: Dictionary = tracks[i]
	if i == current: player.stop(); player.stream = null; current = -1; lines = []; trans = {}; now_lbl.text = "Aucun morceau"; lyrics_view.text = ""; trans_view.text = ""
	for f in [t.file, t.get("lrc", ""), _tr_path(t)]:
		if f != "" and FileAccess.file_exists(f): DirAccess.remove_absolute(f)
	tracks.remove_at(i)
	if current > i: current -= 1
	_save_lib()


func _refresh_list() -> void:
	list.clear()
	for t in tracks:
		list.add_item("%s%s — %s" % ["♪ " if t.get("lrc", "") != "" else "   ", t.artist, t.track])
	if current >= 0: list.select(current)


func _load_lib() -> void:
	if FileAccess.file_exists(LIB_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(LIB_PATH))
		if d is Array: tracks = d
	_refresh_list()
	if status.text == "": status.text = "%d morceaux. Double-clic pour jouer." % tracks.size()


func _save_lib(refresh := true) -> void:
	var f := FileAccess.open(LIB_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(tracks, "\t")); f.close()
	if refresh: _refresh_list()
