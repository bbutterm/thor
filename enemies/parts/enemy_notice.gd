extends RefCounted
class_name EnemyNotice
## Обнаружение Тора: слух по радиусу, запасной таймер, тревога от удара (alert_to_player).
## Компонент Enemy (этап 3 рефакторинга): числа и состояние — поля Enemy (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — enemy.notice; нужные снаружи функции есть и на Enemy.

var enemy: Enemy

func _init(owner_node: Enemy) -> void:
	enemy = owner_node

## Новая цель не наследует знание прошлой. Без живого игрока время поиска не идёт.
func _sync_notice_player() -> bool:
	var valid_player: Player = null
	if is_instance_valid(enemy.player) and not enemy.player.is_dead:
		valid_player = enemy.player
	var player_id: int = valid_player.get_instance_id() if valid_player else 0
	if player_id != enemy._notice_player_id:
		enemy._notice_player_id = player_id
		enemy._notice_wait = 0.0
		enemy._noticed_player = enemy._notice_pending and player_id != 0
		if player_id != 0:
			enemy._notice_pending = false
	return player_id != 0

## Удар/толчок будит врага сразу; сигнал до назначения player не теряется.
func alert_to_player() -> void:
	if _sync_notice_player():
		enemy._noticed_player = true
	else:
		enemy._notice_pending = true

func is_alert_to_player() -> bool:
	return _sync_notice_player() and (enemy.kind == Enemy.Kind.BOSS or enemy._noticed_player)

func _notice_tick(delta: float) -> bool:
	if not _sync_notice_player():
		return false
	if enemy.kind == Enemy.Kind.BOSS or enemy._noticed_player:
		return true
	var mult := maxf(0.0, float(enemy.player.modify_stat(&"enemy_notice_radius_mult", 1.0)))
	var radius := maxf(0.0, enemy.notice_radius) * mult
	var diff := enemy.player.global_position - enemy.global_position
	# Слух не требует дополнительного луча через всю толпу и работает за стенами.
	if diff.x * diff.x + diff.z * diff.z <= radius * radius:
		enemy._noticed_player = true
	else:
		enemy._notice_wait += maxf(0.0, delta)
		if enemy._notice_wait >= maxf(0.0, enemy.notice_fallback_time):
			enemy._noticed_player = true
	return enemy._noticed_player
