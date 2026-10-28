extends Node
## До/после для дополнительной эмоции персонажа в диалоге и боевом пузыре.
## godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/extra_emotion_shots.tscn -- <папка> <loki|jarl>

var output := "user://extra_emotion_shots"
var speaker := "loki"

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
	if args.size() > 1:
		speaker = args[1]
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
	var texts := {
		"loki": "Мне? Ничего! Просто… поддержать брата. Морально. Издалека.",
		"jarl": "Это не нитка! Это… крепкий шов! Мне его пришили! Почти профессионально!",
	}
	var barks := {
		"loki": "Ладно, ладно, забирай. Я и так собирался проиграть.",
		"jarl": "Я… я сам слез. Специально.",
	}
	if not texts.has(speaker) or not Portrait.texture_path(speaker, "embarrassed").ends_with(speaker + "_embarrassed.webp"):
		printerr("SHOT FAIL: неизвестный персонаж или нет новой эмоции: ", speaker)
		get_tree().quit(1)
		return
	var line := str(texts[speaker])
	var backdrop := "midgard" if speaker == "jarl" else "couch"
	Save.use_path("user://extra_emotion_shots_save.json")
	Save.reset()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await wait_frames(12)
	# Раньше embarrassed при отсутствии файла выбирал neutral.
	Dialogue.play_lines([{"speaker": speaker, "emotion": "neutral", "text": line}], "", backdrop)
	await wait_frames(20)
	Dialogue.box()._finish_typing()
	await wait_frames(2)
	if not await shot("before"):
		get_tree().quit(1)
		return
	Dialogue.box().skip()
	await wait_frames(5)
	Dialogue.play_lines([{"speaker": speaker, "emotion": "embarrassed", "text": line}], "", backdrop)
	await wait_frames(20)
	Dialogue.box()._finish_typing()
	await wait_frames(2)
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
	for enemy in game.room.alive_enemies():
		enemy.set_physics_process(false)
	# Дожидаемся затухания образцов прогрева, чтобы они не закрывали игровой кадр.
	await wait_frames(40)
	Dialogue.bubble().show_line(speaker, "embarrassed", str(barks[speaker]))
	await wait_frames(20)
	if not await shot("bark"):
		get_tree().quit(1)
		return
	get_tree().quit(0)
