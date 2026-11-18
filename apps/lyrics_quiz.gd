extends Control
## Jeu « Deviner les paroles » : la musique s'arrête juste avant un mot (ou à la fin d'une phrase)
## et il faut choisir la bonne réponse parmi trois. Utilise les paroles synchronisées (.lrc) du morceau.
## Timing des mots : interpolé dans la ligne (proportionnel au nombre de lettres).

const QUESTIONS := 10
const LEAD := 2.5   # secondes de musique avant la coupure

var stream: AudioStream
var lines: Array = []       # [[t, texte], ...]
var offset := 0.0
var player: AudioStreamPlayer
var box: VBoxContainer
var title_lbl: Label
var q_lbl: RichTextLabel
var info_lbl: Label
var btns: Array = []
var qs: Array = []
var qi := -1
var score := 0
var qmode := 0               # 0 mot manquant, 1 suite des paroles, 2 mélange
var stop_at := 0.0
var waiting := false        # musique en cours, attend la coupure
var answered := false
var waiting_next := false
var cur := {}


const LIB_PATH := "user://library.json"
var lib: Array = []
var back_btn: Button


func _ready() -> void:
	player = AudioStreamPlayer.new(); add_child(player)
	var bg := PanelContainer.new(); bg.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var m := MarginContainer.new()
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 20)
	bg.add_child(m)
	box = VBoxContainer.new(); box.add_theme_constant_override("separation", 12); m.add_child(box)
	title_lbl = Label.new(); title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(title_lbl)
	q_lbl = RichTextLabel.new(); q_lbl.bbcode_enabled = true; q_lbl.fit_content = false
	q_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	q_lbl.add_theme_font_size_override("normal_font_size", 26); box.add_child(q_lbl)
	info_lbl = Label.new(); info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(info_lbl)
	for i in 3:
		var b := Button.new(); b.custom_minimum_size = Vector2(0, 48)
		b.add_theme_font_size_override("font_size", 18); box.add_child(b); btns.append(b)
	back_btn = Button.new(); back_btn.text = "Changer de morceau"; back_btn.pressed.connect(_picker); box.add_child(back_btn)
	_picker()


## Écran 1 : choix d'un morceau de la bibliothèque Music qui a des paroles synchronisées.
func _picker() -> void:
	waiting = false; answered = true; player.stop(); qi = -1
	back_btn.visible = false
	lib = []
	if FileAccess.file_exists(LIB_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(LIB_PATH))
		if d is Array: lib = d
	var ok := []
	for t in lib:
		if String(t.get("lrc", "")) != "" and FileAccess.file_exists(t.lrc): ok.append(t)
	title_lbl.text = "Jeu des paroles"
	if ok.is_empty():
		q_lbl.text = "[center]Aucun morceau avec paroles synchronisées.\nOuvre Music, joue un morceau et récupère ses paroles (bouton Paroles).[/center]"
		info_lbl.text = ""
		for b in btns: b.visible = false
		return
	q_lbl.text = "[center]Choisis un morceau[/center]"
	info_lbl.text = "Les morceaux affichés ont leurs paroles."
	for i in 3:
		btns[i].visible = true
		if i < ok.size():
			var t: Dictionary = ok[(i + picker_off) % ok.size()]
			btns[i].text = "%s — %s" % [t.get("artist", ""), t.get("track", "")]; btns[i].disabled = false
			_rebind(btns[i], _load_track.bind(t))
		else:
			btns[i].text = ""; btns[i].disabled = true
	if ok.size() > 3:
		back_btn.visible = true; back_btn.text = "Autres morceaux ›"
		_rebind(back_btn, func(): picker_off = (picker_off + 3) % ok.size(); _picker())


var picker_off := 0


func _load_track(t: Dictionary) -> void:
	var path: String = t.file
	var g := ProjectSettings.globalize_path(path)
	var s: AudioStream = AudioStreamOggVorbis.load_from_file(g) if path.get_extension().to_lower() == "ogg" else AudioStreamMP3.load_from_file(g)
	if s == null:
		info_lbl.text = "Fichier illisible."; return
	stream = s; player.stream = s
	lines = Lyrics.parse(FileAccess.get_file_as_string(t.lrc))
	offset = float(t.get("offset", 0.0))
	song = "%s — %s" % [t.get("artist", ""), t.get("track", "")]
	back_btn.text = "Changer de morceau"; _rebind(back_btn, _picker); back_btn.visible = true
	_menu()


var song := ""


func _menu() -> void:
	waiting = false; player.stop()
	title_lbl.text = "Deviner les paroles — " + song
	q_lbl.text = "[center]Choisis un mode[/center]"
	info_lbl.text = "%d questions, d'après les paroles synchronisées du morceau." % QUESTIONS
	var labels := ["Mot manquant", "Suite des paroles", "Mélange"]
	for i in 3:
		btns[i].visible = true; btns[i].text = labels[i]; btns[i].disabled = false
		_rebind(btns[i], func(): _start(i))


func _rebind(b: Button, f: Callable) -> void:
	for c in b.pressed.get_connections(): b.pressed.disconnect(c.callable)
	b.pressed.connect(f)


func _words(s: String) -> Array:
	var out := []
	for w in s.split(" ", false):
		out.append(w.strip_edges().lstrip("¿¡\"'(").rstrip(".,;:!?\"')…"))
	return out


func _start(m: int) -> void:
	qmode = m; score = 0; qi = -1
	qs = _build()
	if qs.size() < 3:
		q_lbl.text = "[center]Pas assez de paroles synchronisées pour jouer.[/center]"
		return
	_next()


func _build() -> Array:
	var cand := []
	var pool := []   # mots pour les distracteurs
	for i in lines.size():
		var txt: String = lines[i][1]
		var ws := _words(txt)
		for w in ws:
			if w.length() >= 4 and not pool.has(w.to_lower()): pool.append(w.to_lower())
		if ws.size() < 4 or i + 1 >= lines.size(): continue
		cand.append(i)
	cand.shuffle()
	var res := []
	for i in cand:
		if res.size() >= QUESTIONS: break
		var kind := qmode if qmode < 2 else randi() % 2
		var txt: String = lines[i][1]
		var t0: float = lines[i][0]
		var t1: float = lines[i + 1][0]
		if kind == 0:
			var ws := _words(txt)
			var idx := []
			for k in ws.size():
				if ws[k].length() >= 4 and k >= ws.size() / 2: idx.append(k)
			if idx.is_empty(): continue
			var k: int = idx[randi() % idx.size()]
			var before := 0
			for j in k: before += ws[j].length() + 1
			var total := maxi(1, txt.length())
			var span := minf(t1 - t0, 6.0)
			var tw := t0 + span * float(before) / float(total) * 0.95
			var good: String = ws[k]
			var opts := [good]
			var tries := 0
			while opts.size() < 3 and tries < 200:
				tries += 1
				var d: String = pool[randi() % pool.size()]
				if d == good.to_lower() or opts.has(d): continue
				if absi(d.length() - good.length()) > 3 and tries < 100: continue
				opts.append(d)
			if opts.size() < 3: continue
			opts.shuffle()
			res.append({"kind": 0, "line": i, "t_stop": tw, "answer": good.to_lower(), "opts": opts, "k": k, "ws": ws})
		else:
			if i + 2 >= lines.size() or String(lines[i + 1][1]).length() < 8: continue
			var good: String = lines[i + 1][1]
			var opts := [good]
			var tries := 0
			while opts.size() < 3 and tries < 100:
				tries += 1
				var d: String = lines[randi() % lines.size()][1]
				if d.length() < 8 or opts.has(d) or d == txt: continue
				opts.append(d)
			if opts.size() < 3: continue
			opts.shuffle()
			res.append({"kind": 1, "line": i, "t_stop": t1 - 0.05, "answer": good, "opts": opts})
	return res


func _next() -> void:
	qi += 1
	if qi >= qs.size(): _end(); return
	cur = qs[qi]
	answered = false; waiting = true
	title_lbl.text = "Question %d / %d — score %d" % [qi + 1, qs.size(), score]
	info_lbl.text = "Écoute…"
	q_lbl.text = "[center]♪ ♪ ♪[/center]"
	for b in btns: b.text = "…"; b.disabled = true
	var start := maxf(0.0, float(lines[maxi(0, cur.line - 1)][0]) - offset)
	stop_at = float(cur.t_stop) - offset
	player.play(maxf(0.0, minf(start, stop_at - LEAD)))


func _process(_d: float) -> void:
	if not waiting or not player.playing: return
	var p := player.get_playback_position() + AudioServer.get_time_since_last_mix()
	if p >= stop_at:
		waiting = false; player.stop(); _ask()


func _ask() -> void:
	info_lbl.text = "Quelle est la suite ?" if cur.kind == 1 else "Quel est le mot manquant ?"
	if cur.kind == 0:
		var ws: Array = cur.ws.duplicate()
		ws[cur.k] = "[color=#ffcc55]_____[/color]"
		q_lbl.text = "[center]" + " ".join(ws) + "[/center]"
	else:
		q_lbl.text = "[center]%s\n[color=#ffcc55]…[/color][/center]" % lines[cur.line][1]
	for i in 3:
		btns[i].text = cur.opts[i]; btns[i].disabled = false
		_rebind(btns[i], _answer.bind(i))


func _answer(i: int) -> void:
	if answered: return
	answered = true; waiting_next = true
	var ok: bool = String(cur.opts[i]).to_lower() == String(cur.answer).to_lower()
	if ok: score += 1
	for b in btns: b.disabled = true
	info_lbl.text = ("Bravo ! " if ok else "Raté — c'était : ") + (("" if ok else String(cur.answer)))
	var full: String = lines[cur.line][1] + ("\n" + lines[cur.line + 1][1] if cur.kind == 1 else "")
	q_lbl.text = "[center]%s[/center]" % full
	player.play(maxf(0.0, stop_at - 0.3))   # on laisse entendre la suite
	await get_tree().create_timer(3.0).timeout
	if not is_inside_tree() or qi < 0 or not waiting_next: return
	waiting_next = false
	player.stop()
	_next()


func _end() -> void:
	player.stop(); waiting = false
	title_lbl.text = "Terminé !"
	q_lbl.text = "[center]Score : %d / %d[/center]" % [score, qs.size()]
	info_lbl.text = ""
	btns[0].text = "Rejouer"; btns[0].disabled = false; _rebind(btns[0], _menu)
	btns[1].text = "Autre morceau"; btns[1].disabled = false; _rebind(btns[1], _picker)
	btns[2].text = ""; btns[2].disabled = true
