extends RefCounted
class_name EnemyFodderLod
## Дальняя массовка: корм дальше fodder_lod_distance реже пересчитывает направление и позу анимации.
## Компонент Enemy (этап 3 рефакторинга): числа и состояние — поля Enemy (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — enemy.fodder_lod; нужные снаружи функции есть и на Enemy.

var enemy: Enemy

func _init(owner_node: Enemy) -> void:
	enemy = owner_node

## Только ближний корм: дальние стрелки и боссы по-прежнему думают каждый кадр.
## Если дальность атаки переопределили, её область тоже остаётся на полной частоте.
func _fodder_lod_active() -> bool:
	if enemy.kind != Enemy.Kind.FODDER or enemy.state != Enemy.State.CHASE or not is_instance_valid(enemy.player) or enemy.player.is_dead:
		return false
	var d := enemy.player.global_position - enemy.global_position
	var distance := maxf(maxf(0.0, enemy.fodder_lod_distance), enemy.attack_range + 1.0)
	return d.x * d.x + d.z * d.z > distance * distance and enemy.fodder_lod_frames > 1

## Задерживаем только пересчёт направления и раздвигания толпы. Движение, гравитация,
## обнаружение, таймеры и все фазы удара продолжают обновляться каждый физический кадр.
func _think_chase_lod(delta: float) -> Vector3:
	if not _fodder_lod_active():
		enemy._fodder_lod_move_valid = false
		return enemy._think_chase()
	var interval := maxi(1, enemy.fodder_lod_frames)
	if not enemy._fodder_lod_move_valid or Engine.get_physics_frames() % interval == enemy.get_instance_id() % interval:
		enemy._fodder_lod_move = enemy._think_chase()
		enemy._fodder_lod_move_valid = true
	else:
		if enemy._tier_navigation != null and enemy._tier_navigation.is_active():
			enemy._face_dir(enemy._tier_navigation.direction(), delta)
		else:
			enemy._face_player(delta)
	return enemy._fodder_lod_move

## У дальнего корма обновляем именно позу анимации, а не просто повторный вызов play().
func _update_fodder_animation_lod(delta: float) -> void:
	if not _fodder_lod_active() or enemy._humanoid == null or enemy._humanoid.anim == null:
		_restore_fodder_animation()
		return
	var ap := enemy._humanoid.anim
	if not enemy._fodder_anim_lod:
		enemy._fodder_anim_previous_mode = ap.callback_mode_process
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		enemy._fodder_anim_delta = 0.0
		enemy._fodder_anim_lod = true
	enemy._fodder_anim_delta += delta
	var interval := maxi(1, enemy.fodder_lod_frames)
	if Engine.get_physics_frames() % interval == (enemy.get_instance_id() + 1) % interval:
		ap.advance(enemy._fodder_anim_delta)
		enemy._fodder_anim_delta = 0.0

func _restore_fodder_animation() -> void:
	if not enemy._fodder_anim_lod:
		return
	if enemy._humanoid and is_instance_valid(enemy._humanoid) and enemy._humanoid.anim:
		if enemy._fodder_anim_delta > 0.0:
			enemy._humanoid.anim.advance(enemy._fodder_anim_delta)
		enemy._humanoid.anim.callback_mode_process = enemy._fodder_anim_previous_mode
	enemy._fodder_anim_delta = 0.0
	enemy._fodder_anim_lod = false
