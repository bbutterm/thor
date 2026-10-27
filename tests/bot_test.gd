extends Node
## Короткая проверка бота-плейтестера (блок Б5): одно тело, один забег, первые залы — бот играет без ошибок.
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/bot_test.tscn
## Полный прогон баланса — tests/balance_run.tscn (не входит в обычный набор, см. CLAUDE.md).

const BalanceRunner := preload("res://tests/bot/balance_runner.gd")

var _fails: Array[String] = []
var _passes: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		# Сцена теста заменится сценой игры — работаем из корня дерева
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
	# 3 зала (до мини-босса), 4 минуты игрового времени максимум
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
	check(results.size() == 1, "один забег сыгран")
	if results.is_empty():
		_finish()
		return
	var r: Dictionary = results[0]
	print("  итог: %s, зал %d, %.0f с, Слава %d, убито %d, урон %.0f" % [r.outcome, r.rooms_reached, r.time, r.glory, r.kills, r.dmg_total])
	check(r.outcome in ["stopped", "death", "win"], "забег закончился штатно (%s)" % r.outcome)
	check(int(r.kills) > 0, "бот убивает врагов (%d)" % int(r.kills))
	var rooms: Array = r.rooms
	var cleared := rooms.filter(func(rm: Dictionary) -> bool: return rm.get("cleared", false))
	check(not cleared.is_empty(), "зачищен хотя бы один зал (%d)" % cleared.size())
	if r.outcome == "stopped":
		check(int(r.rooms_reached) >= 4, "бот прошёл двери до 4-го зала (%d)" % int(r.rooms_reached))
	var picks: Array = r.picks
	check(picks.any(func(s: String) -> bool: return s.begins_with("door:")), "выбрана дверь")
	check(picks.any(func(s: String) -> bool: return s.begins_with("rune:") or s.begins_with("trait:") or s.begins_with("choice:") or s.begins_with("shop:")),
		"взята награда (%s)" % ", ".join(picks))
	var stats: Dictionary = r.stats
	check(int(stats.get("throws", 0)) > 0, "бросал Мьёльнир (%d)" % int(stats.get("throws", 0)))
	check(float(r.time) > 5.0, "время забега считается (%.0f с)" % float(r.time))
	var ranks := 0.0
	for x in r.rank_time:
		ranks += float(x)
	check(ranks > 0.0, "шкала стиля записана")
	check(not get_tree().paused, "игра не на паузе")
	_finish()

func _finish() -> void:
	print("=== ИТОГ: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
