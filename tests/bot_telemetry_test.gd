extends Node
## Контролируемые игровые сигналы и блоки: наблюдатель не должен менять бой или выдавать ложные события.

const BalanceTelemetry := preload("res://tests/bot/balance_telemetry.gd")
const BotPlayer := preload("res://tests/bot/bot_player.gd")

var fails: Array[String] = []
var passes := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var n := Node.new()
		n.set_script(get_script())
		n.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(n)
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

func find_events(observer: Node, kind: String) -> Array:
	return observer.events.filter(func(e: Dictionary) -> bool: return e.type == kind)

## Одинаковая последовательность настоящих вызовов при выключенной и включённой записи.
func controlled_exchange(p: Player, enemy: Enemy) -> Dictionary:
	p.health = p.max_health
	p.shield = 10.0
	p.shield_max = 10.0
	p.health_changed.emit(p.health, p.max_health)
	enemy.health = enemy.max_health
	enemy.state = Enemy.State.CHASE
	enemy.velocity = Vector3.ZERO
	enemy.knockback_velocity = Vector3.ZERO
	var to := p.global_position - enemy.global_position
	enemy.rotation.y = atan2(to.x, to.z)
	var away := -to.normalized() * 5.0
	seed(9102)
	RunTracker.note_damage("paired_control")
	p.take_damage(16.0, Vector3.ZERO, true)
	p.heal(3.0)
	var hp_before_block := enemy.health
	enemy.take_hit(20.0, away, "melee")
	var blocked := is_equal_approx(enemy.health, hp_before_block)
	enemy.take_hit(10.0, away, "slam")
	return {"hp": p.health, "shield": p.shield, "enemy_hp": enemy.health, "blocked": blocked}

func _run() -> void:
	print("=== BOT TELEMETRY TEST ===")
	Run.start_run("thrall")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(110)
	var game := get_tree().current_scene as Game
	if game == null or game.room == null or game.player == null:
		check(false, "игра загрузилась")
		_finish()
		return
	var room := game.room
	room.set_physics_process(false)
	room._spawn_queue.clear()
	for enemy in room.alive_enemies().duplicate():
		enemy.queue_free()
	room._alive.clear()
	var p := game.player
	p.input_enabled = false
	await frames(3)
	if p.is_dead:
		check(false, "игрок жив до начала контролируемого теста")
		_finish()
		return
	p.health = p.max_health
	p.shield = 0.0
	p.shield_max = 0.0
	p.health_changed.emit(p.health, p.max_health)

	var observer := BalanceTelemetry.new()
	get_tree().root.add_child(observer)
	seed(48231)
	var expected_random := randf()
	seed(48231)
	observer.begin(game)
	check(is_equal_approx(randf(), expected_random), "запуск наблюдателя не расходует случайное число")
	var hp := p.health
	RunTracker.note_damage("test_hit")
	p.take_damage(10.0, Vector3.ZERO, true)
	var hurts := find_events(observer, "hurt")
	check(hurts.size() == 1 and hurts[0].source == "test_hit" and is_equal_approx(hurts[0].hp_before, hp)
		and is_equal_approx(hurts[0].hp_after, hp - 10.0), "попадание записано с источником и HP до/после")
	p.heal(3.0)
	var hp_events := find_events(observer, "health_change")
	check(hp_events.size() == 1 and is_equal_approx(hp_events[0].hp_after - hp_events[0].hp_before, 3.0), "восстановление HP записано отдельно от удара")

	p.shield = 10.0
	p.shield_max = 10.0
	p.health_changed.emit(p.health, p.max_health)
	RunTracker.note_damage("test_shield_only")
	p.take_damage(4.0, Vector3.ZERO, true)
	var shield_events := find_events(observer, "shield_change")
	check(shield_events.size() == 2 and is_equal_approx(shield_events[1].before, 10.0)
		and is_equal_approx(shield_events[1].after, 6.0) and shield_events[1].pending_source == "test_shield_only",
		"полное поглощение щитом видно даже без сигнала hurt")
	check(find_events(observer, "hurt").size() == 1, "полностью поглощённый удар не записан как потеря HP")
	RunTracker.note_damage("test_partial")
	p.take_damage(9.0, Vector3.ZERO, true)
	hurts = find_events(observer, "hurt")
	shield_events = find_events(observer, "shield_change")
	check(shield_events.size() == 3 and is_equal_approx(shield_events[2].after, 0.0) and hurts.size() == 2
		and hurts[1].source == "test_partial" and is_equal_approx(hurts[1].amount, 3.0), "частичный щит и дошедший до HP остаток разделены")

	var shield_enemy := room.spawn_extra("shieldbearer", p.global_position + Vector3(0, 0, -2.5))
	shield_enemy.set_physics_process(false)
	shield_enemy.state = Enemy.State.CHASE
	var to := p.global_position - shield_enemy.global_position
	shield_enemy.rotation.y = atan2(to.x, to.z)
	var enemy_hp := shield_enemy.health
	var away := -to.normalized() * 5.0
	shield_enemy.take_hit(20.0, away, "melee")
	shield_enemy.take_hit(20.0, away, "melee")
	shield_enemy.take_hit(10.0, away, "slam")
	await get_tree().process_frame
	await get_tree().process_frame  # наблюдатель уже отработал до Perf на предыдущем кадре
	check(shield_enemy.health < enemy_hp, "удар-приземление прошёл по щиту")
	check(find_events(observer, "shield_block").size() == 2, "два настоящих блока щита записаны по одному разу")
	await get_tree().process_frame
	check(find_events(observer, "shield_block").size() == 2, "чтение отметок Perf не дублирует блоки в следующем кадре")
	observer.finish()
	observer.queue_free()
	var paired_observer := BalanceTelemetry.new()
	get_tree().root.add_child(paired_observer)
	var without_trace := controlled_exchange(p, shield_enemy)
	paired_observer.begin(game)
	var with_trace := controlled_exchange(p, shield_enemy)
	check(without_trace == with_trace and with_trace.blocked, "контролируемые HP, щит и урон врагу совпадают с trace и без него")
	await get_tree().process_frame
	await get_tree().process_frame
	check(find_events(paired_observer, "shield_block").size() == 1, "при запуске trace старый блок не попадает в новый журнал")
	paired_observer.finish()
	paired_observer.queue_free()
	shield_enemy.queue_free()
	await frames(2)

	var bot := BotPlayer.new()
	bot.telemetry_enabled = true
	get_tree().root.add_child(bot)
	bot.begin(game, 7)
	bot.tap("attack")
	check(find_events(bot.telemetry, "input").any(func(e: Dictionary) -> bool: return e.action == "attack"), "зафиксирована реально поданная кнопка атаки")
	p.axe._begin_stage(0, false)
	check(find_events(bot.telemetry, "melee_swing").size() == 1, "фактический взмах отличается от нажатия")
	p._do_slam_impact(4.0)
	check(find_events(bot.telemetry, "slam_impact").size() == 1, "фактическое приземление записано по сигналу игрока")
	bot.stop()
	bot.queue_free()
	await frames(2)
	bot = BotPlayer.new()
	get_tree().root.add_child(bot)
	bot.begin(game, 7)
	check(not is_instance_valid(bot.telemetry), "в обычном прогоне телеметрия выключена")
	bot.stop()
	bot.queue_free()

	var limited := BalanceTelemetry.new()
	get_tree().root.add_child(limited)
	limited.begin(game, 2)
	limited.record("one")
	limited.record("two")
	check(limited.events.size() == 2 and limited.dropped == 1, "лимит событий ограничивает объём и считает пропущенные")
	limited.finish()
	limited.queue_free()
	_finish()

func _finish() -> void:
	print("=== ИТОГ BOT TELEMETRY: %d OK, %d FAIL ===" % [passes, fails.size()])
	for fail in fails:
		print("  FAIL: ", fail)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(1 if not fails.is_empty() else 0)
