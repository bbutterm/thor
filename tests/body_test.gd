extends Node
## Тела смертных (блок Л, GDD 6, 7.3, 7.4): забег каждым телом стартует, стили движения, пассивки и изъяны,
## подкат, экран выбора тела.
## godot --headless --path . --fixed-fps 60 res://tests/body_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "BodyRunner"
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

## Забег телом id в зале 1, враги зала убраны. Возвращает игрока.
func _start(id: String) -> Player:
	get_tree().paused = false
	Run.start_run(id)
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.4)
	game = get_tree().current_scene as Game
	await wait(0.9)
	game.room.set_physics_process(false)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	await wait(0.1)
	return game.player

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

func _place(p: Player, pos: Vector3) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2(0, 0)
	await wait(0.25)

## Сколько раз подряд удаётся прыгнуть в воздухе (после прыжка с земли)
func _count_air_jumps(p: Player) -> int:
	await press("jump")
	await wait(0.12)
	var n := 0
	for i in 4:
		var vy_before := p.velocity.y
		await press("jump")
		await get_tree().physics_frame
		if p.velocity.y > vy_before + 2.0:
			n += 1
		await wait(0.08)
	await wait(1.5)
	return n

func _run() -> void:
	print("=== BODY TEST ===")
	await _test_all_bodies_start()
	await _test_nimble()
	await _test_ram()
	await _test_jumper()
	await _test_heavy()
	await _test_slider()
	await _test_feel_rules()
	await _test_passives()
	await _test_select_screen()
	_finish()

func _test_all_bodies_start() -> void:
	print("-- Забег каждым телом")
	check(Run.all_bodies.size() == 9, "тел 9 (%d)" % Run.all_bodies.size())
	for b in Run.all_bodies:
		var p := await _start(b.id)
		var ok := game != null and is_equal_approx(p.max_health, b.max_health) and is_equal_approx(p.move_speed, b.move_speed)
		check(ok, "%s: забег стартовал, HP %d, скорость %.1f" % [b.id, int(p.max_health), p.move_speed])
		check(p.movement_style() == b.movement_style, "%s: стиль движения %s" % [b.id, p.movement_style()])
		check(p.weapons.melee != null and p.weapons.melee.def == b.start_melee, "%s: стартовое мили %s" % [b.id, b.start_melee.id if b.start_melee else "?"])
		check((p.weapons.ranged != null) == (b.start_ranged != null), "%s: стартовый ренж" % b.id)
		for pd in [b.passive, b.flaw]:
			check(pd != null and (pd.handler != null or pd.id in ["frail", "social_lift", "odin_scorn"]), "%s: черта %s с обработчиком" % [b.id, pd.id if pd else "?"])

func _test_nimble() -> void:
	print("-- Шустрый (Охотник): 3 коротких рывка, перезарядка 1.67 с")
	var p := await _start("hunter")
	await _place(p, _floor_pos())
	check(p.dash_charges_max == 3 and is_equal_approx(p.dash_recharge, 1.67), "3 руны, восстановление 1.67 (%d, %.2f)" % [p.dash_charges_max, p.dash_recharge])
	var base_dur := (load("res://run/movement/base.tres") as MovementProfile).dash_duration
	check(p.dash_duration < base_dur, "рывок короче базового (%.2f < %.2f)" % [p.dash_duration, base_dur])
	for i in 3:
		await press("dash")
		await wait(0.2)
	check(p.dash_charges == 0, "три рывка подряд потрачены (%d)" % p.dash_charges)
	await wait(1.8)
	check(p.dash_charges >= 1, "руна вернулась за ~1.67 с")
	var c := await _start("courier")
	check(c.movement_style() == "nimble_plus" and c.dash_charges_max == 3 and c.dash_recharge < 1.67, "Шустрый+ (гонец): 3 рывка, перезарядка %.2f" % c.dash_recharge)

func _test_ram() -> void:
	print("-- Таран (Берсерк): 1 длинный рывок сквозь врагов")
	var p := await _start("berserker")
	check(p.dash_charges_max == 1 and is_equal_approx(p.dash_recharge, 3.33), "1 руна, восстановление 3.33")
	await _place(p, _floor_pos())
	var e := _dummy(p.global_position + Vector3(0, 0, -3.0))
	var e2 := _dummy(p.global_position + Vector3(0.6, 0, -5.0))
	await wait(0.1)
	var z0 := p.global_position.z
	Input.action_press("move_forward")
	await press("dash")
	await wait(0.4)
	Input.action_release("move_forward")
	var expected := p.ram_damage
	check(absf((e.max_health - e.health) - expected) < 0.6, "враг получил 0.7 У (%.1f)" % (e.max_health - e.health))
	check(e2.health < e2.max_health, "второй враг на пути тоже задет")
	check(p.global_position.z < e.global_position.z - 0.5, "Тор пролетел сквозь врага (z %.1f → %.1f, враг %.1f)" % [z0, p.global_position.z, e.global_position.z])
	check(p.collision_mask & (1 << 2) != 0, "после рывка снова сталкивается с врагами")
	e.queue_free()
	e2.queue_free()
	# Бочку толкает: независимый сценарий после предыдущего рывка.
	p.restore_mjolnir_runes(p.dash_charges_max)
	await wait(0.1)
	await _place(p, _floor_pos() + Vector3(3, 0, 0))
	var barrel := (load("res://props/barrel.tscn") as PackedScene).instantiate() as RigidBody3D
	game.add_child(barrel)
	barrel.global_position = p.global_position + Vector3(0, 0.1, -2.5)
	await wait(0.3)
	var bpos := barrel.global_position
	Input.action_press("move_forward")
	await press("dash")
	await wait(0.4)
	Input.action_release("move_forward")
	# Сильно отброшенная бочка разбивается в серебро (блок К) — это тоже «отбросил»
	var moved := barrel.global_position.distance_to(bpos) if is_instance_valid(barrel) else 99.0
	check(moved > 1.0, "таран отбросил бочку (%.1f м)" % moved)
	if is_instance_valid(barrel):
		barrel.queue_free()

func _test_jumper() -> void:
	print("-- Прыгун (Скальд): тройной прыжок, 3 отскока от стены, рывка на земле нет")
	var p := await _start("skald")
	check(p.extra_jumps == 2 and p.wall_jumps == 3 and p.wall_jump_mult > 1.0, "прыжков в воздухе 2, отскоков 3, сильнее (×%.2f)" % p.wall_jump_mult)
	await _place(p, _floor_pos())
	var n := await _count_air_jumps(p)
	check(n == 2, "в воздухе ровно 2 прыжка (тройной) — %d" % n)
	p.restore_mjolnir_runes(p.dash_charges_max)
	await _place(p, _floor_pos())
	var ch := p.dash_charges
	await press("dash")
	await wait(0.1)
	check(p.dash_charges == ch and not p.is_dashing(), "на земле рывка нет")
	await press("jump")
	await wait(0.15)
	await press("dash")
	await wait(0.02)
	check(p.dash_charges == ch - 1, "в воздухе рывок есть")
	await wait(1.5)

func _test_heavy() -> void:
	print("-- Тяжёлый (Жрец): нет двойного прыжка, удар-приземление ×1.5, стан 1 с")
	var p := await _start("priest")
	check(p.extra_jumps == 0, "двойного прыжка нет (extra_jumps 0)")
	await _place(p, _floor_pos())
	var n := await _count_air_jumps(p)
	check(n == 0, "в воздухе прыжков нет (%d)" % n)
	check(is_equal_approx(p.slam_radius_mult, 1.5) and is_equal_approx(p.slam_damage_mult, 1.5), "удар-приземление ×1.5 по радиусу и урону")
	check(p.slam_bounce_mult > 1.0, "отскок от удара-приземления выше (×%.2f)" % p.slam_bounce_mult)
	# Враг на 4.6 м — дальше базового радиуса 3.5 + 0.25*4, но внутри ×1.5
	var e := _dummy(_floor_pos() + Vector3(0, 0, -4.6))
	await _place(p, _floor_pos() + Vector3(0, 5.0, 0))
	await press("slam")
	var stunned := false
	for i in 90:
		await get_tree().physics_frame
		stunned = stunned or e.state == Enemy.State.STUNNED
		if not p.is_slamming and p.is_on_floor():
			break
	await get_tree().physics_frame
	check(e.health < e.max_health, "удар-приземление достал врага на 4.6 м")
	check(stunned or e.state == Enemy.State.STUNNED, "враг оглушён ударом-приземлением")
	e.queue_free()
	await wait(1.5)
	var s := await _start("smith")
	check(s.movement_style() == "heavy" and s.extra_jumps == 0, "Кузнец — тоже Тяжёлый")
	check(s.weapons.melee.level == 2, "Кузнец: стартовое оружие +1 уровень (ур. %d)" % s.weapons.melee.level)
	await _place(s, _floor_pos())
	await press("jump")
	await wait(0.15)
	var ch := s.dash_charges
	await press("dash")
	await wait(0.02)
	check(s.dash_charges == ch, "Кузнец: нет рывка в воздухе")
	await wait(1.2)
	await press("dash")
	await wait(0.02)
	check(s.dash_charges == ch - 1, "Кузнец: на земле рывок есть")

func _test_slider() -> void:
	print("-- Скользящий (Солдат): рывок переходит в подкат, скорость не гасится, предел ×2.2")
	var p := await _start("soldier")
	check(p.dash_to_slide and is_equal_approx(p.momentum_cap, 2.2), "подкат после рывка, предел ×2.2")
	await _place(p, _floor_pos() + Vector3(0, 0, 3))
	Input.action_press("move_forward")
	await press("dash")
	var slid := false
	var max_speed := 0.0
	for i in 40:
		await get_tree().physics_frame
		slid = slid or p.is_sliding
		if p.is_sliding:
			max_speed = maxf(max_speed, p.horizontal_speed())
	Input.action_release("move_forward")
	check(slid, "рывок перешёл в подкат")
	check(max_speed > p.effective_move_speed() * 1.5, "в подкате скорость держится (%.1f м/с)" % max_speed)
	check(max_speed <= p.effective_move_speed() * 2.2 + 0.1, "не выше ×2.2 от бега")
	await wait(1.0)

func _test_feel_rules() -> void:
	print("-- Правила ощущений (7.4) и подкат Ctrl+Shift")
	var p := await _start("thrall")
	check(is_equal_approx(p.air_control, 0.7), "управление в воздухе 70 %")
	check(is_equal_approx(p.momentum_cap, 1.8), "предел импульса ×1.8")
	await _place(p, _floor_pos() + Vector3(0, 0, 3))
	# Два рывка подряд — скорость не выше ×1.8 от бега
	Input.action_press("move_forward")
	await press("dash")
	await wait(0.2)
	await press("dash")
	var top := 0.0
	for i in 30:
		await get_tree().physics_frame
		if not p.is_dashing():
			top = maxf(top, p.horizontal_speed())
	Input.action_release("move_forward")
	check(top <= p.effective_move_speed() * 1.8 + 0.1, "после двух рывков скорость ≤ ×1.8 (%.1f)" % top)
	await wait(2.5)
	# Подкат: Ctrl + Shift на земле
	await _place(p, _floor_pos() + Vector3(0, 0, 3))
	Input.action_press("move_forward")
	await wait(0.3)
	Input.action_press("slam")
	await press("dash")
	var slid := false
	for i in 10:
		await get_tree().physics_frame
		slid = slid or p.is_sliding
	Input.action_release("slam")
	check(slid and not p.is_dashing(), "Ctrl+Shift на земле — подкат, а не рывок")
	await press("jump")
	await wait(0.05)
	Input.action_release("move_forward")
	check(not p.is_sliding and p.horizontal_speed() > p.effective_move_speed(), "прыжок из подката сохраняет скорость (%.1f)" % p.horizontal_speed())
	await wait(1.5)

func _test_passives() -> void:
	print("-- Пассивки и изъяны")
	# Берсерк: кровавая ярость, лечение −50 %
	var p := await _start("berserker")
	var e := _dummy(_floor_pos() + Vector3(0, 0, -6))
	check(is_equal_approx(p.outgoing_damage_mult(e, "melee"), 1.0), "Кровавая ярость: на полном HP ×1.0")
	p.health = p.max_health * 0.5
	check(is_equal_approx(p.outgoing_damage_mult(e, "melee"), 1.5), "на 50 %% HP ×%.2f" % p.outgoing_damage_mult(e, "melee"))
	p.health = p.max_health * 0.1
	check(is_equal_approx(p.outgoing_damage_mult(e, "melee"), 1.5), "предел +50 %")
	p.health = 50.0
	p.heal(10.0)
	check(is_equal_approx(p.health, 55.0), "лечение −50 %% (+%.1f)" % (p.health - 50.0))
	# Батрак: урон −30 %
	p = await _start("thrall")
	check(is_equal_approx(p.outgoing_damage_mult(null, "hammer"), 0.7), "Батрак: урон ×0.7")
	# Жрец: руны ×2
	p = await _start("priest")
	check(Run.rune_power == 2, "Жрец: руны ×2 (rune_power %d)" % Run.rune_power)
	var rune: RuneDef = null
	for r in Run.all_runes:
		if r.id == "max_health":
			rune = r
	if rune:
		Run.add_rune(rune)
		p.recalc_from_runes(Run)
		check(is_equal_approx(p.max_health, 70.0 + 60.0), "руна +30 HP даёт жрецу +60 (%d)" % int(p.max_health))
	# Охотник: ренж не замедляет
	p = await _start("hunter")
	p.weapons.switch_to(WeaponHolder.RANGED, true)
	await wait(0.1)
	check(p.is_ranged_active() and p.weapon_move_mult() >= 1.0, "Охотник: с арбалетом скорость ×%.2f" % p.weapon_move_mult())
	# Дева щита: ренж −25 %
	p = await _start("shieldmaiden")
	check(is_equal_approx(p.outgoing_damage_mult(null, "ranged"), 0.75) and is_equal_approx(p.outgoing_damage_mult(null, "melee"), 1.0), "Дева щита: ренж ×0.75, мили ×1")
	check(not (load("res://run/passives/parry_master.tres") as PassiveDef).implemented, "«Мастер щита» — заглушка (implemented=false)")
	# Гонец: в спину ×2, спереди −30 %
	p = await _start("courier")
	await _place(p, _floor_pos())
	var front := _dummy(p.global_position + Vector3(0, 0, -2))
	front.look_at(p.global_position, Vector3.UP, true)
	await wait(0.05)
	check(is_equal_approx(p.outgoing_damage_mult(front, "melee"), 0.7), "Гонец: спереди ×%.2f" % p.outgoing_damage_mult(front, "melee"))
	front.look_at(p.global_position + (front.global_position - p.global_position) * 3.0, Vector3.UP, true)
	await wait(0.05)
	check(is_equal_approx(p.outgoing_damage_mult(front, "melee"), 2.0), "Гонец: в спину ×%.2f" % p.outgoing_damage_mult(front, "melee"))
	var hp0 := front.health
	p.crit_chance_base = 0.0  # крит 5 % (GDD 8) делал проверку случайной
	p.deal_damage(front, 10.0, Vector3.ZERO, "melee")
	check(is_equal_approx(hp0 - front.health, 20.0), "deal_damage применяет множитель (−%.1f)" % (hp0 - front.health))
	front.queue_free()
	# Скальд: первый удар в зале не ранит, прицел качается
	p = await _start("skald")
	check(p.camera_fx.aim_wobble_deg > 0.0, "Скальд: прицел покачивается (%.1f°)" % p.camera_fx.aim_wobble_deg)
	var hp := p.health
	p.take_damage(12.0, Vector3.ZERO, true)
	check(is_equal_approx(p.health, hp), "первый удар в зале не ранит")
	p.take_damage(12.0, Vector3.ZERO, true)
	check(is_equal_approx(p.health, hp - 12.0), "второй — ранит")
	p.on_room_start()
	p.take_damage(12.0, Vector3.ZERO, true)
	check(is_equal_approx(p.health, hp - 12.0), "новый зал — снова первый удар прощён")
	# Солдат: рывок перезаряжает ренж
	p = await _start("soldier")
	await _place(p, _floor_pos())
	var gun := p.weapons.ranged
	gun.mag = 0
	var reserve := gun.reserve
	await press("dash")
	await wait(0.05)
	check(gun.mag == mini(gun.def.mag_size, reserve), "Солдат: рывок перезарядил ренж (%d/%d)" % [gun.mag, gun.def.mag_size])
	await wait(1.0)

func _test_select_screen() -> void:
	print("-- Экран выбора тела")
	Save.reset()
	var bs := BodySelect.new()
	get_tree().root.add_child(bs)
	bs.open("Назад", "hunter")
	await wait(0.1)
	check(bs.visible and bs.bodies.size() == 9, "экран открыт, тел 9")
	check(bs.selected != null and bs.selected.id == "hunter", "выбрано прошлое тело")
	var locked := 0
	for b in bs.bodies:
		if bs.card(b.id).get_meta("locked"):
			locked += 1
	check(locked == 6, "закрыто 6 тел (без открытий) — %d" % locked)
	bs.select("priest")
	check(bs._fight_btn.disabled and bs._fight_btn.text.contains("300"), "закрытое: цена на кнопке (%s)" % bs._fight_btn.text)
	check(bs._move_title.text == "Тяжёлый" and bs._passive_title.text.begins_with("Мудрость"), "видны стиль и пассивка")
	check(bs._odin_text.text != "", "слово Одина: «%s»" % bs._odin_text.text)
	check(not bs.choose("priest"), "закрытое тело не выбрать")
	Save.add_glory_bank(300)
	bs._rebuild()
	bs.select("priest")
	check(not bs._fight_btn.disabled, "хватает Славы — можно открыть")
	bs._fight_btn.pressed.emit()
	check(not BodySelect.is_locked("priest"), "жрец открыт с экрана выбора")
	var got: Array = []
	bs.closed.connect(func(id: String) -> void: got.append(id))
	bs._fight_btn.pressed.emit()
	check(got == ["priest"], "«В бой» — забег жрецом (%s)" % [got])
	bs.queue_free()
	Save.reset()
	get_tree().paused = false

func _finish() -> void:
	print("=== ИТОГ BODY: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
