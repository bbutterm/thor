extends BodyTraitHandler
## «Слабак» (Трэлл): урон −30 % — любым оружием, молотом и ударом-приземлением.

@export var damage_factor: float = 0.7

func damage_mult(_target: Object, _source: String) -> float:
	return damage_factor
