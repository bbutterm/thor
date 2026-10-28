extends Node
## Бот-плейтест Мидгарда (блок Б5): каждое тело × N забегов, бот играет сам (tests/bot/bot_player.gd).
## Запуск (не входит в обычный набор *_test):
##   godot --headless --path . --fixed-fps 60 res://tests/balance_run.tscn -- bodies=berserker,hunter runs=5 seed=1 out=/tmp/b.jsonl
## Аргументы: bodies (через запятую; пусто — все тела), runs, seed, out (JSON Lines — строка на забег),
## time_cap (с игрового времени на забег), room_cap (с на зал), max_rooms (остановиться после стольких залов — bot_test),
## trace=1 (событийная телеметрия в JSONL, по умолчанию выключена).
## progression=1 — один открытый персонаж, чистый тестовый профиль и покупки после каждого завершённого забега.
## Отчёт по файлам: python3 tests/bot/balance_report.py <out.jsonl> … (docs/balance_<дата>.md).

const BotPlayer := preload("res://tests/bot/bot_player.gd")

var args := {"bodies": "", "runs": "5", "seed": "1", "out": "", "time_cap": "1800", "room_cap": "300", "max_rooms": "0", "profile": "skilled", "trace": "0", "progression": "0"}
var bot: Node
var results: Array = []
var errors: int = 0
const PROGRESSION_SAVE := "user://balance_progression.json"
## Для bot_test: колбэк по итогу (Array результатов)
var on_done: Callable

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner") and not has_meta("args"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "BalanceRunner"
		get_tree().root.add_child.call_deferred(runner)
		return
	if has_meta("args"):
		# Запуск из теста (tests/bot_test.gd): аргументы и колбэк заданы до add_child
		var a: Dictionary = get_meta("args")
		for k in a:
			args[k] = str(a[k])
		if has_meta("on_done"):
			on_done = get_meta("on_done")
	else:
		for a in OS.get_cmdline_user_args():
			var kv := a.split("=", true, 1)
			if kv.size() == 2:
				args[kv[0]] = kv[1]
	_run.call_deferred()

func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().physics_frame

func _bodies() -> Array[String]:
	var out: Array[String] = []
	if str(args.bodies) != "":
		for b in str(args.bodies).split(",", false):
			out.append(b.strip_edges())
		return out
	var ids: Array = Run.all_bodies.map(func(b: BodyDef) -> String: return b.id)
	ids.sort()
	out.assign(ids)
	return out

func _run() -> void:
	bot = BotPlayer.new()
	bot.name = "Bot"
	add_child(bot)
	bot.set_profile(str(args.profile))
	bot.telemetry_enabled = str(args.trace) == "1"
	var runs := int(args.runs)
	var base_seed := int(args.seed)
	var bodies := _bodies()
	var progression := str(args.progression) == "1"
	var known: Array = Run.all_bodies.map(func(b: BodyDef) -> String: return b.id)
	if runs <= 0 or bodies.is_empty() or not str(args.profile) in BotPlayer.PROFILES or not str(args.trace) in ["0", "1"] or not str(args.progression) in ["0", "1"] or bodies.any(func(b: String) -> bool: return not b in known):
		push_error("balance: неверный профиль, число забегов или тело")
		errors += 1
		if progression:
			Save.data.clear()
		if on_done.is_valid():
			on_done.call([])
		else:
			_finish()
		return
	if progression:
		var setup_error := _prepare_progression(bodies)
		if setup_error != "":
			print("balance progression: ", setup_error)
			errors += 1
			# _exit_tree у Save сам пишет файл: не затереть чужой профиль при отказе.
			Save.data.clear()
			if on_done.is_valid():
				on_done.call([])
			else:
				_finish()
			return
	print("=== BALANCE RUN: %s × %d (seed %d) ===" % [", ".join(bodies), runs, base_seed])
	var t0 := Time.get_ticks_msec()
	for body in bodies:
		for r in runs:
			var before: Dictionary = Save.data.duplicate(true) if progression else {}
			var s := base_seed * 1000 + _hash(body) % 997 * 7 + r
			var res: Dictionary = await play_one(body, r, s)
			var incomplete := false
			if progression:
				var reason := ""
				if res.outcome in ["death", "win"]:
					reason = _record_progression(res, before)
				else:
					reason = "незавершённый забег: " + str(res.outcome)
				if reason != "":
					var observed := str(res.outcome)
					var restored := await _rollback_progression(before)
					res["progression"] = {"completed": false, "failure": reason, "rollback_saved": restored,
						"bank_before": int(before.glory.bank), "glory_awarded": 0,
						"bank_after": Save.glory_bank(), "purchases": []}
					if observed in ["death", "win"]:
						res["observed_outcome"] = observed
						res["outcome"] = "error"
					print("balance progression: ", reason, "; сохранение восстановлено: ", restored)
					errors += 1
					incomplete = true
			results.append(res)
			if res.outcome == "error" and not incomplete:
				errors += 1
			var prior_errors := errors
			_append(res)
			print("  %s #%d: %s, зал %d, %.0f с, Слава %d, убито %d, урон %.0f, подсадок %d  [%.0f с реальных]" % [body, r + 1,
				res.outcome, res.rooms_reached, res.time, res.glory, res.kills, res.dmg_total, res.stats.assists,
				(Time.get_ticks_msec() - t0) / 1000.0])
			if progression and errors > prior_errors and not incomplete:
				# Без журнала нельзя продолжать серию с покупками, которые нельзя проверить.
				var observed := str(res.outcome)
				var restored := await _rollback_progression(before)
				res["observed_outcome"] = observed
				res["outcome"] = "error"
				res["progression"] = {"completed": false, "failure": "ошибка записи журнала",
					"rollback_saved": restored, "bank_before": int(before.glory.bank),
					"glory_awarded": 0, "bank_after": Save.glory_bank(), "purchases": []}
				incomplete = true
			if incomplete:
				break
	if progression:
		var completed := results.filter(func(row: Dictionary) -> bool: return bool(row.get("progression", {}).get("completed", false))).size()
		print("=== ИТОГ PROGRESSION: %d завершено, %d незавершено, %.0f с реальных ===" % [completed, results.size() - completed, (Time.get_ticks_msec() - t0) / 1000.0])
	else:
		print("=== ИТОГ BALANCE: %d забегов, %.0f с реальных ===" % [results.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	if on_done.is_valid():
		on_done.call(results)
		return
	_finish()

static func _hash(s: String) -> int:
	var h := 0
	for c in s.to_utf8_buffer():
		h = (h * 31 + c) % 1000003
	return h

## Серия прогрессии всегда начинается с нуля и не перезаписывает существующие файлы.
func _prepare_progression(bodies: Array[String]) -> String:
	GameSettings.ensure_loaded()
	var out := str(args.out)
	if bodies.size() != 1 or int(args.max_rooms) != 0 or not str(args.seed).is_valid_int() \
			or int(args.seed) < 0 or not str(args.time_cap).is_valid_float() or float(args.time_cap) <= 0.0 \
			or not str(args.room_cap).is_valid_float() or float(args.room_cap) <= 0.0:
		return "нужно одно тело, max_rooms=0, неотрицательный seed и положительные лимиты"
	if not out.is_absolute_path() or out.begins_with("res://") or FileAccess.file_exists(out) \
			or not DirAccess.dir_exists_absolute(out.get_base_dir()):
		return "нужен новый абсолютный путь журнала в существующем каталоге"
	if not Save.is_test or Save.path != Save.TEST_PATH or GameSettings.path != GameSettings.TEST_PATH \
			or FileAccess.file_exists(Save.TEST_PATH) or FileAccess.file_exists(PROGRESSION_SAVE) \
			or FileAccess.file_exists(GameSettings.TEST_PATH):
		return "нужен отдельный чистый XDG_DATA_HOME с тестовым сохранением и настройками"
	Save.use_path(PROGRESSION_SAVE, true)
	if not Save.is_in_pool("body", bodies[0]):
		return "выбранное тело закрыто в новом профиле"
	if not Save.save_game():
		return "не удалось создать тестовое сохранение"
	return ""

## Покупаем только разрешённые игрой открытия, в стабильном порядке: цена, порядок, id.
func _affordable_unlocks() -> Array[UnlockDef]:
	var choices: Array[UnlockDef] = []
	for u in Save.all_unlocks:
		if Save.buy_block_reason(u.id) == "":
			choices.append(u)
	choices.sort_custom(func(a: UnlockDef, b: UnlockDef) -> bool:
		if a.price != b.price:
			return a.price < b.price
		if a.order != b.order:
			return a.order < b.order
		return a.id < b.id)
	return choices

## Начисление делает только tracker.finish → Save.end_run, здесь мы его проверяем.
func _record_progression(res: Dictionary, before: Dictionary) -> String:
	var saved: Dictionary = Save.data.get("last_run", {})
	var won := str(res.outcome) == "win"
	var awarded := int(saved.get("glory", -1))
	var previous_bank := int(before.glory.bank)
	if awarded < 0 or bool(saved.get("won", not won)) != won or str(saved.get("body", "")) != str(res.body):
		return "сохранённый результат не соответствует настоящему исходу"
	if Save.runs() != int(before.stats.runs) + 1 \
			or Save.wins() != int(before.stats.wins) + (1 if won else 0) \
			or Save.deaths() != int(before.stats.deaths) + (0 if won else 1):
		return "неверное число завершений в сохранении"
	if Save.glory_bank() != previous_bank + awarded \
			or int(Save.data.glory.earned) != int(before.glory.earned) + awarded \
			or int(Save.data.glory.spent) != int(before.glory.spent) \
			or Save.data.unlocks != before.unlocks or Save.data.purchases != before.purchases:
		return "начисление записано неверно или повторно"
	var after_award := Save.glory_bank()
	var purchases: Array[Dictionary] = []
	while true:
		var choices := _affordable_unlocks()
		if choices.is_empty():
			break
		var u := choices[0]
		var bank_before := Save.glory_bank()
		var spent_before := int(Save.data.glory.spent)
		var reason := Save.buy(u.id)
		if reason != "" or Save.glory_bank() != bank_before - u.price \
				or int(Save.data.glory.spent) != spent_before + u.price or not Save.is_unlocked(u.id):
			return "ошибка покупки %s: %s" % [u.id, reason]
		purchases.append({"id": u.id, "price": u.price, "bank_before": bank_before, "bank_after": Save.glory_bank()})
	if not Save.save_game():
		return "не удалось сохранить покупки"
	res["progression"] = {
		"completed": true, "completed_run": Save.runs(),
		"bank_before": previous_bank, "glory_awarded": awarded, "bank_after_award": after_award,
		"purchases": purchases, "bank_after": Save.glory_bank(),
		"earned_total": int(Save.data.glory.earned), "spent_total": int(Save.data.glory.spent),
		"wins": Save.wins(), "deaths": Save.deaths(),
	}
	return ""

## Таймеры и PROCESS_MODE_ALWAYS-потомки не должны завершить забег после тайм-аута.
func _disable_subtree(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	for child in node.get_children(true):
		_disable_subtree(child)

func _rollback_progression(before: Dictionary) -> bool:
	get_tree().paused = true
	bot.stop()
	var game := get_tree().current_scene as Game
	if is_instance_valid(game):
		_disable_subtree(game)
		game.queue_free()
	# queue_free завершается в конце кадра; только затем восстанавливаем снимок.
	await get_tree().process_frame
	await get_tree().process_frame
	Save.data = before.duplicate(true)
	Save.changed.emit()
	return Save.save_game()

## Один забег телом body. Возвращает итог (словарь — строка JSON Lines).
func play_one(body: String, run_no: int, seed_value: int) -> Dictionary:
	get_tree().paused = false
	FX.reset_time()
	seed(seed_value)
	Run.start_run(body)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	var game: Game = null
	for i in 120:
		await get_tree().physics_frame
		game = get_tree().current_scene as Game
		if game and game.is_node_ready() and game.room:
			break
	if game == null or not game.is_node_ready() or game.room == null:
		push_error("balance: сцена игры не загрузилась")
		return {"body": body, "run": run_no, "seed": seed_value, "profile": str(args.profile), "outcome": "error", "rooms_reached": 0, "time": 0.0, "glory": 0, "kills": 0,
			"dmg_total": 0.0, "stats": {"assists": 0}}
	bot.begin(game, seed_value)
	var outcome := ""
	var time_cap := float(args.time_cap)
	var room_cap := float(args.room_cap)
	var max_rooms := int(args.max_rooms)
	var room_t := 0.0
	var last_room := -1
	while outcome == "":
		await get_tree().physics_frame
		if not is_instance_valid(game):
			outcome = "error"
			break
		var p := game.player
		if Run.room_index != last_room:
			last_room = Run.room_index
			room_t = 0.0
		if not get_tree().paused:
			room_t += get_physics_process_delta_time()
		if p.is_dead:
			outcome = "death"
		elif Run.won:
			outcome = "win"
		elif game.tracker.run_time > time_cap:
			outcome = "timeout"
		elif room_t > room_cap:
			outcome = "room_timeout"
		elif max_rooms > 0 and Run.room_index >= max_rooms:
			outcome = "stopped"
	if str(args.progression) == "1":
		# Смерть уже вызывает finish(false); победа ждёт экрана результата и часто
		# не успевает сохраниться до следующей сцены. finish защищён от повтора.
		if is_instance_valid(game) and outcome in ["death", "win"]:
			game.tracker.finish(outcome == "win")
		get_tree().paused = true
		if is_instance_valid(game):
			_disable_subtree(game)
	else:
		await wait(0.2)
	bot._flush_glory()
	bot.stop()
	var tr_res: Dictionary = game.tracker.result(outcome == "win") if is_instance_valid(game) else {}
	var rooms: Array = bot.rooms.duplicate(true)
	var dmg := 0.0
	for rm in rooms:
		dmg += float(rm.get("dmg", 0.0))
	var last: Dictionary = rooms[rooms.size() - 1] if not rooms.is_empty() else {}
	var res := {
		"body": body, "run": run_no, "seed": seed_value, "outcome": outcome,
		"time": float(tr_res.get("time", 0.0)),
		"rooms_reached": Run.room_index + 1,
		"total_rooms": Run.total_rooms(),
		"death_room": Run.room_index if outcome != "win" else -1,
		"death_scene": str(last.get("scene", "")) if outcome != "win" else "",
		"death_reward": str(last.get("reward", "")) if outcome != "win" else "",
		"cause": str(tr_res.get("killed_by", "")) if outcome == "death" else outcome,
		"kills": Run.kills, "glory": Run.glory, "silver": Run.silver_earned, "best_streak": Run.best_streak,
		"glory_mult_body": Run.body.glory_mult if Run.body else 1.0,
		"dmg_total": dmg,
		"rank_time": Array(bot.rank_time),
		"picks": bot.picks.duplicate(),
		"stats": bot.stats.duplicate(),
		"glory_src": bot.glory_src.duplicate(),
		"profile": str(args.profile),
		"runes": Run.runes.map(func(r: RuneDef) -> String: return r.id),
		"traits": Run.mjolnir_traits.map(func(t: MjolnirTrait) -> String: return str(t.id)),
		"rooms": rooms,
	}
	if bot.telemetry_enabled and is_instance_valid(bot.telemetry):
		res["telemetry"] = bot.telemetry.result()
	if str(args.progression) == "1" and not outcome in ["death", "win"]:
		res["death_room"] = -1
		res["death_scene"] = ""
		res["death_reward"] = ""
	return res

func _append(res: Dictionary) -> void:
	var path := str(args.out)
	if path == "":
		return
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		errors += 1
		push_error("balance: не открыть %s" % path)
		return
	f.store_line(JSON.stringify(res))
	if str(args.progression) == "1":
		f.flush()
		if f.get_error() != OK:
			errors += 1
			push_error("balance: ошибка записи %s" % path)
	f.close()

func _finish() -> void:
	bot.stop()
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(1 if errors > 0 else 0)
