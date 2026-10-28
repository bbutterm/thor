extends Node
## Кадры молота после плейтеста 28.10 (П2/П5): бросок сквозь толпу, втыкание, возврат по ПКМ, идеальный хват.
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/hammer_shots.tscn -- <папка> [old]
## С «old» — то же со старым поведением (FeelSwitch: hammer_power, hammer_recall), для сравнения.

const START := Vector3(-3, 0.1, -4)

var out_dir := "user://hammer_shots"
var game: Game
var prefix := ""

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
	if args.size() > 1 and args[1] == "old":
		FeelSwitch.set_old(&"hammer_power", true)
		FeelSwitch.set_old(&"hammer_recall", true)
		prefix = "old_"
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func wait(sec: float) -> void:
	for i in maxi(1, int(ceil(sec * 60.0))):
		await get_tree().physics_frame

func grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(out_dir.path_join(prefix + name + ".png"))
	print("frame: ", prefix + name)

func _enemy(scene: String, side: float, fwd: float) -> Enemy:
	var e := (load("res://enemies/%s.tscn" % scene) as PackedScene).instantiate() as Enemy
	e.move_speed = 0.0
	e.attack_range = 0.0
	game.add_child(e)
	e.global_position = Vector3(START.x + side, 0.0, START.z - fwd)
	var to := START - e.global_position
	e.rotation.y = atan2(to.x, to.z)
	return e

func _reset(pitch: float = 0.0) -> void:
	var p := game.player
	if not p.mjolnir.in_hand:
		p.mjolnir.force_return_instant()
	p.global_position = START
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2(pitch, 0.0)
	p.rotation.y = 0.0
	p.head.rotation.x = pitch
	p.health = p.max_health
	p.mjolnir.reset_cooldown()

func _run() -> void:
	seed(2810)
	GameSettings.set_value("access", "catch_assist", true)
	Run.start_run("berserker")
	Run.room_order.assign([Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.5)
	game = get_tree().current_scene as Game
	await wait(1.5)
	game.room.set_physics_process(false)
	game.room._spawn_queue.clear()
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	var p := game.player
	var hand := p.mjolnir
	_reset()
	await wait(0.5)
	# 1. Сквозь толпу: корм и бойцы в линию до стены
	for i in 6:
		_enemy("fodder", randf_range(-0.6, 0.6), 2.5 + i * 1.3)
	_enemy("grunt", 0.8, 6.0)
	_enemy("grunt", -0.8, 8.5)
	await wait(0.6)
	await grab("01_aim_crowd")
	hand.press_throw()
	await wait(2.0 / 60.0)
	await grab("02_throw")
	await wait(0.08)
	await grab("03_through_crowd")
	await wait(0.15)
	await grab("04_crowd_flying")
	for i in 120:
		if hand.projectile and hand.projectile.is_stuck():
			break
		await get_tree().physics_frame
	await wait(0.05)
	await grab("05_stuck_wall")
	await wait(0.6)
	await grab("06_stuck_crackle")
	# 2. Возврат по ПКМ: летит к руке, разгоняется; ловим идеально
	hand.press_throw()
	await wait(0.12)
	await grab("07_return")
	var proj := hand.projectile
	for i in 120:
		if proj == null or not is_instance_valid(proj):
			break
		var eta := proj.catch_eta()
		if eta >= 0.0 and eta <= hand.perfect_window * 0.5:
			break
		await get_tree().physics_frame
	await grab("08_return_near")
	hand.press_throw()
	for i in 60:
		if hand.in_hand:
			break
		await get_tree().physics_frame
	await wait(2.0 / 60.0)
	await grab("09_perfect_catch")
	await wait(0.6)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	# 3. Промах вдаль, вверх: падает дугой и втыкается в землю; за спиной — иконка «где молот»
	_reset(0.05)
	hand.max_range = 12.0
	await wait(0.3)
	hand.press_throw()
	for i in 180:
		if hand.projectile and (hand.projectile.is_stuck() or hand.in_hand):
			break
		await get_tree().physics_frame
	await wait(0.1)
	await grab("10_miss_stuck_ground")
	p.rotation_target = Vector2(0.0, PI * 0.75)
	await wait(0.5)
	await grab("11_offscreen_icon")
	hand.max_range = 25.0
	# 4. Щитоносец останавливает: отскок и молот в полу рядом
	_reset()
	await wait(0.3)
	var sh := _enemy("shieldbearer", 0.0, 7.0)
	sh.max_health = 5000
	sh.health = 5000
	await wait(0.4)
	hand.press_throw()
	for i in 120:
		if hand.projectile and hand.projectile.is_stuck():
			break
		await get_tree().physics_frame
	await wait(0.1)
	await grab("12_stopped_by_shield")
	print("=== HAMMER SHOTS: готово, ", out_dir, " ===")
	FeelSwitch.set_all_old(false)
	get_tree().quit(0)
