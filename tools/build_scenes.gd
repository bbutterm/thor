extends Node
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
## Высота опоры корабля в «Причале с драккаром»: палуба модели на уровне палубы-коллизии (2.2 м)
const SHIP_Y := 1.0

func _ready() -> void:
	build_resources()
	build_props()
	build_enemies()
	build_player()
	build_dress()
	build_rooms()
	build_ui_scenes()
	build_game()
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

# ---------------- Ресурсы: тела и руны ----------------

func build_resources() -> void:
	print("Ресурсы…")
	var bodies := [
		{"id": "berserker", "name": "Берсерк", "desc": "Много здоровья, бьёт тяжело, бегает медленно. Орёт.", "hp": 150.0, "speed": 7.5, "dash": 2, "axe": 1.3, "hammer": 1.0, "glory": 1.0, "hand": Color(1.0, 0.86, 0.78), "sleeve": Color(0.55, 0.22, 0.18), "melee": "axe", "ranged": ""},
		{"id": "hunter", "name": "Охотник", "desc": "Быстрый и хрупкий. Три руны Мьёльнира.", "hp": 80.0, "speed": 10.0, "dash": 3, "axe": 0.9, "hammer": 1.2, "glory": 1.0, "hand": Color(0.9, 0.76, 0.64), "sleeve": Color(0.32, 0.42, 0.28), "melee": "knife", "ranged": "crossbow"},
		{"id": "thrall", "name": "Батрак", "desc": "Всё слабое, но Слава ×2. Социальный лифт.", "hp": 60.0, "speed": 8.5, "dash": 2, "axe": 0.7, "hammer": 0.8, "glory": 2.0, "hand": Color(0.95, 0.82, 0.72), "sleeve": Color(0.55, 0.5, 0.42), "melee": "club", "ranged": ""},
	]
	# Тела и руны теперь данные по GDD (блок Г): существующие файлы не перезаписываем — правятся руками
	for b in bodies:
		if ResourceLoader.exists("res://run/bodies/%s.tres" % b.id):
			continue
		var r := BodyDef.new()
		r.id = b.id
		r.display_name = b.name
		r.description = b.desc
		r.max_health = b.hp
		r.move_speed = b.speed
		r.dash_charges = b.dash
		r.axe_damage_mult = b.axe
		r.hammer_damage_mult = b.hammer
		r.glory_mult = b.glory
		r.hand_color = b.hand
		r.sleeve_color = b.sleeve
		# Стартовое оружие — описания из weapons/defs/
		r.start_melee = load("res://weapons/defs/%s.tres" % b.melee) as WeaponDef
		r.start_ranged = load("res://weapons/defs/%s.tres" % b.ranged) as WeaponDef if b.ranged != "" else null
		ResourceSaver.save(r, "res://run/bodies/%s.tres" % b.id)
	var runes := [
		{"id": "axe_damage", "title": "Руна Тюра", "desc": "Урон оружия ближнего боя +25%", "glyph": "ᛏ", "color": Color(1.0, 0.55, 0.35)},
		{"id": "dash_charge", "title": "Копыта Слейпнира", "desc": "+1 руна Мьёльнира", "glyph": "ᛖ", "color": Color(0.5, 0.85, 1.0)},
		{"id": "hammer_power", "title": "Гнев Мьёльнира", "desc": "Молот бьёт на 40% сильнее и возвращается на 30% быстрее", "glyph": "ᛗ", "color": Color(0.55, 0.75, 1.0)},
		{"id": "slam_fire", "title": "Огонь Муспельхейма", "desc": "Удар-приземление поджигает землю на 2 секунды", "glyph": "ᚲ", "color": Color(1.0, 0.5, 0.15)},
		{"id": "max_health", "title": "Яблоко Идунн", "desc": "+30 к максимуму здоровья", "glyph": "ᛁ", "color": Color(0.5, 1.0, 0.5)},
		{"id": "dash_damage", "title": "Таран Хеймдалля", "desc": "Рывок сквозь врагов наносит 15 урона и отбрасывает", "glyph": "ᚱ", "color": Color(1.0, 0.85, 0.35)},
		{"id": "heal", "title": "Мёд поэзии", "desc": "Сразу лечит 50 здоровья. Вкусно.", "glyph": "ᚨ", "color": Color(1.0, 0.75, 0.3)},
	]
	for d in runes:
		if ResourceLoader.exists("res://run/runes/%s.tres" % d.id):
			continue
		var r := RuneDef.new()
		r.id = d.id
		r.title = d.title
		r.description = d.desc
		r.glyph = d.glyph
		r.color = d.color
		ResourceSaver.save(r, "res://run/runes/%s.tres" % d.id)

# ---------------- Бочки и ящики ----------------

func build_props() -> void:
	print("Бочки и ящики…")
	# Разрушаемые (props/destructible.gd): прочность и содержимое — поля Destructible на сцене
	var destructible := load("res://props/destructible.gd")
	for kind in ["barrel", "crate", "barrel_explosive"]:
		var rb := RigidBody3D.new()
		rb.name = kind.capitalize().replace(" ", "")
		rb.collision_layer = PROPS_L
		rb.collision_mask = WORLD | PLAYER_L | ENEMY_L | PROPS_L | DEBRIS_L
		rb.add_to_group("props", true)
		rb.set_script(destructible)
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		rb.add_child(shape)
		if kind != "crate":
			# Quaternius Fantasy Props: Barrel (0.7 × 0.9 м), чуть увеличен
			rb.mass = 1.2
			var cs := CylinderShape3D.new()
			cs.radius = 0.4
			cs.height = 1.0
			shape.shape = cs
			shape.position.y = 0.5
			_model(rb, "Model", QP + "Barrel.gltf", Vector3.ZERO, Vector3.ZERO, Vector3(1.15, 1.12, 1.15))
			# Бочка — 1 удар топором (22), клёпки по 6 секторам + крышка и дно, серебро
			rb.set("max_health", 15.0)
			rb.set("debris_mode", "radial")
			rb.set("debris_sectors", 6)
			rb.set("loot", "barrel")
		else:
			# Quaternius Medieval Village: Prop_Crate (1.08 м) → 0.9 м
			rb.mass = 1.6
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.9, 0.88, 0.9)
			shape.shape = bs
			shape.position.y = 0.44
			_model(rb, "Model", QV + "Prop_Crate.gltf", Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 0.83)
			# Ящик — 2 обычных удара (финишер, сильный, молот, рывок — один), шесть стенок, серебро/патроны/лечение
			rb.set("max_health", 30.0)
			rb.set("debris_mode", "box")
			rb.set("wood_color", Color(0.62, 0.45, 0.28))
			rb.set("break_sound", "sounds/sfx/crate_break.wav")
			rb.set("loot", "crate")
		if kind == "barrel_explosive":
			# Взрывная бочка: красный пояс и крышка (светятся — читается издалека), взрыв Blast, цепная реакция
			rb.set("max_health", 10.0)
			rb.set("loot", "none")
			rb.set("explosive", true)
			rb.set("burn_time", 1.2)
			rb.set("comic_event", "")
			var mark := StandardMaterial3D.new()
			mark.resource_name = "ExplosiveMark"
			mark.albedo_color = Color(0.78, 0.08, 0.05)
			mark.roughness = 0.7
			mark.emission_enabled = true
			mark.emission = Color(1.0, 0.18, 0.06)
			mark.emission_energy_multiplier = 1.3
			var band := MeshInstance3D.new()
			band.name = "Mark"
			var bm := CylinderMesh.new()
			bm.top_radius = 0.412
			bm.bottom_radius = 0.412
			bm.height = 0.17
			bm.radial_segments = 20
			bm.rings = 1
			bm.cap_top = false
			bm.cap_bottom = false
			band.mesh = bm
			band.material_override = mark
			band.position.y = 0.52
			rb.add_child(band)
			var cap := MeshInstance3D.new()
			cap.name = "MarkTop"
			var cm := CylinderMesh.new()
			cm.top_radius = 0.24
			cm.bottom_radius = 0.24
			cm.height = 0.02
			cm.radial_segments = 16
			cm.rings = 1
			cap.mesh = cm
			cap.material_override = mark
			cap.position.y = 1.01
			rb.add_child(cap)
		_save(rb, "res://props/%s.tscn" % kind)

# ---------------- Враги ----------------

func build_enemies() -> void:
	print("Враги…")
	var defs := {
		"grunt": {"kind": Enemy.Kind.GRUNT, "hp": 60.0, "speed": 4.4, "range": 2.0, "dmg": 12.0, "windup": 0.6, "recover": 0.7, "cd": 0.9, "color": Color(0.36, 0.48, 0.38), "scale": 1.0, "resist": 0.0},
		"thrower": {"kind": Enemy.Kind.THROWER, "hp": 40.0, "speed": 3.8, "range": 12.0, "dmg": 10.0, "windup": 0.55, "recover": 0.4, "cd": 2.2, "color": Color(0.42, 0.33, 0.55), "scale": 1.0, "resist": 0.0},
		"boss": {"kind": Enemy.Kind.BOSS, "hp": 480.0, "speed": 3.6, "range": 3.6, "dmg": 20.0, "windup": 0.8, "recover": 0.9, "cd": 1.1, "color": Color(0.5, 0.26, 0.2), "scale": 2.1, "resist": 0.75},
		# Мидгард (GDD 12.1). HP/скорость/урон перекрывает EnemyDef (enemies/defs) при спавне в зале.
		"fodder": {"kind": Enemy.Kind.FODDER, "hp": 7.7, "speed": 3.5, "range": 1.8, "dmg": 5.0, "windup": 0.55, "recover": 0.6, "cd": 1.1, "color": Color(0.4, 0.5, 0.45), "scale": 0.95, "resist": 0.0,
			"extra": {"max_debris": 10}},
		"bloated": {"kind": Enemy.Kind.BLOATED, "hp": 22.0, "speed": 5.0, "range": 2.4, "dmg": 44.0, "windup": 0.7, "recover": 0.5, "cd": 0.5, "color": Color(0.6, 0.65, 0.35), "scale": 1.05, "resist": 0.2,
			"extra": {"boss_slam_radius": 3.0, "boss_slam_windup": 0.7, "bloat_trigger_range": 2.4}},
		"shieldbearer": {"kind": Enemy.Kind.SHIELD, "hp": 88.0, "speed": 3.0, "range": 2.0, "dmg": 15.0, "windup": 0.75, "recover": 0.8, "cd": 1.4, "color": Color(0.4, 0.45, 0.55), "scale": 1.08, "resist": 0.6,
			"extra": {"turn_speed": 2.6, "lunge_speed": 9.0}},
		"shaman": {"kind": Enemy.Kind.SHAMAN, "hp": 44.0, "speed": 3.0, "range": 0.0, "dmg": 15.0, "windup": 1.0, "recover": 0.6, "cd": 1.0, "color": Color(0.3, 0.5, 0.35), "scale": 1.0, "resist": 0.1,
			"extra": {}},
		"merc": {"kind": Enemy.Kind.MERC, "hp": 44.0, "speed": 4.0, "range": 14.0, "dmg": 15.0, "windup": 0.8, "recover": 0.9, "cd": 2.4, "color": Color(0.35, 0.3, 0.3), "scale": 1.0, "resist": 0.0,
			"extra": {"keep_min_dist": 7.0, "keep_max_dist": 13.0}},
		# Ярл Бьорн Мёртвый — босс Мидгарда (GDD 14.2): 60 У, три фазы (enemies/bosses/jarl.gd); HP/урон — enemies/defs/jarl.tres
		"jarl": {"kind": Enemy.Kind.BOSS, "hp": 1320.0, "speed": 3.6, "range": 3.6, "dmg": 25.0, "windup": 0.8, "recover": 0.9, "cd": 1.1, "color": Color(0.5, 0.26, 0.2), "scale": 2.1, "resist": 0.85,
			"script": "res://enemies/bosses/jarl.gd", "extra": {"lunge_speed": 5.0, "wall_splat_speed": 99.0, "boss_slam_radius": 6.0, "boss_slam_damage": 30.0, "boss_slam_windup": 1.0, "boss_far_slam_chance": 0.0}},
		# Толстый Свен — мини-босс (GDD 14.1): свой скрипт поверх enemy.gd; числа и вид перекрывает MinibossDef
		"sven": {"kind": Enemy.Kind.BOSS, "hp": 550.0, "speed": 4.2, "range": 2.6, "dmg": 18.0, "windup": 0.75, "recover": 0.9, "cd": 1.0, "color": Color(0.55, 0.62, 0.4), "scale": 1.5, "resist": 0.6,
			"script": "res://enemies/bosses/sven.gd", "extra": {"lunge_speed": 5.0, "wall_splat_speed": 99.0, "boss_slam_radius": 4.5, "boss_slam_damage": 20.0, "boss_slam_windup": 0.9, "boss_far_slam_chance": 0.004}},
	}
	var script := load("res://enemies/enemy.gd")
	for key in defs:
		var d: Dictionary = defs[key]
		var e := CharacterBody3D.new()
		e.name = key.capitalize()
		e.set_script(load(d.script) if d.has("script") else script)
		e.set("kind", d.kind)
		e.set("max_health", d.hp)
		e.set("move_speed", d.speed)
		e.set("attack_range", d.range)
		e.set("attack_damage", d.dmg)
		e.set("windup_time", d.windup)
		e.set("recover_time", d.recover)
		e.set("attack_cooldown", d.cd)
		e.set("body_color", d.color)
		e.set("model_scale", d.scale)
		e.set("knock_resist", d.resist)
		if key == "boss":
			e.set("lunge_speed", 5.0)
			e.set("wall_splat_speed", 99.0)
		var extra: Dictionary = d.get("extra", {})
		for prop in extra:
			e.set(prop, extra[prop])
		var look: Dictionary = MODEL_LOOKS[key]
		for prop in look:
			e.set(prop, look[prop])
		e.collision_layer = ENEMY_L
		e.collision_mask = WORLD | PLAYER_L | ENEMY_L | PROPS_L
		e.floor_snap_length = 0.3
		var shape := CollisionShape3D.new()
		shape.name = "Collider"
		var cap := CapsuleShape3D.new()
		cap.radius = 0.45 * d.scale
		cap.height = 1.8 * d.scale
		shape.shape = cap
		shape.position = Vector3(0, 0.9 * d.scale, 0)
		e.add_child(shape)
		_save(e, "res://enemies/%s.tscn" % key)

## Вид врагов: персонажи Quaternius (Universal Base Characters + одежда) и анимации UAL.
## Чтобы поменять модели — меняй здесь или прямо в сценах enemies/*.tscn (группы «Модель» и «Анимации»).
const MODEL_LOOKS := {
	"grunt": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Peasant.gltf", "model_hair": "",
		"skin_tint": Color(0.45, 0.58, 0.66), "cloth_tint": Color(0.55, 0.55, 0.52), "eye_glow": Color(0.4, 0.85, 1.0, 1.0),
		"hand_weapon": "q_axe", "randomize_look": true, "shield_chance": 0.3,
		"weapon_pool": ["q_axe", "q_sword"],
		"anim_spawn": "LayToIdle", "anim_idle": "Zombie_Idle_Loop", "anim_move": "Zombie_Walk_Fwd_Loop", "anim_move_ref_speed": 1.6,
		"anim_attack": "Zombie_Scratch", "anim_attack_hit_at": 0.45, "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	"thrower": {
		"model_body": "base/Superhero_Female_FullBody.gltf", "model_outfit": "outfits/Female_Ranger.gltf", "model_hair": "",
		"skin_tint": Color(0.5, 0.58, 0.66), "cloth_tint": Color(0.5, 0.42, 0.68), "eye_glow": Color(0.75, 0.4, 1.0, 1.0),
		"hand_weapon": "staff",
		"anim_spawn": "LayToIdle", "anim_idle": "Spell_Simple_Idle_Loop", "anim_move": "Walk_Loop", "anim_move_ref_speed": 1.5,
		"anim_attack": "Spell_Simple_Shoot", "anim_attack_hit_at": 0.6, "anim_hit": "Hit_Head", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	"boss": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Peasant.gltf", "model_hair": "hair/Hair_Beard.gltf",
		"skin_tint": Color(0.5, 0.72, 1.0), "cloth_tint": Color(0.55, 0.7, 1.0), "eye_glow": Color(0.5, 0.95, 1.0, 1.0),
		"hand_weapon": "club",
		"anim_spawn": "LayToIdle", "anim_idle": "Sword_Idle", "anim_move": "Walk_Loop", "anim_move_ref_speed": 1.6,
		"anim_attack": "Sword_Regular_C", "anim_attack_hit_at": 0.35, "anim_slam": "Sword_Regular_C", "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	# Ярл: огромный синеватый драугр с бородой, рука-дубина в правой руке (бросает её бумерангом)
	"jarl": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Peasant.gltf", "model_hair": "hair/Hair_Beard.gltf",
		"skin_tint": Color(0.5, 0.72, 1.0), "cloth_tint": Color(0.55, 0.7, 1.0), "eye_glow": Color(0.5, 0.95, 1.0, 1.0),
		"hand_weapon": "club",
		"anim_spawn": "LayToIdle", "anim_idle": "Sword_Idle", "anim_move": "Walk_Loop", "anim_move_ref_speed": 1.6,
		"anim_attack": "Sword_Regular_C", "anim_attack_hit_at": 0.35, "anim_slam": "Sword_Regular_C", "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	# Толстый Свен: раздутый драугр с бородой, без оружия (бочка — своя, enemies/bosses/sven.gd)
	"sven": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Peasant.gltf", "model_hair": "hair/Hair_Beard.gltf",
		"skin_tint": Color(0.55, 0.7, 0.6), "cloth_tint": Color(0.7, 0.5, 0.32), "eye_glow": Color(1.0, 0.7, 0.2, 1.0),
		"hand_weapon": "", "randomize_look": false, "shield_chance": 0.0,
		"anim_spawn": "LayToIdle", "anim_idle": "Zombie_Idle_Loop", "anim_move": "Zombie_Walk_Fwd_Loop", "anim_move_ref_speed": 1.6,
		"anim_attack": "Punch_Cross", "anim_attack_hit_at": 0.45, "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	# Корм — облегчённый: одно тело + один комплект одежды, без оружия, волос и случайной сборки
	"fodder": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Peasant.gltf", "model_hair": "",
		"skin_tint": Color(0.5, 0.6, 0.62), "cloth_tint": Color(0.42, 0.4, 0.36), "eye_glow": Color(0.35, 0.75, 1.0, 1.0),
		"hand_weapon": "", "randomize_look": false, "shield_chance": 0.0,
		"anim_spawn": "LayToIdle", "anim_idle": "Zombie_Idle_Loop", "anim_move": "Zombie_Walk_Fwd_Loop", "anim_move_ref_speed": 1.6,
		"anim_attack": "Zombie_Scratch", "anim_attack_hit_at": 0.45, "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	# Раздутый: толстый (bloat_fatness), желчно-зелёный, раздувается к взрыву
	"bloated": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Peasant.gltf", "model_hair": "",
		"skin_tint": Color(0.78, 0.9, 0.5), "cloth_tint": Color(0.5, 0.42, 0.3), "eye_glow": Color(1.0, 0.55, 0.1, 1.0),
		"hand_weapon": "", "randomize_look": false, "shield_chance": 0.0,
		"anim_spawn": "LayToIdle", "anim_idle": "Zombie_Idle_Loop", "anim_move": "Jog_Fwd_Loop", "anim_move_ref_speed": 3.2,
		"anim_attack": "Zombie_Scratch", "anim_attack_hit_at": 0.9, "anim_slam": "Zombie_Scratch", "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	# Щитоносец: круглый щит в левой руке всегда, меч в правой
	"shieldbearer": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Ranger.gltf", "model_hair": "",
		"skin_tint": Color(0.45, 0.55, 0.66), "cloth_tint": Color(0.5, 0.52, 0.58), "eye_glow": Color(0.4, 0.85, 1.0, 1.0),
		"hand_weapon": "q_sword", "randomize_look": false, "shield_chance": 0.0,
		"anim_spawn": "LayToIdle", "anim_idle": "Idle_Shield_Loop", "anim_move": "Walk_Loop", "anim_move_ref_speed": 1.5,
		"anim_attack": "Shield_OneShot", "anim_attack_hit_at": 0.4, "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	# Шаман: зелёное свечение, посох
	"shaman": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Ranger.gltf", "model_hair": "hair/Hair_Long.gltf",
		"skin_tint": Color(0.55, 0.68, 0.58), "cloth_tint": Color(0.32, 0.5, 0.36), "eye_glow": Color(0.4, 1.0, 0.5, 1.0),
		"hand_weapon": "q_staff", "randomize_look": false, "shield_chance": 0.0,
		"anim_spawn": "LayToIdle", "anim_idle": "Spell_Simple_Idle_Loop", "anim_move": "Walk_Loop", "anim_move_ref_speed": 1.5,
		"anim_attack": "Spell_Simple_Shoot", "anim_attack_hit_at": 0.6, "anim_hit": "Hit_Head", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
	# Наёмник Локи — смертный (обычная кожа, без свечения глаз), с автоматом
	"merc": {
		"model_body": "base/Superhero_Male_FullBody.gltf", "model_outfit": "outfits/Male_Ranger.gltf", "model_hair": "hair/Hair_Buzzed.gltf",
		"skin_tint": Color(1.0, 0.9, 0.82), "cloth_tint": Color(0.3, 0.3, 0.32), "eye_glow": Color(0, 0, 0, 0),
		"hand_weapon": "gun_smg", "randomize_look": false, "shield_chance": 0.0,
		"anim_spawn": "LayToIdle", "anim_idle": "Pistol_Idle_Loop", "anim_move": "Walk_Loop", "anim_move_ref_speed": 1.5,
		"anim_attack": "Pistol_Aim_Neutral", "anim_attack_hit_at": 0.95, "anim_hit": "Hit_Chest", "anim_stun": "Hit_Knockback", "anim_death": "Death01",
	},
}

# ---------------- Игрок ----------------

func build_player() -> void:
	print("Игрок…")
	var p := CharacterBody3D.new()
	p.name = "Player"
	p.set_script(load("res://player/player.gd"))
	p.collision_layer = PLAYER_L
	p.collision_mask = WORLD | ENEMY_L | PROPS_L
	p.floor_snap_length = 0.35
	p.floor_max_angle = deg_to_rad(50)

	var col := CollisionShape3D.new()
	col.name = "Collider"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	p.add_child(col)

	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.6, 0)
	p.add_child(head)

	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.set_script(load("res://player/camera_fx.gd"))
	cam.cull_mask = 0xFFFFF & ~2
	cam.fov = 85
	cam.near = 0.05
	cam.current = true
	head.add_child(cam)

	var hitbox := ShapeCast3D.new()
	hitbox.name = "AxeHitbox"
	var hb := BoxShape3D.new()
	hb.size = Vector3(2.6, 2.0, 1.6)
	hitbox.shape = hb
	hitbox.position = Vector3(0, -0.15, -0.9)
	hitbox.target_position = Vector3(0, 0, -1.0)
	hitbox.collision_mask = ENEMY_L | PROPS_L | PROJ_L | DEBRIS_L
	hitbox.collide_with_areas = true
	hitbox.collide_with_bodies = true
	hitbox.enabled = false
	hitbox.max_results = 128
	cam.add_child(hitbox)

	var svc := SubViewportContainer.new()
	svc.name = "ViewmodelContainer"
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cam.add_child(svc)
	var sv := SubViewport.new()
	sv.name = "SubViewport"
	sv.transparent_bg = true
	sv.handle_input_locally = false
	sv.msaa_3d = Viewport.MSAA_2X
	sv.size = Vector2i(1280, 720)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Свой «мир» для рук: независимое освещение, руки не темнеют в тёмных залах
	sv.own_world_3d = true
	svc.add_child(sv)
	var vm_env := WorldEnvironment.new()
	vm_env.name = "ViewmodelEnvironment"
	var ve := Environment.new()
	ve.background_mode = Environment.BG_CLEAR_COLOR
	ve.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ve.ambient_light_color = Color(0.85, 0.78, 0.7)
	ve.ambient_light_energy = 0.9
	ve.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Небо только для отражений (фон прозрачный): металлу Мьёльнира и топора есть что отражать — блики вместо серой матовости
	var vsky := Sky.new()
	var vsm := ProceduralSkyMaterial.new()
	vsm.sky_top_color = Color(0.16, 0.18, 0.3)
	vsm.sky_horizon_color = Color(1.0, 0.62, 0.38)
	vsm.ground_horizon_color = Color(0.42, 0.3, 0.24)
	vsm.ground_bottom_color = Color(0.06, 0.05, 0.06)
	vsky.sky_material = vsm
	vsky.radiance_size = Sky.RADIANCE_SIZE_64
	ve.sky = vsky
	ve.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	vm_env.environment = ve
	sv.add_child(vm_env)
	var vm_sun := DirectionalLight3D.new()
	vm_sun.name = "ViewmodelKeyLight"
	vm_sun.rotation_degrees = Vector3(-35, 30, 0)
	vm_sun.light_color = Color(1.0, 0.9, 0.8)
	vm_sun.light_energy = 1.1
	sv.add_child(vm_sun)
	var vcam := Camera3D.new()
	vcam.name = "ViewCam"
	vcam.cull_mask = 2
	vcam.fov = 60
	vcam.near = 0.05
	# Далеко от мира, чтобы геометрия залов не отбрасывала тень на руки
	vcam.position = Vector3(0, -500, 0)
	sv.add_child(vcam)
	var vlight := OmniLight3D.new()
	vlight.name = "HandLight"
	vlight.light_cull_mask = 2
	vlight.position = Vector3(0.3, 0.6, 0.6)
	vlight.light_energy = 1.6
	vlight.omni_range = 5.0
	vcam.add_child(vlight)

	var skin := _mat("skin_default", Color(0.85, 0.65, 0.5), 0.9, false)
	var wood := _mat("handle_wood", Color(0.36, 0.22, 0.12), 0.9, false)
	var steel := _mat("steel", Color(0.7, 0.72, 0.76), 0.3, false)
	steel.metallic = 0.85
	var edge := _mat("edge", Color(0.92, 0.93, 0.95), 0.15, false)
	edge.metallic = 1.0
	var rune_glow := _mat("rune_glow", Color(0.45, 0.8, 1.0), 0.4, false, 3.0)

	var axe_pivot := Node3D.new()
	axe_pivot.name = "AxePivot"
	axe_pivot.scale = Vector3.ONE * 0.68
	vcam.add_child(axe_pivot)
	var arm_r := ViewmodelArm.new()
	arm_r.name = "Hand"
	arm_r.side = "right"
	# Топор Quaternius: лезвие разворачиваем вперёд (-Z), держим за нижнюю треть
	arm_r.weapon_kind = "q_axe"
	arm_r.weapon_rotation = Vector3(0, 90, 0)
	arm_r.weapon_scale = 1.25
	arm_r.weapon_offset = Vector3(0, -0.22, 0)
	axe_pivot.add_child(arm_r)

	var ham_pivot := Node3D.new()
	ham_pivot.name = "HammerPivot"
	ham_pivot.scale = Vector3.ONE * 0.68
	vcam.add_child(ham_pivot)
	var arm_l := ViewmodelArm.new()
	arm_l.name = "Hand"
	arm_l.side = "left"
	arm_l.weapon_kind = "hammer"
	arm_l.weapon_offset = Vector3(0, -0.06, 0)
	# Боёк поперёк кадра (в модели он вдоль Z — к камере торцом)
	arm_l.weapon_rotation = Vector3(0, 90, 0)
	arm_l.weapon_scale = 1.2
	ham_pivot.add_child(arm_l)

	var axe := Node.new()
	axe.name = "Axe"
	axe.set_script(load("res://weapons/axe.gd"))
	p.add_child(axe)
	var mj := Node.new()
	mj.name = "Mjolnir"
	mj.set_script(load("res://weapons/mjolnir_hand.gd"))
	p.add_child(mj)
	# Слоты оружия (мили + ренж): свитч, подбор, патроны — weapons/weapon_holder.gd
	var wh := Node.new()
	wh.name = "Weapons"
	wh.set_script(load("res://weapons/weapon_holder.gd"))
	p.add_child(wh)

	var steps := AudioStreamPlayer.new()
	steps.name = "Footsteps"
	steps.stream = load("res://sounds/walking.ogg")
	steps.volume_db = -8.0
	steps.autoplay = true
	steps.stream_paused = true
	p.add_child(steps)

	# Пути для оружия (относительно узла оружия)
	axe.set("pivot_path", NodePath("../Head/Camera/ViewmodelContainer/SubViewport/ViewCam/AxePivot"))
	axe.set("hitbox_path", NodePath("../Head/Camera/AxeHitbox"))
	axe.set("hand_mesh_path", NodePath("../Head/Camera/ViewmodelContainer/SubViewport/ViewCam/AxePivot/Hand"))
	mj.set("pivot_path", NodePath("../Head/Camera/ViewmodelContainer/SubViewport/ViewCam/HammerPivot"))
	mj.set("hand_mesh_path", NodePath("../Head/Camera/ViewmodelContainer/SubViewport/ViewCam/HammerPivot/Hand"))
	_save(p, "res://player/player.tscn")

# ---------------- Залы ----------------

## Описание залов. Координаты в метрах; y — высота центра блока.
## Блоки: [центр, размер, материал]; врагов: [kind, позиция, волна, (сколько, разброс м, вход)]; пропсы: [тип, позиция].
## Волны по GDD 12.5: корм толпой (60–70 %), бойцы, 1–2 особых на волну.
## Графика мира (комплект владельца): "decor" — картинки на стенах [ключ assets/decor/, позиция, поворот Y, высота м],
## "decals" — декали на полу [ключ assets/decals/, позиция, поворот Y, размер м, (glow)], "no_auto" — без авто-знамён/щитов
## на стенах "north"/"south"/"side", "floor_tex" — рисованная текстура пола (assets/textures/midgard/<ключ>).
func room_defs() -> Array:
	var r: Array = []
	# 1. Зал Бочек — разминка, много физики
	r.append({
		"file": "room_01", "title": "Зал бочек", "w": 24.0, "d": 24.0, "max_alive": 60,
		"blocks": [
			[Vector3(-6, 0.75, -3), Vector3(4, 1.5, 4), "wood"],
			[Vector3(6, 0.75, 2), Vector3(4, 1.5, 4), "wood"],
		],
		"pillars": [Vector3(-6, 0, 6), Vector3(6, 0, -6), Vector3(0, 0, 0)],
		# Открытая вышка: ступени с севера, площадка для удара-приземления.
		"watchtowers": [Vector3(9, 0, -2.5)],
		"jump_pads": [[Vector3(9.5, 0, 4.8), 8.0]],
		"enemies": [["grunt", Vector3(-4, 0, -6), 0], ["grunt", Vector3(4, 0, -7), 0], ["grunt", Vector3(1, 0, -9), 0], ["bloated", Vector3(7, 0, -9), 0], ["grunt", Vector3(-8, 0, -8), 0], ["fodder", Vector3(-8.5, 0, -10.5), 0, 10, 2.25, {"entry_mode": "edge", "entry_target": Vector3(-8.5, 0.05, -7), "spread_axes": Vector2(1.2, 0.35), "entry_batch": 1}],
			["grunt", Vector3(-8, 0, -8), 1], ["grunt", Vector3(7.5, 0, -8), 1], ["thrower", Vector3(-6, 1.6, -3), 1], ["grunt", Vector3(4, 0, -7), 1], ["grunt", Vector3(7, 0, -9), 1], ["fodder", Vector3(-3, 0, -8.5), 1, 11, 2.375],
			["shieldbearer", Vector3(0, 0, -9), 2], ["grunt", Vector3(-8, 0, -8), 2], ["grunt", Vector3(-5.5, 0, -5.5), 2], ["grunt", Vector3(7.5, 0, -8), 2], ["grunt", Vector3(7, 0, -9), 2], ["grunt", Vector3(-10, 0, 8), 2], ["fodder", Vector3(-3.5, 0, -8.5), 2, 12, 2.5]],
		"props": _ring_props(Vector3(0, 0, -3), 3.5, 6, "barrel") + [["crate", Vector3(-9, 0, 3)], ["crate", Vector3(-9, 0.95, 3)], ["crate", Vector3(9, 0, 7)], ["barrel", Vector3(8, 0, 8)]],
	})
	# 2. Ярусы — центральная платформа 2.6 м: нужен двойной или супер-прыжок
	r.append({
		"file": "room_02", "title": "Ярусы Ётунов", "w": 26.0, "d": 24.0, "max_alive": 60,
		"blocks": [
			[Vector3(0, 1.3, -3), Vector3(7, 2.6, 7), "stone_dark"],
			[Vector3(-10, 1.0, -6), Vector3(4, 2, 8), "stone_dark"],
			[Vector3(10, 1.0, -6), Vector3(4, 2, 8), "stone_dark"],
			[Vector3(-4.5, 0.5, 2.5), Vector3(2, 1, 2), "wood"],
		],
		"pillars": [Vector3(-7, 0, 6), Vector3(7, 0, 6)],
		"jump_pads": [[Vector3(0, 0, 5), 8.0]],
		"enemies": [["grunt", Vector3(-5, 0, -8), 0], ["grunt", Vector3(5, 0, -8), 0], ["thrower", Vector3(0, 2.7, -4), 0], ["thrower", Vector3(-10, 2.1, -7), 0], ["grunt", Vector3(-8, 0, 0), 0], ["fodder", Vector3(3, 0, 5.5), 0, 11, 2.375],
			["thrower", Vector3(10, 2.1, -7), 1], ["grunt", Vector3(-3, 0, 4), 1], ["grunt", Vector3(0.5, 0, 2), 1], ["shaman", Vector3(0, 2.7, -2), 1], ["grunt", Vector3(-5, 0, -8), 1], ["grunt", Vector3(-8, 0, 0), 1], ["fodder", Vector3(3.5, 0, 4), 1, 12, 2.5],
			["merc", Vector3(-8, 0, 0), 2], ["bloated", Vector3(6, 0, -10), 2], ["grunt", Vector3(3, 0, 4), 2], ["grunt", Vector3(-3, 0, 4), 2], ["grunt", Vector3(-5.5, 0, -6), 2], ["grunt", Vector3(5, 0, -8), 2], ["fodder", Vector3(-4.5, 0, -9), 2, 13, 2.25]],
		"props": [["barrel", Vector3(-1, 2.6, -1)], ["barrel", Vector3(1, 2.6, -5)], ["crate", Vector3(-8, 0, 3)], ["crate", Vector3(8, 0, 3)], ["barrel", Vector3(0, 0, 3)]],
	})
	# 3. Кольцо колонн — вокруг башни 5 м (супер-прыжок + двойной на неё)
	r.append({
		"file": "room_03", "title": "Кольцо колонн", "w": 28.0, "d": 28.0, "max_alive": 60,
		"blocks": [
			[Vector3(0, 2.5, -2), Vector3(4, 5, 4), "stone_dark"],
			[Vector3(0, 0.6, 4), Vector3(3, 1.2, 3), "wood"],
		],
		"pillars": _ring_points(Vector3(0, 0, -2), 9.0, 8),
		"jump_pads": [[Vector3(-3.5, 0, 6.5), 9.0], [Vector3(3.5, 0, 6.5), 9.0]],
		# Башня — круглая (каменный барабан и деревянная площадка по коллизии 4 × 4)
		"dress": {"styles": {0: "tower"}},
		"enemies": [["grunt", Vector3(-5.5, 0, -7), 0], ["grunt", Vector3(6, 0, -8), 0], ["grunt", Vector3(-8, 0, -0.5), 0], ["grunt", Vector3(7.5, 0, 0), 0], ["bloated", Vector3(-10, 0, -6), 0], ["grunt", Vector3(10, 0, -10), 0], ["fodder", Vector3(-7.5, 0, -10), 0, 12, 2.5],
			["thrower", Vector3(0, 5.1, -2), 1], ["thrower", Vector3(-10, 0, -10), 1], ["grunt", Vector3(11, 0, -10), 1], ["grunt", Vector3(0, 0, -11), 1], ["grunt", Vector3(-8, 0, -0.5), 1], ["grunt", Vector3(-6, 0, -8), 1], ["fodder", Vector3(7.5, 0, -9.5), 1, 13, 2.625],
			["shaman", Vector3(0.5, 5.1, -1.5), 2], ["shieldbearer", Vector3(0, 0, -8), 2], ["grunt", Vector3(10, 0, -10), 2], ["grunt", Vector3(7.5, 0, 0), 2], ["grunt", Vector3(6, 0, -8), 2], ["grunt", Vector3(-8, 0, -0.5), 2], ["grunt", Vector3(0, 0, -11), 2], ["fodder", Vector3(-8, 0, -10), 2, 14, 2.75]],
		"props": _ring_props(Vector3(0, 0, -2), 5.5, 8, "crate"),
	})
	# 4. Коридор Хель — длинный зал, метатели в конце, укрытия
	r.append({
		"file": "room_04", "title": "Коридор Хель", "w": 16.0, "d": 34.0, "max_alive": 60,
		"blocks": [
			[Vector3(-4, 0.6, 6), Vector3(4, 1.2, 1), "stone_dark"],
			[Vector3(4, 0.6, 0), Vector3(4, 1.2, 1), "stone_dark"],
			[Vector3(-4, 0.6, -6), Vector3(4, 1.2, 1), "stone_dark"],
			[Vector3(0, 1.0, -13), Vector3(10, 2, 3), "stone_dark"],
			# Открытые ворота внутри западной границы: боковые стены и перемычка,
			# пол и невидимая внешняя граница остаются непрерывными.
			[Vector3(-6.75, 1.8, 9.1), Vector3(2.5, 3.6, 0.6), "wood"],
			[Vector3(-6.75, 1.8, 13.9), Vector3(2.5, 3.6, 0.6), "wood"],
			[Vector3(-5.5, 3.45, 11.5), Vector3(0.7, 0.7, 5.4), "wood"],
		],
		"pillars": [],
		"enemies": [["thrower", Vector3(-3, 2.1, -13), 0], ["thrower", Vector3(3, 2.1, -13), 0], ["grunt", Vector3(-4, 0, -3), 0], ["grunt", Vector3(4.5, 0, -9), 0], ["grunt", Vector3(0, 0, 2), 0], ["grunt", Vector3(-5, 0, -10), 0], ["fodder", Vector3(-7.2, 0, 11.5), 0, 13, 2.625, {"entry_mode": "gate", "entry_target": Vector3(-3.5, 0.05, 11.5), "spread_axes": Vector2(0.1, 1.5), "entry_batch": 1}],
			["grunt", Vector3(-5, 0, -10), 1], ["grunt", Vector3(0, 0, -8), 1], ["grunt", Vector3(0.5, 0, 2.5), 1], ["merc", Vector3(0, 2.1, -13), 1], ["bloated", Vector3(5, 0, -10), 1], ["grunt", Vector3(4, 0, -9), 1], ["grunt", Vector3(-6, 0, 15), 1], ["fodder", Vector3(-2, 0, -0.5), 1, 14, 2.75],
			["shieldbearer", Vector3(0, 0, -8), 2], ["bloated", Vector3(-5, 0, -10), 2], ["grunt", Vector3(5, 0, -10), 2], ["grunt", Vector3(0, 0, 2), 2], ["grunt", Vector3(-4, 0, -3), 2], ["fodder", Vector3(-1.5, 0, -1), 2, 10, 2.25]],
		"props": [["barrel", Vector3(-6.8, 0, 6.8)], ["barrel", Vector3(6, 0, 4)], ["crate", Vector3(-6, 0, -2)], ["crate", Vector3(6, 0, -6)], ["barrel", Vector3(0, 0, -4)]],
	})
	# 5. Мост — пониженная середина, два «берега»
	r.append({
		"file": "room_05", "title": "Мост Биврёст (сломан)", "w": 30.0, "d": 22.0, "max_alive": 60,
		"blocks": [
			[Vector3(-10.5, 1.0, 0), Vector3(9, 2, 22), "stone_dark"],
			[Vector3(10.5, 1.0, 0), Vector3(9, 2, 22), "stone_dark"],
			[Vector3(0, 1.75, -2), Vector3(12, 0.5, 2.5), "wood"],
		],
		"pillars": [Vector3(-3, 0, 6), Vector3(3, 0, -7)],
		"enemies": [["grunt", Vector3(-10, 2, -6), 0], ["grunt", Vector3(10, 2, -6), 0], ["grunt", Vector3(0, 0, -6), 0], ["thrower", Vector3(10, 2, 6), 0], ["grunt", Vector3(-10, 2, 4), 0], ["grunt", Vector3(0, 0, 3), 0], ["grunt", Vector3(12.5, 2, 2.5), 0], ["fodder", Vector3(7.25, 2, 4), 0, 14, 2.75, {"entry_mode": "balcony", "entry_target": Vector3(4.4, 0.05, 4), "spread_axes": Vector2(0.35, 3.5), "entry_batch": 1}],
			["grunt", Vector3(-10, 2, 4), 1], ["grunt", Vector3(10, 2, 2), 1], ["thrower", Vector3(-11, 2, -8), 1], ["grunt", Vector3(-3, 0, 2), 1], ["merc", Vector3(12, 2, -8), 1], ["fodder", Vector3(0, 0, 3), 1, 10, 2.25],
			["shaman", Vector3(12, 2, -5), 2], ["shieldbearer", Vector3(2, 2.1, -2), 2], ["grunt", Vector3(-10, 2, 4), 2], ["grunt", Vector3(-10, 2, -6), 2], ["grunt", Vector3(10, 2, 2), 2], ["fodder", Vector3(0, 0, 2.5), 2, 11, 2.375]],
		"props": [["barrel", Vector3(-12, 2, 3)], ["barrel", Vector3(12, 2, -3)], ["crate", Vector3(0, 2.0, -2)], ["crate", Vector3(2, 0, 6)], ["barrel", Vector3(-2, 0, -8)]],
		"spawn_y": 2.0,
	})
	# 6. Склад медовухи — штабеля ящиков, крушить всё
	r.append({
		"file": "room_06", "title": "Склад медовухи", "w": 26.0, "d": 26.0, "max_alive": 60,
		"blocks": [
			[Vector3(-7, 1.0, -5), Vector3(5, 2, 3), "wood"],
			[Vector3(7, 1.0, 1), Vector3(5, 2, 3), "wood"],
		],
		"pillars": [Vector3(0, 0, -4)],
		"watchtowers": [Vector3(10, 0, -4)],
		"enemies": [["grunt", Vector3(4, 0, -9.5), 0], ["grunt", Vector3(0.5, 0, -11), 0], ["bloated", Vector3(-4, 0, -9), 0], ["merc", Vector3(8, 0, -9), 0], ["grunt", Vector3(-6, 0, 4), 0], ["fodder", Vector3(-0.5, 0, -8), 0, 10, 2.25],
			["thrower", Vector3(-7, 2.1, -5), 1], ["thrower", Vector3(7, 2.1, 1), 1], ["grunt", Vector3(-6, 0, 4), 1], ["grunt", Vector3(6, 0, -6), 1], ["grunt", Vector3(-4, 0, -9), 1], ["fodder", Vector3(6.5, 0, -10), 1, 11, 2],
			["shaman", Vector3(-7.5, 2.1, -5.5), 2], ["shieldbearer", Vector3(0, 0, -9), 2], ["grunt", Vector3(8, 0, -9), 2], ["grunt", Vector3(-4, 0, -9), 2], ["grunt", Vector3(4, 0, -9.5), 2], ["grunt", Vector3(6, 0, -6), 2], ["fodder", Vector3(-5.5, 0, 7.5), 2, 12, 2.5]],
		"props": _stack_props(Vector3(-3, 0, 3)) + _stack_props(Vector3(3, 0, -8)) + _stack_props(Vector3(-9, 0, 5)) + [["barrel", Vector3(9, 0, 8)], ["barrel", Vector3(10, 0, 7)], ["barrel", Vector3(-10, 0, -10)]],
		# Плакат «Разыскивается» (Локи) на западной стене склада, у входа
		"decor": [["wanted_poster", Vector3(-13 + WALL_INSET, 1.9, 1.0), 90.0, 1.5]],
		# Разлитая медовуха у штабелей и бочек
		"decals": [["puddle_mead", Vector3(9.5, 0, 6.5), 40.0, 2.6], ["puddle_mead", Vector3(-1.5, 0, 5.0), 200.0, 1.8]],
	})
	# 7. Причал с драккаром (GDD 16) — корабль (модель Quaternius Pirate Kit поверх невидимой коллизии: палуба 2.2 м,
	# нос 3.2 м), склад на берегу 3 м. Наверх: сходни-ящики 1.1 м → палуба (залезание), прыжковая руна у склада.
	r.append({
		"file": "room_07", "title": "Причал с драккаром", "w": 26.0, "d": 30.0, "max_alive": 60,
		"blocks": [
			[Vector3(6, 1.1, 0), Vector3(5, 2.2, 15), "none"],
			[Vector3(6, 1.6, -9.0), Vector3(3, 3.2, 2), "none"],
			[Vector3(2.0, 0.55, 2), Vector3(3, 1.1, 2), "wood"],
			[Vector3(2.0, 0.55, -5), Vector3(3, 1.1, 2), "wood"],
			[Vector3(-8, 1.5, 4), Vector3(8, 3, 6), "stone_dark"],
		],
		"pillars": [],
		"models": [["res://assets/quaternius/pirate/Ship_Large.gltf", Vector3(6, SHIP_Y, 0), 90.0, 1.0]],
		"jump_pads": [[Vector3(-3, 0, 9), 8.0]],
		"enemies": [["grunt", Vector3(-4, 0, -6), 0], ["grunt", Vector3(-8, 0, -6), 0], ["thrower", Vector3(6, 2.3, 5), 0], ["bloated", Vector3(-9, 0, -9), 0], ["grunt", Vector3(6, 2.3, -4), 0], ["fodder", Vector3(-4, 0, -2), 0, 11, 2.375],
			["shaman", Vector3(-8, 3.1, 4), 1], ["merc", Vector3(6, 3.3, -9.5), 1], ["grunt", Vector3(6, 2.3, -4), 1], ["grunt", Vector3(6, 2.3, 5.5), 1], ["grunt", Vector3(-9, 0, -9), 1], ["grunt", Vector3(-8, 0, -6), 1], ["fodder", Vector3(-4, 0, -4), 1, 12, 2.5],
			["shieldbearer", Vector3(-2, 0, -8), 2], ["thrower", Vector3(6, 2.3, -6), 2], ["grunt", Vector3(6, 2.3, 5.5), 2], ["grunt", Vector3(-9, 0, -9), 2], ["grunt", Vector3(-8, 0, -6), 2], ["grunt", Vector3(-4, 0, -6), 2], ["fodder", Vector3(-5, 0, -10), 2, 13, 2.625]],
		"props": [["barrel", Vector3(-11, 0, -2)], ["barrel", Vector3(-10, 0, -1)], ["barrel", Vector3(-11, 0, 0)], ["crate", Vector3(-4, 0, 6)], ["crate", Vector3(-4, 0.92, 6)],
			["barrel", Vector3(5, 2.2, 6)], ["barrel", Vector3(7, 2.2, -3)], ["crate", Vector3(-11, 3.0, 6)], ["barrel", Vector3(-1, 0, -11)]],
	})
	# 8. Яма-колизей (GDD 16) — яма с кормом посередине, трибуны-террасы 2 м по бокам, ложи 4 м в углах.
	# Наверх: ступени 1 м → террасы → ложи (залезание), прыжковая руна в центре ямы — 10 м над ареной.
	r.append({
		"file": "room_08", "title": "Яма-колизей", "w": 28.0, "d": 28.0, "max_alive": 60,
		"blocks": [
			[Vector3(-11, 1.0, 0), Vector3(6, 2, 20), "stone_dark"],
			[Vector3(11, 1.0, 0), Vector3(6, 2, 20), "stone_dark"],
			[Vector3(-11, 2.0, -9), Vector3(6, 4, 4), "stone_dark"],
			[Vector3(11, 2.0, 9), Vector3(6, 4, 4), "stone_dark"],
			[Vector3(-6.5, 0.5, 6), Vector3(3, 1, 3), "wood"],
			[Vector3(6.5, 0.5, -6), Vector3(3, 1, 3), "wood"],
		],
		"pillars": [Vector3(-4, 0, -8), Vector3(4, 0, 8)],
		"jump_pads": [[Vector3(0, 0, 0), 10.0]],
		# Следы прошлых боёв в яме: подпалины и засохший ихор
		"decals": [["scorch", Vector3(-4.5, 0, 3.5), 15.0, 3.2], ["scorch", Vector3(4, 0, -9), 120.0, 2.6], ["ichor_splat_02", Vector3(3, 0, 4.5), 70.0, 1.8]],
		"enemies": [["grunt", Vector3(-4, 0, -2), 0], ["grunt", Vector3(4, 0, -4), 0], ["thrower", Vector3(-11, 2.1, -3), 0], ["thrower", Vector3(11, 2.1, 3), 0], ["grunt", Vector3(-11, 2.1, 6), 0], ["grunt", Vector3(0, 0, -8), 0], ["fodder", Vector3(0, 0, -3), 0, 12, 2.5],
			["shaman", Vector3(-11, 4.1, -9), 1], ["merc", Vector3(11, 2.1, -6), 1], ["grunt", Vector3(0, 0, -8), 1], ["grunt", Vector3(-11, 2.1, 6), 1], ["grunt", Vector3(4, 0, -4), 1], ["grunt", Vector3(-4, 0, -2), 1], ["fodder", Vector3(-2, 0, 2), 1, 13, 2.625],
			["bloated", Vector3(0, 0, -8), 2], ["shieldbearer", Vector3(0, 0, -6), 2], ["grunt", Vector3(-11, 2.1, 6), 2], ["grunt", Vector3(-3, 0, 2), 2], ["grunt", Vector3(-4, 0, -2), 2], ["grunt", Vector3(4, 0, 4), 2], ["grunt", Vector3(-12, 0, -12), 2], ["fodder", Vector3(2, 0, -2), 2, 14, 2.75]],
		"props": _ring_props(Vector3(0, 0, 0), 6.5, 8, "barrel") + [["crate", Vector3(-13, 2.0, 8)], ["crate", Vector3(13, 2.0, -8)], ["crate", Vector3(-12, 4.0, -10)]],
	})
	# 9. Деревня (GDD 16) — дома с плоскими крышами 2.5–3 м, мост между домами над улицей, площадь.
	# Наверх: ящики-ступени 1 м → крыши (залезание), прыжковая руна на площади, мост.
	r.append({
		"file": "room_09", "title": "Деревня у фьорда", "w": 30.0, "d": 28.0, "max_alive": 60,
		"blocks": [
			[Vector3(-9, 1.5, -5), Vector3(6, 3, 5), "wood"],
			[Vector3(9, 1.5, -5), Vector3(6, 3, 5), "wood"],
			[Vector3(-9, 1.5, 6), Vector3(5, 3, 5), "wood"],
			[Vector3(9, 1.25, 6), Vector3(5, 2.5, 5), "wood"],
			[Vector3(0, 2.85, -5), Vector3(12, 0.3, 2), "wood"],
			[Vector3(-5.5, 0.5, 6), Vector3(2, 1, 2), "wood"],
			[Vector3(6, 0.5, 2.5), Vector3(2, 1, 2), "wood"],
			[Vector3(-5, 0.5, -1.5), Vector3(2, 1, 2), "wood"],
		],
		"pillars": [],
		"houses": [[0, "s", "Plaster"], [1, "s", "UnevenBrick"], [2, "e", "UnevenBrick"], [3, "w", "Plaster"]],
		# Улица деревни — утоптанная земля с соломой (assets/textures/midgard/dirt_straw)
		"floor_tex": "dirt_straw",
		"jump_pads": [[Vector3(0, 0, 3), 8.0]],
		"enemies": [["grunt", Vector3(-3, 0, -9), 0], ["grunt", Vector3(3, 0, -9), 0], ["thrower", Vector3(-10, 3.1, -4), 0], ["bloated", Vector3(-12, 0, 0), 0], ["grunt", Vector3(12, 0, 0), 0], ["grunt", Vector3(0, 0, -8), 0], ["fodder", Vector3(0, 0, -1), 0, 13, 2.625],
			["shaman", Vector3(0, 3.1, -5), 1], ["merc", Vector3(10, 2.6, 5), 1], ["grunt", Vector3(-12, 0, 0), 1], ["grunt", Vector3(12, 0, 0), 1], ["grunt", Vector3(-3, 0, -9), 1], ["grunt", Vector3(3, 0, -9), 1], ["grunt", Vector3(0, 0, -8), 1], ["fodder", Vector3(3, 0, -1), 1, 14, 2.75],
			["shieldbearer", Vector3(0, 0, -8), 2], ["thrower", Vector3(-9, 3.1, 6), 2], ["grunt", Vector3(12, 0, 0), 2], ["grunt", Vector3(-12, 0, 0), 2], ["grunt", Vector3(-3, 0, -9), 2], ["fodder", Vector3(1, 0, 0), 2, 10, 2.25]],
		"props": [["barrel", Vector3(-12, 0, -10)], ["barrel", Vector3(12, 0, -10)], ["crate", Vector3(-13, 0, 1)], ["crate", Vector3(13, 0, 1)], ["barrel", Vector3(2, 0, 7)],
			["barrel", Vector3(-2, 0, 8)], ["crate", Vector3(-9, 3.0, -5.5)], ["barrel", Vector3(9, 3.0, -4)], ["crate", Vector3(9, 2.5, 7)]],
		# Плакаты на южных стенах домов (лицевая сторона модулей — z = −2.31): «Разыскивается» и Один «Качайся!»
		"decor": [["wanted_poster", Vector3(-11, 1.75, -2.31 + WALL_INSET), 0.0, 1.4], ["odin_poster", Vector3(11, 1.75, -2.31 + WALL_INSET), 0.0, 1.4]],
	})
	return r

## Блок — деревянный настил над полом: материал "wood", толщина ≤ 0.5 м, низ выше 1 м (мост деревни, Биврёст).
func _is_wood_deck(b: Array) -> bool:
	var c: Vector3 = b[0]
	var sz: Vector3 = b[1]
	return b[2] == "wood" and sz.y <= 0.5 and c.y - sz.y * 0.5 > 1.0

func _ring_points(c: Vector3, radius: float, n: int) -> Array:
	var out: Array = []
	for i in n:
		var a := TAU * i / n + PI / n
		out.append(c + Vector3(cos(a) * radius, 0, sin(a) * radius))
	return out

func _ring_props(c: Vector3, radius: float, n: int, kind: String) -> Array:
	var out: Array = []
	for p in _ring_points(c, radius, n):
		out.append([kind, p])
	return out

func _stack_props(base: Vector3) -> Array:
	return [["crate", base], ["crate", base + Vector3(0.95, 0, 0)], ["crate", base + Vector3(0.45, 0.92, 0)], ["crate", base + Vector3(0, 0, 0.95)]]

## Блок Б0 «Одеть залы»: общие меши и материалы одевания (rooms/meshes, rooms/materials) и даль за стенами.
func build_dress() -> void:
	print("Одевание залов: меши, материалы, даль…")
	RoomDresser.build_assets()
	_save(RoomDresser.build_backdrop(), RoomDresser.BACKDROP_SCENE)

## Стиль одевания блока зала (RoomDresser): дом, мост/настил, только коллизия, дерево, камень;
## ключ "dress": {"styles": {индекс: стиль}} зала перекрывает (например, "tower" — круглая башня).
func _block_style(d: Dictionary, i: int) -> String:
	var over: Dictionary = (d.get("dress", {}) as Dictionary).get("styles", {})
	if over.has(i):
		return over[i]
	for h in d.get("houses", []):
		if h[0] == i:
			return "house"
	var b: Array = d.blocks[i]
	if _is_wood_deck(b):
		return "deck"
	if b[2] == "none":
		return "none"
	return "wood" if b[2] == "wood" else "stone"

## Бочка и ящик в свободных углах зала (не больше двух): углы не пустые, а пропсы — разрушаемые.
func _corner_props(d: Dictionary) -> Array:
	var out: Array = []
	var hw: float = d.w * 0.5 - 1.1
	var hd: float = d.d * 0.5 - 1.1
	var kinds := ["barrel", "crate"]
	for c in [Vector3(-hw, 0, -hd), Vector3(hw, 0, hd), Vector3(hw, 0, -hd), Vector3(-hw, 0, hd)]:
		if out.size() >= 2:
			break
		var ok := true
		for b in d.blocks:
			var bc: Vector3 = b[0]
			var bs: Vector3 = b[1]
			if absf(c.x - bc.x) < bs.x * 0.5 + 1.2 and absf(c.z - bc.z) < bs.z * 0.5 + 1.2:
				ok = false
		for pr in d.props:
			if (pr[1] as Vector3).distance_to(c) < 2.0:
				ok = false
		for jp in d.get("jump_pads", []):
			if (jp[0] as Vector3).distance_to(c) < 2.5:
				ok = false
		if ok:
			out.append([kinds[out.size() % 2], c])
	return out

func build_rooms() -> void:
	print("Залы…")
	for d in room_defs():
		_build_room(d, false)
	# Зал-ларёк Брокка и Эйтри (блок К): без врагов, сам ларёк собирает rooms/shop_stall.gd
	_build_room(shop_room_def(), false)
	# Арены боссов (Длинный дом Ярла, погреб Свена) — ручные сцены, см. MANUAL_SCENES

## Открытая вышка 3.75 м. Четыре ступени с северной стороны дают пройти наверх
## обычными прыжками; видимые опоры/перила не меняют физику и не закрывают обзора.
func _watchtower(parent: Node, name: String, center: Vector3, mat: Material) -> void:
	var tower := Node3D.new()
	tower.name = name
	tower.position = center
	parent.add_child(tower)
	_box(tower, "Deck", Vector3(0, 3.61, 0), Vector3(2.8, 0.28, 2.8), mat)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(tower, "Post_%d_%d" % [int(sx), int(sz)], Vector3(sx * 1.18, 1.7, sz * 1.18), Vector3(0.22, 3.4, 0.22), mat, false)
	for i in 4:
		var top := 0.75 * (i + 1)
		var z := -4.8 + i
		_box(tower, "Step%d" % i, Vector3(0, top - 0.09, z), Vector3(1.5, 0.18, 0.95), mat)
		for sx in [-1.0, 1.0]:
			_box(tower, "StepPost%d_%d" % [i, int(sx)], Vector3(sx * 0.62, top * 0.5, z), Vector3(0.14, top, 0.14), mat, false)
	# Перила — только вид; северная сторона открыта для выхода со ступеней.
	for sx in [-1.0, 1.0]:
		_box(tower, "Rail_%d" % int(sx), Vector3(sx * 1.32, 4.35, 0), Vector3(0.12, 0.12, 2.5), mat, false)
	_box(tower, "RailSouth", Vector3(0, 4.35, 1.32), Vector3(2.5, 0.12, 0.12), mat, false)

func _build_room(d: Dictionary, boss: bool) -> void:
	# Случайные повороты пропсов — одни и те же при каждом запуске генератора (меньше шума в .tscn)
	seed(hash(d.file))
	var root := Node3D.new()
	root.name = d.file.capitalize().replace(" ", "")
	root.set_script(load("res://rooms/room.gd"))
	root.set("room_title", d.title)
	root.set("max_alive", int(d.get("max_alive", 0)))
	var w: float = d.w
	var dep: float = d.d
	var h := 6.0
	var floor_mat := _tex_mat("q_floor", "Brick", Color(0.72, 0.68, 0.64), 0.35)
	var wall_mat: Material = null  # стены — модели Quaternius, у коробок только коллизия
	var mats := {
		"wood": _tex_mat("q_wood", "WoodTrim", Color(0.85, 0.75, 0.65), 0.5),
		"stone_dark": _tex_mat("q_rock", "RockTrim", Color(0.7, 0.7, 0.74), 0.4),
	}
	var pillar_mat := _tex_mat("q_pillar", "UnevenBrick", Color(0.8, 0.78, 0.75), 0.45)
	for kind in MIDGARD_BLOCKS:
		mats[kind] = _world_tex_mat("m_" + kind, MIDGARD_BLOCKS[kind], Color(0.9, 0.9, 0.92), 0.3)
	if d.has("floor_tex"):
		floor_mat = _world_tex_mat("m_floor_" + d.floor_tex, d.floor_tex, Color(0.92, 0.9, 0.88), 0.3)

	var geo := Node3D.new()
	geo.name = "Geometry"
	root.add_child(geo)
	_box(geo, "Floor", Vector3(0, -0.5, 0), Vector3(w + 2, 1, dep + 2), floor_mat)
	# Стены (дверной проём 4 м по центру северной стены, z = -d/2)
	var gap := 4.0
	var side_w := (w - gap) / 2.0
	_box(geo, "WallN_L", Vector3(-(gap / 2 + side_w / 2), h / 2, -dep / 2 - 0.5), Vector3(side_w, h, 1), wall_mat)
	_box(geo, "WallN_R", Vector3(gap / 2 + side_w / 2, h / 2, -dep / 2 - 0.5), Vector3(side_w, h, 1), wall_mat)
	_box(geo, "WallS", Vector3(0, h / 2, dep / 2 + 0.5), Vector3(w + 2, h, 1), wall_mat)
	_box(geo, "WallW", Vector3(-w / 2 - 0.5, h / 2, 0), Vector3(1, h, dep + 2), wall_mat)
	_box(geo, "WallE", Vector3(w / 2 + 0.5, h / 2, 0), Vector3(1, h, dep + 2), wall_mat)
	# Стены — секции Quaternius (UnevenBrick), в 2 ряда
	var walls := Node3D.new()
	walls.name = "WallModels"
	geo.add_child(walls)
	_wall_row(walls, "N_L", Vector3(-w / 2, 0, -dep / 2 - 0.1), side_w, 0)
	_wall_row(walls, "N_R", Vector3(gap / 2, 0, -dep / 2 - 0.1), side_w, 0)
	_wall_row(walls, "S", Vector3(w / 2, 0, dep / 2 + 0.1), w, 180)
	_wall_row(walls, "W", Vector3(-w / 2 - 0.1, 0, dep / 2), dep, 90)
	_wall_row(walls, "E", Vector3(w / 2 + 0.1, 0, -dep / 2), dep, -90)
	_wall_row(walls, "CL", Vector3(-gap / 2 - 0.1, 0, -dep / 2 - 0.5), 5.0, 90)
	_wall_row(walls, "CR", Vector3(gap / 2 + 0.1, 0, -dep / 2 - 5.5), 5.0, -90)
	_wall_row(walls, "CE", Vector3(-gap / 2 - 1, 0, -dep / 2 - 5.6), gap + 2, 0)
	# Коридор за дверью
	_box(geo, "CorridorFloor", Vector3(0, -0.5, -dep / 2 - 3), Vector3(gap + 2, 1, 5), floor_mat)
	_box(geo, "CorridorL", Vector3(-gap / 2 - 0.5, h / 2, -dep / 2 - 3), Vector3(1, h, 5), wall_mat)
	_box(geo, "CorridorR", Vector3(gap / 2 + 0.5, h / 2, -dep / 2 - 3), Vector3(1, h, 5), wall_mat)
	_box(geo, "CorridorEnd", Vector3(0, h / 2, -dep / 2 - 6), Vector3(gap + 2, h, 1), wall_mat)
	var portal := _mat("portal", Color(0.45, 0.8, 1.0), 0.3, false, 2.5)
	_box(geo, "Portal", Vector3(0, 2.2, -dep / 2 - 5.45), Vector3(2.6, 3.6, 0.1), portal, false)

	for i in d.blocks.size():
		var b: Array = d.blocks[i]
		if _is_wood_deck(b):
			# Деревянный мост/настил над полом (GDD 16): ломается ударом-приземлением сверху (rooms/balcony.gd),
			# при новом заходе в зал — снова целый (зал собирается из сцены заново)
			_balcony(geo, "Block%d" % i, b[0], b[1], mats.wood, false, true)
			continue
		# "none" — только коллизия (вид даёт декоративная модель из "models", например корпус корабля)
		_box(geo, "Block%d" % i, b[0], b[1], null if b[2] == "none" else mats.get(b[2], mats.stone_dark))
	# Небольшие наблюдательные вышки: реальные ступени и настил, декоративные опоры.
	var towers: Array = d.get("watchtowers", [])
	for i in towers.size():
		_watchtower(geo, "Watchtower%d" % i, towers[i], mats.wood)
	for i in d.pillars.size():
		var pp: Vector3 = d.pillars[i]
		_cyl(geo, "Pillar%d" % i, pp + Vector3(0, h / 2, 0), 0.8, h, pillar_mat)
		_cyl(geo, "PillarBase%d" % i, pp + Vector3(0, 0.25, 0), 1.05, 0.5, pillar_mat)
		_cyl(geo, "PillarCap%d" % i, pp + Vector3(0, h - 0.2, 0), 1.0, 0.4, pillar_mat)

	# Разрушаемые балконы: [центр настила, размер настила] — rooms/balcony.gd
	var bals: Array = d.get("balconies", [])
	if not bals.is_empty():
		var bnode := Node3D.new()
		bnode.name = "Balconies"
		root.add_child(bnode)
		for i in bals.size():
			_balcony(bnode, "Balcony%d" % i, bals[i][0], bals[i][1], mats.wood)

	# Дверь
	var door := _box(root, "Door", Vector3(0, h / 2, -dep / 2 - 0.5), Vector3(gap, h, 0.6), _tex_mat("q_door", "WoodTrim", Color(0.55, 0.32, 0.25), 0.6))
	var door_rune := _mat("door_rune", Color(1.0, 0.45, 0.2), 0.5, false, 3.0)
	_box(door, "Rune", Vector3(0, 0.3, 0.33), Vector3(0.5, 2.2, 0.05), door_rune, false)
	_box(door, "RuneBar", Vector3(0, 0.9, 0.33), Vector3(1.4, 0.3, 0.05), door_rune, false)

	# Выход
	var exit := Area3D.new()
	exit.name = "Exit"
	exit.collision_layer = TRIGGER_L
	exit.collision_mask = PLAYER_L
	exit.position = Vector3(0, 1.5, -dep / 2 - 4)
	var es := CollisionShape3D.new()
	es.name = "Shape"
	var ebox := BoxShape3D.new()
	ebox.size = Vector3(gap, 3, 2.5)
	es.shape = ebox
	exit.add_child(es)
	root.add_child(exit)

	# Точка появления игрока — у южной стены, лицом к двери
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.position = Vector3(0, float(d.get("spawn_y", 0.0)) + 0.1, dep / 2 - 2.5)
	if d.get("spawn_y", 0.0) > 0.0:
		spawn.position = Vector3(-w / 2 + 4, float(d.spawn_y) + 0.1, dep / 2 - 2.5)
	root.add_child(spawn)

	# Маркеры врагов
	var spawns := Node3D.new()
	spawns.name = "Spawns"
	root.add_child(spawns)
	for i in d.enemies.size():
		var e: Array = d.enemies[i]
		var m := Marker3D.new()
		m.name = "%s_%d" % [e[0], i]
		m.position = e[1] + Vector3(0, 0.05, 0)
		m.set_meta("kind", e[0])
		m.set_meta("wave", e[2])
		if e.size() > 3:
			m.set_meta("count", e[3])
			m.set_meta("spread", e[4] if e.size() > 4 else 1.5)
		if e.size() > 5:
			var entry: Dictionary = e[5]
			for key in ["entry_mode", "entry_target", "spread_axes", "entry_batch"]:
				if entry.has(key):
					m.set_meta(key, entry[key])
		spawns.add_child(m)

	# Особые точки (не волны): {"Имя": Vector3} — один маркер, {"Имя": [Vector3...]} — группа маркеров
	var marks: Dictionary = d.get("markers", {})
	for mname in marks:
		var v: Variant = marks[mname]
		if v is Vector3:
			var mk := Marker3D.new()
			mk.name = mname
			mk.position = v + Vector3(0, 0.05, 0)
			root.add_child(mk)
		else:
			var grp := Node3D.new()
			grp.name = mname
			root.add_child(grp)
			for k in (v as Array).size():
				var mk2 := Marker3D.new()
				mk2.name = "%s%d" % [mname.trim_suffix("s"), k]
				mk2.position = (v as Array)[k] + Vector3(0, 0.05, 0)
				grp.add_child(mk2)

	# Дома из модулей MegaKit вокруг блоков: [индекс блока в "blocks", сторона двери, стиль]
	var houses: Array = d.get("houses", [])
	if not houses.is_empty():
		var hnode := Node3D.new()
		hnode.name = "Houses"
		root.add_child(hnode)
		for i in houses.size():
			var hb: Array = d.blocks[houses[i][0]]
			_house(hnode, "House%d" % i, hb[0], hb[1], houses[i][1], houses[i][2] if (houses[i] as Array).size() > 2 else "Plaster")

	# Декоративные модели (без коллизии): [путь к сцене, позиция, поворот по Y (град), масштаб]
	var models: Array = d.get("models", [])
	if not models.is_empty():
		var dnode := Node3D.new()
		dnode.name = "Decor"
		root.add_child(dnode)
		for i in models.size():
			var md: Array = models[i]
			var inst := (load(md[0]) as PackedScene).instantiate() as Node3D
			inst.name = "%s_%d" % [(md[0] as String).get_file().get_basename(), i]
			inst.position = md[1]
			inst.rotation_degrees.y = md[2]
			inst.scale = Vector3.ONE * float(md[3])
			dnode.add_child(inst)

	# Прыжковые руны (GDD 7.2): [позиция на полу, высота подброса]
	var pads: Array = d.get("jump_pads", [])
	if not pads.is_empty():
		var pnode := Node3D.new()
		pnode.name = "JumpPads"
		root.add_child(pnode)
		for i in pads.size():
			var jp := Area3D.new()
			jp.name = "JumpPad%d" % i
			jp.set_script(load("res://rooms/jump_pad.gd"))
			jp.position = (pads[i] as Array)[0]
			jp.set("height", (pads[i] as Array)[1])
			pnode.add_child(jp)

	# Бочки и ящики
	var props := Node3D.new()
	props.name = "Props"
	root.add_child(props)
	var prop_scenes := {}
	var all_props: Array = d.props + (_corner_props(d) if (d.get("dress", {}) as Dictionary).get("corner_props", true) else [])
	for i in all_props.size():
		var pr: Array = all_props[i]
		# "barrel", "crate", "barrel_explosive" → props/<вид>.tscn
		if not prop_scenes.has(pr[0]):
			prop_scenes[pr[0]] = load("res://props/%s.tscn" % pr[0]) as PackedScene
		var inst := (prop_scenes[pr[0]] as PackedScene).instantiate() as Node3D
		inst.name = "%s_%d" % [pr[0], i]
		inst.position = pr[1] + Vector3(0, 0.02, 0)
		inst.rotation.y = randf() * TAU
		props.add_child(inst)

	# Факелы
	var lights := Node3D.new()
	lights.name = "Torches"
	root.add_child(lights)
	var ty := float(d.get("torch_y", 3.2))
	var torch_pos := [Vector3(-w / 2 + 0.2, ty, -dep / 4), Vector3(w / 2 - 0.2, ty, -dep / 4), Vector3(-w / 2 + 0.2, ty, dep / 4), Vector3(w / 2 - 0.2, ty, dep / 4),
		Vector3(-gap / 2 - 1.2, 3.6, -dep / 2 + 0.1), Vector3(gap / 2 + 1.2, 3.6, -dep / 2 + 0.1)]
	var flame := _mat("flame", Color(1.0, 0.6, 0.2), 0.5, false, 5.0)
	var holder := _mat("holder", Color(0.25, 0.22, 0.2), 0.6, false)
	for i in torch_pos.size():
		var t := Node3D.new()
		t.name = "Torch%d" % i
		t.position = torch_pos[i]
		lights.add_child(t)
		# Модель Quaternius Torch_Metal смотрит в +Z — разворачиваем от стены внутрь зала
		var p3: Vector3 = torch_pos[i]
		var yaw := 0.0
		if absf(p3.x) > w / 2 - 1.0:
			yaw = 90.0 if p3.x < 0 else -90.0
		t.rotation_degrees.y = yaw
		_model(t, "Model", QP + "Torch_Metal.gltf", Vector3(0, -0.3, -0.25), Vector3.ZERO, Vector3.ONE * 1.4)
		_mesh(t, "Flame", _cylmesh(0.0, 0.11, 0.3), Vector3(0, 0.38, 0.08), flame)
		var l := OmniLight3D.new()
		l.name = "Light"
		l.light_color = Color(1.0, 0.62, 0.3)
		l.light_energy = 2.2
		l.omni_range = 9.0
		l.position = Vector3(0, 0.3, 0)
		t.add_child(l)

	# Знамёна, щиты и плакаты на стенах (комплект владельца assets/decor/, rooms/wall_decor.gd): авто-расстановка
	# по стенам + ключ "decor" зала. Квады собираются при запуске из общего материала WorldArt.
	_build_wall_art(root, d, w, dep, gap)
	# Статичные декали на полу (assets/decals/, rooms/floor_decal.gd): [декаль, позиция, поворот Y, размер м, (glow)]
	var decals: Array = d.get("decals", [])
	if not decals.is_empty():
		var dn := Node3D.new()
		dn.name = "Decals"
		root.add_child(dn)
		for i in decals.size():
			var dc: Array = decals[i]
			var fd := Node3D.new()
			fd.name = "%s_%d" % [(dc[0] as String).to_pascal_case(), i]
			fd.set_script(load("res://rooms/floor_decal.gd"))
			fd.set("art", dc[0])
			fd.set("size", dc[3])
			fd.set("glow", dc.size() > 4 and bool(dc[4]))
			fd.position = dc[1]
			fd.rotation_degrees.y = dc[2]
			dn.add_child(fd)

	# Портал-свет у выхода
	var pl := OmniLight3D.new()
	pl.name = "PortalLight"
	pl.light_color = Color(0.45, 0.8, 1.0)
	pl.light_energy = 2.5
	pl.omni_range = 7.0
	pl.position = Vector3(0, 2.0, -dep / 2 - 4.5)
	root.add_child(pl)

	# Ларёк (зал-ларёк): узел со скриптом, модели собираются при запуске
	if d.has("stall"):
		var stall := Node3D.new()
		stall.name = "ShopStall"
		stall.set_script(load("res://rooms/shop_stall.gd"))
		stall.position = d.stall
		root.add_child(stall)

	# Одевание (блок Б0): коллизия та же, вид — модели, MultiMesh и общий шейдер поверхностей
	var opts: Dictionary = (d.get("dress", {}) as Dictionary).duplicate()
	var styles := {}
	for i in d.blocks.size():
		styles["Block%d" % i] = _block_style(d, i)
	opts["styles"] = styles
	if d.get("floor_tex", "") == "dirt_straw":
		opts["floor"] = "dirt"
	RoomDresser.new(hash(d.file)).dress_room(root, opts)
	_save(root, "res://rooms/%s.tscn" % d.file)

## Графика стен зала (assets/decor/*): знамёна по центру боковых стен (там, где были знамёна-модели), щиты
## в простенках между факелами, знамёна по бокам выхода, щиты на южной стене; плюс ключ "decor" зала —
## [картинка, позиция, поворот Y (град), высота м]. "no_auto": ["north", "south", "side"] — без авто на этих стенах.
## Выбор картинок детерминированный (по имени зала): перезапуск генератора их не меняет.
## Отступ от плоскости стены (лицевая сторона модулей Quaternius — +0.09 м от их начала); ещё WorldArt.cfg().wall_offset — у квада
const WALL_INSET := 0.03

func _build_wall_art(root: Node, d: Dictionary, w: float, dep: float, gap: float) -> void:
	var art := Node3D.new()
	art.name = "Banners"
	root.add_child(art)
	var ri := absi(hash(d.file)) % 97
	var no_auto: Array = d.get("no_auto", [])
	var k := 0
	var bz: Array = [0.0] if dep < 26 else [-dep / 8, dep / 8 + 2]
	if not "side" in no_auto:
		for z in bz:
			_wall_decor(art, "BannerW%d" % int(z), WorldArt.BANNERS[(ri + k) % 8], Vector3(-w / 2 + WALL_INSET, 4.35, z), 90.0, 2.3)
			_wall_decor(art, "BannerE%d" % int(z), WorldArt.BANNERS[(ri + k + 3) % 8], Vector3(w / 2 - WALL_INSET, 4.35, z), -90.0, 2.3)
			k += 1
		# Щиты: у углов и между факелами и знамёнами
		var sz: Array = [-dep * 3 / 8, dep * 3 / 8]
		if dep < 26:
			sz += [-dep / 8, dep / 8]
		else:
			sz.append((float(bz[0]) + float(bz[1])) / 2.0)
		for z in sz:
			_wall_decor(art, "ShieldW%d" % int(z), WorldArt.SHIELDS[(ri + k) % 8], Vector3(-w / 2 + WALL_INSET, 4.55, z), 90.0, 1.05)
			_wall_decor(art, "ShieldE%d" % int(z), WorldArt.SHIELDS[(ri + k + 4) % 8], Vector3(w / 2 - WALL_INSET, 4.55, z), -90.0, 1.05)
			k += 1
	if not "north" in no_auto:
		# Знамёна по бокам выхода (дальше факелов у проёма)
		var nx := gap / 2 + minf(3.6, (w - gap) / 4)
		for sx in [-1.0, 1.0]:
			_wall_decor(art, "BannerN%d" % int(sx), WorldArt.BANNERS[(ri + k) % 8], Vector3(sx * nx, 4.2, -dep / 2 + WALL_INSET), 0.0, 2.1)
			k += 1
	if not "south" in no_auto:
		for sx in [-1.0, 1.0]:
			_wall_decor(art, "ShieldS%d" % int(sx), WorldArt.SHIELDS[(ri + k) % 8], Vector3(sx * w / 4, 4.3, dep / 2 - WALL_INSET), 180.0, 1.15)
			k += 1
	var extra: Array = d.get("decor", [])
	for i in extra.size():
		var e: Array = extra[i]
		_wall_decor(art, "%s_%d" % [(e[0] as String).to_pascal_case(), i], e[0], e[1], e[2], e[3])

func _wall_decor(parent: Node, name: String, art: String, pos: Vector3, yaw: float, height: float) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.set_script(load("res://rooms/wall_decor.gd"))
	n.set("art", art)
	n.set("height", height)
	n.position = pos
	n.rotation_degrees.y = yaw
	parent.add_child(n)
	return n

## Зал-ларёк (блок К, GDD 13): тихий зал без волн, ларёк посередине, ящики по углам.
func shop_room_def() -> Dictionary:
	return {
		"file": "shop_room", "title": "Ларёк Брокка и Эйтри", "w": 22.0, "d": 20.0,
		"blocks": [],
		"pillars": [Vector3(-7.5, 0, -5), Vector3(7.5, 0, -5)],
		"enemies": [],
		"props": _stack_props(Vector3(-9.5, 0, 6.5)) + _stack_props(Vector3(8.5, 0, 6.5)) + [["crate", Vector3(-9.5, 0, -8.5)], ["crate", Vector3(9.5, 0, -8.5)]],
		"stall": Vector3(0, 0, 0.5),
		# За ларьком, на северной стене: гобелен и плакат Одина «Качайся!» (вместо авто-знамён у выхода)
		"no_auto": ["north"],
		"decor": [["tapestry", Vector3(-6.5, 3.0, -10 + WALL_INSET), 0.0, 3.0], ["odin_poster", Vector3(6.5, 2.4, -10 + WALL_INSET), 0.0, 1.9]],
	}

# ---------------- UI ----------------

func build_ui_scenes() -> void:
	print("UI…")
	var specs := [
		["res://ui/hud.tscn", "HUD", "res://ui/hud.gd", "CanvasLayer"],
		["res://ui/rune_pick.tscn", "RunePick", "res://ui/rune_pick.gd", "CanvasLayer"],
		["res://ui/pause_menu.tscn", "PauseMenu", "res://ui/pause_menu.gd", "CanvasLayer"],
		["res://ui/end_screen.tscn", "EndScreen", "res://ui/end_screen.gd", "CanvasLayer"],
		["res://ui/main_menu.tscn", "MainMenu", "res://ui/main_menu.gd", "Control"],
	]
	for s in specs:
		var n: Node = CanvasLayer.new() if s[3] == "CanvasLayer" else Control.new()
		n.name = s[1]
		n.set_script(load(s[2]))
		_save(n, s[0])

# ---------------- Сцена игры ----------------

func build_game() -> void:
	print("Сцена игры…")
	var g := Node3D.new()
	g.name = "Game"
	g.set_script(load("res://scenes/game.gd"))

	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.16, 0.18, 0.32)
	sm.sky_horizon_color = Color(0.85, 0.55, 0.38)
	sm.ground_horizon_color = Color(0.5, 0.36, 0.3)
	sm.ground_bottom_color = Color(0.1, 0.09, 0.1)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.45, 0.42)
	env.fog_density = 0.008
	env.ssao_enabled = true
	ResourceSaver.save(env, "res://scenes/game_environment.tres")
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = load("res://scenes/game_environment.tres")
	g.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color = Color(1.0, 0.86, 0.7)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	g.add_child(sun)

	var level := Node3D.new()
	level.name = "Level"
	g.add_child(level)

	var player := (load("res://player/player.tscn") as PackedScene).instantiate()
	player.name = "Player"
	g.add_child(player)

	for spec in [["HUD", "res://ui/hud.tscn"], ["RunePick", "res://ui/rune_pick.tscn"], ["PauseMenu", "res://ui/pause_menu.tscn"], ["EndScreen", "res://ui/end_screen.tscn"]]:
		var n := (load(spec[1]) as PackedScene).instantiate()
		n.name = spec[0]
		g.add_child(n)
	_save(g, "res://scenes/game.tscn")
