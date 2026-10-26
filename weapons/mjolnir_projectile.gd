extends Node3D
## Летящий Мьёльнир. Кинематический (не RigidBody): двигаем сами, проверяем попадания вдоль отрезка.
## Туда — отскакивает от стен; обратно — проходит сквозь стены по дуге к руке. Бьёт врагов в обе стороны.

enum State { OUT, RETURN }
var state: State = State.OUT
var hand: MjolnirHand
var vel: Vector3 = Vector3.ZERO
var _time: float = 0.0
var _return_time: float = 0.0
var _bounces: int = 0
var _hit_ids: Dictionary = {}
var _mesh_root: Node3D
var _light: OmniLight3D
const HIT_RADIUS := 0.6

func launch(owner_hand: MjolnirHand, origin: Vector3, velocity_: Vector3) -> void:
	hand = owner_hand
	global_position = origin
	vel = velocity_
	_build_visual()

func _build_visual() -> void:
	_mesh_root = Node3D.new()
	add_child(_mesh_root)
	var hm := WeaponMeshes.hammer()
	hm.position = Vector3(0, -0.3, 0)
	hm.scale = Vector3.ONE * 1.15
	_mesh_root.add_child(hm)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.5, 0.8, 1.0)
	_light.light_energy = 1.5
	_light.omni_range = 4.0
	add_child(_light)

func start_return() -> void:
	Perf.mark("hammer_return")
	if state == State.RETURN:
		return
	state = State.RETURN
	_hit_ids.clear()
	Audio.play("sounds/weapon_change.ogg")

func _physics_process(delta: float) -> void:
	if hand == null or not is_instance_valid(hand) or hand.player == null:
		queue_free()
		return
	_time += delta
	if _mesh_root:
		_mesh_root.rotate_object_local(Vector3.RIGHT, delta * 22.0)
	match state:
		State.OUT:
			_step_out(delta)
			if _time >= hand.auto_return_after:
				start_return()
		State.RETURN:
			_step_return(delta)

func _step_out(delta: float) -> void:
	var from := global_position
	var to := from + vel * delta
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(ray)
	if hit:
		_sweep_hits(from, hit.position)
		global_position = hit.position + hit.normal * 0.3
		_bounces += 1
		FX.burst(get_parent(), hit.position, 0.5, Color(0.6, 0.85, 1.0, 0.6), 0.15)
		FX.sparks(get_parent(), hit.position, Color(0.7, 0.9, 1.0), 14, 6.0)
		Audio.play("sounds/sfx/hammer_bounce.wav")
		ComicFX.pop("ricochet", hit.position)
		if _bounces > hand.max_wall_bounces:
			start_return()
		else:
			vel = vel.bounce(hit.normal) * 0.85
	else:
		_sweep_hits(from, to)
		global_position = to

func _step_return(delta: float) -> void:
	_return_time += delta
	var target := hand.hand_point()
	var to_target := target - global_position
	var dist := to_target.length()
	var speed := hand.return_speed * hand.return_speed_mult
	if dist < maxf(1.3, speed * delta * 1.5) or _return_time > 4.0:
		hand.on_caught()
		queue_free()
		return
	var desired := to_target / dist * speed
	# Сначала молот разворачивается по дуге, со временем «притяжение» к руке растёт — орбиты невозможны
	var steer := hand.return_turn_accel / speed * (1.0 + _return_time * 4.0)
	vel = vel.lerp(desired, clampf(1.0 - exp(-steer * delta), 0.0, 1.0))
	vel = vel.normalized() * speed
	var from := global_position
	var to := from + vel * delta
	_sweep_hits(from, to)
	global_position = to

func _sweep_hits(from: Vector3, to: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = HIT_RADIUS
	q.shape = s
	q.collision_mask = (1 << 2) | (1 << 3) | (1 << 6)
	q.collide_with_areas = false
	var seg := to - from
	var steps := maxi(1, int(ceil(seg.length() / 0.4)))
	var dir := seg.normalized() if seg.length() > 0.001 else vel.normalized()
	for i in steps + 1:
		q.transform = Transform3D(Basis.IDENTITY, from + seg * (float(i) / steps))
		for h in space.intersect_shape(q, 16):
			var c: Object = h.collider
			if c == null:
				continue
			var id := c.get_instance_id()
			if _hit_ids.has(id):
				continue
			_hit_ids[id] = true
			_on_hit(c, dir)

func _on_hit(c: Object, dir: Vector3) -> void:
	var knock := Vector3(dir.x, 0, dir.z).normalized() * 9.0 + Vector3.UP * 3.0
	if c.has_method("take_hit"):
		var dmg := hand.current_damage()
		c.take_hit(dmg, knock, "hammer")
		ComicFX.on_hammer_hit(c, global_position, state == State.RETURN, _bounces)
		FX.hitstop(hand.hit_hitstop)
		hand.player.camera_fx.add_trauma(0.12)
		FX.burst(get_parent(), global_position, 0.6, Color(0.55, 0.85, 1.0, 0.7), 0.15)
		Audio.play("sounds/sfx/hammer_hit.wav")
		_chain_lightning(c as Node3D, dmg * hand.chain_damage_ratio)
	elif c is RigidBody3D:
		var rb := c as RigidBody3D
		rb.apply_central_impulse(knock * rb.mass * 0.7)

func _chain_lightning(source: Node3D, dmg: float) -> void:
	if source == null or not is_instance_valid(source):
		return
	var best: Node3D = null
	var best_d := hand.chain_radius
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Node3D
		if en == null or en == source or not en.has_method("take_hit"):
			continue
		if e.get("is_dead"):
			continue
		var d := en.global_position.distance_to(source.global_position)
		if d < best_d:
			best_d = d
			best = en
	if best:
		FX.lightning(get_parent(), source.global_position + Vector3(0, 1, 0), best.global_position + Vector3(0, 1, 0))
		Audio.play("sounds/sfx/lightning.wav")
		best.take_hit(dmg, Vector3.UP * 2.0, "lightning")
		ComicFX.on_lightning(best)
