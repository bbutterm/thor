extends Node
## Проверка ИИ врагов: игрок стоит (бессмертный), враги должны дойти, замахнуться, ударить; метатели — стрелять.
## godot --headless --path . --fixed-fps 60 res://tests/ai_test.tscn

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var r := Node.new()
		r.set_script(get_script())
		r.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(r)
		return
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _run() -> void:
	var fails := 0
	# Обе крайние дальности слуха: обычное тело и громкий Берсерк.
	for body_id in ["hunter", "berserker"]:
		for room in Run.ROOM_SCENES + [Run.BOSS_SCENE]:
			Run.start_run(body_id)
			Run.room_order.assign([room, Run.BOSS_SCENE])
			get_tree().change_scene_to_file("res://scenes/game.tscn")
			await frames(20)
			var g := get_tree().current_scene as Game
			var p := g.player
			var hits := [0]
			var dmg := [0.0]
			p.hurt.connect(func(a: float) -> void:
				hits[0] += 1
				dmg[0] += a)
			var projectiles := 0
			for i in 60 * 15:
				await get_tree().physics_frame
				p.health = p.max_health
				if i % 30 == 0:
					for n in g.room.get_children():
						if n.is_in_group("reflectable"):
							projectiles += 1
			var stuck := 0
			for e in g.room.alive_enemies():
				if e.kind != Enemy.Kind.THROWER and e.global_position.distance_to(p.global_position) > 6.0:
					stuck += 1
			var ok: bool = hits[0] > 0
			print("[%s] %s / %s: попаданий по игроку %d (урон %.0f за 15 с), снарядов в воздухе (сэмплы) %d, грунтов далеко от игрока %d" % ["OK" if ok else "FAIL", body_id, room.get_file(), hits[0], dmg[0], projectiles, stuck])
			if not ok:
				fails += 1
	# Враги Мидгарда (GDD 12.1) по одному в пустом зале: доходят и бьют / стреляют / взрываются;
	# Шаман сам не бьёт — поднимает корм, и корм доходит и бьёт
	for kind in ["fodder", "bloated", "shieldbearer", "merc", "shaman"]:
		Run.start_run("berserker")
		Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		await frames(20)
		var gk := get_tree().current_scene as Game
		gk.room.set_physics_process(false)
		gk.room._spawn_queue.clear()
		for e in gk.room.alive_enemies().duplicate():
			e.queue_free()
		gk.room._alive.clear()
		await frames(2)
		var pk := gk.player
		var khits := [0]
		pk.hurt.connect(func(_a: float) -> void: khits[0] += 1)
		var ek := gk.room.spawn_extra(kind, pk.global_position + Vector3(3, 0, -11))
		var raised := 0
		for i in 60 * 15:
			await get_tree().physics_frame
			pk.health = pk.max_health
			if kind == "bloated" and khits[0] > 0:
				break
		raised = gk.room.alive_count() - (1 if is_instance_valid(ek) and not ek.is_dead else 0)
		var kok: bool = khits[0] > 0 and (kind != "shaman" or raised > 0)
		print("[%s] %s: попаданий по игроку %d за 15 с%s" % ["OK" if kok else "FAIL", kind, khits[0], (", поднято корма %d" % raised) if kind == "shaman" else ""])
		if not kok:
			fails += 1
	# Мини-босс (Толстый Свен — заглушка): доходит и бьёт, полоса HP с его именем
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(20)
	var g2 := get_tree().current_scene as Game
	g2.room.set_physics_process(false)
	await frames(60)
	g2.room._spawn_queue.clear()
	for e in g2.room.alive_enemies().duplicate():
		e.queue_free()
	var mb := Run.miniboss_def() as MinibossDef
	var w := g2.room.wave_count()
	mb.add_to_room(g2.room, g2.hud)
	var boss: Enemy = null
	for m in g2.room.spawns.get_children():
		if m.name == "Miniboss":
			g2.room._spawn_enemy(m)
	for e in g2.room.alive_enemies():
		if e.has_meta("miniboss"):
			boss = e
	var mhits := [0]
	g2.player.hurt.connect(func(_a: float) -> void: mhits[0] += 1)
	for i in 60 * 20:
		await get_tree().physics_frame
		g2.player.health = g2.player.max_health
	var title_ok: bool = g2.hud._boss_box.visible and g2.hud._boss_title.text == mb.title
	var mok: bool = boss != null and g2.room.wave_count() == w + 1 and mhits[0] > 0 and title_ok
	print("[%s] мини-босс %s: HP %.0f, попаданий по игроку %d за 20 с, полоса HP «%s»" % ["OK" if mok else "FAIL", mb.title, boss.max_health if boss else 0.0, mhits[0], g2.hud._boss_title.text])
	if not mok:
		fails += 1
	# Толстый Свен на своей арене (блок Н): выходит после собутыльников, таранит на бочке / плюётся брагой и бьёт
	var mi: int = Run.miniboss_rooms[0] if not Run.miniboss_rooms.is_empty() else 1
	Run.start_run("berserker")
	var order: Array = []
	for i in mi:
		order.append(Run.ROOM_SCENES[i % Run.ROOM_SCENES.size()])
	order.append(Run.miniboss_arena)
	order.append(Run.BOSS_SCENE)
	Run.room_order.assign(order)
	Run.room_index = mi
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(60)
	var g3 := get_tree().current_scene as Game
	var sven: FatSven = null
	for t in 60:
		for e in g3.room.alive_enemies():
			if e is FatSven:
				sven = e
		if sven:
			break
		for e in g3.room.alive_enemies().duplicate():
			e.take_hit(9999, Vector3.ZERO, "test")
		await frames(20)
	var shits := [0]
	g3.player.hurt.connect(func(_a: float) -> void: shits[0] += 1)
	var specials := {}
	for i in 60 * 20:
		await get_tree().physics_frame
		g3.player.health = g3.player.max_health
		if sven and is_instance_valid(sven) and sven.act != 0:
			specials[sven.act] = true
	var sok: bool = sven != null and shits[0] > 0 and (specials.has(FatSven.Act.CHARGE) or specials.has(FatSven.Act.SPIT))
	print("[%s] Толстый Свен на арене «%s»: попаданий по игроку %d за 20 с, свои атаки: %s" % ["OK" if sok else "FAIL", g3.room.room_title, shits[0],
		", ".join(specials.keys().map(func(k: int) -> String: return FatSven.Act.keys()[k]))])
	if not sok:
		fails += 1
	if not await _room10_ascent():
		fails += 1
	if not await _room11_ascent():
		fails += 1
	FX.reset_time()
	print("=== ИТОГ AI: %d FAIL ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)

## Враг добирается по обоим маршам от пола до верхнего помоста сам, без переноса.
func _room10_ascent() -> bool:
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_10.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(90)
	var game := get_tree().current_scene as Game
	var room := game.room
	room.set_physics_process(false)
	room._spawn_queue.clear()
	for e in room.alive_enemies().duplicate():
		e.queue_free()
	room._alive.clear()
	var p := game.player
	p.input_enabled = false
	p.global_position = room.to_global(Vector3(-6.5, 6.8, 11.5))
	p.velocity = Vector3.ZERO
	room._player = p
	var enemy := room.spawn_extra("fodder", room.to_global(Vector3(-10, 0.05, 10.4)))
	if enemy == null:
		print("[FAIL] частокол: корм не появился")
		return false
	enemy._set_state(Enemy.State.CHASE)
	enemy.alert_to_player()
	var middle := false
	var reached := false
	for i in 2400:
		await get_tree().physics_frame
		p.health = p.max_health
		if not is_instance_valid(enemy) or enemy.is_dead:
			break
		var local := room.to_local(enemy.global_position)
		if enemy.is_on_floor() and local.y > 2.6 and local.y < 3.5:
			middle = true
		if enemy.is_on_floor() and local.y > 6.3 and enemy.global_position.distance_to(p.global_position) < 3.0:
			reached = true
			break
	var ok := middle and reached
	print("[%s] частокол: корм прошёл средний и верхний ярусы" % ["OK" if ok else "FAIL"])
	return ok

## Корм проходит три марша к игроку на вершине, без переноса по координатам.
func _room11_ascent() -> bool:
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_11.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(90)
	var game := get_tree().current_scene as Game
	var room := game.room
	room.set_physics_process(false)
	room._spawn_queue.clear()
	for e in room.alive_enemies().duplicate():
		e.queue_free()
	room._alive.clear()
	var p := game.player
	p.input_enabled = false
	p.global_position = room.to_global(Vector3(2, 19.6, -12))
	p.velocity = Vector3.ZERO
	room._player = p
	var enemy := room.spawn_extra("fodder", room.to_global(Vector3(-11, 0.05, 10.8)))
	if enemy == null:
		print("[FAIL] башня: корм не появился")
		return false
	var crowd: Array[Enemy] = [enemy]
	for i in 5:
		var pos := Vector3(-11.0 + (float(i % 3) - 1.0) * 0.65, 0.05, 11.7 + floorf(float(i) / 3.0) * 0.7)
		var follower := room.spawn_extra("fodder", room.to_global(pos))
		if follower != null:
			follower._set_state(Enemy.State.CHASE)
			follower.alert_to_player()
			crowd.append(follower)
	enemy._set_state(Enemy.State.CHASE)
	enemy.alert_to_player()
	var level1 := false
	var level2 := false
	var reached := false
	var climbed := {}
	for i in 4800:
		await get_tree().physics_frame
		p.health = p.max_health
		for follower in crowd:
			if is_instance_valid(follower) and not follower.is_dead and room.to_local(follower.global_position).y >= 6.3:
				climbed[follower.get_instance_id()] = true
		if not is_instance_valid(enemy) or enemy.is_dead:
			break
		var y := room.to_local(enemy.global_position).y
		if enemy.is_on_floor() and y >= 6.3:
			level1 = true
		if enemy.is_on_floor() and y >= 12.8:
			level2 = true
		if enemy.is_on_floor() and y >= 19.2 and enemy.global_position.distance_to(p.global_position) < 3.0:
			reached = true
			if climbed.size() >= 4:
				break
	var ok := level1 and level2 and reached and climbed.size() >= 4
	print("[%s] башня: корм прошёл все ярусы, из пачки поднялись %d/%d" % ["OK" if ok else "FAIL", climbed.size(), crowd.size()])
	return ok
