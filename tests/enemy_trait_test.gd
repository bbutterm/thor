extends Node
## Черты мобов (GDD 12.6, ночь 29.10, Н4): данные шести черт, доля ~20–25 % бойцов и особых, корм/боссы/элита —
## никогда, лимит на зал, значок над головой (общий материал, прячется вдали) и поведение каждой черты.
## godot --headless --path . --fixed-fps 60 res://tests/enemy_trait_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game
var room: Room
var p: Player

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var r := Node.new()
		r.set_script(get_script())
		r.set_meta("runner", true)
		r.name = "EnemyTraitTestRunner"
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
		if is_instance_valid(p):
			p.health = p.max_health

func wait_until(sec: float, cond: Callable) -> bool:
	for i in int(sec * 60.0):
		await frames(1)
		if cond.call():
			return true
	return false

func _load_room() -> void:
	Dialogue.in_run_scenes = false
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(30)
	game = get_tree().current_scene as Game
	room = game.room
	p = game.player
	for i in 300:
		if room._started:
			break
		await frames(1)

func _clear() -> void:
	room.set_physics_process(false)
	room._spawn_queue.clear()
	for e in room.alive_enemies().duplicate():
		if is_instance_valid(e):
			e.queue_free()
	room._alive.clear()
	var props := room.get_node_or_null("Props")
	if props:
		props.queue_free()
	await frames(5)
	p.global_position = room.global_position + Vector3(-2, 0.1, 9)
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2.ZERO
	await frames(10)

func _spawn(kind: String, offset: Vector3, trait_id: String = "") -> Enemy:
	var e := room.spawn_extra(kind, p.global_position + offset)
	if trait_id != "":
		EnemyTraits.assign(e, EnemyTraits.get_def(trait_id))
	return e

func _run() -> void:
	print("=== ENEMY TRAIT TEST ===")
	_test_data()
	_test_shares()
	await _load_room()
	await _test_room_waves()
	await _clear()
	await _test_icon()
	await _test_coward()
	await _test_furious()
	await _test_agile()
	await _test_shouter()
	await _test_heavy()
	await _test_jumper()
	_finish()

func _test_data() -> void:
	print("-- Данные")
	var ids := []
	var looks := {}
	for d in EnemyTraits.defs():
		ids.append(d.id)
		looks[d.icon_shape + str(d.color)] = true
		check(d.handler != null and d.title != "", "%s: обработчик и название" % d.id)
	ids.sort()
	check(ids == ["agile", "coward", "furious", "heavy", "jumper", "shouter"], "шесть черт GDD (%s)" % str(ids))
	check(looks.size() == ids.size(), "у каждой черты свой значок (фигура/цвет)")

func _test_shares() -> void:
	print("-- Доли и лимит")
	var holder := Node.new()
	var got := 0
	var n := 400
	for i in n:
		var e := Enemy.new()
		e.kind = Enemy.Kind.GRUNT if i % 2 == 0 else Enemy.Kind.THROWER
		if EnemyTraits.maybe_assign(holder, e, 0.22, 100000) != null:
			got += 1
		e.free()
	var rate := float(got) / n
	check(rate > 0.15 and rate < 0.3, "черта у ~22 %% бойцов и особых (%.0f %%)" % (rate * 100.0))
	var limited := Node.new()
	var lim := 0
	for i in 20:
		var e := Enemy.new()
		if EnemyTraits.maybe_assign(limited, e, 1.0, 3) != null:
			lim += 1
		e.free()
	check(lim == 3, "не больше 3 на зал (%d)" % lim)
	var never := 0
	for k in [Enemy.Kind.FODDER, Enemy.Kind.BOSS]:
		for i in 50:
			var e := Enemy.new()
			e.kind = k
			if EnemyTraits.maybe_assign(holder, e, 1.0, 100000) != null:
				never += 1
			e.free()
	for i in 50:
		var e := Enemy.new()
		e.set_meta("elite", true)
		if EnemyTraits.maybe_assign(holder, e, 1.0, 100000) != null:
			never += 1
		e.free()
	check(never == 0, "корм, боссы и элита — без черт")
	holder.free()
	limited.free()

func _test_room_waves() -> void:
	print("-- Волны зала")
	# Перезапуск волны 2 зала с повышенными шансами (первая уже вышла при загрузке)
	room._spawn_queue.clear()
	for e in room.alive_enemies().duplicate():
		e.queue_free()
	room._alive.clear()
	room.set_meta("traited", 0)
	room.set_meta("elites", 0)
	room.trait_chance = 0.5
	room.elite_chance = 0.5
	room.max_elites = 3
	await frames(3)
	room._spawn_wave(1)
	var ok := await wait_until(12.0, func() -> bool: return room.pending_spawns() == 0 and room.alive_count() >= 10)
	var traited := 0
	var bad := 0
	for e in room.alive_enemies():
		if e.has_meta("enemy_trait"):
			traited += 1
			if e.kind == Enemy.Kind.FODDER or e.has_meta("elite") or e.get_node_or_null("TraitMark") == null:
				bad += 1
		elif e.get_node_or_null("TraitMark") != null:
			bad += 1
	check(ok and traited >= 1 and traited <= room.max_traited, "в волне черты есть, но не больше лимита (%d)" % traited)
	check(bad == 0, "черты — только у бойцов/особых без элиты, значок только у них")

func _test_icon() -> void:
	print("-- Значок")
	var e := _spawn("grunt", Vector3(0, 0, -5), "heavy")
	await frames(20)
	var mark := e.get_node_or_null("TraitMark") as Node3D
	var icon := mark.get_node("Icon") as MeshInstance3D if mark else null
	check(icon != null and icon.material_override == FX.fx_material("glow") and icon.mesh == FX.shared_mesh("box"), "значок — общий меш и материал")
	check(mark != null and mark.visible, "вблизи значок виден")
	var keep := EnemyTraits.icon_hide_distance
	EnemyTraits.icon_hide_distance = 2.0
	await frames(20)
	check(mark != null and not mark.visible, "вдали значок прячется")
	EnemyTraits.icon_hide_distance = keep
	var plain := _spawn("grunt", Vector3(3, 0, -5))
	check(plain.get_node_or_null("TraitMark") == null, "без черты — без значка")
	await _clear()

func _test_coward() -> void:
	print("-- Трус")
	var e := _spawn("grunt", Vector3(0, 0, -3), "coward")
	var friend := _spawn("grunt", Vector3(4, 0, -6))
	friend.set_physics_process(false)
	friend._noticed_player = false
	await wait_until(3.0, func() -> bool: return e.state == Enemy.State.CHASE)
	var d0 := e.global_position.distance_to(p.global_position)
	e.health = e.max_health * 0.2
	await frames(60)
	var h := EnemyTraits.handler_of(e)
	check(h != null and h.get("fled") == true, "при < 30 % HP — бежит")
	check(e.global_position.distance_to(p.global_position) > d0 + 1.5, "убегает от Тора (%.1f → %.1f м)" % [d0, e.global_position.distance_to(p.global_position)])
	check(friend.is_alert_to_player(), "позвал соседей")
	await _clear()

func _test_furious() -> void:
	print("-- Яростный")
	var e := _spawn("grunt", Vector3(0, 0, -6), "furious")
	await frames(5)
	var s0 := e.move_speed
	var c0 := e.attack_cooldown
	e.take_hit(5.0, Vector3.ZERO, "melee")
	check(e.move_speed > s0 * 1.2 and e.attack_cooldown < c0, "после попадания ускоряется (%.1f → %.1f)" % [s0, e.move_speed])
	var def := EnemyTraits.get_def("furious")
	await frames(int((def.rage_time + 0.3) * 60.0))
	check(is_equal_approx(e.move_speed, s0) and is_equal_approx(e.attack_cooldown, c0), "ярость проходит")
	await _clear()

func _test_agile() -> void:
	print("-- Ловкий")
	var e := _spawn("grunt", Vector3(0, 0, -7), "agile")
	await wait_until(3.0, func() -> bool: return e.state == Enemy.State.CHASE)
	e.set_physics_process(true)
	var h := EnemyTraits.handler_of(e)
	var hand := p.mjolnir
	hand.throw_cooldown = 0.0
	hand.reset_cooldown()
	var to := e.global_position + Vector3(0, 1.0, 0) - p.get_aim_origin()
	p.rotation_target = Vector2(asin(clampf(to.normalized().y, -1, 1)), atan2(-to.x, -to.z))
	await frames(3)
	hand.throw_hammer()
	var ok := await wait_until(1.5, func() -> bool: return int(h.get("dodges")) > 0)
	check(ok, "увернулся от летящего Мьёльнира")
	check(float(h.get("cooldown")) > 0.0, "следующий уворот — через перезарядку")
	hand.force_return_instant()
	await _clear()

func _test_shouter() -> void:
	print("-- Крикун")
	var sleepers: Array[Enemy] = []
	for i in 3:
		var s := _spawn("grunt", Vector3(-6 + i * 3, 0, -12))
		s.set_physics_process(false)
		s._noticed_player = false
		sleepers.append(s)
	await frames(2)
	check(sleepers.all(func(s: Enemy) -> bool: return not s.is_alert_to_player()), "соседи ещё не знают о Торе")
	var e := _spawn("grunt", Vector3(0, 0, -6), "shouter")
	var h := EnemyTraits.handler_of(e)
	var ok := await wait_until(3.0, func() -> bool: return h.get("shouted") == true)
	check(ok and sleepers.all(func(s: Enemy) -> bool: return s.is_alert_to_player()), "заметив Тора, будит всех вокруг (%d)" % int(h.get("woken")))
	await _clear()

func _knock_dist(trait_id: String) -> float:
	var e := _spawn("grunt", Vector3(0, 0, -6), trait_id)
	await wait_until(3.0, func() -> bool: return e.state == Enemy.State.CHASE)
	e.set_physics_process(true)
	e.max_health = 999.0
	e.health = 999.0
	e.stun(3.0)  # стоит на месте: сдвиг — только отбрасывание
	await frames(2)
	var x0 := e.global_position
	e.take_hit(1.0, Vector3(10, 0, 0), "melee")
	await frames(30)
	var d := Vector2(e.global_position.x - x0.x, e.global_position.z - x0.z).length()
	e.queue_free()
	room._alive.erase(e)
	await frames(3)
	return d

func _test_heavy() -> void:
	print("-- Тяжёлый")
	var normal := await _knock_dist("")
	var heavy := await _knock_dist("heavy")
	check(heavy < normal * 0.4, "не отлетает от обычного удара (%.2f против %.2f м)" % [heavy, normal])
	await _clear()

func _test_jumper() -> void:
	print("-- Прыгун")
	var e := _spawn("grunt", Vector3(0, 0, -7), "jumper")
	e.hand_weapon = ""
	var h := EnemyTraits.handler_of(e)
	var air := [false]
	var ok := await wait_until(5.0, func() -> bool:
		if int(h.get("leaps")) > 0 and not e.is_on_floor():
			air[0] = true
		return int(h.get("leaps")) > 0 and e.is_on_floor() and air[0])
	check(ok, "прыгнул к Тору с 6–8 м")
	check(e.global_position.distance_to(p.global_position) < 3.5, "приземлился рядом с Тором (%.1f м)" % e.global_position.distance_to(p.global_position))
	await _clear()

func _finish() -> void:
	print("=== ИТОГ ENEMY TRAIT: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
