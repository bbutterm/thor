extends BodyTraitHandler
## «Своя наковальня» (Кузнец): стартовое оружие сразу +1 уровень; заточка у Эйтри −50 %.
## Ларёк (run/shop.gd) берёт цену заточки × player.modify_stat("sharpen_cost_mult", 1.0).

@export var level_bonus: int = 1
@export var sharpen_cost_mult: float = 0.5

func modify(stat: StringName, value: Variant) -> Variant:
	match stat:
		&"start_weapon_level":
			return int(value) + level_bonus
		&"sharpen_cost_mult":
			return float(value) * sharpen_cost_mult
	return value
