extends Node
## Проверяет оставшуюся фоновую предзагрузку экранов и портретов в headless.

func _ready() -> void:
	AssetCache.finish()
	ScreenArt.prefetch_between_runs()
	Portrait.prefetch(PackedStringArray(["odin", "thor", "sif", "loki", "freya", "hild", "hugin", "jarl"]))
	print("PREFETCH: %d screen requests, %d portrait requests" % [ScreenArt._requested.size(), Portrait._pending.size()])
	for i in 2000:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		if i % 5 == 0:
			mi.material_override = StandardMaterial3D.new()
		add_child(mi)
		mi.queue_free()
	Portrait.prefetch(PackedStringArray())
	ScreenArt.shutdown()
	await get_tree().process_frame
	print("PREFETCH STRESS DONE")
	get_tree().quit()
