extends Node
## Сравнение фонового и синхронного чтения сцен залов при создании ресурсов Dummy.
## Запуск: --headless res://tests/room_prefetch_rid_stress.tscn -- threaded|sync

func _ready() -> void:
	AssetCache.finish()
	var threaded := "threaded" in OS.get_cmdline_user_args()
	var paths := PackedStringArray(Run.ROOM_SCENES)
	paths.append(Run.BOSS_SCENE)
	paths.append("res://rooms/sven_arena.tscn")
	paths.append("res://rooms/shop_room.tscn")
	var loaded: Array[Resource] = []
	var requests := 0
	for path in paths:
		if threaded:
			if ResourceLoader.load_threaded_request(path, "", true) == OK:
				requests += 1
		else:
			loaded.append(load(path))
	var active := 0
	if threaded:
		for path in paths:
			if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				active += 1
	print("ROOM PREFETCH: mode=%s requests=%d active=%d" % ["threaded" if threaded else "sync", requests, active])
	var survivors: Array[Node] = []
	for i in 8000:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.0 + (i % 7) * 0.1, 1.0, 1.0)
		var item := MeshInstance3D.new()
		item.mesh = mesh
		if i % 2 == 0:
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(float(i % 100) / 100.0, 0.5, 0.7)
			item.material_override = material
		add_child(item)
		if i % 20 == 0:
			survivors.append(item)
		else:
			item.queue_free()
	if threaded:
		for path in paths:
			loaded.append(ResourceLoader.load_threaded_get(path))
	for resource in loaded:
		if resource == null:
			printerr("ROOM PREFETCH FAIL: не загружен PackedScene")
			get_tree().quit(1)
			return
	await get_tree().process_frame
	for item in survivors:
		if is_instance_valid(item):
			item.queue_free()
	print("ROOM PREFETCH STRESS DONE: %d scenes" % loaded.size())
	get_tree().quit()
