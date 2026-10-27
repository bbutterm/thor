extends MjolnirElementHandler
## Стихия «Земля» (блок Б4, GDD 10) — бывшие «Тяжесть» и «Землетрясение».
## 1 — «Тяжесть»: попадание прибивает врага к полу и оглушает (со 2-го уровня — и всех в радиусе 2 м,
##     бывший ур. 2); удар-приземление рядом с прибитыми даёт вторую волну.
## 2 — след: разлом вдоль полёта — наступивший падает (короткий стан).
## 3 — «Землетрясение»: воткнутый молот трясёт землю вокруг, а удар-приземление в 5 м от него даёт волну
##     у молота. 4 — третья волна (бывший ур. 2 «Землетрясения») и глыба с неба при идеальном хвате.

@export_group("1. При попадании: прибить")
@export var pin_time: float = 1.5
## Со 2-го уровня: оглушает и всех в этом радиусе от цели
@export var splash_radius: float = 2.0

@export_group("Связка: вторая волна")
## Удар-приземление не дальше (радиус удара + столько) от прибитого врага — вторая волна в точке удара
@export var pinned_reach: float = 3.0
@export var wave_delay: float = 0.12
@export var radius_mult: float = 1.0
@export var damage_mult: float = 1.0
## 4-й уровень: третья волна
@export var third_wave_delay: float = 0.35
@export var third_wave_radius_mult: float = 1.4

@export_group("2. След: разлом")
@export var trail_pin: float = 0.6

@export_group("3. Землетрясение у воткнутого молота")
## Насколько близко к воткнутому молоту надо приземлиться (м)
@export var quake_trigger_distance: float = 5.0
## Дрожь земли раз в aura_interval прибивает вокруг молота на столько секунд
@export var aura_pin: float = 0.5

@export_group("4. Глыба с неба")
@export var sky_pin: float = 1.5

func apply_element(enemy: Enemy, power: float, _from: Vector3, _proj: MjolnirProjectile) -> void:
	var s := ElementStatus.of(enemy, true)
	if s == null:
		return
	var parent := enemy.get_parent()
	s.pin(pin_time * clampf(power, 0.4, 1.0))
	FX.ring(parent, enemy.global_position + Vector3(0, 0.05, 0), 1.2, Color(0.6, 0.55, 0.45, 0.8), 0.3)
	if level >= LVL_TRAIL and power >= 1.0:
		for other in enemies_near(enemy.get_tree(), enemy.global_position + Vector3(0, 0.9, 0), splash_radius):
			if other != enemy:
				var os := ElementStatus.of(other, true)
				if os:
					os.pin(pin_time)
		FX.ring(parent, enemy.global_position + Vector3(0, 0.05, 0), splash_radius, Color(0.6, 0.55, 0.45, 0.6), 0.4)

func make_trail_zone(parent: Node, pos: Vector3, _proj: MjolnirProjectile) -> Node3D:
	var z := ElementZone.new()
	parent.add_child(z)
	z.setup(pos, trail_radius, trail_duration, Color(0.55, 0.42, 0.3, 0.7), _trail_trip, true, 0.1)
	FX.crack(parent, pos, 0.0)
	return z

## Дрожь земли и разлом не достают тех, кто в воздухе (летит после удара, прыгает)
static func _grounded(e: Enemy) -> bool:
	return e.is_on_floor() or absf(e.velocity.y) < 0.5

func _trail_trip(enemy: Enemy, _zone: ElementZone) -> void:
	if not _grounded(enemy):
		return
	var s := ElementStatus.of(enemy, true)
	if s:
		s.pin(trail_pin)
	FX.sparks(enemy.get_parent(), enemy.global_position + Vector3(0, 0.2, 0), Color(0.55, 0.47, 0.4), 8, 3.0)

func aura_pulse(proj: MjolnirProjectile) -> void:
	var c := proj.global_position - proj.stuck_normal * 0.38
	var parent := proj.fx_parent()
	FX.ring(parent, c, aura_radius, Color(0.6, 0.5, 0.4, 0.7), 0.35)
	FX.sparks(parent, c + Vector3(0, 0.2, 0), Color(0.55, 0.47, 0.4), 14, 5.0, 18.0, 0.1, 0.5)
	for e in enemies_near(proj.get_tree(), c + Vector3(0, 0.9, 0), aura_radius):
		if not _grounded(e):
			continue
		hurt(e, aura_damage * proj.damage_mult, Vector3.ZERO, "hammer")
		var s := ElementStatus.of(e, true)
		if s:
			s.pin(aura_pin)
	if hand and hand.player:
		hand.player.camera_fx.add_trauma(0.06)

func sky_strike(point: Vector3) -> void:
	var p := player()
	var parent := p.get_parent()
	FX.burst(parent, point + Vector3(0, 0.6, 0), sky_radius * 0.5, Color(0.55, 0.45, 0.35, 0.75), 0.3)
	FX.shockwave(parent, point, sky_radius * 1.2)
	FX.crack(parent, point, 12.0)
	FX.sparks(parent, point + Vector3(0, 0.3, 0), Color(0.55, 0.47, 0.4), 30, 10.0, 18.0, 0.14, 0.7)
	for e in enemies_near(p.get_tree(), point, sky_radius + 0.9):
		hurt(e, sky_damage, Vector3.UP * 2.0, "slam")
		var s := ElementStatus.of(e, true)
		if s:
			s.pin(sky_pin)
	ComicFX.pop("quake", point + Vector3(0, 1.0, 0), true)
	p.camera_fx.add_trauma(0.4)
	Audio.play("sounds/sfx/slam.wav")

## Удар-приземление: вторая волна в точке удара, если рядом прибитые; с 3-го уровня — волна у воткнутого молота
## (бывшее «Землетрясение»), с 4-го — ещё и третья
func slam_combo(power: float, center: Vector3) -> void:
	var p := player()
	if p == null:
		return
	var r := slam_radius(power) * radius_mult
	var dmg := slam_damage(power) * damage_mult
	var knock := p.slam_base_knockback + slam_height(power) * p.slam_knockback_per_meter
	var points: Array[Vector3] = []
	var pinned := enemies_with(center, slam_radius(power) + pinned_reach, func(e: Enemy) -> bool: return ElementStatus.is_pinned(e))
	if not pinned.is_empty():
		points.append(center)
	if level >= LVL_AURA:
		var proj := hand.projectile
		if proj and is_instance_valid(proj) and proj.is_stuck():
			var surface := proj.global_position - proj.stuck_normal * 0.38
			if surface.distance_to(center) <= quake_trigger_distance:
				points.append(surface)
	if points.is_empty():
		return
	mark("wave")
	StyleMeter.event(&"element_slam")
	var parent := p.get_parent()
	var tree := p.get_tree()
	for pt in points:
		tree.create_timer(wave_delay, false).timeout.connect(func() -> void: _wave(parent, pt, r, dmg, knock))
		if level >= LVL_SKY:
			tree.create_timer(third_wave_delay, false).timeout.connect(func() -> void:
				_wave(parent, pt, r * third_wave_radius_mult, dmg * 0.75, knock))

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
			hurt(c, damage * falloff, push, "slam")
		elif c is RigidBody3D:
			(c as RigidBody3D).apply_central_impulse(push * (c as RigidBody3D).mass * 0.6)
	FX.ring(parent, center, radius, Color(0.75, 0.6, 0.4, 0.9), 0.4)
	FX.shockwave(parent, center, radius)
	FX.sparks(parent, center + Vector3(0, 0.2, 0), Color(0.55, 0.47, 0.4), 26, 9.0, 18.0, 0.14, 0.7)
	ComicFX.pop("quake", center + Vector3(0, 1.0, 0))
	FX.hitstop(0.05)
	if hand and is_instance_valid(hand) and hand.player:
		hand.player.camera_fx.add_trauma(0.35)
	Audio.play("sounds/sfx/slam.wav")

## Земля: трещина и пыль под целью
func hit_signature(enemy: Enemy, proj: MjolnirProjectile, _chest: Vector3) -> void:
	var parent := proj.fx_parent()
	FX.crack(parent, enemy.global_position, 0.0)
	FX.smoke(parent, enemy.global_position + Vector3(0, 0.3, 0), 1.4, Color(0.55, 0.42, 0.3, 0.8))
