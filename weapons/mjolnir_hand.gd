extends Node
class_name MjolnirHand
## Мьёльнир в левой руке: ПКМ — метнуть, повторное ПКМ — вернуть (автовозврата нет — П5, GDD 26.4;
## свой возврат только у приёмов, где он суть: Бумеранг, Буря, копии Двух молотов).
## Сам полёт — в mjolnir_projectile.gd. Трейты (GDD 10, блок Б4: стихия + приёмы + связки) — обработчики
## MjolnirTraitHandler, собираются из Run.mjolnir_traits и Run.active_combos(); рука и снаряд вызывают
## их хуки (trait_call / trait_modify).
## Идеальный хват: ПКМ в эффективном окне от поимки — следующий бросок ×perfect_damage_mult.
## Удержание ПКМ (Праща, Заряд — trait_modify(&"hold_throw")): нажал — держишь (on_hold_tick), отпустил —
## бросок с усилением next_throw. Без таких приёмов ПКМ бросает сразу по нажатию, как раньше.

signal state_changed(in_hand: bool)
signal perfect_catch
## Нажал бросок, а молот на перезарядке (HUD мигает, звук осечки)
signal throw_blocked(left: float)
## Итог попытки хвата для подсказки (ui/catch_assist.gd): &"perfect", &"early" (нажал раньше окна), &"late" (позже); offset — на сколько секунд
signal catch_timing(result: StringName, offset: float)
signal traits_changed
## Молот пойман рукой (шлёт снаряд в catch(); служебный возврат — нет) — для итогов забега
signal caught

@export_group("Бросок")
## Скорость броска (П2: 32 → 45 — «как выстрел из пушки»; старое — F6 hammer_power)
@export var throw_speed: float = 45.0
## Перезарядка броска (с) — начинается при поимке (П1, GDD 26.4): после обычной поимки столько секунд
## нельзя бросить. Умеешь ловить — кидаешь без остановки. Качается: трейт modify(&"catch_cooldown"),
## тело/перк — player.modify_stat("hammer_cooldown_mult")
@export var catch_cooldown: float = 1.5
## Перезарядка после идеального хвата (0 — бросай сразу); трейт — modify(&"perfect_catch_cooldown")
@export var perfect_catch_cooldown: float = 0.0
## Старое (FeelSwitch hammer_cooldown, F6): перезарядка от броска и сколько снимает идеальный хват
@export var throw_cooldown: float = 7.0
@export var perfect_cooldown_refund: float = 5.0
## 1.5 У (GDD 10)
@export var base_damage: float = 33.0
## Дальше этого молот не летит: теряет скорость, падает по дуге и втыкается в землю (ждёт ПКМ)
@export var max_range: float = 25.0
## Втыкается в стену или пол (GDD 10). Выключи — будет отскакивать max_wall_bounces раз и возвращаться
@export var sticks_to_world: bool = true
## Возврат разгоняется (П2): с return_speed до return_speed_max с ускорением return_accel (старое — 36 постоянно)
@export var return_speed: float = 25.0
@export var return_speed_max: float = 50.0
@export var return_accel: float = 70.0
## Насколько резко молот поворачивает к руке на возврате (дуга)
@export var return_turn_accel: float = 140.0
## Отскоки от стен до того, как воткнуться/вернуться (база 0; Рикошет добавляет)
@export var max_wall_bounces: int = 0

## Старое (FeelSwitch hammer_recall, F6): автовозврат через столько секунд полёта / воткнутого
@export var auto_return_after: float = 1.5
@export var stuck_auto_return: float = 0.8

@export_group("Промах и останов")
## Долетел до max_range: какая доля скорости остаётся (дальше — падение по дуге)
@export var drop_speed_keep: float = 0.3
## Гравитация падающего молота (м/с²)
@export var drop_gravity: float = 30.0
## Падает дольше этого (пропасть, за край) — сам летит к руке, чтобы не потеряться
@export var drop_lost_time: float = 3.0
## Сквозь корм и бойцов летит дальше; тяжёлые (Раздутый), щитоносцы (без пробития) и боссы останавливают
@export var stopped_by_heavy: bool = true
## Отскок от того, кто остановил: назад (м/с) и вверх — потом падает и втыкается рядом
@export var stop_bounce_speed: float = 4.0
@export var stop_bounce_up: float = 6.0
## Копии «Двух молотов» без ПКМ: через столько секунд полёта возвращаются сами
@export var clone_return_after: float = 1.0

@export_group("Забыл молот")
## Молот не в руке и не летит к ней столько секунд — Один ворчит (раз за зал, пул odin.hammer_forgot)
@export var forgot_nag_after: float = 8.0

@export_group("Без молота")
## Пока молота нет в руке, рывок перезаряжается быстрее на эту долю (0.2 = на 20 %)
@export var dash_recharge_bonus: float = 0.2
## Сколько рун возвращает обычная поимка.
@export var catch_runes: int = 1

@export_group("Идеальный хват")
## Базовое окно (с) до и после поимки; перк добавляется через effective_perfect_window().
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
## Hit-stop первого попадания за бросок; каждое следующее ×hit_hitstop_falloff, не меньше hit_hitstop_min
## (предел за секунду — FX.hitstop, VfxTuning.hitstop_budget_per_second)
@export var hit_hitstop: float = 0.07
@export var hit_hitstop_falloff: float = 0.7
@export var hit_hitstop_min: float = 0.02
@export var catch_shake: float = 0.25
## Толчок руки назад при поимке (множитель ViewmodelMotionTuning.catch_kick)
@export var catch_kick_mult: float = 1.6

@export_group("Сила (П2)")
## Вращение в полёте (рад/с)
@export var spin_speed: float = 34.0
## Бросок: толчок FOV (°), отдача камеры вверх (°), тряска, выпад руки вперёд (ViewmodelMotion.Hand.kick)
@export var throw_fov_kick: float = 3.5
@export var throw_recoil_deg: float = 1.6
@export var throw_trauma: float = 0.18
@export var throw_arm_kick: float = 1.0
@export var throw_arm_tilt: float = 220.0
## Отброс каждого задетого: по линии полёта и вверх (корм — в полёт, «кегли»); на возврате — к Тору
@export var hit_knock_forward: float = 18.0
@export var hit_knock_up: float = 6.0
@export var hit_shake: float = 0.2
## Малая ударная волна у задетого: радиус (м) и отброс соседей без урона
@export var hit_wave_radius: float = 1.5
@export var hit_wave_knock: float = 6.0
@export var hit_wave_up: float = 2.0
## Втыкание в стену/пол: ударная волна (слабый урон, сильный отброс), тряска, трещина на полу
@export var stick_wave_radius: float = 3.0
@export var stick_wave_damage: float = 6.0
@export var stick_wave_knock: float = 14.0
@export var stick_wave_up: float = 5.0
@export var stick_shake: float = 0.3
## «Высота» для размера трещины FX.crack (как у удара-приземления)
@export var stick_crack_height: float = 8.0
## Потрескивание молнии у воткнутого молота (с между разрядами)
@export var stuck_crackle_interval: float = 0.45
## След в полёте: звёзды-искры и короткие ленты молнии (с между ними)
@export var trail_interval: float = 0.035
@export var trail_bolt_interval: float = 0.11
@export var trail_star_size: float = 0.35
## Идеальный хват: короткое замедление (с, масштаб времени), толчок FOV
@export var perfect_slowmo: float = 0.1
@export var perfect_slowmo_scale: float = 0.3
@export var perfect_fov_kick: float = 6.0

## Старые числа силы молота (до плейтеста 28.10) — для сравнения F6 (FeelSwitch hammer_power)
const OLD_POWER := {
	"throw_speed": 32.0, "return_speed": 36.0, "spin": 22.0, "hitstop": 0.04, "catch_shake": 0.15,
	"knock_forward": 9.0, "knock_up": 3.0, "hit_shake": 0.12, "throw_trauma": 0.12, "stick_shake": 0.08,
	"perfect_fov_kick": 4.0, "catch_kick_mult": 1.0,
}

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
## Обработчики активных связок «стихия + приём» (Run.active_combos(); отдельно — тесты сверяют traits с Run.mjolnir_traits)
var combo_traits: Array[MjolnirTraitHandler] = []
## Усиление следующего броска от приёмов удержания: damage_mult, speed_mult, range_mult, pierce, stun
var next_throw: Dictionary = {}
## ПКМ зажата с молотом в руке (Праща, Заряд) и сколько секунд
var holding: bool = false
var hold_time: float = 0.0
## Для HUD: прогресс удержания 0…1 и подпись («ЗАРЯД», «ПРАЩА»); пишут обработчики приёмов
var hold_progress: float = 0.0
var hold_label: String = ""

var _caught_time: float = -10.0
var _recall_press_time: float = -10.0
var _perfect_open: bool = false
var _clock: float = 0.0
## Попытка хвата на этот возврат уже была (одна попытка: нажал раньше окна — провал, повтор не спасает)
var _catch_attempted: bool = false
## Осталось перезарядки броска, с
var cooldown_left: float = 0.0
## Полная длина текущей перезарядки (для полоски HUD)
var cooldown_total: float = 0.0
## Сколько секунд молот не в руке и не возвращается (для ворчания Одина) и сказал ли уже в этом зале
var away_time: float = 0.0
var forgot_nagged: bool = false

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
	if cooldown_left > 0.0:
		cooldown_left = maxf(cooldown_left - delta, 0.0)
	if player == null or player.is_dead:
		return
	if not in_hand:
		_dash_bonus_tick(delta)
		_anim_recall_tick()
		_forgot_tick(delta)
	if holding:
		_hold_tick(delta)
	if not player.input_enabled:
		return
	if Input.is_action_just_pressed("throw"):
		press_throw()

## Нажата ПКМ: с приёмом удержания и молотом в руке — начать удержание, иначе бросок / возврат.
func press_throw() -> void:
	if in_hand and bool(trait_modify(&"hold_throw", false)):
		begin_hold()
	else:
		request_throw_or_recall()

## Начать удержание ПКМ (Праща, Заряд). Идеальный хват засчитывается по нажатию, как у обычного броска.
func begin_hold() -> void:
	if not in_hand or holding:
		return
	var now := _now()
	if _perfect_open and now - _caught_time <= effective_perfect_window():
		_grant_perfect()
		catch_timing.emit(&"perfect", now - _caught_time)
	_perfect_open = false
	if _blocked_by_cooldown():
		return
	holding = true
	hold_time = 0.0
	hold_progress = 0.0
	trait_call(&"on_hold_start", [self])

func _hold_tick(delta: float) -> void:
	if not in_hand or player.is_dead:
		cancel_hold()
		return
	if is_throw_held():
		hold_time += delta
		trait_call(&"on_hold_tick", [self, hold_time, delta])
	else:
		release_hold()

## Отпустил ПКМ (или приём отпустил сам): обработчики кладут усиление в next_throw, затем бросок.
func release_hold() -> void:
	if not holding:
		return
	holding = false
	trait_call(&"on_hold_release", [self, hold_time])
	hold_progress = 0.0
	hold_label = ""
	throw_hammer()

## Прервать удержание без броска (смена зала, смерть, смена трейтов): обработчики убирают за собой (held = -1)
func cancel_hold() -> void:
	if not holding:
		return
	holding = false
	trait_call(&"on_hold_release", [self, -1.0])
	next_throw = {}
	hold_progress = 0.0
	hold_label = ""

## Игровое время (сумма шагов физики): окно хвата не зависит от скорости прогона тестов
func _now() -> float:
	return _clock

func request_throw_or_recall() -> void:
	var now := _now()
	if in_hand:
		# ПКМ сразу после поимки — тоже идеальный хват (и сразу усиленный бросок)
		if _perfect_open and now - _caught_time <= effective_perfect_window():
			_grant_perfect()
			catch_timing.emit(&"perfect", now - _caught_time)
		elif _perfect_open and now - _caught_time <= catch_feedback_range:
			catch_timing.emit(&"late", now - _caught_time)
		_perfect_open = false
		if _blocked_by_cooldown():
			return
		throw_hammer()
	elif projectile and is_instance_valid(projectile):
		if projectile.state == MjolnirProjectile.State.RETURN:
			# Уже летит обратно — нажатие засчитывается для идеального хвата. Попытка одна:
			# раньше окна — сразу «РАНО», на этот возврат хват провален
			if _catch_attempted:
				return
			_catch_attempted = true
			var eta := projectile.catch_eta()
			if eta > effective_perfect_window():
				catch_timing.emit(&"early", -eta)
			else:
				_recall_press_time = now
		else:
			projectile.start_return(true)

## Бросок на перезарядке — осечка (звук, сигнал для HUD); true — бросать нельзя.
func _blocked_by_cooldown() -> bool:
	if cooldown_left <= 0.0:
		return false
	Audio.play("sounds/sfx/gun_empty.wav")
	throw_blocked.emit(cooldown_left)
	return true

## Длина перезарядки после поимки с учётом трейтов и тела (perfect — после идеального хвата)
## Старое (FeelSwitch hammer_cooldown) — перезарядка от броска throw_cooldown, perfect не учитывается.
func effective_cooldown(perfect: bool = false) -> float:
	var cd: float
	if FeelSwitch.is_old(&"hammer_cooldown"):
		cd = float(trait_modify(&"throw_cooldown", throw_cooldown))
	elif perfect:
		cd = float(trait_modify(&"perfect_catch_cooldown", perfect_catch_cooldown))
	else:
		cd = float(trait_modify(&"catch_cooldown", catch_cooldown))
	if player:
		cd *= float(player.modify_stat(&"hammer_cooldown_mult", 1.0))
	return maxf(cd, 0.0)

## Сбросить перезарядку (смена зала, тесты)
func reset_cooldown() -> void:
	cooldown_left = 0.0

func throw_hammer() -> void:
	Perf.mark("hammer_throw")
	if not in_hand:
		return
	in_hand = false
	_catch_attempted = false
	away_time = 0.0
	if FeelSwitch.is_old(&"hammer_cooldown"):
		cooldown_total = effective_cooldown()
		cooldown_left = cooldown_total
	var proj := MjolnirProjectile.new()
	player.get_parent().add_child(proj)
	var origin := player.get_aim_origin() + player.get_aim_forward() * 0.8 + player.global_transform.basis.x * -0.35
	var mods := next_throw
	next_throw = {}
	var speed := float(trait_modify(&"throw_speed", current_throw_speed())) * float(mods.get("speed_mult", 1.0))
	projectile = proj
	proj.launch(self, origin, player.get_aim_forward() * speed)
	proj.apply_throw_mods(mods)
	if perfect_ready:
		perfect_ready = false
		proj.set_empowered(perfect_damage_mult)
	_anim_throw()
	player.camera_fx.add_trauma(pw(throw_trauma, &"throw_trauma"))
	Audio.play("sounds/sfx/hammer_throw.wav")
	if powered():
		# П2: толчок FOV, отдача камеры, низы под «вжух»
		player.camera_fx.kick_fov(throw_fov_kick)
		player.camera_fx.kick_recoil(throw_recoil_deg, randf_range(-0.3, 0.3))
		Audio.play("sounds/sfx/hammer_throw_low.wav")
	state_changed.emit(false)

## Вызывается снарядом, когда молот вернулся в руку.
func on_caught() -> void:
	Perf.mark("hammer_caught")
	in_hand = true
	projectile = null
	var now := _now()
	_caught_time = now
	# Нажал раньше окна — «поздний» хват после поимки тоже не засчитывается
	_perfect_open = not _catch_attempted
	var perfect := now - _recall_press_time <= effective_perfect_window()
	# Перезарядка начинается при поимке; идеальный хват (ниже или в окне после поимки) её снимает
	if not FeelSwitch.is_old(&"hammer_cooldown"):
		cooldown_total = effective_cooldown()
		cooldown_left = cooldown_total
	if player and not player.is_dead:
		player.restore_mjolnir_runes(catch_runes)
		if not player.is_on_floor() and not player.is_climbing:
			player._jumps_left = player.extra_jumps
			player._wall_jumps_left = player.wall_jumps
	if perfect:
		_perfect_open = false
		_grant_perfect()
		catch_timing.emit(&"perfect", _recall_press_time - now)
	_recall_press_time = -10.0
	_anim_catch(perfect)
	player.camera_fx.add_trauma(pw(catch_shake, &"catch_shake"))
	Audio.play("sounds/sfx/hammer_catch.wav")
	if powered() and player and not player.is_dead:
		FX.sparks(player.get_parent(), hand_point() + player.get_aim_forward() * 0.6, Color(0.6, 0.88, 1.0), 12, 4.0, 6.0, 0.05, 0.3)
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
	if powered():
		# П2: короткий резкий выпуск — рука «выстреливает» вперёд
		h.kick(Vector3(0.15, 0.05, -1.0) * throw_arm_kick, Vector3(-throw_arm_tilt, 0, 0))
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
	var km := pw(catch_kick_mult, &"catch_kick_mult")
	if perfect:
		h.set_state(&"perfect_catch", t.perfect_twirl_time)
		h.kick(Vector3(0, 0.3, 1.0) * t.perfect_kick * km, Vector3(t.perfect_tilt, 0, -t.perfect_tilt * 0.3))
		_twirl(arm, t)
	else:
		h.set_state(&"catch", 0.1)
		h.kick(Vector3(0, 0.2, 1.0) * t.catch_kick * km, Vector3(t.catch_tilt, 0, 0))

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
	if player and not player.is_dead:
		player.restore_mjolnir_runes(player.dash_charges_max)
	if FeelSwitch.is_old(&"hammer_cooldown"):
		cooldown_left = maxf(cooldown_left - float(trait_modify(&"perfect_cooldown_refund", perfect_cooldown_refund)), 0.0)
	else:
		cooldown_left = minf(cooldown_left, effective_cooldown(true))
	Audio.play("sounds/sfx/perfect_catch.wav")
	var p := hand_point() + player.get_aim_forward() * 0.7
	FX.burst(player.get_parent(), p, 0.3, Color(1.0, 0.85, 0.4, 0.8), 0.16)
	FX.perfect_catch(p)
	player.camera_fx.kick_fov(pw(perfect_fov_kick, &"perfect_fov_kick"))
	if powered():
		# П2: ярче — короткое замедление и золотая вспышка
		FX.slowmo(perfect_slowmo, perfect_slowmo_scale)
		FX.hit_flash(player.get_parent(), p, 0.9, Color(1.0, 0.82, 0.35))
		FX.sparks(player.get_parent(), p, Color(1.0, 0.85, 0.4), 16, 5.0, 4.0, 0.05, 0.35)
		ComicFX.on_perfect_catch()
	perfect_catch.emit()
	Dialogue.thor_bark("catch", 0.5)
	trait_call(&"on_perfect_catch", [self])

## Новая сила молота (П2) включена — не старое под F6 (FeelSwitch hammer_power)
func powered() -> bool:
	return not FeelSwitch.is_old(&"hammer_power")

## Число силы: новое значение или старое из OLD_POWER (F6)
func pw(new_value: float, old_key: StringName) -> float:
	return new_value if powered() else float(OLD_POWER[String(old_key)])

func current_throw_speed() -> float:
	return pw(throw_speed, &"throw_speed")

## Скорость возврата через t с после начала: разгон return_speed → return_speed_max (старое — постоянная 36)
func return_speed_at(t: float) -> float:
	var v := float(OLD_POWER["return_speed"]) if not powered() else minf(return_speed + return_accel * maxf(t, 0.0), return_speed_max)
	return v * return_speed_mult

## Hit-stop n-го попадания за бросок (n с 0)
func hitstop_for(n: int) -> float:
	if not powered():
		return float(OLD_POWER["hitstop"])
	return maxf(hit_hitstop * pow(hit_hitstop_falloff, n), hit_hitstop_min)

func current_damage() -> float:
	return base_damage * damage_mult

## Общий размер окна для игровой логики, подсказки и бота. Базовое экспортированное значение не меняется.
func effective_perfect_window() -> float:
	return perfect_window + Save.perk("catch_window")

## Сколько ещё открыто окно хвата после поимки (с), −1 — закрыто. Для подсказки хвата.
func perfect_window_left() -> float:
	if not in_hand or not _perfect_open:
		return -1.0
	var left := effective_perfect_window() - (_now() - _caught_time)
	return left if left >= 0.0 else -1.0

func hand_point() -> Vector3:
	return player.get_aim_origin() + player.global_transform.basis.x * -0.4 + Vector3(0, -0.3, 0)

func is_throw_held() -> bool:
	return hold_override or Input.is_action_pressed("throw")

## Без молота в руке рывок перезаряжается быстрее (GDD 10). Таймер игрока подкручиваем снаружи,
## чтобы не трогать player.gd; если поле переименуют — бонус просто пропадёт.
func _dash_bonus_tick(delta: float) -> void:
	if dash_recharge_bonus <= 0.0 or not player.is_on_floor() or player.is_climbing or player.dash_charges >= player.dash_charges_max:
		return
	var t: Variant = player.get("_dash_recharge_timer")
	if t is float:
		player.set("_dash_recharge_timer", t + delta * dash_recharge_bonus)

## Забыл молот: воткнут/лежит/висит без ПКМ дольше forgot_nag_after — Один ворчит раз за зал.
## Реплика может не пройти лимит боевых реплик Одина — тогда попробуем ещё раз позже.
func _forgot_tick(delta: float) -> void:
	if FeelSwitch.is_old(&"hammer_recall"):
		return
	if projectile and is_instance_valid(projectile) and projectile.state == MjolnirProjectile.State.RETURN:
		away_time = 0.0
		return
	away_time += delta
	if not forgot_nagged and away_time >= forgot_nag_after:
		if Odin.say("hammer_forgot") != "":
			forgot_nagged = true
		else:
			away_time = forgot_nag_after - 1.0

## Новый зал: молот сам в руке, без перезарядки, ворчание Одина — снова доступно.
func on_room_start() -> void:
	force_return_instant()
	away_time = 0.0
	forgot_nagged = false

## Сбросить при смене зала (на всякий случай).
func force_return_instant() -> void:
	cancel_hold()
	if projectile and is_instance_valid(projectile):
		projectile.queue_free()
	if not in_hand:
		on_caught()
	# Служебный возврат (смена зала, трейтов) — не поимка: перезарядки нет
	reset_cooldown()

# --- Трейты ---

func _rebuild_traits(_list: Array = []) -> void:
	if not in_hand and is_inside_tree():
		force_return_instant()
	cancel_hold()
	next_throw = {}
	for h in traits + combo_traits:
		h.on_unequip(self)
	traits.clear()
	combo_traits.clear()
	for t in Run.mjolnir_traits:
		var h := _make_handler(t, Run.mjolnir_trait_level(t.id) if t else 1)
		if h:
			traits.append(h)
	for c in Run.active_combos():
		var h := _make_handler(c, 1)
		if h:
			combo_traits.append(h)
	for h in traits + combo_traits:
		h.on_equip(self)
	traits_changed.emit()

func _make_handler(t: MjolnirTrait, lv: int) -> MjolnirTraitHandler:
	if t == null or t.handler == null:
		return null
	var h := t.handler.duplicate(true) as MjolnirTraitHandler
	h.level = lv
	h.trait_def = t
	h.hand = self
	return h

## Сначала трейты (стихия, приёмы), потом связки — связки видят, что уже сделали их части
func trait_call(method: StringName, args: Array) -> void:
	for h in traits:
		h.callv(method, args)
	for h in combo_traits:
		h.callv(method, args)

func trait_modify(stat: StringName, value: Variant) -> Variant:
	for h in traits:
		value = h.modify(stat, value)
	for h in combo_traits:
		value = h.modify(stat, value)
	return value

func has_trait(id: StringName) -> bool:
	return trait_handler(id) != null

## Обработчик трейта или связки по id (null — нет)
func trait_handler(id: StringName) -> MjolnirTraitHandler:
	for h in traits + combo_traits:
		if h.trait_def and h.trait_def.id == id:
			return h
	return null

## Обработчик стихии молота (null — стихии нет)
func element_handler() -> MjolnirElementHandler:
	for h in traits:
		if h is MjolnirElementHandler:
			return h as MjolnirElementHandler
	return null

func _on_player_slammed(power: float) -> void:
	trait_call(&"on_player_slam", [self, power, player.global_position])
