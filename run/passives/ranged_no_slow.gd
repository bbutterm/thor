extends BodyTraitHandler
## «Привычка к луку» (Охотник): ренж в руке не замедляет (ни в руке, ни при стрельбе).

func modify(stat: StringName, value: Variant) -> Variant:
	if stat == &"ranged_move_mult":
		return maxf(float(value), 1.0)
	return value
