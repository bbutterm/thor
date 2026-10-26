extends BodyTraitHandler
## «Мастер щита» (Дева щита): окно парирования ×2, парирование лечит 5 HP.
## TODO: парирования мечом ещё нет (WeaponDef.special = "parry" — только метка). Когда появится, механика должна
## брать окно × player.modify_stat("parry_window_mult", 1.0) и лечить player.modify_stat("parry_heal", 0.0).

@export var window_mult: float = 2.0
@export var heal_on_parry: float = 5.0

func modify(stat: StringName, value: Variant) -> Variant:
	match stat:
		&"parry_window_mult":
			return float(value) * window_mult
		&"parry_heal":
			return float(value) + heal_on_parry
	return value
