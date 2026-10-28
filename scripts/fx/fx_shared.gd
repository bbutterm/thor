extends RefCounted
class_name FXShared
## Общие материалы и меши эффектов (против фризов): fx_material/fx_apply, учёт instance uniform,
## затухание в GL Compatibility (fade), общие меши.
## Модуль фасада FX (этап 5 рефакторинга): только static-функции; состояние, константы и вызовы снаружи — через FX.

## Общий материал эффекта. Новый материал на каждую вспышку — это компиляция пайплайна при каждом
## эффекте (замерено на Forward+). Поэтому на вид эффекта — один материал, цвет и яркость задаются
## на экземпляре (fx_apply), затухание — через GeometryInstance3D.transparency.
## Виды: "unshaded", "alpha", "alpha_nocull", "glow" (освещённый, светится).
static func fx_material(kind: String) -> ShaderMaterial:
	if FX._fx_mats.has(kind):
		return FX._fx_mats[kind]
	var m := ShaderMaterial.new()
	m.shader = FX.FX_SHADERS[kind]
	FX._fx_mats[kind] = m
	FX.materials_created += 1
	return m

## Узлы под root с текущим override/overlay, чей шейдер совпадает с текстовым признаком _has_iu.
## Это не занятые слоты: поверхностные материалы, next_pass, сохранённые параметры и удалённые из дерева RID
## здесь не учитываются; текстовый признак также может ошибаться (диагностика: Perf F3, тесты).
static func instance_uniform_users(root: Node) -> int:
	if root == null:
		return 0
	var n := 0
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if _has_iu(gi.material_override) or _has_iu(gi.material_overlay):
			n += 1
	return n

static func _has_iu(m: Material) -> bool:
	var sm := m as ShaderMaterial
	if sm == null or sm.shader == null:
		return false
	var s := sm.shader
	if not FX._iu_shaders.has(s):
		FX._iu_shaders[s] = s.code.contains("instance uniform") or s.code.contains("fx_common")
	return FX._iu_shaders[s]

## Назначить эффекту общий материал вида kind и задать цвет/яркость экземпляра.
static func fx_apply(gi: GeometryInstance3D, kind: String, color: Color, energy: float = 1.0) -> void:
	gi.material_override = fx_material(kind)
	gi.set_instance_shader_parameter("color", color)
	gi.set_instance_shader_parameter("energy", energy)
	_track_fade(gi)

static func uses_fade_emulation() -> bool:
	if FX._gl < 0:
		FX._gl = 1 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 0
	return FX._gl == 1

static func _track_fade(gi: GeometryInstance3D) -> void:
	if not uses_fade_emulation():
		return
	# Материал назначен заново — принудительно отправим fade, независимо от состояния сервера
	gi.set_meta("_fade", -1.0)
	if not gi.has_meta("_fade_tracked"):
		gi.set_meta("_fade_tracked", true)
		FX._fade_nodes.append(gi)

## Раз в кадр: transparency → fade у зарегистрированных узлов (только GL Compatibility).
static func sync_fades() -> void:
	if FX._fade_nodes.is_empty():
		return
	var keep: Array = []
	for n in FX._fade_nodes:
		if not is_instance_valid(n):
			continue
		var gi := n as GeometryInstance3D
		keep.append(gi)
		if gi.material_override == null:
			continue
		var f := 1.0 - gi.transparency
		if absf(f - float(gi.get_meta("_fade", -1.0))) > 0.002:
			gi.set_meta("_fade", f)
			gi.set_instance_shader_parameter("fade", f)
	FX._fade_nodes = keep

## Общие меши эффектов единичного размера (масштабируются узлом) — не строим примитив на каждую вспышку.
static func shared_mesh(kind: String) -> Mesh:
	if FX._meshes.has(kind):
		return FX._meshes[kind]
	var m: Mesh
	match kind:
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 16
			sm.rings = 8
			m = sm
		"ring":
			var tm := TorusMesh.new()
			tm.inner_radius = 0.85
			tm.outer_radius = 1.0
			tm.rings = 32
			tm.ring_segments = 6
			m = tm
		"box":
			m = BoxMesh.new()
		"disc":
			# Плоский диск радиуса 1 (огонь на земле, телеграф босса) — масштабируется по X/Z
			var cm := CylinderMesh.new()
			cm.top_radius = 1.0
			cm.bottom_radius = 1.0
			cm.height = 1.0
			cm.radial_segments = 32
			cm.rings = 1
			m = cm
		"wedge":
			# Сектор 90° (±45° от +Z) радиуса 1 на полу (XZ) — конус опасной зоны (enemies/hazard_zone.gd).
			# Другой угол — масштаб по X (tan половины угла), радиус — по Z и X.
			var verts := PackedVector3Array()
			var seg := 12
			for i in seg:
				var a0 := deg_to_rad(-45.0 + 90.0 * float(i) / seg)
				var a1 := deg_to_rad(-45.0 + 90.0 * float(i + 1) / seg)
				verts.append(Vector3.ZERO)
				verts.append(Vector3(sin(a1), 0, cos(a1)))
				verts.append(Vector3(sin(a0), 0, cos(a0)))
			var normals := PackedVector3Array()
			normals.resize(verts.size())
			normals.fill(Vector3.UP)
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = normals
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			m = am
		"quad", "quad_bottom", "quad_floor":
			# Квад 1×1 для текстурных эффектов (fx_sprite): по центру / с опорой на нижний край
			# (огонь, кристаллы льда растут от пола) / лёжа на полу (пятна, трещины, волна)
			var qm := QuadMesh.new()
			if kind == "quad_bottom":
				qm.center_offset = Vector3(0, 0.5, 0)
			elif kind == "quad_floor":
				qm.orientation = PlaneMesh.FACE_Y
			m = qm
	FX._meshes[kind] = m
	return m
