extends Node
## Кадры комиксовой обводки (GDD 20, scripts/outline.gd) «с обводкой / без» (нужен дисплей; в CI — xvfb-run):
## 01 — строй врагов (элита, щитоносец, наёмник, шаман, Раздутый) + бочка, ящик, взрывная бочка, оружие на полу,
## патроны, сундук; 02 — тот же строй со вспышкой урона (обводка — next_pass оверлея); 03 — толпа 44 врагов;
## 04 — руки от первого лица (обводка во вьюмодели — только для сравнения, в игре выключена);
## 05 — толщина 50 % и 200 %.
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/outline_shots.tscn -- <папка>
## На медленном программном рендере: --fixed-fps 15 и аргумент fps=15 после пути.
## Forward+ (lavapipe): VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot … --rendering-method forward_plus …

var out_dir := "user://outline_shots"
## Частота кадров из --fixed-fps; на программном рендерере можно задать 15.
var capture_fps := 60
var game: Game
var p: Player

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	for arg in args:
		if arg.begins_with("fps="):
			capture_fps = maxi(1, int(arg.trim_prefix("fps=")))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func wait(sec: float) -> void:
	for i in maxi(1, int(ceil(sec * capture_fps))):
		await get_tree().process_frame
		if is_instance_valid(p):
			p.health = p.max_health
			p.is_dead = false

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot: ", name)

## Пара кадров: с обводкой и без
func pair(name: String) -> void:
	GameSettings.set_value("video", "outline", true, false)
	await wait(0.05)
	await shot(name + "_on")
	GameSettings.set_value("video", "outline", false, false)
	await wait(0.05)
	await shot(name + "_off")
	GameSettings.set_value("video", "outline", true, false)

func _clear_room() -> void:
	game.room.set_physics_process(false)
	game.room._spawn_queue.clear()
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	game.room._alive.clear()
	for n in get_tree().get_nodes_in_group("debris"):
		n.queue_free()
	await wait(0.1)

func _freeze(list: Array) -> void:
	for e in list:
		if is_instance_valid(e):
			e.set_physics_process(false)
			if e._humanoid:
				e._humanoid.play(e.anim_idle, 0.0)

func _show_hands(on: bool) -> void:
	var c := p.get_node_or_null("Head/Camera/ViewmodelContainer") as CanvasItem
	if c:
		c.visible = on
	var t := game.get_node_or_null("Tutorial")
	if t:
		t.process_mode = Node.PROCESS_MODE_DISABLED

func _look_at(target: Vector3) -> void:
	var d := target - p.head.global_position
	p.rotation_target = Vector2(atan2(d.y, Vector2(d.x, d.z).length()), atan2(-d.x, -d.z))
	p.rotation.y = p.rotation_target.y
	p.head.rotation.x = p.rotation_target.x

func _run() -> void:
	GameSettings.set_value("video", "outline_width", 1.0, false)
	# Без обучения (пузырь Хугина закрывает кадр)
	if Save.event_count("tutorial_done") == 0:
		Save.bump_event("tutorial_done")
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn"])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.5)
	game = get_tree().current_scene as Game
	p = game.player
	await wait(1.5)
	await _clear_room()
	var base := game.room.global_position
	p.global_position = base + Vector3(0, 0.1, 5.5)
	p.velocity = Vector3.ZERO
	# Строй врагов
	var kinds := ["grunt", "shieldbearer", "merc", "shaman", "bloated"]
	var row: Array = []
	for i in kinds.size():
		var e := game.room.spawn_extra(kinds[i], base + Vector3((i - 2) * 1.6, 0.05, 0.5))
		if i == 0:
			Loot.make_elite(e)
		e.set_physics_process(false)
		row.append(e)
	# Пропсы, оружие, сундук — передний ряд
	var props := [Destructible.BARREL_SCENE, Destructible.CRATE_SCENE, Destructible.EXPLOSIVE_SCENE]
	for i in props.size():
		var d := (load(props[i]) as PackedScene).instantiate() as Destructible
		d.freeze = true
		game.room.add_child(d)
		d.global_position = base + Vector3(-2.6 + i * 1.1, 0.0, 3.0)
	var defs := Loot.all_defs()
	if defs.size() > 1:
		Loot.spawn_weapon(game.room, base + Vector3(0.9, 0.0, 3.2), WeaponItem.create(defs[0]))
		Loot.spawn_weapon(game.room, base + Vector3(1.7, 0.0, 3.0), WeaponItem.create(defs[defs.size() - 3]))
	Loot.spawn_ammo(game.room, base + Vector3(-0.2, 0.0, 3.6))
	Loot.spawn_chest(game.room, base + Vector3(2.9, 0.0, 2.4))
	await wait(1.8)
	_freeze(row)
	for e in row:
		(e as Node3D).look_at((e as Node3D).global_position + Vector3(0, 0, 1), Vector3.UP, true)
	_look_at(base + Vector3(0, 0.9, 1.5))
	# Кадры без HUD и рук (руки — отдельный кадр 04)
	game.hud.visible = false
	_show_hands(false)
	await wait(0.4)
	await pair("01_lineup")
	# Вспышка урона и свечение замаха — обводка в next_pass оверлея
	for e in row:
		(e as Enemy)._set_overlay(0.8, 0.6)
	await wait(0.02)
	for e in row:
		(e as Enemy)._set_overlay(0.8, 0.6)
	await pair("02_flash")
	for e in row:
		(e as Enemy)._set_overlay(0.0, 0.0)
	# Толщина
	GameSettings.set_value("video", "outline_width", Outline.WIDTH_MIN, false)
	await wait(0.05)
	await shot("05_width_50")
	GameSettings.set_value("video", "outline_width", Outline.WIDTH_MAX, false)
	await wait(0.05)
	await shot("05_width_200")
	GameSettings.set_value("video", "outline_width", 1.0, false)
	# Руки от первого лица: обводка во вьюмодели (только для кадра — решение по нему)
	_show_hands(true)
	game.hud.visible = true
	_look_at(base + Vector3(0, 1.2, -6))
	await wait(0.3)
	var vm := p.get_node_or_null("Head/Camera/ViewmodelContainer/SubViewport")
	await shot("04_hands_off")
	if vm:
		Outline.add(vm)
		await wait(0.05)
		await shot("04_hands_on")
		Outline.remove(vm)
	await _clear_room()
	for n in get_tree().get_nodes_in_group("props"):
		n.queue_free()
	if "quick" in OS.get_cmdline_user_args():
		get_tree().quit(0)
		return
	# Толпа 44 врагов
	var crowd: Array = []
	for i in 44:
		var kind := "grunt" if i % 4 == 0 else "fodder"
		var e := game.room.spawn_extra(kind, base + Vector3(randf_range(-7, 7), 0.05, randf_range(-8, 1.5)))
		crowd.append(e)
	await wait(2.5)
	_freeze(crowd)
	p.global_position = base + Vector3(0, 0.1, 6.5)
	_look_at(base + Vector3(0, 0.6, -2))
	game.hud.visible = false
	_show_hands(false)
	await wait(0.3)
	await pair("03_crowd")
	print("обведено узлов: %d, instance uniform: %d" % [Outline.active_count(), FX.instance_uniform_users(get_tree().root)])
	get_tree().quit(0)
