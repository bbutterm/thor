extends RefCounted
class_name PlayerJumps
## Прыжки (обычный, воздушный, супер-прыжок, в окне отскока), гравитация, прыжок по головам,
## залезание на уступ, отскок от стены, подброс прыжковой руной.
## Компонент игрока (этап 2 рефакторинга): числа и состояние — поля Player (их ставят сцена, тела
## и тесты), здесь только логика. Доступ — player.jumps; публичные функции есть и на Player.

var p: Player

func _init(player: Player) -> void:
	p = player

func _process_jump(on_floor: bool) -> void:
	if p._jump_buffer_left <= 0.0:
		return
	if p._bounce_window_left > 0.0:
		# Прыжок в окне отскока от удара-приземления — подбрасывает выше
		p._jump_buffer_left = 0.0
		p._bounce_window_left = 0.0
		p._slam_ready = true
		p.velocity.y = maxf(p.velocity.y, p._bounce_boost_velocity)
		p.camera_fx.kick_fov(8.0)
		Audio.play("sounds/sfx/super_jump.wav")
		Perf.mark("slam_bounce_boost")
		return
	if p._super_jump_left > 0.0:
		p._jump_buffer_left = 0.0
		p._super_jump_left = 0.0
		p._slam_ready = true
		p.velocity.y = p.jump_velocity * sqrt(p.super_jump_height_mult)
		p.camera_fx.kick_fov(10.0)
		p.camera_fx.add_trauma(0.25)
		Audio.play("sounds/sfx/super_jump.wav")
		FX.ring(p.get_parent(), p.global_position, 2.0, Color(0.6, 0.85, 1.0, 0.8), 0.3)
		return
	if on_floor or p._coyote_left > 0.0:
		p._jump_buffer_left = 0.0
		p._coyote_left = 0.0
		p._slam_ready = false
		p.velocity.y = p.jump_velocity
		Audio.play("sounds/jump_a.ogg, sounds/jump_b.ogg")
		if p.is_sliding:
			# Прыжок из подката: скорость подката сохраняется (bunny-hop)
			p.is_sliding = false
			Perf.mark("slide_jump")
		for h in p.body_handlers:
			h.on_jump(p)
	elif p._jumps_left > 0 and p.dash_charges > 0:
		p._jump_buffer_left = 0.0
		p._jumps_left -= 1
		p.dash._spend_dash_charge()
		p._slam_ready = true
		# Крылья валькирии ур. 2+: прыжки в воздухе выше
		p.velocity.y = p.jump_velocity * 0.92 * (Run.rune_value("valkyrie_wings", true) if Run.rune_level("valkyrie_wings") > 0 else 1.0)
		p.camera_fx.kick_fov(3.0)
		Audio.sfx("double_jump", "sounds/jump_b.ogg, sounds/jump_c.ogg")
	elif p._wall_jumps_left > 0 and _try_wall_jump():
		# Отскок от стены бесплатный, когда воздушных прыжков или рун не осталось.
		p._jump_buffer_left = 0.0

func _process_gravity(on_floor: bool, delta: float) -> void:
	if on_floor and p.velocity.y <= 0.0:
		p.velocity.y = -0.5
		return
	var g := p.gravity * (p.fall_gravity_mult if p.velocity.y < 0.0 else 1.0)
	p.velocity.y -= g * delta
	p.velocity.y = maxf(p.velocity.y, -45.0)

## Приземлился на врага сверху (без удара-приземления) — отскок, как в Mario.
func _check_stomp(pre_velocity: Vector3) -> void:
	if p._stomp_cooldown > 0.0 or p.is_slamming or pre_velocity.y > -1.0 or not can_stomp():
		return
	for i in p.get_slide_collision_count():
		var col := p.get_slide_collision(i)
		var e := col.get_collider() as Enemy
		if e == null or e.is_dead or col.get_normal().y < 0.6:
			continue
		p.deal_damage(e, p.stomp_damage, Vector3(0, -1, 0), "stomp")
		if e.has_method("stun"):
			e.stun(p.stomp_stun)
		p.velocity.y = p.stomp_bounce_velocity
		p._slam_ready = true
		p._jumps_left = p.extra_jumps
		p._air_peak_y = p.global_position.y
		p._stomp_cooldown = 0.2
		p.camera_fx.add_trauma(0.12)
		FX.ring(p.get_parent(), e.global_position + Vector3(0, 1.8 * e.model_scale, 0), 0.8, Color(1, 0.95, 0.7, 0.8), 0.2)
		Audio.sfx("helmet_bonk", "sounds/jump_b.ogg")
		Perf.mark("stomp")
		StyleMeter.event(&"stomp")
		return

## Прыжок по головам и залезание зависят от оружия в руке (этап 1): с ренжем по головам не прыгаем.
func can_stomp() -> bool:
	return not (p.has_method("is_ranged_active") and p.call("is_ranged_active"))

## Край на уровне груди или чуть выше, игрок жмёт вперёд в стену — залезаем сами за ledge_climb_time.
func _check_ledge(wish: Vector3) -> void:
	if p._climb_check_cooldown > 0.0 or p.is_slamming or p._dash_time_left > 0.0 or wish == Vector3.ZERO:
		return
	if p.velocity.y > 4.0:
		return
	var fwd := -p.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	if wish.dot(fwd) < 0.5:
		return
	var space := p.get_world_3d().direct_space_state
	var base := p.global_position
	# 1) Стена перед грудью
	var chest := PhysicsRayQueryParameters3D.create(base + Vector3(0, 1.0, 0), base + Vector3(0, 1.0, 0) + fwd * 0.75, 1)
	chest.exclude = [p.get_rid()]
	var wall := space.intersect_ray(chest)
	if wall.is_empty() or absf((wall.normal as Vector3).y) > 0.3:
		return
	# 2) Верх уступа: луч вниз чуть за стеной
	var probe_xz: Vector3 = (wall.position as Vector3) + fwd * 0.4
	var top_q := PhysicsRayQueryParameters3D.create(Vector3(probe_xz.x, base.y + p.ledge_max_height + 0.3, probe_xz.z), Vector3(probe_xz.x, base.y + p.ledge_min_height - 0.05, probe_xz.z), 1)
	top_q.exclude = [p.get_rid()]
	var top := space.intersect_ray(top_q)
	if top.is_empty() or (top.normal as Vector3).y < 0.7:
		return
	var top_y: float = (top.position as Vector3).y
	var h := top_y - base.y
	if h < p.ledge_min_height or h > p.ledge_max_height:
		return
	# 3) Место наверху: капсула игрока помещается
	var dest := Vector3(probe_xz.x, top_y + 0.05, probe_xz.z) + fwd * 0.2
	var col := p.get_node_or_null("Collider") as CollisionShape3D
	if col and col.shape:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = col.shape
		q.transform = Transform3D(Basis.IDENTITY, dest + col.position + Vector3(0, 0.05, 0))
		q.collision_mask = 1
		q.exclude = [p.get_rid()]
		if not space.intersect_shape(q, 1).is_empty():
			return
	_start_climb(dest)

## Отскок от стены: стена рядом (лучи по 8 направлениям на уровне груди) — толчок от неё и вверх.
func _try_wall_jump() -> bool:
	var space := p.get_world_3d().direct_space_state
	var origin := p.global_position + Vector3(0, 1.0, 0)
	var best_n := Vector3.ZERO
	var best_d := 0.75
	for i in 8:
		var a := TAU * i / 8.0
		var dir := Vector3(cos(a), 0, sin(a))
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 0.75, 1)
		q.exclude = [p.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.3:
			continue
		var d := origin.distance_to(hit.position)
		if d < best_d:
			best_d = d
			best_n = hit.normal
	if best_n == Vector3.ZERO:
		return false
	p._wall_jumps_left -= 1
	var n := Vector3(best_n.x, 0, best_n.z).normalized()
	var horiz := Vector3(p.velocity.x, 0, p.velocity.z)
	# Гасим скорость в стену, добавляем толчок от неё
	horiz -= n * minf(horiz.dot(n), 0.0)
	horiz += n * p.wall_jump_push * p.wall_jump_mult
	p.velocity = Vector3(horiz.x, p.wall_jump_up * p.wall_jump_mult, horiz.z)
	p.camera_fx.kick_fov(4.0)
	FX.ring(p.get_parent(), p.global_position + Vector3(0, 1.0, 0) - n * best_d, 0.6, Color(0.8, 0.9, 1.0, 0.7), 0.2)
	Audio.play("sounds/jump_b.ogg, sounds/jump_c.ogg")
	Perf.mark("wall_jump")
	return true

func _start_climb(dest: Vector3) -> void:
	p.skills.weapon_skill_cancel_motion()
	p.is_climbing = true
	p._climb_t = 0.0
	p._climb_time = p.ledge_climb_time * (p.ledge_climb_ranged_mult if (p.has_method("is_ranged_active") and p.call("is_ranged_active")) else 1.0)
	p._climb_from = p.global_position
	p._climb_mid = Vector3(p.global_position.x, dest.y + 0.1, p.global_position.z)
	p._climb_to = dest
	p.velocity = Vector3.ZERO
	p.camera_fx.land_dip(0.12)
	Audio.play("sounds/jump_a.ogg")
	Perf.mark("ledge_climb")

func _process_climb(delta: float) -> void:
	p._climb_t += delta
	var k := clampf(p._climb_t / maxf(p._climb_time, 0.01), 0.0, 1.0)
	# Сначала вверх (60 % времени), потом вперёд на уступ
	if k < 0.6:
		p.global_position = p._climb_from.lerp(p._climb_mid, ease(k / 0.6, 0.6))
	else:
		p.global_position = p._climb_mid.lerp(p._climb_to, (k - 0.6) / 0.4)
	if k >= 1.0:
		p.is_climbing = false
		p._slam_ground_contacts += 1
		p._weapon_skill_landing_used = false
		p._climb_check_cooldown = 0.3
		var fwd := -p.global_transform.basis.z
		fwd.y = 0
		p.velocity = fwd.normalized() * 3.0
		p._jumps_left = p.extra_jumps
		p._air_peak_y = p.global_position.y
		p._was_on_floor = true

## Подброс прыжковой руной (rooms/jump_pad.gd): на height метров, прыжки в воздухе восстановлены, удар-приземление прерван.
func launch_up(height: float) -> void:
	p.skills.weapon_skill_cancel_motion()
	if p.is_slamming:
		p.slam._cancel_slam()
	p._dash_time_left = 0.0
	p.dash._end_ram()
	p.velocity.y = sqrt(2.0 * p.gravity * maxf(height, 0.5))
	p._slam_ready = true
	p._jumps_left = p.extra_jumps
	p._wall_jumps_left = p.wall_jumps
	p._coyote_left = 0.0
	p.camera_fx.kick_fov(10.0)
	p.camera_fx.speed_lines_pulse()
