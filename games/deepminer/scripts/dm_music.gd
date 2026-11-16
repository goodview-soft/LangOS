class_name DMMusic extends Node
## Musique de fond en boucle (nœud local au jeu) : fondu d'entrée de 3 s, suit le volume des options.

const TRACK := "res://games/deepminer/audio/cavern_lull.ogg"
const LEVEL := 0.6  # niveau de la musique par rapport au volume général
var player: AudioStreamPlayer
var fade := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # continue pendant la pause du jeu
	if not ResourceLoader.exists(TRACK):
		return
	var s: Resource = load(TRACK)
	if s is AudioStreamOggVorbis:
		s.loop = true
	player = AudioStreamPlayer.new()
	player.stream = s
	player.volume_db = -80.0
	add_child(player)
	player.play()

func _process(dt: float) -> void:
	if player == null:
		return
	fade = minf(fade + dt / 3.0, 1.0)
	player.volume_db = linear_to_db(maxf(LEVEL * fade * DMSettings.volume, 0.0001))
