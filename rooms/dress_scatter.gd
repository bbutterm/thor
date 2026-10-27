@tool
extends MultiMeshInstance3D
class_name DressScatter
## Повторяющиеся детали одевания зала (блок Б0: валуны, обломки, кант, балки, частокол, сосны дали) — один
## MultiMesh на вид меша (один draw call), общий материал без instance uniform (RoomDress.MESHES).
## Трансформы хранятся в xforms, а MultiMesh собирается при загрузке: генератор залов работает headless,
## а там буфер MultiMesh не сохраняется в сцену (данные живут в RenderingServer).

## Меш детали (rooms/meshes/*.res)
@export var mesh: Mesh
## Буфер MultiMesh (TRANSFORM_3D): по 12 чисел на экземпляр — строки базиса 3×4 с origin в конце строки
@export var xforms: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	if multimesh == null or multimesh.instance_count * 12 != xforms.size():
		build()

func build() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size() / 12
	if mm.instance_count > 0:
		mm.buffer = xforms
	multimesh = mm

func count() -> int:
	return xforms.size() / 12

## Трансформы → буфер MultiMesh (генератор).
static func pack(list: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(list.size() * 12)
	var o := 0
	for t in list:
		var xf: Transform3D = t
		var b := xf.basis
		var row := [b.x.x, b.y.x, b.z.x, xf.origin.x, b.x.y, b.y.y, b.z.y, xf.origin.y, b.x.z, b.y.z, b.z.z, xf.origin.z]
		for v in row:
			out[o] = v
			o += 1
	return out
