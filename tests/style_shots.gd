extends Node
## Кадры шкалы стиля «ДОСТОЙНО!» (блок Б3): HUD на каждом ранге (кадр целиком и крупно низ экрана),
## «удар» подписи и слово комикса при повышении, высший ранг — берсерк. Второй аргумент — язык (`en`).
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/style_shots.tscn -- <папка> [en]

var out_dir := "user://style_shots"
var game: Game

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

## Кадр целиком и вырезка низа по центру (шкала с подписью) ×2
func shot(name: String, crop: bool = true) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	if crop:
		var sz := img.get_size()
		var w := int(sz.x * 0.36)
		var h := int(sz.y * 0.24)
		var part := img.get_region(Rect2i((sz.x - w) / 2, sz.y - h, w, h))
		part.resize(w * 2, h * 2, Image.INTERPOLATE_LANCZOS)
		part.save_png(out_dir.path_join(name + "_hud.png"))
	print("shot: ", name)

func _run() -> void:
	Run.start_run("hunter")
	Run.room_order.assign(["res://rooms/room_02.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(2.0)
	game = get_tree().current_scene as Game
	var p := game.player
	game.room.set_physics_process(false)
	for en in game.room.alive_enemies():
		en.set_physics_process(false)
	game.tracker.idle_time = 1.0e6
	var s := p.style
	s.set_physics_process(false)  # без утечки — кадр ровно на нужном числе очков
	var t := s.tuning
	# Каждый ранг: середина ранга
	for r in StyleMeter.TOP:
		s.reset()
		var lo := t.rank_points[r]
		var hi := t.rank_points[r + 1]
		s.set_points(lo + (hi - lo) * 0.55)
		await wait(0.6)  # «удар» подписи затих
		await shot("%02d_rank_%d" % [r + 1, r])
	# Повышение: «удар» подписи, потом слово комикса над залом
	s.reset()
	s.set_points(t.rank_points[2] + 3.0)
	await wait(0.6)
	s.set_physics_process(true)
	s.reset_cooldowns()
	s.add_points(t.rank_points[3] - s.points + 4.0)
	await wait(0.05)
	await shot("05_rankup_punch")
	await wait(t.rank_pop_delay + 0.05)
	await shot("06_rankup_comic_word")
	s.set_physics_process(false)
	await wait(1.0)
	# Высший ранг — берсерк, крупное слово
	s.set_physics_process(true)
	s.start_berserk()
	await wait(0.25)
	await shot("07_top_rank_berserk")
	await wait(2.0)
	await shot("08_berserk_timer")
	get_tree().quit(0)
