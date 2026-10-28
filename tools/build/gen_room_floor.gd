extends RefCounted
class_name GenRoomFloor
## Генератор: вырезы в полу зала и навигация врагов между ярусами (NavigationRegion3D по описанию зала).
## Компонент SceneBuilder (этап 4 рефакторинга): числа и состояние — поля SceneBuilder (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — генератор.room_floor; нужные снаружи функции есть и на SceneBuilder.

const K = preload("res://tools/rooms/room_kit.gd")

var gen: SceneBuilder

func _init(owner_node: SceneBuilder) -> void:
	gen = owner_node

## Открытые прямоугольники в координатах пола X/Z. Центр и размер берём из данных зала.
## Запас 0.1 м у края не даёт рамке земли снаружи зала закрыть проём.
func _floor_opening_rects(specs: Variant, width: float, depth: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not (specs is Array):
		push_error("floor_openings: нужен массив пар [центр Vector2, размер Vector2]")
		return out
	for pair in specs:
		if not (pair is Array) or pair.size() != 2 or not (pair[0] is Vector2) or not (pair[1] is Vector2):
			push_error("floor_openings: нужна пара [центр Vector2, размер Vector2]")
			continue
		var center: Vector2 = pair[0]
		var size: Vector2 = pair[1]
		if not is_finite(center.x) or not is_finite(center.y) or not is_finite(size.x) or not is_finite(size.y) or size.x <= 0.0 or size.y <= 0.0:
			push_error("floor_openings: координаты должны быть конечными, размеры — положительными")
			continue
		var rect := Rect2(center - size * 0.5, size)
		var end := rect.end
		if rect.position.x < -width * 0.5 + 0.1 or end.x > width * 0.5 - 0.1 or rect.position.y < -depth * 0.5 + 0.1 or end.y > depth * 0.5 - 0.1:
			push_error("floor_openings: проём должен быть внутри видимого пола с отступом 0.1 м")
			continue
		out.append(rect)
	return out

func _floor_opening_contains(openings: Array[Rect2], p: Vector2) -> bool:
	for rect in openings:
		if rect.has_point(p):
			return true
	return false

## Сначала исходные края, потом ВСЕ точные края проёмов; близкие границы не сливать.
func _floor_cut_lines(openings: Array[Rect2], lo: float, hi: float, axis: int) -> PackedFloat32Array:
	var lines := PackedFloat32Array([lo, hi])
	for rect in openings:
		lines.append(rect.position[axis])
		lines.append(rect.end[axis])
	lines.sort()
	var result := PackedFloat32Array()
	for v in lines:
		if result.is_empty() or v > result[result.size() - 1]:
			result.append(v)
	return result

## Один StaticBody WORLD, вместо исходной формы — горизонтальные полосы вокруг объединения отверстий.
## Метаданные — общий источник границ для RoomDresser при повторном одевании.
func _cut_floor(floor: Node3D, openings: Array[Rect2], width: float, depth: float) -> void:
	floor.set_meta("floor_openings", openings)
	var old := floor.get_node("Shape")
	floor.remove_child(old)
	old.free()
	var xs := _floor_cut_lines(openings, -width * 0.5 - 1.0, width * 0.5 + 1.0, 0)
	var zs := _floor_cut_lines(openings, -depth * 0.5 - 1.0, depth * 0.5 + 1.0, 1)
	var shape_id := 0
	for iz in zs.size() - 1:
		var z0 := zs[iz]
		var z1 := zs[iz + 1]
		var open_run := false
		var x0 := 0.0
		for ix in xs.size() - 1:
			var mid := Vector2((xs[ix] + xs[ix + 1]) * 0.5, (z0 + z1) * 0.5)
			var solid := not _floor_opening_contains(openings, mid)
			if solid and not open_run:
				x0 = xs[ix]
				open_run = true
			if open_run and (not solid or ix == xs.size() - 2):
				var x1 := xs[ix] if not solid else xs[ix + 1]
				var shape := CollisionShape3D.new()
				shape.name = "Shape%d" % shape_id
				var box := BoxShape3D.new()
				box.size = Vector3(x1 - x0, 1.0, z1 - z0)
				shape.shape = box
				# Floor уже расположен в y = -0.5, поэтому локальная высота равна нулю.
				shape.position = Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5)
				floor.add_child(shape)
				shape_id += 1
				open_run = false

## Поверхность задаётся полигонами, общие вершины получают общие индексы.
func _nav_region(parent: Node3D, spec: Array) -> void:
	var verts := PackedVector3Array()
	var index := {}
	var faces: Array[PackedInt32Array] = []
	for poly in spec[1]:
		var face := PackedInt32Array()
		for point in poly:
			var v: Vector3 = point
			if not index.has(v):
				index[v] = verts.size()
				verts.append(v)
			face.append(int(index[v]))
		faces.append(face)
	var mesh := NavigationMesh.new()
	mesh.set_vertices(verts)
	for face in faces:
		mesh.add_polygon(face)
	var region := NavigationRegion3D.new()
	region.name = spec[0]
	region.navigation_layers = 1
	region.navigation_mesh = mesh
	if spec.size() > 2:
		region.set_meta("break_with", spec[2])
	parent.add_child(region)

## Необязательная навигация: пол с физическими проёмами, дополнительные полигоны и связи.
func _build_enemy_navigation(root: Node3D, d: Dictionary, openings: Array[Rect2], width: float, depth: float) -> void:
	if not d.has("enemy_navigation"):
		return
	var data: Dictionary = d.enemy_navigation
	var clearance := maxf(0.0, float(data.get("clearance", 0.55)))
	var bounds := Rect2(Vector2(-width * 0.5 + clearance, -depth * 0.5 + clearance), Vector2(width - clearance * 2, depth - clearance * 2))
	if not bounds.has_area():
		push_error("EnemyNavigation: недостаточный размер пола")
		return
	var excluded: Array[Rect2] = []
	var raw := _floor_opening_rects(data.get("ground_exclusions", []), width, depth)
	for value in openings + raw:
		var rect: Rect2 = value
		var clipped: Rect2 = rect.grow(clearance).intersection(bounds)
		if clipped.has_area():
			excluded.append(clipped)
	var xs := _floor_cut_lines(excluded, bounds.position.x, bounds.end.x, 0)
	var zs := _floor_cut_lines(excluded, bounds.position.y, bounds.end.y, 1)
	var floor_faces: Array = []
	for iz in zs.size() - 1:
		for ix in xs.size() - 1:
			var mid := Vector2((xs[ix] + xs[ix + 1]) * 0.5, (zs[iz] + zs[iz + 1]) * 0.5)
			if not _floor_opening_contains(excluded, mid):
				floor_faces.append(K.nav_quad(Vector3(xs[ix], 0, zs[iz]), Vector3(xs[ix + 1], 0, zs[iz + 1])))
	var nav := Node3D.new()
	nav.name = "EnemyNavigation"
	root.add_child(nav)
	_nav_region(nav, ["Floor", floor_faces])
	for spec in data.get("regions", []):
		_nav_region(nav, spec)
	for spec in data.get("links", []):
		var link := NavigationLink3D.new()
		link.name = spec[0]
		link.navigation_layers = 1
		link.bidirectional = true
		link.start_position = spec[1]
		link.end_position = spec[2]
		if spec.size() > 3:
			if spec[3] is Dictionary:
				var options: Dictionary = spec[3]
				link.navigation_layers = int(options.get("layers", 1))
				link.bidirectional = bool(options.get("bidirectional", true))
				if options.has("traverse"):
					link.set_meta("traverse", options.traverse)
				if options.has("break_with"):
					link.set_meta("break_with", options.break_with)
			else:
				link.set_meta("break_with", spec[3])
		nav.add_child(link)
