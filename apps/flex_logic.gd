class_name FlexLogic
## Logique pure (testable) du mode Flex.

## Vrai si le téléphone est plié à moitié, charnière horizontale. Hystérésis : on entre à 25°–160°, on ne sort qu'en dehors de 15°–172°
## (l'angle vibre autour du seuil : sans cela le pavé clignoterait). `was` = décision précédente.
static func is_half(d: Dictionary, was: bool) -> bool:
	if str(d.get("orientation", "")) != "horizontal" or int(d.get("bottom", 0)) <= 0: return false
	if str(d.get("state", "")) == "half": return true
	var a := int(d.get("angle", -1))
	if a < 0: return false
	return (a >= 15 and a <= 172) if was else (a >= 25 and a <= 160)
