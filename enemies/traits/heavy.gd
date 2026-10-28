extends EnemyTraitHandler
## Тяжёлый: не отлетает от обычных ударов (сопротивление отбрасыванию heavy_knock_resist).

func _apply_stats() -> void:
	enemy.knock_resist = maxf(enemy.knock_resist, def.heavy_knock_resist)
