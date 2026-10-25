extends Node
## Генератор сцен и ресурсов прототипа.
## Запуск: godot --headless --path . res://tools/build_scenes.tscn
## Создаёт: игрока, врагов, бочки/ящики, 6 залов + арену босса, тела, руны, сцену игры и UI-сцены.
## ВНИМАНИЕ: перезаписывает файлы. Если правил залы руками в редакторе — не запускай повторно
## (или закомментируй build_rooms() ниже).

const WORLD := 1
const PLAYER_L := 1 << 1
const ENEMY_L := 1 << 2
const PROPS_L := 1 << 3
const PROJ_L := 1 << 4
const TRIGGER_L := 1 << 5
const DEBRIS_L := 1 << 6

var _mats := {}

func _ready() -> void:
	build_resources()
	build_props()
	build_enemies()
	build_player()
	build_rooms()
	build_ui_scenes()
	build_game()
	print("build_scenes: готово")
	get_tree().quit(0)

# ---------------- Общие помощники ----------------

func _own(node: Node, owner: Node) -> void:
	for c in node.get_children():
		c.owner = owner
		if c.scene_file_path == "":
			_own(c, owner)

func _save(root: Node, path: String) -> void:
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

func _box(parent: Node, name: String, center: Vector3, size: Vector3, mat: Material, collide: bool = true) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = name
	b.size = size
	b.position = center
	b.material = mat
	b.use_collision = collide
	b.collision_layer = WORLD
	b.collision_mask = 0
	parent.add_child(b)
	return b

func _cyl(parent: Node, name: String, center: Vector3, radius: float, height: float, mat: Material) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.name = name
	c.radius = radius
	c.height = height
	c.sides = 12
	c.position = center
	c.material = mat
	c.use_collision = true
	c.collision_layer = WORLD
	c.collision_mask = 0
	parent.add_child(c)
	return c

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
		{"id": "berserker", "name": "Берсерк", "desc": "Много здоровья, бьёт тяжело, бегает медленно. Орёт.", "hp": 150.0, "speed": 7.5, "dash": 2, "axe": 1.3, "hammer": 1.0, "glory": 1.0, "hand": Color(0.85, 0.62, 0.5)},
		{"id": "hunter", "name": "Охотник", "desc": "Быстрый и хрупкий. Три заряда рывка.", "hp": 80.0, "speed": 10.0, "dash": 3, "axe": 0.9, "hammer": 1.2, "glory": 1.0, "hand": Color(0.72, 0.55, 0.42)},
		{"id": "thrall", "name": "Трэлл-раб", "desc": "Всё слабое, но Слава ×2. Социальный лифт.", "hp": 60.0, "speed": 8.5, "dash": 2, "axe": 0.7, "hammer": 0.8, "glory": 2.0, "hand": Color(0.8, 0.68, 0.58)},
	]
	for b in bodies:
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
		ResourceSaver.save(r, "res://run/bodies/%s.tres" % b.id)
	var runes := [
		{"id": "axe_damage", "title": "Руна Тюра", "desc": "Урон топора +25%", "glyph": "ᛏ", "color": Color(1.0, 0.55, 0.35)},
		{"id": "dash_charge", "title": "Копыта Слейпнира", "desc": "+1 заряд рывка", "glyph": "ᛖ", "color": Color(0.5, 0.85, 1.0)},
		{"id": "hammer_power", "title": "Гнев Мьёльнира", "desc": "Молот бьёт на 40% сильнее и возвращается на 30% быстрее", "glyph": "ᛗ", "color": Color(0.55, 0.75, 1.0)},
		{"id": "slam_fire", "title": "Огонь Муспельхейма", "desc": "Удар-приземление поджигает землю на 2 секунды", "glyph": "ᚲ", "color": Color(1.0, 0.5, 0.15)},
		{"id": "max_health", "title": "Яблоко Идунн", "desc": "+30 к максимуму здоровья", "glyph": "ᛁ", "color": Color(0.5, 1.0, 0.5)},
		{"id": "dash_damage", "title": "Таран Хеймдалля", "desc": "Рывок сквозь врагов наносит 15 урона и отбрасывает", "glyph": "ᚱ", "color": Color(1.0, 0.85, 0.35)},
		{"id": "heal", "title": "Мёд поэзии", "desc": "Сразу лечит 50 здоровья. Вкусно.", "glyph": "ᚨ", "color": Color(1.0, 0.75, 0.3)},
	]
	for d in runes:
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
	for kind in ["barrel", "crate"]:
		var rb := RigidBody3D.new()
		rb.name = kind.capitalize()
		rb.collision_layer = PROPS_L
		rb.collision_mask = WORLD | PLAYER_L | ENEMY_L | PROPS_L | DEBRIS_L
		rb.add_to_group("props", true)
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		rb.add_child(shape)
		if kind == "barrel":
			rb.mass = 1.2
			var cs := CylinderShape3D.new()
			cs.radius = 0.45
			cs.height = 1.0
			shape.shape = cs
			shape.position.y = 0.5
			var wood := _mat("barrel_wood", Color(0.5, 0.3, 0.16), 0.9)
			var iron := _mat("iron", Color(0.3, 0.3, 0.33), 0.5, false)
			_mesh(rb, "Body", _cylmesh(0.42, 0.42, 1.0), Vector3(0, 0.5, 0), wood)
			_mesh(rb, "Hoop1", _cylmesh(0.45, 0.45, 0.07), Vector3(0, 0.2, 0), iron)
			_mesh(rb, "Hoop2", _cylmesh(0.45, 0.45, 0.07), Vector3(0, 0.8, 0), iron)
		else:
			rb.mass = 1.6
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.9, 0.9, 0.9)
			shape.shape = bs
			shape.position.y = 0.45
			var wood2 := _mat("crate_wood", Color(0.62, 0.45, 0.25), 0.9)
			var dark := _mat("crate_dark", Color(0.35, 0.22, 0.12), 0.9)
			_mesh(rb, "Body", _boxmesh(Vector3(0.9, 0.9, 0.9)), Vector3(0, 0.45, 0), wood2)
			_mesh(rb, "Plank1", _boxmesh(Vector3(0.95, 0.12, 0.95)), Vector3(0, 0.08, 0), dark)
			_mesh(rb, "Plank2", _boxmesh(Vector3(0.95, 0.12, 0.95)), Vector3(0, 0.82, 0), dark)
		_save(rb, "res://props/%s.tscn" % kind)

# ---------------- Враги ----------------

func build_enemies() -> void:
	print("Враги…")
	var defs := {
		"grunt": {"kind": Enemy.Kind.GRUNT, "hp": 60.0, "speed": 4.4, "range": 2.0, "dmg": 12.0, "windup": 0.6, "recover": 0.7, "cd": 0.9, "color": Color(0.36, 0.48, 0.38), "scale": 1.0, "resist": 0.0},
		"thrower": {"kind": Enemy.Kind.THROWER, "hp": 40.0, "speed": 3.8, "range": 12.0, "dmg": 10.0, "windup": 0.55, "recover": 0.4, "cd": 2.2, "color": Color(0.42, 0.33, 0.55), "scale": 1.0, "resist": 0.0},
		"boss": {"kind": Enemy.Kind.BOSS, "hp": 480.0, "speed": 3.6, "range": 3.6, "dmg": 20.0, "windup": 0.8, "recover": 0.9, "cd": 1.1, "color": Color(0.5, 0.26, 0.2), "scale": 2.1, "resist": 0.75},
	}
	var script := load("res://enemies/enemy.gd")
	for key in defs:
		var d: Dictionary = defs[key]
		var e := CharacterBody3D.new()
		e.name = key.capitalize()
		e.set_script(script)
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
	hitbox.max_results = 16
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
	svc.add_child(sv)
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
	vlight.light_energy = 0.8
	vlight.omni_range = 4.0
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
	vcam.add_child(axe_pivot)
	_mesh(axe_pivot, "Hand", _boxmesh(Vector3(0.16, 0.18, 0.2)), Vector3(0, 0, 0), skin, Vector3.ZERO, 2)
	_mesh(axe_pivot, "Handle", _cylmesh(0.032, 0.04, 0.95), Vector3(0, 0.38, 0), wood, Vector3.ZERO, 2)
	_mesh(axe_pivot, "Blade", _boxmesh(Vector3(0.04, 0.34, 0.36)), Vector3(0, 0.72, -0.2), steel, Vector3.ZERO, 2)
	_mesh(axe_pivot, "Edge", _boxmesh(Vector3(0.045, 0.42, 0.06)), Vector3(0, 0.72, -0.39), edge, Vector3.ZERO, 2)
	_mesh(axe_pivot, "Spike", _boxmesh(Vector3(0.05, 0.1, 0.14)), Vector3(0, 0.74, 0.07), steel, Vector3.ZERO, 2)

	var ham_pivot := Node3D.new()
	ham_pivot.name = "HammerPivot"
	vcam.add_child(ham_pivot)
	_mesh(ham_pivot, "Hand", _boxmesh(Vector3(0.16, 0.18, 0.2)), Vector3(0, 0, 0), skin, Vector3.ZERO, 2)
	_mesh(ham_pivot, "Handle", _cylmesh(0.035, 0.04, 0.5), Vector3(0, 0.2, 0), wood, Vector3.ZERO, 2)
	_mesh(ham_pivot, "Head", _boxmesh(Vector3(0.48, 0.28, 0.28)), Vector3(0, 0.52, 0), steel, Vector3.ZERO, 2)
	_mesh(ham_pivot, "Rune", _boxmesh(Vector3(0.14, 0.14, 0.3)), Vector3(0, 0.52, 0), rune_glow, Vector3.ZERO, 2)

	var axe := Node.new()
	axe.name = "Axe"
	axe.set_script(load("res://weapons/axe.gd"))
	p.add_child(axe)
	var mj := Node.new()
	mj.name = "Mjolnir"
	mj.set_script(load("res://weapons/mjolnir_hand.gd"))
	p.add_child(mj)

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
## Блоки: [центр, размер, материал]; врагов: [kind, позиция, волна]; пропсы: [тип, позиция].
func room_defs() -> Array:
	var r: Array = []
	# 1. Зал Бочек — разминка, много физики
	r.append({
		"file": "room_01", "title": "Зал бочек", "w": 24.0, "d": 24.0,
		"blocks": [
			[Vector3(-6, 0.75, -3), Vector3(4, 1.5, 4), "wood"],
			[Vector3(6, 0.75, 2), Vector3(4, 1.5, 4), "wood"],
		],
		"pillars": [Vector3(-6, 0, 6), Vector3(6, 0, -6), Vector3(0, 0, 0)],
		"enemies": [["grunt", Vector3(-4, 0, -6), 0], ["grunt", Vector3(4, 0, -7), 0], ["grunt", Vector3(0, 0, -9), 0],
			["grunt", Vector3(-8, 0, -8), 1], ["grunt", Vector3(8, 0, -8), 1], ["thrower", Vector3(-6, 1.6, -3), 1]],
		"props": _ring_props(Vector3(0, 0, -3), 3.5, 6, "barrel") + [["crate", Vector3(-9, 0, 3)], ["crate", Vector3(-9, 0.95, 3)], ["crate", Vector3(9, 0, 7)], ["barrel", Vector3(8, 0, 8)]],
	})
	# 2. Ярусы — центральная платформа 3 м: нужен двойной или супер-прыжок
	r.append({
		"file": "room_02", "title": "Ярусы Ётунов", "w": 26.0, "d": 24.0,
		"blocks": [
			[Vector3(0, 1.5, -3), Vector3(7, 3, 7), "stone_dark"],
			[Vector3(-10, 1.0, -6), Vector3(4, 2, 8), "stone_dark"],
			[Vector3(10, 1.0, -6), Vector3(4, 2, 8), "stone_dark"],
			[Vector3(-4.5, 0.5, 2.5), Vector3(2, 1, 2), "wood"],
		],
		"pillars": [Vector3(-7, 0, 6), Vector3(7, 0, 6)],
		"enemies": [["grunt", Vector3(-5, 0, -8), 0], ["grunt", Vector3(5, 0, -8), 0], ["thrower", Vector3(0, 3.1, -4), 0],
			["thrower", Vector3(-10, 2.1, -7), 1], ["thrower", Vector3(10, 2.1, -7), 1], ["grunt", Vector3(-3, 0, 4), 1], ["grunt", Vector3(3, 0, 4), 1]],
		"props": [["barrel", Vector3(-1, 3.0, -1)], ["barrel", Vector3(1, 3.0, -5)], ["crate", Vector3(-8, 0, 3)], ["crate", Vector3(8, 0, 3)], ["barrel", Vector3(0, 0, 3)]],
	})
	# 3. Кольцо колонн — вокруг башни 6 м (супер-прыжок на неё)
	r.append({
		"file": "room_03", "title": "Кольцо колонн", "w": 28.0, "d": 28.0,
		"blocks": [
			[Vector3(0, 3.0, -2), Vector3(4, 6, 4), "stone_dark"],
			[Vector3(0, 0.6, 4), Vector3(3, 1.2, 3), "wood"],
		],
		"pillars": _ring_points(Vector3(0, 0, -2), 9.0, 8),
		"enemies": [["grunt", Vector3(-6, 0, -8), 0], ["grunt", Vector3(6, 0, -8), 0], ["grunt", Vector3(-8, 0, 0), 0], ["grunt", Vector3(8, 0, 0), 0],
			["thrower", Vector3(0, 6.1, -2), 1], ["thrower", Vector3(-10, 0, -10), 1], ["grunt", Vector3(10, 0, -10), 1], ["grunt", Vector3(0, 0, -11), 1]],
		"props": _ring_props(Vector3(0, 0, -2), 5.5, 8, "crate"),
	})
	# 4. Коридор Хель — длинный зал, метатели в конце, укрытия
	r.append({
		"file": "room_04", "title": "Коридор Хель", "w": 16.0, "d": 34.0,
		"blocks": [
			[Vector3(-4, 0.6, 6), Vector3(4, 1.2, 1), "stone_dark"],
			[Vector3(4, 0.6, 0), Vector3(4, 1.2, 1), "stone_dark"],
			[Vector3(-4, 0.6, -6), Vector3(4, 1.2, 1), "stone_dark"],
			[Vector3(0, 1.0, -13), Vector3(10, 2, 3), "stone_dark"],
		],
		"pillars": [],
		"enemies": [["thrower", Vector3(-3, 2.1, -13), 0], ["thrower", Vector3(3, 2.1, -13), 0], ["grunt", Vector3(-4, 0, -3), 0], ["grunt", Vector3(4, 0, -9), 0],
			["grunt", Vector3(-5, 0, -10), 1], ["grunt", Vector3(5, 0, -10), 1], ["grunt", Vector3(0, 0, -8), 1], ["grunt", Vector3(0, 0, 2), 1]],
		"props": [["barrel", Vector3(-6, 0, 10)], ["barrel", Vector3(6, 0, 4)], ["crate", Vector3(-6, 0, -2)], ["crate", Vector3(6, 0, -6)], ["barrel", Vector3(0, 0, -4)]],
	})
	# 5. Мост — пониженная середина, два «берега»
	r.append({
		"file": "room_05", "title": "Мост Биврёст (сломан)", "w": 30.0, "d": 22.0,
		"blocks": [
			[Vector3(-10.5, 1.0, 0), Vector3(9, 2, 22), "stone_dark"],
			[Vector3(10.5, 1.0, 0), Vector3(9, 2, 22), "stone_dark"],
			[Vector3(0, 1.75, -2), Vector3(12, 0.5, 2.5), "wood"],
		],
		"pillars": [Vector3(-3, 0, 6), Vector3(3, 0, -7)],
		"enemies": [["grunt", Vector3(-10, 2, -6), 0], ["grunt", Vector3(10, 2, -6), 0], ["grunt", Vector3(0, 0, -6), 0], ["thrower", Vector3(10, 2, 6), 0],
			["grunt", Vector3(-10, 2, 4), 1], ["grunt", Vector3(10, 2, 2), 1], ["thrower", Vector3(-11, 2, -8), 1], ["grunt", Vector3(0, 0, 3), 1]],
		"props": [["barrel", Vector3(-12, 2, 3)], ["barrel", Vector3(12, 2, -3)], ["crate", Vector3(0, 2.0, -2)], ["crate", Vector3(2, 0, 6)], ["barrel", Vector3(-2, 0, -8)]],
		"spawn_y": 2.0,
	})
	# 6. Склад медовухи — штабеля ящиков, крушить всё
	r.append({
		"file": "room_06", "title": "Склад медовухи", "w": 26.0, "d": 26.0,
		"blocks": [
			[Vector3(-7, 1.0, -5), Vector3(5, 2, 3), "wood"],
			[Vector3(7, 1.0, 1), Vector3(5, 2, 3), "wood"],
		],
		"pillars": [Vector3(0, 0, -4)],
		"enemies": [["grunt", Vector3(-4, 0, -9), 0], ["grunt", Vector3(4, 0, -9), 0], ["grunt", Vector3(0, 0, -10), 0],
			["thrower", Vector3(-7, 2.1, -5), 1], ["thrower", Vector3(7, 2.1, 1), 1], ["grunt", Vector3(-6, 0, 4), 1], ["grunt", Vector3(6, 0, -6), 1]],
		"props": _stack_props(Vector3(-3, 0, 3)) + _stack_props(Vector3(3, 0, -8)) + _stack_props(Vector3(-9, 0, 5)) + [["barrel", Vector3(9, 0, 8)], ["barrel", Vector3(10, 0, 7)], ["barrel", Vector3(-10, 0, -10)]],
	})
	return r

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

func build_rooms() -> void:
	print("Залы…")
	for d in room_defs():
		_build_room(d, false)
	_build_room({
		"file": "boss_arena", "title": "Чертог Хримтурса", "w": 32.0, "d": 32.0,
		"blocks": [
			[Vector3(-12.5, 1.5, -12.5), Vector3(5, 3, 5), "stone_dark"],
			[Vector3(12.5, 1.5, -12.5), Vector3(5, 3, 5), "stone_dark"],
			[Vector3(-12.5, 1.5, 8), Vector3(5, 3, 5), "stone_dark"],
			[Vector3(12.5, 1.5, 8), Vector3(5, 3, 5), "stone_dark"],
		],
		"pillars": [Vector3(-6, 0, -6), Vector3(6, 0, -6), Vector3(-6, 0, 4), Vector3(6, 0, 4)],
		"enemies": [["boss", Vector3(0, 0, -8), 0], ["grunt", Vector3(-8, 0, -10), 0], ["grunt", Vector3(8, 0, -10), 0],
			["thrower", Vector3(-12.5, 3.1, -12.5), 1], ["thrower", Vector3(12.5, 3.1, -12.5), 1]],
		"props": _ring_props(Vector3(0, 0, -2), 11.0, 10, "barrel"),
	}, true)

func _build_room(d: Dictionary, boss: bool) -> void:
	var root := Node3D.new()
	root.name = d.file.capitalize().replace(" ", "")
	root.set_script(load("res://rooms/room.gd"))
	root.set("room_title", d.title)
	var w: float = d.w
	var dep: float = d.d
	var h := 6.0
	var floor_mat := _mat("floor", Color(0.42, 0.4, 0.38), 0.95)
	var wall_mat := _mat("wall", Color(0.55, 0.53, 0.5), 0.9)
	var mats := {
		"wood": _mat("plat_wood", Color(0.5, 0.34, 0.2), 0.9),
		"stone_dark": _mat("stone_dark", Color(0.36, 0.35, 0.36), 0.9),
	}
	var pillar_mat := _mat("pillar", Color(0.62, 0.6, 0.56), 0.85)
	var trim_mat := _mat("trim", Color(0.75, 0.55, 0.25), 0.6, false)

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
	# Золотой кант поверху
	_box(geo, "TrimS", Vector3(0, h + 0.1, dep / 2 + 0.5), Vector3(w + 2.2, 0.2, 1.2), trim_mat, false)
	_box(geo, "TrimW", Vector3(-w / 2 - 0.5, h + 0.1, 0), Vector3(1.2, 0.2, dep + 2.2), trim_mat, false)
	_box(geo, "TrimE", Vector3(w / 2 + 0.5, h + 0.1, 0), Vector3(1.2, 0.2, dep + 2.2), trim_mat, false)
	# Коридор за дверью
	_box(geo, "CorridorFloor", Vector3(0, -0.5, -dep / 2 - 3), Vector3(gap + 2, 1, 5), floor_mat)
	_box(geo, "CorridorL", Vector3(-gap / 2 - 0.5, h / 2, -dep / 2 - 3), Vector3(1, h, 5), wall_mat)
	_box(geo, "CorridorR", Vector3(gap / 2 + 0.5, h / 2, -dep / 2 - 3), Vector3(1, h, 5), wall_mat)
	_box(geo, "CorridorEnd", Vector3(0, h / 2, -dep / 2 - 6), Vector3(gap + 2, h, 1), wall_mat)
	var portal := _mat("portal", Color(0.45, 0.8, 1.0), 0.3, false, 2.5)
	_box(geo, "Portal", Vector3(0, 2.2, -dep / 2 - 5.45), Vector3(2.6, 3.6, 0.1), portal, false)

	for i in d.blocks.size():
		var b: Array = d.blocks[i]
		_box(geo, "Block%d" % i, b[0], b[1], mats.get(b[2], mats.stone_dark))
	for i in d.pillars.size():
		var pp: Vector3 = d.pillars[i]
		_cyl(geo, "Pillar%d" % i, pp + Vector3(0, h / 2, 0), 0.8, h, pillar_mat)
		_cyl(geo, "PillarBase%d" % i, pp + Vector3(0, 0.25, 0), 1.05, 0.5, pillar_mat)

	# Дверь
	var door := CSGBox3D.new()
	door.name = "Door"
	door.size = Vector3(gap, h, 0.6)
	door.position = Vector3(0, h / 2, -dep / 2 - 0.5)
	door.material = _mat("door", Color(0.45, 0.16, 0.12), 0.8)
	door.use_collision = true
	door.collision_layer = WORLD
	root.add_child(door)
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
		spawns.add_child(m)

	# Бочки и ящики
	var props := Node3D.new()
	props.name = "Props"
	root.add_child(props)
	var barrel := load("res://props/barrel.tscn") as PackedScene
	var crate := load("res://props/crate.tscn") as PackedScene
	for i in d.props.size():
		var pr: Array = d.props[i]
		var inst := (barrel if pr[0] == "barrel" else crate).instantiate() as Node3D
		inst.name = "%s_%d" % [pr[0], i]
		inst.position = pr[1] + Vector3(0, 0.02, 0)
		inst.rotation.y = randf() * TAU
		props.add_child(inst)

	# Факелы
	var lights := Node3D.new()
	lights.name = "Torches"
	root.add_child(lights)
	var torch_pos := [Vector3(-w / 2 + 0.2, 3.2, -dep / 4), Vector3(w / 2 - 0.2, 3.2, -dep / 4), Vector3(-w / 2 + 0.2, 3.2, dep / 4), Vector3(w / 2 - 0.2, 3.2, dep / 4),
		Vector3(-gap / 2 - 1.2, 3.6, -dep / 2 + 0.1), Vector3(gap / 2 + 1.2, 3.6, -dep / 2 + 0.1)]
	var flame := _mat("flame", Color(1.0, 0.6, 0.2), 0.5, false, 5.0)
	var holder := _mat("holder", Color(0.25, 0.22, 0.2), 0.6, false)
	for i in torch_pos.size():
		var t := Node3D.new()
		t.name = "Torch%d" % i
		t.position = torch_pos[i]
		lights.add_child(t)
		_mesh(t, "Holder", _boxmesh(Vector3(0.15, 0.5, 0.15)), Vector3(0, -0.3, 0), holder)
		_mesh(t, "Flame", _cylmesh(0.0, 0.15, 0.35), Vector3(0, 0.1, 0), flame)
		var l := OmniLight3D.new()
		l.name = "Light"
		l.light_color = Color(1.0, 0.62, 0.3)
		l.light_energy = 2.2
		l.omni_range = 9.0
		l.position = Vector3(0, 0.3, 0)
		t.add_child(l)

	# Портал-свет у выхода
	var pl := OmniLight3D.new()
	pl.name = "PortalLight"
	pl.light_color = Color(0.45, 0.8, 1.0)
	pl.light_energy = 2.5
	pl.omni_range = 7.0
	pl.position = Vector3(0, 2.0, -dep / 2 - 4.5)
	root.add_child(pl)

	_save(root, "res://rooms/%s.tscn" % d.file)

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
