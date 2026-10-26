extends Node
## Тест структуры забега — двери-награды (блок И, GDD 15.1):
##  • мир: 7 залов + босс, мини-босс в 4-м зале, первый зал — бой;
##  • наборы дверей: 2–3 разные награды, к мини-боссу и боссу — одна дверь, частоты — по таблице GDD,
##    тихие залы не подряд, ларёк — гарантированно (если зал-ларёк уже есть);
##  • забег через разные двери до босса: Элита → оружие + Слава, Сундук → сундук, Мини-босс → трейт + руна,
##    Отдых → лечение 40 %, Локи → половина HP за оружие ур. 3, Фрейя → руна сразу ур. 2, Босс → победа.
## godot --headless --path . --fixed-fps 60 res://tests/run_map_test.tscn

const DoorHelper := preload("res://tests/door_helper.gd")

var _fails: Array[String] = []
var _passes: int = 0
var game: Game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "RunMapRunner"
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
	await DoorHelper.wait(get_tree(), sec)

func _run() -> void:
	print("=== RUN MAP TEST ===")
	_test_structure()
	_test_offers()
	await _test_run_through_doors()
	await wait(1.5)
	_finish()

# --- Структура мира ---

func _test_structure() -> void:
	print("-- Структура мира")
	check(Run.map != null, "карта мира загружена (%s)" % (Run.map.title if Run.map else "—"))
	check(Run.all_rewards.size() >= 10, "наград загружено: %d" % Run.all_rewards.size())
	var total := 0.0
	for r in Run.all_rewards:
		total += r.weight
	check(is_equal_approx(total, 100.0), "сумма частот наград = 100 %% (%.1f)" % total)
	Run.start_run("berserker")
	check(Run.room_order.size() == 8, "7 залов + босс (%d)" % Run.room_order.size())
	check(Run.room_order[7] == Run.BOSS_SCENE, "босс в конце")
	var repeats := 0
	for i in range(1, 7):
		if Run.room_order[i] == Run.room_order[i - 1]:
			repeats += 1
	check(repeats == 0, "залы не повторяются подряд")
	check(Array(Run.miniboss_rooms) == [3], "мини-босс в 4-м зале (%s)" % str(Run.miniboss_rooms))
	check(Run.current_reward() == "combat", "первый зал — бой")
	Run.room_index = 3
	check(Run.is_miniboss_room() and Run.current_reward() == "miniboss", "4-й зал — мини-босс")
	Run.room_index = 7
	check(Run.is_boss_room() and Run.current_reward() == "boss", "8-й — босс")
	Run.room_index = 0

# --- Наборы дверей ---

func _test_offers() -> void:
	print("-- Наборы дверей")
	var m := Run.map
	var boss := Run.room_order.size() - 1
	var bad_size := 0
	var dupes := 0
	var disabled := 0
	for i in 2000:
		var offers := m.roll_offers(Run.all_rewards, 1 + i % 2, boss, {"shop": 9}, "combat", false)
		if offers.size() < m.doors_min or offers.size() > m.doors_max:
			bad_size += 1
		var seen := {}
		for id in offers:
			if seen.has(id):
				dupes += 1
			seen[id] = true
			var d := Run.reward_def(id)
			if d == null or not d.enabled:
				disabled += 1
	check(bad_size == 0, "в наборе 2–3 двери")
	check(dupes == 0, "награды в наборе разные")
	check(disabled == 0, "без наград, которых ещё нет в игре")
	check(m.roll_offers(Run.all_rewards, m.miniboss_index(), boss, {}, "combat", true) == ["miniboss"], "к мини-боссу — одна дверь")
	check(m.roll_offers(Run.all_rewards, boss, boss, {}, "combat", true) == ["boss"], "к боссу — одна дверь")
	# Тихие залы не подряд
	var peaceful_after_rest := 0
	for i in 500:
		for id in m.roll_offers(Run.all_rewards, 5, boss, {}, "rest", true):
			if not Run.reward_def(id).combat:
				peaceful_after_rest += 1
	check(peaceful_after_rest == 0, "после отдыха — без тихих залов")
	# Частоты: одна дверь в наборе — доли по таблице GDD (среди доступных наград)
	var one := m.duplicate() as RunMap
	one.doors_min = 1
	one.doors_max = 1
	var counts := {}
	var n := 20000
	for i in n:
		var id: String = one.roll_offers(Run.all_rewards, 1, boss, {"shop": 9}, "combat", false)[0]
		counts[id] = int(counts.get(id, 0)) + 1
	var wsum := 0.0
	for r in Run.all_rewards:
		if r.enabled and r.weight > 0.0:
			wsum += r.weight
	var worst := 0.0
	var line: Array[String] = []
	for r in Run.all_rewards:
		if not r.enabled or r.weight <= 0.0:
			continue
		var got := float(counts.get(r.id, 0)) / n
		var want := r.weight / wsum
		worst = maxf(worst, absf(got - want))
		line.append("%s %.1f/%.1f" % [r.id, got * 100.0, want * 100.0])
	print("    частоты (получено/ожидается, %): ", ", ".join(line))
	check(worst < 0.015, "частоты наград по таблице GDD (отклонение %.3f)" % worst)
	# Ларёк: гарантирован, если зал-ларёк уже есть (блок К), иначе не предлагается
	var shop_seen := 0
	for i in 300:
		for id in m.roll_offers(Run.all_rewards, 4, boss, {}, "combat", Run.shop_available()):
			if id == "shop":
				shop_seen += 1
	if Run.shop_available():
		check(shop_seen == 300, "ларёк в каждом наборе, пока не посещён (%d/300)" % shop_seen)
		var after_visit := 0
		for i in 300:
			if "shop" in m.roll_offers(Run.all_rewards, 4, boss, {"shop": 1}, "combat", true):
				after_visit += 1
		check(after_visit == 0, "после посещения ларёк больше не предлагается")
		var early := 0
		for i in 300:
			if "shop" in m.roll_offers(Run.all_rewards, 1, boss, {}, "combat", true):
				early += 1
		check(early == 0, "ларёк не раньше %d-го зала" % m.shop_earliest_room)
	else:
		check(shop_seen == 0, "ларька ещё нет — дверь ларька не предлагается")

# --- Забег через разные двери ---

func _kill_all(room: Room) -> void:
	var safety := 0
	while not room._is_cleared and safety < 40:
		safety += 1
		await wait(1.0)
		for e in room.alive_enemies().duplicate():
			if is_instance_valid(e):
				e.take_hit(9999, Vector3(0, 3, -5), "melee_finisher")
		game.player.heal(999)

func _pickups_in_room() -> Array:
	var out: Array = []
	for c in game.room.get_children():
		if c is WeaponPickup:
			out.append(c)
	return out

func _test_run_through_doors() -> void:
	print("-- Забег через двери")
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", "res://rooms/room_02.tscn", "res://rooms/room_03.tscn", "res://rooms/room_04.tscn",
		"res://rooms/room_05.tscn", "res://rooms/room_06.tscn", "res://rooms/room_01.tscn", Run.BOSS_SCENE])
	Run.forced_offers.assign([["elite", "chest"], ["chest", "rest", "freya"], ["miniboss"], ["rest", "loki"], ["loki", "freya"], ["freya", "combat"], ["boss"]])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.5)
	game = get_tree().current_scene as Game
	check(game != null and game.rewards != null, "игра и RewardFlow")
	var p := game.player

	# 1. Бой → руна → двери Элита / Сундук
	await wait(1.0)
	await _kill_all(game.room)
	await wait(1.4)
	check(game.rune_pick.visible, "бой: выбор руны")
	await DoorHelper.resolve_reward(get_tree(), game)
	check(game.rewards.doors.size() == 2, "две двери (Элита, Сундук)")
	var labels := game.rewards.doors.map(func(d: RewardDoor) -> String: return d.reward_id)
	check(labels.has("elite") and labels.has("chest"), "двери: %s" % ", ".join(labels))
	var d0: RewardDoor = game.rewards.doors[0]
	check(d0.get_node_or_null("Icon") != null and d0.get_node_or_null("Portal") != null, "у двери иконка и проём")
	await DoorHelper.take_door(get_tree(), game, labels.find("elite"))
	check(Run.room_index == 1 and Run.current_reward() == "elite", "вошли в зал «Элитный бой»")
	check(game.room.elite_chance >= 0.4 and game.room.max_elites >= 3, "в элитном зале больше элиты (%.2f / %d)" % [game.room.elite_chance, game.room.max_elites])

	# 2. Элита → оружие + Слава
	await wait(1.0)
	await _kill_all(game.room)
	var glory0 := Run.glory
	var picks0 := _pickups_in_room().size()
	await wait(1.4)
	check(_pickups_in_room().size() > picks0, "элита: оружие на полу")
	check(Run.glory >= glory0 + Run.map.elite_reward_glory, "элита: Слава +%d (%d → %d)" % [Run.map.elite_reward_glory, glory0, Run.glory])
	await wait(0.5)
	check(game.rewards.doors.size() == 3, "три двери")
	await DoorHelper.take_door(get_tree(), game, game.rewards.doors.map(func(d: RewardDoor) -> String: return d.reward_id).find("chest"))
	check(Run.current_reward() == "chest", "вошли в зал «Сундук»")

	# 3. Сундук
	await wait(1.0)
	await _kill_all(game.room)
	await wait(1.4)
	var chest: Chest = null
	for c in game.room.get_children():
		if c is Chest:
			chest = c
	check(chest != null, "сундук после зачистки")
	check(game.rewards.doors.size() == 1 and game.rewards.doors[0].reward_id == "miniboss", "к мини-боссу — одна дверь")
	await DoorHelper.take_door(get_tree(), game, 0)

	# 4. Мини-босс → трейт → руна
	check(Run.is_miniboss_room(), "4-й зал — мини-босс")
	await wait(1.0)
	await _kill_all(game.room)
	await wait(1.4)
	check(game.trait_pick.visible, "мини-босс: выбор трейта")
	var traits0 := Run.mjolnir_traits.size()
	var runes0 := Run.runes.size()
	await DoorHelper.resolve_reward(get_tree(), game)
	check(Run.mjolnir_traits.size() == traits0 + 1 and Run.runes.size() == runes0 + 1, "трейт и руна взяты")
	await DoorHelper.take_door(get_tree(), game, 0)

	# 5. Отдых: без врагов, лечение 40 %
	check(Run.current_reward() == "rest" and Run.is_peaceful_room(), "зал «Отдых» — тихий")
	p.health = 40.0
	await wait(1.6)
	check(game.room.alive_count() == 0 and not game.room._started, "на отдыхе врагов нет")
	check(game.rewards.choice.visible, "выбор: похлёбка или руна")
	var hp0 := p.health
	await DoorHelper.resolve_reward(get_tree(), game, "heal")
	check(absf(p.health - minf(p.max_health, hp0 + p.max_health * 0.4 * float(p.modify_stat(&"heal_mult", 1.0)))) < 1.0, "лечение 40 %% (%.0f → %.0f из %.0f)" % [hp0, p.health, p.max_health])
	check(game.rewards.doors.size() == 2, "после отдыха — двери")
	await DoorHelper.take_door(get_tree(), game, game.rewards.doors.map(func(d: RewardDoor) -> String: return d.reward_id).find("loki"))

	# 6. Локи: половина HP за легендарное оружие
	check(Run.current_reward() == "loki", "зал «Сделка Локи»")
	await wait(1.0)
	await _kill_all(game.room)
	await wait(1.4)
	check(game.rewards.choice.visible, "Локи предлагает сделку")
	# Случайные руны прошлых залов (Щит Сиф, Шкура медведя) съедают часть «крови» — без них ровно половина
	Run.runes.clear()
	p.recalc_from_runes(Run)
	p.shield = 0.0
	p.health = 100.0
	var picks1 := _pickups_in_room().size()
	await DoorHelper.resolve_reward(get_tree(), game, "blood")
	check(p.health <= 52.0 and p.health >= 45.0, "Локи забрал половину здоровья (%.0f)" % p.health)
	var legendary := false
	for wp in _pickups_in_room():
		if (wp as WeaponPickup).item.level == 3:
			legendary = true
	check(_pickups_in_room().size() > picks1 and legendary, "легендарное оружие (ур. 3) на полу")
	await DoorHelper.take_door(get_tree(), game, game.rewards.doors.map(func(d: RewardDoor) -> String: return d.reward_id).find("freya"))

	# 7. Фрейя: руна сразу ур. 2
	check(Run.current_reward() == "freya", "зал «Благословение Фрейи»")
	await wait(1.0)
	await _kill_all(game.room)
	await wait(1.4)
	check(game.rune_pick.visible and game.rune_pick._title.text.contains("ФРЕЙ"), "выбор руны Фрейи")
	game.rune_pick._open_time = -10.0
	var rune: RuneDef = game.rune_pick._choices[0]
	var had := Run.rune_count(rune.id)
	game.rune_pick.choose(0)
	await wait(0.3)
	check(Run.rune_count(rune.id) >= maxi(2, had + 1), "руна %s сразу уровня %d" % [rune.id, Run.rune_count(rune.id)])
	check(game.rewards.doors.size() == 1 and game.rewards.doors[0].reward_id == "boss", "к боссу — одна дверь")
	await DoorHelper.take_door(get_tree(), game, 0)

	# 8. Босс
	check(Run.is_boss_room(), "финальный зал — босс")
	await wait(1.0)
	await _kill_all(game.room)
	await wait(2.5)
	check(Run.won and game.end_screen.visible, "победа после босса")
	print("    награды залов: ", ", ".join(Run.room_rewards))

func _finish() -> void:
	print("=== ИТОГ: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
