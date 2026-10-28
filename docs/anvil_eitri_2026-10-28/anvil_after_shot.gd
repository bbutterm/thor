extends Node
## Стенд для отдельной копии d95bb11. Принудительно: награда anvil, выбор fire,
## одна строка пула dwarves.eitri. Действительный выбор проходит TraitPick.choose().
var output := "user://anvil_after_shot"

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

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func fail(message: String) -> void:
	printerr("SHOT FAIL: ", message)
	get_tree().quit(1)

func shot(name: String) -> bool:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(output.path_join(name + ".png")) != OK:
		return false
	print("SHOT: ", name)
	return true

func _run() -> void:
	# Как и в прежнем снимке, свежий забег в первом зале; сцены и обучение здесь не проходят.
	Save.use_path("user://anvil_after_shot_save.json")
	Save.reset()
	Dialogue.in_run_scenes = false
	seed(81494)
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(60)
	var game := get_tree().current_scene as Game
	if game == null or game.room == null or game.rewards == null or game.trait_pick == null:
		fail("игровая сцена не готова")
		return
	game.room.set_physics_process(false)
	game.room._spawn_queue.clear()
	for enemy in game.room.alive_enemies():
		enemy.set_physics_process(false)

	# Награда и единственный вариант стихии фиксируются только в памяти стенда.
	while Run.room_rewards.size() <= Run.room_index:
		Run.room_rewards.append("")
	Run.room_rewards[Run.room_index] = "anvil"
	var fire := Run.mjolnir_trait_def(&"fire")
	if fire == null:
		fail("нет стихии fire")
		return
	Run.all_mjolnir_traits.assign([fire])
	Run.mjolnir_traits.clear()
	Run.mjolnir_trait_levels.clear()
	Run.mjolnir_traits_changed.emit(Run.mjolnir_traits)

	# Оставляем в настоящем пуле одну исходную строку: фиксируем случайность, не рисуем пузырь вручную.
	var selected: Array = []
	for item in Dialogue.pools.get("dwarves.eitri", []):
		var lines: Array = item.get("lines", [])
		if not lines.is_empty() and str(lines[0].get("id", "")) == "dwarves.eitri.04":
			selected.append(item)
	if selected.size() != 1:
		fail("не найдена исходная строка dwarves.eitri.04")
		return
	Dialogue.pools["dwarves.eitri"] = selected
	var before := Dialogue.history.size()
	game.rewards._granted = false
	game.rewards.grant()
	await frames(12)
	var pick := game.trait_pick
	if not pick.visible or pick._choices.size() != 1 or pick._choices[0].id != &"fire" or not game.rewards._anvil_pick:
		fail("не открылся выбор наковальни с одной стихией fire")
		return
	if Dialogue.history.size() != before:
		fail("реплика прозвучала до подтверждения")
		return
	if not await shot("01_picker_before_choose"):
		fail("не сохранён кадр выбора")
		return
	# Пропускаем защиту от случайного клика, затем используем обычный путь выбора.
	pick._open_time = -10.0
	pick.choose(0)
	if pick.visible or get_tree().paused or game.rewards._anvil_pick:
		fail("TraitPick не закрылся или награда не подтверждена")
		return
	if Dialogue.history.size() != before + 1:
		fail("число реплик после выбора не равно одной")
		return
	var entry: Dictionary = Dialogue.history[-1]
	if str(entry.get("speaker", "")) != "eitri" or str(entry.get("text", "")) != "Угу-угу.":
		fail("вместо ожидаемой строки показан другой говорящий или текст")
		return
	await frames(16)
	var bubble := Dialogue.bubble()
	if pick.visible or bubble._name.text != "ЭЙТРИ" or bubble._text.text != "Угу-угу." or bubble._panel.modulate.a < 0.5:
		fail("пузырь Эйтри не виден после закрытия выбора")
		return
	if not await shot("02_eitri_after_confirmed_fire"):
		fail("не сохранён итоговый кадр")
		return
	print("FORCED: reward=anvil; offered and chosen=fire; pool=dwarves.eitri.04 (smug, Угу-угу.); TraitPick.choose(0)")
	get_tree().quit(0)
