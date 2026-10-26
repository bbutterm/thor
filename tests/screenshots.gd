extends Node
## Снимает скриншоты ключевых моментов (нужен дисплей; в CI — через xvfb-run).
## godot --path . --rendering-method gl_compatibility res://tests/screenshots.tscn -- <папка>

var out_dir := "user://shots"

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
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot: ", name)

func _run() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await wait(0.5)
	await shot("01_menu")
	# Настройки из главного меню (с образцом слова)
	var sp := SettingsPanel.new()
	get_tree().current_scene.add_child(sp)
	ComicFX.preview()
	await wait(0.15)
	await shot("01b_settings")
	sp.close()
	# Выбор тела (блок Л): открытое и закрытое тело
	var bsel := BodySelect.new()
	get_tree().current_scene.add_child(bsel)
	bsel.open("Назад", "berserker")
	await wait(0.4)
	await shot("01c_body_select")
	bsel.select("smith")
	await wait(0.1)
	await shot("01d_body_locked")
	bsel.close("")
	bsel.queue_free()
	get_tree().paused = false
	Run.start_run("hunter")
	Run.room_order.assign(["res://rooms/room_02.tscn", "res://rooms/room_03.tscn", "res://rooms/boss_arena.tscn"])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.4)
	var game := get_tree().current_scene as Game
	var p := game.player
	await wait(1.4)
	# Для постановочных кадров враги «замирают»
	for en in game.room.alive_enemies():
		en.set_physics_process(false)
	await wait(0.2)
	await shot("02_room_start")
	# Ярость (блок П): шкала наполовину, потом берсерк
	for i in 14:
		p.rage.add_kill()
	await wait(0.2)
	await shot("02b_rage")
	p.rage.start_berserk()
	await wait(0.6)
	await shot("02c_berserk")
	p.rage.reset()
	# Подходим к врагу и бьём
	var enemies := game.room.alive_enemies()
	if not enemies.is_empty():
		var e := enemies[0]
		var to := e.global_position - p.global_position
		p.rotation_target = Vector2(-0.12, atan2(-to.x, -to.z))
		p.global_position = e.global_position - to.normalized() * 2.2
		p.global_position.y = e.global_position.y + 0.05
		await wait(0.1)
		p.axe.request_attack()
		await wait(0.12)
		await shot("03_axe_swing")
		# Комиксовое слово: крит (тяжёлый 3-й удар комбо по живому врагу)
		ComicFX.reset_state()
		e.take_hit(1.0, Vector3.ZERO, "axe_finisher")
		await wait(0.12)
		await shot("03b_comic_crit")
		await wait(0.4)
		p.mjolnir.throw_hammer()
		await wait(0.18)
		await shot("04_hammer_throw")
	await wait(1.5)
	# Дальний вид зала сверху (удар-приземление)
	p.global_position += Vector3(0, 6, 0)
	p.rotation_target.x = -0.6
	await wait(0.2)
	ComicFX.reset_state()
	p.call("_start_slam")
	var slam_frames := 0
	while p.is_slamming and slam_frames < 60:
		await get_tree().process_frame
		slam_frames += 1
	await wait(0.1)
	await shot("05a_comic_slam")
	await wait(0.6 - slam_frames / 60.0 - 0.1)
	await shot("05_slam")
	for en in game.room.alive_enemies().duplicate():
		en.take_hit(9999, Vector3(0, 2, -6), "melee_finisher")
	await wait(1.4)
	for en in game.room.alive_enemies().duplicate():
		en.take_hit(9999, Vector3(0, 2, -6), "melee_finisher")
	await wait(2.0)
	await shot("06_rune_pick")
	Run.forced_offers.assign([["elite", "rest", "freya"]])
	game.rune_pick._open_time = -10.0
	game.rune_pick.choose(0)
	await wait(1.6)
	# Двери-награды (блок И): встаём посреди зала лицом к северной стене
	if not game.rewards.doors.is_empty():
		var dz := game.rewards.doors[0].global_position
		p.global_position = Vector3(game.room.global_position.x, dz.y + 0.1, dz.z + 8.5)
		p.velocity = Vector3.ZERO
		p.rotation_target = Vector2(0.12, 0.0)
		await wait(0.4)
	await shot("07_doors")
	game.pause_menu.toggle()
	await wait(0.2)
	await shot("07b_pause")
	game.pause_menu.toggle()
	# Босс
	Run.room_index = 1
	game.call("_on_exit_reached")
	await wait(2.6)
	var boss: Enemy = null
	for en in game.room.alive_enemies():
		if en.kind == Enemy.Kind.BOSS:
			boss = en
	if boss:
		var to2 := boss.global_position - p.global_position
		p.rotation_target = Vector2(0.05, atan2(-to2.x, -to2.z))
		await wait(0.2)
	await shot("08_boss")
	# Крупное слово на весь экран (добивание босса)
	ComicFX.reset_state()
	ComicFX.pop("boss_kill", Vector3.ZERO, true)
	await wait(0.2)
	await shot("08b_comic_big")
	# Мьёльнир: трейты в HUD, воткнутый молот, экран выбора трейта, мини-босс
	for en in game.room.alive_enemies():
		en.set_physics_process(false)
	for t in Run.all_mjolnir_traits:
		if t.id in [&"fire_trail", &"chain_lightning", &"chain_lightning"]:
			Run.add_mjolnir_trait(t)
	p.rotation_target.x = -0.35
	await wait(0.2)
	p.mjolnir.throw_hammer()
	await wait(0.5)
	await shot("10_hammer_stuck")
	var tchoices := Run.random_mjolnir_trait_choices(3)
	game.trait_pick.open(tchoices)
	await wait(0.5)
	await shot("11_trait_pick")
	game.trait_pick._open_time = -10.0
	game.trait_pick.choose(0, true)
	await wait(0.9)
	if game.rune_pick.visible:
		game.rune_pick._open_time = -10.0
		game.rune_pick.choose(0)
	var mb := Run.miniboss_def() as MinibossDef
	if mb:
		var sven := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
		mb.apply(sven, game.hud)
		var fwd := p.get_aim_forward()
		fwd.y = 0
		sven.position = p.global_position + fwd.normalized() * 6.0
		game.room.add_child(sven)
		sven.rotation.y = p.rotation.y
		game.hud.show_boss(sven)
		p.rotation_target.x = 0.05
		await wait(2.0)
		sven.set_physics_process(false)
		await shot("12_miniboss")
	# Ларёк Брокка и Эйтри (блок К): зал-ларёк, прилавок, экран покупки
	Run.room_index = 1
	Run.room_rewards.assign(["combat", "shop"])
	game.call("_load_room")
	await wait(1.6)
	var stall := game.room.get_node_or_null("ShopStall") as Node3D
	if stall:
		p.global_position = stall.global_position + Vector3(1.2, 0.1, 5.2)
		p.velocity = Vector3.ZERO
		p.rotation_target = Vector2(0.05, 0.22)
		Run.add_silver(230)
		await wait(1.0)
		await shot("13_shop_stall")
		game.rewards.open_shop()
		await wait(0.6)
		await shot("14_shop_screen")
		game.rewards.shop.close()
		await wait(0.3)
	# Испытание Локи «пол — лава» (блок Ф): лава, панель испытания, реплика
	Run.room_rewards.assign(["combat", "trial"])
	Run.forced_trial = "loki_lava"
	game.call("_load_room")
	await wait(2.4)
	for en in game.room.alive_enemies():
		en.set_physics_process(false)
	p.rotation_target = Vector2(-0.25, 0.0)
	await wait(0.3)
	await shot("15_trial_lava")
	p.take_damage(99999.0, Vector3.ZERO, true)
	await wait(2.2)
	await shot("09_death")
	# Диалог у дивана после смерти (блок А)
	game.end_screen.restart_requested.emit()
	await wait(1.6)
	await shot("10_dialogue")
	var box := Dialogue.box()
	for i in 60:
		if not box.visible or box._waiting_choice:
			break
		box.advance()
		await wait(0.15)
	if box.visible and box._waiting_choice:
		await wait(0.2)
		await shot("11_dialogue_choice")
	box.skip()
	await wait(0.6)
	# «План тренировок» (блок В): немного Славы для наглядности и одна покупка
	var plan := game.get_node_or_null("TrainingPlan") as TrainingPlan
	if plan:
		Save.add_glory_bank(420)
		plan._rebuild()
		plan.buy("belly")
		await wait(0.6)
		await shot("12_training_plan")
	FX.reset_time()
	get_tree().quit(0)
