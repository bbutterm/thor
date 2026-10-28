extends RefCounted
class_name GenPlayer
## Генератор: сцена игрока player/player.tscn (камера, руки, оружие, вьюмодель).
## Компонент SceneBuilder (этап 4 рефакторинга): числа и состояние — поля SceneBuilder (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — генератор.player; нужные снаружи функции есть и на SceneBuilder.

var gen: SceneBuilder

func _init(owner_node: SceneBuilder) -> void:
	gen = owner_node

func build_player() -> void:
	print("Игрок…")
	var p := CharacterBody3D.new()
	p.name = "Player"
	p.set_script(load("res://player/player.gd"))
	p.collision_layer = SceneBuilder.PLAYER_L
	p.collision_mask = SceneBuilder.WORLD | SceneBuilder.ENEMY_L | SceneBuilder.PROPS_L
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
	hitbox.collision_mask = SceneBuilder.ENEMY_L | SceneBuilder.PROPS_L | SceneBuilder.PROJ_L | SceneBuilder.DEBRIS_L
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

	var skin := gen._mat("skin_default", Color(0.85, 0.65, 0.5), 0.9, false)
	var wood := gen._mat("handle_wood", Color(0.36, 0.22, 0.12), 0.9, false)
	var steel := gen._mat("steel", Color(0.7, 0.72, 0.76), 0.3, false)
	steel.metallic = 0.85
	var edge := gen._mat("edge", Color(0.92, 0.93, 0.95), 0.15, false)
	edge.metallic = 1.0
	var rune_glow := gen._mat("rune_glow", Color(0.45, 0.8, 1.0), 0.4, false, 3.0)

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
	gen._save(p, "res://player/player.tscn")
