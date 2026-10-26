extends EliteHandler
## Вампир: каждый удар по Тору лечит элиту на mod.heal_ratio × нанесённого урона.

func on_struck_player(amount: float) -> void:
	if not alive():
		return
	var heal := minf(amount * mod.heal_ratio, enemy.max_health - enemy.health)
	if heal <= 0.0:
		return
	Perf.mark("elite_vampire_heal")
	enemy.health += heal
	var parent := enemy.get_parent()
	FX.damage_number(parent, enemy.global_position + Vector3(0, 1.8 * enemy.model_scale, 0), heal, Color(0.95, 0.25, 0.35))
	if is_instance_valid(enemy.player):
		FX.lightning(parent, enemy.player.global_position + Vector3(0, 1.0, 0), enemy.global_position + Vector3(0, 1.2, 0), 0.25, Color(0.95, 0.2, 0.3))
