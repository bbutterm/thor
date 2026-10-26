extends Node
## Проверка «достижимости»: можно ли запрыгнуть на центральную платформу (зал 2, 2.6 м) двойным прыжком
## и на башню (зал 3, 5 м) супер-прыжком + двойным, а также трейтом «Притяжение к молоту».
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
	# Платформа 7 м в глубину: держим «вперёд», пока не окажемся наверху (иначе пробегаем её насквозь;
	# с залезанием на уступ (GDD 7.2) Тор бывает наверху уже после первого прыжка)
	var top_y := p.global_position.y
	for i in 60:
		await get_tree().physics_frame
		top_y = maxf(top_y, p.global_position.y)
		if p.is_on_floor() and p.global_position.y > 2.4:
			break
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
	# Залез — отпускаем «вперёд» (с топором бег ×1.1, иначе перелетает башню насквозь)
	var on_top := false
	for i in 50:
		await get_tree().physics_frame
		if p.is_on_floor() and p.global_position.y > 4.8:
			on_top = true
			break
	Input.action_release("move_forward")
	await frames(20)
	var ok2 := on_top and p.global_position.y > 4.8
	print("[%s] супер+двойной на башню 5 м: y=%.2f" % ["OK" if ok2 else "FAIL", p.global_position.y])
	if not ok2:
		fails += 1

	# Зал 3 ещё раз: трейт «Притяжение к молоту» — метнуть молот в стену башни под самым верхом
	# и «дёрнуть» себя к нему (ПКМ) — это способ перемещения
	g = await _start("res://rooms/room_03.tscn")
	p = g.player
	for t in Run.all_mjolnir_traits:
		if t.id == &"pull_to_hammer":
			Run.add_mjolnir_trait(t)
	p.global_position = Vector3(0, 0.1, 8.0)
	p.velocity = Vector3.ZERO
	await frames(10)
	var cam := p.get_aim_origin()
	p.rotation_target = Vector2(atan2(4.7 - cam.y, cam.z - 0.0), 0)
	await frames(5)
	p.mjolnir.throw_hammer()
	var stuck := false
	for i in 60:
		await get_tree().physics_frame
		var pr := p.mjolnir.projectile
		if pr and is_instance_valid(pr) and pr.is_stuck():
			stuck = true
			break
	p.mjolnir.request_throw_or_recall()
	await frames(120)
	var ok3 := stuck and p.global_position.y > 4.8 and p.mjolnir.in_hand
	print("[%s] Притяжение к молоту на башню 5 м: воткнулся=%s, y=%.2f" % ["OK" if ok3 else "FAIL", stuck, p.global_position.y])
	if not ok3:
		fails += 1
	# Длинный дом Ярла (блок О): на каждый балкон (настил 3 м) — со ступени-ящика 1.5 м прыжками
	g = await _start(Run.BOSS_SCENE)
	for e in g.room.alive_enemies().duplicate():
		e.queue_free()
	g.room.set_physics_process(false)
	var balconies := get_tree().get_nodes_in_group("balconies")
	var reached := 0
	for b in balconies:
		var bc := b as Balcony
		var top := bc.top_point()
		p = g.player
		# Ступень — со стороны середины зала по Z: встаём ещё дальше и бежим к балкону
		var toward := -signf(top.z - g.room.global_position.z)
		var start := Vector3(top.x, g.room.global_position.y + 0.1, top.z + toward * (6.0 + 5.5))
		p.global_position = start
		p.velocity = Vector3.ZERO
		# Смотрим на балкон (вперёд = -Z камеры)
		p.rotation_target = Vector2(0, 0.0 if toward > 0 else PI)
		await frames(10)
		Input.action_press("move_forward")
		var on := false
		for i in 300:
			await get_tree().physics_frame
			if p.is_on_floor() and (p.global_position.y < top.y - 0.5):
				Input.action_press("jump")
			elif not p.is_on_floor() and p.velocity.y < 0.5 and p.global_position.y < top.y + 0.2:
				Input.action_press("jump")
			else:
				Input.action_release("jump")
			if i % 2 == 1:
				Input.action_release("jump")
			if p.is_on_floor() and bc.has_point_on_top(p.global_position):
				on = true
				break
		Input.action_release("move_forward")
		Input.action_release("jump")
		await frames(10)
		if on:
			reached += 1
		print("  %s: %s (y=%.2f)" % [bc.name, "наверху" if on else "не залез", p.global_position.y - g.room.global_position.y])
	var ok4 := balconies.size() == 4 and reached == balconies.size()
	print("[%s] балконы длинного дома ярла: залез на %d из %d" % ["OK" if ok4 else "FAIL", reached, balconies.size()])
	if not ok4:
		fails += 1
	FX.reset_time()
	get_tree().quit(1 if fails > 0 else 0)
