class_name Cfg
## Constantes globales du jeu (structure, équipes, carte).

const TEAM_RED := 0
const TEAM_BLUE := 1
const TEAM_COLORS := [Color(0.93, 0.27, 0.27), Color(0.27, 0.5, 0.95)]
const TEAM_NAMES := ["ROUGE", "BLEU"]

const MAP_SIZE := Vector3i(64, 32, 24)
const WIN_SCORE := 5
const VOID_Y := -12.0

# Blocs
const B_AIR := 0
const B_STONE := 1
const B_RED_FLOOR := 2
const B_BLUE_FLOOR := 3
const B_BRIDGE := 4
const B_RED_PLACED := 5
const B_BLUE_PLACED := 6

# Etats de partie
enum State { WAITING, COUNTDOWN, PLAYING, POINT_SCORED, ROUND_RESET, MATCH_FINISHED }
# Emplacements de la barre d'inventaire
enum Slot { SWORD, PICKAXE, BLOCKS }

# Lits (centre), spawns et orientation (yaw) par équipe
const BEDS := [Vector3(4.0, 8.0, 12.0), Vector3(60.0, 8.0, 12.0)]
const SPAWNS := [Vector3(9.5, 8.05, 12.0), Vector3(54.5, 8.05, 12.0)]
const SPAWN_YAW := [-PI / 2.0, PI / 2.0]

static func placed_block(team: int) -> int:
	return B_RED_PLACED if team == TEAM_RED else B_BLUE_PLACED
