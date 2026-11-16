class_name Carry extends RefCounted
## Charge du sac : chaque objet a un poids, chaque espèce une capacité (DMSettings.CARRY).
## Dépasser la capacité ralentit progressivement (jamais de blocage) ; la capacité est volontairement large.

const W := {World.DIRT: 0.25, World.STONE: 0.25, World.MOSS: 0.25, World.COAL: 0.6, World.COPPER: 1.0, World.IRON: 1.4,
	World.CRYSTAL: 0.8, World.FORGE: 2.0, World.IRON_B: 2.0, World.COPPER_B: 1.4, World.TORCH: 0.1, World.MUSHROOM: 0.1}
const DEFAULT_W := 0.3

static func weight_of(id: int) -> float:
	return W.get(id, DEFAULT_W)

static func weight(inv: Dictionary) -> float:
	var t := 0.0
	for id in inv:
		t += weight_of(id) * maxi(inv[id], 0)
	return t

## 1 jusqu'à la capacité ; ensuite -0,8 % de vitesse par % de dépassement, jamais sous 45 % (125 % de charge : x0,8).
static func speed_mult(wt: float, cap: float) -> float:
	if wt <= cap:
		return 1.0
	return clampf(1.0 - (wt / cap - 1.0) * 0.8, 0.45, 1.0)
