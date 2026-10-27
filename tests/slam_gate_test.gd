extends Node
## Удар после второго прыжка, специальных подбросов и падения с высоты.
var fails: Array[String] = []
var passes := 0

func _ready() -> void:
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
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

func press(action: String) -> void:
	Input.action_press(action)
	await frames(3)
	Input.action_release(action)
	await frames(1)

func _run() -> void:
	print("=== SLAM GATE TEST ===")
	Run.start_run("hunter")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(100)
	var game := get_tree().current_scene as Game
	game.room.set_physics_process(false)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	var p := game.player
	await frames(10)
	var hints := [0]
	p.slam_unavailable.connect(func() -> void: hints[0] += 1)
	await press("jump")
	await frames(5)
	check(not p.is_on_floor() and not p.can_start_slam(), "обычный прыжок не открывает удар")
	await press("slam")
	check(not p.is_slamming and hints[0] == 1 and game.hud._toast_label.text == "НУЖЕН ВТОРОЙ ПРЫЖОК", "запрет и подсказка в HUD")
	await press("slam")
	check(hints[0] == 1, "повторная подсказка ограничена кулдауном")
	await press("jump")
	check(p.can_start_slam(), "воздушный прыжок разрешает удар")
	await press("slam")
	check(p.is_slamming, "удар после воздушного прыжка начинается")
	for i in 120:
		await get_tree().physics_frame
		if p.is_on_floor() and not p.is_slamming:
			break
	await frames(3)
	check(not p._slam_ready, "посадка без отскока сбрасывает разрешение")
	# Взлёт с площадки высотой выше порога — даже без воздушного прыжка.
	p.global_position += Vector3.UP * (p.slam_min_height + 1.0)
	p.velocity = Vector3.ZERO
	await frames(2)
	check(p.can_start_slam(), "падение с высоты разрешает удар")
	await press("slam")
	check(p.is_slamming, "удар с высоты начинается")
	for i in 120:
		await get_tree().physics_frame
		if p.is_on_floor() and not p.is_slamming:
			break
	# Окно супер-прыжка после удара: он сам открывает следующий удар.
	check(p._super_jump_left > 0.0, "после удара есть окно супер-прыжка")
	await press("jump")
	check(not p.is_on_floor() and p._slam_ready and p.can_start_slam(), "супер-прыжок разрешает удар до второго прыжка")
	await frames(150)
	p.launch_up(8.0)
	await frames(3)
	check(not p.is_on_floor() and p.can_start_slam(), "прыжковая руна разрешает удар")
	# Оба отскока задают то же разрешение, которое сбрасывается только следующей посадкой.
	p._slam_ready = false
	p._slam_bounce(1.0)
	check(p._slam_ready and p.can_start_slam(), "отскок от удара разрешает следующий удар")
	print("ИТОГ: %d PASS, %d FAIL" % [passes, fails.size()])
	get_tree().quit(1 if fails.size() else 0)
