extends Node
## Разрушаемое (props/destructible.gd, props/prop_debris.gd): каждый источник урона ломает бочку и ящик,
## обломки ≤ лимита и исчезают, материалы общие, серебро/патроны/лечение, взрывная бочка и цепная реакция,
## мост деревни ломается ударом-приземлением и цел при новом заходе, балконы Ярла целы, Ярость/руны не растут.
## godot --headless --path . --fixed-fps 60 res://tests/destructible_test.tscn

const BARREL := "res://props/barrel.tscn"
const CRATE := "res://props/crate.tscn"
const BOOM := "res://props/barrel_explosive.tscn"

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

## Ждать; Тор всё это время бессмертен.
func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().physics_frame
		if game and is_instance_valid(game) and game.player:
			game.player.health = game.player.max_health

func wait_until(cond: Callable, timeout: float) -> bool:
	for i in int(ceil(timeout * 60.0)):
		if cond.call():
			return true
		await get_tree().physics_frame
		if game and is_instance_valid(game) and game.player:
			game.player.health = game.player.max_health
	return cond.call()

func _start(order: Array) -> void:
	Run.start_run("berserker")
	Run.room_order.assign(order)
	Run.room_index = 0
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.6)
	game = get_tree().current_scene as Game
	game.room.set_physics_process(false)
	await wait(0.6)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	await wait(0.1)

func spawn(path: String, pos: Vector3, frozen: bool = false) -> Destructible:
	var d := (load(path) as PackedScene).instantiate() as Destructible
	if frozen:
		d.freeze = true
	game.room.add_child(d)
	d.global_position = pos
	return d

func broken(d: Variant) -> bool:
	return not is_instance_valid(d) or (d as Destructible).is_broken or (d as Node).is_queued_for_deletion()

func fwd() -> Vector3:
	var f := game.player.get_aim_forward()
	f.y = 0.0
	return f.normalized()

func eye() -> Vector3:
	return game.player.get_aim_origin()

## Тор в точке pos, смотрит вдоль -Z (без наклона), стоит.
func place(pos: Vector3) -> void:
	var p := game.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2(0, 0)
	await wait(0.25)

func clear_props() -> void:
	for n in get_tree().get_nodes_in_group("props"):
		(n as Node).queue_free()
	PropDebris.clear_all()
	await wait(0.1)

func _run() -> void:
	print("=== DESTRUCTIBLE TEST ===")
	Destructible.surprise_chance_override = 0.0
	await _start(["res://rooms/room_09.tscn", Run.BOSS_SCENE])
	await clear_props()
	_test_data()
	await _test_melee()
	await _test_hammer()
	await _test_ranged()
	await _test_slam()
	await _test_dash()
	await _test_explosions()
	await _test_fire()
	await _test_speed()
	await _test_comic()
	await _test_enemies()
	await _test_loot()
	await _test_explosive()
	await _test_rage()
	await _test_debris()
	await _test_surprise()
	await _test_bridge()
	await _test_jarl()
	Destructible.surprise_chance_override = -1.0
	_finish()

func _finish() -> void:
	print("=== ИТОГ DESTRUCTIBLE: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("  FAIL: ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)

# --- Данные ---

func _test_data() -> void:
	print("-- Сцены пропсов")
	var hp := {BARREL: 15.0, CRATE: 30.0, BOOM: 10.0}
	for path in hp:
		var d := (load(path) as PackedScene).instantiate() as Destructible
		check(d != null and is_equal_approx(d.max_health, hp[path]) and d.is_in_group("props") and d.collision_layer == 1 << 3,
			"%s — Destructible, HP %.0f, группа props, слой 4" % [path.get_file(), hp[path]])
		if d:
			check(d.explosive == (path == BOOM), "%s: взрывная = %s" % [path.get_file(), path == BOOM])
			d.free()

# --- Источники урона Тора ---

func _test_melee() -> void:
	print("-- Мили")
	var p := game.player
	p.equip(Loot.get_def("axe"))
	p.weapons.switch_to(WeaponHolder.MELEE, true)
	await place(Vector3(0, 0.1, 9))
	print("    (топор: урон обычного удара %.1f)" % p.axe._stage_damage())
	var b := spawn(BARREL, p.global_position + fwd() * 1.4 + Vector3(0, -0.08, 0))
	await wait(0.3)
	p.axe.request_attack()
	await wait(0.5)
	check(broken(b), "бочка — с одного удара топором")
	await wait(0.4)
	var c := spawn(CRATE, p.global_position + fwd() * 1.4 + Vector3(0, -0.08, 0))
	await wait(0.3)
	p.axe.request_attack()
	await wait(0.35)
	check(not broken(c) and c.health < c.max_health, "ящик после обычного удара цел (HP %.0f/%.0f)" % [c.health if is_instance_valid(c) else 0.0, 30.0])
	check(p.axe._enemies_hit == 0, "удар по пропсу не тратит цели оружия")
	if is_instance_valid(c):
		c.queue_free()
	await wait(0.6)
	var c2 := spawn(CRATE, p.global_position + fwd() * 1.4 + Vector3(0, -0.08, 0))
	await wait(0.3)
	p.axe.request_heavy()
	await wait(1.0)
	check(broken(c2), "ящик — сильным ударом")

func _test_hammer() -> void:
	print("-- Мьёльнир: бросок и возврат")
	var p := game.player
	await place(Vector3(0, 0.1, 9))
	var b := spawn(BARREL, eye() + fwd() * 6.0 - Vector3(0, 0.5, 0), true)
	p.mjolnir.request_throw_or_recall()
	await wait(0.6)
	check(broken(b), "бросок молота разбил бочку")
	await wait_until(func() -> bool: return p.mjolnir.projectile == null or p.mjolnir.projectile.state != MjolnirProjectile.State.OUT, 2.0)
	var c := spawn(CRATE, eye() + fwd() * 3.0 - Vector3(0, 0.45, 0), true)
	p.mjolnir.request_throw_or_recall()
	var back := await wait_until(func() -> bool: return p.mjolnir.in_hand, 4.0)
	check(back and broken(c), "возврат молота разбил ящик")
	await wait(0.3)

func _test_ranged() -> void:
	print("-- Ренж")
	var p := game.player
	await place(Vector3(0, 0.1, 9))
	p.equip(Loot.get_def("pistol"))
	p.weapons.switch_to(WeaponHolder.RANGED, true)
	await wait(0.3)
	var gun := p.weapons.gun
	for path in [BARREL, CRATE]:
		var d := spawn(path, eye() + fwd() * 5.0 - Vector3(0, 0.45, 0), true)
		for i in 4:
			if broken(d):
				break
			gun._cooldown = 0.0
			gun.item.mag = maxi(gun.item.mag, 3)
			gun.try_fire()
			await wait(0.1)
		check(broken(d), "пистолет разбил %s за 2–4 выстрела" % path.get_file())
	p.weapons.switch_to(WeaponHolder.MELEE, true)
	await wait(0.3)

func _test_slam() -> void:
	print("-- Удар-приземление")
	var p := game.player
	await place(Vector3(0, 0.1, 9))
	var at := p.global_position
	var b := spawn(BARREL, at + Vector3(1.6, -0.08, 0))
	var c := spawn(CRATE, at + Vector3(-2.0, -0.08, 0.5))
	await wait(0.3)
	p.global_position = at + Vector3(0, 3.0, 0)
	p.velocity = Vector3.ZERO
	await get_tree().physics_frame
	p._start_slam()
	await wait_until(func() -> bool: return p.is_on_floor() and not p.is_slamming, 2.0)
	await wait(0.1)
	check(broken(b) and broken(c), "удар-приземление разбил бочку и ящик в радиусе")
	await wait(0.6)

func _test_dash() -> void:
	print("-- Рывок и таран")
	var p := game.player
	for ram in [false, true]:
		await place(Vector3(0, 0.1, 9))
		p.dash_ram = ram
		p.dash_charges = p.dash_charges_max
		var c := spawn(CRATE, p.global_position + fwd() * 2.2 + Vector3(0, -0.08, 0))
		await wait(0.3)
		p._start_dash(fwd())
		await wait(0.4)
		check(broken(c), "%s разбил ящик" % ("таран" if ram else "рывок"))
		if ram:
			p._end_ram()
		p.dash_ram = false
	await wait(0.3)

func _test_explosions() -> void:
	print("-- Взрывы")
	var p := game.player
	await place(Vector3(0, 0.1, 12))
	var at := Vector3(0, 0.0, 4)
	var b := spawn(BARREL, at + Vector3(1.0, 0, 0))
	var c := spawn(CRATE, at + Vector3(-1.2, 0, 0))
	await wait(0.3)
	Blast.detonate(game.room, at + Vector3(0, 0.8, 0), 3.0, 44.0)
	await wait(0.1)
	check(broken(b) and broken(c), "взрыв Раздутого (Blast) разбил бочку и ящик")
	var b2 := spawn(BARREL, at + Vector3(0.8, 0, 0))
	var c2 := spawn(CRATE, at + Vector3(-1.0, 0, 0))
	await wait(0.3)
	var rk := Rocket.new()
	game.add_child(rk)
	rk.player = p
	rk.explode(at + Vector3(0, 0.5, 0))
	await wait(0.1)
	check(broken(b2) and broken(c2), "ракета разбила бочку и ящик")
	await wait(0.3)

func _test_fire() -> void:
	print("-- Огонь")
	await place(Vector3(0, 0.1, 12))
	var at := Vector3(0, 0.0, 4)
	var b := spawn(BARREL, at + Vector3(0.6, 0, 0))
	var c := spawn(CRATE, at + Vector3(-0.8, 0, 0))
	await wait(0.3)
	var fire := preload("res://weapons/fire_zone.gd").new()
	game.add_child(fire)
	fire.setup(at, 2.0, 1.0, 0.0, false)
	await wait(0.4)
	check(is_instance_valid(b) and b.burning and is_instance_valid(c) and c.burning, "в огне бочка и ящик загорелись")
	var burn := b.burn_time
	await wait(burn + 0.5)
	check(broken(b) and broken(c), "сгорели и развалились через %.1f с" % burn)

func _test_speed() -> void:
	print("-- Скорость (удар о стену, падение)")
	await place(Vector3(0, 0.1, 12))
	var b := spawn(BARREL, Vector3(0, 0.0, 4))
	var c := spawn(CRATE, Vector3(2, 0.0, 4))
	await wait(0.3)
	b.linear_velocity = Vector3(1, 0, 0)
	await wait(0.2)
	check(not broken(b), "медленная бочка цела")
	b.linear_velocity = Vector3(14, 3, 0)
	c.linear_velocity = Vector3(-14, 3, 0)
	await wait(0.1)
	check(broken(b) and broken(c), "отброшенные быстрее %.0f м/с бочка и ящик разбились" % Silver.cfg().barrel_break_speed)

func _test_comic() -> void:
	print("-- Слово комикса: только сильный удар")
	var cf := get_tree().root.get_node("ComicFX")
	var saved: bool = GameSettings.comic_enabled
	GameSettings.comic_enabled = true
	await place(Vector3(0, 0.1, 12))
	var b := spawn(BARREL, Vector3(0, 0, 8))
	var c := spawn(CRATE, Vector3(1.5, 0, 8))
	await wait(0.3)
	FX.reset_time()
	cf.reset_state()
	await get_tree().process_frame
	b.take_hit(99.0, Vector3.ZERO, "melee")
	await wait(0.2)
	var evs: Array = cf.history.map(func(h: Dictionary) -> String: return String(h.event))
	check(not "smash" in evs, "обычный удар разбил бочку — без слова (%s)" % [evs])
	await wait(0.8)
	cf.reset_state()
	c.take_hit(99.0, Vector3.ZERO, "melee_heavy")
	await wait(0.2)
	evs = cf.history.map(func(h: Dictionary) -> String: return String(h.event))
	check("smash" in evs, "сильный удар разбил ящик — KRAK!/SMASH! (%s)" % [evs])
	GameSettings.comic_enabled = saved
	FX.reset_time()

# --- Враги ---

func _test_enemies() -> void:
	print("-- Враги: удар по площади и таран ломают, ходьба — нет")
	var p := game.player
	await place(Vector3(0, 0.1, 12))
	var boss := (load("res://enemies/boss.tscn") as PackedScene).instantiate() as Enemy
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	game.room.add_child(boss)
	boss.remove_from_group("enemies")
	boss.global_position = Vector3(0, 0.05, 2)
	var b := spawn(BARREL, Vector3(1.5, 0, 2))
	var c := spawn(CRATE, Vector3(-1.5, 0, 2.5))
	await wait(0.3)
	boss._do_boss_slam()
	await wait(0.1)
	check(broken(b) and broken(c), "удар босса по площади разбил бочку и ящик")
	boss.queue_free()
	# Таран Свена
	var sven := (load("res://enemies/sven.tscn") as PackedScene).instantiate() as BossEnemy
	game.room.add_child(sven)
	sven.set_physics_process(false)
	sven.set_process(false)
	sven.remove_from_group("enemies")
	sven.global_position = Vector3(0, 0.05, 6)
	var b2 := spawn(BARREL, Vector3(0, 0, 2.5))
	var c2 := spawn(CRATE, Vector3(0.4, 0, 0.5))
	await wait(0.3)
	sven.charge_begin(Vector3(0, 0, -1))
	for i in 50:
		await get_tree().physics_frame
		if sven.charge_step(1.0 / 60.0, 12.0, 9.0, 0.0, 0.0) != 0:
			break
	check(broken(b2) and broken(c2), "таран Свена разбил бочку и ящик на пути")
	sven.queue_free()
	# Обычный враг идёт к Тору сквозь бочку — толкает, но не ломает
	await place(Vector3(0, 0.1, 12))
	var b3 := spawn(BARREL, Vector3(0, 0, 9))
	var e := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	game.room.add_child(e)
	e.global_position = Vector3(0, 0.05, 5)
	e.max_health = 9999.0
	e.health = 9999.0
	await wait(3.0)
	check(not broken(b3), "ходьба врага бочку не ломает")
	e.queue_free()
	if is_instance_valid(b3):
		b3.queue_free()
	await wait(0.2)

# --- Содержимое ---

func _coins() -> int:
	return get_tree().get_nodes_in_group("silver_coins").size()

func _test_loot() -> void:
	print("-- Содержимое: серебро, патроны, лечение")
	var p := game.player
	await place(Vector3(0, 0.1, 12))
	await wait_until(func() -> bool: return _coins() == 0, 4.0)
	var s0 := Run.silver
	var b := spawn(BARREL, Vector3(0, 0, 9))
	await wait(0.2)
	b.take_hit(50.0, Vector3.ZERO, "melee")
	await wait(0.1)
	check(_coins() > 0, "из бочки высыпались монеты (%d)" % _coins())
	await wait(3.0)
	var got := Run.silver - s0
	check(got >= Silver.cfg().barrel_silver_min and got <= Silver.cfg().barrel_silver_max, "из бочки %d серебра (3–8)" % got)
	# Ящик: по очереди только серебро / только патроны / только лечение
	var cfg := Silver.cfg()
	var saved := [cfg.crate_silver_chance, cfg.crate_ammo_chance, cfg.crate_heal_chance]
	p.equip(Loot.get_def("pistol"))
	cfg.crate_silver_chance = 0.0
	cfg.crate_ammo_chance = 1.0
	cfg.crate_heal_chance = 0.0
	var ammo0 := get_tree().get_nodes_in_group("ammo_pickups").size()
	var c := spawn(CRATE, Vector3(3, 0, 6))
	await wait(0.2)
	c.take_hit(50.0, Vector3.ZERO, "melee")
	await wait(0.1)
	check(get_tree().get_nodes_in_group("ammo_pickups").size() > ammo0, "ящик (шанс патронов 100 %) — ящик патронов")
	cfg.crate_ammo_chance = 0.0
	cfg.crate_heal_chance = 1.0
	var c2 := spawn(CRATE, Vector3(0, 0, 9))
	await wait(0.2)
	p.health = p.max_health - 30.0
	var hp0 := p.health
	c2.take_hit(50.0, Vector3.ZERO, "melee")
	await get_tree().physics_frame
	check(get_tree().get_nodes_in_group("heal_orbs").size() > 0, "ящик (шанс лечения 100 %) — шар лечения")
	var healed := false
	for i in 240:
		await get_tree().physics_frame
		if p.health > hp0 + 1.0:
			healed = true
			break
	check(healed, "шар лечения долетел и вылечил (+%.0f)" % (p.health - hp0))
	cfg.crate_silver_chance = saved[0]
	cfg.crate_ammo_chance = saved[1]
	cfg.crate_heal_chance = saved[2]
	for n in get_tree().get_nodes_in_group("ammo_pickups"):
		(n as Node).queue_free()
	await wait(0.2)

# --- Взрывная бочка ---

func _test_explosive() -> void:
	print("-- Взрывная бочка и цепная реакция")
	var p := game.player
	await place(Vector3(0, 0.1, 13))
	var at := Vector3(0, 0, 2)
	var e1 := spawn(BOOM, at)
	var e2 := spawn(BOOM, at + Vector3(2.6, 0, 0))
	var b := spawn(BARREL, at + Vector3(-1.4, 0, 0))
	var dummy := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	game.room.add_child(dummy)
	dummy.global_position = at + Vector3(0, 0.05, 1.5)
	dummy.max_health = 9999.0
	dummy.health = 9999.0
	dummy.set_physics_process(false)
	await wait(0.3)
	var hp_p := p.health
	e1.take_hit(20.0, Vector3.ZERO, "ranged")
	await get_tree().physics_frame
	check(broken(e1), "выстрел — взрыв сразу")
	check(dummy.health < dummy.max_health, "взрыв ранил врага рядом (−%.0f)" % (dummy.max_health - dummy.health))
	check(broken(b), "взрыв разбил обычную бочку рядом")
	check(is_instance_valid(e2) and e2._fusing, "соседняя взрывная бочка — фитиль (цепная реакция)")
	check(p.health >= hp_p, "Тор далеко — не задет")
	var delay := e2.chain_delay if is_instance_valid(e2) else 0.0
	await wait(delay + 0.15)
	check(broken(e2), "соседняя взрывная бочка взорвалась через %.2f с" % delay)
	# Удар вплотную — фитиль, успеть отскочить
	var e3 := spawn(BOOM, at)
	await wait(0.3)
	e3.take_hit(30.0, Vector3.ZERO, "melee")
	await get_tree().physics_frame
	check(is_instance_valid(e3) and e3._fusing and not e3.is_broken, "удар топором — шипит фитиль %.1f с" % e3.melee_fuse)
	await wait(e3.melee_fuse + 0.15)
	check(broken(e3), "и взрывается")
	dummy.queue_free()
	await wait(0.3)

# --- Ярость, руны, убийства ---

func _test_rage() -> void:
	print("-- Удары по пропсам не кормят Ярость, руны и счёт убийств")
	var p := game.player
	await place(Vector3(0, 0.1, 9))
	Run.add_rune(Run.rune_def("thunder_call"))
	p.recalc_from_runes(Run)
	p._thunder_hits = 0
	var kills := [0]
	var cb := func(_s: String) -> void: kills[0] += 1
	Run.kill_registered.connect(cb)
	var g0 := Run.glory
	var rage0 := p.rage.kills
	var crates: Array[Destructible] = []
	for i in 4:
		crates.append(spawn(CRATE, Vector3(-3 + i * 2, 0, 3)))
	await wait(0.2)
	for k in 3:
		for c in crates:
			if is_instance_valid(c):
				p.deal_damage(c, 6.0, Vector3.ZERO, "melee")
	for c in crates:
		if is_instance_valid(c):
			p.deal_damage(c, 99.0, Vector3.ZERO, "melee_finisher")
	await wait(0.2)
	check(crates.all(func(c: Variant) -> bool: return broken(c)), "deal_damage ломает пропсы")
	check(p._thunder_hits == 0, "«Зов грома» не считает удары по пропсам (%d)" % p._thunder_hits)
	check(p.rage.kills == rage0 and not p.rage.active, "Ярость не растёт (%d → %d)" % [rage0, p.rage.kills])
	check(kills[0] == 0, "разбитые пропсы — не убийства (%d)" % kills[0])
	check(Run.glory == g0, "Славы за пропсы нет (%d → %d)" % [g0, Run.glory])
	# И настоящим взмахом топора
	p.weapons.switch_to(WeaponHolder.MELEE, true)
	var b := spawn(BARREL, p.global_position + fwd() * 1.4 + Vector3(0, -0.08, 0))
	await wait(0.3)
	p.axe.request_attack()
	await wait(0.5)
	check(broken(b) and p._thunder_hits == 0 and kills[0] == 0 and p.rage.kills == rage0,
		"взмах по бочке — тоже мимо Ярости и рун (разбита %s, гром %d, убийств %d, ярость %d)" % [broken(b), p._thunder_hits, kills[0], p.rage.kills])
	Run.kill_registered.disconnect(cb)
	Run.runes.clear()
	p.recalc_from_runes(Run)

# --- Обломки ---

func _piece_materials_ok(allowed: Dictionary) -> bool:
	for n in get_tree().get_nodes_in_group(PropDebris.GROUP):
		for mi in (n as Node).find_children("*", "MeshInstance3D", false, false):
			var m := (mi as MeshInstance3D).mesh
			if (mi as MeshInstance3D).material_override != null:
				return false
			for s in m.get_surface_count():
				if not allowed.has(m.surface_get_material(s)):
					return false
	return true

func _test_debris() -> void:
	print("-- Обломки: лимит, общие меши и материалы, исчезают")
	await place(Vector3(0, 0.1, 13))
	await clear_props()
	var t := PropDebris.cfg()
	# Материалы моделей пропсов — обломки должны носить только их
	var allowed := {}
	for path in [BARREL, CRATE, BOOM]:
		var d := (load(path) as PackedScene).instantiate() as Node3D
		for mi in d.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			for s in m.get_surface_count():
				allowed[(mi as MeshInstance3D).get_active_material(s)] = true
		d.free()
	var row: Array[Destructible] = []
	for i in 3:
		row.append(spawn(BARREL, Vector3(-4 + i * 4, 0, 4)))
		row.append(spawn(CRATE, Vector3(-4 + i * 4, 0, 1)))
	await wait(0.3)
	for d in row:
		d.smash(Vector3(0, 2, -6), "melee")
	await get_tree().physics_frame
	var first := PropDebris.live_count()
	check(first >= 6 * 4 and first <= t.debris_limit, "обломки: %d (4–8 на пропс, ≤ %d)" % [first, t.debris_limit])
	var meshes0 := PropDebris.cached_meshes().size()
	var mats0 := FX.materials_created
	check(_piece_materials_ok(allowed), "у обломков материалы моделей пропсов (новых нет, без material_override)")
	row.clear()
	for i in 10:
		row.append(spawn(BARREL if i % 2 == 0 else CRATE, Vector3(-9 + i * 2, 0, 2)))
	await wait(0.3)
	for d in row:
		d.smash(Vector3(0, 2, -6), "melee")
	await get_tree().physics_frame
	check(PropDebris.live_count() <= t.debris_limit, "обломков в зале не больше лимита: %d ≤ %d" % [PropDebris.live_count(), t.debris_limit])
	check(PropDebris.cached_meshes().size() == meshes0, "меши обломков общие — не растут (%d → %d)" % [meshes0, PropDebris.cached_meshes().size()])
	check(FX.materials_created == mats0, "материалы эффектов не растут (%d → %d)" % [mats0, FX.materials_created])
	check(_piece_materials_ok(allowed), "и после 10 разрушений — те же материалы")
	var layers_ok := get_tree().get_nodes_in_group(PropDebris.GROUP).all(func(n: Node) -> bool:
		return (n as RigidBody3D).collision_layer == 1 << 6 and not n.is_in_group("debris"))
	check(layers_ok, "обломки на слое 7 (debris), не в группе трупов debris")
	await wait(t.debris_life * 1.15 + t.debris_sink_time + 0.6)
	check(PropDebris.live_count() == 0 and get_tree().get_nodes_in_group(PropDebris.GROUP).is_empty(), "обломки провалились в пол и исчезли")

# --- Сюрпризы ---

func _test_surprise() -> void:
	print("-- Сюрприз: взрывные бочки в зале")
	Destructible.surprise_chance_override = 1.0
	game._load_room()
	await wait(0.5)
	var boom := 0
	var plain := 0
	for n in get_tree().get_nodes_in_group("destructibles"):
		var d := n as Destructible
		if d.scene_file_path == BOOM:
			boom += 1
		elif d.scene_file_path == BARREL:
			plain += 1
	check(boom >= 1 and boom <= Silver.cfg().explosive_barrel_max and plain >= 2, "в зале %d взрывных бочек (≤ %d), обычных осталось %d (≥ 2)" % [boom, Silver.cfg().explosive_barrel_max, plain])
	Destructible.surprise_chance_override = 0.0

# --- Мост деревни ---

func _deck(room: Node) -> Balcony:
	for n in room.find_children("*", "StaticBody3D", true, false):
		if n is Balcony and (n as Balcony).slam_breakable and not (n as Balcony).is_broken:
			return n
	return null

func _test_bridge() -> void:
	print("-- Мост деревни (room_09) и Биврёст (room_05)")
	for path in ["res://rooms/room_05.tscn", "res://rooms/room_09.tscn"]:
		var r := (load(path) as PackedScene).instantiate()
		check(_deck(r) != null, "%s: деревянный настил ломается ударом-приземлением" % path.get_file())
		r.free()
	game._load_room()
	await wait(0.5)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	var deck := _deck(game.room)
	check(deck != null, "в деревне мост целый")
	if deck == null:
		return
	var p := game.player
	var top := deck.top_point()
	p.global_position = top + Vector3(0, 3.5, 0)
	p.velocity = Vector3.ZERO
	await get_tree().physics_frame
	p._start_slam()
	await wait_until(func() -> bool: return not p.is_slamming, 2.0)
	await wait(deck.shake_time + 0.3 if is_instance_valid(deck) else 0.3)
	check(not is_instance_valid(deck) or deck.is_broken, "удар-приземление сломал мост")
	await wait(1.0)
	check(p.global_position.y < top.y - 0.5, "Тор провалился вниз (y %.1f)" % p.global_position.y)
	game._load_room()
	await wait(0.5)
	var again := _deck(game.room)
	check(again != null and not again.is_broken, "при новом заходе в зал мост снова целый")

# --- Длинный дом Ярла ---

func _test_jarl() -> void:
	print("-- Балконы Ярла: удар-приземление не ломает")
	await _start([Run.BOSS_SCENE])
	for e in game.room.alive_enemies().duplicate():
		e.process_mode = Node.PROCESS_MODE_DISABLED
	var bals := get_tree().get_nodes_in_group("balconies")
	check(bals.size() == 4 and bals.all(func(b: Node) -> bool: return not (b as Balcony).slam_breakable), "4 балкона, все не ломаются ударом-приземлением")
	if bals.is_empty():
		return
	var bc := bals[0] as Balcony
	var p := game.player
	p.global_position = bc.top_point() + Vector3(0, 4.0, 0)
	p.velocity = Vector3.ZERO
	await get_tree().physics_frame
	p._start_slam()
	await wait_until(func() -> bool: return not p.is_slamming, 2.0)
	await wait(1.0)
	check(is_instance_valid(bc) and not bc.is_broken, "балкон Ярла цел после удара-приземления")
	check(p.global_position.y > bc.top_point().y - 0.3, "Тор стоит на балконе (y %.1f)" % p.global_position.y)
