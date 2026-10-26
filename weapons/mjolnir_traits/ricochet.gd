extends MjolnirTraitHandler
## Рикошет (группа «воткнулся»): молот отскакивает от стен и врагов — и летит к следующему врагу.
## Отскоки кончились — втыкается (как база) или возвращается.

@export var ricochets: int = 3
@export var ricochets_lvl2: int = 5
## В каком радиусе ищем следующую цель (м)
@export var seek_radius: float = 14.0

func modify(stat: StringName, value: Variant) -> Variant:
	if stat == &"wall_bounces":
		return int(value) + int(lvl(ricochets, ricochets_lvl2))
	return value

func on_hit_enemy(proj: MjolnirProjectile, enemy: Node3D, _damage: float) -> void:
	if proj.state != MjolnirProjectile.State.OUT or proj.bounces_left <= 0:
		return
	var hit: Dictionary = proj.data.get("ric_hit", {})
	hit[enemy.get_instance_id()] = true
	proj.data["ric_hit"] = hit
	var next := _find_target(proj, enemy)
	if next == null:
		return
	proj.bounces_left -= 1
	_aim_at(proj, next)
	proj.hit_ids[enemy.get_instance_id()] = true
	FX.sparks(proj.fx_parent(), proj.global_position, Color(0.8, 0.95, 1.0), 10, 6.0)
	Audio.play("sounds/sfx/hammer_bounce.wav")
	mark()

func on_hit_world(proj: MjolnirProjectile, _pos: Vector3, _normal: Vector3, stuck: bool) -> void:
	if stuck:
		return
	var next := _find_target(proj, null)
	if next:
		_aim_at(proj, next)
	else:
		# Отскок без цели — летим дальше по отражению с полной скоростью
		proj.redirect(proj.vel.normalized() * hand.throw_speed)

func _aim_at(proj: MjolnirProjectile, e: Enemy) -> void:
	var to := (e.global_position + Vector3(0, 1.0, 0) - proj.global_position).normalized()
	proj.redirect(to * hand.throw_speed)

func _find_target(proj: MjolnirProjectile, exclude: Node3D) -> Enemy:
	var hit: Dictionary = proj.data.get("ric_hit", {})
	var space := proj.get_world_3d().direct_space_state
	var best: Enemy = null
	var best_d := seek_radius
	for e in proj.get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en == null or en.is_dead or en == exclude or hit.has(en.get_instance_id()):
			continue
		var chest := en.global_position + Vector3(0, 1.0, 0)
		var d := chest.distance_to(proj.global_position)
		if d >= best_d:
			continue
		var los := space.intersect_ray(PhysicsRayQueryParameters3D.create(proj.global_position, chest, 1))
		if los.is_empty():
			best = en
			best_d = d
	return best
