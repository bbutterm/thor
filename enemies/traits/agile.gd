extends EnemyTraitHandler
## Ловкий: замечает летящий к нему Мьёльнир (ближе dodge_detect) и отскакивает вбок; раз в dodge_interval секунд.

var cooldown := 0.0
var dodges := 0

func _trait_tick(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	if cooldown > 0.0 or enemy.state == Enemy.State.STUNNED:
		return
	for n in enemy.get_tree().get_nodes_in_group("mjolnir_projectiles"):
		var m := n as MjolnirProjectile
		if m == null or not is_instance_valid(m) or m.is_queued_for_deletion():
			continue
		var to_me := enemy.global_position + Vector3(0, 1.0, 0) - m.global_position
		if to_me.length() > def.dodge_detect or m.vel.length() < 1.0 or m.vel.normalized().dot(to_me.normalized()) < 0.6:
			continue
		dodge(m.vel)
		return

## Отскок перпендикулярно полёту молота (в сторону, где есть пол).
func dodge(hammer_vel: Vector3) -> void:
	Perf.mark("trait_agile_dodge")
	cooldown = def.dodge_interval
	dodges += 1
	var side := hammer_vel.cross(Vector3.UP)
	side.y = 0.0
	side = side.normalized() if side.length() > 0.01 else enemy.global_transform.basis.x
	if randf() < 0.5:
		side = -side
	if not enemy._has_floor_ahead(side, 1.5):
		side = -side
	enemy.knockback_velocity += side * def.dodge_speed
	enemy.velocity += side * def.dodge_speed
	if enemy.is_on_floor():
		enemy.velocity.y = 3.0
	FX.burst(enemy.get_parent(), enemy.global_position + Vector3(0, 0.8, 0), 0.5, Color(def.color, 0.5), 0.2)
	Audio.play("sounds/sfx/dash.wav")
