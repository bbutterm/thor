extends Node
## Элита (GDD 12.4): каждый вид врага с каждым модификатором появляется и умирает без ошибок; элита с каждым
## модификатором доходит и бьёт; проверки модификаторов: броня держит первые 3 У (кирка ломает сразу),
## Быстрый ×1.5, Ледяной замедляет Тора, Вампир лечится ударами, Взрывной взрывается после смерти,
## Призыватель зовёт 3 корма, Огненный оставляет огонь (не больше лимита) и он жжёт Тора; гарантированный дроп.
## godot --headless --path . --fixed-fps 60 res://tests/elite_test.tscn

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
		r.name = "EliteTestRunner"
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

func wait_until(sec: float, cond: Callable, immortal: bool = true) -> bool:
	for i in int(sec * 60.0):
		await get_tree().physics_frame
		if immortal and is_instance_valid(p):
			p.health = p.max_health
		if cond.call():
			return true
	return false

func _home() -> void:
	p.global_position = room.global_position + Vector3(0, 0.1, 4)
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2.ZERO

func _clear() -> void:
	for e in room.alive_enemies().duplicate():
		if is_instance_valid(e):
			e.queue_free()
	room._alive.clear()
	for g in ["pickups", "ammo_pickups"]:
		for n in get_tree().get_nodes_in_group(g):
			n.queue_free()
	await frames(4)
	_home()
	await frames(2)
	_hurts.clear()

## Элита вида kind с модификатором mod в offset от Тора (добавлена в зал и учтена в нём).
func _elite(kind: String, mod: EliteModifier, offset: Vector3) -> Enemy:
	var e := room._make_enemy(kind)
	Loot.make_elite(e, mod)
	e.position = room.to_local(p.global_position + offset)
	room.add_child(e)
	room._register(e)
	return e

func _run() -> void:
	print("=== ELITE TEST ===")
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(30)
	game = get_tree().current_scene as Game
	room = game.room
	p = game.player
	p.hurt.connect(func(a: float) -> void: _hurts.append(a))
	room.set_physics_process(false)
	room._spawn_queue.clear()
	await _clear()
	var mods := Loot.elite_modifiers()
	var ids := mods.map(func(m: EliteModifier) -> String: return m.id)
	check(mods.size() == 7, "7 модификаторов (%s)" % ", ".join(ids))
	for want in ["fire", "ice", "armored", "fast", "explosive", "vampire", "summoner"]:
		check(want in ids, "есть модификатор %s" % want)
	await _test_all_combos(mods)
	await _test_each_hits(mods)
	await _test_armored()
	await _test_fast()
	await _test_ice()
	await _test_vampire()
	await _test_explosive()
	await _test_summoner()
	await _test_fire()
	await _test_drop_and_rules()
	_finish()

## Каждый вид × каждый модификатор: появляется, живёт полсекунды, умирает, без ошибок.
func _test_all_combos(mods: Array[EliteModifier]) -> void:
	print("-- Все виды × все модификаторы")
	var n := 0
	var ok := 0
	for kind in ["grunt", "thrower", "bloated", "shieldbearer", "shaman", "merc"]:
		for m in mods:
			var e := _elite(kind, m, Vector3(randf_range(-3, 3), 0, -8))
			n += 1
			var good0: bool = e.has_meta("elite") and e.get_node_or_null("EliteLabel") != null and e.elite_handlers.size() == 1
			var ew: WeakRef = weakref(e)
			await frames(25)
			if ew.get_ref() == null or e.is_dead:
				# Погиб раньше (взрыв соседа) — тоже без ошибок
				ok += 1 if good0 else 0
				continue
			var good: bool = e.has_meta("elite") and str(e.get_meta("elite_mod")) == m.id and e.get_node_or_null("EliteLabel") != null \
				and e.elite_handlers.size() == 1 and e.elite_glow.a > 0.0
			e.take_hit(9999.0, Vector3.ZERO, "test")
			await frames(3)
			if good and (ew.get_ref() == null or e.is_dead):
				ok += 1
			else:
				print("    не так: %s + %s" % [kind, m.id])
		await frames(60)
		await _clear()
	check(ok == n, "элиты появились с подписью/свечением и умерли: %d/%d" % [ok, n])

## Элита-грунт с каждым модификатором доходит и бьёт.
func _test_each_hits(mods: Array[EliteModifier]) -> void:
	print("-- Каждая элита бьёт")
	for m in mods:
		var e := _elite("grunt", m, Vector3(0, 0, -5))
		var ok := await wait_until(8.0, func() -> bool: return not _hurts.is_empty())
		check(ok, "%s: дошёл и ударил (%s)" % [m.title, str(_hurts.slice(0, 3))])
		check(ok and _hurts.max() >= 12.0 * 1.5 - 0.01, "%s: урон элиты ×1.5" % m.title)
		if is_instance_valid(e):
			e.take_hit(9999.0, Vector3.ZERO, "test")
		await frames(80)
		await _clear()

func _test_armored() -> void:
	print("-- Бронированный")
	var m := Loot.get_elite_modifier("armored")
	var e := _elite("grunt", m, Vector3(0, 0, -6))
	e.set_physics_process(false)
	await frames(30)
	var hp := e.health
	e.take_hit(30.0, Vector3.ZERO, "hammer")
	check(is_equal_approx(e.health, hp), "30 урона съела броня")
	e.take_hit(30.0, Vector3.ZERO, "melee")
	check(is_equal_approx(e.health, hp), "ещё 30 — тоже броня (итого 60 < 66)")
	check((e.get_node("EliteLabel") as Label3D).text.contains("6"), "остаток брони в подписи (%s)" % (e.get_node("EliteLabel") as Label3D).text)
	e.take_hit(30.0, Vector3.ZERO, "melee")
	check(is_equal_approx(e.health, hp - 24.0), "броня 3 У = 66: из 30 прошло 24 (%.0f → %.0f)" % [hp, e.health])
	hp = e.health
	e.take_hit(10.0, Vector3.ZERO, "melee")
	check(is_equal_approx(e.health, hp - 10.0), "после брони урон проходит целиком")
	e.take_hit(9999.0, Vector3.ZERO, "test")
	await _clear()
	# Кирка ломает броню сразу
	var e2 := _elite("grunt", m, Vector3(0, 0, -6))
	e2.set_physics_process(false)
	await frames(30)
	p.equip(Loot.get_def("pickaxe"), 1, false)
	p.weapons.switch_to(WeaponHolder.MELEE, true)
	await frames(2)
	hp = e2.health
	e2.take_hit(20.0, Vector3.ZERO, "melee")
	check(is_equal_approx(e2.health, hp - 20.0), "кирка: урон проходит и броня сломана сразу")
	check((e2.get_node("EliteLabel") as Label3D).text.contains("сломана"), "в подписи «сломана»")
	p.equip(Loot.get_def("axe"), 1, false)
	p.weapons.switch_to(WeaponHolder.MELEE, true)
	e2.take_hit(9999.0, Vector3.ZERO, "test")
	await _clear()

func _test_fast() -> void:
	print("-- Быстрый")
	var plain := room._make_enemy("grunt")
	var base := plain.move_speed
	plain.free()
	var e := _elite("grunt", Loot.get_elite_modifier("fast"), Vector3(0, 0, -8))
	check(is_equal_approx(e.move_speed, base * 1.5), "скорость ×1.5 (%.2f → %.2f)" % [base, e.move_speed])
	e.take_hit(9999.0, Vector3.ZERO, "test")
	await _clear()

func _test_ice() -> void:
	print("-- Ледяной")
	var base := p.move_speed
	var e := _elite("grunt", Loot.get_elite_modifier("ice"), Vector3(0, 0, -4))
	var ok := await wait_until(8.0, func() -> bool: return not _hurts.is_empty())
	await frames(2)
	check(ok and p.move_speed < base * 0.7, "удар замедлил Тора (%.2f → %.2f)" % [base, p.move_speed])
	check(PlayerSlow.factor(p) < 1.0, "на Торе компонент замедления")
	e.take_hit(9999.0, Vector3.ZERO, "test")
	await _clear()
	await wait_until(3.0, func() -> bool: return is_equal_approx(p.move_speed, base))
	check(is_equal_approx(p.move_speed, base), "замедление прошло, скорость вернулась (%.2f)" % p.move_speed)

func _test_vampire() -> void:
	print("-- Вампир")
	var e := _elite("grunt", Loot.get_elite_modifier("vampire"), Vector3(0, 0, -4))
	await frames(20)
	e.health = e.max_health * 0.5
	var h0 := e.health
	var ok := await wait_until(8.0, func() -> bool: return not _hurts.is_empty())
	await frames(2)
	check(ok and e.health > h0, "удар по Тору лечит вампира (%.0f → %.0f)" % [h0, e.health])
	e.take_hit(9999.0, Vector3.ZERO, "test")
	await _clear()

func _test_explosive() -> void:
	print("-- Взрывной")
	var e := _elite("grunt", Loot.get_elite_modifier("explosive"), Vector3(0, 0, -2))
	e.set_physics_process(false)
	await frames(20)
	_hurts.clear()
	e.take_hit(9999.0, Vector3.ZERO, "test")
	await frames(2)
	var blast := false
	for n in room.get_children():
		if n is Blast:
			blast = true
	check(blast, "после смерти — телеграф взрыва")
	check(_hurts.is_empty(), "до взрыва есть время уйти")
	await wait_until(1.5, func() -> bool: return not _hurts.is_empty())
	check(not _hurts.is_empty(), "взрыв задел стоящего рядом Тора (%s)" % str(_hurts))
	await _clear()

func _test_summoner() -> void:
	print("-- Призыватель")
	var e := _elite("grunt", Loot.get_elite_modifier("summoner"), Vector3(0, 0, -10))
	var h := e.get_node("Elite_summoner")
	var ok := await wait_until(12.0, func() -> bool: return int(h.get("summoned")) >= 3)
	var fodder := 0
	for x in room.alive_enemies():
		if x.kind == Enemy.Kind.FODDER:
			fodder += 1
	check(ok and fodder >= 3, "через ~8 с позвал 3 корма (%d)" % fodder)
	await _clear()

func _test_fire() -> void:
	print("-- Огненный")
	var e := _elite("grunt", Loot.get_elite_modifier("fire"), Vector3(0, 0, -10))
	var m := Loot.get_elite_modifier("fire")
	var max_zones := [0]
	await wait_until(6.0, func() -> bool:
		var n := 0
		for c in room.get_children():
			if c.get("hostile") == true and not c.is_queued_for_deletion():
				n += 1
		max_zones[0] = maxi(max_zones[0], n)
		return false)
	check(max_zones[0] >= 2, "на ходу оставляет огонь (%d луж)" % max_zones[0])
	check(max_zones[0] <= m.trail_max, "не больше лимита (%d ≤ %d)" % [max_zones[0], m.trail_max])
	e.take_hit(9999.0, Vector3.ZERO, "test")
	await frames(2)
	# Огонь жжёт Тора, а врагов — нет
	var f := preload("res://weapons/fire_zone.gd").new()
	f.hostile = true
	room.add_child(f)
	f.setup(p.global_position, 1.5, 2.0, 12.0, false)
	var dummy := room.spawn_extra("grunt", p.global_position + Vector3(0.8, 0, 0))
	dummy.set_physics_process(false)
	_hurts.clear()
	var ok := await wait_until(1.5, func() -> bool: return not _hurts.is_empty(), false)
	check(ok, "огонь элиты жжёт Тора (%s)" % str(_hurts))
	check(dummy.health >= dummy.max_health, "и не жжёт своих")
	p.health = p.max_health
	await _clear()

func _test_drop_and_rules() -> void:
	print("-- Дроп и правила")
	var picks0 := get_tree().get_nodes_in_group("pickups").size()
	var e := _elite("grunt", Loot.get_elite_modifier("fast"), Vector3(0, 0, -6))
	await frames(10)
	# С серебром (блок К) элита в 40 % роняет серебро вместо оружия — здесь проверяем оружие
	var silver_chance := Loot.elite_silver_chance
	Loot.elite_silver_chance = 0.0
	e.take_hit(9999.0, Vector3.ZERO, "melee_finisher")
	Loot.elite_silver_chance = silver_chance
	await frames(5)
	check(get_tree().get_nodes_in_group("pickups").size() > picks0, "элита гарантированно роняет оружие")
	await _clear()
	# Корм элитой не бывает, особый — бывает
	var f := room._make_enemy("fodder")
	Loot.maybe_make_elite(room, f, 1.0, 99)
	check(not f.has_meta("elite"), "корм элитой не бывает")
	f.free()
	var s := room._make_enemy("shieldbearer")
	Loot.maybe_make_elite(room, s, 1.0, 99)
	check(s.has_meta("elite") and s.has_meta("elite_mod"), "особый враг становится элитой со случайным модификатором (%s)" % str(s.get_meta("elite_mod", "")))
	s.free()

func _finish() -> void:
	print("=== ИТОГ ELITE: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
