extends Node
## Тест оружия (этап 1): слоты, свитч, подбор, штраф скорости с ренжем, патроны, перезарядка,
## ренж не сбивает замах, мили сбивает, сильный удар, элита и сундук, стартовое оружие тел, награды за добивание.
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/weapon_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "WeaponRunner"
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

func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().physics_frame

func _action(name: String) -> void:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().physics_frame
	var up := InputEventAction.new()
	up.action = name
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().physics_frame

func _run() -> void:
	print("=== WEAPON TEST ===")
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.3)
	game = get_tree().current_scene as Game
	if game == null:
		check(false, "сцена игры загрузилась")
		_finish()
		return
	var p := game.player
	var h := p.weapons
	await wait(1.6)
	# Враги не мешают: останавливаем очередь и уводим уже появившихся.
	# Иначе при поштучном входе оставшийся корм появляется во время теста.
	game.room.set_physics_process(false)
	for e in game.room.alive_enemies():
		e.global_position = game.room.global_position + Vector3(14, 0.1, -14)
		e.set_physics_process(false)
	p.global_position = game.room.global_position + Vector3(3, 0.1, 10)
	p.rotation_target = Vector2(0, 0)
	p.velocity = Vector3.ZERO
	await wait(0.4)

	print("-- Стартовые слоты")
	check(h != null, "у игрока есть WeaponHolder")
	check(h.melee != null and h.melee.def.id == "axe", "Берсерк: топор в слоте мили")
	check(h.ranged == null, "Берсерк: ренж-слот пуст")
	check(p.current_weapon() != null and p.current_weapon().id == "axe", "current_weapon() = топор")
	check(p.current_melee_style() == "blade", "current_melee_style() = blade")
	var speed_melee := await _measure_speed(p)
	check(absf(speed_melee - p.move_speed * h.melee.def.move_speed_mult) < 0.5, "скорость с мили ×%.2f (%.2f м/с)" % [h.melee.def.move_speed_mult, speed_melee])
	h.switch_to(WeaponHolder.RANGED)
	check(h.active_slot == WeaponHolder.MELEE, "без ренжа свитч на ренж невозможен")

	print("-- Подбор ренжа")
	var pistol := Loot.get_def("pistol")
	var pk := Loot.spawn_weapon(game, p.global_position + _fwd(p) * 1.2, WeaponItem.create(pistol))
	await wait(0.2)
	check(h.focused() == pk, "пистолет в фокусе, подсказка: «%s»" % h._prompt)
	await _action("interact")
	await wait(0.1)
	check(h.ranged != null and h.ranged.def.id == "pistol", "пистолет встал в слот ренжа")
	check(h.melee.def.id == "axe", "топор остался в слоте мили")
	check(not is_instance_valid(pk), "подобранное исчезло с пола")
	check(h.active_slot == WeaponHolder.RANGED, "после подбора в руке пистолет")
	check(h.is_switching(), "идёт анимация свитча")
	check(not h.gun.active, "во время свитча стрелять нельзя")
	await wait(h.switch_time + 0.05)
	check(h.gun.active and not h.axe.active, "после свитча активен ренж, мили убрано")
	var speed_ranged := await _measure_speed(p)
	check(speed_ranged < speed_melee * 0.85, "с ренжем заметно медленнее (%.2f против %.2f м/с)" % [speed_ranged, speed_melee])
	check(absf(speed_ranged - p.move_speed * pistol.move_speed_mult) < 0.5, "скорость с ренжем ×%.2f" % pistol.move_speed_mult)
	check(p.weapon_dash_recharge_mult() > 1.0, "рывок с ренжем перезаряжается дольше (×%.2f)" % p.weapon_dash_recharge_mult())

	print("-- Стрельба и патроны")
	var mag0 := h.ranged.mag
	var res0 := h.ranged.reserve
	check(h.gun.try_fire(), "выстрел")
	check(h.ranged.mag == mag0 - 1, "патрон списан (%d → %d)" % [mag0, h.ranged.mag])
	check(get_tree().get_nodes_in_group("casings").size() > 0, "вылетела гильза")
	check(p.weapon_move_mult() < pistol.move_speed_mult, "при стрельбе ещё медленнее (×%.2f)" % p.weapon_move_mult())
	var speed_firing := await _measure_speed(p, true)
	check(speed_firing < speed_ranged - 0.3, "скорость во время стрельбы %.2f < %.2f" % [speed_firing, speed_ranged])
	# Опустошаем магазин — автоперезарядка
	for i in 40:
		if h.ranged.mag <= 0:
			break
		h.gun.try_fire()
		await wait(pistol.fire_interval + 0.02)
	check(h.ranged.mag == 0, "магазин пуст")
	await wait(0.25)
	check(h.gun.reloading, "автоперезарядка началась")
	await wait(pistol.reload_time + 0.1)
	check(h.ranged.mag == pistol.mag_size and h.ranged.reserve == res0 - pistol.mag_size, "перезарядка: %d / %d" % [h.ranged.mag, h.ranged.reserve])
	h.gun.try_fire()
	await wait(0.2)
	h.gun.try_fire()
	await wait(0.2)
	var res1 := h.ranged.reserve
	await _action("reload")
	check(h.gun.reloading, "R — перезарядка")
	await wait(pistol.reload_time + 0.1)
	check(h.ranged.mag == pistol.mag_size and h.ranged.reserve == res1 - 2, "ручная перезарядка дозарядила 2 патрона")

	print("-- Ренж не сбивает замах, мили — сбивает")
	var dummy := _make_dummy(p, 4.0)
	await wait(0.1)
	dummy._set_state(Enemy.State.WINDUP)
	var hp0 := dummy.health
	await wait(0.25)
	h.gun.try_fire()
	await wait(0.05)
	check(dummy.health < hp0, "пуля попала (%.1f → %.1f)" % [hp0, dummy.health])
	check(dummy.state == Enemy.State.WINDUP, "замах после попадания из ренжа не сбит")
	check(dummy.knockback_velocity.length() < 0.01, "ренж не отбрасывает")
	h.switch_to(WeaponHolder.MELEE)
	await wait(h.switch_time + 0.05)
	check(h.axe.active and not h.gun.active, "свитч обратно на мили")
	dummy.global_position = p.global_position + _fwd(p) * 1.6
	dummy._set_state(Enemy.State.WINDUP)
	var hp1 := dummy.health
	h.axe.request_attack()
	await wait(0.3)
	check(dummy.health < hp1, "удар мили попал")
	check(dummy.state != Enemy.State.WINDUP, "мили сбил замах (состояние %d)" % dummy.state)

	print("-- Приём топора (зажать ЛКМ)")
	await wait(0.5)
	dummy.global_position = p.global_position + _fwd(p) * 1.6
	dummy.velocity = Vector3.ZERO
	dummy.knockback_velocity = Vector3.ZERO
	dummy._set_state(Enemy.State.CHASE)
	var toward_player := p.global_position - dummy.global_position
	dummy.rotation.y = atan2(toward_player.x, toward_player.z)
	p.health = p.max_health  # кровавая ярость не должна менять базовый урон приёма
	p.style.reset()
	var hp2 := dummy.health
	var crit0 := p.crit_chance_base
	p.crit_chance_base = 0.0  # случайный крит (5 %) удваивал урон — проверка нестабильна
	h.axe.request_heavy()
	check(h.axe.heavy and h.axe.is_busy(), "начата вертушка топора")
	await wait(0.75)
	var heavy_dmg := hp2 - dummy.health
	p.crit_chance_base = crit0
	check(absf(heavy_dmg - h.melee.def.damage * h.axe.damage_mult * h.melee.def.skill_damage_mult) < 0.6, "вертушка ×%.1f (%.1f урона)" % [h.melee.def.skill_damage_mult, heavy_dmg])

	print("-- Подбор мили: старое падает на пол")
	var sword_pk := Loot.spawn_weapon(game, p.global_position + _fwd(p) * 1.0, WeaponItem.create(Loot.get_def("sword"), 2))
	await wait(0.2)
	h.interact()
	await wait(0.1)
	check(h.melee.def.id == "sword" and h.melee.level == 2, "меч ур. 2 в слоте мили")
	check(h.ranged.def.id == "pistol", "пистолет остался в ренж-слоте")
	check(not is_instance_valid(sword_pk), "меч подобран")
	var dropped := _find_pickup("axe")
	check(dropped != null, "старый топор лежит на полу")
	check(absf(h.axe._stage_damage() - h.melee.def.damage * h.axe.damage_mult * 1.2) < 0.5, "урон меча ур. 2: +20%% (%.1f)" % h.axe._stage_damage())
	await wait(0.6)
	if dropped:
		h._focus = dropped
		dropped.interact(h)
	await wait(0.1)
	check(h.melee.def.id == "axe", "топор подобран обратно")
	check(_find_pickup("sword") != null, "меч упал на пол")

	print("-- Свитч с клавиатуры")
	await wait(0.3)
	await _action("weapon_switch")
	check(h.active_slot == WeaponHolder.RANGED, "Q — на ренж")
	await wait(h.switch_time + 0.05)
	await _action("weapon_melee")
	check(h.active_slot == WeaponHolder.MELEE, "1 — на мили")
	await wait(h.switch_time + 0.05)
	await _action("weapon_ranged")
	check(h.active_slot == WeaponHolder.RANGED, "2 — на ренж")
	await wait(h.switch_time + 0.05)

	print("-- Патроны с пола и пустой ренж")
	h.ranged.reserve = 4
	Loot.spawn_ammo(game, p.global_position + Vector3(0.3, 0, 0))
	await wait(0.15)
	check(h.ranged.reserve > 4, "ящик патронов пополнил запас (4 → %d)" % h.ranged.reserve)
	h.ranged.mag = 0
	h.ranged.reserve = 0
	h.gun.cancel_reload()
	h.gun.try_fire()
	await wait(0.05)
	check(h.active_slot == WeaponHolder.MELEE, "пустой ренж без запаса — автосвитч на мили")
	h.ranged.reserve = 20
	await wait(h.switch_time + 0.05)

	print("-- Элита и сундук")
	var elite := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	Loot.make_elite(elite)
	game.add_child(elite)
	elite.global_position = p.global_position + _fwd(p) * 5.0 + Vector3(2, 0, 0)
	elite.set_physics_process(false)
	check(elite.max_health >= 60.0 * 2.5 - 0.1 and Loot.is_elite(elite), "элита: ×2.5 HP (%.0f)" % elite.max_health)
	check(elite.get_node_or_null("EliteMark") != null, "у элиты видимая метка")
	var before := get_tree().get_nodes_in_group("pickups").size()
	var silver_chance := Loot.elite_silver_chance
	Loot.elite_silver_chance = 0.0  # элита роняет оружие или серебро — здесь проверяем оружие
	elite.take_hit(9999, Vector3.ZERO, "melee")
	await wait(0.2)
	Loot.elite_silver_chance = silver_chance
	check(get_tree().get_nodes_in_group("pickups").size() == before + 1, "элита уронила оружие")
	for n in get_tree().get_nodes_in_group("pickups"):
		n.queue_free()
	await wait(0.05)
	var chest := Loot.spawn_chest(game, p.global_position + _fwd(p) * 2.0)
	await wait(0.1)
	check(h.focused() == chest, "сундук в фокусе: «%s»" % h._prompt)
	h.interact()
	await wait(0.6)
	var choice: Array[WeaponPickup] = []
	for n in get_tree().get_nodes_in_group("pickups"):
		var wp := n as WeaponPickup
		if wp and wp.choice_group != "":
			choice.append(wp)
	check(choice.size() == 2, "из сундука выпало 2 оружия на выбор (%d)" % choice.size())
	if choice.size() == 2:
		check(choice[0].item.is_ranged() != choice[1].item.is_ranged(), "выбор: мили и ренж")
		choice[0].interact(h)
		await wait(0.1)
		check(not is_instance_valid(choice[1]), "второе оружие из выбора исчезло")

	print("-- Награды за добивание")
	var d2 := _make_dummy(p, 3.0)
	d2.health = 1.0
	d2.player = p
	p.health = 50.0
	Run._recent_kill_times.clear()
	var g0 := Run.glory
	d2.take_hit(10, Vector3.ZERO, "melee")
	await wait(0.05)
	var melee_glory := Run.glory - g0
	var hm := float(p.modify_stat(&"heal_mult", 1.0))  # тело: Берсерк лечится вполовину (блок Л)
	check(absf(p.health - (50.0 + (p.heal_per_kill + p.melee_kill_heal) * hm)) < 0.01, "добивание мили лечит (%.0f+%.0f)×%.1f HP" % [p.heal_per_kill, p.melee_kill_heal, hm])
	await wait(1.0)
	var d3 := _make_dummy(p, 3.0)
	d3.health = 1.0
	d3.player = p
	p.health = 50.0
	Run._recent_kill_times.clear()
	g0 = Run.glory
	d3.take_hit(10, Vector3.ZERO, "ranged")
	await wait(0.05)
	var ranged_glory := Run.glory - g0
	check(absf(p.health - (50.0 + p.heal_per_kill * hm)) < 0.01, "добивание ренжем лечит только %.0f×%.1f HP" % [p.heal_per_kill, hm])
	check(melee_glory > ranged_glory * 2, "Слава: мили %d > ренж %d" % [melee_glory, ranged_glory])

	print("-- Стартовое оружие тел")
	for b in Run.all_bodies:
		check(b.start_melee != null, "%s: есть стартовое мили (%s)" % [b.id, b.start_melee.id if b.start_melee else "-"])
	var hunter: BodyDef = null
	for b in Run.all_bodies:
		if b.id == "hunter":
			hunter = b
	if hunter:
		h.apply_body(hunter)
		await wait(0.1)
		check(h.melee.def.id == "sword" and h.ranged and h.ranged.def.id == "crossbow", "Охотник: меч + арбалет")
		check(h.active_slot == WeaponHolder.MELEE, "после смены тела в руке мили")
		h.switch_to(WeaponHolder.RANGED, true)
		var bolt_mag := h.ranged.mag
		check(h.gun.try_fire() and h.ranged.mag == bolt_mag - 1, "арбалет стреляет")
	print("-- Все описания оружия")
	var n_melee := 0
	var n_ranged := 0
	for d in Loot.all_defs():
		var it := WeaponItem.create(d)
		check(d.id != "" and d.model != "", "%s: описание корректно" % d.id)
		if d.is_ranged():
			n_ranged += 1
			check(it.mag == d.mag_size and d.move_speed_mult >= 0.75 and d.move_speed_mult <= 0.85, "%s: магазин полный, бег ×%.2f" % [d.id, d.move_speed_mult])
		else:
			n_melee += 1
			check(d.move_speed_mult >= 1.0, "%s: мили не замедляет (×%.2f)" % [d.id, d.move_speed_mult])
		h.equip(d, 1, false)
		await wait(0.05)
	check(n_melee >= 5 and n_ranged >= 4, "оружия: %d мили, %d ренж" % [n_melee, n_ranged])

	print("-- Гвоздомёт и ракетница")
	# Подобранное/выброшенное оружие на полу перекрывает выстрелы — убрать
	for n in get_tree().get_nodes_in_group("pickups") + get_tree().get_nodes_in_group("enemies"):
		n.queue_free()
	await wait(0.1)
	p.health = p.max_health
	h.equip(load("res://weapons/defs/nailgun.tres") as WeaponDef, 1, false)
	h.switch_to(WeaponHolder.RANGED, true)
	await wait(h.switch_time + 0.1)
	var fod := (load("res://enemies/fodder.tscn") as PackedScene).instantiate() as Enemy
	fod.max_health = 500
	game.add_child(fod)
	fod.global_position = p.global_position + _fwd(p) * 4.0
	fod.health = 500
	fod.set_physics_process(false)
	await wait(0.1)
	h.gun._cooldown = 0.0
	h.gun.try_fire()
	await wait(0.05)
	check(fod.health < 500 and fod.state == Enemy.State.STUNNED, "гвоздомёт прибил корм (стан)")
	fod.queue_free()
	h.equip(load("res://weapons/defs/rocket_launcher.tres") as WeaponDef, 1, false)
	h.switch_to(WeaponHolder.RANGED, true)
	await wait(h.switch_time + 0.1)
	var tgt := _make_dummy(p, 7.0)
	tgt.global_position.y = p.global_position.y
	var side := _make_dummy(p, 7.0)
	side.global_position = tgt.global_position + p.global_transform.basis.x * 2.0
	await wait(0.1)
	var hp_p := p.health
	h.gun._cooldown = 0.0
	check(h.gun.try_fire(), "ракетница стреляет")
	await wait(0.6)
	check(tgt.health < 500 and side.health < 500, "взрыв ракеты задел обоих врагов (по площади)")
	check(is_equal_approx(p.health, hp_p), "своя ракета не ранит Тора")
	tgt.queue_free()
	side.queue_free()
	# Рокет-джамп: выстрел под ноги
	h.ranged.mag = 1
	h.gun.reloading = false
	p.rotation_target = Vector2(deg_to_rad(-89.0), p.rotation_target.y)
	await wait(0.3)
	h.gun._cooldown = 0.0
	h.gun.try_fire()
	var vy := 0.0
	for i in 40:
		await get_tree().physics_frame
		vy = maxf(vy, p.velocity.y)
	check(vy > 8.0 and is_equal_approx(p.health, hp_p), "рокет-джамп: подбросило (vy=%.1f), урона нет" % vy)
	p.rotation_target = Vector2(0.0, p.rotation_target.y)
	_finish()

func _fwd(p: Player) -> Vector3:
	var f := p.get_aim_forward()
	f.y = 0
	return f.normalized()

func _find_pickup(id: String) -> WeaponPickup:
	for n in get_tree().get_nodes_in_group("pickups"):
		var wp := n as WeaponPickup
		if wp and wp.item and wp.item.def.id == id:
			return wp
	return null

## Скорость бега вбок (не уходим от точки теста), установившаяся за ~0.8 с.
func _measure_speed(p: Player, firing: bool = false) -> float:
	var start := p.global_position
	Input.action_press("move_right")
	var acc := 0.0
	var n := 0
	for i in 60:
		if firing and p.weapons.is_ranged_active():
			p.weapons.gun._fire_slow_left = p.weapons.fire_slow_time
		await get_tree().physics_frame
		if i > 30:
			acc += p.horizontal_speed()
			n += 1
	Input.action_release("move_right")
	await wait(0.4)
	p.global_position = start
	p.velocity = Vector3.ZERO
	await wait(0.1)
	return acc / maxf(1, n)

func _make_dummy(p: Player, dist: float) -> Enemy:
	var e := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	e.max_health = 500
	game.add_child(e)
	e.global_position = p.global_position + _fwd(p) * dist
	e.set_physics_process(false)
	e.health = 500
	return e

func _finish() -> void:
	print("=== ИТОГ: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
