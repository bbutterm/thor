extends BodyTraitHandler
## «Тяжёлые сапоги» (Кузнец): нет рывка в воздухе.

func modify(stat: StringName, value: Variant) -> Variant:
	if stat == &"air_dash":
		return false
	return value
