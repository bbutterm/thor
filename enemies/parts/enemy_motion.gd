extends RefCounted
class_name EnemyMotion
## Движение и физика врага: скорость с отбрасыванием, толчок без урона, падение с высоты,
## толчок пропсов, обход застревания, шмяк об стену.
## Компонент Enemy (этап 3 рефакторинга): числа и состояние — поля Enemy (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — enemy.motion; нужные снаружи функции есть и на Enemy.

var enemy: Enemy

func _init(owner_node: Enemy) -> void:
	enemy = owner_node

## Толчок без урона: волна посоха на первых двух уровнях использует ту же физику, что и попадание.
func apply_knockback_only(knockback: Vector3) -> Vector3:
	if enemy.is_dead:
		return Vector3.ZERO
	if knockback.length_squared() > 0.0001:
		if enemy._tier_navigation != null:
			enemy._tier_navigation.interrupt_jump()
		if enemy._spawn_entry != null:
			enemy._spawn_entry.cancel()
		enemy.notice.alert_to_player()
	var k := knockback * (1.0 - enemy.knock_resist)
	if k.length_squared() > 0.0001:
		# Толчок без урона тоже может сбросить врага с уступа.
		enemy._last_hit_time = Run.combat_clock
		# Удар может прервать прыжок уже в воздухе, а не только до отрыва.
		if enemy._airborne:
			enemy._fall_forced = true
			enemy._fall_peak_y = maxf(enemy._fall_peak_y, enemy.global_position.y)
	enemy.knockback_velocity += k
	# _apply_movement вычитает накопленный толчок из velocity при вычислении базовой скорости.
	enemy.velocity.x += k.x
	enemy.velocity.z += k.z
	return k

func _apply_movement(move_dir: Vector3, delta: float) -> void:
	var can_move: bool = enemy.state == Enemy.State.CHASE or (enemy.state == Enemy.State.SPAWNING and enemy._spawn_entry != null and enemy._spawn_entry.active)
	var target := move_dir * enemy.move_speed if can_move else Vector3.ZERO
	var horiz := Vector3(enemy.velocity.x, 0, enemy.velocity.z)
	# Базовая скорость стремится к цели, отбрасывание добавляется сверху
	var base := horiz - Vector3(enemy.knockback_velocity.x, 0, enemy.knockback_velocity.z)
	base = base.move_toward(target, enemy.accel * delta)
	# Прыжок черты «Прыгун» (enemies/traits/jumper.gd): горизонталь прыжка не гаснет до конца дуги
	if enemy._leap_left > 0.0:
		enemy._leap_left -= delta
	else:
		enemy.knockback_velocity = enemy.knockback_velocity.lerp(Vector3.ZERO, clampf(enemy.knock_decay * delta, 0.0, 1.0))
		if not enemy.is_on_floor():
			enemy.knockback_velocity = enemy.knockback_velocity.lerp(Vector3.ZERO, clampf(enemy.knock_decay * 0.3 * delta, 0.0, 1.0))
	var new_h := base + Vector3(enemy.knockback_velocity.x, 0, enemy.knockback_velocity.z)
	enemy.velocity.x = new_h.x
	enemy.velocity.z = new_h.z
	if not enemy.is_on_floor():
		enemy.velocity.y -= enemy.gravity * delta
	elif enemy.velocity.y < 0:
		enemy.velocity.y = -0.5
	var pre := Vector3(enemy.velocity.x, 0, enemy.velocity.z)
	enemy.move_and_slide()
	_push_props()
	_check_wall_splat(pre)
	_check_fall()
	_update_stuck(move_dir, delta)
	if _below_fall_limit():
		enemy._die("fall")

## Залы с ямой могут задать локальную границу, не меняя другие арены.
func _below_fall_limit() -> bool:
	if enemy.global_position.y < -30.0:
		return true
	var room := enemy.get_parent() as Node3D
	return room != null and room.has_meta("enemy_fall_y") \
		and room.to_local(enemy.global_position).y < float(room.get_meta("enemy_fall_y"))

## Сброшенный с высоты враг (GDD 8): корм — насмерть, остальные — fall_damage. Босса не касается.
func _check_fall() -> void:
	var on_floor := enemy.is_on_floor()
	if not on_floor:
		if not enemy._airborne:
			enemy._airborne = true
			enemy._fall_peak_y = enemy.global_position.y
			enemy._fall_forced = enemy.state != Enemy.State.SPAWNING and Run.combat_clock - enemy._last_hit_time <= enemy.fall_hit_window
		enemy._fall_peak_y = maxf(enemy._fall_peak_y, enemy.global_position.y)
		return
	if not enemy._airborne:
		return
	enemy._airborne = false
	var h := enemy._fall_peak_y - enemy.global_position.y
	if not enemy._fall_forced or h < enemy.fall_kill_height or enemy.kind == Enemy.Kind.BOSS or enemy.is_dead:
		return
	Perf.mark("enemy_fall")
	var dmg := enemy.health + 1.0 if enemy.kind == Enemy.Kind.FODDER else enemy.fall_damage
	enemy.take_hit(dmg, Vector3.ZERO, "fall")

func _push_props() -> void:
	for i in enemy.get_slide_collision_count():
		var col := enemy.get_slide_collision(i)
		var rb := col.get_collider() as RigidBody3D
		if rb:
			var dir := -col.get_normal()
			dir.y = 0.1
			rb.apply_central_impulse(dir.normalized() * 0.9 * enemy.model_scale * enemy.model_scale)

func _update_stuck(move_dir: Vector3, delta: float) -> void:
	if enemy._detour_left > 0.0:
		enemy._detour_left -= delta
	if enemy.state != Enemy.State.CHASE or move_dir == Vector3.ZERO:
		enemy._stuck_check_t = 0.0
		enemy._stuck_check_pos = enemy.global_position
		return
	enemy._stuck_check_t += delta
	if enemy._stuck_check_t >= 0.6:
		var moved := Vector2(enemy.global_position.x - enemy._stuck_check_pos.x, enemy.global_position.z - enemy._stuck_check_pos.z).length()
		if moved < enemy.move_speed * 0.6 * 0.25 and enemy._detour_left <= 0.0:
			enemy._detour_dir = move_dir.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
			enemy._detour_left = 0.9
		enemy._stuck_check_t = 0.0
		enemy._stuck_check_pos = enemy.global_position

func _check_wall_splat(pre_horiz: Vector3) -> void:
	var kspeed := Vector2(enemy.knockback_velocity.x, enemy.knockback_velocity.z).length()
	if kspeed < enemy.wall_splat_speed:
		return
	for i in enemy.get_slide_collision_count():
		var col := enemy.get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) > 0.5:
			continue
		var other := col.get_collider()
		if other is CharacterBody3D or other is RigidBody3D:
			continue
		if pre_horiz.normalized().dot(-n) < 0.3:
			continue
		enemy._last_splat_time = Run.combat_clock
		enemy.knockback_velocity = n * 2.0
		FX.burst(enemy.get_parent(), col.get_position(), 0.8, Color(1, 1, 1, 0.6), 0.2)
		if enemy.player:
			enemy.player.camera_fx.add_trauma(0.2)
		Audio.play("sounds/sfx/wall_splat.wav")
		StyleMeter.event(&"wall_splat")
		if enemy.kind != Enemy.Kind.BOSS:
			enemy._stun_left = enemy.wall_splat_stun
			enemy._set_state(Enemy.State.STUNNED)
		enemy.take_hit(enemy.wall_splat_damage, Vector3.ZERO, "wall")
		return
