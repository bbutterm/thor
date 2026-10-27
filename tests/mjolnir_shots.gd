extends Node
## Кадры Мьёльнира (нужен дисплей; в CI — xvfb-run): в руке, в полёте, воткнутый, крупно в мире с трёх сторон.
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/mjolnir_shots.tscn -- <папка>

var out_dir := "user://mjolnir_shots"

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
	for i in maxi(1, int(ceil(sec * 60.0))):
		await get_tree().process_frame

func grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(out_dir.path_join(name + ".png"))
	print("frame: ", name)

func _run() -> void:
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_02.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.4)
	var game := get_tree().current_scene as Game
	var p := game.player
	await wait(1.4)
	for en in game.room.alive_enemies():
		en.set_physics_process(false)
		en.global_position += Vector3(0, 0, -40)
	p.rotation_target = Vector2(-0.05, p.rotation_target.y)
	await wait(0.4)
	await grab("01_in_hand")
	p.rotation_target = Vector2(-0.25, p.rotation_target.y)
	await wait(0.3)
	p.mjolnir.throw_hammer()
	await wait(0.12)
	await grab("02_flight")
	await wait(1.2)
	await grab("03_out")
	# Крупно в мире: тот же молот, что летит (WeaponMeshes.hammer), на уровне глаз перед камерой
	var cam := get_viewport().get_camera_3d()
	var hm := WeaponMeshes.hammer()
	game.add_child(hm)
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	p.mjolnir.set_process(false)
	for i in 3:
		hm.global_position = cam.global_position + fwd * 1.1 + Vector3(0, -0.15, 0)
		hm.rotation = Vector3(0.0, cam.global_rotation.y + [0.0, PI * 0.5, PI * 0.25][i], [0.0, 0.0, 0.5][i])
		hm.scale = Vector3.ONE * 1.15
		await wait(0.1)
		await grab("0%d_close" % (4 + i))
	get_tree().quit(0)
