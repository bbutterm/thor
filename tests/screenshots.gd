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
		await wait(0.4)
		p.mjolnir.throw_hammer()
		await wait(0.18)
		await shot("04_hammer_throw")
	await wait(1.5)
	# Дальний вид зала сверху (удар-приземление)
	p.global_position += Vector3(0, 6, 0)
	p.rotation_target.x = -0.6
	await wait(0.2)
	p.call("_start_slam")
	await wait(0.6)
	await shot("05_slam")
	for en in game.room.alive_enemies().duplicate():
		en.take_hit(9999, Vector3(0, 2, -6), "axe_finisher")
	await wait(1.4)
	for en in game.room.alive_enemies().duplicate():
		en.take_hit(9999, Vector3(0, 2, -6), "axe_finisher")
	await wait(2.0)
	await shot("06_rune_pick")
	game.rune_pick._open_time = -10.0
	game.rune_pick.choose(0)
	await wait(1.0)
	await shot("07_door_open")
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
	await wait(1.0)
	FX.reset_time()
	get_tree().quit(0)
