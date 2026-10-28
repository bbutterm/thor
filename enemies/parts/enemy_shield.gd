extends RefCounted
class_name EnemyShield
## Щитоносец (GDD 12.1): блок щитом спереди, пробитие брони (кирка, Заряд/Праща Мьёльнира), удар щитом.
## Компонент Enemy (этап 3 рефакторинга): числа и состояние — поля Enemy (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — enemy.shield; нужные снаружи функции есть и на Enemy.

var enemy: Enemy

func _init(owner_node: Enemy) -> void:
	enemy = owner_node

func _shield_blocks(knockback: Vector3, source: String) -> bool:
	if enemy.state == Enemy.State.STUNNED or enemy.state == Enemy.State.SPAWNING:
		return false
	if source in ["slam", "stomp", "fire", "lightning", "explosion", "wall", "fall"]:
		return false
	# Пробитие (кирка, Заряд/Праща Мьёльнира) — даже если враг ещё не знает игрока
	if hit_breaks_armor(source):
		return false
	if enemy.player and is_instance_valid(enemy.player):
		if enemy.player.global_position.y - enemy.global_position.y > 1.6 * enemy.model_scale:
			return false
	var from_dir := Vector3.ZERO
	if source in ["hammer", "reflect"] and knockback.length() > 0.1:
		from_dir = -knockback
	elif enemy.player and is_instance_valid(enemy.player):
		from_dir = enemy.player.global_position - enemy.global_position
	from_dir.y = 0
	if from_dir.length() < 0.01:
		return false
	return from_dir.normalized().dot(enemy.global_transform.basis.z) > enemy.shield_front_dot

## Удар мили оружием, ломающим броню и щиты (кирка: WeaponDef.special = "armor_break").
func hit_breaks_armor(source: String) -> bool:
	if enemy.armor_pierce_hit:
		return true
	if not source.begins_with("melee") or enemy.player == null or not is_instance_valid(enemy.player):
		return false
	var w := enemy.player.current_weapon()
	return w != null and w.special == "armor_break"

func _on_blocked(knockback: Vector3) -> void:
	Perf.mark("shield_block")
	var push := Vector3(knockback.x, 0, knockback.z) * 0.25 * (1.0 - enemy.knock_resist)
	enemy.knockback_velocity += push
	enemy.velocity += push  # как в take_hit: база не должна съедать толчок
	var pos := enemy.global_position + Vector3(0, 1.2 * enemy.model_scale, 0) + enemy.global_transform.basis.z * 0.6
	FX.sparks(enemy.get_parent(), pos, Color(0.85, 0.92, 1.0), 12, 6.0)
	Audio.play("sounds/sfx/hammer_bounce.wav")
	ComicFX.pop("ricochet", pos)

## Удар щитом: урон и сильный толчок — теснит Тора (к краю, в огонь, под удары толпы).
func _do_shield_bash() -> void:
	var fwd := enemy.global_transform.basis.z
	enemy.knockback_velocity += fwd * enemy.lunge_speed
	if enemy.player and not enemy.player.is_dead:
		var to_p := enemy.player.global_position - enemy.global_position
		to_p.y = 0
		if to_p.length() <= enemy.attack_range * 1.35 + 0.3 and fwd.dot(to_p.normalized()) > 0.25 and enemy._can_reach_melee_target():
			enemy._hit_player(enemy.attack_damage, to_p.normalized() * enemy.shove_force + Vector3.UP * enemy.shove_up, true)
	FX.burst(enemy.get_parent(), enemy.global_position + fwd * enemy.attack_range * 0.8 + Vector3(0, 1, 0), 0.6 * enemy.model_scale, Color(0.8, 0.85, 1.0, 0.5), 0.15)
	Audio.play("sounds/sfx/wall_splat.wav")

## Щит — на корпусе спереди (а не в кисти): всегда виден там, где он блокирует. Из Enemy._setup_special.
func attach_front_shield() -> void:
	var sh := WeaponMeshes.build("q_shield")
	sh.name = "FrontShield"
	sh.rotation_degrees = enemy.shield_rotation
	sh.position = enemy.shield_offset
	sh.scale = Vector3.ONE * enemy.shield_scale
	enemy._visual.add_child(sh)
	enemy.visual._collect_meshes(enemy._visual)
