extends Node
## Окна Славы и недавнего удара в обычном режиме, hit-stop и паузе.
var passes := 0
var fails: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	if ok:
		passes += 1
		print("  [OK] ", text)
	else:
		fails.append(text)
		print("  [FAIL] ", text)

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func kill() -> void:
	Run.register_kill(false, false, false, "", 0)

func _run() -> void:
	print("=== COMBAT CLOCK TEST ===")
	Run.start_run("berserker")
	FX.reset_time()
	Run.glory_multikill_bonus = 1
	Run.multikill_window = 0.6
	kill()
	kill()
	check(Run.glory == 1 and Run._recent_kill_times.size() == 2, "быстрые убийства дают бонус мультикилла")
	await frames(50)
	var g := Run.glory
	kill()
	check(Run.glory == g and Run._recent_kill_times.size() == 1, "убийство после окна не даёт мультикилл при ускоренном прогоне")
	# Удар замедляет игру, но первоначальное окно было в реальных секундах, как и сам hit-stop.
	var start := Run.combat_clock
	FX.hitstop(0.35, 0.05)
	await frames(50)
	var elapsed := Run.combat_clock - start
	check(elapsed > 0.7 and elapsed < 1.0 and FX._hitstop_left <= 0.0,
		"хит-стоп учитывает реальную длительность кадров (%.2f с)" % elapsed)
	g = Run.glory
	kill()
	check(Run.glory == g and Run._recent_kill_times.size() == 1, "хит-стоп не продлевает реальное окно мультикилла")
	get_tree().paused = true
	start = Run.combat_clock
	await frames(50)
	get_tree().paused = false
	check(Run.combat_clock - start > 0.7, "часы идут на паузе, сохраняя прежнее правило")
	g = Run.glory
	kill()
	check(Run.glory == g, "за время паузы прежнее окно мультикилла истекло")
	FX.reset_time()
	print("=== ИТОГ COMBAT CLOCK: %d OK, %d FAIL ===" % [passes, fails.size()])
	get_tree().quit(1 if not fails.is_empty() else 0)
