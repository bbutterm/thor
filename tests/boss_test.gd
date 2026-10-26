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
	if has_method("_test_jarl"):
		await call("_test_jarl")
	_finish()

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
	check(sven._visual.scale.x > sven._base_visual_scale.x * 1.25, "раздулся (%.2f → %.2f)" % [sven._base_visual_scale.x, sven._visual.scale.x])
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

func _finish() -> void:
	print("=== ИТОГ BOSS: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
