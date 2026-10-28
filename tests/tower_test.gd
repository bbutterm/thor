extends Node
## Игровая проверка: реальные ступени обеих новых вышек можно преодолеть обычными прыжками.
var failures := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _run() -> void:
	for room_name in ["room_01", "room_06"]:
		Run.start_run("berserker")
		Run.room_order.assign(["res://rooms/%s.tscn" % room_name, Run.BOSS_SCENE])
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		await frames(80)
		var game := get_tree().current_scene as Game
		game.room.set_physics_process(false)
		game.room._spawn_queue.clear()
		for e in game.room.alive_enemies().duplicate():
			e.queue_free()
		var p := game.player
		var tower := game.room.get_node("Geometry/Watchtower0") as Node3D
		p.global_position = tower.to_global(Vector3(0, 0.1, -5.8))
		p.velocity = Vector3.ZERO
		p.rotation_target = Vector2(0, PI)
		await frames(12)
		Input.action_press("move_forward")
		var peak := 0.0
		var jumped := false
		var reached := false
		var braking := false
		var stopped := false
		for i in 300:
			# Притормозить перед площадкой: просто держать «вперёд» — перелететь её.
			if not braking and not stopped and p.global_position.y - tower.global_position.y > 3.75 and p.global_position.z > tower.global_position.z - 1.2 and p.velocity.z > 1.0:
				braking = true
				Input.action_release("move_forward")
				Input.action_press("move_back")
			elif braking and p.velocity.z <= 0.2:
				braking = false
				stopped = true
				Input.action_release("move_back")
			if p.is_on_floor() and not jumped:
				Input.action_press("jump")
				jumped = true
			else:
				Input.action_release("jump")
				jumped = false
			await get_tree().physics_frame
			peak = maxf(peak, p.global_position.y - tower.global_position.y)
			if p.is_on_floor() and p.global_position.y - tower.global_position.y >= 3.65:
				reached = true
				break
		Input.action_release("move_forward")
		Input.action_release("move_back")
		Input.action_release("jump")
		print("[%s] %s: вышка доступна обычными прыжками (максимум %.2f м)" % ["OK" if reached else "FAIL", room_name, peak])
		if not reached:
			failures += 1
	print("=== ИТОГ ВЫШЕК: %d FAIL ===" % failures)
	get_tree().quit(1 if failures else 0)
