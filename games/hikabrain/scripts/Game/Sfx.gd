class_name Sfx
## Sons synthétisés à la volée (aucun asset requis).

static var _cache := {}

const PRESETS := {
	# f0, f1, bruit, durée, décroissance, volume
	"swing": [400.0, 150.0, 0.9, 0.14, 18.0, 0.35],
	"hit": [160.0, 60.0, 0.4, 0.2, 14.0, 0.8],
	"hurt": [220.0, 90.0, 0.2, 0.25, 9.0, 0.7],
	"place": [520.0, 300.0, 0.15, 0.08, 35.0, 0.5],
	"break": [300.0, 120.0, 0.8, 0.15, 20.0, 0.6],
	"land": [90.0, 50.0, 0.3, 0.12, 25.0, 0.6],
	"jump": [200.0, 340.0, 0.1, 0.1, 25.0, 0.25],
	"beep": [660.0, 660.0, 0.0, 0.15, 6.0, 0.4],
	"go": [990.0, 990.0, 0.0, 0.3, 4.0, 0.45],
	"score": [523.0, 1046.0, 0.0, 0.5, 3.0, 0.5],
	"death": [300.0, 60.0, 0.2, 0.5, 4.0, 0.6],
}

static func get_stream(sfx_name: String) -> AudioStreamWAV:
	if _cache.has(sfx_name):
		return _cache[sfx_name]
	var p: Array = PRESETS[sfx_name]
	var rate := 22050
	var n := int(rate * float(p[3]))
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var f := lerpf(float(p[0]), float(p[1]), t / float(p[3]))
		phase += TAU * f / rate
		var noise := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.5)
		var s := (sin(phase) * (1.0 - float(p[2])) + lp * float(p[2])) * exp(-t * float(p[4])) * float(p[5])
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	_cache[sfx_name] = w
	return w

## pos == Vector3.INF -> son 2D (UI / joueur local), sinon son positionnel.
static func play(owner: Node, sfx_name: String, pos: Vector3 = Vector3.INF, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if owner == null or not owner.is_inside_tree():
		return
	if pos == Vector3.INF:
		var a := AudioStreamPlayer.new()
		a.stream = get_stream(sfx_name)
		a.pitch_scale = pitch
		a.volume_db = vol_db
		owner.add_child(a)
		a.play()
		a.finished.connect(a.queue_free)
	else:
		var a3 := AudioStreamPlayer3D.new()
		a3.stream = get_stream(sfx_name)
		a3.pitch_scale = pitch
		a3.volume_db = vol_db
		a3.unit_size = 10.0
		a3.max_distance = 70.0
		owner.add_child(a3)
		a3.global_position = pos
		a3.play()
		a3.finished.connect(a3.queue_free)
