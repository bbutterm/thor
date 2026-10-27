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
	"column": [QV + "Corner_ExteriorWide_Brick.gltf", "rocktrim"],
	"post": [QV + "Corner_Exterior_Wood.gltf", "woodtrim"],
	"beam": [QV + "HoleCover_Straight.gltf", "woodtrim"],
	"support": [QV + "Prop_Support.gltf", "woodtrim"],
	"tile": [QV + "Floor_WoodDark.gltf", "woodtrim"],
	"cliff_1": [QS + "Environment_Cliff1.gltf", "surface_cliff"],
	"cliff_2": [QS + "Environment_Cliff2.gltf", "surface_cliff"],
	"cliff_3": [QS + "Environment_Cliff3.gltf", "surface_cliff"],
	"cliff_4": [QS + "Environment_Cliff4.gltf", "surface_cliff"],
	"stake": ["", "surface_wood"],
	"log": ["", "surface_wood"],
	"pine": ["", "pine"],
	"grime": ["", "grime"],
}

## Материалы на шейдере world_surface (один шейдер — одни пайплайны) и прочие общие
const SURFACES := ["surface_floor_brick", "surface_floor_dirt", "surface_stone", "surface_rock", "surface_cliff",
	"surface_wood", "surface_plank", "surface_pillar", "surface_ground"]
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
