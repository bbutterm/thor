extends RefCounted
class_name WeaponMeshes
## Процедурное оружие в текстурах Quaternius (дерево, камень, металл) — чтобы стиль совпадал с моделями.
## Когда появятся настоящие модели (Synty, Quaternius Medieval Weapons), замени build() на загрузку .glb.
## Ось оружия: рукоять вдоль +Y от точки хвата (0,0,0), лезвие/боёк смотрит в -Z.

const TEX := "res://assets/quaternius/village/"
static var _mats: Dictionary = {}

static func mat(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	match kind:
		"wood":
			m.albedo_texture = load(TEX + "T_WoodTrim_BaseColor.png")
			m.normal_enabled = true
			m.normal_texture = load(TEX + "T_WoodTrim_Normal.png")
			m.albedo_color = Color(0.75, 0.6, 0.5)
			m.roughness = 0.85
			m.uv1_scale = Vector3(1.5, 1.5, 1.5)
		"iron":
			# Тёмное кованое железо: цвет + лёгкий шум шероховатости (без узорной текстуры)
			m.roughness_texture = load(TEX + "T_BrushedNoise.png")
			m.albedo_color = Color(0.34, 0.35, 0.38)
			m.metallic = 0.9
			m.roughness = 0.5
			m.uv1_scale = Vector3(2.0, 2.0, 2.0)
		"steel":
			m.roughness_texture = load(TEX + "T_BrushedNoise.png")
			m.albedo_color = Color(0.8, 0.82, 0.86)
			m.metallic = 1.0
			m.roughness = 0.3
			m.uv1_scale = Vector3(3.0, 3.0, 3.0)
		"stone":
			m.albedo_texture = load(TEX + "T_RockTrim_BaseColor.png")
			m.normal_enabled = true
			m.normal_texture = load(TEX + "T_RockTrim_Normal.png")
			m.albedo_color = Color(0.7, 0.72, 0.78)
			m.roughness = 0.9
			m.uv1_scale = Vector3(1.2, 1.2, 1.2)
		"leather":
			m.albedo_texture = load(TEX + "T_WoodTrim_BaseColor.png")
			m.albedo_color = Color(0.35, 0.22, 0.15)
			m.roughness = 0.9
			m.uv1_scale = Vector3(4, 4, 4)
		"rune":
			m.albedo_color = Color(0.3, 0.65, 0.95)
			m.emission_enabled = true
			m.emission = Color(0.3, 0.7, 1.0)
			m.emission_energy_multiplier = 1.6
		"curse":
			m.albedo_color = Color(0.7, 0.25, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.7, 0.25, 1.0)
			m.emission_energy_multiplier = 3.0
	_mats[kind] = m
	return m

static func _add(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material, rot_deg: Vector3 = Vector3.ZERO, layer: int = 1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.layers = layer
	if layer == 2:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b

static func _cyl(r_top: float, r_bot: float, h: float, seg: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	return c

## Бородатый топор викинга. Масштаб: длина ~0.95 м.
static func axe(layer: int = 1) -> Node3D:
	var r := Node3D.new()
	r.name = "Axe"
	_add(r, _cyl(0.028, 0.034, 0.95), Vector3(0, 0.38, 0), mat("wood"), Vector3.ZERO, layer)
	_add(r, _cyl(0.04, 0.04, 0.16), Vector3(0, -0.02, 0), mat("leather"), Vector3.ZERO, layer)
	# «Борода» лезвия: широкая нижняя часть + узкая шейка
	_add(r, _box(Vector3(0.035, 0.16, 0.12)), Vector3(0, 0.75, -0.08), mat("iron"), Vector3.ZERO, layer)
	_add(r, _box(Vector3(0.03, 0.34, 0.2)), Vector3(0, 0.7, -0.23), mat("iron"), Vector3(-12, 0, 0), layer)
	_add(r, _box(Vector3(0.034, 0.4, 0.05)), Vector3(0, 0.68, -0.34), mat("steel"), Vector3(-12, 0, 0), layer)
	_add(r, _box(Vector3(0.06, 0.08, 0.08)), Vector3(0, 0.78, 0.05), mat("iron"), Vector3.ZERO, layer)
	return r

## Мьёльнир: короткая рукоять, массивный боёк с рунами.
static func hammer(layer: int = 1) -> Node3D:
	var r := Node3D.new()
	r.name = "Mjolnir"
	_add(r, _cyl(0.034, 0.04, 0.5), Vector3(0, 0.18, 0), mat("leather"), Vector3.ZERO, layer)
	_add(r, _cyl(0.05, 0.05, 0.05), Vector3(0, -0.08, 0), mat("iron"), Vector3.ZERO, layer)
	_add(r, _box(Vector3(0.5, 0.27, 0.27)), Vector3(0, 0.55, 0), mat("iron"), Vector3.ZERO, layer)
	_add(r, _box(Vector3(0.06, 0.31, 0.31)), Vector3(-0.24, 0.55, 0), mat("steel"), Vector3.ZERO, layer)
	_add(r, _box(Vector3(0.06, 0.31, 0.31)), Vector3(0.24, 0.55, 0), mat("steel"), Vector3.ZERO, layer)
	_add(r, _box(Vector3(0.16, 0.12, 0.285)), Vector3(0, 0.55, 0), mat("rune"), Vector3.ZERO, layer)
	return r

## Дубина великана: бревно с каменным навершием.
static func club(layer: int = 1) -> Node3D:
	var r := Node3D.new()
	r.name = "Club"
	_add(r, _cyl(0.07, 0.045, 1.1), Vector3(0, 0.45, 0), mat("wood"), Vector3.ZERO, layer)
	_add(r, _box(Vector3(0.26, 0.32, 0.26)), Vector3(0, 1.0, 0), mat("stone"), Vector3(10, 25, 5), layer)
	_add(r, _box(Vector3(0.2, 0.06, 0.2)), Vector3(0, 0.82, 0), mat("iron"), Vector3(0, 25, 0), layer)
	return r

## Посох шамана со светящимся навершием.
static func staff(layer: int = 1) -> Node3D:
	var r := Node3D.new()
	r.name = "Staff"
	_add(r, _cyl(0.025, 0.03, 1.6), Vector3(0, 0.3, 0), mat("wood"), Vector3.ZERO, layer)
	var orb := SphereMesh.new()
	orb.radius = 0.08
	orb.height = 0.16
	_add(r, orb, Vector3(0, 1.17, 0), mat("curse"), Vector3.ZERO, layer)
	_add(r, _cyl(0.0, 0.05, 0.12), Vector3(0, 1.05, 0), mat("iron"), Vector3(180, 0, 0), layer)
	return r

static func build(kind: String, layer: int = 1) -> Node3D:
	var n: Node3D
	match kind:
		"axe": n = axe(layer)
		"hammer": n = hammer(layer)
		"club": n = club(layer)
		"staff": n = staff(layer)
		_: n = Node3D.new()
	# Хват в кисти Quaternius: рукоять вдоль пальцев
	return n
