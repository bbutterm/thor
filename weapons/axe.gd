extends Node
class_name Axe
## Топор: комбо из 3 ударов (горизонтальный, обратный, сверху), хитбокс ShapeCast3D в активные кадры,
## процедурная анимация вьюмодели твинами, hit-stop, отбивание снарядов.

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

var damage_mult: float = 1.0

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY }
var phase: Phase = Phase.IDLE
var stage: int = 0
var _phase_time: float = 0.0
var _since_swing_end: float = 99.0
var _queued: bool = false
var _hit_ids: Dictionary = {}
var _hits_this_swing: int = 0
var _tween: Tween

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
# Позы: [замах_поз, замах_рот, конец_поз, конец_рот] для каждой ступени комбо
const POSES := [
	[Vector3(0.8, -0.25, -0.85), Vector3(5, 75, -80), Vector3(-0.5, -0.4, -1.05), Vector3(-5, -75, -80)],
	[Vector3(-0.45, -0.3, -0.9), Vector3(5, -70, 80), Vector3(0.75, -0.45, -1.05), Vector3(-5, 75, 80)],
	[Vector3(0.3, 0.2, -0.75), Vector3(75, 10, -10), Vector3(0.1, -0.75, -1.15), Vector3(-85, 5, -10)],
]

func _ready() -> void:
	if pivot:
		pivot.position = REST_POS
		pivot.rotation_degrees = REST_ROT

## Цвет кожи и рукава (из тела BodyDef). Рука — ViewmodelArm или (старое) простой меш.
func set_hand_color(c: Color, sleeve: Color = Color(0, 0, 0, 0)) -> void:
	if hand_mesh is ViewmodelArm:
		(hand_mesh as ViewmodelArm).recolor(c, sleeve)
	elif hand_mesh is MeshInstance3D:
		(hand_mesh as MeshInstance3D).material_override = FX.make_material(c, 0.9)

func _physics_process(delta: float) -> void:
	if player == null or player.is_dead or not player.input_enabled:
		return
	if Input.is_action_just_pressed("attack"):
		request_attack()
	_tick(delta)

## Можно вызывать из тестов/ИИ без ввода.
func request_attack() -> void:
	match phase:
		Phase.IDLE:
			if _since_swing_end <= combo_window:
				_begin_stage((stage + 1) % 3)
			else:
				_begin_stage(0)
		Phase.ACTIVE, Phase.RECOVERY, Phase.WINDUP:
			_queued = true

func _tick(delta: float) -> void:
	if phase == Phase.IDLE:
		_since_swing_end += delta
		return
	_phase_time += delta
	match phase:
		Phase.WINDUP:
			if _phase_time >= stage_windup[stage]:
				_enter_active()
		Phase.ACTIVE:
			_do_hitbox()
			if _phase_time >= stage_active[stage]:
				_enter_recovery()
		Phase.RECOVERY:
			if _queued and _phase_time >= stage_recovery[stage] * 0.4:
				_queued = false
				_begin_stage((stage + 1) % 3)
			elif _phase_time >= stage_recovery[stage]:
				phase = Phase.IDLE
				_since_swing_end = 0.0
				_animate_to(REST_POS, REST_ROT, 0.18, Tween.TRANS_QUAD)

func _begin_stage(s: int) -> void:
	Perf.mark("axe_swing")
	stage = s
	phase = Phase.WINDUP
	_phase_time = 0.0
	_queued = false
	_hit_ids.clear()
	_hits_this_swing = 0
	var p: Array = POSES[stage]
	_animate_to(p[0], p[1], stage_windup[stage], Tween.TRANS_SINE)
	swung.emit(stage)

func _enter_active() -> void:
	phase = Phase.ACTIVE
	_phase_time = 0.0
	var p: Array = POSES[stage]
	_animate_to(p[2], p[3], stage_active[stage] * 1.15, Tween.TRANS_EXPO, Tween.EASE_OUT)
	Audio.play("sounds/sfx/axe_swing_%d.wav" % (stage + 1))
	player.camera_fx.add_trauma(0.05)

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

func _do_hitbox() -> void:
	if hitbox == null:
		return
	hitbox.force_shapecast_update()
	var forward := player.get_aim_forward()
	var flat := Vector3(forward.x, 0, forward.z).normalized()
	var right := player.global_transform.basis.x
	var side := 0.0
	match stage:
		0: side = -0.5
		1: side = 0.5
	var new_hits := 0
	for i in hitbox.get_collision_count():
		var c: Object = hitbox.get_collider(i)
		if c == null or c == player:
			continue
		var id := c.get_instance_id()
		if _hit_ids.has(id):
			continue
		_hit_ids[id] = true
		var knock := (flat + right * side).normalized() * stage_knockback[stage] + Vector3.UP * stage_knock_up[stage]
		if c.has_method("reflect") and c.is_in_group("reflectable"):
			c.reflect(forward * reflect_speed_mult)
			new_hits += 1
		elif c.has_method("take_hit"):
			var dmg := base_damage * stage_damage_mult[stage] * damage_mult
			c.take_hit(dmg, knock, "axe_finisher" if stage == 2 else "axe")
			new_hits += 1
		elif c is RigidBody3D:
			var rb := c as RigidBody3D
			rb.apply_central_impulse(knock.normalized() * prop_impulse * rb.mass * (1.6 if stage == 2 else 1.0))
			rb.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * rb.mass)
			new_hits += 1
	if new_hits > 0:
		_hits_this_swing += new_hits
		FX.hitstop(stage_hitstop[stage])
		player.camera_fx.add_trauma(stage_shake[stage])
		if stage == 2:
			Audio.play("sounds/sfx/axe_finisher.wav")
		else:
			Audio.play("sounds/sfx/axe_hit_1.wav, sounds/sfx/axe_hit_2.wav, sounds/sfx/axe_hit_3.wav")
		hit_landed.emit(new_hits, stage)

func is_busy() -> bool:
	return phase != Phase.IDLE
