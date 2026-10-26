extends BodyTraitHandler
## «Удар в спину» (Трусливый гонец): ×2 урона в спину — любым оружием, поверх множителя оружия (у ножа ×3).

@export var backstab_mult: float = 2.0

func damage_mult(target: Object, _source: String) -> float:
	return backstab_mult if is_behind(player, target) else 1.0
