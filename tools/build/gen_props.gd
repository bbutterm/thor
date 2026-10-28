extends RefCounted
class_name GenProps
## Генератор: бочки, ящики, взрывные бочки (props/*.tscn; скрипт props/destructible.gd).
## Компонент SceneBuilder (этап 4 рефакторинга): числа и состояние — поля SceneBuilder (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — генератор.props; нужные снаружи функции есть и на SceneBuilder.

var gen: SceneBuilder

func _init(owner_node: SceneBuilder) -> void:
	gen = owner_node

func build_props() -> void:
	print("Бочки и ящики…")
	# Разрушаемые (props/destructible.gd): прочность и содержимое — поля Destructible на сцене
	var destructible := load("res://props/destructible.gd")
	for kind in ["barrel", "crate", "barrel_explosive"]:
		var rb := RigidBody3D.new()
		rb.name = kind.capitalize().replace(" ", "")
		rb.collision_layer = SceneBuilder.PROPS_L
		rb.collision_mask = SceneBuilder.WORLD | SceneBuilder.PLAYER_L | SceneBuilder.ENEMY_L | SceneBuilder.PROPS_L | SceneBuilder.DEBRIS_L
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
			gen._model(rb, "Model", SceneBuilder.QP + "Barrel.gltf", Vector3.ZERO, Vector3.ZERO, Vector3(1.15, 1.12, 1.15))
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
			gen._model(rb, "Model", SceneBuilder.QV + "Prop_Crate.gltf", Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 0.83)
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
		gen._save(rb, "res://props/%s.tscn" % kind)
