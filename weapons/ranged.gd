extends Node
class_name RangedWeapon
## Ренж в правой руке: выстрелы лучом (пули, дробь, болт), патроны, перезарядка, разброс, отдача,
## вспышка у дула, трассеры, гильзы. Урон "ranged": не отбрасывает и не сбивает замах.
## Создаётся WeaponHolder; числа оружия — в WeaponDef, общие — в WeaponHolder (@export).

signal fired(item: WeaponItem)
signal ammo_changed(mag: int, reserve: int)
signal reload_changed(active: bool, progress: float)
## Магазин и запас пусты — WeaponHolder переключит на мили
signal ran_dry

const HIT_MASK := 1 | (1 << 2) | (1 << 3)
## Помощь в прицеливании (настройки «Доступность»): полуугол конуса доводки, градусы
@export var aim_assist_cone_deg: float = 6.0

var holder: WeaponHolder
var player: Player
var item: WeaponItem
var active: bool = false
var reloading: bool = false

var _cooldown: float = 0.0
var _spread_extra: float = 0.0
var _reload_left: float = 0.0
var _fire_slow_left: float = 0.0
var _flash_left: float = 0.0
var _flash: MeshInstance3D
var _light: OmniLight3D

func setup(h: WeaponHolder) -> void:
	holder = h
	player = h.player
	_light = OmniLight3D.new()
	_light.name = "MuzzleLight"
	_light.light_color = Color(1.0, 0.75, 0.4)
	_light.light_energy = 2.2
	_light.omni_range = 7.0
	_light.shadow_enabled = false
	_light.visible = false
	# Камера Player ещё не готова (@onready родителя), берём узел напрямую
	(player.get_node("Head/Camera") as Node).add_child(_light)
	_light.position = Vector3(0.25, -0.15, -0.8)

## Новое оружие в руке (или null).
func equip(it: WeaponItem) -> void:
	cancel_reload()
	item = it
	_spread_extra = 0.0
	_cooldown = 0.0
	_flash = null
	_emit_ammo()

func set_active(on: bool) -> void:
	active = on
	if not on:
		cancel_reload()
		_fire_slow_left = 0.0

## Множитель бега: в руке — move_speed_mult, во время стрельбы — fire_move_mult.
func move_mult() -> float:
	if item == null:
		return 1.0
	return item.def.fire_move_mult if _fire_slow_left > 0.0 else item.def.move_speed_mult

func is_firing() -> bool:
	return _fire_slow_left > 0.0

func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_fire_slow_left = maxf(0.0, _fire_slow_left - delta)
	if item:
		_spread_extra = maxf(0.0, _spread_extra - item.def.spread_recover * delta)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			if _flash:
				_flash.visible = false
			_light.visible = false
	if reloading:
		_reload_left -= delta
		reload_changed.emit(true, 1.0 - _reload_left / maxf(0.01, item.def.reload_time))
		if _reload_left <= 0.0:
			_finish_reload()
	if not active or item == null or player.is_dead or not player.input_enabled:
		return
	if Input.is_action_just_pressed("reload"):
		start_reload()
	var want := Input.is_action_pressed("attack") if item.def.automatic else Input.is_action_just_pressed("attack")
	if want:
		try_fire()

## Выстрел (из ввода или теста). Пустой магазин — перезарядка, совсем пусто — сигнал ran_dry.
func try_fire() -> bool:
	if item == null or not active or reloading or _cooldown > 0.0:
		return false
	if item.mag <= 0:
		if item.reserve > 0:
			start_reload()
		else:
			Audio.play("sounds/sfx/gun_empty.wav")
			_cooldown = 0.3
			ran_dry.emit()
		return false
	_fire()
	return true

func _fire() -> void:
	Perf.mark("gun_fire")
	var d := item.def
	item.mag -= 1
	_cooldown = d.fire_interval
	_fire_slow_left = holder.fire_slow_time
	var origin := player.get_aim_origin()
	var basis := player.camera.global_transform.basis
	var muzzle := muzzle_world_position()
	var dmg := d.damage * item.damage_mult()
	# Помощь в прицеливании (настройки, GDD 22): центр разброса — на ближайшего врага в узком конусе
	var fwd := -basis.z
	if GameSettings.aim_assist():
		fwd = assisted_aim(player, origin, fwd, d.max_range, aim_assist_cone_deg)
	if d.special == "rocket":
		# Ракетница: снаряд вместо луча, взрыв по площади, рокет-джамп (weapons/rocket.gd)
		var rk := Rocket.new()
		player.get_parent().add_child(rk)
		rk.max_range = d.max_range
		rk.radius = holder.rocket_radius
		rk.self_push_up = holder.rocket_jump_up
		rk.self_push_side = holder.rocket_jump_side
		rk.launch(player, muzzle, fwd * d.tracer_speed, dmg)
	for p in (0 if d.special == "rocket" else maxi(1, d.pellets)):
		var spread := deg_to_rad(d.spread_deg + _spread_extra)
		var a := randf() * TAU
		var r := sqrt(randf()) * tan(spread)
		var dir := (fwd + basis.x * cos(a) * r + basis.y * sin(a) * r).normalized()
		var end := _ray(origin, dir, dmg, d.pierce)
		_spawn_tracer(muzzle, end, d)
	_spread_extra = minf(d.spread_max_deg, _spread_extra + d.spread_per_shot_deg)
	# Отдача: камера подпрыгивает, прицел (у автомата) уходит вверх
	player.camera_fx.kick_recoil(d.recoil_kick_deg, randf_range(-0.35, 0.35) * d.recoil_kick_deg)
	if d.recoil_climb_deg > 0.0:
		player.rotation_target.x = clampf(player.rotation_target.x + deg_to_rad(d.recoil_climb_deg), deg_to_rad(-89), deg_to_rad(89))
	player.camera_fx.add_trauma(d.shake)
	_show_flash(d)
	_animate_kick(d)
	if d.shell_casing:
		_spawn_casing()
	Audio.play(d.sound_fire)
	fired.emit(item)
	_emit_ammo()
	if item.mag <= 0 and item.reserve > 0 and holder.auto_reload:
		get_tree().create_timer(0.12, false).timeout.connect(func() -> void:
			if active and item and item.mag <= 0:
				start_reload())

## Направление на ближайшего видимого врага внутри конуса cone_deg вокруг fwd (иначе fwd).
static func assisted_aim(p: Node3D, origin: Vector3, fwd: Vector3, max_range: float, cone_deg: float) -> Vector3:
	var best := fwd
	var best_cos := cos(deg_to_rad(cone_deg))
	var space := p.get_world_3d().direct_space_state
	for n in p.get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.is_dead:
			continue
		var target := e.global_position + Vector3.UP * 1.1
		var to := target - origin
		var dist := to.length()
		if dist < 0.5 or dist > max_range:
			continue
		var c := fwd.dot(to / dist)
		if c <= best_cos:
			continue
		# Сквозь стены не доводим
		var q := PhysicsRayQueryParameters3D.create(origin, target, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		best_cos = c
		best = to / dist
	return best

## Луч с пробитием: по врагам урон "ranged", по бочкам — толчок, по стенам — искры. Возвращает конечную точку.
func _ray(origin: Vector3, dir: Vector3, dmg: float, pierce: int) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var exclude: Array[RID] = [player.get_rid()]
	var to := origin + dir * item.def.max_range
	var left := pierce
	for i in 8:
		var q := PhysicsRayQueryParameters3D.create(origin, to, HIT_MASK, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return to
		var c: Object = hit.collider
		var pos: Vector3 = hit.position
		if c is Destructible:
			# Бочка/ящик: урон по пропсу (DestructTuning.source_mult["ranged"]) и толчок пулей; пробивает дальше
			(c as Destructible).take_hit(dmg, dir * holder.prop_bullet_impulse, "ranged")
			FX.sparks(player.get_parent(), pos, Color(0.7, 0.5, 0.3), 4, 3.0, 12.0, 0.05, 0.25)
			if left > 0:
				left -= 1
				exclude.append((c as CollisionObject3D).get_rid())
				continue
			return pos
		if c and c.has_method("take_hit"):
			player.deal_damage(c, dmg, Vector3.ZERO, "ranged")
			# Гвоздомёт: прибивает корм к полу
			if item.def.special == "pin_fodder" and c is Enemy and (c as Enemy).kind == Enemy.Kind.FODDER:
				(c as Enemy).apply_stun(holder.nail_pin_time, true)
			FX.sparks(player.get_parent(), pos, Color(1.0, 0.55, 0.35), 5, 3.0, 12.0, 0.05, 0.25)
			if left > 0 and c is CollisionObject3D:
				left -= 1
				exclude.append((c as CollisionObject3D).get_rid())
				continue
			return pos
		if c is RigidBody3D:
			var rb := c as RigidBody3D
			rb.apply_impulse(dir * holder.prop_bullet_impulse * rb.mass, pos - rb.global_position)
		FX.sparks(player.get_parent(), pos + (hit.normal as Vector3) * 0.05, Color(1.0, 0.85, 0.5), 4, 3.5, 14.0, 0.04, 0.22)
		return pos
	return to

func start_reload() -> void:
	if item == null or reloading or item.mag >= item.def.mag_size or item.reserve <= 0:
		return
	Perf.mark("gun_reload")
	reloading = true
	_reload_left = item.def.reload_time
	Audio.play(item.def.sound_reload)
	reload_changed.emit(true, 0.0)
	_animate_reload(item.def.reload_time)

## Мгновенная перезарядка из запаса (Солдат: рывок перезаряжает ренж). true — патроны добавились.
func instant_reload() -> bool:
	if item == null or item.mag >= item.def.mag_size or item.reserve <= 0:
		return false
	cancel_reload()
	var take := mini(item.def.mag_size - item.mag, item.reserve)
	item.mag += take
	item.reserve -= take
	Audio.play(item.def.sound_reload)
	_emit_ammo()
	return true

func cancel_reload() -> void:
	if not reloading:
		return
	reloading = false
	var h := _hand()
	if h and h.state == &"reload" and active:
		h.wrist_target = Vector3.ZERO
		h.to_rest(0.15)
	reload_changed.emit(false, 0.0)

func _finish_reload() -> void:
	reloading = false
	var take := mini(item.def.mag_size - item.mag, item.reserve)
	item.mag += take
	item.reserve -= take
	reload_changed.emit(false, 1.0)
	_emit_ammo()

func _emit_ammo() -> void:
	if item:
		ammo_changed.emit(item.mag, item.reserve)
	else:
		ammo_changed.emit(0, 0)

# --- Вид ---

## Точка дула в мире: проецируем дуло вьюмодели (свой мир и камера) на экран и обратно в основной мир,
## чтобы трассер вылетал ровно из видимого ствола.
func muzzle_world_position() -> Vector3:
	var cam := player.camera
	var w := holder.arm.weapon if holder.arm else null
	var vcam := holder.view_camera
	if w == null or vcam == null or item == null:
		return cam.global_position + cam.global_transform.basis * Vector3(0.2, -0.18, -0.7)
	var mp := w.global_transform * item.def.muzzle_offset
	var depth := (vcam.global_transform.affine_inverse() * mp).z
	var screen := vcam.unproject_position(mp)
	# SubViewport рук растянут на весь экран — переводим координаты в экран основной камеры
	var vp_size := Vector2(vcam.get_viewport().get_visible_rect().size)
	var main_size := Vector2(cam.get_viewport().get_visible_rect().size)
	if vp_size.x > 0.0:
		screen *= main_size / vp_size
	return cam.project_position(screen, maxf(0.3, -depth))

func _show_flash(d: WeaponDef) -> void:
	var w := holder.arm.weapon if holder.arm else null
	if w and (_flash == null or not is_instance_valid(_flash) or _flash.get_parent() != w):
		_flash = w.get_node_or_null("MuzzleFlash") as MeshInstance3D
		if _flash == null:
			_flash = make_flash_mesh(2)
			w.add_child(_flash)
	if _flash:
		_flash.position = d.muzzle_offset
		_flash.rotation = Vector3(0, 0, randf() * TAU)
		# Вспышка — дочерний узел модели: делим на масштаб модели, чтобы размер не зависел от view_scale
		var s := d.muzzle_flash_size * randf_range(0.8, 1.2) / maxf(0.01, w.scale.x)
		_flash.scale = Vector3(0.07, 0.07, 0.16) * s
		_flash.visible = d.tracer != "bolt"
	_light.visible = d.tracer != "bolt"
	_flash_left = 0.045

## Вспышка дула: общий меш и общий материал эффектов (без новых материалов на выстрел).
static func make_flash_mesh(layer: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "MuzzleFlash"
	mi.mesh = FX.shared_mesh("sphere")
	FX.fx_apply(mi, "alpha_nocull", Color(1.0, 0.62, 0.2, 0.85), 1.4)
	mi.layers = layer
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi

func _spawn_tracer(from: Vector3, to: Vector3, d: WeaponDef) -> void:
	var parent := player.get_parent()
	var dist := from.distance_to(to)
	if dist < 0.5:
		return
	var node: Node3D
	if d.tracer == "bolt":
		node = WeaponMeshes.bolt()
		node.scale = Vector3.ONE * 1.4
	else:
		node = make_tracer_mesh(d.tracer == "pellet")
	parent.add_child(node)
	node.add_to_group("tracers")
	node.global_position = from
	node.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var t := dist / maxf(1.0, d.tracer_speed)
	var tw := node.create_tween()
	tw.tween_property(node, "global_position", to, t)
	if d.tracer == "bolt":
		# Болт торчит из стены/врага ещё немного
		tw.tween_interval(holder.bolt_stick_time)
	tw.tween_callback(node.queue_free)
	# Не копим болты в стенах
	if d.tracer == "bolt":
		var bolts := get_tree().get_nodes_in_group("tracers")
		if bolts.size() > holder.max_tracers:
			bolts[0].queue_free()

static func make_tracer_mesh(pellet: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = FX.shared_mesh("box")
	FX.fx_apply(mi, "alpha_nocull", Color(1.0, 0.9, 0.55, 0.85), 2.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(0.018, 0.018, 0.9 if pellet else 1.8)
	return mi

func _spawn_casing() -> void:
	Perf.mark("gun_casing")
	var old := get_tree().get_nodes_in_group("casings").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	for k in maxi(0, old.size() - holder.max_casings + 1):
		old[k].queue_free()
	var cam := player.camera.global_transform
	var rb := make_casing()
	player.get_parent().add_child(rb)
	rb.global_position = cam.origin + cam.basis * Vector3(0.22, -0.2, -0.45)
	rb.global_rotation = Vector3(randf() * TAU, randf() * TAU, 0)
	rb.linear_velocity = player.velocity * 0.8 + cam.basis * Vector3(randf_range(2.0, 3.0), randf_range(1.5, 2.5), randf_range(0.2, 0.8))
	rb.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
	var tw := rb.create_tween()
	tw.tween_interval(holder.casing_lifetime)
	tw.tween_callback(rb.queue_free)

## Гильза: маленькое физтело на слое debris, общий меш и материал.
static func make_casing() -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.add_to_group("casings")
	rb.collision_layer = 1 << 6
	rb.collision_mask = 1
	rb.mass = 0.02
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.025, 0.025, 0.05)
	cs.shape = box
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = FX.shared_mesh("box")
	mi.material_override = WeaponMeshes.mat("gold")
	mi.scale = Vector3(0.025, 0.025, 0.05)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(mi)
	return rb

## Рука вьюмодели (правая, общая с мили), null — пока Player не собрал руки.
func _hand() -> ViewmodelMotion.Hand:
	if player == null or player.view_motion == null or holder.pivot == null:
		return null
	return player.view_motion.hand_for(holder.pivot)

## Отдача в руке: импульс пружины по силе отдачи оружия (тяжёлое — сильнее и возвращается медленнее).
func _animate_kick(d: WeaponDef) -> void:
	var h := _hand()
	if h == null or holder.is_switching():
		return
	var t := player.view_motion.tuning
	var deg := maxf(0.2, d.recoil_kick_deg)
	var back := minf(t.fire_kick_per_deg * deg, t.fire_kick_max)
	var tilt := minf(t.fire_tilt_per_deg * deg, t.fire_tilt_max)
	h.stiffness_mult = 1.0 / (1.0 + deg * 0.12)
	h.kick(Vector3(randf_range(-0.05, 0.05), 0.22, 1.0) * back, Vector3(tilt, randf_range(-0.15, 0.15) * tilt, randf_range(-0.2, 0.2) * tilt))
	h.set_state(&"fire", 0.05)

## Перезарядка: опустить и наклонить, «вставили магазин» (толчок вверх), поднять. Длится ровно reload_time.
func _animate_reload(time: float) -> void:
	var h := _hand()
	if h == null or item == null:
		return
	var d := item.def
	var t := player.view_motion.tuning
	var low_pos := d.view_rest_pos + t.reload_low_pos
	var low_rot := d.view_rest_rot + t.reload_low_rot
	h.set_state(&"reload", time)
	h.wrist_target = Vector3(-10, 0, 0)
	var tw := h.new_tween()
	tw.set_parallel(true)
	tw.tween_property(h, "position", low_pos, time * 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_property(h, "rotation_degrees", low_rot, time * 0.25).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_interval(time * 0.2)
	tw.chain().tween_callback(func() -> void:
		h.kick(Vector3(0, t.reload_slap, -0.2), Vector3(-t.reload_slap * 60.0, 0, 0)))
	tw.chain().tween_interval(time * 0.25)
	tw.chain().tween_callback(func() -> void: h.wrist_target = Vector3.ZERO)
	tw.chain().tween_property(h, "position", d.view_rest_pos, time * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(h, "rotation_degrees", d.view_rest_rot, time * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
