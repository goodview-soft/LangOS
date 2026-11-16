class_name HikaNetTest
extends Node
## Scénario de test réseau headless (tests/hika_net_test.sh) : un hôte et un client sur 127.0.0.1.
## Vérifie : connexion, apparition des joueurs (et équipes), déplacement répliqué, bloc posé répliqué (dans les deux
## sens), scores synchronisés, déconnexion propre. Sorties « [HBTEST] » ; code de sortie 0 si tout passe.

var game: GameManager
var role := ""
var fails := 0

class Walk extends Node:
	var p: PlayerController
	var on := true
	func gather(c: InputCmd, _dt: float) -> void:
		c.clear()
		if on:
			c.move = Vector2(0, 1)

func _ready() -> void:
	_run.call_deferred()

func _ok(cond: bool, msg: String) -> void:
	print("[HBTEST] %s : %s" % ["OK  " if cond else "ECHEC", msg])
	if not cond:
		fails += 1

func _wait(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	return cond.call()

func _finish() -> void:
	print("[HBTEST] %s : %s (%d échec(s))" % [role.to_upper(), "SUCCES" if fails == 0 else "ECHEC", fails])
	get_tree().quit(0 if fails == 0 else 1)

func _run() -> void:
	if role == "host":
		await _host()
	else:
		await _client()
	_finish()

func _playing() -> bool:
	return game.match_manager.state == Cfg.State.PLAYING

func _bridge_blocks() -> int:
	var k := 0
	for x in range(25, 42):
		if game.blocks.get_block(Vector3i(x, 7, 12)) == Cfg.B_BLUE_PLACED:
			k += 1
	return k

func _host() -> void:
	var n := game.hnet
	await get_tree().create_timer(4.0).timeout
	_ok(game.match_manager.state == Cfg.State.LOBBY and n.lobby_t < 0.0 and n.players.size() == 1, "hôte seul : en attente, rien ne démarre")
	_ok(await _wait(func() -> bool: return n.players.size() >= 2, 40.0), "un client s'est connecté (2 joueurs)")
	_ok(await _wait(func() -> bool: return n.lobby_t >= 0.0 and game.match_manager.state == Cfg.State.LOBBY, 3.0), "compte à rebours du salon lancé à 2 joueurs")
	if n.players.size() < 2:
		return
	var remote: PlayerController = n.players[n.players.keys().filter(func(k: int) -> bool: return k != 1)[0]]
	var me: PlayerController = n.players[1]
	_ok(remote.team != me.team, "équipes différentes (%d/%d)" % [me.team, remote.team])
	_ok(remote.provider is RemoteInput, "le joueur distant est simulé par l'hôte")
	_ok(await _wait(_playing, 20.0), "la partie démarre chez l'hôte (PLAYING)")
	var x0 := remote.global_position.x
	_ok(await _wait(func() -> bool: return absf(remote.global_position.x - x0) > 2.0, 20.0), "déplacement du client répliqué sur l'hôte (dx=%.1f)" % (remote.global_position.x - x0))
	var cell := Vector3i(50, 8, 15)
	_ok(await _wait(func() -> bool: return game.blocks.get_block(cell) == Cfg.B_BLUE_PLACED, 20.0), "bloc posé par le client présent chez l'hôte")
	_ok(remote.inv.block_count < Tuning.start_blocks, "stock du client décrémenté côté hôte (%d)" % remote.inv.block_count)
	# L'hôte pose un bloc à son tour : le client doit le recevoir
	var hc := Vector3i(12, 8, 9)
	me.inv.select(Cfg.Slot.BLOCKS)
	_ok(game.authority.request_place(me, hc), "pose de l'hôte acceptée")
	# Pont automatique du client : ses poses passent par l'hôte (même chemin que la pose manuelle)
	_ok(await _wait(func() -> bool: return _bridge_blocks() >= 3, 30.0), "pont automatique du client construit chez l'hôte (%d blocs)" % _bridge_blocks())
	# Point marqué : scores synchronisés vers le client
	game.match_manager.on_bed_reached(me, 1)
	_ok(game.score_manager.scores[0] == 1, "point enregistré chez l'hôte")
	_ok(await _wait(func() -> bool: return n.players.size() < 2, 25.0), "départ du client détecté, joueur retiré")
	_ok(game.team_manager.players.size() == 1, "un seul joueur après déconnexion")

func _client() -> void:
	var n := game.hnet
	_ok(await _wait(func() -> bool: return game.human != null and n.players.size() >= 2, 30.0), "connecté : joueurs créés (%d)" % n.players.size())
	if game.human == null:
		return
	var me := game.human
	_ok(me.pid == multiplayer.get_unique_id() and me.is_local, "joueur local identifié (id %d)" % me.pid)
	_ok(game.match_manager.state == Cfg.State.LOBBY, "le client voit le salon d'attente")
	_ok(await _wait(_playing, 20.0), "la partie démarre ensuite chez le client (PLAYING)")
	var others := n.players.keys().filter(func(k: int) -> bool: return k != me.pid)
	_ok(others.size() == 1 and (n.players[others[0]] as PlayerController).net_puppet, "autre joueur présent (marionnette interpolée)")
	# Déplacement : le joueur local avance, l'hôte le simule et le renvoie
	var w := Walk.new()
	w.p = me
	me.add_child(w)
	me.provider = w
	var x0 := me.global_position.x
	await get_tree().create_timer(1.2).timeout
	w.on = false
	_ok(absf(me.global_position.x - x0) > 2.0, "le joueur local avance (dx=%.1f)" % (me.global_position.x - x0))
	await get_tree().create_timer(1.0).timeout
	var host_p: PlayerController = n.players[others[0]]
	_ok(host_p.global_position.distance_to(Cfg.spawn_pos(host_p.team, 0)) < 1.0, "le joueur hôte est resté près de son spawn")
	# Pose d'un bloc : demandée à l'hôte, qui valide et diffuse
	var cell := Vector3i(50, 8, 15)
	me.inv.select(Cfg.Slot.BLOCKS)
	_ok(game.authority.request_place(me, cell), "demande de pose envoyée")
	_ok(await _wait(func() -> bool: return game.blocks.get_block(cell) == Cfg.B_BLUE_PLACED, 10.0), "bloc reçu en retour de l'hôte")
	_ok(await _wait(func() -> bool: return game.blocks.get_block(Vector3i(12, 8, 9)) == Cfg.B_RED_PLACED, 15.0), "bloc posé par l'hôte reçu")
	# Pont automatique : on avance vers le vide avec l'option, des blocs doivent apparaître sous les pieds
	me.auto_bridge = true
	w.on = true
	_ok(await _wait(func() -> bool: return _bridge_blocks() >= 3, 25.0), "pont automatique : blocs posés dans le vide (%d)" % _bridge_blocks())
	w.on = false
	_ok(me.alive and me.global_position.y > 7.0, "le joueur local ne tombe pas (y=%.1f)" % me.global_position.y)
	_ok(await _wait(func() -> bool: return game.score_manager.scores[0] == 1, 15.0), "score synchronisé (rouge 1)")
	await get_tree().create_timer(0.3).timeout
	game.net.leave()
