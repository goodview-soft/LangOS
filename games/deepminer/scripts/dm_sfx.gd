class_name DMSfx
## Bruitages (statique) : DMSfx.play("pick", pos). Sons CC0 dans games/deepminer/audio/sfx/.
## Les lecteurs sont rattachés à `host` (le nœud racine du jeu : ils disparaissent avec la fenêtre).
## Volume selon la distance à l'écouteur ; un fichier absent est ignoré sans erreur.

const DIR := "res://games/deepminer/audio/sfx/"
const GROUPS := {
	"pick": ["pick1", "pick2", "pick3"], "break": ["break1", "break2"], "step": ["step1", "step2", "step3"],
	"swing": ["swing1", "swing2"], "zombie": ["zg1", "zg2", "zg3"], "zhit": ["zhit"], "hurt": ["hurt"],
	"giant": ["giant"], "splash": ["splash"], "death": ["death"], "pickup": ["pickup"],
}
const MAX_DIST := 28.0
const MAX_VOICES := 24
static var host: Node
static var listener := Vector3.ZERO
static var cache := {}
static var voices := 0
static var last := {}  # nom -> dernière variante (pas deux fois la même de suite)

static func _stream(n: String) -> AudioStream:
	if not cache.has(n):
		var p := DIR + n + ".ogg"
		cache[n] = load(p) if ResourceLoader.exists(p) else null
	return cache[n]

## group : clé de GROUPS ; pos : position monde (null = proche de l'écouteur) ; db : gain ; pitch : variation aléatoire ±.
static func play(group: String, pos: Variant = null, db := 0.0, pitch := 0.08) -> void:
	if host == null or not is_instance_valid(host) or voices >= MAX_VOICES or not GROUPS.has(group):
		return
	var names: Array = GROUPS[group]
	var n: String = names[randi() % names.size()]
	if names.size() > 1 and n == last.get(group, ""):
		n = names[(names.find(n) + 1) % names.size()]
	last[group] = n
	var s := _stream(n)
	if s == null:
		return
	if pos is Vector3:
		var d: float = (pos as Vector3).distance_to(listener)
		if d > MAX_DIST:
			return
		db += linear_to_db(clampf(1.0 - d / MAX_DIST, 0.02, 1.0) ** 1.5)
	var p := AudioStreamPlayer.new()
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.stream = s
	p.volume_db = db + linear_to_db(maxf(DMSettings.volume, 0.0001))
	p.pitch_scale = 1.0 + randf_range(-pitch, pitch)
	p.finished.connect(func() -> void:
		voices -= 1
		p.queue_free())
	voices += 1
	host.add_child(p)
	p.play()
