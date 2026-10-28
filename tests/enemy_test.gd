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
const ENEMY_PROJECTILE := preload("res://enemies/enemy_projectile.gd")

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
	# П3: в залах до 20 врагов на экране; проверки ставят врагов сверх волн больше лимита
	room.max_alive = 0
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
	# Лужи (Раздутый оставляет брагу, GDD 12.6) и зоны не переносятся в следующую проверку
	for g in ["ammo_pickups", "brew_puddles", "hazard_zones", "enemy_projectiles"]:
		for n in get_tree().get_nodes_in_group(g):
			n.queue_free()
	await frames(5)
	p.global_position = room.global_position + Vector3(0, 0.1, 4)
	p.velocity = Vector3.ZERO
	_hurts.clear()

## Аудио запускается асинхронно из общей очереди; учитываем и версию владельца.
func _warning_path(event: String, fallback: String) -> String:
	var entry: Dictionary = Audio._owner_sfx.get(event, Audio.resolve("res://" + fallback))
	return str(entry.get("path", ""))

func _warnings_queued_after(first: int, path: String) -> int:
	var count := 0
	for item in Audio.queue.slice(first):
		if item is Dictionary and str(item.get("path", "")) == path:
			count += 1
	return count

## Изолируем проверку от звуков предыдущих сцен, сохраняя штатный пул из 12 плееров.
func _reset_sfx_pool() -> void:
	Audio.queue.clear()
	Audio.available.clear()
	for n in Audio.get_children():
		if n is AudioStreamPlayer and n.bus == Audio.bus:
			n.stop()
			n.stream = null
			Audio.available.append(n)

func _sfx_playing(path: String) -> bool:
	return Audio.get_children().any(func(n: Node) -> bool:
		return (n is AudioStreamPlayer and n.bus == Audio.bus and n.playing
			and n.stream != null and n.stream.resource_path == path))

func _run() -> void:
	print("=== ENEMY TEST ===")
	await _load_room(0)
	await _empty_room()
	await _test_fodder()
	await _test_horde_hits()
	await _test_horde_wide_hit()
	await _test_bloated()
	await _test_death_marks()
	await _test_shield()
	await _test_shaman()
	await _test_thrower_warning()
	await _test_merc()
	await _test_warning_waits("thrower", "thrower_aim", "sounds/sfx/enemy_growl.wav")
	await _test_warning_waits("merc", "merc_aim", "sounds/sfx/gun_reload.wav")
	await _test_warning_saturation("thrower", "thrower_aim", "sounds/sfx/enemy_growl.wav", true)
	await _test_warning_saturation("thrower", "thrower_aim", "sounds/sfx/enemy_growl.wav", false)
	await _test_warning_saturation("merc", "merc_aim", "sounds/sfx/gun_reload.wav", true)
	await _test_warning_saturation("merc", "merc_aim", "sounds/sfx/gun_reload.wav", false)
	await _test_interrupted_warning()
	await _test_horde_glory_and_corpses()
	await _test_waves()
	await _test_fall_and_reflect()
	await _test_vertical_melee()
	await _test_hit_feel()
	await _test_wave_corpses()
	await _test_actual_ledge_push()
	_finish()

func _test_fodder() -> void:
	print("-- Драугр-корм")
	var e := _spawn("fodder", Vector3(0, 0, -4))
	check(e != null and e.kind == Enemy.Kind.FODDER, "корм появился")
	check(is_equal_approx(e.max_health, 0.35 * EnemyDef.U), "HP корма 0.35 У (%.1f)" % e.max_health)
	var scene_enemy := (load("res://enemies/fodder.tscn") as PackedScene).instantiate() as Enemy
	check(is_equal_approx(scene_enemy.max_health, e.max_health), "сцена и данные корма задают одинаковое HP")
	scene_enemy.free()
	var candidate := room._make_enemy("fodder")
	Loot.maybe_make_elite(room, candidate, 1.0, 100)
	check(not candidate.has_meta("elite"), "корм не превращается в элиту даже при 100%% шансе")
	candidate.free()
	check(e._humanoid != null and e._humanoid.parts.is_empty() and e.hand_weapon == "", "корм облегчённый: одна модель, без оружия и частей")
	var ok := await wait_until(8.0, func() -> bool: return _hurts.size() > 0)
	check(ok, "корм дошёл и ударил (%s)" % str(_hurts))
	check(ok and absf(_hurts[0] - 5.0) < 0.01, "удар корма — 5")
	await _clear()

## Настоящие попадания при минимальном уроне тел Батрака и Гонца (удар спереди).
func _test_horde_hits() -> void:
	print("-- Одно попадание по корму слабым телом")
	var old_body: BodyDef = Run.body
	var old_crit := p.crit_chance_base
	var keeper := _spawn("grunt", Vector3(0, 0, 30))
	keeper.set_physics_process(false)
	for body_id in ["thrall", "courier"]:
		Run.body = load("res://run/bodies/" + body_id + ".tres") as BodyDef
		p.apply_body_and_runes(Run.body, Run)
		p.crit_chance_base = 0.0
		for mode in ["axe", "sword", "staff", "axe_dive", "hammer"]:
			FX.reset_time()
			p.style.reset()
			var weapon := "axe" if mode in ["axe_dive", "hammer"] else str(mode)
			p.weapons.equip(Loot.get_def(weapon), 1, false)
			p.weapons.switch_to(WeaponHolder.MELEE, true)
			var e := _spawn("fodder", Vector3(0, 0, -1.5))
			e.set_physics_process(false)
			e.rotation.y = 0.0  # смотрит на Тора, действует изъян Гонца
			await frames(2)
			var amount := 0.0
			if mode == "hammer":
				var proj := MjolnirProjectile.new()
				room.add_child(proj)
				proj.set_physics_process(false)
				proj.hand = p.mjolnir
				proj.global_position = e.global_position + Vector3.UP
				amount = proj.damage() * p.outgoing_damage_mult(e, "hammer")
				proj._on_hit(e, Vector3.FORWARD)
				proj.queue_free()
			elif mode == "axe_dive":
				amount = p.axe._skill_damage(p.axe.def.skill_dive_damage_mult) * p.outgoing_damage_mult(e, "melee_heavy")
				p.axe._skill_mode = "axe_dive"
				p.axe._on_weapon_skill_landed("axe_dive")
			else:
				p.axe._begin_stage(0)
				amount = p.axe._stage_damage() * p.outgoing_damage_mult(e, "melee")
				p.axe._do_hitbox()
			check(e.is_dead, "%s: %s одним попаданием (%.1f урона, %.1f HP)" % [body_id, mode, amount, e.max_health])
			if mode == "axe_dive":
				check(absf(amount - 8.4) < 0.01, "%s: минимальный урон воздушной рубки 8.4" % body_id)
			for n in get_tree().get_nodes_in_group("debris"):
				n.queue_free()
			await frames(2)
	Run.body = old_body
	p.apply_body_and_runes(old_body, Run)
	p.crit_chance_base = old_crit
	p.style.reset()
	FX.reset_time()
	await _clear()

## Больше прежних 16 пересечений: один взмах поражает всех внутри хитбокса по одному разу.
func _test_horde_wide_hit() -> void:
	print("-- Широкий взмах по толпе")
	p.weapons.equip(Loot.get_def("axe"), 1, false)
	p.weapons.switch_to(WeaponHolder.MELEE, true)
	p.style.reset()
	var targets: Array[Enemy] = []
	for i in 24:
		var x := (float(i % 6) - 2.5) * 0.35
		var z := -1.3 - float(int(i / 6)) * 0.2
		var e := _spawn("fodder", Vector3(x, 0, z))
		e.set_physics_process(false)
		e.max_health = 1000.0  # мишень переживает взмах, чтобы измерить число попаданий
		e.health = 1000.0
		targets.append(e)
	await frames(3)
	p.axe._begin_stage(0)
	p.axe._do_hitbox()
	var damaged := targets.filter(func(e: Enemy) -> bool: return e.health < 1000.0).size()
	check(damaged == targets.size(), "взмах задел всех %d врагов (%d)" % [targets.size(), damaged])
	var health_after: Array[float] = []
	for e in targets:
		health_after.append(e.health)
	p.axe._do_hitbox()
	var once := true
	for i in targets.size():
		once = once and is_equal_approx(targets[i].health, health_after[i])
	check(once, "повторный расчёт того же взмаха не наносит повторный урон")
	FX.reset_time()
	await _clear()

## Массовая награда считается через реальные смерти; трупы не копятся бесконечно.
func _test_horde_glory_and_corpses() -> void:
	print("-- Слава и тела орды")
	var keeper := _spawn("grunt", Vector3(0, 0, 30))
	keeper.set_physics_process(false)
	for n in get_tree().get_nodes_in_group("debris"):
		n.queue_free()
	await frames(2)
	Run.glory = 0
	Run.kills = 0
	Run.streak = 0
	Run.best_streak = 0
	Run._recent_kill_times.clear()
	Run.glory_fodder_multikill = false
	Run.glory_fodder_flat = true
	p.style.reset()
	ComicFX._kill_times.clear()
	for i in 20:
		Run.style_glory_mult = 1.0
		var e := _spawn("fodder", Vector3(float(i) * 0.1, 3, -3))
		e.set_physics_process(false)
		e.take_hit(100.0, Vector3(8, 3, 0), "melee")
	check(Run.glory == 40 and Run.kills == 20 and Run.streak == 20 and Run._recent_kill_times.is_empty(),
		"20 настоящих смертей корма дают 40 Славы и сохраняют серию (%d)" % Run.glory)
	check(p.style._kill_times.size() == 20 and ComicFX._kill_times.size() == 20,
		"все убийства корма учтены для шкалы и комикса")
	var bodies := get_tree().get_nodes_in_group("debris").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	check(bodies.size() == 10, "из 20 смертей остаётся 10 тел (%d)" % bodies.size())
	var layers_ok := bodies.all(func(n: Node) -> bool:
		return n is RigidBody3D and n.collision_layer == 1 << 6 and n.collision_mask == (1 | (1 << 3) | (1 << 6)))
	check(layers_ok, "тела на слое 7, сталкиваются с миром, пропсами и другими телами")
	# П3: корм — мясо: 3–5 кусков на смерть из общих мешей, общий лимит, тот же слой
	var pieces: Array = FodderGibs._pieces.get("res://enemies/fodder.tscn", [])
	check(pieces.size() >= 3 and pieces.size() <= 5, "корм режется на 3–5 кусков (%d)" % pieces.size())
	var gibs := get_tree().get_nodes_in_group(FodderGibs.GROUP).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	var limit := int((load("res://enemies/enemy.gd") as Script).get_property_default_value("gib_limit"))
	check(gibs.size() > 0 and gibs.size() <= limit, "куски корма разлетелись и не больше лимита (%d ≤ %d)" % [gibs.size(), limit])
	check(gibs.all(func(n: Node) -> bool: return n is RigidBody3D and n.collision_layer == 1 << 6 and n.get_node_or_null("Mesh") != null),
		"куски — физтела на слое 7 с мешем")
	var shared := true
	for n in gibs:
		var mi := (n as Node).get_node_or_null("Mesh") as MeshInstance3D
		shared = shared and mi != null and mi.mesh in FodderGibs.cached_meshes() and mi.material_override == null
	check(shared, "у кусков общие меши и материалы модели (без новых материалов)")
	check(FodderGibs.cached_meshes().size() == pieces.size(), "меши кусков нарезаны один раз на вид (%d)" % FodderGibs.cached_meshes().size())
	check(p.camera_fx.trauma > 0.0, "мульти-килл корма трясёт камеру")
	await frames(1)
	var moving := bodies.any(func(n: Node) -> bool:
		return is_instance_valid(n) and (n as RigidBody3D).linear_velocity.x > 1.0)
	check(moving, "тело корма летит по направлению толчка")
	var payouts: Array[int] = []
	for i in 5:
		Run.style_glory_mult = 1.0
		var before := Run.glory
		var fighter := _spawn("grunt", Vector3(0, 0, -8))
		fighter._die("melee")
		payouts.append(Run.glory - before)
	check(payouts == [5, 6, 7, 8, 9] and Run.glory == 75,
		"после корма пять бойцов дают 5+6+7+8+9, всего %d" % Run.glory)
	Run.style_glory_mult = 1.0
	var before := Run.glory
	var special := _spawn("thrower", Vector3(0, 0, -8))
	special._die("melee")
	check(Run.glory - before == 13, "особый получает 8 базовых + 5 мультикилл за бойцов")
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

## Читаем метки сразу, до следующего кадра, когда Perf переносит их в историю.
func _mark_count(name: String) -> int:
	var count := 0
	for mark in Perf._marks:
		if mark == name or mark == "*" + name:
			count += 1
	return count

func _test_death_marks() -> void:
	print("-- Метки смерти врагов")
	# Оставляем одного врага живым, чтобы зал не завершился во время проверки.
	var keeper := _spawn("fodder", Vector3(0, 0, 20))
	var ordinary := _spawn("fodder", Vector3(-12, 0, -8))
	var killed_bloated := _spawn("bloated", Vector3(12, 0, -8))
	var self_bloated := _spawn("bloated", Vector3(0, 0, -22))
	for e in [keeper, ordinary, killed_bloated, self_bloated]:
		e.set_physics_process(false)
	var deaths := _mark_count("enemy_death")
	ordinary._die("ranged")
	check(_mark_count("enemy_death") == deaths + 1, "смерть обычного врага отмечается один раз")
	ordinary._die("ranged")
	check(_mark_count("enemy_death") == deaths + 1, "повторная обработка смерти не добавляет метку")
	var blasts := _mark_count("blast")
	killed_bloated._die("ranged")
	check(_mark_count("enemy_death") == deaths + 2 and _mark_count("blast") == blasts + 1,
		"при убийстве Раздутого отмечены и смерть, и взрыв")
	self_bloated._die("self_blast")
	check(_mark_count("enemy_death") == deaths + 3 and _mark_count("blast") == blasts + 2,
		"при самоподрыве Раздутого отмечены и смерть, и взрыв")
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

func _test_thrower_warning() -> void:
	print("-- Предупреждение метателя")
	var t := _spawn("thrower", Vector3(0, 0, -8))
	var was_processing := Audio.is_processing()
	Audio.set_process(false)  # Снимаем срез очереди до её обычного потребления.
	_reset_sfx_pool()
	var first: int = Audio.queue.size()
	var path := _warning_path("thrower_aim", "sounds/sfx/enemy_growl.wav")
	t._begin_windup(false)
	check(t.state == Enemy.State.WINDUP and t._attack_count == 0 and _hurts.is_empty()
		and _warnings_queued_after(first, path) == 1,
		"метатель ставит звуковое предупреждение в очередь до выпуска снаряда")
	Audio._process(0.0)
	check(_sfx_playing(path) and t.state == Enemy.State.WINDUP and t._attack_count == 0,
		"при свободном канале предупреждение метателя воспроизводится до выпуска")
	first = Audio.queue.size()
	await frames(10)
	check(t.state == Enemy.State.WINDUP and t._attack_count == 0
		and _warnings_queued_after(first, path) == 0,
		"предупреждение метателя не повторяется каждый кадр замаха")
	Audio.set_process(was_processing)
	var released := await wait_until(2.0, func() -> bool: return is_instance_valid(t) and t._attack_count > 0)
	var projectile := get_tree().get_nodes_in_group("reflectable").any(func(n: Node) -> bool:
		return is_instance_valid(n) and n.get_script() == ENEMY_PROJECTILE and n.get("shooter") == t)
	check(released and projectile, "после предупреждения метатель действительно выпускает снаряд")
	for n in get_tree().get_nodes_in_group("reflectable"):
		if is_instance_valid(n) and n.get_script() == ENEMY_PROJECTILE and n.get("shooter") == t:
			n.queue_free()
	await _clear()

func _test_merc() -> void:
	print("-- Наёмник Локи")
	var m := _spawn("merc", Vector3(0, 0, -10))
	var laser := [false]
	var laser_t := [0.0]
	var was_processing := Audio.is_processing()
	Audio.set_process(false)
	_reset_sfx_pool()
	var first: int = Audio.queue.size()
	var path := _warning_path("merc_aim", "sounds/sfx/gun_reload.wav")
	m._begin_windup(false)
	check(m.state == Enemy.State.WINDUP and m._attack_count == 0 and _hurts.is_empty()
		and _warnings_queued_after(first, path) == 1,
		"наёмник ставит звуковое предупреждение до первой пули")
	Audio._process(0.0)
	check(_sfx_playing(path) and m.state == Enemy.State.WINDUP and m._attack_count == 0,
		"при свободном канале предупреждение наёмника воспроизводится до первой пули")
	first = Audio.queue.size()
	for i in 10:
		await get_tree().physics_frame
		if m._laser and m._laser.visible:
			laser[0] = true
			laser_t[0] += 1.0 / 60.0
	check(m.state == Enemy.State.WINDUP and m._attack_count == 0 and _hurts.is_empty()
		and _warnings_queued_after(first, path) == 0,
		"наёмник не повторяет предупреждение каждый кадр прицеливания")
	Audio.set_process(was_processing)
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

## Если канал освободился вовремя, ожидавшее предупреждение всё-таки играет до атаки.
func _test_warning_waits(kind: String, event: String, fallback: String) -> void:
	print("-- Канал освободился вовремя: ", kind)
	var e := _spawn(kind, Vector3(0, 0, -8))
	var was_processing := Audio.is_processing()
	Audio.set_process(false)
	_reset_sfx_pool()
	var path := _warning_path(event, fallback)
	var looping: AudioStreamWAV = (load("res://sounds/sfx/enemy_growl.wav") as AudioStreamWAV).duplicate()
	looping.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var slots := Audio.available.duplicate()
	for slot in slots:
		slot.stream = looping
		slot.play()
	Audio.available.clear()
	e._begin_windup(false)
	await frames(5)
	var slot: AudioStreamPlayer = slots[0]
	slot.stop()
	Audio.available.append(slot)
	Audio._process(0.0)
	check(_sfx_playing(path) and e.state == Enemy.State.WINDUP and e._attack_count == 0,
		"%s дождался канала и предупредил до атаки" % kind)
	var released := await wait_until(2.0, func() -> bool: return is_instance_valid(e) and e._attack_count > 0)
	check(released, "%s атакует после предупредившего сигнала" % kind)
	for n in get_tree().get_nodes_in_group("reflectable"):
		if is_instance_valid(n) and n.get_script() == ENEMY_PROJECTILE and n.get("shooter") == e:
			n.queue_free()
	_reset_sfx_pool()
	Audio.set_process(was_processing)
	await _clear()

## Все каналы реально заняты: ожидающий сигнал не должен зазвучать уже после выстрела.
func _test_warning_saturation(kind: String, event: String, fallback: String, free_before_attack: bool) -> void:
	print("-- Занятые каналы: ", kind, ", освободить до атаки: ", free_before_attack)
	var e := _spawn(kind, Vector3(0, 0, -8))
	var was_processing := Audio.is_processing()
	Audio.set_process(false)
	_reset_sfx_pool()
	var path := _warning_path(event, fallback)
	Audio._last_played.erase(path)
	var looping: AudioStreamWAV = (load("res://sounds/sfx/enemy_growl.wav") as AudioStreamWAV).duplicate()
	looping.loop_mode = AudioStreamWAV.LOOP_FORWARD  # только в памяти теста
	var slots := Audio.available.duplicate()
	for slot in slots:
		slot.stream = looping
		slot.play()
	Audio.available.clear()
	e._begin_windup(false)
	check(slots.size() == Audio.num_players and Audio.available.is_empty()
		and _warnings_queued_after(0, path) == 1,
		"все каналы заняты, предупреждение %s ожидает в общей очереди" % kind)
	if free_before_attack:
		await frames(int(ceil(e.windup_time * 45.0)))  # 75 % замаха; время реакции уже упущено
		check(e.state == Enemy.State.WINDUP and e._attack_count == 0
			and e._state_time >= e.windup_time * 0.5 and _warnings_queued_after(0, path) == 1,
			"%s ещё не атакует, но половина замаха прошла" % kind)
	else:
		var released := await wait_until(2.0, func() -> bool: return is_instance_valid(e) and e._attack_count > 0)
		check(released and _warnings_queued_after(0, path) == 1,
			"%s атакует, пока сигнал ожидает свободный канал" % kind)
	var slot: AudioStreamPlayer = slots[0]
	slot.stop()
	Audio.available.append(slot)
	Audio._process(0.0)
	check(not Audio._last_played.has(path) and _warnings_queued_after(0, path) == 0,
		"опоздавший сигнал %s не воспроизводится %s" % [kind, "в конце замаха" if free_before_attack else "после атаки"])
	if free_before_attack:
		var released := await wait_until(2.0, func() -> bool: return is_instance_valid(e) and e._attack_count > 0)
		check(released, "%s всё же атакует после пропуска устаревшего сигнала" % kind)
	for n in get_tree().get_nodes_in_group("reflectable"):
		if is_instance_valid(n) and n.get_script() == ENEMY_PROJECTILE and n.get("shooter") == e:
			n.queue_free()
	_reset_sfx_pool()
	Audio.set_process(was_processing)
	await _clear()

## После прерывания старая запись не принадлежит следующему замаху, даже если удара ещё не было.
func _test_interrupted_warning() -> void:
	print("-- Прерванное предупреждение")
	var t := _spawn("thrower", Vector3(0, 0, -8))
	var was_processing := Audio.is_processing()
	Audio.set_process(false)
	_reset_sfx_pool()
	var path := _warning_path("thrower_aim", "sounds/sfx/enemy_growl.wav")
	Audio._last_played.erase(path)
	t._begin_windup(false)
	t._set_state(Enemy.State.STUNNED)
	t._begin_windup(false)
	check(t._attack_count == 0 and _warnings_queued_after(0, path) == 2,
		"после прерывания и нового замаха в очереди два разных предупреждения")
	Audio._process(0.0)
	check(_sfx_playing(path) and _warnings_queued_after(0, path) == 0,
		"старый сигнал пропущен, новый зазвучал до выпуска")
	_reset_sfx_pool()
	Audio.set_process(was_processing)
	await _clear()

func _test_waves() -> void:
	print("-- Волны (GDD 12.5)")
	await _load_room(0)
	# Game запускает зал таймером; дождаться его до ручного перезапуска, иначе
	# штатный старт добавит вторую первую волну в уже созданную очередь.
	var started := await wait_until(3.0, func() -> bool: return room._started)
	check(started, "зал начал первую волну штатным запуском")
	if not started:
		return
	room.set_physics_process(false)
	await frames(5)
	# Пересоберём старт: очередь первой волны и замер пачек
	for e in room.alive_enemies().duplicate():
		e.queue_free()
	room._alive.clear()
	room._spawn_queue.clear()
	room._wave_index = 0
	room.next_wave_timeout = 999.0  # проверяем именно порог, а не таймаут
	room._spawn_wave(0)
	var size0 := room._wave_size
	check(size0 >= 6, "в первой волне толпа корма (%d врагов)" % size0)
	room.set_physics_process(true)
	var max_per_frame := 0
	var last := room.alive_count()
	for i in 300:
		await get_tree().physics_frame
		p.health = p.max_health
		var now := room.alive_count()
		max_per_frame = maxi(max_per_frame, now - last)
		last = now
		if room.pending_spawns() == 0:
			break
	check(max_per_frame >= 2 and max_per_frame <= room.spawn_batch, "поток пачками по 2–3 (до %d за кадр)" % max_per_frame)
	check(room.pending_spawns() == 0, "первая волна полностью вышла из очереди")
	if room.pending_spawns() != 0:
		return
	# Убиваем всех, кроме одного: меньше 30 % — следующая волна, не дожидаясь последнего
	var alive := room.alive_enemies().duplicate()
	if alive.is_empty():
		check(false, "для проверки порога остался живой враг")
		return
	var survivor := alive.back() as Enemy
	for k in alive.size() - 1:
		(alive[k] as Enemy).take_hit(9999.0, Vector3.ZERO, "test")
	var below_threshold := is_instance_valid(survivor) and not survivor.is_dead \
		and room.alive_count() == 1 and room.alive_count() < size0 * room.next_wave_fraction
	check(below_threshold, "живой враг остался ниже порога следующей волны")
	if not below_threshold:
		return
	var ok := await wait_until(3.0, func() -> bool: return room._wave_index == 1 and room.alive_count() > 1)
	check(ok, "волна 2 пошла при остатке < 30 %% (живы %d)" % room.alive_count())
	check(is_instance_valid(survivor) and not survivor.is_dead, "враг первой волны жив при начале второй")
	check(not room._is_cleared, "зал не зачищен, пока жив враг прошлой волны")
	# Таймаут: волна 3 через next_wave_timeout, даже если все живы
	await wait_until(3.0, func() -> bool: return room.pending_spawns() == 0)
	# П3: в залах по две волны — для проверки таймаута добавим третью
	if not room._waves.has(2):
		var extra := Marker3D.new()
		extra.set_meta("kind", "grunt")
		room.add_wave([extra])
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

func _ready_enemy(kind: String, offset: Vector3) -> Enemy:
	# Зал уже «зачищен» прошлыми проверками (открыт выбор руны, пауза) — подселяем напрямую
	room._is_cleared = false
	var g := get_tree().current_scene as Game
	if g and g.rune_pick.visible:
		g.rune_pick.visible = false
	get_tree().paused = false
	var e := _spawn(kind, offset)
	await wait_until(3.0, func() -> bool: return e.state != Enemy.State.SPAWNING)
	return e

func _test_fall_and_reflect() -> void:
	print("-- Падение с высоты и отражённый снаряд (GDD 8)")
	await _clear()
	var f := await _ready_enemy("fodder", Vector3(3, 0, -8))
	var g := await _ready_enemy("grunt", Vector3(-3, 0, -8))
	g.max_health = 200.0
	g.health = 200.0
	for e in [f, g]:
		e._last_hit_time = Run.combat_clock
		e.global_position += Vector3(0, 9.0, 0)
	# Корм разбивается и исчезает — в лямбде держим слабую ссылку (захват удалённого узла — ошибка движка)
	var fref: WeakRef = weakref(f)
	await wait_until(3.0, func() -> bool: return (fref.get_ref() == null or (fref.get_ref() as Enemy).is_dead) and g.health < 200.0)
	check(not is_instance_valid(f) or f.is_dead, "сброшенный с 9 м корм разбился")
	check(absf((200.0 - g.health) - g.fall_damage) < 0.5, "боец получил 2 У за падение (%.0f)" % (200.0 - g.health))
	var s := await _ready_enemy("fodder", Vector3(0, 0, -8))
	s._last_hit_time = -10.0
	s.global_position += Vector3(0, 9.0, 0)
	await frames(10)
	await wait_until(3.0, func() -> bool: return s.is_on_floor())
	await frames(5)
	check(not s.is_dead, "просто спрыгнувший (без удара) корм жив")
	await _clear()
	var d := await _ready_enemy("grunt", Vector3(0, 0, -6))
	d.set_physics_process(false)
	d.max_health = 500.0
	d.health = 500.0
	var pr := preload("res://enemies/enemy_projectile.gd").new()
	get_tree().current_scene.add_child(pr)
	pr.launch(d.global_position + Vector3(0, 1.0, 1.3), Vector3(0, 0, 6), 10.0, null)
	pr.reflect(Vector3(0, 0, -1))
	pr.process_mode = Node.PROCESS_MODE_ALWAYS  # выбор руны после зачистки ставит паузу
	await wait_until(1.5, func() -> bool: return d.health < 500.0)
	check(absf((500.0 - d.health) - 18.0) < 0.5, "отражённый снаряд — ×1.8 урона (%.1f)" % (500.0 - d.health))
	await _clear()

func _test_vertical_melee() -> void:
	print("-- Ближний бой на разных ярусах")
	var e := await _ready_enemy("grunt", Vector3(0, 0, -1.5))
	e.set_physics_process(false)
	var origin := p.global_position
	var toward := origin - e.global_position
	e.rotation.y = atan2(toward.x, toward.z)
	p.health = p.max_health
	p._invuln_left = 0.0
	p.global_position = origin + Vector3.UP * 3.0
	e._set_state(Enemy.State.CHASE)
	e._cooldown = 0.0
	e._think_chase()
	check(e.state == Enemy.State.CHASE, "враг не замахивается на Тора этажом выше")
	var hp := p.health
	e._do_melee()
	check(is_equal_approx(p.health, hp), "удар не проходит между ярусами")
	p.global_position = origin
	p._invuln_left = 0.0
	e._do_melee()
	check(p.health < hp, "на одном уровне обычный удар по-прежнему попадает")
	await _clear()

func _test_hit_feel() -> void:
	print("-- Реакция на попадание и лимит hit-stop")
	await _clear()
	room._is_cleared = false
	var e := _spawn("grunt", Vector3(0, 0, -4))
	e.set_physics_process(false)
	e.max_health = 500.0
	e.health = 500.0
	e._set_state(Enemy.State.WINDUP)
	var initial := e._visual.position
	e.take_hit(1.0, Vector3.RIGHT * 3.0, "ranged")
	var offset := e.global_basis * (e._visual.position - initial)
	check(offset.dot(Vector3.RIGHT) > 0.01 and e.state == Enemy.State.WINDUP,
		"флинч в направлении удара не прерывает замах от ренжа")
	e._update_visual_feedback(e.flinch_time + 0.01)
	check(e._visual.position.distance_to(initial) < 0.001, "вид возвращается после флинча")
	var boss := _spawn("boss", Vector3(0, 0, -8))
	boss.set_physics_process(false)
	boss.max_health = 500.0
	boss.health = 500.0
	boss._set_state(Enemy.State.WINDUP)
	initial = boss._visual.position
	boss.take_hit(1.0, Vector3.ZERO, "ranged")
	check(boss._visual.position.distance_to(initial) > 0.01 and boss.state == Enemy.State.WINDUP,
		"босс реагирует на попадание без толчка, не прерывая замах")
	await _clear()
	FX.reset_time()
	FX.hitstop(0.08)
	for i in 30:
		FX.hitstop(0.08)
	check(absf(FX._hitstop_left - 0.08) < 0.001, "одновременные попадания не складывают стоп")
	FX.reset_time()
	var stopped_frames := 0
	for i in 60:
		FX.hitstop(0.15)
		await get_tree().process_frame
		if FX._hitstop_left > 0.0:
			stopped_frames += 1
	check(stopped_frames <= int(ceil(FX.cfg().hitstop_budget_per_second * 60.0)) + 2,
		"непрерывная толпа ограничена бюджетом стопа (%d кадров)" % stopped_frames)
	FX.reset_time()

func _test_wave_corpses() -> void:
	print("-- Тела и пересекающиеся волны")
	await _clear()
	room._is_cleared = false
	room._started = true
	room.set_physics_process(false)
	room._spawn_queue.clear()
	room._finished_waves.clear()
	room._advance_pending = false
	room._wave_index = 7
	var a := _spawn("fodder", Vector3(0, 0, -4))
	var b := _spawn("fodder", Vector3(1, 0, -4))
	a.set_physics_process(false)
	b.set_physics_process(false)
	a.debris_lifetime = 0.02
	a.take_hit(9999.0, Vector3.RIGHT * 2.0, "test")
	var bodies := get_tree().get_nodes_in_group("debris").filter(func(n: Node) -> bool:
		return not n.is_queued_for_deletion() and int(n.get_meta("_fodder_wave", -1)) == 7)
	var body: Node = bodies.back() if not bodies.is_empty() else null
	await frames(25)
	check(is_instance_valid(body) and not body.is_queued_for_deletion(), "тело лежит, пока жива его волна")
	room._wave_index = 8
	var next := _spawn("grunt", Vector3(3, 0, -4))
	next.set_physics_process(false)
	FX.reset_time()
	b.take_hit(9999.0, Vector3.ZERO, "test")
	check(room._finished_waves.has(7) and is_instance_valid(next) and not next.is_dead,
		"прошлая волна завершена, хотя следующая ещё жива")
	check(FX._slow_left > 0.0 and Engine.time_scale > 0.1, "последний враг запускает замедление волны")
	await frames(75)
	check(not is_instance_valid(body) or body.is_queued_for_deletion(), "после конца своей волны тело исчезло")
	FX.reset_time()
	await _clear()

func _test_actual_ledge_push() -> void:
	print("-- Реальный сброс ударом с уступа")
	await _clear()
	room._is_cleared = false
	room._started = false
	p.style.reset()
	ComicFX.reset_state()
	FX.reset_time()
	var platform := StaticBody3D.new()
	platform.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.3, 4.0)
	shape.shape = box
	platform.add_child(shape)
	room.add_child(platform)
	platform.global_position = room.global_position + Vector3(0, 8, 0)
	var e := room.spawn_extra("fodder", platform.global_position + Vector3(1.55, 0.25, 0))
	var keeper := _spawn("grunt", Vector3(0, 0, -20))
	keeper.set_physics_process(false)
	e.max_health = 1000.0
	e.health = 1000.0
	e.fall_kill_height = 3.0
	e._set_state(Enemy.State.STUNNED)
	e._stun_left = 99.0
	var ready := await wait_until(1.0, func() -> bool: return is_instance_valid(e) and e.is_on_floor())
	check(ready, "корм стоит на настоящем уступе")
	var ledge_points := [0]
	var on_gained := func(action: StringName, _amount: float) -> void:
		if action == &"ledge_kill":
			ledge_points[0] += 1
	p.style.gained.connect(on_gained)
	var ref: WeakRef = weakref(e)
	var crossed := false
	if ready:
		e.take_hit(1.0, Vector3.RIGHT * 12.0, "ranged")
		for i in 180:
			await get_tree().physics_frame
			var current := ref.get_ref() as Enemy
			if not is_instance_valid(current) or current.is_dead:
				break
			crossed = crossed or current.global_position.x > platform.global_position.x + 2.0
	var current := ref.get_ref() as Enemy
	check(crossed and (not is_instance_valid(current) or current.is_dead), "толчок выбил врага за край и падение убило")
	check(ledge_points[0] == 1, "сбитый с уступа даёт очки стиля один раз")
	check(ComicFX._data.has("ledge_kill") and ComicFX._data["ledge_kill"].words == ["YEET!"], "для сброса задано слово YEET!")
	p.style.gained.disconnect(on_gained)
	platform.queue_free()
	FX.reset_time()
	await _clear()

func _finish() -> void:
	print("=== ИТОГ ENEMY: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
