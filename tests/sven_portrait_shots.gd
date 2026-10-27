extends Node
## Кадры до/после для реплики Свена в настоящей игровой сцене и отдельного портрета в диалоге.
## godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/sven_portrait_shots.tscn -- <папка>

var output := "user://sven_portrait_shots"

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

func wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty() or img.save_png(output.path_join(name + ".png")) != OK:
		printerr("SHOT FAIL: ", name)
		get_tree().quit(1)
		return
	print("shot: ", name)

func _run() -> void:
	Save.use_path("user://sven_portrait_shots_save.json")
	Save.reset()
	Dialogue.in_run_scenes = false
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(12)
	var game := get_tree().current_scene as Game
	if game == null or game.room == null or game.player == null:
		printerr("SHOT FAIL: игра не запущена")
		get_tree().quit(1)
		return
	for enemy in game.room.alive_enemies():
		enemy.set_physics_process(false)
	var sven := game.room.spawn_extra("sven", game.room.global_position + Vector3(4, 0.05, -3)) as FatSven
	if sven == null:
		printerr("SHOT FAIL: Свен не появился")
		get_tree().quit(1)
		return
	sven.set_physics_process(false)
	sven.set_meta("boss_title", "ТОЛСТЫЙ СВЕН")
	sven.set_meta("miniboss", true)
	game.hud.show_boss(sven)
	if sven._visual:
		sven._visual.scale *= Vector3(1.35, 1.0, 1.35)
	game.player.global_position = game.room.global_position + Vector3(4, 0.1, 5)
	game.player.rotation_target = Vector2(-0.05, 0)
	await wait(12)
	# До: «sven» через прежний alias показывал те же файлы и координаты, что «draugr».
	Dialogue.speakers["draugr"] = Dialogue.speakers.get("sven", {}).duplicate()
	var bubble := Dialogue.bubble()
	bubble.show_line("draugr", "happy", "О! Гость! Пиво будешь? Нет? Тогда бочкой!")
	await wait(15)
	await shot("sven_bark_before")
	bubble.show_line("sven", "happy", "О! Гость! Пиво будешь? Нет? Тогда бочкой!")
	await wait(15)
	await shot("sven_bark_after")
	Dialogue.play_lines([{"speaker": "sven", "emotion": "smug", "text": "Это мой погреб. И моя бочка."}], "", "run")
	await wait(35)
	await shot("sven_dialogue")
	get_tree().quit(0)
