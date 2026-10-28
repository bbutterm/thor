extends RefCounted
class_name EnemyMerc
## Наёмник Локи (GDD 12.1): лазер ведёт Тора windup_time, затем очередь по последней точке.
## Компонент Enemy (этап 3 рефакторинга): числа и состояние — поля Enemy (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — enemy.merc; нужные снаружи функции есть и на Enemy.

var enemy: Enemy

func _init(owner_node: Enemy) -> void:
	enemy = owner_node

func _muzzle() -> Vector3:
	return enemy.global_position + Vector3(0, 1.35 * enemy.model_scale, 0) + enemy.global_transform.basis.z * 0.55

func _update_merc(delta: float) -> void:
	if enemy.state == Enemy.State.WINDUP and enemy.player and is_instance_valid(enemy.player):
		var target := enemy.player.global_position + Vector3(0, 1.0, 0)
		enemy._aim_point = enemy._aim_point.lerp(target, clampf(enemy.merc_aim_track * delta, 0.0, 1.0))
		_show_laser(_muzzle(), enemy._aim_point)
	elif enemy._laser and enemy._laser.visible:
		enemy._laser.visible = false
		enemy._laser_dot.visible = false
	if enemy.state == Enemy.State.STUNNED:
		enemy._burst_left = 0
	if enemy._burst_left > 0:
		enemy._burst_t -= delta
		if enemy._burst_t <= 0.0:
			enemy._burst_t = enemy.merc_burst_interval
			enemy._burst_left -= 1
			_fire_bullet()

func _show_laser(from: Vector3, aim: Vector3) -> void:
	if enemy._laser == null:
		return
	var dir := (aim - from).normalized()
	var to := from + dir * enemy.merc_range
	var hit := enemy._ray(from, to, 1 | (1 << 1))
	if not hit.is_empty():
		to = hit.position
	var length := from.distance_to(to)
	if length < 0.05:
		return
	enemy._laser.visible = true
	enemy._laser_dot.visible = true
	enemy._laser.global_position = (from + to) * 0.5
	enemy._laser.look_at(to, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	enemy._laser.scale = Vector3(0.018, 0.018, length)
	enemy._laser_dot.global_position = to - dir * 0.05

func _start_burst() -> void:
	Perf.mark("merc_burst")
	enemy._burst_dir = (enemy._aim_point - _muzzle()).normalized()
	enemy._burst_left = enemy.merc_burst_count
	enemy._burst_t = 0.0

func _fire_bullet() -> void:
	Perf.mark("merc_shot")
	var from := _muzzle()
	var spread := deg_to_rad(enemy.merc_spread_deg)
	var dir := enemy._burst_dir.rotated(Vector3.UP, randf_range(-spread, spread))
	var side := dir.cross(Vector3.UP)
	if side.length() > 0.01:
		dir = dir.rotated(side.normalized(), randf_range(-spread, spread))
	var to := from + dir * enemy.merc_range
	var hit := enemy._ray(from, to, 1 | (1 << 1))
	if not hit.is_empty():
		to = hit.position
		if hit.collider is Player:
			enemy._hit_player(enemy.attack_damage * enemy.merc_bullet_mult, dir * 2.0)
	var tr := RangedWeapon.make_tracer_mesh()
	enemy.get_parent().add_child(tr)
	tr.global_position = from
	if from.distance_to(to) > 0.1:
		tr.look_at(to, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	var tw := tr.create_tween()
	tw.tween_property(tr, "global_position", to, from.distance_to(to) / 140.0)
	tw.tween_callback(tr.queue_free)
	FX.burst(enemy.get_parent(), from, 0.12, Color(1.0, 0.85, 0.4, 0.8), 0.06)
	Audio.play("sounds/sfx/gun_smg.wav")

## Лазер и точка — общие меш/материал эффектов, создаются один раз на наёмника и только прячутся. Из Enemy._setup_special.
func build_laser() -> void:
	enemy._laser = MeshInstance3D.new()
	enemy._laser.name = "Laser"
	enemy._laser.mesh = FX.shared_mesh("box")
	FX.fx_apply(enemy._laser, "alpha_nocull", Color(1.0, 0.1, 0.08, 0.75), 3.0)
	enemy._laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	enemy._laser.top_level = true
	enemy._laser.visible = false
	enemy.add_child(enemy._laser)
	enemy._laser_dot = MeshInstance3D.new()
	enemy._laser_dot.name = "LaserDot"
	enemy._laser_dot.mesh = FX.shared_mesh("sphere")
	FX.fx_apply(enemy._laser_dot, "glow", Color(1.0, 0.1, 0.05), 6.0)
	enemy._laser_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	enemy._laser_dot.top_level = true
	enemy._laser_dot.scale = Vector3.ONE * 0.14
	enemy._laser_dot.visible = false
	enemy.add_child(enemy._laser_dot)
