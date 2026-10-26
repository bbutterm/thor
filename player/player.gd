extends CharacterBody3D
class_name Player
## Тор в теле смертного. Движение: бег, двойной прыжок, рывок, удар-приземление, супер-прыжок.
## Все «ощущенческие» числа — в группах @export ниже (см. TUNING.md).

signal health_changed(current: float, maximum: float)
signal dash_charges_changed(current: int, maximum: int, recharge_progress: float)
signal died
signal hurt(amount: float)
signal slammed(power: float)

@export_group("Бег")
@export var move_speed: float = 8.0
@export var ground_accel: float = 70.0
@export var ground_decel: float = 55.0
@export var air_accel: float = 28.0
## Насколько быстро гасится скорость выше обычной в воздухе (после рывка)
@export var air_overspeed_drag: float = 6.0
## Насколько быстро гасится скорость выше обычной на земле
@export var ground_overspeed_drag: float = 18.0

@export_group("Прыжок")
@export var jump_velocity: float = 9.0
@export var extra_jumps: int = 1
@export var gravity: float = 24.0
@export var fall_gravity_mult: float = 1.35
@export var coyote_time: float = 0.1
@export var jump_buffer: float = 0.1

@export_group("Рывок")
@export var dash_charges_base: int = 2
@export var dash_speed: float = 24.0
@export var dash_duration: float = 0.16
@export var dash_recharge: float = 1.2
@export var dash_invuln: float = 0.15
## Скорость, которая остаётся после рывка (доля от dash_speed)
@export var dash_exit_keep: float = 0.55
@export var dash_damage: float = 15.0

@export_group("Удар-приземление и супер-прыжок")
@export var slam_speed: float = 34.0
@export var slam_base_radius: float = 3.5
@export var slam_radius_per_meter: float = 0.25
@export var slam_base_damage: float = 20.0
@export var slam_damage_per_meter: float = 3.0
@export var slam_base_knockback: float = 10.0
@export var slam_knockback_per_meter: float = 0.8
@export var super_jump_window: float = 0.25
## Во сколько раз выше обычного прыжка (по высоте)
@export var super_jump_height_mult: float = 2.5

@export_group("Прыжки по GDD 7.2")
## Отскок от удара-приземления, если задет хотя бы один враг (доля высоты падения)
@export var slam_bounce_ratio: float = 0.6
## Минимальная высота отскока (м) — даже после низкого удара-приземления
@export var slam_bounce_min_height: float = 1.2
## Окно (с) после отскока: нажал прыжок — подбросит выше
@export var slam_bounce_window: float = 0.2
## Во сколько раз выше подбрасывает прыжок в окне отскока
@export var slam_bounce_boost: float = 1.6
## Прыжок по головам: урон (0.5 У), стан, скорость отскока вверх
@export var stomp_damage: float = 11.0
@export var stomp_stun: float = 0.8
@export var stomp_bounce_velocity: float = 9.5
## Залезание на уступ: высота края над ступнями (м) и время
@export var ledge_min_height: float = 0.75
@export var ledge_max_height: float = 2.2
@export var ledge_climb_time: float = 0.3
## С ренжем в руке залезание дольше (GDD 7.4)
@export var ledge_climb_ranged_mult: float = 1.5
## Отскок от стены в воздухе: сколько раз до касания земли, сила от стены и вверх
@export var wall_jumps: int = 2
@export var wall_jump_push: float = 7.0
@export var wall_jump_up: float = 8.5

@export_group("Физика толчков")
@export var push_force: float = 1.6

@export_group("Здоровье")
@export var max_health: float = 100.0
## Лечение за каждое убийство — поощряет агрессию
@export var heal_per_kill: float = 3.0
## Дополнительное лечение, если добил мили (GDD 8: +2 HP)
@export var melee_kill_heal: float = 2.0

var health: float = 100.0
var is_dead: bool = false
var input_enabled: bool = true

var dash_charges: int = 2
var dash_charges_max: int = 2
var _dash_recharge_timer: float = 0.0
var _dash_time_left: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _invuln_left: float = 0.0
var _dash_hit: Dictionary = {}

var _jumps_left: int = 1
var _coyote_left: float = 0.0
var _jump_buffer_left: float = 0.0
var _was_on_floor: bool = true

var is_slamming: bool = false
## Сколько врагов задел последний удар-приземление (для отскока)
var _last_slam_hits: int = 0
var _bounce_window_left: float = 0.0
var _bounce_boost_velocity: float = 0.0
var _stomp_cooldown: float = 0.0
var is_climbing: bool = false
var _climb_t: float = 0.0
var _climb_time: float = 0.3
var _climb_from: Vector3
var _climb_mid: Vector3
var _climb_to: Vector3
var _climb_check_cooldown: float = 0.0
var _wall_jumps_left: int = 2
var _super_jump_left: float = 0.0
## Самая высокая точка текущего пребывания в воздухе — для силы приземления
var _air_peak_y: float = 0.0

var rotation_target: Vector2 = Vector2.ZERO
var mouse_sensitivity: float = 0.0022
var gamepad_sensitivity: float = 3.0

var axe_damage_mult: float = 1.0
var hammer_damage_mult: float = 1.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var camera_fx: CameraFX = $Head/Camera
@onready var axe: Axe = $Axe
@onready var mjolnir: MjolnirHand = $Mjolnir
@onready var footsteps: AudioStreamPlayer = $Footsteps
## Слоты оружия правой руки (мили + ренж), см. weapons/weapon_holder.gd
var weapons: WeaponHolder

func _ready() -> void:
	add_to_group("player")
	_setup_weapons()
	health = max_health
	dash_charges_max = dash_charges_base
	dash_charges = dash_charges_max
	rotation_target = Vector2(head.rotation.x, rotation.y)
	_emit_all()

## Применяет параметры тела (BodyDef) и руны забега.
func apply_body_and_runes(body: BodyDef, run: Node) -> void:
	if body:
		max_health = body.max_health
		move_speed = body.move_speed
		dash_charges_base = body.dash_charges
		axe_damage_mult = body.axe_damage_mult
		hammer_damage_mult = body.hammer_damage_mult
		axe.set_hand_color(body.hand_color, body.sleeve_color)
		mjolnir.set_hand_color(body.hand_color, body.sleeve_color)
		weapons.apply_body(body)
	recalc_from_runes(run, true)

func recalc_from_runes(run: Node, full_heal: bool = false) -> void:
	var body: BodyDef = run.body if run else null
	var base_hp := body.max_health if body else max_health
	var old_max := max_health
	max_health = base_hp + 30.0 * run.rune_count("max_health")
	dash_charges_max = (body.dash_charges if body else dash_charges_base) + run.rune_count("dash_charge")
	axe.damage_mult = (body.axe_damage_mult if body else 1.0) * pow(1.25, run.rune_count("axe_damage"))
	var hammer_runes: int = run.rune_count("hammer_power")
	mjolnir.damage_mult = (body.hammer_damage_mult if body else 1.0) * pow(1.4, hammer_runes)
	mjolnir.return_speed_mult = pow(1.3, hammer_runes)
	if full_heal:
		health = max_health
		dash_charges = dash_charges_max
	else:
		health = minf(max_health, health + maxf(0.0, max_health - old_max))
		dash_charges = mini(dash_charges + 1, dash_charges_max)
	_emit_all()

func _emit_all() -> void:
	health_changed.emit(health, max_health)
	dash_charges_changed.emit(dash_charges, dash_charges_max, 0.0)

# --- Ввод мышью ---

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or is_dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotation_target.y -= motion.relative.x * mouse_sensitivity
		rotation_target.x -= motion.relative.y * mouse_sensitivity
		rotation_target.x = clampf(rotation_target.x, deg_to_rad(-89), deg_to_rad(89))

func _process(delta: float) -> void:
	if not input_enabled or is_dead:
		return
	var look := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if look != Vector2.ZERO:
		rotation_target.y -= look.x * gamepad_sensitivity * delta
		rotation_target.x -= look.y * gamepad_sensitivity * delta
		rotation_target.x = clampf(rotation_target.x, deg_to_rad(-89), deg_to_rad(89))
	rotation.y = rotation_target.y
	head.rotation.x = rotation_target.x

# --- Физика ---

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity.x = move_toward(velocity.x, 0, ground_decel * delta)
		velocity.z = move_toward(velocity.z, 0, ground_decel * delta)
		velocity.y -= gravity * delta
		move_and_slide()
		return

	var input_dir := Vector2.ZERO
	if input_enabled:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := (transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	wish.y = 0
	wish = wish.normalized() if wish.length() > 0.01 else Vector3.ZERO

	_update_timers(delta)
	if is_climbing:
		_process_climb(delta)
		camera_fx.update_motion(self, input_dir, false, delta)
		return
	var on_floor := is_on_floor()

	if on_floor:
		_coyote_left = coyote_time
		_jumps_left = extra_jumps
		_wall_jumps_left = wall_jumps
	if input_enabled and Input.is_action_just_pressed("jump"):
		_jump_buffer_left = jump_buffer

	# Рывок
	if input_enabled and Input.is_action_just_pressed("dash") and dash_charges > 0 and not is_slamming:
		_start_dash(wish)

	# Удар-приземление
	if input_enabled and Input.is_action_just_pressed("slam") and not on_floor and not is_slamming:
		_start_slam()

	if _dash_time_left > 0.0:
		_process_dash(delta)
	elif is_slamming:
		velocity = Vector3(0, -slam_speed, 0)
	else:
		_process_walk(wish, on_floor, delta)
		_process_jump(on_floor)
		_process_gravity(on_floor, delta)

	var pre_velocity := velocity
	move_and_slide()
	_push_rigid_bodies(pre_velocity)
	_check_stomp(pre_velocity)
	_check_ledge(wish)

	var now_on_floor := is_on_floor()
	if not now_on_floor:
		_air_peak_y = maxf(_air_peak_y, global_position.y)
	if now_on_floor and not _was_on_floor:
		_on_landed()
	if now_on_floor:
		_air_peak_y = global_position.y
	_was_on_floor = now_on_floor

	_update_footsteps(now_on_floor)
	camera_fx.update_motion(self, input_dir, now_on_floor, delta)

	if global_position.y < -25.0:
		take_damage(9999.0, Vector3.ZERO, true)

func _update_timers(delta: float) -> void:
	_coyote_left = maxf(0.0, _coyote_left - delta)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	_invuln_left = maxf(0.0, _invuln_left - delta)
	_super_jump_left = maxf(0.0, _super_jump_left - delta)
	_bounce_window_left = maxf(0.0, _bounce_window_left - delta)
	_stomp_cooldown = maxf(0.0, _stomp_cooldown - delta)
	_climb_check_cooldown = maxf(0.0, _climb_check_cooldown - delta)
	if dash_charges < dash_charges_max:
		_dash_recharge_timer += delta
		if _dash_recharge_timer >= dash_recharge * weapon_dash_recharge_mult():
			_dash_recharge_timer = 0.0
			dash_charges += 1
		dash_charges_changed.emit(dash_charges, dash_charges_max, _dash_recharge_timer / (dash_recharge * weapon_dash_recharge_mult()))
	else:
		_dash_recharge_timer = 0.0

func _process_walk(wish: Vector3, on_floor: bool, delta: float) -> void:
	# Скорость бега с учётом оружия в руке (мили быстрее, ренж медленнее)
	var ms := effective_move_speed()
	var horiz := Vector3(velocity.x, 0, velocity.z)
	var target := wish * ms
	var speed := horiz.length()
	if on_floor:
		if speed > ms * 1.05:
			# Скорость выше нормы (после рывка/супер-прыжка) — гасим плавно
			horiz = horiz.move_toward(target, ground_overspeed_drag * delta)
		elif wish != Vector3.ZERO:
			horiz = horiz.move_toward(target, ground_accel * delta)
		else:
			horiz = horiz.move_toward(Vector3.ZERO, ground_decel * delta)
	else:
		if wish != Vector3.ZERO:
			if speed > ms:
				# Сохраняем инерцию, но позволяем рулить
				var steered := horiz.move_toward(wish * speed, air_accel * delta)
				horiz = steered.normalized() * maxf(ms, speed - air_overspeed_drag * delta)
			else:
				horiz = horiz.move_toward(target, air_accel * delta)
		elif speed > ms:
			horiz = horiz.move_toward(horiz.normalized() * ms, air_overspeed_drag * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

func _process_jump(on_floor: bool) -> void:
	if _jump_buffer_left <= 0.0:
		return
	if _bounce_window_left > 0.0:
		# Прыжок в окне отскока от удара-приземления — подбрасывает выше
		_jump_buffer_left = 0.0
		_bounce_window_left = 0.0
		velocity.y = maxf(velocity.y, _bounce_boost_velocity)
		camera_fx.kick_fov(8.0)
		Audio.play("sounds/sfx/super_jump.wav")
		Perf.mark("slam_bounce_boost")
		return
	if _super_jump_left > 0.0:
		_jump_buffer_left = 0.0
		_super_jump_left = 0.0
		velocity.y = jump_velocity * sqrt(super_jump_height_mult)
		camera_fx.kick_fov(10.0)
		camera_fx.add_trauma(0.25)
		Audio.play("sounds/sfx/super_jump.wav")
		FX.ring(get_parent(), global_position, 2.0, Color(0.6, 0.85, 1.0, 0.8), 0.3)
		return
	if on_floor or _coyote_left > 0.0:
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		velocity.y = jump_velocity
		Audio.play("sounds/jump_a.ogg, sounds/jump_b.ogg")
	elif _jumps_left > 0:
		_jump_buffer_left = 0.0
		_jumps_left -= 1
		velocity.y = jump_velocity * 0.92
		camera_fx.kick_fov(3.0)
		Audio.play("sounds/jump_b.ogg, sounds/jump_c.ogg")
	elif _wall_jumps_left > 0 and _try_wall_jump():
		# Отскок от стены — когда прыжки в воздухе кончились (иначе у стены платформы съедал бы двойной прыжок)
		_jump_buffer_left = 0.0

func _process_gravity(on_floor: bool, delta: float) -> void:
	if on_floor and velocity.y <= 0.0:
		velocity.y = -0.5
		return
	var g := gravity * (fall_gravity_mult if velocity.y < 0.0 else 1.0)
	velocity.y -= g * delta
	velocity.y = maxf(velocity.y, -45.0)

# --- Рывок ---

func _start_dash(wish: Vector3) -> void:
	dash_charges -= 1
	_dash_recharge_timer = 0.0 if dash_charges == dash_charges_max - 1 else _dash_recharge_timer
	var dir := wish
	if dir == Vector3.ZERO:
		dir = -transform.basis.z
		dir.y = 0
		dir = dir.normalized()
	_dash_dir = dir
	_dash_time_left = dash_duration
	_invuln_left = dash_invuln
	_dash_hit.clear()
	camera_fx.kick_fov(14.0)
	camera_fx.speed_lines_pulse()
	Audio.play("sounds/sfx/dash.wav")
	dash_charges_changed.emit(dash_charges, dash_charges_max, 0.0)

func _process_dash(delta: float) -> void:
	_dash_time_left -= delta
	velocity = _dash_dir * dash_speed
	velocity.y = 0.0
	if Run.rune_count("dash_damage") > 0:
		_dash_damage_tick()
	if _dash_time_left <= 0.0:
		velocity = _dash_dir * dash_speed * dash_exit_keep
		velocity.y = 1.5

func _dash_damage_tick() -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 1.3
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, 0.6, 0))
	q.collision_mask = 1 << 2
	q.exclude = [get_rid()]
	var dmg := dash_damage * Run.rune_count("dash_damage")
	for hit in space.intersect_shape(q, 16):
		var c: Object = hit.collider
		if c and c.has_method("take_hit") and not _dash_hit.has(c.get_instance_id()):
			_dash_hit[c.get_instance_id()] = true
			c.take_hit(dmg, _dash_dir * 9.0 + Vector3.UP * 3.0, "dash")

# --- Удар-приземление ---

func _start_slam() -> void:
	is_slamming = true
	_dash_time_left = 0.0
	camera_fx.kick_fov(-6.0)
	Audio.play("sounds/jump_c.ogg")

func _on_landed() -> void:
	var fall := maxf(0.0, _air_peak_y - global_position.y)
	if is_slamming:
		is_slamming = false
		_do_slam_impact(fall)
		velocity.x = 0
		velocity.z = 0
		if _last_slam_hits > 0:
			_slam_bounce(fall)
		else:
			_super_jump_left = super_jump_window
	else:
		if fall > 1.5:
			camera_fx.land_dip(clampf(fall / 10.0, 0.05, 0.35))
			Audio.play("sounds/land.ogg")

func _do_slam_impact(height: float) -> void:
	var radius := slam_base_radius + height * slam_radius_per_meter
	var damage := slam_base_damage + height * slam_damage_per_meter
	var knock := slam_base_knockback + height * slam_knockback_per_meter
	var center := global_position
	_last_slam_hits = 0
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, center)
	q.collision_mask = (1 << 2) | (1 << 3) | (1 << 6)
	q.exclude = [get_rid()]
	for hit in space.intersect_shape(q, 64):
		var c: Object = hit.collider
		if c == null:
			continue
		var c3 := c as Node3D
		var dir := (c3.global_position - center)
		dir.y = 0
		var dist := dir.length()
		dir = dir.normalized() if dist > 0.01 else Vector3.FORWARD
		var falloff := clampf(1.0 - dist / radius, 0.35, 1.0)
		var push := dir * knock * falloff + Vector3.UP * knock * 0.55 * falloff
		if c.has_method("take_hit"):
			c.take_hit(damage * falloff, push, "slam")
			if c is Enemy:
				_last_slam_hits += 1
		elif c is RigidBody3D:
			(c as RigidBody3D).apply_central_impulse(push * (c as RigidBody3D).mass * 0.6)
	if Run.rune_count("slam_fire") > 0:
		var fire := preload("res://weapons/fire_zone.gd").new()
		get_parent().add_child(fire)
		fire.setup(center, radius * 0.8, 2.0 + 0.5 * (Run.rune_count("slam_fire") - 1), 22.0 * Run.rune_count("slam_fire"))
	var power := clampf(0.25 + height / 14.0, 0.25, 1.0)
	camera_fx.add_trauma(power)
	camera_fx.land_dip(0.25 + power * 0.2)
	FX.ring(get_parent(), center, radius, Color(1.0, 0.85, 0.5, 0.9), 0.4)
	FX.burst(get_parent(), center + Vector3(0, 0.3, 0), radius * 0.35, Color(1, 0.9, 0.6, 0.45), 0.25)
	FX.sparks(get_parent(), center + Vector3(0, 0.2, 0), Color(0.55, 0.47, 0.4), 26 + int(power * 20), 7.0 + power * 6.0, 18.0, 0.14, 0.7)
	FX.hitstop(0.06 + power * 0.04)
	ComicFX.on_slam(center, height)
	Audio.play("sounds/sfx/slam.wav")
	slammed.emit(power)
	if height >= 9.0:
		Odin.say("big_slam")

# --- Прыжки по GDD 7.2: отскок, прыжок по головам, залезание на уступ ---

## Удар-приземление задел врагов — подбрасывает на долю высоты падения, двойной прыжок восстанавливается.
func _slam_bounce(fall: float) -> void:
	var h := maxf(fall * slam_bounce_ratio, slam_bounce_min_height)
	velocity.y = sqrt(2.0 * gravity * h)
	# Прыжок в окне — не ниже супер-прыжка: отскок от врагов не должен отнимать супер-прыжок
	_bounce_boost_velocity = maxf(sqrt(2.0 * gravity * h * slam_bounce_boost), jump_velocity * sqrt(super_jump_height_mult))
	_bounce_window_left = maxf(slam_bounce_window, super_jump_window)
	_jumps_left = extra_jumps
	_air_peak_y = global_position.y
	Perf.mark("slam_bounce")

## Приземлился на врага сверху (без удара-приземления) — отскок, как в Mario.
func _check_stomp(pre_velocity: Vector3) -> void:
	if _stomp_cooldown > 0.0 or is_slamming or pre_velocity.y > -1.0 or not can_stomp():
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var e := col.get_collider() as Enemy
		if e == null or e.is_dead or col.get_normal().y < 0.6:
			continue
		e.take_hit(stomp_damage, Vector3(0, -1, 0), "stomp")
		if e.has_method("stun"):
			e.stun(stomp_stun)
		velocity.y = stomp_bounce_velocity
		_jumps_left = extra_jumps
		_air_peak_y = global_position.y
		_stomp_cooldown = 0.2
		camera_fx.add_trauma(0.12)
		FX.ring(get_parent(), e.global_position + Vector3(0, 1.8 * e.model_scale, 0), 0.8, Color(1, 0.95, 0.7, 0.8), 0.2)
		Audio.play("sounds/jump_b.ogg")
		Perf.mark("stomp")
		return

## Прыжок по головам и залезание зависят от оружия в руке (этап 1): с ренжем по головам не прыгаем.
func can_stomp() -> bool:
	return not (has_method("is_ranged_active") and call("is_ranged_active"))

## Край на уровне груди или чуть выше, игрок жмёт вперёд в стену — залезаем сами за ledge_climb_time.
func _check_ledge(wish: Vector3) -> void:
	if _climb_check_cooldown > 0.0 or is_slamming or _dash_time_left > 0.0 or wish == Vector3.ZERO:
		return
	if velocity.y > 4.0:
		return
	var fwd := -global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	if wish.dot(fwd) < 0.5:
		return
	var space := get_world_3d().direct_space_state
	var base := global_position
	# 1) Стена перед грудью
	var chest := PhysicsRayQueryParameters3D.create(base + Vector3(0, 1.0, 0), base + Vector3(0, 1.0, 0) + fwd * 0.75, 1)
	chest.exclude = [get_rid()]
	var wall := space.intersect_ray(chest)
	if wall.is_empty() or absf((wall.normal as Vector3).y) > 0.3:
		return
	# 2) Верх уступа: луч вниз чуть за стеной
	var probe_xz: Vector3 = (wall.position as Vector3) + fwd * 0.4
	var top_q := PhysicsRayQueryParameters3D.create(Vector3(probe_xz.x, base.y + ledge_max_height + 0.3, probe_xz.z), Vector3(probe_xz.x, base.y + ledge_min_height - 0.05, probe_xz.z), 1)
	top_q.exclude = [get_rid()]
	var top := space.intersect_ray(top_q)
	if top.is_empty() or (top.normal as Vector3).y < 0.7:
		return
	var top_y: float = (top.position as Vector3).y
	var h := top_y - base.y
	if h < ledge_min_height or h > ledge_max_height:
		return
	# 3) Место наверху: капсула игрока помещается
	var dest := Vector3(probe_xz.x, top_y + 0.05, probe_xz.z) + fwd * 0.2
	var col := get_node_or_null("Collider") as CollisionShape3D
	if col and col.shape:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = col.shape
		q.transform = Transform3D(Basis.IDENTITY, dest + col.position + Vector3(0, 0.05, 0))
		q.collision_mask = 1
		q.exclude = [get_rid()]
		if not space.intersect_shape(q, 1).is_empty():
			return
	_start_climb(dest)

## Отскок от стены: стена рядом (лучи по 8 направлениям на уровне груди) — толчок от неё и вверх.
func _try_wall_jump() -> bool:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0, 1.0, 0)
	var best_n := Vector3.ZERO
	var best_d := 0.75
	for i in 8:
		var a := TAU * i / 8.0
		var dir := Vector3(cos(a), 0, sin(a))
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 0.75, 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.3:
			continue
		var d := origin.distance_to(hit.position)
		if d < best_d:
			best_d = d
			best_n = hit.normal
	if best_n == Vector3.ZERO:
		return false
	_wall_jumps_left -= 1
	var n := Vector3(best_n.x, 0, best_n.z).normalized()
	var horiz := Vector3(velocity.x, 0, velocity.z)
	# Гасим скорость в стену, добавляем толчок от неё
	horiz -= n * minf(horiz.dot(n), 0.0)
	horiz += n * wall_jump_push
	velocity = Vector3(horiz.x, wall_jump_up, horiz.z)
	camera_fx.kick_fov(4.0)
	FX.ring(get_parent(), global_position + Vector3(0, 1.0, 0) - n * best_d, 0.6, Color(0.8, 0.9, 1.0, 0.7), 0.2)
	Audio.play("sounds/jump_b.ogg, sounds/jump_c.ogg")
	Perf.mark("wall_jump")
	return true

func _start_climb(dest: Vector3) -> void:
	is_climbing = true
	_climb_t = 0.0
	_climb_time = ledge_climb_time * (ledge_climb_ranged_mult if (has_method("is_ranged_active") and call("is_ranged_active")) else 1.0)
	_climb_from = global_position
	_climb_mid = Vector3(global_position.x, dest.y + 0.1, global_position.z)
	_climb_to = dest
	velocity = Vector3.ZERO
	camera_fx.land_dip(0.12)
	Audio.play("sounds/jump_a.ogg")
	Perf.mark("ledge_climb")

func _process_climb(delta: float) -> void:
	_climb_t += delta
	var k := clampf(_climb_t / maxf(_climb_time, 0.01), 0.0, 1.0)
	# Сначала вверх (60 % времени), потом вперёд на уступ
	if k < 0.6:
		global_position = _climb_from.lerp(_climb_mid, ease(k / 0.6, 0.6))
	else:
		global_position = _climb_mid.lerp(_climb_to, (k - 0.6) / 0.4)
	if k >= 1.0:
		is_climbing = false
		_climb_check_cooldown = 0.3
		var fwd := -global_transform.basis.z
		fwd.y = 0
		velocity = fwd.normalized() * 3.0
		_jumps_left = extra_jumps
		_air_peak_y = global_position.y
		_was_on_floor = true

func _push_rigid_bodies(pre_velocity: Vector3) -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var body := col.get_collider() as RigidBody3D
		if body == null:
			continue
		var speed := pre_velocity.length()
		var dir := -col.get_normal()
		dir.y = maxf(dir.y, 0.15)
		var dashing := _dash_time_left > 0.0
		var force := push_force * (speed * (2.2 if dashing else 0.35))
		body.apply_central_impulse(dir.normalized() * force)

func _update_footsteps(on_floor: bool) -> void:
	var moving := Vector2(velocity.x, velocity.z).length() > 1.5
	footsteps.stream_paused = not (on_floor and moving and _dash_time_left <= 0.0)

# --- Урон ---

func is_invulnerable() -> bool:
	return _invuln_left > 0.0 or is_dead

func take_damage(amount: float, knockback: Vector3 = Vector3.ZERO, ignore_invuln: bool = false) -> void:
	Perf.mark("player_hurt")
	if is_dead:
		return
	if is_invulnerable() and not ignore_invuln:
		return
	health -= amount
	velocity += knockback
	_invuln_left = 0.25
	camera_fx.add_trauma(clampf(amount / 30.0, 0.15, 0.6))
	Run.register_player_hit()
	hurt.emit(amount)
	health_changed.emit(maxf(health, 0.0), max_health)
	Audio.play("sounds/sfx/player_hurt.wav")
	if health <= 0.0:
		_die()

func heal(amount: float) -> void:
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)

func _die() -> void:
	is_dead = true
	input_enabled = false
	footsteps.stream_paused = true
	var tw := create_tween()
	tw.tween_property(head, "position:y", 0.25, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	tw.parallel().tween_property(camera, "rotation:z", deg_to_rad(35), 0.6)
	died.emit()

func get_aim_origin() -> Vector3:
	return camera.global_position

func get_aim_forward() -> Vector3:
	return -camera.global_transform.basis.z

func is_dashing() -> bool:
	return _dash_time_left > 0.0

func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()

# --- Оружие правой руки (этап 1) ---

func _setup_weapons() -> void:
	weapons = get_node_or_null("Weapons") as WeaponHolder
	if weapons == null:
		weapons = WeaponHolder.new()
		weapons.name = "Weapons"
		add_child(weapons)

## Скорость бега с учётом оружия в руке.
func effective_move_speed() -> float:
	return move_speed * weapon_move_mult()

func weapon_move_mult() -> float:
	return weapons.move_speed_mult() if weapons else 1.0

func weapon_dash_recharge_mult() -> float:
	return weapons.dash_recharge_mult() if weapons else 1.0

## Взять оружие (встанет в слот своего класса). drop_old — старое упадёт на пол.
func equip(def: WeaponDef, level: int = 1, drop_old: bool = false) -> WeaponItem:
	return weapons.equip(def, level, drop_old)

## Активное оружие (WeaponDef) и экземпляр (уровень, патроны).
func current_weapon() -> WeaponDef:
	return weapons.current_def() if weapons else null

func current_weapon_item() -> WeaponItem:
	return weapons.current() if weapons else null

## Ренж в руке (для прыжка по головам, залезания, причины смерти).
func is_ranged_active() -> bool:
	return weapons.is_ranged_active() if weapons else false

## Стиль мили в слоте: blade / blunt / pierce (для слов-ударов этапа 4).
func current_melee_style() -> String:
	return weapons.melee_style() if weapons else "blade"

## Лечение за убийство: базовое + бонус за добивание мили.
func kill_heal(source: String) -> float:
	return heal_per_kill + (melee_kill_heal if source.begins_with("melee") else 0.0)
