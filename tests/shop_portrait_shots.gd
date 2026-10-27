extends Node
## Кадр настоящего ларька и крупные планы гномов для проверки импорта портретов.
## godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x800 res://tests/shop_portrait_shots.tscn -- <папка>

var output := "user://shop_portrait_shots"

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
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(output.path_join(name + ".png")) != OK:
		printerr("SHOT FAIL: ", name)
		get_tree().quit(1)
		return
	print("shot: ", name)

func _run() -> void:
	Save.use_path("user://shop_portrait_shots_save.json")
	Save.reset()
	Dialogue.in_run_scenes = false
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(12)
	var game := get_tree().current_scene as Game
	if game == null or game.rewards == null:
		printerr("SHOT FAIL: игра не запущена")
		get_tree().quit(1)
		return
	Run.silver = 1000
	game.rewards.open_shop()
	await wait(15)
	await shot("shop")
	game.rewards.shop.close()
	await wait(3)
	Dialogue.play_lines([{"speaker": "brokk", "emotion": "happy", "text": "Для тебя скидка!"}], "", "shop")
	await wait(35)
	await shot("brokk_dialogue")
	Dialogue.box().skip()
	await wait(3)
	Dialogue.play_lines([{"speaker": "eitri", "emotion": "embarrassed", "text": "Угу…"}], "", "shop")
	await wait(35)
	await shot("eitri_dialogue")
	get_tree().quit(0)
