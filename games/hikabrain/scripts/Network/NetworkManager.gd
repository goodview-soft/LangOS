class_name NetworkManager
extends Node
## Transport réseau (ENet). Mode LOCAL par défaut : l'autorité est le processus local.
## Le prototype ne réplique pas encore l'état ; voir PlayerReplication et ServerAuthority.

enum Mode { LOCAL, HOST, CLIENT }
signal connected
signal disconnected

var mode := Mode.LOCAL
const DEFAULT_PORT := 24567

func is_authority() -> bool:
	return mode != Mode.CLIENT

func host(port: int = DEFAULT_PORT, max_clients: int = 4) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		mode = Mode.HOST
		connected.emit()
	return err

func join(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		mode = Mode.CLIENT
	return err

func leave() -> void:
	multiplayer.multiplayer_peer = null
	mode = Mode.LOCAL
	disconnected.emit()
