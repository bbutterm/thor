extends EliteHandler
## Ледяной: каждый удар, дошедший до Тора, замедляет его (PlayerSlow — компонент на игроке, player.gd не трогаем).

func on_struck_player(_amount: float) -> void:
	if enemy == null or not is_instance_valid(enemy.player):
		return
	PlayerSlow.apply(enemy.player, mod.slow_mult, mod.slow_time)
	FX.sparks(enemy.get_parent(), enemy.player.global_position + Vector3(0, 0.6, 0), Color(0.6, 0.9, 1.0), 14, 4.0)
	FX.ice_hit(enemy.get_parent(), enemy.player.global_position, mod.slow_time)
