extends RefCounted
## Только эксперимент: не изменяет исходные ресурсы Skin или файлы игры.
## Снимок хранит каждую исходную Skin у конкретного MeshInstance3D, чтобы можно
## было повторить A/B в одном процессе и затем восстановить состояние.

static func equal_binds(a: Skin, b: Skin) -> bool:
	if a == null or b == null:
		return a == b
	if a.get_bind_count() != b.get_bind_count():
		return false
	for index in a.get_bind_count():
		if a.get_bind_bone(index) != b.get_bind_bone(index):
			return false
		if a.get_bind_name(index) != b.get_bind_name(index):
			return false
		# Никакого приближённого сравнения: даже малейшее отличие позы запрещает замену.
		if a.get_bind_pose(index) != b.get_bind_pose(index):
			return false
	return true

static func snapshot(skeleton: Skeleton3D) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		# Пропускаем оружие и остальные меши дочерних скелетов/вложений, если они есть.
		if mesh.get_node_or_null(mesh.skeleton) != skeleton or mesh.skin == null:
			continue
		records.append({"mesh": mesh, "skin": mesh.skin, "geometry": mesh.mesh,
			"material_override": mesh.material_override, "overlay": mesh.material_overlay})
	return records

static func intern(records: Array[Dictionary]) -> Dictionary:
	var source_to_canonical: Dictionary = {}
	var candidates: Array[Skin] = []
	var replaced := 0
	for rec in records:
		var mesh: MeshInstance3D = rec.mesh
		var source: Skin = rec.skin
		if not source_to_canonical.has(source.get_instance_id()):
			var canonical: Skin = null
			for candidate in candidates:
				if equal_binds(source, candidate):
					canonical = candidate
					break
			if canonical == null:
				canonical = source
				candidates.append(source)
			source_to_canonical[source.get_instance_id()] = canonical
		var result: Skin = source_to_canonical[source.get_instance_id()]
		if mesh.skin != result:
			mesh.skin = result
			replaced += 1
	return {"old_unique": source_to_canonical.size(), "new_unique": candidates.size(), "changed_meshes": replaced}

static func restore(records: Array[Dictionary]) -> void:
	for rec in records:
		var mesh: MeshInstance3D = rec.mesh
		if is_instance_valid(mesh):
			mesh.skin = rec.skin

static func same_content(records: Array[Dictionary]) -> bool:
	for rec in records:
		var mesh: MeshInstance3D = rec.mesh
		if not is_instance_valid(mesh) or not equal_binds(rec.skin, mesh.skin):
			return false
		if mesh.mesh != rec.geometry or mesh.material_override != rec.material_override or mesh.material_overlay != rec.overlay:
			return false
	return true
