extends Node
## Реальный бросок пике с высоты 3+ м при падении: к попаданию молота высота уже меньше 3 м.

var fails: Array[String] = []
var passes := 0

func _ready() -> void:
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

func make_world() -> Node3D:
	var stage := Node3D.new()
	get_tree().root.add_child(stage)
	var floor := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	collider.shape = box
	floor.add_child(collider)
	stage.add_child(floor)
	floor.global_position.y = -0.5
	return stage

func make_airborne(stage: Node3D, speed: float) -> Player:
	var p := (load("res://player/player.tscn") as PackedScene).instantiate() as Player
	stage.add_child(p)
	p.input_enabled = false
	p.gravity = 0.0
	p.global_position = Vector3(0.0, 3.5, 0.0)
	p.rotation_target = Vector2(-0.6, 0.0)
	p.head.rotation.x = -0.6
	await frames(3)
	p.gravity = 24.0
	p.velocity.y = speed
	return p

func _run() -> void:
	print("=== DIVE GATE TEST ===")
	Run.start_run("hunter")
	Run.add_mjolnir_trait(Run.mjolnir_trait_def(&"hammer_dive"))
	var stage := make_world()
	var p := await make_airborne(stage, -10.0)
	check(not p.is_on_floor() and not p._slam_ready and p.can_start_slam(), "бросок разрешён на высоте 3.5 м")
	p.mjolnir.throw_hammer()
	var proj := p.mjolnir.projectile
	check(proj != null and proj.data.get("dive", false), "реальный молот летит как пике")
	var stuck := false
	var followed := false
	var hit_height := -1.0
	for i in 60:
		await get_tree().physics_frame
		if proj != null and is_instance_valid(proj) and proj.is_stuck():
			stuck = true
			hit_height = p.global_position.y
			followed = p.is_slamming
			break
	check(stuck and hit_height > 0.1 and hit_height < p.slam_min_height,
		"молот попал, пока Тор в воздухе ниже порога (%.2f м)" % hit_height)
	check(followed, "разрешённое пике продолжается после снижения высоты")
	stage.queue_free()
	await frames(3)
	# Второй настоящий бросок: при быстром падении Тор успевает приземлиться
	# и снова подпрыгнуть, пока молот летит. Старое разрешение не должно пережить посадку.
	stage = make_world()
	p = await make_airborne(stage, -30.0)
	check(p.can_start_slam(), "второй бросок тоже разрешён до посадки")
	# Скорость броска — прежняя (32 м/с): молот должен лететь дольше, чем Тор падает
	p.mjolnir.throw_speed = 32.0
	p.mjolnir.throw_hammer()
	proj = p.mjolnir.projectile
	var landed := false
	for i in 30:
		await get_tree().physics_frame
		if p.is_on_floor():
			landed = true
			break
	check(landed and is_instance_valid(proj) and not proj.is_stuck(), "Тор приземлился, пока молот ещё летит")
	p.input_enabled = true
	Input.action_press("jump")
	var jumped := false
	stuck = false
	followed = false
	hit_height = -1.0
	for i in 30:
		await get_tree().physics_frame
		if i == 1:
			Input.action_release("jump")
		if not p.is_on_floor():
			jumped = true
		if is_instance_valid(proj) and proj.is_stuck():
			stuck = true
			hit_height = p.global_position.y
			followed = p.is_slamming
			break
	Input.action_release("jump")
	check(jumped and stuck and hit_height < p.slam_min_height, "молот попал после нового одинарного прыжка (%.2f м)" % hit_height)
	check(not followed, "посадка отменила прежнее разрешение пике")
	stage.queue_free()
	await frames(3)
	# Новое разрешение на удар от двойного прыжка не должно включать пике у старого снаряда.
	# Скорость броска настраивается в данных; здесь она ниже, чтобы оба нажатия успели пройти.
	stage = make_world()
	p = await make_airborne(stage, -30.0)
	p.mjolnir.throw_speed = 15.0
	p.mjolnir.throw_hammer()
	proj = p.mjolnir.projectile
	landed = false
	for i in 30:
		await get_tree().physics_frame
		if p.is_on_floor():
			landed = true
			break
	check(landed and is_instance_valid(proj) and not proj.is_stuck(), "старый молот ещё летит после посадки")
	p.input_enabled = true
	Input.action_press("jump")
	await frames(3)
	Input.action_release("jump")
	await frames(2)
	Input.action_press("jump")
	await frames(3)
	Input.action_release("jump")
	check(p._slam_ready and is_instance_valid(proj) and not proj.is_stuck(), "двойной прыжок разрешил новый удар до попадания старого молота")
	stuck = false
	followed = false
	for i in 30:
		await get_tree().physics_frame
		if is_instance_valid(proj) and proj.is_stuck():
			stuck = true
			followed = p.is_slamming
			break
	check(stuck and not followed, "новый двойной прыжок не запускает старое пике")
	print("ИТОГ: %d PASS, %d FAIL" % [passes, fails.size()])
	get_tree().quit(1 if fails.size() else 0)
