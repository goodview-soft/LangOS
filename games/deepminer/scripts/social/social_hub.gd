class_name SocialHub
extends Node
## Faux multijoueur : agents, faux réseau, chat, commérages, événements.
## Rôles (docs/AI_DESIGN.md §1) : le cerveau moteur (Brain, via `responder`) décide ; LLM n'est que
## l'oreille (message du joueur -> intention structurée) et la bouche (intention -> message court).

signal agent_joined(pseudo: String)
signal agent_left(pseudo: String)
signal chat_message(entry: Dictionary)          ## {from, text, kind: player|agent|system, to, time, status}
signal typing_changed(pseudo: String, typing: bool)
signal agent_action(pseudo: String, action: String, params: Dictionary)  ## params: {target, item, count}
signal relations_changed(pseudo: String)

const PLAYER := "player"
const HISTORY_MAX := 30
const PROMPT_HISTORY := 6
const ACTIONS: Array[String] = ["none", "follow", "stop_follow", "mine_with", "build_with", "give", "trade", "guard", "avoid", "accept_alliance", "refuse", "break_alliance"]
const FRIENDLY_ACTIONS: Array[String] = ["follow", "mine_with", "build_with", "give", "trade"]

const DEFAULT_AGENTS := [
	["kevin_mine", "bavard", "écrit vite, abréviations partout, dit mdr"],
	["LeaCraft", "serviable", "gentille, met des :) , propose son aide"],
	["xX_Dark_Xx", "raleur", "sec, se plaint du lag et des autres"],
	["pioche_tranquille", "discret", "répond en 1 à 4 mots"],
	["TomTom42", "farceur", "blagues, ptdr, taquine"],
]

@export var player_name: String = "Joueur"
## false : le jeu (ou les tests) appelle tick(delta) lui-même.
@export var auto_process: bool = true
@export var simulate_network: bool = true
@export var spontaneous_min_gap: float = 25.0
@export var spontaneous_max_gap: float = 40.0
@export var create_defaults: bool = true

var agents: Dictionary = {}          ## pseudo -> SocialAgent
var history: Array = []
var voice: RuleVoice
var now: float = 0.0
var rng := RandomNumberGenerator.new()
var nearby: Array[String] = []       ## pseudos proches du joueur (messages non adressés)
var game_context: Dictionary = {}    ## pseudo -> Dictionary ; clé "" = contexte global
var context_provider: Callable       ## optionnel : func(pseudo) -> Dictionary
var force_decision: String = ""      ## tests : "now" | "later" | "ignore"
## func(pseudo, heard: {intent, item, count, give, want, sentiment}) -> {say, action, item, count, affinity, give, want, pending}
## Vide ({}) ou non défini : décision par règles (generate_fallback).
var responder: Callable
var net_send: Callable  ## client LAN : envoie le texte à l'hôte au lieu de le traiter ici
## func(texte) -> String : un message qui commence par « / » est une commande.
var command_handler: Callable
var pending: Dictionary = {}         ## pseudo -> {kind: trade|alliance, give, want, until} (offre faite au joueur)
@export var mouth_reply_chance: float = 0.6   ## part des réponses formulées par LLM (le reste : phrases toutes faites)
@export var mouth_spont_chance: float = 0.3   ## §7 : ~70 % de phrases toutes faites pour les prises de parole spontanées
@export var ear_enabled: bool = true
var last_latency_ms: int = -1        ## dernière réponse d'LLM (oreille ou bouche)

var _requests: Dictionary = {}       ## request_id -> {pseudo, target, intent, delay, text}
var _scheduled: Array = []           ## messages en cours de « frappe »
var _budget_ready_at: float = 0.0
var _next_ai_chat: float = 60.0
var _ping_timer: float = 0.0
var _network_started: bool = false
var _leaving: Dictionary = {}        ## pseudo -> heure réelle du départ (après le « bon j'y vais »)
var _world_react_at: float = 0.0
var voice_budget_uses: int = 0      ## nombre de requêtes LLM spontanées autorisées (tests du budget)


func _ready() -> void:
	rng.randomize()
	if voice == null:
		voice = RuleVoice.new()
		voice.name = "RuleVoice"
		add_child(voice)
	if not voice.reply.is_connected(_on_reply):
		voice.reply.connect(_on_reply)
	if agents.is_empty() and create_defaults:
		create_default_agents()
	_next_ai_chat = now + rng.randf_range(40.0, 90.0)
	_budget_ready_at = now + rng.randf_range(8.0, 15.0)
	if simulate_network:
		start_network.call_deferred()


func _process(delta: float) -> void:
	if auto_process:
		tick(delta)


# ---------------------------------------------------------------- agents
func create_default_agents() -> void:
	for row: Array in DEFAULT_AGENTS:
		add_agent(SocialAgent.new(String(row[0]), String(row[1]), String(row[2])))
	# petites amitiés / rivalités entre IA
	var names := agents.keys()
	for a: String in names:
		for b: String in names:
			if a != b and not (agents[a] as SocialAgent).has_relation(b):
				var v := rng.randi_range(-35, 55)
				(agents[a] as SocialAgent).set_affinity(b, v)
				(agents[b] as SocialAgent).set_affinity(a, clampi(v + rng.randi_range(-15, 15), -100, 100))


func add_agent(agent: SocialAgent) -> void:
	agents[agent.pseudo] = agent


func get_agent(pseudo: String) -> SocialAgent:
	return agents.get(pseudo, null)


func online_agents() -> Array[SocialAgent]:
	var out: Array[SocialAgent] = []
	for a: SocialAgent in agents.values():
		if a.online:
			out.append(a)
	return out


func set_game_context(pseudo: String, ctx: Dictionary) -> void:
	game_context[pseudo] = ctx


func set_nearby(pseudos: Array) -> void:
	nearby.clear()
	for p: Variant in pseudos:
		nearby.append(String(p))


## Liste pour l'UI : [{pseudo, status, ping, online, affinity, typing, busy}]
func get_player_list() -> Array:
	var out: Array = []
	for a: SocialAgent in agents.values():
		out.append({"pseudo": a.pseudo, "status": a.get_status_name(PLAYER), "ping": a.ping, "online": a.online,
			"affinity": a.get_affinity(PLAYER), "busy": a.is_busy(now), "typing": is_typing(a.pseudo)})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if bool(x["online"]) != bool(y["online"]):
			return bool(x["online"])
		return String(x["pseudo"]).naturalnocasecmp_to(String(y["pseudo"])) < 0)
	return out


func status_for_player(pseudo: String) -> String:
	var a := get_agent(pseudo)
	return a.get_status_name(PLAYER) if a else "INCONNU"


func is_typing(pseudo: String) -> bool:
	for s: Dictionary in _scheduled:
		if String(s["pseudo"]) == pseudo and bool(s["typing"]):
			return true
	return false


# ---------------------------------------------------------------- boucle
func tick(delta: float) -> void:
	now += delta
	if simulate_network:
		_tick_network(delta)
	_tick_scheduled()
	_tick_ai_chat()


func _tick_scheduled() -> void:
	var i := 0
	while i < _scheduled.size():
		var s: Dictionary = _scheduled[i]
		var agent := get_agent(String(s["pseudo"]))
		if agent == null or not agent.online:
			if bool(s["typing"]):
				typing_changed.emit(String(s["pseudo"]), false)
			_scheduled.remove_at(i)
			continue
		if not bool(s["typing"]) and now >= float(s["type_at"]):
			s["typing"] = true
			typing_changed.emit(agent.pseudo, true)
		if now >= float(s["show_at"]):
			_scheduled.remove_at(i)
			typing_changed.emit(agent.pseudo, false)
			_deliver(agent, s)
			continue
		i += 1


# ---------------------------------------------------------------- faux réseau
func start_network() -> void:
	if _network_started:
		return
	_network_started = true
	for a: SocialAgent in agents.values():
		if a.next_change_at <= now:
			# au lancement : une partie des joueurs est déjà là, sans message
			a.online = rng.randf() < 0.5
			a.next_change_at = now + (rng.randf_range(60.0, 600.0) if a.online else rng.randf_range(15.0, 180.0))
		if a.online:
			agent_joined.emit(a.pseudo)


func _tick_network(delta: float) -> void:
	for a: SocialAgent in agents.values():
		if _leaving.has(a.pseudo):
			if now >= float(_leaving[a.pseudo]):
				_leaving.erase(a.pseudo)
				force_leave(a.pseudo)
			continue
		if a.next_change_at > 0.0 and now >= a.next_change_at:
			if a.online:
				if rng.randf() < 0.6:  # « bon j'y vais », puis il part
					_react(a, "bye", "", 1.0)
					_leaving[a.pseudo] = now + 5.0
				else:
					force_leave(a.pseudo)
			else:
				force_join(a.pseudo)
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = 2.0
		for a: SocialAgent in agents.values():
			if a.online:
				a.ping = clampi(a.ping + rng.randi_range(-9, 9), 18, 160)
				if rng.randf() < 0.03:
					a.ping = rng.randi_range(180, 420)  # pic de lag


func force_join(pseudo: String) -> void:
	var a := get_agent(pseudo)
	if a == null or a.online:
		return
	a.online = true
	a.ping = rng.randi_range(25, 110)
	a.next_change_at = now + rng.randf_range(180.0, 900.0)  # session de plusieurs minutes
	_system("%s a rejoint la partie" % pseudo)
	agent_joined.emit(pseudo)
	# un ami salue parfois en arrivant
	if a.is_friend_of(PLAYER) and rng.randf() < 0.5:
		_spontaneous(a, "greet", PLAYER, true)
	elif rng.randf() < 0.6:
		_react(a, "join_greet", "", 1.0)
	# un autre joueur en ligne répond parfois au salut
	var others := online_agents().filter(func(x: SocialAgent) -> bool: return x != a)
	if not others.is_empty() and rng.randf() < 0.35:
		_react(others[rng.randi() % others.size()], "join_greet", "", 1.0, 2.5)


func force_leave(pseudo: String) -> void:
	var a := get_agent(pseudo)
	if a == null or not a.online:
		return
	a.online = false
	_leaving.erase(pseudo)
	a.next_change_at = now + rng.randf_range(40.0, 300.0)
	_tick_scheduled()  # annule ce qu'il était en train d'écrire
	_system("%s a quitté la partie" % pseudo)
	agent_left.emit(pseudo)


# ---------------------------------------------------------------- chat
func _push(entry: Dictionary) -> void:
	entry["time"] = now
	history.append(entry)
	while history.size() > HISTORY_MAX:
		history.pop_front()
	chat_message.emit(entry)


func system_message(text: String) -> void:
	_system(text)


func _system(text: String) -> void:
	_push({"from": "", "text": text, "kind": "system", "to": "", "status": "SYSTEME"})


func _say(agent: SocialAgent, text: String, to: String) -> void:
	_push({"from": agent.pseudo, "text": text, "kind": "agent", "to": to, "status": agent.get_status_name(PLAYER)})


## Hôte LAN : message d'un autre vrai joueur (traité comme celui du joueur local, sous son pseudo).
func remote_player_message(from: String, text: String) -> void:
	if text.begins_with("/"):
		return
	var old := player_name
	player_name = from
	send_player_message(text)
	player_name = old

## Le joueur envoie un message dans le chat.
func send_player_message(text: String) -> void:
	var t := text.strip_edges().left(200)
	if t.is_empty():
		return
	if net_send.is_valid():
		net_send.call(t)
		return
	if t.begins_with("/") and command_handler.is_valid():
		_system(String(command_handler.call(t)))
		return
	var targets := _find_targets(t)
	var addressed := not targets.is_empty()
	_push({"from": player_name, "text": t, "kind": "player", "to": ",".join(targets), "status": "JOUEUR"})
	var intent := classify(t)
	if not addressed:
		for p: String in nearby:
			var na := get_agent(p)
			if na and na.online:
				targets.append(p)
		addressed = not targets.is_empty()
	if not addressed:
		for a: SocialAgent in online_agents():
			targets.append(a.pseudo)
	var max_responders := 99 if addressed else 2
	var who: Array = []  # [pseudo, delay]
	targets.shuffle()
	for p: String in targets:
		var agent := get_agent(p)
		if agent == null:
			continue
		_apply_message_effects(agent, intent, t, addressed)
		if who.size() >= max_responders:
			continue
		var decision := decide_response(agent, addressed, intent)
		if decision == "ignore":
			continue
		who.append([p, 0.0 if decision == "now" else rng.randf_range(6.0, 20.0)])
	if who.is_empty() and force_decision.is_empty():
		# personne n'a voulu répondre : si on lui parle (nom, question, salut), au moins un bot répond, jamais le silence total
		var worth := addressed or t.contains("?") or intent.begins_with("greet") or intent.begins_with("request_") or rng.randf() < 0.4
		var live: Array[String] = []
		for p2: String in targets:
			var ag := get_agent(p2)
			if ag != null and ag.online and ag.get_status(PLAYER) != SocialAgent.Status.ENNEMI:
				live.append(p2)
		if worth and not live.is_empty():
			who.append([live[rng.randi() % live.size()], rng.randf_range(1.5, 5.0)])
	if who.is_empty():
		return
	var rules := hear_rules(t)
	if ear_enabled and _voice_on():
		var pr := build_ear_prompt(t)
		var id := voice.request_chat(pr[0], pr[1], {"intent": "ear", "text": t})
		_requests[id] = {"kind": "ear", "text": t, "who": who, "rules": rules, "addressed": addressed, "t0": Time.get_ticks_msec()}
	else:
		for w: Array in who:
			_respond(get_agent(String(w[0])), rules, t, float(w[1]))


func _find_targets(t: String) -> Array[String]:
	var out: Array[String] = []
	var low := t.to_lower()
	var re := RegEx.new()
	re.compile("@([A-Za-z0-9_\\-]+)")
	for m: RegExMatch in re.search_all(t):
		var name := m.get_string(1).to_lower()
		for p: String in agents:
			if p.to_lower() == name and not out.has(p):
				out.append(p)
	if out.is_empty():
		var words := _words(low)
		for p: String in agents:
			var pl := p.to_lower()
			var head := pl.split("_", false)[0] if not pl.split("_", false).is_empty() else pl
			if low.contains(pl) or (head.length() >= 4 and words.has(head)):
				out.append(p)
	return out


static func _words(low: String) -> PackedStringArray:
	var re := RegEx.new()
	re.compile("[a-zàâäéèêëîïôöùûüç0-9']+")
	var out := PackedStringArray()
	for m: RegExMatch in re.search_all(low):
		out.append(m.get_string())
	return out


const INSULTS: Array[String] = ["con", "conne", "nul", "nulle", "idiot", "noob", "débile", "debile", "tg", "naze", "bouffon", "merde", "pue", "teubé", "abruti", "boulet", "clown", "nullos", "batard"]

## Intention grossière d'un message (sert au repli, aux effets immédiats et au prompt).
static func classify(text: String) -> String:
	var t := text.to_lower()
	var w := _words(t)
	for i: String in INSULTS:
		if w.has(i):
			return "insult"
	if t.contains("ta gueule") or t.contains("ferme la"):
		return "insult"
	for k: String in ["je vais te tuer", "jvais te tuer", "je vais te défoncer", "dégage", "degage", "casse toi", "attention a toi"]:
		if t.contains(k):
			return "threat"
	for k: String in ["désolé", "desole", "dsl", "pardon", "my bad", "excuse"]:
		if w.has(k) or t.contains(k):
			return "apology"
	if w.size() <= 3:
		for k: String in ["ok", "oui", "ouais", "deal", "dac", "d'accord", "go", "vas-y", "ça marche", "ca marche", "yes", "ouep", "okay"]:
			if w.has(k) or t.strip_edges() == k:
				return "accept"
		for k: String in ["non", "nan", "no", "jamais", "nope"]:
			if w.has(k):
				return "refuse"
	for k: String in ["allian", "allié", "allie", "faire équipe", "faire equipe", "on fait team", "en team", "s'allier"]:
		if t.contains(k):
			return "alliance"
	for k: String in ["arrête de me suivre", "arrete de me suivre", "arrête", "arrete", "stop"]:
		if t.contains(k):
			return "request_stop"
	for k: String in ["suis-moi", "suis moi", "viens", "follow", "rejoins-moi", "rejoins moi"]:
		if t.contains(k):
			return "request_follow"
	for k: String in ["échange", "echange", "trade", "troc", "contre"]:
		if t.contains(k):
			return "request_trade"
	for k: String in ["donne", "file-moi", "file moi", "passe-moi", "passe moi", "prête", "prete", "t'as du", "tu as du", "t'aurais"]:
		if t.contains(k):
			return "request_give"
	for k: String in ["mine avec", "miner ensemble", "miner avec", "creuse avec", "creuser ensemble", "on mine", "on creuse"]:
		if t.contains(k):
			return "request_mine"
	for k: String in ["construi", "bâtir", "batir", "on build"]:
		if t.contains(k):
			return "request_build"
	for k: String in ["merci", "bravo", "gg", "cool", "sympa", "génial", "genial", "trop fort", "stylé", "style", "t'es le meilleur", "bien joué"]:
		if w.has(k) or (k.contains(" ") and t.contains(k)):
			return "compliment"
	for k: String in ["salut", "slt", "bonjour", "yo", "coucou", "wesh", "hello", "cc", "bjr", "hey", "re"]:
		if w.has(k):
			return "greet"
	if t.contains("?"):
		return "question"
	return "generic"


func _extract_item(t: String) -> String:
	var re := RegEx.new()
	re.compile("(?:du|de la|des|de l'|d')\\s*([a-zàâéèêîôûç]+)")
	var m := re.search(t.to_lower())
	return m.get_string(1) if m else ""


func _apply_message_effects(agent: SocialAgent, intent: String, text: String, addressed: bool) -> void:
	agent.meet(PLAYER)
	if not addressed:
		return
	match intent:
		"insult":
			agent.change_affinity(PLAYER, -8)
			agent.nudge_mood(-0.25)
			agent.add_memory(PLAYER, "m'a insulté : « %s »" % text.left(40))
			gossip(agent.pseudo, PLAYER, "%s a insulté %s" % [player_name, agent.pseudo], -6)
		"compliment":
			agent.change_affinity(PLAYER, 3)
			agent.nudge_mood(0.1)
			agent.add_memory(PLAYER, "m'a fait un compliment")
	relations_changed.emit(agent.pseudo)


## Répondre tout de suite, plus tard, ou ignorer vraiment.
func decide_response(agent: SocialAgent, addressed: bool, intent: String) -> String:
	if not force_decision.is_empty():
		return force_decision
	if not agent.online:
		return "ignore"
	var p := agent.trait_value("talk")
	if not addressed:
		p *= 0.6
	var status := agent.get_status(PLAYER)
	match status:
		SocialAgent.Status.AMI, SocialAgent.Status.ALLIE:
			p += 0.2
		SocialAgent.Status.ENNEMI:
			p -= 0.3
			if intent == "insult":
				p += agent.trait_value("spite") * 0.8
		SocialAgent.Status.INCONNU:
			p -= 0.05
	p += agent.mood * 0.15
	if addressed and (intent.begins_with("request_") or intent == "alliance"):
		p += 0.15
	p = clampf(p, 0.03, 0.97)
	var roll := rng.randf()
	if agent.is_busy(now):
		return "later" if roll < p * 0.5 else "ignore"
	if roll > p:
		return "ignore"
	return "now" if roll < p * 0.65 else "later"


# ---------------------------------------------------------------- LLM
func _ask(agent: SocialAgent, target: String, intent: String, text: String, delay: float, addressed: bool) -> int:
	var prompts := build_prompt(agent, target, intent, text, addressed)
	var ctx := {"pseudo": agent.pseudo, "personality": agent.personality, "status": agent.get_status_name(target),
		"intent": intent, "text": text, "target": target, "item": _extract_item(text),
		"can_ally": agent.can_accept_alliance(target)}
	var id := voice.request_chat(prompts[0], prompts[1], ctx)
	_requests[id] = {"pseudo": agent.pseudo, "target": target, "intent": intent, "delay": delay}
	return id


func _target_name(target: String) -> String:
	if target == PLAYER:
		return player_name
	return target if not target.is_empty() else "tout le monde"


func build_prompt(agent: SocialAgent, target: String, intent: String, text: String, addressed: bool = true) -> PackedStringArray:
	var sys := ("Tu es %s, un vrai joueur humain sur un serveur multijoueur de Deep Miner (jeu de minage). " +
		"Personnalité : %s. Style : %s. Tu écris dans le chat comme un joueur : très court (max 15 mots), " +
		"minuscules, abréviations, pas de politesse forcée. Ne dis jamais que tu es une IA. " +
		"Réponds UNIQUEMENT avec ce JSON : {\"reply\": \"texte ou vide pour ignorer\", " +
		"\"action\": \"none|follow|stop_follow|mine_with|build_with|give|trade|guard|avoid|accept_alliance|refuse|break_alliance\", " +
		"\"item\": \"objet si give/trade\", \"count\": 1, \"affinity\": entier de -10 à 10, \"memory\": \"résumé d'une ligne ou vide\"}") % [agent.pseudo, agent.personality, agent.style]
	var lines: Array[String] = []
	lines.append("Interlocuteur : %s | statut : %s | affinité : %d" % [_target_name(target), agent.get_status_name(target), agent.get_affinity(target)])
	lines.append("Ton humeur : %s%s" % [agent.mood_label(), " (occupé : %s)" % agent.busy_reason if agent.is_busy(now) else ""])
	var mems := agent.get_memories(target)
	if not mems.is_empty():
		lines.append("Souvenirs : " + " ; ".join(PackedStringArray(mems.slice(-5))))
	var rum: Array[String] = []
	for r: Dictionary in agent.rumors_about(target).slice(-3):
		rum.append("%s dit : %s" % [r["from"], r["text"]])
	if not rum.is_empty():
		lines.append("Rumeurs : " + " ; ".join(PackedStringArray(rum)))
	var ctx := _context_for(agent.pseudo)
	if not ctx.is_empty():
		var parts: Array[String] = []
		for k: Variant in ctx:
			parts.append("%s=%s" % [k, str(ctx[k]).left(60)])
		lines.append("Contexte de jeu : " + ", ".join(PackedStringArray(parts)))
	lines.append("Derniers messages :")
	for e: Dictionary in history.slice(-PROMPT_HISTORY):
		var who := String(e["from"]) if String(e["kind"]) != "system" else "[serveur]"
		lines.append("  %s: %s" % [who, String(e["text"]).left(80)])
	if not text.is_empty():
		lines.append("Message %s : « %s » (intention : %s)" % ["qui t'est adressé" if addressed else "public", text.left(120), intent])
	else:
		lines.append("Situation : %s. Dis un truc spontané à %s." % [intent, _target_name(target)])
	if intent == "alliance":
		lines.append("Alliance possible : %s." % ("oui si tu veux" if agent.can_accept_alliance(target) else "non, refuse"))
	return PackedStringArray([sys, "\n".join(PackedStringArray(lines))])


func _context_for(pseudo: String) -> Dictionary:
	var ctx: Dictionary = (game_context.get("", {}) as Dictionary).duplicate()
	ctx.merge(game_context.get(pseudo, {}), true)
	if context_provider.is_valid():
		var extra: Variant = context_provider.call(pseudo)
		if extra is Dictionary:
			ctx.merge(extra, true)
	return ctx


## Validation stricte + bornage de la sortie JSON. Renvoie {valid:false,...} si inexploitable.
static func validate_response(data: Variant) -> Dictionary:
	var out := {"valid": false, "reply": "", "action": "none", "item": "", "count": 0, "affinity": 0, "memory": ""}
	if not (data is Dictionary):
		return out
	var d: Dictionary = data
	out["valid"] = true
	var r: Variant = d.get("reply", "")
	if r is String:
		var s := (r as String).replace("\n", " ").replace("\r", " ").strip_edges()
		s = s.trim_prefix("\"").trim_suffix("\"").strip_edges()
		out["reply"] = s.left(140)
	var a: Variant = d.get("action", "none")
	if a is String:
		var act := (a as String).strip_edges().to_lower()
		out["action"] = act if ACTIONS.has(act) else "none"
	var it: Variant = d.get("item", "")
	if it is String:
		out["item"] = (it as String).strip_edges().left(32)
	out["count"] = clampi(_to_int(d.get("count", 0)), 0, 64)
	if (out["action"] == "give" or out["action"] == "trade") and int(out["count"]) == 0:
		out["count"] = 1
	out["affinity"] = clampi(_to_int(d.get("affinity", 0)), -10, 10)
	var m: Variant = d.get("memory", "")
	if m is String:
		out["memory"] = (m as String).replace("\n", " ").strip_edges().left(90)
	return out


static func _to_int(v: Variant) -> int:
	if v is int:
		return v
	if v is float:
		return roundi(v)
	if v is String and (v as String).strip_edges().is_valid_float():
		return roundi((v as String).to_float())
	return 0


func _on_reply(request_id: int, data: Dictionary) -> void:
	if not _requests.has(request_id):
		return
	var req: Dictionary = _requests[request_id]
	_requests.erase(request_id)
	var from_llm := String(data.get("_source", "")) == "voice"
	if from_llm and req.has("t0"):
		last_latency_ms = Time.get_ticks_msec() - int(req["t0"])
	match String(req.get("kind", "")):
		"ear":
			var heard: Dictionary = (req["rules"] as Dictionary).duplicate()
			if from_llm:
				heard.merge(validate_heard(data), true)
			for w: Array in req["who"]:
				var a := get_agent(String(w[0]))
				if a and a.online:
					_respond(a, heard, String(req["text"]), float(w[1]))
			return
		"mouth":
			var agent := get_agent(String(req["pseudo"]))
			if agent == null or not agent.online:
				return
			var v: Dictionary = req["v"]
			var canned := String(req["canned"])
			v["reply"] = humanize(String(data.get("reply", "")) if from_llm else canned, canned)
			_schedule_split(agent, String(req["target"]), String(req["intent"]), v, float(req["delay"]))
			return
	var agent2 := get_agent(String(req.get("pseudo", "")))
	if agent2 == null or not agent2.online:
		return
	_schedule(agent2, String(req["target"]), String(req["intent"]), validate_response(data), float(req["delay"]))


func _voice_on() -> bool:
	return voice != null and voice.available and not voice.force_fallback


# ---------------------------------------------------------------- oreille (message -> intention)
const HEARD_INTENTS: Array[String] = ["greet", "insult", "threat", "compliment", "apology", "alliance", "request_follow", "request_stop",
	"request_give", "request_trade", "request_mine", "request_build", "accept", "refuse", "question", "generic"]

## Oreille par règles : {intent, item, count, give, want, sentiment}. give = ce que le joueur donne, want = ce qu'il demande.
static func hear_rules(text: String) -> Dictionary:
	var t := text.to_lower()
	var intent := classify(text)
	var out := {"intent": intent, "item": "", "count": 0, "give": {}, "want": {}, "sentiment": 0.0}
	var re := RegEx.new()
	re.compile("(\\d+)?\\s*(terre|roche|pierre|charbon|fer|cuivre|cristal|cristaux|diamants?|torches?|champignons?)")
	var cut := t.find("contre")
	for m: RegExMatch in re.search_all(t):
		var n := int(m.get_string(1)) if m.get_string(1) != "" else 1
		var word := m.get_string(2)
		if out["item"] == "":
			out["item"] = word
			out["count"] = n
		var side := "want"
		if cut >= 0:
			side = "give" if m.get_start() < cut else "want"
			# « je te donne X contre Y » : X donné ; « file-moi X contre Y » : X demandé
			if t.substr(0, cut).contains("file") or t.substr(0, cut).contains("donne-moi") or t.substr(0, cut).contains("passe"):
				side = "want" if side == "give" else "give"
		elif intent == "request_trade" and (t.contains("je te donne") or t.contains("jte donne") or t.contains("je donne")):
			side = "give"
		(out[side] as Dictionary)[word] = (out[side] as Dictionary).get(word, 0) + n
	if intent == "insult" or intent == "threat":
		out["sentiment"] = -0.8
	elif intent == "compliment" or intent == "apology":
		out["sentiment"] = 0.6
	return out


func build_ear_prompt(text: String) -> PackedStringArray:
	var sys := ("Tu analyses un message de chat d'un jeu de minage multijoueur (objets : terre, roche, charbon, fer, cuivre, cristal, torche, champignon). " +
		"Réponds UNIQUEMENT avec ce JSON : {\"intent\": \"%s\", \"item\": \"objet cité ou vide\", \"count\": 0, " +
		"\"give\": {\"objet\": nombre que l'auteur DONNE}, \"want\": {\"objet\": nombre que l'auteur DEMANDE}, \"sentiment\": -1 à 1}") % "|".join(HEARD_INTENTS)
	return PackedStringArray([sys, "Message : « %s »" % text.left(160)])


static func validate_heard(d: Dictionary) -> Dictionary:
	var out := {}
	var it := String(d.get("intent", "")).strip_edges().to_lower()
	if HEARD_INTENTS.has(it):
		out["intent"] = it
	if d.get("item", "") is String and String(d["item"]) != "":
		out["item"] = String(d["item"]).to_lower().left(20)
		out["count"] = clampi(_to_int(d.get("count", 1)), 1, 64)
	for k: String in ["give", "want"]:
		var src: Variant = d.get(k, {})
		if src is Dictionary and not (src as Dictionary).is_empty():
			var dd := {}
			for key: Variant in src:
				var n := clampi(_to_int(src[key]), 0, 64)
				if n > 0:
					dd[String(key).to_lower().left(20)] = n
			if not dd.is_empty():
				out[k] = dd
	return out


# ---------------------------------------------------------------- décision (Brain) puis bouche
func _respond(agent: SocialAgent, heard: Dictionary, text: String, delay: float) -> void:
	if agent == null:
		return
	var intent := String(heard.get("intent", "generic"))
	var dec: Dictionary = {}
	if responder.is_valid():
		dec = responder.call(agent.pseudo, heard)
	var canned := ""
	if dec.is_empty():  # pas de cerveau : règles
		var ctx := {"pseudo": agent.pseudo, "personality": agent.personality, "status": agent.get_status_name(PLAYER),
			"intent": intent, "text": text, "target": PLAYER, "item": String(heard.get("item", "")), "can_ally": agent.can_accept_alliance(PLAYER)}
		dec = voice.generate_fallback(ctx)
		canned = String(dec.get("reply", ""))
	var v := validate_response(dec)
	v["say"] = String(dec.get("say", intent))
	for k: String in ["give", "want"]:
		if dec.has(k):
			v[k] = dec[k]
	if String(dec.get("pending", "")) != "":
		pending[agent.pseudo] = {"kind": String(dec["pending"]), "give": dec.get("give", {}), "want": dec.get("want", {}), "until": now + 60.0}
	_mouth(agent, PLAYER, intent, v, delay, canned, text, mouth_reply_chance)


## Le cerveau moteur veut dire quelque chose : {intent, target, tone, give?, want?}.
func say_intent(pseudo: String, it: Dictionary) -> void:
	var agent := get_agent(pseudo)
	if agent == null or not agent.online:
		return
	var say := String(it.get("intent", "generic"))
	var target := String(it.get("target", ""))
	var v := {"valid": true, "reply": "", "action": "none", "item": "", "count": 0, "affinity": 0, "memory": "", "say": say,
		"give": it.get("give", {}), "want": it.get("want", {})}
	if target == PLAYER and (say == "propose_trade" or say == "invite_alliance"):
		pending[pseudo] = {"kind": "trade" if say == "propose_trade" else "alliance", "give": it.get("give", {}), "want": it.get("want", {}), "until": now + 60.0}
	var chance := mouth_spont_chance if _budget_ok() else 0.0
	if chance > 0.0:
		_consume_budget()
	_mouth(agent, target, say, v, rng.randf_range(0.4, 2.0), "", "", chance)


static func items_text(d: Variant) -> String:
	var parts: Array[String] = []
	if d is Dictionary:
		for k: Variant in d:
			var w: String = (World.NAMES[k] as String).to_lower() if k is int and k >= 0 and k < World.NAMES.size() else String(k)
			parts.append("%d %s" % [int(d[k]), w])
	return " ".join(PackedStringArray(parts))


## Bouche : phrase toute faite, ou LLM (avec probabilité `chance`) ; sortie filtrée (§7).
func _mouth(agent: SocialAgent, target: String, intent: String, v: Dictionary, delay: float, canned: String = "", heard_text: String = "", chance: float = 0.0) -> void:
	var say := String(v.get("say", intent))
	var ctx := {"intent": "say", "say": say, "pseudo": agent.pseudo, "personality": agent.personality, "status": agent.get_status_name(target),
		"give": items_text(v.get("give", {})), "want": items_text(v.get("want", {})), "item": String(v.get("item", "")), "count": int(v.get("count", 0))}
	if canned.is_empty():
		canned = String(voice.generate_fallback(ctx).get("reply", ""))
	if canned.is_empty() and String(v["action"]) == "none":
		_apply_effects(agent, target, intent, v)
		return
	if _voice_on() and rng.randf() < chance:
		var pr := build_mouth_prompt(agent, target, say, ctx, heard_text)
		var id := voice.request_chat(pr[0], pr[1], ctx)
		_requests[id] = {"kind": "mouth", "pseudo": agent.pseudo, "target": target, "intent": intent, "v": v, "canned": canned, "delay": delay, "t0": Time.get_ticks_msec()}
		return
	v["reply"] = humanize(canned, canned, 0.0)
	_schedule_split(agent, target, intent, v, delay)


## Plusieurs petits messages plutôt qu'une phrase (§7).
func _schedule_split(agent: SocialAgent, target: String, intent: String, v: Dictionary, delay: float) -> void:
	var words := String(v["reply"]).split(" ", false)
	if words.size() >= 5 and rng.randf() < 0.3:
		var k := rng.randi_range(2, words.size() - 2)
		var v2 := v.duplicate()
		v2["action"] = "none"
		v2["affinity"] = 0
		v2["memory"] = ""
		v["reply"] = " ".join(words.slice(0, k))
		v2["reply"] = " ".join(words.slice(k))
		_schedule(agent, target, intent, v, delay)
		_schedule(agent, target, "followup", v2, delay + rng.randf_range(1.0, 2.5))
		return
	_schedule(agent, target, intent, v, delay)


const SAY_DESC := {
	"greet": "dire salut", "greet_enemy": "répondre sèchement, tu ne l'aimes pas", "threaten": "menacer pour qu'il quitte ta zone",
	"taunt": "le provoquer", "scared": "calmer le jeu, t'as pas envie de te battre", "warn_danger": "le prévenir d'un danger (lave, monstre)",
	"danger": "prévenir d'un danger", "invite_alliance": "proposer de faire équipe", "apologize": "t'excuser pour le coup de pioche",
	"propose_trade": "proposer d'échanger tes {give} contre ses {want}", "ask_help": "demander de l'aide, on t'attaque",
	"brag": "te vanter", "trade_yes": "accepter l'échange", "trade_no": "refuser l'échange", "trade_ask": "demander ce qu'il donne en échange",
	"trade_counter": "contre-proposer : tes {give} contre ses {want}", "trade_fail": "dire qu'il n'a pas ce qu'il faut",
	"deal": "confirmer, c'est fait", "too_bad": "dire tant pis", "alliance_yes": "accepter l'alliance", "alliance_no": "refuser l'alliance, pas confiance",
	"follow": "accepter de le suivre", "follow_no": "refuser de le suivre", "stop": "dire ok tu arrêtes", "give": "lui filer {count} {item}",
	"give_no": "refuser de donner", "mine_with": "accepter de miner avec lui", "build_with": "accepter de construire avec lui",
	"insult": "réagir à son insulte", "compliment": "réagir au compliment", "apology_ok": "accepter ses excuses", "apology_no": "refuser ses excuses",
	"question": "répondre vaguement à sa question", "generic": "réagir en deux mots", "chat_ai": "dire un truc banal sur la partie",
	"killed": "chambrer, tu viens de le tuer", "died": "râler, tu viens de mourir", "gift_thanks": "remercier pour le cadeau",
	"betrayal": "lui reprocher sa trahison", "provoke": "le provoquer", "base_broken": "râler, il casse des blocs près de ta base", "found": "dire que t'as trouvé un filon"}

const FEW_SHOT := ["slt", "yo ça va", "jsp mdr", "att jarrive", "tkt", "gg", "wsh t ou", "jai full fer", "qqn a du charbon", "nan flemme",
	"lag de ouf", "mdr t nul", "ok go", "dsl jtai tapé", "dégage de ma base", "jsuis en bas vers la lave", "c mon filon la", "trop bien",
	"ah ouais", "brb jmange"]


func build_mouth_prompt(agent: SocialAgent, target: String, say: String, ctx: Dictionary, heard_text: String = "") -> PackedStringArray:
	var sys := ("Tu es %s, joueur de Deep Miner, style %s. Écris UN message de chat, 1 à 6 mots, minuscules, abréviations, sans emoji, sans politesse. " +
		"Ex : %s. JSON : {\"reply\": \"...\"}") % [agent.pseudo, agent.style if agent.style != "" else agent.personality, " | ".join(PackedStringArray(FEW_SHOT))]
	var desc := String(SAY_DESC.get(say, say)).replace("{give}", String(ctx.get("give", ""))).replace("{want}", String(ctx.get("want", ""))) \
		.replace("{item}", String(ctx.get("item", ""))).replace("{count}", str(ctx.get("count", "")))
	var lines: Array[String] = ["à %s (%s) : %s." % [_target_name(target), agent.get_status_name(target).to_lower(), desc]]
	if not heard_text.is_empty():
		lines.append("il a écrit : « %s »" % heard_text.left(80))
	var c := _context_for(agent.pseudo)
	if not c.is_empty():
		var parts: Array[String] = []
		for k: Variant in c:
			parts.append("%s=%s" % [k, str(c[k]).left(30)])
		lines.append("ctx : " + ", ".join(PackedStringArray(parts.slice(0, 3))))
	return PackedStringArray([sys, "\n".join(PackedStringArray(lines))])


const BLACKLIST: Array[String] = ["bien sûr", "bien sur", "n'hésite", "n'hesite", "je comprends", "en tant que", "avec plaisir", "volontiers",
	"assistant", "intelligence artificielle", " ia ", "comment puis-je", "je serais ravi", "absolument", "certainement", "je ne peux pas",
	"cher ami", "je suis là pour", "je suis la pour", "n'hésitez", "voici", "excellente question", "bonne journée", "modèle de langage",
	"je suis désolé", "je suis desole", "j'espère que", "j'espere que", "n'est-ce pas", "permettez", "pourriez-vous", "pouvez-vous", "ravi de",
	"d'accord, ", "bien entendu", "cordialement", "souhaitez-vous", "puis-je", "n'hésitez pas", "as an ai", "i am", "language model"]

const SHORTEN := {"je sais pas": "jsp", "je suis": "jsuis", "j'suis": "jsuis", "s'il te plaît": "stp", "s'il te plait": "stp", "c'est": "c",
	"quelqu'un": "qqn", "pourquoi": "pk", "beaucoup": "bcp", "aujourd'hui": "ajd", "toujours": "tjr", "attends": "att", "attend": "att",
	"parce que": "pcq", "maintenant": "mtn", "tout de suite": "tt de suite", "salut": "slt", "bonjour": "bjr", "mon dieu": "omg", "je vais": "jvais"}

## Filtre de sortie (§7) : minuscules, sans emoji, 1 à 8 mots, abréviations, fautes rares, sans point final ;
## tournure « IA » -> phrase toute faite. typo_chance = 0 pour un résultat déterministe (tests).
static func humanize(text: String, canned: String, typo_chance: float = 0.12) -> String:
	var t := " " + text.to_lower().replace("\n", " ").strip_edges() + " "
	for b: String in BLACKLIST:
		if t.contains(b):
			return canned
	var re := RegEx.new()
	re.compile("[^a-z0-9àâäéèêëîïôöùûüçœ' ?!.,:()@_\\-]")
	t = re.sub(t, "", true)
	t = t.replace("\"", "")
	for k: String in SHORTEN:
		t = t.replace(" " + k + " ", " " + String(SHORTEN[k]) + " ")
	t = t.strip_edges()
	var words := t.split(" ", false)
	if words.size() > 8:
		words = words.slice(0, 8)
	t = " ".join(words).trim_suffix(".").trim_suffix(",").strip_edges()
	if t.is_empty():
		return canned
	if t.length() > 5 and randf() < typo_chance:
		var i := 1 + randi() % (t.length() - 2)
		if t[i] != " " and t[i + 1] != " ":
			t = t.substr(0, i) + t[i + 1] + t[i] + t.substr(i + 2)
	return t


func _schedule(agent: SocialAgent, target: String, intent: String, v: Dictionary, delay: float) -> void:
	if not bool(v["valid"]):
		return
	if String(v["reply"]).is_empty() and String(v["action"]) == "none":
		_apply_effects(agent, target, intent, v)  # ignore vraiment, mais retient
		return
	var typing_time := (0.6 + String(v["reply"]).length() * 0.07 + rng.randf_range(0.2, 1.0)) * agent.trait_value("speed") + agent.ping / 1000.0
	var type_at := now + delay
	_scheduled.append({"pseudo": agent.pseudo, "target": target, "intent": intent, "v": v,
		"type_at": type_at, "show_at": type_at + typing_time, "typing": false})


func _deliver(agent: SocialAgent, s: Dictionary) -> void:
	var v: Dictionary = s["v"]
	var target := String(s["target"])
	var intent := String(s["intent"])
	_apply_effects(agent, target, intent, v)
	if not String(v["reply"]).is_empty():
		var shown := String(v["reply"])
		if target != PLAYER and not target.is_empty() and rng.randf() < 0.5:
			shown = "@%s %s" % [target, shown]
		_say(agent, shown, target)
	var act := String(v["action"])
	if act != "none":
		agent_action.emit(agent.pseudo, act, {"target": target, "item": String(v["item"]), "count": int(v["count"]),
			"give": v.get("give", {}), "want": v.get("want", {})})
	if intent == "chat_ai" and target != PLAYER and not target.is_empty():
		_ai_answer(agent, target)


## Applique affinité / mémoire / action validée. Les actions incohérentes sont corrigées.
func _apply_effects(agent: SocialAgent, target: String, intent: String, v: Dictionary) -> void:
	if target.is_empty():
		return
	var act := String(v["action"])
	if act == "accept_alliance" and (intent != "alliance" or not agent.can_accept_alliance(target)):
		act = "refuse" if intent == "alliance" else "none"
	if FRIENDLY_ACTIONS.has(act) and agent.get_status(target) == SocialAgent.Status.ENNEMI:
		act = "refuse"
	if act == "break_alliance" and agent.get_status(target) != SocialAgent.Status.ALLIE:
		act = "none" if not agent.relations.get(target, {}).get("betrayed", false) else act
	v["action"] = act
	agent.change_affinity(target, int(v["affinity"]))
	match act:
		"accept_alliance":
			agent.accept_alliance(target)
			agent.add_memory(target, "alliance acceptée")
			gossip(agent.pseudo, target, "%s s'est allié avec %s" % [_target_name(target), agent.pseudo], 2)
		"break_alliance":
			agent.break_alliance(target)
			agent.add_memory(target, "alliance rompue")
		"refuse":
			if intent == "alliance":
				agent.add_memory(target, "j'ai refusé une alliance")
	if not String(v["memory"]).is_empty():
		agent.add_memory(target, String(v["memory"]))
	relations_changed.emit(agent.pseudo)


# ---------------------------------------------------------------- commérages
## Les amis de `victim` apprennent ce que `about` a fait (rumeur + affinité).
func gossip(victim: String, about: String, text: String, delta: int) -> void:
	for other: SocialAgent in agents.values():
		if other.pseudo == victim or other.pseudo == about:
			continue
		if other.is_friend_of(victim) or other.get_affinity(victim) >= 30:
			other.add_rumor(about, victim, text, delta)
			var d := delta / 2
			if d == 0:
				d = signi(delta)
			other.change_affinity(about, d)
			relations_changed.emit(other.pseudo)


# ---------------------------------------------------------------- réactions toutes faites (sans LLM)
## Phrase du répertoire local avec probabilité p ; ne coûte aucun budget LLM.
func _react(agent: SocialAgent, say: String, target: String, p: float, extra_delay: float = 0.0) -> void:
	if agent == null or not agent.online or rng.randf() > p:
		return
	var v := {"valid": true, "reply": "", "action": "none", "item": "", "count": 0, "affinity": 0, "memory": "", "say": say}
	_mouth(agent, target, say, v, rng.randf_range(0.5, 2.0) + extra_delay, "", "", 0.0)


## Événement du jeu vu de tous : un ou deux joueurs en ligne réagissent (phrases toutes faites variées).
## kind : player_died, player_found, player_hit, danger. Limité à une réaction toutes les 6 s.
func world_event(kind: String, _data: Dictionary = {}) -> void:
	if now < _world_react_at:
		return
	var key: String = {"player_died": "react_death", "player_found": "react_found", "player_hit": "react_hit", "danger": "react_danger"}.get(kind, "")
	if key.is_empty():
		return
	var on := online_agents()
	if on.is_empty():
		return
	_world_react_at = now + 6.0
	var p: float = {"player_died": 0.8, "player_found": 0.4, "player_hit": 0.3, "danger": 0.5}[kind]
	var a: SocialAgent = on[rng.randi() % on.size()]
	_react(a, key, PLAYER if a.is_friend_of(PLAYER) else "", p)
	if on.size() >= 2 and rng.randf() < 0.25:
		var b: SocialAgent = on[rng.randi() % on.size()]
		if b != a:
			_react(b, key, "", 1.0, 1.5)


# ---------------------------------------------------------------- prises de parole spontanées
func _budget_ok() -> bool:
	return now >= _budget_ready_at and not voice.is_busy()


func _consume_budget() -> void:
	voice_budget_uses += 1
	_budget_ready_at = now + rng.randf_range(spontaneous_min_gap, spontaneous_max_gap)


## important : si le budget LLM est épuisé, on parle quand même avec les règles locales.
func _spontaneous(agent: SocialAgent, intent: String, target: String, important: bool, extra: Dictionary = {}) -> void:
	if not agent.online:
		return
	var budget := _budget_ok()
	if not budget and not important:
		return
	if budget:
		_consume_budget()
	var ctx := {"pseudo": agent.pseudo, "personality": agent.personality, "status": agent.get_status_name(target),
		"intent": intent, "target": target, "item": String(extra.get("item", ""))}
	var dec := voice.generate_fallback(ctx)  # règles : décident l'action
	var v := validate_response(dec)
	v["say"] = String(dec.get("say", intent))
	_mouth(agent, target, intent, v, rng.randf_range(0.5, 2.0), String(dec.get("reply", "")), "", mouth_spont_chance if budget else 0.0)


func _tick_ai_chat() -> void:
	if now < _next_ai_chat:
		return
	_next_ai_chat = now + rng.randf_range(30.0, 90.0)
	var on := online_agents()
	if on.is_empty() or not _budget_ok():
		return
	var a: SocialAgent = on[rng.randi() % on.size()]
	var target := ""
	if on.size() >= 2 and rng.randf() < 0.7:
		var others := on.filter(func(x: SocialAgent) -> bool: return x != a)
		target = (others[rng.randi() % others.size()] as SocialAgent).pseudo
	_consume_budget()
	var v := {"valid": true, "reply": "", "action": "none", "item": "", "count": 0, "affinity": 0, "memory": "",
		"say": "chat_ai_rival" if target != "" and a.get_affinity(target) < -20 else "chat_ai"}
	_mouth(a, target, "chat_ai", v, rng.randf_range(0.5, 2.0), "", "", mouth_spont_chance)


## Réponse courte d'IA à IA, par règles (n'utilise pas LLM).
func _ai_answer(from: SocialAgent, to_pseudo: String) -> void:
	var b := get_agent(to_pseudo)
	if b == null or not b.online or rng.randf() > 0.45:
		return
	var aff := b.get_affinity(from.pseudo)
	b.change_affinity(from.pseudo, 1 if aff >= 0 else -1)  # amitiés / rivalités qui se creusent
	var ctx := {"pseudo": b.pseudo, "personality": b.personality, "status": b.get_status_name(from.pseudo),
		"intent": "provoke" if aff < -20 else "generic", "target": from.pseudo}
	var v := validate_response(voice.generate_fallback(ctx))
	v["affinity"] = 0
	v["action"] = "none"
	_schedule(b, from.pseudo, "ai_answer", v, rng.randf_range(1.0, 4.0))


# ---------------------------------------------------------------- événements du jeu
## kind : gift, helped, block_broken, attacked, betrayal, danger, found, player_nearby, busy
## data : {from?: "player"|pseudo, item?, count?, what?, duration?}
func notify_event(pseudo: String, kind: String, data: Dictionary = {}) -> void:
	var agent := get_agent(pseudo)
	if agent == null:
		return
	var who := String(data.get("from", PLAYER))
	var who_name := _target_name(who)
	match kind:
		"gift":
			var count := maxi(1, int(data.get("count", 1)))
			var item := String(data.get("item", "objet"))
			agent.change_affinity(who, clampi(3 + count / 4, 3, 10))
			agent.nudge_mood(0.2)
			agent.add_memory(who, "m'a donné %d %s" % [count, item])
			gossip(pseudo, who, "%s a donné du %s à %s" % [who_name, item, pseudo], 4)
			if who == PLAYER:
				_spontaneous(agent, "gift", who, true)
		"helped":
			agent.change_affinity(who, 6)
			agent.add_memory(who, "m'a aidé%s" % (" : " + String(data.get("what", "")) if data.has("what") else ""))
			gossip(pseudo, who, "%s a aidé %s" % [who_name, pseudo], 3)
			if who == PLAYER:
				_spontaneous(agent, "gift", who, false)
		"block_broken":
			agent.change_affinity(who, -3 * maxi(1, int(data.get("count", 1))))
			agent.nudge_mood(-0.15)
			agent.add_memory(who, "a cassé des blocs près de ma base")
			if who == PLAYER:
				var hostile := agent.get_status(who) == SocialAgent.Status.ENNEMI or agent.get_affinity(who) < -20
				if hostile or rng.randf() < 0.5:
					_spontaneous(agent, "base_broken", who, true)
		"attacked":
			agent.change_affinity(who, -15)
			agent.nudge_mood(-0.4)
			agent.add_memory(who, "m'a attaqué")
			gossip(pseudo, who, "%s a attaqué %s" % [who_name, pseudo], -6)
			if who == PLAYER:
				_spontaneous(agent, "provoke" if agent.trait_value("spite") > 0.3 else "insult", who, true)
		"betrayal":
			agent.betray(who)
			agent.add_memory(who, "m'a trahi")
			gossip(pseudo, who, "%s a trahi %s" % [who_name, pseudo], -10)
			if who == PLAYER:
				_spontaneous(agent, "betrayal", who, true)
		"danger":
			agent.add_memory("self", "danger : %s" % String(data.get("what", "?")))
			if agent.is_friend_of(PLAYER):
				_spontaneous(agent, "danger", PLAYER, true)
			elif agent.get_status(PLAYER) == SocialAgent.Status.ENNEMI and rng.randf() < 0.3:
				_spontaneous(agent, "provoke", PLAYER, false)
		"found":
			var it := String(data.get("item", "minerai"))
			agent.nudge_mood(0.2)
			agent.add_memory("self", "j'ai trouvé %s" % it)
			if agent.is_friend_of(PLAYER):
				_spontaneous(agent, "found", PLAYER, false, {"item": it})
			elif agent.get_status(PLAYER) == SocialAgent.Status.ENNEMI:
				_spontaneous(agent, "provoke", PLAYER, false)
			else:
				_spontaneous(agent, "found", "", false, {"item": it})
		"player_nearby":
			agent.meet(PLAYER)
			if agent.get_status(PLAYER) == SocialAgent.Status.ENNEMI and rng.randf() < 0.3:
				_spontaneous(agent, "base_broken" if data.get("near_base", false) else "provoke", PLAYER, false)
		"busy":
			agent.set_busy(now, float(data.get("duration", 30.0)), String(data.get("what", "occupé")))
		_:
			if data.has("memory"):
				agent.add_memory(who, String(data["memory"]))
	relations_changed.emit(pseudo)


# ---------------------------------------------------------------- sauvegarde
func to_dict() -> Dictionary:
	var arr: Array = []
	for a: SocialAgent in agents.values():
		arr.append(a.to_dict())
	return {"version": 1, "now": now, "player_name": player_name, "agents": arr, "history": history.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	agents.clear()
	_scheduled.clear()
	_requests.clear()
	_leaving.clear()
	now = float(d.get("now", 0.0))
	player_name = String(d.get("player_name", player_name))
	for ad: Variant in d.get("agents", []):
		if ad is Dictionary:
			add_agent(SocialAgent.from_dict(ad))
	history.clear()
	for e: Variant in d.get("history", []):
		if e is Dictionary:
			history.append((e as Dictionary).duplicate())
	_budget_ready_at = now + 10.0
	_next_ai_chat = now + rng.randf_range(40.0, 90.0)
	# le jeu doit (re)créer les PNJ des agents en ligne
	_network_started = true
	for a: SocialAgent in agents.values():
		if a.online:
			agent_joined.emit.call_deferred(a.pseudo)
