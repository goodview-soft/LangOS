class_name RuleVoice
extends Node
## Voix des IA : 100 % locale, par règles (aucun appel réseau, aucune IA externe).
## Garde l'API de l'ancien client : request_chat() répond (asynchrone, au prochain frame) avec generate_fallback().

signal reply(request_id: int, data: Dictionary)

## Toujours en mode « règles » : jamais de modèle distant.
var force_fallback: bool = true
var available: bool = false
var active_model: String = ""
var switched_to_fallback: bool = false
var last_ms: int = -1
var _next_id: int = 1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func is_busy() -> bool:
	return false


func pending_count() -> int:
	return 0


## ctx sert aux règles : {pseudo, personality, status, intent, text, target}.
func request_chat(_system_prompt: String, _user_prompt: String, ctx: Dictionary = {}) -> int:
	var id := _next_id
	_next_id += 1
	var d := generate_fallback(ctx)
	d["_source"] = "rules"
	_emit.call_deferred(id, d)
	return id


func _emit(id: int, d: Dictionary) -> void:
	reply.emit(id, d)


## Parse tolérant : JSON direct, sinon premier bloc {...}. Renvoie null si invalide.
static func parse_json_text(text: String) -> Variant:
	var t := text.strip_edges()
	if t.is_empty():
		return null
	var json := JSON.new()
	if json.parse(t) == OK and json.data is Dictionary:
		return json.data
	var a := t.find("{")
	var b := t.rfind("}")
	if a >= 0 and b > a:
		var json2 := JSON.new()
		if json2.parse(t.substr(a, b - a + 1)) == OK and json2.data is Dictionary:
			return json2.data
	return null


# ---------------------------------------------------------------- repli par règles
const LINES := {
	"say_enrichir": ["je vais chercher du fer", "jme remets a miner", "y a du minerai par la", "jdescends miner un peu", "jvais faire un filon", "on mine on mine"],
	"say_equiper": ["plus de torches faut que jen fasse", "jrentre faire des torches", "il fait trop noir jvais mequiper", "jdois refaire le stock de torches"],
	"say_explorer": ["jvais explorer un peu", "jme balade voir ce qu'il y a", "jvais voir de lautre cote", "jvais regarder par la bas"],
	"say_socialiser": ["jvais voir qui est la", "tu fais quoi toi", "ca fait longtemps quon a pas parlé", "jvais faire un tour chez les autres"],
	"say_construire": ["jfinis ma base", "jconstruis un peu", "jvais ranger ma base", "encore quelques blocs et c fini"],
	"say_idle": ["lol", "bon", "hmm", "ca avance doucement", "jai les bras en compote", "il me faut un cafe", "mdr", "jm'ennuie un peu"],
	"greet": ["salut", "yo", "wesh", "slt ca va", "coucou", "hey", "re", "bjr"],
	"greet_enemy": ["koi encore", "tu veux quoi", "...", "ah c toi"],
	"question": ["jsp trop", "aucune idée mdr", "ptet en bas vers les grottes", "demande a qqn d'autre", "hmm bonne question", "chai pas jsuis en train de miner"],
	"compliment": ["merci c gentil", "haha merci", "trop cool merci", "ouais jsuis un pro", "mrc :)"],
	"insult": ["t'es sérieux là", "calme toi", "ok bah tchao", "pas besoin d'etre méchant", "toi même", "wow ok"],
	"insult_raleur": ["répète pour voir", "va miner ailleurs", "t'es relou", "nul toi même"],
	"follow": ["ok jte suis", "vas y jarrive", "ok go", "attend jte suis"],
	"follow_no": ["nan jsuis occupé", "pas mtn", "flemme dsl", "plus tard"],
	"stop": ["ok jarrete", "dac", "ça marche", "ok ok"],
	"give": ["tiens", "cadeau", "prends ça", "vas y jte file ça"],
	"give_no": ["nan c a moi", "jen ai pas assez dsl", "mdr non", "jsuis a sec"],
	"mine_with": ["ok on mine ensemble", "go on creuse", "vas y on fait un tunnel"],
	"build_with": ["ok on construit", "go jai des blocs", "trop bien on fait une base"],
	"trade": ["ok echange", "tu me donnes quoi en échange", "deal"],
	"alliance_yes": ["ok alliés", "deal on fait équipe", "ça marche on s'allie", "ok team"],
	"alliance_no": ["nan jte fais pas confiance", "bof pas pour linstant", "jsp on se connait pas trop", "non merci"],
	"betrayal": ["t'es un traitre", "jvais pas oublier ça", "c fini entre nous", "trahison..."],
	"danger": ["attention ya un truc dangereux là", "fais gaffe en bas", "attention!!", "recule ça craint"],
	"gift_thanks": ["merci beaucoup", "oh merci", "trop sympa", "nice merci", "jte revaudrai ça"],
	"base_warn_friend": ["hé c ma base ça", "touche pas a ma base stp", "euh tu casses ma base là"],
	"base_warn_enemy": ["dégage de ma zone", "touche encore a ma base et tu vas voir", "sors d'ici", "c ma zone ici"],
	"provoke": ["t'es nul a ce jeu", "lol t'as rien trouvé", "jai plus de minerai que toi", "pathétique"],
	"found": ["jai trouvé un filon", "oh des diamants", "trop bien jai trouvé un truc", "gros loot"],
	"chat_ai": ["qqn a du fer", "ya des grottes vers l'est", "jsuis full inventaire", "ce serveur est cool", "qqn veut miner", "lag de fou", "brb", "jai faim irl"],
	"chat_ai_rival": ["arrete de miner dans mon coin", "t'as encore pris mon filon", "jvais te battre au score"],
	"busy": ["2 sec", "jsuis occupé", "attends", "plus tard"],
	"threaten": ["dégage de ma zone", "casse toi d'ici", "touche pas a ma base", "bouge de là", "c ma zone ici"],
	"taunt": ["viens te battre", "lol t'as peur", "t'es nul", "ez", "approche pour voir"],
	"scared": ["calme toi", "ok ok", "jveux pas d'embrouille", "tranquille"],
	"invite_alliance": ["on fait team ?", "alliance ?", "tu veux faire équipe", "on s'allie ?"],
	"apologize": ["dsl pour tout a l'heure", "my bad", "pardon c'était pas voulu", "dsl jtai tapé"],
	"propose_trade": ["jte file {give} contre {want} ?", "échange {give} contre {want} ?", "{give} contre {want} ça te va"],
	"ask_help": ["aide moi", "help on m'attaque", "viens vite", "à l'aide !!"],
	"brag": ["ez", "gg ez", "trop facile", "jsuis trop fort"],
	"trade_yes": ["deal", "ok vas y", "marché conclu", "ok ça marche"],
	"trade_no": ["nan", "mdr non", "c une arnaque", "nan merci"],
	"trade_counter": ["plutot {give} contre {want}", "{give} contre {want} sinon rien", "{give} max pour {want}"],
	"trade_ask": ["tu me donnes koi en échange", "et moi j'ai koi", "contre koi"],
	"trade_fail": ["t'as pas assez", "t'as pas ce qu'il faut", "jai plus dsl"],
	"deal": ["ok c fait", "deal", "tiens", "voila"],
	"too_bad": ["ok tant pis", "dommage", "ok"],
	"apology_ok": ["ok c bon", "tkt", "ça va pour cette fois"],
	"apology_no": ["trop tard", "jte crois pas", "nan"],
	"killed": ["gg ez", "rip", "dans ta face", "next"],
	"died": ["nooon", "t'es sérieux", "jvais me venger", "mon stuff..."],
	"join_greet": ["salut", "yo", "re", "wsh", "slt", "salut tt le monde", "coucou", "yop"],
	"bye": ["bon jy vais", "bon j'y vais", "allez jy go", "bon jme casse", "a+", "bon jvais dormir", "jdois y aller", "bon bah salut", "g plus le temps, a+"],
	"react_death": ["rip", "ptdr", "aïe", "paix a ton ame", "gg", "outch", "t mort la", "mdr"],
	"react_found": ["nice", "gros", "cho", "t'as du bol", "ah ouais ?", "jalouuux", "gg"],
	"react_hit": ["aïe", "ça fait mal ça", "wow doucement", "ouch", "oh ça va"],
	"react_danger": ["fais gaffe", "ça sent mauvais", "att", "wow", "c chaud la"],
	"generic": ["ok", "mdr", "ah ouais", "grave", "lol", "jvois", "ptdr", "ouais", "tkt", "carrément", "ah bon", "ok cool"],
}

const ABBREV := {"je sais pas": "jsp", "s'il te plaît": "stp", "c'est": "c", "quoi": "koi", "pourquoi": "pk", "beaucoup": "bcp", "aujourd'hui": "ajd", "je suis": "jsuis", "toujours": "tjr", "quelqu'un": "qqn"}


func generate_fallback(ctx: Dictionary) -> Dictionary:
	var intent := String(ctx.get("intent", "generic"))
	var status := String(ctx.get("status", "NEUTRE"))
	var pers := String(ctx.get("personality", "bavard"))
	var friendly := status == "AMI" or status == "ALLIE"
	var hostile := status == "ENNEMI"
	var out := {"reply": "", "action": "none", "affinity": 0}
	var key := "generic"
	if intent == "say":  # bouche : le cerveau moteur a déjà décidé quoi dire
		key = String(ctx.get("say", "generic"))
		key = {"warn_danger": "danger", "alliance": "alliance_yes", "gift": "gift_thanks", "insult_raleur": "insult_raleur"}.get(key, key)
		if not LINES.has(key):
			key = "generic"
		intent = "_said"
	match intent:
		"greet":
			key = "greet_enemy" if hostile else "greet"
			out["affinity"] = 0 if hostile else 1
		"question":
			key = "question"
		"compliment":
			key = "compliment"
			out["affinity"] = 3
		"insult":
			key = "insult_raleur" if pers == "raleur" else "insult"
			out["affinity"] = -6
			out["memory"] = "m'a insulté"
		"request_follow":
			if hostile or (not friendly and _rng.randf() < 0.5):
				key = "follow_no"
			else:
				key = "follow"
				out["action"] = "follow"
		"request_stop":
			key = "stop"
			out["action"] = "stop_follow"
		"request_mine":
			key = "follow_no" if hostile else "mine_with"
			if not hostile:
				out["action"] = "mine_with"
		"request_build":
			key = "follow_no" if hostile else "build_with"
			if not hostile:
				out["action"] = "build_with"
		"request_give":
			if friendly or (pers == "serviable" and not hostile):
				key = "give"
				out["action"] = "give"
				out["item"] = String(ctx.get("item", "pierre"))
				out["count"] = 1 + _rng.randi() % 4
			else:
				key = "give_no"
		"request_trade":
			key = "give_no" if hostile else "trade"
			if not hostile:
				out["action"] = "trade"
		"alliance":
			if bool(ctx.get("can_ally", false)):
				key = "alliance_yes"
				out["action"] = "accept_alliance"
				out["affinity"] = 4
				out["memory"] = "on s'est alliés"
			else:
				key = "alliance_no"
				out["action"] = "refuse"
		"betrayal":
			key = "betrayal"
			out["action"] = "break_alliance"
			out["affinity"] = -10
			out["memory"] = "m'a trahi"
		"danger":
			key = "danger"
			out["action"] = "guard" if friendly else "none"
		"gift":
			key = "gift_thanks"
			out["affinity"] = 4
		"base_broken":
			key = "base_warn_enemy" if hostile else "base_warn_friend"
			out["action"] = "guard" if hostile else "none"
			out["affinity"] = -3
		"provoke":
			key = "provoke"
		"found":
			if friendly and _rng.randf() < 0.5:
				key = "give"
				out["action"] = "give"
				out["item"] = String(ctx.get("item", "minerai"))
				out["count"] = 1
			else:
				key = "found"
		"chat_ai":
			key = "chat_ai_rival" if hostile else "chat_ai"
		"busy":
			key = "busy"
		"threat":
			key = "taunt" if pers == "raleur" else "scared"
		"apology":
			key = "apology_no" if hostile else "apology_ok"
			out["affinity"] = 0 if hostile else 3
		"accept", "refuse":
			key = "too_bad" if intent == "refuse" else "generic"
		"_said":
			pass
		_:
			key = "generic"
	var bank: Array = LINES.get(key, LINES["generic"])
	var line := String(bank[_rng.randi() % bank.size()])
	line = line.replace("{give}", String(ctx.get("give", ""))).replace("{want}", String(ctx.get("want", ""))) \
		.replace("{item}", String(ctx.get("item", ""))).replace("{count}", str(ctx.get("count", "")))
	out["say"] = key
	if pers == "farceur" and _rng.randf() < 0.4:
		line += " " + ["mdr", "xD", "ptdr", "lol"][_rng.randi() % 4]
	elif pers == "bavard" and _rng.randf() < 0.3:
		line += " " + LINES["generic"][_rng.randi() % LINES["generic"].size()]
	elif pers == "discret" and line.length() > 12 and _rng.randf() < 0.5:
		line = ["ok", "mh", "ouais", "..."][_rng.randi() % 4]
	out["reply"] = casualize(line)
	return out


## Style « joueur » : minuscules, abréviations, pas de point final, parfois une faute.
func casualize(text: String) -> String:
	var t := text.to_lower()
	for k: String in ABBREV:
		t = t.replace(k, String(ABBREV[k]))
	t = t.trim_suffix(".")
	if t.length() > 5 and _rng.randf() < 0.15:
		var i := 1 + _rng.randi() % (t.length() - 2)
		if t[i] != " " and t[i + 1] != " ":
			t = t.substr(0, i) + t[i + 1] + t[i] + t.substr(i + 2)
	return t
