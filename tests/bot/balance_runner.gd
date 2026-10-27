extends Node
## Бот-плейтест Мидгарда (блок Б5): каждое тело × N забегов, бот играет сам (tests/bot/bot_player.gd).
## Запуск (не входит в обычный набор *_test):
##   godot --headless --path . --fixed-fps 60 res://tests/balance_run.tscn -- bodies=berserker,hunter runs=5 seed=1 out=/tmp/b.jsonl
## Аргументы: bodies (через запятую; пусто — все тела), runs, seed, out (JSON Lines — строка на забег),
## time_cap (с игрового времени на забег), room_cap (с на зал), max_rooms (остановиться после стольких залов — bot_test).
## Отчёт по файлам: python3 tests/bot/balance_report.py <out.jsonl> … (docs/balance_<дата>.md).

const BotPlayer := preload("res://tests/bot/bot_player.gd")

var args := {"bodies": "", "runs": "5", "seed": "1", "out": "", "time_cap": "1800", "room_cap": "300", "max_rooms": "0", "profile": "skilled"}
var bot: Node
var results: Array = []
var errors: int = 0
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
	var runs := int(args.runs)
	var base_seed := int(args.seed)
	var bodies := _bodies()
	print("=== BALANCE RUN: %s × %d (seed %d) ===" % [", ".join(bodies), runs, base_seed])
	var t0 := Time.get_ticks_msec()
	for body in bodies:
		for r in runs:
			var s := base_seed * 1000 + _hash(body) % 997 * 7 + r
			var res: Dictionary = await play_one(body, r, s)
			results.append(res)
			_append(res)
			print("  %s #%d: %s, зал %d, %.0f с, Слава %d, убито %d, урон %.0f, подсадок %d  [%.0f с реальных]" % [body, r + 1,
				res.outcome, res.rooms_reached, res.time, res.glory, res.kills, res.dmg_total, res.stats.assists,
				(Time.get_ticks_msec() - t0) / 1000.0])
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
	if game == null:
		push_error("balance: сцена игры не загрузилась")
		return {"body": body, "run": run_no, "outcome": "error", "rooms_reached": 0, "time": 0.0, "glory": 0, "kills": 0,
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
			room_t += 1.0 / 60.0
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
		push_error("balance: не открыть %s" % path)
		return
	f.store_line(JSON.stringify(res))
	f.close()

func _finish() -> void:
	bot.stop()
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0)
