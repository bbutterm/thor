extends CharacterBody3D
class_name Player
## Тор в теле смертного. Движение: бег, двойной прыжок, рывок, удар-приземление, супер-прыжок.
## Все «ощущенческие» числа — в группах @export ниже (см. TUNING.md).

## Слои поверхностей: мир (1) и предметы (4), на которые игрок тоже может приземлиться.
## Врагов намеренно не учитываем: высота удара считается относительно земли/предметов, а не головы.
const SLAM_SURFACE_MASK := 1 | (1 << 3)
const SKILL_FLOOR_ENEMY := 1
const SKILL_FLOOR_OTHER := 2

signal health_changed(current: float, maximum: float)
signal dash_charges_changed(current: int, maximum: int, recharge_progress: float)
signal died
signal hurt(amount: float)
signal slammed(power: float)
signal slam_unavailable
signal weapon_skill_landed(skill_id: String)
signal weapon_skill_lunge_step(from: Vector3, to: Vector3)

@export_group("Бег")
@export var move_speed: float = 8.0
@export var ground_accel: float = 70.0
@export var ground_decel: float = 55.0
## Управление в воздухе — доля от наземного разгона (GDD 7.4: 70 %)
@export var air_control: float = 0.7
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
## Время восстановления одной руны на земле; в воздухе восстановление приостановлено.
@export var dash_recharge: float = 2.5
@export var dash_invuln: float = 0.15
## Скорость, которая остаётся после рывка (доля от dash_speed)
@export var dash_exit_keep: float = 0.55
@export var dash_damage: float = 15.0

@export_group("Удар-приземление и супер-прыжок")
## С какой высоты над поверхностью можно бить без воздушного прыжка (м).
@export var slam_min_height: float = 3.0
## Интервал подсказки о недоступном ударе (с).
@export var slam_hint_cooldown: float = 8.0
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
## С какой высоты (м) удар-приземление — «Вот! ВОТ!» Одина (GDD 17)
@export var big_slam_height: float = 9.0
## С какой высоты падения (м) начинают расти линии скорости и свист (П6: вместо шкалы высоты)
@export var fall_feel_min_height: float = 2.5

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
## Пике: удар-приземление во время рывка в воздухе или сразу после (окно, с) — наклонное падение по взгляду
@export var dive_window: float = 0.35
@export var dive_horizontal_speed: float = 20.0
@export var dive_down_speed: float = 24.0
## Отмена удара-приземления рывком во время падения
@export var slam_cancel_by_dash: bool = true

@export_group("Стиль движения (GDD 7.3, 7.4)")
## Эти поля ставит Player.apply_movement_profile() из run/movement/<стиль>.tres (Базовый — значения ниже).
## Рывок на земле / в воздухе разрешён (Прыгун — только в воздухе, Кузнец — только на земле)
@export var dash_on_ground: bool = true
@export var dash_in_air: bool = true
## Таран: рывок сквозь врагов, урон каждому (0.7 У), отбрасывание, толчок бочек
@export var dash_ram: bool = false
@export var ram_damage: float = 15.4
@export var ram_knockback: float = 13.0
@export var ram_knock_up: float = 4.0
@export var ram_radius: float = 1.4
@export var ram_prop_impulse: float = 9.0
## Скользящий: рывок по земле переходит в подкат
@export var dash_to_slide: bool = false
## Удар-приземление: множители радиуса и урона, стан врагов (с), множитель высоты отскока
@export var slam_radius_mult: float = 1.0
@export var slam_damage_mult: float = 1.0
@export var slam_stun: float = 0.0
@export var slam_bounce_mult: float = 1.0
## Множитель силы отскока от стены
@export var wall_jump_mult: float = 1.0
## Предел скорости от рывка, подката и отскоков — во сколько раз выше бега (GDD 7.4: ×1.8, Скользящий ×2.2)
@export var momentum_cap: float = 1.8
## Скорость выше бега в воздухе не гасится (Скользящий)
@export var keep_air_momentum: bool = false
## Сколько скорости рывок добавляет к текущей (импульс складывается)
@export var dash_momentum_bonus: float = 3.0

@export_group("Подкат (GDD 5, 7.2)")
## Ctrl + Shift на земле. Начальная скорость (не ниже текущей), длительность, трение (м/с²)
@export var slide_speed: float = 13.0
@export var slide_duration: float = 0.55
@export var slide_friction: float = 9.0
## Поворот подката за секунду (рад)
@export var slide_steer: float = 2.5
## Насколько опускается камера в подкате (м)
@export var slide_camera_drop: float = 0.55
## Подкат кончается, когда скорость упала ниже этой доли бега
@export var slide_min_speed_ratio: float = 0.8

@export_group("Криты и руны")
## Базовый шанс крита и урон крита (GDD 8: 5 %, ×2; руна «Глаз ворона» прибавляет шанс)
@export var crit_chance_base: float = 0.05
@export var crit_mult: float = 2.0
## Хит-стоп крита (GDD 19: 90 мс)
@export var crit_hitstop: float = 0.09
## «Зов грома»: урон молнии с неба (1 У)
@export var thunder_call_damage: float = 22.0
## Проклятые руны Локи: период икоты (с) и шанс «вертушки» камеры в секунду
@export var hiccup_period: float = 10.0
@export var spin_chance_per_sec: float = 0.03

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
## Разрешение после воздушного прыжка, супер-прыжка, руны или отскока; сбрасывается при посадке.
var _slam_ready: bool = false
## Меняется при настоящей посадке и завершении залезания. Для пике: разрешение действует только в этом полёте.
var _slam_ground_contacts: int = 0
var _slam_hint_left: float = 0.0
var _coyote_left: float = 0.0
var _jump_buffer_left: float = 0.0
var _was_on_floor: bool = true

var is_slamming: bool = false
## Пике: удар-приземление летит наклонно (скорость падения задаёт _slam_velocity)
var is_diving: bool = false
var _slam_velocity: Vector3 = Vector3.ZERO
var _dash_in_air: bool = false
var _dive_window_left: float = 0.0
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
## Горизонтальная скорость перед рывком (импульс складывается, GDD 7.4)
var _dash_entry_speed: float = 0.0
## Враги, уже задетые текущим рывком-тараном
var _ram_hit: Dictionary = {}
var _ram_saved_mask: int = -1
var is_sliding: bool = false
var _slide_left: float = 0.0
var _slide_dir: Vector3 = Vector3.ZERO
var _slide_speed: float = 0.0

## Временное замедление от приёма оружия (например, во время вертушки).
var weapon_skill_speed_mult: float = 1.0
var _weapon_skill_lunge_left: float = 0.0
var _weapon_skill_lunge_speed: float = 0.0
var _weapon_skill_lunge_dir: Vector3 = Vector3.ZERO
var _weapon_skill_lunge_mask: int = -1
var _weapon_skill_lunge_completed: bool = false
var _weapon_skill_dive_speed: float = 0.0
var _weapon_skill_landing_id: String = ""
## Приём с ударом при посадке можно начать один раз за полёт, даже если его отменили.
var _weapon_skill_landing_used: bool = false

## Стиль движения тела (GDD 7.3) и обработчики пассивки/изъяна (копии на забег)
var movement_profile: MovementProfile
var body_handlers: Array[BodyTraitHandler] = []

var rotation_target: Vector2 = Vector2.ZERO
var mouse_sensitivity: float = 0.0022
var gamepad_sensitivity: float = 3.0
## Инверсия вертикали (настройки, GDD 22; ставит GameSettings.apply_to_player)
var invert_y: bool = false
## Помощь «замедление при ударе-приземлении» (GDD 22): масштаб времени на падение и окно супер-прыжка
@export var slam_assist_time_scale: float = 0.5
var _slam_assist_on: bool = false
## Ощущение высоты падения 0..1 (линии скорости, свист) и «заряд» молота выше big_slam_height (PlayerSlam._height_feel_tick)
var fall_feel: float = 0.0
var fall_charged: bool = false

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
## Руны (GDD 11): щит Сиф, крит, счётчик ударов «Зова грома», второе дыхание, проклятые руны Локи
var shield: float = 0.0
var shield_max: float = 0.0
var _rune_dash_recharge_mult: float = 1.0
var _thunder_hits: int = 0
var _second_wind_used: bool = false
var _hiccup_t: float = 0.0
var _spin_t: float = 0.0
## Шкала стиля «ДОСТОЙНО!» и берсерк на высшем ранге (блок Б3, GDD 8), см. player/style_meter.gd
var style: StyleMeter
## Старое имя (Ярость, блок П) — тот же узел: value/active/berserk_left/start_berserk/reset/is_stun_immune
var rage: StyleMeter:
	get:
		return style
## Анимация рук от первого лица (блок Б2), см. player/viewmodel_motion.gd
var view_motion: ViewmodelMotion

## Компоненты (этап 2 рефакторинга): логика по файлам player/player_*.gd, состояние — поля выше.
var movement: PlayerMovement
var jumps: PlayerJumps
var slam: PlayerSlam
var dash: PlayerDash
var vitals: PlayerHealth
var skills: PlayerWeaponSkills
var runes: PlayerRunes

func _init() -> void:
	movement = PlayerMovement.new(self)
	jumps = PlayerJumps.new(self)
	slam = PlayerSlam.new(self)
	dash = PlayerDash.new(self)
	vitals = PlayerHealth.new(self)
	skills = PlayerWeaponSkills.new(self)
	runes = PlayerRunes.new(self)

func _ready() -> void:
	add_to_group("player")
	_setup_weapons()
	_setup_style()
	_setup_view_motion()
	health = max_health
	dash_charges_max = dash_charges_base
	dash_charges = dash_charges_max
	rotation_target = Vector2(head.rotation.x, rotation.y)
	if Run.has_signal("kill_registered"):
		Run.kill_registered.connect(vitals._on_kill_registered)
	# Настройки игрока: чувствительность, инверсия, FOV, тряска, покачивание (scripts/settings.gd)
	GameSettings.apply_to_player(self)
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
		movement.apply_movement_profile(body.movement_profile())
		setup_body_traits(body)
		weapons.apply_body(body, int(modify_stat(&"start_weapon_level", 1)))
	runes.recalc_from_runes(run, true)

func _emit_all() -> void:
	health_changed.emit(health, max_health)
	dash_charges_changed.emit(dash_charges, dash_charges_max, dash._rune_recharge_progress())

# --- Ввод мышью ---

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or is_dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotation_target.y -= motion.relative.x * mouse_sensitivity
		rotation_target.x -= motion.relative.y * mouse_sensitivity * (-1.0 if invert_y else 1.0)
		rotation_target.x = clampf(rotation_target.x, deg_to_rad(-89), deg_to_rad(89))

func _process(delta: float) -> void:
	if not input_enabled or is_dead:
		return
	var look := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if look != Vector2.ZERO:
		rotation_target.y -= look.x * gamepad_sensitivity * delta
		rotation_target.x -= look.y * gamepad_sensitivity * delta * (-1.0 if invert_y else 1.0)
		rotation_target.x = clampf(rotation_target.x, deg_to_rad(-89), deg_to_rad(89))
	rotation.y = rotation_target.y
	head.rotation.x = rotation_target.x

# --- Физика ---

func _physics_process(delta: float) -> void:
	if is_dead:
		skills.weapon_skill_cancel_motion()
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
	runes._rune_tick(delta)
	slam._slam_assist_tick()
	slam._height_feel_tick(delta)
	if is_climbing:
		jumps._process_climb(delta)
		camera_fx.update_motion(self, input_dir, false, delta)
		return
	var on_floor := is_on_floor() and not skills._weapon_skill_enemy_only_floor()

	if on_floor:
		_coyote_left = coyote_time
		_jumps_left = extra_jumps
		_wall_jumps_left = wall_jumps
	if input_enabled and Input.is_action_just_pressed("jump"):
		if skills.weapon_skill_lunge_active() or _weapon_skill_dive_speed > 0.0:
			skills.weapon_skill_cancel_motion()
		_jump_buffer_left = jump_buffer

	# Рывок (на земле с зажатым Ctrl — подкат)
	if input_enabled and Input.is_action_just_pressed("dash") and dash_charges > 0:
		if (skills.weapon_skill_lunge_active() or not _weapon_skill_landing_id.is_empty()) and dash.can_dash(on_floor):
			skills.weapon_skill_cancel_motion()
		if is_slamming and slam_cancel_by_dash and not on_floor:
			slam._cancel_slam()
		if not is_slamming:
			dash._try_dash(wish, on_floor)
	_dive_window_left = maxf(0.0, _dive_window_left - delta)

	# Удар-приземление
	if input_enabled and Input.is_action_just_pressed("slam") and not on_floor and not is_slamming:
		slam._start_slam()

	var lunge_step := skills.weapon_skill_lunge_active()
	if lunge_step:
		skills._process_weapon_skill_lunge(on_floor, delta)
	elif _weapon_skill_dive_speed > 0.0:
		movement._process_walk(wish, on_floor, delta)
		# После отскока от головы сначала завершаем подъём, потом продолжаем пике.
		if velocity.y > 0.0:
			jumps._process_gravity(false, delta)
		else:
			velocity.y = -_weapon_skill_dive_speed
	elif _dash_time_left > 0.0:
		dash._process_dash(delta)
	elif is_slamming:
		velocity = _slam_velocity
	elif is_sliding:
		movement._process_slide(wish, on_floor, delta)
		jumps._process_jump(on_floor)
		jumps._process_gravity(on_floor, delta)
	else:
		movement._process_walk(wish, on_floor, delta)
		jumps._process_jump(on_floor)
		jumps._process_gravity(on_floor, delta)

	var pre_velocity := velocity
	var lunge_from := global_position
	move_and_slide()
	if lunge_step:
		weapon_skill_lunge_step.emit(lunge_from, global_position)
	movement._push_rigid_bodies(pre_velocity)
	var skill_floor := skills._weapon_skill_floor_contact_flags() if skills._weapon_skill_waiting_for_ground() and is_on_floor() else 0
	var enemy_only_floor := skill_floor == SKILL_FLOOR_ENEMY
	var peak_before_stomp := _air_peak_y
	# Одновременная опора на мир/предмет — посадка, даже если рядом есть голова врага.
	if (skill_floor & SKILL_FLOOR_OTHER) == 0:
		jumps._check_stomp(pre_velocity)
	if enemy_only_floor:
		_air_peak_y = maxf(_air_peak_y, peak_before_stomp)
	if lunge_step:
		skills._finish_weapon_skill_lunge_step(delta)
	elif _weapon_skill_dive_speed <= 0.0:
		jumps._check_ledge(wish)

	var now_on_floor := is_on_floor() and not enemy_only_floor
	if not now_on_floor:
		_air_peak_y = maxf(_air_peak_y, global_position.y)
	if now_on_floor and not _was_on_floor:
		slam._on_landed()
	if now_on_floor:
		_air_peak_y = global_position.y
	_was_on_floor = now_on_floor

	movement._update_footsteps(now_on_floor)
	camera_fx.crouch_target = slide_camera_drop if is_sliding else 0.0
	camera_fx.update_motion(self, input_dir, now_on_floor, delta)

	if global_position.y < -25.0:
		vitals.take_damage(9999.0, Vector3.ZERO, true)

func _update_timers(delta: float) -> void:
	_coyote_left = maxf(0.0, _coyote_left - delta)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	_invuln_left = maxf(0.0, _invuln_left - delta)
	_super_jump_left = maxf(0.0, _super_jump_left - delta)
	_bounce_window_left = maxf(0.0, _bounce_window_left - delta)
	_stomp_cooldown = maxf(0.0, _stomp_cooldown - delta)
	_slam_hint_left = maxf(0.0, _slam_hint_left - delta)
	_climb_check_cooldown = maxf(0.0, _climb_check_cooldown - delta)
	if dash_charges < dash_charges_max and is_on_floor() and not skills._weapon_skill_enemy_only_floor() and not is_climbing and Oaths.ground_recharge():
		_dash_recharge_timer += delta
		if _dash_recharge_timer >= dash_recharge * weapon_dash_recharge_mult() * _rune_dash_recharge_mult:
			_dash_recharge_timer = 0.0
			dash_charges += 1
		dash_charges_changed.emit(dash_charges, dash_charges_max, dash._rune_recharge_progress())
	elif dash_charges >= dash_charges_max:
		_dash_recharge_timer = 0.0

# --- Прицел и скорость ---

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
	if not weapons.active_changed.is_connected(skills._on_weapon_skill_slot_changed):
		weapons.active_changed.connect(skills._on_weapon_skill_slot_changed)

## Скорость бега с учётом оружия в руке.
func effective_move_speed() -> float:
	return move_speed * weapon_move_mult() * (style.current_speed_mult() if style else 1.0) * (1.0 + Run.rune_value("njord_wind")) * Oaths.speed_mult() * maxf(weapon_skill_speed_mult, 0.0)

func weapon_move_mult() -> float:
	var m := weapons.move_speed_mult() if weapons else 1.0
	if is_ranged_active():
		# Охотник: ренж в руке не замедляет
		m = float(modify_stat(&"ranged_move_mult", m))
	return m

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

# --- Пассивки и изъяны тела (GDD 6) ---

## Копии обработчиков пассивки и изъяна тела на забег (в них хранится состояние).
func setup_body_traits(body: BodyDef) -> void:
	body_handlers.clear()
	if body == null:
		return
	for p in [body.passive, body.flaw]:
		var pd := p as PassiveDef
		if pd == null or pd.handler == null:
			continue
		var h := pd.handler.duplicate(true) as BodyTraitHandler
		h.player = self
		h.def = pd
		body_handlers.append(h)
	for h in body_handlers:
		h.on_equip(self)
	camera_fx.aim_wobble_deg = float(modify_stat(&"aim_wobble_deg", 0.0))

## Число, пропущенное через пассивку и изъян (см. BodyTraitHandler.modify).
func modify_stat(stat: StringName, value: Variant) -> Variant:
	for h in body_handlers:
		value = h.modify(stat, value)
	return value

## Обработчик черты по id (для тестов и экранов), или null.
func body_handler(id: String) -> BodyTraitHandler:
	for h in body_handlers:
		if h.def and h.def.id == id:
			return h
	return null

## Множитель исходящего урона: пассивка/изъян тела (по цели и источнику) и берсерк шкалы стиля.
func outgoing_damage_mult(target: Object, source: String) -> float:
	var m := style.current_damage_mult() if style else 1.0
	for h in body_handlers:
		m *= h.damage_mult(target, source)
	return m

## Единая точка урона Тора по врагу/предмету: множители тела, take_hit, хук on_hit. Возвращает урон.
func deal_damage(target: Object, amount: float, knock: Vector3, source: String) -> float:
	if target == null or not is_instance_valid(target) or not target.has_method("take_hit"):
		return 0.0
	# Разрушаемый пропс (бочка, ящик): урон как есть — без множителей тела/берсерка/рун, критов, on_hit,
	# «Зова грома» (удары по бочкам не кормят серии и руны «за удар»)
	if target is Destructible:
		(target as Destructible).take_hit(amount, knock, source)
		return amount
	var dmg := amount * outgoing_damage_mult(target, source) * runes._rune_damage_mult(target, source)
	DebugBalance.note_damage(dmg)
	var crit := runes._roll_crit(source)
	if crit:
		dmg *= crit_mult
		runes._on_crit(target)
	target.call("take_hit", dmg, knock, source)
	runes._rune_on_hit(target, source)
	for h in body_handlers:
		h.on_hit(self, target, dmg, source)
	return dmg

## Начало зала (Game._load_room): скальд снова «не чувствует» первый удар.
func on_room_start() -> void:
	skills.weapon_skill_cancel_motion()
	_weapon_skill_landing_used = false
	for h in body_handlers:
		h.on_room_start(self)

# --- Шкала стиля «ДОСТОЙНО!» (блок Б3, GDD 8) ---

func _setup_style() -> void:
	style = get_node_or_null("StyleMeter") as StyleMeter
	if style == null:
		style = StyleMeter.new()
		style.name = "StyleMeter"
		style.player = self
		add_child(style)

## Руки от первого лица: пружины, покачивание, позы действий (узел создаётся здесь, в player.tscn его нет).
func _setup_view_motion() -> void:
	view_motion = get_node_or_null("ViewmodelMotion") as ViewmodelMotion
	if view_motion == null:
		view_motion = ViewmodelMotion.new()
		view_motion.name = "ViewmodelMotion"
		add_child(view_motion)

func is_berserk() -> bool:
	return style != null and style.active

## Слой музыки по шкале стиля (Music._auto_state): 0 — фон, 1 — бой, 2 — полный трек.
func music_intensity(fighting: bool) -> int:
	return style.music_level(fighting) if style else (1 if fighting else 0)

# --- Функции компонентов, доступные на Player ---
# API игрока (take_damage, heal, can_start_slam…) и приватные функции, которые зовут тесты и трейты
# (## совместимость). Реализация и описание — в компоненте.

# PlayerMovement (player_movement.gd)

## API игрока → movement.momentum_limit (описание там)
func momentum_limit() -> float:
	return movement.momentum_limit()

## API игрока → movement.apply_movement_profile (описание там)
func apply_movement_profile(mp: MovementProfile) -> void:
	movement.apply_movement_profile(mp)

## API игрока → movement.movement_style (описание там)
func movement_style() -> String:
	return movement.movement_style()

# PlayerJumps (player_jumps.gd)

## совместимость → jumps._process_jump
func _process_jump(on_floor: bool) -> void:
	jumps._process_jump(on_floor)

## API игрока → jumps.can_stomp (описание там)
func can_stomp() -> bool:
	return jumps.can_stomp()

## API игрока → jumps.launch_up (описание там)
func launch_up(height: float) -> void:
	jumps.launch_up(height)

# PlayerSlam (player_slam.gd)

## API игрока → slam.can_start_slam (описание там)
func can_start_slam() -> bool:
	return slam.can_start_slam()

## API игрока → slam.slam_surface_hit (описание там)
func slam_surface_hit(distance: float) -> Dictionary:
	return slam.slam_surface_hit(distance)

## совместимость → slam._start_slam
func _start_slam(allow_latched: bool = false) -> bool:
	return slam._start_slam(allow_latched)

## совместимость → slam._cancel_slam
func _cancel_slam() -> void:
	slam._cancel_slam()

## совместимость → slam._do_slam_impact
func _do_slam_impact(height: float) -> void:
	slam._do_slam_impact(height)

## совместимость → slam._slam_bounce
func _slam_bounce(fall: float) -> void:
	slam._slam_bounce(fall)

# PlayerDash (player_dash.gd)

## API игрока → dash.can_dash (описание там)
func can_dash(on_floor: bool) -> bool:
	return dash.can_dash(on_floor)

## API игрока → dash.restore_mjolnir_runes (описание там)
func restore_mjolnir_runes(amount: int) -> void:
	dash.restore_mjolnir_runes(amount)

## совместимость → dash._spend_dash_charge
func _spend_dash_charge() -> void:
	dash._spend_dash_charge()

## совместимость → dash._start_dash
func _start_dash(wish: Vector3) -> void:
	dash._start_dash(wish)

## совместимость → dash._end_ram
func _end_ram() -> void:
	dash._end_ram()

# PlayerHealth (player_health.gd)

## API игрока → vitals.is_invulnerable (описание там)
func is_invulnerable() -> bool:
	return vitals.is_invulnerable()

## API игрока → vitals.take_damage (описание там)
func take_damage(amount: float, knockback: Vector3 = Vector3.ZERO, ignore_invuln: bool = false) -> void:
	vitals.take_damage(amount, knockback, ignore_invuln)

## API игрока → vitals.pay_health (описание там)
func pay_health(amount: float) -> void:
	vitals.pay_health(amount)

## API игрока → vitals.heal (описание там)
func heal(amount: float) -> void:
	vitals.heal(amount)

## совместимость → vitals._die
func _die() -> void:
	vitals._die()

## API игрока → vitals.kill_heal (описание там)
func kill_heal(source: String) -> float:
	return vitals.kill_heal(source)

## API игрока → vitals.refill_shield (описание там)
func refill_shield() -> void:
	vitals.refill_shield()

# PlayerWeaponSkills (player_weapon_skills.gd)

## API игрока → skills.weapon_skill_start_lunge (описание там)
func weapon_skill_start_lunge(direction: Vector3, distance: float, duration: float) -> bool:
	return skills.weapon_skill_start_lunge(direction, distance, duration)

## API игрока → skills.weapon_skill_lunge_active (описание там)
func weapon_skill_lunge_active() -> bool:
	return skills.weapon_skill_lunge_active()

## API игрока → skills.weapon_skill_lunge_completed (описание там)
func weapon_skill_lunge_completed() -> bool:
	return skills.weapon_skill_lunge_completed()

## совместимость → skills._weapon_skill_enemy_only_floor
func _weapon_skill_enemy_only_floor() -> bool:
	return skills._weapon_skill_enemy_only_floor()

## API игрока → skills.weapon_skill_start_dive (описание там)
func weapon_skill_start_dive(speed: float) -> bool:
	return skills.weapon_skill_start_dive(speed)

## API игрока → skills.weapon_skill_arm_landing (описание там)
func weapon_skill_arm_landing(skill_id: String) -> bool:
	return skills.weapon_skill_arm_landing(skill_id)

## API игрока → skills.weapon_skill_landing_pending (описание там)
func weapon_skill_landing_pending(skill_id: String) -> bool:
	return skills.weapon_skill_landing_pending(skill_id)

## API игрока → skills.weapon_skill_start_vault (описание там)
func weapon_skill_start_vault(height_mult: float) -> bool:
	return skills.weapon_skill_start_vault(height_mult)

## API игрока → skills.weapon_skill_cancel_motion (описание там)
func weapon_skill_cancel_motion() -> void:
	skills.weapon_skill_cancel_motion()

# PlayerRunes (player_runes.gd)

## API игрока → runes.recalc_from_runes (описание там)
func recalc_from_runes(run: Node, full_heal: bool = false) -> void:
	runes.recalc_from_runes(run, full_heal)

## совместимость → runes._rune_on_dash
func _rune_on_dash() -> void:
	runes._rune_on_dash()
