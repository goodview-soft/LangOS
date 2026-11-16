class_name Strategist
extends Node
## Couche « raisonnement » (LLM, rare) : toutes les ~2 min, UNE IA à la fois reçoit un résumé de sa situation et choisit un but dans
## une liste fermée + une phrase d'intention (dite au chat parfois). Le moteur local exécute ; sans LLM, rien ne change.
## Réutilise le client LLM du SocialHub (une seule requête à la fois, partagée avec le chat).

const GOALS := ["enrichir", "equiper", "explorer", "socialiser", "construire"]
const GAP_MIN := 90.0
const GAP_MAX := 150.0

var main: Node
var _t := 60.0
var _chat_t := 25.0   # bavardage spontané (sans LLM) : une IA dit ce qu'elle fait, de temps en temps
var _rr := 0
var _pending := {}   # id requête -> nom du mineur
var _rng := RandomNumberGenerator.new()

func setup(m: Node) -> void:
	main = m
	_rng.randomize()
	var o = main.social.voice
	if o and not o.reply.is_connected(_on_reply):
		o.reply.connect(_on_reply)

func _process(dt: float) -> void:
	if main == null or main.testing or main.social == null:
		return
	_chat_t -= dt
	if _chat_t <= 0.0:
		_chat_t = _rng.randf_range(30.0, 75.0)
		_ambient()
	_t -= dt
	if _t > 0.0:
		return
	_t = _rng.randf_range(GAP_MIN, GAP_MAX)
	var o: RuleVoice = main.social.voice
	if o == null or not o.available or o.force_fallback or o.is_busy():
		return
	var cands: Array = []
	for mi in main.miners:
		if mi.active and mi.get("zid") == null and mi.life != null:
			cands.append(mi)
	if cands.is_empty():
		return
	_rr = (_rr + 1) % cands.size()
	var mi: Miner = cands[_rr]
	var id := o.request_chat(_system(), _situation(mi), {"intent": "strategy"})
	_pending[id] = mi.mname

func _system() -> String:
	return "Tu es un mineur dans un jeu voxel, joueur humain crédible. Tu choisis ton prochain objectif selon ta situation. " \
		+ "Réponds UNIQUEMENT en JSON : {\"goal\": \"enrichir|equiper|explorer|socialiser|construire\", \"ore\": \"charbon|fer|cuivre|cristal\", \"say\": \"phrase très courte, naturelle, en français, à la première personne\"}. " \
		+ "Règles : sans torches, équipe-toi ; pas de plan de base -> pas de construire ; varie ce que tu fais."

func _situation(mi: Miner) -> String:
	var st: Dictionary = main.chests.get(mi.chest, {})
	var tot := func(id: int) -> int: return int(mi.inv.get(id, 0)) + int(st.get(id, 0))
	var t: Dictionary = mi.brain.t
	var th := ""
	if not mi.life.thoughts.is_empty():
		th = " Pensée récente : " + str(mi.life.thoughts[-1]) + "."
	return "Je m'appelle %s, personnalité %s (courage %.1f, cupidité %.1f, sociabilité %.1f). PV %d%%. Torches %d, charbon %d, fer %d, cristal %d. Base %d%% construite. But actuel : %s.%s Quel est mon prochain but ?" % [
		mi.mname, mi.personality, t.courage, t.greed, t.sociability, int(100.0 * mi.health / maxf(mi.max_hp, 1.0)),
		tot.call(World.TORCH), tot.call(World.COAL), tot.call(World.IRON), tot.call(World.CRYSTAL),
		int(100.0 * (1.0 - float(mi.tasks.size()) / float(maxi(mi.base_total, 1)))), mi.life.goal, th]

func _on_reply(id: int, d: Dictionary) -> void:
	if not _pending.has(id):
		return
	var who: String = _pending[id]
	_pending.erase(id)
	if String(d.get("_source", "")) != "voice":
		return
	var mi: Miner = null
	for x in main.miners:
		if x.mname == who:
			mi = x
	if mi == null or not mi.active or mi.life == null:
		return
	var g := String(d.get("goal", "")).to_lower().strip_edges()
	if not (g in GOALS):
		return
	if mi.life.force(mi, main, g, String(d.get("ore", "")), main.game_t):
		mi.life.thoughts.append("Réflexion : %s" % g)
		var say := String(d.get("say", "")).strip_edges().substr(0, 80)
		var a: SocialAgent = main.social.get_agent(who)
		if say != "" and a != null and a.online and _rng.randf() < 0.5 * mi.brain.t.sociability + 0.15:
			main.social._say(a, say, "")

## Une IA en ligne dit à voix haute ce qu'elle fait (phrases toutes faites selon son but ; plus bavarde = plus souvent).
func _ambient() -> void:
	var cands: Array = []
	for mi in main.miners:
		if mi.active and mi.get("zid") == null and mi.life != null:
			var a: SocialAgent = main.social.get_agent(mi.mname)
			if a != null and a.online and _rng.randf() < 0.25 + 0.6 * mi.brain.t.sociability:
				cands.append(mi)
	if cands.is_empty():
		return
	var mi: Miner = cands[_rng.randi() % cands.size()]
	var key := "say_" + mi.life.goal if mi.life.goal != "" and _rng.randf() < 0.75 else "say_idle"
	main.social._react(main.social.get_agent(mi.mname), key, "", 1.0)
