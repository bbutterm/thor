extends RefCounted
class_name PlayerWeaponSkills
## Движение приёмов оружия: выпад, рубка вниз, прыжок с посохом, удар при посадке.
## Компонент игрока (этап 2 рефакторинга): числа и состояние — поля Player (их ставят сцена, тела
## и тесты), здесь только логика. Доступ — player.skills; публичные функции есть и на Player.

var p: Player

func _init(player: Player) -> void:
	p = player

## Движение приёмов оружия не расходует руны и использует обычный move_and_slide игрока.
func weapon_skill_start_lunge(direction: Vector3, distance: float, duration: float) -> bool:
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if p.is_dead or p.is_climbing or p.is_slamming or weapon_skill_lunge_active() \
			or horizontal.length_squared() < 0.0001 or distance <= 0.0 or duration <= 0.0:
		return false
	weapon_skill_cancel_motion()
	p._dash_time_left = 0.0
	p.dash._end_ram()
	p.is_sliding = false
	p._weapon_skill_lunge_dir = horizontal.normalized()
	p._weapon_skill_lunge_speed = distance / duration
	p._weapon_skill_lunge_left = duration
	p._weapon_skill_lunge_mask = p.collision_mask
	# Враги — слой 3; стены и предметы остаются физическими препятствиями.
	p.collision_mask &= ~(1 << 2)
	return true

func weapon_skill_lunge_active() -> bool:
	return p._weapon_skill_lunge_left > 0.0

## Второй выпад разрешён только после естественного завершения первого.
func weapon_skill_lunge_completed() -> bool:
	return not p.is_dead and p._weapon_skill_lunge_completed

func _weapon_skill_waiting_for_ground() -> bool:
	return p._weapon_skill_landing_id in ["axe_dive", "staff_wave"]

## Учитываем только нормали, которые движок признаёт полом, включая все контакты одного столкновения.
func _weapon_skill_floor_contact_flags() -> int:
	var flags := 0
	var min_floor_dot := cos(p.floor_max_angle + 0.01)
	for i in p.get_slide_collision_count():
		var collision := p.get_slide_collision(i)
		for j in collision.get_collision_count():
			if collision.get_normal(j).dot(p.up_direction) < min_floor_dot:
				continue
			if collision.get_collider(j) is Enemy:
				flags |= Player.SKILL_FLOOR_ENEMY
			else:
				flags |= Player.SKILL_FLOOR_OTHER
	return flags

func _weapon_skill_enemy_only_floor() -> bool:
	return _weapon_skill_waiting_for_ground() and p.is_on_floor() \
		and _weapon_skill_floor_contact_flags() == Player.SKILL_FLOOR_ENEMY

func _process_weapon_skill_lunge(on_floor: bool, delta: float) -> void:
	# Последний короткий шаг не должен добавлять расстояние сверх заданного.
	var fraction := minf(1.0, p._weapon_skill_lunge_left / maxf(delta, 0.000001))
	p.velocity.x = p._weapon_skill_lunge_dir.x * p._weapon_skill_lunge_speed * fraction
	p.velocity.z = p._weapon_skill_lunge_dir.z * p._weapon_skill_lunge_speed * fraction
	p.jumps._process_gravity(on_floor, delta)

func _finish_weapon_skill_lunge_step(delta: float) -> void:
	p._weapon_skill_lunge_left = maxf(0.0, p._weapon_skill_lunge_left - delta)
	var blocked := false
	for i in p.get_slide_collision_count():
		var normal := p.get_slide_collision(i).get_normal()
		if absf(normal.y) < 0.7 and normal.dot(p._weapon_skill_lunge_dir) < -0.4:
			blocked = true
			break
	if blocked:
		_end_weapon_skill_lunge()
	elif p._weapon_skill_lunge_left <= 0.0:
		_end_weapon_skill_lunge(true)

func _end_weapon_skill_lunge(completed: bool = false) -> void:
	p._weapon_skill_lunge_completed = completed and p._weapon_skill_lunge_mask >= 0
	if p._weapon_skill_lunge_mask >= 0:
		p.collision_mask = p._weapon_skill_lunge_mask
		p._weapon_skill_lunge_mask = -1
		p.velocity.x = 0.0
		p.velocity.z = 0.0
	p._weapon_skill_lunge_left = 0.0
	p._weapon_skill_lunge_speed = 0.0
	p._weapon_skill_lunge_dir = Vector3.ZERO

## Рубка топором вниз — отдельное пике, не удар-приземление и без расхода руны.
func weapon_skill_start_dive(speed: float) -> bool:
	if speed <= 0.0 or not weapon_skill_arm_landing("axe_dive"):
		return false
	_end_weapon_skill_lunge()
	p._dash_time_left = 0.0
	p.dash._end_ram()
	p.is_sliding = false
	p._weapon_skill_dive_speed = speed
	p.velocity.y = -speed
	return true

## Зарегистрировать один удар при следующей настоящей посадке.
func weapon_skill_arm_landing(skill_id: String) -> bool:
	if skill_id.is_empty() or p.is_dead or p.is_on_floor() or p.is_climbing or p.is_slamming \
			or p._weapon_skill_landing_used:
		return false
	p._weapon_skill_landing_id = skill_id
	p._weapon_skill_landing_used = true
	return true

## Оружие может обнаружить отмену ожидания до касания земли.
func weapon_skill_landing_pending(skill_id: String) -> bool:
	return not p.is_dead and not skill_id.is_empty() and p._weapon_skill_landing_id == skill_id

## Прыжок с посохом: множитель задан по высоте, поэтому скорость растёт на sqrt(mult).
func weapon_skill_start_vault(height_mult: float) -> bool:
	if height_mult <= 0.0 or p.is_dead or not p.is_on_floor() or p.is_climbing or p.is_slamming \
			or (p._weapon_skill_landing_used and _weapon_skill_floor_contact_flags() == Player.SKILL_FLOOR_ENEMY):
		return false
	weapon_skill_cancel_motion()
	p._dash_time_left = 0.0
	p.dash._end_ram()
	p.is_sliding = false
	p._weapon_skill_landing_used = false
	p._jump_buffer_left = 0.0
	p._coyote_left = 0.0
	p.velocity.y = p.jump_velocity * sqrt(height_mult)
	p._slam_ready = true
	return true

## Отмена не меняет накопленную высоту полёта и не возвращает право на удар в этом полёте.
func weapon_skill_cancel_motion() -> void:
	_end_weapon_skill_lunge()
	p._weapon_skill_dive_speed = 0.0
	p._weapon_skill_landing_id = ""
	p.weapon_skill_speed_mult = 1.0

func _on_weapon_skill_slot_changed(_slot: int) -> void:
	weapon_skill_cancel_motion()
