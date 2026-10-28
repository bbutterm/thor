extends Node
class_name Axe
## Мили-оружие правой руки (исторически — топор; теперь любое мили из WeaponDef: топор, меч, копьё, дубина…).
## Комбо из combo_count ударов, хитбокс ShapeCast3D в активные кадры, процедурная анимация вьюмодели твинами,
## hit-stop, отбивание снарядов. Зажатая ЛКМ — приём текущего оружия из WeaponDef.
## Тайминги/отдача ниже — базовые (топор); оружие масштабирует их своим attack_speed и т. п.
## Источник урона: "melee", "melee_finisher" (последний удар комбо), "melee_heavy" (сильный удар).

signal swung(stage: int)
signal hit_landed(count: int, stage: int)
signal weapon_skill_started(kind: String)

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
var _skill_mode: String = ""
var _skill_elapsed: float = 0.0
var _skill_pulses: int = 0
var _skill_lunges_left: int = 0
var _skill_direction: Vector3 = Vector3.ZERO
var _skill_hit_ids: Dictionary = {}
var _skill_shape := SphereShape3D.new()
var _skill_query := PhysicsShapeQueryParameters3D.new()
var _parry_left: float = 0.0

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
## (замах — оружие взведено над правым плечом и видно в кадре, рука с наручем — справа)
const HEAVY_POSE := [Vector3(0.45, -0.04, -0.72), Vector3(50, 22, -30), Vector3(0.05, -0.8, -1.2), Vector3(-90, 5, -10)]

func _ready() -> void:
	_skill_query.shape = _skill_shape
	# Враги (слой 3) и разрушаемые предметы (слой 4), как у обычного взмаха.
	_skill_query.collision_mask = (1 << 2) | (1 << 3)
	_skill_query.collide_with_areas = false
	if player and not player.weapon_skill_landed.is_connected(_on_weapon_skill_landed):
		player.weapon_skill_landed.connect(_on_weapon_skill_landed)
	if player and not player.weapon_skill_lunge_step.is_connected(_on_weapon_skill_lunge_step):
		player.weapon_skill_lunge_step.connect(_on_weapon_skill_lunge_step)
	if hitbox and hitbox.shape is BoxShape3D:
		_base_box_size = (hitbox.shape as BoxShape3D).size
		_base_target = hitbox.target_position
	if pivot:
		pivot.position = rest_pos
		pivot.rotation_degrees = rest_rot

## Рука вьюмодели (ViewmodelMotion.Hand над пивотом; null — пока Player не собрал руки)
var _vm_hand: ViewmodelMotion.Hand

func view_hand() -> ViewmodelMotion.Hand:
	if _vm_hand == null and player and player.view_motion:
		_vm_hand = player.view_motion.hand_for(pivot)
	return _vm_hand

func _tuning() -> ViewmodelMotionTuning:
	return player.view_motion.tuning

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
	var h := view_hand()
	if h:
		h.rest_pos = rest_pos
		h.rest_rot = rest_rot
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
	_skill_mode = ""
	_skill_elapsed = 0.0
	_skill_pulses = 0
	_skill_lunges_left = 0
	_skill_hit_ids.clear()
	_parry_left = 0.0
	if player:
		player.weapon_skill_speed_mult = 1.0
		player.weapon_skill_cancel_motion()
	if _tween and _tween.is_valid():
		_tween.kill()
	var h := view_hand()
	if h:
		h.kill_tween()
		h.tremor = 0.0
		h.wrist_target = Vector3.ZERO

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
	if player == null:
		return
	if player.is_dead or not active:
		if not _skill_mode.is_empty():
			cancel()
		return
	if not player.input_enabled:
		return
	_parry_left = maxf(0.0, _parry_left - delta)
	if not _skill_mode.is_empty():
		_tick_weapon_skill(delta)
		return
	if Input.is_action_just_pressed("attack"):
		request_attack()
		_hold_time = 0.0
	if _hold_time >= 0.0:
		if Input.is_action_pressed("attack"):
			_hold_time += delta
			if _hold_time >= (def.skill_hold_time if def and def.skill_kind != "none" else heavy_hold_time):
				request_heavy()
				_hold_time = -1.0
		else:
			_hold_time = -1.0
	_tick(delta)

## Можно вызывать из тестов/ИИ без ввода.
func request_attack() -> void:
	if not active or player == null or player.is_dead or not _skill_mode.is_empty():
		return
	if def and def.skill_kind == "lunge":
		_parry_left = def.skill_parry_window * (def.skill_parry_lvl3_window_mult if level >= 3 else 1.0)
	if def and not player.is_on_floor():
		if def.skill_kind == "whirl" and player.weapon_skill_start_dive(def.skill_dive_speed):
			_start_air_weapon_skill("axe_dive")
			return
		if def.skill_kind == "vault" and player.weapon_skill_arm_landing("staff_wave"):
			_start_air_weapon_skill("staff_wave")
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
	if not active or player == null or player.is_dead or not _skill_mode.is_empty():
		return
	_queued = false
	if phase == Phase.IDLE:
		_start_heavy_or_weapon_skill()
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
				# Набор силы: рука дрожит (всё сильнее к выпуску)
				player.camera_fx.add_trauma(delta * 0.25)
				var h := view_hand()
				if h:
					h.tremor = _tuning().heavy_tremor * clampf(_phase_time / maxf(_windup_time(), 0.01), 0.2, 1.0)
			if _phase_time >= _windup_time():
				_enter_active()
		Phase.ACTIVE:
			_do_hitbox()
			if _phase_time >= _active_time():
				_enter_recovery()
		Phase.RECOVERY:
			if _heavy_queued and _phase_time >= _recovery_time() * 0.4:
				_heavy_queued = false
				_start_heavy_or_weapon_skill()
			elif _queued and _phase_time >= _recovery_time() * 0.4:
				_queued = false
				_begin_stage((stage + 1) % combo_count())
			elif _phase_time >= _recovery_time():
				phase = Phase.IDLE
				_since_swing_end = 99.0 if heavy else 0.0
				heavy = false
				_animate_to(rest_pos, rest_rot, 0.18, Tween.TRANS_QUAD, Tween.EASE_OUT)

## Обычный сильный удар остаётся только у оружия без заданного приёма.
func _start_heavy_or_weapon_skill() -> void:
	if def == null or def.skill_kind == "none":
		_begin_stage(0, true)
		return
	phase = Phase.IDLE
	heavy = false
	_queued = false
	_since_swing_end = 99.0
	if not _start_weapon_skill():
		_animate_to(rest_pos, rest_rot, 0.18, Tween.TRANS_QUAD, Tween.EASE_OUT)

func _start_weapon_skill() -> bool:
	if def == null or player == null or player.is_dead:
		return false
	match def.skill_kind:
		"whirl":
			if not player.is_on_floor() or player.is_slamming or player.is_climbing or player.is_dashing() or player.is_sliding:
				return false
			_skill_mode = "whirl"
			_skill_elapsed = 0.0
			_skill_pulses = 0
			_skill_hit_ids.clear()
			heavy = true
			player.weapon_skill_speed_mult = clampf(def.skill_move_mult, 0.0, 1.0)
			var turns := maxi(1, def.skill_lvl3_turns) if level >= 3 else 1
			var h := view_hand()
			if h:
				h.set_state(&"melee_strike")
				h.kick(Vector3(0.0, 0.0, -0.35))
				h.tween_to(rest_pos + Vector3(0.0, 0.05, -0.1), rest_rot + Vector3(0.0, 0.0, 360.0 * turns), maxf(0.05, def.skill_duration), Tween.TRANS_LINEAR)
			Audio.sfx("skill_whirl", "sounds/sfx/skill_whirl.wav")
			ComicFX.pop("weapon_whirl", player.global_position + Vector3.UP * 1.8)
			StyleMeter.event(&"melee_whirl")
			player.camera_fx.add_trauma(0.12)
			Perf.mark("weapon_whirl")
			weapon_skill_started.emit("whirl")
			return true
		"lunge":
			var aim := player.get_aim_forward()
			aim.y = 0.0
			_skill_direction = aim.normalized() if aim.length_squared() > 0.001 else -player.global_transform.basis.z
			var distance := def.skill_lunge_distance * (def.skill_lunge_lvl3_distance_mult if level >= 3 else 1.0)
			if not player.weapon_skill_start_lunge(_skill_direction, distance, def.skill_lunge_duration):
				return false
			_skill_mode = "lunge"
			_skill_lunges_left = maxi(1, def.skill_lunge_lvl3_count) if level >= 3 else 1
			_skill_hit_ids.clear()
			heavy = true
			_skill_lunge_feedback()
			StyleMeter.event(&"melee_lunge")
			Perf.mark("weapon_lunge")
			weapon_skill_started.emit("lunge")
			return true
		"vault":
			if not player.weapon_skill_start_vault(def.skill_vault_height_mult):
				return false
			var h := view_hand()
			if h:
				h.set_state(&"melee_strike")
				h.kick(Vector3(0.0, 0.45, -0.3), Vector3(-35.0, 0.0, 0.0))
				var vault_tween := h.tween_to(rest_pos + Vector3(0.0, 0.2, -0.1), rest_rot + Vector3(-55.0, 0.0, 0.0), 0.2)
				vault_tween.chain().tween_property(h, "position", rest_pos, 0.3)
				vault_tween.parallel().tween_property(h, "rotation_degrees", rest_rot, 0.3)
			Audio.sfx("skill_vault", "sounds/sfx/skill_vault.wav")
			ComicFX.pop("weapon_vault", player.global_position + Vector3.UP * 1.8)
			StyleMeter.event(&"melee_vault")
			player.camera_fx.add_trauma(0.12)
			Perf.mark("weapon_vault")
			weapon_skill_started.emit("vault")
			return true
	return false

func _skill_lunge_feedback() -> void:
	var h := view_hand()
	if h:
		h.set_state(&"melee_strike")
		h.kick(Vector3(0.0, 0.0, -0.55))
		h.tween_to(rest_pos + Vector3(0.0, 0.0, -0.48), rest_rot + Vector3(-20.0, 0.0, 0.0), maxf(0.05, def.skill_lunge_duration), Tween.TRANS_EXPO, Tween.EASE_OUT)
	Audio.sfx("skill_lunge", "sounds/sfx/skill_lunge.wav")
	ComicFX.pop("weapon_lunge", player.global_position + Vector3.UP * 1.8)
	player.camera_fx.add_trauma(0.16)

func _start_air_weapon_skill(kind: String) -> void:
	phase = Phase.IDLE
	_queued = false
	_heavy_queued = false
	_since_swing_end = 99.0
	_skill_mode = kind
	heavy = true
	var h := view_hand()
	if h:
		h.set_state(&"melee_windup")
		h.tween_to(HEAVY_POSE[0], HEAVY_POSE[1], 0.15)
	Perf.mark("weapon_" + kind)
	weapon_skill_started.emit(kind)

func _tick_weapon_skill(delta: float) -> void:
	if def == null:
		_finish_weapon_skill()
		return
	match _skill_mode:
		"whirl":
			# Уклонение, прыжок и подкат прерывают вертушку, а не сохраняют её урон на скорости рывка.
			if player.is_dashing() or player.is_sliding or player.is_climbing or not player.is_on_floor():
				_finish_weapon_skill()
				return
			var duration := maxf(0.05, def.skill_duration)
			var turns := maxi(1, def.skill_lvl3_turns) if level >= 3 else 1
			var old_time := _skill_elapsed
			_skill_elapsed = minf(duration, _skill_elapsed + delta)
			player.rotation_target.y += TAU * float(turns) * (_skill_elapsed - old_time) / duration
			while _skill_pulses < turns and _skill_elapsed >= duration * float(_skill_pulses) / float(turns):
				_skill_hit_ids.clear()
				_skill_pulses += 1
			var radius := def.skill_radius * (def.skill_lvl3_radius_mult if level >= 3 else 1.0)
			_skill_hits_at(player.global_position, radius, _skill_damage(def.skill_damage_mult), def.skill_knockback)
			if _skill_elapsed >= duration:
				_finish_weapon_skill()
		"lunge":
			if not player.weapon_skill_lunge_active():
				if player.weapon_skill_lunge_completed() and _skill_lunges_left > 1:
					_skill_lunges_left -= 1
					_skill_hit_ids.clear()
					var distance := def.skill_lunge_distance * (def.skill_lunge_lvl3_distance_mult if level >= 3 else 1.0)
					if player.weapon_skill_start_lunge(_skill_direction, distance, def.skill_lunge_duration):
						_skill_lunge_feedback()
						return
				_finish_weapon_skill()
		"axe_dive", "staff_wave":
			if not player.weapon_skill_landing_pending(_skill_mode):
				_finish_weapon_skill()

func _on_weapon_skill_lunge_step(from: Vector3, to: Vector3) -> void:
	if _skill_mode == "lunge" and active and def != null and player != null and not player.is_dead:
		_skill_hits_along(from, to, def.skill_lunge_hit_radius)

func _on_weapon_skill_landed(kind: String) -> void:
	if not active or def == null or kind != _skill_mode:
		return
	_skill_hit_ids.clear()
	if kind == "axe_dive":
		_skill_hits_at(player.global_position, def.skill_dive_radius, _skill_damage(def.skill_dive_damage_mult), def.skill_knockback)
		FX.ring(player.get_parent(), player.global_position, def.skill_dive_radius, Color(1.0, 0.7, 0.3, 0.8), 0.3)
		StyleMeter.event(&"melee_dive")
	elif kind == "staff_wave":
		var knock := def.skill_wave_knockback * (def.skill_wave_lvl3_knockback_mult if level >= 3 else 1.0)
		var damage := _skill_damage(def.skill_wave_lvl3_damage_mult) if level >= 3 else 0.0
		_skill_hits_at(player.global_position, def.skill_wave_radius, damage, knock)
		FX.ring(player.get_parent(), player.global_position, def.skill_wave_radius, Color(0.7, 0.9, 1.0, 0.8), 0.35)
		StyleMeter.event(&"melee_wave")
	Audio.sfx("skill_land", "sounds/sfx/skill_land.wav")
	player.camera_fx.add_trauma(0.22)
	Perf.mark("weapon_" + kind + "_land")
	_finish_weapon_skill()

func _skill_damage(mult: float) -> float:
	return def.damage * damage_mult * WeaponDef.level_mult(level) * maxf(0.0, mult)

## Проверка вдоль пути выпада не пропускает врага между соседними кадрами.
func _skill_hits_along(from: Vector3, to: Vector3, radius: float) -> void:
	var steps := maxi(1, int(ceil(from.distance_to(to) / maxf(radius * 0.5, 0.05))))
	for i in range(steps + 1):
		_skill_hits_at(from.lerp(to, float(i) / float(steps)), radius, _skill_damage(def.skill_damage_mult), def.skill_knockback)

func _skill_hits_at(center: Vector3, radius: float, damage: float, knockback: float) -> void:
	if not player.is_inside_tree() or player.get_world_3d() == null:
		return
	_skill_shape.radius = maxf(0.05, radius)
	_skill_query.transform = Transform3D(Basis.IDENTITY, center + Vector3.UP * 0.9)
	var hits := player.get_world_3d().direct_space_state.intersect_shape(_skill_query, 128)
	var new_hits := 0
	for hit in hits:
		var target_node := hit.collider as Node3D
		if target_node == null or not is_instance_valid(target_node):
			continue
		var enemy := target_node as Enemy
		var prop := target_node as Destructible
		if enemy == null and prop == null:
			continue
		if (enemy and enemy.is_dead) or (prop and (prop.is_broken or damage <= 0.0)):
			continue
		var id := target_node.get_instance_id()
		if _skill_hit_ids.has(id):
			continue
		# Объём удара не проходит через стены: выпад пересекает врагов, но не геометрию зала.
		var origin := center + Vector3.UP * 0.9
		var target := target_node.global_position + Vector3.UP * (maxf(0.3, enemy.model_scale * 0.9) if enemy else 0.45)
		if origin.distance_squared_to(target) > 0.0001:
			var ray := PhysicsRayQueryParameters3D.create(origin, target, 1)
			if not player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				continue
		_skill_hit_ids[id] = true
		var away := target_node.global_position - center
		away.y = 0.0
		if away.length_squared() < 0.001:
			away = -player.global_transform.basis.z
		var push := away.normalized() * knockback + Vector3.UP * minf(2.0, knockback * 0.2)
		if prop:
			# Player.deal_damage отдельно обрабатывает пропсы, без бонусов за попадание.
			player.deal_damage(prop, damage, push, "melee_heavy")
		elif damage > 0.0:
			player.deal_damage(enemy, damage * _situational_mult(enemy), push, "melee_heavy")
		else:
			enemy.apply_knockback_only(push)
		new_hits += 1
	if new_hits > 0:
		FX.hitstop(heavy_hitstop * (def.hitstop_mult if def else 1.0))
		var h := view_hand()
		if h:
			h.kick(Vector3(0.0, 0.0, 0.2))
		player.camera_fx.add_trauma(heavy_shake * 0.5)
		hit_landed.emit(new_hits, stage)

func _finish_weapon_skill() -> void:
	if player:
		player.weapon_skill_speed_mult = 1.0
		if _skill_mode == "lunge":
			player.weapon_skill_cancel_motion()
	var h := view_hand()
	if h and _skill_mode == "whirl":
		# Полный оборот эквивалентен исходной позе; не вращать руку назад на 360°.
		h.rotation_degrees = rest_rot
	_skill_mode = ""
	_skill_lunges_left = 0
	_skill_hit_ids.clear()
	heavy = false
	phase = Phase.IDLE
	_hold_time = -1.0
	_since_swing_end = 99.0
	_animate_to(rest_pos, rest_rot, 0.18, Tween.TRANS_QUAD, Tween.EASE_OUT)

func weapon_skill_try_parry_melee(attacker: Enemy) -> bool:
	if not _parry_available() or attacker == null or not is_instance_valid(attacker) or attacker.is_dead or attacker.kind == Enemy.Kind.BOSS:
		return false
	_parry_left = 0.0
	attacker.apply_stun(def.skill_parry_stun, true)
	Audio.sfx("skill_parry", "sounds/sfx/skill_parry.wav")
	ComicFX.pop("weapon_parry", attacker.global_position + Vector3.UP * 1.5)
	StyleMeter.event(&"reflect")
	FX.hitstop(0.04)
	player.camera_fx.add_trauma(0.15)
	Perf.mark("weapon_parry")
	weapon_skill_started.emit("parry")
	return true

func weapon_skill_try_parry_projectile(projectile: Node) -> bool:
	if not _parry_available() or projectile == null or not is_instance_valid(projectile) or not projectile.has_method("reflect"):
		return false
	if bool(projectile.get("reflected")):
		return false
	var velocity: Vector3 = projectile.get("vel")
	if velocity.length_squared() < 0.001:
		velocity = -player.get_aim_forward()
	_parry_left = 0.0
	projectile.call("reflect", -velocity)
	Audio.sfx("skill_parry", "sounds/sfx/skill_parry.wav")
	ComicFX.pop("weapon_parry", player.global_position + Vector3.UP * 1.5)
	Perf.mark("weapon_parry")
	weapon_skill_started.emit("parry")
	return true

func _parry_available() -> bool:
	return active and player != null and not player.is_dead and def != null and def.skill_kind == "lunge" and _parry_left > 0.0

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
	var h := view_hand()
	if h:
		# Замах: запястье взводится; сильный — медленный набор с дрожью
		h.set_state(&"heavy_charge" if heavy else (&"finisher_windup" if is_finisher() else &"melee_windup"))
		h.wrist_target = _tuning().windup_wrist * (1.5 if heavy else 1.0)
	if heavy:
		_animate_to(p[0], p[1], _windup_time(), Tween.TRANS_QUAD, Tween.EASE_OUT)
	else:
		_animate_to(p[0], p[1], _windup_time(), Tween.TRANS_SINE)
	swung.emit(stage)

func _enter_active() -> void:
	phase = Phase.ACTIVE
	_phase_time = 0.0
	var p: Array = _pose()
	_animate_to(p[2], p[3], _active_time() * 1.15, Tween.TRANS_EXPO, Tween.EASE_OUT)
	var h := view_hand()
	if h:
		var t := _tuning()
		h.set_state(&"heavy_release" if heavy else (&"finisher" if is_finisher() else &"melee_strike"))
		h.tremor = 0.0
		h.wrist_target = t.strike_wrist * (1.4 if heavy or is_finisher() else 1.0)
		# Доводка: пружина толкает дальше по ходу взмаха
		var dir := ((p[2] as Vector3) - (p[0] as Vector3)).normalized()
		h.kick(dir * (t.heavy_release_kick if heavy else t.strike_follow))
	Audio.play("sounds/sfx/axe_swing_%d.wav" % (3 if heavy else _slot(stage) + 1))
	if heavy:
		Audio.thor_grunt()
	player.camera_fx.add_trauma(0.12 if heavy else 0.05)

func _enter_recovery() -> void:
	phase = Phase.RECOVERY
	_phase_time = 0.0
	var h := view_hand()
	if h:
		var t := _tuning()
		h.wrist_target = Vector3.ZERO
		# Сильный и добивающий — «тяжёлый» конец взмаха вниз
		if heavy or is_finisher():
			h.kick(Vector3(0, -t.finisher_kick, 0.2 * t.finisher_kick))
		# Восстановление: часть пути назад к покою, остальное — после (тайминги фаз не меняются)
		h.tween_to(h.position.lerp(rest_pos, t.recovery_blend), h.rotation_degrees.lerp(rest_rot, t.recovery_blend),
			_recovery_time(), Tween.TRANS_SINE, Tween.EASE_OUT)

func _animate_to(pos: Vector3, rot: Vector3, time: float, trans: Tween.TransitionType, ease_type: Tween.EaseType = Tween.EASE_IN_OUT) -> void:
	if pivot == null:
		return
	var h := view_hand()
	if h:
		h.tween_to(pos, rot, time, trans, ease_type)
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
			var projectile := c as Node
			if projectile == null or not weapon_skill_try_parry_projectile(projectile):
				c.reflect(forward * reflect_speed_mult)
			new_hits += 1
		elif c is Destructible:
			# Бочка/ящик: урон по пропсу (не враг — не тратит max_targets, без множителей и on_hit)
			_hit_ids[id] = true
			(c as Destructible).take_hit(_stage_damage(), knock, _source())
			new_hits += 1
		elif c.has_method("take_hit"):
			if max_t > 0 and _enemies_hit >= max_t:
				continue
			_hit_ids[id] = true
			_enemies_hit += 1
			var dmg := _stage_damage() * _situational_mult(c)
			# Через игрока: множители тела (пассивка/изъян) и берсерка, хук on_hit
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
		var h := view_hand()
		if h:
			# Отдача от попадания: рука вздрагивает назад (в hit-stop замирает — «вязнет» в цели)
			h.kick(Vector3(0, 0, 0.25), Vector3(_tuning().hit_recoil * (1.6 if strong else 1.0), 0, 0))
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
	return phase != Phase.IDLE or not _skill_mode.is_empty()
