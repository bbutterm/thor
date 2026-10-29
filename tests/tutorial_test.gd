extends Node
## Подсказки, реальные действия, общий интервал и разовый вход на ярусы.
## godot --headless --path . --fixed-fps 60 res://tests/tutorial_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
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

func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().physics_frame

func press(action: String, hold: float = 0.05) -> void:
	Input.action_press(action)
	await wait(hold)
	Input.action_release(action)

func _step_is(t: Tutorial, id: String) -> bool:
	return t.step >= 0 and t.step < Tutorial.STEPS.size() and Tutorial.STEPS[t.step] == id

func _run() -> void:
	print("=== TUTORIAL TEST ===")
	var txt := Tutorial.keys_in("{key_jump} / {key_attack} / {key_throw} / {key_dash}")
	check(txt.find("{") < 0 and txt.find("ЛКМ") >= 0 and txt.find("ПКМ") >= 0, "клавиши подставляются из InputMap («%s»)" % txt)
	for id in Tutorial.STEPS:
		check(Dialogue.has_pool("ravens.tutorial_" + id), "реплика шага «%s» есть" % id)
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.5)
	game = get_tree().current_scene as Game
	var t := game.tutorial
	check(t != null and t.active, "в первом зале первого забега обучение включено")
	game.room.set_physics_process(false)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	var p := game.player
	# Управляем временем обучения вручную; игрок и оружие продолжают обычную физику.
	t.set_physics_process(false)
	FX.reset_time()
	t._physics_process(t.first_delay + 0.1)
	check(_step_is(t, "move") and t._announced, "первая подсказка — ходьба")
	var first_wait := t._hint_wait
	Input.action_press("move_forward")
	await wait(0.2)
	t._physics_process(0.01)
	Input.action_release("move_forward")
	check(Save.event_count("tutorial_step_move") == 1 and _step_is(t, "jump") and not t._announced, "ходьба засчитана, следующая подсказка ждёт интервал")

	# Выполняем дальнейшие действия раньше показа; настоящий прыжок, рывок и зажатая атака.
	await press("jump")
	await wait(0.12)
	await press("jump")
	t._physics_process(0.01)
	check(Save.event_count("tutorial_step_jump") == 1, "двойной прыжок засчитан до подсказки")
	for i in 360:
		if p.is_on_floor() and p.dash_charges > 0:
			break
		await get_tree().physics_frame
	Input.action_press("dash")
	await wait(0.05)
	t._physics_process(0.01)
	Input.action_release("dash")
	check(t._saw_rune_spend and Save.event_count("tutorial_step_dash") == 1, "рывок и трата руны засчитаны")
	await wait(0.5)
	Input.action_press("attack")
	await wait(0.1)
	t._physics_process(0.01)
	await wait(0.9)
	Input.action_release("attack")
	check(Save.event_count("tutorial_step_weapon_skill") == 1, "зажатая атака действительно запустила приём")
	game._room_load_active = true
	p.mjolnir.state_changed.emit(true)
	game._room_load_active = false
	check(Save.event_count("tutorial_step_runes") == 0, "служебный возврат при смене зала не засчитывает поимку")
	p.mjolnir.catch_cooldown = 0.0
	p.mjolnir.throw_hammer()
	await wait(0.1)
	p.mjolnir.request_throw_or_recall()
	for i in 240:
		if p.mjolnir.in_hand:
			break
		await get_tree().physics_frame
	check(p.mjolnir.in_hand and Save.event_count("tutorial_step_runes") == 1 and Save.event_count("tutorial_o6_done") == 1,
		"после траты реальная поимка молота засчитала руны")
	FX.reset_time()
	t._physics_process(0.0)
	check(_step_is(t, "slam") and not t._announced, "уже выполненные приём, бросок и руны пропущены")
	check(first_wait >= 10.0 and not t.say("weapon_skill"), "выполненный шаг нельзя показать повторно")

	# Вертикальная подсказка делит ограничение с основными и помечается после показа.
	var normal_room := game.room
	var vertical := (load("res://rooms/room_10.tscn") as PackedScene).instantiate() as Room
	check(vertical.has_meta("tutorial_vertical") and bool(vertical.get_meta("tutorial_vertical", false)), "метаданные вертикального зала сохранены в сцене")
	game.room = vertical
	t._physics_process(9.0)
	check(Save.event_count("tutorial_step_vertical") == 0 and t._hint_wait > 0.0, "в течение 10 секунд вторая подсказка не показана")
	t._physics_process(1.2)
	check(Save.event_count("tutorial_step_vertical") == 1 and t._hint_wait >= 10.0, "первый вход на ярусы показан и засчитан")
	t._physics_process(10.1)
	check(Save.event_count("tutorial_step_vertical") == 1 and _step_is(t, "slam") and t._announced, "ярусы не повторяются, затем показывается незавершённый шаг")
	p.slammed.emit(0.5)
	t._physics_process(0.0)
	check(_step_is(t, "doors"), "сигнал удара-приземления продвигает обучение")
	game.rewards.doors_shown.emit([])
	t._physics_process(0.0)
	check(_step_is(t, "build") and t.active, "после дверей — урок «Tab — сборка»")
	game.build_screen.open()
	game.build_screen.close()
	t._physics_process(0.0)
	check(not t.active and Save.event_count("tutorial_done") == 1 and Save.event_count("tutorial_step_build") == 1, "открыл сборку по Tab — обычное обучение завершено")
	game.room = normal_room
	vertical.free()

	# После уже завершённого старого обучения подсказка ярусов всё ещё доступна.
	Save.data.events.erase("tutorial_step_vertical")
	Save.data.events["tutorial_done"] = 1
	Save.data.events["tutorial_o6_done"] = 1
	# Имитация пересоздания Game сразу после другой подсказки.
	Tutorial._carry_hint_wait = 10.0
	Tutorial._carry_wall_msec = Time.get_ticks_msec()
	var later := Tutorial.new()
	later.game = game
	later.player = p
	game.add_child(later)
	later.set_physics_process(false)
	var vertical_again := (load("res://rooms/room_10.tscn") as PackedScene).instantiate() as Room
	game.room = vertical_again
	later._physics_process(later.first_delay + 0.1)
	check(not later.active and Save.event_count("tutorial_step_vertical") == 0 and later._hint_wait > 0.0, "интервал сохраняется при пересоздании обучения")
	later._physics_process(8.1)
	check(not later.active and Save.event_count("tutorial_step_vertical") == 1, "первый вертикальный зал показывается и после старого tutorial_done")
	game.room = normal_room
	vertical_again.free()
	later.queue_free()
	_finish()

func _finish() -> void:
	print("=== ИТОГ TUTORIAL: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
