extends Node
class_name SceneBuilder
## Генератор сцен и ресурсов прототипа.
## Запуск: godot --headless --path . res://tools/build_scenes.tscn
## Создаёт: игрока, врагов, бочки/ящики, обычные боевые залы (room_defs) + зал-ларёк, тела, руны, сцену игры и UI-сцены.
## Перезаписывает только свои файлы. Арены боссов и сюжетные залы (MANUAL_SCENES) — ручные сцены:
## правятся в редакторе, генератор их не создаёт и не перезаписывает (_save отказывается).

const WORLD := 1
const PLAYER_L := 1 << 1
const ENEMY_L := 1 << 2
const PROPS_L := 1 << 3
const PROJ_L := 1 << 4
const TRIGGER_L := 1 << 5
const DEBRIS_L := 1 << 6

## Ручные сцены: арены боссов и сюжетные залы. Генератор их не трогает (проверка в _save и в tests/generator_test).
const MANUAL_SCENES: Array[String] = [
	"res://rooms/boss_arena.tscn",
	"res://rooms/sven_arena.tscn",
]

var _mats := {}

## Компоненты (этап 4 рефакторинга): логика по файлам tools/build/*.gd, состояние — поля выше.
var resources: GenResources
var props: GenProps
var enemies: GenEnemies
var player: GenPlayer
var rooms: GenRooms
var room_floor: GenRoomFloor
var ui: GenUi

func _init() -> void:
	resources = GenResources.new(self)
	props = GenProps.new(self)
	enemies = GenEnemies.new(self)
	player = GenPlayer.new(self)
	rooms = GenRooms.new(self)
	room_floor = GenRoomFloor.new(self)
	ui = GenUi.new(self)

func _ready() -> void:
	resources.build_resources()
	props.build_props()
	enemies.build_enemies()
	player.build_player()
	rooms.build_dress()
	rooms.build_rooms()
	ui.build_ui_scenes()
	ui.build_game()
	print("build_scenes: готово")
	get_tree().quit(0)

# ---------------- Общие помощники ----------------

func _own(node: Node, owner: Node) -> void:
	for c in node.get_children():
		# Внутренности руки/персонажа строятся при запуске — в сцену их не сохраняем
		if node is ViewmodelArm or node is HumanoidModel:
			continue
		c.owner = owner
		if c.scene_file_path == "":
			_own(c, owner)

func _save(root: Node, path: String) -> void:
	if path in MANUAL_SCENES:
		push_error("build_scenes: %s — ручная сцена (MANUAL_SCENES), не перезаписываю" % path)
		root.free()
		return
	_own(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed %s: %d" % [path, err])
		return
	err = ResourceSaver.save(ps, path)
	if err != OK:
		push_error("save failed %s: %d" % [path, err])
	else:
		print("  сохранено: ", path)
	root.free()

func _mat(key: String, color: Color, rough: float = 0.85, noise: bool = true, emission: float = 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if noise:
		var tex := NoiseTexture2D.new()
		var n := FastNoiseLite.new()
		n.frequency = 0.04
		n.fractal_octaves = 4
		tex.noise = n
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		var grad := Gradient.new()
		grad.set_color(0, Color(0.72, 0.72, 0.72))
		grad.set_color(1, Color(1.0, 1.0, 1.0))
		tex.color_ramp = grad
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.35, 0.35, 0.35)
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m

## Статичный блок: StaticBody3D + коробка-коллизия + меш. (Не CSG: CSG строит коллизию с задержкой,
## и в первые кадры игрок и бочки проваливались сквозь пол.)
const QV := "res://assets/quaternius/village/"
const QP := "res://assets/quaternius/props/"

## Материал из текстур Quaternius Medieval Village с трипланарной развёрткой (для блоков, пола, колонн).
func _tex_mat(key: String, tex: String, tint: Color = Color.WHITE, uv: float = 0.5, rough: float = 0.9) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(QV + "T_%s_BaseColor.png" % tex)
	if ResourceLoader.exists(QV + "T_%s_Normal.png" % tex):
		m.normal_enabled = true
		m.normal_texture = load(QV + "T_%s_Normal.png" % tex)
	if ResourceLoader.exists(QV + "T_%s_Roughness.png" % tex):
		m.roughness_texture = load(QV + "T_%s_Roughness.png" % tex)
	m.albedo_color = tint
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	_mats[key] = m
	return m

## Рисованные текстуры Мидгарда (assets/textures/midgard/, комплект владельца) вместо текстур Quaternius — только там,
## где по кадрам стало лучше (PROGRESS.md «Графика мира»): каменные блоки — stone_wall (те же рисованные камни,
## что у стен MegaKit, но подробнее RockTrim). Пол зала — ключ "floor_tex" (деревня — dirt_straw). Доски wood_floor
## на блоках и полу хуже WoodTrim/Brick (плоские ящики без кромок, рыжий пол двора) — не применены; thatch — некуда (крыш нет).
const MIDGARD_BLOCKS := {"stone_dark": "stone_wall"}
const MT := "res://assets/textures/midgard/"

## Материал из рисованной текстуры мира (только цвет, без карт нормалей), трипланарный по миру.
func _world_tex_mat(key: String, tex: String, tint: Color = Color.WHITE, uv: float = 0.25, rough: float = 0.92) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(MT + tex + ".webp")
	m.albedo_color = tint
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(uv, uv, uv)
	_mats[key] = m
	return m

## Экземпляр модели (gltf) как обычный узел сцены.
func _model(parent: Node, name: String, path: String, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Node3D:
	var n := (load(path) as PackedScene).instantiate() as Node3D
	n.name = name
	n.position = pos
	n.rotation_degrees = rot_deg
	n.scale = scl
	parent.add_child(n)
	return n

## Ряд стеновых секций Quaternius (2 м шириной, 3.12 м высотой) вдоль отрезка, в 2 ряда по высоте.
## yaw: 0 — стена вдоль X, лицом к +Z; 180 — к -Z; 90 — вдоль Z, лицом к +X; -90 — к -X.
func _wall_row(parent: Node, prefix: String, start: Vector3, length: float, yaw: float, rows: int = 2, piece: String = "Wall_UnevenBrick_Straight") -> void:
	var n := maxi(1, int(ceil(length / 2.0 - 0.01)))
	var sx := length / (2.0 * n)
	var dir := Vector3(cos(deg_to_rad(yaw)), 0, -sin(deg_to_rad(yaw)))
	for row in rows:
		for i in n:
			var c := start + dir * (2.0 * sx * (i + 0.5))
			c.y = start.y + row * 3.12
			_model(parent, "%s_%d_%d" % [prefix, row, i], QV + piece + ".gltf", c, Vector3(0, yaw, 0), Vector3(sx, 1, 1))

## Дом из модулей Medieval Village MegaKit вокруг блока-дома (коллизию и плоскую крышу даёт сам блок):
## стены с окнами (высота — по блоку), дверь посередине стороны door ("s"/"n"/"e"/"w"), угловые столбы, труба.
## style: "Plaster" | "UnevenBrick".
func _house(parent: Node, name: String, center: Vector3, size: Vector3, door: String, style: String = "Plaster") -> void:
	const OUT := 0.1
	var root := Node3D.new()
	root.name = name
	parent.add_child(root)
	var base := center.y - size.y / 2.0
	var sy := size.y / 3.12
	var hx := size.x / 2.0
	var hz := size.z / 2.0
	# [имя стороны, начало, длина, yaw] — yaw как у _wall_row (0 — лицом к +Z, 90 — к +X …)
	var sides := [
		["s", Vector3(center.x - hx, base, center.z + hz + OUT), size.x, 0.0],
		["n", Vector3(center.x + hx, base, center.z - hz - OUT), size.x, 180.0],
		["e", Vector3(center.x + hx + OUT, base, center.z + hz), size.z, 90.0],
		["w", Vector3(center.x - hx - OUT, base, center.z - hz), size.z, -90.0],
	]
	for sd in sides:
		var length: float = sd[2]
		var yaw: float = sd[3]
		var n := maxi(1, int(round(length / 2.0)))
		var sx := length / (2.0 * n)
		var dir := Vector3(cos(deg_to_rad(yaw)), 0, -sin(deg_to_rad(yaw)))
		for i in n:
			var piece := "Wall_%s_Straight" % style
			if sd[0] == door and i == n / 2:
				piece = "Wall_%s_Door_Flat" % style
			elif i % 2 == 1 or n == 1:
				piece = "Wall_%s_Window_Wide_Flat" % style
			var c: Vector3 = sd[1] + dir * (2.0 * sx * (i + 0.5))
			_model(root, "%s_%s_%d" % [name, sd[0], i], QV + piece + ".gltf", c, Vector3(0, yaw, 0), Vector3(sx, sy, 1))
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_model(root, "%s_corner_%d_%d" % [name, int(cx), int(cz)], QV + "Corner_Exterior_Wood.gltf",
				Vector3(center.x + cx * (hx + OUT), base, center.z + cz * (hz + OUT)), Vector3.ZERO, Vector3(1.4, size.y / 3.0, 1.4))
	_model(root, name + "_chimney", QV + "Prop_Chimney.gltf", Vector3(center.x + hx - 0.8, base + size.y, center.z - hz + 0.8), Vector3.ZERO, Vector3.ONE * 0.55)

func _box(parent: Node, name: String, center: Vector3, size: Vector3, mat: Material, collide: bool = true) -> Node3D:
	var root: Node3D
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = WORLD
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		root = sb
	else:
		root = Node3D.new()
	root.name = name
	root.position = center
	parent.add_child(root)
	if mat == null:
		return root
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _boxmesh(size)
	mi.material_override = mat
	root.add_child(mi)
	return root

## Разрушаемый балкон (rooms/balcony.gd): StaticBody3D — настил «Deck»/«Mesh» и столбы до пола по переднему краю.
## posts = false — без столбов (мост/настил между опорами); slam = true — ломается ударом-приземлением сверху.
func _balcony(parent: Node, name: String, center: Vector3, size: Vector3, mat: Material, posts: bool = true, slam: bool = false) -> Node3D:
	var sb := StaticBody3D.new()
	sb.name = name
	sb.set_script(load("res://rooms/balcony.gd"))
	if slam:
		sb.set("slam_breakable", true)
	sb.collision_layer = WORLD
	sb.collision_mask = 0
	sb.position = center
	parent.add_child(sb)
	var cs := CollisionShape3D.new()
	cs.name = "Deck"
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _boxmesh(size)
	mi.material_override = mat
	sb.add_child(mi)
	if not posts:
		return sb
	# Столбы — по краю, обращённому в зал (по X к центру), через каждые ~5 м
	var post_h := center.y - size.y * 0.5
	var edge_x := -signf(center.x) * (size.x * 0.5 - 0.25)
	var n := maxi(2, int(round(size.z / 5.0)) + 1)
	for i in n:
		var z := lerpf(-size.z * 0.5 + 0.3, size.z * 0.5 - 0.3, float(i) / (n - 1))
		var pc := CollisionShape3D.new()
		pc.name = "PostShape%d" % i
		var pb := BoxShape3D.new()
		pb.size = Vector3(0.35, post_h, 0.35)
		pc.shape = pb
		pc.position = Vector3(edge_x, -center.y + post_h * 0.5, z)
		sb.add_child(pc)
		var pm := MeshInstance3D.new()
		pm.name = "Post%d" % i
		pm.mesh = _boxmesh(Vector3(0.35, post_h, 0.35))
		pm.material_override = mat
		pm.position = pc.position
		sb.add_child(pm)
	return sb

func _cyl(parent: Node, name: String, center: Vector3, radius: float, height: float, mat: Material) -> Node3D:
	var sb := StaticBody3D.new()
	sb.name = name
	sb.collision_layer = WORLD
	sb.collision_mask = 0
	sb.position = center
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _cylmesh(radius, radius, height)
	mi.material_override = mat
	sb.add_child(mi)
	parent.add_child(sb)
	return sb

func _mesh(parent: Node, name: String, mesh: Mesh, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO, layer: int = 1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.layers = layer
	if layer == 2:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _boxmesh(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m

func _cylmesh(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = 12
	return m

# ---------------- Залы ----------------

## Описание залов. Координаты в метрах; y — высота центра блока.
## Блоки: [центр, размер, материал]; врагов: [kind, позиция, волна, (сколько, разброс м, вход)]; пропсы: [тип, позиция].
## Волны по GDD 12.5: корм толпой (60–70 %), бойцы, 1–2 особых на волну.
## Графика мира (комплект владельца): "decor" — картинки на стенах [ключ assets/decor/, позиция, поворот Y, высота м],
## "decals" — декали на полу [ключ assets/decals/, позиция, поворот Y, размер м, (glow)], "no_auto" — без авто-знамён/щитов
## на стенах "north"/"south"/"side", "floor_tex" — рисованная текстура пола (assets/textures/midgard/<ключ>).
## Данные каждого зала — tools/rooms/<file>.gd (static def()); порядок списка — порядок room_defs().
const ROOM_DATA := [
	preload("res://tools/rooms/room_01.gd"),
	preload("res://tools/rooms/room_02.gd"),
	preload("res://tools/rooms/room_03.gd"),
	preload("res://tools/rooms/room_04.gd"),
	preload("res://tools/rooms/room_05.gd"),
	preload("res://tools/rooms/room_06.gd"),
	preload("res://tools/rooms/room_07.gd"),
	preload("res://tools/rooms/room_08.gd"),
	preload("res://tools/rooms/room_09.gd"),
	preload("res://tools/rooms/room_10.gd"),
	preload("res://tools/rooms/room_11.gd"),
]

func room_defs() -> Array:
	var r: Array = []
	for data in ROOM_DATA:
		r.append(data.def())
	return r

## Четырёхугольник: две диагональные точки, высота линейно меняется по Z.

## Зал-ларёк (блок К, GDD 13): тихий зал без волн, ларёк посередине, ящики по углам.
func shop_room_def() -> Dictionary:
	return preload("res://tools/rooms/shop_room.gd").def()

# --- Функции компонентов, доступные на SceneBuilder ---
# API (## API →) и приватные функции, которые зовут другие файлы (## совместимость →).
# Реализация и описание — в компоненте.

# GenResources (gen_resources.gd)

## API → resources.build_resources
func build_resources() -> void:
	resources.build_resources()

# GenProps (gen_props.gd)

## API → props.build_props
func build_props() -> void:
	props.build_props()

# GenEnemies (gen_enemies.gd)

## API → enemies.build_enemies
func build_enemies() -> void:
	enemies.build_enemies()

# GenPlayer (gen_player.gd)

## API → player.build_player
func build_player() -> void:
	player.build_player()

# GenRooms (gen_rooms.gd)

## API → rooms.build_dress
func build_dress() -> void:
	rooms.build_dress()

## API → rooms.build_rooms
func build_rooms() -> void:
	rooms.build_rooms()

# GenUi (gen_ui.gd)

## API → ui.build_ui_scenes
func build_ui_scenes() -> void:
	ui.build_ui_scenes()

## API → ui.build_game
func build_game() -> void:
	ui.build_game()
