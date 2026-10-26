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
			# Тёмное кованое железо: чистый цвет без текстур
			m.uv1_triplanar = false
			m.albedo_color = Color(0.42, 0.43, 0.46)
			m.metallic = 0.6
			m.roughness = 0.55
			m.uv1_scale = Vector3(2.0, 2.0, 2.0)
		"steel":
			m.uv1_triplanar = false
			m.albedo_color = Color(0.78, 0.8, 0.84)
			m.metallic = 0.7
			m.roughness = 0.35
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
		"gold":
			m.albedo_color = Color(0.85, 0.65, 0.25)
			m.metallic = 0.9
			m.roughness = 0.35
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

## Мьёльнир: короткая рукоять в обмотке, восьмигранный боёк с бандажами и рунной полосой.
static func hammer(layer: int = 1) -> Node3D:
	var r := Node3D.new()
	r.name = "Mjolnir"
	# Рукоять: обмотка кожей с кольцами
	_add(r, _cyl(0.032, 0.036, 0.46), Vector3(0, 0.19, 0), mat("leather"), Vector3.ZERO, layer)
	for y in [0.02, 0.12, 0.22, 0.32]:
		_add(r, _cyl(0.04, 0.04, 0.018), Vector3(0, y, 0), mat("iron"), Vector3.ZERO, layer)
	# Навершие и петля-ремешок
	_add(r, _cyl(0.05, 0.035, 0.06), Vector3(0, -0.07, 0), mat("iron"), Vector3.ZERO, layer)
	var loop := TorusMesh.new()
	loop.inner_radius = 0.025
	loop.outer_radius = 0.045
	_add(r, loop, Vector3(0, -0.13, 0), mat("leather"), Vector3(90, 0, 0), layer)
	# Шейка
	_add(r, _cyl(0.05, 0.04, 0.08), Vector3(0, 0.44, 0), mat("iron"), Vector3.ZERO, layer)
	# Боёк: восьмигранник вдоль X
	_add(r, _cyl(0.14, 0.14, 0.42, 8), Vector3(0, 0.56, 0), mat("iron"), Vector3(0, 0, 90), layer)
	# Ударные грани чуть шире, со скосом
	for x in [-0.22, 0.22]:
		_add(r, _cyl(0.155, 0.155, 0.05, 8), Vector3(x, 0.56, 0), mat("steel"), Vector3(0, 0, 90), layer)
		_add(r, _cyl(0.12, 0.155, 0.03, 8), Vector3(x + signf(x) * 0.035, 0.56, 0), mat("steel"), Vector3(0, 0, -90.0 * signf(x)), layer)
	# Рунная полоса посередине
	_add(r, _cyl(0.147, 0.147, 0.06, 8), Vector3(0, 0.56, 0), mat("rune"), Vector3(0, 0, 90), layer)
	_add(r, _cyl(0.15, 0.15, 0.015, 8), Vector3(-0.05, 0.56, 0), mat("gold"), Vector3(0, 0, 90), layer)
	_add(r, _cyl(0.15, 0.15, 0.015, 8), Vector3(0.05, 0.56, 0), mat("gold"), Vector3(0, 0, 90), layer)
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

## Меч: прямой клинок викинга.
static func sword(layer: int = 1) -> Node3D:
	var r := Node3D.new()
	r.name = "Sword"
	_add(r, _cyl(0.025, 0.028, 0.16), Vector3(0, 0.02, 0), mat("leather"), Vector3.ZERO, layer)
	_add(r, _box(Vector3(0.05, 0.05, 0.05)), Vector3(0, -0.08, 0), mat("iron"), Vector3.ZERO, layer)
	_add(r, _box(Vector3(0.22, 0.04, 0.05)), Vector3(0, 0.12, 0), mat("iron"), Vector3.ZERO, layer)
	_add(r, _box(Vector3(0.06, 0.78, 0.015)), Vector3(0, 0.53, 0), mat("steel"), Vector3.ZERO, layer)
	return r

## Копьё.
static func spear(layer: int = 1) -> Node3D:
	var r := Node3D.new()
	r.name = "Spear"
	_add(r, _cyl(0.022, 0.026, 1.9), Vector3(0, 0.35, 0), mat("wood"), Vector3.ZERO, layer)
	_add(r, _cyl(0.0, 0.05, 0.28), Vector3(0, 1.42, 0), mat("steel"), Vector3.ZERO, layer)
	return r

## Вилы.
static func pitchfork(layer: int = 1) -> Node3D:
	var r := Node3D.new()
	r.name = "Pitchfork"
	_add(r, _cyl(0.022, 0.026, 1.6), Vector3(0, 0.3, 0), mat("wood"), Vector3.ZERO, layer)
	_add(r, _box(Vector3(0.3, 0.035, 0.035)), Vector3(0, 1.1, 0), mat("iron"), Vector3.ZERO, layer)
	for x in [-0.13, 0.0, 0.13]:
		_add(r, _cyl(0.0, 0.014, 0.3), Vector3(x, 1.26, 0), mat("iron"), Vector3.ZERO, layer)
	return r

## Факел (с огоньком и светом).
static func torch(layer: int = 1) -> Node3D:
	var r := Node3D.new()
	r.name = "Torch"
	_add(r, _cyl(0.03, 0.022, 0.6), Vector3(0, 0.15, 0), mat("wood"), Vector3.ZERO, layer)
	_add(r, _cyl(0.045, 0.04, 0.1), Vector3(0, 0.47, 0), mat("leather"), Vector3.ZERO, layer)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.6, 0.2)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.55, 0.15)
	fm.emission_energy_multiplier = 4.0
	_add(r, _cyl(0.0, 0.07, 0.2), Vector3(0, 0.62, 0), fm, Vector3.ZERO, layer)
	if layer == 1:
		var l := OmniLight3D.new()
		l.light_color = Color(1, 0.6, 0.3)
		l.light_energy = 1.2
		l.omni_range = 4.0
		l.position = Vector3(0, 0.7, 0)
		r.add_child(l)
	return r

## Круглый щит (для левой руки).
static func shield(layer: int = 1) -> Node3D:
	var r := Node3D.new()
	r.name = "Shield"
	_add(r, _cyl(0.32, 0.32, 0.04, 16), Vector3(0, 0, 0.06), mat("wood"), Vector3(90, 0, 0), layer)
	_add(r, _cyl(0.33, 0.33, 0.025, 16), Vector3(0, 0, 0.055), mat("iron"), Vector3(90, 0, 0), layer)
	var boss := SphereMesh.new()
	boss.radius = 0.07
	boss.height = 0.08
	_add(r, boss, Vector3(0, 0, 0.1), mat("steel"), Vector3(90, 0, 0), layer)
	return r

const QW := "res://assets/quaternius/weapons/"
## Модели Quaternius Medieval Weapons (CC0). Рукоять вдоль +Y от нижнего конца; лезвие в плоскости X.
const MODEL_WEAPONS := {
	"q_axe": "axe.glb", "q_sword": "sword.glb", "q_spear": "spear.glb", "q_scythe": "scythe.glb",
	"q_dagger": "dagger.glb", "q_shield": "shield-round.glb", "q_staff": "staff.glb", "q_pickaxe": "pickaxe.glb", "q_bow": "bow.glb",
}

## Загружает модель оружия и подменяет её материалы на наши (дерево/сталь в общем стиле).
static func model(kind: String, layer: int = 1) -> Node3D:
	var r := Node3D.new()
	r.name = kind
	var path: String = QW + MODEL_WEAPONS[kind]
	if not ResourceLoader.exists(path):
		return r
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	r.add_child(inst)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.layers = layer
		if layer == 2:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for sidx in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(sidx)
			var n := src.resource_name.to_lower() if src else ""
			var mm: Material = null
			if n.contains("lightsteel"):
				mm = mat("steel")
			elif n.contains("steel") or n.contains("7d82") or n.contains("91") or n.contains("a9b1") or n.contains("bfc8"):
				mm = mat("iron")
			elif n.contains("darkwood"):
				mm = mat("leather")
			elif n.contains("wood") or n.contains("c673") or n.contains("db84"):
				mm = mat("wood")
			elif n.contains("gold"):
				mm = mat("gold")
			if mm:
				m.set_surface_override_material(sidx, mm)
	return r

const CROWD_WEAPONS := ["q_axe", "club", "q_sword", "q_spear", "pitchfork", "torch", "q_scythe", "q_pickaxe", "hammer", "q_dagger"]

static func build(kind: String, layer: int = 1) -> Node3D:
	var n: Node3D
	match kind:
		"axe": n = axe(layer)
		"hammer": n = hammer(layer)
		"club": n = club(layer)
		"staff": n = staff(layer)
		"sword": n = sword(layer)
		"spear": n = spear(layer)
		"pitchfork": n = pitchfork(layer)
		"torch": n = torch(layer)
		"shield": n = shield(layer)
		_:
			n = model(kind, layer) if MODEL_WEAPONS.has(kind) else Node3D.new()
	# Хват в кисти Quaternius: рукоять вдоль пальцев
	return n
