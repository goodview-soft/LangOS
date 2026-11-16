class_name Brain extends RefCounted
## Cerveau moteur d'un joueur IA : logique pure, sans scène (voir docs/AI_DESIGN.md).
## Il décide de tout (buts, combat, alliances, trahison, communication). LLM ne fait que formuler.
##
## Usage : var b := Brain.new(seed) ; à chaque tick tactique (2-5 Hz) :
##   var d := b.decide(percept, now)   -> {opt, name, target, intents:[...], signals:[...]}
## Événements : b.on_event(kind, from_id, data, now)
##
## percept = {
##   hp: float 0-100, dmg: float, inv: {item_id: count}, inv_fill: 0-1, at_base: bool, base_built: 0-1,
##   ore_near: bool, danger: 0-1, in_safe_zone: bool,
##   others: [{id, visible, dist, hp, dmg, attacking_me, attacking: id|"", near_my_base, in_safe_zone, danger_near}]
## }

enum Opt {IDLE, MINE, EXPLORE, RETURN_BASE, BUILD, FLEE, HIDE, ATTACK, DEFEND, FOLLOW, SOCIALIZE, TRADE, VISIT}
const OPT_NAMES := ["traîne", "mine", "explore", "rentre", "construit", "fuit", "se cache", "attaque", "défend", "suit", "discute", "échange", "rend visite"]
enum Status {INCONNU, NEUTRE, AMI, ALLIE, ENNEMI}
const STATUS_NAMES := ["inconnu", "neutre", "ami", "allié", "ennemi"]

const HYSTERESIS := 0.12
const URGENT := 0.7

var rng := RandomNumberGenerator.new()
## traits 0-1
var t := {"courage": 0.5, "aggression": 0.5, "caution": 0.5, "greed": 0.5, "sociability": 0.5, "loyalty": 0.5, "honesty": 0.5}
var rel := {}          # id -> Dictionary (voir _rel)
var current := Opt.EXPLORE
var current_target := ""
var commit_until := 0.0
var noise := {}
var next_noise := 0.0
var session_end := 1800.0   # moment prévu de déconnexion (s)
var boredom := 0.0
var betray_plan := ""
var cooldowns := {}    # "intent:id" -> time
var next_trade_t := 0.0
var _sig := {}         # id -> {kind: [times]}
var _last := 0.0
var visit_cd := 0.0     # pas de nouvelle visite avant
var visit_until := 0.0  # reste avec le visité jusque-là

static var VALUE := {}

func _init(seed_v := 0, traits := {}) -> void:
	rng.seed = seed_v
	for k in t:
		t[k] = clampf(rng.randfn(0.5, 0.2), 0.05, 0.95)
	for k in traits:
		t[k] = traits[k]
	if VALUE.is_empty():
		VALUE = {World.DIRT: 1.0, World.STONE: 1.0, World.COAL: 3.0, World.COPPER: 4.0, World.IRON: 6.0,
			World.CRYSTAL: 10.0, World.TORCH: 1.0, World.MUSHROOM: 2.0}
	next_trade_t = rng.randf_range(40.0, 120.0)

# ------------------------------------------------------------------ relations
func _rel(id: String) -> Dictionary:
	if not rel.has(id):
		rel[id] = {"aff": 0.0, "met": false, "ally": false, "betrayed_me": false, "good_since": 0,
			"peace_until": 0.0, "last_hit": -99.0, "hurt_them": false, "follow": false,
			"last_pos": null, "last_seen": -99.0, "good_acts": 0}
	return rel[id]

func status_of(id: String) -> int:
	var r := _rel(id)
	if not r.met:
		return Status.INCONNU
	if r.betrayed_me or r.aff <= -40.0:
		return Status.ENNEMI
	if r.ally:
		return Status.ALLIE
	if r.aff >= 35.0:
		return Status.AMI
	return Status.NEUTRE

func _aff(id: String, d: float) -> void:
	var r := _rel(id)
	r.met = true
	r.aff = clampf(r.aff + d, -100.0, 100.0)
	if r.ally and r.aff < 10.0:
		r.ally = false

## Alliance seulement depuis AMI (proposée par l'un, acceptée par l'autre).
func accept_alliance(id: String) -> bool:
	if status_of(id) != Status.AMI:
		return false
	_rel(id).ally = true
	return true

func on_event(kind: String, id: String, data := {}, now := 0.0) -> void:
	var r := _rel(id)
	r.met = true
	match kind:
		"hit_me":
			r.last_hit = now
			if r.ally:   # trahison
				r.ally = false
				r.betrayed_me = true
				r.good_since = 0
			_aff(id, -8.0 - 6.0 * (1.0 - t.loyalty))
		"insult": _aff(id, -6.0)
		"broke_near_base": _aff(id, -3.0)
		"stole":
			r.betrayed_me = r.betrayed_me or r.aff > 20.0
			_aff(id, -20.0)
		"gift":
			_aff(id, 2.0 * float(data.get("value", 2.0)))
			_good(id)
		"helped":
			_aff(id, 6.0)
			_good(id)
		"signal_greet": _aff(id, 1.0)
		"signal_peace":
			if not r.betrayed_me:
				_aff(id, 3.0)
				r.peace_until = now + 60.0
			else:
				_good(id)
		"killed_me":
			_aff(id, -15.0)
		"seen":
			r.last_pos = data.get("pos")
			r.last_seen = now

func _good(id: String) -> void:
	var r := _rel(id)
	r.good_acts += 1
	if r.betrayed_me:
		r.good_since += 1
		# pardon possible : il faut plus de bons gestes si l'IA est rancunière (peu loyale envers les traîtres = peu indulgente)
		if r.good_since >= 3 + int(round(3.0 * (1.0 - t.honesty))):
			r.betrayed_me = false
			r.good_since = 0
			r.aff = maxf(r.aff, -10.0)

## Signes non verbaux : « crouch » x2 vite = paix, « jump » x2 vite = salut. Retourne l'événement reconnu ou "".
func observe_action(id: String, kind: String, now: float) -> String:
	if not _sig.has(id):
		_sig[id] = {}
	var h: Array = _sig[id].get(kind, [])
	h.append(now)
	while h.size() > 0 and now - float(h[0]) > 0.8:
		h.pop_front()
	_sig[id][kind] = h
	if h.size() >= 2:
		_sig[id][kind] = []
		var ev: String = "signal_peace" if kind == "crouch" else ("signal_greet" if kind == "jump" else "")
		if ev != "":
			on_event(ev, id, {}, now)
		return ev
	return ""

# ------------------------------------------------------------------ force et besoins
static func power(hp: float, dmg: float) -> float:
	return maxf(hp, 1.0) / 100.0 * maxf(dmg, 1.0)

func _odds(p: Dictionary, foe: Dictionary) -> float:
	var mine := power(p.hp, p.get("dmg", 10.0))
	var theirs := power(foe.hp, foe.get("dmg", 10.0))
	for o in p.others:
		if not o.visible or o.dist > 8.0 or o.id == foe.id:
			continue
		var s := status_of(o.id)
		if s == Status.ALLIE:
			mine += power(o.hp, o.get("dmg", 10.0)) * 0.8
		elif o.get("attacking", "") == "" and s == Status.ENNEMI and o.dist < 6.0:
			theirs += power(o.hp, o.get("dmg", 10.0)) * 0.5
	return mine / (mine + theirs)

func needs(inv: Dictionary, base_built: float) -> Dictionary:
	var n := {}
	if inv.get(World.TORCH, 0) < 6 and inv.get(World.COAL, 0) < 2:
		n[World.COAL] = 1.5
	if base_built < 1.0 and inv.get(World.STONE, 0) + inv.get(World.DIRT, 0) < 20:
		n[World.STONE] = 0.6
		n[World.DIRT] = 0.4
	n[World.CRYSTAL] = t.greed
	n[World.IRON] = 0.3 + t.greed * 0.5
	return n

func value_of(item: int, n: Dictionary) -> float:
	return float(VALUE.get(item, 1.0)) * (1.0 + float(n.get(item, 0.0)))

# ------------------------------------------------------------------ décision tactique (Utility AI)
func decide(p: Dictionary, now: float) -> Dictionary:
	var dt := clampf(now - _last, 0.0, 1.0)
	_last = now
	if now >= next_noise:
		next_noise = now + rng.randf_range(2.0, 6.0)
		for o in Opt.values():
			noise[o] = rng.randf_range(-0.06, 0.06)
	boredom = clampf(boredom + dt * 0.01, 0.0, 1.0)
	var hpf: float = p.hp / 100.0
	var opts := {}  # opt -> [score, target]
	opts[Opt.IDLE] = [0.06 + 0.25 * boredom * (1.0 - t.greed) * (0.3 if rng.randf() < 0.9 else 1.0), ""]
	opts[Opt.MINE] = [(0.55 if p.get("ore_near", false) else 0.0) * (1.0 - p.get("inv_fill", 0.0)) * (0.6 + 0.6 * t.greed), ""]
	opts[Opt.EXPLORE] = [(0.1 if p.get("ore_near", false) else 0.28 + 0.15 * (1.0 - t.caution)) * (1.0 - p.get("inv_fill", 0.0) * 0.6), ""]
	var fill: float = p.get("inv_fill", 0.0)
	opts[Opt.RETURN_BASE] = [0.0 if p.get("at_base", false) else fill * fill * 0.9 + (0.3 if hpf < 0.4 else 0.0), ""]
	var blocks: int = p.inv.get(World.STONE, 0) + p.inv.get(World.DIRT, 0)
	opts[Opt.BUILD] = [(1.0 - p.get("base_built", 0.0)) * 0.55 if p.get("at_base", false) and blocks >= 4 else 0.0, ""]
	# menaces
	var threat := 0.0
	var worst := ""
	var best_atk := 0.0
	var atk_t := ""
	var best_def := 0.0
	var def_t := ""
	for o in p.others:
		var r := _rel(o.id)
		if o.visible:
			r.met = true
			r.last_pos = o.get("pos", r.last_pos)
			r.last_seen = now
		if not o.visible:
			continue
		var s := status_of(o.id)
		var hostile: bool = o.get("attacking_me", false) or (s == Status.ENNEMI and o.dist < 8.0)
		var odds := _odds(p, o)
		if hostile:
			var th := clampf((1.0 - odds) * 1.6 * clampf(1.2 - o.dist / 10.0, 0.0, 1.0), 0.0, 1.0)
			if o.get("attacking_me", false):
				th = maxf(th, 0.35)
			if th > threat:
				threat = th
				worst = o.id
		var safe: bool = p.get("in_safe_zone", false) or o.get("in_safe_zone", false) or now < r.peace_until
		if safe:
			continue
		# attaque / riposte
		var want := 0.0
		if o.get("attacking_me", false):
			want = 0.55 + 0.35 * t.courage                     # se défendre
		elif s == Status.ENNEMI:
			want = 0.25 + 0.55 * t.aggression
		elif o.get("near_my_base", false) and s == Status.INCONNU:
			want = 0.6 * t.aggression * t.aggression
		if betray_plan == o.id and _betray_opportunity(p, o):
			want = maxf(want, 0.9)
		var sc: float = want * smoothstep(0.25, 0.75, odds) * (0.6 + 0.4 * t.courage)
		if sc > best_atk:
			best_atk = sc
			atk_t = o.id
		# défendre un allié attaqué
		var victim: String = o.get("attacking", "")
		if victim != "" and victim != "me" and status_of(victim) == Status.ALLIE:
			var ds: float = t.loyalty * 0.95 * smoothstep(0.2, 0.7, odds + 0.15) * (0.5 + 0.5 * t.courage)
			if ds > best_def:
				best_def = ds
				def_t = o.id
	var flee := clampf(threat * (1.4 - t.courage) * (1.6 - hpf) + p.get("danger", 0.0) * 0.8, 0.0, 1.0)
	opts[Opt.FLEE] = [flee, worst]
	opts[Opt.HIDE] = [flee * (0.4 + 0.7 * t.caution) * (1.2 if hpf < 0.35 else 0.55), worst]
	opts[Opt.ATTACK] = [best_atk, atk_t]
	opts[Opt.DEFEND] = [best_def, def_t]
	# suivre / socialiser
	var fol := ""
	var soc := 0.0
	var soc_t := ""
	for o in p.others:
		if not o.visible:
			continue
		var r := _rel(o.id)
		if r.follow and status_of(o.id) in [Status.AMI, Status.ALLIE]:
			fol = o.id
		var s := status_of(o.id)
		if s != Status.ENNEMI and o.dist < 7.0:
			var v: float = t.sociability * 0.3 * (0.5 + boredom) * (1.3 if s == Status.INCONNU else 1.0)
			if now < visit_until and o.id == "player":
				v = maxf(v, 0.65)  # en visite : il reste un moment avec le joueur
			if v > soc:
				soc = v
				soc_t = o.id
	opts[Opt.FOLLOW] = [0.5 + 0.2 * t.loyalty if fol != "" else 0.0, fol]
	opts[Opt.SOCIALIZE] = [soc, soc_t]
	opts[Opt.TRADE] = [0.0, ""]
	# rendre visite au joueur (comme un vrai joueur qui vient voir ce que tu fais) : sociable, un peu désœuvré, joueur connu et pas ennemi
	var visit := 0.0
	for o in p.others:
		if o.id == "player" and not p.get("in_safe_zone", false) and not o.get("in_safe_zone", false) and o.dist < 45.0 and o.dist > 7.0 \
				and status_of("player") != Status.ENNEMI and now >= visit_cd:
			visit = t.sociability * 0.6 * (0.3 + boredom) * (1.0 - p.get("inv_fill", 0.0)) * (1.25 if status_of("player") in [Status.AMI, Status.ALLIE] else 1.0)
	opts[Opt.VISIT] = [visit, "player" if visit > 0.0 else ""]
	# choix avec bruit + hystérésis + engagement minimal
	var best := current
	var best_s := -1.0
	for o in opts:
		var s: float = opts[o][0] + float(noise.get(o, 0.0))
		if o == current and opts[o][0] > 0.0:
			s += HYSTERESIS
		if s > best_s:
			best_s = s
			best = o
	var urgent: bool = best in [Opt.FLEE, Opt.HIDE, Opt.ATTACK, Opt.DEFEND] and opts[best][0] >= URGENT
	if best != current and (now >= commit_until or urgent):
		current = best
		commit_until = now + rng.randf_range(1.5, 4.0)
		if current == Opt.VISIT:
			visit_cd = now + rng.randf_range(150.0, 260.0)
			visit_until = now + rng.randf_range(35.0, 70.0)
			commit_until = now + 6.0
		if current == Opt.IDLE:
			boredom = 0.0
	current_target = opts[current][1]
	var d := {"opt": current, "name": OPT_NAMES[current], "target": current_target, "intents": [], "signals": []}
	_communicate(p, now, d, threat)
	return d

# ------------------------------------------------------------------ trahison (dilemme du prisonnier répété)
## EV > 0 => la trahison vaut le coup. gain = valeur du butin / avantage immédiat.
func betrayal_ev(id: String, p: Dictionary, foe: Dictionary, gain: float, now: float) -> float:
	var r := _rel(id)
	var minutes_left := maxf(session_end - now, 0.0) / 60.0
	var per_min: float = 1.5 + 0.4 * float(r.good_acts) + r.aff / 50.0
	var future: float = maxf(per_min, 0.0) * minutes_left * (0.4 + 1.2 * t.loyalty)
	var witnesses := 0
	var allies := 0
	for o in p.others:
		if o.id == id:
			continue
		if o.visible and o.dist < 12.0:
			witnesses += 1
		if status_of(o.id) in [Status.AMI, Status.ALLIE]:
			allies += 1
	var rep := 4.0 + 8.0 * allies * (1.0 if witnesses > 0 else 0.35)
	var retaliation := 10.0 * (1.0 - _odds(p, foe))
	var ev: float = gain * (0.5 + t.greed) - future - rep - retaliation - 18.0 * t.honesty
	if r.betrayed_me:
		ev += 25.0   # œil pour œil
	return ev

## À appeler de temps en temps (ex. toutes les 10-20 s) avec le butin estimé de chaque allié.
func consider_betrayal(id: String, p: Dictionary, foe: Dictionary, gain: float, now: float) -> bool:
	if status_of(id) != Status.ALLIE and not _rel(id).betrayed_me:
		return false
	if betrayal_ev(id, p, foe, gain, now) > 0.0:
		betray_plan = id    # on attend le bon moment (cible affaiblie ou isolée)
		return true
	if betray_plan == id:
		betray_plan = ""
	return false

func _betray_opportunity(p: Dictionary, foe: Dictionary) -> bool:
	var witnesses := 0
	for o in p.others:
		if o.id != foe.id and o.visible and o.dist < 12.0:
			witnesses += 1
	return (foe.hp < 50.0 or witnesses == 0) and _odds(p, foe) > 0.55

# ------------------------------------------------------------------ échanges
## give = ce qu'on me donne, want = ce qu'on me demande. -> {accept, counter: {give, want} | {}, reason}
func evaluate_offer(id: String, give: Dictionary, want: Dictionary, inv: Dictionary, base_built := 0.0) -> Dictionary:
	if status_of(id) == Status.ENNEMI:
		return {"accept": false, "counter": {}, "reason": "ennemi"}
	for it in want:
		if inv.get(it, 0) < want[it]:
			return {"accept": false, "counter": {}, "reason": "pas assez"}
	var n := needs(inv, base_built)
	var gain := 0.0
	var cost := 0.0
	for it in give:
		gain += value_of(it, n) * give[it]
	for it in want:
		cost += value_of(it, n) * want[it]
	var generosity := clampf(_rel(id).aff / 200.0, -0.2, 0.35)
	if gain >= cost * (1.0 - generosity):
		return {"accept": true, "counter": {}, "reason": "ok"}
	if gain >= cost * 0.45 and cost > 0.0:
		var ratio := gain / (cost * (1.0 - generosity))
		var w2 := {}
		for it in want:
			var c := int(floor(want[it] * ratio))
			if c > 0:
				w2[it] = c
		if not w2.is_empty():
			return {"accept": false, "counter": {"give": give, "want": w2}, "reason": "contre-offre"}
	return {"accept": false, "counter": {}, "reason": "arnaque"}

## Offre spontanée : un surplus contre un besoin. {} si rien d'intéressant.
func make_offer(inv: Dictionary, base_built := 0.0) -> Dictionary:
	var n := needs(inv, base_built)
	var need_it := -1
	var need_v := 0.0
	for it in n:
		if n[it] > need_v and inv.get(it, 0) < 10:
			need_v = n[it]
			need_it = it
	var sur_it := -1
	var sur_c := 0
	for it in inv:
		if it != need_it and inv[it] > 12 and float(n.get(it, 0.0)) < 0.5 and VALUE.has(it):
			if inv[it] > sur_c:
				sur_c = inv[it]
				sur_it = it
	if need_it < 0 or sur_it < 0:
		return {}
	var want_c := 3
	var give_c := clampi(int(ceil(value_of(need_it, {}) * want_c / value_of(sur_it, {}))), 1, sur_c / 2)
	return {"give": {sur_it: give_c}, "want": {need_it: want_c}}

# ------------------------------------------------------------------ intentions de communication
func _cool(key: String, now: float, dur: float) -> bool:
	if now < float(cooldowns.get(key, -1.0)):
		return false
	cooldowns[key] = now + dur * rng.randf_range(0.7, 1.5)
	return true

func _intent(d: Dictionary, intent: String, target: String, extra := {}) -> void:
	var it := {"intent": intent, "target": target, "tone": _tone(target)}
	it.merge(extra)
	d.intents.append(it)

func _tone(id: String) -> String:
	if id == "":
		return "neutre"
	match status_of(id):
		Status.ENNEMI: return "hostile"
		Status.AMI, Status.ALLIE: return "amical"
		Status.INCONNU: return "méfiant"
	return "neutre"

func _communicate(p: Dictionary, now: float, d: Dictionary, threat: float) -> void:
	for o in p.others:
		if not o.visible:
			continue
		var id: String = o.id
		var r := _rel(id)
		var s := status_of(id)
		# première rencontre : salut (saut x2) + parfois un mot
		if r.get("greeted", false) == false and o.dist < 10.0 and s != Status.ENNEMI:
			r.greeted = true
			d.signals.append({"signal": "jump_twice", "target": id})
			if rng.randf() < 0.35 + 0.5 * t.sociability:
				_intent(d, "greet", id)
		# intrus près de la base
		if o.get("near_my_base", false) and s in [Status.INCONNU, Status.ENNEMI, Status.NEUTRE] and t.aggression > 0.45 and _cool("threaten:" + id, now, 40.0):
			_intent(d, "threaten", id, {"reason": "base"})
		# un ennemi en vue : provocation
		if s == Status.ENNEMI and o.dist < 9.0 and t.aggression > 0.55 and _cool("taunt:" + id, now, 45.0) and rng.randf() < 0.4:
			_intent(d, "taunt", id)
		# prévenir un ami/allié d'un danger
		if s in [Status.AMI, Status.ALLIE] and o.get("danger_near", false) and _cool("warn:" + id, now, 25.0):
			_intent(d, "warn_danger", id)
		# alliance : sneak x2 + proposition
		if s == Status.AMI and r.aff > 60.0 and not r.ally and t.sociability > 0.35 and _cool("ally:" + id, now, 120.0):
			d.signals.append({"signal": "sneak_twice", "target": id})
			_intent(d, "invite_alliance", id)
		# réparer une relation qu'on valorise
		if r.hurt_them and r.aff > -30.0 and t.honesty > 0.4 and _cool("sorry:" + id, now, 60.0):
			r.hurt_them = false
			_intent(d, "apologize", id)
		# échange spontané
		if now >= next_trade_t and s in [Status.NEUTRE, Status.AMI, Status.ALLIE] and o.dist < 10.0:
			next_trade_t = now + rng.randf_range(60.0, 150.0)
			var off := make_offer(p.inv, p.get("base_built", 0.0))
			if not off.is_empty():
				_intent(d, "propose_trade", id, off)
	# en train de perdre un combat : appel à l'aide
	if threat > 0.55 and _cool("help", now, 20.0):
		var to := ""
		for o in p.others:
			if status_of(o.id) in [Status.AMI, Status.ALLIE]:
				to = o.id
				break
		_intent(d, "ask_help", to)

# ------------------------------------------------------------------ sauvegarde
func to_dict() -> Dictionary:
	return {"t": t.duplicate(), "rel": rel.duplicate(true), "session_end": session_end, "betray_plan": betray_plan}

func from_dict(d: Dictionary) -> void:
	for k in d.get("t", {}):
		t[k] = d.t[k]
	rel = (d.get("rel", {}) as Dictionary).duplicate(true)
	session_end = d.get("session_end", session_end)
	betray_plan = d.get("betray_plan", "")
