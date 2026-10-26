extends Node
## Ярость и бой-реплики Одина (блок П, GDD 8, 17): шкала копится в серии и сбрасывается по окну 3 с,
## берсерк 8 с (урон и скорость ×1.5, без отбрасывания), Один орёт; реплики «ДВИГАЙСЯ!», «Хоть что-то»,
## «Скуф…», «Позорище», «Вот! ВОТ!» и лимит 12 с.
## godot --headless --path . --fixed-fps 60 res://tests/rage_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game
var lines: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "RageRunner"
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

func _floor_pos() -> Vector3:
	return Vector3(game.room.global_position.x, 0.05, game.room.global_position.z + 8.0)

func _dummy(pos: Vector3, hp: float = 500.0) -> Enemy:
	var e := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	e.max_health = hp
	game.add_child(e)
	e.global_position = pos
	e.health = hp
	e.set_physics_process(false)
	return e

## Последняя реплика Одина — из пула события?
func said(event: String) -> bool:
	if lines.is_empty():
		return false
	for it in Dialogue.pools.get("odin." + event, []):
		for l in it.lines:
			if Dialogue.format_text(str(l.get("text", ""))) == lines[-1]:
				return true
	return false

func _kill(n: int) -> void:
	for i in n:
		Run.register_kill(false, false, false, "melee")

func _run() -> void:
	print("=== RAGE TEST ===")
	Run.start_run("hunter")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.5)
	game = get_tree().current_scene as Game
	await wait(1.0)
	game.room.set_physics_process(false)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	await wait(0.2)
	Odin.line_spoken.connect(func(t: String) -> void: lines.append(t))
	await _test_rage()
	await _test_lines()
	_finish()

func _test_rage() -> void:
	var p := game.player
	var r := p.rage
	print("-- Ярость: числа GDD 8")
	check(r != null, "у игрока есть Ярость")
	check(is_equal_approx(r.kill_window, 3.0) and r.kills_to_full == 25 and is_equal_approx(r.berserk_time, 8.0), "окно 3 с, 25 убийств, берсерк 8 с")
	var hud_rage := game.hud.get_node_or_null("RageHUD") as RageHUD
	check(hud_rage != null, "шкала Ярости в HUD")

	print("-- Копится и сбрасывается по окну")
	_kill(5)
	check(r.kills == 5 and is_equal_approx(r.value(), 0.2), "5 убийств — шкала 20 %% (%.2f)" % r.value())
	await wait(0.1)
	check(hud_rage and is_equal_approx(hud_rage._bar.value, 0.2), "HUD показывает 20 %")
	await wait(2.5)
	_kill(1)
	check(r.kills == 6, "убийство через 2.6 с — серия продолжается (%d)" % r.kills)
	await wait(3.3)
	check(r.kills == 0 and r.value() == 0.0, "3 с без убийств — шкала сброшена")

	print("-- Берсерк")
	var base_speed := p.effective_move_speed()
	var started := [false]
	var ended := [false]
	r.berserk_started.connect(func() -> void: started[0] = true, CONNECT_ONE_SHOT)
	r.berserk_ended.connect(func() -> void: ended[0] = true, CONNECT_ONE_SHOT)
	lines.clear()
	Odin.reset_cooldown()
	Odin.say("room_clear")  # лимит занят — берсерк всё равно орёт
	_kill(24)
	check(not r.active and r.kills == 24, "24 убийства — ещё не берсерк")
	_kill(1)
	check(r.active and started[0], "25-е убийство — берсерк")
	check(said("berserk"), "Один орёт (лимит 12 с не мешает): «%s»" % (lines[-1] if not lines.is_empty() else ""))
	var e := _dummy(_floor_pos() + Vector3(0, 0, -4))
	check(is_equal_approx(p.outgoing_damage_mult(e, "melee"), 1.5), "урон ×1.5 (%.2f)" % p.outgoing_damage_mult(e, "melee"))
	var hp0 := e.health
	p.crit_chance_base = 0.0  # крит 5 % (GDD 8) делал проверку случайной
	p.deal_damage(e, 10.0, Vector3.ZERO, "melee")
	check(is_equal_approx(hp0 - e.health, 15.0), "deal_damage в берсерке: 10 → %.1f" % (hp0 - e.health))
	check(is_equal_approx(p.effective_move_speed(), base_speed * 1.5), "скорость ×1.5 (%.1f → %.1f)" % [base_speed, p.effective_move_speed()])
	check(r.is_stun_immune(), "неуязвимость к стану")
	p.velocity = Vector3.ZERO
	p.take_damage(1.0, Vector3(20, 0, 0), true)
	check(absf(p.velocity.x) < 0.5, "удар не отбрасывает (vx=%.1f)" % p.velocity.x)
	_kill(3)
	check(r.kills == 0 and r.active, "в берсерке шкала не копится заново")
	await wait(0.1)
	check(hud_rage and hud_rage._label.text.begins_with("БЕРСЕРК"), "HUD: «%s»" % (hud_rage._label.text if hud_rage else ""))
	await wait(4.0)
	check(r.active, "через 4 с берсерк ещё идёт")
	await wait(4.1)
	check(not r.active and ended[0], "через 8 с берсерк выключился")
	check(is_equal_approx(p.outgoing_damage_mult(e, "melee"), 1.0) and is_equal_approx(p.effective_move_speed(), base_speed), "множители вернулись")
	check(not r.is_stun_immune(), "стан снова действует")
	e.queue_free()

	print("-- Настоящие убийства")
	var d := _dummy(_floor_pos() + Vector3(2, 0, -4), 5.0)
	p.deal_damage(d, 50.0, Vector3.ZERO, "melee")
	await wait(0.05)
	check(r.kills == 1, "убийство врага пополнило шкалу (%d)" % r.kills)
	await wait(3.5)

func _test_lines() -> void:
	var p := game.player
	p.heal(999)
	print("-- Бой-реплики Одина (GDD 17)")
	# «Позорище» — добил ренжем
	Odin.reset_cooldown()
	lines.clear()
	var d := _dummy(_floor_pos() + Vector3(2, 0, -4), 5.0)
	p.deal_damage(d, 50.0, Vector3.ZERO, "ranged")
	await wait(0.1)
	check(said("ranged_kill"), "добил ренжем — «Позорище» (%s)" % [lines])
	# Лимит 12 с
	lines.clear()
	var d2 := _dummy(_floor_pos() + Vector3(-2, 0, -4), 5.0)
	p.deal_damage(d2, 50.0, Vector3.ZERO, "ranged")
	await wait(0.1)
	check(lines.is_empty(), "сразу второй раз — молчит (лимит 12 с)")
	# Мульти-килл важнее «Позорища»
	Odin.reset_cooldown()
	lines.clear()
	for i in 3:
		var dd := _dummy(_floor_pos() + Vector3(-3 + i * 1.5, 0, -6), 5.0)
		p.deal_damage(dd, 50.0, Vector3.ZERO, "ranged" if i == 2 else "melee")
	await wait(0.1)
	check(said("multikill"), "3 убийства разом — «Хоть что-то» (%s)" % [lines])
	# «Скуф…» — много урона
	Odin.reset_cooldown()
	lines.clear()
	p.heal(999)
	p.take_damage(p.max_health * 0.4, Vector3.ZERO, true)
	await wait(0.1)
	check(said("big_damage"), "много урона — «Скуф…» (%s)" % [lines])
	p.heal(999)
	# «ДВИГАЙСЯ!» — 4 с без движения при живых врагах
	Odin.reset_cooldown()
	lines.clear()
	var idle_enemy := _dummy(_floor_pos() + Vector3(5, 0, -8))
	p.global_position = _floor_pos()
	p.velocity = Vector3.ZERO
	await wait(4.5)
	check(said("idle"), "4 с стоит столбом — «ДВИГАЙСЯ!» (%s)" % [lines])
	idle_enemy.queue_free()
	# «Вот! ВОТ!» — удар-приземление с высоты
	Odin.reset_cooldown()
	lines.clear()
	p.global_position = _floor_pos() + Vector3(0, p.big_slam_height + 2.0, 0)
	p.velocity = Vector3.ZERO
	await wait(0.05)
	await press("slam")
	for i in 120:
		await get_tree().physics_frame
		if p.is_on_floor() and not p.is_slamming:
			break
	await wait(0.1)
	check(said("big_slam"), "удар-приземление с %.0f м — «Вот! ВОТ!» (%s)" % [p.big_slam_height + 2.0, lines])

func _finish() -> void:
	print("=== ИТОГ RAGE: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
