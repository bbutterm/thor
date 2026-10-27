extends Node
## Diagnostic render comparison. The probe deliberately changes colour and
## roughness; it is not a candidate game material or a visual quality test.
## The old room and N3 share the camera and the same 44 stationary enemies.

const CASES := [
	{"name": "baseline", "old": true, "surfaces": []},
	{"name": "n3_original", "old": false, "surfaces": []},
	{"name": "n3_floor_probe", "old": false, "surfaces": ["floor"]},
	{"name": "n3_skirt_probe", "old": false, "surfaces": ["skirt"]},
	{"name": "n3_ground_probe", "old": false, "surfaces": ["ground"]},
	{"name": "n3_exterior_probe", "old": false, "surfaces": ["skirt", "ground"]},
	{"name": "n3_all_probe", "old": false, "surfaces": ["floor", "skirt", "ground"]},
]
const PATHS := {
	"floor": "Dress/FloorVisual",
	"skirt": "Dress/GroundSkirt",
	"ground": "Dress/Backdrop/Ground",
}
const PARAMS := ["normal_tex", "normal_strength", "tint", "uv_scale", "roughness_base", "overlay_roughness", "blend_sharpness", "vertex_ao"]

var game: Game
var baseline: Room
var out_dir := "user://room_color_probe"
var sample_count := 60
var _targets: Dictionary = {}
var _originals: Dictionary = {}
var _probes: Dictionary = {}
var _failed := false


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
	if args.size() > 1 and args[1].is_valid_int():
		sample_count = maxi(10, int(args[1]))
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	if error != OK:
		push_error("Cannot create screenshot directory: %s (%d)" % [out_dir, error])
		get_tree().quit(1)
		return
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
	if game == null or game.room == null:
		push_error("Failed to load game and room")
		get_tree().quit(1)
		return
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
	var enemy_count := get_tree().get_nodes_in_group("enemies").size()
	if enemy_count != 44:
		push_error("Expected 44 stationary enemies, got %d" % enemy_count)
		get_tree().quit(1)
		return
	get_tree().paused = true
	var shader := load("res://tests/fixtures/surface_color_probe.gdshader") as Shader
	if shader == null:
		push_error("Cannot load diagnostic shader")
		get_tree().quit(1)
		return
	for key in PATHS:
		var node := game.room.get_node_or_null(PATHS[key]) as MeshInstance3D
		if node == null or not (node.material_override is ShaderMaterial):
			push_error("Missing diagnostic surface or shader material: %s" % PATHS[key])
			get_tree().quit(1)
			return
		var original := node.material_override as ShaderMaterial
		var probe := ShaderMaterial.new()
		probe.shader = shader
		for parameter in PARAMS:
			var value: Variant = original.get_shader_parameter(parameter)
			if value != null:
				probe.set_shader_parameter(parameter, value)
		_targets[key] = node
		_originals[key] = original
		_probes[key] = probe
	print("COLOR PROBE: enemies=%d, samples=%d, rounds=2, diagnostic colour differs" % [enemy_count, sample_count])
	# The first pass warms every material before the timed comparison.
	for test_case in CASES:
		await _measure(test_case, "warmup", 15, true)
	# Reverse the order in round 2 to expose timing drift rather than consistently
	# favouring whatever happens to be measured first or last.
	for round_index in 2:
		var order := CASES.duplicate()
		if round_index == 1:
			order.reverse()
		for test_case in order:
			await _measure(test_case, "round_%d" % (round_index + 1), sample_count, false)
	print("COLOR PROBE COMPLETE")
	get_tree().quit(1 if _failed else 0)


func _apply_case(test_case: Dictionary) -> void:
	var old: bool = test_case["old"]
	var replaced: Array = test_case["surfaces"]
	game.room.visible = not old
	baseline.visible = old
	for key in _targets:
		var node := _targets[key] as MeshInstance3D
		node.material_override = _probes[key] if key in replaced else _originals[key]


func _measure(test_case: Dictionary, label: String, count: int, capture: bool) -> void:
	_apply_case(test_case)
	await frames(5)
	if capture and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var error := img.save_png(out_dir.path_join("%s.png" % test_case["name"]))
		if error != OK:
			push_error("Cannot save diagnostic screenshot for %s (%d)" % [test_case["name"], error])
			_failed = true
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
	for value in values:
		total += value
	print("%s %s: avg %.2f ms, median %.2f ms, p95 %.2f ms, draw calls %d, enemies %d" % [test_case["name"], label, total / count, values[count / 2], values[int(count * 0.95)], int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), get_tree().get_nodes_in_group("enemies").size()])
