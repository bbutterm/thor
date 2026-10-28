extends EliteHandler
## Призыватель: раз в mod.summon_interval секунд — телеграф (кольцо, mod.summon_windup с) и mod.summon_count корма рядом.

var _t: float = 0.0
var _casting: float = -1.0
var summoned: int = 0

func _apply_stats() -> void:
	_t = mod.summon_interval * 0.5

func _physics_process(delta: float) -> void:
	if not alive() or mod.summon_interval <= 0.0:
		return
	if _casting >= 0.0:
		_casting += delta
		if _casting >= mod.summon_windup:
			_casting = -1.0
			summoned += enemy.summon_around(mod.summon_kind, mod.summon_count, mod.summon_cap)
			FX.ring(enemy.get_parent(), enemy.global_position, 3.5, Color(mod.color, 0.9), 0.4)
		return
	# Уже начатый обряд выше завершается, но новый не начинается до обнаружения Тора.
	# Таймер идёт и во время атак (GDD 12.4: «раз в 8 с»): боец у Тора бьёт без пауз — роль «окружение».
	if not (enemy.state in [Enemy.State.CHASE, Enemy.State.WINDUP, Enemy.State.RECOVER]) or not enemy.is_alert_to_player():
		return
	_t += delta
	if _t >= mod.summon_interval:
		_t = 0.0
		_casting = 0.0
		Perf.mark("elite_summon_telegraph")
		FX.ring(enemy.get_parent(), enemy.global_position, 3.0, Color(mod.color, 0.9), mod.summon_windup)
		FX.burst(enemy.get_parent(), enemy.global_position + Vector3(0, 2.2 * enemy.model_scale, 0), 0.4, Color(mod.color, 0.6), mod.summon_windup)
		Audio.play("sounds/sfx/curse_throw.wav")
