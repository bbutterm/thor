extends Camera3D
class_name CameraFX
## Эффекты камеры: тряска (trauma), покачивание при ходьбе, наклон при стрейфе, FOV-кик, «присед» при приземлении.

@export_group("FOV")
@export var base_fov: float = 85.0
## Сколько градусов FOV добавляется за 1 м/с сверх обычной скорости
@export var fov_per_overspeed: float = 0.9
@export var fov_return_speed: float = 6.0

@export_group("Тряска")
@export var shake_max_offset: float = 0.22
@export var shake_max_roll_deg: float = 4.0
@export var shake_decay: float = 1.8

@export_group("Отдача ренжа")
## Как быстро камера возвращается после отдачи выстрела
@export var recoil_return_speed: float = 14.0

@export_group("Покачивание и наклон")
@export var head_bob_enabled: bool = true
@export var head_bob_amount: float = 0.05
@export var head_bob_freq: float = 2.2
@export var strafe_tilt_enabled: bool = true
@export var strafe_tilt_deg: float = 2.5

@export_group("Тело")
## Покачивание прицела, градусы (Пьяный скальд — ставит игрок из изъяна тела)
@export var aim_wobble_deg: float = 0.0
@export var aim_wobble_freq: float = 0.45
## Как быстро камера опускается в подкат и поднимается обратно
@export var crouch_speed: float = 12.0

var trauma: float = 0.0
## Сила тряски из настроек игрока 0..1 (GDD 22: «тряска камеры 0–100 %»)
var shake_scale: float = 1.0
## 0..1 — насколько видны линии скорости (читает HUD)
var speed_lines: float = 0.0

var _fov_kick: float = 0.0
var _bob_time: float = 0.0
var _dip: float = 0.0
var _tilt: float = 0.0
var _noise := FastNoiseLite.new()
var _noise_t: float = 0.0
var _speed_pulse: float = 0.0
## Отдача выстрела: x — вверх (рад), y — вбок (рад); гаснет сама
var _recoil: Vector2 = Vector2.ZERO
## Насколько опустить камеру (подкат) — ставит игрок
var crouch_target: float = 0.0
var _crouch: float = 0.0
var _wobble_t: float = 0.0

func _ready() -> void:
	fov = base_fov
	_noise.frequency = 2.0
	_noise.seed = randi()

func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount * shake_scale, 0.0, 1.0)

func kick_fov(deg: float) -> void:
	_fov_kick += deg

func land_dip(amount: float) -> void:
	_dip = maxf(_dip, amount)

func speed_lines_pulse() -> void:
	_speed_pulse = 1.0

func update_motion(player: Player, input_dir: Vector2, on_floor: bool, delta: float) -> void:
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	real_delta = minf(real_delta, 0.05)
	var hspeed := player.horizontal_speed()
	var overspeed := maxf(0.0, hspeed - player.effective_move_speed())

	# FOV
	_fov_kick = lerpf(_fov_kick, 0.0, real_delta * fov_return_speed)
	var target_fov := base_fov + minf(overspeed * fov_per_overspeed, 18.0) + _fov_kick
	fov = lerpf(fov, target_fov, real_delta * 12.0)

	# Линии скорости
	_speed_pulse = maxf(0.0, _speed_pulse - real_delta * 3.0)
	speed_lines = clampf(maxf(overspeed / 12.0, _speed_pulse), 0.0, 1.0)
	if player.is_slamming:
		speed_lines = 1.0

	# Покачивание
	var bob := Vector2.ZERO
	if head_bob_enabled and on_floor and hspeed > 1.0:
		_bob_time += real_delta * hspeed * head_bob_freq
		bob = Vector2(cos(_bob_time * 0.5) * head_bob_amount, abs(sin(_bob_time * 0.5)) * head_bob_amount)
	# Присед после приземления
	_dip = lerpf(_dip, 0.0, real_delta * 7.0)

	# Наклон при стрейфе
	var tilt_target := -input_dir.x * deg_to_rad(strafe_tilt_deg) if strafe_tilt_enabled else 0.0
	_tilt = lerpf(_tilt, tilt_target, real_delta * 8.0)

	# Тряска
	trauma = maxf(0.0, trauma - shake_decay * real_delta)
	_noise_t += real_delta * 60.0
	var shake := trauma * trauma
	var off_x := _noise.get_noise_2d(_noise_t, 0.0) * shake_max_offset * shake
	var off_y := _noise.get_noise_2d(0.0, _noise_t) * shake_max_offset * shake
	var roll := _noise.get_noise_2d(_noise_t, _noise_t) * deg_to_rad(shake_max_roll_deg) * shake

	# Подкат — камера ниже
	_crouch = lerpf(_crouch, crouch_target, clampf(real_delta * crouch_speed, 0.0, 1.0))
	h_offset = bob.x + off_x
	v_offset = bob.y - _dip + off_y - _crouch
	rotation.z = _tilt + roll
	# Отдача ренжа
	_recoil = _recoil.lerp(Vector2.ZERO, clampf(real_delta * recoil_return_speed, 0.0, 1.0))
	# Пьяный прицел: две несоизмеримые синусоиды
	var wob := Vector2.ZERO
	if aim_wobble_deg > 0.0:
		_wobble_t += real_delta * TAU * aim_wobble_freq
		wob = Vector2(sin(_wobble_t * 1.3) * 0.6, sin(_wobble_t)) * deg_to_rad(aim_wobble_deg)
	rotation.x = _recoil.x + wob.x
	rotation.y = _recoil.y + wob.y

## Отдача выстрела: камера подпрыгивает вверх (и чуть вбок) и сама возвращается.
func kick_recoil(up_deg: float, side_deg: float = 0.0) -> void:
	_recoil.x = minf(_recoil.x + deg_to_rad(up_deg), deg_to_rad(12.0))
	_recoil.y += deg_to_rad(side_deg)
