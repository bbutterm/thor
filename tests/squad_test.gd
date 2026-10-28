extends Node
## Отряды-комбинации (GDD 12.6, ночь 29.10, Н3): пять отрядов GDD в данных, состав и подгонка под зал,
## строй (шеренга — щиты впереди, стрелки сзади; кольцо свиты вокруг шамана; россыпь стаи), вход сзади/сбоку,
## задержка засады, роли участников, варианты отряда, описания залов с отрядами.
## godot --headless --path . --fixed-fps 60 res://tests/squad_test.tscn

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
		r.name = "SquadTestRunner"
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

func _load_room() -> void:
	Dialogue.in_run_scenes = false  # сцены-новеллы ставят игру на паузу
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(30)
	game = get_tree().current_scene as Game
	room = game.room
	p = game.player
	# Игра сама запускает волны зала чуть позже — ждём, чтобы не столкнуться с этим запуском
	for i in 300:
		if room._started:
			break
		await frames(1)

## Пустой зал с одной волной из маркеров markers; Тор в (0, 0, 8) лицом на север (-Z).
func _stage(markers: Array[Node3D]) -> void:
	room.set_physics_process(false)
	room._spawn_queue.clear()
	for e in room.alive_enemies().duplicate():
		if is_instance_valid(e):
			e.queue_free()
	room._alive.clear()
	for g in ["hazard_zones", "enemy_projectiles", "brew_puddles"]:
		for n in get_tree().get_nodes_in_group(g):
			n.queue_free()
	for m in room.spawns.get_children():
		m.queue_free()
	room._waves.clear()
	room._wave_index = 0
	room._is_cleared = false
	room.elite_chance = 0.0
	await frames(3)
	p.global_position = room.global_position + Vector3(0, 0.1, 8)
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2.ZERO
	await frames(10)
	for m in markers:
		room.spawns.add_child(m)
	room.add_wave(markers)
	room.set_physics_process(true)
	get_tree().paused = false
	room.start(p)

func _squad_marker(squad: String, local: Vector3, extra: Dictionary = {}) -> Marker3D:
	var m := Marker3D.new()
	m.set_meta("kind", "squad")
	m.set_meta("squad", squad)
	for k in extra:
		m.set_meta(k, extra[k])
	m.position = local
	return m

func _wait_spawned(n: int, sec: float = 4.0) -> bool:
	for i in int(sec * 60.0):
		await frames(1)
		if room.alive_count() >= n and room.pending_spawns() == 0:
			return true
	return false

func _count(kind: Enemy.Kind) -> int:
	var c := 0
	for e in room.alive_enemies():
		if is_instance_valid(e) and e.kind == kind:
			c += 1
	return c

func _run() -> void:
	print("=== SQUAD TEST ===")
	_test_data()
	await _load_room()
	await _test_shield_wall()
	await _test_shaman_escort()
	await _test_pack()
	await _test_ambush_behind()
	await _test_powder_keg_and_override()
	await _test_options()
	_test_room_defs()
	_finish()

func _test_data() -> void:
	print("-- Данные отрядов")
	var want := {"shield_wall": {"shieldbearer": 3, "thrower": 2}, "shaman_escort": {"shaman": 1, "fodder": 6},
		"powder_keg": {"grunt": 4, "bloated": 2}, "loki_ambush": {"merc": 1, "grunt": 3}, "pack": {"fodder": 7, "grunt": 2}}
	for id in want:
		var sq := SquadDef.find(id)
		check(sq != null and sq.totals() == want[id], "%s: состав по GDD %s" % [id, str(sq.totals() if sq else {})])
	check(SquadDef.find("shield_wall").formation == SquadDef.Formation.LINE and SquadDef.find("shaman_escort").formation == SquadDef.Formation.RING
		and SquadDef.find("pack").formation == SquadDef.Formation.SCATTER, "построения: шеренга / кольцо / россыпь")
	check(SquadDef.find("loki_ambush").entry == SquadDef.Entry.BEHIND and SquadDef.find("loki_ambush").delay > 0.0
		and SquadDef.find("loki_flank").entry == SquadDef.Entry.FLANK, "засада: сзади или сбоку, с задержкой")
	var sq2 := SquadDef.find("powder_keg")
	check(sq2.totals({"grunt": 3, "bloated": 1}) == {"grunt": 3, "bloated": 1}, "подгонка под бюджет зала")
	check(sq2.totals({"shieldbearer": 1}).get("shieldbearer", 0) == 1, "подгонка добавляет вид в передний ряд")

func _test_shield_wall() -> void:
	print("-- Стена щитов")
	await _stage([_squad_marker("shield_wall", Vector3(0, 0, -4))])
	var ok := await _wait_spawned(5)
	check(ok and _count(Enemy.Kind.SHIELD) == 3 and _count(Enemy.Kind.THROWER) == 2, "собрался состав: 3 щита + 2 метателя")
	var shields: Array[Enemy] = []
	var throwers: Array[Enemy] = []
	for e in room.alive_enemies():
		if e.kind == Enemy.Kind.SHIELD:
			shields.append(e)
		elif e.kind == Enemy.Kind.THROWER:
			throwers.append(e)
	var front := 0.0
	for s in shields:
		front += s.global_position.distance_to(p.global_position)
	var back := 0.0
	for t in throwers:
		back += t.global_position.distance_to(p.global_position)
	check(shields.size() == 3 and throwers.size() == 2 and front / 3.0 < back / 2.0 - 1.5, "шеренга: щиты ближе к Тору, метатели за ними")
	var xs: Array[float] = []
	for s in shields:
		xs.append(s.global_position.x)
	xs.sort()
	check(xs.size() == 3 and xs[1] - xs[0] > 1.2 and xs[2] - xs[1] > 1.2, "щиты стоят в ряд с шагом")
	check(throwers.all(func(t: Enemy) -> bool: return t._role == EnemyTactics.Role.COVER) and shields.all(func(s: Enemy) -> bool: return s.has_meta("squad_id")), "роли: метатели прикрываются щитами")

func _test_shaman_escort() -> void:
	print("-- Шаман и свита")
	await _stage([_squad_marker("shaman_escort", Vector3(0, 0, -5))])
	var ok := await _wait_spawned(7)
	var sh: Enemy = null
	for e in room.alive_enemies():
		if e.kind == Enemy.Kind.SHAMAN:
			sh = e
	check(ok and sh != null and _count(Enemy.Kind.FODDER) == 6, "шаман + 6 корма (П3: пачки 5–8)")
	var ringed := 0
	var anchored := 0
	for e in room.alive_enemies():
		if e.kind == Enemy.Kind.FODDER and sh:
			var d := Vector2(e.global_position.x - sh.global_position.x, e.global_position.z - sh.global_position.z).length()
			if d > 1.8 and d < 5.0:
				ringed += 1
			if e.has_meta("tactic_anchor") and e.get_meta("tactic_anchor") == sh and e._role == EnemyTactics.Role.ESCORT:
				anchored += 1
	check(ringed >= 5, "свита встала кольцом вокруг шамана (%d)" % ringed)
	check(anchored == 6, "у свиты роль «свита» и якорь — шаман (%d)" % anchored)
	# Свита держится у шамана, пока Тор далеко
	p.global_position = room.global_position + Vector3(0, 0.1, 10)
	await frames(120)
	var near := 0
	for e in room.alive_enemies():
		if e.kind == Enemy.Kind.FODDER and sh and e.global_position.distance_to(sh.global_position) < 6.0:
			near += 1
	check(near >= 4, "свита не бросает шамана, пока Тор далеко (%d)" % near)

func _test_pack() -> void:
	print("-- Стая")
	await _stage([_squad_marker("pack", Vector3(0, 0, -5))])
	var ok := await _wait_spawned(9)
	check(ok and _count(Enemy.Kind.FODDER) == 7 and _count(Enemy.Kind.GRUNT) == 2, "7 корма + 2 воина (П3: пачки 5–8)")

func _test_ambush_behind() -> void:
	print("-- Засада Локи")
	await _stage([_squad_marker("loki_ambush", Vector3(0, 0, -8))])
	p.global_position = room.global_position + Vector3(-2, 0.1, 0)  # за спиной — свободный пол
	await frames(60)
	check(room.alive_count() == 0 and room.pending_spawns() == 4, "в начале волны засады ещё нет")
	var ok := await _wait_spawned(4, 6.0)
	check(ok and _count(Enemy.Kind.MERC) == 1 and _count(Enemy.Kind.GRUNT) == 3, "через задержку вышли наёмник и 3 бойца")
	var behind := 0
	var fwd := -p.global_transform.basis.z
	for e in room.alive_enemies():
		var d := e.global_position - p.global_position
		d.y = 0.0
		if d.normalized().dot(fwd) < -0.3:
			behind += 1
	check(behind >= 3, "засада появилась за спиной Тора (%d из 4)" % behind)
	var fast := room.alive_enemies().filter(func(e: Enemy) -> bool: return e.kind == Enemy.Kind.GRUNT and e.move_speed > 4.4 * 1.2)
	check(fast.size() == 3, "бойцы засады быстрые")
	check(room.alive_enemies().all(func(e: Enemy) -> bool: return e.is_alert_to_player()), "засада сразу в бою")

func _test_powder_keg_and_override() -> void:
	print("-- Пороховая бочка (подгонка)")
	await _stage([_squad_marker("powder_keg", Vector3(0, 0, -5), {"squad_override": {"grunt": 3, "bloated": 1}})])
	var ok := await _wait_spawned(4)
	check(ok and room.alive_count() == 4 and _count(Enemy.Kind.BLOATED) == 1 and _count(Enemy.Kind.GRUNT) == 3, "подгонка: 3 воина + 1 Раздутый")
	var b: Enemy = null
	for e in room.alive_enemies():
		if e.kind == Enemy.Kind.BLOATED:
			b = e
	check(b != null and b._role == EnemyTactics.Role.LURK, "Раздутый прячется за спинами (роль «засада»)")

func _test_options() -> void:
	print("-- Варианты отряда")
	var seen := {}
	for i in 12:
		var m := _squad_marker("", Vector3.ZERO, {"squad_options": ["loki_ambush", "loki_flank"]})
		m.remove_meta("squad")
		var sq := SquadDef.for_marker(m)
		seen[sq.id if sq else "?"] = true
		if i == 0:
			check(sq != null and SquadDef.for_marker(m).id == sq.id, "выбор варианта запоминается на маркере")
		m.free()
	check(seen.has("loki_ambush") and seen.has("loki_flank") and seen.size() == 2, "зал берёт один из вариантов случайно (%s)" % str(seen.keys()))

## Описания залов: отряды в 2–3+ залах, состав волн не изменился (те же враги и Слава).
func _test_room_defs() -> void:
	print("-- Описания залов")
	var rooms_with := 0
	var unknown := 0
	for f in ["room_01", "room_02", "room_03", "room_04", "room_05", "room_06", "room_07", "room_08", "room_09", "room_10", "room_11"]:
		var def: Dictionary = (load("res://tools/rooms/%s.gd" % f) as GDScript).call("def")
		var has := false
		for e in def.get("enemies", []):
			if str(e[0]) == "squad":
				has = true
				var opts: Array = (e[5] as Dictionary).get("squad_options", [(e[5] as Dictionary).get("squad", "")])
				for id in opts:
					if SquadDef.find(str(id)) == null:
						unknown += 1
		if has:
			rooms_with += 1
	check(rooms_with >= 3 and rooms_with < 11, "отряды в нескольких залах, не во всех (%d)" % rooms_with)
	check(unknown == 0, "все отряды залов есть в данных")
	var r02: Dictionary = (load("res://tools/rooms/room_02.gd") as GDScript).call("def")
	var totals := {}
	for e in r02.enemies:
		if int(e[2]) != 1:
			continue
		if str(e[0]) == "squad":
			var sq := SquadDef.find(str(e[5].squad))
			var t := sq.totals(e[5].get("squad_override", {}))
			for k in t:
				totals[k] = int(totals.get(k, 0)) + int(t[k])
		else:
			totals[e[0]] = int(totals.get(e[0], 0)) + (int(e[3]) if e.size() > 3 else 1)
	check(totals == {"thrower": 1, "grunt": 4, "shaman": 1, "fodder": 12}, "зал 2, волна 2: состав прежний (%s)" % str(totals))

func _finish() -> void:
	print("=== ИТОГ SQUAD: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
