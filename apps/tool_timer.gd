extends Control
const UI = preload("res://apps/ui.gd")
## Minuteur, chronomètre et pomodoro avec alarme sonore.

var mode := 0                # 0 minuteur, 1 chrono, 2 pomodoro
var running := false
var remain := 300.0          # minuteur / pomodoro (s)
var set_secs := 300.0
var elapsed := 0.0           # chrono
var laps: Array = []
var pomo_work := true
var pomo_count := 0
var big: Label
var info: Label
var start_btn: Button
var presets: HBoxContainer
var laps_lbl: Label
var player: AudioStreamPlayer
var ring := 0.0

static func fmt_time(s: float, cs := false) -> String:
	var t := maxf(s, 0.0)
	var h := int(t) / 3600; var m := (int(t) % 3600) / 60; var sec := int(t) % 60
	var r := "%02d:%02d" % [m, sec] if h == 0 else "%d:%02d:%02d" % [h, m, sec]
	if cs: r += ".%02d" % int((t - floor(t)) * 100)
	return r

func _ready() -> void:
	var vb := VBoxContainer.new(); vb.set_anchors_preset(Control.PRESET_FULL_RECT); vb.add_theme_constant_override("separation", 8); add_child(vb)
	var tabs := HBoxContainer.new(); tabs.add_theme_constant_override("separation", 6); vb.add_child(tabs)
	for i in 3:
		var b := Button.new(); b.text = ["Minuteur", "Chrono", "Pomodoro"][i]; b.custom_minimum_size.y = 48; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE; b.pressed.connect(_set_mode.bind(i)); tabs.add_child(b)
	big = Label.new(); big.add_theme_font_size_override("font_size", 64); big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; big.size_flags_vertical = Control.SIZE_EXPAND_FILL
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; vb.add_child(big)
	info = Label.new(); info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; info.theme_type_variation = "Muted"; vb.add_child(info)
	presets = HBoxContainer.new(); presets.add_theme_constant_override("separation", 6); vb.add_child(presets)
	for m in [1, 5, 10, 15, 30]:
		var b := Button.new(); b.text = "%d min" % m; b.custom_minimum_size.y = 48; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): _set_time(m * 60.0)); presets.add_child(b)
	var adj := HBoxContainer.new(); adj.add_theme_constant_override("separation", 6); vb.add_child(adj); adj.name = "adj"
	for d in [-60, -10, 10, 60]:
		var b := Button.new(); b.text = "%+d s" % d if abs(d) < 60 else "%+d min" % (d / 60); b.custom_minimum_size.y = 48; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): _set_time(maxf(set_secs + d, 5.0))); adj.add_child(b)
	laps_lbl = Label.new(); laps_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vb.add_child(laps_lbl)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); vb.add_child(row)
	start_btn = Button.new(); start_btn.custom_minimum_size.y = 56; start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL; start_btn.pressed.connect(_toggle); row.add_child(start_btn)
	var rb := Button.new(); rb.text = "Remise à zéro"; rb.custom_minimum_size.y = 56; rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL; rb.pressed.connect(_reset); row.add_child(rb)
	var lb := Button.new(); lb.text = "Tour"; lb.name = "lap"; lb.custom_minimum_size = Vector2(80, 56); lb.pressed.connect(func(): if running and mode == 1: laps.append(elapsed); _refresh()); row.add_child(lb)
	player = AudioStreamPlayer.new(); player.stream = _beep(); add_child(player)
	_set_mode(0)

static func _beep() -> AudioStreamWAV:
	var w := AudioStreamWAV.new(); w.format = AudioStreamWAV.FORMAT_16_BITS; w.mix_rate = 22050
	var n := 22050; var d := PackedByteArray(); d.resize(n * 2)
	for i in n:
		var on := (i % 5512) < 3000
		var v := int(sin(i * TAU * 880.0 / 22050.0) * 12000) if on else 0
		d.encode_s16(i * 2, v)
	w.data = d; return w

func _set_mode(m: int) -> void:
	mode = m; running = false; ring = 0.0
	if m == 0: remain = set_secs
	if m == 2: pomo_work = true; remain = 25 * 60.0
	if m == 1: elapsed = 0.0; laps.clear()
	_refresh()

func _set_time(s: float) -> void:
	set_secs = s; if mode == 0 and not running: remain = s
	_refresh()

func _toggle() -> void:
	if ring > 0: ring = 0.0; player.stop(); _reset(); return
	running = not running; _refresh()

func _reset() -> void:
	running = false; ring = 0.0; player.stop()
	if mode == 0: remain = set_secs
	elif mode == 1: elapsed = 0.0; laps.clear()
	else: pomo_work = true; remain = 25 * 60.0; pomo_count = 0
	_refresh()

func _process(dt: float) -> void:
	if not running: return
	if mode == 1: elapsed += dt
	else:
		remain -= dt
		if remain <= 0.0:
			remain = 0.0; running = false; ring = 1.0; player.play()
			if mode == 2:
				pomo_work = not pomo_work
				if not pomo_work: pomo_count += 1
				remain = 25 * 60.0 if pomo_work else (15 if pomo_count % 4 == 0 else 5) * 60.0
	_refresh()

func _refresh() -> void:
	big.text = fmt_time(elapsed, true) if mode == 1 else fmt_time(remain)
	start_btn.text = "Arrêter l'alarme" if ring > 0 else ("Pause" if running else "Démarrer")
	if mode == 0: info.text = "Alarme !" if ring > 0 else "Choisis une durée puis démarre"
	elif mode == 1: info.text = "%d tour(s)" % laps.size()
	else: info.text = ("Travail" if pomo_work else "Pause") + " — %d pomodoro(s) terminé(s)" % pomo_count + ("  (alarme !)" if ring > 0 else "")
	presets.visible = mode == 0
	var ad := find_child("adj", true, false); if ad: ad.visible = mode == 0
	for c in start_btn.get_parent().get_children(): if c.name == "lap": c.visible = mode == 1
	laps_lbl.text = "\n".join(laps.slice(maxi(0, laps.size() - 3)).map(func(l): return fmt_time(l, true))) if mode == 1 else ""
