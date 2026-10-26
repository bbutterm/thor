extends Node
## Проверка «достижимости»: можно ли запрыгнуть на центральную платформу (зал 2, 2.6 м) двойным прыжком
## и на башню (зал 3, 5 м) супер-прыжком + двойным.
## godot --headless --path . --fixed-fps 60 res://tests/reach_test.tscn

var fails := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var r := Node.new()
		r.set_script(get_script())
		r.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(r)
		return
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _start(room: String) -> Game:
	Run.start_run("berserker")
	Run.room_order.assign([room, Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(20)
	var g := get_tree().current_scene as Game
	g.room.set_process(false)
	await frames(60)
	for e in g.room.alive_enemies().duplicate():
		e.queue_free()
	return g

func _run() -> void:
	# Зал 2: платформа 7x7, центр (0, -3), верх 2.6 м. Встаём в 2 м от южного края (z = 0.5 + 2)
	var g := await _start("res://rooms/room_02.tscn")
	var p := g.player
	p.global_position = Vector3(0, 0.1, 2.8)
	p.rotation_target = Vector2(0, 0)
	p.velocity = Vector3.ZERO
	await frames(10)
	Input.action_press("move_forward")
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(20)
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(60)
	Input.action_release("move_forward")
	await frames(20)
	var ok1 := p.global_position.y > 2.4
	print("[%s] двойной прыжок на платформу 2.6 м: y=%.2f" % ["OK" if ok1 else "FAIL", p.global_position.y])
	if not ok1:
		fails += 1

	# Зал 3: башня 4x4 в (0, -2), верх 5 м. Встаём у южной грани
	g = await _start("res://rooms/room_03.tscn")
	p = g.player
	p.global_position = Vector3(0, 0.1, 1.6)
	p.rotation_target = Vector2(0, 0)
	await frames(10)
	# прыжок -> удар-приземление -> супер-прыжок -> двойной в воздухе вперёд
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(12)
	Input.action_press("slam")
	await frames(2)
	Input.action_release("slam")
	for i in 90:
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	# Второй прыжок — у вершины супер-прыжка (а не через N кадров: hit-stop удара-приземления
	# замедляет время, и фиксированное число кадров попадает в разную точку дуги)
	for i in 60:
		if p.velocity.y < 3.0:
			break
		await get_tree().physics_frame
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	Input.action_press("move_forward")
	await frames(50)
	Input.action_release("move_forward")
	await frames(20)
	var ok2 := p.global_position.y > 4.8
	print("[%s] супер+двойной на башню 5 м: y=%.2f" % ["OK" if ok2 else "FAIL", p.global_position.y])
	if not ok2:
		fails += 1
	FX.reset_time()
	get_tree().quit(1 if fails > 0 else 0)
