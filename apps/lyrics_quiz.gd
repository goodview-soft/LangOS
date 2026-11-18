extends Control
## Jeu des paroles : la musique joue sans s'arrêter ; la question apparaît quelques secondes avant le mot
## (ou la phrase) chanté et il faut répondre avant le chanteur. Karaoké, combos, effets, records, bilan.
## Source : paroles synchronisées (.lrc) de la bibliothèque Music. Timing des mots interpolé dans la ligne.

const LIB_PATH := "user://library.json"
const MUSIC_DIR := "user://music"
const SAVE_PATH := "user://lyricsgame.json"
const BUS := "LGame"
const GOLD := Color("ffd877")
const MUTED := Color("9aa0c6")

const MODES := [
	{"n": "Mot manquant", "d": "Un mot caché par phrase, tiré au hasard", "i": "Aa"},
	{"n": "Suite des paroles", "d": "Quelle phrase arrive ensuite ?", "i": "♪"},
	{"n": "Mélange", "d": "Les deux types, au hasard", "i": "✦"},
]
const DIFFS := [
	{"n": "Facile", "win": 18.0, "gap": 6.0, "ch": 3, "d": "question 18 s avant · 3 choix"},
	{"n": "Normal", "win": 13.0, "gap": 5.0, "ch": 3, "d": "question 13 s avant · 3 choix"},
	{"n": "Expert", "win": 9.0, "gap": 4.0, "ch": 4, "d": "question 9 s avant · 4 choix"},
]
const MAX_OPEN := 5
const REPLAY_PAD := 0.6    # après une erreur, la phrase est rejouée depuis son début (- 0,6 s)
const INK := "26305f"
const LENS := [0, 12, 24]   # 0 = tout le morceau


# ------------------------------------------------------------------ Fond animé + équaliseur
class Bg extends Control:
	var hue := 0.62
	var sat := 0.6
	var t := 0.0
	var bars := PackedFloat32Array()
	var pulse := 0.0

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var top := Color.from_hsv(hue, sat, 0.30)
		var bot := Color.from_hsv(fposmod(hue + 0.13, 1.0), sat + 0.1, 0.09)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]), PackedColorArray([top, top, bot, bot]))
		for i in 7:
			var a := t * 0.35 + i * 1.7
			var c := Vector2(w * (0.5 + 0.46 * sin(a * 0.7 + i)), h * (0.5 + 0.42 * cos(a * 0.5 + i * 2.0)))
			var r := minf(w, h) * (0.16 + 0.07 * sin(t * 1.2 + i) + 0.05 * pulse)
			draw_circle(c, r, Color.from_hsv(fposmod(hue + i * 0.06, 1.0), 0.6, 1.0, 0.06))
		var n := bars.size()
		if n > 0:
			var bw := w / float(n)
			for i in n:
				var bh := (h * 0.28) * clampf(bars[i], 0.0, 1.0)
				var col := Color.from_hsv(fposmod(hue + float(i) / n * 0.25, 1.0), 0.55, 1.0, 0.16)
				draw_rect(Rect2(i * bw + 2, h - bh, bw - 4, bh), col)


# ------------------------------------------------------------------ Frise audio (style Audacity)
class Tl extends Control:
	signal seek_req(t: float)
	var dur := 1.0
	var pos := 0.0
	var wave := PackedFloat32Array()
	var binw := 0.25
	var phrases := PackedFloat32Array()
	var marks: Array = []
	var hover := -1.0

	func _t_at(x: float) -> float:
		return clampf(x / maxf(1.0, size.x) * dur, 0.0, dur)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			seek_req.emit(_t_at(ev.position.x))
		elif ev is InputEventMouseMotion:
			hover = _t_at(ev.position.x)
			queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			hover = -1.0
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var f := ThemeDB.fallback_font
		draw_rect(Rect2(0, 0, w, h), Color("1b1d22"))
		draw_rect(Rect2(0, 0, w, 20), Color("2a2d34"))
		var step := 10.0 if dur < 240.0 else 30.0
		var tt := 0.0
		while tt <= dur:
			var x := tt / dur * w
			draw_line(Vector2(x, 12), Vector2(x, 20), Color("6b7080"), 1.0)
			draw_string(f, Vector2(x + 3, 11), "%d:%02d" % [int(tt) / 60, int(tt) % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("9aa0b4"))
			tt += step
		var strip := 14.0
		var top := 24.0
		var mid := top + (h - top - strip) * 0.5
		var amp := (h - top - strip) * 0.5 - 2.0
		draw_line(Vector2(0, mid), Vector2(w, mid), Color("3a4a6a"), 1.0)
		var xx := 0
		while xx < int(w):
			var bi := int(float(xx) / w * dur / binw)
			var v := wave[bi] if bi < wave.size() else 0.0
			if v > 0.01:
				draw_line(Vector2(xx, mid - v * amp - 1), Vector2(xx, mid + v * amp + 1), Color("5b8def") if float(xx) / w * dur <= pos else Color("3f5f9e"), 2.0)
			xx += 2
		for i in phrases.size():
			var x0 := phrases[i] / dur * w
			var x1 := (phrases[i + 1] / dur * w) if i + 1 < phrases.size() else w
			draw_rect(Rect2(x0, h - strip, maxf(1.0, x1 - x0 - 1), strip), Color("2f3a52") if i % 2 == 0 else Color("3a4766"))
		for m in marks:
			var mx: float = float(m[0]) / dur * w
			draw_colored_polygon(PackedVector2Array([Vector2(mx - 4, top), Vector2(mx + 4, top), Vector2(mx, top + 8)]), m[1])
		if hover >= 0.0:
			draw_line(Vector2(hover / dur * w, top), Vector2(hover / dur * w, h), Color(1, 1, 1, 0.25), 1.0)
		var px := pos / dur * w
		draw_line(Vector2(px, 0), Vector2(px, h), Color("ff4d4d"), 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(px - 6, 0), Vector2(px + 6, 0), Vector2(px, 9)]), Color("ff4d4d"))


# ------------------------------------------------------------------ Page de cahier
class Paper extends Control:
	var side := 0
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("f6efdc")
		sb.corner_radius_top_left = 14 if side == 0 else 2
		sb.corner_radius_bottom_left = 14 if side == 0 else 2
		sb.corner_radius_top_right = 14 if side == 1 else 2
		sb.corner_radius_bottom_right = 14 if side == 1 else 2
		sb.shadow_color = Color(0, 0, 0, 0.35); sb.shadow_size = 12
		draw_style_box(sb, Rect2(0, 0, w, h))
		var y := 74.0
		while y < h - 16.0:
			draw_line(Vector2(14, y), Vector2(w - 14, y), Color(0.4, 0.52, 0.82, 0.30), 1.5)
			y += 38.0
		if side == 0: draw_line(Vector2(48, 0), Vector2(48, h), Color(0.85, 0.3, 0.3, 0.5), 2.0)
		var x := w - 7.0 if side == 0 else 7.0
		var yy := 34.0
		while yy < h - 10.0:
			draw_circle(Vector2(x, yy), 8.0, Color(0.14, 0.15, 0.2))
			draw_circle(Vector2(x, yy), 4.5, Color(0.72, 0.74, 0.8))
			yy += 58.0


# ------------------------------------------------------------------ Effets (particules, scores flottants, flash)
class Fx extends Control:
	var parts: Array = []
	var pops: Array = []
	var flash := Color(0, 0, 0, 0)

	func burst(p: Vector2, col: Color, n := 36) -> void:
		for i in n:
			var a := randf() * TAU
			var v := randf_range(120.0, 420.0)
			parts.append({"p": p, "v": Vector2(cos(a), sin(a)) * v, "life": randf_range(0.5, 1.0), "col": col.lightened(randf() * 0.4), "s": randf_range(3.0, 7.0)})

	func pop(text: String, p: Vector2, col: Color, big := 34) -> void:
		pops.append({"t": text, "p": p, "life": 1.1, "col": col, "s": big})

	func _process(d: float) -> void:
		for q in parts:
			q.p += q.v * d
			q.v = q.v * 0.94 + Vector2(0, 260) * d
			q.life -= d
		parts = parts.filter(func(q): return q.life > 0.0)
		for q in pops:
			q.p.y -= 46.0 * d
			q.life -= d
		pops = pops.filter(func(q): return q.life > 0.0)
		flash.a = maxf(0.0, flash.a - d * 1.8)
		queue_redraw()

	func _draw() -> void:
		if flash.a > 0.0: draw_rect(Rect2(Vector2.ZERO, size), flash)
		for q in parts:
			draw_circle(q.p, q.s * clampf(q.life * 1.6, 0.0, 1.0), Color(q.col, clampf(q.life * 1.5, 0.0, 1.0)))
		var f := ThemeDB.fallback_font
		for q in pops:
			var a := clampf(q.life * 1.8, 0.0, 1.0)
			var sz: int = q.s
			var w := f.get_string_size(q.t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
			draw_string_outline(f, q.p - Vector2(w * 0.5, 0), q.t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 6, Color(0, 0, 0, a * 0.7))
			draw_string(f, q.p - Vector2(w * 0.5, 0), q.t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(q.col, a))


# ------------------------------------------------------------------ État
var bg: Bg
var fx: Fx
var content: MarginContainer
var home: Control
var game: Control
var results: Control
var player: AudioStreamPlayer
var spec: AudioEffectInstance
var sfx := {}
var sfx_player: AudioStreamPlayer

var lib: Array = []
var save := {}
var sel_track := {}
var sel_mode := 2
var sel_diff := 1
var sel_len := 0

# accueil
var carousel: HBoxContainer
var mode_btns: Array = []
var diff_btns: Array = []
var len_btns: Array = []
var home_msg: Label
var play_btn: Button

# jeu
var g_song: Label
var g_score: Label
var g_combo: Label
var g_prog: ProgressBar
var g_lyrics: RichTextLabel
var g_sel_head: RichTextLabel
var g_sel_bar: ProgressBar
var g_cbtns: Array = []
var g_wait: Label
var sel_q := {}
var tr_lines := {}        # traductions du cache de Music : ligne -> {tr, words}
var dict_cache := {}
var dict_pair := ""
var mast_cur := {"b": {}, "n": 0}
var lp: AudioEffectLowPassFilter
var se: AudioEffectStereoEnhance
var mix_t := 0.4
var tip: PanelContainer
var tip_lbl: RichTextLabel
var _last_txt := ""
var view_shift := 0
var view_idle := 0.0
var tl: Tl
var loop_on := true
var paused := false
var btn_play: Button
var btn_loop: Button
var g_time_lbl: Label
var wave := PackedFloat32Array()
var wave_cache := {}
var dur_a := 1.0
var free_t0 := -1.0
var free_t1 := -1.0
var inst_player: AudioStreamPlayer
var inst_ready := false
var inst_thread: Thread
var inst_out := ""
var reverb: AudioEffectReverb
var reveal_until := -1.0
var inst_state := 0   # 0 aucun, 1 en cours, 2 prêt, 3 indisponible
var g_hint: Label
var g_count: Label
var g_prog_lbl: Label

# partie
var lines: Array = []
var offset := 0.0
var song := ""
var stream: AudioStream
var qs: Array = []
var qi := -1
var cur := {}
var active: Array = []
var sel_lock := 0.0
var nxt := 0
var done_n := 0
var end_wait := -1.0
var phase := 3            # 0 attente, 1 question ouverte, 2 résolue, 3 hors jeu
var starting := false
var appear_at := 0.0
var stop_at := 0.0
var resolve_end := 0.0
var window_s := 7.0
var n_choices := 3
var score := 0
var streak := 0
var best_streak := 0
var glog: Array = []
var hue := 0.62
var t_anim := 0.0
var shake := 0.0
var rev_col := ""
var shown_score := 0.0
var _bar_vals := PackedFloat32Array()


func _ready() -> void:
	clip_contents = true
	_load_save()
	_make_audio()
	bg = Bg.new(); bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(bg)
	content = MarginContainer.new(); content.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]: content.add_theme_constant_override("margin_" + k, 26)
	add_child(content)
	var stack := Control.new(); stack.size_flags_horizontal = SIZE_EXPAND_FILL; stack.size_flags_vertical = SIZE_EXPAND_FILL; content.add_child(stack)
	home = _build_home(); game = _build_game(); results = _build_results()
	for s in [home, game, results]:
		s.set_anchors_preset(Control.PRESET_FULL_RECT); stack.add_child(s)
	fx = Fx.new(); fx.set_anchors_preset(Control.PRESET_FULL_RECT); fx.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(fx)
	tip = PanelContainer.new()
	var tsb2 := StyleBoxFlat.new()
	tsb2.bg_color = Color("1b1d22"); tsb2.set_corner_radius_all(10)
	tsb2.border_color = GOLD; tsb2.set_border_width_all(2)
	tsb2.content_margin_left = 12; tsb2.content_margin_right = 12; tsb2.content_margin_top = 8; tsb2.content_margin_bottom = 8
	tip.add_theme_stylebox_override("panel", tsb2)
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	tip.custom_minimum_size = Vector2(240, 0)
	tip_lbl = RichTextLabel.new()
	tip_lbl.bbcode_enabled = true; tip_lbl.fit_content = true; tip_lbl.scroll_active = false
	tip_lbl.custom_minimum_size = Vector2(240, 0)
	tip_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_lbl.add_theme_font_size_override("normal_font_size", 17)
	tip_lbl.add_theme_font_size_override("bold_font_size", 17)
	tip.add_child(tip_lbl)
	add_child(tip)
	_bar_vals.resize(28)
	bg.bars = _bar_vals
	_home_open()


func _exit_tree() -> void:
	var i := AudioServer.get_bus_index(BUS)
	if i >= 0: AudioServer.remove_bus(i)


# ------------------------------------------------------------------ Audio / sons
func _make_audio() -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.add_bus_effect(i, AudioEffectSpectrumAnalyzer.new())
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.7
		rv.damping = 0.55
		rv.spread = 1.0
		rv.dry = 1.0
		rv.wet = 0.0
		AudioServer.add_bus_effect(i, rv)
		var lpf := AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(i, lpf)
		AudioServer.add_bus_effect(i, AudioEffectStereoEnhance.new())
	var bi := AudioServer.get_bus_index(BUS)
	spec = AudioServer.get_bus_effect_instance(bi, 0)
	reverb = AudioServer.get_bus_effect(bi, 1) as AudioEffectReverb
	lp = AudioServer.get_bus_effect(bi, 2) as AudioEffectLowPassFilter
	se = AudioServer.get_bus_effect(bi, 3) as AudioEffectStereoEnhance
	player = AudioStreamPlayer.new(); player.bus = BUS; add_child(player)
	sfx_player = AudioStreamPlayer.new(); sfx_player.volume_db = -6.0; add_child(sfx_player)
	inst_player = AudioStreamPlayer.new(); inst_player.bus = BUS; inst_player.volume_db = -60.0; add_child(inst_player)
	sfx["good"] = _tone([660.0, 880.0, 1175.0], 0.07)
	sfx["bad"] = _tone([220.0, 165.0], 0.12)
	sfx["tick"] = _tone([700.0], 0.06)
	sfx["go"] = _tone([880.0, 1320.0], 0.14)
	sfx["end"] = _tone([523.0, 659.0, 784.0, 1047.0], 0.12)


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


func _play_sfx(n: String) -> void:
	sfx_player.stream = sfx[n]
	sfx_player.play()


func _update_bars(d: float) -> void:
	var n := _bar_vals.size()
	for i in n:
		var v := 0.0
		if player.playing and spec != null:
			var lo := 40.0 * pow(1.28, i)
			var hi := lo * 1.28
			var m: float = spec.get_magnitude_for_frequency_range(lo, hi).length()
			v = clampf((linear_to_db(m + 0.00001) + 58.0) / 50.0, 0.0, 1.0)
		_bar_vals[i] = lerpf(_bar_vals[i], v, clampf(d * 12.0, 0.0, 1.0))
	bg.bars = _bar_vals
	bg.pulse = lerpf(bg.pulse, _bar_vals[2] if n > 3 else 0.0, clampf(d * 8.0, 0.0, 1.0))


# ------------------------------------------------------------------ Sauvegarde (records)
func _load_save() -> void:
	save = {"best": {}, "last": {}, "mastery": {}}
	if FileAccess.file_exists(SAVE_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if d is Dictionary: save = d
	if not save.has("best"): save["best"] = {}
	if not save.has("last"): save["last"] = {}
	if not save.has("mastery"): save["mastery"] = {}
	sel_mode = int(save["last"].get("mode", sel_mode))
	sel_diff = int(save["last"].get("diff", sel_diff))
	sel_len = int(save["last"].get("len", sel_len))
	loop_on = bool(save["last"].get("loop", true))


func _write_save() -> void:
	save["last"] = {"loop": loop_on, "mode": sel_mode, "diff": sel_diff, "len": sel_len, "track": sel_track.get("file", "")}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(save))


func _best_key(t: Dictionary) -> String:
	return "%s|%d|%d|%d" % [t.get("file", ""), sel_mode, sel_diff, sel_len]


# ------------------------------------------------------------------ Style
func _card(b: Button, col: Color, border := Color(1, 1, 1, 0.22), bw := 2, radius := 18) -> void:
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.12) if st == "hover" else col
		sb.set_corner_radius_all(radius)
		sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 10; sb.content_margin_bottom = 10
		sb.border_color = border
		sb.set_border_width_all(bw)
		sb.shadow_color = Color(0, 0, 0, 0.35); sb.shadow_size = 6; sb.shadow_offset = Vector2(0, 3)
		if st == "focus":
			sb.draw_center = false
			sb.shadow_size = 0
		b.add_theme_stylebox_override(st, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color.WHITE)


func _lbl(text: String, sz: int, col := Color.WHITE, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	if parent: parent.add_child(l)
	return l


func _section(text: String, parent: Node) -> void:
	_lbl(text, 13, MUTED, parent)


func _track_hue(t: Dictionary) -> float:
	return float(hash(str(t.get("track", "")) + str(t.get("artist", ""))) % 1000) / 1000.0


func _show(which: Control) -> void:
	for s in [home, game, results]:
		s.visible = s == which
	bg.sat = 0.16 if which == game else 0.6
	which.modulate.a = 0.0
	create_tween().tween_property(which, "modulate:a", 1.0, 0.25)


# ------------------------------------------------------------------ Accueil
func _build_home() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var t := _lbl("JEU DES PAROLES", 44, GOLD, v)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := _lbl("Réponds avant que le chanteur arrive au mot", 16, Color("c3c8ea"), v)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_section("MORCEAU", v)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 150)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	carousel = HBoxContainer.new(); carousel.add_theme_constant_override("separation", 12); sc.add_child(carousel)
	var cols := HBoxContainer.new(); cols.add_theme_constant_override("separation", 22); v.add_child(cols)
	var c1 := VBoxContainer.new(); c1.size_flags_horizontal = SIZE_EXPAND_FILL; c1.add_theme_constant_override("separation", 6); cols.add_child(c1)
	_section("MODE", c1)
	for i in MODES.size():
		var b := Button.new()
		b.text = "%s   %s\n%s" % [MODES[i].i, MODES[i].n, MODES[i].d]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func(): sel_mode = i; _refresh_home())
		c1.add_child(b); mode_btns.append(b)
	var c2 := VBoxContainer.new(); c2.size_flags_horizontal = SIZE_EXPAND_FILL; c2.add_theme_constant_override("separation", 6); cols.add_child(c2)
	_section("DIFFICULTÉ", c2)
	for i in DIFFS.size():
		var b := Button.new()
		b.text = "%s   ·   %s" % [DIFFS[i].n, DIFFS[i].d]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func(): sel_diff = i; _refresh_home())
		c2.add_child(b); diff_btns.append(b)
	_section("MANCHES", c2)
	var lr := HBoxContainer.new(); lr.add_theme_constant_override("separation", 8); c2.add_child(lr)
	for i in LENS.size():
		var b := Button.new()
		b.text = "Tout le morceau" if LENS[i] == 0 else "%d phrases" % LENS[i]
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func(): sel_len = i; _refresh_home())
		lr.add_child(b); len_btns.append(b)
	var sp := Control.new(); sp.size_flags_vertical = SIZE_EXPAND_FILL; v.add_child(sp)
	home_msg = _lbl("", 15, Color("ffb3b8"), v)
	home_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	home_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	play_btn = Button.new()
	play_btn.text = "▶   JOUER"
	play_btn.custom_minimum_size = Vector2(0, 70)
	play_btn.add_theme_font_size_override("font_size", 30)
	play_btn.pressed.connect(_play_pressed)
	v.add_child(play_btn)
	return v


func _home_open() -> void:
	phase = 3; starting = false; qi = -1
	player.stop()
	_clear_cards()
	player.pitch_scale = 1.0
	player.volume_db = 0.0
	player.stream_paused = false
	paused = false
	inst_player.stop()
	_reset_mix()
	hue = 0.62
	lib = []
	if FileAccess.file_exists(LIB_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(LIB_PATH))
		if d is Array: lib = d
	var ok := []
	for t in lib:
		if String(t.get("lrc", "")) != "" and FileAccess.file_exists(t.lrc): ok.append(t)
	for c in carousel.get_children(): c.queue_free()
	var want: String = save["last"].get("track", "")
	if sel_track.is_empty() and want != "":
		for t in ok:
			if t.get("file", "") == want: sel_track = t
	if sel_track.is_empty() or not ok.any(func(x): return x.get("file", "") == sel_track.get("file", "")):
		sel_track = ok[0] if not ok.is_empty() else {}
	for t in ok:
		var b := Button.new()
		b.custom_minimum_size = Vector2(210, 130)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 16)
		b.set_meta("t", t)
		b.pressed.connect(func(): sel_track = t; _refresh_home())
		carousel.add_child(b)
	home_msg.text = "" if not ok.is_empty() else "Aucun morceau avec paroles synchronisées.\nOuvre Music, joue un morceau et récupère ses paroles (bouton Paroles)."
	play_btn.disabled = ok.is_empty()
	_show(home)
	_refresh_home()


func _refresh_home() -> void:
	for b in carousel.get_children():
		var t: Dictionary = b.get_meta("t")
		var on: bool = t.get("file", "") == sel_track.get("file", "")
		var rec := int(save["best"].get(_best_key(t), 0))
		b.text = "♫\n%s\n%s\n%s" % [t.get("track", "?"), t.get("artist", ""), ("★ %d" % rec if rec > 0 else "—") + "   ·   Maîtrise %d%%" % _mastery_pct(t)]
		_card(b, Color.from_hsv(_track_hue(t), 0.6, 0.72 if on else 0.36), GOLD if on else Color(1, 1, 1, 0.2), 4 if on else 2)
	for i in mode_btns.size(): _chip(mode_btns[i], i == sel_mode)
	for i in diff_btns.size(): _chip(diff_btns[i], i == sel_diff)
	for i in len_btns.size(): _chip(len_btns[i], i == sel_len)
	_card(play_btn, Color("2e9e5b"), Color(1, 1, 1, 0.35), 2, 22)
	if not sel_track.is_empty(): bg.hue = _track_hue(sel_track)


func _chip(b: Button, on: bool) -> void:
	_card(b, Color("5b6bff") if on else Color(1, 1, 1, 0.08), GOLD if on else Color(1, 1, 1, 0.15), 3 if on else 1, 14)


# ------------------------------------------------------------------ Écran de jeu (cahier à deux pages)
func _page(side: int) -> Control:
	var pg := Control.new()
	pg.size_flags_horizontal = SIZE_EXPAND_FILL
	pg.size_flags_vertical = SIZE_EXPAND_FILL
	pg.custom_minimum_size = Vector2(280, 300)
	var paper := Paper.new()
	paper.side = side
	paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	pg.add_child(paper)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 62 if side == 0 else 34)
	m.add_theme_constant_override("margin_right", 30 if side == 0 else 24)
	m.add_theme_constant_override("margin_top", 18)
	m.add_theme_constant_override("margin_bottom", 16)
	pg.add_child(m)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	m.add_child(inner)
	pg.set_meta("inner", inner)
	return pg


func _ink_label(text: String, sz: int, col := Color(INK)) -> Label:
	return _lbl(text, sz, col)


func _build_game() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 12); v.add_child(top)
	var back := Button.new()
	back.text = "‹ Menu"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_home_open)
	_card(back, Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.2), 1, 12)
	top.add_child(back)
	g_song = _lbl("", 15, MUTED, top)
	g_song.size_flags_horizontal = SIZE_EXPAND_FILL
	g_song.clip_text = true
	g_combo = _lbl("", 22, Color("ff9d4d"), top)
	g_score = _lbl("0", 36, GOLD, top)
	g_prog = ProgressBar.new(); g_prog.show_percentage = false; g_prog.custom_minimum_size = Vector2(0, 6); v.add_child(g_prog)
	_bar_style(g_prog, Color(1, 1, 1, 0.5))
	g_prog_lbl = _lbl("", 13, MUTED, v)
	g_prog_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tb := PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color("2a2d34"); tsb.set_corner_radius_all(6)
	tsb.content_margin_left = 8; tsb.content_margin_right = 8; tsb.content_margin_top = 6; tsb.content_margin_bottom = 6
	tb.add_theme_stylebox_override("panel", tsb)
	v.add_child(tb)
	var tbv := VBoxContainer.new(); tbv.add_theme_constant_override("separation", 6); tb.add_child(tbv)
	var trow := HBoxContainer.new(); trow.add_theme_constant_override("separation", 6); tbv.add_child(trow)
	var b_prev := _tbtn("⏮", "Phrase précédente"); b_prev.pressed.connect(func(): _step_line(-1)); trow.add_child(b_prev)
	btn_play = _tbtn("⏸", "Pause / lecture"); btn_play.pressed.connect(_toggle_pause); trow.add_child(btn_play)
	var b_next := _tbtn("⏭", "Phrase suivante"); b_next.pressed.connect(func(): _step_line(1)); trow.add_child(b_next)
	var b_end := _tbtn("⏹", "Terminer la partie (bilan)"); b_end.pressed.connect(_finish); trow.add_child(b_end)
	btn_loop = _tbtn("⟲  Boucle", "Rejouer la phrase après une erreur (O = oui / 1 = non)"); btn_loop.custom_minimum_size = Vector2(150, 38)
	btn_loop.pressed.connect(func(): loop_on = not loop_on; _refresh_loop_btn(); _write_save())
	trow.add_child(btn_loop)
	_refresh_loop_btn()
	g_time_lbl = _lbl("0:00.0 / 0:00", 14, Color("c3c8ea"), trow)
	g_time_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	g_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tl = Tl.new()
	tl.custom_minimum_size = Vector2(0, 92)
	tl.seek_req.connect(_on_tl_seek)
	tbv.add_child(tl)
	var book := HBoxContainer.new()
	book.add_theme_constant_override("separation", 0)
	book.size_flags_vertical = SIZE_EXPAND_FILL
	v.add_child(book)
	# page de gauche : les paroles, avec les trous cliquables
	var left := _page(0)
	left.size_flags_stretch_ratio = 1.45
	book.add_child(left)
	var li: VBoxContainer = left.get_meta("inner")
	g_lyrics = RichTextLabel.new()
	g_lyrics.bbcode_enabled = true
	g_lyrics.scroll_active = false
	g_lyrics.size_flags_vertical = SIZE_EXPAND_FILL
	g_lyrics.add_theme_font_size_override("normal_font_size", 24)
	g_lyrics.add_theme_font_size_override("bold_font_size", 24)
	g_lyrics.add_theme_font_size_override("italics_font_size", 24)
	g_lyrics.add_theme_constant_override("line_separation", 12)
	g_lyrics.add_theme_color_override("default_color", Color(INK))
	g_lyrics.meta_clicked.connect(_on_meta)
	g_lyrics.gui_input.connect(_on_lyr_input)
	g_lyrics.meta_underlined = false
	g_lyrics.meta_hover_started.connect(_on_hover)
	g_lyrics.meta_hover_ended.connect(func(_m): tip.visible = false)
	li.add_child(g_lyrics)
	g_count = _lbl("", 120, GOLD, g_lyrics)
	g_count.set_anchors_preset(Control.PRESET_FULL_RECT)
	g_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	g_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g_count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	g_count.add_theme_constant_override("outline_size", 12)
	# page de droite : choix pour le trou sélectionné
	var right := _page(1)
	book.add_child(right)
	var ri: VBoxContainer = right.get_meta("inner")
	g_hint = _ink_label("✎  Clique un trou, puis choisis le mot", 15, Color("6b7390"))
	ri.add_child(g_hint)
	g_sel_head = RichTextLabel.new()
	g_sel_head.bbcode_enabled = true
	g_sel_head.fit_content = true
	g_sel_head.scroll_active = false
	g_sel_head.add_theme_font_size_override("normal_font_size", 19)
	g_sel_head.add_theme_font_size_override("bold_font_size", 19)
	g_sel_head.add_theme_color_override("default_color", Color(INK))
	ri.add_child(g_sel_head)
	g_sel_bar = ProgressBar.new(); g_sel_bar.show_percentage = false; g_sel_bar.max_value = 1.0; g_sel_bar.value = 1.0
	g_sel_bar.custom_minimum_size = Vector2(0, 8); ri.add_child(g_sel_bar)
	for i in 4:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 52)
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(func(): _pick(sel_q, i))
		ri.add_child(b); g_cbtns.append(b)
	var sp := Control.new(); sp.size_flags_vertical = SIZE_EXPAND_FILL; ri.add_child(sp)
	g_wait = _ink_label("", 15, Color("6b7390"))
	g_wait.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ri.add_child(g_wait)
	return v


func _tbtn(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(46, 38)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	_card(b, Color("3a3e48"), Color("565b68"), 1, 6)
	return b


func _refresh_loop_btn() -> void:
	btn_loop.text = "⟲  Boucle : %s" % ("OUI" if loop_on else "NON")
	_card(btn_loop, Color("2f6fd6") if loop_on else Color("3a3e48"), Color("8fb4ff") if loop_on else Color("565b68"), 1, 6)


func _line_at(t_audio: float) -> int:
	var idx := -1
	for i in lines.size():
		if float(lines[i][0]) - offset <= t_audio: idx = i
		else: break
	return idx


func _box(i: int) -> int:
	return int((mast_cur.get("b", {}) as Dictionary).get(str(i), -1))


func _mastery_pct(t: Dictionary) -> int:
	var m: Dictionary = save["mastery"].get(String(t.get("file", "")), {})
	var n := int(m.get("n", 0))
	if n <= 0: return 0
	var k := 0
	for key in m.get("b", {}):
		if int(m["b"][key]) >= 2: k += 1
	return int(100.0 * float(k) / float(n))


func _toggle_pause() -> void:
	paused = not paused
	player.stream_paused = paused
	btn_play.text = "▶" if paused else "⏸"


func _step_line(dir: int) -> void:
	var p := player.get_playback_position()
	var idx := _line_at(p)
	if dir < 0:
		if idx < 0 or p - (float(lines[idx][0]) - offset) <= 1.5: idx -= 1
	else:
		idx += 1
	_play_line(clampi(idx, 0, lines.size() - 1))


## Écoute libre d'une phrase : le mot caché y est audible (on s'entraîne, sans points).
func _play_line(i: int, from_t := -1.0) -> void:
	var st := float(lines[i][0]) - offset
	var en := (float(lines[i + 1][0]) - offset) if i + 1 < lines.size() else st + 4.0
	free_t0 = st - 0.1
	free_t1 = en
	if paused: _toggle_pause()
	_seek_to(maxf(0.0, (from_t if from_t >= 0.0 else st) - 0.1))


func _on_tl_seek(t: float) -> void:
	var li := _line_at(t)
	if li >= 0: _play_line(li, t)
	else: _seek_to(t)


func _seek_to(t: float) -> void:
	player.seek(clampf(t, 0.0, maxf(0.0, dur_a - 0.2)))
	for q in active: q.state = 0   # les trous sautés restent disponibles plus tard
	active = []
	sel_q = {}
	for q in qs: q.past = false
	_auto_select_or_clear()


func _rec_wave(p: float) -> void:
	var bi := int(p / 0.25)
	if bi < 0 or bi >= wave.size() or _bar_vals.size() < 20: return
	var lv := 0.0
	for i in 20: lv += _bar_vals[i]
	lv = clampf(lv / 20.0 * 1.6, 0.0, 1.0)
	if wave[bi] < lv: wave[bi] = lv


func _update_tl(p: float) -> void:
	tl.pos = p
	var m := []
	for q in qs:
		m.append([float(q.stop), Color("5ad07a") if (q.state == 2 and q.ok) else (Color("ff6b6b") if q.state == 2 else (Color("ffd877") if q.state == 1 else Color("8a8fa8")))])
	tl.marks = m
	tl.queue_redraw()
	g_time_lbl.text = "%d:%02d.%d  /  %d:%02d" % [int(p) / 60, int(p) % 60, int(fposmod(p, 1.0) * 10.0), int(dur_a) / 60, int(dur_a) % 60]


func _bar_style(p: ProgressBar, col: Color) -> void:
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(0.5, 0.5, 0.6, 0.25)
	bgs.set_corner_radius_all(8)
	var fl := StyleBoxFlat.new()
	fl.bg_color = col
	fl.set_corner_radius_all(8)
	p.add_theme_stylebox_override("background", bgs)
	p.add_theme_stylebox_override("fill", fl)


## Bouton « papier » : idle / picked / wrong / good / dim
func _paper_btn(b: Button, st: String) -> void:
	var bgc := Color("fff9e6"); var bc := Color(INK); var bw := 2; var fc := Color(INK)
	match st:
		"picked": bgc = Color("ffe27a"); bc = Color("c0392b"); bw = 4
		"wrong": bgc = Color("f4c2c2"); bc = Color("c62828"); bw = 3; fc = Color("7a1f1f")
		"good": bgc = Color("c8f0d0"); bc = Color("2e7d32"); bw = 4; fc = Color("14501a")
		"dim": bgc = Color("ece6d3"); bc = Color("b9b29a"); bw = 1; fc = Color("8d8a7e")
	for stn in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bgc.lightened(0.1) if stn == "hover" and st == "idle" else bgc
		sb.set_corner_radius_all(12)
		sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 8; sb.content_margin_bottom = 8
		sb.border_color = bc
		sb.set_border_width_all(bw)
		if stn == "focus": sb.draw_center = false
		b.add_theme_stylebox_override(stn, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		b.add_theme_color_override(c, fc)


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_SPACE and game.is_visible_in_tree() and phase == 1:
		_toggle_pause()
		get_viewport().set_input_as_handled()


## 1-4 : répond au trou sélectionné (sinon au premier sans réponse).
func _unhandled_key_input(ev: InputEvent) -> void:
	if not game.is_visible_in_tree() or phase != 1: return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var i: int = ev.keycode - KEY_1
		if i < 0 or i >= n_choices: return
		if sel_q.is_empty() or sel_q.state != 1: _auto_select()
		if not sel_q.is_empty(): _pick(sel_q, i)


# ------------------------------------------------------------------ Génération des questions
func _words(s: String) -> Array:
	var out := []
	for w in s.split(" ", false):
		out.append(w.strip_edges().lstrip("¿¡\"'(").rstrip(".,;:!?\"')…"))
	return out


func _build() -> Array:
	var nopt: int = DIFFS[sel_diff].ch
	var want: int = LENS[sel_len] if LENS[sel_len] > 0 else 100000
	var pool := []
	for i in lines.size():
		for w in _words(lines[i][1]):
			if w.length() >= 4 and not pool.has(w.to_lower()): pool.append(w.to_lower())
	var res := []
	var i := 0
	while i < lines.size() - 2 and res.size() < want:   # depuis le début du morceau : une question par phrase
		var kind := sel_mode if sel_mode < 2 else (1 if randf() < 0.2 else 0)
		var q := {}
		if kind == 0:
			q = _make_word_q(i, pool, mini(4, nopt + (1 if _box(i) >= 2 else 0)))   # phrase maîtrisée : un choix de plus
			i += 1
		else:
			q = _make_line_q(i, nopt)
			i += 2
		if not q.is_empty(): res.append(q)
	return res


## Un mot tiré au hasard dans la phrase i.
func _make_word_q(i: int, pool: Array, nopt: int) -> Dictionary:
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
	var tol := 1 if sel_diff == 2 else 3
	while opts.size() < nopt and tries < 300 and not pool.is_empty():
		tries += 1
		var d: String = pool[randi() % pool.size()]
		if opts.has(d): continue
		if absi(d.length() - good.length()) > tol and tries < 150: continue
		opts.append(d)
	if opts.size() < nopt: return {}
	opts.shuffle()
	return {"kind": 0, "line": i, "t_stop": tw, "answer": good.to_lower(), "opts": opts, "k": k, "ws": ws}


## La phrase suivante est cachée : il faut retrouver laquelle.
func _make_line_q(i: int, nopt: int) -> Dictionary:
	if i + 2 >= lines.size() or String(lines[i + 1][1]).length() < 8: return {}
	var good: String = lines[i + 1][1]
	var opts := [good]
	var tries := 0
	while opts.size() < nopt and tries < 200:
		tries += 1
		var d: String = lines[randi() % lines.size()][1]
		if d.length() < 8 or opts.has(d) or d == lines[i][1]: continue
		opts.append(d)
	if opts.size() < nopt: return {}
	opts.shuffle()
	return {"kind": 1, "line": i, "t_stop": float(lines[i + 1][0]) - 0.05, "answer": good, "opts": opts}


# ------------------------------------------------------------------ Déroulement d'une partie
func _play_pressed() -> void:
	if sel_track.is_empty() or starting: return
	if not _load_track(sel_track): return
	_write_save()
	end_wait = -1.0
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


func _clear_cards() -> void:
	active = []
	sel_q = {}
	for b in g_cbtns: b.visible = false
	g_sel_head.text = ""
	g_wait.text = ""


func _start() -> void:
	window_s = float(DIFFS[sel_diff].win)
	n_choices = int(DIFFS[sel_diff].ch)
	qs = _build()
	if qs.size() < 3:
		home_msg.text = "Pas assez de paroles synchronisées pour jouer ce morceau."
		return
	for q in qs:
		q["stop"] = float(q.t_stop) - offset
		q["open_at"] = float(q.stop) - window_s
		q["state"] = 0
		q["pick"] = -1
		q["pick_t"] = 0.0
		q["attempts"] = 0
		q["wrong"] = []
		q["ok"] = false
		if q.kind == 0:
			var dur := clampf(0.085 * String(q.answer).length() + 0.15, 0.3, 1.0)
			q["mute_a"] = float(q.stop) - 0.35
			q["mute_b"] = float(q.stop) + dur + 0.35
		else:
			q["mute_a"] = float(q.stop) - 0.05
			q["mute_b"] = (float(lines[q.line + 2][0]) - offset) if q.line + 2 < lines.size() else float(q.stop) + 4.0
		q["past"] = false
		# la boucle ne repart qu'à la fin de la phrase (le son continue après le mot)
		var end_line: int = q.line + (1 if q.kind == 0 else 2)
		q["loop_at"] = (float(lines[end_line][0]) - offset - 0.05) if end_line < lines.size() else float(q.stop) + 3.0
	player.pitch_scale = 1.0
	player.volume_db = 0.0
	score = 0; shown_score = 0.0; streak = 0; best_streak = 0; glog = []; nxt = 0; done_n = 0; phase = 3
	_clear_cards()
	starting = true
	g_song.text = song; g_score.text = "0"; g_combo.text = ""
	g_prog.max_value = qs.size(); g_prog.value = 0
	g_prog_lbl.text = "%s · %s" % [MODES[sel_mode].n, DIFFS[sel_diff].n]
	g_lyrics.text = ""
	_last_txt = ""
	mix_t = 0.4
	g_hint.text = "✎  Clique un trou, puis choisis le mot"
	paused = false
	reveal_until = -1.0
	player.stream_paused = false
	btn_play.text = "⏸"
	free_t0 = -1.0
	free_t1 = -1.0
	dur_a = maxf(1.0, stream.get_length())
	var wk := String(sel_track.get("file", ""))
	if not wave_cache.has(wk):
		var wv := PackedFloat32Array()
		wv.resize(int(dur_a / 0.25) + 2)
		wave_cache[wk] = wv
	wave = wave_cache[wk]
	tl.dur = dur_a
	tl.wave = wave
	var ph := PackedFloat32Array()
	for i in lines.size(): ph.append(float(lines[i][0]) - offset)
	tl.phrases = ph
	_show(game)
	for n in ["3", "2", "1", "GO !"]:
		if not starting: return
		g_count.text = n
		g_count.pivot_offset = g_count.size / 2.0
		g_count.scale = Vector2(1.6, 1.6)
		g_count.modulate.a = 1.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(g_count, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(g_count, "modulate:a", 0.0, 0.7).set_delay(0.25)
		_play_sfx("go" if n == "GO !" else "tick")
		await get_tree().create_timer(0.75).timeout
	if not starting: return
	starting = false
	g_count.text = ""
	player.play(0.0)   # on commence toujours depuis 0:00
	phase = 1


func _pos_now() -> float:
	return player.get_playback_position() + AudioServer.get_time_since_last_mix()


func _process(d: float) -> void:
	if view_idle > 0.0:
		view_idle -= d
		if view_idle <= 0.0: view_shift = 0
	t_anim += d
	bg.t = t_anim
	bg.queue_redraw()
	_update_bars(d)
	if shake > 0.0:
		shake = maxf(0.0, shake - d * 3.0)
		content.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 9.0
	elif content.position != Vector2.ZERO:
		content.position = Vector2.ZERO
	if absf(shown_score - score) > 0.5:
		shown_score = lerpf(shown_score, score, clampf(d * 9.0, 0.0, 1.0))
		g_score.text = str(int(round(shown_score)))
	elif g_score.text != str(score) and game.visible:
		g_score.text = str(score)
	if phase != 1: return
	if paused:
		var pp := player.get_playback_position()
		_update_tl(pp)
		_render(pp + offset)
		return
	if not player.playing:
		var pend := _first_pending()
		if not pend.is_empty():
			_replay_from(pend)   # fin du morceau : on reboucle sur les trous qu'il reste
			return
		_finish()
		return
	var p := _pos_now()
	_rec_wave(p)
	# le mix réagit à ta série : étouffé au départ, il s'ouvre (aigus + largeur stéréo) quand tu enchaînes
	var tgt := 0.4 + 0.6 * clampf(float(streak) / 6.0, 0.0, 1.0)
	mix_t = lerpf(mix_t, tgt, clampf(d * (6.0 if tgt < mix_t else 1.5), 0.0, 1.0))
	if lp != null: lp.cutoff_hz = 2500.0 * pow(8.0, mix_t)
	if se != null: se.surround = 0.6 * clampf((mix_t - 0.4) / 0.6, 0.0, 1.0)
	var want_db := 0.0
	for q in qs:
		if q.state != 2 and p >= float(q.mute_a) and p <= float(q.mute_b): want_db = -60.0; break
	if free_t1 > 0.0 and p >= free_t0 and p <= free_t1: want_db = 0.0   # écoute libre d'une phrase
	var hole := want_db < 0.0
	var gain := 1.0 if p <= reveal_until else 0.0   # la partie validée ressort très légèrement
	if inst_ready:
		# seule la voix est coupée dans le trou : on bascule sur la version instrumentale
		player.volume_db = move_toward(player.volume_db, -60.0 if hole else gain, 350.0 * d)
		inst_player.volume_db = move_toward(inst_player.volume_db, 0.0 if hole else -60.0, 350.0 * d)
	else:
		player.volume_db = move_toward(player.volume_db, -60.0 if hole else gain, 350.0 * d)   # le mot est coupé : un trou dans le son
	for q in qs:   # ouvre les trous à venir (ceux déjà dépassés restent fermés)
		if active.size() >= MAX_OPEN: break
		if q.state == 0 and p >= float(q.open_at) and p < float(q.stop) - 0.3:
			q.state = 1
			active.append(q)
	g_prog.value = done_n
	g_prog_lbl.text = "Phrases réussies : %d / %d" % [done_n, qs.size()]
	if not active.is_empty() and (sel_q.is_empty() or sel_q.state != 1): _auto_select()
	for q in active.duplicate():
		if p >= float(q.stop):   # le curseur du son est passé : verdict
			if _is_good(q): _resolve_q(q)
			else:
				q.past = true
				if p >= float(q.loop_at):   # fin de la phrase
					if loop_on or q.pick < 0: _retry_q(q)   # sans réponse : on reboucle toujours
					else: _resolve_q(q, true)   # mauvaise réponse sans boucle : on passe à la suite
	if not sel_q.is_empty() and sel_q.state == 1:
		var left := clampf((float(sel_q.stop) - p) / window_s, 0.0, 1.0)
		g_sel_bar.value = left
		_bar_style(g_sel_bar, Color.from_hsv(0.33 * left, 0.7, 0.85))
	_update_wait()
	_update_tl(p)
	_sync_inst()
	if done_n >= qs.size():
		if end_wait < 0.0: end_wait = 1.8
		end_wait -= d
		if end_wait <= 0.0: _finish(); return
	_render(p + offset)


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


func _reset_mix() -> void:
	mix_t = 0.4
	if lp != null: lp.cutoff_hz = 20000.0
	if se != null: se.surround = 0.0


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


func _first_pending() -> Dictionary:
	for q in qs:
		if q.state != 2: return q
	return {}


## Relance la lecture depuis la phrase d'un trou non résolu.
func _replay_from(q: Dictionary) -> void:
	for a in active: a.state = 0
	active = []
	sel_q = {}
	var li: int = q.line
	if q.kind == 0 and int(q.k) <= 1 and li > 0: li -= 1
	paused = false
	player.stream_paused = false
	player.play(maxf(0.0, float(lines[li][0]) - offset - REPLAY_PAD))
	btn_play.text = "⏸"


func _update_wait() -> void:
	var parts := []
	for q in active:
		if q != sel_q: parts.append("%s %s" % ["✔" if q.pick >= 0 else "○", _q_label(q)])
	g_wait.text = "" if parts.is_empty() else "Autres trous ouverts :  " + "   ".join(parts)


func _q_label(q: Dictionary) -> String:
	var w: String = q.ws[q.k] if q.kind == 0 else "phrase"
	return "«%s…»" % w.left(1) if q.kind == 0 else "(phrase)"


## Molette sur le cahier : voir les paroles en avance (bas) ou en arrière (haut) ; retour automatique au direct.
func _on_lyr_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP: view_shift = clampi(view_shift - 1, -60, 60)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: view_shift = clampi(view_shift + 1, -60, 60)
		else: return
		view_idle = 6.0
		g_lyrics.accept_event()


func _on_hover(meta: Variant) -> void:
	var m := str(meta)
	var txt := ""
	if m.begins_with("w:"):
		var parts := m.split(":")
		var li := int(parts[1])
		var ws := _words(lines[li][1])
		var k := int(parts[2])
		if k >= ws.size(): return
		var g := _gloss(String(ws[k]), li)
		txt = "[b]%s[/b]   →   %s" % [ws[k], g if g != "" else "[color=#9aa0b4]pas de traduction[/color]"]
		var lt := str(tr_lines.get(li, {}).get("tr", ""))
		if lt != "": txt += "\n[i][color=#9ec5ff]%s[/color][/i]" % lt.replace("[", "(")
	elif m.begins_with("L"):
		var li2 := int(m.substr(1))
		var lt2 := str(tr_lines.get(li2, {}).get("tr", ""))
		txt = ("[i][color=#9ec5ff]%s[/color][/i]" % lt2.replace("[", "(")) if lt2 != "" else "[color=#9aa0b4]▶ Écouter cette phrase[/color]"
	else:
		return
	tip_lbl.text = txt
	tip.visible = true
	tip.reset_size()
	var pos := get_local_mouse_position() + Vector2(16, 22)
	pos.x = clampf(pos.x, 4.0, maxf(4.0, size.x - tip.size.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, size.y - tip.size.y - 4.0))
	tip.position = pos


func _on_meta(meta: Variant) -> void:
	var m := str(meta)
	if m.begins_with("w:"): return
	if m.begins_with("L"):
		_play_line(int(m.substr(1)))
		return
	var i := int(m)
	if i < 0 or i >= qs.size(): return
	if qs[i].state == 0 and float(qs[i].stop) > _pos_now() + 0.3:   # trou à venir : on répond en avance
		qs[i].state = 1
		active.append(qs[i])
	if qs[i].state == 1: _select(qs[i])


func _auto_select() -> void:
	for q in active:
		if q.state == 1 and q.pick < 0: _select(q); return
	if not active.is_empty(): _select(active[0])


func _select(q: Dictionary) -> void:
	sel_q = q
	g_hint.text = "✎  Choisis la bonne réponse"
	g_sel_head.text = _head_text(q, false)
	g_sel_bar.visible = true
	for i in 4:
		var b: Button = g_cbtns[i]
		b.visible = i < q.opts.size()
		if i < q.opts.size():
			b.text = "%d   %s" % [i + 1, q.opts[i]]
			b.disabled = q.wrong.has(i) or q.state != 1
			b.modulate = Color.WHITE
			_paper_btn(b, "wrong" if q.wrong.has(i) else ("picked" if q.pick == i else "idle"))


func _head_text(q: Dictionary, reveal: bool) -> String:
	var hole := "[bgcolor=#ffd86688][color=#c0392b]  ?  ?  ?  [/color][/bgcolor]"
	if q.kind == 0:
		var ws: Array = q.ws.duplicate()
		ws[q.k] = ("[b][color=#2e7d32]%s[/color][/b]" % ws[q.k]) if reveal else hole
		return "[color=#6b7390]Mot manquant :[/color]  " + " ".join(ws)
	var nxt_l: String = lines[q.line + 1][1]
	return "[color=#6b7390]%s[/color]   →   %s" % [lines[q.line][1], ("[b][color=#2e7d32]%s[/color][/b]" % nxt_l) if reveal else hole]


func _pick(q: Dictionary, i: int) -> void:
	if q.is_empty() or q.state != 1 or q.wrong.has(i): return
	q.pick = i
	q.pick_t = _pos_now()
	_select(q)
	if q.past and _is_good(q):
		_resolve_q(q)   # trouvé avant la fin de la phrase
		return
	# passe au trou suivant sans réponse
	for o in active:
		if o != q and o.state == 1 and o.pick < 0:
			get_tree().create_timer(0.45).timeout.connect(func(): if sel_q == q and q.state == 1 and phase == 1: _select(o))
			break


func _is_good(q: Dictionary) -> bool:
	return q.pick >= 0 and String(q.opts[q.pick]).to_lower() == String(q.answer).to_lower()


## Réponse validée : au lieu d'un bip, la partie trouvée revient bien en avant, avec de la reverb.
func _validate_fx(q: Dictionary) -> void:
	reveal_until = float(q.mute_b) + 0.3
	if reverb == null: return
	reverb.wet = 0.2
	create_tween().tween_property(reverb, "wet", 0.0, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _mult() -> int:
	return clampi(1 + streak / 3, 1, 4)


func _fx_pos() -> Vector2:
	return g_lyrics.global_position - global_position + Vector2(g_lyrics.size.x * 0.5, g_lyrics.size.y * 0.45)


## Verdict d'une question quand le son a dépassé le mot. Erreur = scratch + on rejoue la phrase.
func _resolve_q(q: Dictionary, final := false) -> void:
	if q.state != 1: return
	var ok: bool = q.pick >= 0 and String(q.opts[q.pick]).to_lower() == String(q.answer).to_lower()
	if not ok and not final:
		_retry_q(q)
		return
	q.state = 2
	q.ok = ok
	done_n += 1
	active.erase(q)
	var left := clampf((float(q.stop) - float(q.pick_t)) / window_s, 0.0, 1.0) if q.pick >= 0 else 0.0
	var gp := _fx_pos()
	if ok:
		var pts := int((100.0 * (0.4 + 0.6 * left)) * _mult())
		pts = int(float(pts) / float(1 + q.attempts))   # chaque reprise divise le gain
		score += pts
		streak += 1
		best_streak = maxi(best_streak, streak)
		var label := "ENFIN !" if q.attempts > 0 else ("EN AVANCE" if left > 0.6 else ("BIEN" if left > 0.3 else "OK"))
		fx.burst(gp, GOLD, 40 if left > 0.6 else 24)
		fx.pop("%s  +%d" % [label, pts], gp, GOLD if left > 0.6 else Color("8be9a8"))
		_validate_fx(q)
	else:
		streak = 0
	glog.append({"ok": ok, "left": left, "answer": q.answer, "kind": q.kind, "line": q.line, "tries": q.attempts})
	g_combo.text = ("×%d  🔥" % _mult()) if streak >= 3 else ""
	if sel_q == q:
		g_sel_head.text = _head_text(q, true)
		for k in mini(g_cbtns.size(), q.opts.size()):
			var b: Button = g_cbtns[k]
			b.disabled = true
			b.modulate = Color.WHITE
			_paper_btn(b, "good" if String(q.opts[k]).to_lower() == String(q.answer).to_lower() else ("wrong" if k == q.pick else "dim"))
		get_tree().create_timer(1.1).timeout.connect(func(): if sel_q == q: sel_q = {}; _auto_select_or_clear())


func _auto_select_or_clear() -> void:
	if not active.is_empty(): _auto_select()
	else:
		for b in g_cbtns: b.visible = false
		g_sel_head.text = ""
		g_hint.text = "✎  Écoute… le prochain trou arrive"


## Erreur ou pas de réponse : pas de scratch, on boucle la phrase tant que la bonne réponse n'est pas donnée.
func _retry_q(q: Dictionary) -> void:
	var gp := _fx_pos()
	if q.pick >= 0:
		q.attempts += 1
		q.wrong.append(q.pick)
		streak = 0
		g_combo.text = ""
		shake = 0.6
		fx.flash = Color(1, 0.15, 0.2, 0.22)
		fx.pop("Raté — on la rejoue", gp, Color("c62828"))
		_play_sfx("bad")
	else:
		fx.pop("↻  On boucle", gp, Color("6b7390"), 26)
	q.pick = -1
	q.pick_t = 0.0
	_select(q)
	q.past = false
	var li: int = q.line
	if q.kind == 0 and int(q.k) <= 1 and li > 0: li -= 1   # mot proche du début : on remonte d'une phrase pour tout entendre
	var back := float(lines[li][0]) - offset - REPLAY_PAD
	player.seek(maxf(0.0, back))


# ------------------------------------------------------------------ Page de gauche : paroles avec trous cliquables
func _qs_for(i: int, kind: int) -> int:
	for qi_ in qs.size():
		var q: Dictionary = qs[qi_]
		if q.kind == 0 and kind == 0 and q.line == i: return qi_
		if q.kind == 1 and kind == 1 and q.line + 1 == i: return qi_
	return -1


func _hole_bb(qi_: int, txt: String) -> String:
	var q: Dictionary = qs[qi_]
	if q.state == 2:
		var col := "2e7d32" if q.ok else "c62828"
		return "[b][color=#%s]%s[/color][/b]" % [col, txt]
	if q.state == 0:
		if q.pick >= 0: return "[url=%d][bgcolor=#9ec5ff44][color=#1d4ed8][i] %s [/i][/color][/bgcolor][/url]" % [qi_, String(q.opts[q.pick]).left(40)]
		return "[url=%d][bgcolor=#ffffff33][color=#6b7390]  ✎  ?  [/color][/bgcolor][/url]" % qi_
	var shown := "  ✎  ?  "
	var bgc := "ffd86655"
	if q.pick >= 0:
		shown = " " + String(q.opts[q.pick]).left(40) + " "
		bgc = "9ec5ff66"
	if q == sel_q: bgc = "ffb347aa"
	return "[url=%d][bgcolor=#%s][color=#%s][i]%s[/i][/color][/bgcolor][/url]" % [qi_, bgc, "1d4ed8" if q.pick >= 0 else "c0392b", shown]


func _line_bb(i: int, p: float, idx: int) -> String:
	var bx := _box(i)
	var icon := "[color=#2e7d32]★[/color]" if bx >= 2 else ("[color=#c0392b]↺[/color]" if bx == 0 else "[color=#8d93b5]▶[/color]")
	return "[url=L%d]%s[/url] " % [i, icon] + _line_bb_core(i, p, idx)


func _wk(i: int, k: int, inner: String) -> String:
	return "[url=w:%d:%d]%s[/url]" % [i, k, inner]


func _line_bb_core(i: int, p: float, idx: int) -> String:
	var txt: String = lines[i][1]
	var k1 := _qs_for(i, 1)
	if k1 >= 0: return _hole_bb(k1, txt)
	var k0 := _qs_for(i, 0)
	var hole_k: int = int(qs[k0].k) if k0 >= 0 else -1
	var ws := _words(txt)
	var t0: float = lines[i][0]
	var nxt_t: float = lines[i + 1][0] if i + 1 < lines.size() else t0 + 4.0
	var span := minf(nxt_t - t0, 6.0)
	var total := maxi(1, txt.length())
	var before := 0
	var out := ""
	for k in ws.size():
		var wst := t0 + span * float(before) / float(total) * 0.95
		before += ws[k].length() + 1
		var w: String = String(ws[k]).replace("[", "(").replace("]", ")")
		if k == hole_k:
			out += _hole_bb(k0, w) + " "
		elif i < idx: out += _wk(i, k, "[color=#%s]%s[/color]" % [INK, w]) + " "
		elif i == idx: out += _wk(i, k, ("[bgcolor=#ffe27a99][color=#%s]%s[/color][/bgcolor]" % [INK, w]) if p >= wst else "[color=#6b7390]%s[/color]" % w) + " "
		else: out += _wk(i, k, "[color=#9aa0b4]%s[/color]" % w) + " "
	return out


func _render(p: float) -> void:
	var idx := -1
	for i in lines.size():
		if float(lines[i][0]) <= p: idx = i
		else: break
	hue = fposmod(0.55 + float(maxi(idx, 0)) * 0.03, 1.0)
	bg.hue = hue
	var vi := maxi(idx, 0) + view_shift
	var first := clampi(vi - 1, 0, maxi(0, lines.size() - 1))
	var last := mini(lines.size() - 1, first + 6)
	var txt := ""
	if idx < 0: txt += "[color=#9aa0b4]♪  ♪  ♪[/color]\n"
	for i in range(first, last + 1):
		if String(lines[i][1]).strip_edges() == "": continue
		txt += _line_bb(i, p, idx) + "\n"
	if txt != _last_txt:
		_last_txt = txt
		g_lyrics.text = txt


# ------------------------------------------------------------------ Bilan
func _build_results() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var t := _lbl("TERMINÉ", 20, MUTED, v)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gr := _lbl("S", 110, GOLD, v)
	gr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gr.name = "grade"
	var sc := _lbl("0", 44, Color.WHITE, v)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sc.name = "rscore"
	var rec := _lbl("", 18, Color("ff9d4d"), v)
	rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rec.name = "rrec"
	var st := _lbl("", 17, Color("c3c8ea"), v)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.name = "rstats"
	var miss := RichTextLabel.new()
	miss.bbcode_enabled = true
	miss.size_flags_vertical = SIZE_EXPAND_FILL
	miss.name = "rmiss"
	miss.add_theme_font_size_override("normal_font_size", 16)
	v.add_child(miss)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 14); v.add_child(row)
	var a := Button.new()
	a.text = "↺   Rejouer"
	a.size_flags_horizontal = SIZE_EXPAND_FILL
	a.custom_minimum_size = Vector2(0, 60)
	a.add_theme_font_size_override("font_size", 22)
	a.pressed.connect(_play_pressed)
	_card(a, Color("2e9e5b"))
	row.add_child(a)
	var b := Button.new()
	b.text = "Menu"
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 60)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(_home_open)
	_card(b, Color(1, 1, 1, 0.12))
	row.add_child(b)
	return v


func _finish() -> void:
	if phase == 3: return
	player.stop()
	phase = 3
	_clear_cards()
	player.pitch_scale = 1.0
	player.volume_db = 0.0
	player.stream_paused = false
	paused = false
	inst_player.stop()
	_reset_mix()
	starting = false
	var n := glog.size()
	var good := 0
	var tsum := 0.0
	var missed: Array = []
	for e in glog:
		if e.ok and int(e.tries) == 0:
			good += 1
			tsum += 1.0 - float(e.left)
		else:
			missed.append(e)
	var mb: Dictionary = mast_cur.get("b", {})
	for e in glog:
		var key := str(e.line)
		mb[key] = mini(3, int(mb.get(key, 0)) + 1) if (e.ok and int(e.tries) == 0) else 0   # réussi du premier coup : +1, raté : retour à 0
	mast_cur = {"b": mb, "n": lines.size()}
	save["mastery"][String(sel_track.get("file", ""))] = mast_cur
	_write_save()
	var acc := float(good) / float(maxi(1, n))
	var grade := "S" if acc >= 0.9 else ("A" if acc >= 0.75 else ("B" if acc >= 0.55 else ("C" if acc >= 0.35 else "D")))
	var key := _best_key(sel_track)
	var prev := int(save["best"].get(key, 0))
	var is_rec := score > prev
	if is_rec: save["best"][key] = score
	_write_save()
	hue = 0.4 if acc >= 0.55 else 0.0
	bg.hue = hue
	(results.get_node("grade") as Label).text = grade
	(results.get_node("rscore") as Label).text = "%d pts" % score
	(results.get_node("rrec") as Label).text = "★ NOUVEAU RECORD !" if is_rec and score > 0 else ("Record : %d" % prev)
	var avg := ("%.1f s" % (tsum / float(good) * window_s)) if good > 0 else "—"
	(results.get_node("rstats") as Label).text = "Du premier coup %d%%   ·   Meilleure série ×%d   ·   Réponse moyenne %s" % [int(acc * 100.0), best_streak, avg]
	var rt := ""
	if missed.is_empty():
		rt = "[center][color=#6dffa0]Sans-faute ![/color][/center]"
	else:
		rt = "[color=#9aa0c6]À revoir :[/color]\n"
		for e in missed:
			var l: String = lines[e.line][1] if e.kind == 0 else lines[e.line + 1][1]
			rt += "• [b][color=#ffd877]%s[/color][/b]   [color=#9aa0c6]%s[/color]\n" % [e.answer if e.kind == 0 else "", l]
	(results.get_node("rmiss") as RichTextLabel).text = rt
	_show(results)
	_play_sfx("end")
	if grade in ["S", "A"] or is_rec:
		fx.burst(Vector2(size.x * 0.5, size.y * 0.3), GOLD, 90)
