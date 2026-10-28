extends RefCounted
class_name EnemyShaman
## Шаман (GDD 12.1): отход от Тора, обряд — лечит своих и поднимает корм; призыв вокруг (и для элиты-Призывателя).
## Компонент Enemy (этап 3 рефакторинга): числа и состояние — поля Enemy (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — enemy.shaman; нужные снаружи функции есть и на Enemy.

var enemy: Enemy

func _init(owner_node: Enemy) -> void:
	enemy = owner_node

func _think_shaman(dist: float, dir: Vector3) -> Vector3:
	if dist < enemy.shaman_flee_dist and enemy._has_floor_ahead(-dir):
		return -dir
	return Vector3.ZERO

func _ritual_telegraph() -> void:
	Perf.mark("shaman_telegraph")
	FX.ring(enemy.get_parent(), enemy.global_position, 3.0, Color(0.35, 1.0, 0.45, 0.9), enemy.windup_time)
	FX.burst(enemy.get_parent(), enemy.global_position + Vector3(0, 2.0 * enemy.model_scale, 0), 0.4, Color(0.35, 1.0, 0.45, 0.6), enemy.windup_time)
	Audio.play("sounds/sfx/curse_throw.wav")

func _do_ritual() -> void:
	Perf.mark("shaman_ritual")
	var parent := enemy.get_parent()
	var top := enemy.global_position + Vector3(0, 2.0 * enemy.model_scale, 0)
	for e in enemy._enemies_now():
		var en := e as Enemy
		if en == null or not is_instance_valid(en) or en.is_dead:
			continue
		if en.global_position.distance_to(enemy.global_position) > enemy.ritual_heal_radius or en.health >= en.max_health:
			continue
		var amt := minf(en.max_health * enemy.ritual_heal_fraction, en.max_health - en.health)
		en.health += amt
		FX.damage_number(parent, en.global_position + Vector3(0, 1.8 * en.model_scale, 0), amt, Color(0.4, 1.0, 0.5))
		FX.lightning(parent, top, en.global_position + Vector3(0, 1.0, 0), 0.3, Color(0.4, 1.0, 0.5))
	summon_around("fodder", enemy.ritual_raise_count, enemy.ritual_raise_cap)
	FX.ring(parent, enemy.global_position, 3.5, Color(0.35, 1.0, 0.45, 0.9), 0.4)
	Audio.play("sounds/sfx/lightning.wav")

## Поднять/призвать count врагов вида kind в 2.5–4.5 м вокруг (не в стену, не за край); не больше cap врагов в зале.
## Шаман и элита-Призыватель. Возвращает, сколько появилось.
func summon_around(kind_name: String, count: int, cap: int) -> int:
	var room := enemy._room()
	if room == null or enemy.get_tree().get_nodes_in_group("enemies").size() >= cap:
		return 0
	Perf.mark("summon_" + kind_name)
	var made := 0
	for i in count * 3:
		if made >= count:
			break
		var a := randf() * TAU
		var cand := enemy.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(2.5, 4.5)
		if not enemy._clear_path(enemy.global_position + Vector3(0, 1.0, 0), cand + Vector3(0, 1.0, 0)):
			continue
		var ground := Loot.floor_point(enemy, cand)
		if ground == cand:
			continue
		if room.call("spawn_extra", kind_name, ground) != null:
			made += 1
	return made
