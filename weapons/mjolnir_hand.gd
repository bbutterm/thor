extends Node
class_name MjolnirHand
## Мьёльнир в левой руке: ПКМ — метнуть, повторное ПКМ (или таймер) — вернуть.
## Сам полёт — в mjolnir_projectile.gd. Трейты (GDD 10) — обработчики MjolnirTraitHandler,
## собираются из Run.mjolnir_traits; рука и снаряд вызывают их хуки (trait_call / trait_modify).
## Идеальный хват: ПКМ в окне ±perfect_window от поимки — следующий бросок ×perfect_damage_mult.

signal state_changed(in_hand: bool)
signal perfect_catch
## Итог попытки хвата для подсказки (ui/catch_assist.gd): &"perfect", &"early" (нажал раньше окна), &"late" (позже); offset — на сколько секунд
signal catch_timing(result: StringName, offset: float)
signal traits_changed

@export_group("Бросок")
@export var throw_speed: float = 32.0
## 1.5 У (GDD 10)
@export var base_damage: float = 33.0
## Дальше этого молот не летит — начинает возврат
@export var max_range: float = 25.0
## Через сколько секунд полёта молот сам летит обратно
@export var auto_return_after: float = 1.5
## Втыкается в стену или пол (GDD 10). Выключи — будет отскакивать max_wall_bounces раз и возвращаться
@export var sticks_to_world: bool = true
## Сколько секунд воткнутый молот ждёт ПКМ, прежде чем вернуться сам (0 — ждёт всегда)
@export var stuck_auto_return: float = 0.8
@export var return_speed: float = 36.0
## Насколько резко молот поворачивает к руке на возврате (дуга)
@export var return_turn_accel: float = 140.0
## Отскоки от стен до того, как воткнуться/вернуться (база 0; Рикошет добавляет)
@export var max_wall_bounces: int = 0

@export_group("Без молота")
## Пока молота нет в руке, рывок перезаряжается быстрее на эту долю (0.2 = на 20 %)
@export var dash_recharge_bonus: float = 0.2

@export_group("Идеальный хват")
## Окно (с) до и после поимки, в которое надо нажать ПКМ
@export var perfect_window: float = 0.15
@export var perfect_damage_mult: float = 2.0
## Промах по окну хвата не дальше этого (с) — подсказка покажет «РАНО»/«ПОЗДНО»; дальше нажатие считается обычным
@export var catch_feedback_range: float = 0.6

@export_group("Цепная молния")
## Сколько врагов задевает молния от попадания без трейтов (0 — нет; трейт «Цепная молния» добавляет)
@export var chain_targets: int = 0
@export var chain_damage_ratio: float = 0.5
@export var chain_radius: float = 7.0

@export_group("Отдача")
@export var hit_hitstop: float = 0.04
@export var catch_shake: float = 0.15

var damage_mult: float = 1.0
var return_speed_mult: float = 1.0
var in_hand: bool = true
var projectile: MjolnirProjectile = null
## Следующий бросок усилен идеальным хватом
var perfect_ready: bool = false
## Для тестов: считать ПКМ зажатой (Буря)
var hold_override: bool = false
## Активные обработчики трейтов (копии на забег)
var traits: Array[MjolnirTraitHandler] = []

var _caught_time: float = -10.0
var _recall_press_time: float = -10.0
var _perfect_open: bool = false
var _clock: float = 0.0

@export var player_path: NodePath = ^".."
@export var pivot_path: NodePath
@export var hand_mesh_path: NodePath

@onready var player: Player = get_node(player_path)
@onready var pivot: Node3D = get_node_or_null(pivot_path)
@onready var hand_mesh: Node = get_node_or_null(hand_mesh_path)

const REST_POS := Vector3(-0.5, -0.37, -1.0)
const REST_ROT := Vector3(-10, -15, 12)

func _ready() -> void:
	if pivot:
		pivot.position = REST_POS
		pivot.rotation_degrees = REST_ROT
	Run.mjolnir_traits_changed.connect(_rebuild_traits)
	if player:
		player.slammed.connect(_on_player_slammed)
	_rebuild_traits()

## Цвет кожи и рукава (из тела BodyDef). Рука — ViewmodelArm или (старое) простой меш.
func set_hand_color(c: Color, sleeve: Color = Color(0, 0, 0, 0)) -> void:
	if hand_mesh is ViewmodelArm:
		(hand_mesh as ViewmodelArm).recolor(c, sleeve)
	elif hand_mesh is MeshInstance3D:
		(hand_mesh as MeshInstance3D).material_override = FX.make_material(c, 0.9)

func _physics_process(delta: float) -> void:
	_clock += delta
	if player == null or player.is_dead:
		return
	if not in_hand:
		_dash_bonus_tick(delta)
		_anim_recall_tick()
	if not player.input_enabled:
		return
	if Input.is_action_just_pressed("throw"):
		request_throw_or_recall()

## Игровое время (сумма шагов физики): окно хвата не зависит от скорости прогона тестов
func _now() -> float:
	return _clock

func request_throw_or_recall() -> void:
	var now := _now()
	if in_hand:
		# ПКМ сразу после поимки — тоже идеальный хват (и сразу усиленный бросок)
		if _perfect_open and now - _caught_time <= perfect_window:
			_grant_perfect()
			catch_timing.emit(&"perfect", now - _caught_time)
		elif _perfect_open and now - _caught_time <= catch_feedback_range:
			catch_timing.emit(&"late", now - _caught_time)
		_perfect_open = false
		throw_hammer()
	elif projectile and is_instance_valid(projectile):
		if projectile.state == MjolnirProjectile.State.RETURN:
			# Уже летит обратно — нажатие засчитывается для идеального хвата
			_recall_press_time = now
		else:
			projectile.start_return(true)

func throw_hammer() -> void:
	Perf.mark("hammer_throw")
	if not in_hand:
		return
	in_hand = false
	var proj := MjolnirProjectile.new()
	player.get_parent().add_child(proj)
	var origin := player.get_aim_origin() + player.get_aim_forward() * 0.8 + player.global_transform.basis.x * -0.35
	var speed := float(trait_modify(&"throw_speed", throw_speed))
	projectile = proj
	proj.launch(self, origin, player.get_aim_forward() * speed)
	if perfect_ready:
		perfect_ready = false
		proj.set_empowered(perfect_damage_mult)
	_anim_throw()
	player.camera_fx.add_trauma(0.12)
	Audio.play("sounds/sfx/hammer_throw.wav")
	state_changed.emit(false)

## Вызывается снарядом, когда молот вернулся в руку.
func on_caught() -> void:
	Perf.mark("hammer_caught")
	in_hand = true
	projectile = null
	var now := _now()
	_caught_time = now
	_perfect_open = true
	var perfect := now - _recall_press_time <= perfect_window
	if perfect:
		_perfect_open = false
		_grant_perfect()
		catch_timing.emit(&"perfect", _recall_press_time - now)
	elif now - _recall_press_time <= catch_feedback_range:
		catch_timing.emit(&"early", _recall_press_time - now)
	_recall_press_time = -10.0
	_anim_catch(perfect)
	player.camera_fx.add_trauma(catch_shake)
	Audio.play("sounds/sfx/hammer_catch.wav")
	state_changed.emit(true)
	trait_call(&"on_caught", [self])

# --- Вид: левая рука (ViewmodelMotion.Hand над HammerPivot) ---

## Рука вьюмодели, null — пока Player не собрал руки.
func view_hand() -> ViewmodelMotion.Hand:
	if player == null or player.view_motion == null or pivot == null:
		return null
	return player.view_motion.hand_for(pivot)

## Бросок: рука сразу взведена за плечо → резкий выпуск вперёд (молот вылетает в этом же кадре — вид его
## догоняет за throw_time) → пустая рука с разжатыми пальцами опускается.
func _anim_throw() -> void:
	var h := view_hand()
	if h == null:
		if pivot:
			pivot.visible = false
		return
	var t := player.view_motion.tuning
	h.rest_pos = REST_POS
	h.rest_rot = REST_ROT
	h.set_state(&"throw", t.throw_time + 0.05)
	h.snap(REST_POS + t.throw_cock_pos, REST_ROT + t.throw_cock_rot)
	h.wrist_target = Vector3(-25, 0, 0)
	var arm := h.arm
	var tw := h.new_tween()
	tw.set_parallel(true)
	tw.tween_property(h, "position", REST_POS + t.throw_release_pos, t.throw_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(h, "rotation_degrees", REST_ROT + t.throw_release_rot, t.throw_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		h.wrist_target = Vector3(20, 0, 0)
		if arm:
			arm.set_weapon_visible(false)
			arm.grip_target = 0.0
			arm.open_style = 0.0).set_delay(t.throw_time * 0.45)
	tw.chain().tween_callback(func() -> void:
		h.set_state(&"empty", t.empty_time)
		h.wrist_target = Vector3.ZERO
		if arm:
			arm.grip_target = 0.35)
	tw.chain().tween_property(h, "position", REST_POS + t.empty_pos, t.empty_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(h, "rotation_degrees", REST_ROT + t.empty_rot, t.empty_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	h.rest_pos = REST_POS + t.empty_pos
	h.rest_rot = REST_ROT + t.empty_rot

## Возврат: рука тянется навстречу молоту, пальцы раскрыты «хватом»; на подлёте — чуть следит за ним.
func _anim_recall_tick() -> void:
	var h := view_hand()
	if h == null or projectile == null or not is_instance_valid(projectile):
		return
	if projectile.state != MjolnirProjectile.State.RETURN:
		return
	var t := player.view_motion.tuning
	if h.state != &"recall":
		h.set_state(&"recall")
		var tw := h.tween_to(REST_POS + t.recall_pos, REST_ROT + t.recall_rot, t.recall_time, Tween.TRANS_BACK, Tween.EASE_OUT)
		tw.set_parallel(true)
		if h.arm:
			h.arm.grip_target = 0.0
			h.arm.open_style = 1.0
		h.wrist_target = Vector3(-20, 0, 0)
		return
	if h.is_tweening():
		return
	# Тянуться к молоту по экрану (в системе камеры)
	var cam := player.camera
	var to := cam.global_transform.basis.inverse() * (projectile.global_position - cam.global_position)
	var dir := Vector2(to.x, to.y) / maxf(absf(to.z), 1.0)
	var target := REST_POS + t.recall_pos + Vector3(dir.x, dir.y, 0).limit_length(1.0) * t.recall_track
	h.position = h.position.lerp(target, 0.2)

## Ловля: молот в руке, пальцы сжаты, толчок назад; идеальный хват — сильнее и прокрут молота в руке.
func _anim_catch(perfect: bool) -> void:
	var h := view_hand()
	if h == null:
		if pivot:
			pivot.visible = true
			pivot.position = REST_POS
			pivot.rotation_degrees = REST_ROT
		return
	var t := player.view_motion.tuning
	h.rest_pos = REST_POS
	h.rest_rot = REST_ROT
	h.visible = true
	h.wrist_target = Vector3.ZERO
	var arm := h.arm
	if arm:
		arm.set_weapon_visible(true)
		arm.grip_target = 1.0
		arm.grip = 1.0
		arm.open_style = 0.0
	h.tween_to(REST_POS, REST_ROT, 0.24, Tween.TRANS_BACK, Tween.EASE_OUT)
	if perfect:
		h.set_state(&"perfect_catch", t.perfect_twirl_time)
		h.kick(Vector3(0, 0.3, 1.0) * t.perfect_kick, Vector3(t.perfect_tilt, 0, -t.perfect_tilt * 0.3))
		_twirl(arm, t)
	else:
		h.set_state(&"catch", 0.1)
		h.kick(Vector3(0, 0.2, 1.0) * t.catch_kick, Vector3(t.catch_tilt, 0, 0))

## Прокрут молота вокруг рукояти (только модель в кулаке; рука держит хват).
var _twirl_tween: Tween

func _twirl(arm: ViewmodelArm, t: ViewmodelMotionTuning) -> void:
	if arm == null or arm.weapon == null:
		return
	if _twirl_tween and _twirl_tween.is_valid():
		_twirl_tween.kill()
	var w := arm.weapon
	var base := arm.weapon_rotation
	w.rotation_degrees = base
	_twirl_tween = w.create_tween()
	_twirl_tween.tween_property(w, "rotation_degrees:y", base.y + 360.0 * t.perfect_twirl_turns, t.perfect_twirl_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_twirl_tween.tween_callback(func() -> void: w.rotation_degrees = base)

## Идеальный хват: «дзынь», вспышка, следующий бросок усилен.
func _grant_perfect() -> void:
	Perf.mark("hammer_perfect")
	perfect_ready = true
	Audio.play("sounds/sfx/perfect_catch.wav")
	var p := hand_point() + player.get_aim_forward() * 0.7
	FX.burst(player.get_parent(), p, 0.3, Color(1.0, 0.85, 0.4, 0.8), 0.16)
	FX.perfect_catch(p)
	player.camera_fx.kick_fov(4.0)
	perfect_catch.emit()
	Dialogue.thor_bark("catch", 0.5)
	trait_call(&"on_perfect_catch", [self])

func current_damage() -> float:
	return base_damage * damage_mult

## Сколько ещё открыто окно хвата после поимки (с), −1 — закрыто. Для подсказки хвата.
func perfect_window_left() -> float:
	if not in_hand or not _perfect_open:
		return -1.0
	var left := perfect_window - (_now() - _caught_time)
	return left if left >= 0.0 else -1.0

func hand_point() -> Vector3:
	return player.get_aim_origin() + player.global_transform.basis.x * -0.4 + Vector3(0, -0.3, 0)

func is_throw_held() -> bool:
	return hold_override or Input.is_action_pressed("throw")

## Без молота в руке рывок перезаряжается быстрее (GDD 10). Таймер игрока подкручиваем снаружи,
## чтобы не трогать player.gd; если поле переименуют — бонус просто пропадёт.
func _dash_bonus_tick(delta: float) -> void:
	if dash_recharge_bonus <= 0.0 or player.dash_charges >= player.dash_charges_max:
		return
	var t: Variant = player.get("_dash_recharge_timer")
	if t is float:
		player.set("_dash_recharge_timer", t + delta * dash_recharge_bonus)

## Сбросить при смене зала (на всякий случай).
func force_return_instant() -> void:
	if projectile and is_instance_valid(projectile):
		projectile.queue_free()
	if not in_hand:
		on_caught()

# --- Трейты ---

func _rebuild_traits(_list: Array = []) -> void:
	if not in_hand and is_inside_tree():
		force_return_instant()
	for h in traits:
		h.on_unequip(self)
	traits.clear()
	for t in Run.mjolnir_traits:
		if t == null or t.handler == null:
			continue
		var h := t.handler.duplicate(true) as MjolnirTraitHandler
		h.level = Run.mjolnir_trait_level(t.id)
		h.trait_def = t
		h.hand = self
		traits.append(h)
		h.on_equip(self)
	traits_changed.emit()

func trait_call(method: StringName, args: Array) -> void:
	for h in traits:
		h.callv(method, args)

func trait_modify(stat: StringName, value: Variant) -> Variant:
	for h in traits:
		value = h.modify(stat, value)
	return value

func has_trait(id: StringName) -> bool:
	for h in traits:
		if h.trait_def and h.trait_def.id == id:
			return true
	return false

func _on_player_slammed(power: float) -> void:
	trait_call(&"on_player_slam", [self, power, player.global_position])
