extends Node
## Отдельный профиль, реальный тайм-аут, сохранение через RunTracker и порядок покупок.
## godot --headless --path . --fixed-fps 60 res://tests/bot_progression_test.tscn

const BalanceRunner := preload("res://tests/bot/balance_runner.gd")

var passes := 0
var fails: Array[String] = []
var runner: Node
var done := false
var timed_results: Array = []

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

func _on_done(results: Array) -> void:
	timed_results = results
	done = true

func fake_unlock(id: String, price: int, order: int, available: bool = true, required: String = "") -> UnlockDef:
	var u := UnlockDef.new()
	u.id = id
	u.price = price
	u.order = order
	u.kind = "perk"
	u.target_id = "progression_test_" + id
	u.available = available
	u.requires = required
	return u

func open_game() -> Game:
	get_tree().paused = false
	FX.reset_time()
	Run.start_run("hunter")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	for i in 180:
		await get_tree().physics_frame
		var game := get_tree().current_scene as Game
		if game and game.is_node_ready() and game.room and game.tracker:
			game.room.set_physics_process(false)
			return game
	return null

func _run() -> void:
	print("=== BOT PROGRESSION TEST ===")
	Dialogue.in_run_scenes = false
	var output := ProjectSettings.globalize_path("user://progression_timeout.jsonl")
	runner = Node.new()
	runner.set_script(BalanceRunner)
	runner.set_meta("args", {"bodies": "hunter", "runs": 2, "seed": 17, "progression": 1,
		"time_cap": 0.05, "room_cap": 300, "max_rooms": 0, "out": output})
	runner.set_meta("on_done", _on_done)
	get_tree().root.add_child(runner)
	for i in 1800:
		await get_tree().physics_frame
		if done:
			break
	check(done and timed_results.size() == 1, "тайм-аут завершает серию до второго забега")
	if not done or timed_results.is_empty():
		_finish()
		return
	var result: Dictionary = timed_results[0]
	var progress: Dictionary = result.get("progression", {})
	check(str(result.outcome) == "timeout" and not bool(progress.get("completed", true))
		and bool(progress.get("rollback_saved", false)), "тайм-аут остаётся незавершённым и откат записан")
	check(int(result.get("death_room", 0)) == -1 and int(progress.get("glory_awarded", -1)) == 0,
		"тайм-аут не записан смертью и не начисляет славу")
	check(Save.runs() == 0 and Save.deaths() == 0 and Save.wins() == 0 and Save.glory_bank() == 0
		and int(Save.data.glory.earned) == 0 and int(Save.data.glory.spent) == 0
		and Save.data.unlocks.is_empty() and Save.data.purchases.is_empty(),
		"после тайм-аута банк, счётчики и покупки вернулись к чистому профилю")
	var memory_before := JSON.stringify(Save.data, "", true)
	# Как и в save_test: JSON читает все числа как float, а миграция возвращает
	# версию как int; сравниваем все значения без зависимости от этих типов.
	var snapshot: Dictionary = JSON.parse_string(memory_before)
	var version := int(Save.data.version)
	await get_tree().process_frame
	await get_tree().process_frame
	check(JSON.stringify(Save.data, "", true) == memory_before, "отложенные события не меняют откат в памяти")
	var loaded_ok := Save.load_game()
	var loaded: Dictionary = Save.data.duplicate(true)
	snapshot.erase("version")
	loaded.erase("version")
	var same_data := JSON.stringify(loaded, "", true) == JSON.stringify(snapshot, "", true)
	if not same_data:
		print("  до загрузки: ", JSON.stringify(snapshot, "", true))
		print("  из файла: ", JSON.stringify(loaded, "", true))
	check(loaded_ok and int(Save.data.version) == version and same_data,
		"после загрузки все данные совпадают со снимком отката")
	check(Save.runs() == 0 and Save.deaths() == 0 and Save.wins() == 0 and Save.glory_bank() == 0
		and int(Save.data.glory.earned) == 0 and int(Save.data.glory.spent) == 0
		and Save.data.unlocks.is_empty() and Save.data.purchases.is_empty(),
		"файл отката содержит прежний банк, счётчики и покупки")
	var f := FileAccess.open(output, FileAccess.READ)
	var row: Variant = JSON.parse_string(f.get_line()) if f else null
	check(row is Dictionary and row.get("outcome") == "timeout"
		and not bool(row.get("progression", {}).get("completed", true)) and f.get_position() == f.get_length(),
		"JSONL содержит отдельную незавершённую попытку, а не победу или смерть")

	# Дальше — контролируемые исходы, а не балансный прогон: начисления проходят
	# только через RunTracker.finish / Save.end_run, покупка — через Save.buy.
	var originals: Array[UnlockDef] = Save.all_unlocks.duplicate()
	var a := fake_unlock("a", 100, 1)
	var b := fake_unlock("b", 100, 1)
	var c := fake_unlock("c", 100, 2)
	var soon := fake_unlock("soon", 1, 0, false)
	var blocked := fake_unlock("blocked", 1, 0, true, "missing")
	Save.all_unlocks.assign([c, b, blocked, soon, a])
	Save.reset()
	Save.save_game()
	var before := Save.data.duplicate(true)
	var game := await open_game()
	if game == null:
		check(false, "контрольная игра загрузилась")
		Save.all_unlocks.assign(originals)
		_finish()
		return
	Run.add_glory(250)  # Стендовый источник, а не ручное изменение банка.
	game.player.body_handlers.clear()
	game.player.take_damage(9999.0, Vector3.ZERO, true)
	check(game.player.is_dead and Save.deaths() == 1 and Save.glory_bank() == 250,
		"настоящая смерть вызывает штатное начисление в Save")
	game.tracker.finish(false)
	check(Save.deaths() == 1 and Save.glory_bank() == 250, "повтор finish не начисляет славу и смерть второй раз")
	var death_row := {"body": "hunter", "outcome": "death"}
	var reason: String = runner._record_progression(death_row, before)
	var ledger: Dictionary = death_row.get("progression", {})
	var purchases: Array = ledger.get("purchases", [])
	check(reason == "" and purchases.size() == 2 and purchases[0].id == "a" and purchases[1].id == "b"
		and Save.glory_bank() == 50 and int(Save.data.glory.spent) == 200,
		"покупаются доступные открытия по цене, порядку и id; закрытые не покупаются")
	check(int(ledger.get("glory_awarded", -1)) == 250 and int(ledger.get("bank_before", -1)) == 0
		and int(ledger.get("bank_after_award", -1)) == 250 and int(ledger.get("bank_after", -1)) == 50,
		"журнал показывает реальное начисление, траты и остаток")

	before = Save.data.duplicate(true)
	game = await open_game()
	if game == null:
		check(false, "вторая контрольная игра загрузилась")
		Save.all_unlocks.assign(originals)
		_finish()
		return
	Run.add_glory(125)
	game.tracker.finish(true)  # Контролируем победный путь; сам босс здесь не подменяется.
	game.tracker.finish(true)
	var win_row := {"body": "hunter", "outcome": "win"}
	reason = runner._record_progression(win_row, before)
	ledger = win_row.get("progression", {})
	purchases = ledger.get("purchases", [])
	check(reason == "" and Save.runs() == 2 and Save.wins() == 1 and Save.deaths() == 1
		and int(ledger.get("glory_awarded", -1)) == 125 and purchases.size() == 1
		and purchases[0].id == "c" and Save.glory_bank() == 75,
		"следующий забег сохраняет прогрессию, победа учитывается один раз")
	Save.all_unlocks.assign(originals)
	_finish()

func _finish() -> void:
	print("=== ИТОГ BOT PROGRESSION: %d OK, %d FAIL ===" % [passes, fails.size()])
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(1 if not fails.is_empty() else 0)
