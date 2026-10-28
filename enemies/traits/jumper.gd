extends EnemyTraitHandler
## Прыгун: с leap_min–leap_max м прыгает к Тору (дуга за leap_time), раз в leap_cooldown секунд.

var cooldown := 1.0
var leaps := 0

func _trait_tick(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	if cooldown > 0.0 or enemy.state != Enemy.State.CHASE or not enemy.is_on_floor() or enemy.player == null:
		return
	if not enemy.is_alert_to_player():
		return
	var d := enemy.player.global_position - enemy.global_position
	var flat := Vector2(d.x, d.z).length()
	if flat < def.leap_min or flat > def.leap_max or absf(d.y) > 1.5 or not enemy._has_line_of_sight():
		return
	leap()

func leap() -> void:
	Perf.mark("trait_jumper_leap")
	cooldown = def.leap_cooldown
	leaps += 1
	var to := enemy.player.global_position - enemy.global_position
	to.y = 0.0
	var target := enemy.player.global_position - to.normalized() * 1.5
	target.y = enemy.global_position.y
	var v := EnemyRangedAttacks.lob_velocity(enemy.global_position, target, def.leap_time, enemy.gravity)
	enemy.velocity = v
	# Горизонталь — через отбрасывание: машина движения его не съедает, _leap_left не даёт ему гаснуть до посадки
	enemy.knockback_velocity = Vector3(v.x, 0, v.z)
	enemy._leap_left = def.leap_time
	FX.burst(enemy.get_parent(), enemy.global_position + Vector3(0, 0.3, 0), 0.6, Color(def.color, 0.5), 0.2)
	Audio.sfx("zombie_groan" if FX.is_undead(enemy) else "", "sounds/sfx/enemy_growl.wav")
