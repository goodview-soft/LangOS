class_name SocialAgent
extends RefCounted
## Profil d'un « faux vrai joueur » : pseudo, personnalité, relations, mémoire, humeur.

enum Status { INCONNU, NEUTRE, AMI, ALLIE, ENNEMI }
const STATUS_NAMES: Array[String] = ["INCONNU", "NEUTRE", "AMI", "ALLIE", "ENNEMI"]

const MAX_MEMORIES := 8
const MAX_RUMORS := 8
const FRIEND_THRESHOLD := 40
const ENEMY_THRESHOLD := -40
const ALLIANCE_MIN_AFFINITY := 25
const FORGIVE_THRESHOLD := 40

## talk : envie de répondre (0..1) ; speed : multiplicateur du délai de frappe ; spite : tendance à provoquer.
const PERSONALITIES := {
	"bavard": {"talk": 0.9, "speed": 0.8, "spite": 0.2},
	"raleur": {"talk": 0.65, "speed": 1.0, "spite": 0.6},
	"discret": {"talk": 0.35, "speed": 1.4, "spite": 0.1},
	"farceur": {"talk": 0.75, "speed": 0.9, "spite": 0.4},
	"serviable": {"talk": 0.8, "speed": 1.0, "spite": 0.05},
}

var pseudo: String = ""
var personality: String = "bavard"
var style: String = ""
var mood: float = 0.0            ## -1 (énervé) .. 1 (de bonne humeur)
var busy_until: float = 0.0      ## temps du hub jusqu'auquel l'agent est « occupé »
var busy_reason: String = ""
var online: bool = false
var ping: int = 45
var next_change_at: float = 0.0  ## prochaine connexion/déconnexion planifiée
## entité -> {affinity:int, met:bool, betrayed:bool, allied:bool}
var relations: Dictionary = {}
## entité -> Array[String]
var memories: Dictionary = {}
## Array de {about, from, text, delta}
var rumors: Array = []


func _init(p_pseudo: String = "", p_personality: String = "bavard", p_style: String = "") -> void:
	pseudo = p_pseudo
	personality = p_personality if PERSONALITIES.has(p_personality) else "bavard"
	style = p_style


func trait_value(key: String) -> float:
	var p: Dictionary = PERSONALITIES.get(personality, PERSONALITIES["bavard"])
	return float(p.get(key, 0.5))


# ---------------------------------------------------------------- relations
func _rel(entity: String) -> Dictionary:
	if not relations.has(entity):
		relations[entity] = {"affinity": 0, "met": false, "betrayed": false, "allied": false}
	return relations[entity]


func has_relation(entity: String) -> bool:
	return relations.has(entity)


func get_affinity(entity: String) -> int:
	if not relations.has(entity):
		return 0
	return int(relations[entity].get("affinity", 0))


func meet(entity: String) -> void:
	_rel(entity)["met"] = true


func set_affinity(entity: String, value: int) -> void:
	var r := _rel(entity)
	r["met"] = true
	r["affinity"] = clampi(value, -100, 100)
	_refresh(r)


func change_affinity(entity: String, delta: int) -> int:
	var r := _rel(entity)
	r["met"] = true
	r["affinity"] = clampi(int(r["affinity"]) + delta, -100, 100)
	_refresh(r)
	return int(r["affinity"])


func _refresh(r: Dictionary) -> void:
	var a: int = int(r["affinity"])
	# Une alliance ne survit pas à une affinité négative.
	if bool(r["allied"]) and a < 0:
		r["allied"] = false
	# Le pardon d'une trahison demande de vraiment remonter.
	if bool(r["betrayed"]) and a >= FORGIVE_THRESHOLD:
		r["betrayed"] = false


func get_status(entity: String) -> int:
	if not relations.has(entity):
		return Status.INCONNU
	var r: Dictionary = relations[entity]
	var a: int = int(r.get("affinity", 0))
	if bool(r.get("betrayed", false)):
		return Status.ENNEMI
	if bool(r.get("allied", false)):
		return Status.ALLIE
	if not bool(r.get("met", false)) and a == 0:
		return Status.INCONNU
	if a <= ENEMY_THRESHOLD:
		return Status.ENNEMI
	if a >= FRIEND_THRESHOLD:
		return Status.AMI
	return Status.NEUTRE


func get_status_name(entity: String) -> String:
	return STATUS_NAMES[get_status(entity)]


func is_friend_of(entity: String) -> bool:
	var s := get_status(entity)
	return s == Status.AMI or s == Status.ALLIE


## Événement marquant : trahison -> ENNEMI immédiatement.
func betray(entity: String) -> void:
	var r := _rel(entity)
	r["met"] = true
	r["betrayed"] = true
	r["allied"] = false
	r["affinity"] = mini(int(r["affinity"]) - 50, ENEMY_THRESHOLD)
	mood = clampf(mood - 0.5, -1.0, 1.0)


func can_accept_alliance(entity: String) -> bool:
	var r := _rel(entity)
	return not bool(r["betrayed"]) and int(r["affinity"]) >= ALLIANCE_MIN_AFFINITY


## Proposition d'alliance acceptée -> ALLIE. Renvoie false si refusée.
func accept_alliance(entity: String) -> bool:
	if not can_accept_alliance(entity):
		return false
	var r := _rel(entity)
	r["met"] = true
	r["allied"] = true
	return true


func break_alliance(entity: String) -> void:
	var r := _rel(entity)
	r["allied"] = false


# ---------------------------------------------------------------- mémoire
func add_memory(entity: String, text: String) -> void:
	var t := text.strip_edges().replace("\n", " ").left(90)
	if t.is_empty():
		return
	if not memories.has(entity):
		memories[entity] = []
	var arr: Array = memories[entity]
	arr.append(t)
	while arr.size() > MAX_MEMORIES:
		arr.pop_front()


func get_memories(entity: String) -> Array:
	return memories.get(entity, [])


func add_rumor(about: String, from: String, text: String, delta: int) -> void:
	rumors.append({"about": about, "from": from, "text": text.left(90), "delta": delta})
	while rumors.size() > MAX_RUMORS:
		rumors.pop_front()


func rumors_about(entity: String) -> Array:
	var out: Array = []
	for r: Dictionary in rumors:
		if String(r.get("about", "")) == entity:
			out.append(r)
	return out


# ---------------------------------------------------------------- humeur / occupation
func is_busy(now: float) -> bool:
	return now < busy_until


func set_busy(now: float, duration: float, reason: String) -> void:
	busy_until = now + duration
	busy_reason = reason


func nudge_mood(delta: float) -> void:
	mood = clampf(mood + delta, -1.0, 1.0)


func mood_label() -> String:
	if mood > 0.4:
		return "de bonne humeur"
	if mood < -0.4:
		return "énervé"
	return "normal"


# ---------------------------------------------------------------- sérialisation
func to_dict() -> Dictionary:
	return {
		"pseudo": pseudo, "personality": personality, "style": style,
		"mood": mood, "busy_until": busy_until, "busy_reason": busy_reason,
		"online": online, "ping": ping, "next_change_at": next_change_at,
		"relations": relations.duplicate(true), "memories": memories.duplicate(true),
		"rumors": rumors.duplicate(true),
	}


static func from_dict(d: Dictionary) -> SocialAgent:
	var a := SocialAgent.new(String(d.get("pseudo", "")), String(d.get("personality", "bavard")), String(d.get("style", "")))
	a.mood = float(d.get("mood", 0.0))
	a.busy_until = float(d.get("busy_until", 0.0))
	a.busy_reason = String(d.get("busy_reason", ""))
	a.online = bool(d.get("online", false))
	a.ping = int(d.get("ping", 45))
	a.next_change_at = float(d.get("next_change_at", 0.0))
	var rels: Dictionary = d.get("relations", {})
	for k: Variant in rels:
		var r: Dictionary = rels[k]
		a.relations[String(k)] = {
			"affinity": clampi(int(r.get("affinity", 0)), -100, 100),
			"met": bool(r.get("met", false)),
			"betrayed": bool(r.get("betrayed", false)),
			"allied": bool(r.get("allied", false)),
		}
	var mems: Dictionary = d.get("memories", {})
	for k: Variant in mems:
		var arr: Array = []
		for m: Variant in mems[k]:
			arr.append(String(m))
		a.memories[String(k)] = arr
	for r: Variant in d.get("rumors", []):
		if r is Dictionary:
			a.rumors.append((r as Dictionary).duplicate())
	return a
