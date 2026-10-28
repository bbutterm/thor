extends RefCounted
class_name PlayerDash
## Рывок и руны Мьёльнира (общий запас рывка и воздушных прыжков), таран, урон рывком.
## Компонент игрока (этап 2 рефакторинга): числа и состояние — поля Player (их ставят сцена, тела
## и тесты), здесь только логика. Доступ — player.dash; публичные функции есть и на Player.

var p: Player

func _init(player: Player) -> void:
	p = player

## Рывок разрешён стилем и изъяном: на земле (Прыгун — нет) / в воздухе (Кузнец — нет).
func can_dash(on_floor: bool) -> bool:
	if on_floor:
		return p.dash_on_ground
	return p.dash_in_air and bool(p.modify_stat(&"air_dash", true))

## Shift: на земле с зажатым Ctrl — подкат (GDD 5), иначе рывок (если стиль/изъян позволяют).
func _try_dash(wish: Vector3, on_floor: bool) -> void:
	if not can_dash(on_floor):
		return
	if on_floor and Input.is_action_pressed("slam"):
		_spend_dash_charge()
		p.movement._start_slide(_dir_or_forward(wish), maxf(p.slide_speed, p.horizontal_speed()))
		for h in p.body_handlers:
			h.on_dash(p)
		return
	_start_dash(wish)

func _dir_or_forward(wish: Vector3) -> Vector3:
	if wish != Vector3.ZERO:
		return wish
	var dir := -p.transform.basis.z
	dir.y = 0
	return dir.normalized()

## Восстановление рун при ловле Мьёльнира и от приёмов.
func restore_mjolnir_runes(amount: int) -> void:
	p.dash_charges = mini(p.dash_charges_max, p.dash_charges + maxi(0, amount))
	if p.dash_charges >= p.dash_charges_max:
		p._dash_recharge_timer = 0.0
	p.dash_charges_changed.emit(p.dash_charges, p.dash_charges_max, _rune_recharge_progress())

## В воздухе таймер приостановлен, но его сохранённая доля остаётся видимой в HUD.
func _rune_recharge_progress() -> float:
	var duration := maxf(p.dash_recharge * p.weapon_dash_recharge_mult() * p._rune_dash_recharge_mult, 0.001)
	return clampf(p._dash_recharge_timer / duration, 0.0, 1.0)

func _spend_dash_charge() -> void:
	p.dash_charges -= 1
	p._dash_recharge_timer = 0.0 if p.dash_charges == p.dash_charges_max - 1 else p._dash_recharge_timer
	p.dash_charges_changed.emit(p.dash_charges, p.dash_charges_max, _rune_recharge_progress())

func _start_dash(wish: Vector3) -> void:
	_spend_dash_charge()
	p._dash_entry_speed = p.horizontal_speed()
	p.is_sliding = false
	p._dash_dir = _dir_or_forward(wish)
	p._dash_time_left = p.dash_duration
	p._dash_in_air = not p.is_on_floor()
	p._invuln_left = p.dash_invuln
	p._dash_hit.clear()
	if p.dash_ram:
		_start_ram()
	p.camera_fx.kick_fov(14.0)
	p.camera_fx.speed_lines_pulse()
	Audio.play("sounds/sfx/dash.wav")
	Perf.mark("dash_ram" if p.dash_ram else "dash")
	for h in p.body_handlers:
		h.on_dash(p)
	p.runes._rune_on_dash()

func _process_dash(delta: float) -> void:
	p._dash_time_left -= delta
	p.velocity = p._dash_dir * p.dash_speed
	p.velocity.y = 0.0
	if Run.rune_count("dash_damage") > 0:
		_dash_damage_tick()
	if p.dash_ram:
		_ram_tick()
	if p._dash_time_left <= 0.0:
		_end_ram()
		if p._dash_in_air:
			p._dive_window_left = p.dive_window
		# Импульс складывается: к скорости до рывка добавляется бонус, но не ниже обычного выхода и не выше предела
		var exit_speed := minf(maxf(p.dash_speed * p.dash_exit_keep, p._dash_entry_speed + p.dash_momentum_bonus), p.movement.momentum_limit())
		p.velocity = p._dash_dir * exit_speed
		p.velocity.y = 1.5
		if p.dash_to_slide and p.is_on_floor():
			# Скользящий: скорость рывка не гасится — подкат на ней (до предела ×2.2)
			p.velocity.y = 0.0
			p.movement._start_slide(p._dash_dir, p.dash_speed)

func _start_ram() -> void:
	p._ram_hit.clear()
	if p._ram_saved_mask < 0:
		p._ram_saved_mask = p.collision_mask
	# Сквозь врагов (слой 3) — бочки и ящики (слой 4) по-прежнему толкаем телом
	p.collision_mask = p._ram_saved_mask & ~(1 << 2)

func _end_ram() -> void:
	if p._ram_saved_mask >= 0:
		p.collision_mask = p._ram_saved_mask
		p._ram_saved_mask = -1

## Каждый кадр тарана: враги рядом получают урон и отлетают в стороны, бочки — толчок.
func _ram_tick() -> void:
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = p.ram_radius
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, p.global_position + Vector3(0, 0.9, 0))
	q.collision_mask = (1 << 2) | (1 << 3)
	q.exclude = [p.get_rid()]
	var right := p._dash_dir.cross(Vector3.UP)
	for hit in space.intersect_shape(q, 16):
		var c: Object = hit.collider
		if c == null or p._ram_hit.has(c.get_instance_id()):
			continue
		p._ram_hit[c.get_instance_id()] = true
		var c3 := c as Node3D
		var side := signf(right.dot(c3.global_position - p.global_position))
		if side == 0.0:
			side = 1.0
		var knock := (p._dash_dir * 0.6 + right * side).normalized() * p.ram_knockback + Vector3.UP * p.ram_knock_up
		if c is Enemy:
			if not (c as Enemy).is_dead:
				p.deal_damage(c, p.ram_damage, knock, "dash")
				p.camera_fx.add_trauma(0.18)
				FX.hitstop(0.03)
				Audio.play("sounds/sfx/axe_hit_1.wav, sounds/sfx/axe_hit_2.wav")
		elif c is Destructible:
			# Бочки и ящики на пути тарана разлетаются
			p._dash_hit[c.get_instance_id()] = true
			(c as Destructible).take_hit(PropDebris.cfg().dash_damage, knock.normalized() * p.ram_prop_impulse, "dash")
		elif c is RigidBody3D:
			var rb := c as RigidBody3D
			rb.apply_central_impulse(knock.normalized() * p.ram_prop_impulse * rb.mass)
			rb.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * rb.mass * 2.0)
	Perf.mark("ram_tick")

func _dash_damage_tick() -> void:
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 1.3
	q.shape = s
	q.transform = Transform3D(Basis.IDENTITY, p.global_position + Vector3(0, 0.6, 0))
	q.collision_mask = 1 << 2
	q.exclude = [p.get_rid()]
	var dmg := p.dash_damage * Run.rune_count("dash_damage")
	for hit in space.intersect_shape(q, 16):
		var c: Object = hit.collider
		if c and c.has_method("take_hit") and not p._dash_hit.has(c.get_instance_id()):
			p._dash_hit[c.get_instance_id()] = true
			p.deal_damage(c, dmg, p._dash_dir * 9.0 + Vector3.UP * 3.0, "dash")
