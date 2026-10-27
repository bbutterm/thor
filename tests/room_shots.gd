extends Node
## Кадры залов: вид от входа и обзор сверху (для проверки планировок глазами).
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/room_shots.tscn -- <папка> [room_07 room_08 …]

var out_dir := "user://room_shots"
var rooms: Array[String] = ["room_07", "room_08", "room_09"]

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
		rooms.assign(args.slice(1))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("shot: ", name)

func _run() -> void:
	for r in rooms:
		Run.start_run("berserker")
		Run.room_order.assign(["res://rooms/%s.tscn" % r, Run.BOSS_SCENE])
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		await wait(2.5)
		var game := get_tree().current_scene as Game
		var p := game.player
		for en in game.room.alive_enemies():
			en.set_physics_process(false)
		game.hud.visible = false
		# Без интерфейса поверх зала (выбор руны в ларьке, пузыри реплик, обучение)
		for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(cl as CanvasLayer).visible = false
		await wait(0.3)
		await shot("%s_a_vhod" % r)
		# Обзор: высоко над южной стеной, взгляд на центр зала
		p.set_physics_process(false)
		var w: float = (game.room.get_node("Geometry/WallE") as Node3D).position.x
		var dz: float = (game.room.get_node("Geometry/WallS") as Node3D).position.z
		# Под крышей (Room.indoor — длинный дом) — ниже стропил
		var oy := 5.2 if bool(game.room.get("indoor")) else 9.0
		p.global_position = game.room.to_global(Vector3(-w * 0.55, oy, dz - 1.5))
		var to := game.room.to_global(Vector3(0, 0, -2)) - p.get_aim_origin()
		p.rotation_target = Vector2(atan2(to.y, Vector2(to.x, to.z).length()), atan2(-to.x, -to.z))
		await wait(0.4)
		await shot("%s_b_obzor" % r)
	get_tree().quit()
