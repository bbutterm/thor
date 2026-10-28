extends Node
## Снаряды и опасные зоны (GDD 12.6, НОЧЬ Н2): телеграф зоны, удар, лужа, прыжок спасает, рывок — неуязвимость,
## линия и конус, лимиты зала; каждый вид снаряда попадает, отражается топором; сфера сбивается Мьёльниром;
## новые атаки врагов (веер/навес метателя, сфера и круг шамана, лужа Раздутого, копьё воина, граната наёмника);
## роли поведения (окружение, фланг, прикрытие за щитоносцем, отступление раненого стрелка).
## godot --headless --path . --fixed-fps 60 res://tests/hazard_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game
var room: Room
var p: Player
var _hurts: Array[float] = []
var _immortal := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var r := Node.new()
		r.set_script(get_script())
		r.set_meta("runner", true)
		r.name = "HazardTestRunner"
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
		if _immortal and is_instance_valid(p):
			p.health = p.max_health

func wait_until(sec: float, cond: Callable) -> bool:
	for i in int(sec * 60.0):
		await get_tree().physics_frame
		if _immortal and is_instance_valid(p):
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
	p.hurt.connect(func(a: float) -> void: _hurts.append(a))
	room.set_physics_process(false)
	room._spawn_queue.clear()
	# Чистая площадка: без бочек на линии стрельбы
	var props := room.get_node_or_null("Props")
	if props:
		props.queue_free()
	await _clear()

func _clear() -> void:
	for e in room.alive_enemies().duplicate():
		if is_instance_valid(e):
			e.queue_free()
	room._alive.clear()
	for g in ["hazard_zones", "enemy_projectiles", "brew_puddles", "ammo_pickups"]:
		for n in get_tree().get_nodes_in_group(g):
			n.queue_free()
	for n in room.get_children():
		if n is Blast:
			n.queue_free()
	await frames(5)
	# Линия x = 3 в зале 1 свободна от колонн и блоков
	p.global_position = room.global_position + Vector3(3, 0.1, 8)
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2.ZERO
	p._invuln_left = 0.0
	await frames(20)
	_hurts.clear()

func _spawn(kind: String, offset: Vector3) -> Enemy:
	return room.spawn_extra(kind, p.global_position + offset)

func _dummy(pos: Vector3) -> Enemy:
	var e := room.spawn_extra("grunt", pos)
	e.set_physics_process(false)
	e.max_health = 500.0
	e.health = 500.0
	return e

func _zone(shape: HazardZone.Shape, pos: Vector3, facing: Vector3, size: float, telegraph: float, damage: float) -> HazardZone:
	return HazardZone.make(shape, pos, facing, size, telegraph, damage, Color(1, 0.3, 0.2)).place(room)

func _run() -> void:
	print("=== HAZARD TEST ===")
	await _load_room(0)
	await _test_zone_telegraph()
	await _test_zone_jump_and_dash()
	await _test_zone_shapes()
	await _test_zone_puddle()
	await _test_limits()
	await _test_projectile_kinds()
	await _test_reflect_all()
	await _test_orb_knocked_by_hammer()
	await _test_enemy_attacks()
	await _test_roles()
	_finish()

func _test_zone_telegraph() -> void:
	print("-- Зона: телеграф и удар")
	var z := _zone(HazardZone.Shape.CIRCLE, p.global_position, Vector3.FORWARD, 2.5, 1.0, 15.0)
	await frames(20)
	var k1 := z.progress()
	var s1 := z._fill.scale.x
	check(_hurts.is_empty() and k1 > 0.2 and k1 < 0.6, "во время телеграфа урона нет, контур заполняется (%.2f)" % k1)
	await frames(25)
	check(z.progress() > k1 and z._fill.scale.x > s1, "заливка растёт к удару (%.2f → %.2f)" % [s1, z._fill.scale.x])
	check(z._outline.scale.x >= 2.4, "контур сразу во весь радиус")
	check(z._outline.material_override == FX.fx_material("alpha") and z._fill.material_override == FX.fx_material("alpha"), "общий материал эффектов (без нового на зону)")
	var ok := await wait_until(1.0, func() -> bool: return not _hurts.is_empty())
	check(ok and absf(_hurts[0] - 15.0) < 0.01, "удар зоны по стоящему Тору — 15 (%s)" % str(_hurts))
	await frames(30)
	check(not is_instance_valid(z), "зона без лужи исчезает после удара")
	await _clear()

func _test_zone_jump_and_dash() -> void:
	print("-- Зона: прыжок спасает, рывок — неуязвимость")
	var z := _zone(HazardZone.Shape.CIRCLE, p.global_position, Vector3.FORWARD, 2.5, 5.0, 15.0)
	await frames(3)
	var foot := p.global_position
	check(z.contains(foot), "стоящий Тор — в зоне")
	check(not z.contains(foot + Vector3(0, 1.2, 0)), "Тор в прыжке (1.2 м над полом) — вне зоны")
	p.global_position = foot + Vector3(0, 1.5, 0)
	p.velocity = Vector3.ZERO
	z._strike()
	check(_hurts.is_empty(), "удар зоны не задел Тора в прыжке")
	await _clear()
	var z2 := _zone(HazardZone.Shape.CIRCLE, p.global_position, Vector3.FORWARD, 2.5, 5.0, 15.0)
	await frames(3)
	p.dash._start_dash(Vector3.RIGHT)
	check(p.is_invulnerable(), "рывок даёт неуязвимость")
	z2._strike()
	check(_hurts.is_empty(), "удар зоны во время рывка не прошёл")
	await _clear()

func _test_zone_shapes() -> void:
	print("-- Линия и конус")
	var origin := p.global_position + Vector3(0, 0, -6)
	var line := _zone(HazardZone.Shape.LINE, origin, Vector3.BACK, 8.0, 5.0, 10.0)
	line.width = 1.6
	await frames(2)
	check(line.contains(origin + Vector3(0, 0, 4)) and line.contains(origin + Vector3(0.6, 0, 7.5)), "линия накрывает полосу вдоль направления")
	check(not line.contains(origin + Vector3(2.0, 0, 4)) and not line.contains(origin + Vector3(0, 0, -1.5)), "вбок и позади начала — мимо линии")
	check(line._fill.material_override == FX.fx_material("alpha"), "линия — общий материал")
	var cone := HazardZone.make(HazardZone.Shape.CONE, origin, Vector3.BACK, 6.0, 5.0, 10.0, Color.ORANGE)
	cone.half_angle_deg = 30.0
	cone.place(room)
	await frames(2)
	check(cone.contains(origin + Vector3(0, 0, 5)) and cone.contains(origin + Vector3(1.5, 0, 4)), "конус накрывает сектор впереди")
	check(not cone.contains(origin + Vector3(4, 0, 2)) and not cone.contains(origin + Vector3(0, 0, -3)), "вне угла и позади — мимо конуса")
	check(cone._fill.mesh == FX.shared_mesh("wedge") and cone._fill.material_override == FX.fx_material("alpha_nocull"), "конус — общий меш-сектор и материал")
	await _clear()

func _test_zone_puddle() -> void:
	print("-- Лужа после удара")
	var z := _zone(HazardZone.Shape.CIRCLE, p.global_position, Vector3.FORWARD, 2.5, 0.3, 0.0)
	z.puddle_time = 2.0
	z.puddle_dps = 10.0
	z.puddle_slow = 0.5
	await frames(30)
	check(z.is_puddle(), "после телеграфа осталась лужа")
	await frames(60)
	check(_hurts.size() >= 2, "лужа жжёт, пока стоишь (%d тиков)" % _hurts.size())
	check(PlayerSlow.factor(p) < 1.0, "лужа замедляет")
	var n := _hurts.size()
	p.global_position += Vector3(5, 0, 0)
	await frames(40)
	check(_hurts.size() <= n + 1, "вне лужи урона нет")
	await frames(90)
	check(not is_instance_valid(z), "лужа высыхает")
	await _clear()

func _test_limits() -> void:
	print("-- Лимиты зала")
	var keep_z := room.max_zones
	var keep_p := room.max_projectiles
	room.max_zones = 2
	for i in 2:
		_zone(HazardZone.Shape.CIRCLE, p.global_position + Vector3(8 + i * 4, 0, 0), Vector3.FORWARD, 1.0, 9.0, 0.0)
	await frames(2)
	check(not EnemyRangedAttacks.can_add_zone(room), "больше max_zones зон не ставится")
	var sh := _spawn("shaman", Vector3(0, 0, -9))
	sh.shaman_orb_chance = 0.0
	sh._special_cd = 0.0
	room.max_projectiles = 0
	check(sh.ranged.choose_shaman() == &"wait", "шаман при обоих лимитах ждёт")
	check(sh.ranged.cast_curse() == null and get_tree().get_nodes_in_group("hazard_zones").size() == 2, "круг сверх лимита не появился")
	var t := _spawn("thrower", Vector3(-3, 0, -9))  # не в одной точке с шаманом
	t._cooldown = 0.0
	var thrown := await wait_until(2.0, func() -> bool: return t._attack_count > 0)
	check(not thrown and get_tree().get_nodes_in_group("enemy_projectiles").is_empty(), "метатель при лимите снарядов ждёт")
	room.max_projectiles = 3
	check(t.ranged.can_fire(t, 3) and not t.ranged.can_fire(t, 4), "лимит снарядов — max_projectiles")
	t.thrower_fan_chance = 1.0
	t.thrower_fan_count = 3
	check(t.ranged.choose_thrower() == &"fan", "веер, если влезает")
	t.thrower_fan_count = 5
	check(t.ranged.choose_thrower() != &"fan", "веер сверх лимита заменяется одиночным снарядом")
	room.max_zones = keep_z
	room.max_projectiles = keep_p
	await _clear()

func _fire(kind: EnemyProjectile.Kind, from: Vector3, vel: Vector3, setup: Callable = Callable()) -> EnemyProjectile:
	var proj := EnemyProjectile.new()
	proj.kind = kind
	if setup.is_valid():
		setup.call(proj)
	room.add_child(proj)
	proj.launch(from, vel, 10.0, null)
	return proj

func _test_projectile_kinds() -> void:
	print("-- Снаряды каждого вида попадают")
	var c := p.global_position + Vector3(0, 0.9, 0)
	for k in [EnemyProjectile.Kind.STRAIGHT, EnemyProjectile.Kind.SPEAR, EnemyProjectile.Kind.ORB]:
		_fire(k, c + Vector3(0, 0, -6), Vector3(0, 0, 8), func(pr: EnemyProjectile) -> void:
			if k == EnemyProjectile.Kind.ORB:
				pr.radius = 0.6
				pr.homing = 0.9)
		var ok := await wait_until(2.0, func() -> bool: return not _hurts.is_empty())
		check(ok, "снаряд %s попал по Тору" % EnemyProjectile.Kind.keys()[k])
		await _clear()
	# Навесной: метка на полу, всплеск по площади
	var ground := Loot.floor_point(p, p.global_position)
	var from := c + Vector3(0, 1.0, -9)
	var lob := _fire(EnemyProjectile.Kind.LOB, from, EnemyRangedAttacks.lob_velocity(from, ground, 1.1, 20.0), func(pr: EnemyProjectile) -> void:
		pr.fall_gravity = 20.0
		pr.landing = ground
		pr.flight_time = 1.1
		pr.blast_radius = 1.6)
	await frames(10)
	check(lob._marker != null and lob._marker_ring != null and lob._marker_ring.global_position.distance_to(ground) < 0.2, "навесной: метка падения на полу")
	var ok_l := await wait_until(2.5, func() -> bool: return not _hurts.is_empty())
	check(ok_l, "навесной упал рядом и задел Тора")
	await _clear()
	# Граната: метка, на полу — взрыв с фитилём
	ground = Loot.floor_point(p, p.global_position + Vector3(1.0, 0, 0))
	from = c + Vector3(0, 1.0, -9)
	var gren := _fire(EnemyProjectile.Kind.GRENADE, from, EnemyRangedAttacks.lob_velocity(from, ground + Vector3(0, 0.15, 0), 1.0, 20.0), func(pr: EnemyProjectile) -> void:
		pr.fall_gravity = 20.0
		pr.landing = ground
		pr.flight_time = 1.0
		pr.radius = 0.18
		pr.blast_radius = 2.6
		pr.fuse = 0.5)
	await frames(5)
	check(gren._marker != null, "граната: метка падения")
	var saw_blast := [false]
	var ok_g := await wait_until(3.0, func() -> bool:
		for n in room.get_children():
			if n is Blast:
				saw_blast[0] = true
		return not _hurts.is_empty())
	check(saw_blast[0], "граната на полу — телеграф взрыва (фитиль)")
	check(ok_g, "взрыв гранаты задел Тора")
	await _clear()

func _test_reflect_all() -> void:
	print("-- Отражение — все виды")
	for k in EnemyProjectile.Kind.values():
		var target := _dummy(p.global_position + Vector3(0, 0, -7))
		var proj := _fire(k, p.global_position + Vector3(0, 1.0, -1.2), Vector3(0, 0, 4), func(pr: EnemyProjectile) -> void:
			if k == EnemyProjectile.Kind.LOB or k == EnemyProjectile.Kind.GRENADE:
				pr.fall_gravity = 20.0
				pr.landing = p.global_position
				pr.blast_radius = 1.5)
		await frames(1)
		proj.reflect(Vector3(0, 0, -1))
		check(proj.reflected and proj.fall_gravity == 0.0 and proj._marker == null, "%s отражается и летит прямо (метка убрана)" % EnemyProjectile.Kind.keys()[k])
		var ok := await wait_until(2.0, func() -> bool: return target.health < 500.0)
		check(ok, "отражённый %s бьёт врага (%.0f)" % [EnemyProjectile.Kind.keys()[k], target.health])
		check(_hurts.is_empty(), "отражённый %s не бьёт Тора" % EnemyProjectile.Kind.keys()[k])
		await _clear()
	var z := _zone(HazardZone.Shape.CIRCLE, p.global_position, Vector3.FORWARD, 2.0, 5.0, 10.0)
	check(not z.is_in_group("reflectable") and not z.has_method("reflect"), "зону не отразить")
	await _clear()

func _test_orb_knocked_by_hammer() -> void:
	print("-- Мьёльнир сбивает сферу")
	var hand := p.mjolnir
	hand.throw_cooldown = 0.0
	hand.reset_cooldown()
	var aim := p.get_aim_origin() + p.get_aim_forward() * 7.0
	var orb := _fire(EnemyProjectile.Kind.ORB, aim, -p.get_aim_forward() * 2.0, func(pr: EnemyProjectile) -> void:
		pr.radius = 0.6)
	var g0 := Run.glory
	hand.throw_hammer()
	var ref: WeakRef = weakref(orb)
	var ok := await wait_until(1.5, func() -> bool: return ref.get_ref() == null)
	check(ok and _hurts.is_empty(), "летящий молот сбил сферу, Тор цел")
	check(Run.glory > g0, "за сбитую сферу — Слава (%d → %d)" % [g0, Run.glory])
	hand.force_return_instant()
	await _clear()

func _count_proj(shooter: Node, kind: int = -1) -> int:
	var n := 0
	for pr in get_tree().get_nodes_in_group("enemy_projectiles"):
		if is_instance_valid(pr) and pr.shooter == shooter and (kind < 0 or pr.kind == kind):
			n += 1
	return n

func _test_enemy_attacks() -> void:
	print("-- Новые атаки врагов")
	var t := _spawn("thrower", Vector3(0, 0, -10))
	t.thrower_fan_chance = 1.0
	t.thrower_fan_count = 4
	var fan := await wait_until(5.0, func() -> bool: return _count_proj(t) >= 4)
	check(fan, "метатель: веер из 4 снарядов")
	await _clear()
	t = _spawn("thrower", Vector3(0, 0, -10))
	t.thrower_fan_chance = 0.0
	t.thrower_lob_chance = 1.0
	var lob := await wait_until(5.0, func() -> bool: return _count_proj(t, EnemyProjectile.Kind.LOB) >= 1)
	check(lob, "метатель: навесной бросок")
	await _clear()
	var sh := _spawn("shaman", Vector3(0, 0, -10))
	sh._ritual_left = 99.0
	sh._special_cd = 0.0
	sh.shaman_orb_chance = 1.0
	sh.alert_to_player()
	var orb := await wait_until(4.0, func() -> bool: return _count_proj(sh, EnemyProjectile.Kind.ORB) >= 1)
	check(orb, "шаман: медленная сфера")
	await _clear()
	sh = _spawn("shaman", Vector3(0, 0, -10))
	sh._ritual_left = 99.0
	sh._special_cd = 0.0
	sh.shaman_orb_chance = 0.0
	sh.alert_to_player()
	var zone := [null]
	var curse := await wait_until(4.0, func() -> bool:
		for z in get_tree().get_nodes_in_group("hazard_zones"):
			if z.source_node == sh:
				zone[0] = z
		return zone[0] != null)
	check(curse and (zone[0] as HazardZone).global_position.distance_to(p.global_position) < 1.5, "шаман: круг проклятия под Тором")
	check(curse and (zone[0] as HazardZone).puddle_time > 0.0, "круг проклятия оставляет лужу")
	await _clear()
	var b := _spawn("bloated", Vector3(0, 0, -12))
	b.set_physics_process(false)
	await frames(3)
	b.take_hit(200.0, Vector3.ZERO, "ranged")
	await frames(3)
	var puddles := get_tree().get_nodes_in_group("brew_puddles").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	check(puddles.size() == 1, "Раздутый после взрыва оставил лужу")
	await _clear()
	var g := _spawn("grunt", Vector3(0, 0, -10))
	g.hand_weapon = "q_spear"
	g.alert_to_player()
	var spear := await wait_until(4.0, func() -> bool: return _count_proj(g, EnemyProjectile.Kind.SPEAR) >= 1)
	check(spear, "воин с копьём бросает его с 8–12 м")
	var hit := await wait_until(2.0, func() -> bool: return not _hurts.is_empty())
	check(hit, "копьё долетело до Тора")
	await _clear()
	var m := _spawn("merc", Vector3(0, 0, -10))
	m.merc_grenade_chance = 1.0
	var gren := await wait_until(5.0, func() -> bool: return _count_proj(m, EnemyProjectile.Kind.GRENADE) >= 1)
	check(gren, "наёмник: граната с меткой")
	await _clear()

func _test_roles() -> void:
	print("-- Роли поведения")
	# Открытый участок зала 1 без колонн и блоков на подходе
	p.global_position = room.global_position + Vector3(-2, 0.1, 9)
	await frames(10)
	var grunts: Array[Enemy] = []
	for i in 4:
		var e := _spawn("grunt", Vector3(-3 + i * 2, 0, -7))
		e.hand_weapon = ""
		e.set_meta("tactic_role", "surround")
		e.tactics.assign()
		grunts.append(e)
	var angles: Array[float] = []
	for e in grunts:
		angles.append(e._slot_angle)
	var spread := true
	for i in angles.size():
		for j in range(i + 1, angles.size()):
			spread = spread and absf(angle_difference(angles[i], angles[j])) > 0.5
	check(spread, "окружение: у бойцов разные точки круга")
	await frames(240)
	var dirs: Array[Vector3] = []
	for e in grunts:
		if is_instance_valid(e):
			var d := e.global_position - p.global_position
			d.y = 0
			dirs.append(d.normalized())
	var max_sep := 0.0
	for i in dirs.size():
		for j in range(i + 1, dirs.size()):
			max_sep = maxf(max_sep, rad_to_deg(dirs[i].angle_to(dirs[j])))
	check(dirs.size() == 4 and max_sep > 90.0, "бойцы обступили Тора с разных сторон (размах %.0f°)" % max_sep)
	check(not _hurts.is_empty(), "окружающие бьют (очереди нет)")
	await _clear()
	var f := _spawn("grunt", Vector3(0, 0, -12))
	f.set_meta("tactic_role", "flank")
	f.tactics.assign()
	var to_p := p.global_position - f.global_position
	to_p.y = 0.0
	var flank_dir := f.tactics.melee_dir(to_p.length(), to_p.normalized())
	check(flank_dir.dot(to_p.normalized()) < 0.93, "фланг: обход сбоку, а не в лоб (%.2f)" % flank_dir.dot(to_p.normalized()))
	await _clear()
	var shield := _spawn("shieldbearer", Vector3(0, 0, -8))
	shield.set_physics_process(false)
	var t := _spawn("thrower", Vector3(5, 0, -12))
	t._cooldown = 99.0
	t.set_meta("tactic_role", "cover")
	t.tactics.assign()
	var covered := await wait_until(6.0, func() -> bool: return t.tactics.is_covered())
	check(covered, "прикрытие: метатель встал за щитоносцем")
	await _clear()
	var r := _spawn("thrower", Vector3(0, 0, -9))
	r._cooldown = 99.0
	await wait_until(4.0, func() -> bool: return r.state == Enemy.State.CHASE)
	await frames(5)
	var d0 := r.global_position.distance_to(p.global_position)
	r.health = r.max_health * 0.2
	await frames(60)
	check(r._retreated and r.global_position.distance_to(p.global_position) > d0 + 1.0, "раненый стрелок отступает (%.1f → %.1f м)" % [d0, r.global_position.distance_to(p.global_position)])
	await _clear()

func _finish() -> void:
	print("=== ИТОГ HAZARD: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
