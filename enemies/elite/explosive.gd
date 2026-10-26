extends EliteHandler
## Взрывной: после смерти на месте тела — телеграф (диск наливается) и взрыв (Blast): бьёт и Тора, и своих.

func on_died() -> void:
	if enemy == null or enemy.get_parent() == null:
		return
	Blast.delayed(enemy.get_parent(), enemy.global_position, mod.blast_radius, mod.blast_damage_u * EnemyDef.U, mod.blast_delay, null, mod.color)
