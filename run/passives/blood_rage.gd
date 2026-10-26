extends BodyTraitHandler
## «Кровавая ярость» (Берсерк): +1 % урона за каждый 1 % потерянного HP, до +50 %.

## Сколько % урона за 1 % потерянного HP
@export var damage_per_lost_pct: float = 1.0
## Предел бонуса (0.5 = +50 %)
@export var max_bonus: float = 0.5

func damage_mult(_target: Object, _source: String) -> float:
	if player == null or player.max_health <= 0.0:
		return 1.0
	var lost := clampf(1.0 - player.health / player.max_health, 0.0, 1.0)
	return 1.0 + minf(max_bonus, lost * damage_per_lost_pct)
