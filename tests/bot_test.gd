extends Node
## Бот-плейтестер: настоящий забег может закончиться смертью. Отдельная контролируемая площадка
## с одним обычным врагом проверяет бой, зачистку, реальную награду и вход в дверь.
## godot --headless --path . --fixed-fps 60 res://tests/bot_test.tscn

const BalanceRunner := preload("res://tests/bot/balance_runner.gd")
const BotPlayer := preload("res://tests/bot/bot_player.gd")

var _fails: Array[String] = []
var _passes: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var n := Node.new()
		n.set_script(get_script())
		n.set_meta("runner", true)
		n.name = "BotTest"
		get_tree().root.add_child.call_deferred(n)
		return
	print("=== BOT TEST ===")
	var r := Node.new()
	r.set_script(BalanceRunner)
	r.name = "BalanceRunner"
	r.set_meta("args", {"bodies": "berserker", "runs": 1, "seed": 7, "max_rooms": 3, "time_cap": 240, "room_cap": 120})
	r.set_meta("on_done", _on_done)
	get_tree().root.add_child.call_deferred(r)

func check(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
		print("  [OK] ", what)
	else:
		_fails.append(what)
		print("  [FAIL] ", what)

func _on_done(results: Array) -> void:
	check(results.size() == 1, "один настоящий забег сыгран")
	if results.is_empty():
		_finish()
		return
	var r: Dictionary = results[0]
	print("  итог: %s, зал %d, %.0f с, Слава %d, убито %d, урон %.0f" % [r.outcome, r.rooms_reached, r.time, r.glory, r.kills, r.dmg_total])
	# Смерть — ожидаемый исход, а не ошибка инфраструктуры бота.
	check(r.outcome in ["stopped", "death", "win"], "забег закончился штатно (%s)" % r.outcome)
	check(float(r.time) > 0.0 and int(r.rooms_reached) >= 1, "время и достигнутый зал записаны")
	var rooms: Array = r.rooms
	check(not rooms.is_empty() and int(rooms[0].get("index", -1)) == 0, "записан первый зал")
	check(int(r.stats.get("throws", -1)) >= 0 and int(r.kills) >= 0, "счётчики действий и убийств записаны")
	if r.outcome == "death":
		check(str(r.cause) != "", "причина смерти сохранена")
	check(not get_tree().paused, "игра не на паузе")
	_test_controlled_encounter.call_deferred()

func _test_controlled_encounter() -> void:
	print("-- Контролируемый бой, награда и дверь")
	# Только состав тестовой сцены контролируется; HP игрока, ввод, оружие, враг и награды обычные.
	get_tree().paused = false
	FX.reset_time()
	seed(773)
	Run.start_run("berserker")
	Run.room_order.assign(["res://tests/bot/fixture_room.tscn", "res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	var game: Game = null
	for i in 120:
		await get_tree().physics_frame
		game = get_tree().current_scene as Game
		if game and game.is_node_ready() and game.room:
			break
	if game == null or not game.is_node_ready() or game.room == null:
		check(false, "тестовый зал загружен")
		_finish()
		return
	var first_room_id := game.room.get_instance_id()
	var bot := BotPlayer.new()
	get_tree().root.add_child(bot)
	bot.begin(game, 773)
	for i in 1800:
		await get_tree().physics_frame
		if game.player.is_dead or (Run.room_index >= 1 and is_instance_valid(game.room) and game.room.get_instance_id() != first_room_id):
			break
	bot.stop()
	check(not game.player.is_dead, "бот выжил в бою с одним обычным врагом")
	check(Run.kills >= 1, "бот победил обычного врага (%d)" % Run.kills)
	check(bot.rooms.any(func(rm: Dictionary) -> bool: return rm.get("scene", "") == "fixture_room" and rm.get("cleared", false)), "зал зачищен штатной логикой")
	check(bot.picks.any(func(s: String) -> bool: return s.begins_with("rune:")), "бот выбрал настоящую награду")
	check(bot.picks.any(func(s: String) -> bool: return s.begins_with("door:")), "бот выбрал настоящую дверь")
	check(Run.room_index >= 1 and is_instance_valid(game.room) and game.room.get_instance_id() != first_room_id, "бот вошёл в следующий зал через триггер двери")
	bot.queue_free()
	_finish()

func _finish() -> void:
	print("=== ИТОГ: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
