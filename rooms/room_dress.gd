extends RefCounted
class_name RoomDress
## Блок Б0 «Одеть залы» — то, что нужно в игре: список общих мешей и материалов одевания залов
## (их собирает и расставляет генератор, tools/room_dresser.gd — в экспорт не идёт) и прогрев.
## Правило фризов (CLAUDE.md «Важно»): всё одевание — на этих файлах, ни одного материала на блок или
## экземпляр; мелкие повторяющиеся детали — MultiMesh. Файлы держит AssetCache (rooms/materials/,
## rooms/meshes/ в DIRS), прогрев — ShaderWarmup → warmup(): после него пайплайны не компилируются в бою.

const MESH_DIR := "res://rooms/meshes/"
const MAT_DIR := "res://rooms/materials/"
const QV := "res://assets/quaternius/village/"
const QS := "res://assets/quaternius/pirate/"

## Меши для MultiMesh и подгонки по габаритам: ключ → [источник gltf ("" — процедурный), материал]
const MESHES := {
	"rock_1": [QS + "Environment_Rock_1.gltf", "surface_rock"],
	"rock_2": [QS + "Environment_Rock_2.gltf", "surface_rock"],
	"rock_3": [QS + "Environment_Rock_3.gltf", "surface_rock"],
	"rock_4": [QS + "Environment_Rock_4.gltf", "surface_rock"],
	"rock_5": [QS + "Environment_Rock_5.gltf", "surface_rock"],
	"brick_1": [QV + "Prop_Brick1.gltf", "surface_rock"],
	"brick_2": [QV + "Prop_Brick2.gltf", "surface_rock"],
	"brick_3": [QV + "Prop_Brick3.gltf", "surface_rock"],
	"brick_4": [QV + "Prop_Brick4.gltf", "surface_rock"],
	"kerb_1": [QV + "Prop_ExteriorBorder_Straight1.gltf", "rocktrim"],
	"kerb_2": [QV + "Prop_ExteriorBorder_Straight2.gltf", "rocktrim"],
	"pilaster": ["", "surface_pillar"],
	"post": [QV + "Corner_Exterior_Wood.gltf", "woodtrim"],
	"beam": [QV + "HoleCover_Straight.gltf", "woodtrim"],
	"support": [QV + "Prop_Support.gltf", "woodtrim"],
	"tile": [QV + "Floor_WoodDark.gltf", "woodtrim"],
	"cliff_1": [QS + "Environment_Cliff1.gltf", "surface_cliff"],
	"stake": ["", "surface_wood"],
	"log": ["", "surface_wood"],
	"pine": ["", "pine"],
	"grime": ["", "grime"],
}

## Материалы на шейдере world_surface (один шейдер — одни пайплайны) и прочие общие
const SURFACES := ["surface_floor_brick", "surface_floor_dirt", "surface_stone", "surface_rock", "surface_cliff",
	"surface_wood", "surface_plank", "surface_pillar", "surface_ground",
	# Вид Мидгарда в генерируемых залах (срез зала 10, Н1): тот же шейдер, другие параметры
	"slice_dirt", "slice_plank", "slice_rock", "slice_wood", "slice_floor_brick", "slice_stone", "slice_pillar"]
const OTHER := ["rocktrim", "woodtrim", "grime", "pine", "water"]

static var _held: Array = []

## Пути всех общих файлов одевания (AssetCache держит их в памяти).
static func preload_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for k in SURFACES + OTHER:
		out.append(MAT_DIR + k + ".tres")
	for k in MESHES:
		out.append(MESH_DIR + k + ".res")
	return out

static func material(key: String) -> Material:
	var p := MAT_DIR + key + ".tres"
	return load(p) as Material if ResourceLoader.exists(p) else null

## Прогрев (ShaderWarmup, экран затемнён): каждый меш одевания — в MultiMesh со своим материалом (так он и
## рисуется в зале), каждая поверхность world_surface — на меше с цветом вершин (пол, блоки) и на BoxMesh.
static func warmup(parent: Node3D, center: Vector3, right: Vector3) -> void:
	if not ResourceLoader.exists(MAT_DIR + "surface_stone.tres"):
		return
	var x := -1.2
	for k in MESHES:
		var mp: String = MESH_DIR + str(k) + ".res"
		if not ResourceLoader.exists(mp):
			continue
		var mesh := load(mp) as Mesh
		var a := mesh.get_aabb()
		var s := 0.12 / maxf(a.get_longest_axis_size(), 0.01)
		var mmi := DressScatter.new()
		mmi.mesh = mesh
		mmi.xforms = DressScatter.pack([Transform3D(Basis.from_scale(Vector3.ONE * s), -a.get_center() * s)])
		mmi.material_override = material(MESHES[k][1])
		parent.add_child(mmi)
		mmi.global_position = center + right * x + Vector3(0, 0.25, 0)
		x += 0.1
	var tri := _colored_quad()
	x = -1.2
	for k in SURFACES:
		var mi := MeshInstance3D.new()
		mi.mesh = tri
		mi.material_override = material(k)
		parent.add_child(mi)
		mi.global_position = center + right * x + Vector3(0, 0.05, 0)
		mi.scale = Vector3.ONE * 0.1
		var box := MeshInstance3D.new()
		box.mesh = FX.shared_mesh("box")
		box.material_override = material(k)
		parent.add_child(box)
		box.global_position = center + right * x + Vector3(0, 0.15, 0)
		box.scale = Vector3.ONE * 0.06
		x += 0.25
	for k in ["water", "grime"]:
		var mi2 := MeshInstance3D.new()
		mi2.mesh = FX.shared_mesh("quad")
		mi2.material_override = material(k)
		parent.add_child(mi2)
		mi2.global_position = center + right * x + Vector3(0, 0.1, 0)
		mi2.scale = Vector3.ONE * 0.08
		x += 0.2

## Форматы и материалы открытого зала могут отличаться от общих образцов выше. Для каждой
## комбинации берём настоящий меш и материалы загруженной сцены и рисуем маленькую копию
## перед камерой. Одинаковые варианты объединяем: одинаковых камней в зале может быть сотня.
## Копии не меняют ресурсы зала и удаляются вместе с ShaderWarmup.
static func warmup_room(parent: Node3D, room: Node3D) -> Node3D:
	var samples := Node3D.new()
	samples.name = "RoomVisualSamples"
	parent.add_child(samples)
	if room == null:
		return samples
	var seen := {}
	# Формат поверхности PrimitiveMesh читается через RenderingServer. Снимок содержит
	# и данные меша, поэтому запрашиваем его только раз на ресурс/поверхность в этом зале.
	var format_cache := {}
	for root_name in ["Geometry", "Dress"]:
		var root := room.get_node_or_null(root_name)
		if root == null:
			continue
		for node in root.find_children("*", "GeometryInstance3D", true, false):
			var source := node as GeometryInstance3D
			var mesh := _room_mesh(source)
			if mesh == null or mesh.get_surface_count() == 0:
				continue
			var key := _room_variant_key(source, mesh, format_cache)
			if seen.has(key):
				continue
			seen[key] = true
			var sample := _room_variant_sample(source, mesh)
			if sample == null:
				continue
			sample.name = "RoomSample%03d" % (seen.size() - 1)
			sample.set_meta("room_source", room.get_path_to(source))
			samples.add_child(sample)
			# В локальных координатах ShaderWarmup это перед камерой и в поле зрения.
			# Небольшой наклон показывает в том числе горизонтальные пол и воду.
			var idx := seen.size() - 1
			var bounds := mesh.get_aabb()
			var scale := 0.18 / maxf(bounds.get_longest_axis_size(), 0.01)
			sample.rotation_degrees.x = 35.0
			sample.scale = Vector3.ONE * scale
			# Сетка повторяется в пределах видимой области, даже если в будущем
			# уникальных комбинаций будет больше 72.
			var row := int(floorf(float(idx) / 12.0)) % 6
			var grid := Vector3(-1.1 + float(idx % 12) * 0.2, 0.3 + float(row) * 0.2, -floorf(float(idx) / 72.0) * 0.001)
			sample.position = grid - sample.transform.basis * bounds.get_center()
	return samples

static func _room_mesh(source: GeometryInstance3D) -> Mesh:
	if source is MeshInstance3D:
		return (source as MeshInstance3D).mesh
	if source is MultiMeshInstance3D:
		var mm := (source as MultiMeshInstance3D).multimesh
		if mm and mm.transform_format == MultiMesh.TRANSFORM_3D:
			return mm.mesh
	return null

## Вариант отличается форматом каждой поверхности, материалом, оверлеем и режимом геометрии.
static func _room_variant_key(source: GeometryInstance3D, mesh: Mesh, format_cache: Dictionary) -> String:
	var parts := PackedStringArray(["multi" if source is MultiMeshInstance3D else "mesh",
		str(source.cast_shadow), str(source.gi_mode), str(source.layers), str(source.transparency),
		str(source.material_overlay.get_instance_id() if source.material_overlay else 0)])
	if source is MultiMeshInstance3D:
		var mm := (source as MultiMeshInstance3D).multimesh
		parts.append(str(mm.use_colors))
		parts.append(str(mm.use_custom_data))
	for i in mesh.get_surface_count():
		var mat := source.material_override
		if mat == null and source is MeshInstance3D:
			mat = (source as MeshInstance3D).get_surface_override_material(i)
		if mat == null:
			mat = mesh.surface_get_material(i)
		parts.append("%s:%d" % [_room_surface_format(mesh, i, format_cache), mat.get_instance_id() if mat else 0])
	return "|".join(parts)

static func _room_surface_format(mesh: Mesh, surface: int, cache: Dictionary) -> String:
	var key := "%d:%d" % [mesh.get_instance_id(), surface]
	if cache.has(key):
		return str(cache[key])
	var value := ""
	if mesh is ArrayMesh:
		var array_mesh := mesh as ArrayMesh
		value = "%d:%d" % [array_mesh.surface_get_format(surface), array_mesh.surface_get_primitive_type(surface)]
	else:
		var data := RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
		if data.has("format") and data.has("primitive"):
			value = "%d:%d" % [int(data["format"]), int(data["primitive"])]
		else:
			# Неизвестный формат не объединяем с другими ресурсами.
			value = "unknown:" + key
	cache[key] = value
	return value

static func _room_variant_sample(source: GeometryInstance3D, mesh: Mesh) -> GeometryInstance3D:
	var sample: GeometryInstance3D
	if source is MeshInstance3D:
		var src := source as MeshInstance3D
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		for i in mesh.get_surface_count():
			var override := src.get_surface_override_material(i)
			if override:
				mi.set_surface_override_material(i, override)
		sample = mi
	elif source is MultiMeshInstance3D:
		var original := (source as MultiMeshInstance3D).multimesh
		if original == null:
			return null
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = original.use_colors
		mm.use_custom_data = original.use_custom_data
		mm.mesh = mesh
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D.IDENTITY)
		if mm.use_colors:
			mm.set_instance_color(0, Color.WHITE)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		sample = mi
	else:
		return null
	sample.material_override = source.material_override
	sample.material_overlay = source.material_overlay
	sample.cast_shadow = source.cast_shadow
	sample.gi_mode = source.gi_mode
	sample.layers = source.layers
	sample.transparency = source.transparency
	return sample

## Квад с цветом вершин (формат вершин как у пола и скошенных блоков зала).
static func _colored_quad() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Обе стороны: образец виден камере прогрева при любом обходе
	for v in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1),
			Vector3(-1, 0, -1), Vector3(1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		st.set_normal(Vector3.UP)
		st.set_color(Color(0.8, 0.8, 0.8))
		st.set_uv(Vector2(v.x, v.z))
		st.add_vertex(v)
	return st.commit()
