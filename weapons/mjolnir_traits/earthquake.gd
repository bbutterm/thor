extends MjolnirTraitHandler
## Землетрясение (без группы): удар-приземление недалеко от воткнутого молота даёт вторую волну у молота.
## Ур. 2 — третья волна, шире. Сила волны — как у удара-приземления игрока (с той же высоты).

## Насколько близко к молоту надо приземлиться (м)
@export var trigger_distance: float = 5.0
@export var wave_delay: float = 0.12
@export var radius_mult: float = 1.0
@export var damage_mult: float = 1.0
@export var third_wave_delay: float = 0.35
@export var third_wave_radius_mult: float = 1.4
## Сколько воткнутый молот ждёт ПКМ
@export var stuck_hold: float = 3.0

func modify(stat: StringName, value: Variant) -> Variant:
	if stat == &"stuck_auto_return" and float(value) > 0.0:
		return maxf(float(value), stuck_hold)
	return value

func on_player_slam(h: MjolnirHand, power: float, center: Vector3) -> void:
	var proj := h.projectile
	if proj == null or not is_instance_valid(proj) or not proj.is_stuck():
		return
	var surface := proj.global_position - proj.stuck_normal * 0.38
	if surface.distance_to(center) > trigger_distance:
		return
	mark()
	var p := h.player
	var height := maxf(0.0, (power - 0.25) * 14.0)
	var r := (p.slam_base_radius + height * p.slam_radius_per_meter) * radius_mult
	var dmg := (p.slam_base_damage + height * p.slam_damage_per_meter) * damage_mult
	var knock := p.slam_base_knockback + height * p.slam_knockback_per_meter
	var parent := p.get_parent()
	var tree := p.get_tree()
	tree.create_timer(wave_delay, false).timeout.connect(func() -> void: _wave(parent, surface, r, dmg, knock))
	if level >= 2:
		tree.create_timer(third_wave_delay, false).timeout.connect(func() -> void:
			_wave(parent, surface, r * third_wave_radius_mult, dmg * 0.75, knock))

func _wave(parent: Node, center: Vector3, radius: float, damage: float, knock: float) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var space := (parent as Node3D).get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, center)
	q.collision_mask = (1 << 2) | (1 << 3) | (1 << 6)
	for hit in space.intersect_shape(q, 64):
		var c: Object = hit.collider
		if c == null or not (c is Node3D):
			continue
		var dir := (c as Node3D).global_position - center
		dir.y = 0
		var dist := dir.length()
		dir = dir / dist if dist > 0.01 else Vector3.FORWARD
		var falloff := clampf(1.0 - dist / radius, 0.35, 1.0)
		var push := dir * knock * falloff + Vector3.UP * knock * 0.55 * falloff
		if c.has_method("take_hit"):
			c.take_hit(damage * falloff, push, "slam")
		elif c is RigidBody3D:
			(c as RigidBody3D).apply_central_impulse(push * (c as RigidBody3D).mass * 0.6)
	FX.ring(parent, center, radius, Color(0.6, 0.85, 1.0, 0.9), 0.4)
	FX.burst(parent, center + Vector3(0, 0.3, 0), radius * 0.3, Color(0.6, 0.85, 1.0, 0.45), 0.25)
	FX.sparks(parent, center + Vector3(0, 0.2, 0), Color(0.55, 0.47, 0.4), 26, 9.0, 18.0, 0.14, 0.7)
	FX.hitstop(0.05)
	if hand and is_instance_valid(hand) and hand.player:
		hand.player.camera_fx.add_trauma(0.35)
	Audio.play("sounds/sfx/slam.wav")
