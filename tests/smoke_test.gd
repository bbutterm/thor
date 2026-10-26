extends Node
## Автотест «дымовой проверки»: прогоняет весь цикл без человека.
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/smoke_test.tscn
## Проверяет движение, топор, Мьёльнир, удар-приземление, волны, руны, двери, все залы, босса, смерть.

var _fails: Array[String] = []
var _passes: int = 0
var game: Game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		# Сцена теста будет заменена сценой игры — запускаем «бегуна» прямо в корне дерева
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "SmokeRunner"
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
	var frames := int(ceil(sec * 60.0))
	for i in frames:
		await get_tree().physics_frame

func press(action: String, hold: float = 0.05) -> void:
	Input.action_press(action)
	await wait(hold)
	Input.action_release(action)
	await get_tree().physics_frame

func _run() -> void:
	print("=== SMOKE TEST ===")
	Run.start_run("berserker")
	# Тестовый порядок: все 6 залов + босс
	Run.room_order.assign(Run.ROOM_SCENES.duplicate())
	Run.room_order.append(Run.BOSS_SCENE)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.3)
	game = get_tree().current_scene as Game
	check(game != null, "сцена игры загрузилась")
	if game == null:
		_finish()
		return
	var p := game.player
	check(p.max_health == 150.0, "тело Берсерк применилось (150 HP)")
	await wait(1.6)
	check(game.room.alive_count() > 0, "враги первой волны появились (%d)" % game.room.alive_count())

	# Отодвигаем врагов, чтобы не мешали тестам движения
	for e in game.room.alive_enemies():
		e.global_position = Vector3(game.room.global_position.x + 9, 0.1, -9)
		e.set_physics_process(false)

	await _test_movement(p)
	await _test_axe(p)
	await _test_hammer(p)
	await _test_slam(p)
	for e in game.room.alive_enemies():
		e.set_physics_process(true)

	# Проходим все залы
	var total := Run.total_rooms()
	for i in total:
		var ok := await _clear_room_and_exit(i == total - 1)
		if not ok:
			break
	await wait(2.5)
	check(game.end_screen.visible, "после босса показан экран победы")
	check(Run.won, "Run.won = true")
	print("  Слава за забег: ", Run.glory, ", убито: ", Run.kills, ", рун: ", Run.runes.size(), ", вердикт: ", Run.verdict())

	# Смерть
	game.restart_run()
	await wait(0.5)
	game = get_tree().current_scene as Game
	check(game != null, "новый забег после победы")
	await wait(1.0)
	game.player.take_damage(99999.0, Vector3.ZERO, true)
	await wait(2.0)
	check(game.player.is_dead, "игрок умер")
	check(game.end_screen.visible, "экран смерти показан")
	await _test_after_death()
	_finish()

## После смерти: «К Одину» → диалог у дивана → «План тренировок» → «В бой» → новый забег
func _test_after_death() -> void:
	print("-- После смерти")
	var deaths := Save.deaths()
	check(deaths >= 1, "смерть записана в сохранение (%d)" % deaths)
	game.end_screen.restart_requested.emit()
	await wait(0.4)
	var box := Dialogue.box()
	check(box.visible, "диалог Одина после смерти")
	box.skip()
	await wait(0.4)
	var plan := game.get_node_or_null("TrainingPlan") as TrainingPlan
	check(plan != null and plan.visible, "после диалога — «План тренировок»")
	check(Save.glory_bank() > 0, "Слава забегов в копилке (%d)" % Save.glory_bank())
	if plan:
		plan._fight_btn.pressed.emit()
	await wait(1.0)
	var g2 := get_tree().current_scene as Game
	check(g2 != null and g2 != game, "новый забег после диалога")
	check(not get_tree().paused, "новый забег не на паузе")
	game = g2

func _test_movement(p: Player) -> void:
	print("-- Движение")
	await wait(0.3)
	check(p.is_on_floor(), "игрок стоит на полу")
	await press("jump")
	await wait(0.15)
	var y1 := p.global_position.y
	check(p.velocity.y > 0.0 and not p.is_on_floor(), "прыжок")
	await press("jump")
	await wait(0.05)
	check(p.velocity.y > 5.0, "двойной прыжок (vy=%.1f)" % p.velocity.y)
	await wait(1.5)
	check(p.is_on_floor(), "приземлился")
	var charges_before := p.dash_charges
	Input.action_press("move_forward")
	await press("dash")
	await wait(0.03)
	check(p.horizontal_speed() > 15.0, "рывок (скорость %.1f)" % p.horizontal_speed())
	check(p.dash_charges == charges_before - 1, "заряд рывка списан")
	Input.action_release("move_forward")
	await wait(1.6)
	check(p.dash_charges == p.dash_charges_max, "заряды восстановились")
	print("    высота прыжка ~", snappedf(y1, 0.01))

func _test_axe(p: Player) -> void:
	print("-- Топор")
	var dummy := _make_dummy(p, 1.6)
	var hp0 := dummy.health
	p.axe.request_attack()
	await wait(0.35)
	check(dummy.health < hp0, "удар топором нанёс урон (%.0f → %.0f)" % [hp0, dummy.health])
	p.axe.request_attack()
	await wait(0.1)
	p.axe.request_attack()
	await wait(0.6)
	check(p.axe.stage == 2, "комбо дошло до 3-го удара")
	if is_instance_valid(dummy):
		dummy.take_hit(9999, Vector3.ZERO, "test")
	await wait(0.2)

func _test_hammer(p: Player) -> void:
	print("-- Мьёльнир")
	# Ставим игрока на свободную линию (без колонн и бочек между ним и манекенами)
	p.global_position = game.room.global_position + Vector3(3, 0.1, 10)
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2(0, 0)
	await wait(0.3)
	var dummies: Array[Enemy] = []
	for d in [4.0, 7.0, 10.0]:
		dummies.append(_make_dummy(p, d))
	await wait(0.1)
	p.mjolnir.throw_hammer()
	await wait(0.1)
	check(not p.mjolnir.in_hand, "молот улетел")
	await wait(3.0)
	var hit := 0
	for dd in dummies:
		if not is_instance_valid(dd) or dd.health < dd.max_health:
			hit += 1
	check(hit == 3, "молот задел все 3 манекена (%d/3)" % hit)
	check(p.mjolnir.in_hand, "молот вернулся в руку")
	# Ручной возврат
	p.mjolnir.throw_hammer()
	await wait(0.3)
	p.mjolnir.request_throw_or_recall()
	await wait(1.5)
	check(p.mjolnir.in_hand, "ручной возврат молота")
	for dd in dummies:
		if is_instance_valid(dd):
			dd.take_hit(9999, Vector3.ZERO, "test")
	await wait(0.2)

func _test_slam(p: Player) -> void:
	print("-- Удар-приземление и супер-прыжок")
	var dummy := _make_dummy(p, 2.5)
	var hp0 := dummy.health
	await press("jump")
	await wait(0.35)
	await press("slam")
	var landed := false
	for i in 120:
		await get_tree().physics_frame
		if p.is_on_floor():
			landed = true
			break
	check(landed, "приземлился после удара")
	check(not p.is_slamming, "удар завершён")
	await get_tree().physics_frame
	Input.action_press("jump")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("jump")
	check(p.velocity.y > p.jump_velocity * 1.25, "супер-прыжок (vy=%.1f при обычном %.1f)" % [p.velocity.y, p.jump_velocity])
	await wait(0.2)
	check(not is_instance_valid(dummy) or dummy.health < hp0, "волна удара задела врага")
	await wait(2.0)
	if is_instance_valid(dummy):
		dummy.take_hit(9999, Vector3.ZERO, "test")
	await wait(0.2)

func _make_dummy(p: Player, dist: float) -> Enemy:
	var e := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	e.max_health = 500
	game.add_child(e)
	var fwd := p.get_aim_forward()
	fwd.y = 0
	fwd = fwd.normalized()
	e.global_position = p.global_position + fwd * dist
	e.set_physics_process(false)
	e.health = 500
	return e

func _clear_room_and_exit(is_last: bool) -> bool:
	var room := game.room
	print("-- Зал %d: %s" % [Run.room_index + 1, room.room_title])
	var waves := room.wave_count()
	var safety := 0
	var seen_boss := false
	var seen_miniboss := false
	var miniboss_room := Run.is_miniboss_room()
	while not room._is_cleared and safety < 40:
		safety += 1
		await wait(1.2)
		for e in room.alive_enemies().duplicate():
			if is_instance_valid(e):
				if e.kind == Enemy.Kind.BOSS:
					seen_boss = true
				if e.has_meta("miniboss"):
					seen_miniboss = true
				e.take_hit(9999, Vector3(0, 3, -5), "axe_finisher")
		game.player.heal(999)
	check(room._is_cleared, "зал зачищен (%d волн)" % waves)
	if is_last:
		check(seen_boss, "босс появился в финальном зале")
		return true
	await wait(1.2)
	if miniboss_room:
		# Мини-босс → выбор трейта Мьёльнира → выбор руны
		check(seen_miniboss, "мини-босс появился последней волной")
		check(game.trait_pick.visible, "показан выбор трейта Мьёльнира")
		check(get_tree().paused, "игра на паузе во время выбора трейта")
		var levels_before := 0
		for v in Run.mjolnir_trait_levels.values():
			levels_before += int(v)
		game.trait_pick._open_time = -10.0
		game.trait_pick.choose(randi() % game.trait_pick._choices.size(), true)
		await wait(0.2)
		var levels_after := 0
		for v in Run.mjolnir_trait_levels.values():
			levels_after += int(v)
		check(levels_after == levels_before + 1, "трейт взят (%s)" % ", ".join(Run.mjolnir_traits.map(func(t: MjolnirTrait) -> String: return str(t.id))))
		check(game.player.mjolnir.traits.size() == Run.mjolnir_traits.size(), "обработчики трейтов у молота (%d)" % game.player.mjolnir.traits.size())
		await wait(1.0)
	check(game.rune_pick.visible, "показан выбор руны")
	check(get_tree().paused, "игра на паузе во время выбора")
	await wait(0.4)
	var idx_before := Run.room_index
	game.rune_pick._open_time = -10.0
	game.rune_pick.choose(randi() % 3)
	await wait(0.2)
	check(not get_tree().paused, "пауза снята после выбора")
	check(room.door_open, "дверь открыта")
	await wait(1.0)
	var exit_pos := room.exit_area.global_position
	game.player.global_position = exit_pos + Vector3(0, 0.2, 1.5)
	game.player.velocity = Vector3(0, 0, -6)
	await wait(1.2)
	check(Run.room_index == idx_before + 1, "переход в следующий зал (%d)" % (Run.room_index + 1))
	check(game.room != room, "загружен новый зал")
	return game.room != room

func _finish() -> void:
	print("=== ИТОГ: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
