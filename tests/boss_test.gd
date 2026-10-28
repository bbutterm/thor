extends Node
## Боссы: Толстый Свен (GDD 14.1, блок Н) — арена, таран на бочке, лужи браги, раздувание и взрыв, реплики;
## Ярл Бьорн (GDD 14.2, блок О) — три фазы, рука-бумеранг, балкон и корм, ломает балконы, бодается.
## godot --headless --path . --fixed-fps 60 res://tests/boss_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "BossRunner"
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

## Ждать sec секунд; Тор бессмертен (здоровье восстанавливается каждый кадр).
func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().physics_frame
		if game and is_instance_valid(game) and game.player:
			game.player.health = game.player.max_health

## Ждать, пока cond() не станет true (не дольше timeout секунд); Тор всё это время бессмертен.
func wait_until(cond: Callable, timeout: float) -> bool:
	for i in int(ceil(timeout * 60.0)):
		if cond.call():
			return true
		await get_tree().physics_frame
		if game and is_instance_valid(game) and game.player:
			game.player.health = game.player.max_health
	return cond.call()

func _start(order: Array, index: int) -> void:
	Run.start_run("berserker")
	Run.room_order.assign(order)
	Run.room_index = index
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.4)
	game = get_tree().current_scene as Game

func _kill_all_but(keep: Enemy = null) -> void:
	for e in game.room.alive_enemies().duplicate():
		if e != keep and is_instance_valid(e) and not e.is_dead:
			e.take_hit(9999, Vector3.ZERO, "test")

## Была ли в журнале реплика из пула (Dialogue.history — всё показанное, в т. ч. пузыри).
func _said(pool: String) -> bool:
	var texts: Array = []
	for item in Dialogue.pools.get(pool, []):
		for l in item.lines:
			texts.append(Dialogue.format_text(str(l.get("text", ""))))
	return Dialogue.history.any(func(h: Dictionary) -> bool: return h.text in texts or Dialogue.format_text(h.text) in texts)

func _hold_player(pos: Vector3) -> void:
	var p := game.player
	p.global_position = pos
	p.velocity = Vector3.ZERO

func _run() -> void:
	print("=== BOSS TEST ===")
	await _test_sven()
	await _test_rotation()
	await _test_hovding()
	await _test_volva()
	await _test_berserker()
	await _test_jarl()
	_finish()

# --- Чередование мини-боссов (GDD 14.1, ночь 29.10, Н5) ---

func _test_rotation() -> void:
	print("-- Чередование мини-боссов")
	Run.miniboss_rotation_in_tests = true
	seed(29102026)
	var ids: Array[String] = []
	Save.data["last_miniboss"] = ""
	for i in 12:
		Run.start_run("berserker")
		ids.append((Run.miniboss_def() as MinibossDef).id)
	var repeats := 0
	for i in range(1, ids.size()):
		if ids[i] == ids[i - 1]:
			repeats += 1
	var distinct := {}
	for id in ids:
		distinct[id] = true
	check(repeats == 0 and distinct.size() >= 3, "4-й зал — случайный мини-босс без повтора подряд (%s)" % ", ".join(ids))
	check(Run.miniboss_pool.size() == 4, "в чередовании Свен, Хёвдинг, Вёльва, Берсерк")
	Save.data["last_miniboss"] = "fat_sven"
	Run.start_run("berserker")
	var picked := Run.miniboss_def() as MinibossDef
	check(picked.id != "fat_sven" and Run.miniboss_arena == "" and not "res://rooms/sven_arena.tscn" in Run.room_order,
		"после Свена — другой мини-босс (%s) в обычном зале" % picked.id)
	Run.miniboss_rotation_in_tests = false
	Run.forced_miniboss = "fat_sven"
	Run.start_run("berserker")
	check((Run.miniboss_def() as MinibossDef).id == "fat_sven" and Run.room_order.has(Run.miniboss_arena) and Run.miniboss_arena != "", "Свен — со своей ареной")
	Run.forced_miniboss = "hovding"
	Run.start_run("berserker")
	check((Run.miniboss_def() as MinibossDef).id == "hovding", "принудительный выбор (Run.forced_miniboss)")
	Run.forced_miniboss = ""

## Забег с мини-боссом id в зале 1: дождаться его выхода (остальных убиваем). null — не вышел.
func _miniboss_run(id: String) -> Enemy:
	Dialogue.in_run_scenes = false
	Run.forced_miniboss = id
	Run.start_run("berserker")
	Run.miniboss_rooms = PackedInt32Array([0])
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	Run.room_index = 0
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.6)
	game = get_tree().current_scene as Game
	if game.tutorial:
		game.tutorial.active = false
	var boss: Enemy = null
	for i in 60:
		for e in game.room.alive_enemies():
			if e.has_meta("miniboss"):
				boss = e
		if boss:
			break
		_kill_all_but(null)
		await wait(0.3)
	return boss

func _end_miniboss_run(boss: Enemy, death_pool: String, name: String) -> void:
	if is_instance_valid(boss) and not boss.is_dead:
		boss.take_hit(9999, Vector3.ZERO, "melee")
	await wait(0.3)
	check(_said(death_pool), "смертная реплика: %s" % name)
	_kill_all_but()
	var picked := await wait_until(func() -> bool: return game.trait_pick.visible, 5.0)
	check(picked, "после мини-босса «%s» — выбор трейта Мьёльнира" % name)
	if game.trait_pick.visible:
		game.trait_pick._open_time = -10.0
		game.trait_pick.choose(0, true)
		await wait(0.3)
	get_tree().paused = false
	Run.forced_miniboss = ""
	Run.miniboss_rooms = PackedInt32Array([3])
	await wait(0.2)

# --- Вёльва-ведьма (GDD 14.1, ночь 29.10, Н6) ---

func _test_volva() -> void:
	print("-- Вёльва-ведьма")
	var vb := await _miniboss_run("volva")
	var v := vb as VolvaBoss
	check(v != null, "Вёльва вышла последней волной")
	if v == null:
		Run.forced_miniboss = ""
		Run.miniboss_rooms = PackedInt32Array([3])
		return
	await wait(1.0)
	check(is_equal_approx(v.max_health, 396.0) and game.hud._boss_title.text == "ВЁЛЬВА", "18 У, полоса HP «%s»" % game.hud._boss_title.text)
	check(_said("volva.intro"), "интро-реплика Вёльвы")
	check(v.high_points.size() >= 2, "нашла высокие точки зала (%d)" % v.high_points.size())
	_kill_all_but(v)
	var room_o := game.room.global_position
	_hold_player(room_o + Vector3(-2, 0.1, 9))
	v._fire_cd = 99.0
	v._raise_cd = 99.0
	v._tp_cd = 0.0
	var tele := await wait_until(func() -> bool: return v.is_teleporting(), 4.0)
	check(tele and v._tp_ring != null, "телеграф телепорта (кольцо в точке выхода)")
	var gone := await wait_until(func() -> bool: return v.teleports > 0, 3.0)
	check(gone and v.is_elevated(), "телепорт на высокую точку (высота %.1f м)" % (v.global_position.y - room_o.y))
	v._tp_cd = 99.0
	v._fire_cd = 0.0
	var fired := await wait_until(func() -> bool:
		return get_tree().get_nodes_in_group("hazard_zones").filter(func(z: Node) -> bool: return z.get("source_node") == v).size() >= v.fire_count, 3.0)
	check(fired, "огненные круги на полу (%d)" % v.fire_count)
	var zones := get_tree().get_nodes_in_group("hazard_zones").filter(func(z: Node) -> bool: return z.get("source_node") == v)
	check(not zones.is_empty() and is_equal_approx((zones[0] as HazardZone).telegraph, 1.0) and (zones[0] as HazardZone).puddle_time > 0.0, "телеграф 1 с, потом лужа огня")
	v._fire_cd = 99.0
	var alive0 := game.room.alive_count()
	v._raise_cd = 0.0
	var raised := await wait_until(func() -> bool: return game.room.alive_count() > alive0, 4.0)
	check(raised, "поднимает корм")
	_kill_all_but(v)
	v._raise_cd = 99.0
	var hp0 := v.health
	v.take_hit(20.0, Vector3(0, 0, -6), "hammer")
	check(v.is_knocked() and v.knockdowns == 1, "Мьёльнир сбивает её (оглушена)")
	var hp1 := v.health
	v.take_hit(10.0, Vector3.ZERO, "melee")
	check(hp1 - v.health > 10.0 * 1.4, "оглушённую бить больнее (%.0f)" % (hp1 - v.health))
	check(hp0 > hp1, "молот ранит")
	var up := await wait_until(func() -> bool: return not v.is_knocked(), v.knock_stun + 1.0)
	check(up, "встаёт через %.1f с" % v.knock_stun)
	v.take_hit(v.health - v.max_health * 0.45, Vector3.ZERO, "melee")
	await wait(0.2)
	check(v.engaged and v.fire_count == 3, "при 50 % HP — злее: больше кругов")
	await _end_miniboss_run(v, "volva.death", "Вёльва")

# --- Берсерк-ульфхеднар (GDD 14.1, ночь 29.10, Н6) ---

func _test_berserker() -> void:
	print("-- Берсерк-ульфхеднар")
	var bb := await _miniboss_run("berserker")
	var b := bb as BerserkerBoss
	check(b != null, "Берсерк вышел последней волной")
	if b == null:
		Run.forced_miniboss = ""
		Run.miniboss_rooms = PackedInt32Array([3])
		return
	await wait(1.0)
	check(is_equal_approx(b.max_health, 528.0) and game.hud._boss_title.text == "БЕРСЕРК", "24 У, полоса HP «%s»" % game.hud._boss_title.text)
	_kill_all_but(b)
	var room_o := game.room.global_position
	b.global_position = room_o + Vector3(-2, 0.05, -4)
	_hold_player(room_o + Vector3(-2, 0.1, 6))
	b._series_cd = 0.0
	var strip := [false]
	var hits := [0]
	game.player.hurt.connect(func(_a: float) -> void: hits[0] += 1)
	var window := await wait_until(func() -> bool:
		if b.act == BerserkerBoss.Act.DASH_AIM and b._strip and b._strip.visible:
			strip[0] = true
		_hold_player(room_o + Vector3(-2, 0.1, 6))
		return b.is_vulnerable(), 10.0)
	check(strip[0], "перед рывком — полоса-телеграф на полу")
	check(window and b.dashes == 3, "серия из 3 рывков, потом окно (%d)" % b.dashes)
	check(hits[0] > 0, "рывок задевает стоящего Тора")
	var hp0 := b.health
	b.take_hit(10.0, Vector3.ZERO, "melee")
	check(hp0 - b.health > 10.0 * 1.4, "в окне уязвимости урон больше (%.0f)" % (hp0 - b.health))
	var ended := await wait_until(func() -> bool: return not b.is_vulnerable(), b.vulnerable_time + 1.0)
	check(ended, "окно — %.1f с" % b.vulnerable_time)
	var aim0 := b.current_aim()
	var win0 := b.current_window()
	b.take_hit(b.health - b.max_health * 0.3, Vector3.ZERO, "melee")
	await wait(0.1)
	check(b.raging and b.current_aim() < aim0 and b.current_window() < win0, "при 33 % HP — ярость: серии быстрее, окно короче")
	check(_said("berserker.rage"), "реплика ярости")
	await _end_miniboss_run(b, "berserker.death", "Берсерк")

# --- Хёвдинг с дружиной (GDD 14.1, ночь 29.10, Н5) ---

func _test_hovding() -> void:
	print("-- Хёвдинг с дружиной")
	Dialogue.in_run_scenes = false
	Run.forced_miniboss = "hovding"
	Run.start_run("berserker")
	Run.miniboss_rooms = PackedInt32Array([0])
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	Run.room_index = 0
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.6)
	game = get_tree().current_scene as Game
	if game.tutorial:
		game.tutorial.active = false
	check(Run.is_miniboss_room(), "зал мини-босса — обычный зал 1")
	var hov: HovdingBoss = null
	for i in 60:
		for e in game.room.alive_enemies():
			if e is HovdingBoss:
				hov = e as HovdingBoss
		if hov:
			break
		_kill_all_but(null)
		await wait(0.3)
	check(hov != null, "Хёвдинг вышел последней волной")
	if hov == null:
		Run.forced_miniboss = ""
		Run.miniboss_rooms = PackedInt32Array([3])
		return
	await wait(1.0)
	check(hov.has_meta("miniboss") and hov.kind == Enemy.Kind.BOSS and is_equal_approx(hov.max_health, 484.0), "мини-босс 22 У (%.0f)" % hov.max_health)
	check(game.hud._boss_box.visible and game.hud._boss_title.text == "ХЁВДИНГ", "полоса HP «%s»" % game.hud._boss_title.text)
	check(Dialogue.history.any(func(h: Dictionary) -> bool: return h.speaker == "hovding"), "интро-реплика Хёвдинга")
	check(hov.get_node_or_null("Banner") != null, "знамя на спине")
	var guards: Array[Enemy] = []
	for e in game.room.alive_enemies():
		if e != hov and hov.is_guard(e):
			guards.append(e)
	check(guards.size() == 5, "дружина — отряд из 5 воинов (%d)" % guards.size())
	game.player.global_position = hov.global_position + Vector3(0, 0.1, 9)
	hov._horn_cd = 99.0
	await wait(1.0)
	var boosted := guards.filter(func(g: Enemy) -> bool: return is_instance_valid(g) and HovdingBoss.has_aura(g))
	check(boosted.size() >= 3, "знамя-аура на дружине (%d)" % boosted.size())
	var g0: Enemy = boosted[0] if not boosted.is_empty() else null
	var base_speed := float(g0.get_meta("_aura_speed", 0.0)) if g0 else 0.0
	check(g0 != null and g0.move_speed > base_speed * 1.2 and g0.get_node_or_null("AuraRing") != null, "дружина быстрее и с кольцом ауры")
	# Рог: телеграф, подкрепление, круг под Тором
	var alive0 := game.room.alive_count()
	hov._horn_cd = 0.0
	var raised := await wait_until(func() -> bool: return hov.is_horn_raised(), 3.0)
	check(raised and hov._horn_mesh.visible, "поднял рог (телеграф)")
	var blown := await wait_until(func() -> bool: return hov.horns > 0, 3.0)
	check(blown and game.room.alive_count() > alive0, "рог созвал подкрепление (%d → %d)" % [alive0, game.room.alive_count()])
	var zone := get_tree().get_nodes_in_group("hazard_zones").any(func(z: Node) -> bool: return z.get("source_node") == hov)
	check(zone, "рог — круг под Тором")
	# Вторая фаза
	check(not hov.engaged, "в начале держится за дружиной")
	var s0 := hov.move_speed
	hov.take_hit(hov.health - hov.max_health * 0.45, Vector3.ZERO, "melee")
	await wait(0.2)
	check(hov.engaged and hov.move_speed > s0, "при 50 % HP сам идёт в бой")
	check(_said("hovding.engage"), "реплика второй фазы")
	# Смерть: аура снимается
	var keep: Array[Enemy] = []
	for g in guards:
		if is_instance_valid(g) and not g.is_dead and HovdingBoss.has_aura(g):
			keep.append(g)
	hov.take_hit(9999, Vector3.ZERO, "melee")
	await wait(0.2)
	check(not keep.is_empty() and keep.all(func(g: Enemy) -> bool: return not is_instance_valid(g) or (not HovdingBoss.has_aura(g) and g.get_node_or_null("AuraRing") == null)), "со смертью вожака аура пропала")
	check(_said("hovding.death"), "смертная реплика Хёвдинга")
	await wait(0.3)
	_kill_all_but()
	var picked := await wait_until(func() -> bool: return game.trait_pick.visible, 5.0)
	check(picked, "после Хёвдинга — выбор трейта Мьёльнира")
	if game.trait_pick.visible:
		game.trait_pick._open_time = -10.0
		game.trait_pick.choose(0, true)
		await wait(0.3)
	get_tree().paused = false
	Run.forced_miniboss = ""
	Run.miniboss_rooms = PackedInt32Array([3])
	await wait(0.2)

# --- Толстый Свен ---

func _test_sven() -> void:
	print("-- Толстый Свен: арена в забеге")
	Run.start_run("berserker")
	var arena_ok := true
	for i in Run.miniboss_rooms:
		arena_ok = arena_ok and Run.room_order[i] == Run.miniboss_arena
	check(arena_ok and Run.room_order.count(Run.miniboss_arena) >= 1, "залы мини-босса — его арена (%s)" % ", ".join(Run.room_order.map(func(r: String) -> String: return r.get_file())))
	check(Run.room_order.back() == Run.BOSS_SCENE, "последний зал — босс")
	check(Run.room_order.count(Run.miniboss_arena) == Run.miniboss_rooms.size(), "арена Свена — только в зале мини-босса (мини-боссов %d)" % Run.miniboss_rooms.size())

	var mi: int = Run.miniboss_rooms[0]
	var order: Array = []
	for i in mi:
		order.append(Run.ROOM_SCENES[i % Run.ROOM_SCENES.size()])
	order.append(Run.miniboss_arena)
	order.append(Run.BOSS_SCENE)
	await _start(order, mi)
	check(game.room.room_title.contains("Свен"), "арена Свена загрузилась: «%s»" % game.room.room_title)
	check(Run.is_miniboss_room(), "это зал мини-босса")
	var spot := game.room.get_node_or_null("MinibossSpot") as Node3D
	check(spot != null, "на арене есть точка MinibossSpot")
	var waves := game.room.wave_count()
	check(waves >= 2, "волны: собутыльники, потом Свен (%d)" % waves)
	game.player.global_position = game.room.get_spawn_transform().origin
	await wait(1.0)
	var sven: FatSven = null
	for i in 40:
		for e in game.room.alive_enemies():
			if e is FatSven:
				sven = e as FatSven
		if sven:
			break
		_kill_all_but(null)
		await wait(0.3)
	check(sven != null, "Свен вышел последней волной")
	if sven == null:
		return
	await wait(0.2)
	_kill_all_but(sven)
	check(sven.has_meta("miniboss") and sven.kind == Enemy.Kind.BOSS, "Свен — мини-босс (Kind.BOSS)")
	check(is_equal_approx(sven.max_health, 550.0), "HP 25 У = 550 (%.0f)" % sven.max_health)
	check(spot and Vector2(sven.global_position.x - spot.global_position.x, sven.global_position.z - spot.global_position.z).length() < 1.5, "появился у MinibossSpot")
	check(game.hud._boss_box.visible and game.hud._boss_title.text == "ТОЛСТЫЙ СВЕН", "полоса HP «%s»" % game.hud._boss_title.text)
	check(Dialogue.history.any(func(h: Dictionary) -> bool: return h.speaker == "sven"), "интро-реплика Свена")
	await wait(sven._spawn_time + 0.2)

	var p := game.player
	var hits := [0]
	p.hurt.connect(func(_a: float) -> void: hits[0] += 1)

	print("-- Таран на бочке")
	# Тор между Свеном и южной стеной — Свен проедет через него и врежется в стену
	var room_o := game.room.global_position
	sven.global_position = room_o + Vector3(0, 0.05, -6)
	_hold_player(room_o + Vector3(0, 0.1, 6))
	sven._spit_cd = 999.0
	sven._charge_cd = 0.0
	var aimed := await wait_until(func() -> bool: return sven.act == FatSven.Act.CHARGE_AIM, 4.0)
	check(aimed, "Свен встал на бочку (телеграф тарана)")
	await wait(0.1)
	check(sven._strip != null and sven._strip.visible, "красная полоса на полу показывает путь")
	check(sven._barrel_pivot != null and sven._barrel_pivot.position.y < 1.0, "бочка под Свеном")
	var h0: int = hits[0]
	var stunned := await wait_until(func() -> bool: return sven.act == FatSven.Act.CHARGE_STUN, 4.0)
	check(hits[0] > h0, "таран сбил Тора (попаданий %d)" % (hits[0] - h0))
	check(stunned, "врезался в стену — оглушён")
	var hp0 := sven.health
	sven.take_hit(20.0, Vector3.ZERO, "melee")
	check(hp0 - sven.health > 25.0, "оглушённого бить больнее (×1.5: %.0f)" % (hp0 - sven.health))
	await wait_until(func() -> bool: return sven.act == 0, 4.0)
	check(sven.act == 0 and sven._barrel_pivot.position.y > 1.0, "очнулся, бочка снова на спине")

	print("-- Перепрыгнуть таран")
	sven.global_position = room_o + Vector3(0, 0.05, -6)
	_hold_player(room_o + Vector3(0, 0.1, 4))
	sven._charge_cd = 0.0
	await wait_until(func() -> bool: return sven.act == FatSven.Act.CHARGE, 5.0)
	var h1: int = hits[0]
	# Тор в воздухе всё время проезда
	for i in 90:
		p.global_position = Vector3(p.global_position.x, room_o.y + 2.2, room_o.z + 4)
		p.velocity = Vector3.ZERO
		await get_tree().physics_frame
		if sven.act != FatSven.Act.CHARGE:
			break
	check(hits[0] == h1, "в прыжке таран проходит под Тором")
	await wait_until(func() -> bool: return sven.act == 0, 4.0)

	print("-- Лужи браги")
	sven._charge_cd = 999.0
	sven._spit_cd = 0.0
	sven.global_position = room_o + Vector3(0, 0.05, -5)
	_hold_player(room_o + Vector3(0, 0.1, 3))
	var spat := await wait_until(func() -> bool: return sven.act == FatSven.Act.SPIT, 4.0)
	check(spat, "Свен набирает брагу (замах)")
	var made := await wait_until(func() -> bool: return get_tree().get_nodes_in_group("brew_puddles").size() >= 1, 4.0)
	var puddles := get_tree().get_nodes_in_group("brew_puddles")
	check(made, "плевки растеклись лужами (%d)" % puddles.size())
	sven._spit_cd = 999.0
	sven.set_physics_process(false)
	if not puddles.is_empty():
		var pd := puddles[0] as BrewPuddle
		var base_speed := p.move_speed
		_hold_player(pd.global_position + Vector3(0, 0.05, 0))
		await wait(0.2)
		check(PlayerSlow.factor(p) < 0.99 and p.move_speed < base_speed, "в луже Тор замедлен (%.1f → %.1f)" % [base_speed, p.move_speed])
		_hold_player(pd.global_position + Vector3(6, 0.05, 6))
		await wait(1.0)
		check(PlayerSlow.factor(p) >= 0.99 and is_equal_approx(p.move_speed, base_speed), "вышел из лужи — скорость вернулась (%.1f)" % p.move_speed)
		check(not pd.contains(pd.global_position + Vector3(0, 2.0, 0)), "в прыжке над лужей — не замедляет")
	sven.set_physics_process(true)
	var lifetime := 0.0
	if not puddles.is_empty():
		lifetime = (puddles[0] as BrewPuddle).lifetime
	await wait(lifetime + 0.5)
	var left := get_tree().get_nodes_in_group("brew_puddles").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion()).size()
	check(left < puddles.size() or puddles.is_empty(), "лужи высыхают (осталось %d)" % left)

	print("-- Раздувание и взрыв")
	sven._spit_cd = 999.0
	sven._charge_cd = 999.0
	sven.global_position = room_o + Vector3(0, 0.05, -6)
	_hold_player(room_o + Vector3(0, 0.1, 5))
	sven.take_hit(sven.health - sven.max_health * 0.2, Vector3.ZERO, "melee")
	check(sven.act == FatSven.Act.SWELL, "на 20 % HP раздувается и бежит к Тору")
	check(_said("sven.swell"), "реплика при раздувании")
	var fused := await wait_until(func() -> bool: return sven.act == FatSven.Act.FUSE, 8.0)
	check(fused, "добежал — фитиль")
	check(sven._telegraph != null and is_instance_valid(sven._telegraph), "красный круг взрыва на полу")
	check(sven._visual.scale.x > sven._base_visual_scale.x * 1.2, "раздулся (%.2f → %.2f)" % [sven._base_visual_scale.x, sven._visual.scale.x])
	var h2: int = hits[0]
	var sref: WeakRef = weakref(sven)
	var boomed := await wait_until(func() -> bool: return sref.get_ref() == null or (sref.get_ref() as Enemy).is_dead, 3.0)
	check(boomed, "взорвался — Свену конец")
	check(hits[0] > h2, "взрыв задел стоявшего рядом Тора")
	check(_said("sven.death"), "смертная реплика Свена")
	await wait(0.3)
	_kill_all_but()
	var picked := await wait_until(func() -> bool: return game.trait_pick.visible, 4.0)
	check(picked, "после Свена — выбор трейта Мьёльнира")
	if game.trait_pick.visible:
		game.trait_pick._open_time = -10.0
		game.trait_pick.choose(0, true)
		await wait(0.3)
	get_tree().paused = false
	await wait(0.2)

	print("-- Убит во время раздувания — всё равно бахнет")
	var s2 := game.room.spawn_extra("sven", game.room.global_position + Vector3(0, 0.05, -4)) as FatSven
	if s2 == null:
		# Зал уже зачищен — ставим Свена вручную
		s2 = (load("res://enemies/sven.tscn") as PackedScene).instantiate() as FatSven
		game.room.add_child(s2)
		s2.global_position = game.room.global_position + Vector3(0, 0.05, -4)
	await wait(1.5)
	s2.take_hit(s2.health - s2.max_health * 0.2, Vector3.ZERO, "melee")
	check(s2.act == FatSven.Act.SWELL, "второй Свен раздувается")
	s2.take_hit(9999, Vector3.ZERO, "melee")
	var blasts := game.room.get_children().filter(func(n: Node) -> bool: return n is Blast)
	check(not blasts.is_empty(), "убит раздутым — взрыв с телеграфом")
	await wait(1.0)

# --- Ярл Бьорн ---

func _others_dead(keep: Enemy) -> void:
	for e in game.room.alive_enemies().duplicate():
		if e != keep and is_instance_valid(e) and not e.is_dead and not e.has_meta("jarl_summon"):
			e.take_hit(9999, Vector3.ZERO, "test")

func _balconies_left() -> int:
	return get_tree().get_nodes_in_group("balconies").filter(func(b: Node) -> bool: return not (b as Balcony).is_broken and not b.is_queued_for_deletion()).size()

func _test_jarl() -> void:
	print("-- Ярл Бьорн: арена")
	await _start([Run.BOSS_SCENE], 0)
	check(Run.is_boss_room(), "зал босса")
	check(game.room.room_title == "Длинный дом ярла", "длинный дом: «%s»" % game.room.room_title)
	check(_balconies_left() == 4, "4 балкона (%d)" % _balconies_left())
	var perches := game.room.get_node_or_null("JarlPerches")
	var gates := game.room.get_node_or_null("FodderGates")
	check(perches != null and perches.get_child_count() == 4 and gates != null and gates.get_child_count() >= 2, "маркеры балконов и ворот корма")
	var balcony_static := true
	for b in get_tree().get_nodes_in_group("balconies"):
		balcony_static = balcony_static and b is StaticBody3D and (b as StaticBody3D).collision_layer == 1
	check(balcony_static, "балконы — StaticBody3D на слое мира")
	var jarl: JarlBoss = null
	for i in 30:
		for e in game.room.alive_enemies():
			if e is JarlBoss:
				jarl = e as JarlBoss
		if jarl:
			break
		await wait(0.2)
	check(jarl != null, "Ярл появился")
	if jarl == null:
		return
	check(is_equal_approx(jarl.max_health, 60.0 * 22.0), "HP 60 У = 1320 (%.0f)" % jarl.max_health)
	check(jarl.kind == Enemy.Kind.BOSS and not jarl.has_meta("miniboss"), "Ярл — босс")
	await wait(0.2)
	check(game.hud._boss_box.visible and game.hud._boss_title.text == "ЯРЛ БЬОРН МЁРТВЫЙ", "полоса HP «%s»" % game.hud._boss_title.text)
	check(Music.current_track == "jarl" or Music._pending_track == "jarl", "своя тема Ярла (%s)" % Music.current_track)
	check(_said("jarl.intro") or Dialogue.history.any(func(h: Dictionary) -> bool: return h.speaker == "jarl"), "интро-реплика Ярла")
	await wait(jarl._spawn_time + 0.2)
	_others_dead(jarl)
	var p := game.player
	var hits := [0]
	p.hurt.connect(func(_a: float) -> void: hits[0] += 1)
	var o := game.room.global_position

	print("-- Фаза 1: рука-бумеранг")
	check(jarl.phase == 1, "фаза 1")
	var hp0 := jarl.health
	jarl.take_hit(100.0, Vector3.ZERO, "melee")
	check(absf((hp0 - jarl.health) - 100.0 * jarl.armed_damage_mult) < 0.5, "с рукой урон ×%.1f (%.0f)" % [jarl.armed_damage_mult, hp0 - jarl.health])
	jarl.global_position = o + Vector3(0, 0.05, -8)
	_hold_player(o + Vector3(0, 0.1, 4))
	jarl._throw_cd = 0.0
	var threw := await wait_until(func() -> bool: return jarl.act == JarlBoss.Act.ARMLESS, 5.0)
	check(threw, "бросил руку")
	var arm_ok := game.room.get_children().any(func(n: Node) -> bool: return n is JarlArm)
	check(arm_ok and jarl.is_armless(), "рука летит бумерангом, Ярл без руки")
	var h0: int = hits[0]
	hp0 = jarl.health
	jarl.take_hit(100.0, Vector3.ZERO, "melee")
	check(absf((hp0 - jarl.health) - 100.0 * jarl.window_damage_mult) < 0.5, "без руки — окно урона ×%.1f (%.0f)" % [jarl.window_damage_mult, hp0 - jarl.health])
	var t_frames := [0]
	await wait_until(func() -> bool:
		t_frames[0] += 1
		return jarl.act != JarlBoss.Act.ARMLESS, 6.0)
	var window: float = float(t_frames[0]) / 60.0
	check(window >= jarl.arm_window - 0.3, "окно без руки ≈ %.1f с (по GDD 3 с)" % window)
	check(hits[0] > h0, "рука попала по Тору (попаданий %d)" % (hits[0] - h0))
	check(not jarl.is_armless(), "рука вернулась")

	print("-- Фаза 2: балкон и корм")
	jarl.take_hit((jarl.health - jarl.max_health * 0.6) / jarl.armed_damage_mult, Vector3.ZERO, "melee")
	check(jarl._pending_phase == 2, "на 60 % HP — фаза 2")
	var perched := await wait_until(func() -> bool: return jarl.act == JarlBoss.Act.PERCH, 8.0)
	check(perched and jarl.phase == 2, "запрыгнул на балкон")
	check(jarl.global_position.y > o.y + 2.5 and jarl._balcony_at(jarl.global_position) != null, "стоит на балконе (y=%.1f)" % (jarl.global_position.y - o.y))
	check(_said("jarl.phase2"), "«Пришить!»")
	_hold_player(o + Vector3(0, 0.1, 0))
	var summoned := await wait_until(func() -> bool: return game.room.alive_enemies().any(func(e: Enemy) -> bool: return e.has_meta("jarl_summon")), jarl.summon_interval + 2.0)
	check(summoned, "из ворот лезет корм")
	hp0 = jarl.health
	jarl.take_hit(100.0, Vector3.ZERO, "melee")
	check(absf((hp0 - jarl.health) - 100.0 * jarl.perch_damage_mult) < 0.5 and jarl.act == JarlBoss.Act.PERCH, "наверху топором почти не ранить (%.0f)" % (hp0 - jarl.health))
	jarl.take_hit(30.0, Vector3.ZERO, "slam")
	var knocked := await wait_until(func() -> bool: return jarl.act == JarlBoss.Act.KNOCKED, 3.0)
	check(knocked, "удар-приземление сбил с балкона")
	check(jarl.global_position.y < o.y + 1.0, "упал на пол (y=%.1f)" % (jarl.global_position.y - o.y))
	hp0 = jarl.health
	jarl.take_hit(100.0, Vector3.ZERO, "melee")
	check(absf((hp0 - jarl.health) - 100.0 * jarl.window_damage_mult) < 0.5, "сбитый оглушён — окно урона (%.0f)" % (hp0 - jarl.health))
	check(_balconies_left() == 4, "в фазе 2 балконы целы")

	print("-- Фаза 3: ломает балконы, бодается")
	jarl.take_hit((jarl.health - jarl.max_health * 0.3) / jarl.window_damage_mult, Vector3.ZERO, "melee")
	check(jarl._pending_phase == 3, "на 30 % HP — фаза 3")
	var broke := await wait_until(func() -> bool: return jarl.phase == 3 and _balconies_left() == 0, 12.0)
	check(broke, "все балконы сломаны (осталось %d)" % _balconies_left())
	var planks := get_tree().get_nodes_in_group("debris").filter(func(n: Node) -> bool: return n is RigidBody3D and (n as RigidBody3D).collision_layer == 1 << 6)
	check(planks.size() >= 4, "обломки — физтела на слое debris (%d)" % planks.size())
	check(jarl._arms_off and jarl._humanoid.skeleton.get_bone_pose_scale(jarl._humanoid.skeleton.find_bone("upperarm_r")).x < 0.1, "отвалились обе руки")
	check(_said("jarl.phase3"), "«Рагнарёк деревни!»")
	await wait_until(func() -> bool: return jarl.act == 0, 6.0)
	_others_dead(jarl)
	for e in game.room.alive_enemies().duplicate():
		if e != jarl:
			e.take_hit(9999, Vector3.ZERO, "test")
	jarl.global_position = o + Vector3(0, 0.05, -10)
	_hold_player(o + Vector3(0, 0.1, 4))
	jarl._slam_cd = 999.0
	jarl._butt_cd = 0.0
	var aimed := await wait_until(func() -> bool: return jarl.act == JarlBoss.Act.BUTT_AIM, 4.0)
	await wait(0.1)
	check(aimed and jarl._strip != null and jarl._strip.visible, "бодание: полоса-телеграф на полу")
	var h1: int = hits[0]
	var butted := await wait_until(func() -> bool: return jarl.act == JarlBoss.Act.BUTT_STUN or jarl.act == JarlBoss.Act.BUTT_END, 4.0)
	check(butted and hits[0] > h1, "боднул Тора (попаданий %d)" % (hits[0] - h1))
	await wait_until(func() -> bool: return jarl.act == 0, 4.0)
	jarl._butt_cd = 999.0
	jarl._slam_cd = 0.0
	jarl.global_position = o + Vector3(0, 0.05, -10)
	_hold_player(o + Vector3(0, 0.1, 2))
	var leapt := await wait_until(func() -> bool: return jarl.act == JarlBoss.Act.SLAM_LEAP, 4.0)
	check(leapt and jarl._telegraph != null and is_instance_valid(jarl._telegraph), "прыжок с ударной волной — круг на полу")
	var h2: int = hits[0]
	await wait_until(func() -> bool: return jarl.act != JarlBoss.Act.SLAM_LEAP, 3.0)
	check(hits[0] > h2, "волна задела стоящего Тора")
	# В прыжке волна не задевает
	await wait_until(func() -> bool: return jarl.act == 0, 3.0)
	jarl.global_position = o + Vector3(0, 0.05, -10)
	_hold_player(o + Vector3(0, 0.1, 2))
	jarl._slam_cd = 0.0
	var leapt2 := await wait_until(func() -> bool: return jarl.act == JarlBoss.Act.SLAM_LEAP, 4.0)
	var h3: int = hits[0]
	if leapt2:
		# В воздухе в 3 м от точки приземления (не на голове у Ярла)
		var air := jarl._leap_to + Vector3(3.0, 2.2, 0)
		for i in 120:
			p.global_position = air
			p.velocity = Vector3.ZERO
			await get_tree().physics_frame
			p.health = p.max_health
			if jarl.act != JarlBoss.Act.SLAM_LEAP:
				break
	check(leapt2 and hits[0] == h3, "в прыжке ударная волна мимо")

	print("-- Поражение")
	var summon := game.room.spawn_extra("fodder", o + Vector3(3, 0.05, 0))
	summon.set_meta("jarl_summon", true)
	await wait(0.3)
	jarl.take_hit(9999, Vector3.ZERO, "melee_finisher")
	await wait(0.2)
	var head := game.room.get_node_or_null("JarlHead")
	check(head != null, "голова укатывается")
	var cleared := await wait_until(func() -> bool: return game.room._is_cleared, 3.0)
	check(cleared, "свита рассыпалась — зал зачищен")
	var won := await wait_until(func() -> bool: return Run.won, 3.0)
	check(won, "победа в забеге")
	check(_said("jarl.defeat"), "фраза при поражении")
	await wait(2.0)

func _finish() -> void:
	print("=== ИТОГ BOSS: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
