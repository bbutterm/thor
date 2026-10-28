extends RefCounted
class_name PlayerSlam
## Удар-приземление: допуск (can_start_slam), пике, отмена, посадка, удар по площади,
## мосты, отскок от удара, помощь «замедление при ударе-приземлении».
## Компонент игрока (этап 2 рефакторинга): числа и состояние — поля Player (их ставят сцена, тела
## и тесты), здесь только логика. Доступ — player.slam; публичные функции есть и на Player.

var p: Player

func _init(player: Player) -> void:
	p = player

## Доступен после воздушного прыжка/специального подброса или на достаточной высоте над поверхностью.
func can_start_slam() -> bool:
	if p.is_dead or p.is_on_floor() or p.is_climbing or p.is_slamming:
		return false
	if p._slam_ready:
		return true
	return slam_surface_hit(p.slam_min_height).is_empty()

## Ближайшая поверхность под ногами для проверки удара и его шкалы в HUD.
func slam_surface_hit(distance: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p.global_position, p.global_position + Vector3.DOWN * distance,
		p.collision_mask & Player.SLAM_SURFACE_MASK, [p.get_rid()])
	return p.get_world_3d().direct_space_state.intersect_ray(q)

## allow_latched — уже разрешённое при броске пике в том же полёте; само оно не обходит проверку смерти/посадки.
func _start_slam(allow_latched: bool = false) -> bool:
	if not can_start_slam():
		if not allow_latched or p.is_dead or p.is_on_floor() or p.is_climbing or p.is_slamming:
			if p._slam_hint_left <= 0.0:
				p._slam_hint_left = p.slam_hint_cooldown
				p.slam_unavailable.emit()
			return false
	p.skills.weapon_skill_cancel_motion()
	# Пике (GDD 7.2): сразу после рывка в воздухе — наклонно по направлению взгляда
	p.is_diving = (p._dash_time_left > 0.0 and p._dash_in_air) or p._dive_window_left > 0.0
	p._dive_window_left = 0.0
	p._slam_velocity = Vector3(0, -p.slam_speed, 0)
	if p.is_diving:
		var f := p.get_aim_forward()
		f.y = 0.0
		f = f.normalized() if f.length() > 0.01 else p._dash_dir
		p._slam_velocity = f * p.dive_horizontal_speed + Vector3.DOWN * p.dive_down_speed
		p.camera_fx.speed_lines_pulse()
		Perf.mark("dive")
	p.is_slamming = true
	p._dash_time_left = 0.0
	p.dash._end_ram()
	p.is_sliding = false
	p.camera_fx.kick_fov(-6.0)
	Audio.play("sounds/jump_c.ogg")
	Audio.thor_grunt()
	return true

## Отмена удара-приземления (GDD 7.2): рывок во время падения — дальше обычное падение
func _cancel_slam() -> void:
	p.is_slamming = false
	p.is_diving = false
	p.velocity = Vector3(p.velocity.x, maxf(p.velocity.y, -4.0), p.velocity.z)
	Perf.mark("slam_cancel")

func _on_landed() -> void:
	# Контакт с головой врага может считаться полом в тот же кадр: это отскок, а не посадка.
	if p._stomp_cooldown > 0.0 and p.velocity.y > 0.0:
		return
	var skill_id := p._weapon_skill_landing_id
	p._weapon_skill_landing_id = ""
	p._weapon_skill_dive_speed = 0.0
	p._weapon_skill_landing_used = false
	p._slam_ground_contacts += 1
	p._slam_ready = false
	var fall := maxf(0.0, p._air_peak_y - p.global_position.y)
	if p.is_slamming:
		p.is_slamming = false
		p.is_diving = false
		_do_slam_impact(fall)
		p.velocity.x = 0
		p.velocity.z = 0
		if p._last_slam_hits > 0:
			_slam_bounce(fall)
		else:
			p._super_jump_left = p.super_jump_window
	else:
		if fall > 1.5:
			p.camera_fx.land_dip(clampf(fall / 10.0, 0.05, 0.35))
			Audio.play("sounds/land.ogg")
	if not skill_id.is_empty() and not p.is_dead:
		p.weapon_skill_landed.emit(skill_id)

func _do_slam_impact(height: float) -> void:
	# Тяжёлый стиль: ×1.5 по радиусу и урону (slam_radius_mult / slam_damage_mult)
	# Руны: Тяжесть горы (радиус), Падение звезды (урон за метр высоты)
	var radius := (p.slam_base_radius + height * p.slam_radius_per_meter) * p.slam_radius_mult * (1.0 + Run.rune_value("mountain_weight"))
	var damage := (p.slam_base_damage + height * p.slam_damage_per_meter * Run.rune_value("star_fall")) * p.slam_damage_mult
	var knock := p.slam_base_knockback + height * p.slam_knockback_per_meter
	var center := p.global_position
	p._last_slam_hits = 0
	var space := p.get_world_3d().direct_space_state
	_slam_break_floor(space, height)
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, center)
	q.collision_mask = (1 << 2) | (1 << 3) | (1 << 6)
	q.exclude = [p.get_rid()]
	for hit in space.intersect_shape(q, 64):
		var c: Object = hit.collider
		if c == null:
			continue
		var c3 := c as Node3D
		var dir := (c3.global_position - center)
		dir.y = 0
		var dist := dir.length()
		dir = dir.normalized() if dist > 0.01 else Vector3.FORWARD
		var falloff := clampf(1.0 - dist / radius, 0.35, 1.0)
		var push := dir * knock * falloff + Vector3.UP * knock * 0.55 * falloff
		if c is Destructible:
			# Бочки и ящики в радиусе — без спада урона к краю (DestructTuning.slam_full_damage)
			(c as Destructible).take_hit(damage if PropDebris.cfg().slam_full_damage else damage * falloff, push, "slam")
		elif c.has_method("take_hit"):
			p.deal_damage(c, damage * falloff, push, "slam")
			if c is Enemy:
				p._last_slam_hits += 1
				# Руна «Оглушающий гром» — оглушение ударом-приземлением (берётся большее из стиля и руны)
				var stun_time := maxf(p.slam_stun, Run.rune_value("stun_thunder"))
				if stun_time > 0.0 and is_instance_valid(c) and c.has_method("stun"):
					c.call("stun", stun_time)
		elif c is RigidBody3D:
			(c as RigidBody3D).apply_central_impulse(push * (c as RigidBody3D).mass * 0.6)
	if Run.rune_level("slam_fire") > 0:
		var fire := preload("res://weapons/fire_zone.gd").new()
		p.get_parent().add_child(fire)
		fire.setup(center, radius * 0.8, Run.rune_value("slam_fire"), 22.0)
	var power := clampf(0.25 + height / 14.0, 0.25, 1.0)
	p.camera_fx.add_trauma(power)
	p.camera_fx.land_dip(0.25 + power * 0.2)
	FX.ring(p.get_parent(), center, radius, Color(1.0, 0.85, 0.5, 0.9), 0.4)
	FX.burst(p.get_parent(), center + Vector3(0, 0.3, 0), radius * 0.35, Color(1, 0.9, 0.6, 0.45), 0.25)
	FX.sparks(p.get_parent(), center + Vector3(0, 0.2, 0), Color(0.55, 0.47, 0.4), 26 + int(power * 20), 7.0 + power * 6.0, 18.0, 0.14, 0.7)
	FX.slam_impact(p.get_parent(), center, radius, height)  # волна и трещина (VFX-комплект)
	FX.hitstop(0.06 + power * 0.04)
	ComicFX.on_slam(center, height)
	Audio.play("sounds/sfx/slam.wav")
	p.slammed.emit(power)
	for h in p.body_handlers:
		h.on_slam(p, power, p._last_slam_hits)
	if height >= p.big_slam_height:
		Odin.say("big_slam")
		Dialogue.thor_bark("slam", 0.6)

## Удар-приземление по деревянному мосту/настилу (Balcony со slam_breakable) — настил ломается (GDD 16).
func _slam_break_floor(space: PhysicsDirectSpaceState3D, height: float) -> void:
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0, 0.3, 0), p.global_position + Vector3(0, -0.6, 0), 1, [p.get_rid()])
	var hit := space.intersect_ray(q)
	var deck := hit.get("collider") as Balcony if not hit.is_empty() else null
	if deck:
		deck.on_slam(height)

## Удар-приземление задел врагов — подбрасывает на долю высоты падения, двойной прыжок восстанавливается.
func _slam_bounce(fall: float) -> void:
	# Тяжёлый стиль: отскок выше (slam_bounce_mult)
	var h := maxf(fall * p.slam_bounce_ratio, p.slam_bounce_min_height) * p.slam_bounce_mult
	p.velocity.y = sqrt(2.0 * p.gravity * h)
	# Прыжок в окне — не ниже супер-прыжка: отскок от врагов не должен отнимать супер-прыжок
	p._bounce_boost_velocity = maxf(sqrt(2.0 * p.gravity * h * p.slam_bounce_boost), p.jump_velocity * sqrt(p.super_jump_height_mult))
	p._bounce_window_left = maxf(p.slam_bounce_window, p.super_jump_window)
	p._slam_ready = true
	p._jumps_left = p.extra_jumps
	p._air_peak_y = p.global_position.y
	Perf.mark("slam_bounce")
	StyleMeter.event(&"slam_bounce")

## Помощь «замедление при ударе-приземлении» (GDD 22, облегчённый режим без штрафа к Славе):
## пока падаешь ударом-приземлением и в окне супер-прыжка/отскока после него — время идёт медленнее.
## Hit-stop главнее: пока он идёт, масштаб не трогаем (FX вернёт 1.0 сам).
func _slam_assist_tick() -> void:
	var want := GameSettings.slam_slowmo() and not p.is_dead and (p.is_slamming or p._super_jump_left > 0.0 or p._bounce_window_left > 0.0)
	if FX._hitstop_left > 0.0 or FX._slow_left > 0.0:
		return
	if want and not is_equal_approx(Engine.time_scale, p.slam_assist_time_scale):
		FX._set_time_scale(p.slam_assist_time_scale)
		p._slam_assist_on = true
	elif not want and p._slam_assist_on:
		p._slam_assist_on = false
		FX._set_time_scale(1.0)
