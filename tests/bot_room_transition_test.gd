extends Node
## Учёт бота при реальном барьере смены зала: отсутствие Room не создаёт запись,
## обработка открытого UI при паузе сохраняется, новый зал фиксируется один раз.
## godot --headless --path . --fixed-fps 60 res://tests/bot_room_transition_test.tscn

const BotPlayer := preload("res://tests/bot/bot_player.gd")

var passes: int = 0
var fails: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.name = "BotRoomTransitionTestRunner"
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	if condition:
		passes += 1
		print("  [OK] ", description)
	else:
		fails.append(description)
		print("  [FAIL] ", description)

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func starts(bot: Node) -> Array:
	return bot.telemetry.events.filter(func(e: Dictionary) -> bool: return e.get("type", "") == "room_start")

func _run() -> void:
	print("=== BOT ROOM TRANSITION TEST ===")
	Dialogue.in_run_scenes = false
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", "res://rooms/room_02.tscn", "res://rooms/room_03.tscn"])
	Run.room_rewards.clear()
	Run.room_index = 0
	Run.miniboss_rooms.clear()
	Run.doors_enabled = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	var game: Game = null
	for i in 120:
		await get_tree().process_frame
		game = get_tree().current_scene as Game
		if is_instance_valid(game) and is_instance_valid(game.room):
			break
	if not is_instance_valid(game) or not is_instance_valid(game.room):
		check(false, "первый зал загружен")
		await _finish(null, game)
		return
	await frames(20) # прогрев первого зала завершился
	var bot := BotPlayer.new()
	bot.telemetry_enabled = true
	get_tree().root.add_child(bot)
	bot.begin(game, 831)
	# Тики вызываются вручную, чтобы проверять обе стадии удаления детерминированно.
	get_tree().physics_frame.disconnect(bot._tick)
	get_tree().paused = true
	bot._tick()
	check(bot.rooms.is_empty() and bot.cur_room.get("index", -1) == 0 and starts(bot).size() == 1,
		"первый настоящий зал начал одну запись")
	var original: Dictionary = bot.cur_room.duplicate(true)
	Run.kills += 2
	Run.glory += 7
	Run.silver_earned += 3
	var old_room: WeakRef = weakref(game.room)
	Run.room_index = 1
	game._load_room()
	check(game.room == null and game._room_load_active, "барьер действительно оставил Game без зала")
	bot._tick()
	check(old_room.get_ref() != null and bot.rooms.is_empty() and bot.cur_room == original and starts(bot).size() == 1,
		"пока старый зал жив, null не закрывает его и не создаёт новый")
	# Открытый UI по-прежнему обрабатывается при паузе, несмотря на отсутствие зала.
	game.rune_pick.visible = true
	bot._ui_wait = -100.0
	bot.hold("move_forward", true)
	bot._tick()
	check(not Input.is_action_pressed("move_forward") and game.rune_pick.visible and get_tree().paused,
		"пауза и обработка открытого UI сохраняются в промежутке")
	game.rune_pick.visible = false
	await frames(4)
	bot._tick()
	bot._tick()
	check(old_room.get_ref() == null and game.room == null and bot.rooms.is_empty()
		and bot.cur_room == original and starts(bot).size() == 1,
		"после освобождения старого зала повторные тики не добавляют фантомную запись")
	get_tree().paused = false
	var loaded := false
	for i in 120:
		await get_tree().process_frame
		if is_instance_valid(game.room):
			loaded = true
			break
	check(loaded and game.room.scene_file_path.ends_with("room_02.tscn"), "второй зал реально загрузился")
	if loaded:
		get_tree().paused = true
		bot._tick()
		bot._tick()
		check(bot.rooms.size() == 1 and bot.rooms[0].get("index", -1) == 0
			and bot.cur_room.get("index", -1) == 1 and starts(bot).size() == 2,
			"реальный второй зал закрывает первый и создаёт ровно одну запись и событие")
		check(int(bot.rooms[0].get("kills", -1)) == 2 and int(bot.rooms[0].get("glory", -1)) == 7
			and int(bot.rooms[0].get("silver", -1)) == 3, "счётчики старого зала сохранены")
		Run.room_index = 2
		game._load_room()
		bot._tick()
		bot.stop()
		bot.stop()
		check(bot.rooms.size() == 2 and bot.rooms[1].get("index", -1) == 1 and starts(bot).size() == 2,
			"остановка в следующем промежутке закрывает реальный зал один раз")
	await _finish(bot, game)

func _finish(bot: Node, game: Game) -> void:
	if is_instance_valid(bot):
		bot.queue_free()
	if is_instance_valid(game):
		game.queue_free()
	get_tree().paused = false
	FX.reset_time()
	await frames(50)
	print("=== ИТОГ BOT ROOM TRANSITION: %d OK, %d FAIL ===" % [passes, fails.size()])
	for failure in fails:
		print("  FAIL: ", failure)
	get_tree().quit(1 if not fails.is_empty() else 0)
