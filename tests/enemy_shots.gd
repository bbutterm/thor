extends Node
## Кадры врагов Мидгарда и элиты (нужен дисплей; в CI — xvfb-run): строй новых врагов, телеграфы
## (фитиль Раздутого, лазер Наёмника, обряд Шамана), толпа корма, элиты с модификаторами.
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 960x540 res://tests/enemy_shots.tscn -- <папка>

var out_dir := "user://enemy_shots"
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
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func wait(sec: float) -> void:
	for i in maxi(1, int(ceil(sec * 60.0))):
		await get_tree().process_frame
		if is_instance_valid(p):
			p.health = p.max_health

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot: ", name)

func _clear_room() -> void:
	game.room.set_physics_process(false)
	game.room._spawn_queue.clear()
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	game.room._alive.clear()
	await wait(0.1)

func _run() -> void:
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.5)
	game = get_tree().current_scene as Game
	p = game.player
	await wait(1.2)
	await _clear_room()
	var base := game.room.global_position
	p.global_position = base + Vector3(0, 0.1, 6)
	p.rotation_target = Vector2(-0.08, 0.0)
	# Строй: корм, Раздутый, Щитоносец, Шаман, Наёмник
	var kinds := ["fodder", "bloated", "shieldbearer", "shaman", "merc"]
	var row: Array[Enemy] = []
	for i in kinds.size():
		var e := game.room.spawn_extra(kinds[i], base + Vector3((i - 2) * 1.9, 0.05, 1.0))
		row.append(e)
	await wait(1.6)
	for e in row:
		e.set_physics_process(false)
		e.rotation.y = 0.0
		e._humanoid.play(e.anim_idle, 0.0)
	await wait(0.3)
	await shot("01_lineup")
	# Телеграфы: фитиль Раздутого, лазер Наёмника, обряд Шамана
	for e in row:
		e.set_physics_process(true)
	row[1]._begin_windup(true)
	row[3]._begin_windup(false)
	row[4]._begin_windup(false)
	await wait(0.5)
	await shot("02_telegraphs")
	await wait(1.0)
	await _clear_room()
	# Толпа корма
	for i in 30:
		game.room.spawn_extra("fodder", base + Vector3(randf_range(-8, 8), 0.05, randf_range(-9, -2)))
	await wait(2.5)
	await shot("03_horde")
	await _clear_room()
	get_tree().quit(0)
