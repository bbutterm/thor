extends Node
## Реальная дверь награды в игровом зале до/после добавления иконки Ярла.
## godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/boss_door_shots.tscn -- <папка>

var output := "user://boss_door_shots"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	_run.call_deferred()

func wait_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func shot(name: String) -> bool:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty() or img.save_png(output.path_join(name + ".png")) != OK:
		printerr("SHOT FAIL: ", name)
		return false
	print("shot: ", name)
	return true

func _run() -> void:
	Save.use_path("user://boss_door_shots_save.json")
	Save.reset()
	Dialogue.in_run_scenes = false
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait_frames(18)
	var game := get_tree().current_scene as Game
	var def := Run.reward_def("boss")
	if game == null or game.room == null or game.player == null or def == null or def.icon() == null:
		printerr("SHOT FAIL: игра или иконка босса не загружены")
		get_tree().quit(1)
		return
	for enemy in game.room.alive_enemies():
		enemy.set_physics_process(false)
	var player := game.player
	player.set_physics_process(false)
	# Смотреть вдоль прохода: в центре «Зала бочек» стоит колонна, за ней дверь не видно.
	player.global_position = game.room.to_global(Vector3(-4, 0.1, 4))
	player.rotation = Vector3.ZERO
	player.head.rotation.x = 0.2
	var before := def.duplicate() as RewardDef
	before.icon_name = "boss_before"
	var door_before := RewardDoor.create(before, "boss")
	game.room.add_child(door_before)
	door_before.global_position = game.room.to_global(Vector3(-4, 0, -6))
	await wait_frames(20)
	if not await shot("before"):
		get_tree().quit(1)
		return
	door_before.queue_free()
	await wait_frames(2)
	var door_after := RewardDoor.create(def, "boss")
	game.room.add_child(door_after)
	door_after.global_position = game.room.to_global(Vector3(-4, 0, -6))
	await wait_frames(20)
	if not await shot("after"):
		get_tree().quit(1)
		return
	get_tree().quit(0)
