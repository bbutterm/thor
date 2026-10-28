extends Node
## Одни и те же реплики до/после, плюс боевой пузырь Тора с новой эмоцией.
## godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/thor_embarrassed_shots.tscn -- <папка>

var output := "user://thor_embarrassed_shots"

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
	Save.use_path("user://thor_embarrassed_shots_save.json")
	Save.reset()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await wait_frames(12)
	# Раньше embarrassed при отсутствии файла выбирал нейтральный портрет.
	Dialogue.play_lines([{"speaker": "thor", "emotion": "neutral", "text": "Я просто разогревался."}], "", "couch")
	await wait_frames(35)
	if not await shot("before"):
		get_tree().quit(1)
		return
	Dialogue.box().skip()
	await wait_frames(5)
	Dialogue.play_lines([{"speaker": "thor", "emotion": "embarrassed", "text": "Я просто разогревался."}], "", "couch")
	await wait_frames(35)
	if not await shot("after"):
		get_tree().quit(1)
		return
	Dialogue.box().skip()
	await wait_frames(5)
	Dialogue.in_run_scenes = false
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait_frames(18)
	var game := get_tree().current_scene as Game
	if game == null or game.room == null:
		printerr("SHOT FAIL: игра не загружена")
		get_tree().quit(1)
		return
	Dialogue.bubble().show_line("thor", "embarrassed", "Я просто разогревался.")
	await wait_frames(20)
	if not await shot("bark"):
		get_tree().quit(1)
		return
	get_tree().quit(0)
