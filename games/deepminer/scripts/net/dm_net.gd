class_name DMNet
## Remplaçant local de l'autoload « Net » de Deep Miner : dans LangOS le jeu est toujours solo
## (le multijoueur LAN dépendait d'un nœud RPC à chemin fixe, incompatible avec une fenêtre hébergée).
## Mêmes noms que l'original pour que le reste du code ne change pas.

static var main: Node
static var mode := "solo"
static var joined := false
static var peers := {}
static var remotes := {}
static var puppets := {}
static var pending_partial := {}
static var pvp_att := {"id": 0, "t": 0}
static var zpup := {}

static func is_client() -> bool:
	return false

static func is_host() -> bool:
	return false

static func reset() -> void:
	mode = "solo"; joined = false
	peers = {}; remotes = {}; puppets = {}; pending_partial = {}; zpup = {}
	pvp_att = {"id": 0, "t": 0}

static func host(_port: int) -> Error:
	return ERR_UNAVAILABLE

static func join(_ip: String, _port: int) -> Error:
	return ERR_UNAVAILABLE

static func local_ip() -> String:
	return "127.0.0.1"

static func attack(_vic: int) -> bool:
	return false

static func puppet_tick(_dt: float) -> void: pass
static func report_kill(_att: int) -> void: pass
static func _deliver(_vic: int, _dmg: float, _from: Vector3, _kb: float, _att: int) -> void: pass
static func broadcast_edit(_c: Vector3i, _id: int) -> void: pass
static func broadcast_pieces(_c: Vector3i) -> void: pass
static func send_gear(_g: Dictionary) -> void: pass
static func send_fluid(_idx: Array) -> void: pass
static func send_break(_c: Vector3i) -> void: pass
static func send_place(_c: Vector3i, _item: int) -> void: pass
static func send_pbreak(_c: Vector3i, _b: int) -> void: pass
static func send_pplace(_c: Vector3i, _b: int, _item: int) -> void: pass
static func start_test(_args: PackedStringArray) -> void: pass
