extends EliteHandler
## Быстрый: скорость ×mod.speed_mult (анимация ходьбы ускоряется сама — она привязана к скорости).

func _apply_stats() -> void:
	enemy.move_speed *= mod.speed_mult
