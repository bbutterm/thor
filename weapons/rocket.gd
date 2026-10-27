extends Node3D
class_name Rocket
## Ракета ракетницы (GDD 9): летит, взрывается о стену/врага/пол — урон по площади врагам (через player.deal_damage),
## Тора не ранит, но отбрасывает: рокет-джамп. Вид — процедурная модель + общие эффекты FX.

const HIT_MASK := 1 | (1 << 2) | (1 << 3)

var player: Player
var vel: Vector3 = Vector3.ZERO
var damage: float = 44.0
var radius: float = 3.5
var max_range: float = 70.0
## Рокет-джамп: толчок Тора от центра взрыва (вверх + в сторону), если он в радиусе × self_radius_mult
var self_push_up: float = 13.0
var self_push_side: float = 7.0
var self_radius_mult: float = 1.0
var _travelled: float = 0.0
var _done: bool = false

func launch(p: Player, origin: Vector3, velocity_: Vector3, dmg: float) -> void:
	player = p
	global_position = origin
	vel = velocity_
	damage = dmg
	var m := WeaponMeshes.rocket()
	add_child(m)
	if vel.length() > 0.01:
		look_at(global_position + vel, Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.FORWARD)

func _physics_process(delta: float) -> void:
	if _done:
		return
	if player == null or not is_instance_valid(player):
		queue_free()
		return
	var from := global_position
	var to := from + vel * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		explode(hit.position + (hit.normal as Vector3) * 0.2)
		return
	global_position = to
	_travelled += from.distance_to(to)
	if _travelled >= max_range:
		explode(global_position)

func explode(pos: Vector3) -> void:
	if _done:
		return
	_done = true
	Perf.mark("rocket_blast")
	var parent := get_parent()
	FX.burst(parent, pos, radius * 0.75, Color(1.0, 0.55, 0.2, 0.6), 0.3)
	FX.ring(parent, pos, radius, Color(1.0, 0.5, 0.15, 0.9), 0.35)
	FX.sparks(parent, pos, Color(1.0, 0.75, 0.4), 22, 9.0)
	ComicFX.pop("slam", pos)
	Audio.play("sounds/sfx/boss_slam.wav")
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Node3D
		if en == null or not is_instance_valid(en) or (en is Enemy and (en as Enemy).is_dead):
			continue
		var d := en.global_position + Vector3(0, 0.9, 0) - pos
		if d.length() <= radius + 0.4:
			var kd := Vector3(d.x, 0, d.z).normalized() if Vector2(d.x, d.z).length() > 0.05 else Vector3.FORWARD
			var falloff := clampf(1.0 - d.length() / (radius + 0.4) * 0.5, 0.5, 1.0)
			player.deal_damage(en, damage * falloff, kd * 10.0 + Vector3.UP * 4.0, "ranged")
	# Бочки и ящики: урон и толчок, props/destructible.gd (не через player.deal_damage — не враги)
	Destructible.hit_area(self, pos, radius * 1.3, damage, 7.0, 4.0, "explosion")
	# Рокет-джамп: урона себе нет, только толчок
	var pc := player.global_position + Vector3(0, 0.9, 0)
	var pd := pc - pos
	if pd.length() <= radius * self_radius_mult + 0.4:
		var side := Vector3(pd.x, 0, pd.z)
		side = side.normalized() if side.length() > 0.05 else Vector3.ZERO
		player.velocity = Vector3(player.velocity.x, maxf(player.velocity.y, 0.0), player.velocity.z) + side * self_push_side + Vector3.UP * self_push_up
		player.camera_fx.add_trauma(0.45)
		Perf.mark("rocket_jump")
	elif pd.length() < radius * 3.0:
		player.camera_fx.add_trauma(0.25)
	queue_free()
