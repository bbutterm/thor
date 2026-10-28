extends RefCounted
class_name RoomDresser
## Блок Б0 «Одеть залы»: убирает вид «как в Майнкрафте». Работает по уже собранному дереву зала (узлы
## Geometry/Floor, WallN_L…WallE, Block*, Pillar*, Balconies, Torches, Banners, JumpPads, Props) — поэтому
## одинаково одевает и залы генератора (tools/build_scenes.gd → _build_room), и ручные арены
## (tools/dress_arenas.tscn). Коллизия НЕ меняется: коробки остаются StaticBody3D, меняется только вид.
## Что делает:
##  - пол — меш-сетка с запечённым затемнением у стен, блоков и колонн (цвет вершин; GL Compatibility без SSAO);
##  - видимые коробки — скошенные меши (фаска по рёбрам) на общем шейдере world_surface (трипланар без повторов,
##    мох/грязь/сажа по шуму), рамы из балок и столбов у деревянных, каменный кант и угловые колонны у каменных,
##    квадратная башня — круглая с деревянной площадкой;
##  - стены — частокол по верху, колонны в углах и у ворот, валуны и обломки у основания, тёмная полоса
##    на стыке стены с полом, плющ; разброс высот верхнего ряда модулей;
##  - 10–20 декалей владельца на пол (трещины, подпалины, ихор, следы), кости и черепа в углах;
##  - даль за стенами — сцена rooms/backdrop_midgard.tscn (горы-скалы, сосны, драккары, вода).
## Повторяющиеся мелкие детали — MultiMesh (один draw call на вид), материалы — общие файлы
## rooms/materials/*.tres без instance uniform, меши — rooms/meshes/*.res (собирает build_assets()).
## Все случайности — от seed зала: перезапуск генератора даёт тот же зал.

const QV := "res://assets/quaternius/village/"
const QP := "res://assets/quaternius/props/"
const QS := "res://assets/quaternius/pirate/"
const MT := "res://assets/textures/midgard/"
const MESH_DIR := "res://rooms/meshes/"
const MAT_DIR := "res://rooms/materials/"
const SHADER := "res://shaders/world_surface.gdshader"
const NOISE := QV + "T_Noise_Terrain.png"
const BACKDROP_SCENE := "res://rooms/backdrop_midgard.tscn"
## Высота видимых стен (2 ряда модулей MegaKit по 3.12 м)
const WALL_TOP := 6.24

## Меши и их материалы — RoomDress.MESHES (rooms/room_dress.gd: нужен и в игре для прогрева)
const MESHES := RoomDress.MESHES

## Поверхности на шейдере world_surface: ключ → параметры (имена — uniform шейдера; текстуры — путями)
const SURFACES := {
	# Пол двора: кирпич MegaKit с нормалями, пятна грязи, анти-повтор
	"surface_floor_brick": {"albedo_tex": QV + "T_Brick_BaseColor.png", "normal_tex": QV + "T_Brick_Normal.png", "normal_strength": 0.8,
		"tint": Color(0.74, 0.69, 0.64), "uv_scale": 0.35, "overlay_tex": MT + "dirt_straw.webp", "overlay_uv": 0.3,
		"overlay_color": Color(0.82, 0.76, 0.7), "overlay_amount": 0.36, "overlay_scale": 0.075, "overlay_softness": 0.16,
		"overlay_top": 0.0, "macro_strength": 0.32, "grime_strength": 0.0},
	# Утоптанная земля с соломой (рисованная владельца)
	"surface_floor_dirt": {"albedo_tex": MT + "dirt_straw.webp", "tint": Color(0.92, 0.9, 0.88), "uv_scale": 0.3,
		"overlay_tex": QV + "T_UnevenBrick_BaseColor.png", "overlay_uv": 0.45, "overlay_color": Color(0.78, 0.74, 0.7),
		"overlay_amount": 0.3, "overlay_scale": 0.07, "overlay_softness": 0.08, "overlay_top": 0.0, "macro_strength": 0.35, "grime_strength": 0.0},
	# Каменные блоки (рисованная stone_wall владельца): мох сверху, грязь у основания
	"surface_stone": {"albedo_tex": MT + "stone_wall.webp", "tint": Color(0.9, 0.9, 0.92), "uv_scale": 0.3,
		"overlay_color": Color(0.33, 0.37, 0.2), "overlay_amount": 0.2, "overlay_scale": 0.16, "overlay_top": 0.45, "macro_strength": 0.3},
	# Валуны и обломки скал (RockTrim с нормалями)
	"surface_rock": {"albedo_tex": QV + "T_RockTrim_BaseColor.png", "normal_tex": QV + "T_RockTrim_Normal.png", "normal_strength": 1.0,
		"tint": Color(0.7, 0.68, 0.7), "uv_scale": 0.9, "overlay_color": Color(0.3, 0.35, 0.18), "overlay_amount": 0.32, "overlay_scale": 0.5,
		"overlay_top": 0.8, "macro_strength": 0.25, "grime_height": 0.35},
	# Скалы за стенами (крупнее, без грязи)
	"surface_cliff": {"albedo_tex": QV + "T_RockTrim_BaseColor.png", "tint": Color(0.42, 0.38, 0.42), "uv_scale": 0.12,
		"overlay_color": Color(0.22, 0.28, 0.14), "overlay_amount": 0.4, "overlay_scale": 0.05, "overlay_top": 0.9, "macro_strength": 0.35, "grime_strength": 0.0},
	# Брёвна, частокол, столбы — WoodTrim, копоть пятнами
	"surface_wood": {"albedo_tex": QV + "T_WoodTrim_BaseColor.png", "normal_tex": QV + "T_WoodTrim_Normal.png", "normal_strength": 0.7,
		"tint": Color(0.72, 0.62, 0.54), "uv_scale": 0.5, "overlay_color": Color(0.12, 0.1, 0.09), "overlay_amount": 0.22, "overlay_scale": 0.2,
		"overlay_top": 0.0, "macro_strength": 0.3, "grime_height": 0.6},
	# Доски настилов и деревянных помостов (рисованная wood_floor владельца)
	"surface_plank": {"albedo_tex": MT + "wood_floor.webp", "tint": Color(0.86, 0.8, 0.74), "uv_scale": 0.35,
		"overlay_color": Color(0.16, 0.12, 0.1), "overlay_amount": 0.2, "overlay_scale": 0.15, "overlay_top": 0.2, "macro_strength": 0.3},
	# Колонны залов (UnevenBrick): мох у основания и сверху
	"surface_pillar": {"albedo_tex": QV + "T_UnevenBrick_BaseColor.png", "normal_tex": QV + "T_UnevenBrick_Normal.png", "normal_strength": 0.8,
		"tint": Color(0.82, 0.8, 0.77), "uv_scale": 0.45, "overlay_color": Color(0.33, 0.37, 0.2), "overlay_amount": 0.16, "overlay_scale": 0.2,
		"overlay_top": 0.4, "macro_strength": 0.25},
	# Земля за стенами (даль): крупно, трава-мох пятнами
	"surface_ground": {"albedo_tex": MT + "dirt_straw.webp", "tint": Color(0.7, 0.62, 0.55), "uv_scale": 0.1, "detail_scale": 0.37,
		"overlay_color": Color(0.24, 0.3, 0.14), "overlay_amount": 0.5, "overlay_scale": 0.03, "overlay_top": 0.0, "macro_scale": 0.012,
		"macro_strength": 0.45, "grime_strength": 0.0},
}

## Декали на пол (assets/decals/): ключ → [вес, мин. размер, макс. размер]
const FLOOR_DECALS := {
	"slam_crack_small": [3.0, 1.2, 2.0], "slam_crack_medium": [2.0, 1.8, 2.8], "slam_crack_large": [0.6, 2.6, 3.4],
	"scorch": [2.0, 1.6, 3.0], "ichor_splat_01": [0.5, 1.0, 1.6], "ichor_splat_02": [0.5, 1.0, 1.6],
	"ichor_splat_03": [0.5, 1.0, 1.6], "ichor_splat_04": [0.5, 1.0, 1.6], "footprints_giant": [0.5, 2.6, 3.4],
}

# ---------------- Ресурсы (меши и материалы) ----------------

## Собрать общие меши (rooms/meshes/) и материалы (rooms/materials/). Генератор — перед залами.
static func build_assets() -> void:
	DirAccess.make_dir_recursive_absolute(MESH_DIR)
	DirAccess.make_dir_recursive_absolute(MAT_DIR)
	var shader := load(SHADER) as Shader
	var noise := load(NOISE) as Texture2D
	for key in SURFACES:
		var m := ShaderMaterial.new()
		m.resource_name = key
		m.shader = shader
		m.set_shader_parameter("noise_tex", noise)
		var spec: Dictionary = SURFACES[key]
		for p in spec:
			var v: Variant = spec[p]
			m.set_shader_parameter(p, load(v) if v is String else v)
		_save_res(m, MAT_DIR + key + ".tres")
	# Копии материалов MegaKit (общие на все залы вместо копии в каждом gltf)
	for pair in [["rocktrim", QV + "Prop_Brick1.gltf"], ["woodtrim", QV + "HoleCover_Straight.gltf"]]:
		var src := _first_mesh(pair[1])
		var mat := (src[0] as Mesh).surface_get_material(0).duplicate() as Material
		mat.resource_name = pair[0]
		_save_res(mat, MAT_DIR + pair[0] + ".tres")
	# Тёмная полоса на стыке стены с полом: снизу 0.6 → сверху 0
	var grime := StandardMaterial3D.new()
	grime.resource_name = "grime"
	grime.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grime.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grime.cull_mode = BaseMaterial3D.CULL_DISABLED
	grime.albedo_color = Color(0.05, 0.035, 0.03, 1.0)
	var gt := GradientTexture2D.new()
	var gg := Gradient.new()
	gg.set_color(0, Color(1, 1, 1, 0.0))
	gg.set_color(1, Color(1, 1, 1, 0.62))
	gg.add_point(0.6, Color(1, 1, 1, 0.22))
	gt.gradient = gg
	gt.width = 4
	gt.height = 64
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	grime.albedo_texture = gt
	_save_res(grime, MAT_DIR + "grime.tres")
	var pine := StandardMaterial3D.new()
	pine.resource_name = "pine"
	pine.vertex_color_use_as_albedo = true
	pine.albedo_color = Color(0.34, 0.42, 0.32)
	pine.roughness = 1.0
	_save_res(pine, MAT_DIR + "pine.tres")
	var water := StandardMaterial3D.new()
	water.resource_name = "water"
	water.albedo_color = Color(0.09, 0.1, 0.14)
	water.roughness = 0.12
	water.metallic_specular = 0.7
	_save_res(water, MAT_DIR + "water.tres")
	# Меши
	for key in MESHES:
		var src: String = MESHES[key][0]
		var mesh: Mesh = null
		if src != "":
			var fm := _first_mesh(src)
			mesh = _bake_mesh(fm[0], fm[1])
		else:
			mesh = _procedural(key)
		mesh.resource_name = key
		_save_res(mesh, MESH_DIR + key + ".res")

static func _save_res(r: Resource, path: String) -> void:
	var err := ResourceSaver.save(r, path)
	if err != OK:
		push_error("room_dresser: не сохранён %s (%d)" % [path, err])
	r.take_over_path(path)

## Первый меш gltf и его трансформ относительно корня сцены: [Mesh, Transform3D].
static func _first_mesh(path: String) -> Array:
	var n := (load(path) as PackedScene).instantiate() as Node3D
	var out: Array = [null, Transform3D.IDENTITY]
	var stack: Array = [[n, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_front()
		var node: Node = e[0]
		var xf: Transform3D = e[1]
		if node is Node3D and node != n:
			xf = xf * (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			out = [(node as MeshInstance3D).mesh, xf]
			break
		for c in node.get_children():
			stack.append([c, xf])
	n.free()
	return out

## Меш с запечённым трансформом узла gltf (поверхности и их материалы сохраняются).
static func _bake_mesh(mesh: Mesh, xf: Transform3D) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(mesh, s, xf)
		st.set_material(mesh.surface_get_material(s))
		st.commit(out)
	return out

## Процедурные меши: кол частокола, бревно, сосна, квад полосы-затемнения.
static func _procedural(key: String) -> Mesh:
	match key:
		"stake":
			# Кол: цилиндр r = 1, от y = 0 до 1, и остриё до 1.3 (масштабируется экземпляром)
			var st := _new_st()
			_cyl_band(st, 0.0, 1.0, 1.0, 1.0, 7, Color(0.8, 0.8, 0.8), Color.WHITE)
			_cyl_band(st, 1.0, 1.3, 1.0, 0.05, 7, Color.WHITE, Color.WHITE)
			return st.commit()
		"pilaster":
			# Колонна у стены/в углу: 12 граней, база и капитель шире (≈ 150 треугольников вместо 2.9 тыс.
			# у Corner_ExteriorWide_Brick — та дорого стоила на каждом факеле в GL Compatibility)
			var st := _new_st()
			var dark := Color(0.6, 0.6, 0.6)
			_cyl_band(st, 0.0, 0.25, 0.56, 0.56, 12, dark, dark)
			_cyl_band(st, 0.25, 0.32, 0.56, 0.47, 12, dark, Color(0.8, 0.8, 0.8))
			_cyl_band(st, 0.32, 0.9, 0.47, 0.44, 12, Color(0.8, 0.8, 0.8), Color.WHITE)
			_cyl_band(st, 0.9, 0.95, 0.44, 0.52, 12, Color.WHITE, Color.WHITE)
			_cyl_band(st, 0.95, 1.0, 0.52, 0.52, 12, Color.WHITE, Color.WHITE)
			_disc(st, 1.0, 0.52, 12, Color.WHITE)
			return st.commit()
		"log":
			# Бревно вдоль X: r = 1, длина 1 (от −0.5 до 0.5)
			var st := _new_st()
			_cyl_band(st, -0.5, 0.5, 1.0, 1.0, 8, Color.WHITE, Color.WHITE, true)
			return st.commit()
		"pine":
			# Сосна-силуэт ~10 м: ствол и четыре яруса конусов; цвет вершин — темнее книзу яруса
			var st := _new_st()
			var trunk := Color(0.32, 0.22, 0.16)
			_cyl_band(st, 0.0, 2.2, 0.28, 0.2, 6, trunk, trunk)
			var tiers := [[1.4, 4.6, 2.6], [3.6, 6.6, 2.1], [5.6, 8.4, 1.6], [7.4, 10.0, 1.05]]
			for t in tiers:
				var dark := Color(0.12, 0.17, 0.12)
				var lite := Color(0.3, 0.38, 0.26)
				_cyl_band(st, t[0], t[1], t[2], 0.02, 9, dark, lite)
				_disc(st, t[0], t[2], 9, Color(0.08, 0.1, 0.08))
			return st.commit()
		"grime":
			var q := QuadMesh.new()
			q.size = Vector2(1.0, 1.0)
			q.center_offset = Vector3(0, 0.5, 0)
			return q
	return BoxMesh.new()

static func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

## Треугольник лицом по нормали n (порядок обхода Godot — по часовой стрелке со стороны лица).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
		var tc := cb
		cb = cc
		cc = tc
	for v in [[a, ca], [b, cb], [c, cc]]:
		st.set_normal(n)
		st.set_color(v[1])
		st.set_uv(Vector2((v[0] as Vector3).x + (v[0] as Vector3).z, (v[0] as Vector3).y))
		st.add_vertex(v[0])

## Боковая поверхность усечённого конуса (вдоль Y; along_x — вдоль X).
static func _cyl_band(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, seg: int, c0: Color, c1: Color, along_x: bool = false) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p := [Vector3(cos(a0) * r0, y0, sin(a0) * r0), Vector3(cos(a1) * r0, y0, sin(a1) * r0),
			Vector3(cos(a1) * r1, y1, sin(a1) * r1), Vector3(cos(a0) * r1, y1, sin(a0) * r1)]
		var mid := (a0 + a1) * 0.5
		var slope := (r0 - r1) / maxf(y1 - y0, 0.001)
		var n := Vector3(cos(mid), slope, sin(mid)).normalized()
		if along_x:
			for k in 4:
				var v: Vector3 = p[k]
				p[k] = Vector3(v.y, v.x, v.z)
			n = Vector3(n.y, n.x, n.z)
		_tri(st, p[0], p[1], p[2], n, c0, c0, c1)
		_tri(st, p[0], p[2], p[3], n, c0, c1, c1)

## Диск-низ яруса сосны (смотрит вниз).
static func _disc(st: SurfaceTool, y: float, r: float, seg: int, c: Color) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		_tri(st, Vector3(0, y, 0), Vector3(cos(a0) * r, y, sin(a0) * r), Vector3(cos(a1) * r, y, sin(a1) * r), Vector3.DOWN, c, c, c)

# ---------------- Одевание зала ----------------

var rng := RandomNumberGenerator.new()
var root: Node3D
var opts: Dictionary
var dress: Node3D
var w: float = 20.0
var dep: float = 20.0
var gap: float = 4.0
## Ключ меша → Array[Transform3D] (в MultiMesh в конце)
var _mm: Dictionary = {}
## Габариты мешей (кеш)
var _aabb: Dictionary = {}
## [центр, размер, стиль, узел] — блоки зала
var _blocks: Array = []
## Колонны: [центр на полу, радиус]
var _pillars: Array = []
## Проёмы в полу из метаданных Geometry/Floor, в координатах X/Z.
var _floor_openings: Array[Rect2] = []
## Точки, рядом с которыми не кладём обломки и декали: [точка, радиус]
var _avoid: Array = []
var _mats: Dictionary = {}
## Сторона клетки, на которые режутся MultiMesh деталей, м (даль — крупнее)
var chunk_size: float = 9.0

func _init(seed_: int) -> void:
	rng.seed = seed_

## Одеть зал root. opts (ключ "dress" зала): floor ("brick" | "dirt" | "plank"), styles ({имя блока: стиль}),
## palisade, rubble, vines, decals (сколько), backdrop, bones — см. CLAUDE.md «Одевание залов».
func dress_room(root_: Node3D, opts_: Dictionary) -> void:
	root = root_
	opts = opts_
	var geo := root.get_node_or_null("Geometry")
	if geo == null:
		return
	var old := root.get_node_or_null("Dress")
	if old:
		root.remove_child(old)
		old.free()
	dress = Node3D.new()
	dress.name = "Dress"
	root.add_child(dress)
	_read_layout(geo)
	_floor(geo)
	for b in _blocks:
		_block(b)
	_pillar_dress(geo)
	_walls(geo)
	_timber_posts()
	_palisade_rows()
	_decals()
	if opts.get("bones", true):
		_bones()
	_flush()
	if opts.get("backdrop", true) and ResourceLoader.exists(BACKDROP_SCENE):
		_ground_skirt()
		var bd := (load(BACKDROP_SCENE) as PackedScene).instantiate()
		bd.name = "Backdrop"
		dress.add_child(bd)

## Габариты зала, блоки, колонны и запретные точки — по узлам сцены.
func _read_layout(geo: Node) -> void:
	_floor_openings.clear()
	var floor := geo.get_node_or_null("Floor")
	if floor:
		for rect in floor.get_meta("floor_openings", []):
			if rect is Rect2:
				_floor_openings.append(rect)
	var we := geo.get_node("WallE") as Node3D
	var ws := geo.get_node("WallS") as Node3D
	w = (we.position.x - 0.5) * 2.0
	dep = (ws.position.z - 0.5) * 2.0
	var nl := geo.get_node_or_null("WallN_L") as Node3D
	if nl:
		gap = w - 2.0 * _box_size(nl).x
	var styles: Dictionary = opts.get("styles", {})
	for c in geo.get_children():
		if c is StaticBody3D and String(c.name).begins_with("Block"):
			_blocks.append([(c as Node3D).position, _box_size(c), styles.get(String(c.name), "stone"), c])
		elif c is StaticBody3D and String(c.name).begins_with("Pillar") and not String(c.name).begins_with("PillarBase") and not String(c.name).begins_with("PillarCap"):
			var p := (c as Node3D).position
			_pillars.append([Vector3(p.x, 0, p.z), 1.05])
	var bals := root.get_node_or_null("Balconies")
	if bals:
		for c in bals.get_children():
			if c is StaticBody3D:
				_blocks.append([(c as Node3D).position, _box_size(c, "Deck"), "balcony", c])
	for b in _blocks:
		var c: Vector3 = b[0]
		var s: Vector3 = b[1]
		if b[2] == "deck" or b[2] == "balcony":
			continue
		if c.y - s.y * 0.5 < 0.2:
			_avoid.append([Vector3(c.x, 0, c.z), 0.0, s])
	var pads := root.get_node_or_null("JumpPads")
	if pads:
		for p in pads.get_children():
			_avoid.append([(p as Node3D).position, 2.4])
	var spawn := root.get_node_or_null("PlayerSpawn") as Node3D
	if spawn:
		_avoid.append([spawn.position, 1.8])
	var props := root.get_node_or_null("Props")
	if props:
		for p in props.get_children():
			if p is Node3D:
				_avoid.append([(p as Node3D).position, 0.9])
	# Проём выхода и коридор
	_avoid.append([Vector3(0, 0, -dep / 2.0), gap / 2.0 + 0.8])
	var stall := root.get_node_or_null("ShopStall") as Node3D
	if stall:
		_avoid.append([stall.position, 4.0])

func _box_size(n: Node, shape_name: String = "Shape") -> Vector3:
	var cs := n.get_node_or_null(shape_name) as CollisionShape3D
	if cs and cs.shape is BoxShape3D:
		return (cs.shape as BoxShape3D).size
	return Vector3.ONE

## Свободна ли точка пола (вне блоков, прыжковых рун, пропсов, проёма; r — свой радиус).
func _near_floor_opening(p: Vector3, r: float = 0.0) -> bool:
	for rect in _floor_openings:
		if rect.grow(r).has_point(Vector2(p.x, p.z)):
			return true
	return false

func _free(p: Vector3, r: float = 0.0) -> bool:
	if _near_floor_opening(p, r):
		return false
	for a in _avoid:
		var c: Vector3 = a[0]
		if a.size() > 2:
			var s: Vector3 = a[2]
			if absf(p.x - c.x) < s.x * 0.5 + r and absf(p.z - c.z) < s.z * 0.5 + r:
				return false
		elif Vector2(p.x - c.x, p.z - c.z).length() < float(a[1]) + r:
			return false
	for pl in _pillars:
		var c2: Vector3 = pl[0]
		if Vector2(p.x - c2.x, p.z - c2.z).length() < float(pl[1]) + r:
			return false
	return true

func _mat(key: String) -> Material:
	if not _mats.has(key):
		_mats[key] = load(MAT_DIR + key + ".tres")
	return _mats[key]

func _mesh_aabb(key: String) -> AABB:
	if not _aabb.has(key):
		_aabb[key] = (load(MESH_DIR + key + ".res") as Mesh).get_aabb()
	return _aabb[key]

func _add(key: String, xf: Transform3D) -> void:
	if not _mm.has(key):
		_mm[key] = []
	(_mm[key] as Array).append(xf)

## Трансформ, вписывающий габариты меша key в коробку size с центром center (поворот yaw, затем basis).
func _fit(key: String, center: Vector3, size: Vector3, yaw_deg: float = 0.0, extra: Basis = Basis.IDENTITY) -> Transform3D:
	var a := _mesh_aabb(key)
	var s := Vector3(size.x / maxf(a.size.x, 0.001), size.y / maxf(a.size.y, 0.001), size.z / maxf(a.size.z, 0.001))
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * extra * Basis.from_scale(s)
	return Transform3D(b, center - b * (a.position + a.size * 0.5))

## Все MultiMesh зала: по одному узлу на вид меша (один draw call), общий материал без instance uniform.
func _flush() -> void:
	var prev := dress.get_node_or_null("Scatter")
	if prev:
		dress.remove_child(prev)
		prev.free()
	var node := Node3D.new()
	node.name = "Scatter"
	dress.add_child(node)
	for key in _mm:
		var all: Array = _mm[key]
		if all.is_empty():
			continue
		# Куски по клеткам chunk_size: MultiMesh на весь зал задевает все факелы (в GL Compatibility каждый
		# свет — ещё проход по всему MultiMesh) и не отсекается камерой; клетка — 1–3 факела и честное отсечение
		var cells := {}
		for t in all:
			var o: Vector3 = (t as Transform3D).origin
			var cell := Vector2i(floori(o.x / chunk_size), floori(o.z / chunk_size))
			if not cells.has(cell):
				cells[cell] = []
			(cells[cell] as Array).append(t)
		for cell in cells:
			var list: Array = cells[cell]
			_scatter_node(node, key, list, "%s_%d_%d" % [key.to_pascal_case(), cell.x, cell.y] if cells.size() > 1 else key.to_pascal_case())
	_mm.clear()

func _scatter_node(node: Node3D, key: String, list: Array, nm: String) -> void:
	# Буфер MultiMesh в headless не сохраняется — DressScatter собирает его при загрузке из xforms
	var mmi := DressScatter.new()
	mmi.name = nm
	mmi.mesh = load(MESH_DIR + key + ".res") as Mesh
	mmi.xforms = DressScatter.pack(list)
	mmi.material_override = _mat(MESHES[key][1])
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Мелочь без теней (тени — 4 прохода каскадов на каждый вид)
	if key in ["grime", "brick_1", "brick_2", "brick_3", "brick_4", "tile", "rock_1", "rock_2", "rock_3", "rock_4", "rock_5"]:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mmi)

# ---------------- Пол ----------------

## Пол: сетка с затемнением в цвете вершин у стен, блоков и колонн (видимая часть коробки пола убрана).
func _floor(geo: Node) -> void:
	var fl := geo.get_node_or_null("Floor")
	if fl == null:
		return
	var old := fl.get_node_or_null("Mesh")
	if old:
		fl.remove_child(old)
		old.free()
	var kind: String = opts.get("floor", "brick")
	var mat := _mat("surface_floor_" + kind) if kind != "plank" else _mat("surface_plank")
	var cf := geo.get_node_or_null("CorridorFloor/Mesh") as MeshInstance3D
	if cf:
		cf.material_override = mat
	var xs := _grid_lines(w * 0.5, 0)
	var zs := _grid_lines(dep * 0.5, 2)
	# Добавляем после объединения близких линий: каждая граница точно сохранится.
	for rect in _floor_openings:
		xs.append(rect.position.x)
		xs.append(rect.end.x)
		zs.append(rect.position.y)
		zs.append(rect.end.y)
	xs = _unique_floor_lines(xs)
	zs = _unique_floor_lines(zs)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ao_cache := {}
	for iz in zs.size() - 1:
		for ix in xs.size() - 1:
			# Совпавшие линии допустимы, но нулевые ячейки не рисуем.
			if xs[ix + 1] <= xs[ix] or zs[iz + 1] <= zs[iz]:
				continue
			var mid := Vector3((xs[ix] + xs[ix + 1]) * 0.5, 0, (zs[iz] + zs[iz + 1]) * 0.5)
			if _near_floor_opening(mid):
				continue
			var q := [Vector3(xs[ix], 0, zs[iz]), Vector3(xs[ix + 1], 0, zs[iz]), Vector3(xs[ix + 1], 0, zs[iz + 1]), Vector3(xs[ix], 0, zs[iz + 1])]
			var cs: Array = []
			for v in q:
				var key := Vector2((v as Vector3).x, (v as Vector3).z)
				if not ao_cache.has(key):
					var a := _floor_ao(v)
					ao_cache[key] = Color(a, a, a)
				cs.append(ao_cache[key])
			_tri(st, q[0], q[1], q[2], Vector3.UP, cs[0], cs[1], cs[2])
			_tri(st, q[0], q[2], q[3], Vector3.UP, cs[0], cs[2], cs[3])
			# Видимые внутренние грани толщины исходного пола, без дополнительных узлов.
			if ix > 0 and _near_floor_opening(Vector3((xs[ix - 1] + xs[ix]) * 0.5, 0, mid.z)):
				_floor_cut_face(st, q[0], q[3], Vector3.LEFT)
			if ix < xs.size() - 2 and _near_floor_opening(Vector3((xs[ix + 1] + xs[ix + 2]) * 0.5, 0, mid.z)):
				_floor_cut_face(st, q[1], q[2], Vector3.RIGHT)
			if iz > 0 and _near_floor_opening(Vector3(mid.x, 0, (zs[iz - 1] + zs[iz]) * 0.5)):
				_floor_cut_face(st, q[0], q[1], Vector3.FORWARD)
			if iz < zs.size() - 2 and _near_floor_opening(Vector3(mid.x, 0, (zs[iz + 1] + zs[iz + 2]) * 0.5)):
				_floor_cut_face(st, q[3], q[2], Vector3.BACK)
	st.index()
	var mi := MeshInstance3D.new()
	mi.name = "FloorVisual"
	mi.mesh = st.commit()
	mi.material_override = mat
	dress.add_child(mi)

## Объединять только равные границы: близкий край проёма нельзя потерять.
func _unique_floor_lines(lines: PackedFloat32Array) -> PackedFloat32Array:
	lines.sort()
	var result := PackedFloat32Array()
	for v in lines:
		if result.is_empty() or v > result[result.size() - 1]:
			result.append(v)
	return result

func _floor_cut_face(st: SurfaceTool, a: Vector3, b: Vector3, normal: Vector3) -> void:
	var aa := _floor_ao(a)
	var ab := _floor_ao(b)
	var top_a := Color(aa, aa, aa)
	var top_b := Color(ab, ab, ab)
	var low_a := Color(aa * 0.7, aa * 0.7, aa * 0.7)
	var low_b := Color(ab * 0.7, ab * 0.7, ab * 0.7)
	var a_low := a + Vector3.DOWN
	var b_low := b + Vector3.DOWN
	_tri(st, a, b, b_low, normal, top_a, top_b, low_b)
	_tri(st, a, b_low, a_low, normal, top_a, low_b, low_a)

## Линии сетки пола по оси (0 — X, 2 — Z): края, сгущение у стен и у краёв блоков/колонн, остальное ~2.5 м.
func _grid_lines(half: float, axis: int) -> PackedFloat32Array:
	var vals: Array = [-half, half]
	for d in [0.35, 0.9, 1.7]:
		vals.append(-half + d)
		vals.append(half - d)
	var n := int(ceil(half * 2.0 / 2.5))
	for i in range(1, n):
		vals.append(-half + half * 2.0 * i / n)
	for b in _blocks:
		var c: Vector3 = b[0]
		var s: Vector3 = b[1]
		if c.y - s.y * 0.5 > 0.2:
			continue
		for sign in [-1.0, 1.0]:
			var e: float = c[axis] + sign * s[axis] * 0.5
			for d in [0.0, 0.4, 1.1]:
				vals.append(e + sign * d)
	for p in _pillars:
		var c: Vector3 = p[0]
		for d in [-1.9, -1.1, 0.0, 1.1, 1.9]:
			vals.append(c[axis] + d)
	vals.sort()
	var out := PackedFloat32Array()
	for v in vals:
		var fv := clampf(float(v), -half, half)
		if out.is_empty() or fv - out[out.size() - 1] > 0.15:
			out.append(fv)
	if out[out.size() - 1] < half:
		out[out.size() - 1] = half
	return out

## Затемнение точки пола: у стен (в углах — сильнее), у основания блоков и колонн.
func _floor_ao(p: Vector3) -> float:
	var hx := w * 0.5
	var hz := dep * 0.5
	var dx := minf(p.x + hx, hx - p.x)
	var dz := hz - p.z
	if absf(p.x) > gap * 0.5 + 0.3:
		dz = minf(dz, p.z + hz)
	# Открытый край не отбрасывает тень стены: не рисуем тёмную квадратную рамку.
	var a := 1.0
	if not opts.get("backdrop", true):
		a = lerpf(0.42, 1.0, smoothstep(0.0, 1.5, dx)) * lerpf(0.42, 1.0, smoothstep(0.0, 1.5, dz))
	for b in _blocks:
		var c: Vector3 = b[0]
		var s: Vector3 = b[1]
		if c.y - s.y * 0.5 > 0.2:
			continue
		var ox := maxf(absf(p.x - c.x) - s.x * 0.5, 0.0)
		var oz := maxf(absf(p.z - c.z) - s.z * 0.5, 0.0)
		var d := Vector2(ox, oz).length()
		a *= lerpf(0.5, 1.0, smoothstep(0.0, 1.1, d))
	for pl in _pillars:
		var c: Vector3 = pl[0]
		var d2 := Vector2(p.x - c.x, p.z - c.z).length() - float(pl[1])
		a *= lerpf(0.55, 1.0, smoothstep(0.0, 1.0, d2))
	return clampf(a, 0.3, 1.0)

# ---------------- Блоки ----------------

func _block(b: Array) -> void:
	var c: Vector3 = b[0]
	var s: Vector3 = b[1]
	var style: String = b[2]
	var node: Node3D = b[3]
	match style:
		"none":
			return
		"stone":
			_replace_mesh(node, _bevel_box(s, 0.12), _mat("surface_stone"))
			_kerb_top(c, s)
			if s.y >= 1.8:
				_corner_columns(c, s)
			_base_rubble(c, s, 1.0)
		"wood":
			_replace_mesh(node, _bevel_box(s, 0.05), _mat("surface_plank"))
			_timber_frame(c, s, true)
			_base_rubble(c, s, 0.4)
		"house":
			_replace_mesh(node, _bevel_box(s, 0.05), _mat("surface_plank"))
			_edge_beams(c + Vector3(0, s.y * 0.5 - 0.1, 0), s, 0.2, 0.26)
		"deck":
			# Мост/настил (Balcony): меш настила остаётся «Mesh» (из него — доски-обломки), новый материал;
			# балки по длинным краям — дети настила (падают вместе с ним)
			var dm := node.get_node_or_null("Mesh") as MeshInstance3D
			if dm:
				dm.material_override = _mat("surface_plank")
			_deck_beams(node, s)
		"balcony":
			for ch in node.get_children():
				if ch is MeshInstance3D:
					(ch as MeshInstance3D).material_override = _mat("surface_plank") if ch.name == "Mesh" else _mat("surface_wood")
			_deck_beams(node, s)
		"tower":
			_round_tower(node, c, s)

func _replace_mesh(node: Node3D, mesh: Mesh, mat: Material) -> void:
	var old := node.get_node_or_null("Mesh")
	if old:
		node.remove_child(old)
		old.free()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = mat
	node.add_child(mi)

## Коробка со скошенными вертикальными и верхними рёбрами (фаска b); низ без фаски. Цвет вершин —
## затемнение к основанию (на полосе 0–0.6 м) — стык с полом без SSAO.
func _bevel_box(size: Vector3, b: float) -> ArrayMesh:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	b = minf(b, minf(minf(hx, hz), hy) * 0.45)
	var y0 := -hy
	var yb := -hy + minf(0.6, size.y * 0.4)
	var y1 := hy - b
	var dark := Color(0.55, 0.55, 0.55)
	var mid := Color(0.86, 0.86, 0.86)
	var lite := Color.WHITE
	var st := _new_st()
	# Верх
	var t := [Vector3(-hx + b, hy, -hz + b), Vector3(hx - b, hy, -hz + b), Vector3(hx - b, hy, hz - b), Vector3(-hx + b, hy, hz - b)]
	_tri(st, t[0], t[1], t[2], Vector3.UP, lite, lite, lite)
	_tri(st, t[0], t[2], t[3], Vector3.UP, lite, lite, lite)
	# Стороны: [нормаль, ось вдоль, полудлина вдоль, расстояние до грани]
	var sides := [[Vector3.RIGHT, Vector3.BACK, hz, hx], [Vector3.LEFT, Vector3.FORWARD, hz, hx],
		[Vector3.BACK, Vector3.LEFT, hx, hz], [Vector3.FORWARD, Vector3.RIGHT, hx, hz]]
	for sd in sides:
		var n: Vector3 = sd[0]
		var u: Vector3 = sd[1]
		var hl: float = sd[2] - b
		var off: Vector3 = n * float(sd[3])
		for band in [[y0, yb, dark, mid], [yb, y1, mid, lite]]:
			var ya: float = band[0]
			var yc: float = band[1]
			var p0 := off - u * hl + Vector3(0, ya, 0)
			var p1 := off + u * hl + Vector3(0, ya, 0)
			var p2 := off + u * hl + Vector3(0, yc, 0)
			var p3 := off - u * hl + Vector3(0, yc, 0)
			_tri(st, p0, p1, p2, n, band[2], band[2], band[3])
			_tri(st, p0, p2, p3, n, band[2], band[3], band[3])
		# Верхняя фаска грани
		var q0 := off - u * hl + Vector3(0, y1, 0)
		var q1 := off + u * hl + Vector3(0, y1, 0)
		var q2 := off - n * b + u * hl + Vector3(0, hy, 0)
		var q3 := off - n * b - u * hl + Vector3(0, hy, 0)
		var bn := (n + Vector3.UP).normalized()
		_tri(st, q0, q1, q2, bn, lite, lite, lite)
		_tri(st, q0, q2, q3, bn, lite, lite, lite)
	# Вертикальные фаски на углах и треугольники-уголки сверху
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var a := Vector3(sx * hx, 0, sz * (hz - b))
			var c := Vector3(sx * (hx - b), 0, sz * hz)
			var n2 := Vector3(sx, 0, sz).normalized()
			for band in [[y0, yb, dark, mid], [yb, y1, mid, lite]]:
				var ya: float = band[0]
				var yc: float = band[1]
				_tri(st, a + Vector3(0, ya, 0), c + Vector3(0, ya, 0), c + Vector3(0, yc, 0), n2, band[2], band[2], band[3])
				_tri(st, a + Vector3(0, ya, 0), c + Vector3(0, yc, 0), a + Vector3(0, yc, 0), n2, band[2], band[3], band[3])
			var top := Vector3(sx * (hx - b), hy, sz * (hz - b))
			_tri(st, a + Vector3(0, y1, 0), c + Vector3(0, y1, 0), top, (n2 + Vector3.UP).normalized(), lite, lite, lite)
	# Низ (виден у настилов над полом)
	var bt := [Vector3(-hx, y0, -hz), Vector3(hx, y0, -hz), Vector3(hx, y0, hz), Vector3(-hx, y0, hz)]
	_tri(st, bt[0], bt[1], bt[2], Vector3.DOWN, dark, dark, dark)
	_tri(st, bt[0], bt[2], bt[3], Vector3.DOWN, dark, dark, dark)
	return st.commit()

## Каменный кант (бордюр MegaKit) по верхним рёбрам: лежит на крыше блока, чуть свисает наружу.
func _kerb_top(c: Vector3, s: Vector3) -> void:
	var top := c.y + s.y * 0.5
	if top < 0.7:
		return
	const DEPTH := 0.5
	const H := 0.12
	var y := top + H * 0.5 - 0.03
	# Вдоль X — во всю длину, вдоль Z — между ними
	for sz in [-1.0, 1.0]:
		_kerb_run(Vector3(c.x, y, c.z + sz * (s.z * 0.5 - DEPTH * 0.5 + 0.04)), s.x + 0.08, 0.0 if sz > 0 else 180.0, DEPTH, H)
	for sx in [-1.0, 1.0]:
		_kerb_run(Vector3(c.x + sx * (s.x * 0.5 - DEPTH * 0.5 + 0.04), y, c.z), s.z - DEPTH * 2.0 + 0.08, 90.0 if sx > 0 else -90.0, DEPTH, H)

## Ряд камней канта длиной length вдоль локальной X (после поворота yaw), с разбросом.
func _kerb_run(center: Vector3, length: float, yaw: float, depth: float, h: float) -> void:
	if length < 0.3:
		return
	var n := maxi(1, int(round(length / 1.6)))
	var seg := length / n
	var dir := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3.RIGHT
	for i in n:
		var p := center + dir * (seg * (i + 0.5) - length * 0.5)
		p.y += rng.randf_range(-0.012, 0.012)
		var j := Basis(Vector3.UP, deg_to_rad(rng.randf_range(-1.5, 1.5)))
		_add("kerb_%d" % (1 + rng.randi() % 2), _fit("kerb_1", p, Vector3(seg + 0.03, h, depth), yaw + (180.0 if rng.randf() < 0.5 else 0.0), j))

## Угловые колонны (Corner_ExteriorWide_Brick) на вертикальных рёбрах высоких каменных блоков.
func _corner_columns(c: Vector3, s: Vector3) -> void:
	var h := s.y - 0.05
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(c.x + sx * (s.x * 0.5 - 0.12), c.y - s.y * 0.5 + h * 0.5, c.z + sz * (s.z * 0.5 - 0.12))
			_add("pilaster", _fit("pilaster", p, Vector3(0.62, h, 0.62), rng.randf_range(0, 360)))

## Обломки и валуны у основания блока (density — доля мест, где кладём кучку).
func _base_rubble(c: Vector3, s: Vector3, density: float) -> void:
	if c.y - s.y * 0.5 > 0.2:
		return
	var per := 2.0 * (s.x + s.z)
	var n := int(per / 2.2)
	for i in n:
		if rng.randf() > density * 0.75:
			continue
		var t := rng.randf() * per
		var p: Vector3
		var outn: Vector3
		if t < s.x:
			p = Vector3(c.x - s.x * 0.5 + t, 0, c.z + s.z * 0.5)
			outn = Vector3.BACK
		elif t < s.x + s.z:
			p = Vector3(c.x + s.x * 0.5, 0, c.z + s.z * 0.5 - (t - s.x))
			outn = Vector3.RIGHT
		elif t < 2.0 * s.x + s.z:
			p = Vector3(c.x + s.x * 0.5 - (t - s.x - s.z), 0, c.z - s.z * 0.5)
			outn = Vector3.FORWARD
		else:
			p = Vector3(c.x - s.x * 0.5, 0, c.z - s.z * 0.5 + (t - 2.0 * s.x - s.z))
			outn = Vector3.LEFT
		_rubble_cluster(p, outn, 0.9)

## Кучка: 1–2 валуна (наполовину в земле) и 2–4 обломка кирпича рядом, отступ от грани — вдоль outn.
func _rubble_cluster(p: Vector3, outn: Vector3, scale: float) -> void:
	var side := outn.cross(Vector3.UP)
	var rocks := rng.randi_range(1, 2)
	for i in rocks:
		var q := p + outn * rng.randf_range(0.12, 0.45) + side * rng.randf_range(-0.6, 0.6)
		if _near_floor_opening(q, 1.2) or not _free_wall(q, 0.2):
			continue
		var sc := rng.randf_range(0.45, 1.0) * scale
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25)) * Basis.from_scale(Vector3(sc, sc * rng.randf_range(0.6, 1.0), sc))
		q.y = -0.08 * sc
		_add("rock_%d" % [1, 3, 4, 5][rng.randi() % 4], Transform3D(b, q))
	for i in rng.randi_range(2, 4):
		var q2 := p + outn * rng.randf_range(0.1, 0.9) + side * rng.randf_range(-0.9, 0.9)
		if _near_floor_opening(q2, 1.2) or not _free_wall(q2, 0.1):
			continue
		var sc2 := rng.randf_range(1.1, 1.9)
		var b2 := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.FORWARD, rng.randf_range(-0.3, 0.3)) * Basis.from_scale(Vector3.ONE * sc2)
		q2.y = 0.04 * sc2
		_add("brick_%d" % rng.randi_range(1, 4), Transform3D(b2, q2))

## Точка у стены/блока свободна от прыжковых рун, пропсов и проёма (блоки не мешают — кучка у их основания).
func _free_wall(p: Vector3, r: float) -> bool:
	if _near_floor_opening(p, r):
		return false
	for a in _avoid:
		if a.size() > 2:
			continue
		var c: Vector3 = a[0]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(a[1]) + r:
			return false
	return absf(p.x) < w * 0.5 and absf(p.z) < dep * 0.5

## Рама деревянного помоста: столбы по вертикальным рёбрам, балки по верхним (и нижним) рёбрам.
func _timber_frame(c: Vector3, s: Vector3, bottom: bool) -> void:
	var h := s.y
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(c.x + sx * (s.x * 0.5 - 0.1), c.y, c.z + sz * (s.z * 0.5 - 0.1))
			_add("post", _fit("post", p, Vector3(0.3, h + 0.04, 0.3), rng.randf_range(-4, 4)))
	_edge_beams(c + Vector3(0, s.y * 0.5 - 0.11, 0), s, 0.22, 0.24)
	if bottom and h > 0.9:
		_edge_beams(c + Vector3(0, -s.y * 0.5 + 0.12, 0), s, 0.24, 0.24)
	if h >= 2.2:
		_edge_beams(c, s, 0.2, 0.2)

## Балки по четырём рёбрам прямоугольника s на высоте center.y (снаружи на 3 см).
func _edge_beams(center: Vector3, s: Vector3, bh: float, bd: float) -> void:
	for sz in [-1.0, 1.0]:
		_beam_run(Vector3(center.x, center.y, center.z + sz * (s.z * 0.5 - bd * 0.5 + 0.04)), s.x + 0.06, 0.0, bh, bd)
	for sx in [-1.0, 1.0]:
		_beam_run(Vector3(center.x + sx * (s.x * 0.5 - bd * 0.5 + 0.04), center.y, center.z), s.z - bd * 1.2, 90.0, bh, bd)

## Балка из кусков ≤ 2.6 м с лёгким разбросом (ручная работа, не «одна линейка»).
func _beam_run(center: Vector3, length: float, yaw: float, bh: float, bd: float) -> void:
	if length < 0.3:
		return
	var n := maxi(1, int(ceil(length / 2.6)))
	var seg := length / n
	var dir := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3.RIGHT
	for i in n:
		var p := center + dir * (seg * (i + 0.5) - length * 0.5)
		p.y += rng.randf_range(-0.015, 0.015)
		var j := Basis(Vector3.FORWARD, deg_to_rad(rng.randf_range(-0.8, 0.8)))
		_add("beam", _fit("beam", p, Vector3(seg + 0.02, bh, bd), yaw + (180.0 if rng.randf() < 0.5 else 0.0), j))

## Настил/мост: балки по длинным краям — дочерние узлы настила (MultiMesh в его системе координат).
func _deck_beams(node: Node3D, s: Vector3) -> void:
	var saved := _mm
	_mm = {}
	var long_x := s.x >= s.z
	var length := maxf(s.x, s.z)
	for sg in [-1.0, 1.0]:
		var off := Vector3(0, -0.04, sg * (s.z * 0.5 + 0.06)) if long_x else Vector3(sg * (s.x * 0.5 + 0.06), -0.04, 0)
		_beam_run(off, length + 0.1, 0.0 if long_x else 90.0, minf(s.y + 0.1, 0.42), 0.2)
	var keep := dress
	dress = node
	_flush()
	dress = keep
	_mm = saved

## Квадратная башня (зал 3) — круглая: каменный барабан, вписанный в коробку коллизии, и деревянная
## площадка сверху по размеру коллизии (на ней стоят метатели), с подкосами под свесом.
func _round_tower(node: Node3D, c: Vector3, s: Vector3) -> void:
	var old := node.get_node_or_null("Mesh")
	if old:
		node.remove_child(old)
		old.free()
	const CAP := 0.4
	var r := minf(s.x, s.z) * 0.5 * 1.18
	var body := CylinderMesh.new()
	body.top_radius = r * 0.94
	body.bottom_radius = r * 1.04
	body.height = s.y - CAP
	body.radial_segments = 28
	body.rings = 2
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = body
	mi.material_override = _mat("surface_stone")
	mi.position = Vector3(0, -CAP * 0.5, 0)
	node.add_child(mi)
	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	cap.mesh = _bevel_box(Vector3(s.x + 0.1, CAP, s.z + 0.1), 0.04)
	cap.material_override = _mat("surface_plank")
	cap.position = Vector3(0, s.y * 0.5 - CAP * 0.5, 0)
	node.add_child(cap)
	_edge_beams(c + Vector3(0, s.y * 0.5 - CAP * 0.5, 0), s + Vector3(0.1, 0, 0.1), CAP + 0.04, 0.24)
	# Подкосы под углами площадки (Prop_Support смотрит вдоль Z)
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		var dirv := Vector3(cos(a), 0, sin(a))
		var p := c + dirv * (r * 0.98 + 0.35) + Vector3(0, s.y * 0.5 - CAP - 0.75, 0)
		_add("support", _fit("support", p, Vector3(0.22, 1.5, 0.95), rad_to_deg(atan2(dirv.x, dirv.z))))
	# Кольцо валунов у основания
	for k in 10:
		var a2 := TAU * k / 10.0 + rng.randf_range(-0.2, 0.2)
		var outn := Vector3(cos(a2), 0, sin(a2))
		_rubble_cluster(Vector3(c.x, 0, c.z) + outn * r, outn, 1.0)

# ---------------- Колонны ----------------

func _pillar_dress(geo: Node) -> void:
	for c in geo.get_children():
		var nm := String(c.name)
		if c is StaticBody3D and nm.begins_with("Pillar"):
			var mi := c.get_node_or_null("Mesh") as MeshInstance3D
			if mi:
				mi.material_override = _mat("surface_pillar")
	for p in _pillars:
		var c2: Vector3 = p[0]
		for k in 3:
			var a := rng.randf() * TAU
			var outn := Vector3(cos(a), 0, sin(a))
			_rubble_cluster(c2 + outn * 1.05, outn, 0.7)

# ---------------- Стены ----------------

func _walls(geo: Node) -> void:
	# Закрытый длинный дом остаётся зданием. В остальных залах внешняя граница — только
	# коллизия, а даль, скалы и деревья видны прямо с пола арены.
	if opts.get("backdrop", true):
		_open_edges(geo)
		return
	var models := geo.get_node_or_null("WallModels")
	if models:
		# Верхний ряд модулей — разной высоты, с лёгким наклоном: верх стены перестаёт быть линейкой
		for m in models.get_children():
			if m is Node3D and String(m.name).contains("_1_"):
				# Абсолютные значения (повторный запуск по ручной арене не копит разброс)
				var n3 := m as Node3D
				n3.scale.y = rng.randf_range(0.97, 1.07)
				n3.rotation.y = snappedf(n3.rotation.y, PI * 0.5) + deg_to_rad(rng.randf_range(-0.5, 0.5))
	# Внутренние грани стен: [начало, конец, нормаль внутрь зала]
	var hx := w * 0.5
	var hz := dep * 0.5
	var faces := [
		[Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3.FORWARD],
		[Vector3(-hx, 0, -hz), Vector3(-gap * 0.5, 0, -hz), Vector3.BACK],
		[Vector3(gap * 0.5, 0, -hz), Vector3(hx, 0, -hz), Vector3.BACK],
		[Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz), Vector3.RIGHT],
		[Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3.LEFT],
	]
	for f in faces:
		_wall_face(f[0], f[1], f[2])
	# Колонны в углах и у ворот
	if opts.get("pilasters", true):
		var corners := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz),
			Vector3(-gap * 0.5 - 0.22, 0, -hz), Vector3(gap * 0.5 + 0.22, 0, -hz)]
		for p in corners:
			_add("pilaster", _fit("pilaster", p + Vector3(0, WALL_TOP * 0.5 + 0.05, 0), Vector3(0.9, WALL_TOP + 0.1, 0.9), rng.randf_range(0, 360)))
	# Частокол по верху стен (и коридора) и бревно-перемычка над воротами
	if opts.get("palisade", true):
		for nm in ["WallN_L", "WallN_R", "WallS", "WallW", "WallE", "CorridorL", "CorridorR", "CorridorEnd"]:
			var wall := geo.get_node_or_null(nm) as Node3D
			if wall:
				# Колья — по осевой модулей стены: они на 0.3 м ближе к залу (коридору), чем коробка коллизии
				var sz := _box_size(wall)
				var to := Vector3(0, 0, -hz - 3.0) if nm.begins_with("Corridor") else Vector3.ZERO
				var c := wall.position
				if sz.x >= sz.z:
					c.z += signf(to.z - c.z) * 0.29
				else:
					c.x += signf(to.x - c.x) * 0.29
				_palisade(c, sz)
		_add("log", Transform3D(Basis.from_scale(Vector3(gap + 1.4, 0.22, 0.22)), Vector3(0, 6.05, -hz - 0.25)))
	if opts.get("vines", true):
		_vines()

## Периметр открытой арены: коллизии Wall* остаются, видимые модули периметра и частокол
## убираются. Коридор выхода остаётся оформленным как отдельные ворота.
func _open_edges(geo: Node) -> void:
	# Нижние 6 м коллизии прежние; над ними невидимая граница продолжается, чтобы
	# прыжковая руна или рывок с площадки не выносили игрока за пределы уровня.
	var exit_y := float(root.get_meta("exit_y", 0.0))
	var boundary_height := maxf(24.0, exit_y + 12.0)
	for wall_name in ["WallN_L", "WallN_R", "WallS", "WallW", "WallE"]:
		var wall := geo.get_node_or_null(wall_name) as StaticBody3D
		var shape := wall.get_node_or_null("Shape") as CollisionShape3D if wall else null
		if shape and shape.shape is BoxShape3D:
			var box := shape.shape.duplicate() as BoxShape3D
			var bottom := wall.position.y + shape.position.y - box.size.y * 0.5
			box.size.y = boundary_height
			shape.shape = box
			wall.position.y = bottom - shape.position.y + boundary_height * 0.5
	var models := geo.get_node_or_null("WallModels")
	if models:
		for model in models.get_children():
			var nm := String(model.name)
			if nm.begins_with("N_L_") or nm.begins_with("N_R_") or nm.begins_with("S_") or nm.begins_with("W_") or nm.begins_with("E_"):
				models.remove_child(model)
				model.free()
	# Рунные ворота оформлены как отдельно стоящая арка.
	for sign_x in [-1.0, 1.0]:
		var c := Vector3(sign_x * (gap * 0.5 + 0.38), exit_y + WALL_TOP * 0.5, -dep * 0.5 - 0.1)
		_add("pilaster", _fit("pilaster", c, Vector3(0.8, WALL_TOP, 0.8)))
	_add("log", Transform3D(Basis.from_scale(Vector3(gap + 1.7, 0.18, 0.18)), Vector3(0, exit_y + WALL_TOP, -dep * 0.5)))
	# Факелы и знамёна больше не висят в воздухе: у каждого есть отдельная стойка.
	var torches := root.get_node_or_null("Torches")
	if torches:
		for t in torches.get_children():
			if not t is Node3D:
				continue
			var pos := (t as Node3D).position
			var h := maxf(pos.y + 0.15, 0.5)
			_add("pilaster", _fit("pilaster", Vector3(pos.x, h * 0.5, pos.z), Vector3(0.46, h, 0.46)))
	var banners := root.get_node_or_null("Banners")
	if banners:
		for banner in banners.get_children():
			if not banner is Node3D:
				continue
			var b := banner as Node3D
			# Плакаты на домах по-прежнему крепятся к домам, не к отдельным шестам.
			if absf(b.position.x) < w * 0.5 - 0.5 and absf(b.position.z) < dep * 0.5 - 0.5:
				continue
			var bh := maxf(b.position.y + 0.4, 1.0)
			_add("post", _fit("post", Vector3(b.position.x, bh * 0.5, b.position.z), Vector3(0.22, bh, 0.22), b.rotation_degrees.y))
	# Неровные редкие скальные группы за границей не образуют сплошную квадратную стену.
	var faces := [
		[Vector3(-w * 0.5, 0, dep * 0.5), Vector3(w * 0.5, 0, dep * 0.5), Vector3.BACK],
		[Vector3(-w * 0.5, 0, -dep * 0.5), Vector3(w * 0.5, 0, -dep * 0.5), Vector3.FORWARD],
		[Vector3(-w * 0.5, 0, -dep * 0.5), Vector3(-w * 0.5, 0, dep * 0.5), Vector3.LEFT],
		[Vector3(w * 0.5, 0, -dep * 0.5), Vector3(w * 0.5, 0, dep * 0.5), Vector3.RIGHT],
	]
	for f in faces:
		var a: Vector3 = f[0]
		var end: Vector3 = f[1]
		var outward: Vector3 = f[2]
		var length := a.distance_to(end)
		var dir := (end - a) / length
		var offset := rng.randf_range(1.0, 4.0)
		while offset < length - 0.5:
			var point := a + dir * offset + outward * rng.randf_range(0.7, 2.6)
			# Не загораживать коридор ворот на северной стороне.
			if outward != Vector3.FORWARD or absf(point.x) > gap * 0.5 + 2.0:
				var key := "rock_%d" % rng.randi_range(1, 5)
				var r := rng.randf_range(0.7, 1.7)
				_add(key, _fit(key, point + Vector3(0, r * 0.28 - 0.1, 0), Vector3(r * 1.6, r * 0.65, r * 1.15), rng.randf_range(0, 360)))
			offset += rng.randf_range(2.8, 5.8)

## Обломки, валуны и тёмная полоса вдоль внутренней грани стены a→b.
func _wall_face(a: Vector3, b: Vector3, inward: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.5:
		return
	var dir := (b - a) / length
	# Полоса затемнения у пола (квад на 2 см от грани, лицом в зал)
	var yaw := rad_to_deg(atan2(inward.x, inward.z))
	var mid := (a + b) * 0.5 + inward * 0.03
	_add("grime", Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)) * Basis.from_scale(Vector3(length, 1.5, 1.0)), mid))
	if not opts.get("rubble", true):
		return
	var t := rng.randf_range(0.3, 1.5)
	while t < length - 0.3:
		var p := a + dir * t
		if rng.randf() < 0.7 and _free_wall(p + inward * 0.5, 0.3) and _not_in_block(p + inward * 0.4):
			_rubble_cluster(p, inward, 1.0)
		t += rng.randf_range(1.4, 3.4)

func _not_in_block(p: Vector3) -> bool:
	for a in _avoid:
		if a.size() > 2:
			var c: Vector3 = a[0]
			var s: Vector3 = a[2]
			if absf(p.x - c.x) < s.x * 0.5 + 0.3 and absf(p.z - c.z) < s.z * 0.5 + 0.3:
				return false
	return true

## Опоры из уже общего меша post, без коллизии: [основание Vector3, высота, ширина].
func _timber_posts() -> void:
	for spec in opts.get("timber_posts", []):
		if not (spec is Array) or spec.size() != 3 or not (spec[0] is Vector3):
			push_error("timber_posts: нужны основание, высота и ширина")
			continue
		var base: Vector3 = spec[0]
		var h := float(spec[1])
		var width := float(spec[2])
		if not is_finite(h) or not is_finite(width) or h <= 0.0 or width <= 0.0:
			push_error("timber_posts: высота и ширина должны быть положительными")
			continue
		_add("post", _fit("post", base + Vector3(0, h * 0.5, 0), Vector3(width, h, width)))

## Короткие декоративные ряды частокола: пары конечных точек [Vector3, Vector3].
## Точки одной высоты, вдоль X или Z; y — основание кола. Коллизии нет.
func _palisade_rows() -> void:
	for row in opts.get("palisade_rows", []):
		if not (row is Array) or row.size() != 2 or not (row[0] is Vector3) or not (row[1] is Vector3):
			push_error("palisade_rows: нужна пара конечных точек Vector3")
			continue
		var a: Vector3 = row[0]
		var b: Vector3 = row[1]
		var delta := b - a
		if not is_finite(a.x) or not is_finite(a.y) or not is_finite(a.z) or not is_finite(b.x) or not is_finite(b.y) or not is_finite(b.z) or absf(delta.y) > 0.001 or (absf(delta.x) > 0.001 and absf(delta.z) > 0.001) or Vector2(delta.x, delta.z).length() < 0.34:
			push_error("palisade_rows: ряд должен быть горизонтальным, вдоль X или Z и длиной не меньше 0.34 м")
			continue
		_palisade((a + b) * 0.5, Vector3(absf(delta.x), 0, absf(delta.z)), a.y)

## Частокол на верху стены-коробки (центр, размер): колья разной высоты и наклона по осевой линии.
func _palisade(center: Vector3, size: Vector3, base_y: float = WALL_TOP - 0.3) -> void:
	var along_x := size.x >= size.z
	var length := maxf(size.x, size.z)
	var step := 0.34
	var n := int(length / step)
	for i in n:
		var t := (i + 0.5) * length / n - length * 0.5
		var p := center + (Vector3(t, 0, 0) if along_x else Vector3(0, 0, t))
		p.y = base_y
		var r := rng.randf_range(0.13, 0.17)
		var h := rng.randf_range(1.0, 1.6)
		var lean := Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(-4, 4))) * Basis(Vector3.FORWARD, deg_to_rad(rng.randf_range(-4, 4)))
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		_add("stake", Transform3D(lean * b * Basis.from_scale(Vector3(r, h, r)), p))
	# Связка: бревно вдоль частокола
	var lp := center
	lp.y = base_y + 0.65
	var lb := Basis.from_scale(Vector3(length, 0.1, 0.1))
	if not along_x:
		lb = Basis(Vector3.UP, PI * 0.5) * lb
	_add("log", Transform3D(lb, lp))

## Плющ со стен (Prop_Vine MegaKit): несколько свисающих плетей сверху, вдали от факелов и знамён.
func _vines() -> void:
	var busy: Array[Vector3] = []
	for grp in ["Torches", "Banners"]:
		var g := root.get_node_or_null(grp)
		if g:
			for c in g.get_children():
				if c is Node3D:
					busy.append((c as Node3D).position)
	var hx := w * 0.5
	var hz := dep * 0.5
	var count := int(opts.get("vine_count", 4))
	var placed := 0
	var tries := 0
	var node := Node3D.new()
	node.name = "Vines"
	dress.add_child(node)
	while placed < count and tries < 40:
		tries += 1
		var side := rng.randi() % 3
		var p: Vector3
		var yaw: float
		match side:
			0:
				p = Vector3(-hx + 0.05, 0, rng.randf_range(-hz + 2.0, hz - 2.0))
				yaw = 90.0
			1:
				p = Vector3(hx - 0.05, 0, rng.randf_range(-hz + 2.0, hz - 2.0))
				yaw = -90.0
			_:
				p = Vector3(rng.randf_range(-hx + 2.0, hx - 2.0), 0, hz - 0.05)
				yaw = 180.0
		var ok := true
		for q in busy:
			if Vector2(p.x - q.x, p.z - q.z).length() < 1.8:
				ok = false
				break
		if not ok:
			continue
		busy.append(p)
		var vine := ["Prop_Vine1", "Prop_Vine2", "Prop_Vine4"][rng.randi() % 3] as String
		var sc := rng.randf_range(1.0, 1.35)
		var inst := (load(QV + vine + ".gltf") as PackedScene).instantiate() as Node3D
		inst.name = "Vine%d" % placed
		inst.position = p + Vector3(0, WALL_TOP - 0.5 * sc, 0)
		inst.rotation_degrees.y = yaw
		inst.scale = Vector3.ONE * sc
		node.add_child(inst)
		placed += 1

# ---------------- Декали и кости ----------------

## 10–20 декалей владельца на пол (FloorDecal, общий материал): трещины, подпалины, ихор, следы великана.
func _decals() -> void:
	var count := int(opts.get("decals", 14))
	if count <= 0:
		return
	var node := Node3D.new()
	node.name = "Decals"
	dress.add_child(node)
	var keys: Array = FLOOR_DECALS.keys()
	var total := 0.0
	for k in keys:
		total += float(FLOOR_DECALS[k][0])
	var placed: Array[Vector3] = []
	var foot := 0
	var tries := 0
	while placed.size() < count and tries < count * 20:
		tries += 1
		var r := rng.randf() * total
		var key: String = keys[0]
		for k in keys:
			r -= float(FLOOR_DECALS[k][0])
			if r <= 0.0:
				key = k
				break
		if key == "footprints_giant":
			if foot > 0:
				continue
		var spec: Array = FLOOR_DECALS[key]
		var size := rng.randf_range(spec[1], spec[2])
		var p := Vector3(rng.randf_range(-w * 0.5 + 1.2, w * 0.5 - 1.2), 0, rng.randf_range(-dep * 0.5 + 1.2, dep * 0.5 - 1.2))
		if _near_floor_opening(p, size * 0.708) or not _free(p, size * 0.4):
			continue
		var near := false
		for q in placed:
			if q.distance_to(p) < 2.2:
				near = true
				break
		if near:
			continue
		if key == "footprints_giant":
			foot += 1
		placed.append(p)
		var fd := Node3D.new()
		fd.name = "%s_%d" % [key.to_pascal_case(), placed.size()]
		fd.set_script(load("res://rooms/floor_decal.gd"))
		fd.set("art", key)
		fd.set("size", size)
		fd.position = p + Vector3(0, 0.004 * (placed.size() % 4), 0)
		fd.rotation_degrees.y = rng.randf_range(0, 360)
		node.add_child(fd)

## Кости и черепа (Pirate Kit) в одном-двух углах зала — без коллизии, у самой стены.
func _bones() -> void:
	var hx := w * 0.5
	var hz := dep * 0.5
	var corners := [Vector3(-hx + 1.0, 0, hz - 1.0), Vector3(hx - 1.0, 0, hz - 1.0), Vector3(-hx + 1.0, 0, -hz + 1.0), Vector3(hx - 1.0, 0, -hz + 1.0)]
	var node := Node3D.new()
	node.name = "Bones"
	dress.add_child(node)
	var k := 0
	var start := rng.randi() % 4
	for i in 4:
		if k >= 2:
			break
		var p: Vector3 = corners[(start + i) % 4]
		if _near_floor_opening(p, 2.0) or not _free(p, 0.6):
			continue
		var skulls := k == 0
		var inst := (load(QS + ("Environment_Skulls.gltf" if skulls else "Environment_LargeBones.gltf")) as PackedScene).instantiate() as Node3D
		inst.name = "Skulls" if skulls else "Ribs"
		var sc := 0.2 if skulls else 0.24
		inst.scale = Vector3.ONE * sc
		inst.position = p + Vector3(0, (0.3 if skulls else 0.12) * sc, 0)
		inst.rotation_degrees.y = rng.randf_range(0, 360)
		node.add_child(inst)
		k += 1

# ---------------- Даль за стенами ----------------

## Земля дали — кольцо от этого радиуса (м); ближе — рамка зала _ground_skirt (до SKIRT_HALF)
const GROUND_INNER := 29.5
const SKIRT_HALF := 30.0

## Плоское кольцо (лицом вверх): внутренний край на высоте y0, внешний — y1 (берег уходит под воду).
static func _ring_mesh(r0: float, r1: float, seg: int, y0: float, y1: float) -> ArrayMesh:
	var st := _new_st()
	var c := Color.WHITE
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var p1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var q0 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var q1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		_tri(st, p0, q0, q1, Vector3.UP, c, c, c)
		_tri(st, p0, q1, p1, Vector3.UP, c, c, c)
	return st.commit()

## Земля вокруг зала до кольца дали: квадратная рамка от внешних стен (с коридором) до ±SKIRT_HALF, на 5 см
## ниже пола — стены не «висят», под самим залом ничего лишнего не рисуется.
func _ground_skirt() -> void:
	# Открытый пол больше не закрывает стена: земля должна слегка заходить под его кромку,
	# иначе в просвете видна полоска неба (земля на 5 см ниже, наложение без z-fighting).
	var x0 := w * 0.5 - 0.08
	var zs := dep * 0.5 - 0.08
	var zw := -dep * 0.5 + 0.08
	var zn := -dep * 0.5 - 5.8
	var cx := gap * 0.5 + 0.3
	var o := SKIRT_HALF
	var y := -0.05
	var st := _new_st()
	var c := Color.WHITE
	# Полосы: юг, север (за коридором), запад, восток и по бокам коридора
	var quads := [[Vector3(-o, y, zs), Vector3(o, y, zs), Vector3(o, y, o), Vector3(-o, y, o)],
		[Vector3(-o, y, -o), Vector3(o, y, -o), Vector3(o, y, zn), Vector3(-o, y, zn)],
		[Vector3(-o, y, zn), Vector3(-x0, y, zn), Vector3(-x0, y, zs), Vector3(-o, y, zs)],
		[Vector3(x0, y, zn), Vector3(o, y, zn), Vector3(o, y, zs), Vector3(x0, y, zs)],
		[Vector3(-x0, y, zn), Vector3(-cx, y, zn), Vector3(-cx, y, zw), Vector3(-x0, y, zw)],
		[Vector3(cx, y, zn), Vector3(x0, y, zn), Vector3(x0, y, zw), Vector3(cx, y, zw)]]
	for q in quads:
		_tri(st, q[0], q[1], q[2], Vector3.UP, c, c, c)
		_tri(st, q[0], q[2], q[3], Vector3.UP, c, c, c)
	var mi := MeshInstance3D.new()
	mi.name = "GroundSkirt"
	mi.mesh = st.commit()
	mi.material_override = _mat("surface_ground")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dress.add_child(mi)

## Сцена дали (rooms/backdrop_midgard.tscn): земля, вода фьорда, кольцо скал, сосны, драккары. Без коллизии,
## вне игровой зоны (от 30 м), тени не бросает. Одна на все залы мира — экземпляр в каждом открытом зале.
static func build_backdrop() -> Node3D:
	var d := RoomDresser.new(hash("backdrop_midgard"))
	d.chunk_size = 40.0
	var root_ := Node3D.new()
	root_.name = "Backdrop"
	d.dress = root_
	# Земля и вода — кольца, не диски: под залом ничего не рисуется (иначе большой меш с центром в зале
	# сортируется первым и закрашивает весь экран под полом — лишний проход на программном рендере).
	# Землю у самых стен даёт рамка зала (RoomDresser._ground_skirt), кольцо — от GROUND_INNER.
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = _ring_mesh(GROUND_INNER, 78.0, 40, -0.07, -1.5)
	ground.material_override = load(MAT_DIR + "surface_ground.tres")
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root_.add_child(ground)
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = _ring_mesh(70.0, 450.0, 40, -1.1, -1.1)
	water.material_override = load(MAT_DIR + "water.tres")
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root_.add_child(water)
	# Сосны: кольцо 32–70 м, гуще вблизи, разная высота
	for i in 120:
		var a := d.rng.randf() * TAU
		var r := lerpf(38.0, 72.0, pow(d.rng.randf(), 0.8))
		var sc := d.rng.randf_range(0.55, 1.15)
		var b := Basis(Vector3.UP, d.rng.randf() * TAU) * Basis.from_scale(Vector3(sc * d.rng.randf_range(0.85, 1.15), sc, sc))
		d._add("pine", Transform3D(b, Vector3(cos(a) * r, -0.4, sin(a) * r)))
	# Берег (край земли) — валуны-глыбы (лёгкие меши ~750 треугольников), острова в воде — скала Cliff1.
	# Тяжёлые Cliff2–4 (19–24 тыс. треугольников) не берём: 38 скал давали 600 тыс. треугольников на кадр
	for i in 28:
		var a2 := TAU * i / 28.0 + d.rng.randf_range(-0.08, 0.08)
		var r2 := d.rng.randf_range(73.0, 79.0)
		var sc2 := d.rng.randf_range(9.0, 16.0)
		var b2 := Basis(Vector3.UP, d.rng.randf() * TAU) * Basis.from_scale(Vector3(sc2 * 1.3, sc2 * d.rng.randf_range(0.6, 1.0), sc2))
		d._add("rock_%d" % [1, 3, 4, 5][d.rng.randi() % 4], Transform3D(b2, Vector3(cos(a2) * r2, -1.2, sin(a2) * r2)))
	for i in 6:
		var a3 := TAU * i / 6.0 + d.rng.randf_range(-0.4, 0.4)
		var r3 := d.rng.randf_range(120.0, 200.0)
		var sc3 := d.rng.randf_range(2.5, 4.0)
		var b3 := Basis(Vector3.UP, d.rng.randf() * TAU) * Basis.from_scale(Vector3(sc3 * 1.4, sc3 * d.rng.randf_range(0.6, 1.0), sc3 * 1.4))
		d._add("cliff_1", Transform3D(b3, Vector3(cos(a3) * r3, -2.0, sin(a3) * r3)))
	d._flush()
	for mmi in root_.get_node("Scatter").get_children():
		(mmi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Драккары в воде фьорда (Pirate Kit), один у берега
	var ships := [["Ship_Large", Vector3(-30, -1.6, 98), 20.0, 1.4], ["Ship_Small", Vector3(64, -1.2, 92), -60.0, 2.2],
		["Ship_Small", Vector3(-104, -1.2, -40), 110.0, 2.0], ["Ship_Large", Vector3(120, -1.6, -70), 200.0, 1.2]]
	for s in ships:
		var inst := (load(QS + s[0] + ".gltf") as PackedScene).instantiate() as Node3D
		inst.name = "%s_%d" % [s[0], ships.find(s)]
		inst.position = s[1]
		inst.rotation_degrees.y = s[2]
		inst.scale = Vector3.ONE * float(s[3])
		root_.add_child(inst)
	return root_
