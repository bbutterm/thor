extends BodyTraitHandler
## «Не её оружие» (Дева щита): ренж наносит −25 %.

@export var ranged_mult: float = 0.75

func damage_mult(_target: Object, source: String) -> float:
	return ranged_mult if source == "ranged" else 1.0
