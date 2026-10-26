extends EliteHandler
## Бронированный: первые mod.armor_u «У» урона съедает броня (искры, звон), кирка ломает её сразу.
## Остаток брони — в подписи над элитой.

var armor: float = 0.0

func _apply_stats() -> void:
	armor = mod.armor_u * EnemyDef.U

func filter_damage(damage: float, _knockback: Vector3, source: String) -> float:
	if armor <= 0.0:
		return damage
	if enemy.hit_breaks_armor(source):
		_break()
		return damage
	var absorbed := minf(armor, damage)
	armor -= absorbed
	Perf.mark("elite_armor_hit")
	if source != "fire":
		FX.sparks(enemy.get_parent(), enemy.global_position + Vector3(0, 1.1 * enemy.model_scale, 0), Color(0.75, 0.78, 0.85), 10, 5.0)
		Audio.play("sounds/sfx/hammer_bounce.wav")
	if armor <= 0.0:
		_break()
	else:
		Loot.refresh_elite_label(enemy)
	return damage - absorbed

func _break() -> void:
	armor = 0.0
	Perf.mark("elite_armor_break")
	var pos := enemy.global_position + Vector3(0, 1.2 * enemy.model_scale, 0)
	FX.burst(enemy.get_parent(), pos, 0.9, Color(0.8, 0.82, 0.9, 0.6), 0.2)
	FX.sparks(enemy.get_parent(), pos, Color(0.85, 0.88, 0.95), 24, 8.0)
	Audio.play("sounds/sfx/wall_splat.wav")
	ComicFX.pop("ricochet", pos)
	Loot.refresh_elite_label(enemy)

func label_suffix() -> String:
	return " %d" % ceili(armor) if armor > 0.0 else " — сломана"
