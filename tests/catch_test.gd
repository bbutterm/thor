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

## Настоящий снаряд возвращается по прямой к неподвижному игроку, чтобы попасть между границами 0.15 и 0.20 с.
func _return_from(hand: MjolnirHand, distance: float) -> MjolnirProjectile:
	hand.force_return_instant()
	# Даём предыдущему окну и отметке промаха в HUD закрыться.
	await wait(0.25)
	hand.perfect_ready = false
	hand.reset_cooldown()
	_results.clear()
	hand.throw_hammer()
	var proj := hand.projectile
	if proj == null:
		return null
	proj.start_return(true)
	proj.global_position = hand.hand_point() + Vector3.UP * distance
	proj.vel = Vector3.DOWN * hand.return_speed * hand.return_speed_mult
	return proj

func _test_before_catch(hand: MjolnirHand, assist: CatchAssist, distance: float, expected: bool,
		min_offset: float, max_offset: float, label: String) -> void:
	var proj := await _return_from(hand, distance)
	if proj == null:
		check(false, label + ": снаряд не создан")
		return
	var eta := proj.catch_eta()
	if assist:
		assist._process(0.0)
		check(assist._window == expected, "%s: окно HUD до поимки (ETA %.3f с)" % [label, eta])
	var pressed_at := hand._now()
	hand.press_throw()
	await _wait_caught(hand)
	if not hand.in_hand:
		check(false, label + ": молот не вернулся")
		return
	var actual := hand._caught_time - pressed_at
	check(actual > min_offset and actual < max_offset, "%s: фактическое время до поимки %.3f с" % [label, actual])
	var perfects := _results.filter(func(r: Array) -> bool: return r[0] == &"perfect")
	var early := _results.filter(func(r: Array) -> bool: return r[0] == &"early")
	check((perfects.size() == 1 and early.is_empty() and hand.perfect_ready) if expected else
			(perfects.is_empty() and early.size() == 1 and not hand.perfect_ready), label + ": результат хвата до поимки")
	if expected and perfects.size() == 1:
		check(absf(float(perfects[0][1]) + actual) < 0.001, label + ": сигнал содержит фактическое время")
	# Усиление должно попасть на настоящий следующий бросок, а не только в флаг.
	hand.press_throw()
	check(hand.projectile != null and is_equal_approx(hand.projectile.damage_mult, hand.perfect_damage_mult if expected else 1.0),
			label + ": множитель следующего броска")

func _test_after_catch(hand: MjolnirHand, assist: CatchAssist, target: float, expected: bool,
		min_offset: float, max_offset: float, hold: bool, label: String) -> void:
	var proj := await _return_from(hand, 2.0)
	if proj == null:
		check(false, label + ": снаряд не создан")
		return
	await _wait_caught(hand)
	if not hand.in_hand:
		check(false, label + ": молот не вернулся")
		return
	for i in 60:
		if hand._now() - hand._caught_time >= target:
			break
		await get_tree().physics_frame
	var actual := hand._now() - hand._caught_time
	check(actual > min_offset and actual < max_offset, "%s: фактическое время после поимки %.3f с" % [label, actual])
	if assist:
		assist._process(0.0)
		check(assist._window == expected and (hand.perfect_window_left() >= 0.0) == expected,
				label + ": окно HUD после поимки")
	_results.clear()
	if hold:
		hand.begin_hold()
		var perfects := _results.filter(func(r: Array) -> bool: return r[0] == &"perfect")
		check(hand.holding and (perfects.size() == 1) == expected and hand.perfect_ready == expected,
				label + ": хват при удержании")
		hand.cancel_hold()
	else:
		hand.press_throw()
		var result: StringName = _results[-1][0] if not _results.is_empty() else &""
		check(result == (&"perfect" if expected else &"late"), label + ": результат хвата после поимки")
		if not _results.is_empty():
			check(absf(float(_results[-1][1]) - actual) < 0.001, label + ": сигнал содержит фактическое время")
		check(hand.projectile != null and is_equal_approx(hand.projectile.damage_mult, hand.perfect_damage_mult if expected else 1.0),
				label + ": множитель следующего броска")

func _test_catch_perk(hand: MjolnirHand, assist: CatchAssist) -> void:
	print("-- Перк окна хвата")
	check(not Save.is_unlocked("catch") and is_equal_approx(hand.perfect_window, 0.15)
			and is_equal_approx(hand.effective_perfect_window(), 0.15), "без перка базовое окно ±0.15 с")
	await _test_before_catch(hand, assist, 3.9, true, 0.0, 0.15, "база: до поимки внутри окна")
	await _test_before_catch(hand, assist, 6.9, false, 0.15, 0.20, "база: до поимки за окном")
	await _test_after_catch(hand, assist, 0.09, true, 0.0, 0.15, false, "база: после поимки внутри окна")
	await _test_after_catch(hand, assist, 0.17, false, 0.15, 0.20, false, "база: после поимки за окном")
	await _test_after_catch(hand, assist, 0.17, false, 0.15, 0.20, true, "база: удержание за окном")
	var unlock := Save.get_unlock("catch")
	if unlock == null:
		check(false, "перк ловли существует")
		return
	Save.add_glory_bank(unlock.price)
	var reason := Save.buy("catch")
	check(reason == "", "покупка перка ловли: %s" % reason)
	if reason != "":
		return
	check(is_equal_approx(Save.perk("catch_window"), 0.05) and is_equal_approx(hand.perfect_window, 0.15)
			and is_equal_approx(hand.effective_perfect_window(), 0.20), "купленный перк расширяет окно до ±0.20 с")
	var bank := Save.glory_bank()
	check(Save.load_game() and Save.is_unlocked("catch") and Save.glory_bank() == bank
			and is_equal_approx(hand.effective_perfect_window(), 0.20), "окно и банк сохранены после загрузки")
	var base := hand.perfect_window
	hand.perfect_window = 0.22
	check(is_equal_approx(hand.effective_perfect_window(), 0.27), "перк добавляется к настройке сцены, не заменяя её")
	hand.perfect_window = base
	await _test_before_catch(hand, assist, 6.9, true, 0.15, 0.20, "перк: до поимки в новом окне")
	await _test_before_catch(hand, assist, 10.5, false, 0.20, 0.40, "перк: до поимки за новым окном")
	await _test_after_catch(hand, assist, 0.17, true, 0.15, 0.20, false, "перк: после поимки в новом окне")
	await _test_after_catch(hand, assist, 0.17, true, 0.15, 0.20, true, "перк: удержание в новом окне")
	await _test_after_catch(hand, assist, 0.23, false, 0.20, 0.40, false, "перк: после поимки за новым окном")
	hand.force_return_instant()
	hand.perfect_ready = false

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
	var saved_cd := hand.catch_cooldown
	hand.catch_cooldown = 0.0
	hand.catch_timing.connect(func(r: StringName, off: float) -> void: _results.append([r, off]))
	var assist := game.find_child("CatchAssist", true, false) as CatchAssist
	check(assist != null, "подсказка хвата есть в сцене игры")
	await wait(0.2)
	check(assist != null and assist._eta < 0.0, "молот в руке — колец нет")
	var cam := get_viewport().get_camera_3d()
	if assist and cam:
		var camera_transform := cam.get_camera_transform()
		for depth in [-0.025, 0.0, 0.025]:
			assist._arrow_on = false
			assist._aim_arrow(camera_transform * Vector3(2.0, 0.0, depth))
			check(assist._arrow_on and is_finite(assist._arrow_angle) and absf(assist._arrow_angle) < 0.05,
					"стрелка хвата у плоскости камеры указывает вправо (глубина %.3f)" % depth)
	else:
		check(false, "есть камера и подсказка для проверки стрелки хвата")

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
	await get_tree().physics_frame
	check(not _results.is_empty() and _results[-1][0] == &"early", "нажал рано — «РАНО» сразу при нажатии")
	# Попытка одна: второе нажатие в окне уже не спасает
	await _wait_eta(proj, hand.perfect_window * 0.5)
	hand.request_throw_or_recall()
	await _wait_caught(hand)
	await get_tree().process_frame
	check(not hand.perfect_ready and _results.count(_results[0]) >= 1 and _results.filter(func(r: Array) -> bool: return r[0] == &"perfect").is_empty(),
		"после «РАНО» повтор в окне не даёт идеального хвата")
	check(assist._failed or not assist._window, "кольцо провала (без золотого окна)")
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

	print("-- Перезарядка броска (начинается при поимке, П1)")
	hand.catch_cooldown = saved_cd
	hand.reset_cooldown()
	var blocked := [0]
	hand.throw_blocked.connect(func(_l: float) -> void: blocked[0] += 1)
	check(is_equal_approx(saved_cd, 1.5) and is_equal_approx(hand.perfect_catch_cooldown, 0.0),
		"перезарядка: обычная поимка %.1f с, идеальный хват %.1f с" % [saved_cd, hand.perfect_catch_cooldown])
	_results.clear()
	proj = await _throw_and_recall(hand, 0.6)
	check(hand.cooldown_left == 0.0, "в полёте перезарядки нет (%.1f)" % hand.cooldown_left)
	await _wait_caught(hand)
	await get_tree().physics_frame
	var left := hand.cooldown_left
	check(left > saved_cd - 0.2 and left <= saved_cd, "обычная поимка — перезарядка ~%.1f с (%.2f с)" % [saved_cd, left])
	await wait(0.3)
	hand.request_throw_or_recall()
	await get_tree().physics_frame
	check(hand.in_hand and blocked[0] == 1, "бросок на перезарядке не проходит (осечка)")
	await get_tree().process_frame
	check(game.hud._hammer_state == "cooldown" and game.hud._rune_hammer.cooldown > 0.0,
		"HUD: полоска перезарядки у молота (%.2f), «%s»" % [game.hud._rune_hammer.cooldown, game.hud._hammer_label.text])
	await grab("06_cooldown")
	await wait(saved_cd)
	check(hand.cooldown_left == 0.0 and game.hud._hammer_state == "hand" and game.hud._rune_hammer.cooldown == 0.0,
		"через %.1f с после поимки — снова можно бросать, полоски нет" % saved_cd)
	_results.clear()
	proj = await _throw_and_recall(hand, 1.0)
	await _wait_eta(proj, hand.perfect_window * 0.5)
	hand.request_throw_or_recall()
	await _wait_caught(hand)
	check(not _results.is_empty() and _results[-1][0] == &"perfect", "идеальный хват")
	check(hand.cooldown_left == 0.0, "идеальный хват — перезарядки нет (%.2f с)" % hand.cooldown_left)
	hand.request_throw_or_recall()
	check(not hand.in_hand and blocked[0] == 1, "после идеального хвата бросок сразу")
	await wait(0.2)
	hand.force_return_instant()
	check(hand.in_hand and hand.cooldown_left == 0.0, "служебный возврат (новый зал) — молот в руке без перезарядки")
	print("-- Старая перезарядка под переключателем F6 (FeelSwitch hammer_cooldown)")
	check(not FeelSwitch.is_old(&"hammer_cooldown"), "по умолчанию — новая перезарядка")
	FeelSwitch.set_old(&"hammer_cooldown", true)
	hand.reset_cooldown()
	_results.clear()
	proj = await _throw_and_recall(hand, 1.0)
	var old_before := hand.cooldown_left
	check(old_before > hand.throw_cooldown - 1.5, "старое: перезарядка от броска ~%.0f с (%.1f)" % [hand.throw_cooldown, old_before])
	await _wait_eta(proj, hand.perfect_window * 0.5)
	hand.request_throw_or_recall()
	await _wait_caught(hand)
	var old_after := hand.cooldown_left
	check(not _results.is_empty() and _results[-1][0] == &"perfect" and old_after < old_before - hand.perfect_cooldown_refund + 0.01,
		"старое: идеальный хват снял %.0f с (%.1f → %.1f)" % [hand.perfect_cooldown_refund, old_before, old_after])
	FeelSwitch.set_old(&"hammer_cooldown", false)
	hand.reset_cooldown()
	hand.catch_cooldown = 0.0
	hand.reset_cooldown()
	await _test_catch_perk(hand, assist)

	print("=== ИТОГ CATCH: %d OK, %d FAIL ===" % [ok, fail])
	get_tree().quit(1 if fail > 0 else 0)
