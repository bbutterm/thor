extends EnemyTraitHandler
## Яростный: после попадания по нему ускоряется (скорость ×rage_speed_mult, перезарядка атаки ×rage_cooldown_mult)
## на rage_time секунд; повторное попадание продлевает.

var rage_left := 0.0
var _base_speed := 0.0
var _base_cooldown := 0.0

func _apply_stats() -> void:
	_base_speed = enemy.move_speed
	_base_cooldown = enemy.attack_cooldown

func on_hit(damage: float, _source: String) -> void:
	if damage <= 0.0 or not alive():
		return
	if rage_left <= 0.0:
		Perf.mark("trait_furious")
		_base_speed = enemy.move_speed
		_base_cooldown = enemy.attack_cooldown
		enemy.move_speed = _base_speed * def.rage_speed_mult
		enemy.attack_cooldown = _base_cooldown * def.rage_cooldown_mult
		FX.burst(enemy.get_parent(), enemy.global_position + Vector3(0, 1.6 * enemy.model_scale, 0), 0.45, Color(def.color, 0.6), 0.25)
	rage_left = def.rage_time

func _trait_tick(delta: float) -> void:
	if rage_left > 0.0:
		rage_left -= delta
		if rage_left <= 0.0:
			enemy.move_speed = _base_speed
			enemy.attack_cooldown = _base_cooldown

func is_raging() -> bool:
	return rage_left > 0.0
