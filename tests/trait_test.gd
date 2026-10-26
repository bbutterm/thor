extends Node
## Тест трейтов Мьёльнира и базы молота (GDD 10):
##  • база: втыкается в стену, сам возвращается; идеальный хват → следующий бросок ×2; без молота рывок быстрее;
##  • выбор трейтов: в предложении нет двух из одной группы, трейт той же группы заменяет, повтор — уровень 2,
##    на макс. уровне не выпадает; экран выбора требует подтверждения замены;
##  • каждый трейт (ур. 1 и 2): бросок, полёт, попадание/втыкание, возврат — и его особый эффект.
## godot --headless --path . --fixed-fps 60 res://tests/trait_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game
var p: Player
var hand: MjolnirHand
const START := Vector3(-3, 0.1, 2)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "TraitRunner"
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()

func check(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
		print("  [OK] ", what)
	else:
		_fails.append(what)
		print("  [FAIL] ", what)

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func wait(sec: float) -> void:
	await frames(int(ceil(sec * 60.0)))

func _run() -> void:
	print("=== TRAIT TEST ===")
	Run.start_run("berserker")
	Run.room_order.assign([Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(20)
	game = get_tree().current_scene as Game
	p = game.player
	hand = p.mjolnir
	game.room.set_physics_process(false)
	await wait(1.0)
	game.room._spawn_queue.clear()
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	await frames(5)
	check(Run.all_mjolnir_traits.size() >= 13, "трейтов загружено: %d (13 по GDD 10)" % Run.all_mjolnir_traits.size())
	# Закрытые в «Плане тренировок» не выпадают; дальше тест открывает все трейты
	var locked_ok := true
	for i in 40:
		for t in Run.random_mjolnir_trait_choices(3):
			if not Save.is_in_pool("trait", str(t.id)):
				locked_ok = false
	check(locked_ok, "закрытые трейты («План тренировок») в выбор не попадают")
	for u in Save.all_unlocks:
		if u.kind == "trait":
			Save.data.unlocks[u.id] = 0

	_test_choices()
	await _test_pick_ui()
	await _test_base()
	for t in Run.all_mjolnir_traits:
		for lv in [1, 2]:
			await _test_trait(t, lv)
	_finish()

# --- Выбор ---

func _set_traits(list: Array) -> void:
	Run.mjolnir_traits.clear()
	Run.mjolnir_trait_levels.clear()
	Run.mjolnir_traits_changed.emit(Run.mjolnir_traits)
	for t in list:
		Run.add_mjolnir_trait(t)

func _find(id: StringName) -> MjolnirTrait:
	for t in Run.all_mjolnir_traits:
		if t.id == id:
			return t
	return null

func _test_choices() -> void:
	print("-- Выбор трейтов")
	var bad_groups := 0
	var bad_max := 0
	var short := 0
	var all := Run.all_mjolnir_traits
	for i in 300:
		# Случайный набор взятых трейтов (по правилам добавления)
		var owned: Array = []
		for t in all:
			if randf() < 0.25:
				owned.append(t)
				if randf() < 0.3:
					owned.append(t)
		_set_traits(owned)
		var ch := Run.random_mjolnir_trait_choices(3)
		var groups := {}
		for t in ch:
			if t.group != "":
				if groups.has(t.group):
					bad_groups += 1
				groups[t.group] = true
			if Run.mjolnir_trait_level(t.id) >= t.max_level:
				bad_max += 1
		if ch.size() < 3:
			short += 1
		# Не больше одного активного трейта на группу
		var active := {}
		for t in Run.mjolnir_traits:
			if t.group != "":
				if active.has(t.group):
					bad_groups += 1
				active[t.group] = true
	check(bad_groups == 0, "в предложении и в активных нет двух трейтов одной группы")
	check(bad_max == 0, "трейт на макс. уровне не выпадает")
	check(short == 0, "всегда есть 3 варианта")
	var pull := _find(&"pull_to_hammer")
	var magnet := _find(&"magnet")
	var ric := _find(&"ricochet")
	var rod := _find(&"lightning_rod")
	if pull and magnet and ric and rod:
		_set_traits([pull, magnet])
		check(Run.mjolnir_trait_level(&"pull_to_hammer") == 0 and Run.mjolnir_trait_level(&"magnet") == 1, "Магнит заменил Притяжение (одна группа)")
		_set_traits([ric, rod])
		check(Run.mjolnir_traits.size() == 1 and Run.mjolnir_traits[0] == rod, "Громоотвод заменил Рикошет (одна группа)")
		_set_traits([rod, rod])
		check(Run.mjolnir_trait_level(&"lightning_rod") == 2, "повтор — уровень 2")
		var offered := false
		for i in 50:
			for t in Run.random_mjolnir_trait_choices(3):
				if t == rod:
					offered = true
		check(not offered, "трейт уровня 2 больше не предлагается")
	_set_traits([])

func _test_pick_ui() -> void:
	print("-- Экран выбора трейта")
	var pull := _find(&"pull_to_hammer")
	var magnet := _find(&"magnet")
	var chain := _find(&"chain_lightning")
	_set_traits([pull])
	var got: Array = []
	var cb := func(t: MjolnirTrait) -> void: got.append(t)
	# Игровой обработчик (руна после трейта) на время теста отключаем
	game.trait_pick.picked.disconnect(game._on_trait_picked)
	game.trait_pick.picked.connect(cb)
	var choices: Array[MjolnirTrait] = [magnet, chain]
	game.trait_pick.open(choices)
	game.trait_pick._open_time = -10.0
	check(game.trait_pick.visible and get_tree().paused, "экран открыт, игра на паузе")
	game.trait_pick.choose(0)
	check(game.trait_pick.visible and got.is_empty(), "замена требует подтверждения")
	game.trait_pick.choose(0)
	check(not game.trait_pick.visible and got.size() == 1 and got[0] == magnet, "второе нажатие — выбрано")
	game.trait_pick.picked.disconnect(cb)
	game.trait_pick.picked.connect(game._on_trait_picked)
	check(not get_tree().paused, "пауза снята")
	await frames(5)
	_set_traits([])

# --- База молота ---

func _reset_player(pitch: float = 0.0) -> void:
	hand.hold_override = false
	if not hand.in_hand:
		hand.force_return_instant()
	p.set_physics_process(true)
	p.global_position = START
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2(pitch, 0.0)
	p.rotation.y = 0.0
	p.head.rotation.x = pitch
	p.health = p.max_health
	hand.perfect_ready = false

func _clear_dummies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	for n in game.get_children():
		if n.get_script() and n.get_script().resource_path.ends_with("fire_zone.gd"):
			n.queue_free()

## Манекен: без своего ИИ (если physics = false), много HP. Позиция — относительно START (x вбок, z — вперёд по -Z).
func _dummy(side: float, fwd: float, physics: bool = false) -> Enemy:
	var e := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	e.max_health = 500
	e.move_speed = 0.0
	e.attack_range = 0.0
	game.add_child(e)
	e.global_position = Vector3(START.x + side, 0.0, START.z - fwd)
	e.set_physics_process(physics)
	e.health = 500
	return e

func _hurt(e: Enemy) -> bool:
	return not is_instance_valid(e) or e.health < e.max_health

## Ждать, пока молот в руке (или timeout). Возвращает true, если вернулся.
func _wait_in_hand(timeout: float) -> bool:
	for i in int(timeout * 60):
		if hand.in_hand:
			return true
		await get_tree().physics_frame
	return hand.in_hand

## Ждать состояния снаряда. Возвращает true, если дождались.
func _wait_state(s: MjolnirProjectile.State, timeout: float) -> bool:
	for i in int(timeout * 60):
		if hand.projectile and is_instance_valid(hand.projectile) and hand.projectile.state == s:
			return true
		if hand.in_hand:
			return false
		await get_tree().physics_frame
	return false

func _test_base() -> void:
	print("-- База молота (без трейтов)")
	_set_traits([])
	_clear_dummies()
	await frames(3)
	_reset_player()
	await frames(5)
	var d := _dummy(0, 6)
	hand.throw_hammer()
	check(not hand.in_hand, "бросок")
	var stuck := await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	check(stuck, "молот воткнулся в стену")
	check(_hurt(d), "попал по манекену на пути")
	var back := await _wait_in_hand(3.0)
	check(back, "воткнутый молот сам вернулся (stuck_auto_return %.1f с)" % hand.stuck_auto_return)
	# Рывок перезаряжается быстрее, пока молота нет (без манекена: hit-stop от крита съедал время)
	_clear_dummies()
	await frames(2)
	p.dash_charges = p.dash_charges_max - 1
	p.set("_dash_recharge_timer", 0.0)
	hand.throw_hammer()
	await wait(0.5)
	var t: float = p.get("_dash_recharge_timer")
	check(t > 0.55, "без молота рывок перезаряжается быстрее (таймер %.2f за 0.5 с)" % t)
	await _wait_in_hand(4.0)
	# Идеальный хват: ПКМ сразу после поимки — бросок ×2
	hand.throw_hammer()
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	hand.request_throw_or_recall()
	await _wait_in_hand(3.0)
	hand.request_throw_or_recall()
	check(hand.projectile != null and is_equal_approx(hand.projectile.damage_mult, hand.perfect_damage_mult), "идеальный хват (после поимки): бросок ×%.0f" % hand.perfect_damage_mult)
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	hand.request_throw_or_recall()
	await _wait_in_hand(3.0)
	# Обычная (не идеальная) поимка — бросок без усиления
	await wait(0.4)
	hand.request_throw_or_recall()
	check(hand.projectile != null and is_equal_approx(hand.projectile.damage_mult, 1.0), "без идеального хвата — обычный урон")
	await _wait_in_hand(4.0)
	_clear_dummies()

# --- Трейты ---

func _test_trait(t: MjolnirTrait, lv: int) -> void:
	print("-- Трейт %s (%s), ур. %d" % [t.title, t.id, lv])
	_set_traits([t] if lv == 1 else [t, t])
	check(hand.traits.size() == 1 and hand.traits[0].level == lv, "обработчик у молота, уровень %d" % lv)
	_clear_dummies()
	await frames(3)
	match t.id:
		&"earthquake":
			await _scenario_earthquake()
		&"sky_thunder":
			await _scenario_sky_thunder()
		&"storm":
			await _scenario_storm()
		_:
			await _scenario_generic(t)
	check(hand.in_hand, "молот в руке после сценария")
	check(p.is_physics_processing(), "игрок снова управляется")
	_clear_dummies()
	await frames(3)

func _scenario_generic(t: MjolnirTrait) -> void:
	_reset_player()
	await frames(5)
	var line := [_dummy(0, 4), _dummy(0, 7)]
	# Сбоку от линии полёта — их задевают только трейты (молния, рикошет)
	var side := [_dummy(3.0, 7.5), _dummy(-3.0, 10.0)]
	# У стены (точка втыкания ~ z = -15.6) — для Магнита и Громоотвода
	var wall_l := _dummy(2.2, 16.0, t.id == &"magnet")
	var wall_r := _dummy(-2.2, 16.0, t.id == &"magnet")
	var wall_d0 := 0.0
	var holds := t.handler.get("stuck_hold") != null
	var start_pos := p.global_position
	var fires := 0
	var saw_stuck := false
	var clones_seen := 0
	hand.throw_hammer()
	check(not hand.in_hand, "бросок")
	for i in 150:
		await get_tree().physics_frame
		var cl := 0
		for c in p.get_parent().get_children():
			if c is MjolnirProjectile and (c as MjolnirProjectile).is_clone:
				cl += 1
		clones_seen = maxi(clones_seen, cl)
		if hand.projectile and is_instance_valid(hand.projectile) and hand.projectile.is_stuck():
			saw_stuck = true
			wall_d0 = _flat_dist(wall_l, hand.projectile.global_position)
			break
		if hand.in_hand:
			break
		fires = maxi(fires, _fire_count())
	check(line.any(_hurt), "попал по врагу на линии")
	match t.id:
		&"boomerang":
			check(not saw_stuck, "Бумеранг не втыкается")
			check(await _wait_in_hand(3.0), "Бумеранг вернулся сам, без ПКМ")
			return
		&"ricochet":
			check(side.any(_hurt), "рикошет задел врага в стороне")
		&"chain_lightning":
			check(side.any(_hurt), "молния перескочила на врага в стороне")
		&"fire_trail":
			check(fires > 0, "огненный след: пятен %d" % fires)
		&"ice_trail":
			var ih := hand.traits[0]
			check(int(ih.call("active_zones")) > 0, "ледяной след: пятен льда %d" % int(ih.call("active_zones")))
		&"heaviness":
			var pinned := line.filter(func(e: Enemy) -> bool: return is_instance_valid(e) and e.state == Enemy.State.STUNNED)
			check(not pinned.is_empty(), "Тяжесть прибила врага (стан)")
			if hand.traits[0].level >= 2:
				check(side.any(func(e: Enemy) -> bool: return is_instance_valid(e) and e.state == Enemy.State.STUNNED) or pinned.size() >= 2, "Тяжесть ур. 2: стан по кругу")
		&"two_hammers":
			check(clones_seen >= hand.traits[0].level, "Два молота: копий в полёте %d" % clones_seen)
	if t.id != &"ricochet":
		check(saw_stuck, "молот воткнулся")
	if saw_stuck:
		await wait(1.2 if holds else 0.3)
		match t.id:
			&"magnet":
				var d1 := _flat_dist(wall_l, hand.projectile.global_position)
				check(d1 < wall_d0 - 0.5, "Магнит стянул врага (%.1f → %.1f м)" % [wall_d0, d1])
			&"lightning_rod":
				check(_hurt(wall_l) or _hurt(wall_r), "Громоотвод ударил молнией врага рядом")
		check(hand.projectile != null and hand.projectile.is_stuck(), "воткнутый молот ждёт ПКМ")
		var hp_before := wall_l.health if is_instance_valid(wall_l) else 0.0
		hand.request_throw_or_recall()
		if t.id == &"pull_to_hammer":
			check(not p.is_physics_processing(), "Притяжение: игрок летит к молоту")
		await frames(2)
		if t.id == &"magnet":
			check(not is_instance_valid(wall_l) or wall_l.health < hp_before, "Магнит раскидал врагов при возврате")
	check(await _wait_in_hand(4.0), "молот вернулся")
	if t.id == &"pull_to_hammer":
		var moved := start_pos.distance_to(p.global_position)
		check(moved > 10.0, "Притяжение перенесло игрока к стене (%.1f м)" % moved)
	if t.id == &"fire_trail":
		var h := hand.traits[0]
		check(int(h.call("active_zones")) <= int(h.get("max_zones")), "огней не больше max_zones")

func _flat_dist(e: Node3D, pos: Vector3) -> float:
	if not is_instance_valid(e):
		return 0.0
	return Vector2(e.global_position.x - pos.x, e.global_position.z - pos.z).length()

func _fire_count() -> int:
	var n := 0
	for c in game.get_children():
		if c.get_script() and c.get_script().resource_path.ends_with("fire_zone.gd") and not c.is_queued_for_deletion():
			n += 1
	return n

func _scenario_storm() -> void:
	_reset_player()
	await frames(5)
	var side := _dummy(2.0, 6.5)
	hand.hold_override = true
	hand.throw_hammer()
	var hovered := await _wait_state(MjolnirProjectile.State.HOVER, 1.0)
	check(hovered, "Буря: молот завис")
	await wait(1.0)
	check(hand.projectile != null and hand.projectile.state == MjolnirProjectile.State.HOVER, "висит, пока ПКМ зажата")
	check(_hurt(side), "Буря: урон по кругу")
	hand.hold_override = false
	check(await _wait_in_hand(3.0), "отпустил ПКМ — вернулся")

func _scenario_earthquake() -> void:
	# Молот — в пол в ~4 м перед игроком; враг в 3 м за молотом (вне волны игрока)
	var pitch := -atan2(1.6, 4.0)
	_reset_player(pitch)
	await frames(5)
	var far := _dummy(0, 7.6)
	hand.throw_hammer()
	var stuck := await _wait_state(MjolnirProjectile.State.STUCK, 1.0)
	check(stuck, "молот воткнулся в пол")
	if stuck:
		check(hand.projectile.stuck_normal.y > 0.6, "воткнулся именно в пол")
		Input.action_press("jump")
		await frames(2)
		Input.action_release("jump")
		await wait(0.35)
		Input.action_press("slam")
		await frames(2)
		Input.action_release("slam")
		for i in 90:
			await get_tree().physics_frame
			if p.is_on_floor():
				break
		await wait(0.5)
		check(_hurt(far), "Землетрясение: вторая волна у молота задела врага")
		hand.request_throw_or_recall()
	check(await _wait_in_hand(4.0), "молот вернулся")

func _scenario_sky_thunder() -> void:
	# Целимся в пол у манекена; идеальный хват вызывает молнию туда
	var pitch := -atan2(1.6, 8.0)
	_reset_player(pitch)
	await frames(5)
	var target := _dummy(0, 8.5)
	hand.throw_hammer()
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	hand.request_throw_or_recall()
	await _wait_in_hand(3.0)
	var hp0 := target.health
	hand.request_throw_or_recall()
	check(target.health < hp0, "Гром небесный: молния в точку прицела")
	check(hand.projectile != null and hand.projectile.damage_mult > 1.0, "бросок после идеального хвата усилен")
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	hand.request_throw_or_recall()
	check(await _wait_in_hand(4.0), "молот вернулся")

func _finish() -> void:
	print("=== ИТОГ TRAITS: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
