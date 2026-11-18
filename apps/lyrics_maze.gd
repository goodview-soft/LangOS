extends Control
## Labyrinthe des paroles : FPS (raycasting 2.5D). Chaque phrase = une salle ; on prend le tunnel du mot manquant.

const LIB_PATH := "user://library.json"
const MUSIC_DIR := "user://music"
const SAVE_PATH := "user://lyricsgame.json"
const BUS := "LMaze"
const GOLD := Color("ffd877")
const MUTED := Color("9aa0c6")
const INK := Color("26305f")
const REPLAY_PAD := 0.6
const COLW := 4
const FOVK := 0.66
const HALL_Y0 := 5.0
const GH := 11
const DIFFS := [
	{"name": "Facile", "ch": 3, "tol": 3, "cs": 0.010},
	{"name": "Normal", "ch": 3, "tol": 2, "cs": 0.017},
	{"name": "Expert", "ch": 4, "tol": 1, "cs": 0.026},
]
const ROOMFX := {
	"couloir": {"n": "couloir étroit", "size": 0.2, "damp": 0.8, "wet": 0.05},
	"salle": {"n": "salle", "size": 0.5, "damp": 0.55, "wet": 0.15},
	"grande": {"n": "grande salle", "size": 0.9, "damp": 0.35, "wet": 0.30},
	"carrefour": {"n": "carrefour", "size": 0.75, "damp": 0.45, "wet": 0.25},
	"derniere": {"n": "dernière salle", "size": 0.97, "damp": 0.2, "wet": 0.40},
}
const RUN_MULT := 1.75

var player: AudioStreamPlayer
var inst_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var sfx := {}
var lp: AudioEffectLowPassFilter
var se: AudioEffectStereoEnhance
var reverb: AudioEffectReverb
var heart_player: AudioStreamPlayer
var rumble_player: AudioStreamPlayer
var step_player: AudioStreamPlayer
var cstep_player: AudioStreamPlayer

var home: Control
var view: Control
var results: Control
var menu: Control
var res_lbl: RichTextLabel
var carousel: HBoxContainer
var diff_btns: Array = []
var home_msg: Label
var play_btn: Button

var lib: Array = []
var save := {}
var sel_track := {}
var sel_diff := 1
var scene := 0           # 0 accueil, 1 jeu, 2 bilan
var menu_open := false
var map_open := false

# morceau
var lines: Array = []
var offset := 0.0
var song := ""
var stream: AudioStream
var tr_lines := {}
var dict_cache := {}
var dict_pair := ""
var inst_ready := false
var inst_thread: Thread
var inst_out := ""
var inst_state := 0
var mast_cur := {"b": {}, "n": 0}
var gloss_cache := {}

# partie
var rooms: Array = []
var cur := 0
var phase := 0           # 0 carrefour, 1 bon tunnel, 2 impasse
var chosen := -1
var grid := PackedByteArray()
var gw := 11
var door_xs: Array = []
var pos := Vector2(5.5, 9.3)
var ang := -PI / 2.0
var score := 0
var streak := 0
var best_streak := 0
var glog: Array = []
var clock := 0.0
var paused := false
var mix_t := 0.0
var reveal_until := -1.0
var hue := 0.6
var t_anim := 0.0
var fade := 0.0
var fade_col := Color.BLACK
var msg := ""
var msg_t := 0.0
var msg_col := Color.WHITE
var door_vis := {}
var look_door := -1
var look_dist := 99.0
var mouse_cap := false
var bob := 0.0
var end_checked := 0.0
var entered := false
# horreur / poursuite
var chase_d := 0.9        # 0 = attrapé, 1 = très loin
var chase_s := 0.9        # version lissée (audio / visuel)
var lives := 3
var scare := 0.0
var shake := 0.0
var lamp := 1.0
var flick_t := 0.0
var rv_size := 0.5
var rv_damp := 0.55
var rv_wet := 0.15
var rv_tw: Tween
var step_t := 0.0
var cstep_t := 0.5
var run_seed := 0
var rew := 0.0            # effet « retour en arrière » après une erreur
var par_t := 0.0
var trav := 0.0
var running := false
var dust: Array = []
var jfirst := 0
var cr_tx := 0.0
var cr_ty := -1.0


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	_load_save()
	_make_audio()
	var bgc := ColorRect.new(); bgc.color = Color("0b0e1f"); bgc.set_anchors_preset(Control.PRESET_FULL_RECT); bgc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bgc)
	view = Control.new(); view.set_anchors_preset(Control.PRESET_FULL_RECT); view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.draw.connect(_draw_game)
	add_child(view)
	home = _build_home(); add_child(home)
	results = _build_results(); add_child(results)
	menu = _build_menu(); add_child(menu)
	_home_open()


func _exit_tree() -> void:
	if mouse_cap: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if inst_thread != null:
		inst_thread.wait_to_finish()
		inst_thread = null
	var i := AudioServer.get_bus_index(BUS)
	if i >= 0: AudioServer.remove_bus(i)


# ------------------------------------------------------------------ Audio
func _make_audio() -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.add_bus_effect(i, AudioEffectSpectrumAnalyzer.new())
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.7; rv.damping = 0.55; rv.spread = 1.0; rv.dry = 1.0; rv.wet = 0.0
		AudioServer.add_bus_effect(i, rv)
		var lpf := AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(i, lpf)
		AudioServer.add_bus_effect(i, AudioEffectStereoEnhance.new())
	var bi := AudioServer.get_bus_index(BUS)
	reverb = AudioServer.get_bus_effect(bi, 1) as AudioEffectReverb
	lp = AudioServer.get_bus_effect(bi, 2) as AudioEffectLowPassFilter
	se = AudioServer.get_bus_effect(bi, 3) as AudioEffectStereoEnhance
	player = AudioStreamPlayer.new(); player.bus = BUS; add_child(player)
	sfx_player = AudioStreamPlayer.new(); sfx_player.volume_db = -6.0; add_child(sfx_player)
	inst_player = AudioStreamPlayer.new(); inst_player.bus = BUS; inst_player.volume_db = -60.0; add_child(inst_player)
	sfx["good"] = _tone([660.0, 880.0, 1175.0], 0.07)
	sfx["bad"] = _tone([220.0, 165.0], 0.12)
	sfx["door"] = _tone([300.0, 400.0], 0.05)
	sfx["go"] = _tone([880.0, 1320.0], 0.14)
	sfx["end"] = _tone([523.0, 659.0, 784.0, 1047.0], 0.12)
	sfx["step"] = _thud(0.09, 140.0, 9000.0)
	sfx["cstep"] = _thud(0.18, 62.0, 16000.0)
	sfx["scare"] = _scare_wav()
	step_player = AudioStreamPlayer.new(); step_player.bus = BUS; step_player.volume_db = -8.0; step_player.stream = sfx["step"]; add_child(step_player)
	cstep_player = AudioStreamPlayer.new(); cstep_player.bus = BUS; cstep_player.volume_db = -20.0; cstep_player.stream = sfx["cstep"]; add_child(cstep_player)
	heart_player = AudioStreamPlayer.new(); heart_player.stream = _heart_wav(); heart_player.volume_db = -60.0; add_child(heart_player)
	rumble_player = AudioStreamPlayer.new(); rumble_player.stream = _rumble_wav(); rumble_player.volume_db = -60.0; add_child(rumble_player)


func _tone(freqs: Array, each: float) -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	for f in freqs:
		var n := int(rate * each)
		var chunk := PackedByteArray()
		chunk.resize(n * 2)
		for k in n:
			var env := minf(1.0, float(k) / 150.0) * (1.0 - float(k) / n)
			chunk.encode_s16(k * 2, int(sin(TAU * f * k / rate) * 9000.0 * env))
		data.append_array(chunk)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _wav16(data: PackedByteArray, rate: int, loop := false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size() / 2
	return w


func _thud(dur: float, f: float, amp: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var b := PackedByteArray(); b.resize(n * 2)
	for k in n:
		var env := exp(-float(k) / (n * 0.22)) * minf(1.0, float(k) / 40.0)
		var v := sin(TAU * f * k / rate) * 0.8 + randf_range(-1.0, 1.0) * 0.25
		b.encode_s16(k * 2, int(clampf(v * env, -1.0, 1.0) * amp))
	return _wav16(b, rate)


func _scare_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.9)
	var b := PackedByteArray(); b.resize(n * 2)
	var ph := 0.0
	for k in n:
		var t := float(k) / n
		ph += TAU * lerpf(1100.0, 180.0, t) / rate
		var env := minf(1.0, float(k) / 120.0) * (1.0 - t * t)
		var v := (fposmod(ph / TAU, 1.0) * 2.0 - 1.0) * 0.55 + randf_range(-1.0, 1.0) * 0.5 + sin(ph * 0.5) * 0.4
		b.encode_s16(k * 2, int(clampf(v * env, -1.0, 1.0) * 26000.0))
	return _wav16(b, rate)


## Battement de coeur (boucle d'1 s : « toum-toum ») ; le rythme se règle avec pitch_scale.
func _heart_wav() -> AudioStreamWAV:
	var rate := 22050
	var b := PackedByteArray(); b.resize(rate * 2)
	for k in rate:
		var t := float(k) / rate
		var v := 0.0
		for th in [[0.0, 60.0, 1.0], [0.3, 50.0, 0.7]]:
			if t >= th[0]:
				var dt: float = t - th[0]
				v += sin(TAU * th[1] * dt) * exp(-dt * 18.0) * th[2]
		b.encode_s16(k * 2, int(clampf(v, -1.0, 1.0) * 24000.0))
	return _wav16(b, rate, true)


## Grondement grave (fréquences entières : la boucle d'1 s est sans raccord).
func _rumble_wav() -> AudioStreamWAV:
	var rate := 22050
	var b := PackedByteArray(); b.resize(rate * 2)
	for k in rate:
		var t := float(k) / rate
		var v := sin(TAU * 38.0 * t) * 0.5 + sin(TAU * 50.0 * t) * 0.35 + sin(TAU * 53.0 * t) * 0.35
		v *= 0.75 + 0.25 * sin(TAU * 3.0 * t)
		b.encode_s16(k * 2, int(v * 9000.0))
	return _wav16(b, rate, true)


func _play_sfx(n: String) -> void:
	sfx_player.stream = sfx[n]
	sfx_player.play()


func _pos_now() -> float:
	if player.stream != null and player.playing: return player.get_playback_position() + AudioServer.get_time_since_last_mix()
	return clock


func _seek(t: float) -> void:
	t = maxf(0.0, t)
	clock = t
	if player.stream != null:
		player.play(t)
		player.stream_paused = paused or menu_open
	end_checked = 0.4


# ------------------------------------------------------------------ Sauvegarde
func _load_save() -> void:
	save = {"best": {}, "last": {}, "mastery": {}}
	if FileAccess.file_exists(SAVE_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if d is Dictionary: save = d
	for k in ["best", "last", "mastery"]:
		if not save.has(k): save[k] = {}
	if not save.has("maze"): save["maze"] = {"best": {}, "last": {}}
	sel_diff = int(save["maze"].get("last", {}).get("diff", sel_diff))


## Relit le fichier avant d'écrire pour ne pas écraser ce que le quiz y a mis entre-temps.
func _write_save() -> void:
	var disk := {}
	if FileAccess.file_exists(SAVE_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if d is Dictionary: disk = d
	disk["maze"] = save["maze"]
	if not disk.has("mastery"): disk["mastery"] = {}
	var tk := String(sel_track.get("file", ""))
	if tk != "" and save["mastery"].has(tk): disk["mastery"][tk] = save["mastery"][tk]
	for k in ["best", "last"]:
		if not disk.has(k): disk[k] = save[k]
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(disk))


# ------------------------------------------------------------------ UI
func _lbl(text: String, sz: int, col := Color.WHITE, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if parent: parent.add_child(l)
	return l


func _card(b: Button, col: Color, border := Color(1, 1, 1, 0.2), bw := 2, radius := 16) -> void:
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.12) if st == "hover" else col
		sb.set_corner_radius_all(radius)
		sb.border_color = border; sb.set_border_width_all(bw)
		sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 8; sb.content_margin_bottom = 8
		b.add_theme_stylebox_override(st, sb)


func _build_home() -> Control:
	var c := Control.new(); c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := MarginContainer.new(); m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 28)
	c.add_child(m)
	var v := VBoxContainer.new(); v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)
	_lbl("LABYRINTHE DES PAROLES", 38, GOLD, v)
	_lbl("Chaque phrase est une salle. Prends le tunnel du mot manquant.", 16, MUTED, v)
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(0, 170)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	carousel = HBoxContainer.new(); carousel.add_theme_constant_override("separation", 12)
	sc.add_child(carousel)
	var dr := HBoxContainer.new(); dr.alignment = BoxContainer.ALIGNMENT_CENTER; dr.add_theme_constant_override("separation", 10)
	v.add_child(dr)
	for i in DIFFS.size():
		var b := Button.new(); b.text = "%s\n%d tunnels" % [DIFFS[i].name, DIFFS[i].ch]
		b.custom_minimum_size = Vector2(130, 60)
		b.pressed.connect(func(): sel_diff = i; _refresh_home())
		dr.add_child(b); diff_btns.append(b)
	play_btn = Button.new(); play_btn.text = "JOUER"
	play_btn.custom_minimum_size = Vector2(260, 64); play_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play_btn.add_theme_font_size_override("font_size", 26)
	_card(play_btn, Color("2e7d4f"), GOLD, 3, 22)
	play_btn.pressed.connect(_play_pressed)
	v.add_child(play_btn)
	home_msg = _lbl("", 15, Color("ff9b9b"), v)
	_lbl("ZQSD / flèches : marcher · ←/→ ou souris : tourner · M : carte · Espace : pause · Échap : menu", 13, MUTED, v)
	return c


func _build_results() -> Control:
	var c := CenterContainer.new(); c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color("151a33"); sb.set_corner_radius_all(20)
	sb.border_color = GOLD; sb.set_border_width_all(2)
	for k in ["left", "right", "top", "bottom"]: sb.set("content_margin_" + k, 28)
	p.add_theme_stylebox_override("panel", sb)
	c.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 14); p.add_child(v)
	res_lbl = RichTextLabel.new(); res_lbl.bbcode_enabled = true; res_lbl.fit_content = true; res_lbl.scroll_active = false
	res_lbl.custom_minimum_size = Vector2(460, 0)
	res_lbl.add_theme_font_size_override("normal_font_size", 20)
	v.add_child(res_lbl)
	var h := HBoxContainer.new(); h.alignment = BoxContainer.ALIGNMENT_CENTER; h.add_theme_constant_override("separation", 12); v.add_child(h)
	var b1 := Button.new(); b1.text = "Rejouer"; b1.pressed.connect(_play_pressed); _card(b1, Color("2e7d4f"), GOLD, 2, 14); h.add_child(b1)
	var b2 := Button.new(); b2.text = "Accueil"; b2.pressed.connect(_home_open); _card(b2, Color("2a3050")); h.add_child(b2)
	return c


func _build_menu() -> Control:
	var c := CenterContainer.new(); c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10)
	c.add_child(v)
	_lbl("Pause", 28, GOLD, v)
	for it in [["Reprendre", func(): _set_menu(false)], ["Recommencer", func(): _set_menu(false); _play_pressed()], ["Quitter vers l'accueil", func(): _set_menu(false); _home_open()]]:
		var b := Button.new(); b.text = it[0]; b.custom_minimum_size = Vector2(260, 48)
		_card(b, Color("2a3050"), GOLD, 2, 12)
		b.pressed.connect(it[1])
		v.add_child(b)
	root.add_child(c)
	root.visible = false
	return root


func _show(s: int) -> void:
	scene = s
	home.visible = s == 0
	results.visible = s == 2
	view.visible = s == 1
	if s != 1:
		_capture(false)
		if heart_player != null:
			heart_player.stop(); rumble_player.stop()


func _capture(on: bool) -> void:
	mouse_cap = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _set_menu(on: bool) -> void:
	menu_open = on
	menu.visible = on
	if on: _capture(false)
	if player != null: player.stream_paused = on or paused


func _home_open() -> void:
	player.stop()
	inst_player.stop()
	player.volume_db = 0.0
	paused = false
	_set_menu(false)
	_reset_mix()
	lib = []
	if FileAccess.file_exists(LIB_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(LIB_PATH))
		if d is Array: lib = d
	var ok := []
	for t in lib:
		if String(t.get("lrc", "")) != "" and FileAccess.file_exists(t.lrc): ok.append(t)
	for c in carousel.get_children(): c.queue_free()
	var want: String = save["maze"].get("last", {}).get("track", "")
	if sel_track.is_empty() and want != "":
		for t in ok:
			if t.get("file", "") == want: sel_track = t
	if sel_track.is_empty() or not ok.any(func(x): return x.get("file", "") == sel_track.get("file", "")):
		sel_track = ok[0] if not ok.is_empty() else {}
	for t in ok:
		var b := Button.new()
		b.custom_minimum_size = Vector2(210, 140)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 16)
		b.set_meta("t", t)
		b.text = "♫\n%s\n%s" % [t.get("track", "?"), t.get("artist", "")]
		b.pressed.connect(func(): sel_track = t; _refresh_home())
		carousel.add_child(b)
	home_msg.text = "" if not ok.is_empty() else "Aucun morceau avec paroles synchronisées.\nOuvre Music, joue un morceau et récupère ses paroles."
	play_btn.disabled = ok.is_empty()
	_show(0)
	_refresh_home()


func _refresh_home() -> void:
	for b in carousel.get_children():
		var on: bool = b.get_meta("t").get("file", "") == sel_track.get("file", "")
		_card(b, Color("2e4a8a") if on else Color("1c2142"), GOLD if on else Color(1, 1, 1, 0.18), 3 if on else 2)
	for i in diff_btns.size():
		_card(diff_btns[i], Color("7a5a1c") if i == sel_diff else Color("1c2142"), GOLD if i == sel_diff else Color(1, 1, 1, 0.18), 3 if i == sel_diff else 2, 12)


# ------------------------------------------------------------------ Questions
func _words(s: String) -> Array:
	var out := []
	for w in s.split(" ", false):
		out.append(w.strip_edges().lstrip("¿¡\"'(").rstrip(".,;:!?\"')…"))
	return out


func _build_rooms() -> Array:
	var nopt: int = DIFFS[sel_diff].ch
	var tol: int = DIFFS[sel_diff].tol
	var pool := []
	for i in lines.size():
		for w in _words(lines[i][1]):
			if w.length() >= 4 and not pool.has(w.to_lower()): pool.append(w.to_lower())
	var res := []
	for i in lines.size() - 1:
		if res.size() >= 60: break
		var q := _make_word_q(i, pool, nopt, tol)
		if not q.is_empty(): res.append(q)
	# agencement / thème / réverb de chaque salle, tirés d'une graine propre à la partie
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	var lays := ["plain", "piliers", "alcoves", "L", "Z", "ronde", "carree", "escalier"]
	var tints := [Color(1, 0.9, 0.75), Color(0.8, 0.92, 1.0), Color(0.85, 1.0, 0.82), Color(1.0, 0.8, 0.8), Color(0.95, 0.85, 1.0)]
	var last_lay := ""
	for i in res.size():
		var q: Dictionary = res[i]
		var lay: String = lays[rng.randi() % lays.size()]
		while lay == last_lay: lay = lays[rng.randi() % lays.size()]
		last_lay = lay
		q["layout"] = lay
		q["mir"] = rng.randf() < 0.5
		q["hue"] = rng.randf()
		q["sat"] = rng.randf_range(0.3, 0.7)
		q["val"] = rng.randf_range(0.62, 0.85)
		q["pat"] = rng.randi() % 5
		q["tint"] = tints[rng.randi() % tints.size()]
		var nw: int = q.ws.size()
		var rt := "salle"
		if i == res.size() - 1: rt = "derniere"
		elif lay == "L" or lay == "Z" or nw <= 4: rt = "couloir"
		elif lay == "ronde" or lay == "carree" or nw >= 9: rt = "grande"
		elif i % 4 == 3 or lay == "piliers": rt = "carrefour"
		q["rt"] = rt
	return res


func _make_word_q(i: int, pool: Array, nopt: int, tol: int) -> Dictionary:
	var ws := _words(lines[i][1])
	var idx := []
	for k in ws.size():
		if ws[k].length() >= 3: idx.append(k)
	if ws.size() < 3 or idx.is_empty(): return {}
	var k: int = idx[randi() % idx.size()]
	var txt: String = lines[i][1]
	var t0: float = lines[i][0]
	var t1: float = lines[i + 1][0]
	var before := 0
	for j in k: before += ws[j].length() + 1
	var tw := t0 + minf(t1 - t0, 6.0) * float(before) / float(maxi(1, txt.length())) * 0.95
	var good: String = ws[k]
	var opts := [good.to_lower()]
	var tries := 0
	while opts.size() < nopt and tries < 300 and not pool.is_empty():
		tries += 1
		var d: String = pool[randi() % pool.size()]
		if opts.has(d): continue
		if absi(d.length() - good.length()) > tol and tries < 150: continue
		opts.append(d)
	if opts.size() < nopt: return {}
	opts.shuffle()
	var stop := tw - offset
	var dur := clampf(0.085 * good.length() + 0.15, 0.3, 1.0)
	var li0 := i - 1 if (k <= 1 and i > 0) else i
	var mb := stop + dur + 0.35
	return {"line": i, "k": k, "ws": ws, "answer": good.to_lower(), "opts": opts, "good_idx": opts.find(good.to_lower()),
		"stop": stop, "mute_a": stop - 0.35, "mute_b": mb,
		"ps": maxf(0.0, float(lines[li0][0]) - offset - REPLAY_PAD),
		"loop_at": maxf(float(t1) - offset - 0.05, mb + 0.4),
		"ok": false, "tries": 0, "wrong": [], "visited": false, "first": false, "loops": 0,
		"picked": false, "pick": -1, "judged": false}


# ------------------------------------------------------------------ Partie
func _play_pressed() -> void:
	if sel_track.is_empty(): return
	if not _load_track(sel_track): return
	save["maze"]["last"] = {"diff": sel_diff, "track": sel_track.get("file", "")}
	_write_save()
	_start()


func _load_track(t: Dictionary) -> bool:
	var path: String = t.file
	var g := ProjectSettings.globalize_path(path)
	var st: AudioStream = AudioStreamOggVorbis.load_from_file(g) if path.get_extension().to_lower() == "ogg" else AudioStreamMP3.load_from_file(g)
	if st == null:
		home_msg.text = "Fichier illisible."
		return false
	stream = st
	player.stream = st
	lines = Lyrics.parse(FileAccess.get_file_as_string(t.lrc))
	offset = float(t.get("offset", 0.0))
	song = "%s — %s" % [t.get("artist", ""), t.get("track", "")]
	_prepare_inst(path)
	_load_translations(t)
	mast_cur = save["mastery"].get(String(t.file), {"b": {}, "n": 0})
	return true


func _start() -> void:
	run_seed = randi()
	rooms = _build_rooms()
	if rooms.size() < 3:
		home_msg.text = "Pas assez de paroles synchronisées pour ce morceau."
		_show(0)
		return
	score = 0; streak = 0; best_streak = 0; glog = []; paused = false; mix_t = 0.0; reveal_until = -1.0
	lives = 3; chase_d = 0.9; chase_s = 0.9; scare = 0.0; shake = 0.0; rew = 0.0; trav = 0.0; par_t = 0.0; step_t = 0.0; cstep_t = 0.5
	dust = []
	for i in 80: dust.append({"x": randf(), "y": randf(), "z": randf_range(0.15, 1.0)})
	_set_menu(false)
	player.volume_db = 0.0
	pos = Vector2(5.5, 9.3)
	ang = -PI / 2.0
	_show(1)
	grab_focus()
	_seek(0.0)
	_enter_room(0, true)
	heart_player.play(); rumble_player.play()
	_play_sfx("go")
	_say("Mode horreur : une chose te suit. Choisis un tunnel avant le mot.", GOLD)


func _say(t: String, col: Color) -> void:
	msg = t; msg_t = 2.6; msg_col = col


func _apply_room_fx(q: Dictionary, instant: bool) -> void:
	var fx: Dictionary = ROOMFX[String(q.get("rt", "salle"))]
	if rv_tw != null and rv_tw.is_valid(): rv_tw.kill()
	if instant:
		rv_size = fx.size; rv_damp = fx.damp; rv_wet = fx.wet
		return
	rv_tw = create_tween().set_parallel(true)
	rv_tw.tween_property(self, "rv_size", float(fx.size), 0.4)
	rv_tw.tween_property(self, "rv_damp", float(fx.damp), 0.4)
	rv_tw.tween_property(self, "rv_wet", float(fx.wet), 0.4)


func _enter_room(r: int, first_time: bool) -> void:
	cur = r
	var q: Dictionary = rooms[r]
	q["visited"] = true
	_build_grid(q.opts.size())
	hue = float(q.hue)
	phase = 0
	chosen = -1
	entered = false
	_apply_room_fx(q, rv_tw == null)
	if first_time:
		pos = Vector2(clampf(pos.x, 1.5, gw - 1.5), 9.3)
		var p := _pos_now()
		if p > float(q.loop_at): _seek(float(q.ps))
	else:
		pos = Vector2(gw * 0.5, 9.3)
		ang = -PI / 2.0


func _build_grid(n: int) -> void:
	gw = 3 * n + 2
	grid = PackedByteArray()
	grid.resize(gw * GH)
	grid.fill(1)
	for y in range(int(HALL_Y0), GH - 1):
		for x in range(1, gw - 1): grid[y * gw + x] = 0
	door_xs = []
	for k in n:
		var x := 2 + 3 * k
		door_xs.append(x)
		for y in range(1, 4): grid[y * gw + x] = 0
		grid[0 * gw + x] = 3
		grid[4 * gw + x] = 2
	var q: Dictionary = rooms[cur]
	var bl: Array = []
	var third := gw / 3
	match String(q.layout):
		"piliers":
			for dx in door_xs: bl.append(Vector2i(int(dx) + 1, 7))
		"alcoves":
			bl.append_array([Vector2i(1, 7), Vector2i(2, 7), Vector2i(gw - 3, 7), Vector2i(gw - 2, 7)])
		"L":
			for x in range(1, third + 1):
				for y in range(6, 9): bl.append(Vector2i(x, y))
		"Z":
			for x in range(1, third + 1):
				for y in range(7, 9): bl.append(Vector2i(x, y))
			for x in range(2 * third, gw - 1):
				for y in range(6, 8): bl.append(Vector2i(x, y))
		"ronde":
			bl.append_array([Vector2i(1, 5), Vector2i(1, 6), Vector2i(gw - 2, 5), Vector2i(gw - 2, 6), Vector2i(1, 8), Vector2i(gw - 2, 8)])
		"carree":
			bl.append_array([Vector2i(1, 8), Vector2i(gw - 2, 8), Vector2i(1, 5), Vector2i(gw - 2, 5), Vector2i(int(door_xs[0]) + 1, 7), Vector2i(int(door_xs[-1]) - 1, 7)])
		"escalier":
			bl.append_array([Vector2i(1, 7), Vector2i(1, 8), Vector2i(2, 8)])
	for b in bl:
		var bx: int = gw - 1 - b.x if q.mir else b.x
		if b.y == 5 and door_xs.has(bx): continue
		if bx >= 1 and bx <= gw - 2 and b.y >= 5 and b.y <= 8: grid[b.y * gw + bx] = 1


func _cell(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= gw or y >= GH: return 1
	return grid[y * gw + x]


func _bump_door(cx: int) -> void:
	var idx := door_xs.find(cx)
	if idx < 0: return
	var q: Dictionary = rooms[cur]
	if q.picked:
		_say("Le verdict tombe avec la musique…", MUTED)
		return
	if q.wrong.has(idx):
		_say("Tunnel déjà essayé : faux", Color("ff9b9b"))
		return
	_choose(idx)


## Les tunnels se ressemblent : on ne sait pas si c'est le bon. Le verdict tombe quand la musique passe sur le mot.
func _choose(idx: int) -> void:
	var q: Dictionary = rooms[cur]
	q.pick = idx
	q.picked = true
	_play_sfx("door")
	fade = 0.35; fade_col = Color("ffffff")
	if cur + 1 < rooms.size():
		_say("Tunnel pris. Verdict au mot…", MUTED)
		_enter_room(cur + 1, true)
	else:
		_say("Dernier tunnel. Verdict au mot…", GOLD)


func _credit(q: Dictionary) -> void:
	q.judged = true
	q.ok = true
	var first: bool = int(q.tries) == 0
	q.first = first
	if first:
		var mult := clampi(1 + streak / 3, 1, 4)
		score += 100 * mult
		streak += 1
		best_streak = maxi(best_streak, streak)
		_say("Bon mot « %s » ! +%d" % [q.answer, 100 * mult], Color("8dffb0"))
	else:
		score += 30
		_say("Bon mot « %s » (+30)" % q.answer, Color("8dffb0"))
	glog.append({"line": q.line, "ok": true, "tries": q.tries})


func _verdict(i: int) -> void:
	var q: Dictionary = rooms[i]
	if int(q.pick) == int(q.good_idx):
		_credit(q)
		chase_d = minf(1.0, chase_d + 0.16)
		_play_sfx("good")
		print("MAZE verdict room=%d bon chase=%.2f" % [i, chase_d])
		if i == rooms.size() - 1: _finish(false)
		return
	# faux : retour dans la même salle, par l'arrière, phrase rejouée, la créature gagne du terrain
	q.tries += 1
	q.wrong.append(q.pick)
	q.picked = false
	q.pick = -1
	for j in range(i + 1, rooms.size()):
		rooms[j].picked = false
		rooms[j].pick = -1
	streak = 0
	chase_d = maxf(0.0, chase_d - 0.22)
	rew = 1.0; shake = 0.5
	fade = 1.0; fade_col = Color("a01818")
	_play_sfx("bad")
	_enter_room(i, false)
	_seek(float(q.ps))
	_say("Faux ! Retour dans la salle, il se rapproche…", Color("ff9b9b"))
	print("MAZE verdict room=%d FAUX replace-arriere chase=%.2f seek=%.2f" % [i, chase_d, float(q.ps)])


func _judge_tick(p: float) -> void:
	for _g in 80:
		var hit := false
		for i in mini(cur, rooms.size() - 1) + 1:
			var q: Dictionary = rooms[i]
			if q.picked and not q.judged and p >= float(q.mute_b):
				_verdict(i)
				hit = true
				break
		if not hit or scene != 1: return


func _caught() -> void:
	chase_d = 0.0
	scare = 1.7
	shake = 1.0
	lives -= 1
	sfx_player.stream = sfx["scare"]
	sfx_player.volume_db = 0.0
	sfx_player.play()
	print("MAZE caught lives=%d" % lives)


func _after_scare() -> void:
	sfx_player.volume_db = -6.0
	_judge_tick(1e9)
	if scene != 1: return
	if lives <= 0:
		_finish(true)
		return
	chase_d = 0.6; chase_s = 0.6; rew = 0.6
	_enter_room(cur, false)
	_seek(float(rooms[cur].ps))
	_say("Il t'a attrapé… on repart de cette salle (%d vie%s)" % [lives, "s" if lives > 1 else ""], Color("ff9b9b"))


func _first_unresolved() -> int:
	for i in rooms.size():
		if not rooms[i].ok: return i
	return -1





func _finish(caught := false) -> void:
	player.stop(); inst_player.stop()
	_play_sfx("end")
	if caught:
		for q in rooms:
			if q.picked and not q.judged and int(q.pick) == int(q.good_idx): _credit(q)
	var n := rooms.size()
	var good := 0
	for e in glog:
		if int(e.tries) == 0: good += 1
	var mb: Dictionary = mast_cur.get("b", {})
	for e in glog:
		var key := str(e.line)
		mb[key] = mini(3, int(mb.get(key, 0)) + 1) if int(e.tries) == 0 else 0
	mast_cur = {"b": mb, "n": lines.size()}
	save["mastery"][String(sel_track.get("file", ""))] = mast_cur
	var bk := "%s|%d" % [sel_track.get("file", ""), sel_diff]
	var prev := int(save["maze"]["best"].get(bk, 0))
	var rec := score > prev
	if rec: save["maze"]["best"][bk] = score
	_write_save()
	var acc := float(good) / float(maxi(1, n))
	var grade := "S" if acc >= 0.9 else ("A" if acc >= 0.75 else ("B" if acc >= 0.55 else ("C" if acc >= 0.35 else "D")))
	var head := "[color=#ff7a7a]Attrapé par la créature…[/color]" if caught else "[color=#ffd877]Sortie du labyrinthe ![/color]"
	res_lbl.text = "[center][font_size=30]%s[/font_size]\n%s\n\n[font_size=52]%s[/font_size]\n\nScore : [b]%d[/b]%s\nPremier coup : [b]%d / %d[/b] (%d %%)\nSalle atteinte : [b]%d / %d[/b]\nMeilleure série : [b]%d[/b][/center]" % [head, song, grade, score, "  [color=#8dffb0](record !)[/color]" if rec else "  (record %d)" % prev, good, n, int(acc * 100.0), cur + 1, n, best_streak]
	_show(2)
	print("MAZE finish caught=%s score=%d good=%d/%d grade=%s" % [str(caught), score, good, n, grade])


# ------------------------------------------------------------------ Boucle
func _reset_mix() -> void:
	mix_t = 0.0
	if lp != null: lp.cutoff_hz = 20000.0
	if se != null: se.surround = 0.0
	if reverb != null: reverb.wet = 0.0; reverb.dry = 1.0


func _process(d: float) -> void:
	t_anim += d
	if scene != 1:
		return
	msg_t = maxf(0.0, msg_t - d)
	fade = maxf(0.0, fade - d * 2.2)
	shake = maxf(0.0, shake - d * 1.2)
	rew = maxf(0.0, rew - d * 1.1)
	chase_s = lerpf(chase_s, chase_d, clampf(d * 2.5, 0.0, 1.0))
	par_t += d * (1.0 - rew * 25.0)
	trav -= d * rew * 10.0
	# lumière qui vacille (plus nerveuse quand la créature approche)
	var prox := clampf(1.0 - chase_s, 0.0, 1.0)
	flick_t = maxf(0.0, flick_t - d)
	if flick_t <= 0.0 and randf() < d * (0.25 + prox * 1.6): flick_t = randf_range(0.05, 0.22)
	lamp = clampf(0.9 + 0.08 * sin(t_anim * 11.0) * sin(t_anim * 5.3), 0.0, 1.0) * (0.35 if flick_t > 0.0 else 1.0)
	if not menu_open:
		if scare <= 0.0: _input_move(d)
		if not paused:
			if scare > 0.0:
				scare -= d
				if scare <= 0.0: _after_scare()
			else:
				_chase_step(d)
			if scene == 1: _audio_logic(d)
	_sync_inst()
	view.queue_redraw()


func _chase_step(d: float) -> void:
	chase_d = clampf(chase_d - float(DIFFS[sel_diff].cs) * d, 0.0, 1.0)
	if chase_d <= 0.0: _caught()


func _input_move(d: float) -> void:
	var fwd := 0.0
	var str_ := 0.0
	var turn := 0.0
	if Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): fwd += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): fwd -= 1.0
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_A): str_ -= 1.0
	if Input.is_key_pressed(KEY_D): str_ += 1.0
	if Input.is_key_pressed(KEY_LEFT): turn -= 1.0
	if Input.is_key_pressed(KEY_RIGHT): turn += 1.0
	_step_move(fwd, str_, turn, d, Input.is_key_pressed(KEY_SHIFT))


func _step_move(fwd: float, str_: float, turn: float, d: float, run := false) -> void:
	if scene != 1: return
	ang += turn * 2.2 * d
	var dir := Vector2(cos(ang), sin(ang))
	var rt := Vector2(-dir.y, dir.x)
	var v := (dir * fwd + rt * str_)
	if v.length() > 1.0: v = v.normalized()
	running = run and v != Vector2.ZERO
	v *= 3.0 * d * (RUN_MULT if run else 1.0)
	if v != Vector2.ZERO:
		bob += d * (13.0 if run else 9.0)
		trav += fwd * 3.0 * d * (RUN_MULT if run else 1.0)
		step_t -= d * (RUN_MULT if run else 1.0)
		if step_t <= 0.0:
			step_t = 0.42
			step_player.pitch_scale = randf_range(0.85, 1.15)
			step_player.play()
	var r := 0.22
	var nx := pos.x + v.x
	var cxn := _cell(int(nx + signf(v.x) * r), int(pos.y))
	if cxn == 0: pos.x = nx
	elif cxn == 2 and fwd > 0.0: _bump_door(int(nx + signf(v.x) * r))
	var ny := pos.y + v.y
	var cyn := _cell(int(pos.x), int(ny + signf(v.y) * r))
	if cyn == 0: pos.y = ny
	elif cyn == 2 and fwd > 0.0: _bump_door(int(pos.x))


func _audio_logic(d: float) -> void:
	if player.stream == null and not menu_open: clock += d
	elif player.playing: clock = player.get_playback_position()
	var q: Dictionary = rooms[cur]
	var p := _pos_now()
	_judge_tick(p)
	if scene != 1: return
	q = rooms[cur]
	# --- son lié à la distance de la créature (loin : étouffé, distant, réverbéré ; près : net, sec, fort, large)
	var prox := clampf(1.0 - chase_s, 0.0, 1.0)
	if lp != null: lp.cutoff_hz = 1500.0 * pow(13.34, prox)
	if se != null: se.surround = lerpf(0.0, 0.9, prox)
	if reverb != null:
		reverb.room_size = rv_size
		reverb.damping = rv_damp
		reverb.wet = clampf(rv_wet + (1.0 - prox) * 0.5, 0.0, 0.95)
		reverb.dry = lerpf(0.5, 1.0, prox)
	var vol := lerpf(-11.0, 0.0, prox)
	var hole := false
	for i in mini(cur, rooms.size() - 1) + 1:
		var qq: Dictionary = rooms[i]
		if not qq.judged and p >= float(qq.mute_a) and p <= float(qq.mute_b):
			hole = true
			break
	if inst_ready:
		player.volume_db = move_toward(player.volume_db, -60.0 if hole else vol, 350.0 * d)
		inst_player.volume_db = move_toward(inst_player.volume_db, vol if hole else -60.0, 350.0 * d)
	else:
		player.volume_db = move_toward(player.volume_db, -60.0 if hole else vol, 350.0 * d)
	# battement de coeur + grondement + pas de la créature
	var pw := pow(prox, 1.5)
	heart_player.volume_db = -60.0 if prox < 0.06 else lerpf(-42.0, -2.0, pw)
	heart_player.pitch_scale = lerpf(0.6, 1.9, prox)
	rumble_player.volume_db = -60.0 if prox < 0.06 else lerpf(-48.0, -7.0, pow(prox, 1.3))
	rumble_player.pitch_scale = lerpf(0.85, 1.25, prox)
	if prox > 0.25:
		cstep_t -= d
		if cstep_t <= 0.0:
			cstep_t = lerpf(0.95, 0.38, prox)
			cstep_player.volume_db = lerpf(-30.0, -4.0, prox)
			cstep_player.pitch_scale = randf_range(0.8, 1.0)
			cstep_player.play()
	end_checked = maxf(0.0, end_checked - d)
	if not q.picked:
		if p >= float(q.loop_at) and end_checked <= 0.0:
			q.loops += 1
			_seek(float(q.ps))
			_say("La phrase reboucle…", MUTED)
		elif player.stream != null and not player.playing and end_checked <= 0.0:
			_seek(float(q.ps))
	elif player.stream != null and not player.playing and end_checked <= 0.0:
		_judge_tick(1e9)


func _input(ev: InputEvent) -> void:
	if scene != 1: return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_M, KEY_TAB:
				map_open = not map_open
				get_viewport().set_input_as_handled()
			KEY_SPACE:
				paused = not paused
				player.stream_paused = paused or menu_open
				_say("Pause" if paused else "Reprise", MUTED)
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if map_open: map_open = false
				else: _set_menu(not menu_open)
				get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and ev.pressed and not menu_open and not mouse_cap:
		if get_global_rect().has_point(ev.global_position): _capture(true)
	elif ev is InputEventMouseMotion and mouse_cap and not menu_open:
		ang += ev.relative.x * 0.0035




# ------------------------------------------------------------------ Rendu
func _h2(a: float, b: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)


## Texture procédurale : luminosité de la bande r (sur n) à l'abscisse murale wx.
func _tex_b(pat: int, wx: float, r: int, seed_: float) -> float:
	match pat:
		1:
			var u := wx * 3.0 + (r % 2) * 0.5
			if fposmod(u, 1.0) < 0.07: return 0.6
			return 0.9 + 0.2 * _h2(floorf(u) + seed_, float(r))
		2:
			if fposmod(wx * 2.0, 1.0) < 0.06: return 0.55
			return 0.8 if (r == 0 or r == 2) else 1.08
		3:
			return 1.1 if r % 2 == 0 else 0.8
		4:
			if _h2(floorf(wx * 20.0), seed_) < 0.07: return 0.5
			return 0.8 + 0.3 * _h2(floorf(wx * 10.0) + seed_ * 3.0, float(r))
	return 1.0


func _wall_col(g: int, side: int, perp: float, wx: float, dx: int, dead: bool, sat: float, val: float) -> Color:
	var c: Color
	if g == 2:
		c = Color("8a2a2a") if dead else Color.from_hsv(fposmod(hue + 0.08, 1.0), 0.55, 0.62)
		if wx < 0.07 or wx > 0.93: c = Color("e0b04a")
	elif g == 3:
		c = Color("2a2a38")
	else:
		c = Color.from_hsv(hue, sat, val)
		if wx < 0.035 or wx > 0.965: c = c.darkened(0.3)
	var sh := clampf(1.0 - perp / 9.5, 0.1, 1.0)
	if side == 1: sh *= 0.78
	return Color(c.r * sh, c.g * sh, c.b * sh)


## Créature : silhouette sombre aux yeux lumineux (base = pieds, h = hauteur).
func _draw_creature(base: Vector2, h: float, a: float, mouth := false) -> void:
	if h < 3.0: return
	var hc := base + Vector2(0, -h * 0.82)
	var r := h * 0.13
	var rim := Color(0.45, 0.04, 0.06, a * 0.55)
	var body := Color(0.015, 0.0, 0.025, a)
	var torso := PackedVector2Array([base + Vector2(-h * 0.2, -h * 0.7), base + Vector2(h * 0.2, -h * 0.7), base + Vector2(h * 0.32, -h * 0.04), base + Vector2(-h * 0.32, -h * 0.04)])
	var big := PackedVector2Array([base + Vector2(-h * 0.225, -h * 0.725), base + Vector2(h * 0.225, -h * 0.725), base + Vector2(h * 0.35, -h * 0.02), base + Vector2(-h * 0.35, -h * 0.02)])
	view.draw_colored_polygon(big, rim)
	view.draw_circle(hc, r * 1.12, rim)
	view.draw_colored_polygon(torso, body)
	view.draw_circle(hc, r, body)
	for sd in [-1.0, 1.0]:
		var sh := base + Vector2(sd * h * 0.2, -h * 0.68)
		view.draw_line(sh, base + Vector2(sd * h * 0.46, -h * 0.02), body, maxf(2.0, h * 0.055))
		view.draw_colored_polygon(PackedVector2Array([hc + Vector2(sd * r * 0.6, -r * 0.8), hc + Vector2(sd * r * 1.2, -r * 1.9), hc + Vector2(sd * r * 0.1, -r * 0.9)]), body)
	var ea := clampf(a * 1.6, 0.0, 1.0)
	for sd in [-1.0, 1.0]:
		var ep := hc + Vector2(sd * r * 0.42, -r * 0.1)
		view.draw_circle(ep, r * 0.42, Color(1.0, 0.1, 0.05, ea * 0.28))
		view.draw_circle(ep, r * 0.2, Color(1.0, 0.35, 0.1, ea))
		view.draw_circle(ep, r * 0.09, Color(1.0, 0.95, 0.6, ea))
	if mouth:
		var mp := hc + Vector2(0, r * 0.5)
		view.draw_colored_polygon(PackedVector2Array([mp + Vector2(-r * 0.6, 0), mp + Vector2(r * 0.6, 0), mp + Vector2(0, r * 0.7)]), Color(0.5, 0.0, 0.03, a))
		for k in 5:
			var tx := mp.x - r * 0.5 + k * r * 0.25
			view.draw_colored_polygon(PackedVector2Array([Vector2(tx, mp.y), Vector2(tx + r * 0.12, mp.y), Vector2(tx + r * 0.06, mp.y + r * 0.22)]), Color(0.95, 0.9, 0.8, a))


func _draw_vignette(vw: float, vh: float, prox: float) -> void:
	var c := Vector2(vw, vh) * 0.5
	var rin := lerpf(1.05, 0.4, prox)
	var ab := lerpf(0.5, 0.95, prox)
	var pulse := 0.5 + 0.5 * sin(t_anim * lerpf(2.0, 9.0, prox))
	var ar := prox * prox * (0.2 + 0.5 * pulse)
	var n := 28
	var clear := Color(0, 0, 0, 0)
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var rx := vw * 0.5
		var ry := vh * 0.5
		var pts := PackedVector2Array([c + d0 * Vector2(rx, ry) * rin, c + d1 * Vector2(rx, ry) * rin, c + d1 * Vector2(rx, ry) * 1.7, c + d0 * Vector2(rx, ry) * 1.7])
		view.draw_polygon(pts, PackedColorArray([clear, clear, Color(0, 0, 0, ab), Color(0, 0, 0, ab)]))
		if ar > 0.01:
			view.draw_polygon(pts, PackedColorArray([clear, clear, Color(0.8, 0.0, 0.0, ar), Color(0.8, 0.0, 0.0, ar)]))


## Parallaxe : brume et poussière en couches qui défilent à des vitesses différentes (tourner, avancer, reculer après une erreur).
func _draw_layers(vw: float, vh: float, hz: float, tint: Color, prox: float) -> void:
	for j in 3:
		var kk := 0.25 + 0.3 * j
		var yb := hz + (j - 1) * vh * 0.12 + sin(t_anim * 0.4 + j) * 6.0
		var bw := vw * 1.6
		var x0 := fposmod(-ang * vw * 0.35 * kk + par_t * 3.0 * kk, bw)
		var mc := Color(tint.r * 0.7, tint.g * 0.7, tint.b * 0.8, (0.035 + 0.03 * j) * (1.0 + prox))
		view.draw_rect(Rect2(x0 - bw, yb, bw, vh * 0.08), mc)
		view.draw_rect(Rect2(x0, yb, bw, vh * 0.08), mc)
	for dd in dust:
		var kk: float = dd.z
		var x := fposmod(float(dd.x) * vw - ang * vw * 0.45 * kk + par_t * 6.0 * kk, vw)
		var y := fposmod(float(dd.y) * vh + trav * 26.0 * kk + t_anim * 4.0 * kk, vh)
		var col := Color(tint.r, tint.g, tint.b, (0.12 + 0.25 * kk) * lamp)
		if rew > 0.05:
			view.draw_line(Vector2(x, y), Vector2(x - rew * 90.0 * kk, y), col, 0.8 + 2.0 * kk)
		else:
			view.draw_circle(Vector2(x, y), 0.8 + 2.4 * kk, col)


func _draw_grain(vw: float, vh: float, prox: float) -> void:
	if prox <= 0.7: return
	var k := (prox - 0.7) / 0.3
	for i in int(k * 110.0):
		view.draw_rect(Rect2(randf() * vw, randf() * vh, 2, 2), Color(1, 1, 1, randf_range(0.05, 0.18)))
	if prox > 0.85 and randf() < 0.35:
		var y := randf() * vh
		view.draw_rect(Rect2(randf_range(-6.0, 6.0), y, vw, randf_range(3.0, 10.0)), Color(0.9, 0.1, 0.1, 0.07 * k))
		view.draw_rect(Rect2(randf_range(-10.0, 10.0), y + 6.0, vw, 2.0), Color(0.1, 0.9, 0.9, 0.06 * k))


func _draw_mirror(vw: float, prox: float) -> float:
	var mw := clampf(vw * 0.28, 70.0, 140.0)
	var mh := mw * 0.5
	var r := Rect2(vw * 0.5 - mw * 0.5, 28, mw, mh)
	view.draw_rect(r, Color(0.04, 0.02, 0.05, 0.92))
	if cr_ty < -0.2:
		var by := -cr_ty
		var lat := clampf(cr_tx / by, -1.0, 1.0)
		var hh := mh * lerpf(0.3, 0.98, prox * prox)
		var cx := r.position.x + mw * 0.5 + lat * mw * 0.4
		cx = clampf(cx, r.position.x + hh * 0.3, r.end.x - hh * 0.3)
		_draw_creature(Vector2(cx, r.end.y - 1.0), hh, clampf(0.35 + prox, 0.0, 1.0) * (0.5 + lamp * 0.5))
	else:
		view.draw_rect(Rect2(r.position.x, r.position.y + mh * 0.6, mw, mh * 0.4), Color(0.1, 0.06, 0.1, 0.8))
	view.draw_rect(r, Color(GOLD.r, GOLD.g, GOLD.b, 0.55), false, 2.0)
	return mh


func _draw_game() -> void:
	if rooms.is_empty(): return
	var vw := view.size.x
	var vh := view.size.y
	var q: Dictionary = rooms[cur]
	var prox := clampf(1.0 - chase_s, 0.0, 1.0)
	var tint: Color = q.tint
	var sat: float = q.sat
	var val: float = q.val
	var pat: int = q.pat
	var c0 := Vector2(vw, vh) * 0.5
	var off := Vector2.ZERO
	var rot := 0.0
	var amp := shake * 14.0 + maxf(0.0, prox - 0.85) * 12.0
	if amp > 0.0: off = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amp
	if running:
		rot = sin(bob * 0.5) * 0.012
		off.y += sin(bob) * 4.0
	view.draw_set_transform_matrix(Transform2D(rot, c0 + off) * Transform2D(0.0, -c0))
	var hz := vh * 0.5 + sin(bob) * 3.0
	# plafond / sol dégradés
	var nb := 14
	for i in nb:
		var t := float(i) / float(nb - 1)
		var bh := hz / nb
		view.draw_rect(Rect2(-20, hz - (i + 1) * bh, vw + 40, bh + 1), Color.from_hsv(hue, 0.5, (0.05 + 0.2 * t) * lamp))
		var fh := (vh - hz) / nb
		view.draw_rect(Rect2(-20, hz + i * fh, vw + 40, fh + 1), Color.from_hsv(fposmod(hue + 0.06, 1.0), 0.35, (0.06 + 0.26 * t) * lamp))
	var cols := int(ceil(vw / COLW))
	var dirx := cos(ang)
	var diry := sin(ang)
	var plx := -diry * FOVK
	var ply := dirx * FOVK
	door_vis = {}
	look_door = -1
	look_dist = 99.0
	for c in cols:
		var camx := 2.0 * c / cols - 1.0
		var rdx := dirx + plx * camx
		var rdy := diry + ply * camx
		var mx := int(pos.x)
		var my := int(pos.y)
		var ddx := 1e30 if rdx == 0.0 else absf(1.0 / rdx)
		var ddy := 1e30 if rdy == 0.0 else absf(1.0 / rdy)
		var stx := 1 if rdx > 0 else -1
		var sty := 1 if rdy > 0 else -1
		var sdx := ((mx + 1 - pos.x) if rdx > 0 else (pos.x - mx)) * ddx
		var sdy := ((my + 1 - pos.y) if rdy > 0 else (pos.y - my)) * ddy
		var side := 0
		var g := 0
		var guard := 0
		while guard < 40:
			guard += 1
			if sdx < sdy:
				sdx += ddx; mx += stx; side = 0
			else:
				sdy += ddy; my += sty; side = 1
			g = _cell(mx, my)
			if g != 0: break
		var perp := (sdx - ddx) if side == 0 else (sdy - ddy)
		perp = maxf(perp, 0.05)
		var wx := (pos.y + perp * rdy) if side == 0 else (pos.x + perp * rdx)
		wx -= floor(wx)
		var dx := -1
		if g == 2 or g == 3: dx = door_xs.find(mx)
		var h := vh / perp
		var col := _wall_col(g, side, perp, wx, dx, g == 2 and dx >= 0 and q.wrong.has(dx), sat, val)
		# lampe torche : cône plus clair au centre, vacillement, teinte de la salle
		var cf := lerpf(0.42, 1.0, clampf(1.0 - absf(camx) * 1.15, 0.0, 1.0)) * lamp
		col = Color(col.r * cf * tint.r, col.g * cf * tint.g, col.b * cf * tint.b)
		var x := c * COLW
		var top := hz - h * 0.5
		if g == 1 and pat > 0:
			var nr := [1, 4, 3, 6, 5][pat]
			var sd := float(mx * 7 + my * 3)
			for r in nr:
				var b := _tex_b(pat, wx, r, sd)
				view.draw_rect(Rect2(x, top + h * r / nr, COLW, h / nr + 1.0), Color(col.r * b, col.g * b, col.b * b))
		else:
			view.draw_rect(Rect2(x, top, COLW, h + 1), col)
		view.draw_rect(Rect2(x, hz + h * 0.5 - h * 0.06, COLW, h * 0.06), col.darkened(0.45))
		if g == 2 and dx >= 0:
			var e: Dictionary = door_vis.get(dx, {"x0": x, "x1": x, "p": perp})
			e["x1"] = x
			e["p"] = minf(e.p, perp)
			door_vis[dx] = e
			if c == cols / 2:
				look_door = dx; look_dist = perp
	# la créature (billboard) : derrière soi ; visible en se retournant
	var cpos := pos + Vector2(sin(t_anim * 0.9) * 0.5, 1.2 + chase_s * 6.5)
	var rel := cpos - pos
	var inv := 1.0 / (plx * diry - dirx * ply)
	cr_tx = inv * (diry * rel.x - dirx * rel.y)
	cr_ty = inv * (-ply * rel.x + plx * rel.y)
	if cr_ty > 0.25 and scare <= 0.0:
		var sx := vw * 0.5 * (1.0 + cr_tx / cr_ty)
		var hb := vh / cr_ty
		_draw_creature(Vector2(sx, hz + hb * 0.5), hb * 1.05, clampf(1.3 - cr_ty / 10.0, 0.2, 1.0) * (0.6 + lamp * 0.4))
	_draw_layers(vw, vh, hz, tint, prox)
	_draw_vignette(vw, vh, prox)
	_draw_grain(vw, vh, prox)
	# plaques des portes (toujours lisibles : par-dessus l'obscurité)
	var font := get_theme_default_font()
	for dx in door_vis:
		var e: Dictionary = door_vis[dx]
		var span: float = e.x1 - e.x0 + COLW
		var hh := vh / float(e.p)
		var txt: String = q.opts[dx]
		var dead: bool = q.wrong.has(dx)
		var fs := int(clampf(hh * 0.2, 10.0, 60.0))
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw > span * 0.9: fs = int(fs * span * 0.9 / tw)
		if fs < 8: continue
		tw = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx: float = (e.x0 + e.x1 + COLW) * 0.5
		view.draw_rect(Rect2(cx - tw * 0.5 - 8, hz - fs * 0.95, tw + 16, fs * 1.4), Color(0, 0, 0, 0.7))
		var tc := Color("ff8a8a") if dead else Color("fff3c4")
		view.draw_string(font, Vector2(cx - tw * 0.5, hz + fs * 0.25), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
		if dead: view.draw_line(Vector2(cx - tw * 0.5, hz - fs * 0.15), Vector2(cx + tw * 0.5, hz - fs * 0.15), Color("ff5a5a"), 3.0)
	view.draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_hud(vw, vh, q, font, prox)
	if scare > 0.0:
		var st := 1.0 - scare / 1.7
		var fl := 0.55 + 0.35 * sin(t_anim * 40.0)
		view.draw_rect(Rect2(0, 0, vw, vh), Color(0.7, 0.0, 0.0, clampf(fl * (1.0 - st * 0.4), 0.0, 1.0)))
		var jh := vh * lerpf(1.0, 2.3, minf(1.0, st * 3.0))
		view.draw_set_transform(Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 18.0)
		_draw_creature(Vector2(vw * 0.5, vh * 0.2 + jh), jh, 1.0, true)
		view.draw_set_transform(Vector2.ZERO)
		var tf := clampi(int(vw / 9.0), 22, 80)
		_text_c(font, "ATTRAPÉ", vw * 0.5, vh * 0.9, tf, Color(1, 0.2, 0.2, 0.95))
	if fade > 0.0: view.draw_rect(Rect2(0, 0, vw, vh), Color(fade_col.r, fade_col.g, fade_col.b, fade * 0.8))
	if map_open: _draw_map(vw, vh, font)


func _draw_game() -> void:
	if rooms.is_empty(): return
	var vw := view.size.x
	var vh := view.size.y
	var hz := vh * 0.5 + sin(bob) * 3.0
	var q: Dictionary = rooms[cur]
	# plafond / sol dégradés
	var nb := 14
	for i in nb:
		var t := float(i) / float(nb - 1)
		var bh := hz / nb
		view.draw_rect(Rect2(0, hz - (i + 1) * bh, vw, bh + 1), Color.from_hsv(hue, 0.5, 0.05 + 0.2 * t))
		var fh := (vh - hz) / nb
		view.draw_rect(Rect2(0, hz + i * fh, vw, fh + 1), Color.from_hsv(hue, 0.35, 0.06 + 0.26 * t))
	var cols := int(ceil(vw / COLW))
	var dirx := cos(ang)
	var diry := sin(ang)
	var plx := -diry * FOVK
	var ply := dirx * FOVK
	door_vis = {}
	look_door = -1
	look_dist = 99.0
	for c in cols:
		var camx := 2.0 * c / cols - 1.0
		var rdx := dirx + plx * camx
		var rdy := diry + ply * camx
		var mx := int(pos.x)
		var my := int(pos.y)
		var ddx := 1e30 if rdx == 0.0 else absf(1.0 / rdx)
		var ddy := 1e30 if rdy == 0.0 else absf(1.0 / rdy)
		var stx := 1 if rdx > 0 else -1
		var sty := 1 if rdy > 0 else -1
		var sdx := ((mx + 1 - pos.x) if rdx > 0 else (pos.x - mx)) * ddx
		var sdy := ((my + 1 - pos.y) if rdy > 0 else (pos.y - my)) * ddy
		var side := 0
		var g := 0
		var guard := 0
		while guard < 40:
			guard += 1
			if sdx < sdy:
				sdx += ddx; mx += stx; side = 0
			else:
				sdy += ddy; my += sty; side = 1
			g = _cell(mx, my)
			if g != 0: break
		var perp := (sdx - ddx) if side == 0 else (sdy - ddy)
		perp = maxf(perp, 0.05)
		var wx := (pos.y + perp * rdy) if side == 0 else (pos.x + perp * rdx)
		wx -= floor(wx)
		var dx := -1
		if g == 2 or g == 3: dx = door_xs.find(mx)
		var h := vh / perp
		var col := _wall_col(g, side, perp, wx, hue, dx)
		var x := c * COLW
		view.draw_rect(Rect2(x, hz - h * 0.5, COLW, h + 1), col)
		view.draw_rect(Rect2(x, hz + h * 0.5 - h * 0.06, COLW, h * 0.06), col.darkened(0.45))
		if g == 2 and dx >= 0:
			var e: Dictionary = door_vis.get(dx, {"x0": x, "x1": x, "p": perp})
			e["x1"] = x
			e["p"] = minf(e.p, perp)
			door_vis[dx] = e
			if c == cols / 2:
				look_door = dx; look_dist = perp
	# plaques des portes
	var font := get_theme_default_font()
	for dx in door_vis:
		var e: Dictionary = door_vis[dx]
		var span: float = e.x1 - e.x0 + COLW
		var hh := vh / float(e.p)
		var txt: String = q.opts[dx]
		var dead: bool = q.wrong.has(dx)
		var fs := int(clampf(hh * 0.2, 10.0, 60.0))
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw > span * 0.9: fs = int(fs * span * 0.9 / tw)
		if fs < 8: continue
		tw = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx: float = (e.x0 + e.x1 + COLW) * 0.5
		view.draw_rect(Rect2(cx - tw * 0.5 - 8, hz - fs * 0.95, tw + 16, fs * 1.4), Color(0, 0, 0, 0.62))
		var tc := Color("ff8a8a") if dead else Color("fff3c4")
		view.draw_string(font, Vector2(cx - tw * 0.5, hz + fs * 0.25), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
		if dead: view.draw_line(Vector2(cx - tw * 0.5, hz - fs * 0.15), Vector2(cx + tw * 0.5, hz - fs * 0.15), Color("ff5a5a"), 3.0)
	_draw_hud(vw, vh, q, font)
	if fade > 0.0: view.draw_rect(Rect2(0, 0, vw, vh), Color(fade_col.r, fade_col.g, fade_col.b, fade * 0.8))
	if map_open: _draw_map(vw, vh, font)


func _text_c(font: Font, s: String, cx: float, y: float, fs: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	view.draw_string(font, Vector2(cx - w * 0.5, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _hud_line(q: Dictionary) -> String:
	var ws: Array = q.ws.duplicate()
	if not q.ok: ws[int(q.k)] = "_____"
	return " ".join(ws)


func _draw_hud(vw: float, vh: float, q: Dictionary, font: Font, prox: float) -> void:
	var mir_h := _draw_mirror(vw, prox)
	var py := 30.0 + mir_h + 8.0
	var line := _hud_line(q)
	var fs := 22
	var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while w > vw - 40 and fs > 12:
		fs -= 1
		w = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	view.draw_rect(Rect2(vw * 0.5 - w * 0.5 - 14, py, w + 28, fs + 18), Color(0, 0, 0, 0.6))
	_text_c(font, line, vw * 0.5, py + fs + 4, fs, Color("fff3c4") if q.ok else Color.WHITE)
	var rtn: String = ROOMFX[String(q.rt)].n
	var narrow := vw < 480.0
	var ttl := ("Salle %d/%d" % [cur + 1, rooms.size()]) if narrow else ("%s · Salle %d / %d · %s" % [song, cur + 1, rooms.size(), rtn])
	view.draw_string(font, Vector2(8, 20), ttl, HORIZONTAL_ALIGNMENT_LEFT, maxf(40.0, vw * 0.5 - mir_h * 1.1 - 8.0 if narrow else vw * 0.5 - mir_h * 1.1), 14, Color(1, 1, 1, 0.8))
	view.draw_string(font, Vector2(vw * 0.5 + mir_h * 1.1, 20), "%d · x%d" % [score, streak] if narrow else "Score %d   Série %d" % [score, streak], HORIZONTAL_ALIGNMENT_RIGHT, vw * 0.5 - mir_h * 1.1 - 8.0, 15, GOLD)
	view.draw_string(font, Vector2(8, vh - 8), "M carte · Maj court" if narrow else "M carte · Maj courir · Espace pause · Échap menu", HORIZONTAL_ALIGNMENT_LEFT, vw * 0.55, 12, Color(1, 1, 1, 0.5))
	# vies + distance de la créature
	var bwid := clampf(vw * 0.3, 60.0, 130.0)
	view.draw_string(font, Vector2(8, vh - 42), "♥".repeat(maxi(0, lives)), HORIZONTAL_ALIGNMENT_LEFT, bwid, 16, Color("ff5a6a"))
	view.draw_rect(Rect2(8, vh - 32, bwid, 8), Color(0, 0, 0, 0.6))
	view.draw_rect(Rect2(8, vh - 32, bwid * clampf(chase_s, 0.0, 1.0), 8), Color.from_hsv(0.0, 0.8, lerpf(1.0, 0.55, chase_s)))
	view.draw_rect(Rect2(8, vh - 32, bwid, 8), Color(1, 1, 1, 0.35), false, 1.0)
	# viseur
	view.draw_circle(Vector2(vw * 0.5, vh * 0.5), 2.0, Color(1, 1, 1, 0.6))
	if msg_t > 0.0 and msg != "":
		var mfs := 24 if vw >= 480.0 else 15
		var mtw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, mfs).x
		while mtw > vw - 16.0 and mfs > 10:
			mfs -= 1
			mtw = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, mfs).x
		_text_c(font, msg, vw * 0.5, vh * 0.78, mfs, Color(msg_col.r, msg_col.g, msg_col.b, clampf(msg_t, 0.0, 1.0)))
	if paused: _text_c(font, "PAUSE", vw * 0.5, vh * 0.3, 40, Color(1, 1, 1, 0.85))
	# infobulle de traduction sur la porte regardée
	if look_door >= 0 and look_dist < 6.0 and phase == 0:
		var wd: String = q.opts[look_door]
		if not gloss_cache.has(wd): gloss_cache[wd] = _gloss(wd, int(q.line))
		var gl: String = gloss_cache[wd]
		var tip := "%s → %s" % [wd, gl if gl != "" else "pas de traduction"]
		var tw := font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var bx := vw * 0.5 - tw * 0.5 - 12
		view.draw_rect(Rect2(bx, vh * 0.62, tw + 24, 32), Color("1b1d22"))
		view.draw_rect(Rect2(bx, vh * 0.62, tw + 24, 32), GOLD, false, 2.0)
		view.draw_string(font, Vector2(bx + 12, vh * 0.62 + 22), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
	# minimap
	var cs := 8.0
	var mw := gw * cs
	var mh := GH * cs
	var o := Vector2(vw - mw - 12, vh - mh - 12)
	view.draw_rect(Rect2(o - Vector2(3, 3), Vector2(mw + 6, mh + 6)), Color(0, 0, 0, 0.55))
	for y in GH:
		for x in gw:
			var g := _cell(x, y)
			if g != 1:
				view.draw_rect(Rect2(o + Vector2(x, y) * cs, Vector2(cs, cs)), Color(1, 1, 1, 0.22) if g == 0 else Color(GOLD.r, GOLD.g, GOLD.b, 0.5))
	var pp := o + pos * cs
	view.draw_circle(pp, 3.0, Color("ff5a5a"))
	view.draw_line(pp, pp + Vector2(cos(ang), sin(ang)) * 9.0, Color("ff5a5a"), 2.0)


func _draw_map(vw: float, vh: float, font: Font) -> void:
	view.draw_rect(Rect2(0, 0, vw, vh), Color(0, 0, 0, 0.6))
	var pw := minf(vw - 40, 920.0)
	var ph := minf(vh - 40, 660.0)
	var px0 := (vw - pw) * 0.5
	var py0 := (vh - ph) * 0.5
	view.draw_rect(Rect2(px0 + 6, py0 + 8, pw, ph), Color(0, 0, 0, 0.4))
	view.draw_rect(Rect2(px0, py0, pw, ph), Color("f6efdc"))
	var ly := py0 + 70.0
	while ly < py0 + ph - 10:
		view.draw_line(Vector2(px0 + 8, ly), Vector2(px0 + pw - 8, ly), Color("c9d4e6"), 1.0)
		ly += 26.0
	view.draw_line(Vector2(px0 + 56, py0), Vector2(px0 + 56, py0 + ph), Color("e59a9a"), 1.5)
	view.draw_string(font, Vector2(px0 + 72, py0 + 40), "Carte du labyrinthe", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, INK)
	view.draw_string(font, Vector2(px0 + pw - 330, py0 + 40), "vert : réussi · rouge : raté · M ferme", HORIZONTAL_ALIGNMENT_RIGHT, 316, 13, Color(INK.r, INK.g, INK.b, 0.7))
	var n := rooms.size()
	var ncol := clampi(int(ceil(sqrt(n * 1.5))), 3, 8)
	var nrow := int(ceil(float(n) / ncol))
	var ax := px0 + 70.0
	var ay := py0 + 62.0
	var aw := pw - 90.0
	var ah := ph - 80.0
	var cw := aw / ncol
	var chh := ah / nrow
	var centers := []
	for i in n:
		var r := i / ncol
		var cx := i % ncol
		if r % 2 == 1: cx = ncol - 1 - cx
		centers.append(Vector2(ax + (cx + 0.5) * cw, ay + (r + 0.5) * chh))
	for i in n - 1:
		if rooms[i].visited and rooms[i + 1].visited:
			view.draw_line(centers[i], centers[i + 1], Color(INK.r, INK.g, INK.b, 0.6), 2.0)
	var bw := cw * 0.8
	var bh := chh * 0.74
	for i in n:
		var rm: Dictionary = rooms[i]
		var ctr: Vector2 = centers[i]
		var rect := Rect2(ctr - Vector2(bw, bh) * 0.5, Vector2(bw, bh))
		if not rm.visited:
			view.draw_circle(ctr, 3.0, Color(INK.r, INK.g, INK.b, 0.25))
			continue
		var fill := Color("fff8e6")
		if rm.ok and int(rm.tries) == 0: fill = Color("bfe5c6")
		elif int(rm.tries) > 0: fill = Color("efb7b0")
		view.draw_rect(rect, fill)
		view.draw_rect(rect, GOLD.darkened(0.2) if i == cur else Color(INK.r, INK.g, INK.b, 0.6), false, 4.0 if i == cur else 1.5)
		view.draw_string(font, rect.position + Vector2(4, 12), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
		if bh > 38.0 and bw > 70.0:
			var ex := _hud_line(rm)
			if ex.length() > 40: ex = ex.substr(0, 39) + "…"
			view.draw_multiline_string(font, rect.position + Vector2(5, 26), ex, HORIZONTAL_ALIGNMENT_LEFT, bw - 10, 11, 2, Color(INK.r, INK.g, INK.b, 0.9))
		if i == cur:
			var f := Vector2(clampf(pos.x / gw, 0.0, 1.0), clampf(pos.y / GH, 0.0, 1.0))
			var pp := rect.position + Vector2(8, 8) + f * (rect.size - Vector2(16, 16))
			var dv := Vector2(cos(ang), sin(ang))
			var nv := Vector2(-dv.y, dv.x)
			view.draw_colored_polygon(PackedVector2Array([pp + dv * 8.0, pp - dv * 5.0 + nv * 5.0, pp - dv * 5.0 - nv * 5.0]), Color("c62828"))



# ------------------------------------------------------------------ Instrumental (ffmpeg)
func _sync_inst() -> void:
	if inst_state == 1 and inst_thread != null and not inst_thread.is_alive():
		inst_thread.wait_to_finish()
		inst_thread = null
		if FileAccess.file_exists(inst_out):
			var st := AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(inst_out))
			if st != null:
				inst_player.stream = st
				inst_ready = true
				inst_state = 2
		if inst_state != 2: inst_state = 3
	if not inst_ready: return
	inst_player.stream_paused = player.stream_paused
	if player.playing:
		var pos := player.get_playback_position()
		if not inst_player.playing: inst_player.play(pos)
		elif absf(inst_player.get_playback_position() - pos) > 0.08: inst_player.seek(pos)
	elif inst_player.playing:
		inst_player.stop()


## Version « sans voix » du morceau (annulation du canal central) calculée une fois avec ffmpeg (PC).
func _prepare_inst(path: String) -> void:
	inst_ready = false
	inst_player.stop()
	inst_player.stream = null
	inst_state = 0
	if OS.get_name() == "Android" or inst_thread != null: return
	DirAccess.make_dir_recursive_absolute("user://lgame_inst")
	inst_out = "user://lgame_inst/%s.ogg" % path.md5_text()
	if FileAccess.file_exists(inst_out):
		var st := AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(inst_out))
		if st != null:
			inst_player.stream = st
			inst_ready = true
			inst_state = 2
		return
	inst_state = 1
	var src := ProjectSettings.globalize_path(path)
	var dst := ProjectSettings.globalize_path(inst_out)
	inst_thread = Thread.new()
	inst_thread.start(func():
		OS.execute("ffmpeg", ["-y", "-loglevel", "quiet", "-i", src, "-af", "pan=stereo|c0=0.8*c0-0.8*c1|c1=0.8*c1-0.8*c0", "-c:a", "libvorbis", "-q:a", "4", dst]))




# ------------------------------------------------------------------ Traductions
func _load_translations(t: Dictionary) -> void:
	tr_lines = {}
	dict_pair = ""
	var dir := DirAccess.open(MUSIC_DIR)
	if dir != null:
		var best := ""
		for f in dir.get_files():
			if f.begins_with(str(t.get("id", "")) + ".") and f.ends_with(".v3.json"):
				if best == "" or f.contains(".fra."): best = f
		if best != "":
			var d = JSON.parse_string(FileAccess.get_file_as_string(MUSIC_DIR.path_join(best)))
			if d is Dictionary:
				for k in d:
					if k != "_c": tr_lines[int(k)] = d[k]
	# langue des paroles (heuristique sur les petits mots) -> dictionnaire hors-ligne
	var stop := {
		"spa-eng": ["el", "los", "las", "que", "una", "con", "por", "mi", "te", "es", "lo", "pero", "como", "para"],
		"fra-eng": ["le", "les", "des", "je", "il", "est", "pas", "une", "et", "mon", "ma", "tu", "dans", "pour"],
		"ita-eng": ["il", "che", "di", "per", "non", "ti", "sei", "sono", "con", "ma", "una", "della"],
		"por-eng": ["o", "não", "um", "uma", "você", "eu", "em", "com", "mas", "para", "meu"],
		"nld-eng": ["het", "een", "ik", "je", "niet", "van", "dat", "en", "maar", "voor"],
		"eng-fra": ["the", "and", "you", "i", "to", "my", "me", "it", "is", "in", "of", "that"],
	}
	var best_n := 0
	for pair in stop:
		var n := 0
		for i in mini(lines.size(), 30):
			for w in _words(lines[i][1]):
				if stop[pair].has(String(w).to_lower()): n += 1
		if n > best_n:
			best_n = n
			dict_pair = pair


func _nk(w: String) -> String:
	var o := w.strip_edges().to_lower()
	for pr in [["á", "a"], ["à", "a"], ["â", "a"], ["ä", "a"], ["ã", "a"], ["é", "e"], ["è", "e"], ["ê", "e"], ["ë", "e"], ["í", "i"], ["î", "i"], ["ï", "i"], ["ó", "o"], ["ô", "o"], ["ö", "o"], ["õ", "o"], ["ú", "u"], ["ù", "u"], ["û", "u"], ["ü", "u"], ["ç", "c"], ["ñ", "n"]]:
		o = o.replace(pr[0], pr[1])
	return o


func _gloss(w: String, line: int) -> String:
	var key := _nk(w)
	var cands := [line]
	for k in tr_lines: cands.append(k)
	for k in cands:
		if not tr_lines.has(k): continue
		for g in tr_lines[k].get("words", []):
			if _nk(str(g.get("w", ""))) == key and str(g.get("sens", "")) != "": return str(g["sens"])
	return _dict_gloss(key)


func _dict_gloss(key: String) -> String:
	if dict_pair == "" or key.length() < 2: return ""
	if not dict_cache.has(dict_pair):
		var path := "res://dicts/%s.tsv" % dict_pair
		dict_cache[dict_pair] = FileAccess.get_file_as_string(path).split("\n", false) if FileAccess.file_exists(path) else PackedStringArray()
	var d: PackedStringArray = dict_cache[dict_pair]
	var lo := 0
	var hi := d.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if d[mid].get_slice("\t", 0) < key: lo = mid + 1
		else: hi = mid
	if lo >= d.size() or d[lo].get_slice("\t", 0) != key: return ""
	var df := d[lo].get_slice("\t", 2).replace("¶", " ; ")
	var out := []
	for part in df.split(";", false):
		var x := part.strip_edges()
		if x.begins_with("("): x = x.substr(x.find(")") + 1).strip_edges()
		if x != "" and not x in out: out.append(x)
		if out.size() >= 3: break
	return ", ".join(out)
