extends Node
## Временный стенд: те же треугольники GroundSkirt, сгруппированные по одной полосе
## либо по одному треугольнику. Никаких изменений игровых ресурсов и материалов.
## Одна и та же камера, окружение и 44 неподвижных врага; это не реальный бой.
var game: Game
var baseline: Room
var out_dir := "user://skirt_optimization"
var original: MeshInstance3D
var variants: Array[Node3D] = []

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
		var e := game.room.spawn_extra("grunt" if i % 4 == 0 else "fodder", c + Vector3(cos(a) * radius, 0.05, sin(a) * radius))
		if e:
			e.health = 1e6
			e.max_health = 1e6
			e.set_physics_process(false)
			e.reparent(game, true)
		await get_tree().process_frame
	await frames(25)
	get_tree().paused = true
	original = game.room.get_node("Dress/GroundSkirt") as MeshInstance3D
	if original == null or original.mesh == null or original.mesh.get_surface_count() != 1:
		push_error("У GroundSkirt ожидалась одна поверхность")
		get_tree().quit(1)
		return
	var arrays := original.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents := PackedFloat32Array()
	if arrays[Mesh.ARRAY_TANGENT] != null:
		tangents = arrays[Mesh.ARRAY_TANGENT]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	else:
		for i in vertices.size():
			indices.append(i)
	if indices.size() != 36 or normals.size() != vertices.size() or colors.size() != vertices.size() or uvs.size() != vertices.size() or (not tangents.is_empty() and tangents.size() != vertices.size() * 4):
		push_error("Формат GroundSkirt изменился; сравнение остановлено")
		get_tree().quit(1)
		return
	variants.append(_split(arrays, indices, 6)) # 6 исходных полос, по два треугольника
	variants.append(_split(arrays, indices, 3)) # 12 исходных треугольников
	print("ВРАГОВ: ", get_tree().get_nodes_in_group("enemies").size())
	print("GROUND SKIRT: 12 triangles, variants=%d/%d pieces" % [variants[0].get_child_count(), variants[1].get_child_count()])
	await _measure(true, "СТАРЫЙ ПРОГРЕВ", 15)
	await _skirt_measure(-1, "ОРИГИНАЛ ПРОГРЕВ", 15)
	await _skirt_measure(0, "ПОЛОСЫ ПРОГРЕВ", 15)
	await _skirt_measure(1, "ТРЕУГОЛЬНИКИ ПРОГРЕВ", 15)
	for round_index in 2:
		await _measure(true, "СТАРЫЙ %d" % (round_index + 1), 45)
		await _skirt_measure(-1, "ОРИГИНАЛ %d" % (round_index + 1), 45)
		await _skirt_measure(0, "ПОЛОСЫ %d" % (round_index + 1), 45)
		await _skirt_measure(1, "ТРЕУГОЛЬНИКИ %d" % (round_index + 1), 45)
	await _capture_views()
	print("ИТОГ BENCH")
	get_tree().quit(0)

func _split(arrays: Array, indices: PackedInt32Array, group_size: int) -> Node3D:
	var parent := Node3D.new()
	parent.name = "ExperimentalSkirt%d" % group_size
	parent.visible = false
	original.get_parent().add_child(parent)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents := PackedFloat32Array()
	if arrays[Mesh.ARRAY_TANGENT] != null:
		tangents = arrays[Mesh.ARRAY_TANGENT]
	for start in range(0, indices.size(), group_size):
		var vs := PackedVector3Array()
		var ns := PackedVector3Array()
		var cs := PackedColorArray()
		var ts := PackedVector2Array()
		var tangents_out := PackedFloat32Array()
		for offset in range(start, start + group_size):
			var index := indices[offset]
			vs.append(vertices[index])
			ns.append(normals[index])
			cs.append(colors[index])
			ts.append(uvs[index])
			if not tangents.is_empty():
				tangents_out.append_array(tangents.slice(index * 4, index * 4 + 4))
		var split_arrays := []
		split_arrays.resize(Mesh.ARRAY_MAX)
		split_arrays[Mesh.ARRAY_VERTEX] = vs
		split_arrays[Mesh.ARRAY_NORMAL] = ns
		split_arrays[Mesh.ARRAY_COLOR] = cs
		split_arrays[Mesh.ARRAY_TEX_UV] = ts
		if not tangents_out.is_empty():
			split_arrays[Mesh.ARRAY_TANGENT] = tangents_out
		var split_mesh := ArrayMesh.new()
		split_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, split_arrays)
		var piece := original.duplicate() as MeshInstance3D
		piece.name = "Piece%d" % start
		piece.mesh = split_mesh
		piece.visible = true
		parent.add_child(piece)
	return parent

func _select(index: int) -> void:
	original.visible = index == -1
	for j in variants.size():
		variants[j].visible = j == index

func _measure(old: bool, label: String, count: int) -> void:
	game.room.visible = not old
	baseline.visible = old
	await frames(5)
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

func _skirt_measure(index: int, label: String, count: int) -> void:
	_select(index)
	await _measure(false, label, count)

func _capture_views() -> void:
	if DisplayServer.get_name() == "headless":
		return
	game.room.visible = true
	baseline.visible = false
	var old_yaw := game.player.rotation.y
	for view in 4:
		game.player.rotation.y = old_yaw + TAU * float(view) / 4.0
		for index in [-1, 0, 1]:
			_select(index)
			await frames(5)
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png(out_dir.path_join("view_%d_variant_%d.png" % [view, index]))
	game.player.rotation.y = old_yaw
