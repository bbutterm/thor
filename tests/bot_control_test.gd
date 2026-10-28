extends Node
## Управление ботом с реальным Player: воздушный прыжок перед ударом и перезарядка молота.
const BotPlayer := preload("res://tests/bot/bot_player.gd")
var fails: Array[String] = []
var passes: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	if ok:
		passes += 1
		print("  [OK] ", text)
	else:
		fails.append(text)
		print("  [FAIL] ", text)

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _run() -> void:
	print("=== BOT CONTROL TEST ===")
	Run.start_run("hunter")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(110)
	var game := get_tree().current_scene as Game
	game.room.set_physics_process(false)
	game.room._started = false
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	var p := game.player
	var bot := BotPlayer.new()
	get_tree().root.add_child(bot)
	p.input_enabled = true
	await frames(10)
	check(p.is_on_floor(), "Тор на земле")
	check(p.has_method("can_start_slam"), "бот использует правило удара игрока")
	p.dash_charges = p.dash_charges_max
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(10)
	var before := p._jumps_left
	bot._jump_plan = 1
	bot._jump_t = 0.33
	bot._slam_logic(p, [], 2.0, -2.0, 1.0 / 60.0)
	await frames(4)
	bot._slam_logic(p, [], 2.0, -2.0, 1.0 / 60.0)
	check(not p.is_on_floor() and p._jumps_left == before - 1 and bot._jump_plan == 3, "бот подтверждает второй прыжок и трату руны")
	var did_slam := false
	for i in 120:
		bot._slam_logic(p, [], 2.0, -2.0, 1.0 / 60.0)
		await frames(1)
		if p.is_slamming:
			did_slam = true
			break
	check(did_slam, "после второго прыжка бот выполняет удар-приземление")
	await frames(100)
	bot.release_all()
	p.global_position = Vector3(0, 0.1, 8)
	p.velocity = Vector3.ZERO
	await frames(20)
	p.dash_charges = 0
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await frames(10)
	before = p._jumps_left
	bot._jump_plan = 1
	bot._jump_t = 0.33
	bot._slam_logic(p, [], 2.0, -2.0, 1.0 / 60.0)
	await frames(3)
	check(p._jumps_left == before and bot._jump_plan == 0 and not p.is_slamming, "без рун бот не имитирует второй прыжок и не бьёт с обычного")
	await frames(100)
	bot.begin(game, 7)
	var h := p.mjolnir
	h.cooldown_left = 7.0
	bot._catch_decided = false
	bot._throw_t = 0.0
	bot._hammer(p, 10.0, 0.0, 1.0 / 60.0)
	check(not bot._held.has("throw") and h.in_hand and int(bot.stats.throws) == 0, "на перезарядке бот не пытается бросить и не считает бросок")
	h.cooldown_left = 0.0
	h.throw_hammer()
	check(not h.in_hand and int(bot.stats.throws) == 1, "статистика считает реально выполненный бросок")
	var proj := h.projectile
	if proj:
		# На одном и том же настоящем возврате ETA между порогами бота: 0.15×0.75 и 0.20×0.75.
		proj.start_return(true)
		proj.global_position = h.hand_point() + Vector3.UP * 5.7
		proj.vel = Vector3.DOWN * h.return_speed * h.return_speed_mult
		var eta := proj.catch_eta()
		check(eta > 0.15 * 0.75 and eta < 0.20 * 0.75, "время возврата между порогами бота (%.3f с)" % eta)
		check(not Save.is_unlocked("catch"), "бот: перк сначала закрыт")
		bot._catch_decided = true
		bot._catch_attempt = true
		bot._hammer(p, 10.0, 0.0, 1.0 / 60.0)
		check(not bot._held.has("throw") and bot._catch_attempt, "без перка бот ждёт базовое окно")
		var unlock := Save.get_unlock("catch")
		if unlock:
			Save.add_glory_bank(unlock.price)
			var reason := Save.buy("catch")
			check(reason == "", "бот: покупка перка ловли: %s" % reason)
			if reason == "":
				bot._hammer(p, 10.0, 0.0, 1.0 / 60.0)
				check(bot._held.has("throw") and not bot._catch_attempt, "с перком бот нажимает в расширенном окне")
				await frames(20)
				check(h.in_hand and int(bot.stats.perfect) == 1, "нажатие бота даёт настоящий идеальный хват")
		else:
			check(false, "бот: перк ловли существует")
	else:
		check(false, "бот: снаряд для проверки хвата существует")
	bot.stop()
	# На высокой изолированной площадке проверяем, что рывок не начнётся за край.
	var platform := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(8, 1, 6)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	platform.add_child(collider)
	game.add_child(platform)
	platform.global_position = Vector3(200, 4, 0)
	p.global_position = Vector3(200, 4.6, 0)
	p.velocity = Vector3.ZERO
	p.input_enabled = false
	p.rotation = Vector3.ZERO
	await frames(3)
	Input.action_press("move_forward")
	check(not bot._safe_dash(p), "бот замечает край в конце полного рывка")
	shape.size = Vector3(8, 1, 20)
	await frames(3)
	check(bot._safe_dash(p), "бот разрешает рывок, когда под конечной точкой пол")
	Input.action_release("move_forward")
	platform.queue_free()
	bot.queue_free()
	print("=== ИТОГ BOT CONTROL: %d OK, %d FAIL ===" % [passes, fails.size()])
	get_tree().quit(1 if not fails.is_empty() else 0)
