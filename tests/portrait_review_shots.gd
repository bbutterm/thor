extends Node
## Воспроизводимые кадры семи новых эмоций; до объединения ресурсов не запускать.
## Скопировать этот .gd и .tscn в res://tests/, импортировать, затем:
## godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/portrait_review_shots.tscn -- <папка>

const CASES := [
	{"speaker": "sif", "emotion": "embarrassed", "file": "sif", "background": "couch", "line": "После… Ой. Один говорил. Тренировки. Ну… ладно."},
	{"speaker": "eitri", "emotion": "smug", "file": "eitri", "background": "shop", "line": "Угу-угу."},
	{"speaker": "munin", "emotion": "embarrassed", "file": "hugin", "background": "couch", "line": "Ой. Это было секретно? Я не помню. То есть помню. Но не скажу."},
	{"speaker": "skadi", "emotion": "embarrassed", "file": "skadi", "background": "couch", "line": "…Фигура. Речи. Я не умею фигуры. Я умею лыжи."},
	{"speaker": "hel", "emotion": "embarrassed", "file": "hel", "background": "couch", "line": "«Не приходи. Тут скучно. Хотя… приходи. Тут скучно»."},
	{"speaker": "hild", "emotion": "embarrassed", "file": "hild", "background": "couch", "line": "Ладно, дедуля, неплохо. Но в следующий раз — я."},
	{"speaker": "brokk", "emotion": "embarrassed", "file": "brokk", "background": "couch", "line": "Ковали! И рукоять короткая не брак — так задумано! Эргономика!"},
]

var output := "user://portrait_review_shots"

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

func dialogue_shot(item: Dictionary, emotion: String, suffix: String) -> bool:
	Dialogue.play_lines([{"speaker": item.speaker, "emotion": emotion, "text": item.line}], "", str(item.background))
	await wait_frames(20)
	if not Dialogue.box().visible:
		printerr("SHOT FAIL: окно диалога не открылось: ", item.speaker)
		return false
	Dialogue.box()._finish_typing()
	await wait_frames(2)
	var ok := await shot(str(item.speaker) + "_" + suffix)
	Dialogue.box().skip()
	await wait_frames(5)
	return ok

func _run() -> void:
	# До первых кадров убедиться, что тест не подменяет новые эмоции прежним neutral-fallback.
	for item: Dictionary in CASES:
		var expected := "res://sprites/portraits/%s_%s.webp" % [item.file, item.emotion]
		var found := Portrait.texture_path(str(item.speaker), str(item.emotion))
		if found != expected:
			printerr("SHOT FAIL: ", item.speaker, "/", item.emotion, " → ", found, "; ожидалось ", expected)
			get_tree().quit(1)
			return
	if Portrait.texture_path("hugin", "embarrassed") != Portrait.texture_path("munin", "embarrassed") or Portrait.face_of("hugin").get("eye_center", []) != [380.0, 410.0] or Portrait.face_of("munin").get("eye_center", []) != [730.0, 420.0]:
		printerr("SHOT FAIL: alias или точки лиц Хугина/Мунина")
		get_tree().quit(1)
		return
	Save.use_path("user://portrait_review_shots_save.json")
	Save.reset()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await wait_frames(12)
	for item: Dictionary in CASES:
		# neutral воспроизводит прежний fallback, но не меняет игру или исходные файлы.
		if not await dialogue_shot(item, "neutral", "before"):
			get_tree().quit(1)
			return
		if not await dialogue_shot(item, str(item.emotion), "after"):
			get_tree().quit(1)
			return
	Dialogue.in_run_scenes = false
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait_frames(18)
	var game := get_tree().current_scene as Game
	if game == null or game.room == null or game.rewards == null:
		printerr("SHOT FAIL: игровая сцена не загружена")
		get_tree().quit(1)
		return
	for enemy in game.room.alive_enemies():
		enemy.set_physics_process(false)
	await wait_frames(40)
	# Настоящий выбор наковальни; точную случайную фразу задаём явно ради воспроизводимости.
	game.rewards._offer_anvil()
	await wait_frames(8)
	if not game.trait_pick.visible:
		printerr("SHOT FAIL: выбор наковальни не открылся")
		get_tree().quit(1)
		return
	Dialogue.bubble().show_line("eitri", "smug", "Угу-угу.")
	await wait_frames(14)
	if not await shot("eitri_anvil"):
		get_tree().quit(1)
		return
	game.trait_pick.visible = false
	get_tree().paused = false
	# Настоящий TrialRunner Хильд; выбранную реплику задаём явно после прохождения.
	var trial_def := load("res://run/trials/hild_record.tres") as TrialDef
	if trial_def == null:
		printerr("SHOT FAIL: испытание Хильд не загружено")
		get_tree().quit(1)
		return
	var trial := TrialRunner.attach(game.room, trial_def)
	trial.start(game.player)
	trial.pass_trial()
	Dialogue.bubble().show_line("hild", "embarrassed", "Ладно, дедуля, неплохо. Но в следующий раз — я.")
	await wait_frames(14)
	if not await shot("hild_trial"):
		get_tree().quit(1)
		return
	# Компактная диагностическая обрезка Мунина — его реальная реплика используется в новелле.
	Dialogue.bubble().show_line("munin", "embarrassed", "Ой. Это было секретно?")
	await wait_frames(14)
	if not await shot("munin_compact"):
		get_tree().quit(1)
		return
	get_tree().quit(0)
