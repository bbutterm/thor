extends Node
## Шкала стиля «ДОСТОЙНО!» (блок Б3, GDD 8) и бой-реплики Одина (GDD 17): очки за каждый приём и способ
## убийства (и настоящие хуки: отскок, прыжок по головам, идеальный хват, шмяк, отражение, падение, взрыв,
## мульти-килл), штраф за повтор и его забывание, урон сбивает шкалу, спад без очков, пороги всех рангов,
## берсерк на высшем (×1.5 урона и скорости, 8 с, без отбрасывания), множитель Славы, слой музыки,
## слова комикса и голос Одина один раз на повышение (с кулдауном и лимитом), руна «Песнь берсерка», HUD;
## реплики «ДВИГАЙСЯ!», «Хоть что-то», «Скуф…», «Позорище», «Вот! ВОТ!» и лимит 12 с.
## godot --headless --path . --fixed-fps 60 res://tests/style_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game
var lines: Array[String] = []
var gains: Array = []  # [action, amount]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "StyleRunner"
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

func press(action: String, hold: float = 0.05) -> void:
	Input.action_press(action)
	await wait(hold)
	Input.action_release(action)

func _floor_pos() -> Vector3:
	return Vector3(game.room.global_position.x, 0.05, game.room.global_position.z + 8.0)

func _dummy(pos: Vector3, hp: float = 500.0, scene: String = "res://enemies/grunt.tscn") -> Enemy:
	var e := (load(scene) as PackedScene).instantiate() as Enemy
	e.max_health = hp
	game.add_child(e)
	e.global_position = pos
	e.health = hp
	e.set_physics_process(false)
	return e

## Последняя реплика Одина — из пула события?
func said(event: String) -> bool:
	if lines.is_empty():
		return false
	for it in Dialogue.pools.get("odin." + event, []):
		for l in it.lines:
			if Dialogue.format_text(str(l.get("text", ""))) == lines[-1]:
				return true
	return false

## Начислено ли за приём (после последней очистки gains)
func gained(action: StringName) -> float:
	var sum := 0.0
	for g in gains:
		if g[0] == action:
			sum += float(g[1])
	return sum

func _fresh(s: StyleMeter) -> void:
	s.reset()
	s.reset_cooldowns()
	gains.clear()

func _run() -> void:
	print("=== STYLE TEST ===")
	Run.start_run("hunter")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.5)
	game = get_tree().current_scene as Game
	await wait(1.0)
	game.room.set_physics_process(false)
	# Враги зала стоят замороженными далеко — «идёт бой» (для музыки), но никто не бьёт
	for e in game.room.alive_enemies():
		e.set_physics_process(false)
		e.global_position = _floor_pos() + Vector3(0, -40.0, 0)
	game.tracker.idle_time = 1.0e6  # «ДВИГАЙСЯ!» не мешает лимиту реплик (вернём в _test_lines)
	await wait(0.2)
	Odin.line_spoken.connect(func(t: String) -> void: lines.append(t))
	game.player.style.gained.connect(func(a: StringName, n: float) -> void: gains.append([a, n]))
	game.player.crit_chance_base = 0.0  # крит 5 % (GDD 8) делал проверки урона случайными
	await _test_numbers()
	await _test_points()
	await _test_repeat()
	await _test_hooks()
	await _test_damage_and_decay()
	await _test_ranks()
	await _test_glory_music()
	await _test_voice_and_comic()
	await _test_berserk()
	await _test_rune()
	game.player.style.reset()
	await _test_lines()
	_finish()

func _test_numbers() -> void:
	var p := game.player
	var s := p.style
	print("-- Числа и узлы")
	check(s != null and s.name == "StyleMeter" and p.rage == s, "у игрока шкала стиля (Player.rage — то же)")
	var t := s.tuning
	check(t.rank_points == PackedFloat32Array([0, 15, 35, 60, 100]), "пороги рангов 0/15/35/60/100 (%s)" % [t.rank_points])
	check(is_equal_approx(t.berserk_time, 8.0) and is_equal_approx(t.damage_mult, 1.5) and is_equal_approx(t.speed_mult, 1.5), "берсерк 8 с, ×1.5 урона и скорости")
	check(StyleMeter.RANK_NAMES == ["Скуф", "Сойдёт", "Неплохо", "Достойно", "ДОСТОЙНЕЙШИЙ!"], "ранги по GDD")
	var hud := game.hud.get_node_or_null("StyleHUD") as StyleHUD
	check(hud != null and hud._bar is SkinBar, "шкала стиля в HUD (рамка комплекта)")
	check(game.hud.get_node_or_null("RageHUD") == null, "старой шкалы Ярости нет")

## Каждое действие таблицы — своя цена при первом применении; источник урона → способ убийства
func _test_points() -> void:
	var s := game.player.style
	print("-- Очки за приём (первое применение)")
	var t := s.tuning
	for key in t.points.keys():
		_fresh(s)
		var got := s.add_action(StringName(key))
		check(is_equal_approx(got, float(t.points[key])) and is_equal_approx(s.points, got), "%s: +%.1f" % [key, got])
	var map := {"melee": &"kill_melee", "melee_finisher": &"kill_finisher", "melee_heavy": &"kill_heavy",
		"ranged": &"kill_ranged", "slam": &"kill_slam", "stomp": &"kill_stomp", "hammer": &"kill_hammer",
		"lightning": &"kill_hammer", "fall": &"kill_fall", "wall": &"kill_wall", "reflect": &"kill_reflect",
		"dash": &"kill_dash", "explosion": &"kill_explosion", "fire": &"kill_fire", "zzz": &"kill_other"}
	var bad: Array[String] = []
	for src in map.keys():
		if StyleMeter.kill_action(src) != map[src]:
			bad.append(src)
	check(bad.is_empty(), "источник урона → способ убийства (ошибки: %s)" % [bad])
	check(t.points.kill_ranged < t.points.kill_melee and t.points.kill_melee < t.points.kill_slam and t.points.kill_slam < t.points.kill_fall,
		"ренж < мили < удар-приземление < сбил с края")
	# Мульти-килл: 3 убийства в окне — бонус один раз, 5 — крупный
	_fresh(s)
	for i in 5:
		s.note_kill("melee")
	check(gained(&"multikill") > 0.0 and gained(&"multikill_big") > 0.0, "3 убийства разом — мульти-килл, 5 — крупный")
	check(gains.filter(func(g: Array) -> bool: return g[0] == &"multikill").size() == 1, "мульти-килл за окно — один раз")

func _test_repeat() -> void:
	var s := game.player.style
	var t := s.tuning
	print("-- Повтор одного приёма даёт меньше")
	_fresh(s)
	var a: Array[float] = []
	for i in 4:
		a.append(s.add_action(&"kill_melee"))
	check(is_equal_approx(a[1], a[0] * t.repeat_falloff) and is_equal_approx(a[2], a[0] * pow(t.repeat_falloff, 2)), "2-й ×%.1f, 3-й ×%.2f (%.2f, %.2f, %.2f)" % [t.repeat_falloff, pow(t.repeat_falloff, 2), a[0], a[1], a[2]])
	var other := s.add_action(&"kill_slam")
	check(is_equal_approx(other, float(t.points.kill_slam)), "другой приём сразу после — полная цена (%.1f)" % other)
	for i in 10:
		s.add_action(&"kill_melee")
	check(is_equal_approx(s.repeat_mult(&"kill_melee"), t.repeat_min_mult), "заезженный приём — не меньше ×%.2f" % t.repeat_min_mult)
	check(float(s.fatigue[&"kill_melee"]) <= t.repeat_memory_max + 0.01, "усталость не выше потолка %.0f" % t.repeat_memory_max)
	var m0 := s.repeat_mult(&"kill_melee")
	await wait(4.0)
	var m1 := s.repeat_mult(&"kill_melee")
	check(m1 > m0 * 1.5, "через 4 с приём «отдохнул» (×%.2f → ×%.2f)" % [m0, m1])
	# Только один приём — шкала не доходит до верха: 60 мили-убийств подряд раз в 0.5 с
	_fresh(s)
	for i in 60:
		s.note_kill("melee")
		await wait(0.5)
	check(s.rank < 3 and not s.active, "одни мили-убийства — выше «Неплохо» не подняться (ранг %d, %.1f очков)" % [s.rank, s.points])

## Настоящие хуки из игрового кода
func _test_hooks() -> void:
	var p := game.player
	var s := p.style
	var fp := _floor_pos()
	print("-- Хуки: убийства по способу")
	for src in ["slam", "hammer", "stomp", "melee_finisher"]:
		_fresh(s)
		var d := _dummy(fp + Vector3(2, 0, -4), 5.0)
		p.deal_damage(d, 50.0, Vector3.ZERO, src)
		await wait(0.05)
		check(gained(StyleMeter.kill_action(src)) > 0.0, "убийство «%s» → %s" % [src, StyleMeter.kill_action(src)])
	# Сбил с края: корм падает с 9 м после удара
	_fresh(s)
	var f := _dummy(fp + Vector3(4, 9.0, -6), 10.0, "res://enemies/fodder.tscn")
	f.state = Enemy.State.CHASE
	f._last_hit_time = Time.get_ticks_msec() / 1000.0
	f.set_physics_process(true)
	for i in 180:
		await get_tree().physics_frame
		if gained(&"kill_fall") > 0.0:
			break
	check(gained(&"kill_fall") > 0.0, "сбитый с высоты корм разбился — «сбил с края»")
	# Взрыв бочки/Раздутого
	_fresh(s)
	var b := _dummy(fp + Vector3(-5, 0, -6), 5.0)
	Blast.detonate(game, b.global_position + Vector3(0, 0.9, 0), 2.0, 30.0)
	await wait(0.05)
	check(gained(&"kill_explosion") > 0.0, "убит взрывом")

	print("-- Хуки: трюки")
	# Отскок от удара-приземления
	_fresh(s)
	var e1 := _dummy(fp + Vector3(0, 0, -1.5))
	p.global_position = fp + Vector3(0, 6.0, 0)
	p.velocity = Vector3.ZERO
	await wait(0.05)
	await press("slam")
	for i in 90:
		await get_tree().physics_frame
		if gained(&"slam_bounce") > 0.0:
			break
	check(gained(&"slam_bounce") > 0.0, "отскок от удара-приземления")
	e1.queue_free()
	await wait(1.5)
	# Прыжок по головам
	_fresh(s)
	var e3 := _dummy(fp + Vector3(-3, 0, 0))
	await wait(0.1)
	p.global_position = e3.global_position + Vector3(0, 3.2, 0)
	p.velocity = Vector3(0, -2, 0)
	for i in 60:
		await get_tree().physics_frame
		if gained(&"stomp") > 0.0:
			break
	check(gained(&"stomp") > 0.0, "прыжок по головам")
	e3.queue_free()
	await wait(1.0)
	# Идеальный хват
	_fresh(s)
	p.mjolnir._grant_perfect()
	check(gained(&"perfect_catch") > 0.0, "идеальный хват")
	# Отражение снаряда
	_fresh(s)
	var pr := preload("res://enemies/enemy_projectile.gd").new()
	game.add_child(pr)
	pr.launch(p.global_position + Vector3(0, 1.2, -3), Vector3(0, 0, 4), 5.0, null)
	pr.reflect(Vector3(0, 1, 0))
	check(gained(&"reflect") > 0.0, "отражение снаряда (парирование)")
	# Шмяк о стену: враг летит в стену на скорости — своя площадка с ящиком-стеной над залом
	_fresh(s)
	var sky := fp + Vector3(0, 30.0, 0)
	var arena := Node3D.new()
	game.add_child(arena)
	for box in [[Vector3(0, -0.5, 0), Vector3(14, 1, 6)], [Vector3(5.5, 2.0, 0), Vector3(1, 4, 6)]]:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = box[1]
		cs.shape = bs
		sb.add_child(cs)
		arena.add_child(sb)
		sb.global_position = sky + box[0]
	var w := _dummy(sky + Vector3(3.6, 0.05, 0), 500.0)
	w.state = Enemy.State.CHASE
	w.set_physics_process(true)
	await wait(0.1)
	w.take_hit(1.0, Vector3(22, 0, 0), "melee")
	for i in 60:
		await get_tree().physics_frame
		if gained(&"wall_splat") > 0.0:
			break
	check(gained(&"wall_splat") > 0.0 and w.state == Enemy.State.STUNNED, "удар отбросил врага в стену — шмяк (%.1f м от стены)" % (sky.x + 5.0 - w.global_position.x))
	w.queue_free()
	arena.queue_free()
	# Мульти-килл настоящими убийствами
	_fresh(s)
	for i in 3:
		var dd := _dummy(fp + Vector3(-3 + i * 1.5, 0, -6), 5.0)
		p.deal_damage(dd, 50.0, Vector3.ZERO, "melee")
	await wait(0.05)
	check(gained(&"multikill") > 0.0, "3 убийства разом — мульти-килл")
	p.heal(999)

func _test_damage_and_decay() -> void:
	var p := game.player
	var s := p.style
	var t := s.tuning
	print("-- Урон сбивает шкалу")
	_fresh(s)
	p.heal(999)
	s.set_points(50.0)
	p._invuln_left = 0.0
	p.take_damage(10.0, Vector3.ZERO, true)
	check(is_equal_approx(s.points, 50.0 - t.damage_knock_min), "10 урона — минус %.0f (%.1f)" % [t.damage_knock_min, s.points])
	p.take_damage(30.0, Vector3.ZERO, true)
	check(is_equal_approx(s.points, 50.0 - t.damage_knock_min - 30.0 * t.damage_knock_per_hp), "30 урона — минус %.0f (%.1f)" % [30.0 * t.damage_knock_per_hp, s.points])
	check(s.rank == 0, "сбит до «Скуф»")
	p.heal(999)
	p.pay_health(5.0)
	check(is_equal_approx(s.points, 50.0 - t.damage_knock_min - 30.0 * t.damage_knock_per_hp), "плата здоровьем (сделка) шкалу не трогает")

	print("-- Спад без новых очков")
	_fresh(s)
	s.set_points(20.0)
	s.idle_time = 0.0
	await wait(1.0)
	check(s.points < 20.0 and s.points > 20.0 - 1.0, "первые секунды — только утечка ранга (%.2f/с): %.2f" % [t.rank_drain[1], s.points])
	await wait(t.idle_delay + 0.5)
	check(s.points < 15.0 and s.rank == 0, "через %.1f с без очков пустеет быстрее — ранг упал (%.1f)" % [t.idle_delay, s.points])
	_fresh(s)
	s.add_points(5.0)
	await wait(1.0)
	check(is_equal_approx(s.points, 5.0), "на «Скуф» без простоя не утекает")

func _test_ranks() -> void:
	var s := game.player.style
	var t := s.tuning
	print("-- Пороги рангов")
	var changes: Array = []
	var cb := func(r: int, prev: int) -> void: changes.append([r, prev])
	s.rank_changed.connect(cb)
	for r in range(1, StyleMeter.TOP):
		_fresh(s)
		s.set_points(t.rank_points[r] - 0.01)
		check(s.rank == r - 1, "%.2f очков — «%s»" % [t.rank_points[r] - 0.01, StyleMeter.rank_name(r - 1)])
		changes.clear()
		s.set_points(t.rank_points[r])
		check(s.rank == r and changes.size() == 1 and changes[0] == [r, r - 1], "%.0f очков — «%s»" % [t.rank_points[r], StyleMeter.rank_name(r)])
	_fresh(s)
	s.set_points(t.rank_points[StyleMeter.TOP] - 0.01)
	check(s.rank == 3 and not s.active, "99.99 — ещё «Достойно»")
	s.add_points(0.02)
	check(s.rank == StyleMeter.TOP and s.active, "100 — «ДОСТОЙНЕЙШИЙ!» и берсерк")
	s.rank_changed.disconnect(cb)
	_fresh(s)
	# HUD: подпись ранга и засечки
	var hud := game.hud.get_node_or_null("StyleHUD") as StyleHUD
	s.set_points(40.0)
	await wait(0.05)
	check(hud._rank_label.text == "Неплохо" and is_equal_approx(hud._bar.value, s.value()), "HUD: «%s», шкала %.2f" % [hud._rank_label.text, hud._bar.value])
	check(hud._glory_label.text == "СЛАВА ×1.25", "HUD: множитель Славы («%s»)" % hud._glory_label.text)
	_fresh(s)

func _test_glory_music() -> void:
	var p := game.player
	var s := p.style
	var t := s.tuning
	print("-- Слава по рангу")
	var body := Run.body.glory_mult if Run.body else 1.0
	for r in StyleMeter.RANKS - 1:
		_fresh(s)
		s.set_points(t.rank_points[r] + 0.5)
		check(is_equal_approx(Run.style_glory_mult, t.rank_glory_mult[r]), "«%s» — Слава ×%.2f" % [StyleMeter.rank_name(r), Run.style_glory_mult])
		Run._recent_kill_times.clear()
		var g0 := Run.glory
		Run.register_kill(false, false, false, "", 10)
		var want := int(round(int(round(10 * t.rank_glory_mult[r])) * body))
		check(Run.glory - g0 == want, "  враг на 10 Славы → +%d (ждали %d)" % [Run.glory - g0, want])
	_fresh(s)
	s.start_berserk()
	check(is_equal_approx(Run.style_glory_mult, t.rank_glory_mult[StyleMeter.TOP]), "берсерк — Слава ×%.2f" % Run.style_glory_mult)
	s.reset()
	check(is_equal_approx(Run.style_glory_mult, 1.0), "сброс — ×1")

	print("-- Слой музыки")
	_fresh(s)
	check(p.music_intensity(false) == 0 and p.music_intensity(true) == 1, "«Скуф»: фон / барабаны в бою")
	s.set_points(t.rank_points[2] + 1.0)
	check(p.music_intensity(true) == 1, "«Неплохо» в бою — барабаны")
	s.set_points(t.rank_points[3] + 20.0)
	check(p.music_intensity(true) == 2 and p.music_intensity(false) == 0, "«Достойно» в бою — полный трек, вне боя — фон")
	check(game.room.alive_count() > 0, "в зале «идёт бой» (враги заморожены)")
	await wait(1.5)
	check(Music.intensity == 2, "Music.auto: на «Достойно» — полный трек (%d)" % Music.intensity)
	_fresh(s)
	await wait(1.5)
	check(Music.intensity == 1, "Music.auto: сброс до «Скуф» — барабаны (%d)" % Music.intensity)
	s.start_berserk()
	check(p.music_intensity(false) == 2, "берсерк — полный трек даже вне боя")
	s.reset()

func _test_voice_and_comic() -> void:
	var s := game.player.style
	var t := s.tuning
	print("-- Голос Одина на ранги")
	_fresh(s)
	s.set_points(t.rank_points[2])
	Odin.reset_cooldown()
	Audio.stop_voice()
	lines.clear()
	s.set_points(t.rank_points[3] + 10.0)
	check(lines.size() == 1 and said("rank_worthy") and lines[-1] == "Достойно!", "«Достойно» — Один: «%s»" % [lines])
	check(Audio.current_voice() == "odin_dostoyno" or Audio.current_voice() == "", "голос владельца «Достойно!» (%s)" % Audio.current_voice())
	s.set_points(t.rank_points[2] + 1.0)
	Odin.reset_cooldown()
	s.set_points(t.rank_points[3] + 10.0)
	await wait(0.2)
	check(lines.size() == 1, "снова «Достойно» в пределах %.0f с — молчит (%d реплик)" % [t.voice_cooldown, lines.size()])
	# Лимит боевых реплик Одина занят — «Достойно!» скажется, когда освободится (в пределах voice_retry_time)
	_fresh(s)
	s.set_points(t.rank_points[2])
	Odin.reset_cooldown()
	Odin.say("room_clear")
	lines.clear()
	s.set_points(t.rank_points[3] + 20.0)
	await wait(0.5)
	check(lines.is_empty(), "лимит 12 с занят — молчит")
	Odin.reset_cooldown()  # лимит освободился
	await wait(0.3)
	check(said("rank_worthy"), "лимит освободился в пределах %.1f с — «Достойно!» (%s)" % [t.voice_retry_time, lines])
	# Лимит занят надолго — не говорит вовсе
	_fresh(s)
	s.set_points(t.rank_points[2])
	Odin.reset_cooldown()
	Odin.say("room_clear")
	lines.clear()
	s.set_points(t.rank_points[3] + 20.0)
	await wait(t.voice_retry_time + 0.3)
	check(lines.is_empty(), "лимит занят дольше %.1f с — реплика пропущена" % t.voice_retry_time)

	print("-- Высший ранг: «ДОСТОЙНЕЙШИЙ!»")
	_fresh(s)
	Odin.reset_cooldown()
	Odin.say("room_clear")  # лимит занят — высший ранг всё равно орёт
	Audio.stop_voice()
	lines.clear()
	s.set_points(100.0)
	check(said("rank_top") and lines[-1] == "ДОСТОЙНЕЙШИЙ!", "берсерк — «ДОСТОЙНЕЙШИЙ!» без лимита (%s)" % [lines])
	check(Audio.current_voice() == "odin_dostoyneyshiy" or Audio.current_voice() == "", "голос владельца «ДОСТОЙНЕЙШИЙ!» (%s)" % Audio.current_voice())
	s.reset()
	lines.clear()
	s.set_points(100.0)
	check(said("berserk") and not said("rank_top"), "второй берсерк в пределах %.0f с — другая реплика пула berserk (%s)" % [t.voice_cooldown, lines])
	s.reset()
	Odin.reset_cooldown()

	print("-- Слово комикса на повышение")
	_fresh(s)
	ComicFX.reset_state()
	await get_tree().process_frame
	# Мульти-килл поднял ранг: сначала слово приёма, слово ранга — через rank_pop_delay
	for i in 3:
		var dd := _dummy(_floor_pos() + Vector3(-3 + i * 1.5, 0, -6), 5.0)
		game.player.deal_damage(dd, 50.0, Vector3.ZERO, "melee")
	await get_tree().process_frame
	await get_tree().process_frame
	var ev := ComicFX.history.map(func(h: Dictionary) -> String: return str(h.event))
	check(s.rank == 1 and ev == ["multikill"], "мульти-килл поднял до «Сойдёт» — сначала слово приёма (%s)" % [ev])
	await wait(t.rank_pop_delay + 0.1)
	ev = ComicFX.history.map(func(h: Dictionary) -> String: return str(h.event))
	check(ev == ["multikill", "rank_1"], "через %.2f с — слово ранга «%s» (%s)" % [t.rank_pop_delay, ComicFX.history[-1].text if not ComicFX.history.is_empty() else "", ev])
	s.set_points(1.0)
	await wait(0.5)
	s.set_points(t.rank_points[1] + 1.0)
	await wait(t.rank_pop_delay + 0.2)
	ev = ComicFX.history.map(func(h: Dictionary) -> String: return str(h.event))
	check(ev.count("rank_1") == 1, "повтор ранга в пределах %.0f с — без слова" % t.rank_pop_cooldown)
	s.set_points(t.rank_points[2] + 0.5)
	await wait(0.1)
	s.set_points(1.0)
	await wait(t.rank_pop_delay + 0.2)
	ev = ComicFX.history.map(func(h: Dictionary) -> String: return str(h.event))
	check(not "rank_2" in ev, "ранг упал, пока слово ждало, — слова нет")
	s.set_points(100.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var big := ComicFX.history.filter(func(h: Dictionary) -> bool: return h.event == "rank_4")
	check(big.size() == 1 and big[0].big and big[0].text == "MOST WORTHY!", "высший ранг — крупно «MOST WORTHY!» (%s)" % [big])
	s.reset()
	var hud := game.hud.get_node_or_null("StyleHUD") as StyleHUD
	s.set_points(t.rank_points[2] + 1.0)
	await get_tree().process_frame
	check(hud._punch > 0.5 and hud._caption.scale.x > 1.1, "HUD: подпись «бьёт» при повышении (×%.2f)" % hud._caption.scale.x)
	_fresh(s)

func _test_berserk() -> void:
	var p := game.player
	var s := p.style
	var t := s.tuning
	print("-- Берсерк на высшем ранге")
	_fresh(s)
	p.heal(999)
	var base_speed := p.effective_move_speed()
	var started := [false]
	var ended := [false]
	s.berserk_started.connect(func() -> void: started[0] = true, CONNECT_ONE_SHOT)
	s.berserk_ended.connect(func() -> void: ended[0] = true, CONNECT_ONE_SHOT)
	s.set_points(95.0)
	check(not s.active, "95 — ещё не берсерк")
	s.add_action(&"kill_fall")
	check(s.active and started[0] and s.rank == StyleMeter.TOP and is_equal_approx(s.berserk_left, t.berserk_time), "сбил с края на 95 — берсерк на %.0f с" % s.berserk_left)
	check(p.is_berserk(), "Player.is_berserk()")
	var e := _dummy(_floor_pos() + Vector3(0, 0, -4))
	check(is_equal_approx(p.outgoing_damage_mult(e, "melee"), 1.5), "урон ×1.5 (%.2f)" % p.outgoing_damage_mult(e, "melee"))
	var hp0 := e.health
	p.deal_damage(e, 10.0, Vector3.ZERO, "melee")
	check(is_equal_approx(hp0 - e.health, 15.0), "deal_damage в берсерке: 10 → %.1f" % (hp0 - e.health))
	check(is_equal_approx(p.effective_move_speed(), base_speed * 1.5), "скорость ×1.5 (%.1f → %.1f)" % [base_speed, p.effective_move_speed()])
	check(s.is_stun_immune(), "неуязвимость к стану")
	p.velocity = Vector3.ZERO
	p.take_damage(1.0, Vector3(20, 0, 0), true)
	check(absf(p.velocity.x) < 0.5, "удар не отбрасывает (vx=%.1f)" % p.velocity.x)
	check(s.active and is_equal_approx(s.points, 100.0), "урон в берсерке шкалу не сбивает")
	check(s.add_action(&"kill_slam") == 0.0, "в берсерке шкала не копится")
	await wait(0.1)
	var hud := game.hud.get_node_or_null("StyleHUD") as StyleHUD
	check(hud._glory_label.text.begins_with("БЕРСЕРК") and hud._rank_label.text == "ДОСТОЙНЕЙШИЙ!", "HUD: «%s» / «%s»" % [hud._rank_label.text, hud._glory_label.text])
	await wait(4.0)
	check(s.active, "через 4 с берсерк ещё идёт")
	await wait(4.1)
	check(not s.active and ended[0], "через 8 с берсерк выключился")
	check(s.rank == t.after_berserk_rank and s.points > t.rank_points[t.after_berserk_rank] + 5.0,
		"после берсерка — середина «%s» (%.1f)" % [StyleMeter.rank_name(s.rank), s.points])
	check(is_equal_approx(p.outgoing_damage_mult(e, "melee"), 1.0) and is_equal_approx(p.effective_move_speed(), base_speed), "множители вернулись")
	check(not s.is_stun_immune(), "стан снова действует")
	e.queue_free()
	_fresh(s)

func _test_rune() -> void:
	var s := game.player.style
	var t := s.tuning
	print("-- Руна «Песнь берсерка»")
	var rune := Run.rune_def("berserk_song")
	check(rune != null and rune.implemented and "Шкала стиля" in rune.description, "руна про шкалу стиля: «%s»" % (rune.description if rune else ""))
	for lvl in 3:
		Run.add_rune(rune)
		_fresh(s)
		var got := s.add_action(&"kill_melee")
		var want := float(t.points.kill_melee) * (1.0 + Run.rune_value("berserk_song"))
		check(Run.rune_level("berserk_song") == lvl + 1 and Run.rune_value("berserk_song") >= rune.level_values[lvl] - 0.001, "  уровень %d: +%d %%" % [lvl + 1, roundi(Run.rune_value("berserk_song") * 100.0)])
		check(is_equal_approx(got, want), "ур. %d: мили-убийство +%.2f (ждали %.2f)" % [lvl + 1, got, want])
	Run.runes.clear()
	Run.runes_changed.emit(Run.runes)
	_fresh(s)

func _test_lines() -> void:
	var p := game.player
	game.tracker.idle_time = 4.0
	game.tracker._idle = 0.0
	p.heal(999)
	print("-- Бой-реплики Одина (GDD 17)")
	# «Позорище» — добил ренжем
	Odin.reset_cooldown()
	lines.clear()
	var d := _dummy(_floor_pos() + Vector3(2, 0, -4), 5.0)
	p.deal_damage(d, 50.0, Vector3.ZERO, "ranged")
	await wait(0.1)
	check(said("ranged_kill"), "добил ренжем — «Позорище» (%s)" % [lines])
	# Лимит 12 с
	lines.clear()
	var d2 := _dummy(_floor_pos() + Vector3(-2, 0, -4), 5.0)
	p.deal_damage(d2, 50.0, Vector3.ZERO, "ranged")
	await wait(0.1)
	check(lines.is_empty(), "сразу второй раз — молчит (лимит 12 с)")
	# Мульти-килл важнее «Позорища»
	Odin.reset_cooldown()
	lines.clear()
	for i in 3:
		var dd := _dummy(_floor_pos() + Vector3(-3 + i * 1.5, 0, -6), 5.0)
		p.deal_damage(dd, 50.0, Vector3.ZERO, "ranged" if i == 2 else "melee")
	await wait(0.1)
	check(said("multikill"), "3 убийства разом — «Хоть что-то» (%s)" % [lines])
	# «Скуф…» — много урона
	Odin.reset_cooldown()
	lines.clear()
	p.heal(999)
	p.take_damage(p.max_health * 0.4, Vector3.ZERO, true)
	await wait(0.1)
	check(said("big_damage"), "много урона — «Скуф…» (%s)" % [lines])
	p.heal(999)
	# «ДВИГАЙСЯ!» — 4 с без движения при живых врагах
	Odin.reset_cooldown()
	lines.clear()
	var idle_enemy := _dummy(_floor_pos() + Vector3(5, 0, -8))
	p.global_position = _floor_pos()
	p.velocity = Vector3.ZERO
	await wait(4.5)
	check(said("idle"), "4 с стоит столбом — «ДВИГАЙСЯ!» (%s)" % [lines])
	idle_enemy.queue_free()
	# «Вот! ВОТ!» — удар-приземление с высоты
	Odin.reset_cooldown()
	lines.clear()
	p.global_position = _floor_pos() + Vector3(0, p.big_slam_height + 2.0, 0)
	p.velocity = Vector3.ZERO
	await wait(0.05)
	await press("slam")
	for i in 120:
		await get_tree().physics_frame
		if p.is_on_floor() and not p.is_slamming:
			break
	await wait(0.1)
	check(said("big_slam"), "удар-приземление с %.0f м — «Вот! ВОТ!» (%s)" % [p.big_slam_height + 2.0, lines])

func _finish() -> void:
	print("=== ИТОГ STYLE: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
