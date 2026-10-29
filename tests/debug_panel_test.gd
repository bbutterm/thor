extends Node
## Debug-панель баланса (П8, DEBUG_PANEL.md): F1 открывает/закрывает, без available() панели нет; значение сразу у живого
## MjolnirHand; «ХП мобов ×0.5» для новых и (с галочкой) живых; сохранить → сбросить → загрузить; файл при старте и кривые ключи;
## пауза F2 останавливает игру, панель работает; скорость времени умножает хит-стоп, а не перезаписывает.
## godot --headless --path . --fixed-fps 60 res://tests/debug_panel_test.tscn

var _fails: Array[String] = []
var _passes: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "DebugPanelRunner"
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

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await frames(2)
	var u := e.duplicate() as InputEventKey
	u.pressed = false
	Input.parse_input_event(u)
	await frames(1)

func _run() -> void:
	print("=== DEBUG PANEL TEST ===")
	check(DebugPanel.available() == QuickCheck.available() and DebugPanel.available(), "панель доступна там же, где «Быстрая проверка» (отладка)")
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_02.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(90)
	var game := get_tree().current_scene as Game
	if game == null or game.player == null:
		check(false, "сцена игры загрузилась")
		_finish()
		return
	game.room.set_physics_process(false)
	var p := game.player
	var hand := p.mjolnir
	check(DebugPanel.source(&"player") == p and DebugPanel.source(&"mjolnir") == hand and DebugPanel.source(&"room") == game.room
		and DebugPanel.source(&"style") != null and DebugPanel.source(&"economy") != null, "источники зарегистрированы: игрок, молот, зал, стиль, экономика")
	check(p.style.tuning.resource_path == "", "числа стиля — копия в памяти, .tres не трогаем")

	# Без доступа (релиз) F1 ничего не делает
	DebugPanel.force_off = true
	await _key(KEY_F1)
	check(not DebugPanel.is_open() and get_tree().root.get_node_or_null("DebugPanelUI") == null, "в релизном режиме F1 — панели нет")
	DebugPanel.force_off = false
	# F1 — открыть/закрыть, ввод Тора выключен, пока открыта
	await _key(KEY_F1)
	check(DebugPanel.is_open() and not p.input_enabled and not get_tree().paused, "F1: панель открыта, Тор не слушает ввод, игра идёт")
	var ui := get_tree().root.get_node_or_null("DebugPanelUI") as DebugPanelUI
	check(ui != null and ui.visible and ui._row_widgets.has("mjolnir.perfect_window"), "вкладка «Мьёльнир» со строкой окна хвата")

	# Значение сразу у живого MjolnirHand
	var pw0 := hand.perfect_window
	DebugPanel.set_value("mjolnir.perfect_window", 0.3)
	check(is_equal_approx(hand.perfect_window, 0.3) and DebugPanel.overrides.has("mjolnir.perfect_window"), "окно хвата 0.3 — сразу у молота")
	check(is_equal_approx(float(DebugPanel.default_of("mjolnir.perfect_window")), pw0), "умолчание запомнено (%.2f)" % pw0)
	check(DebugPanel.changes_in("mjolnir") == 1, "на вкладке счётчик изменений: 1")
	(ui._row_widgets["mjolnir.perfect_window"].slider as HSlider).value = 0.25
	check(is_equal_approx(hand.perfect_window, 0.25), "ползунок меняет значение")

	# ХП мобов ×0.5: новые враги и живые
	DebugPanel.set_value("enemy_mult.apply_to_live", false)
	var live := game.room.spawn_extra("grunt", p.global_position + Vector3(0, 0, -8))
	await frames(2)
	var live_hp := live.max_health if live else 0.0
	DebugPanel.set_value("enemy_mult.hp", 0.5)
	check(live and is_equal_approx(live.max_health, live_hp), "без «к живым» — живой враг не меняется")
	var fresh := game.room.spawn_extra("grunt", p.global_position + Vector3(2, 0, -8))
	await frames(2)
	check(fresh and is_equal_approx(fresh.max_health, live_hp * 0.5), "новый враг — половина ХП (%.0f из %.0f)" % [fresh.max_health if fresh else 0.0, live_hp])
	DebugPanel.set_value("enemy_mult.apply_to_live", true)
	DebugPanel.set_value("enemy_mult.hp", 0.25)
	check(live and is_equal_approx(live.max_health, live_hp * 0.25) and fresh and is_equal_approx(fresh.max_health, live_hp * 0.25),
		"с «Применить и к живым» — живые пересчитаны (%.0f)" % (live.max_health if live else 0.0))
	DebugPanel.set_value("enemy_mult.damage", 2.0)
	var hitter := game.room.spawn_extra("grunt", p.global_position + Vector3(-2, 0, -8))
	await frames(2)
	check(hitter and is_equal_approx(hitter.attack_damage, live.attack_damage * 2.0), "урон мобов ×2 у новых")

	# Сохранить → сбросить → загрузить: в JSON только изменённое
	DebugPanel.note = "тест"
	check(DebugPanel.save_file(), "сохранено в %s" % DebugPanel.FILE)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DebugPanel.FILE))
	var vals: Dictionary = data.get("values", {})
	check(vals.size() == DebugPanel.overrides.size() and vals.has("mjolnir.perfect_window") and not vals.has("mjolnir.throw_speed")
		and int(data.version) == 1 and str(data.note) == "тест", "в файле только изменённое (%d), версия и заметка" % vals.size())
	DebugPanel.reset_all()
	check(DebugPanel.overrides.is_empty() and is_equal_approx(hand.perfect_window, pw0) and is_equal_approx(DebugBalance.enemy.hp, 1.0), "«Сбросить всё» — значения из кода")
	var n := DebugPanel.load_file()
	check(n == vals.size() and is_equal_approx(hand.perfect_window, 0.25) and is_equal_approx(DebugBalance.enemy.hp, 0.25), "загрузка вернула значения (%d)" % n)

	# Пресет и кривой ключ: не падаем, пропускаем
	var bad := DebugPanel.DIR + "balance_bad.json"
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "values": {"mjolnir.catch_cooldown": 0.5, "nonsense.x": 3, "mjolnir": 1, "room.spawn_batch": "много"}}))
	f.close()
	check(DebugPanel.presets().has("balance_bad.json"), "пресеты видны в списке")
	n = DebugPanel.load_file(bad)
	check(n == 1 and is_equal_approx(hand.catch_cooldown, 0.5), "кривые ключи пропущены, верный применён")

	# Новый зал/игрок подхватывает значения при регистрации (как при старте игры с balance.json)
	DebugPanel.reset_all()
	DebugPanel.set_value("room.spawn_batch", 5)
	DebugPanel.set_value("player.move_speed", 11.0)
	var room2 := (load("res://rooms/room_03.tscn") as PackedScene).instantiate() as Room
	add_child(room2)
	check(room2.spawn_batch == 5, "новый зал получил «Врагов за раз» 5")
	room2.queue_free()
	DebugPanel.register(&"room", game.room)
	p.recalc_from_runes(Run)
	check(is_equal_approx(p.move_speed, 11.0), "пересчёт рун не сбрасывает значение панели")

	# «Все параметры»: собираются из @export сами
	ui._select_tab(DebugPanelUI.ALL_TAB)
	check(ui._row_widgets.has("player.dash_speed") and ui._row_widgets.has("room.max_projectiles") and ui._row_widgets.has("style.berserk_time"),
		"«Все параметры»: @export игрока, зала и стиля (%d строк)" % ui._row_widgets.size())
	ui._search.text = "hitstop"
	ui._build_rows()
	check(not ui._row_widgets.is_empty() and ui._row_widgets.keys().all(func(k: String) -> bool: return k.to_lower().contains("hitstop")), "поиск фильтрует строки")
	ui._search.text = ""
	ui._select_tab("mjolnir")

	# Пауза F2: игра стоит, панель работает; скорость времени умножает
	await _key(KEY_F2)
	check(get_tree().paused, "F2 — пауза")
	DebugPanel.set_value("mjolnir.throw_speed", 60.0)
	check(is_equal_approx(hand.throw_speed, 60.0), "на паузе значения меняются")
	await _key(KEY_F2)
	check(not get_tree().paused, "F2 ещё раз — дальше")
	DebugPanel.set_time_mult(0.5)
	check(is_equal_approx(Engine.time_scale, 0.5), "скорость времени ×0.5")
	FX.hitstop(0.05)
	await frames(1)
	check(Engine.time_scale < 0.5 and Engine.time_scale > 0.0, "хит-стоп работает поверх (%.3f)" % Engine.time_scale)
	FX.reset_time()
	check(is_equal_approx(Engine.time_scale, 0.5), "после хит-стопа — снова ×0.5")
	DebugPanel.set_time_mult(1.0)
	check(is_equal_approx(Engine.time_scale, 1.0), "скорость времени ×1")

	# Кнопки: спавн перед прицелом, убить всех
	DebugPanelUI.kill_all()
	await frames(3)
	var made := DebugPanelUI.spawn("grunt", 5)
	check(made == 5 and game.room.alive_enemies().size() == 5, "+5 перед прицелом (%d)" % made)
	DebugPanelUI.kill_all()
	await frames(3)
	check(game.room.alive_enemies().is_empty(), "«Убить всех»")
	check(DebugPanel.status_text().contains("0"), "строка состояния: «%s»" % DebugPanel.status_text())

	await _key(KEY_F1)
	check(not DebugPanel.is_open() and p.input_enabled, "F1 — панель закрыта, ввод Тора вернулся")
	DebugPanel.reset_all()
	DirAccess.remove_absolute(bad)
	DirAccess.remove_absolute(DebugPanel.FILE)
	_finish()

func _finish() -> void:
	print("=== ИТОГ DEBUG PANEL: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().quit(1 if _fails.size() else 0)
