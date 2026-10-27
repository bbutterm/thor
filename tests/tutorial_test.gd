extends Node
## Обучение в первом зале: подсказки воронов по шагам, клавиши из InputMap, «пройдено» в сохранении.
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

func _wait_step(t: Tutorial, id: String, sec: float = 4.0) -> bool:
	for i in int(sec * 60.0):
		if _step_is(t, id):
			return true
		await get_tree().physics_frame
	return _step_is(t, id)

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
	check(await _wait_step(t, "move", t.first_delay + 1.0), "первая подсказка — ходьба")
	Input.action_press("move_forward")
	await wait(0.5)
	Input.action_release("move_forward")
	check(await _wait_step(t, "jump"), "пошёл — дальше прыжок")
	await press("jump")
	await wait(0.15)
	await press("jump")
	check(await _wait_step(t, "dash"), "двойной прыжок — дальше рывок")
	await wait(p.dash_recharge + 0.2) # после двойного прыжка руна восстанавливается на земле
	await press("dash")
	check(await _wait_step(t, "attack"), "рывок — дальше удар")
	await press("attack", 0.1)
	check(await _wait_step(t, "throw"), "удар — дальше Мьёльнир")
	await press("throw")
	check(await _wait_step(t, "slam"), "бросок — дальше удар-приземление")
	await wait(0.5)
	p.global_position += Vector3(0, 3.0, 0)
	await wait(0.05)
	await press("slam")
	check(await _wait_step(t, "doors", 5.0), "удар-приземление — дальше двери")
	await wait(t.step_timeout + 1.0)
	check(_step_is(t, "doors"), "подсказка о дверях ждёт дверей (без тайм-аута)")
	game.rewards.doors_shown.emit([])
	await wait(t.step_gap + 0.3)
	check(not t.active and Save.event_count("tutorial_done") == 1, "все шаги пройдены — обучение больше не показывается")
	_finish()

func _finish() -> void:
	print("=== ИТОГ TUTORIAL: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
