extends Node
## Кадры графики мира крупно (небо, рунный круг прыжка, двери-награды, лужа браги и подпалина, очаг и стены
## длинного дома, вывеска ларька, плакаты деревни):
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/world_art_shots.tscn -- <папка>

var out_dir := "user://world_art_shots"

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
	for i in int(ceil(sec * 60.0)):
		await get_tree().process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("shot: ", name)

func open(room: String) -> Game:
	Run.start_run("berserker")
	Run.room_order.assign([room, Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(2.2)
	var game := get_tree().current_scene as Game
	game.room.set_physics_process(false)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	game.room._spawn_queue.clear()
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	game.player.set_physics_process(false)
	return game

## Встать в точку from (ноги) и смотреть на to.
func look(game: Game, from: Vector3, to: Vector3) -> void:
	var p := game.player
	p.global_position = game.room.to_global(from)
	await wait(0.05)
	var d := game.room.to_global(to) - p.get_aim_origin()
	p.rotation_target = Vector2(atan2(d.y, Vector2(d.x, d.z).length()), atan2(-d.x, -d.z))
	await wait(0.4)

func _run() -> void:
	# Деревня: небо, плакаты на домах, знамёна, туман у земли
	var game := await open("res://rooms/room_09.tscn")
	await look(game, Vector3(-8, 0, 1.2), Vector3(-11, 1.75, -2.3))
	await shot("village_posters")
	await look(game, Vector3(-3, 0, 9), Vector3(0, 0.2, 3))
	await shot("village_jump_rune")
	# Подпалины и лужа браги (Свен), взрыв, огонь
	FX.scorch(game.room, game.room.to_global(Vector3(-2, 0, -2)), 2.5)
	Blast.detonate(game.room, game.room.to_global(Vector3(2.5, 0.8, -1)), 2.5, 0.0)
	BrewPuddle.spawn(game.room, game.room.to_global(Vector3(0, 0.5, 0.5)), 1.8, 30.0, 0.55)
	await look(game, Vector3(0, 0, 5), Vector3(0, 0, -0.5))
	await wait(0.6)
	await shot("village_scorch_puddle")
	# Двери-награды с рунными кругами
	Run.forced_offers = [["combat", "rest", "chest"]]
	game.rewards.show_doors()
	await wait(1.2)
	var dz := (game.room.door as Node3D).position.z + 1.5
	await look(game, Vector3(0, 0, dz + 8), Vector3(0, 1.0, dz))
	await shot("doors_circles")
	# Длинный дом Ярла: очаг, щиты, знамёна
	game = await open(Run.BOSS_SCENE)
	await look(game, Vector3(-4, 0, 9), Vector3(0, 1.0, 0))
	await shot("longhouse_hearth")
	await look(game, Vector3(4, 0, 2), Vector3(-11, 4.4, -8))
	await shot("longhouse_wall")
	await look(game, Vector3(0, 0, 13), Vector3(0, 3.6, 22))
	await shot("longhouse_tapestry")
	# Ларёк: вывеска, гобелен и плакат Одина за ним
	Run.start_run("berserker")
	game = await open("res://rooms/shop_room.tscn")
	await look(game, Vector3(-1.5, 0, 7.5), Vector3(1.5, 2.2, 0))
	await shot("shop_sign")
	get_tree().quit()
