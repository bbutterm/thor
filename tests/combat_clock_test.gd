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
	_test_horde_glory()
	FX.reset_time()
	print("=== ИТОГ COMBAT CLOCK: %d OK, %d FAIL ===" % [passes, fails.size()])
	get_tree().quit(1 if not fails.is_empty() else 0)

func _test_horde_glory() -> void:
	print("-- Слава за корм и смешанную серию")
	Run.start_run("berserker")
	Run.glory_fodder_multikill = false
	Run.glory_fodder_flat = true
	var signals_seen := [0]
	var listener := func(_source: String) -> void: signals_seen[0] += 1
	Run.kill_registered.connect(listener)
	for i in 20:
		Run.register_kill(false, false, false, "melee", 1, true)
	check(Run.glory == 40 and Run.kills == 20 and Run.streak == 20 and Run._recent_kill_times.is_empty(),
		"20 корма: 20 базовых + 20 серия = %d; корм не в денежной истории" % Run.glory)
	var payouts: Array[int] = []
	for i in 5:
		var before := Run.glory
		Run.register_kill(false, false, false, "melee", 3)
		payouts.append(Run.glory - before)
	check(payouts == [5, 6, 7, 8, 9] and Run.glory == 75 and Run._recent_kill_times.size() == 5,
		"после корма бойцы получают 5+6+7+8+9, всего %d" % Run.glory)
	check(signals_seen[0] == 25, "сигнал убийства для шкалы и реплик получен для всех 25 врагов")
	var g := Run.glory
	Run.register_kill(false, false, false, "melee", 5)
	check(Run.glory - g == 13, "особый после бойцов: 8 базовых + 5 мультикилл")
	# Серия одних бойцов даёт прежний бонус; корм после неё тоже не получает денежный бонус.
	Run.start_run("berserker")
	for i in 5:
		Run.register_kill(false, false, false, "melee", 3)
	check(Run.glory == 35 and Run._recent_kill_times.size() == 5, "пять бойцов без корма: прежние 35 Славы")
	g = Run.glory
	Run.register_kill(false, false, false, "melee", 1, true)
	check(Run.glory - g == 1 and Run._recent_kill_times.size() == 5,
		"корм после бойцов не получает и не продлевает денежный мультикилл")
	# Настройки денежного мультикилла и множителей независимы.
	Run.start_run("berserker")
	Run.glory_fodder_multikill = true
	Run.register_kill(false, false, false, "melee", 1, true)
	Run.register_kill(false, false, false, "melee", 1, true)
	check(Run.glory == 3 and Run._recent_kill_times.size() == 2, "мультикилл можно включить при фиксированной награде корма")
	Run.start_run("berserker")
	Run.glory_fodder_flat = false
	Run.register_kill(false, false, false, "melee", 1, true)
	Run.register_kill(false, false, false, "melee", 1, true)
	check(Run.glory == 5 and Run._recent_kill_times.size() == 2, "настройка возвращает прежний бонус корма")
	Run.glory_fodder_multikill = false
	Run.glory_fodder_flat = true
	Run.start_run("berserker")
	Run.style_glory_mult = 1.6
	Run.register_kill(false, false, false, "melee", 1, true)
	check(Run.glory == 1, "ранг и мили не увеличивают базовую Славу корма")
	Run.register_kill(false, true, false, "melee", 1, true)
	check(Run.glory == 3, "бонус шмяка о стену сохраняется")
	Run.start_run("thrall")
	Run.register_kill(false, false, false, "melee", 1, true)
	check(Run.glory == 2, "множитель тела сохраняется для корма")
	Run.kill_registered.disconnect(listener)
