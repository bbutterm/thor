extends Node
## Партия 12: лечение от агрессии — враги, убитые ударом-приземлением, лечат Тора (+3, с большой высоты +6,
## не больше 25 за удар); пассивное лечение ×0.7; F6 (FeelSwitch slam_heal) — как раньше.
## godot --headless --path . --fixed-fps 60 res://tests/slam_heal_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game
var _healed: float = 0.0
var _spot: int = 0

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

## Тор над n врагами с 1 HP на высоте h — удар-приземление; вернуть лечение ударом (сигнал slam_healed;
## другое лечение за убийство — тела, руны — не считается)
func _slam_on(n: int, h: float) -> float:
	var p := game.player
	for e in game.room.alive_enemies().duplicate():
		if is_instance_valid(e) and not e.is_dead and not e.is_queued_for_deletion():
			e.queue_free()
	await frames(30)
	# Каждый удар — на новом месте (трупы и обломки прошлого не мешают)
	_spot += 1
	var base := game.room.to_global(Vector3(-6 + _spot * 4, 0, 4))
	var spawned: Array = []
	for i in n:
		var a := TAU * i / n
		var e := game.room.spawn_extra("grunt", base + Vector3(cos(a), 0, sin(a)) * 1.2)
		if e:
			spawned.append(e)
			e.set_physics_process(false)
			e.health = 1.0
	await frames(45)  # враги вышли из появления
	p.health = 5.0
	p.health_changed.emit(p.health, p.max_health)
	_healed = 0.0
	p.global_position = base + Vector3(0, h, 0)
	p.velocity = Vector3.ZERO
	p._air_peak_y = p.global_position.y
	await get_tree().physics_frame
	p._start_slam()
	for i in 240:
		await get_tree().physics_frame
		if not p.is_slamming and p.is_on_floor():
			break
	await frames(3)
	var dead := 0
	for e in spawned:
		if not is_instance_valid(e) or (e as Enemy).is_dead:
			dead += 1
	print("    (врагов %d, убито ударом %d)" % [spawned.size(), dead])
	return _healed

func _run() -> void:
	print("=== SLAM HEAL TEST ===")
	Run.start_run("thrall")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(40)
	game = get_tree().current_scene as Game
	game.room.set_physics_process(false)
	game.room._spawn_queue.clear()
	var p := game.player
	p.slam_healed.connect(func(a: float) -> void: _healed += a)
	var got := await _slam_on(3, 4.0)
	check(absf(got - 3.0 * p.slam_kill_heal) < 0.6, "3 врага ударом с 4 м: +%.0f HP (ждали %.0f)" % [got, 3.0 * p.slam_kill_heal])
	check(game.hud._heal_gain.modulate.a > 0.5 and game.hud._heal_gain.text.begins_with("+"), "сигнал и «%s» у полосы HP" % game.hud._heal_gain.text)
	got = await _slam_on(3, p.big_slam_height + 3.0)
	check(absf(got - 3.0 * p.slam_kill_heal_big) < 0.6, "с большой высоты: +%.0f HP (ждали %.0f)" % [got, 3.0 * p.slam_kill_heal_big])
	got = await _slam_on(6, p.big_slam_height + 3.0)
	check(absf(got - p.slam_heal_cap) < 0.6, "6 врагов с высоты — не больше %.0f за удар (+%.0f)" % [p.slam_heal_cap, got])
	check(is_equal_approx(p.passive_heal(), p.passive_heal_mult) and p.passive_heal_mult < 1.0, "пассивное лечение ×%.1f" % p.passive_heal())
	FeelSwitch.set_old(&"slam_heal", true)
	got = await _slam_on(3, 4.0)
	check(got < 0.5 and is_equal_approx(p.passive_heal(), 1.0), "F6 — старое: удар не лечит (+%.0f), пассивное ×1" % got)
	FeelSwitch.set_old(&"slam_heal", false)
	print("=== ИТОГ SLAM HEAL: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
