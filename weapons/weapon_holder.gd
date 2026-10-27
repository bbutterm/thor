extends Node
class_name WeaponHolder
## Два слота оружия правой руки: мили (слот 0) и ренж (слот 1). Мьёльнир — в левой, вне слотов.
## Свитч (Q / колесо / 1 / 2) с короткой анимацией, подбор по E (подобранное встаёт в слот своего класса,
## старое падает на пол), сундуки, патроны. Мили исполняет узел Axe (axe.gd), ренж — RangedWeapon.
## Узел «Weapons» игрока (player.tscn); если его нет — Player создаёт его сам.

signal slots_changed
signal active_changed(slot: int)
signal ammo_changed(mag: int, reserve: int)
signal reload_changed(active: bool, progress: float)
## Подсказка «[E] …» (пустая строка — скрыть)
signal prompt_changed(text: String)

const MELEE := 0
const RANGED := 1
const DEFAULT_MELEE := "res://weapons/defs/axe.tres"

@export_group("Свитч")
## Время смены оружия, с (половина — убрать, половина — достать)
@export var switch_time: float = 0.25
## Пустой ренж без запаса — сам переключиться на мили (GDD 9.2)
@export var auto_switch_on_empty: bool = true
@export var auto_reload: bool = true

@export_group("Подбор")
@export var interact_radius: float = 2.4
## Патроны подбираются сами, если подойти ближе
@export var ammo_pickup_radius: float = 1.4
## Ящик патронов: доля предела запаса (но не меньше магазина)
@export var ammo_box_fraction: float = 0.4
## Шанс, что враг уронит патроны (если у Тора есть ренж); у метателей ×2, элита — всегда
@export_range(0.0, 1.0) var ammo_drop_chance: float = 0.15
## Всё оружие в пуле выпадения (иначе — только с in_drop_pool, «стартовый пул» GDD)
@export var drop_all_weapons: bool = false
## Шанс, что найденное оружие будет уровня 2 / 3
@export_range(0.0, 1.0) var drop_level2_chance: float = 0.2
@export_range(0.0, 1.0) var drop_level3_chance: float = 0.05

@export_group("Ренж: общее")
## Сколько секунд после выстрела действует замедление «при стрельбе»
@export var fire_slow_time: float = 0.3
## Толчок бочки пулей
@export var prop_bullet_impulse: float = 1.2
## Гильзы на полу одновременно (слой debris)
@export var max_casings: int = 24
@export var casing_lifetime: float = 2.0
@export var max_tracers: int = 40
@export var bolt_stick_time: float = 1.5
## Гвоздомёт: корм прибит к полу (с)
@export var nail_pin_time: float = 1.0
## Ракетница: радиус взрыва и рокет-джамп (толчок Тора вверх / от взрыва)
@export var rocket_radius: float = 3.5
@export var rocket_jump_up: float = 13.0
@export var rocket_jump_side: float = 7.0

var player: Player
var axe: Axe
var gun: RangedWeapon
var pivot: Node3D
var arm: ViewmodelArm
var view_camera: Camera3D

var melee: WeaponItem
var ranged: WeaponItem
var active_slot: int = MELEE
var _switch_left: float = 0.0
var _switch_tween: Tween
var _focus: Node3D
var _prompt: String = ""

func _ready() -> void:
	player = get_parent() as Player
	axe = player.get_node("Axe") as Axe
	pivot = axe.pivot
	arm = axe.hand_mesh as ViewmodelArm
	view_camera = pivot.get_parent() as Camera3D if pivot else null
	gun = RangedWeapon.new()
	gun.name = "Ranged"
	add_child(gun)
	gun.setup(self)
	gun.ammo_changed.connect(func(m: int, r: int) -> void: ammo_changed.emit(m, r))
	gun.reload_changed.connect(func(a: bool, p: float) -> void: reload_changed.emit(a, p))
	gun.ran_dry.connect(_on_ran_dry)
	if melee == null:
		var d := load(DEFAULT_MELEE) as WeaponDef
		if d:
			equip(d, 1, false)

# --- Публичное API (тела этапа 2, тесты, сундуки) ---

## Взять оружие по описанию: встаёт в слот своего класса. drop_old — старое падает на пол.
func equip(d: WeaponDef, level: int = 1, drop_old: bool = true) -> WeaponItem:
	if d == null:
		return null
	return equip_item(WeaponItem.create(d, level), drop_old)

## Взять конкретный экземпляр (с его патронами/уровнем). Возвращает выброшенный старый (или null).
func equip_item(it: WeaponItem, drop_old: bool = true) -> WeaponItem:
	Perf.mark("weapon_equip")
	var old: WeaponItem
	if it.is_ranged():
		old = ranged
		ranged = it
		gun.equip(it)
	else:
		old = melee
		melee = it
		axe.apply_def(it.def, it.level)
	if old and drop_old:
		drop_item(old)
	var slot := RANGED if it.is_ranged() else MELEE
	if slot == active_slot:
		_show_slot(slot, false)
	else:
		switch_to(slot)
	slots_changed.emit()
	return old

## Очистить ренж-слот (тело без ренжа).
func clear_ranged() -> void:
	ranged = null
	gun.equip(null)
	if active_slot == RANGED:
		switch_to(MELEE, true)
	slots_changed.emit()

## Стартовое оружие тела (поля BodyDef.start_melee / start_ranged).
## level — уровень стартового оружия (Кузнец: +1, см. run/passives/smith_level.gd)
func apply_body(body: BodyDef, level: int = 1) -> void:
	if body == null:
		return
	if body.start_melee:
		equip(body.start_melee, level, false)
	if body.start_ranged:
		equip(body.start_ranged, level, false)
	else:
		clear_ranged()
	switch_to(MELEE, true)

func current() -> WeaponItem:
	return ranged if active_slot == RANGED else melee

func current_def() -> WeaponDef:
	var c := current()
	return c.def if c else null

func is_ranged_active() -> bool:
	return active_slot == RANGED and ranged != null

func is_switching() -> bool:
	return _switch_left > 0.0

## Множитель скорости бега (активное оружие; ренж при стрельбе — ещё медленнее).
func move_speed_mult() -> float:
	if is_ranged_active():
		# Руна «Рука Брокка»: штраф ренжа ×0.9 → ×0.95 → без штрафа (база ренжа — ×0.8)
		var brokk := Run.rune_value("brokk_hand") if Run.rune_level("brokk_hand") > 0 else 0.0
		var m := gun.move_mult()
		return minf(1.0, m * brokk / 0.8) if brokk > 0.0 else m
	return melee.def.move_speed_mult if melee else 1.0

func dash_recharge_mult() -> float:
	var d := current_def()
	return d.dash_recharge_mult if d else 1.0

func melee_style() -> String:
	return melee.def.style if melee else "blade"

## Свитч на слот. instant — без анимации (смена тела, тесты).
func switch_to(slot: int, instant: bool = false) -> void:
	if slot == RANGED and ranged == null:
		return
	if slot == active_slot and not instant:
		return
	Perf.mark("weapon_switch")
	active_slot = slot
	axe.cancel()
	axe.active = false
	gun.set_active(false)
	if instant or pivot == null or switch_time <= 0.0:
		_switch_left = 0.0
		_show_slot(slot, false)
		_enable_slot(slot)
	else:
		_switch_left = switch_time
		Audio.play("sounds/sfx/weapon_switch.wav")
		if _switch_tween and _switch_tween.is_valid():
			_switch_tween.kill()
		var half := switch_time * 0.5
		var h := _hand()
		if h:
			# Убрать: рука уходит вниз и запрокидывает оружие, во второй половине — достать новое снизу
			var t := player.view_motion.tuning
			h.set_state(&"switch_down")
			h.wrist_target = Vector3.ZERO
			_switch_tween = h.new_tween().set_parallel(true)
			_switch_tween.tween_property(h, "position", h.position + t.switch_down_pos, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_switch_tween.tween_property(h, "rotation_degrees", h.rotation_degrees + t.switch_down_rot, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		else:
			_switch_tween = pivot.create_tween()
			_switch_tween.set_parallel(true)
			_switch_tween.tween_property(pivot, "position", pivot.position + Vector3(0.05, -0.55, 0.2), half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_switch_tween.tween_property(pivot, "rotation_degrees", pivot.rotation_degrees + Vector3(-45, 0, 0), half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_switch_tween.chain().tween_callback(func() -> void: _show_slot(active_slot, true))
	active_changed.emit(slot)
	slots_changed.emit()

func toggle() -> void:
	switch_to(MELEE if active_slot == RANGED else RANGED)

## Модель оружия слота в кулаке и поза: raise — поднять снизу (вторая половина свитча).
func _show_slot(slot: int, raise: bool) -> void:
	var it := ranged if slot == RANGED else melee
	if it == null or arm == null or pivot == null:
		return
	var d := it.def
	arm.set_weapon(d.model, d.view_offset, d.view_rotation, d.view_scale * (ViewmodelMotion.tuning_res().gun_view_scale if it.is_ranged() else 1.0))
	if _switch_tween and _switch_tween.is_valid() and not raise:
		_switch_tween.kill()
	var h := _hand()
	if h:
		var t := player.view_motion.tuning
		h.rest_pos = d.view_rest_pos
		h.rest_rot = d.view_rest_rot
		h.stiffness_mult = 1.0
		if raise:
			h.set_state(&"switch_up")
			h.snap(d.view_rest_pos + t.switch_down_pos, d.view_rest_rot + t.switch_down_rot)
			_switch_tween = h.new_tween().set_parallel(true)
			_switch_tween.tween_property(h, "position", d.view_rest_pos, switch_time * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_switch_tween.tween_property(h, "rotation_degrees", d.view_rest_rot, switch_time * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			h.snap(d.view_rest_pos, d.view_rest_rot)
		return
	if raise:
		pivot.position = d.view_rest_pos + Vector3(0.05, -0.55, 0.2)
		pivot.rotation_degrees = d.view_rest_rot + Vector3(-45, 0, 0)
		var half := switch_time * 0.5
		_switch_tween = pivot.create_tween().set_parallel(true)
		_switch_tween.tween_property(pivot, "position", d.view_rest_pos, half).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_switch_tween.tween_property(pivot, "rotation_degrees", d.view_rest_rot, half).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		pivot.position = d.view_rest_pos
		pivot.rotation_degrees = d.view_rest_rot

## Правая рука вьюмодели (ViewmodelMotion.Hand), null — пока Player не собрал руки.
func _hand() -> ViewmodelMotion.Hand:
	if player == null or player.view_motion == null or pivot == null:
		return null
	return player.view_motion.hand_for(pivot)

func _enable_slot(slot: int) -> void:
	axe.active = slot == MELEE
	gun.set_active(slot == RANGED)

func _on_ran_dry() -> void:
	if auto_switch_on_empty and active_slot == RANGED and ranged and ranged.is_empty():
		Odin.say("ranged_empty")
		switch_to(MELEE)

func _physics_process(delta: float) -> void:
	if _switch_left > 0.0:
		_switch_left -= delta
		if _switch_left <= 0.0:
			_switch_left = 0.0
			_enable_slot(active_slot)
	if player.is_dead:
		_set_prompt("")
		return
	_update_focus()
	_collect_ammo()
	if player.input_enabled and Input.is_action_just_pressed("interact"):
		interact()

func _unhandled_input(event: InputEvent) -> void:
	if not player or player.is_dead or not player.input_enabled:
		return
	if event.is_action_pressed("weapon_switch"):
		toggle()
	elif event.is_action_pressed("weapon_next") or event.is_action_pressed("weapon_prev"):
		# Колесо шлёт несколько событий за один прокрут — пока идёт свитч, не переключаем обратно
		if not is_switching():
			toggle()
	elif event.is_action_pressed("weapon_melee"):
		switch_to(MELEE)
	elif event.is_action_pressed("weapon_ranged"):
		switch_to(RANGED)

# --- Подбор ---

## Ближайший подбираемый предмет (оружие, сундук) в радиусе, с приоритетом того, на что смотрим.
func _update_focus() -> void:
	var best: Node3D = null
	var best_score := INF
	var eye := player.get_aim_origin()
	var fwd := player.get_aim_forward()
	for n in get_tree().get_nodes_in_group("interactable"):
		var it := n as Node3D
		if it == null or not it.is_inside_tree() or (it.has_method("can_interact") and not it.call("can_interact")):
			continue
		var d := it.global_position - player.global_position
		if absf(d.y) > 2.2:
			continue
		var dist := Vector2(d.x, d.z).length()
		if dist > interact_radius:
			continue
		var look := (it.global_position - eye).normalized().dot(fwd)
		var score := dist - look * 1.2
		if score < best_score:
			best_score = score
			best = it
	_focus = best
	_set_prompt(str(best.call("prompt_text", self)) if best else "")

func _set_prompt(t: String) -> void:
	if t != _prompt:
		_prompt = t
		prompt_changed.emit(t)

func focused() -> Node3D:
	return _focus

## E: подобрать / открыть то, что в фокусе.
func interact() -> bool:
	if _focus == null or not is_instance_valid(_focus):
		return false
	Perf.mark("interact")
	_focus.call("interact", self)
	_focus = null
	_update_focus()
	return true

## Бросить экземпляр на пол перед собой.
func drop_item(it: WeaponItem) -> WeaponPickup:
	var fwd := player.get_aim_forward()
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var target := player.global_position + fwd * 1.3
	var from := player.get_aim_origin() + fwd * 0.4 + Vector3(0, -0.3, 0)
	return Loot.spawn_weapon(player.get_parent(), target, it, from)

func _collect_ammo() -> void:
	if ranged == null:
		return
	for n in get_tree().get_nodes_in_group("ammo_pickups"):
		var a := n as Node3D
		if a == null or not a.is_inside_tree():
			continue
		var d := a.global_position - player.global_position
		if absf(d.y) < 2.0 and Vector2(d.x, d.z).length() <= ammo_pickup_radius:
			if give_ammo_box():
				Perf.mark("ammo_pickup")
				a.queue_free()

## Ящик патронов для ренжа в слоте. false — некуда (полный запас или нет ренжа).
func give_ammo_box() -> bool:
	if ranged == null or ranged.reserve >= ranged.reserve_cap():
		return false
	var amount := maxi(ranged.def.mag_size, int(ceil(ranged.reserve_cap() * ammo_box_fraction)))
	ranged.add_ammo(amount)
	Audio.play("sounds/sfx/ammo_pickup.wav")
	ammo_changed.emit(ranged.mag, ranged.reserve)
	slots_changed.emit()
	if gun.active and ranged.mag <= 0:
		gun.start_reload()
	return true

## Нужны ли патроны (для выпадения с врагов).
func wants_ammo() -> bool:
	return ranged != null and ranged.reserve < ranged.reserve_cap()

## Прогрев: вспышка дула и все модели оружия во вьюмодели (свой SubViewport — свои пайплайны).
func warmup_viewmodel(frames: int = 10) -> void:
	if arm == null:
		return
	var keep := arm.weapon
	var nodes: Array[Node3D] = []
	for d in Loot.all_defs():
		var w := WeaponMeshes.build(d.model, 2)
		arm.add_child(w)
		w.position = Vector3(randf_range(-0.2, 0.2), 0, -0.1)
		w.scale = Vector3.ONE * d.view_scale * 0.3
		nodes.append(w)
	var fl := RangedWeapon.make_flash_mesh(2)
	fl.visible = true
	arm.add_child(fl)
	nodes.append(fl)
	for k in frames:
		await get_tree().process_frame
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	if keep and is_instance_valid(keep):
		keep.visible = true
