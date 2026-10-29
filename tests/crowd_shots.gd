extends Node
## Кадры «толпа издалека» (партия 12, враги различимы по роли): по 1–3 врага каждой роли на 12–16 м,
## сначала новое, потом старое (F6, FeelSwitch enemy_roles).
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/crowd_shots.tscn -- <папка>

var out_dir := "user://crowd_shots"

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

func _crowd(game: Game) -> Array:
	var out: Array = []
	var p := game.player
	var fwd := -p.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var row := ["fodder", "fodder", "fodder", "grunt", "grunt", "shieldbearer", "shaman", "thrower", "merc", "fodder", "grunt"]
	for i in row.size():
		var pos := p.global_position + fwd * (6.0 + (i % 3) * 1.6) + right * ((i - row.size() / 2.0) * 1.0)
		var e := game.room.spawn_extra(row[i], pos)
		if e:
			out.append(e)
	await wait(1.2)
	for e in out:
		if is_instance_valid(e):
			(e as Enemy).set_physics_process(false)
			(e as Enemy).rotation.y = p.rotation.y
	var tints := []
	for e in out:
		if is_instance_valid(e) and (e as Enemy)._humanoid:
			tints.append("%s:%s" % [(e as Enemy).kind, (e as Enemy)._humanoid.cloth_tint.to_html(false)])
	print("в кадре врагов: %d, роли %s, %s" % [out.size(), Enemy.roles_on(), " ".join(tints)])
	return out

func _run() -> void:
	for mode in ["new", "old"]:
		FeelSwitch.set_old(&"enemy_roles", mode == "old")
		Run.start_run("berserker")
		Run.room_order.assign(["res://rooms/room_06.tscn", Run.BOSS_SCENE])
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		await wait(2.0)
		var game := get_tree().current_scene as Game
		game.room.set_physics_process(false)
		game.room._spawn_queue.clear()
		for e in game.room.alive_enemies().duplicate():
			e.queue_free()
		game.room._alive.clear()
		await wait(0.2)
		for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(cl as CanvasLayer).visible = false
		await _crowd(game)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("crowd_%s.png" % mode))
	FeelSwitch.set_old(&"enemy_roles", false)
	get_tree().quit()
