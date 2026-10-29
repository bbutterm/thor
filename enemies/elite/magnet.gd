extends EliteHandler
## Магнит (С5): тянет летящий Мьёльнир к себе — бросок мимо уходит в него. Против него: бросать вблизи или
## убить первым. Радиус и сила — mod.magnet_radius / mod.magnet_pull (доля разворота скорости за секунду).

func _physics_process(delta: float) -> void:
	if not alive() or enemy.player == null or not is_instance_valid(enemy.player):
		return
	var proj := enemy.player.mjolnir.projectile
	if proj == null or not is_instance_valid(proj) or proj.state != MjolnirProjectile.State.OUT:
		return
	var target := enemy.global_position + Vector3(0, 1.0 * enemy.model_scale, 0)
	var to := target - proj.global_position
	if to.length() > mod.magnet_radius or to.length() < 0.2:
		return
	var speed := proj.vel.length()
	proj.vel = proj.vel.lerp(to.normalized() * speed, clampf(mod.magnet_pull * delta, 0.0, 1.0))
	if Engine.get_physics_frames() % 6 == 0:
		FX.lightning(enemy.get_parent(), target, proj.global_position, 0.08)
