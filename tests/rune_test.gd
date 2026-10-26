extends Node
## Руны по GDD 11: уровни 1–3, выбор (без максимальных и проклятых), значения у жреца, эффекты рун.
## godot --headless --path . --fixed-fps 60 res://tests/rune_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
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
	for i in int(ceil(sec * 60.0)):
		await get_tree().physics_frame

func rune(id: String) -> RuneDef:
	return Run.rune_def(id)

func give(id: String, times: int = 1) -> void:
	for i in times:
		Run.add_rune(rune(id))
	game.player.recalc_from_runes(Run)

func clear_runes() -> void:
	Run.runes.clear()
	game.player.recalc_from_runes(Run)

func dummy(dist: float, hp: float = 5000.0) -> Enemy:
	var e := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	e.max_health = hp
	game.add_child(e)
	var p := game.player
	var f := p.get_aim_forward()
	f.y = 0
	e.global_position = p.global_position + f.normalized() * dist
	e.health = hp
	e.set_physics_process(false)
	return e

func _run() -> void:
	print("=== RUNE TEST ===")
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.6)
	game = get_tree().current_scene as Game
	game.room.set_physics_process(false)
	await wait(0.8)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	var p := game.player
	await wait(0.2)

	print("-- Данные и уровни")
	var impl := 0
	for r in Run.all_runes:
		if r.implemented and not r.cursed:
			impl += 1
			if r.level_values.size() != 3:
				check(false, "у руны %s три значения уровней" % r.id)
	check(impl >= 25, "рун с механикой: %d (из 25 по GDD)" % impl)
	clear_runes()
	give("max_health", 4)
	check(Run.rune_level("max_health") == 3, "повтор повышает уровень, максимум 3")
	check(is_equal_approx(p.max_health, 150.0 + 80.0), "Яблоко Идунн ур. 3: +80 HP (%.0f)" % p.max_health)
	var choices_ok := true
	for i in 30:
		for r in Run.random_rune_choices(3):
			if r.id == "max_health" or r.cursed or not r.implemented:
				choices_ok = false
	check(choices_ok, "в выборе нет рун ур. 3, проклятых и без механики")
	check(Run.random_cursed_rune() != null and Run.random_cursed_rune().cursed, "проклятая руна Локи — отдельно (сделка Локи)")
	clear_runes()
	Run.rune_power = 2
	give("max_health", 1)
	check(is_equal_approx(p.max_health, 150.0 + 60.0), "жрец: руны ×2 (Яблоко ур. 1 → +60)")
	give("thunder_call", 1)
	check(int(Run.rune_value("thunder_call")) == 3, "жрец: «каждый 5-й» → чаще (каждый %d-й)" % int(Run.rune_value("thunder_call")))
	Run.rune_power = 1
	clear_runes()

	print("-- Движение и защита")
	var sp0 := p.effective_move_speed()
	give("njord_wind", 3)
	check(absf(p.effective_move_speed() / sp0 - 1.25) < 0.01, "Ветер Ньёрда ур. 3: бег +25%")
	var j0 := p.extra_jumps
	give("valkyrie_wings", 1)
	check(p.extra_jumps == j0 + 1, "Крылья валькирии: +1 прыжок в воздухе")
	clear_runes()
	give("bear_skin", 3)
	p._invuln_left = 0.0
	var hp := p.health
	p.take_damage(20.0)
	check(absf((hp - p.health) - 15.0) < 0.01, "Шкура медведя ур. 3: урон −25%% (%.1f)" % (hp - p.health))
	clear_runes()
	give("sif_shield", 1)
	p.refill_shield()
	check(is_equal_approx(p.shield, 20.0), "Щит Сиф: 20 HP щита")
	p._invuln_left = 0.0
	hp = p.health
	p.take_damage(15.0)
	check(is_equal_approx(p.health, hp) and is_equal_approx(p.shield, 5.0), "щит принимает урон первым")
	game.room._spawn_wave(0)
	check(is_equal_approx(p.shield, 20.0), "щит восстановился с новой волной")
	game.room._spawn_queue.clear()
	clear_runes()
	give("second_wind", 1)
	p._invuln_left = 0.0
	p.take_damage(99999.0)
	check(not p.is_dead and absf(p.health - p.max_health * 0.3) < 1.0, "Второе дыхание: встал с 30% HP")
	p.heal(9999)
	clear_runes()

	print("-- Атака")
	var e := dummy(2.0)
	p.crit_chance_base = 1.0
	var h0 := e.health
	p.deal_damage(e, 10.0, Vector3.ZERO, "melee")
	check(absf((h0 - e.health) - 20.0) < 0.5, "крит ×2 (%.1f)" % (h0 - e.health))
	p.crit_chance_base = 0.0
	give("raven_eye", 3)
	check(absf(Run.rune_value("raven_eye") - 0.25) < 0.001, "Глаз ворона ур. 3: шанс крита +25%")
	clear_runes()
	give("thunder_call", 1)
	h0 = e.health
	for i in 5:
		p.deal_damage(e, 1.0, Vector3.ZERO, "melee")
	check(h0 - e.health > 20.0, "Зов грома: 5-й удар — молния (урон %.0f)" % (h0 - e.health))
	clear_runes()
	give("loki_backstab", 3)
	e.look_at(e.global_position + (e.global_position - p.global_position), Vector3.UP, true)
	h0 = e.health
	p.deal_damage(e, 10.0, Vector3.ZERO, "melee")
	check(absf((h0 - e.health) - 25.0) < 0.5, "Нож в спину Локи ур. 3: ×2.5 сзади (%.1f)" % (h0 - e.health))
	clear_runes()
	give("fenrir_fang", 1)
	p.health = 50.0
	Run.kill_registered.emit("melee_finisher")
	check(absf(p.health - (50.0 + 4.0 * float(p.modify_stat(&"heal_mult", 1.0)))) < 0.5, "Клык Фенрира: лечение за добивание мили")
	clear_runes()
	give("dash_damage", 2)
	check(is_equal_approx(Run.rune_value("dash_damage"), 30.0), "Таран Хеймдалля ур. 2: 30 урона")
	clear_runes()
	give("hammer_power", 3)
	check(absf(p.mjolnir.damage_mult / (p.hammer_damage_mult if p.hammer_damage_mult > 0 else 1.0) - 1.9) < 0.2, "Гнев Мьёльнира ур. 3: молот +90%")
	clear_runes()

	print("-- Удар-приземление и огонь")
	give("stun_thunder", 1)
	give("mountain_weight", 3)
	var e2 := dummy(2.0)
	await wait(0.1)  # тело врага попадает в физику со следующего кадра
	p._do_slam_impact(0.0)
	check(e2.state == Enemy.State.STUNNED, "Оглушающий гром: удар-приземление оглушает")
	clear_runes()
	give("fire_step", 1)
	var fires_before := _fire_count()
	p._rune_on_dash()
	check(_fire_count() > fires_before, "Огненный шаг: рывок оставляет огонь")
	clear_runes()

	print("-- Ренж, Ярость, мета")
	give("endless_quiver", 2)
	var it := WeaponItem.create(load("res://weapons/defs/pistol.tres") as WeaponDef, 1)
	check(it.reserve_cap() == it.def.reserve_max * 2, "Бездонный колчан ур. 2: запас ×2")
	clear_runes()
	give("berserk_song", 3)
	p.rage.kills = 0
	for i in 5:
		p.rage.add_kill()
	check(p.rage.kills >= 9, "Песнь берсерка ур. 3: Ярость быстрее (%d за 5 убийств)" % p.rage.kills)
	clear_runes()
	give("ancestor_glory", 3)
	var g0 := Run.glory
	Run.add_glory(100)
	check(Run.glory - g0 == 140, "Слава предков ур. 3: +40%% (%d)" % (Run.glory - g0))
	clear_runes()
	give("brokk_greed", 3)
	var sv0 := Run.silver
	Run.add_silver(10)
	check(Run.silver - sv0 == 16, "Жадность Брокка ур. 3: серебро +60%% (%d)" % (Run.silver - sv0))
	clear_runes()

	print("-- Проклятые руны Локи")
	p.health = p.max_health  # «Кровавая ярость» Берсерка не должна мешать счёту урона
	give("loki_glass", 1)
	h0 = e.health
	p.deal_damage(e, 10.0, Vector3.ZERO, "melee")
	check(absf((h0 - e.health) - 18.0) < 0.5, "Стеклянная пушка: урон ×1.8")
	p._invuln_left = 0.0
	hp = p.health
	p.take_damage(10.0)
	check(absf((hp - p.health) - 15.0) < 0.5, "Стеклянная пушка: входящий урон ×1.5")
	clear_runes()
	give("loki_hiccup", 1)
	p._hiccup_t = p.hiccup_period - 0.01
	await wait(0.1)
	check(p.velocity.y > 1.0 or p._hiccup_t < 1.0, "Икота Локи: Тор подпрыгнул сам")
	clear_runes()
	give("loki_spin", 1)
	check(p.dash_charges_max >= 3, "Вертушка Локи: +2 рывка")
	clear_runes()
	_finish()

func _fire_count() -> int:
	var n := 0
	for c in game.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with("fire_zone.gd"):
			n += 1
	return n

func _finish() -> void:
	print("=== ИТОГ RUNES: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
