extends Node
## Диагностическая нагрузка Dummy-рендера: основная нить создаёт обычные ресурсы,
## пока проект штатно предзагружает те же сцены/модели в фоне.

func _ready() -> void:
	var active := 0
	for path in AssetCache._pending:
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			active += 1
	print("BACKGROUND: %d pending, %d in progress" % [AssetCache._pending.size(), active])
	var survivors: Array = []
	for i in 2000:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.0 + (i % 7) * 0.1, 1.0, 1.0)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		add_child(mi)
		if i % 10 == 0:
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(float(i % 100) / 100.0, 0.5, 0.7)
			mi.material_override = material
		if i % 20 == 0:
			survivors.append(mi)
		else:
			mi.queue_free()
	AssetCache.finish()
	await get_tree().process_frame
	for instance in survivors:
		if is_instance_valid(instance):
			instance.queue_free()
	print("STRESS DONE")
	get_tree().quit()
