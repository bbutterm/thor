extends RefCounted
class_name PropDebris
## Обломки разрушаемых пропсов (props/destructible.gd). Модель пропса режется на куски по её же треугольникам:
## бочка — клёпки по секторам вокруг оси + крышка и дно, ящик — шесть стенок. У кусков тот же материал и
## тот же формат вершин, что у модели (материалы НЕ создаются; меши кусков — общие на тип пропса, режутся
## один раз — при прогреве ShaderWarmup). Кусок — RigidBody3D на слое 7 (debris), группа prop_debris
## (не debris: тот общий лимит — трупы врагов), лежит DestructTuning.debris_life секунд и проваливается в пол.
## Общий лимит на зал — DestructTuning.debris_limit: сверх — самые старые исчезают сразу.

const GROUP := "prop_debris"
const LAYER := 1 << 6
## Мир и другие обломки (пропсы не толкаем — бочки от щепок не катятся и не бьются)
const MASK := 1 | (1 << 6)
const CONFIG := "res://props/destruct_tuning.tres"

static var _cfg: DestructTuning
## Куски по ключу «сцена:режим:секторы» → Array[Dictionary] {mesh, center, shape}
static var _pieces: Dictionary = {}
static var _live: Array[RigidBody3D] = []
## Сколько обломков создано за игру (диагностика, тест)
static var spawned_total: int = 0

static func cfg() -> DestructTuning:
	if _cfg == null:
		_cfg = load(CONFIG) as DestructTuning if ResourceLoader.exists(CONFIG) else DestructTuning.new()
	return _cfg

## Живые обломки (для тестов и F3).
static func live_count() -> int:
	_prune()
	return _live.size()

static func _prune() -> void:
	var keep: Array[RigidBody3D] = []
	for rb in _live:
		if is_instance_valid(rb) and not rb.is_queued_for_deletion():
			keep.append(rb)
	_live = keep

## Куски модели пропса (режутся один раз на тип). mode: "radial" (бочка) | "box" (ящик).
static func pieces_for(prop: Node3D, mode: String, sectors: int) -> Array:
	var key := "%s:%s:%d" % [prop.scene_file_path if prop.scene_file_path != "" else String(prop.name), mode, sectors]
	if _pieces.has(key):
		return _pieces[key]
	var out := _slice(prop, mode, sectors)
	_pieces[key] = out
	return out

## Все уже нарезанные меши кусков (тест: общие, не растут).
static func cached_meshes() -> Array:
	var out: Array = []
	for k in _pieces:
		for p in _pieces[k]:
			out.append(p.mesh)
	return out

## Трансформ узла относительно предка (работает и вне дерева сцены).
static func _rel_xform(node: Node3D, ancestor: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

static func _slice(prop: Node3D, mode: String, sectors: int) -> Array:
	var model := prop.get_node_or_null("Model")
	if model == null:
		return []
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	# Сначала — границы модели в координатах пропса (по ним решаем, куда какой треугольник)
	var bounds := AABB()
	var first := true
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := _rel_xform(mi, prop) * mi.mesh.get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
	if first:
		return []
	var center := bounds.get_center()
	var half := bounds.size * 0.5
	var groups := sectors + 2 if mode == "radial" else 6
	# Группа → материал → массивы
	var data: Array = []
	for g in groups:
		data.append({})
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := _rel_xform(mi, prop)
		var nb := xf.basis.inverse().transposed()
		var flip := xf.basis.determinant() < 0.0
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var tans: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				idx.resize(verts.size())
				for i in verts.size():
					idx[i] = i
			var mat := mi.get_active_material(s)
			var flags: int = mi.mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
			for t in range(0, idx.size() - 2, 3):
				var a := xf * verts[idx[t]]
				var b := xf * verts[idx[t + 1]]
				var c := xf * verts[idx[t + 2]]
				var g := _group_of((a + b + c) / 3.0, (b - a).cross(c - a), center, half, mode, sectors)
				var bucket: Dictionary = data[g]
				if not bucket.has(mat):
					# Обычные Array (по ссылке): Packed*-массив из словаря при изменении копируется
					bucket[mat] = {"v": [], "n": [], "t": [], "uv": [], "flags": flags}
				var dst: Dictionary = bucket[mat]
				var dv: Array = dst.v
				var dn: Array = dst.n
				var dt: Array = dst.t
				var duv: Array = dst.uv
				var tri := [a, b, c]
				for k in 3:
					var vi := idx[t + k]
					dv.append(tri[k])
					if not norms.is_empty():
						dn.append((nb * norms[vi]).normalized())
					if tans.size() >= (vi + 1) * 4:
						var tv := (xf.basis * Vector3(tans[vi * 4], tans[vi * 4 + 1], tans[vi * 4 + 2])).normalized()
						dt.append_array([tv.x, tv.y, tv.z, tans[vi * 4 + 3] * (-1.0 if flip else 1.0)])
					if not uvs.is_empty():
						duv.append(uvs[vi])
	var out: Array = []
	for g in groups:
		var bucket: Dictionary = data[g]
		if bucket.is_empty():
			continue
		# Центр куска — середина его вершин: тело обломка вращается вокруг него
		var pb := AABB()
		var pf := true
		for mat in bucket:
			for v in (bucket[mat].v as Array):
				if pf:
					pb = AABB(v, Vector3.ZERO)
					pf = false
				else:
					pb = pb.expand(v)
		var pc := pb.get_center()
		var mesh := ArrayMesh.new()
		for mat in bucket:
			var d: Dictionary = bucket[mat]
			var vs := PackedVector3Array(d.v)
			for i in vs.size():
				vs[i] -= pc
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vs
			if not (d.n as Array).is_empty():
				arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(d.n)
			if (d.t as Array).size() == vs.size() * 4:
				arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array(d.t)
			if not (d.uv as Array).is_empty():
				arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(d.uv)
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, int(d.flags))
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		var shape := BoxShape3D.new()
		shape.size = pb.size.max(Vector3.ONE * 0.06)
		out.append({"mesh": mesh, "center": pc, "shape": shape})
	return out

## Куда относится треугольник: бочка — сектор вокруг оси Y или крышка/дно; ящик — ближайшая стенка.
static func _group_of(c: Vector3, face_n: Vector3, center: Vector3, half: Vector3, mode: String, sectors: int) -> int:
	var l := (c - center) / half.max(Vector3.ONE * 0.001)
	if mode == "radial":
		var n := face_n.normalized() if face_n.length() > 0.000001 else Vector3.ZERO
		if absf(l.y) > 0.82 and absf(n.y) > 0.6:
			return sectors if l.y > 0.0 else sectors + 1
		var ang := atan2(c.x - center.x, c.z - center.z) + PI
		return clampi(int(ang / TAU * sectors), 0, sectors - 1)
	var ax := absf(l.x)
	var ay := absf(l.y)
	var az := absf(l.z)
	if ax >= ay and ax >= az:
		return 0 if l.x > 0.0 else 1
	if ay >= az:
		return 2 if l.y > 0.0 else 3
	return 4 if l.z > 0.0 else 5

## Разбросать куски пропса prop (вызывать до его удаления). knock — сила и направление удара.
static func spawn(prop: Node3D, knock: Vector3, mode: String, sectors: int, base_velocity: Vector3 = Vector3.ZERO) -> int:
	var parent := prop.get_parent()
	if parent == null or not prop.is_inside_tree():
		return 0
	var list := pieces_for(prop, mode, sectors)
	if list.is_empty():
		return 0
	var t := cfg()
	_prune()
	var xf := prop.global_transform.orthonormalized()
	var kdir := knock.normalized() if knock.length() > 0.05 else Vector3.ZERO
	var kspeed := minf(knock.length() * t.debris_knock_ratio, t.debris_knock_max)
	var n := 0
	for p in list:
		while _live.size() >= maxi(1, t.debris_limit):
			var old: RigidBody3D = _live.pop_front()
			if is_instance_valid(old):
				old.queue_free()
		var rb := RigidBody3D.new()
		rb.name = "PropDebris"
		rb.add_to_group(GROUP)
		rb.set_meta("transient", true)
		rb.collision_layer = LAYER
		rb.collision_mask = MASK
		rb.mass = t.debris_mass
		var cs := CollisionShape3D.new()
		cs.shape = p.shape
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		rb.add_child(mi)
		parent.add_child(rb)
		var center: Vector3 = p.center
		rb.global_transform = Transform3D(xf.basis, xf * center)
		var out := xf.basis * (center - Vector3(0, center.y, 0))
		out = out.normalized() if out.length() > 0.01 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		rb.linear_velocity = kdir * kspeed * randf_range(0.6, 1.0) + out * t.debris_outward * randf_range(0.6, 1.2) \
			+ Vector3.UP * t.debris_up * randf_range(0.6, 1.2) + base_velocity * 0.5
		rb.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * t.debris_spin
		_live.append(rb)
		spawned_total += 1
		n += 1
		var tw := rb.create_tween()
		tw.tween_interval(t.debris_life * randf_range(0.85, 1.15))
		tw.tween_callback(_sink.bind(rb))
	return n

## Обломок отлежал: перестаёт сталкиваться и уходит в пол.
static func _sink(rb: RigidBody3D) -> void:
	if not is_instance_valid(rb):
		return
	var t := cfg()
	rb.freeze = true
	rb.collision_layer = 0
	rb.collision_mask = 0
	var tw := rb.create_tween()
	tw.tween_property(rb, "global_position", rb.global_position - Vector3(0, t.debris_sink_depth, 0), t.debris_sink_time).set_ease(Tween.EASE_IN)
	tw.tween_callback(rb.queue_free)

## Убрать все обломки сразу (тесты).
static func clear_all() -> void:
	for rb in _live:
		if is_instance_valid(rb):
			rb.queue_free()
	_live.clear()
