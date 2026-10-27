extends Node
## Проверка фактической геометрии трёх разрушаемых пропсов в штатной headless-загрузке.
## Запуск без пользовательских аргументов: godot --headless --path . --fixed-fps 60 res://tests/headless_assets_test.tscn

var _fails: Array[String] = []
var _passes := 0

func check(ok: bool, text: String) -> void:
	if ok:
		_passes += 1
		print("  [OK] ", text)
	else:
		_fails.append(text)
		print("  [FAIL] ", text)

func _ready() -> void:
	print("=== HEADLESS ASSETS TEST ===")
	check(DisplayServer.get_name() == "headless", "тест запущен с Dummy-рендерером")
	check(AssetCache._started and AssetCache._pending.is_empty(), "в headless основные ресурсы загружены без фоновых запросов")
	AssetCache.finish()
	for path in ["res://props/barrel.tscn", "res://props/crate.tscn", "res://props/barrel_explosive.tscn"]:
		_test_prop(path)
	# Тест держал созданные меши только для проверки; освобождаем их до завершения движка.
	PropDebris._pieces.clear()
	print("RESULT: %d OK / %d FAIL" % [_passes, _fails.size()])
	for failure in _fails:
		print("  FAIL: ", failure)
	get_tree().quit(1 if not _fails.is_empty() else 0)

func _test_prop(path: String) -> void:
	var scene := load(path) as PackedScene
	check(scene != null and AssetCache._held.get(path) != null, "%s — загруженная сцена" % path)
	if scene == null:
		return
	var prop := scene.instantiate() as Destructible
	check(prop != null, "%s — разрушаемый пропс" % path)
	if prop == null:
		return
	var model := prop.get_node_or_null("Model")
	check(model != null, "%s — модель" % path)
	if model == null:
		prop.free()
		return
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	var surfaces := 0
	var vertices := 0
	var valid := true
	for node in meshes:
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			surfaces += 1
			var arrays := mesh.surface_get_arrays(surface)
			if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				valid = false
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			vertices += verts.size()
			if verts.is_empty():
				valid = false
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			if indices is PackedInt32Array:
				for index in indices:
					if index < 0 or index >= verts.size():
						valid = false
	check(valid and surfaces > 0 and vertices > 0, "%s — %d поверхностей, %d вершин и допустимые индексы" % [path, surfaces, vertices])
	if valid and surfaces > 0 and vertices > 0:
		var pieces := PropDebris.pieces_for(prop, prop.debris_mode, prop.debris_sectors)
		var all_pieces_valid := not pieces.is_empty()
		for piece in pieces:
			var part := piece.get("mesh") as ArrayMesh
			if part == null or part.get_surface_count() == 0:
				all_pieces_valid = false
				continue
			for surface in part.get_surface_count():
				var arrays := part.surface_get_arrays(surface)
				if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
					all_pieces_valid = false
		check(all_pieces_valid, "%s — %d непустых мешей обломков" % [path, pieces.size()])
		var cached := PropDebris.pieces_for(prop, prop.debris_mode, prop.debris_sectors)
		check(not cached.is_empty() and cached[0].mesh == pieces[0].mesh, "%s — меши обломков повторно используются" % path)
	prop.free()
