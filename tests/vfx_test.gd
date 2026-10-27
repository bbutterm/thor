extends Node
## VFX-комплект (sprites/vfx/*): каждый эффект создаётся, берёт общий материал (не новый), пулы не растут
## сверх лимита, анимации доходят до конца и освобождают узлы; экранные эффекты (линии скорости, Ярость,
## идеальный хват) и «взрыв» под комиксовым словом.
## godot --headless --path . --fixed-fps 60 res://tests/vfx_test.tscn

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

func dummy(scene: String, dist: float, side: float = 0.0) -> Enemy:
	var e := (load(scene) as PackedScene).instantiate() as Enemy
	e.max_health = 5000.0
	game.add_child(e)
	var p := game.player
	var f := p.get_aim_forward()
	f.y = 0
	f = f.normalized()
	e.global_position = p.global_position + f * dist + f.cross(Vector3.UP) * side
	e.health = 5000.0
	e.set_physics_process(false)
	return e

## Все узлы пула используют общий материал своей текстуры
func shared_ok(kind: String) -> bool:
	var mats := FX.sprite_materials()
	for n in FX.pool_nodes(kind):
		var mi := n as MeshInstance3D
		if mi.visible and not mats.has(mi.material_override):
			return false
	return true

func ahead(d: float, h: float = 1.0) -> Vector3:
	var p := game.player
	var f := p.get_aim_forward()
	f.y = 0
	return p.global_position + f.normalized() * d + Vector3(0, h, 0)

func _run() -> void:
	print("=== VFX TEST ===")
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.3)
	game = get_tree().current_scene as Game
	game.room.set_physics_process(false)
	await wait(0.8)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	game.room._spawn_queue.clear()
	var p := game.player
	await wait(0.3)
	var c := FX.cfg()

	print("-- Материалы и прогрев")
	var keys := FX.sprite_keys()
	check(keys.size() == 3 + 12 + 4 + 3 + 3 + 5 + 5 + FX.EXTRA_SPRITES.size(), "ключей текстур: %d (с декалями мира)" % keys.size())
	check(FX.sprite_materials().size() == keys.size(), "ShaderWarmup создал материал на каждую текстуру (%d)" % FX.sprite_materials().size())
	var no_tex := 0
	for k in keys:
		if FX.sprite_material(k).get_shader_parameter("tex") == null:
			no_tex += 1
	check(no_tex == 0, "у каждого материала есть текстура sprites/vfx/vfx_<ключ>.webp")
	check(FX.sprite_material("hit_flash").get_shader_parameter("grid") == Vector2(6, 1) and FX.sprite_material("smoke").get_shader_parameter("grid") == Vector2(8, 1), "полосы: вспышка 6 кадров, дым 8")
	check(FX.sprite_material("sparks_03") == FX.sprite_material("sparks_03"), "материал текстуры — один и тот же объект")
	var mats0 := FX.materials_created
	check(AssetCache.paths().has("res://sprites/vfx/vfx_hit_flash.webp"), "AssetCache держит текстуры sprites/vfx/")

	print("-- Вспышка попадания")
	FX.hit_flash(game, ahead(3.0), 1.0)
	await get_tree().physics_frame
	check(FX.pool_active("hit_flash") >= 1, "вспышка появилась")
	check(shared_ok("hit_flash"), "вспышка — общий материал")
	var fl := FX.pool_nodes("hit_flash")[0] as MeshInstance3D
	await wait(c.hit_flash_time + 0.15)
	check(FX.pool_active("hit_flash") == 0, "вспышка доиграла и вернулась в пул")
	check(FX.sprite_frame(fl) >= 5.0, "дошла до последнего кадра (%.2f)" % FX.sprite_frame(fl))
	for i in 60:
		FX.hit_flash(game, ahead(3.0), 1.0)
	check(FX.pool_size("hit_flash") <= c.hit_flash_limit, "пул вспышек не больше %d (%d)" % [c.hit_flash_limit, FX.pool_size("hit_flash")])

	print("-- Искры-звёзды")
	await wait(0.4)
	var s0 := FX.pool_active("sparks")
	FX.sparks(game, ahead(3.0), Color(1, 0.85, 0.4), 18, 6.0)
	check(FX.pool_active("sparks") > s0, "яркие искры дают звёзды")
	await wait(c.spark_time + 0.2)
	FX.sparks(game, ahead(3.0), Color(0.55, 0.47, 0.4), 26, 7.0, 18.0, 0.14, 0.7)
	check(FX.pool_active("sparks") == 0, "пыль удара-приземления звёзд не даёт, прошлые погасли")
	for i in 40:
		FX.sparks(game, ahead(3.0), Color(1, 1, 1), 18, 6.0)
	check(FX.pool_size("sparks") <= c.sparks_limit and shared_ok("sparks"), "пул звёзд не больше %d" % c.sparks_limit)

	print("-- Ихор нежити")
	await wait(0.5)
	var g := dummy("res://enemies/grunt.tscn", 3.5)
	var merc := dummy("res://enemies/merc.tscn", 3.5, 2.0)
	await wait(0.1)
	check(FX.is_undead(g) and not FX.is_undead(merc), "драугр — нежить, наёмник Локи — нет")
	var splats0 := FX.pool_active("splat")
	g.take_hit(10.0, Vector3.ZERO, "melee_finisher")
	await get_tree().physics_frame
	check(FX.pool_active("ichor_splash") >= 1, "удар по драугру — брызги ихора")
	check(FX.pool_active("splat") > splats0, "крупный удар — пятно на полу")
	check(shared_ok("ichor_splash") and shared_ok("splat"), "ихор — общие материалы")
	var sp := FX.pool_nodes("splat")[0] as MeshInstance3D
	check(absf(sp.global_position.y - (Loot.floor_point(g, g.global_position).y + c.decal_lift)) < 0.1, "пятно лежит на полу")
	await wait(c.ichor_splash_time + 0.2)
	var hf0 := FX.pool_active("hit_flash")
	merc.take_hit(10.0, Vector3.ZERO, "melee")
	await get_tree().physics_frame
	check(FX.pool_active("ichor_splash") == 0, "по наёмнику — без ихора")
	check(FX.pool_active("hit_flash") > hf0, "по наёмнику — вспышка есть")
	var before_fire := FX.pool_active("hit_flash")
	g.take_hit(5.0, Vector3.ZERO, "fire")
	check(FX.pool_active("hit_flash") == before_fire, "огонь не даёт вспышек (тикает 4 раза в секунду)")
	var old_life := c.splat_life
	var old_fade := c.splat_fade
	c.splat_life = 0.6
	c.splat_fade = 0.2
	for i in 80:
		FX.splat(game, g.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), 1.0)
	check(FX.pool_size("splat") == c.splat_limit, "пул пятен = лимиту %d (самое старое уходит)" % c.splat_limit)
	await wait(0.9)
	check(FX.pool_active("splat") == 0, "пятна исчезли по времени")
	c.splat_life = old_life
	c.splat_fade = old_fade
	g.health = 1.0
	g.take_hit(50.0, Vector3.ZERO, "melee")
	await get_tree().physics_frame
	check(FX.pool_active("splat") >= 1, "смерть драугра — пятно ихора")
	merc.queue_free()

	print("-- Дым")
	await wait(0.6)
	Blast.detonate(game, ahead(6.0, 0.8), 3.0, 0.0)
	await get_tree().physics_frame
	check(FX.pool_active("smoke") >= 1 and shared_ok("smoke"), "взрыв — дым (общий материал)")
	await wait(c.smoke_time + 0.2)
	check(FX.pool_active("smoke") == 0, "дым доиграл 8 кадров и исчез")
	for i in 40:
		FX.smoke(game, ahead(4.0), 1.0)
	check(FX.pool_size("smoke") <= c.smoke_limit, "пул дыма не больше %d" % c.smoke_limit)

	print("-- Бочка и серебро")
	await wait(c.smoke_time + 0.2)
	var barrel := (load("res://props/barrel.tscn") as PackedScene).instantiate() as RigidBody3D
	game.add_child(barrel)
	barrel.global_position = ahead(4.0, 0.3)
	await get_tree().physics_frame
	var star0 := FX.pool_active("sparks")
	BarrelWatch.break_barrel(barrel)
	await get_tree().physics_frame
	check(FX.pool_active("smoke") >= 1, "разбитая бочка — облако пыли")
	check(FX.pool_active("sparks") > star0, "монеты из бочки — блеск-звёздочка")

	print("-- Огонь")
	var fire := preload("res://weapons/fire_zone.gd").new()
	game.add_child(fire)
	fire.setup(ahead(4.0, 0.0), 2.0, 0.8, 0.0, false)
	var flames := fire.find_children("*", "MeshInstance3D", false, false).filter(func(n: Node) -> bool: return (n as MeshInstance3D).material_override == FX.sprite_material("fire"))
	var expect := clampi(int(ceil(2.0 * c.fire_per_meter)), 1, c.fire_max)
	check(flames.size() == expect, "зона огня r=2: языков пламени %d (ждали %d), общий материал" % [flames.size(), expect])
	check(((flames[0] as MeshInstance3D).get_meta("sp") as Vector4).w > 0.0 if not flames.is_empty() else false, "огонь — петля кадров в шейдере")
	await wait(1.0)
	check(not is_instance_valid(fire), "зона огня с пламенем исчезла по времени")

	print("-- Молния")
	await wait(0.4)
	var a := ahead(2.0, 1.0)
	var b := ahead(12.0, 1.0)
	FX.lightning(game, a, b, 0.25)
	var segs := int(ceil(a.distance_to(b) / c.lightning_segment))
	check(FX.pool_active("lightning") == segs, "молния 10 м — %d текстурных отрезков" % segs)
	check(shared_ok("lightning"), "молния — общие материалы")
	await wait(0.4)
	check(FX.pool_active("lightning") == 0, "молния погасла")
	for i in 30:
		FX.lightning(game, a, b + Vector3(0, 10, 0), 0.25)
	check(FX.pool_size("lightning") <= c.lightning_limit, "пул молний не больше %d" % c.lightning_limit)

	print("-- Удар-приземление")
	await wait(0.4)
	var cracks := {}
	for h in [1.0, 6.0, 12.0]:
		FX.slam_impact(game, ahead(3.0, 0.0), 4.0, h)
		await get_tree().physics_frame
		var newest: MeshInstance3D = null
		for n in FX.pool_nodes("crack"):
			if newest == null or int(n.get_meta("t", 0)) > int(newest.get_meta("t", 0)):
				newest = n
		cracks[h] = String(newest.get_meta("crack", "")) if newest else ""
	check(cracks[1.0] == "crack_decal_small" and cracks[6.0] == "crack_decal_medium" and cracks[12.0] == "crack_decal_large", "трещина по высоте: %s" % str(cracks))
	check(FX.pool_active("shockwave") >= 1 and shared_ok("shockwave") and shared_ok("crack"), "ударная волна и трещины — общие материалы")
	var wave := FX.pool_nodes("shockwave")[0] as MeshInstance3D
	var s_start := wave.basis.get_scale().x
	await wait(c.shockwave_time * 0.6)
	check(wave.basis.get_scale().x > s_start * 2.0, "волна растёт")
	await wait(c.shockwave_time)
	check(FX.pool_active("shockwave") == 0, "волна погасла")
	check(FX.pool_size("crack") <= c.crack_limit, "пул трещин не больше %d" % c.crack_limit)
	var crack_before := FX.pool_nodes("crack").size()
	p.global_position = p.global_position
	p._do_slam_impact(12.0)
	await get_tree().physics_frame
	check(FX.pool_active("crack") >= 1 and FX.pool_nodes("crack").size() >= crack_before, "настоящий удар-приземление Тора оставил трещину")

	print("-- Лёд")
	FX.ice_hit(game, p.global_position, 0.6)
	await wait(0.2)
	check(FX.pool_active("ice_patch") == 1, "наледь под Тором")
	check(FX.pool_active("ice_shard") == c.ice_shards and shared_ok("ice_shard"), "кристаллов льда: %d" % FX.pool_active("ice_shard"))
	await wait(1.0)
	check(FX.pool_active("ice_patch") == 0 and FX.pool_active("ice_shard") == 0, "лёд растаял")
	var ice := dummy("res://enemies/grunt.tscn", 2.0)
	Loot.make_elite(ice, load("res://enemies/elite/mods/ice.tres") as EliteModifier)
	await wait(0.1)
	ice.player = p
	var handled := false
	for h in ice.elite_handlers:
		if h.has_method("on_struck_player"):
			h.call("on_struck_player", 5.0)
			handled = true
	await get_tree().physics_frame
	check(handled and FX.pool_active("ice_shard") >= 1, "удар ледяной элиты — кристаллы")
	ice.queue_free()

	print("-- Экран: идеальный хват, Ярость, линии скорости")
	var vs := VfxScreen.instance
	check(vs != null and is_instance_valid(vs) and vs.get_parent() == game, "VfxScreen подключён к игре")
	check(not (game.hud.get("_speed_rect") as CanvasItem).visible, "процедурные линии HUD спрятаны (рисованные вместо)")
	p.mjolnir._grant_perfect()
	await get_tree().process_frame
	check(vs.catch_active() == 1, "идеальный хват — золотое кольцо")
	for i in 5:
		FX.perfect_catch(p.global_position + p.get_aim_forward() * 2.0)
	check(vs.catch_active() <= vs.catch_limit, "колец не больше %d" % vs.catch_limit)
	await wait(vs.catch_time + 0.2)
	check(vs.catch_active() == 0, "кольцо погасло")
	p.rage.start_berserk()
	await wait(0.6)
	check(vs.rage_rect.visible and vs.rage_rect.modulate.a > 0.3, "берсерк — виньетка Ярости (%.2f)" % vs.rage_rect.modulate.a)
	p.rage.reset()
	await wait(1.6)
	check(not vs.rage_rect.visible, "после берсерка виньетка ушла")
	for i in p.rage.kills_to_full - 2:
		p.rage.add_kill()
	await wait(0.5)
	check(vs.rage_target() > 0.0, "почти полная шкала — слабое мерцание по краям")
	p.rage.reset()
	p.camera_fx.speed_lines_pulse()
	await wait(0.1)
	check(vs.speed_rect.visible and vs.speed_rect.modulate.a > 0.1, "рывок — линии скорости")
	await wait(1.2)
	check(not vs.speed_rect.visible, "линии скорости погасли")
	p.velocity.y = 30.0
	check(vs.speed_target() > 0.9, "супер-прыжок / падение (|v.y| 30) — линии на полную")
	p.velocity = Vector3.ZERO

	print("-- Комиксовое слово на рисованном «взрыве»")
	ComicFX.reset_state()
	GameSettings.comic_enabled = true
	ComicFX.pop("lightning", ahead(3.0, 1.5), false)
	await get_tree().process_frame
	await get_tree().process_frame
	var word: Variant = null
	for w in ComicFX._pool:
		if w.active:
			word = w
	check(word != null and word.sprite.visible and ComicFX._kit_bursts.has(word.sprite.texture), "слово — на случайном comic_burst_0N")
	check(word != null and word.sprite.material == ComicFX._kit_mat, "«взрыв» — общий материал перекраски")
	check(word != null and word.sprite.modulate.is_equal_approx(Color.from_string("#1b8cff", Color.WHITE)), "цвет «взрыва» — по событию (молния — голубой)")
	var used := {}
	for i in 12:
		ComicFX.reset_state()
		ComicFX.pop("slam", ahead(3.0, 1.5), true)
		await get_tree().process_frame
		await get_tree().process_frame
		for w in ComicFX._pool:
			if w.active:
				used[w.sprite.texture] = true
	check(used.size() >= 3, "«взрывы» разные (%d из 6 за 12 слов)" % used.size())
	ComicFX.reset_state()

	print("-- Итог по материалам")
	check(FX.materials_created == mats0, "в бою не создано ни одного нового материала эффектов (%d → %d)" % [mats0, FX.materials_created])
	var holder := FX._holder
	check(holder != null and holder.has_meta("transient") and holder.top_level, "пулы — в узле верхнего уровня с меткой transient (чистится при смене зала)")
	_finish()

func _finish() -> void:
	print("=== ИТОГ VFX: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
