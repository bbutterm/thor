extends Node
## Прыжки по GDD 7.2: отскок от удара-приземления, усиленный отскок, прыжок по головам, залезание на уступ.
## godot --headless --path . --fixed-fps 60 res://tests/jump_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "JumpRunner"
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

## Свободная площадка: пол зала 1 у точки появления, враги зала убраны.
func _clear_room() -> void:
	game.room.set_physics_process(false)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	await wait(0.1)

func _dummy(pos: Vector3, hp: float = 500.0) -> Enemy:
	var e := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	e.max_health = hp
	game.add_child(e)
	e.global_position = pos
	e.health = hp
	e.set_physics_process(false)
	return e

func _run() -> void:
	print("=== JUMP TEST ===")
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.5)
	game = get_tree().current_scene as Game
	await wait(1.0)
	await _clear_room()
	var p := game.player
	var floor_pos := Vector3(game.room.global_position.x + 0, 0.05, game.room.global_position.z + 8.0)

	print("-- Отскок от удара-приземления")
	var e1 := _dummy(floor_pos + Vector3(0, 0, -1.5))
	p.global_position = floor_pos + Vector3(0, 6.0, 0)
	p.velocity = Vector3.ZERO
	await wait(0.05)
	await press("slam")
	var peak_v := 0.0
	for i in 90:
		await get_tree().physics_frame
		peak_v = maxf(peak_v, p.velocity.y)
		if peak_v > 2.0 and p.velocity.y < 0.0:
			break
	check(e1.health < e1.max_health, "удар-приземление задел манекен")
	check(peak_v > 4.0, "удар по врагу подбросил Тора (vy=%.1f)" % peak_v)
	check(p._jumps_left == p.extra_jumps, "двойной прыжок восстановлен после отскока")
	e1.queue_free()
	await wait(1.5)

	print("-- Усиленный отскок (прыжок в окне)")
	var e2 := _dummy(floor_pos + Vector3(0, 0, -1.5))
	p.global_position = floor_pos + Vector3(0, 6.0, 0)
	p.velocity = Vector3.ZERO
	await wait(0.05)
	await press("slam")
	var bounced := false
	for i in 90:
		await get_tree().physics_frame
		if p._bounce_window_left > 0.0:
			bounced = true
			break
	check(bounced, "окно отскока открылось")
	await press("jump")
	var peak_boost := p.velocity.y
	for i in 10:
		await get_tree().physics_frame
		peak_boost = maxf(peak_boost, p.velocity.y)
	check(peak_boost > peak_v + 1.0, "прыжок в окне подбрасывает выше (vy=%.1f > %.1f)" % [peak_boost, peak_v])
	e2.queue_free()
	await wait(2.0)

	print("-- Удар-приземление мимо врагов — без отскока, супер-прыжок как раньше")
	p.global_position = floor_pos + Vector3(4, 4.0, 0)
	p.velocity = Vector3.ZERO
	await wait(0.05)
	await press("slam")
	for i in 60:
		await get_tree().physics_frame
		if p.is_on_floor() and not p.is_slamming:
			break
	await get_tree().physics_frame
	check(p.velocity.y <= 0.5 and p._bounce_window_left <= 0.0, "без врагов не подбрасывает")
	check(p._super_jump_left > 0.0, "окно супер-прыжка открыто")
	await wait(1.0)

	print("-- Прыжок по головам")
	var e3 := _dummy(floor_pos + Vector3(-3, 0, 0))
	await wait(0.1)
	p.global_position = e3.global_position + Vector3(0, 3.2, 0)
	p.velocity = Vector3(0, -2, 0)
	var hp3 := e3.health
	var stomp_v := 0.0
	for i in 60:
		await get_tree().physics_frame
		stomp_v = maxf(stomp_v, p.velocity.y)
		if stomp_v > 5.0:
			break
	check(e3.health < hp3, "враг получил урон от прыжка на голову (%.0f → %.0f)" % [hp3, e3.health])
	check(stomp_v > 5.0, "Тор отскочил от головы (vy=%.1f)" % stomp_v)
	check(e3.state == Enemy.State.STUNNED, "враг оглушён")
	e3.queue_free()
	await wait(1.5)

	print("-- Залезание на уступ")
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(4, 1.6, 3)
	cs.shape = bs
	wall.add_child(cs)
	game.add_child(wall)
	var fwd := Vector3(0, 0, -1)
	p.rotation_target = Vector2(0, 0)
	p.global_position = floor_pos + Vector3(8, 0.05, 0)
	p.velocity = Vector3.ZERO
	wall.global_position = p.global_position + fwd * 2.2 + Vector3(0, 0.8, 0)
	await wait(0.3)
	Input.action_press("move_forward")
	var climbed := false
	var max_y := p.global_position.y
	for i in 120:
		await get_tree().physics_frame
		climbed = climbed or p.is_climbing
		max_y = maxf(max_y, p.global_position.y)
	Input.action_release("move_forward")
	check(climbed, "Тор полез на уступ 1.6 м сам")
	check(max_y > wall.global_position.y + 0.7, "Тор забрался наверх уступа (макс. y=%.2f)" % max_y)
	wall.queue_free()
	await wait(0.3)

	print("-- Высокая стена (3 м) — не залезает; отскок от стены")
	var wall2 := StaticBody3D.new()
	var cs2 := CollisionShape3D.new()
	var bs2 := BoxShape3D.new()
	bs2.size = Vector3(4, 3.0, 1)
	cs2.shape = bs2
	wall2.add_child(cs2)
	game.add_child(wall2)
	p.global_position = floor_pos + Vector3(8, 0.05, 0)
	p.velocity = Vector3.ZERO
	wall2.global_position = p.global_position + fwd * 2.0 + Vector3(0, 1.5, 0)
	await wait(0.3)
	Input.action_press("move_forward")
	var climbed2 := false
	for i in 90:
		await get_tree().physics_frame
		climbed2 = climbed2 or p.is_climbing
	Input.action_release("move_forward")
	check(not climbed2, "на стену 3 м сам не залезает")
	# Отскок от стены: в воздухе у стены, двойной прыжок уже потрачен
	p.global_position = wall2.global_position + Vector3(0, -1.5 + 1.4, 0.95)
	p.velocity = Vector3(0, 3.0, -1.0)
	for i in 6:
		await get_tree().physics_frame
	p._jumps_left = 0
	p._coyote_left = 0.0
	p._wall_jumps_left = p.wall_jumps
	await press("jump")
	await get_tree().physics_frame
	check(p.velocity.y > 5.0 and p.velocity.z > 3.0, "отскок от стены: вверх и от стены (v=%s)" % [p.velocity])
	check(p._wall_jumps_left == p.wall_jumps - 1, "потрачен 1 отскок от стены")
	wall2.queue_free()
	_finish()

func _finish() -> void:
	print("=== ИТОГ JUMP: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
