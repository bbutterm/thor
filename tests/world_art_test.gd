extends Node
## Графика мира (комплект владельца docs/world_art/, scripts/world_art.gd): небо мира из RunMap, рунные круги
## на прыжковых рунах и под дверьми-наградами, лужи браги и подпалины, декор на стенах залов и длинного дома,
## атмосферные частицы; общие материалы (не растут от зала к залу), без instance uniform у статичного декора,
## количество текущих instance-материалов на толпе (это не измерение занятых слотов GL).
## godot --headless --path . --fixed-fps 60 res://tests/world_art_test.tscn

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

func open(room: String) -> void:
	Run.start_run("berserker")
	Run.room_order.assign([room, Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.4)
	game = get_tree().current_scene as Game
	game.room.set_physics_process(false)
	await wait(0.8)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	game.room._spawn_queue.clear()
	await wait(0.2)

## Узел с материалом графики мира: StandardMaterial3D из общего кеша WorldArt, без instance uniform.
func world_mat_ok(gi: GeometryInstance3D) -> bool:
	return gi != null and gi.material_override is StandardMaterial3D and WorldArt.materials().has(gi.material_override) \
		and not FX._has_iu(gi.material_override)

func _run() -> void:
	print("=== WORLD ART TEST ===")
	await open("res://rooms/room_09.tscn")
	var map := Run.map

	print("-- Небо мира")
	check(map != null and map.sky == "res://assets/sky/midgard.webp", "у Мидгарда в run/maps/midgard.tres панорама неба")
	var we := game.get_node("WorldEnvironment") as WorldEnvironment
	var env := we.environment
	var psm := env.sky.sky_material as PanoramaSkyMaterial if env and env.sky else null
	check(psm != null and psm.panorama != null and psm.panorama.resource_path == map.sky, "небо зала — PanoramaSkyMaterial(midgard.webp)")
	check(is_equal_approx(env.fog_sky_affect, map.fog_sky_affect) and env.fog_sky_affect < 0.5, "дымка не закрывает небо (fog_sky_affect %.2f)" % env.fog_sky_affect)
	check(is_equal_approx(env.tonemap_exposure, map.exposure) and is_equal_approx(env.ambient_light_energy, map.ambient_energy), "экспозиция и рассеянный свет — из карты мира")
	var shared_env := load("res://scenes/game_environment.tres") as Environment
	check(env != shared_env and shared_env.sky.sky_material is ProceduralSkyMaterial, "общий game_environment.tres не тронут (процедурное небо для мира без панорамы)")
	var sky1 := env.sky
	var no_sky := RunMap.new()
	check(not WorldArt.apply_world(game, no_sky), "мир без панорамы — небо сцены не меняется")
	check(WorldArt.sky_for(map.sky, map.sky_energy) == sky1, "небо мира одно на файл (кешируется)")

	print("-- Атмосфера зала")
	var atm := game.room.get_node_or_null("Atmosphere")
	check(atm != null and atm.get_node_or_null("Dust") is CPUParticles3D, "пылинки в зале")
	check(atm != null and atm.get_node_or_null("GroundFog0") is CPUParticles3D, "низкий туман у земли")
	var torches := game.room.get_node("Torches").get_children()
	var with_embers := torches.filter(func(t: Node) -> bool: return t.get_node_or_null("Embers") is CPUParticles3D).size()
	check(with_embers == torches.size() and with_embers > 0, "искры над всеми факелами (%d)" % with_embers)
	var parts := get_tree().get_nodes_in_group("world_particles")
	check(not parts.is_empty() and parts.all(func(n: Node) -> bool: return world_mat_ok(n as GeometryInstance3D)), "частицы — общие материалы WorldArt без instance uniform (%d)" % parts.size())
	check(FX.instance_uniform_users(atm) == 0, "у атмосферы нет текущих instance-материалов")

	print("-- Декор и декали в зале")
	var decor := game.room.find_children("*", "WallDecor", true, false)
	check(decor.size() >= 10, "декор на стенах деревни (%d)" % decor.size())
	var arts := {}
	for n in decor:
		arts[(n as WallDecor).art] = true
	check(arts.has("wanted_poster") and arts.has("odin_poster"), "в деревне плакаты «Разыскивается» и Одина")
	check(arts.keys().any(func(a: String) -> bool: return a.begins_with("banner_")) and arts.keys().any(func(a: String) -> bool: return a.begins_with("shield_")), "знамёна и щиты")
	var quads_ok := decor.all(func(n: Node) -> bool: return world_mat_ok(n.get_node_or_null("Quad") as GeometryInstance3D))
	check(quads_ok, "у каждой картинки общий материал без instance uniform")
	check(FX.instance_uniform_users(game.room.get_node("Banners")) == 0, "у декора нет текущих instance-материалов")
	check(game.room.find_children("*", "StaticBody3D", true, false).filter(func(b: Node) -> bool: return b.get_parent() is WallDecor).is_empty(), "декор без коллизии")
	var pad := game.room.find_children("*", "JumpPad", true, false)
	var circle := (pad[0] as Node).get_node_or_null("Circle") as MeshInstance3D if not pad.is_empty() else null
	check(circle != null and world_mat_ok(circle) and circle.material_override == WorldArt.material("rune_circle_jump", "glow"), "прыжковая руна — рунный круг rune_circle_jump")
	var d6 := (load("res://rooms/room_06.tscn") as PackedScene).instantiate()
	var fd := d6.find_children("*", "FloorDecal", true, false)
	check(not fd.is_empty() and (fd[0] as FloorDecal).art == "puddle_mead", "ключ \"decals\" зала: разлитая медовуха на складе")
	add_child(d6)
	await wait(0.05)
	check(not fd.is_empty() and world_mat_ok((fd[0] as Node).get_node_or_null("Decal") as GeometryInstance3D), "статичная декаль — общий материал без instance uniform")
	d6.queue_free()
	await wait(0.05)

	print("-- Двери-награды")
	var expect := {"combat": "rune_circle_blue", "rest": "rune_circle_green", "chest": "rune_circle_gold", "boss": "rune_circle_red", "freya": "rune_circle_green", "elite": "rune_circle_gold"}
	for id in expect:
		var def := Run.reward_def(id)
		var door := RewardDoor.create(def, id)
		door.set_meta("warmup", true)
		game.room.add_child(door)
		var rc := door.get_node_or_null("RuneCircle") as MeshInstance3D
		check(rc != null and rc.material_override == WorldArt.material(expect[id], "glow"), "дверь «%s» — круг %s" % [id, expect[id]])
		door.dim()
		check(rc != null and not rc.visible, "погашенная дверь «%s» — круг спрятан" % id)
		door.queue_free()

	print("-- Лужа браги и подпалины")
	var puddle := BrewPuddle.spawn(game.room, game.room.to_global(Vector3(0, 0.5, 4)), 1.8, 2.0, 0.55)
	await wait(0.4)  # растекается 0.25 с
	check(puddle != null and puddle._disc.material_override == FX.sprite_material("puddle_mead"), "лужа браги — декаль puddle_mead (общий материал)")
	check(puddle != null and puddle._disc.scale.x > 1.8 * 2.0, "лужа по размеру больше радиуса замедления (%.1f м)" % (puddle._disc.scale.x if puddle else 0.0))
	var fx0 := FX.materials_created
	for i in 15:
		FX.scorch(game.room, game.room.to_global(Vector3(randf_range(-6, 6), 0, randf_range(-3, 6))), 2.0)
	check(FX.pool_size("scorch") <= FX.cfg().scorch_limit and FX.pool_size("scorch") > 0, "подпалины — пул с лимитом (%d ≤ %d)" % [FX.pool_size("scorch"), FX.cfg().scorch_limit])
	check(FX.pool_nodes("scorch").all(func(n: Node) -> bool: return not (n as Node3D).visible or (n as MeshInstance3D).material_override == FX.sprite_material("scorch")), "подпалины на общем материале scorch")
	var fire := preload("res://weapons/fire_zone.gd").new()
	game.add_child(fire)
	var fpos := game.room.to_global(Vector3(1.5, 0, 2.5))
	fire.setup(fpos, 2.0, 0.3, 0.0, false)
	var near := FX.pool_nodes("scorch").filter(func(n: Node) -> bool:
		var q := (n as Node3D).global_position
		return (n as Node3D).visible and Vector2(q.x - fpos.x, q.z - fpos.z).length() < 0.3)
	check(not near.is_empty(), "огонь оставляет подпалину")
	var t0 := FX.pool_active("scorch")
	await wait(FX.cfg().scorch_life + 1.0)
	check(FX.pool_active("scorch") < t0 or t0 == 0, "подпалины затухают (было %d, стало %d)" % [t0, FX.pool_active("scorch")])
	check(FX.materials_created == fx0, "новых материалов эффектов не создано (%d)" % FX.materials_created)

	print("-- Длинный дом Ярла и ларёк: материалы не растут")
	var wa0 := WorldArt.materials_created
	await open(Run.BOSS_SCENE)
	var ld := game.room.find_children("*", "WallDecor", true, false)
	check(ld.size() >= 20, "щиты, знамёна и гобелен на стенах длинного дома (%d)" % ld.size())
	check(ld.any(func(n: Node) -> bool: return (n as WallDecor).art == "tapestry"), "гобелен на южной стене")
	check(game.room.get_node_or_null("Banners/BannerW-5") is WallDecor, "знамёна-модели заменены рисованными")
	var hearth := game.room.get_node_or_null("Decor/Hearth")
	check(hearth != null and hearth.get_node_or_null("Embers") is CPUParticles3D and hearth.get_node_or_null("Flames") is CPUParticles3D, "очаг: языки пламени и искры")
	check(world_mat_ok(hearth.get_node("Flames") as GeometryInstance3D) if hearth and hearth.has_node("Flames") else false, "пламя очага — общий материал без instance uniform")
	await open("res://rooms/shop_room.tscn")
	var stall := game.room.get_node_or_null("ShopStall")
	var sq := stall.get_node_or_null("Stall/SignBoard/Quad") as MeshInstance3D if stall else null
	check(sq != null and world_mat_ok(sq) and sq.material_override == WorldArt.material("shop_sign", "decor"), "вывеска ларька — картинка shop_sign")
	var sarts := game.room.find_children("*", "WallDecor", true, false).map(func(n: Node) -> String: return (n as WallDecor).art)
	check(sarts.has("tapestry") and sarts.has("odin_poster"), "в ларьке гобелен и плакат Одина")
	check(WorldArt.materials_created == wa0, "материалы графики мира не растут от зала к залу (%d)" % WorldArt.materials_created)
	check(WorldArt.materials().size() >= WorldArt.material_specs().size(), "прогрев создал все материалы (%d)" % WorldArt.materials().size())

	print("-- Толпа: текущие instance-материалы (не занятые слоты GL)")
	await open("res://rooms/room_08.tscn")
	var c := Vector3(0, 0.05, 0)
	for i in 40:
		var a := TAU * i / 40.0
		game.room.spawn_extra("fodder" if i % 3 else "grunt", c + Vector3(cos(a) * 6.0, 0, sin(a) * 6.0))
	await wait(1.5)
	for i in 6:
		FX.scorch(game.room, game.room.to_global(Vector3(i - 3, 0, 2)), 2.0)
	var iu := FX.instance_uniform_users(get_tree().root)
	check(iu < FX.INSTANCE_SLOTS_GL, "толпа %d врагов + декор + атмосфера: %d узлов с текущим instance-материалом < %d (ориентир)" % [game.room.alive_count(), iu, FX.INSTANCE_SLOTS_GL])
	var decor_iu := FX.instance_uniform_users(game.room.get_node("Banners")) + FX.instance_uniform_users(game.room.get_node("Atmosphere"))
	check(decor_iu == 0, "декор и атмосфера: текущих instance-материалов — 0")
	print("   текущие instance-материалы, узлы: %d (декор и атмосфера: %d), материалов графики мира: %d" % [iu, decor_iu, WorldArt.materials_created])

	print("=== ИТОГ WORLD ART: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
