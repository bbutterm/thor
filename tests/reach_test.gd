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

func _start(room: String, body_id: String = "berserker") -> Game:
	Run.start_run(body_id)
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
	# Две руны нужны: на второй прыжок перед ударом и ещё один после супер-прыжка.
	g = await _start("res://rooms/room_03.tscn", "hunter")
	p = g.player
	p.global_position = Vector3(0, 0.1, 1.6)
	p.rotation_target = Vector2(0, 0)
	await frames(10)
	# прыжок -> удар-приземление -> супер-прыжок -> двойной в воздухе вперёд
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(12)
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(2)
	Input.action_press("slam")
	await frames(2)
	Input.action_release("slam")
	var started_slam := p.is_slamming
	for i in 90:
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	var started_super := p.velocity.y > p.jump_velocity * 1.2
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
	var ok2 := started_slam and started_super and on_top and p.global_position.y > 4.8
	print("[%s] супер+двойной на башню 5 м: slam=%s, super=%s, y=%.2f" % ["OK" if ok2 else "FAIL", started_slam, started_super, p.global_position.y])
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

	# Новые планировки Мидгарда (GDD 16): от пола на верхний ярус — бегом вперёд с прыжками (залезание на уступ)
	# П7 «зал как путь»: весь путь от входа к дверям одним движением по точкам, короткие пути и лестницы
	await _route("res://rooms/room_07.tscn", Vector3.INF, [Vector3(-2, 0, 17.6), Vector3(-2, 1, 12), Vector3(-2, 1, -2), Vector3(4.9, 3, -2),
		Vector3(7, 3, -8.5), Vector3(7, 6, -18.6), Vector3(0, 6, -21.2)], "причал: берег → пирс → палуба → башня-ворота 6 м")
	await _route("res://rooms/room_07.tscn", Vector3(-10, 2.1, 9), [Vector3(-10, 2, 5), Vector3(-10, 2, -7.6), Vector3(-10, 6, -18.6)],
		"причал (короткий путь): склад → мост → пандус на башню")
	await _climb("res://rooms/room_07.tscn", Vector3(-10, 0.1, 15.2), 0.0, 1.9, "причал: берег → склад 2 м (уступ)")
	await _ladder_up("res://rooms/room_07.tscn", Vector3(7, 3.1, 0.9), 0.0, 7.9, "причал: лестница на мачту 8 м")
	await _route("res://rooms/room_09.tscn", Vector3.INF, [Vector3(3, 0, 14.2), Vector3(12.2, 2, 14.2), Vector3(12, 2, 11.8), Vector3(8, 2, 3.3),
		Vector3(-3.4, 4, 3.3), Vector3(-3.4, 4, 0), Vector3(0, 4, -2.6), Vector3(0, 6, -8.6), Vector3(0, 6, -21)],
		"деревня: набережная → рынок → площадь → двор 6 м")
	await _ladder_up("res://rooms/room_09.tscn", Vector3(-7.2, 2.1, 8), PI / 2, 4.9, "деревня: лестница на крышу рынка 5 м")
	await _route("res://rooms/room_09.tscn", Vector3(-11, 5.1, 6.5), [Vector3(-11, 5, 1.8), Vector3(-11, 7, -1), Vector3(-11, 7, -4.6), Vector3(-11, 6, -10)],
		"деревня (короткий путь): мост с крыши → крыша площади 7 м → двор")
	await _climb("res://rooms/room_08.tscn", Vector3(-3, 0.1, 6), PI / 2, 1.9, "колизей: ступень → терраса 2 м")
	await _climb("res://rooms/room_08.tscn", Vector3(-11, 2.1, -3), 0.0, 3.9, "колизей: терраса → ложа 4 м")
	await _walk_room10_ramp(Vector3(-10, 0.1, 10.4), 0.0, 2.9, "яма → средний ярус")
	await _walk_room10_ramp(Vector3(-6.8, 3.1, -1.6), PI, 6.5, "средний → верхний помост")
	await _walk_room10_ramp(Vector3(9, 3.1, -6.4), PI, 6.5, "средний ярус → вышка")
	await _walk_tower11_ramp(Vector3(-11, 0.1, 10.8), 0.0, 6.4, "первый")
	await _walk_tower11_ramp(Vector3(-5, 6.6, -10.7), PI, 12.9, "второй")
	await _walk_tower11_ramp(Vector3(1, 13.1, 10.7), 0.0, 19.4, "третий")
	await _tower11_wave_gate()
	await _tower11_slam()
	FX.reset_time()
	get_tree().quit(1 if fails > 0 else 0)

## Путь по точкам (П7): от start (Vector3.INF — точка входа зала) бежим к каждой точке, прыгаем, если упёрлись;
## точка взята, если ближе 0.9 м по горизонтали и не ниже её высоты − 0.3 м. Вода и враги выключены (физика зала стоит).
func _route(room: String, start: Vector3, points: Array, what: String) -> void:
	var g := await _start(room)
	g.room.set_physics_process(false)
	g.room._spawn_queue.clear()
	var p := g.player
	if start != Vector3.INF:
		p.global_position = g.room.to_global(start)
	p.velocity = Vector3.ZERO
	await frames(10)
	var done := 0
	var stuck := 0
	var last := p.global_position
	for i in 60 * 40:
		if done >= points.size():
			break
		var target: Vector3 = points[done]
		var here := g.room.to_local(p.global_position)
		var flat := Vector2(target.x - here.x, target.z - here.z)
		if flat.length() < 0.9 and here.y >= target.y - 0.3 and p.is_on_floor():
			done += 1
			continue
		p.rotation_target = Vector2(0, atan2(-flat.x, -flat.y))
		Input.action_press("move_forward")
		await get_tree().physics_frame
		if i % 15 == 0:
			stuck = stuck + 1 if p.global_position.distance_to(last) < 0.5 else 0
			last = p.global_position
		# Упёрся (уступ, край) — прыжок; на спаде — второй
		if stuck >= 2 and p.is_on_floor():
			Input.action_press("jump")
		elif not p.is_on_floor() and p.velocity.y < 0.5 and stuck >= 2:
			Input.action_press("jump")
		else:
			Input.action_release("jump")
		if g.room.to_local(p.global_position).y < -3.0:
			break
	Input.action_release("move_forward")
	Input.action_release("jump")
	var ok := done >= points.size()
	print("[%s] %s: точек %d из %d (y=%.2f)" % ["OK" if ok else "FAIL", what, done, points.size(), g.room.to_local(p.global_position).y])
	if not ok:
		fails += 1

## Лестница (rooms/ladder.gd): вперёд без прыжков, пока не окажемся на площадке не ниже min_y.
func _ladder_up(room: String, local: Vector3, yaw: float, min_y: float, what: String) -> void:
	var g := await _start(room)
	g.room.set_physics_process(false)
	g.room._spawn_queue.clear()
	var p := g.player
	p.global_position = g.room.to_global(local)
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2(0, yaw)
	await frames(10)
	Input.action_press("move_forward")
	var ok := false
	var top := 0.0
	for i in 60 * 6:
		await get_tree().physics_frame
		var y := g.room.to_local(p.global_position).y
		top = maxf(top, y)
		# Наверху — отпустить «вперёд» через полсекунды (как игрок, сошедший на площадку)
		if p.ladder == null and y >= min_y and i % 30 == 29:
			Input.action_release("move_forward")
		if p.is_on_floor() and y >= min_y:
			ok = true
			break
	Input.action_release("move_forward")
	print("[%s] %s (y=%.2f)" % ["OK" if ok else "FAIL", what, top])
	if not ok:
		fails += 1

## Встать в точку зала (локальные координаты), смотреть по yaw и бежать вперёд с прыжками, пока не окажемся
## на высоте >= min_y на земле (залезание на уступ, двойной прыжок).
func _climb(room: String, local: Vector3, yaw: float, min_y: float, what: String) -> void:
	var g := await _start(room)
	g.room.set_physics_process(false)
	var p := g.player
	p.global_position = g.room.to_global(local)
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2(0, yaw)
	await frames(10)
	var y0 := g.room.global_position.y
	Input.action_press("move_forward")
	var top := 0.0
	var ok := false
	for i in 240:
		await get_tree().physics_frame
		var y := p.global_position.y - y0
		top = maxf(top, y)
		if p.is_on_floor() and y >= min_y:
			ok = true
			break
		# Прыжок у стенки: на земле — первый, в воздухе на спаде — второй
		if i % 20 == 0:
			Input.action_press("jump")
		elif i % 20 == 2:
			Input.action_release("jump")
	Input.action_release("move_forward")
	Input.action_release("jump")
	await frames(5)
	print("[%s] %s: макс. y=%.2f" % ["OK" if ok else "FAIL", what, top])
	if not ok:
		fails += 1

## Проходим каждый марш нового зала обычным движением, без искусственного подъёма.
func _walk_room10_ramp(start: Vector3, yaw: float, min_y: float, what: String) -> void:
	var g := await _start("res://rooms/room_10.tscn")
	g.room.set_physics_process(false)
	var p := g.player
	p.global_position = g.room.to_global(start)
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2(0, yaw)
	await frames(10)
	Input.action_press("move_forward")
	var ok := false
	var top := 0.0
	for i in 240:
		await get_tree().physics_frame
		var y := g.room.to_local(p.global_position).y
		top = maxf(top, y)
		if p.is_on_floor() and y >= min_y:
			ok = true
			break
	Input.action_release("move_forward")
	print("[%s] частокол: %s (y=%.2f)" % ["OK" if ok else "FAIL", what, top])
	if not ok:
		fails += 1

## Три физические поверхности, ведущие игрока от уровня к уровню.
func _walk_tower11_ramp(start: Vector3, yaw: float, min_y: float, what: String) -> void:
	var g := await _start("res://rooms/room_11.tscn")
	g.room.set_physics_process(false)
	g.room._spawn_queue.clear()
	var p := g.player
	p.global_position = g.room.to_global(start)
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2(0, yaw)
	await frames(10)
	Input.action_press("move_forward")
	var ok := false
	var peak := 0.0
	for i in 360:
		await get_tree().physics_frame
		var y := g.room.to_local(p.global_position).y
		peak = maxf(peak, y)
		if p.is_on_floor() and y >= min_y:
			ok = true
			break
	Input.action_release("move_forward")
	print("[%s] башня: %s марш (y=%.2f)" % ["OK" if ok else "FAIL", what, peak])
	if not ok:
		fails += 1

## Пустая предыдущая волна не пропускает финал, пока Тор не ступил на вершину.
func _tower11_wave_gate() -> void:
	var g := await _start("res://rooms/room_11.tscn")
	var room := g.room
	room.set_physics_process(false)
	room._spawn_queue.clear()
	for e in room.alive_enemies().duplicate():
		e.queue_free()
	room._alive.clear()
	room._wave_index = 2
	room._wave_size = 1
	room._advance_pending = false
	room._started = true
	room._player = g.player
	g.player.global_position = room.to_global(Vector3(0, 0.1, 12))
	g.player.velocity = Vector3.ZERO
	await frames(8)
	room._check_next_wave()
	var held := room._wave_index == 2 and not room._advance_pending and not room._is_cleared
	g.player.global_position = room.to_global(Vector3(2, 19.6, -15))
	g.player.velocity = Vector3.ZERO
	await frames(12)
	room._check_next_wave()
	await frames(70)
	var opened := room._wave_index == 3 and room.pending_spawns() > 0
	print("[%s] башня: финал ждёт вершины и запускается там" % ["OK" if held and opened else "FAIL"])
	if not (held and opened):
		fails += 1

## Сойти с верхней кромки на открытый двор, ударить в пол и остаться живым.
func _tower11_slam() -> void:
	var g := await _start("res://rooms/room_11.tscn")
	g.room.set_physics_process(false)
	g.room._spawn_queue.clear()
	var p := g.player
	var powers := [0.0]
	p.slammed.connect(func(power: float) -> void: powers[0] = power)
	p.global_position = g.room.to_global(Vector3(10.0, 19.6, -14))
	p.rotation_target = Vector2.ZERO
	p.velocity = Vector3.ZERO
	await frames(10)
	Input.action_press("move_right")
	await frames(30)
	Input.action_release("move_right")
	Input.action_press("slam")
	await frames(2)
	Input.action_release("slam")
	await frames(100)
	var local := g.room.to_local(p.global_position)
	var ok: bool = not p.is_dead and p.is_on_floor() and absf(local.y) < 0.3 and powers[0] >= 0.99
	print("[%s] башня: прыжок 19.5 м, жизнь и сила удара (y=%.2f, сила=%.2f)" % ["OK" if ok else "FAIL", local.y, powers[0]])
	if not ok:
		fails += 1
