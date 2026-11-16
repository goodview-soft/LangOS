class_name Skills
extends RefCounted
## Bibliothèque de compétences des IA (idée de Voyager) : chaque IA mémorise, par compétence nommée, ses réussites et ses échecs.
## Un échec répété allonge le délai avant le prochain essai (recul exponentiel) ; une réussite le raccourcit.
## La mémoire est un Dictionary simple (sauvegardable) : {nom: {ok, fail, streak, t, until, dur}}.

const NAMES := ["fonder_base", "annexe", "cacher_butin", "visiter_cache", "carriere", "refuge", "eclairer"]
const BACKOFF := 45.0  # secondes après le 1er échec, doublé à chaque échec de suite
const BACKOFF_MAX := 900.0

static func new_mem() -> Dictionary:
	var m := {}
	for n in NAMES:
		m[n] = {"ok": 0, "fail": 0, "streak": 0, "t": -999.0, "until": 0.0, "dur": 0.0}
	return m

static func _e(mem: Dictionary, name: String) -> Dictionary:
	if not mem.has(name):
		mem[name] = {"ok": 0, "fail": 0, "streak": 0, "t": -999.0, "until": 0.0, "dur": 0.0}
	return mem[name]

## Peut-on (re)tenter cette compétence maintenant ?
static func ready(mem: Dictionary, name: String, now: float) -> bool:
	return now >= float(_e(mem, name).until)

static func start(mem: Dictionary, name: String, now: float) -> void:
	_e(mem, name).t = now

static func success(mem: Dictionary, name: String, now: float, cooldown := 0.0) -> void:
	var e := _e(mem, name)
	e.ok += 1
	e.streak = 0
	var d: float = maxf(now - float(e.t), 0.0)
	e.dur = d if e.dur <= 0.0 else lerpf(e.dur, d, 0.4)
	e.until = now + cooldown

static func failure(mem: Dictionary, name: String, now: float) -> void:
	var e := _e(mem, name)
	e.fail += 1
	e.streak += 1
	e.until = now + minf(BACKOFF * pow(2.0, float(e.streak - 1)), BACKOFF_MAX)

## Part de réussites (0,5 sans historique) : sert à choisir entre deux options.
static func rate(mem: Dictionary, name: String) -> float:
	var e := _e(mem, name)
	var n: int = e.ok + e.fail
	return 0.5 if n == 0 else float(e.ok) / float(n)

static func summary(mem: Dictionary) -> String:
	var parts: Array = []
	for n in mem:
		var e: Dictionary = mem[n]
		if e.ok + e.fail > 0:
			parts.append("%s %d/%d" % [n, e.ok, e.ok + e.fail])
	return ", ".join(parts)
