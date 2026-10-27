extends Node
class_name Axe
## Мили-оружие правой руки (исторически — топор; теперь любое мили из WeaponDef: топор, меч, копьё, дубина…).
## Комбо из combo_count ударов, хитбокс ShapeCast3D в активные кадры, процедурная анимация вьюмодели твинами,
## hit-stop, отбивание снарядов. Зажатая ЛКМ — сильный удар (долгий замах, ×2 урона, сбивает даже особых).
## Тайминги/отдача ниже — базовые (топор); оружие масштабирует их своим attack_speed и т. п.
## Источник урона: "melee", "melee_finisher" (последний удар комбо), "melee_heavy" (сильный удар).

signal swung(stage: int)
signal hit_landed(count: int, stage: int)

@export_group("Урон и отбрасывание")
@export var base_damage: float = 22.0
@export var stage_damage_mult: Array[float] = [1.0, 1.0, 2.2]
@export var stage_knockback: Array[float] = [7.0, 7.0, 16.0]
@export var stage_knock_up: Array[float] = [2.0, 2.0, 5.5]
@export var prop_impulse: float = 6.0

@export_group("Тайминги (сек)")
@export var stage_windup: Array[float] = [0.06, 0.06, 0.12]
@export var stage_active: Array[float] = [0.11, 0.11, 0.13]
@export var stage_recovery: Array[float] = [0.14, 0.14, 0.32]
## Окно после удара, в которое нажатие продолжает комбо
@export var combo_window: float = 0.38

@export_group("Отдача")
@export var stage_hitstop: Array[float] = [0.045, 0.045, 0.085]
@export var stage_shake: Array[float] = [0.18, 0.18, 0.42]
@export var reflect_speed_mult: float = 1.8

@export_group("Сильный удар (зажать ЛКМ)")
## Сколько держать ЛКМ, чтобы после текущего взмаха пошёл сильный удар
@export var heavy_hold_time: float = 0.28
@export var heavy_active: float = 0.14
@export var heavy_recovery: float = 0.36
@export var heavy_knockback: float = 15.0
@export var heavy_knock_up: float = 6.0
@export var heavy_hitstop: float = 0.09
@export var heavy_shake: float = 0.45

var damage_mult: float = 1.0
## Оружие (WeaponDef) и его уровень — задаёт WeaponHolder
var def: WeaponDef
var level: int = 1
## false — оружие убрано (в руке ренж или идёт свитч)
var active: bool = true

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY }
var phase: Phase = Phase.IDLE
var stage: int = 0
## Текущий взмах — сильный удар
var heavy: bool = false
var _phase_time: float = 0.0
var _since_swing_end: float = 99.0
var _queued: bool = false
var _heavy_queued: bool = false
var _hold_time: float = -1.0
var _hit_ids: Dictionary = {}
var _hits_this_swing: int = 0
var _enemies_hit: int = 0
var _tween: Tween
var _base_box_size: Vector3 = Vector3(2.6, 2.0, 1.6)
var _base_target: Vector3 = Vector3(0, 0, -1.0)

@export var player_path: NodePath = ^".."
@export var pivot_path: NodePath
@export var hitbox_path: NodePath
@export var hand_mesh_path: NodePath

@onready var player: Player = get_node(player_path)
@onready var pivot: Node3D = get_node_or_null(pivot_path)
@onready var hitbox: ShapeCast3D = get_node_or_null(hitbox_path)
@onready var hand_mesh: Node = get_node_or_null(hand_mesh_path)

const REST_POS := Vector3(0.46, -0.36, -0.95)
const REST_ROT := Vector3(-8, 12, -14)
var rest_pos: Vector3 = REST_POS
var rest_rot: Vector3 = REST_ROT
# Позы: [замах_поз, замах_рот, конец_поз, конец_рот] для каждой ступени комбо
const POSES := [
	[Vector3(0.8, -0.25, -0.85), Vector3(5, 75, -80), Vector3(-0.5, -0.4, -1.05), Vector3(-5, -75, -80)],
	[Vector3(-0.45, -0.3, -0.9), Vector3(5, -70, 80), Vector3(0.75, -0.45, -1.05), Vector3(-5, 75, 80)],
	[Vector3(0.3, 0.2, -0.75), Vector3(75, 10, -10), Vector3(0.1, -0.75, -1.15), Vector3(-85, 5, -10)],
]
## Тычки (копьё, нож): отвести назад → выбросить вперёд; последний — с доворотом
const THRUST_POSES := [
	[Vector3(0.5, -0.3, -0.45), Vector3(-82, 10, 0), Vector3(0.15, -0.22, -1.55), Vector3(-90, 0, 0)],
	[Vector3(0.35, -0.42, -0.45), Vector3(-80, -6, 25), Vector3(0.05, -0.18, -1.6), Vector3(-92, 0, 15)],
	[Vector3(0.45, -0.1, -0.35), Vector3(-70, 12, -20), Vector3(0.05, -0.25, -1.75), Vector3(-95, 0, 0)],
]
## Сильный удар: высокий замах из-за головы
const HEAVY_POSE := [Vector3(0.35, 0.35, -0.55), Vector3(100, 15, -15), Vector3(0.05, -0.8, -1.2), Vector3(-90, 5, -10)]

func _ready() -> void:
	if hitbox and hitbox.shape is BoxShape3D:
		_base_box_size = (hitbox.shape as BoxShape3D).size
		_base_target = hitbox.target_position
	if pivot:
		pivot.position = rest_pos
		pivot.rotation_degrees = rest_rot

## Цвет кожи и рукава (из тела BodyDef). Рука — ViewmodelArm или (старое) простой меш.
func set_hand_color(c: Color, sleeve: Color = Color(0, 0, 0, 0)) -> void:
	if hand_mesh is ViewmodelArm:
		(hand_mesh as ViewmodelArm).recolor(c, sleeve)
	elif hand_mesh is MeshInstance3D:
		(hand_mesh as MeshInstance3D).material_override = FX.make_material(c, 0.9)

## Взять мили-оружие: урон, скорость, дальность и позы из WeaponDef (null — базовый топор).
func apply_def(d: WeaponDef, lvl: int = 1) -> void:
	def = d
	level = lvl
	cancel()
	rest_pos = d.view_rest_pos if d else REST_POS
	rest_rot = d.view_rest_rot if d else REST_ROT
	if hitbox:
		var reach := d.reach if d else 1.0
		var arc := d.arc if d else 1.0
		if hitbox.shape is BoxShape3D:
			(hitbox.shape as BoxShape3D).size = Vector3(_base_box_size.x * arc, _base_box_size.y, _base_box_size.z)
		hitbox.target_position = _base_target * reach

## Прервать взмах (свитч, смена оружия).
func cancel() -> void:
	phase = Phase.IDLE
	heavy = false
	_queued = false
	_heavy_queued = false
	_hold_time = -1.0
	_since_swing_end = 99.0
	if _tween and _tween.is_valid():
		_tween.kill()

func combo_count() -> int:
	return maxi(1, def.combo_count) if def else 3

func is_finisher() -> bool:
	return not heavy and stage == combo_count() - 1

## Индекс в базовых массивах таймингов (0, 1 — обычные, 2 — добивающий).
func _slot(s: int) -> int:
	if s == combo_count() - 1:
		return 2
	return mini(s, 1)

func _speed() -> float:
	return maxf(0.1, def.attack_speed) if def else 1.0

func _windup_time() -> float:
	if heavy:
		return (def.heavy_windup if def else 0.4)
	return stage_windup[_slot(stage)] / _speed()

func _active_time() -> float:
	return (heavy_active if heavy else stage_active[_slot(stage)]) / _speed()

func _recovery_time() -> float:
	return (heavy_recovery if heavy else stage_recovery[_slot(stage)]) / _speed()

func _stage_damage() -> float:
	var base := (def.damage if def else base_damage) * damage_mult * WeaponDef.level_mult(level)
	if heavy:
		return base * (def.heavy_damage_mult if def else 2.0)
	var mults: Array[float] = def.stage_damage_mult if def and not def.stage_damage_mult.is_empty() else stage_damage_mult
	if stage == combo_count() - 1:
		return base * mults[mults.size() - 1]
	return base * mults[mini(stage, maxi(0, mults.size() - 2))]

func _pose() -> Array:
	if heavy:
		return HEAVY_POSE
	var set_: Array = THRUST_POSES if def and def.swing_set == "thrust" else POSES
	if stage == combo_count() - 1:
		return set_[2]
	return set_[stage % 2]

func _physics_process(delta: float) -> void:
	if player == null or player.is_dead or not player.input_enabled or not active:
		return
	if Input.is_action_just_pressed("attack"):
		request_attack()
		_hold_time = 0.0
	if _hold_time >= 0.0:
		if Input.is_action_pressed("attack"):
			_hold_time += delta
			if _hold_time >= heavy_hold_time:
				request_heavy()
				_hold_time = -1.0
		else:
			_hold_time = -1.0
	_tick(delta)

## Можно вызывать из тестов/ИИ без ввода.
func request_attack() -> void:
	if not active:
		return
	match phase:
		Phase.IDLE:
			if _since_swing_end <= combo_window:
				_begin_stage((stage + 1) % combo_count())
			else:
				_begin_stage(0)
		Phase.ACTIVE, Phase.RECOVERY, Phase.WINDUP:
			_queued = true

## Сильный удар: сразу, если оружие свободно, иначе — сразу после текущего взмаха.
func request_heavy() -> void:
	if not active:
		return
	_queued = false
	if phase == Phase.IDLE:
		_begin_stage(0, true)
	elif not heavy:
		_heavy_queued = true

func _tick(delta: float) -> void:
	if phase == Phase.IDLE:
		_since_swing_end += delta
		return
	_phase_time += delta
	match phase:
		Phase.WINDUP:
			if heavy:
				# Набор силы: рука дрожит
				player.camera_fx.add_trauma(delta * 0.25)
			if _phase_time >= _windup_time():
				_enter_active()
		Phase.ACTIVE:
			_do_hitbox()
			if _phase_time >= _active_time():
				_enter_recovery()
		Phase.RECOVERY:
			if _heavy_queued and _phase_time >= _recovery_time() * 0.4:
				_heavy_queued = false
				_begin_stage(0, true)
			elif _queued and _phase_time >= _recovery_time() * 0.4:
				_queued = false
				_begin_stage((stage + 1) % combo_count())
			elif _phase_time >= _recovery_time():
				phase = Phase.IDLE
				_since_swing_end = 99.0 if heavy else 0.0
				heavy = false
				_animate_to(rest_pos, rest_rot, 0.18, Tween.TRANS_QUAD)

func _begin_stage(s: int, is_heavy: bool = false) -> void:
	Perf.mark("melee_heavy" if is_heavy else "axe_swing")
	stage = s
	heavy = is_heavy
	phase = Phase.WINDUP
	_phase_time = 0.0
	_queued = false
	_hit_ids.clear()
	_hits_this_swing = 0
	_enemies_hit = 0
	var p: Array = _pose()
	_animate_to(p[0], p[1], _windup_time(), Tween.TRANS_SINE)
	swung.emit(stage)

func _enter_active() -> void:
	phase = Phase.ACTIVE
	_phase_time = 0.0
	var p: Array = _pose()
	_animate_to(p[2], p[3], _active_time() * 1.15, Tween.TRANS_EXPO, Tween.EASE_OUT)
	Audio.play("sounds/sfx/axe_swing_%d.wav" % (3 if heavy else _slot(stage) + 1))
	if heavy:
		Audio.thor_grunt()
	player.camera_fx.add_trauma(0.12 if heavy else 0.05)

func _enter_recovery() -> void:
	phase = Phase.RECOVERY
	_phase_time = 0.0

func _animate_to(pos: Vector3, rot: Vector3, time: float, trans: Tween.TransitionType, ease_type: Tween.EaseType = Tween.EASE_IN_OUT) -> void:
	if pivot == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = pivot.create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(pivot, "position", pos, maxf(time, 0.01)).set_trans(trans).set_ease(ease_type)
	_tween.tween_property(pivot, "rotation_degrees", rot, maxf(time, 0.01)).set_trans(trans).set_ease(ease_type)

func _source() -> String:
	if heavy:
		return "melee_heavy"
	return "melee_finisher" if is_finisher() else "melee"

func _do_hitbox() -> void:
	if hitbox == null:
		return
	hitbox.force_shapecast_update()
	var forward := player.get_aim_forward()
	var flat := Vector3(forward.x, 0, forward.z).normalized()
	var right := player.global_transform.basis.x
	var side := 0.0
	if not heavy and not is_finisher() and not (def and def.swing_set == "thrust"):
		side = -0.5 if stage % 2 == 0 else 0.5
	var slot := _slot(stage)
	var kb := (heavy_knockback if heavy else stage_knockback[slot]) * (def.knockback_mult if def else 1.0)
	var ku := (heavy_knock_up if heavy else stage_knock_up[slot]) * (def.knockback_mult if def else 1.0)
	var strong := heavy or is_finisher()
	var max_t := def.max_targets if def else 0
	var new_hits := 0
	for i in hitbox.get_collision_count():
		var c: Object = hitbox.get_collider(i)
		if c == null or c == player:
			continue
		var id := c.get_instance_id()
		if _hit_ids.has(id):
			continue
		var knock := (flat + right * side).normalized() * kb + Vector3.UP * ku
		if c.has_method("reflect") and c.is_in_group("reflectable"):
			_hit_ids[id] = true
			c.reflect(forward * reflect_speed_mult)
			new_hits += 1
		elif c.has_method("take_hit"):
			if max_t > 0 and _enemies_hit >= max_t:
				continue
			_hit_ids[id] = true
			_enemies_hit += 1
			var dmg := _stage_damage() * _situational_mult(c)
			# Через игрока: множители тела (пассивка/изъян) и Ярости, хук on_hit
			player.deal_damage(c, dmg, knock, _source())
			if def and def.stun_on_hit > 0.0 and c.has_method("apply_stun") and is_instance_valid(c):
				c.call("apply_stun", def.stun_on_hit * (1.5 if strong else 1.0), strong)
			new_hits += 1
		elif c is RigidBody3D:
			_hit_ids[id] = true
			var rb := c as RigidBody3D
			rb.apply_central_impulse(knock.normalized() * prop_impulse * rb.mass * (1.6 if strong else 1.0))
			rb.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * rb.mass)
			new_hits += 1
	if new_hits > 0:
		_hits_this_swing += new_hits
		var hs_mult := def.hitstop_mult if def else 1.0
		FX.hitstop((heavy_hitstop if heavy else stage_hitstop[slot]) * hs_mult)
		player.camera_fx.add_trauma(heavy_shake if heavy else stage_shake[slot])
		if strong:
			Audio.play("sounds/sfx/axe_finisher.wav")
		else:
			Audio.play("sounds/sfx/axe_hit_1.wav, sounds/sfx/axe_hit_2.wav, sounds/sfx/axe_hit_3.wav")
		hit_landed.emit(new_hits, stage)

## В спину (×backstab_mult) и по оглушённым (×stunned_mult).
func _situational_mult(c: Object) -> float:
	var m := 1.0
	var e := c as Enemy
	if e == null or def == null:
		return m
	var to_p := player.global_position - e.global_position
	to_p.y = 0
	if to_p.length() > 0.01 and e.global_transform.basis.z.dot(to_p.normalized()) < -0.35:
		m *= def.backstab_mult
	if e.state == Enemy.State.STUNNED:
		m *= def.stunned_mult
	return m

func is_busy() -> bool:
	return phase != Phase.IDLE
