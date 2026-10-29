extends Control
class_name OffscreenIndicators
## Индикаторы врагов за экраном (GDD 18): красный треугольник с черепом (hud_offscreen) на краю экрана,
## остриё — в сторону врага. Ближние крупнее и ярче, босс — золотой. Только _draw, раз в кадр.
## Выключаются в настройках ([hud] offscreen). Плюс «где молот» (П5): Мьёльнир не в руке и вне поля зрения —
## иконка молота на краю экрана (не выключается вместе с врагами: без неё молот легко забыть).

## Дальше этого враг не показывается (м)
@export var max_distance: float = 30.0
## Сколько индикаторов максимум (ближайшие)
@export var max_count: int = 8
## Размер индикатора у ближнего / дальнего врага (px)
@export var near_size: float = 40.0
@export var far_size: float = 24.0
## Отступ от края экрана (px)
@export var edge_margin: float = 46.0
## Иконка «где молот» (px) и её цвет
@export var hammer_size: float = 44.0
@export var hammer_color: Color = Color(0.6, 0.88, 1.0, 1.0)

var player: Player
var enabled: bool = true
var _tex: Texture2D
## Что сейчас нарисовано: [позиция, угол, размер, цвет] — для тестов
var shown: Array = []
## Иконка молота на краю: [позиция, угол стрелки, размер] или пусто — для тестов
var hammer_shown: Array = []
var _hammer_tex: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.full_rect(self)
	_tex = UISkin.texture("hud_offscreen")
	_hammer_tex = UISkin.texture("hud_mjolnir_thrown")
	enabled = bool(GameSettings.get_value("hud", "offscreen"))

func _process(_delta: float) -> void:
	var before := shown.size() + hammer_shown.size()
	shown.clear()
	hammer_shown.clear()
	if player and is_instance_valid(player) and not player.is_dead:
		if enabled:
			_collect()
		_collect_hammer()
	if not shown.is_empty() or not hammer_shown.is_empty() or before > 0:
		queue_redraw()

## Точка на краю экрана (эллипс с отступом) в сторону мировой точки pos и угол; пусто — точка на экране.
func edge_point(pos: Vector3) -> Array:
	var cam := player.camera
	var vp := get_viewport_rect().size
	var center := vp * 0.5
	var behind := cam.is_position_behind(pos)
	if absf((cam.global_transform.affine_inverse() * pos).z) < 0.05:
		pos -= cam.global_transform.basis.z * 0.1
	var sp := cam.unproject_position(pos)
	if not behind and Rect2(Vector2.ZERO, vp).grow(-8.0).has_point(sp):
		return []
	var dir := sp - center
	if behind:
		dir = -dir
		if dir.length() < 1.0:
			dir = Vector2(0, 1)
	var half := center - Vector2(edge_margin, edge_margin)
	var d := dir.normalized()
	var k := 1.0 / sqrt(pow(d.x / half.x, 2.0) + pow(d.y / half.y, 2.0))
	return [center + d * k, dir.angle()]

## Мьёльнир не в руке и вне поля зрения — где он (воткнут, лежит, летит)
func _collect_hammer() -> void:
	var m := player.mjolnir
	if FeelSwitch.is_old(&"hammer_recall"):
		return
	if m == null or m.in_hand or m.projectile == null or not is_instance_valid(m.projectile) or not m.projectile.is_inside_tree():
		return
	var e := edge_point(m.projectile.global_position)
	if e.is_empty():
		return
	hammer_shown = [e[0], e[1], hammer_size]

func _collect() -> void:
	var cam := player.camera
	var vp := get_viewport_rect().size
	var center := vp * 0.5
	var inner := Rect2(Vector2.ZERO, vp).grow(-8.0)
	var list: Array = []
	var to_cam := cam.global_transform.affine_inverse()
	var cam_back := cam.global_transform.basis.z
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.is_dead or not e.is_inside_tree():
			continue
		var pos := e.global_position + Vector3.UP * 1.2
		var dist := pos.distance_to(cam.global_position)
		if dist > max_distance:
			continue
		var behind := cam.is_position_behind(pos)
		# Точка в плоскости камеры (глубина 0) — unproject_position падает с ошибкой «p.d == 0»:
		# сдвигаем её чуть вперёд вдоль взгляда (направление на краю экрана то же)
		if absf((to_cam * pos).z) < 0.05:
			pos -= cam_back * 0.1
		var sp := cam.unproject_position(pos)
		if not behind and inner.has_point(sp):
			continue
		list.append([dist, e, sp, behind])
	# Точки появления волны (Room.spawn_telegraph, П7): за краем экрана — красная стрелка
	for n in get_tree().get_nodes_in_group("spawn_telegraphs"):
		var pos := (n as Node3D).global_position + Vector3.UP * 1.0
		var dist := pos.distance_to(cam.global_position)
		var behind := cam.is_position_behind(pos)
		if absf((to_cam * pos).z) < 0.05:
			pos -= cam_back * 0.1
		var sp := cam.unproject_position(pos)
		if not behind and inner.has_point(sp):
			continue
		list.append([minf(dist, 1.0), null, sp, behind])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(list.size(), max_count):
		var dist: float = list[i][0]
		var e: Enemy = list[i][1] as Enemy
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
		if e == null:
			col = Color(1.0, 0.35, 0.2, 1.0)
			sz = near_size * 1.1
		elif e.kind == Enemy.Kind.BOSS:
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
	if not hammer_shown.is_empty():
		var hp: Vector2 = hammer_shown[0]
		var hs: float = hammer_shown[2]
		# Стрелка-остриё к молоту и сама иконка (прямо, не повёрнута)
		draw_set_transform(hp, hammer_shown[1], Vector2.ONE)
		draw_colored_polygon(PackedVector2Array([Vector2(hs * 0.75, 0), Vector2(hs * 0.45, -hs * 0.2), Vector2(hs * 0.45, hs * 0.2)]), hammer_color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(hp, hs * 0.55, Color(0.05, 0.07, 0.1, 0.75))
		if _hammer_tex:
			draw_texture_rect(_hammer_tex, Rect2(hp - Vector2(hs, hs) * 0.5, Vector2(hs, hs)), false, hammer_color)
		else:
			draw_rect(Rect2(hp - Vector2(hs * 0.3, hs * 0.3), Vector2(hs * 0.6, hs * 0.6)), hammer_color)
