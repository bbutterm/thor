extends RefCounted
class_name EnemyVisual
## Вид врага: анимации по состоянию, вздрагивание, вспышка и свечение (общий оверлей), меши для обводки,
## оружие в руке, процедурная заглушка, труп-«рэгдолл».
## Компонент Enemy (этап 3 рефакторинга): числа и состояние — поля Enemy (их ставят сцены, данные
## и тесты), здесь только логика. Доступ — enemy.visual; нужные снаружи функции есть и на Enemy.

var enemy: Enemy

func _init(owner_node: Enemy) -> void:
	enemy = owner_node

## Анимации персонажа по состоянию. Атака запускается в _begin_windup, здесь — ходьба/стойка.
func _update_animation(delta: float) -> void:
	if enemy._humanoid == null:
		return
	enemy._hit_anim_left = maxf(0.0, enemy._hit_anim_left - delta)
	match enemy.state:
		Enemy.State.CHASE:
			if enemy._hit_anim_left > 0.0:
				return
			var hs := Vector2(enemy.velocity.x, enemy.velocity.z).length()
			if hs > 0.4:
				enemy._humanoid.play(enemy.anim_move, 0.2, clampf(hs / enemy.anim_move_ref_speed, 0.5, 2.5))
			else:
				enemy._humanoid.play(enemy.anim_idle, 0.25)
		Enemy.State.RECOVER:
			# Даём доиграть атаке, к концу восстановления — в стойку
			if enemy._state_time > enemy.recover_time * 0.7:
				enemy._humanoid.play(enemy.anim_idle, 0.25)

## Только локальный вид: не мешаем замахам, физике, навигации и защитам.
func _begin_flinch(knockback: Vector3) -> void:
	if enemy._visual == null or not is_instance_valid(enemy._visual) or enemy.flinch_time <= 0.0:
		return
	var dir := Vector3(knockback.x, 0.0, knockback.z)
	if dir.length_squared() < 0.0001 and is_instance_valid(enemy.player):
		dir = enemy.global_position - enemy.player.global_position
		dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = -enemy.global_transform.basis.z
		dir.y = 0.0
	enemy._visual.position -= enemy._flinch_applied
	enemy._flinch_direction = enemy.global_transform.basis.inverse() * dir.normalized()
	enemy._flinch_left = enemy.flinch_time
	enemy._flinch_applied = enemy._flinch_direction * maxf(0.0, enemy.flinch_distance) * enemy.model_scale
	enemy._visual.position += enemy._flinch_applied

func _spawn_debris() -> void:
	if enemy._visual == null:
		return
	enemy._visual.position -= enemy._flinch_applied
	enemy._flinch_applied = Vector3.ZERO
	# Не копим трупы: сверх лимита самый старый исчезает сразу
	var old := enemy.get_tree().get_nodes_in_group("debris").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	for k in maxi(0, old.size() - enemy.max_debris + 1):
		old[k].queue_free()
	var room := enemy.get_parent()
	# П3: корм — мясо, разлетается на куски; торс остаётся «телом» (лимит трупов, учёт волны)
	if enemy.kind == Enemy.Kind.FODDER and enemy.gib_on_death and not enemy.has_meta("elite"):
		_set_overlay(0.0, 0.0)
		var knock_gib := enemy._last_knock if enemy._last_knock.length() > 0.5 else -enemy.global_transform.basis.z * 4.0
		var gib := FodderGibs.spawn(enemy, knock_gib)
		if not gib.is_empty():
			enemy._visual.visible = false
			var body := gib.body as RigidBody3D
			var mesh := gib.visual as Node3D
			if room and room.has_method("keep_fodder_corpse") and bool(room.call("keep_fodder_corpse", enemy, body, mesh)):
				return
			Enemy.fade_debris(body, mesh, enemy.debris_lifetime)
			return
	var rb := RigidBody3D.new()
	rb.add_to_group("debris")
	rb.collision_layer = 1 << 6
	rb.collision_mask = 1 | (1 << 3) | (1 << 6)
	rb.mass = 2.0 * enemy.model_scale
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 1.6, 0.7) * enemy.model_scale
	shape.shape = box
	shape.position = Vector3(0, 0.8 * enemy.model_scale, 0)
	rb.add_child(shape)
	enemy.get_parent().add_child(rb)
	rb.global_transform = enemy.global_transform
	var vis := enemy._visual
	vis.get_parent().remove_child(vis)
	rb.add_child(vis)
	vis.scale = Vector3.ONE * enemy.model_scale
	_set_overlay(0.0, 0.0)
	var knock := enemy._last_knock if enemy._last_knock.length() > 0.5 else -enemy.global_transform.basis.z * 4.0
	if enemy._humanoid:
		# Персонаж с анимацией: тело летит от удара, но не кувыркается — играет анимация смерти
		rb.lock_rotation = true
		box.size = Vector3(0.6, 0.4, 0.6) * enemy.model_scale
		shape.position = Vector3(0, 0.2 * enemy.model_scale, 0)
		enemy._humanoid.play(enemy.anim_death, 0.05, 1.4)
		rb.apply_central_impulse((knock * 0.9 + Vector3.UP * 3.0) * rb.mass)
	else:
		rb.apply_central_impulse((knock * 1.1 + Vector3.UP * 4.0) * rb.mass)
		rb.apply_torque_impulse(Vector3(randf_range(-3, 3), randf_range(-2, 2), randf_range(-3, 3)) * rb.mass)
	# Корм в активной волне остаётся до её полного завершения; вне волн — старый таймер.
	if enemy.kind == Enemy.Kind.FODDER and room and room.has_method("keep_fodder_corpse") \
			and bool(room.call("keep_fodder_corpse", enemy, rb, vis)):
		return
	Enemy.fade_debris(rb, vis, enemy.debris_lifetime)

func _update_visual_feedback(delta: float) -> void:
	enemy._hurt_flash = maxf(0.0, enemy._hurt_flash - delta * 8.0)
	if enemy._visual and is_instance_valid(enemy._visual):
		enemy._visual.position -= enemy._flinch_applied
		enemy._flinch_left = maxf(0.0, enemy._flinch_left - delta)
		enemy._flinch_applied = enemy._flinch_direction * maxf(0.0, enemy.flinch_distance) * enemy.model_scale * (enemy._flinch_left / maxf(enemy.flinch_time, 0.001))
	# Процедурная «анимация» (только для заглушки): покачивание, отклонение на замахе, рывок на ударе
	if enemy._visual and enemy._humanoid == null and enemy.state != Enemy.State.STUNNED:
		var hs := Vector2(enemy.velocity.x, enemy.velocity.z).length()
		var bob := 0.0
		if hs > 0.5 and enemy.is_on_floor():
			enemy._walk_t += delta * hs * 2.4
			bob = absf(sin(enemy._walk_t)) * 0.09 * enemy.model_scale
		enemy._visual.position.y = lerpf(enemy._visual.position.y, bob, clampf(delta * 14.0, 0.0, 1.0))
		var lean := clampf(hs * 0.035, 0.0, 0.2)
		if enemy.state == Enemy.State.WINDUP:
			lean = -0.28
		elif enemy.state == Enemy.State.RECOVER and enemy._state_time < 0.18:
			lean = 0.38
		enemy._visual.rotation.x = lerp_angle(enemy._visual.rotation.x, lean, clampf(delta * 14.0, 0.0, 1.0))
		enemy._visual.rotation.z = sin(enemy._walk_t) * 0.06 if hs > 0.5 else lerpf(enemy._visual.rotation.z, 0.0, clampf(delta * 10.0, 0.0, 1.0))
	var glow := 0.0
	if enemy._windup_glow > 0.0:
		var pulse := 0.5 + 0.5 * sin(enemy._state_time * 30.0)
		glow = enemy._windup_glow * (1.0 + pulse) * (0.35 if enemy._humanoid else 0.8)
	if enemy._visual and is_instance_valid(enemy._visual):
		enemy._visual.position += enemy._flinch_applied
	_set_overlay(enemy._hurt_flash, glow)

## Forward+ использует общий оверлей с per-instance параметрами; в GL у каждого врага
## свой материал с обычными uniform, чтобы части модели не занимали ограниченный буфер.
## Оверлей включается только пока есть что показывать (лишний проход рисования не нужен).
## Элита светится постоянно (цвет модификатора, мягкая пульсация) — тот же материал, параметр "elite".
func _set_overlay(flash: float, glow: float) -> void:
	var el := 0.0
	var el_color := Color(enemy.elite_glow.r, enemy.elite_glow.g, enemy.elite_glow.b)
	if enemy.elite_glow.a > 0.0 and not enemy.is_dead:
		el = enemy.elite_glow.a * (0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.004))
	# Состояние стихии (горит, заморожен, под током…) важнее свечения элиты — тот же параметр, без нового материала
	if enemy.status_glow.a > 0.001 and not enemy.is_dead:
		el = enemy.status_glow.a
		el_color = Color(enemy.status_glow.r, enemy.status_glow.g, enemy.status_glow.b)
	var on := flash > 0.001 or glow > 0.001 or el > 0.001
	if not on and not enemy._overlay_on:
		return
	var use_gl_material := enemy._flash_material_gl != null
	if on and use_gl_material:
		if not enemy._overlay_on:
			enemy._flash_material_gl.next_pass = Outline.flash_next_pass()
		enemy._flash_material_gl.set_shader_parameter("flash", flash)
		enemy._flash_material_gl.set_shader_parameter("glow", glow)
		enemy._flash_material_gl.set_shader_parameter("elite", Color(el_color.r, el_color.g, el_color.b, el))
	for g in enemy._flash_meshes:
		if not is_instance_valid(g):
			continue
		if on != enemy._overlay_on:
			# Погасла — обратно комиксовая обводка (scripts/outline.gd; при вспышке она — next_pass FLASH_MATERIAL)
			g.material_overlay = (enemy._flash_material_gl if use_gl_material else Enemy.FLASH_MATERIAL) if on else Outline.overlay()
		if on and not use_gl_material:
			g.set_instance_shader_parameter("flash", flash)
			g.set_instance_shader_parameter("glow", glow)
			g.set_instance_shader_parameter("elite", Color(el_color.r, el_color.g, el_color.b, el))
	enemy._overlay_on = on

func _collect_meshes(root: Node) -> void:
	enemy._flash_meshes.clear()
	for mi in root.find_children("*", "GeometryInstance3D", true, false):
		# Глаза и брови (Eyes, Eyebrows*) вспышку не показывают — светятся сами и крошечные.
		if mi is MeshInstance3D and not mi.name.begins_with("Eye"):
			enemy._flash_meshes.append(mi as GeometryInstance3D)
	# Комиксовая обводка (GDD 20) — тот же слот оверлея, те же меши
	Outline.add_meshes(enemy._flash_meshes)

## Оружие в правую руку (процедурное, в текстурах Quaternius).
func _attach_weapon(kind_name: String) -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "hand_r"
	enemy._humanoid.skeleton.add_child(att)
	var w := WeaponMeshes.build(kind_name)
	# Хват: рукоять поперёк кулака, оружие смотрит вверх-вперёд
	w.rotation_degrees = Vector3(0, 0, -90)
	w.position = Vector3(0, 0.08, 0)
	att.add_child(w)
	if enemy.shield_chance > 0.0 and randf() < enemy.shield_chance:
		var att2 := BoneAttachment3D.new()
		att2.bone_name = "hand_l"
		enemy._humanoid.skeleton.add_child(att2)
		var sh := WeaponMeshes.build("q_shield")
		sh.rotation_degrees = Vector3(0, 0, 90)
		att2.add_child(sh)

func _build_procedural_model() -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	enemy.add_child(root)
	var skin := FX.make_material(enemy.body_color, 0.9)
	var dark := FX.make_material(enemy.body_color.darkened(0.45), 0.9)
	var metal := FX.make_material(Color(0.55, 0.55, 0.6), 0.4)
	metal.metallic = 0.6
	var eye := FX.make_material(Color(1.0, 0.85, 0.2), 0.5, 4.0)
	eye.set_meta("glow", true)
	match enemy.kind:
		Enemy.Kind.THROWER:
			# Тощий шаман-драугр с капюшоном
			_add_mesh(root, _capsule(0.32, 1.3), Vector3(0, 0.75, 0), dark)
			_add_mesh(root, _sphere(0.3), Vector3(0, 1.55, 0), skin)
			_add_mesh(root, _cone(0.36, 0.55), Vector3(0, 1.85, -0.05), dark)
			_add_mesh(root, _sphere(0.06), Vector3(-0.1, 1.58, 0.25), eye)
			_add_mesh(root, _sphere(0.06), Vector3(0.1, 1.58, 0.25), eye)
			_add_mesh(root, _box(Vector3(0.08, 1.2, 0.08)), Vector3(0.42, 0.9, 0.15), FX.make_material(Color(0.35, 0.22, 0.12)))
			_add_mesh(root, _sphere(0.13), Vector3(0.42, 1.55, 0.15), FX.make_material(Color(0.6, 0.2, 1.0), 0.4, 3.0))
		_:
			# Коренастый драугр в рогатом шлеме
			_add_mesh(root, _capsule(0.42, 1.25), Vector3(0, 0.72, 0), skin)
			_add_mesh(root, _box(Vector3(0.9, 0.35, 0.6)), Vector3(0, 1.2, 0), dark)
			_add_mesh(root, _sphere(0.32), Vector3(0, 1.6, 0.03), skin)
			_add_mesh(root, _sphere(0.34), Vector3(0, 1.7, 0), metal)
			_add_mesh(root, _cone(0.08, 0.45), Vector3(-0.32, 1.9, 0), FX.make_material(Color(0.92, 0.88, 0.78)), Vector3(0, 0, 40))
			_add_mesh(root, _cone(0.08, 0.45), Vector3(0.32, 1.9, 0), FX.make_material(Color(0.92, 0.88, 0.78)), Vector3(0, 0, -40))
			_add_mesh(root, _sphere(0.065), Vector3(-0.12, 1.6, 0.28), eye)
			_add_mesh(root, _sphere(0.065), Vector3(0.12, 1.6, 0.28), eye)
			# Дубина
			_add_mesh(root, _box(Vector3(0.12, 0.9, 0.12)), Vector3(0.55, 0.9, 0.25), FX.make_material(Color(0.35, 0.22, 0.12)), Vector3(35, 0, 0))
			_add_mesh(root, _box(Vector3(0.26, 0.32, 0.26)), Vector3(0.55, 1.25, 0.5), metal, Vector3(35, 0, 0))
	return root

func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: StandardMaterial3D, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat.duplicate() if not mat.has_meta("glow") else mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m

func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	return m

func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m

func _cone(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 10
	return m
