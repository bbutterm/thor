extends Node
## Кадры залов: вид от входа и обзор сверху (для проверки планировок глазами).
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/room_shots.tscn -- <папка> [room_07 room_08 …] [old]

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
	# «old» среди залов — старые текстуры (партия 10.1, как F6 в «Быстрой проверке»)
	if "old" in rooms:
		rooms.erase("old")
		QuickTextures.apply(true)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("shot: %s, draw calls: %d, visible objects: %d" % [name,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])

func _run() -> void:
	for r in rooms:
		seed(20261028)
		Run.start_run("berserker")
		Run.room_order.assign(["res://rooms/%s.tscn" % r, Run.BOSS_SCENE])
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		# Для парных кадров крепости достаточно нескольких кадров подготовки;
		# это не превращает съёмку в долгий прогон программного рендера.
		await wait(0.2 if r == "room_10" else 2.5)
		var game := get_tree().current_scene as Game
		var p := game.player
		if r == "room_10":
			# Одинаковые неподвижные силуэты в обеих сериях позволяют оценить
			# читаемость врагов на фоне, не завися от очереди появления волны.
			game.room._player = p
			for sample in [["fodder", Vector3(-2.2, 0, 1.5)], ["grunt", Vector3(2.0, 0, -0.5)]]:
				var en := game.room.spawn_extra(sample[0], game.room.to_global(sample[1]))
				if en:
					en._set_state(Enemy.State.CHASE)
					if en._humanoid:
						en._humanoid.play(en.anim_idle, 0.0)
		for en in game.room.alive_enemies():
			en.set_physics_process(false)
		if r == "room_10":
			if p.is_dead or not p.input_enabled:
				push_error("room_10: игрок не готов к съёмке")
				get_tree().quit(1)
				return
			# В кадр не добавляются новые враги; физика тел остаётся в пространстве.
			game.room.set_physics_process(false)
			p.set_physics_process(false)
			p.velocity = Vector3.ZERO
			var spawn := game.room.get_spawn_transform()
			p.global_position = spawn.origin
			p.rotation_target = Vector2(0.0, spawn.basis.get_euler().y)
		game.hud.visible = false
		# Без интерфейса поверх зала (выбор руны в ларьке, пузыри реплик, обучение)
		for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(cl as CanvasLayer).visible = false
		await wait(0.05 if r == "room_10" else 0.3)
		await shot("%s_a_vhod" % r)
		# Обзор: высоко над южной стеной, взгляд на центр зала
		p.set_physics_process(false)
		if r == "room_10":
			var viewmodel := p.get_node("Head/Camera/ViewmodelContainer") as CanvasItem
			# С северо-востока обзор охватывает верхний помост и подход к вышке.
			viewmodel.visible = false
			await view_at(game, Vector3(13, 14, -13), Vector3(0, 2, 0), "room_10_b_obzor")
			viewmodel.visible = true
			await view_at(game, Vector3(-9, 1.6, 12), Vector3(-7.6, 3.1, 0), "room_10_c_podyom")
			await view_at(game, Vector3(-6.5, 8.35, 10), Vector3(0, 0, -1), "room_10_d_pryzhok")
		else:
			var w: float = (game.room.get_node("Geometry/WallE") as Node3D).position.x
			var dz: float = (game.room.get_node("Geometry/WallS") as Node3D).position.z
			# Под крышей (Room.indoor — длинный дом) — ниже стропил
			var indoor := bool(game.room.get("indoor"))
			p.global_position = game.room.to_global(Vector3(0.0 if indoor else -w * 0.55, 4.0 if indoor else 9.0, dz - 1.5))
			var to := game.room.to_global(Vector3(0, 0, -2)) - p.get_aim_origin()
			p.rotation_target = Vector2(atan2(to.y, Vector2(to.x, to.z).length()), atan2(-to.x, -to.z))
			await wait(0.4)
			await shot("%s_b_obzor" % r)
	get_tree().quit()

func view_at(game: Game, eye_local: Vector3, target_local: Vector3, name: String) -> void:
	var p := game.player
	p.velocity = Vector3.ZERO
	# Параметр eye_local — положение камеры, а не нижней точки тела игрока.
	p.global_position += game.room.to_global(eye_local) - p.get_aim_origin()
	var d := game.room.to_global(target_local) - p.get_aim_origin()
	if d.length_squared() < 0.001:
		push_error("Нулевая длина направления камеры: " + name)
		return
	p.rotation_target = Vector2(atan2(d.y, Vector2(d.x, d.z).length()), atan2(-d.x, -d.z))
	await wait(0.05)
	await shot(name)
