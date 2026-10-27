extends Node
## Подсказка идеального хвата (ui/catch_assist.gd): время до поимки убывает, кольцо видно только на возврате,
## окно золотеет, итог «идеально / рано / поздно», выключатель [access] catch_assist.
## godot --headless --path . --fixed-fps 60 res://tests/catch_test.tscn
## Кадры (xvfb): xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/catch_test.tscn -- <папка>

var ok := 0
var fail := 0
var out_dir := ""
var game: Game
var _results: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
		DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func check(cond: bool, msg: String) -> void:
	if cond:
		ok += 1
		print("  [OK] ", msg)
	else:
		fail += 1
		print("  [FAIL] ", msg)

func wait(sec: float) -> void:
	for i in maxi(1, int(ceil(sec * 60.0))):
		await get_tree().physics_frame

func grab(name: String) -> void:
	if out_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(out_dir.path_join(name + ".png"))
	print("frame: ", name)

## Бросить, подождать и позвать обратно; вернуть снаряд на возврате
func _throw_and_recall(hand: MjolnirHand, fly: float) -> MjolnirProjectile:
	hand.request_throw_or_recall()
	await wait(fly)
	var proj := hand.projectile
	if proj and proj.state != MjolnirProjectile.State.RETURN:
		hand.request_throw_or_recall()
	await wait(1.0 / 60.0)
	return hand.projectile

## Ждать, пока до поимки останется не больше eta (с); false — не дождались
func _wait_eta(proj: MjolnirProjectile, eta: float) -> bool:
	for i in 240:
		if proj == null or not is_instance_valid(proj):
			return false
		var e := proj.catch_eta()
		if e >= 0.0 and e <= eta:
			return true
		await get_tree().physics_frame
	return false

func _wait_caught(hand: MjolnirHand) -> void:
	for i in 300:
		if hand.in_hand:
			return
		await get_tree().physics_frame

func _run() -> void:
	GameSettings.set_value("access", "catch_assist", true)
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_02.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.5)
	game = get_tree().current_scene as Game
	await wait(1.2)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	game.room.set_physics_process(false)
	var p := game.player
	# Вверх и вперёд: молот улетает на всю дальность, не втыкаясь в стены зала
	p.rotation_target = Vector2(0.7, p.rotation_target.y)
	var hand := p.mjolnir
	# Кольца и окно хвата — без перезарядки (она проверяется в конце)
	var saved_cd := hand.throw_cooldown
	hand.throw_cooldown = 0.0
	hand.catch_timing.connect(func(r: StringName, off: float) -> void: _results.append([r, off]))
	var assist := game.find_child("CatchAssist", true, false) as CatchAssist
	check(assist != null, "подсказка хвата есть в сцене игры")
	await wait(0.2)
	check(assist != null and assist._eta < 0.0, "молот в руке — колец нет")

	print("-- Время до поимки и кольца")
	var proj := await _throw_and_recall(hand, 1.0)
	check(proj != null and proj.state == MjolnirProjectile.State.RETURN, "молот летит обратно")
	var e1 := proj.catch_eta() if proj else -1.0
	await wait(0.1)
	var e2 := proj.catch_eta() if proj and is_instance_valid(proj) else -1.0
	check(e1 > 0.0 and e2 >= 0.0 and e2 < e1, "время до поимки убывает (%.2f → %.2f с)" % [e1, e2])
	check(await _wait_eta(proj, 0.3), "дождались 0.3 с до поимки")
	await get_tree().process_frame
	check(assist._eta >= 0.0 and not assist._window and assist._key.visible, "на подлёте: сходящееся кольцо и клавиша, окно ещё закрыто")
	await grab("01_approach")
	check(await _wait_eta(proj, hand.perfect_window * 0.6), "дождались окна хвата")
	await get_tree().process_frame
	check(assist._window, "в окне хвата кольцо золотое")
	await grab("02_window")
	hand.request_throw_or_recall()
	await _wait_caught(hand)
	await get_tree().process_frame
	check(not _results.is_empty() and _results[-1][0] == &"perfect" and hand.perfect_ready, "нажал в окне — «ИДЕАЛЬНО!» и усиленный бросок")
	check(assist._feedback.visible and assist._feedback.text == tr("ИДЕАЛЬНО!"), "подпись «ИДЕАЛЬНО!»")
	await grab("03_perfect")
	await wait(1.0)

	print("-- Рано")
	_results.clear()
	proj = await _throw_and_recall(hand, 1.0)
	hand.perfect_ready = false
	check(await _wait_eta(proj, 0.3) and proj.catch_eta() > hand.perfect_window + 0.05, "за 0.3 с до поимки")
	hand.request_throw_or_recall()
	await _wait_caught(hand)
	await get_tree().process_frame
	check(not _results.is_empty() and _results[-1][0] == &"early" and not hand.perfect_ready, "нажал рано — «РАНО», без усиления")
	check(assist._feedback.visible and assist._feedback.text.begins_with(tr("РАНО · %d мс").split(" ")[0]), "подпись «РАНО · … мс»: %s" % assist._feedback.text)
	await grab("04_early")
	await wait(1.0)

	print("-- Поздно")
	_results.clear()
	proj = await _throw_and_recall(hand, 1.0)
	var predicted := proj.catch_eta() if proj else -1.0
	var frames := 0
	while not hand.in_hand and frames < 300:
		await get_tree().physics_frame
		frames += 1
	var actual := frames / 60.0
	check(predicted > 0.2 and absf(predicted - actual) <= 0.05, "время до поимки точное: предсказано %.2f с, поймал через %.2f с" % [predicted, actual])
	await get_tree().process_frame
	check(assist._window, "сразу после поимки окно ещё открыто (можно нажать после)")
	await wait(hand.perfect_window + 0.12)
	hand.request_throw_or_recall()  # бросок «поздно»
	await get_tree().process_frame
	check(not _results.is_empty() and _results[-1][0] == &"late", "нажал после окна — «ПОЗДНО»")
	await grab("05_late")
	await wait(0.4)
	if hand.projectile:
		hand.projectile.start_return(true)
	await _wait_caught(hand)
	await wait(1.0)

	print("-- Выключатель")
	GameSettings.set_value("access", "catch_assist", false)
	_results.clear()
	proj = await _throw_and_recall(hand, 0.45)
	await _wait_eta(proj, 0.4)
	await get_tree().process_frame
	check(assist._eta < 0.0 and not assist._key.visible, "подсказка выключена — колец нет")
	await _wait_caught(hand)
	GameSettings.set_value("access", "catch_assist", true)

	print("-- Перезарядка броска")
	hand.throw_cooldown = saved_cd
	hand.reset_cooldown()
	var blocked := [0]
	hand.throw_blocked.connect(func(_l: float) -> void: blocked[0] += 1)
	proj = await _throw_and_recall(hand, 0.6)
	check(hand.cooldown_left > saved_cd - 1.0, "после броска перезарядка ~%.0f с (%.1f)" % [saved_cd, hand.cooldown_left])
	await _wait_caught(hand)
	await wait(0.3)
	var left := hand.cooldown_left
	check(left > 0.5, "поймал без идеального хвата — перезарядка ещё идёт (%.1f с)" % left)
	hand.request_throw_or_recall()
	await get_tree().physics_frame
	check(hand.in_hand and blocked[0] == 1, "бросок на перезарядке не проходит (осечка)")
	await get_tree().process_frame
	check(game.hud._hammer_state == "cooldown", "HUD: «ПЕРЕЗАРЯДКА …» (%s)" % game.hud._hammer_label.text)
	await grab("06_cooldown")
	hand.reset_cooldown()
	_results.clear()
	proj = await _throw_and_recall(hand, 1.0)
	var before := hand.cooldown_left
	await _wait_eta(proj, hand.perfect_window * 0.5)
	hand.request_throw_or_recall()
	await _wait_caught(hand)
	check(not _results.is_empty() and _results[-1][0] == &"perfect", "идеальный хват")
	var after := hand.cooldown_left
	check(after < before - hand.perfect_cooldown_refund,
		"идеальный хват снял %.0f с перезарядки (%.1f с на возврате → %.1f с после поимки)" % [hand.perfect_cooldown_refund, before, after])
	hand.throw_cooldown = 0.0
	hand.reset_cooldown()

	print("=== ИТОГ CATCH: %d OK, %d FAIL ===" % [ok, fail])
	get_tree().quit(1 if fail > 0 else 0)
