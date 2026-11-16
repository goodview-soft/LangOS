class_name Gear extends RefCounted
## Équipement PvP (idées reprises d'afterworld-game, version Deep Miner) :
## armures par pièces et par paliers, enchantements de pioche, pomme dorée, plafonds PvP.
## État du joueur : {"armor": [t,t,t,t] (-1 = rien, 0 cuivre, 1 fer, 2 cristal), "sharp": 0-3, "kb": 0-2, "thorns": 0-1, "apples": n}

const SLOT_NAMES := ["Casque", "Plastron", "Jambières", "Bottes"]
const SLOT_COST := [3, 5, 4, 2]  # minerai par pièce
const TIER_NAMES := ["cuivre", "fer", "cristal"]
const TIER_ORE := [World.COPPER, World.IRON, World.CRYSTAL]
const PIECE_PCT := [0.04, 0.065, 0.09]  # réduction par pièce : jeu complet = 16 % / 26 % / 36 %
const ARMOR_CAP := 0.35  # plafond de réduction
const SHARP_PCT := [0.0, 0.15, 0.30, 0.45]
const DMG_CAP := 0.40  # plafond de bonus de dégâts
const KB_MULT := [0.8, 1.2, 1.6]  # recul de base 0,8 (PvP : on reste à portée pour riposter)
const THORNS_DMG := 3.0
const TAG_TIME := 15.0  # « en combat » après un coup
const APPLE_USE := 2.0
const APPLE_CD := 4.0
const APPLE_HEAL := 60.0
const APPLE_ABS := 20.0
const APPLE_REGEN := 2.5  # PV/s pendant 8 s
const APPLE_REGEN_T := 8.0
const HIT_IFRAMES := 0.25  # invulnérabilité vis-à-vis du MÊME attaquant
const SWORD_NAMES := ["aucune", "cuivre", "fer", "cristal"]
const SWORD_ORE := [World.COPPER, World.IRON, World.CRYSTAL]
const SWORD_COST := [4, 5, 4]  # minerai par palier (+ 1 charbon)
const SWORD_MULT := [1.0, 1.35, 1.7, 2.0]  # dégâts x
const SWORD_REACH := 0.8  # portée en plus
const SWORD_CD := 0.75  # le coup revient plus vite (x délai de la pioche)
const PVP_MULT := 0.8  # PvP entre joueurs : dégâts x0,8 (les mineurs IA restent à 1,0)

static func fresh() -> Dictionary:
	return {"armor": [-1, -1, -1, -1], "sharp": 0, "kb": 0, "thorns": 0, "apples": 0, "sword": 1}  # on commence avec une épée de cuivre

static func sanitize(g: Variant) -> Dictionary:
	var out := fresh()
	if g is Dictionary:
		var a: Variant = g.get("armor", [])
		if a is Array and (a as Array).size() == 4:
			for i in 4:
				out.armor[i] = clampi(int(a[i]), -1, 2)
		out.sharp = clampi(int(g.get("sharp", 0)), 0, 3)
		out.kb = clampi(int(g.get("kb", 0)), 0, 2)
		out.thorns = clampi(int(g.get("thorns", 0)), 0, 1)
		out.apples = clampi(int(g.get("apples", 0)), 0, 99)
		out.sword = clampi(int(g.get("sword", 1)), 0, 3)
	return out

static func armor_pct(g: Dictionary) -> float:
	var s := 0.0
	for t in g.armor:
		if int(t) >= 0:
			s += PIECE_PCT[int(t)]
	return minf(s, ARMOR_CAP)

## with_sword : false = pioche en main (l'épée ne compte que quand elle est sélectionnée dans la barre).
static func dmg_mult(g: Dictionary, with_sword := true) -> float:
	return (1.0 + minf(SHARP_PCT[int(g.sharp)], DMG_CAP)) * (SWORD_MULT[int(g.get("sword", 0))] if with_sword else 1.0)

## Recettes d'équipement (affichées après les recettes classiques, à la fonderie).
## kind : "armor" (idx = emplacement), "sharp", "kb", "thorns", "apple".
static func recipes(g: Dictionary) -> Array:
	var r: Array = []
	var cur_pct := armor_pct(g)
	for i in 4:
		var cur: int = g.armor[i]
		var nxt := cur + 1
		var maxed := nxt > 2
		var worn: String = "rien" if cur < 0 else TIER_NAMES[cur]
		var tip := ""
		if maxed:
			tip = "%s : palier maximum (cristal)." % SLOT_NAMES[i]
		else:
			var after := minf(cur_pct - (PIECE_PCT[cur] if cur >= 0 else 0.0) + PIECE_PCT[nxt], ARMOR_CAP)
			tip = "%s en %s : réduit les dégâts reçus de %d %% (porté : %s).\nRéduction totale : %d %% -> %d %% (plafond %d %%)." % [SLOT_NAMES[i], TIER_NAMES[nxt], int(PIECE_PCT[nxt] * 100.0), worn, int(cur_pct * 100.0), int(after * 100.0), int(ARMOR_CAP * 100.0)]
		r.append({"name": "%s (%s)" % [SLOT_NAMES[i], "complet" if maxed else TIER_NAMES[nxt]], "cost": {} if maxed else {TIER_ORE[nxt]: SLOT_COST[i], World.COAL: 1},
			"out": {}, "station": "forge", "gear": ["armor", i], "maxed": maxed, "info": "-%d %%" % int(PIECE_PCT[mini(nxt, 2)] * 100.0), "tip": tip})
	var sw: int = int(g.get("sword", 0))
	r.append({"name": "Épée (%s)" % ("max" if sw >= 3 else SWORD_NAMES[sw + 1]), "cost": {} if sw >= 3 else {SWORD_ORE[sw]: SWORD_COST[sw], World.COAL: 1}, "out": {}, "station": "forge", "gear": ["sword", 0], "maxed": sw >= 3,
		"info": "dégâts x%s" % String.num(SWORD_MULT[mini(sw + 1, 3)], 2),
		"tip": "Épée en %s : dégâts x%s (actuel x%s), portée +%s bloc, coup %d %% plus rapide. Elle sort toute seule quand tu frappes un joueur, un mineur ou un zombie ; la pioche reste pour creuser." % [SWORD_NAMES[mini(sw + 1, 3)], String.num(SWORD_MULT[mini(sw + 1, 3)], 2), String.num(SWORD_MULT[sw], 2), String.num(SWORD_REACH, 1), int((1.0 - SWORD_CD) * 100.0)]})
	var s: int = g.sharp
	r.append({"name": "Pioche tranchante %s" % ["I", "II", "III", "max"][s], "cost": {} if s >= 3 else {World.CRYSTAL: 3 * (s + 1)}, "out": {}, "station": "forge", "gear": ["sharp", 0], "maxed": s >= 3, "info": "+%d %% dégâts" % int(SHARP_PCT[mini(s + 1, 3)] * 100.0),
		"tip": "Pioche tranchante : +%d %% de dégâts aux ennemis et aux joueurs (actuel : +%d %%, plafond +%d %%)." % [int(SHARP_PCT[mini(s + 1, 3)] * 100.0), int(SHARP_PCT[s] * 100.0), int(DMG_CAP * 100.0)]})
	var k: int = g.kb
	r.append({"name": "Pioche recul %s" % ["I", "II", "max"][k], "cost": {} if k >= 2 else {World.CRYSTAL: 2 * (k + 1)}, "out": {}, "station": "forge", "gear": ["kb", 0], "maxed": k >= 2, "info": "recul accru",
		"tip": "Pioche recul : repousse plus fort les ennemis touchés (x%s -> x%s), pour garder de la distance." % [String.num(KB_MULT[k], 1), String.num(KB_MULT[mini(k + 1, 2)], 1)]})
	r.append({"name": "Épines I" if int(g.thorns) == 0 else "Épines (max)", "cost": {} if int(g.thorns) >= 1 else {World.CRYSTAL: 4, World.IRON: 2}, "out": {}, "station": "forge", "gear": ["thorns", 0], "maxed": int(g.thorns) >= 1, "info": "renvoie %d" % int(THORNS_DMG),
		"tip": "Épines : renvoie %d dégâts à quiconque te frappe au corps à corps." % int(THORNS_DMG)})
	r.append({"name": "Pomme dorée (N)", "cost": {World.CRYSTAL: 3, World.MUSHROOM: 2}, "out": {}, "station": "", "gear": ["apple", 0], "maxed": int(g.apples) >= 99, "info": "soin +%d" % int(APPLE_HEAL),
		"tip": "Pomme dorée (touche N, %s s pour la manger) :\n- soigne %d PV d'un coup\n- régénère %s PV/s pendant %d s\n- absorbe %d dégâts\nDélai entre deux pommes : %d s.  Tu en as %d." % [String.num(APPLE_USE, 0), int(APPLE_HEAL), String.num(APPLE_REGEN, 1), int(APPLE_REGEN_T), int(APPLE_ABS), int(APPLE_CD), int(g.apples)]})
	return r

## Applique la fabrication d'une recette d'équipement à l'état g (le coût est payé par l'appelant).
static func apply(g: Dictionary, gear: Array) -> void:
	match gear[0]:
		"armor":
			g.armor[int(gear[1])] = int(g.armor[int(gear[1])]) + 1
		"apple":
			g.apples = int(g.apples) + 1
		_:
			g[gear[0]] = int(g[gear[0]]) + 1
