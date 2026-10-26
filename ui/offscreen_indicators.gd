extends Control
class_name OffscreenIndicators
## Индикаторы врагов за экраном (GDD 18): красный треугольник с черепом (hud_offscreen) на краю экрана,
## остриё — в сторону врага. Ближние крупнее и ярче, босс — золотой. Только _draw, раз в кадр.
## Выключаются в настройках ([hud] offscreen).

## Дальше этого враг не показывается (м)
@export var max_distance: float = 30.0
## Сколько индикаторов максимум (ближайшие)
@export var max_count: int = 8
## Размер индикатора у ближнего / дальнего врага (px)
@export var near_size: float = 40.0
@export var far_size: float = 24.0
## Отступ от края экрана (px)
@export var edge_margin: float = 46.0

var player: Player
var enabled: bool = true
var _tex: Texture2D
## Что сейчас нарисовано: [позиция, угол, размер, цвет] — для тестов
var shown: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.full_rect(self)
	_tex = UISkin.texture("hud_offscreen")
	enabled = bool(GameSettings.get_value("hud", "offscreen"))

func _process(_delta: float) -> void:
	var before := shown.size()
	shown.clear()
	if enabled and player and is_instance_valid(player) and not player.is_dead:
		_collect()
	if not shown.is_empty() or before > 0:
		queue_redraw()

func _collect() -> void:
	var cam := player.camera
	var vp := get_viewport_rect().size
	var center := vp * 0.5
	var inner := Rect2(Vector2.ZERO, vp).grow(-8.0)
	var list: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.is_dead or not e.is_inside_tree():
			continue
		var pos := e.global_position + Vector3.UP * 1.2
		var dist := pos.distance_to(cam.global_position)
		if dist > max_distance:
			continue
		var behind := cam.is_position_behind(pos)
		var sp := cam.unproject_position(pos)
		if not behind and inner.has_point(sp):
			continue
		list.append([dist, e, sp, behind])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(list.size(), max_count):
		var dist: float = list[i][0]
		var e: Enemy = list[i][1]
		var sp: Vector2 = list[i][2]
		var dir := sp - center
		# За спиной проекция зеркальна — разворачиваем
		if list[i][3]:
			dir = -dir
			if dir.length() < 1.0:
				dir = Vector2(0, 1)
		var ang := dir.angle()
		# Точка на краю эллипса, вписанного в экран с отступом
		var half := center - Vector2(edge_margin, edge_margin)
		var d := dir.normalized()
		var k := 1.0 / sqrt(pow(d.x / half.x, 2.0) + pow(d.y / half.y, 2.0))
		var p := center + d * k
		var t := clampf(dist / max_distance, 0.0, 1.0)
		var sz := lerpf(near_size, far_size, t)
		var col := Color(1, 1, 1, lerpf(1.0, 0.45, t))
		if e.kind == Enemy.Kind.BOSS:
			col = Color(1.0, 0.85, 0.4, col.a)
			sz *= 1.25
		shown.append([p, ang, sz, col])

func _draw() -> void:
	for s in shown:
		var p: Vector2 = s[0]
		var sz: float = s[2]
		draw_set_transform(p, s[1], Vector2.ONE)
		if _tex:
			draw_texture_rect(_tex, Rect2(-sz * 0.5, -sz * 0.5, sz, sz), false, s[3])
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(sz * 0.5, 0), Vector2(-sz * 0.4, -sz * 0.4), Vector2(-sz * 0.4, sz * 0.4)]), Color(0.9, 0.15, 0.1, (s[3] as Color).a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
