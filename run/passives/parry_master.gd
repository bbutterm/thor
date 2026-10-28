extends BodyTraitHandler
## «Мастер щита» (Дева щита): окно парирования ×2, парирование лечит 5 HP.
## Меч берёт множитель окна и лечение через player.modify_stat.

@export var window_mult: float = 2.0
@export var heal_on_parry: float = 5.0

func modify(stat: StringName, value: Variant) -> Variant:
	match stat:
		&"parry_window_mult":
			return float(value) * window_mult
		&"parry_heal":
			return float(value) + heal_on_parry
	return value
