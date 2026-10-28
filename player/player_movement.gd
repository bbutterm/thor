extends RefCounted
class_name PlayerMovement
## Бег по земле и в воздухе, предел импульса, подкат, толчок тел, шаги, стиль движения тела.
## Компонент игрока (этап 2 рефакторинга): числа и состояние — поля Player (их ставят сцена, тела
## и тесты), здесь только логика. Доступ — player.movement; публичные функции есть и на Player.

var p: Player

func _init(player: Player) -> void:
	p = player

func _process_walk(wish: Vector3, on_floor: bool, delta: float) -> void:
	# Скорость бега с учётом оружия в руке (мили быстрее, ренж медленнее)
	var ms := p.effective_move_speed()
	var horiz := Vector3(p.velocity.x, 0, p.velocity.z)
	var target := wish * ms
	var speed := horiz.length()
	# Управление в воздухе — 70 % от наземного (GDD 7.4)
	var air_accel := p.ground_accel * p.air_control
	var air_drag := 0.0 if p.keep_air_momentum else p.air_overspeed_drag
	if on_floor:
		if speed > ms * 1.05:
			# Скорость выше нормы (после рывка/супер-прыжка) — гасим плавно
			horiz = horiz.move_toward(target, p.ground_overspeed_drag * delta)
		elif wish != Vector3.ZERO:
			horiz = horiz.move_toward(target, p.ground_accel * delta)
		else:
			horiz = horiz.move_toward(Vector3.ZERO, p.ground_decel * delta)
	else:
		if wish != Vector3.ZERO:
			if speed > ms:
				# Сохраняем инерцию, но позволяем рулить
				var steered := horiz.move_toward(wish * speed, air_accel * delta)
				horiz = steered.normalized() * maxf(ms, speed - air_drag * delta)
			else:
				horiz = horiz.move_toward(target, air_accel * delta)
		elif speed > ms:
			horiz = horiz.move_toward(horiz.normalized() * ms, air_drag * delta)
	# Импульс складывается, но не выше предела (GDD 7.4)
	horiz = horiz.limit_length(momentum_limit())
	p.velocity.x = horiz.x
	p.velocity.z = horiz.z

## Предел горизонтальной скорости от импульсов (GDD 7.4)
func momentum_limit() -> float:
	return p.effective_move_speed() * p.momentum_cap

func _start_slide(dir: Vector3, speed: float) -> void:
	p.is_sliding = true
	p._slide_dir = dir
	p._slide_speed = minf(speed, momentum_limit())
	p._slide_left = p.slide_duration
	p.camera_fx.kick_fov(6.0)
	Audio.play("sounds/sfx/dash.wav")
	Perf.mark("slide")

func _process_slide(wish: Vector3, on_floor: bool, delta: float) -> void:
	p._slide_left -= delta
	p._slide_speed = maxf(0.0, p._slide_speed - p.slide_friction * delta)
	if wish != Vector3.ZERO:
		var ang := p._slide_dir.signed_angle_to(wish, Vector3.UP)
		p._slide_dir = p._slide_dir.rotated(Vector3.UP, clampf(ang, -p.slide_steer * delta, p.slide_steer * delta)).normalized()
	p.velocity.x = p._slide_dir.x * p._slide_speed
	p.velocity.z = p._slide_dir.z * p._slide_speed
	if not on_floor or p._slide_left <= 0.0 or p._slide_speed < p.effective_move_speed() * p.slide_min_speed_ratio:
		# Слетел с края или подкат кончился — скорость остаётся, дальше обычный бег/полёт
		p.is_sliding = false

func _push_rigid_bodies(pre_velocity: Vector3) -> void:
	for i in p.get_slide_collision_count():
		var col := p.get_slide_collision(i)
		var body := col.get_collider() as RigidBody3D
		if body == null:
			continue
		var speed := pre_velocity.length()
		var dir := -col.get_normal()
		dir.y = maxf(dir.y, 0.15)
		var dashing := p._dash_time_left > 0.0
		if dashing and body is Destructible and not p._dash_hit.has(body.get_instance_id()):
			# Рывок в бочку/ящик — ломает (один раз за рывок)
			p._dash_hit[body.get_instance_id()] = true
			(body as Destructible).take_hit(PropDebris.cfg().dash_damage, p._dash_dir * 8.0 + Vector3.UP * 2.0, "dash")
			continue
		var force := p.push_force * (speed * (2.2 if dashing else 0.35))
		body.apply_central_impulse(dir.normalized() * force)

func _update_footsteps(on_floor: bool) -> void:
	var moving := Vector2(p.velocity.x, p.velocity.z).length() > 1.5
	p.footsteps.stream_paused = not (on_floor and moving and p._dash_time_left <= 0.0)

## Кладёт числа и флаги стиля в поля игрока. Заряды рывка — у тела (BodyDef.dash_charges).
func apply_movement_profile(mp: MovementProfile) -> void:
	if mp == null:
		return
	p.movement_profile = mp
	p.dash_speed = mp.dash_speed
	p.dash_duration = mp.dash_duration
	p.dash_recharge = mp.dash_recharge
	p.dash_on_ground = mp.dash_on_ground
	p.dash_in_air = mp.dash_in_air
	p.dash_ram = mp.dash_ram
	p.ram_damage = mp.ram_damage
	p.ram_knockback = mp.ram_knockback
	p.ram_knock_up = mp.ram_knock_up
	p.ram_radius = mp.ram_radius
	p.ram_prop_impulse = mp.ram_prop_impulse
	p.dash_to_slide = mp.dash_to_slide
	p.slide_friction = mp.slide_friction
	p.extra_jumps = mp.extra_jumps
	p._jumps_left = p.extra_jumps
	p.wall_jumps = mp.wall_jumps
	p._wall_jumps_left = p.wall_jumps
	p.wall_jump_mult = mp.wall_jump_mult
	p.slam_radius_mult = mp.slam_radius_mult
	p.slam_damage_mult = mp.slam_damage_mult
	p.slam_stun = mp.slam_stun
	p.slam_bounce_mult = mp.slam_bounce_mult
	p.momentum_cap = mp.momentum_cap
	p.keep_air_momentum = mp.keep_air_momentum

func movement_style() -> String:
	return p.movement_profile.id if p.movement_profile else "base"
