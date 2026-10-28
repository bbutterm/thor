extends Node
## Модель корма: общий один меш/материал, рабочие анимации, вспышка и труп.

var _passes := 0
var _fails: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		_passes += 1
		print("  [OK] ", label)
	else:
		_fails.append(label)
		print("  [FAIL] ", label)

func _run() -> void:
	print("=== FODDER MODEL TEST ===")
	Run.start_run("berserker")
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var scene := load("res://enemies/fodder.tscn") as PackedScene
	var a := scene.instantiate() as Enemy
	var b := scene.instantiate() as Enemy
	var original := scene.instantiate() as Enemy
	original.kind = Enemy.Kind.GRUNT # прежняя модель корма: базовое тело и комплект одежды
	world.add_child(a)
	world.add_child(b)
	world.add_child(original)
	original.kind = Enemy.Kind.FODDER
	a.set_physics_process(false)
	b.set_physics_process(false)
	original.set_physics_process(false)
	var h := a._humanoid
	check(h != null and h.outfit == "" and h.parts.is_empty() and h.hair == "", "готовая одетая модель без сборки частей")
	check(a._flash_meshes.size() == 1 and b._flash_meshes.size() == 1, "по одному мешу на врага")
	if h == null or a._flash_meshes.size() != 1 or b._flash_meshes.size() != 1:
		_finish(world)
		return
	var mesh_a := a._flash_meshes[0] as MeshInstance3D
	var mesh_b := b._flash_meshes[0] as MeshInstance3D
	check(mesh_a.mesh.get_surface_count() == 1 and mesh_b.mesh.get_surface_count() == 1, "одна поверхность и материал")
	check(mesh_a.mesh == mesh_b.mesh and mesh_a.get_active_material(0) == mesh_b.get_active_material(0),
		"оба врага используют один меш и материал")
	check(mesh_a.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "тени у массовки отключены")
	check(h.skeleton != null and h.skeleton.get_bone_count() == 65 and mesh_a.skin != null, "скелет и скин сохранены")
	var animation_root := h.anim.get_node(h.anim.root_node)
	check(animation_root.get_node_or_null("Armature/Skeleton3D") == h.skeleton, "пути существующих анимаций совпадают со скелетом")
	var anims_ok := true
	for anim_name in [a.anim_idle, a.anim_move, a.anim_attack, a.anim_death]:
		anims_ok = anims_ok and h.resolve(anim_name) != ""
	check(anims_ok, "анимации ожидания, движения, удара и смерти доступны")
	var original_h := original._humanoid
	var same_lengths := original_h != null
	if original_h:
		for anim_name in [a.anim_idle, a.anim_move, a.anim_attack, a.anim_death]:
			var new_name := h.resolve(anim_name)
			var old_name := original_h.resolve(anim_name)
			if new_name == "" or old_name == "":
				same_lengths = false
				continue
			same_lengths = same_lengths and is_equal_approx(h.anim.get_animation(new_name).length, original_h.anim.get_animation(old_name).length)
	check(same_lengths, "продолжительность штатных анимаций сохранилась")
	var ap := h.anim
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ap.play(h.resolve(a.anim_move), 0.0, 1.0)
	ap.seek(0.0, true)
	var poses: Array[Transform3D] = []
	for i in h.skeleton.get_bone_count():
		poses.append(h.skeleton.get_bone_pose(i))
	ap.advance(0.2)
	var changed := false
	for i in h.skeleton.get_bone_count():
		changed = changed or not poses[i].is_equal_approx(h.skeleton.get_bone_pose(i))
	check(changed, "анимация действительно меняет позу костей")
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	a._set_overlay(1.0, 0.0)
	check(Outline.is_flash(mesh_a.material_overlay), "вспышка попадания работает на новом меше")
	var visual := a._visual
	a.take_hit(9999.0, Vector3.ZERO, "test")
	check(a.is_dead and visual.get_parent() is RigidBody3D, "смерть передаёт одетое тело физическому трупу")
	check(mesh_a.material_overlay == Outline.overlay(), "после смерти вспышка очищается, обводка сохраняется")
	_finish(world)

func _finish(world: Node) -> void:
	print("=== ИТОГ FODDER MODEL: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	world.queue_free()
	get_tree().quit(0 if _fails.is_empty() else 1)
