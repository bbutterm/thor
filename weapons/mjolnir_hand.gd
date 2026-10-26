extends Node
class_name MjolnirHand
## Мьёльнир в левой руке: ПКМ — метнуть, повторное ПКМ (или таймер) — вернуть.
## Сам полёт — в mjolnir_projectile.gd. Трейты (GDD 10) — обработчики MjolnirTraitHandler,
## собираются из Run.mjolnir_traits; рука и снаряд вызывают их хуки (trait_call / trait_modify).
## Идеальный хват: ПКМ в окне ±perfect_window от поимки — следующий бросок ×perfect_damage_mult.

signal state_changed(in_hand: bool)
signal perfect_catch
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
	if pivot:
		var tw := pivot.create_tween()
		tw.tween_property(pivot, "position", REST_POS + Vector3(0.3, 0.2, -0.4), 0.06)
		tw.tween_property(pivot, "position", REST_POS + Vector3(0, -0.8, 0), 0.1)
		tw.tween_callback(func() -> void: pivot.visible = false)
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
	if now - _recall_press_time <= perfect_window:
		_perfect_open = false
		_grant_perfect()
	_recall_press_time = -10.0
	if pivot:
		pivot.visible = true
		pivot.position = REST_POS + Vector3(0.15, 0.1, -0.35)
		pivot.rotation_degrees = REST_ROT + Vector3(30, 0, 0)
		var tw := pivot.create_tween().set_parallel(true)
		tw.tween_property(pivot, "position", REST_POS, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(pivot, "rotation_degrees", REST_ROT, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	player.camera_fx.add_trauma(catch_shake)
	Audio.play("sounds/sfx/hammer_catch.wav")
	state_changed.emit(true)
	trait_call(&"on_caught", [self])

## Идеальный хват: «дзынь», вспышка, следующий бросок усилен.
func _grant_perfect() -> void:
	Perf.mark("hammer_perfect")
	perfect_ready = true
	Audio.play("sounds/sfx/perfect_catch.wav")
	var p := hand_point() + player.get_aim_forward() * 0.7
	FX.burst(player.get_parent(), p, 0.3, Color(1.0, 0.85, 0.4, 0.8), 0.16)
	player.camera_fx.kick_fov(4.0)
	perfect_catch.emit()
	trait_call(&"on_perfect_catch", [self])

func current_damage() -> float:
	return base_damage * damage_mult

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
