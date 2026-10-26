extends BodyTraitHandler
## «Мудрость предков» (Старый жрец): все руны действуют ×2 — Run.rune_count считает каждую руну дважды.

@export var rune_power: int = 2

func modify(stat: StringName, value: Variant) -> Variant:
	if stat == &"rune_power":
		return int(value) * rune_power
	return value
