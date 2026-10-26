extends Node
## Враги Мидгарда (GDD 12.1) и волны (GDD 12.5): корм бьёт, Раздутый взрывается (и задевает своих),
## щит Щитоносца держит удар спереди и пропускает сверху/сзади/кирку, Шаман лечит и поднимает корм,
## Наёмник светит лазером, стреляет и роняет патроны; волны идут пачками и не ждут полной зачистки.
## godot --headless --path . --fixed-fps 60 res://tests/enemy_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game
var room: Room
var p: Player
var _hurts: Array[float] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var r := Node.new()
		r.set_script(get_script())
		r.set_meta("runner", true)
		r.name = "EnemyTestRunner"
		get_tree().root.add_child.call_deferred(r)
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

## Ждать до sec секунд, пока cond() не станет true; Тор бессмертен.
func wait_until(sec: float, cond: Callable) -> bool:
	for i in int(sec * 60.0):
		await get_tree().physics_frame
		if is_instance_valid(p):
			p.health = p.max_health
		if cond.call():
			return true
	return false

func _load_room(idx: int = 0) -> void:
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[idx], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(30)
	game = get_tree().current_scene as Game
	room = game.room
	p = game.player
	_hurts.clear()
	p.hurt.connect(func(a: float) -> void: _hurts.append(a))

## Пустой зал: волны выключены, все враги убраны, Тор в центре лицом на север (-Z).
func _empty_room() -> void:
	room.set_physics_process(false)
	room._spawn_queue.clear()
	for e in room.alive_enemies().duplicate():
		e.queue_free()
	room._alive.clear()
	await frames(2)
	p.global_position = room.global_position + Vector3(0, 0.1, 4)
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2.ZERO
	await frames(10)
	_hurts.clear()

func _spawn(kind: String, offset: Vector3) -> Enemy:
	return room.spawn_extra(kind, p.global_position + offset)

func _dummy(pos: Vector3) -> Enemy:
	var e := room.spawn_extra("grunt", pos)
	e.set_physics_process(false)
	e.max_health = 500.0
	e.health = 500.0
	return e

func _clear() -> void:
	for e in room.alive_enemies().duplicate():
		if is_instance_valid(e):
			e.queue_free()
	room._alive.clear()
	for n in get_tree().get_nodes_in_group("ammo_pickups"):
		n.queue_free()
	await frames(5)
	p.global_position = room.global_position + Vector3(0, 0.1, 4)
	p.velocity = Vector3.ZERO
	_hurts.clear()

func _run() -> void:
	print("=== ENEMY TEST ===")
	await _load_room(0)
	await _empty_room()
	await _test_fodder()
	await _test_bloated()
	await _test_shield()
	await _test_shaman()
	await _test_merc()
	await _test_waves()
	_finish()

func _test_fodder() -> void:
	print("-- Драугр-корм")
	var e := _spawn("fodder", Vector3(0, 0, -4))
	check(e != null and e.kind == Enemy.Kind.FODDER, "корм появился")
	check(is_equal_approx(e.max_health, 0.8 * EnemyDef.U), "HP корма 0.8 У (%.1f)" % e.max_health)
	check(e._humanoid != null and e._humanoid.parts.is_empty() and e.hand_weapon == "", "корм облегчённый: одна модель, без оружия и частей")
	var ok := await wait_until(8.0, func() -> bool: return _hurts.size() > 0)
	check(ok, "корм дошёл и ударил (%s)" % str(_hurts))
	check(ok and absf(_hurts[0] - 5.0) < 0.01, "удар корма — 5")
	await _clear()

func _test_bloated() -> void:
	print("-- Раздутый")
	var friend := _dummy(p.global_position + Vector3(1.5, 0, 0))
	var b := _spawn("bloated", Vector3(0, 0, -9))
	check(b.kind == Enemy.Kind.BLOATED and is_equal_approx(b.move_speed, 5.0), "Раздутый: скорость 5")
	var saw_tele := [false]
	var bw: WeakRef = weakref(b)
	var ok := await wait_until(8.0, func() -> bool:
		var bb := bw.get_ref() as Enemy
		if bb and bb.state == Enemy.State.WINDUP and bb._telegraph and is_instance_valid(bb._telegraph):
			saw_tele[0] = true
		return bb == null or bb.is_dead)
	check(ok, "Раздутый добежал и взорвался")
	check(saw_tele[0], "перед взрывом — телеграф (диск радиусом взрыва)")
	check(_hurts.size() > 0 and _hurts[0] >= 2.0 * EnemyDef.U - 0.1, "взрыв задел Тора на 2 У (%s)" % str(_hurts))
	check(is_instance_valid(friend) and friend.health < friend.max_health, "взрыв задел и своих (%.0f/%.0f)" % [friend.health if is_instance_valid(friend) else 0.0, 500.0])
	await _clear()
	# Убит издалека — взрывается на месте, Тора не задевает
	var b2 := _spawn("bloated", Vector3(0, 0, -12))
	b2.set_physics_process(false)
	var f2 := _dummy(b2.global_position + Vector3(1.2, 0, 0))
	await frames(5)
	var g0 := Run.glory
	b2.take_hit(200.0, Vector3.ZERO, "ranged")
	await frames(3)
	check(is_instance_valid(f2) and f2.health < 500.0, "убитый Раздутый взорвался и задел соседа")
	check(_hurts.is_empty(), "издалека Тора не задело")
	check(Run.glory > g0, "убийство Раздутого засчитано (Слава %d → %d)" % [g0, Run.glory])
	await _clear()

func _test_shield() -> void:
	print("-- Щитоносец")
	var s := _spawn("shieldbearer", Vector3(0, 0, -2.5))
	await frames(40)
	s.set_physics_process(false)
	s.state = Enemy.State.CHASE
	s.rotation.y = 0.0
	# Смотрит на Тора (+Z — к нему)
	var to := p.global_position - s.global_position
	s.rotation.y = atan2(to.x, to.z)
	var hp := s.health
	var away := -to.normalized() * 5.0
	s.take_hit(20.0, away, "melee")
	check(is_equal_approx(s.health, hp), "щит держит мили спереди")
	s.take_hit(20.0, Vector3.ZERO, "ranged")
	check(is_equal_approx(s.health, hp), "щит держит ренж спереди")
	s.take_hit(20.0, away, "hammer")
	check(is_equal_approx(s.health, hp), "щит держит Мьёльнир спереди")
	s.take_hit(10.0, away, "slam")
	check(s.health < hp, "удар-приземление (сверху) проходит")
	hp = s.health
	s.take_hit(10.0, -away, "hammer")
	check(s.health < hp, "Мьёльнир на возврате (сзади) проходит")
	hp = s.health
	p.equip(Loot.get_def("pickaxe"), 1, false)
	p.weapons.switch_to(WeaponHolder.MELEE, true)
	await frames(2)
	s.take_hit(10.0, away, "melee")
	check(s.health < hp, "кирка пробивает щит спереди")
	p.equip(Loot.get_def("axe"), 1, false)
	p.weapons.switch_to(WeaponHolder.MELEE, true)
	await frames(2)
	hp = s.health
	p.global_position = s.global_position - to.normalized() * 2.0
	s.take_hit(10.0, to.normalized() * 5.0, "melee")
	check(s.health < hp, "удар сзади проходит")
	# Теснит: удар щитом толкает Тора
	p.global_position = s.global_position + to.normalized() * 1.6
	s.rotation.y = atan2(to.x, to.z)
	s.set_physics_process(true)
	_hurts.clear()
	var max_v := [0.0]
	var ok := await wait_until(6.0, func() -> bool:
		max_v[0] = maxf(max_v[0], Vector2(p.velocity.x, p.velocity.z).length())
		return _hurts.size() > 0)
	check(ok and absf(_hurts[0] - 15.0) < 0.01, "удар щитом — 15 (%s)" % str(_hurts))
	for i in 6:
		await get_tree().physics_frame
		max_v[0] = maxf(max_v[0], Vector2(p.velocity.x, p.velocity.z).length())
	check(max_v[0] > 9.0, "удар щитом теснит Тора (скорость %.1f)" % max_v[0])
	s.take_hit(9999.0, Vector3.ZERO, "melee_finisher")
	check(s.is_dead, "отладочный урон 9999 проходит сквозь щит (тесты)")
	await _clear()

func _test_shaman() -> void:
	print("-- Шаман")
	var sh := _spawn("shaman", Vector3(0, 0, -10))
	var hurt := _dummy(sh.global_position + Vector3(2.0, 0, 0))
	hurt.health = 100.0
	var before := room.alive_count()
	var tele := [false]
	var ok := await wait_until(9.0, func() -> bool:
		if sh.state == Enemy.State.WINDUP:
			tele[0] = true
		return hurt.health > 100.0)
	check(tele[0], "у обряда есть телеграф (замах)")
	check(ok, "Шаман лечит своих (%.0f)" % hurt.health)
	await frames(2)
	var fodder := 0
	for e in room.alive_enemies():
		if e.kind == Enemy.Kind.FODDER:
			fodder += 1
	check(fodder >= 1 and room.alive_count() > before, "Шаман поднял корм (%d)" % fodder)
	check(sh.ritual_interval == 6.0, "обряд раз в 6 с")
	await _clear()

func _test_merc() -> void:
	print("-- Наёмник Локи")
	var m := _spawn("merc", Vector3(0, 0, -10))
	var laser := [false]
	var laser_t := [0.0]
	var mw: WeakRef = weakref(m)
	var ok := await wait_until(10.0, func() -> bool:
		var mm := mw.get_ref() as Enemy
		if mm and mm._laser and mm._laser.visible:
			laser[0] = true
			laser_t[0] += 1.0 / 60.0
		return _hurts.size() > 0)
	check(laser[0], "лазерная точка перед очередью (%.2f с)" % laser_t[0])
	check(laser_t[0] >= 0.7, "лазер горит ~0.8 с до первой пули")
	check(ok, "очередь попала по Тору (%s)" % str(_hurts))
	var ammo0 := get_tree().get_nodes_in_group("ammo_pickups").size()
	m.take_hit(9999.0, Vector3.ZERO, "melee_finisher")
	await frames(3)
	check(get_tree().get_nodes_in_group("ammo_pickups").size() > ammo0, "Наёмник уронил патроны")
	await _clear()

func _test_waves() -> void:
	print("-- Волны (GDD 12.5)")
	await _load_room(0)
	room.set_physics_process(false)
	await frames(5)
	# Пересоберём старт: очередь первой волны и замер пачек
	for e in room.alive_enemies().duplicate():
		e.queue_free()
	room._alive.clear()
	room._spawn_queue.clear()
	room._wave_index = 0
	room._spawn_wave(0)
	var size0 := room._wave_size
	check(size0 >= 6, "в первой волне толпа корма (%d врагов)" % size0)
	room.set_physics_process(true)
	var max_per_frame := 0
	var last := room.alive_count()
	for i in 120:
		await get_tree().physics_frame
		p.health = p.max_health
		var now := room.alive_count()
		max_per_frame = maxi(max_per_frame, now - last)
		last = now
		if room.pending_spawns() == 0:
			break
	check(max_per_frame >= 2 and max_per_frame <= room.spawn_batch, "поток пачками по 2–3 (до %d за кадр)" % max_per_frame)
	# Убиваем всех, кроме одного: меньше 30 % — следующая волна, не дожидаясь последнего
	var alive := room.alive_enemies().duplicate()
	for k in alive.size() - 1:
		(alive[k] as Enemy).take_hit(9999.0, Vector3.ZERO, "test")
	var ok := await wait_until(3.0, func() -> bool: return room._wave_index == 1 and room.alive_count() > 1)
	check(ok, "волна 2 пошла при остатке < 30 %% (живы %d)" % room.alive_count())
	check(not room._is_cleared, "зал не зачищен, пока жив враг прошлой волны")
	# Таймаут: волна 3 через next_wave_timeout, даже если все живы
	await wait_until(3.0, func() -> bool: return room.pending_spawns() == 0)
	room.next_wave_timeout = 1.0
	ok = await wait_until(4.0, func() -> bool: return room._wave_index == 2)
	check(ok, "следующая волна по таймауту (25 с в игре)")
	for i in 30:
		for e in room.alive_enemies().duplicate():
			if is_instance_valid(e):
				e.take_hit(9999.0, Vector3.ZERO, "test")
		await frames(20)
		if room._is_cleared:
			break
	check(room._is_cleared, "зал зачищен после всех волн")

func _finish() -> void:
	print("=== ИТОГ ENEMY: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
