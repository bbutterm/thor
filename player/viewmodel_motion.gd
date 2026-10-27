extends Node
class_name ViewmodelMotion
## Анимация рук от первого лица (блок Б2). Узел Player/ViewmodelMotion (создаёт Player._ready).
## Каждая рука — ViewmodelMotion.Hand над пивотом (AxePivot — правая, HammerPivot — левая):
##   поза действия (position / rotation_degrees) — её ведут твины оружия (axe.gd, ranged.gd, weapon_holder.gd,
##   mjolnir_hand.gd) через hand.new_tween(); геймплейные тайминги остаются в оружии, вид их догоняет;
##   + пружина добавок (отдача, ловля, удар) — hand.kick(); + общий слой обеих рук: покачивание при беге,
##   качание за мышью, прыжок/приземление/рывок/подкат, дыхание, дрожь берсерка.
## Итог пишется в пивот, затем ViewmodelArm.update_pose() ставит кости руки (process_priority 100).
## Время — игровое (delta с Engine.time_scale): в hit-stop руки замирают, в замедлении — медленнее.
## Числа — ViewmodelMotionTuning (player/viewmodel_motion.tres), описание — TUNING.md.

const TUNING_PATH := "res://player/viewmodel_motion.tres"

## Одна рука: поза действия + пружина + состояние (для тестов и отладки).
class Hand extends RefCounted:
	var motion: ViewmodelMotion
	var pivot: Node3D
	var arm: ViewmodelArm
	var base_scale: Vector3 = Vector3.ONE
	## Поза действия (пишут твины оружия)
	var position: Vector3 = Vector3.ZERO
	var rotation_degrees: Vector3 = Vector3.ZERO
	## Поза покоя текущего оружия (к ней всё возвращается)
	var rest_pos: Vector3 = Vector3.ZERO
	var rest_rot: Vector3 = Vector3.ZERO
	var visible: bool = true
	## Пружина добавок: смещение/скорость (м) и поворот/скорость (град.)
	var sp_pos: Vector3 = Vector3.ZERO
	var sp_vel: Vector3 = Vector3.ZERO
	var sp_rot: Vector3 = Vector3.ZERO
	var sp_rvel: Vector3 = Vector3.ZERO
	## Жёсткость пружины этой руки ×(тяжёлое оружие возвращается медленнее)
	var stiffness_mult: float = 1.0
	## Дрожь (град.): набор сильного удара и т. п.
	var tremor: float = 0.0
	## Запястье (град.), плавно идёт к wrist_target
	var wrist: Vector3 = Vector3.ZERO
	var wrist_target: Vector3 = Vector3.ZERO
	## Текущее движение («rest», «melee_windup», «throw», …) и сколько оно длится (игровое время)
	var state: StringName = &"rest"
	var state_age: float = 0.0
	## Сколько держать состояние минимум, прежде чем считать руку в покое
	var hold: float = 0.0
	var tween: Tween

	## Новый твин позы (старый — убить). Цели — свойства руки: position, rotation_degrees.
	func new_tween() -> Tween:
		if tween and tween.is_valid():
			tween.kill()
		tween = motion.create_tween()
		return tween

	## Плавно в позу за time.
	func tween_to(pos: Vector3, rot: Vector3, time: float, trans: Tween.TransitionType = Tween.TRANS_SINE,
			ease_type: Tween.EaseType = Tween.EASE_IN_OUT) -> Tween:
		var tw := new_tween().set_parallel(true)
		tw.tween_property(self, "position", pos, maxf(time, 0.01)).set_trans(trans).set_ease(ease_type)
		tw.tween_property(self, "rotation_degrees", rot, maxf(time, 0.01)).set_trans(trans).set_ease(ease_type)
		return tw

	func to_rest(time: float, trans: Tween.TransitionType = Tween.TRANS_QUAD) -> Tween:
		return tween_to(rest_pos, rest_rot, time, trans, Tween.EASE_OUT)

	## Сразу в позу (без твина).
	func snap(pos: Vector3, rot: Vector3) -> void:
		if tween and tween.is_valid():
			tween.kill()
		position = pos
		rotation_degrees = rot

	func kill_tween() -> void:
		if tween and tween.is_valid():
			tween.kill()

	## Импульс пружины: скорость смещения (м/с) и поворота (град./с).
	func kick(vel: Vector3, rot_vel: Vector3 = Vector3.ZERO) -> void:
		sp_vel += vel
		sp_rvel += rot_vel

	func set_state(s: StringName, min_hold: float = 0.0) -> void:
		state = s
		state_age = 0.0
		hold = min_hold

	func is_tweening() -> bool:
		return tween != null and tween.is_valid() and tween.is_running()

	## Поза = покой, пружина успокоилась, твина нет.
	func settled() -> bool:
		var eps := motion.tuning.settle_epsilon
		return not is_tweening() \
			and position.distance_to(rest_pos) < 0.01 and rotation_degrees.distance_to(rest_rot) < 1.0 \
			and sp_pos.length() < eps and sp_vel.length() < eps * 10.0 \
			and sp_rot.length() < eps * 100.0 and sp_rvel.length() < 1.0

var tuning: ViewmodelMotionTuning
var player: Player
static var _tuning_res: ViewmodelMotionTuning

## Числа рук без узла (WeaponHolder до сборки рук).
static func tuning_res() -> ViewmodelMotionTuning:
	if _tuning_res == null:
		_tuning_res = load(TUNING_PATH) as ViewmodelMotionTuning
		if _tuning_res == null:
			_tuning_res = ViewmodelMotionTuning.new()
	return _tuning_res
var right: Hand
var left: Hand
## false — руки стоят в позах действий без добавок (сравнение в тестах)
var enabled: bool = true
## Последнее общее событие («jump», «land», «slam_land», «dash», «air_jump») и его возраст
var last_event: StringName = &""
var event_age: float = 99.0
## Текущее смещение покачивания при беге (для тестов)
var bob_offset: Vector3 = Vector3.ZERO

# Общий слой (обе руки)
var _c_pos: Vector3 = Vector3.ZERO
var _c_vel: Vector3 = Vector3.ZERO
var _c_rot: Vector3 = Vector3.ZERO
var _c_rvel: Vector3 = Vector3.ZERO
var _sway_pos: Vector3 = Vector3.ZERO
var _sway_vel: Vector3 = Vector3.ZERO
var _sway_rot: Vector3 = Vector3.ZERO
var _sway_rvel: Vector3 = Vector3.ZERO
var _hold_pos: Vector3 = Vector3.ZERO
var _hold_rot: Vector3 = Vector3.ZERO
var _bob_phase: float = 0.0
var _bob_amount: float = 0.0
var _breath_t: float = 0.0
var _noise_t: float = 0.0
var _last_look: Vector2 = Vector2.ZERO
var _was_floor: bool = true
var _was_dashing: bool = false
var _prev_vy: float = 0.0
var _air_peak: float = 0.0
var _min_vy: float = 0.0
var _noise := FastNoiseLite.new()
## [right, left] — один массив на всё время (без выделений в кадре)
var _hands: Array[Hand] = []

func _ready() -> void:
	tuning = tuning_res()
	player = get_parent() as Player
	_noise.frequency = 1.0
	_noise.seed = 7
	right = _make_hand(player.axe.pivot if player.axe else null)
	left = _make_hand(player.mjolnir.pivot if player.mjolnir else null)
	_hands = [right, left]
	_last_look = player.rotation_target
	if player.has_signal("slammed"):
		player.slammed.connect(_on_slammed)
	# Раньше рук (ViewmodelArm — 100), позже оружия (0): позы этого кадра уже выставлены
	process_priority = 50

func _make_hand(pivot: Node3D) -> Hand:
	var h := Hand.new()
	h.motion = self
	h.pivot = pivot
	if pivot:
		h.base_scale = pivot.scale
		h.position = pivot.position
		h.rotation_degrees = pivot.rotation_degrees
		h.rest_pos = pivot.position
		h.rest_rot = pivot.rotation_degrees
		h.visible = pivot.visible
		for c in pivot.get_children():
			if c is ViewmodelArm:
				h.arm = c
				h.arm.driven = true
	return h

## Рука по пивоту (оружие ищет свою руку так, без жёстких ссылок).
func hand_for(pivot: Node3D) -> Hand:
	if right and right.pivot == pivot:
		return right
	if left and left.pivot == pivot:
		return left
	return null

func _process(delta: float) -> void:
	if player == null:
		return
	var t := tuning
	var dt := minf(delta, 0.05)
	event_age += dt
	_watch_player(dt)
	# Пружины — шагами не длиннее 1/120 с (устойчивость при просадке кадра)
	var steps := maxi(1, int(ceil(dt / (1.0 / 120.0))))
	var h_dt := dt / steps
	for i in steps:
		for h in _hands:
			var hh := h
			var k := t.spring_stiffness * hh.stiffness_mult
			hh.sp_vel += (-k * hh.sp_pos - t.spring_damping * hh.sp_vel) * h_dt
			hh.sp_pos += hh.sp_vel * h_dt
			hh.sp_rvel += (-k * hh.sp_rot - t.spring_damping * hh.sp_rvel) * h_dt
			hh.sp_rot += hh.sp_rvel * h_dt
		_c_vel += (-t.spring_stiffness * _c_pos - t.spring_damping * _c_vel) * h_dt
		_c_pos += _c_vel * h_dt
		_c_rvel += (-t.spring_stiffness * _c_rot - t.spring_damping * _c_rvel) * h_dt
		_c_rot += _c_rvel * h_dt
		_sway_vel += (-t.sway_stiffness * _sway_pos - t.sway_damping * _sway_vel) * h_dt
		_sway_pos += _sway_vel * h_dt
		_sway_rvel += (-t.sway_stiffness * _sway_rot - t.sway_damping * _sway_rvel) * h_dt
		_sway_rot += _sway_rvel * h_dt
	_noise_t += dt * t.tremor_freq
	_breath_t += dt
	# Покачивание при беге (фаза — от скорости; в воздухе гаснет)
	var on_floor := player.is_on_floor()
	var hs := player.horizontal_speed()
	var norm := maxf(player.effective_move_speed(), 0.1)
	var bob_target := clampf(hs / norm, 0.0, t.bob_max_speed_ratio) if on_floor and hs > 0.5 and not player.is_sliding else 0.0
	_bob_amount = lerpf(_bob_amount, bob_target, clampf(dt * 8.0, 0.0, 1.0))
	_bob_phase += dt * hs * t.bob_freq_per_speed * TAU
	var bob_scale := 1.0 if _bob_enabled() else t.bob_when_disabled
	var bob := Vector3(sin(_bob_phase * 0.5) * t.bob_side, -absf(cos(_bob_phase * 0.5)) * t.bob_up, 0.0) * _bob_amount * bob_scale
	var bob_rot := Vector3(0, 0, sin(_bob_phase * 0.5) * t.bob_roll) * _bob_amount * bob_scale
	bob_offset = bob
	var breath := Vector3(0, sin(_breath_t * TAU * t.idle_breath_freq) * t.idle_breath, 0)
	# Постоянные добавки: рывок, подкат, воздух
	var hold_pos := Vector3.ZERO
	var hold_rot := Vector3.ZERO
	if player.is_dashing():
		hold_pos += t.dash_pull
		hold_rot += t.dash_tilt
	if player.is_sliding:
		hold_pos += t.slide_offset
		hold_rot.z += t.slide_roll
	if not on_floor and not player.is_dashing():
		hold_pos.y += clampf(player.velocity.y / 10.0, -1.0, 1.0) * t.air_lift_per_speed
	var a := clampf(dt * t.offset_smooth, 0.0, 1.0)
	_hold_pos = _hold_pos.lerp(hold_pos, a)
	_hold_rot = _hold_rot.lerp(hold_rot, a)
	# Дрожь берсерка
	var tremor_all := t.berserk_tremor if player.is_berserk() else 0.0
	var common_pos := _c_pos + _sway_pos + _hold_pos + breath
	var common_rot := _c_rot + _sway_rot + _hold_rot
	var mirror := 1.0
	for h in _hands:
		var hh := h as Hand
		hh.state_age += dt
		if hh.state != &"rest" and hh.state_age >= hh.hold and hh.settled():
			hh.state = &"rest"
		hh.wrist = hh.wrist.lerp(hh.wrist_target, clampf(dt * 18.0, 0.0, 1.0))
		if hh.arm:
			hh.arm.extra_wrist = hh.wrist if enabled else Vector3.ZERO
		if hh.pivot == null:
			continue
		hh.pivot.visible = hh.visible
		var pos := hh.position
		var rot := hh.rotation_degrees
		if enabled:
			var tr := hh.tremor + tremor_all
			var jitter := Vector3.ZERO
			if tr > 0.0:
				jitter = Vector3(_noise.get_noise_2d(_noise_t, mirror * 10.0), _noise.get_noise_2d(mirror * 20.0, _noise_t),
					_noise.get_noise_2d(_noise_t, _noise_t + mirror * 5.0)) * tr
			# Левая рука качается в противофазе по крену и вбок
			pos += hh.sp_pos + common_pos + Vector3(bob.x * mirror, bob.y, bob.z)
			rot += hh.sp_rot + common_rot + bob_rot * mirror + jitter
		hh.pivot.transform = Transform3D(Basis.from_euler(rot * (PI / 180.0)).scaled_local(hh.base_scale), pos)
		mirror = -1.0
		if hh.arm:
			hh.arm.update_pose(dt)

func _bob_enabled() -> bool:
	var cam := player.camera_fx
	return cam == null or cam.head_bob_enabled

## События движения игрока (без правок player.gd): прыжок, приземление, рывок; качание за мышью.
func _watch_player(dt: float) -> void:
	var t := tuning
	var look := player.rotation_target
	var d := look - _last_look
	_last_look = look
	d.y = wrapf(d.y, -PI, PI)
	if d.length() > 0.5:
		d = Vector2.ZERO  # разворот кодом (руна, смена зала) — без рывка рук
	# Поворот влево (+yaw) — руки отстают вправо; взгляд вверх (+pitch) — руки отстают вниз
	_sway_pos += Vector3(d.y * t.sway_pos_per_rad, -d.x * t.sway_pos_per_rad, 0.0)
	_sway_rot += Vector3(-d.x * t.sway_rot_per_rad, d.y * t.sway_rot_per_rad, d.y * t.sway_rot_per_rad * 0.5)
	_sway_pos = _sway_pos.limit_length(t.sway_max_pos)
	_sway_rot = _sway_rot.clamp(Vector3.ONE * -t.sway_max_rot, Vector3.ONE * t.sway_max_rot)
	var on_floor := player.is_on_floor()
	var vy := player.velocity.y
	if not on_floor:
		_air_peak = maxf(_air_peak, player.global_position.y)
		_min_vy = minf(_min_vy, vy)
	if on_floor and not _was_floor:
		var fall := maxf(0.0, _air_peak - player.global_position.y)
		if fall >= t.land_min_fall and last_event != &"slam_land":
			var k := minf(fall * t.land_kick_per_meter, t.land_kick_max)
			_c_vel += Vector3(0, -k, 0)
			_c_rvel += Vector3(-k * t.land_tilt, 0, 0)
			_event(&"land")
	if on_floor:
		_air_peak = player.global_position.y
		_min_vy = 0.0
	if _was_floor and not on_floor and vy > 2.0:
		_c_vel += Vector3(0, t.jump_kick, 0)
		_c_rvel += Vector3(t.jump_kick * 20.0, 0, 0)
		_event(&"jump")
	elif not on_floor and vy - _prev_vy > 4.0:
		_c_vel += Vector3(0, t.air_jump_kick, 0)
		_event(&"air_jump")
	var dashing := player.is_dashing()
	if dashing and not _was_dashing:
		_c_vel += Vector3(0, 0, t.dash_kick)
		_event(&"dash")
	_was_dashing = dashing
	_was_floor = on_floor
	_prev_vy = vy
	if dt <= 0.0:
		return

func _on_slammed(power: float) -> void:
	var k := tuning.slam_land_kick * clampf(power, 0.25, 1.0) * 1.3
	_c_vel += Vector3(0, -k, 0.2 * k)
	_c_rvel += Vector3(-k * tuning.land_tilt, 0, 0)
	_event(&"slam_land")

func _event(e: StringName) -> void:
	last_event = e
	event_age = 0.0

## Нет NaN/бесконечностей в итоговых трансформах рук (для тестов).
func transforms_finite() -> bool:
	for h in _hands:
		var hh := h as Hand
		if hh.pivot and not _finite(hh.pivot.transform):
			return false
		if hh.arm and hh.arm.skeleton:
			var sk := hh.arm.skeleton
			for b in sk.get_bone_count():
				if not _finite(sk.get_bone_global_pose(b)):
					return false
	return true

static func _finite(t: Transform3D) -> bool:
	for v in [t.basis.x, t.basis.y, t.basis.z, t.origin]:
		var vv := v as Vector3
		if not (is_finite(vv.x) and is_finite(vv.y) and is_finite(vv.z)):
			return false
	return true
