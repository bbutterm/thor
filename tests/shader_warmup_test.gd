extends Node
## Проверка состава образцов без рендера: настоящие варианты новых залов и материал пыли.
## Компиляции графики в headless не измеряются; для этого есть warmup_probe.tscn.

var _passes := 0
var _fails := 0
var _formats: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	if ok:
		_passes += 1
		print("  [OK] ", what)
	else:
		_fails += 1
		print("  [FAIL] ", what)

func mesh_of(gi: GeometryInstance3D) -> Mesh:
	if gi is MeshInstance3D:
		return (gi as MeshInstance3D).mesh
	if gi is MultiMeshInstance3D:
		var mm := (gi as MultiMeshInstance3D).multimesh
		return mm.mesh if mm else null
	return null

func material_of(gi: GeometryInstance3D, mesh: Mesh, surface: int) -> Material:
	if gi.material_override:
		return gi.material_override
	if gi is MeshInstance3D:
		var override := (gi as MeshInstance3D).get_surface_override_material(surface)
		if override:
			return override
	return mesh.surface_get_material(surface)

## Независимо читаем фактические формат и тип поверхности для ArrayMesh и PrimitiveMesh.
func surface_format(mesh: Mesh, surface: int) -> String:
	var key := "%d:%d" % [mesh.get_instance_id(), surface]
	if _formats.has(key):
		return str(_formats[key])
	var result := ""
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		result = "%d:%d" % [am.surface_get_format(surface), am.surface_get_primitive_type(surface)]
	else:
		var data := RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
		result = "%d:%d" % [int(data["format"]), int(data["primitive"])] if data.has("format") and data.has("primitive") else "unknown:" + key
	_formats[key] = result
	return result

## Сравниваем независимо от группировки в RoomDress: исходные материалы и форматы
## должны быть представлены видимым образцом той же разновидности геометрии.
func covered(source: GeometryInstance3D, samples: Node3D) -> bool:
	if source == null or samples == null:
		return false
	var original := mesh_of(source)
	if original == null:
		return false
	for node in samples.get_children():
		var candidate := node as GeometryInstance3D
		if candidate == null or not candidate.visible or (source is MeshInstance3D) != (candidate is MeshInstance3D):
			continue
		var mesh := mesh_of(candidate)
		if mesh == null or mesh.get_surface_count() != original.get_surface_count():
			continue
		if source.material_overlay != candidate.material_overlay or source.cast_shadow != candidate.cast_shadow \
				or source.gi_mode != candidate.gi_mode or source.layers != candidate.layers \
				or not is_equal_approx(source.transparency, candidate.transparency):
			continue
		if source is MultiMeshInstance3D:
			var a := (source as MultiMeshInstance3D).multimesh
			var b := (candidate as MultiMeshInstance3D).multimesh
			if not a or not b or b.instance_count != 1 or a.use_colors != b.use_colors or a.use_custom_data != b.use_custom_data:
				continue
		var same := true
		for i in mesh.get_surface_count():
			if surface_format(mesh, i) != surface_format(original, i) \
					or material_of(source, original, i) != material_of(candidate, mesh, i):
				same = false
				break
		if same:
			return true
	return false

func missing_room_variants(room: Node3D, samples: Node3D) -> PackedStringArray:
	var missing := PackedStringArray()
	for root_name in ["Geometry", "Dress"]:
		var root := room.get_node_or_null(root_name)
		if root == null:
			continue
		for node in root.find_children("*", "GeometryInstance3D", true, false):
			var gi := node as GeometryInstance3D
			var mesh := mesh_of(gi)
			if mesh and mesh.get_surface_count() > 0 and not covered(gi, samples):
				missing.append(str(room.get_path_to(gi)))
	return missing

func _run() -> void:
	print("=== SHADER WARMUP TEST ===")
	var parent := Node3D.new()
	add_child(parent)
	var world := Node3D.new()
	parent.add_child(world)
	WorldArt.warmup(world, Vector3(0, 0, -3.2), Vector3.RIGHT)
	var dust := world.get_node_or_null("Warm_dust") as CPUParticles3D
	check(dust != null and dust.visible and dust.emitting and dust.preprocess > 0.0
			and dust.material_override == WorldArt.material("dust", "particle_add"),
			"пылинки представлены видимым действующим образцом с настоящим материалом")
	world.free()
	# Два BoxMesh с одним материалом, но разными каналами вершин: нельзя склеить их
	# в один образец только потому, что это один тип меша и материал совпадает.
	var fixture := Node3D.new()
	var geometry := Node3D.new()
	geometry.name = "Geometry"
	fixture.add_child(geometry)
	var material := StandardMaterial3D.new()
	var plain := BoxMesh.new()
	var with_uv2 := BoxMesh.new()
	with_uv2.add_uv2 = true
	var plain_node := MeshInstance3D.new()
	plain_node.mesh = plain
	plain_node.material_override = material
	geometry.add_child(plain_node)
	var uv2_node := MeshInstance3D.new()
	uv2_node.mesh = with_uv2
	uv2_node.material_override = material
	geometry.add_child(uv2_node)
	parent.add_child(fixture)
	var variants := RoomDress.warmup_room(parent, fixture)
	var plain_format := surface_format(plain, 0)
	var uv2_format := surface_format(with_uv2, 0)
	check(not plain_format.begins_with("unknown:") and not uv2_format.begins_with("unknown:") and plain_format != uv2_format,
			"BoxMesh с UV2 отличается форматом от обычного")
	check(variants.get_child_count() == 2 and covered(plain_node, variants) and covered(uv2_node, variants),
			"меши одного материала с разными форматами прогреваются отдельно")
	variants.free()
	fixture.free()
	var total_samples := 0
	for number in range(1, 10):
		var path := "res://rooms/room_%02d.tscn" % number
		var packed := load(path) as PackedScene
		if packed == null:
			check(false, "%s загружается" % path)
			continue
		var room := packed.instantiate() as Node3D
		room.process_mode = Node.PROCESS_MODE_DISABLED
		parent.add_child(room)
		var samples := RoomDress.warmup_room(parent, room)
		total_samples += samples.get_child_count()
		var backdrop := room.get_node_or_null("Dress/Backdrop")
		var ground := backdrop.get_node_or_null("Ground") as GeometryInstance3D if backdrop else null
		var water := backdrop.get_node_or_null("Water") as GeometryInstance3D if backdrop else null
		var pines := backdrop.find_children("Pine_*", "MultiMeshInstance3D", true, false) if backdrop else []
		var pine := pines[0] as GeometryInstance3D if not pines.is_empty() else null
		check(covered(ground, samples) and covered(water, samples) and covered(pine, samples),
				"зал %d: настоящие материалы и форматы земли, воды и сосен покрыты" % number)
		var missing := missing_room_variants(room, samples)
		check(missing.is_empty(), "зал %d: покрыты все варианты Geometry/Dress (пропущено: %s)" % [number, str(missing.slice(0, 4))])
		check(samples.get_child_count() > 0 and samples.get_child_count() <= 100,
				"зал %d: повторяющиеся варианты объединены (%d образцов)" % [number, samples.get_child_count()])
		if number == 1 and water:
			var saved := water.material_override
			water.material_override = StandardMaterial3D.new()
			check(not covered(water, samples), "проверка обнаруживает непрогретый материал")
			water.material_override = saved
			var saved_overlay := water.material_overlay
			water.material_overlay = Outline.material()
			check(not covered(water, samples), "проверка различает вариант с обводкой")
			var outlined := RoomDress.warmup_room(parent, room)
			check(covered(water, outlined), "образец сохраняет настоящую обводку")
			outlined.free()
			water.material_overlay = saved_overlay
		var ship := backdrop.get_node_or_null("Ship_Large_0") if backdrop else null
		var ship_meshes := ship.find_children("*", "MeshInstance3D", true, false) if ship else []
		var ship_mesh: GeometryInstance3D = null
		for n in ship_meshes:
			if mesh_of(n as GeometryInstance3D):
				ship_mesh = n as GeometryInstance3D
				break
		check(covered(ship_mesh, samples), "зал %d: материал и формат дальнего корабля покрыты" % number)
		samples.free()
		room.free()
	for path in ["res://rooms/sven_arena.tscn", "res://rooms/boss_arena.tscn"]:
		var packed := load(path) as PackedScene
		if packed == null:
			check(false, "%s загружается" % path)
			continue
		var room := packed.instantiate() as Node3D
		room.process_mode = Node.PROCESS_MODE_DISABLED
		parent.add_child(room)
		var samples := RoomDress.warmup_room(parent, room)
		total_samples += samples.get_child_count()
		var missing := missing_room_variants(room, samples)
		check(missing.is_empty(), "%s: покрыты все варианты Geometry/Dress (пропущено: %s)" % [path.get_file(), str(missing.slice(0, 4))])
		check(samples.get_child_count() > 0 and samples.get_child_count() <= 100,
				"%s: повторяющиеся варианты объединены (%d образцов)" % [path.get_file(), samples.get_child_count()])
		samples.free()
		room.free()
	parent.free()
	print("Всего временных образцов в девяти залах и двух аренах: ", total_samples)
	print("=== ИТОГ SHADER WARMUP: %d OK, %d FAIL ===" % [_passes, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
