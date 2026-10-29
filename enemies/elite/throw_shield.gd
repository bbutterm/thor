extends EliteHandler
## Щит от бросков (С5): Мьёльнир отскакивает и урона не наносит (ни бросок, ни возврат) — бить вблизи или сверху
## (мили, удар-приземление, пике). Остановку молота даёт MjolnirProjectile.stops_hammer по метке HAMMER_SHIELD.

const HAMMER_SHIELD := &"elite_hammer_shield"

func _apply_stats() -> void:
	enemy.set_meta(HAMMER_SHIELD, true)

func filter_damage(damage: float, _knockback: Vector3, source: String) -> float:
	if source != "hammer":
		return damage
	Perf.mark("elite_hammer_shield")
	var pos := enemy.global_position + Vector3(0, 1.1 * enemy.model_scale, 0)
	FX.sparks(enemy.get_parent(), pos, mod.color, 14, 6.0)
	FX.ring(enemy.get_parent(), pos, 1.1 * enemy.model_scale, Color(mod.color, 0.8), 0.25)
	Audio.sfx("armor_tink", "sounds/sfx/hammer_bounce.wav")
	return 0.0
