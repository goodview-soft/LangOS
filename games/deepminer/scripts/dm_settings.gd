class_name DMSettings
## Réglages statiques (ex-autoload "Settings") : apparence du mineur + options dans user://deepminer/settings.cfg.

const PATH := "user://deepminer/settings.cfg"

const SKINS := ["#f0b98a", "#e0a070", "#c68650", "#9a6440", "#6e452a", "#f8d0b0", "#7fae4a", "#4f8a3a", "#8a9ab0", "#c87a6a"]
const COLORS := ["#ffd02a", "#c8452f", "#3d5fa8", "#3f8a4a", "#e07a20", "#8a4ab0", "#d8d8e0", "#3a3a44", "#6b4220", "#e070a0"]
const HAIR_COLORS := ["#3a2414", "#6b4220", "#c8941a", "#a8361e", "#d8d8e0", "#1a1410"]
const HAIRS := ["Aucun", "Courts", "Longs"]
const BEARDS := ["Aucune", "Moustache", "Barbe"]
const BODIES := ["Humain", "Nain", "Géant", "Gobelin", "Robot"]
## Statistiques par espece (meme ordre que BODIES). hh/hw = taille (dessin) ; chh/chw (facultatif) = capsule de collision plus petite (le nain passe dans un passage d'un demi-bloc), mine = vitesse de minage.
const SPECIES := [
	{"hh": 1.7, "hw": 0.3, "speed": 5.0, "jump": 9.6, "hp": 100.0, "mine": 1.0, "reach": 5.5, "lamp": 10.0, "lava": 1.0, "torch": 6, "sinks": false,
		"desc": "Polyvalent : 6 torches par charbon au lieu de 4."},
	{"hh": 0.9, "hw": 0.3, "chh": 0.48, "chw": 0.24, "speed": 4.2, "jump": 7.6, "hp": 130.0, "mine": 1.3, "reach": 4.5, "lamp": 8.0, "lava": 1.0, "torch": 4, "sinks": false, "climb": true,
		"desc": "1 bloc de haut : passe partout, et s'agrippe aux murs (Espace vers le mur, 5 s). Mine très vite et encaisse bien, mais lent et saute peu."},
	{"hh": 2.8, "hw": 0.42, "speed": 5.2, "jump": 11.5, "bigjump": true, "hp": 220.0, "mine": 1.2, "reach": 8.0, "lamp": 12.0, "lava": 0.5, "torch": 4, "sinks": false,
		"desc": "3 blocs de haut : très résistant, longue portée, saute haut. Mais coincé dans les passages bas."},
	{"hh": 1.7, "hw": 0.28, "speed": 6.8, "jump": 11.0, "hp": 70.0, "mine": 0.9, "reach": 5.0, "lamp": 16.0, "lava": 1.0, "torch": 4, "sinks": false, "climb": true,
		"desc": "Rapide et agile, s'agrippe aux murs (Espace vers le mur, 5 s), voit loin dans le noir. Mais fragile et mine un peu moins vite."},
	{"hh": 1.7, "hw": 0.3, "speed": 4.6, "jump": 8.5, "hp": 110.0, "mine": 1.4, "reach": 6.0, "lamp": 13.0, "lava": 0.15, "torch": 4, "sinks": true,
		"desc": "Presque insensible à la lave et bon mineur. Mais lent, et il coule dans l'eau."},
]

## Capacité spéciale (touche G), même ordre que BODIES. cd = recharge en secondes.
const ABILITIES := [
	{"id": "heal", "name": "Second souffle", "cd": 25.0, "desc": "soigne 50 PV en 3 s et accélère un peu"},
	{"id": "quake", "name": "Frappe sismique", "cd": 15.0, "desc": "brise d'un coup les blocs autour de lui (3x3)"},
	{"id": "charge", "name": "Charge", "cd": 12.0, "desc": "fonce et défonce tout sur sa route"},
	{"id": "sniff", "name": "Flair", "cd": 25.0, "desc": "révèle les minerais proches à travers la roche"},
	{"id": "overheat", "name": "Surchauffe", "cd": 20.0, "desc": "minage x2 pendant 6 s, mais coûte des PV"},
]

## Design FIXE des IA par espèce (même ordre que BODIES) : seule la couleur d'identité (casque, chemise) change d'une IA à l'autre.
const AI_DESIGNS := [
	{"skin": "#f0b98a", "overalls": "#3d5fa8", "boots": "#6b4220", "hair": 1, "hair_color": "#3a2414", "beard": 0},  # humain
	{"skin": "#e0a070", "overalls": "#6b4220", "boots": "#4f3017", "hair": 0, "hair_color": "#a8361e", "beard": 0},  # nain (barbe rousse)
	{"skin": "#9a6440", "overalls": "#3a3a44", "boots": "#3a2414", "hair": 1, "hair_color": "#1a1410", "beard": 2},  # géant
	{"skin": "#7fae4a", "overalls": "#6b4220", "boots": "#3a2414", "hair": 0, "hair_color": "#3a2414", "beard": 0},  # gobelin vert
	{"skin": "#8a9ab0", "overalls": "#3a3a44", "boots": "#3a3a44", "hair": 0, "hair_color": "#1a1410", "beard": 0},  # robot (métal teinté par l'identité)
]

## Apparence complète d'une IA : design de l'espèce + couleur d'identité.
static func ai_look(species: int, id_color: Color) -> Dictionary:
	var sp := clampi(species, 0, AI_DESIGNS.size() - 1)
	var d: Dictionary = AI_DESIGNS[sp].duplicate()
	d["body"] = sp
	d["helmet"] = id_color
	d["shirt"] = id_color.darkened(0.35).lerp(Color(0.25, 0.3, 0.45), 0.35)
	return d

## Capacité du sac (même ordre que BODIES), en unités de Carry : large, pour ne pas revenir au camp toutes les 5 minutes.
const CARRY := [300.0, 320.0, 600.0, 220.0, 400.0]

static func carry_cap() -> float:
	return CARRY[clampi(int(look.get("body", 0)), 0, CARRY.size() - 1)]

static func ability() -> Dictionary:
	return ABILITIES[clampi(int(look.get("body", 0)), 0, ABILITIES.size() - 1)]

static func species() -> Dictionary:
	return SPECIES[clampi(int(look.get("body", 0)), 0, SPECIES.size() - 1)]

const DEFAULT_LOOK := {
	"name": "Mineur",
	"body": 0,
	"skin": "#f0b98a",
	"helmet": "#ffd02a",
	"shirt": "#c8452f",
	"overalls": "#3d5fa8",
	"boots": "#6b4220",
	"hair": 1,
	"hair_color": "#3a2414",
	"beard": 0,
}

static var look := DEFAULT_LOOK.duplicate()
static var fullscreen := false
static var vsync := true
static var volume := 0.8
static var hd := true  # rendu 3D en haute résolution (interface 640x360 mise à l'échelle) ; /hd off = pixels gros
static var tordu := 0.12  # déformation des sommets en 3D (/tordu 0-0.3) : 0 = blocs droits, 0.12 = un peu « crochu »
static var chat_bots := false  # messages des bots dans le chat : désactivés par défaut (/chat on)
static var zoom := 1  # closer default (v2 key: the old saved default 2 is not kept)

static func init() -> void:
	DirAccess.make_dir_recursive_absolute("user://deepminer")
	load_cfg()

static func load_cfg() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	for k in DEFAULT_LOOK:
		look[k] = c.get_value("look", k, DEFAULT_LOOK[k])
	fullscreen = c.get_value("options", "fullscreen", fullscreen)
	vsync = c.get_value("options", "vsync", vsync)
	volume = c.get_value("options", "volume", volume)
	zoom = c.get_value("options", "zoom_v2", zoom)
	chat_bots = c.get_value("options", "chat_bots", chat_bots)
	tordu = clampf(float(c.get_value("options", "tordu", tordu)), 0.0, 0.3)
	hd = c.get_value("options", "hd", hd)

static func save_cfg() -> void:
	DirAccess.make_dir_recursive_absolute("user://deepminer")
	var c := ConfigFile.new()
	for k in look:
		c.set_value("look", k, look[k])
	c.set_value("options", "fullscreen", fullscreen)
	c.set_value("options", "vsync", vsync)
	c.set_value("options", "volume", volume)
	c.set_value("options", "zoom_v2", zoom)
	c.set_value("options", "chat_bots", chat_bots)
	c.set_value("options", "tordu", tordu)
	c.set_value("options", "hd", hd)
	c.save(PATH)

## (le jeu est hébergé dans une fenêtre LangOS : plus de plein écran, vsync ni échelle de fenêtre à régler)
static func apply_video() -> void:
	pass

static func randomize_look() -> void:
	look.skin = SKINS.pick_random()
	look.helmet = COLORS.pick_random()
	look.shirt = COLORS.pick_random()
	look.overalls = COLORS.pick_random()
	look.boots = COLORS.pick_random()
	look.hair = randi() % HAIRS.size()
	look.hair_color = HAIR_COLORS.pick_random()
	look.beard = randi() % BEARDS.size()
	look.body = randi() % BODIES.size()
