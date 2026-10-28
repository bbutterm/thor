extends RefCounted
class_name FodderGibs
## Мясо корма (П3, плейтест 28.10): при смерти корм разлетается на куски — голова, две руки, ноги, торс.
## Модель режется по своим треугольникам (в позе привязки: T-поза) — как обломки пропсов (props/prop_debris.gd):
## один раз на вид модели (ключ — сцена врага), те же материалы модели (новых материалов нет), меши кусков
## общие. Первый раз режет прогрев (ShaderWarmup.warmup_sample) — там же пайплайны формата кусков.
## Торс — «тело» корма: группа debris, лимит трупов Enemy.max_debris, держится до конца волны
## (Room.keep_fodder_corpse), отлёт по удару. Остальные куски — группа fodder_gibs, общий лимит
## Enemy.gib_limit (сверх — старые исчезают сразу), лежат Enemy.gib_life с и проваливаются в пол. Слой 7 (debris).

const GROUP := "fodder_gibs"
const LAYER := 1 << 6
## Мир, пропсы и другие куски/тела — как у трупа (enemy_visual.gd)
const MASK := 1 | (1 << 3) | (1 << 6)

enum Part {HEAD, ARM_L, ARM_R, LEGS, TORSO}
const PART_NAMES := ["Head", "ArmL", "ArmR", "Legs", "Torso"]

## Куски по ключу вида → Array[Dictionary] {mesh, center, size, part}
static var _pieces: Dictionary = {}
static var _live: Array[RigidBody3D] = []
## Сколько кусков создано за игру (тест, F3)
static var spawned_total: int = 0

static func live_count() -> int:
	_prune()
	return _live.size()

static func _prune() -> void:
	var keep: Array[RigidBody3D] = []
	for rb in _live:
		if is_instance_valid(rb) and not rb.is_queued_for_deletion():
			keep.append(rb)
	_live = keep

static func _key(enemy: Enemy) -> String:
	return enemy.scene_file_path if enemy.scene_file_path != "" else "fodder:%s" % enemy.model_body

## Все нарезанные меши (тест: общие, не растут с числом смертей).
static func cached_meshes() -> Array:
	var out: Array = []
	for k in _pieces:
		for p in _pieces[k]:
			out.append(p.mesh)
	return out

## Куски модели врага (режутся один раз на вид).
static func pieces_for(enemy: Enemy) -> Array:
	var key := _key(enemy)
	if _pieces.has(key):
		return _pieces[key]
	var out: Array = []
	if enemy._visual != null:
		out = _slice(enemy._visual)
	_pieces[key] = out
	return out

static func _rel_xform(node: Node3D, ancestor: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

## Меши вида без масштаба самого узла вида (масштаб model_scale ставится кускам при появлении).
static func _slice(vis: Node3D) -> Array:
	var meshes: Array = vis.find_children("*", "MeshInstance3D", true, false)
	if vis is MeshInstance3D:
		meshes.append(vis)
	var bounds := AABB()
	var first := true
	var sources: Array = []
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var xf := Transform3D.IDENTITY if mi == vis else _rel_xform(mi, vis)
		sources.append([mi, xf])
		var b := xf * mi.mesh.get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
	if first:
		return []
	var data: Array = []
	for g in Part.size():
		data.append({})
	for src in sources:
		var mi := src[0] as MeshInstance3D
		var xf := src[1] as Transform3D
		var nb := xf.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if idx.is_empty():
				idx.resize(verts.size())
				for i in verts.size():
					idx[i] = i
			var mat := mi.get_active_material(s)
			for t in range(0, idx.size() - 2, 3):
				var a := xf * verts[idx[t]]
				var b := xf * verts[idx[t + 1]]
				var c := xf * verts[idx[t + 2]]
				var g := part_of((a + b + c) / 3.0, bounds)
				var bucket: Dictionary = data[g]
				if not bucket.has(mat):
					bucket[mat] = {"v": [], "n": [], "uv": []}
				var dst: Dictionary = bucket[mat]
				var dv: Array = dst.v
				var dn: Array = dst.n
				var duv: Array = dst.uv
				var tri := [a, b, c]
				for k in 3:
					var vi := idx[t + k]
					dv.append(tri[k])
					if not norms.is_empty():
						dn.append((nb * norms[vi]).normalized())
					if not uvs.is_empty():
						duv.append(uvs[vi])
	var out: Array = []
	for g in Part.size():
		var bucket: Dictionary = data[g]
		if bucket.is_empty():
			continue
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
		mesh.resource_name = "fodder_gib_" + PART_NAMES[g]
		for mat in bucket:
			var d: Dictionary = bucket[mat]
			var vs := PackedVector3Array(d.v)
			for i in vs.size():
				vs[i] -= pc
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vs
			if (d.n as Array).size() == vs.size():
				arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(d.n)
			if (d.uv as Array).size() == vs.size():
				arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(d.uv)
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		out.append({"mesh": mesh, "center": pc, "size": pb.size.max(Vector3.ONE * 0.08), "part": g})
	return out

## К какому куску относится треугольник (центр c в координатах вида; персонаж в T-позе смотрит в +Z,
## руки — вдоль X): голова — выше 80 % роста у оси, руки — дальше 13 % роста от оси выше 55 %,
## ноги — ниже 48 %, остальное — торс.
static func part_of(c: Vector3, bounds: AABB) -> int:
	var h := maxf(bounds.size.y, 0.01)
	var y := (c.y - bounds.position.y) / h
	var dx := (c.x - bounds.get_center().x) / h
	if y > 0.8 and absf(dx) < 0.12:
		return Part.HEAD
	if y > 0.55 and absf(dx) > 0.13:
		return Part.ARM_L if dx > 0.0 else Part.ARM_R
	if y < 0.48:
		return Part.LEGS
	return Part.TORSO

## Разорвать корм на куски (вызывать в _die до удаления врага). Возвращает {"body": торс-RigidBody3D,
## "visual": его меш} для учёта трупа залом или {} — если куски не получились (тогда — обычный труп).
static func spawn(enemy: Enemy, knock: Vector3) -> Dictionary:
	var vis := enemy._visual
	var parent := enemy.get_parent()
	if vis == null or parent == null or not enemy.is_inside_tree():
		return {}
	var list := pieces_for(enemy)
	if list.size() < 3:
		return {}
	_prune()
	var vxf := vis.global_transform
	var basis := vxf.basis.orthonormalized()
	var sc := vxf.basis.get_scale()
	var body_center := vxf * Vector3(0, 0.9, 0)
	var kdir := knock.normalized() if knock.length() > 0.05 else -enemy.global_transform.basis.z
	var kspeed := minf(maxf(knock.length(), 4.0) * enemy.gib_knock_ratio, enemy.gib_knock_max)
	var result := {}
	for p in list:
		var part := int(p.part)
		var torso := part == Part.TORSO
		if not torso:
			while _live.size() >= maxi(1, enemy.gib_limit):
				var old: RigidBody3D = _live.pop_front()
				if is_instance_valid(old):
					old.queue_free()
		var rb := RigidBody3D.new()
		rb.name = "FodderGib" + PART_NAMES[part]
		rb.set_meta("transient", true)
		rb.collision_layer = LAYER
		rb.collision_mask = MASK
		rb.mass = (2.0 if torso else 0.6) * enemy.model_scale
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = (p.size as Vector3) * sc * 0.8
		cs.shape = box
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = p.mesh
		mi.scale = sc
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rb.add_child(mi)
		Outline.add(mi)
		if torso:
			rb.add_to_group("debris")
		else:
			rb.add_to_group(GROUP)
		parent.add_child(rb)
		var at := vxf * (p.center as Vector3)
		var out := at - body_center
		out.y = 0.0
		out = out.normalized() if out.length() > 0.02 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		# Куски сразу чуть врозь — разрыв читается в первом же кадре, а не «целое тело в T-позе»
		if not torso:
			at += out * enemy.gib_burst_offset * enemy.model_scale
		rb.global_transform = Transform3D(basis, at)
		var spread := 0.75 if torso else randf_range(0.7, 1.15)
		rb.linear_velocity = kdir * kspeed * spread + out * (0.0 if torso else enemy.gib_outward * randf_range(0.6, 1.2)) \
			+ Vector3.UP * enemy.gib_up * (0.6 if torso else randf_range(0.8, 1.3))
		rb.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * enemy.gib_spin * (0.4 if torso else 1.0)
		spawned_total += 1
		if torso:
			result = {"body": rb, "visual": mi}
		else:
			_live.append(rb)
			var tw := rb.create_tween()
			tw.tween_interval(enemy.gib_life * randf_range(0.85, 1.15))
			tw.tween_callback(_sink.bind(rb, enemy.gib_sink_time))
	return result

## Кусок отлежал: перестаёт сталкиваться и уходит в пол.
static func _sink(rb: RigidBody3D, time: float) -> void:
	if not is_instance_valid(rb):
		return
	rb.freeze = true
	rb.collision_layer = 0
	rb.collision_mask = 0
	var tw := rb.create_tween()
	tw.tween_property(rb, "global_position", rb.global_position - Vector3(0, 0.5, 0), time).set_ease(Tween.EASE_IN)
	tw.tween_callback(rb.queue_free)

## Прогрев (ShaderWarmup): нарезать куски по образцу корма и показать их в кадре — пайплайны формата кусков
## (без скиннинга, с материалом модели и обводкой) компилируются под затемнением, а не на первой смерти.
static func warmup_sample(parent: Node3D, sample: Enemy, pos: Vector3) -> void:
	if sample == null or not is_instance_valid(sample):
		return
	var list := pieces_for(sample)
	var i := 0
	for p in list:
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		mi.position = pos + Vector3((i - 2) * 0.25, 0, 0)
		mi.scale = Vector3.ONE * 0.3
		Outline.add(mi)
		i += 1

## Убрать все куски сразу (тесты).
static func clear_all() -> void:
	for rb in _live:
		if is_instance_valid(rb):
			rb.queue_free()
	_live.clear()
