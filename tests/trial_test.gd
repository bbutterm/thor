extends Node
## Тест испытаний (блок Ф, GDD 15.1): Один («за 40 с», «без ренжа», «только удар-приземление и молот»),
## Хильд (рекорд убийств за 30 с), Локи («пол — лава»). Проверяет: условие, таймер, HUD, награду
## (Слава 40–80 или особая руна) и провал без награды.
## godot --headless --path . --fixed-fps 60 res://tests/trial_test.tscn

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
		runner.name = "TrialRunnerTest"
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
	print("=== TRIAL TEST ===")
	_test_data()
	Run.start_run("berserker")
	Run.miniboss_rooms = PackedInt32Array()
	Run.room_order.assign(["res://rooms/room_01.tscn", "res://rooms/room_02.tscn", "res://rooms/room_03.tscn", "res://rooms/room_04.tscn",
		"res://rooms/room_05.tscn", "res://rooms/room_06.tscn", "res://rooms/room_01.tscn", Run.BOSS_SCENE])
	Run.forced_offers.assign([["trial", "combat"], ["trial", "combat"], ["trial", "combat"], ["trial", "combat"], ["trial", "combat"], ["trial", "combat"], ["boss"]])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.5)
	game = get_tree().current_scene as Game
	await wait(1.0)
	await _kill_all("melee_finisher")
	await wait(1.4)
	await DoorHelper.resolve_reward(get_tree(), game)
	await _enter_trial("odin_time")
	await _test_time_pass()
	await _enter_trial("odin_no_ranged")
	await _test_no_ranged_fail()
	await _enter_trial("odin_slam_hammer")
	await _test_slam_hammer()
	await _enter_trial("hild_record")
	await _test_hild()
	await _enter_trial("loki_lava")
	await _test_lava()
	await _enter_trial("odin_time")
	await _test_time_fail()
	await wait(1.5)
	_finish()

func _test_data() -> void:
	print("-- Данные")
	check(Run.all_trials.size() >= 5, "испытаний: %d" % Run.all_trials.size())
	var hosts := {}
	var kinds := {}
	for t in Run.all_trials:
		hosts[t.host] = true
		kinds[t.kind] = true
		check(t.reward_rune or (t.reward_glory >= 20 and t.reward_glory <= 80), "%s: награда %s (Слава 20–80 или руна; Б5: 25–40)" % [t.id, t.reward_text()])
		for w in ["intro", "win", "fail"]:
			check(Dialogue.has_pool(t.pool(w)), "%s: реплики «%s» (%s)" % [t.id, w, t.pool(w)])
	check(hosts.has("odin") and hosts.has("hild") and hosts.has("loki"), "ведущие: Один, Хильд, Локи")
	check(kinds.size() == 5, "все виды условий: %s" % ", ".join(kinds.keys()))
	var d := Run.reward_def("trial")
	check(d != null and d.enabled and is_equal_approx(d.weight, 10.0), "дверь «Испытание» включена, частота 10 %")

func _trial() -> TrialRunner:
	return game.room.get_node_or_null("Trial") as TrialRunner

func _enter_trial(id: String) -> void:
	Run.forced_trial = id
	var ids := game.rewards.doors.map(func(dd: RewardDoor) -> String: return dd.reward_id)
	await DoorHelper.take_door(get_tree(), game, ids.find("trial"))
	print("-- Испытание %s (зал %d)" % [id, Run.room_index + 1])
	await wait(1.0)
	var t := _trial()
	check(Run.current_reward() == "trial" and t != null and t.def.id == id, "зал-испытание «%s»" % (t.def.title if t else "—"))
	check(t != null and t.is_running(), "испытание идёт, таймер пошёл")
	check(t != null and t.hud != null and t.hud._title.text != "", "панель испытания в HUD")

func _kill_all(source: String) -> void:
	var room := game.room
	var safety := 0
	while not room._is_cleared and safety < 40:
		safety += 1
		await wait(0.6)
		for e in room.alive_enemies().duplicate():
			if is_instance_valid(e):
				e.take_hit(9999, Vector3(0, 3, -5), source)
		game.player.heal(999)

func _test_time_pass() -> void:
	var t := _trial()
	var g0 := Run.glory
	await _kill_all("melee_finisher")
	check(t.is_success(), "зачистил за %.1f с из %d — пройдено" % [t.elapsed, int(t.def.time_limit)])
	await wait(1.5)
	check(Run.glory >= g0 + t.def.reward_glory, "награда: +%d Славы (%d → %d)" % [t.def.reward_glory, g0, Run.glory])
	check(game.rewards.doors.size() == 2, "двери после испытания")

func _test_no_ranged_fail() -> void:
	var t := _trial()
	var p := game.player
	p.weapons.equip(Loot.get_def("crossbow"), 1, false)
	p.weapons.switch_to(WeaponHolder.RANGED, true)
	await wait(0.4)
	p.weapons.gun.try_fire()
	await wait(0.2)
	check(t.state == "failed", "выстрел ренжем — провал («%s»)" % t.fail_reason)
	check(t.hud._status.text.begins_with("ПРОВАЛ"), "HUD: «%s»" % t.hud._status.text)
	p.weapons.switch_to(WeaponHolder.MELEE, true)
	await _kill_all("melee_finisher")
	var g0 := Run.glory
	await wait(1.5)
	check(Run.glory - g0 < t.def.reward_glory, "провал — без награды (Слава +%d)" % (Run.glory - g0))
	check(not game.rune_pick.visible and game.rewards.doors.size() == 2, "сразу двери, без выбора руны")

func _test_slam_hammer() -> void:
	var t := _trial()
	await _kill_all("slam")
	check(t.is_success(), "добивал ударом-приземлением — пройдено")
	await wait(1.5)
	check(game.rune_pick.visible and game.rune_pick._title.text.contains("ИСПЫТАНИЯ"), "награда — особая руна")
	game.rune_pick._open_time = -10.0
	var r: RuneDef = game.rune_pick._choices[0]
	var had := Run.rune_count(r.id)
	game.rune_pick.choose(0)
	await wait(0.3)
	check(Run.rune_count(r.id) == mini(had + 2, 3), "руна %s сразу на уровень выше (%d → %d)" % [r.id, had, Run.rune_count(r.id)])
	# Провал того же условия: добил топором
	var t2 := TrialRunner.attach(game.room, t.def)
	t2.start(game.player)
	Run.kill_registered.emit("melee")
	check(t2.state == "failed", "добил топором — провал («%s»)" % t2.fail_reason)
	t2.queue_free()
	await wait(0.2)

func _test_hild() -> void:
	var t := _trial()
	check(game.room.wave_count() >= 4, "Хильд: зал получил доп. волны (%d)" % game.room.wave_count())
	var g0 := Run.glory
	var safety := 0
	while t.is_running() and safety < 30:
		safety += 1
		await wait(0.5)
		for e in game.room.alive_enemies().duplicate():
			if is_instance_valid(e):
				e.take_hit(9999, Vector3(0, 3, -5), "melee_finisher")
	check(t.is_success() and t.kills >= t.def.target and t.elapsed <= t.def.time_limit, "рекорд Хильд побит: %d убийств за %.1f с" % [t.kills, t.elapsed])
	await _kill_all("melee_finisher")
	await wait(1.5)
	check(Run.glory - g0 >= t.def.reward_glory, "награда +%d Славы" % t.def.reward_glory)
	check(int(Save.data.records.get("trial_hild_record_best", 0)) >= t.def.target, "рекорд записан в сохранение")

func _test_lava() -> void:
	var t := _trial()
	var p := game.player
	check(t.get_node_or_null("Lava") != null, "пол залит лавой")
	for e in game.room.alive_enemies():
		e.set_physics_process(false)
	p.global_position = game.room.get_spawn_transform().origin
	p.velocity = Vector3.ZERO
	p.health = p.max_health
	await wait(0.3)
	var hp0 := p.health
	# Прыгаем — в воздухе не жжёт
	p.velocity.y = 8.0
	await wait(0.05)
	var burn_air := t.burn
	await wait(0.3)
	check(not p.is_on_floor() and is_equal_approx(t.burn, burn_air), "в воздухе лава не жжёт")
	await wait(1.0)
	var waited := 0
	while t.is_running() and waited < 400:
		waited += 1
		await get_tree().physics_frame
	check(p.health < hp0, "стоя на полу — ожоги (%.0f → %.0f)" % [hp0, p.health])
	check(t.state == "failed" and t.burn > t.def.lava_max_burn, "долго в лаве — провал (ожог %.1f с)" % t.burn)
	await wait(0.8)
	check(t.get_node_or_null("Lava") == null, "лава убрана после провала")
	for e in game.room.alive_enemies():
		e.set_physics_process(true)
	await _kill_all("melee_finisher")
	await wait(1.5)
	check(not game.rune_pick.visible, "провал — без руны")

func _test_time_fail() -> void:
	var t := _trial()
	t.elapsed = t.def.time_limit + 0.5
	await wait(0.1)
	check(t.state == "failed", "таймер вышел — провал («%s»)" % t.fail_reason)
	await _kill_all("melee_finisher")
	var g0 := Run.glory
	await wait(1.5)
	check(Run.glory - g0 < t.def.reward_glory, "без награды (Слава +%d)" % (Run.glory - g0))
	check(game.rewards.doors.size() == 1 and game.rewards.doors[0].reward_id == "boss", "дальше — босс")

func _finish() -> void:
	print("=== ИТОГ: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
