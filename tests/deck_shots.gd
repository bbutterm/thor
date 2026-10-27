extends Node
## Скриншоты экранов для проверки 1280×800, в том числе таблицы переназначения.
## godot --path . --rendering-method gl_compatibility --resolution 1280x800 res://tests/deck_shots.tscn -- /path/to/shots
## Для ускорения программного рендера фон 3D отключён; все 2D-контролы настоящие.

var output: String = "user://deck_shots"
var layout_failures: int = 0

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

func frames(n: int = 15) -> void:
	for i in n:
		await get_tree().process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := output.path_join(name + ".png")
	if img == null or img.is_empty() or img.save_png(path) != OK:
		push_error("Снимок не записан: " + path)
		get_tree().quit(1)
		return
	print("shot: %s (%d×%d)" % [name, img.get_width(), img.get_height()])

func check_bounds(control: Control, label: String) -> void:
	var rect := control.get_global_rect()
	var viewport := get_viewport().get_visible_rect().size
	var ok := rect.position.x >= 8.0 and rect.position.y >= 8.0 and rect.end.x <= viewport.x - 8.0 and rect.end.y <= viewport.y - 8.0
	print("layout: %s %s in %s: %s" % [label, rect, viewport, "OK" if ok else "FAIL"])
	if not ok:
		layout_failures += 1

func _run() -> void:
	Save.use_path("user://deck_shots_save.json")
	Save.reset()
	GameSettings.reset_all()
	Dialogue.in_run_scenes = false
	get_viewport().disable_3d = true
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await frames()
	await shot("01_menu")
	var panel := SettingsPanel.new()
	get_tree().current_scene.add_child(panel)
	await frames()
	panel.show_tab(2)
	await frames()
	await shot("02_settings_buttons")
	panel._scroll.scroll_vertical = int(panel._scroll.get_v_scroll_bar().max_value)
	await frames()
	await shot("03_settings_camera")
	panel.close()
	await frames()
	var body := BodySelect.new()
	get_tree().current_scene.add_child(body)
	body.open("Назад", "berserker")
	await frames()
	await shot("04_body")
	check_bounds(body._detail_panel, "body detail")
	check_bounds(body._back_btn, "body back")
	check_bounds(body._fight_btn, "body fight")
	var joy := InputEventJoypadMotion.new()
	joy.device = 0
	joy.axis = JOY_AXIS_RIGHT_Y
	joy.axis_value = 1.0
	Input.parse_input_event(joy)
	await frames(30)
	joy.axis_value = 0.0
	Input.parse_input_event(joy)
	await frames()
	print("detail scroll: %d" % body._detail_scroll.scroll_vertical)
	if body._detail_scroll.scroll_vertical <= 0:
		layout_failures += 1
	await shot("04_body_scrolled")
	body.close("")
	body.queue_free()
	await frames()
	var plan := TrainingPlan.new()
	get_tree().current_scene.add_child(plan)
	plan.open("Назад")
	await frames()
	await shot("05_training")
	plan.close(false)
	plan.queue_free()
	await frames()
	Run.start_run("berserker")
	var rune := RunePick.new()
	get_tree().current_scene.add_child(rune)
	await frames()
	var rune_choices: Array[RuneDef] = []
	rune_choices.assign(Run.all_runes.slice(0, 3))
	rune.open(rune_choices)
	await frames()
	await shot("06_runes")
	rune.visible = false
	rune.queue_free()
	get_tree().paused = false
	await frames()
	var trait_picker := TraitPick.new()
	get_tree().current_scene.add_child(trait_picker)
	await frames()
	var traits: Array[MjolnirTrait] = []
	traits.assign(Run.all_mjolnir_traits.slice(0, 3))
	trait_picker.open(traits)
	await frames()
	await shot("07_traits")
	trait_picker.visible = false
	trait_picker.queue_free()
	get_tree().paused = false
	await frames()
	var choice := ChoicePick.new()
	get_tree().current_scene.add_child(choice)
	await frames()
	choice.open("ВЫБОР", "Один предлагает награду.", [
		{"id": "a", "title": "Лечение", "desc": "Восстанавливает здоровье."},
		{"id": "b", "title": "Руна", "desc": "Улучшает руну."},
		{"id": "c", "title": "Отказ", "desc": "Уйти без награды."},
	], "odin")
	await frames()
	await shot("08_choice")
	choice.visible = false
	choice.queue_free()
	get_tree().paused = false
	await frames()
	var dialogue := DialogueBox.new()
	get_tree().current_scene.add_child(dialogue)
	await frames()
	dialogue.open([{"id": "deck", "speaker": "odin", "text": "Тор, что скажешь?", "choices": [
		{"id": "yes", "label": "Согласиться", "text": "Я готов."},
		{"id": "no", "label": "Огрызнуться", "text": "Сам иди!"},
	]}])
	dialogue._finish_typing()
	await frames()
	await shot("09_dialogue")
	dialogue.skip()
	dialogue.queue_free()
	await frames()
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(12)
	var game := get_tree().current_scene as Game
	Run.silver = 1000
	game.rewards.open_shop()
	await frames()
	await shot("10_shop")
	game.rewards.shop.close()
	await frames()
	game.pause_menu.toggle()
	await frames()
	await shot("11_pause")
	game.pause_menu.toggle()
	await frames()
	game.end_screen.show_result(false)
	await frames()
	await shot("12_end")
	get_tree().quit(1 if layout_failures > 0 else 0)
