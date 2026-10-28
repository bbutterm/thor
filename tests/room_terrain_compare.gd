extends Node
## Сравнение стоимости рендера первого зала до Б0 и после Н3: одна камера и одинаковые
## 44 неподвижных врага. Исключает ИИ/падения и предназначено для сравнения графики,
## а не для оценки FPS реального боя. См. docs/report_open_rooms/performance.md.
var game: Game
var baseline: Room
var out_dir := "user://room_optimization"
var _ground: MeshInstance3D
var _original: Mesh
var _clipped: Mesh

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
	_ground = game.room.get_node("Dress/Backdrop/Ground") as MeshInstance3D
	_original = _ground.mesh
	_clipped = _clip_mesh(_original)
	print("ВЕРШИНЫ: до %d, после %d" % [_original.surface_get_array_len(0), _clipped.surface_get_array_len(0)])
	print("ВРАГОВ: ", get_tree().get_nodes_in_group("enemies").size())
	await _measure(true, "СТАРЫЙ ПРОГРЕВ", 15)
	await _ground_measure(false, "ЗЕМЛЯ ОРИГИНАЛ ПРОГРЕВ", 15)
	await _ground_measure(true, "ЗЕМЛЯ ОБРЕЗКА ПРОГРЕВ", 15)
	for round_index in 2:
		await _measure(true, "СТАРЫЙ %d" % (round_index + 1), 60)
		await _ground_measure(false, "ЗЕМЛЯ ОРИГИНАЛ %d" % (round_index + 1), 60)
		await _ground_measure(true, "ЗЕМЛЯ ОБРЕЗКА %d" % (round_index + 1), 60)
	print("ИТОГ BENCH")
	get_tree().quit(0)

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


func _ground_measure(clipped: bool, label: String, count: int) -> void:
	_ground.mesh = _clipped if clipped else _original
	if "ПРОГРЕВ" in label and DisplayServer.get_name() != "headless":
		game.room.visible = true
		baseline.visible = false
		await frames(4)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join("terrain_%s.png" % ("clipped" if clipped else "original")))
	await _measure(false, label, count)


# Split each source triangle at the sides of the square covered by GroundSkirt.
# Keep the outside pieces and linearly interpolate all original vertex attributes.
func _clip_mesh(source: Mesh) -> ArrayMesh:
	var a := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = a[Mesh.ARRAY_TANGENT]
	var colors: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var points := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_tangents := PackedFloat32Array()
	var out_colors := PackedColorArray()
	var out_uvs := PackedVector2Array()
	var original_area := 0.0
	var remaining_area := 0.0
	for i in range(0, vertices.size(), 3):
		var polygon: Array = []
		for j in range(i, i + 3):
			polygon.append({"p": vertices[j], "n": normals[j], "t": tangents.slice(j * 4, j * 4 + 4), "c": colors[j], "uv": uvs[j]})
		original_area += _area(polygon[0].p, polygon[1].p, polygon[2].p)
		for plane in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var split := _split_polygon(polygon, plane)
			var outside: Array = split[0]
			for k in range(1, outside.size() - 1):
				var tri := [outside[0], outside[k], outside[k + 1]]
				var area := _area(tri[0].p, tri[1].p, tri[2].p)
				if area < 0.000001:
					continue
				remaining_area += area
				for v in tri:
					points.append(v.p)
					out_normals.append(v.n)
					out_tangents.append_array(v.t)
					out_colors.append(v.c)
					out_uvs.append(v.uv)
			polygon = split[1]
			if polygon.is_empty():
				break
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = points
	out[Mesh.ARRAY_NORMAL] = out_normals
	out[Mesh.ARRAY_TANGENT] = out_tangents
	out[Mesh.ARRAY_COLOR] = out_colors
	out[Mesh.ARRAY_TEX_UV] = out_uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	print("ПЛОЩАДЬ XZ: до %.2f м², после %.2f м², удалено %.2f м²" % [original_area, remaining_area, original_area - remaining_area])
	return mesh


func _area(a: Vector3, b: Vector3, c: Vector3) -> float:
	return absf((b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)) * 0.5


func _split_polygon(polygon: Array, normal: Vector3) -> Array:
	var outside: Array = []
	var inside: Array = []
	if polygon.is_empty():
		return [outside, inside]
	var previous: Dictionary = polygon.back()
	var previous_distance: float = previous.p.dot(normal) - 30.0
	for current: Dictionary in polygon:
		var distance: float = current.p.dot(normal) - 30.0
		if (distance > 0.0) != (previous_distance > 0.0):
			var amount := previous_distance / (previous_distance - distance)
			var intersection := _lerp_vertex(previous, current, amount)
			outside.append(intersection)
			inside.append(intersection)
		if distance > 0.0:
			outside.append(current)
		else:
			inside.append(current)
		previous = current
		previous_distance = distance
	return [outside, inside]


func _lerp_vertex(a: Dictionary, b: Dictionary, amount: float) -> Dictionary:
	var tangent := PackedFloat32Array()
	for i in 4:
		tangent.append(lerpf(a.t[i], b.t[i], amount))
	return {"p": a.p.lerp(b.p, amount), "n": a.n.lerp(b.n, amount), "t": tangent, "c": a.c.lerp(b.c, amount), "uv": a.uv.lerp(b.uv, amount)}
