extends Node
## Проверка ненарушенной фоновой загрузки с настоящим GL Compatibility (не --headless).

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
	print("=== ASSET CACHE GL TEST ===")
	check(DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "gl_compatibility", "настоящий GL Compatibility, не Dummy-рендерер")
	check("sync_load" not in OS.get_cmdline_user_args(), "обычный режим, без sync_load")
	check(AssetCache._started and AssetCache._pending.size() > 0, "фоновая загрузка действительно запущена: %d запросов" % AssetCache._pending.size())
	AssetCache.finish()
	check(AssetCache.is_finished() and AssetCache._pending.is_empty(), "фоновые запросы дождались завершения")
	var path := "res://props/barrel.tscn"
	var scene := AssetCache._held.get(path) as PackedScene
	check(scene != null, "сцена бочки загружена")
	if scene:
		var prop := scene.instantiate() as Destructible
		var model := prop.get_node_or_null("Model") if prop else null
		var meshes := model.find_children("*", "MeshInstance3D", true, false) if model else []
		var vertices := 0
		for node in meshes:
			var mesh := (node as MeshInstance3D).mesh
			if mesh:
				for surface in mesh.get_surface_count():
					var arrays := mesh.surface_get_arrays(surface)
					if arrays.size() == Mesh.ARRAY_MAX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
						vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		check(vertices > 0, "данные поверхностей бочки читаются после фоновой загрузки (%d вершин)" % vertices)
		if prop:
			prop.free()
	print("RESULT: %d OK / %d FAIL" % [_passes, _fails.size()])
	for f in _fails:
		print("  FAIL: ", f)
	get_tree().quit(1 if not _fails.is_empty() else 0)
