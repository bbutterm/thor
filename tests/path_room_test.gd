extends Node
## П7 «зал как путь» (Причал room_07, Деревня room_09): двери-награды с порога под решёткой, точки появления
## светятся заранее, вода (Тор — урон и на сушу, враг — гибнет), лестница — в reach_test.
## godot --headless --path . --fixed-fps 60 res://tests/path_room_test.tscn

var _fails: Array[String] = []
var _passes: int = 0

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

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _open(room: String) -> Game:
	Run.start_run("berserker")
	Run.room_order.assign([room, "res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(3)
	for i in 600:
		var g := get_tree().current_scene as Game
		if g and is_instance_valid(g.room) and g.room.is_inside_tree() and g.room._started:
			return g
		await get_tree().physics_frame
	return get_tree().current_scene as Game

func _run() -> void:
	print("=== PATH ROOM TEST ===")
	for room in ["res://rooms/room_07.tscn", "res://rooms/room_09.tscn"]:
		print("-- ", room.get_file())
		var g := await _open(room)
		var r := g.room
		check(bool(r.get_meta("doors_early", false)) and r.spawn_telegraph >= 1.0 and r.has_meta("water_y"), "зал-путь: двери с порога, подсветка появления, вода")
		# Подсветка: враги не появились, точки светятся (для стрелок за краем экрана — группа)
		check(r.alive_count() == 0 and get_tree().get_nodes_in_group("spawn_telegraphs").size() >= 3,
			"первые %.1f с — только свет и звук в точках появления (%d точек)" % [r.spawn_telegraph, get_tree().get_nodes_in_group("spawn_telegraphs").size()])
		await frames(int((r.spawn_telegraph + 0.6) * 60.0))
		check(r.alive_count() > 0, "после подсветки — враги волны (%d)" % r.alive_count())
		# Двери: видны с порога, под решёткой; вход закрыт
		var doors: Array = g.rewards.doors
		var all_locked := not doors.is_empty() and doors.all(func(d: Variant) -> bool: return is_instance_valid(d) and (d as RewardDoor).locked)
		check(doors.size() >= 2 and all_locked, "двери-награды стоят с начала боя под решёткой (%d)" % doors.size())
		var exit_y := float(r.get_meta("exit_y", 0.0))
		check(doors.all(func(d: Variant) -> bool: return absf(r.to_local((d as RewardDoor).global_position).y - exit_y) < 0.3), "двери — на высоте выхода %.0f м" % exit_y)
		var p := g.player
		var d0 := doors[0] as RewardDoor
		d0._on_body_entered(p)
		check(not d0.used and Run.room_index == 0, "в закрытую дверь не войти")
		# Вода: Тор в воде — урон и обратно на сушу
		p.health = p.max_health
		var dry := p.global_position
		for i in 20:
			await get_tree().physics_frame
		var hp0 := p.health
		p.global_position = r.to_global(Vector3(-13, float(r.get_meta("water_y")) - 0.5, 19.0 if room.ends_with("room_09.tscn") else -6.0))
		await frames(3)
		check(p.health <= hp0 - r.water_damage + 0.01 and r.to_local(p.global_position).y > float(r.get_meta("water_y")) + 0.3,
			"Тор в воде: −%.0f HP (%.0f → %.0f) и обратно на сушу" % [r.water_damage, hp0, p.health])
		check(p.global_position.distance_to(dry) < 6.0, "вернулся к последней сухой точке")
		# Враг, упавший в воду, гибнет
		var e := r.spawn_extra("grunt", r.to_global(Vector3(-13, 2.0, 19.0 if room.ends_with("room_09.tscn") else -6.0)))
		var died := false
		for i in 180:
			await get_tree().physics_frame
			if e == null or not is_instance_valid(e) or e.is_dead:
				died = true
				break
		check(died, "враг в воде гибнет")
		# Бой окончен: решётки поднимаются, вход открыт
		for en in r.alive_enemies().duplicate():
			en.queue_free()
		p.health = p.max_health
		g.call("_after_reward")
		await frames(5)
		check(doors.all(func(d: Variant) -> bool: return is_instance_valid(d) and not (d as RewardDoor).locked), "после награды решётки подняты")
		check(g.rewards.take_door("", 0), "дверь открыта — можно войти")
	_finish()

func _finish() -> void:
	print("=== ИТОГ PATH ROOM: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
