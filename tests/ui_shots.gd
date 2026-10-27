extends Node
## Кадры интерфейса на скине комплекта (блок С): меню, настройки, выбор тела, «План тренировок»,
## HUD в бою, шкала стиля, выбор рун/трейтов/награды, ларёк, пауза, диалог, экран конца.
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/ui_shots.tscn -- <папка>
## (то же с --resolution 1920x1080 — проверка масштаба). Второй аргумент — язык: `-- <папка> en`.

var out_dir := "user://ui_shots"

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
	if args.size() > 1:
		GameSettings.set_value("text", "language", args[1], false)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot: ", name)

func _run() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await wait(0.6)
	await shot("01_menu")
	var sp := SettingsPanel.new()
	get_tree().current_scene.add_child(sp)
	await wait(0.2)
	for i in sp.tab_count():
		sp.show_tab(i)
		await wait(0.1)
		await shot("02_settings_%d" % i)
	sp.close()
	var bsel := BodySelect.new()
	get_tree().current_scene.add_child(bsel)
	bsel.open("Назад", "berserker")
	await wait(0.4)
	await shot("03_body_select")
	bsel.close("")
	bsel.queue_free()
	var tp := TrainingPlan.new()
	get_tree().current_scene.add_child(tp)
	tp.open("Назад")
	await wait(0.4)
	await shot("04_training_plan")
	tp.close(false)
	tp.queue_free()
	get_tree().paused = false

	Run.start_run("hunter")
	Run.room_order.assign(["res://rooms/room_02.tscn", "res://rooms/room_03.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(2.0)
	var game := get_tree().current_scene as Game
	var p := game.player
	for en in game.room.alive_enemies():
		en.set_physics_process(false)
	# Руны и трейты — для ряда иконок; щит Сиф; полрывка; молот в полёте
	for id in ["sif_shield", "sif_shield", "axe_damage", "dash_charge", "valkyrie_wings", "star_fall", "loki_hiccup"]:
		var r := Run.rune_def(id)
		if r:
			Run.add_rune(r)
	p.recalc_from_runes(Run)
	p.refill_shield()
	for t in Run.all_mjolnir_traits:
		if str(t.id) in ["fire", "storm"]:
			Run.add_mjolnir_trait(t)
	p.health = p.max_health * 0.62
	p.health_changed.emit(p.health, p.max_health)
	p.dash_charges = 1
	p.dash_charges_changed.emit(1, p.dash_charges_max, 0.45)
	p.style.set_points(40.0)
	await wait(0.3)
	await shot("05_hud")
	p.mjolnir.throw_hammer()
	p.rotation_target.y += PI * 0.9
	await wait(0.15)
	await shot("06_hud_thrown_offscreen")
	p.style.start_berserk()
	game.hud.show_boss(game.room.alive_enemies()[0])
	await wait(0.5)
	await shot("07_berserk_boss")
	p.style.reset()
	# Выбор руны и трейта
	game.rune_pick.open(Run.random_rune_choices(3))
	await wait(0.3)
	(game.rune_pick._cards.get_child(1) as Control).grab_focus()
	await wait(0.1)
	await shot("08_rune_pick")
	game.rune_pick._open_time = -10.0
	game.rune_pick.choose(0)
	await wait(0.1)
	var traits := Run.random_mjolnir_trait_choices(3)
	if not traits.is_empty():
		game.trait_pick.open(traits)
		await wait(0.4)
		await shot("09_trait_pick")
		game.trait_pick._open_time = -10.0
		game.trait_pick.choose(0, true)
	await wait(0.1)
	if game.rewards and game.rewards.choice:
		game.rewards.choice.open(tr("ПРИВАЛ"), tr("Один разрешил пять минут. Выбери одно."), [
			{"id": "heal", "title": tr("Похлёбка"), "desc": tr("Лечение %d %% (+%d HP)") % [40, 60], "glyph": "ᚺ", "color": Color(0.9, 0.5, 0.3)},
			{"id": "rune", "title": tr("Точить руну"), "desc": tr("Улучшить руну на 1 уровень"), "glyph": "ᚱ", "color": Color(0.6, 0.7, 1.0)},
		], "odin")
		await wait(0.4)
		await shot("10_choice_pick")
		game.rewards.choice.visible = false
		get_tree().paused = false
	if game.rewards:
		Run.silver = 140
		Run.silver_changed.emit(140)
		game.rewards.open_shop()
		await wait(0.6)
		await shot("11_shop")
		if game.rewards.shop:
			game.rewards.shop.close()
		get_tree().paused = false
	await wait(0.2)
	game.pause_menu.toggle()
	await wait(0.3)
	await shot("12_pause")
	game.pause_menu.toggle()
	await wait(0.1)
	# Реплики с id — на английском берутся из data/dialogues/en/odin.json
	Dialogue.play_lines([{"id": "odin_intro_03", "speaker": "odin", "emotion": "smug", "text": "Там уже тысячу лет «всё решится». Посмотри на себя."},
		{"id": "odin_intro_04", "speaker": "thor", "emotion": "angry", "text": "А что не так? Плечи на месте. Пузо… тоже на месте."}])
	await wait(1.6)
	await shot("13_dialogue")
	Dialogue.box().skip()
	await wait(0.2)
	game.end_screen.show_result(false)
	await wait(0.8)
	await shot("14_end")
	get_tree().quit()
