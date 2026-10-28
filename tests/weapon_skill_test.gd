extends Node
## Приёмы проходят через настоящий ввод, Player, Enemy и физические столкновения.
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/weapon_skill_test.tscn

const ENEMY_SCENE := preload("res://enemies/fodder.tscn")
const CRATE_SCENE := preload("res://props/crate.tscn")
const PROJECTILE := preload("res://enemies/enemy_projectile.gd")
const ORIGIN := Vector3(100.0, 0.1, 0.0)

var game: Game
var p: Player
var targets: Array[Enemy] = []
var props: Array[Destructible] = []
var obstacles: Array[StaticBody3D] = []
var started: Dictionary = {}
var landed: Dictionary = {}
var passes := 0
var fails: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok:
		passes += 1
		print("  [OK] ", message)
	else:
		fails.append(message)
		print("  [FAIL] ", message)

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func input_action(action: String, down: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = down
	Input.parse_input_event(event)

func tap(action: String) -> void:
	input_action(action, true)
	await frames(2)
	input_action(action, false)
	await frames(1)

func count(events: Dictionary, id: String) -> int:
	return int(events.get(id, 0))

func hold_until(id: String) -> bool:
	var before := count(started, id)
	input_action("attack", false)
	await frames(2)
	input_action("attack", true)
	for i in 360:
		await get_tree().physics_frame
		if count(started, id) > before:
			break
	input_action("attack", false)
	return count(started, id) > before

func wait_weapon() -> bool:
	for i in 480:
		await get_tree().physics_frame
		if not p.axe.is_busy() and not p.weapon_skill_lunge_active():
			return true
	return false

func wait_landing(id: String, before: int) -> bool:
	for i in 360:
		await get_tree().physics_frame
		if count(landed, id) > before:
			return true
	return false

func make_box(center: Vector3, size: Vector3, temporary: bool = true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	game.add_child(body)
	body.global_position = center
	if temporary:
		obstacles.append(body)
	return body

func enemy_at(pos: Vector3) -> Enemy:
	var e := ENEMY_SCENE.instantiate() as Enemy
	game.add_child(e)
	e.global_position = pos
	e.max_health = 1000.0
	e.health = 1000.0
	e.player = p
	e.set_physics_process(false)
	e._set_state(Enemy.State.CHASE)
	var toward := p.global_position - e.global_position
	e.rotation.y = atan2(toward.x, toward.z)
	targets.append(e)
	return e

func prop_at(pos: Vector3) -> Destructible:
	var prop := CRATE_SCENE.instantiate() as Destructible
	# Держим ящик на месте и сохраняем его для измерения урона за один оборот.
	prop.freeze = true
	prop.max_health = 1000.0
	prop.loot = "none"
	game.add_child(prop)
	prop.global_position = pos
	props.append(prop)
	return prop

func reset_player(weapon: String, level: int = 1, origin: Vector3 = ORIGIN) -> void:
	for action in ["attack", "jump", "dash", "slam", "move_left", "move_right", "move_forward", "move_back"]:
		input_action(action, false)
	for e in targets:
		if is_instance_valid(e):
			e.queue_free()
	targets.clear()
	for prop in props:
		if is_instance_valid(prop):
			prop.queue_free()
	props.clear()
	for body in obstacles:
		if is_instance_valid(body):
			body.queue_free()
	obstacles.clear()
	FX.reset_time()
	p.axe.cancel()
	p.weapon_skill_cancel_motion()
	p._weapon_skill_landing_used = false
	p._dash_time_left = 0.0
	p._stomp_cooldown = 0.0
	p._super_jump_left = 0.0
	p._bounce_window_left = 0.0
	p._jump_buffer_left = 0.0
	p.is_slamming = false
	p.is_sliding = false
	p.is_climbing = false
	p.health = p.max_health
	p._invuln_left = 0.0
	p.crit_chance_base = 0.0
	p.shield = 0.0
	p.body_handlers.clear()
	p.style.reset()
	Run.runes.clear()
	p.dash_recharge = 100000.0
	p.dash_charges = 0
	p.velocity = Vector3.ZERO
	p.global_position = origin
	p.rotation_target = Vector2.ZERO
	p.rotation.y = 0.0
	p.head.rotation.x = 0.0
	p.weapons.equip(Loot.get_def(weapon), level, false)
	p.weapons.switch_to(WeaponHolder.MELEE, true)
	await frames(20)

func test_whirl() -> void:
	print("-- Вертушка")
	await reset_player("axe")
	var right := enemy_at(p.global_position + Vector3(2.35, 0, 0))
	var left := enemy_at(p.global_position + Vector3(-2.35, 0, 0))
	var back := enemy_at(p.global_position + Vector3(0, 0, 2.35))
	var far := enemy_at(p.global_position + Vector3(3.45, 0, 0))
	var started_ok := await hold_until("whirl")
	var finished := await wait_weapon()
	var one := 1000.0 - right.health
	check(started_ok and finished and one > 0.0 and left.health < 1000.0 and back.health < 1000.0,
		"удержание запускает вертушку и бьёт с трёх сторон")
	check(far.health == 1000.0, "цель вне радиуса вертушки ур. 1 не получает урона")

	await reset_player("axe", 3)
	var near3 := enemy_at(p.global_position + Vector3(2.35, 0, 0))
	var far3 := enemy_at(p.global_position + Vector3(3.45, 0, 0))
	var yaw_before := p.rotation_target.y
	started_ok = await hold_until("whirl")
	finished = await wait_weapon()
	var three := 1000.0 - near3.health
	var expected := one * WeaponDef.level_mult(3) * 2.0
	check(started_ok and finished and far3.health < 1000.0,
		"вертушка ур. 3 достаёт цель за пределами радиуса ур. 1")
	check(one > 0.0 and absf(three - expected) < expected * 0.15 and p.rotation_target.y - yaw_before > TAU * 1.9,
		"ур. 3 делает два оборота и два попадания (урон %.1f / %.1f)" % [one, three])

	await reset_player("axe")
	var late := enemy_at(p.global_position + Vector3(5.0, 0, 0))
	started_ok = await hold_until("whirl")
	await frames(6)
	late.global_position = p.global_position + Vector3(2.2, 0, 0)
	finished = await wait_weapon()
	check(started_ok and finished and late.health < 1000.0,
		"вертушка попадает по врагу, вошедшему в радиус после начала")

	await reset_player("axe")
	var hidden := enemy_at(p.global_position + Vector3(2.1, 0, 0))
	var visible := enemy_at(p.global_position + Vector3(-2.1, 0, 0))
	make_box(p.global_position + Vector3(1.05, 1.0, 0), Vector3(0.2, 2.0, 2.0))
	await frames(2)
	started_ok = await hold_until("whirl")
	finished = await wait_weapon()
	check(started_ok and finished and hidden.health == 1000.0 and visible.health < 1000.0,
		"стена блокирует урон вертушки, открытая цель получает урон")

	await reset_player("axe")
	p.dash_charges = 1
	started_ok = await hold_until("whirl")
	await tap("dash")
	var speed_reset := is_equal_approx(p.weapon_skill_speed_mult, 1.0)
	var after_dash := enemy_at(p.global_position + Vector3(1.5, 0, 0))
	await frames(20)
	check(started_ok and speed_reset and after_dash.health == 1000.0 and not p.axe.is_busy(),
		"рывок отменяет вертушку, её урон и замедление")

func test_lunge() -> void:
	print("-- Выпад")
	var distances: Array[float] = []
	for level in [1, 3]:
		await reset_player("sword", level)
		var origin := p.global_position
		var started_ok := await hold_until("lunge")
		var forward := p.get_aim_forward()
		forward.y = 0.0
		forward = forward.normalized()
		# Цели ставятся после взмаха, чтобы урон мог нанести только выпад.
		var first := enemy_at(origin + forward * 2.7)
		var second: Enemy = null
		if level == 3:
			second = enemy_at(origin + forward * 8.0)
		var finished := await wait_weapon()
		var travel := (p.global_position - origin).dot(forward)
		distances.append(travel)
		check(started_ok and finished and first.health < 1000.0 and travel > 3.5,
			"выпад ур. %d двигает игрока через первую цель и наносит ей урон" % level)
		if level == 3:
			check(second.health < 1000.0 and travel > 9.5,
				"второй выпад ур. 3 достигает следующей цели")
	check(distances.size() == 2 and distances[1] > distances[0] * 1.8,
		"двойной выпад ур. 3 заметно длиннее выпада ур. 1")

	await reset_player("sword")
	var origin := p.global_position
	make_box(origin + Vector3(0, 1.0, -1.1), Vector3(2.0, 2.0, 0.2))
	await frames(2)
	var wall_start := await hold_until("lunge")
	var hidden := enemy_at(origin + Vector3(0, 0, -1.75))
	var visible := enemy_at(origin + Vector3(1.0, 0, -0.3))
	var wall_finished := await wait_weapon()
	check(wall_start and wall_finished and hidden.health == 1000.0 and visible.health < 1000.0,
		"выпад останавливается у стены и не бьёт врага за ней, открытая цель получает урон")

	await reset_player("sword")
	p.dash_charges = 1
	var started_ok := await hold_until("lunge")
	await tap("dash")
	var dash_direction := p._dash_dir
	var target := enemy_at(p.global_position + dash_direction * 2.0)
	await frames(20)
	check(started_ok and target.health == 1000.0 and not p.weapon_skill_lunge_active(),
		"выпад отменяется рывком и не наносит урон на пути рывка")

func test_skill_props() -> void:
	print("-- Приёмы и разрушаемые предметы")
	await reset_player("axe")
	Run.add_rune(Run.rune_def("thunder_call"))
	p.recalc_from_runes(Run)
	p._thunder_hits = 0
	var actions: Array[StringName] = []
	var on_gained := func(action: StringName, _amount: float) -> void: actions.append(action)
	p.style.gained.connect(on_gained)
	var kills_before := Run.kills
	var glory_before := Run.glory
	var visible := prop_at(p.global_position + Vector3(-2.2, 0.0, 0.0))
	var hidden := prop_at(p.global_position + Vector3(2.2, 0.0, 0.0))
	make_box(p.global_position + Vector3(1.05, 1.0, 0), Vector3(0.2, 2.0, 2.0))
	await frames(2)
	var expected := p.axe._skill_damage(p.axe.def.skill_damage_mult)
	p.axe.request_heavy()
	var finished := await wait_weapon()
	check(finished and absf((1000.0 - visible.health) - expected) < 0.1 and is_equal_approx(hidden.health, 1000.0),
		"вертушка бьёт ящик один раз за оборот и не проходит через стену")
	check(actions == [&"melee_whirl"] and p._thunder_hits == 0 and Run.kills == kills_before and Run.glory == glory_before,
		"попадание по ящику не даёт дополнительных очков, убийств, Славы или срабатывания руны")
	p.style.gained.disconnect(on_gained)
	Run.runes.clear()
	p.recalc_from_runes(Run)

	await reset_player("sword")
	var along := prop_at(p.global_position + Vector3(0, 0, -2.0))
	await frames(2)
	p.axe.request_heavy()
	finished = await wait_weapon()
	check(finished and along.health < 1000.0, "выпад наносит урон ящику на своём пути")

	await reset_player("axe")
	var dive_prop := prop_at(p.global_position + Vector3(1.5, 0, 0))
	p.global_position.y = 4.0
	p.velocity = Vector3.ZERO
	await frames(3)
	var before := count(landed, "axe_dive")
	await tap("attack")
	var touchdown := await wait_landing("axe_dive", before)
	check(touchdown and dive_prop.health < 1000.0, "пике топора наносит урон ящику при посадке")

	for level in [1, 3]:
		await reset_player("staff", level)
		var ground := p.global_position
		var vault_started := await hold_until("vault")
		var wave_prop := prop_at(ground + Vector3(1.8, 0, 0))
		await frames(3)
		before = count(landed, "staff_wave")
		await tap("attack")
		touchdown = await wait_landing("staff_wave", before)
		check(vault_started and touchdown and (is_equal_approx(wave_prop.health, 1000.0) if level == 1 else wave_prop.health < 1000.0),
			"волна посоха ур. %d %s ящик" % [level, "не повреждает" if level == 1 else "повреждает"])

func test_dive() -> void:
	print("-- Пике топора")
	await reset_player("axe")
	var e := enemy_at(p.global_position + Vector3(1.0, 0, 0))
	p.global_position.y = 4.0
	p.velocity = Vector3.ZERO
	await frames(3)
	var before := count(landed, "axe_dive")
	await tap("attack")
	var touched_floor := await wait_landing("axe_dive", before)
	var dive_damage := 1000.0 - e.health
	check(touched_floor and p.is_on_floor() and dive_damage > 0.0 and p.dash_charges == 0,
		"пике наносит урон при настоящей посадке и не расходует руну")
	await reset_player("axe")
	e = enemy_at(p.global_position + Vector3(1.0, 0, 0))
	await frames(2)
	p._do_slam_impact(0.0)
	var slam_damage := 1000.0 - e.health
	check(slam_damage > dive_damage and dive_damage > 0.0,
		"пике слабее обычного удара-приземления по той же цели (%.1f < %.1f)" % [dive_damage, slam_damage])

func test_parry() -> void:
	print("-- Парирование")
	# Прицельные атаки врага проходят через _execute_attack, а не прямой вызов парирования.
	for level in [1, 3]:
		await reset_player("sword", level)
		p.axe.hitbox.collision_mask = 0
		var e := enemy_at(p.global_position + Vector3(0, 0, -1.3))
		e._set_state(Enemy.State.WINDUP)
		var hp := p.health
		await tap("attack")
		if level == 3:
			await frames(12)
		e._execute_attack()
		check(is_equal_approx(p.health, hp) and e.state == Enemy.State.STUNNED and e._stun_left > 1.0,
			"парирование ур. %d останавливает реальную атаку и сохраняет оглушение" % level)
		p.axe.hitbox.collision_mask = 92

	await reset_player("sword")
	p.axe.hitbox.collision_mask = 0
	var e := enemy_at(p.global_position + Vector3(0, 0, -1.3))
	e._set_state(Enemy.State.WINDUP)
	var hp := p.health
	await tap("attack")
	await frames(12)
	e._execute_attack()
	check(p.health < hp and e.state != Enemy.State.STUNNED,
		"та же атака после окна ур. 1 попадает, тогда как ур. 3 ещё парирует")

	await reset_player("sword")
	p.axe.hitbox.collision_mask = 0
	hp = p.health
	await tap("attack")
	var projectile := PROJECTILE.new()
	game.add_child(projectile)
	projectile.launch(p.global_position + Vector3(0, 0.9, -1.0), Vector3(0, 0, 8), 7.0, null)
	await frames(6)
	check(is_instance_valid(projectile) and projectile.reflected and projectile.vel.z < 0.0 and p.health == hp,
		"входящий снаряд отражается назад без урона игроку")
	if is_instance_valid(projectile):
		projectile.queue_free()
	p.axe.hitbox.collision_mask = 92

func jump_height() -> float:
	var start := p.global_position.y
	await tap("jump")
	var peak := p.global_position.y
	for i in 240:
		await get_tree().physics_frame
		peak = maxf(peak, p.global_position.y)
		if p.is_on_floor() and i > 5:
			break
	return peak - start

func test_staff() -> void:
	print("-- Посох")
	await reset_player("staff")
	var normal := await jump_height()
	await reset_player("staff")
	var ground := p.global_position.y
	var started_ok := await hold_until("vault")
	await frames(3)
	var may_slam := not p.is_on_floor() and p.can_start_slam()
	var peak := p.global_position.y
	for i in 240:
		await get_tree().physics_frame
		peak = maxf(peak, p.global_position.y)
		if p.is_on_floor() and i > 5:
			break
	var vault := peak - ground
	check(started_ok and normal > 0.0 and vault / normal > 1.4 and vault / normal < 1.85,
		"прыжок с шестом выше обычного примерно в 1.6 раза (%.2f / %.2f)" % [vault, normal])
	check(may_slam and p.dash_charges == 0, "прыжок с шестом разрешает удар и не расходует руну")

	var weak_push := 0.0
	for level in [1, 2, 3]:
		await reset_player("staff", level)
		started_ok = await hold_until("vault")
		await frames(3)
		var e := enemy_at(p.global_position + Vector3(1.5, -p.global_position.y, 0))
		var before := count(landed, "staff_wave")
		await tap("attack")
		var touchdown := await wait_landing("staff_wave", before)
		var push := e.knockback_velocity.length()
		if level == 1:
			weak_push = push
		if level < 3:
			check(started_ok and touchdown and e.health == 1000.0 and push > 1.0,
				"волна ур. %d толкает врага при посадке без урона" % level)
		else:
			check(started_ok and touchdown and e.health < 1000.0 and push > weak_push * 1.5,
				"волна ур. 3 наносит урон и толкает сильнее")
		var old_x := e.global_position.x
		e._set_state(Enemy.State.STUNNED)
		e._stun_left = 10.0
		e.set_physics_process(true)
		await frames(20)
		check(e.global_position.x > old_x + 0.1, "толчок волны ур. %d реально сдвигает врага" % level)

func test_wave_fall() -> void:
	print("-- Сброс волной")
	await reset_player("staff")
	make_box(Vector3(130, 7.5, 0), Vector3(4, 1, 4))
	p.global_position = Vector3(130, 8.1, 0)
	p.velocity = Vector3.ZERO
	await frames(20)
	var started_ok := await hold_until("vault")
	await frames(3)
	var e := enemy_at(Vector3(131.7, 8.05, 0))
	var kills_before := Run.kills
	var before := count(landed, "staff_wave")
	await tap("attack")
	var touchdown := await wait_landing("staff_wave", before)
	var pushed_without_damage := is_instance_valid(e) and e.health == 1000.0 and e.knockback_velocity.x > 1.0
	e._set_state(Enemy.State.STUNNED)
	e._stun_left = 10.0
	e.set_physics_process(true)
	for i in 300:
		await get_tree().physics_frame
		if not is_instance_valid(e) or e.is_dead:
			break
	check(started_ok and touchdown and pushed_without_damage and Run.kills == kills_before + 1,
		"волна без урона сбрасывает врага с уступа и учитывает убийство падением")

func test_enemy_head() -> void:
	print("-- Контакт с головой")
	for id in ["axe", "staff"]:
		await reset_player(id)
		var e := enemy_at(p.global_position)
		p.global_position.y = 3.4
		p.velocity = Vector3.ZERO
		await frames(3)
		p._stomp_cooldown = 5.0
		var skill := "axe_dive" if id == "axe" else "staff_wave"
		var before_start := count(started, skill)
		var before_land := count(landed, skill)
		await tap("attack")
		var contacted := false
		for i in 100:
			await get_tree().physics_frame
			for j in p.get_slide_collision_count():
				var col := p.get_slide_collision(j)
				if col.get_collider() == e and col.get_normal().y > 0.6:
					contacted = true
			if contacted:
				break
		check(count(started, skill) > before_start and contacted and count(landed, skill) == before_land and e.health == 1000.0,
			"%s: голова врага при активном кулдауне отскока не запускает удар о землю" % id)

func test_labels() -> void:
	print("-- Подписи приёмов")
	var hud := game.hud.get_node_or_null("WeaponHUD") as WeaponHUD
	check(hud != null, "HUD оружия создан")
	if hud == null:
		return
	var pickup := WeaponPickup.new()
	game.add_child(pickup)
	for loc in ["ru", "en"]:
		GameSettings.set_value("text", "language", loc, false)
		for row in [["axe", "Вертушка", "Whirlwind"], ["sword", "Выпад и парирование", "Lunge and Parry"], ["staff", "Шест", "Pole Vault"]]:
			var def := Loot.get_def(row[0])
			p.weapons.equip(def, 1, false)
			hud._refresh()
			pickup.item = WeaponItem.create(def)
			var expected: String = row[1] if loc == "ru" else row[2]
			check(hud._skills[0].visible and expected in hud._skills[0].text and expected in pickup.prompt_text(p.weapons),
				"%s: название приёма %s в HUD и подсказке подбора" % [loc, row[0]])
		p.weapons.equip(Loot.get_def("pistol"), 1, false)
		hud._refresh()
		pickup.item = WeaponItem.create(Loot.get_def("pistol"))
		check(not hud._skills[1].visible and not ("\n" in pickup.prompt_text(p.weapons)),
			"%s: у ренжа нет пустой подписи приёма" % loc)
	pickup.queue_free()
	GameSettings.set_value("text", "language", "ru", false)
	p.weapons.switch_to(WeaponHolder.MELEE, true)

func _run() -> void:
	print("=== WEAPON SKILL TEST ===")
	Dialogue.in_run_scenes = false
	Run.start_run("hunter")
	Run.doors_enabled = false
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(100)
	game = get_tree().current_scene as Game
	if game == null or game.player == null or game.room == null:
		check(false, "сцена игры загрузилась")
		get_tree().quit(1)
		return
	p = game.player
	game.room.set_physics_process(false)
	game.room._spawn_queue.clear()
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	game.room._alive.clear()
	GameSettings.set_value("access", "slam_slowmo", false, false)
	p.axe.weapon_skill_started.connect(func(kind: String) -> void: started[kind] = count(started, kind) + 1)
	p.weapon_skill_landed.connect(func(kind: String) -> void: landed[kind] = count(landed, kind) + 1)
	make_box(Vector3(100.0, -0.5, 0.0), Vector3(100.0, 1.0, 100.0), false)
	await test_whirl()
	await test_lunge()
	await test_skill_props()
	await test_dive()
	await test_parry()
	await test_staff()
	await test_wave_fall()
	await test_enemy_head()
	test_labels()
	FX.reset_time()
	print("=== ИТОГ WEAPON SKILL: %d OK, %d FAIL ===" % [passes, fails.size()])
	get_tree().quit(1 if not fails.is_empty() else 0)
