extends Node
## Руны Мьёльнира: общая трата, восстановление на земле и поимка молота.
var failures: Array[String] = []
var passes := 0

func _ready() -> void:
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok:
		passes += 1
		print("  [OK] ", message)
	else:
		failures.append(message)
		print("  [FAIL] ", message)

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _run() -> void:
	print("=== MJOLNIR RUNES TEST ===")
	Run.start_run("hunter")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(120)
	var game := get_tree().current_scene as Game
	game.room.set_physics_process(false)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	var p := game.player
	var h := p.mjolnir
	p.input_enabled = false
	await frames(10)
	check(p.is_on_floor(), "игрок на земле")
	p.set_physics_process(false)
	h.set_physics_process(false)
	p.dash_charges = p.dash_charges_max
	p._jump_buffer_left = 1.0
	p._process_jump(true)
	check(p.dash_charges == p.dash_charges_max, "прыжок с земли бесплатный")
	p._coyote_left = 0.0
	p._jumps_left = 1
	p._jump_buffer_left = 1.0
	p._process_jump(false)
	check(p.dash_charges == p.dash_charges_max - 1 and p._jumps_left == 0, "прыжок в воздухе тратит одну руну")
	p.dash_charges = 0
	p._jumps_left = 1
	p._jump_buffer_left = 1.0
	p.velocity.y = 0.0
	p._wall_jumps_left = 0
	p._process_jump(false)
	check(p._jumps_left == 1 and is_zero_approx(p.velocity.y), "без рун воздушный прыжок недоступен")
	p._dash_recharge_timer = 0.0
	p._update_timers(p.dash_recharge - 0.1)
	check(p.dash_charges == 0, "руна не заряжается раньше времени")
	p._update_timers(0.11)
	check(p.dash_charges == 1, "руна восстанавливается на земле")
	# Дать физике обновить контакт с полом после перемещения.
	p.set_physics_process(true)
	p.global_position += Vector3.UP * 5.0
	p.velocity = Vector3.ZERO
	p.gravity = 0.0
	await frames(3)
	p.set_physics_process(false)
	check(not p.is_on_floor(), "игрок в воздухе")
	# Зарядка в воздухе стоит. Первая трата из полного запаса начинает отсчёт с нуля,
	# следующая сохраняет уже накопленную долю и показывает её на текущей руне.
	var duration := p.dash_recharge * p.weapon_dash_recharge_mult() * p._rune_dash_recharge_mult
	p.dash_charges = p.dash_charges_max
	p._dash_recharge_timer = duration * 0.5
	p._coyote_left = 0.0
	p._jumps_left = 1
	p._jump_buffer_left = 1.0
	p._process_jump(false)
	check(p.dash_charges == p.dash_charges_max - 1 and is_zero_approx(p._dash_recharge_timer)
		and is_zero_approx(game.hud._dash_pips[p.dash_charges].fill), "трата из полного запаса сбрасывает долю в HUD")
	p._dash_recharge_timer = duration * 0.5
	p._jumps_left = 1
	p._jump_buffer_left = 1.0
	p._process_jump(false)
	check(p.dash_charges == p.dash_charges_max - 2 and is_equal_approx(game.hud._dash_pips[p.dash_charges].fill, 0.5),
		"воздушный прыжок показывает сохранённую долю восстановления")
	p._update_timers(4.0)
	check(is_equal_approx(game.hud._dash_pips[p.dash_charges].fill, 0.5), "в воздухе доля не меняется")
	p.dash_charges = 0
	p._dash_recharge_timer = 0.5
	p._update_timers(4.0)
	h._dash_bonus_tick(4.0)
	check(p.dash_charges == 0 and is_equal_approx(p._dash_recharge_timer, 0.5), "в воздухе таймер и бонус без молота не заряжают руны")
	p._jumps_left = 0
	p._wall_jumps_left = 0
	h._recall_press_time = -100.0
	h._catch_attempted = false
	h.on_caught()
	check(p.dash_charges == 1 and p._jumps_left == p.extra_jumps and p._wall_jumps_left == p.wall_jumps, "обычная поимка в воздухе возвращает руну и прыжки")
	h._grant_perfect()
	check(p.dash_charges == p.dash_charges_max, "идеальный хват после поимки заполняет все руны")
	p.dash_charges = 0
	h._recall_press_time = h._now()
	h.on_caught()
	check(p.dash_charges == p.dash_charges_max, "идеальный хват до поимки заполняет все руны")
	# Позднее нажатие в окне работает даже пока бросок ещё перезаряжается.
	p.dash_charges = 0
	h._recall_press_time = -100.0
	h._catch_attempted = false
	h.on_caught()
	var cd_after_catch := h.cooldown_left
	h.press_throw()
	# П1: перезарядка начинается при поимке, идеальный хват её снимает — бросок проходит сразу
	check(p.dash_charges == p.dash_charges_max and cd_after_catch > 0.0 and h.cooldown_left == 0.0 and not h.in_hand,
		"кнопка после поимки засчитывает идеальный хват во время перезарядки и бросает сразу")
	h.force_return_instant()
	p.dash_charges = 0
	p.restore_mjolnir_runes(999)
	p._spend_dash_charge()
	check(p.dash_charges == p.dash_charges_max - 1, "рывок и прыжок используют один запас")
	print("ИТОГ: %d PASS, %d FAIL" % [passes, failures.size()])
	get_tree().quit(1 if failures.size() else 0)
