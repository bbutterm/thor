extends Node
## Сравнение стоимости рендера первого зала до Б0 и после Н3: одна камера и одинаковые
## 44 неподвижных врага. Исключает ИИ/падения и предназначено для сравнения графики,
## а не для оценки FPS реального боя. См. docs/report_open_rooms/performance.md.
var game: Game
var baseline: Room

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(40)
	game = get_tree().current_scene as Game
	game.room.set_physics_process(false)
	game.room._spawn_queue.clear()
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	game.room._alive.clear()
	game.player.input_enabled = false
	game.player.set_physics_process(false)
	await frames(5)
	baseline = (load("res://tests/fixtures/room_01_before_b0.tscn") as PackedScene).instantiate() as Room
	game.level.add_child(baseline)
	baseline.visible = false
	baseline.set_physics_process(false)
	WorldArt.dress_room(baseline, Run.map)
	var c := game.player.global_position
	for i in 44:
		var a := TAU * i / 44.0
		var radius := 5.0 + (i % 4) * 1.5
		var e := game.room.spawn_extra("grunt" if i % 4 == 0 else "fodder", c + Vector3(cos(a) * radius, 0.05, sin(a) * radius))
		if e:
			e.health = 1e6
			e.max_health = 1e6
			e.set_physics_process(false)
			e.reparent(game, true)
		await get_tree().process_frame
	await frames(25)
	print("ВРАГОВ: ", get_tree().get_nodes_in_group("enemies").size())
	if get_tree().get_nodes_in_group("enemies").size() != 44:
		printerr("BENCH FAIL: нужно ровно 44 врага")
		get_tree().quit(1)
		return
	await _measure(true, "СТАРЫЙ ПРОГРЕВ", 15)
	await _measure(false, "НОВЫЙ ПРОГРЕВ", 15)
	await _measure(true, "СТАРЫЙ 1", 60)
	await _measure(false, "НОВЫЙ 1", 60)
	await _measure(true, "СТАРЫЙ 2", 60)
	await _measure(false, "НОВЫЙ 2", 60)
	print("ИТОГ BENCH")
	get_tree().quit(0)

func _measure(old: bool, label: String, count: int) -> void:
	game.room.visible = not old
	baseline.visible = old
	await frames(5)
	var values := PackedFloat32Array()
	var draw_counts := PackedInt32Array()
	var visible_counts := PackedInt32Array()
	var before := Time.get_ticks_usec()
	for i in count:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		values.append((now - before) / 1000.0)
		draw_counts.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		visible_counts.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		before = now
	values.sort()
	draw_counts.sort()
	visible_counts.sort()
	var total := 0.0
	for x in values:
		total += x
	print("%s: avg %.2f ms, median %.2f ms, p95 %.2f ms, draw calls %d, visible objects %d, enemies %d" % [label, total / count, values[count / 2], values[int(count * 0.95)], draw_counts[count / 2], visible_counts[count / 2], get_tree().get_nodes_in_group("enemies").size()])
