extends Node
## Тест комиксовых слов (этап 4): слова на сильных событиях и только на них, кулдаун, лимит на экране,
## переключатель в настройках, синхронизация с hit-stop.
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/comic_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game
var CF: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "ComicRunner"
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

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func events() -> Array[String]:
	var out: Array[String] = []
	for h in CF.history:
		out.append(String(h.event))
	return out

func last() -> Dictionary:
	return CF.history[-1] if not CF.history.is_empty() else {}

func fresh() -> void:
	FX.reset_time()
	CF.reset_state()
	# Слова рангов шкалы стиля (блок Б3) — свой тест (style_test); здесь шкала не мешает
	if game and is_instance_valid(game.player):
		game.player.style.reset()
		game.player.style.reset_cooldowns()
	await frames(1)

func _run() -> void:
	print("=== COMIC TEST ===")
	CF = get_tree().root.get_node("ComicFX")
	GameSettings.ensure_loaded()
	var saved_enabled := GameSettings.comic_enabled
	var saved_scale := GameSettings.comic_scale
	GameSettings.comic_enabled = true
	# Обычные слова в игре показываются через раз (routine_chance) — тест проверяет каждое
	var saved_chance: float = CF.routine_chance
	CF.routine_chance = 1.0
	Run.start_run("berserker")
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.3)
	game = get_tree().current_scene as Game
	check(game != null, "сцена игры загрузилась")
	if game == null:
		_finish()
		return
	await wait(1.6)
	var p := game.player
	for e in game.room.alive_enemies():
		e.global_position = Vector3(game.room.global_position.x + 9, 0.1, -9)
		e.set_physics_process(false)
	p.global_position = game.room.global_position + Vector3(3, 0.1, 10)
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2(0, 0)
	await wait(0.3)

	print("-- Обычные удары")
	await fresh()
	var d := _make_dummy(p, 1.6)
	d.take_hit(5, Vector3.ZERO, "axe")
	await frames(3)
	d.take_hit(5, Vector3.ZERO, "melee")
	await frames(3)
	d.take_hit(5, Vector3.ZERO, "hammer")
	await frames(3)
	d.take_hit(5, Vector3.ZERO, "ranged")
	await frames(3)
	var hp0 := d.health
	p.axe.request_attack()
	await wait(0.4)
	check(d.health < hp0, "обычный удар топором попал")
	check(CF.history.is_empty() and CF.stats.requested == 0, "обычные удары не дают слов (%s)" % [events()])

	print("-- Крит (тяжёлый 3-й удар) и кулдаун")
	await wait(0.5)
	await fresh()
	d.take_hit(5, Vector3.ZERO, "axe_finisher")
	await frames(2)
	check(events() == ["blade"], "крит финишером → слово топора (%s)" % [events()])
	check(String(last().get("text", "")) in ["CHOP!", "SLASH!", "SHNK!"], "слово из словаря (%s)" % last().get("text", ""))
	check(CF.active_count() == 1, "слово на экране")
	d.take_hit(5, Vector3.ZERO, "melee_finisher")
	await frames(2)
	check(CF.history.size() == 1 and CF.stats.cooldown == 1, "второе слово сразу — отсечено кулдауном")
	await wait(CF.cooldown + 0.05)
	d.take_hit(5, Vector3.ZERO, "melee_finisher")
	await frames(2)
	check(CF.history.size() == 2, "после кулдауна — снова слово (melee_finisher)")
	await wait(1.0)
	check(CF.active_count() == 0, "слова исчезли сами")

	print("-- Настоящее комбо топора")
	await fresh()
	p.axe.request_attack()
	await wait(0.35)
	check(CF.history.is_empty(), "1-й удар комбо — без слова")
	p.axe.request_attack()
	await wait(0.1)
	p.axe.request_attack()
	await wait(0.6)
	check(p.axe.stage == 2 and events().count("blade") == 1 and CF.history.size() == 1, "слово только на 3-м ударе комбо (%s)" % [events()])
	d.take_hit(9999, Vector3.ZERO, "test")
	await wait(0.6)

	print("-- Удар-приземление")
	await fresh()
	p.call("_do_slam_impact", 3.0)
	await frames(2)
	check(events() == ["slam"] and not bool(last().get("big", true)), "удар-приземление → слово в мире (%s)" % [events()])
	await wait(0.6)
	await fresh()
	p.call("_do_slam_impact", 12.0)
	check(FX._hitstop_left >= CF.big_slam_hitstop - 0.001, "приземление с 10+ м → hit-stop %.0f мс" % (FX._hitstop_left * 1000.0))
	await frames(3)
	check(events() == ["slam"] and bool(last().get("big", false)), "приземление с 10+ м → крупное слово на весь экран")
	var w: Node2D = null
	for pw in CF._pool:
		if pw.active:
			w = pw
	check(w != null and Engine.time_scale < 0.5 and w.scale.x > 0.3, "слово видно уже во время hit-stop (масштаб %.2f, time_scale %.2f)" % [w.scale.x if w else 0.0, Engine.time_scale])
	check(CF._vignette.visible, "виньетка под крупным словом")
	await wait(0.3)
	check(Engine.time_scale == 1.0, "hit-stop закончился")
	check(CF.active_count() == 1 and w.modulate.a > 0.5, "после стопа слово ещё держится")
	await wait(2.0)
	check(CF.active_count() == 0 and not CF._vignette.visible, "крупное слово не залипает")

	print("-- Слово связки и реплика Одина")
	await fresh()
	game.hud.show_odin_line("Огненный смерч! Только не деревянный.")
	CF.pop("combo", p.get_aim_origin() + p.get_aim_forward() * 3.0, true)
	await frames(6)
	check(events() == ["combo"] and CF.active_count() == 1 and game.hud._odin_panel.modulate.a > 0.0,
		"слово связки и реплика видны одновременно")
	check(CF._layer.layer < game.hud.layer, "слово и виньетка связки не закрывают реплику Одина")
	# Общий слой остаётся под HUD, пока живо хотя бы одно слово связки.
	CF.pop("slam", p.get_aim_origin() + p.get_aim_forward() * 3.0, true)
	await frames(3)
	check(CF.active_count() == 2 and CF._layer.layer < game.hud.layer, "новое слово не возвращает слой над репликой связки")
	CF.pop("boss_kill", Vector3.ZERO, true)
	await frames(3)
	CF.pop("rank_4", Vector3.ZERO, true) # полный пул вытесняет самое старое слово — связку
	await frames(3)
	check(CF.active_count() == CF.max_on_screen and CF._layer.layer > game.hud.layer,
		"вытеснение связки возвращает обычный слой остальным словам")
	await fresh()
	CF.pop("combo", Vector3.ZERO, true)
	await frames(3)
	await wait(1.5)
	check(CF.active_count() == 0 and CF._layer.layer > game.hud.layer, "после окончания связки обычный слой восстановлен")
	CF.pop("combo", Vector3.ZERO, true)
	await frames(3)
	CF._last_pop = -100.0 # образец настраивается во время активного слова, минуя боевой кулдаун
	CF.preview()
	await frames(3)
	check(CF._layer.layer == 25, "одновременный образец в настройках остаётся поверх меню")
	CF.reset_state()
	check(CF.active_count() == 0 and CF._layer.layer > game.hud.layer and not CF._vignette.visible,
		"сброс отменяет слова и сразу восстанавливает обычный слой и виньетку")
	CF.pop("slam", p.get_aim_origin() + p.get_aim_forward() * 3.0, true)
	await frames(3)
	check(events() == ["slam"] and CF._layer.layer > game.hud.layer, "другое крупное слово остаётся над HUD")
	await wait(1.5)

	print("-- Мульти-килл и добивание")
	await fresh()
	for i in 3:
		_make_dummy(p, 3.0 + i).take_hit(9999, Vector3.ZERO, "test")
	await frames(2)
	check(events() == ["multikill"] and not bool(last().big), "3 убийства разом → мульти-килл (%s)" % [events()])
	await wait(0.8)
	await fresh()
	for i in CF.multikill_big_count:
		_make_dummy(p, 3.0 + i).take_hit(9999, Vector3.ZERO, "test")
	await frames(2)
	check(events() == ["multikill"] and not bool(last().big) and not ("multikill" in CF.fullscreen_events),
		"%d убийств → крупный мульти-килл у места, не на весь экран" % CF.multikill_big_count)
	await wait(1.2)
	await fresh()
	_make_dummy(p, 2.0).take_hit(9999, Vector3.ZERO, "test")
	await frames(2)
	check(CF.history.is_empty(), "одиночное убийство обычным ударом — без слова")
	await wait(0.8)
	await fresh()
	_make_dummy(p, 2.0).take_hit(9999, Vector3.ZERO, "melee_finisher")
	await frames(2)
	check(events() == ["blade"], "добивание финишером → слово")
	await wait(0.8)

	print("-- Отражение снаряда")
	await fresh()
	var proj: Node3D = preload("res://enemies/enemy_projectile.gd").new()
	game.add_child(proj)
	proj.call("launch", p.global_position + Vector3(0, 1.2, -3), Vector3(0, 0, 4), 5.0, null)
	await frames(1)
	proj.call("reflect", Vector3(0, 0, -1))
	await frames(2)
	check(events() == ["parry"], "отражение снаряда → слово (%s)" % [events()])
	if is_instance_valid(proj):
		proj.queue_free()
	await wait(0.8)

	print("-- Мьёльнир")
	await fresh()
	CF.on_hammer_hit(null, p.global_position, false, 0)
	await frames(2)
	check(CF.history.is_empty(), "обычное попадание молотом — без слова")
	var hd := _make_dummy(p, 4.0)
	await frames(1)
	p.mjolnir.throw_hammer()
	await wait(0.2)
	check(hd.health < hd.max_health - 1.0, "молот попал по манекену (туда)")
	check(not "hammer" in events(), "попадание молотом туда без рикошета — без слова (%s)" % [events()])
	# Попадание на возврате — через ту же функцию снаряда, что и в бою
	await fresh()
	var proj_h: Node3D = p.mjolnir.projectile
	check(proj_h != null, "снаряд молота найден")
	if proj_h:
		proj_h.call("start_return")
		proj_h.call("_on_hit", hd, Vector3.BACK)
	await frames(2)
	check(events() == ["hammer"], "попадание на возврате → слово (%s)" % [events()])
	check(String(last().get("text", "")) in ["BONK!", "THUNK!", "KRAK!"], "слово молота из словаря")
	await wait(2.0)
	check(p.mjolnir.in_hand, "молот вернулся")
	hd.take_hit(9999, Vector3.ZERO, "test")
	await wait(0.6)
	# Рикошет: стена перед игроком. Отскоки от стен — трейт «Рикошет» (этап 3), без него молот втыкается
	await fresh()
	for t in Run.all_mjolnir_traits:
		if t.id == &"ricochet":
			Run.add_mjolnir_trait(t)
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(6, 6, 0.5)
	cs.shape = bs
	wall.add_child(cs)
	game.add_child(wall)
	var fwd := p.get_aim_forward()
	wall.global_position = p.get_aim_origin() + fwd * 4.0
	wall.look_at(p.get_aim_origin())
	await get_tree().physics_frame
	p.mjolnir.throw_hammer()
	await wait(0.5)
	check("ricochet" in events(), "рикошет молота от стены → слово (%s)" % [events()])
	await wait(2.0)
	wall.queue_free()
	await wait(0.3)

	print("-- Удары по игроку")
	await fresh()
	var grunt := _make_dummy(p, 1.5)
	grunt.look_at(Vector3(p.global_position.x, grunt.global_position.y, p.global_position.z), Vector3.UP, true)
	grunt.player = p
	p.set("_invuln_left", 0.0)
	var hp_p := p.health
	grunt.call("_do_melee")
	await frames(2)
	check(p.health < hp_p and CF.history.is_empty(), "удар грунта по игроку — без слова")
	grunt.take_hit(9999, Vector3.ZERO, "test")
	await wait(0.5)
	await fresh()
	var boss := (load("res://enemies/boss.tscn") as PackedScene).instantiate() as Enemy
	game.add_child(boss)
	var f2 := p.get_aim_forward()
	f2.y = 0
	boss.global_position = p.global_position + f2.normalized() * 2.0
	boss.set_physics_process(false)
	boss.look_at(Vector3(p.global_position.x, boss.global_position.y, p.global_position.z), Vector3.UP, true)
	boss.player = p
	p.set("_invuln_left", 0.0)
	hp_p = p.health
	boss.call("_do_melee")
	await frames(2)
	check(p.health < hp_p and events() == ["player_hurt"], "удар босса по игроку → OOF/UGH (%s)" % [events()])
	check(String(last().get("text", "")) in ["OOF!", "UGH!"], "слово по игроку из словаря")
	await wait(0.8)
	await fresh()
	boss.take_hit(99999, Vector3.ZERO, "melee_finisher")
	await frames(2)
	check(events() == ["boss_kill"] and bool(last().big) and last().text == "KA-THOOM!", "добивание босса → KA-THOOM! на весь экран (%s)" % [events()])
	await wait(1.5)

	print("-- Лимит на экране")
	await fresh()
	var cd: float = CF.cooldown
	CF.cooldown = 0.0
	for ev in ["slam", "blade", "blunt", "hammer", "ricochet", "parry"]:
		CF.pop(ev, p.get_aim_origin() + p.get_aim_forward() * 4.0)
		await frames(1)
	check(CF.active_count() == CF.max_on_screen and CF.history.size() == 3 and CF.stats.limit == 3, "на экране не больше %d слов (активно %d, отсечено %d)" % [CF.max_on_screen, CF.active_count(), CF.stats.limit])
	CF.pop("boss_kill", Vector3.ZERO, true)
	await frames(1)
	check(CF.active_count() == CF.max_on_screen and CF.history.size() == 4, "крупное слово вытесняет старое, лимит соблюдён")
	CF.cooldown = cd
	await wait(1.5)

	print("-- Выключатель Comic FX")
	await fresh()
	GameSettings.comic_enabled = false
	var d2 := _make_dummy(p, 2.0)
	d2.take_hit(5, Vector3.ZERO, "axe_finisher")
	await frames(2)
	p.call("_do_slam_impact", 12.0)
	check(FX._hitstop_left > 0.1, "hit-stop приземления работает и без слов")
	await frames(2)
	check(CF.history.is_empty() and CF.active_count() == 0 and CF.stats.disabled >= 1, "при выключенном Comic FX слов нет")
	GameSettings.comic_enabled = true
	d2.take_hit(9999, Vector3.ZERO, "test")
	await wait(0.6)

	print("-- Сохранение настроек")
	GameSettings.set_comic_scale(1.3)
	GameSettings.set_comic_enabled(false)
	var cf := ConfigFile.new()
	check(cf.load(GameSettings.path) == OK and is_equal_approx(float(cf.get_value("comic", "scale", 0.0)), 1.3) and cf.get_value("comic", "enabled", true) == false, "настройки записаны в settings.cfg [comic]")
	GameSettings.set_comic_scale(saved_scale)
	GameSettings.set_comic_enabled(saved_enabled)
	_finish()

func _make_dummy(p: Player, dist: float) -> Enemy:
	var e := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	e.max_health = 500
	game.add_child(e)
	var fwd := p.get_aim_forward()
	fwd.y = 0
	fwd = fwd.normalized()
	e.global_position = p.global_position + fwd * dist
	e.set_physics_process(false)
	e.health = 500
	return e

func _finish() -> void:
	print("=== ИТОГ: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	FX.reset_time()
	get_tree().quit(1 if _fails.size() > 0 else 0)
