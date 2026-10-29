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
	# Поверхность на слое предметов (ящики/бочки): обычный прыжок с неё не должен
	# разрешать удар только потому, что до пола зала больше трёх метров.
	var prop := StaticBody3D.new()
	prop.collision_layer = 1 << 3
	prop.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	shape.shape = box
	prop.add_child(shape)
	game.add_child(prop)
	prop.global_position = Vector3(p.global_position.x, 1.0, p.global_position.z)
	p.global_position = prop.global_position + Vector3(0.0, 1.05, 0.0)
	p.velocity = Vector3.ZERO
	p._super_jump_left = 0.0
	p._bounce_window_left = 0.0
	await frames(30)
	check(p.is_on_floor(), "игрок стоит на поверхности предмета")
	await press("jump")
	await frames(10)
	check(not p.is_on_floor() and p.global_position.y > p.slam_min_height and not p.can_start_slam(),
		"одинарный прыжок с ящика не обходит ограничение высоты")
	check(p.slam.fall_height() < p.fall_feel_min_height, "высота падения учитывает близкую поверхность предмета (%.2f м)" % p.slam.fall_height())
	var old_gravity := p.gravity
	p.gravity = 0.0
	p.global_position.y = 5.2
	p.velocity = Vector3.ZERO
	await frames(3)
	p._air_peak_y = p.global_position.y
	check(p.can_start_slam(), "удар разрешён выше 3 м над предметом")
	var expected := p._air_peak_y - 2.0
	check(absf(p.slam.fall_height() - expected) < 0.2,
		"высота падения — до предмета, а не до пола (%.2f м, ждали %.2f)" % [p.slam.fall_height(), expected])
	p.gravity = old_gravity
	prop.queue_free()
	print("ИТОГ: %d PASS, %d FAIL" % [passes, fails.size()])
	get_tree().quit(1 if fails.size() else 0)
