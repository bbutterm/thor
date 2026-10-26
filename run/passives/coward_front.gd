extends BodyTraitHandler
## «Трус» (Трусливый гонец): урон спереди (враг смотрит на Тора) −30 %.

@export var front_mult: float = 0.7

func damage_mult(target: Object, _source: String) -> float:
	return front_mult if is_front(player, target) else 1.0
