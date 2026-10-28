extends Node
## A/B одной и той же толпы при движущихся анимациях; ИИ и физика врагов выключены.
## Старый зал/Н3 и исходные/интернированные Skin переключаются в одном процессе.
## Данные Skin исходных ресурсов не меняются, после проверки ссылки восстанавливаются.
const Exp := preload("res://tests/fixtures/skin_intern_experimental.gd")
var game: Game
var baseline: Room
var data: Array = []
var animations: Array[AnimationPlayer] = []
var out_dir := "user://skin_intern_bench"
var all_grunts := false

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
		out_dir = args[0]
	all_grunts = "all_grunts" in args
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(40)
	game = get_tree().current_scene as Game
	game.room.set_physics_process(false)
	game.room._spawn_queue.clear()
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	game.room._alive.clear()
	game.player.input_enabled = false
	game.player.set_physics_process(false)
	await frames(5)
	baseline = (load("res://tests/fixtures/room_01_before_b0.tscn") as PackedScene).instantiate() as Room
	game.level.add_child(baseline)
	baseline.visible = false
	baseline.set_physics_process(false)
	WorldArt.dress_room(baseline, Run.map)
	var c := game.player.global_position
	for i in 44:
		var a := TAU * i / 44.0
		var radius := 5.0 + (i % 4) * 1.5
		var kind := "grunt" if all_grunts or i % 4 == 0 else "fodder"
		var e := game.room.spawn_extra(kind, c + Vector3(cos(a) * radius, 0.05, sin(a) * radius))
		if not e or not e._humanoid:
			push_error("У врага отсутствует ожидаемая модель")
			get_tree().quit(1)
			return
		e.health = 1e6
		e.max_health = 1e6
		e.set_physics_process(false)
		e.reparent(game, true)
		var humanoid := e._humanoid
		if not humanoid.play("Zombie_Walk_Fwd_Loop", 0.0, 1.0):
			push_error("Не найдена анимация ходьбы")
			get_tree().quit(1)
			return
		var ap := humanoid.anim
		var walking := ap.get_animation(ap.current_animation)
		walking.loop_mode = Animation.LOOP_LINEAR
		animations.append(ap)
		var records := Exp.snapshot(humanoid.skeleton)
		var stats: Dictionary = Exp.intern(records)
		for rec in records:
			rec.optimized = (rec.mesh as MeshInstance3D).skin
		if not Exp.same_content(records):
			push_error("Содержимое Skin/меша изменилось при интернировании")
			get_tree().quit(1)
			return
		Exp.restore(records)
		data.append({"records": records, "kind": kind, "before": stats.old_unique,
			"after": stats.new_unique, "changed": stats.changed_meshes})
		await get_tree().process_frame
	await frames(25)
	_print_counts()
	await _measure(true, false, "OLD ORIGINAL WARMUP", 15)
	await _measure(false, false, "N3 ORIGINAL WARMUP", 15)
	await _measure(false, true, "N3 INTERNED WARMUP", 15)
	for iteration in 3:
		await _measure(true, false, "OLD ORIGINAL %d" % (iteration + 1), 45)
		await _measure(false, false, "N3 ORIGINAL %dA" % (iteration + 1), 45)
		await _measure(false, true, "N3 INTERNED %d" % (iteration + 1), 45)
		await _measure(false, false, "N3 ORIGINAL %dB" % (iteration + 1), 45)
	await _capture_views()
	_select(false)
	for group in data:
		if not Exp.same_content(group.records):
			push_error("После восстановления Skin содержимое изменилось")
			get_tree().quit(1)
			return
	print("SKIN INTERN BENCH COMPLETE")
	get_tree().paused = false
	get_tree().quit(0)

func _print_counts() -> void:
	for kind in ["grunt", "fodder"]:
		var n := 0
		var before := 0
		var after := 0
		var changed := 0
		for group in data:
			if group.kind == kind:
				n += 1
				before += int(group.before)
				after += int(group.after)
				changed += int(group.changed)
		print("SKIN COUNT kind=%s enemies=%d distinct_before=%d distinct_after=%d changed_meshes=%d" % [kind, n, before, after, changed])
	print("ENEMIES: ", get_tree().get_nodes_in_group("enemies").size())

func _select(optimized: bool) -> void:
	for group in data:
		for rec in group.records:
			var mesh: MeshInstance3D = rec.mesh
			mesh.skin = rec.optimized if optimized else rec.skin

func _measure(old: bool, optimized: bool, label: String, count: int) -> void:
	_select(optimized)
	game.room.visible = not old
	baseline.visible = old
	for ap in animations:
		ap.seek(0.15, true)
	await frames(10)
	var values := PackedFloat32Array()
	var before := Time.get_ticks_usec()
	for i in count:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		values.append((now - before) / 1000.0)
		before = now
	values.sort()
	var total := 0.0
	for x in values:
		total += x
	print("%s: avg %.2f ms, median %.2f ms, p95 %.2f ms, draw calls %d, enemies %d" % [label, total / count, values[count / 2], values[int(count * 0.95)], int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), get_tree().get_nodes_in_group("enemies").size()])

func _capture_views() -> void:
	if DisplayServer.get_name() == "headless":
		return
	get_tree().paused = true
	game.room.visible = true
	baseline.visible = false
	var old_yaw := game.player.rotation.y
	for sample in [0.15, 0.50]:
		for ap in animations:
			ap.seek(sample, true)
		for view in 4:
			game.player.rotation.y = old_yaw + TAU * float(view) / 4.0
			for optimized in [false, true]:
				_select(optimized)
				await frames(5)
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				img.save_png(out_dir.path_join("pose_%d_view_%d_interned_%d.png" % [int(sample * 100), view, int(optimized)]))
	game.player.rotation.y = old_yaw
	get_tree().paused = false
