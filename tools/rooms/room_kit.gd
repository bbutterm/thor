extends RefCounted
## Общие помощники и константы описаний залов (tools/rooms/<зал>.gd) и генератора (tools/build_scenes.gd).

## Высота опоры корабля в «Причале с драккаром»: палуба модели на уровне палубы-коллизии (2.2 м)
const SHIP_Y := 1.0
## Отступ картинок от стены (WallDecor), м
const WALL_INSET := 0.03

static func ring_points(c: Vector3, radius: float, n: int) -> Array:
	var out: Array = []
	for i in n:
		var a := TAU * i / n + PI / n
		out.append(c + Vector3(cos(a) * radius, 0, sin(a) * radius))
	return out

static func ring_props(c: Vector3, radius: float, n: int, kind: String) -> Array:
	var out: Array = []
	for p in ring_points(c, radius, n):
		out.append([kind, p])
	return out

static func stack_props(base: Vector3) -> Array:
	return [["crate", base], ["crate", base + Vector3(0.95, 0, 0)], ["crate", base + Vector3(0.45, 0.92, 0)], ["crate", base + Vector3(0, 0, 0.95)]]

## Прямоугольник навигации по двум углам (a — ближний, b — дальний).
static func nav_quad(a: Vector3, b: Vector3) -> PackedVector3Array:
	return PackedVector3Array([a, Vector3(a.x, b.y, b.z), b, Vector3(b.x, a.y, a.z)])
