extends Node3D
class_name MjolnirProjectile
## Летящий Мьёльнир. Кинематический (не RigidBody): двигаем сами, проверяем попадания вдоль отрезка.
## База (GDD 10, П5 — GDD 26.4): летит сквозь корм и бойцов, бьёт всех на пути; останавливают стена/пол
## (втыкается), тяжёлые, щитоносцы и боссы (отскок, падение, втыкается рядом). Промах — на max_range теряет
## скорость, падает по дуге и втыкается в землю. Возврат — только по ПКМ (по дуге сквозь стены, бьёт на
## обратном пути); свой возврат — у приёмов, где он суть (Бумеранг, Буря) и у копий Двух молотов.
## Трейты (MjolnirTraitHandler) подключаются через хуки — см. вызовы _trait(...) (→ hand.trait_call).
##
## Точки событий (для эффектов/комиксовых слов): _on_hit (попал по врагу), _on_world_hit (стена/пол:
## отскок или _stick — воткнулся), start_return (начало возврата), catch (поймал).

enum State { OUT, HOVER, STUCK, RETURN }
var state: State = State.OUT
var hand: MjolnirHand
var vel: Vector3 = Vector3.ZERO
## Время полёта «туда» (трейты могут сбрасывать, чтобы продлить полёт)
var flight_time: float = 0.0
## Пройденный путь «туда» (м) — для max_range
var travelled: float = 0.0
var stuck_time: float = 0.0
var stuck_normal: Vector3 = Vector3.UP
var return_time: float = 0.0
## Отскоки от стен, которые ещё остались (база 0; Рикошет добавляет и тратит их же на врагов)
var bounces_left: int = 0
## Сколько раз уже отскочил (для комиксового слова при попадании после рикошета)
var bounces_done: int = 0
## Множитель урона этого броска (идеальный хват ×2)
var damage_mult: float = 1.0
## Копия броска (трейт «Два молота»): без трейтов, не втыкается, у руки просто исчезает
var is_clone: bool = false
## Возврат начат игроком (ПКМ), а не приёмом/служебно
var recalled_by_player: bool = false
## Возврат начат из воткнутого состояния (stuck_normal — нормаль поверхности)
var recalled_from_stuck: bool = false
## Состояние броска для трейтов
var data: Dictionary = {}
## Кого уже задели на этом проходе (туда / обратно) — id коллайдеров
var hit_ids: Dictionary = {}
## Пробивает щит Щитоносца и броню элиты (Заряд в полную силу, Праща — блок Б4)
var pierce: bool = false
## Оглушение каждого задетого врага, с (Заряд ур. 2); 0 — нет
var stun_on_hit: float = 0.0

var _time: float = 0.0
var _caught: bool = false
var _recall_controller: MjolnirTraitHandler = null
var _mesh_root: Node3D
var _light: OmniLight3D
var _sticks: bool = true
var _max_range: float = 25.0
## Копия Двух молотов: через сколько секунд сама летит к руке
var _clone_return_after: float = 1.0
## Старое (FeelSwitch hammer_recall): автовозврат полёта / воткнутого (трейты продлевают — modify, hold_stuck)
var _auto_return_after: float = 1.5
var _stuck_auto_return: float = 0.8
## Падает по дуге (промах на max_range или отскок от тяжёлого/босса) — потом втыкается в землю
var dropping: bool = false
var drop_time: float = 0.0
## Попаданий по врагам за этот бросок (туда и обратно) — для hit-stop по убыванию и бота
var hits_done: int = 0
var _spin_speed: float = 22.0
## След в полёте и потрескивание воткнутого (П2): таймеры и точка начала ленты молнии
var _trail_t: float = 0.0
var _bolt_t: float = 0.0
var _bolt_from: Vector3 = Vector3.INF
var _crackle_t: float = 0.0
var _redirected: bool = false
const HIT_RADIUS := 0.6

func launch(owner_hand: MjolnirHand, origin: Vector3, velocity_: Vector3) -> void:
	hand = owner_hand
	global_position = origin
	vel = velocity_
	_sticks = bool(hand.trait_modify(&"sticks", hand.sticks_to_world))
	bounces_left = int(hand.trait_modify(&"wall_bounces", hand.max_wall_bounces))
	bounces_done = 0
	_max_range = float(hand.trait_modify(&"max_range", hand.max_range))
	_spin_speed = hand.pw(hand.spin_speed, &"spin")
	_auto_return_after = float(hand.trait_modify(&"auto_return_after", hand.auto_return_after))
	_stuck_auto_return = float(hand.trait_modify(&"stuck_auto_return", hand.stuck_auto_return))
	_build_visual()
	_trait(&"on_throw", [self])

## Копия-молот веера (Два молота): летит по своей траектории, возвращается и исчезает у руки.
func launch_clone(owner_hand: MjolnirHand, origin: Vector3, velocity_: Vector3, mult: float) -> void:
	is_clone = true
	hand = owner_hand
	global_position = origin
	vel = velocity_
	damage_mult = mult
	_sticks = false
	bounces_left = 0
	_max_range = hand.max_range
	_clone_return_after = hand.clone_return_after
	_spin_speed = hand.pw(hand.spin_speed, &"spin")
	_auto_return_after = hand.auto_return_after
	_stuck_auto_return = hand.stuck_auto_return
	_build_visual()
	if _light:
		_light.light_energy = 0.8

## Хуки трейтов — только у настоящего молота (у копий их нет, иначе трейты срабатывали бы дважды)
func _trait(hook: StringName, args: Array) -> void:
	if not is_clone:
		hand.trait_call(hook, args)

func _build_visual() -> void:
	# Летящий молот сбивает медленные сферы врагов (enemies/enemy_projectile.gd, вид ORB)
	add_to_group("mjolnir_projectiles")
	_mesh_root = Node3D.new()
	add_child(_mesh_root)
	var hm := WeaponMeshes.hammer()
	hm.position = Vector3(0, -0.4, 0)
	hm.scale = Vector3.ONE * 1.15
	_mesh_root.add_child(hm)
	if Outline.cfg().mjolnir_projectile:
		Outline.add(hm)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.85, 0.45) if damage_mult > 1.0 else Color(0.5, 0.8, 1.0)
	_light.light_energy = 1.5
	_light.omni_range = 4.0
	# Молот со стихией светится её цветом — ярче и дальше, видно издалека, какая стихия
	var el := hand.element_handler() if hand else null
	if el and damage_mult <= 1.0:
		_light.light_color = el.element_color()
		_light.light_energy = 2.6
		_light.omni_range = 5.5
	add_child(_light)

## Усиление броска от приёмов (рука после launch): hand.next_throw — damage_mult, range_mult, pierce, stun
func apply_throw_mods(mods: Dictionary) -> void:
	if mods.is_empty():
		return
	damage_mult *= float(mods.get("damage_mult", 1.0))
	var rm := float(mods.get("range_mult", 1.0))
	_max_range *= rm
	_auto_return_after *= rm
	pierce = pierce or bool(mods.get("pierce", false))
	stun_on_hit = maxf(stun_on_hit, float(mods.get("stun", 0.0)))
	if pierce and _light:
		_light.light_color = Color(1.0, 0.95, 0.75)
		_light.light_energy = 2.5

## Старое (FeelSwitch hammer_recall): воткнутый молот ждёт ПКМ не меньше sec секунд (ступенька, пёс, пике)
func hold_stuck(sec: float) -> void:
	if _stuck_auto_return > 0.0:
		_stuck_auto_return = maxf(_stuck_auto_return, sec)

## Боёк «кусает» точку to и возвращается (Верный пёс): только вид, сам молот остаётся воткнутым
func lunge(to: Vector3) -> void:
	if _mesh_root == null:
		return
	var local := to_local(to).limit_length(3.0) * 0.85
	var tw := _mesh_root.create_tween()
	tw.tween_property(_mesh_root, "position", local, 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(_mesh_root, "position", Vector3.ZERO, 0.14).set_ease(Tween.EASE_IN_OUT)

## Включить свечение «идеального» броска (вызывает рука после launch). Множитель складывается
## с уже набранным (Два молота ×0.6, Заряд) — раньше перезаписывал его.
func set_empowered(mult: float) -> void:
	damage_mult *= mult
	if _light:
		_light.light_color = Color(1.0, 0.85, 0.45) if mult > 1.0 else Color(0.5, 0.8, 1.0)
		_light.light_energy = 3.0 if mult > 1.0 else 1.5

func fx_parent() -> Node:
	return get_parent()

func is_stuck() -> bool:
	return state == State.STUCK

func damage() -> float:
	return hand.current_damage() * damage_mult

## Сменить направление полёта «туда» (рикошет). Сбрасывает дальность и падение.
func redirect(new_vel: Vector3) -> void:
	vel = new_vel
	flight_time = 0.0
	travelled = 0.0
	dropping = false
	hit_ids.clear()
	_redirected = true

## Зависнуть на месте (Буря). Пока висит — on_flight_tick продолжает вызываться; вернётся, когда Буря отпустит.
func hover(on: bool) -> void:
	if on and state == State.OUT:
		state = State.HOVER
		vel = Vector3.ZERO
		_spin_speed = 40.0
		if _mesh_root:
			# Лёжа на боку, крутится вокруг вертикали — «вертолёт»
			_mesh_root.basis = Basis(Vector3.FORWARD, PI * 0.5)
	elif not on and state == State.HOVER:
		state = State.OUT
		_spin_speed = hand.pw(hand.spin_speed, &"spin")

## Обработчик трейта берёт возврат на себя (Притяжение к молоту). false — уже занято другим.
func take_recall_control(handler: MjolnirTraitHandler) -> bool:
	if _recall_controller == null:
		_recall_controller = handler
	return _recall_controller == handler

func start_return(by_player: bool = false) -> void:
	Perf.mark("hammer_return")
	if state == State.RETURN or _caught:
		return
	var was_stuck := state == State.STUCK
	state = State.RETURN
	dropping = false
	recalled_by_player = by_player
	recalled_from_stuck = was_stuck
	hit_ids.clear()
	_redirected = false
	if was_stuck:
		# Выдёргиваем из стены: сначала от поверхности, дальше дуга к руке
		vel = stuck_normal * hand.return_speed_at(0.0) * 0.5
	_spin_speed = hand.pw(hand.spin_speed, &"spin")
	if vel.length() < 0.1:
		vel = (hand.hand_point() - global_position).normalized() * 0.1
	Audio.play("sounds/weapon_change.ogg")
	if hand.powered() and not is_clone:
		# П2: гул с нарастающей высотой — молот разгоняется к руке
		Audio.play("sounds/sfx/hammer_return_hum.wav")
		FX.sparks(get_parent(), global_position, Color(0.6, 0.88, 1.0), 10, 5.0)
	_trait(&"on_recall_start", [self, by_player])

func _physics_process(delta: float) -> void:
	if hand == null or not is_instance_valid(hand) or hand.player == null:
		queue_free()
		return
	_time += delta
	if _mesh_root and state != State.STUCK:
		if state == State.HOVER:
			_mesh_root.rotate(Vector3.UP, delta * _spin_speed * 0.5)
		else:
			_mesh_root.rotate_object_local(Vector3.RIGHT, delta * _spin_speed)
	match state:
		State.OUT:
			flight_time += delta
			_trait(&"on_flight_tick", [self, delta])
			if state == State.OUT:
				_step_out(delta)
				if state == State.OUT:
					_out_limits(delta)
		State.HOVER:
			_trait(&"on_flight_tick", [self, delta])
		State.STUCK:
			stuck_time += delta
			_crackle_tick(delta)
			_trait(&"on_stuck_tick", [self, delta])
			if state == State.STUCK and FeelSwitch.is_old(&"hammer_recall") and _stuck_auto_return > 0.0 \
					and stuck_time >= _stuck_auto_return:
				start_return(false)
		State.RETURN:
			return_time += delta
			_trait(&"on_recall_tick", [self, delta])
			if _caught:
				return
			if _recall_controller:
				_recall_controller.control_recall_tick(self, delta)
			else:
				_step_return(delta)

## Предел полёта «туда»: копия возвращается сама; настоящий молот на max_range начинает падать по дуге.
## Упал в пропасть (падает дольше drop_lost_time) — летит к руке сам, чтобы не потеряться.
func _out_limits(delta: float) -> void:
	if FeelSwitch.is_old(&"hammer_recall") and not dropping:
		# Старое: сам летит обратно по таймеру или на дальности
		if flight_time >= _auto_return_after or travelled >= _max_range:
			start_return(false)
		return
	if is_clone:
		if flight_time >= _clone_return_after or travelled >= _max_range:
			start_return(false)
		return
	if dropping:
		drop_time += delta
		if drop_time >= hand.drop_lost_time:
			start_return(false)
	elif travelled >= _max_range:
		begin_drop(vel * hand.drop_speed_keep)

## Начать падение по дуге со скоростью v (промах на дальности, отскок от тяжёлого/босса).
func begin_drop(v: Vector3) -> void:
	Perf.mark("hammer_drop")
	dropping = true
	drop_time = 0.0
	vel = v
	_spin_speed = 12.0

## П2: след в полёте — звёзды-искры (пул VFX-комплекта) и короткие ленты молнии; общие материалы FX.
func _trail_tick(delta: float) -> void:
	if not hand.powered() or is_clone:
		return
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = hand.trail_interval
		FX.spark_star(get_parent(), global_position, _light.light_color if _light else Color(0.6, 0.88, 1.0), hand.trail_star_size)
	_bolt_t -= delta
	if _bolt_t <= 0.0:
		_bolt_t = hand.trail_bolt_interval
		if _bolt_from != Vector3.INF and _bolt_from.distance_to(global_position) > 0.5:
			FX.lightning(get_parent(), _bolt_from, global_position, 0.12, _light.light_color if _light else Color(0.55, 0.85, 1.0))
		_bolt_from = global_position

## П2: воткнутый молот потрескивает молнией рядом с собой
func _crackle_tick(delta: float) -> void:
	if not hand.powered() or is_clone:
		return
	_crackle_t -= delta
	if _crackle_t > 0.0:
		return
	_crackle_t = hand.stuck_crackle_interval * randf_range(0.7, 1.3)
	var off := Vector3(randf_range(-1, 1), randf_range(-0.2, 1), randf_range(-1, 1)).normalized() * randf_range(0.5, 1.0)
	FX.lightning(get_parent(), global_position, global_position + off, 0.1, Color(0.6, 0.88, 1.0))
	if _light:
		_light.light_energy = randf_range(1.2, 3.0)

func _step_out(delta: float) -> void:
	_trail_tick(delta)
	if dropping:
		vel.y -= hand.drop_gravity * delta
	var from := global_position
	var to := from + vel * delta
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(ray)
	_redirected = false
	if hit:
		_sweep_hits(from, hit.position)
		if state == State.OUT and not _redirected:
			travelled += from.distance_to(hit.position)
			_on_world_hit(hit.position, hit.normal)
	else:
		_sweep_hits(from, to)
		if state == State.OUT and not _redirected:
			travelled += from.distance_to(to)
			global_position = to

## Удар о стену/пол: отскок (если остались), иначе воткнуться (база) или вернуться (Бумеранг).
func _on_world_hit(pos: Vector3, normal: Vector3) -> void:
	if bounces_left > 0 and not dropping:
		bounces_left -= 1
		bounces_done += 1
		ComicFX.pop("ricochet", pos)
		global_position = pos + normal * 0.3
		vel = vel.bounce(normal) * 0.85
		FX.burst(get_parent(), pos, 0.5, Color(0.6, 0.85, 1.0, 0.6), 0.15)
		FX.sparks(get_parent(), pos, Color(0.7, 0.9, 1.0), 14, 6.0)
		Audio.play("sounds/sfx/hammer_bounce.wav")
		_trait(&"on_hit_world", [self, pos, normal, false])
	elif _sticks:
		_stick(pos, normal)
	else:
		global_position = pos + normal * 0.3
		FX.burst(get_parent(), pos, 0.5, Color(0.6, 0.85, 1.0, 0.6), 0.15)
		FX.sparks(get_parent(), pos, Color(0.7, 0.9, 1.0), 14, 6.0)
		Audio.play("sounds/sfx/hammer_bounce.wav")
		vel = vel.bounce(normal) * 0.5
		_trait(&"on_hit_world", [self, pos, normal, false])
		start_return(false)

## Молот воткнулся: боёк в поверхности, рукоять наружу (на полу — стоит рукоятью вверх).
func _stick(pos: Vector3, normal: Vector3) -> void:
	Perf.mark("hammer_stick")
	state = State.STUCK
	stuck_time = 0.0
	dropping = false
	stuck_normal = normal.normalized()
	vel = Vector3.ZERO
	global_position = pos + stuck_normal * 0.38
	if _mesh_root:
		# +Y меша (боёк) смотрит в поверхность
		var y := -stuck_normal
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y).normalized()
		_mesh_root.basis = Basis(x, y, z)
	FX.burst(get_parent(), pos, 0.6, Color(0.6, 0.85, 1.0, 0.6), 0.18)
	FX.sparks(get_parent(), pos, Color(0.55, 0.5, 0.45), 18, 5.0, 14.0, 0.08, 0.5)
	Audio.play("sounds/sfx/hammer_stick.wav")
	hand.player.camera_fx.add_trauma(hand.pw(hand.stick_shake, &"stick_shake"))
	if hand.powered() and not is_clone:
		_stick_impact(pos)
	_trait(&"on_hit_world", [self, pos, stuck_normal, true])

## П2: втыкание — ударная волна (слабый урон, сильный отброс), трещина на полу, обломки, пыль, треск.
func _stick_impact(pos: Vector3) -> void:
	Perf.mark("hammer_stick_wave")
	var on_floor := stuck_normal.y > 0.6
	var parent := get_parent()
	if on_floor:
		FX.shockwave(parent, pos + Vector3(0, 0.05, 0), hand.stick_wave_radius, Color(0.7, 0.9, 1.0))
		FX.crack(parent, pos, hand.stick_crack_height)
	else:
		FX.burst(parent, pos, 1.1, Color(0.6, 0.85, 1.0, 0.5), 0.2)
	FX.hit_flash(parent, pos, 1.4, Color(0.75, 0.92, 1.0))
	FX.sparks(parent, pos, Color(0.45, 0.38, 0.3), 24, 7.0, 16.0, 0.1, 0.7)
	FX.smoke(parent, pos + stuck_normal * 0.3, 1.2)
	Audio.play("sounds/sfx/hammer_boom_1.wav,sounds/sfx/hammer_boom_2.wav,sounds/sfx/hammer_boom_3.wav")
	Audio.play("sounds/sfx/hammer_crackle.wav")
	var r := hand.stick_wave_radius
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.is_dead:
			continue
		var d := e.global_position - pos
		d.y = 0.0
		var dist := d.length()
		if dist > r or absf(e.global_position.y - pos.y) > 2.5:
			continue
		var out := d / dist if dist > 0.05 else Vector3.FORWARD
		var k := clampf(1.0 - dist / r, 0.35, 1.0)
		hand.player.deal_damage(e, hand.stick_wave_damage * damage_mult, out * hand.stick_wave_knock * k + Vector3.UP * hand.stick_wave_up * k, "hammer")

func _step_return(delta: float) -> void:
	_trail_tick(delta)
	var target := hand.hand_point()
	var to_target := target - global_position
	var dist := to_target.length()
	var speed := hand.return_speed_at(return_time)
	if dist < maxf(1.3, speed * delta * 1.5) or return_time > 4.0:
		catch()
		return
	var desired := to_target / dist * speed
	# Сначала молот разворачивается по дуге, со временем «притяжение» к руке растёт — орбиты невозможны
	var steer := hand.return_turn_accel / speed * (1.0 + return_time * 4.0)
	vel = vel.lerp(desired, clampf(1.0 - exp(-steer * delta), 0.0, 1.0))
	vel = vel.normalized() * speed
	var from := global_position
	var to := from + vel * delta
	_sweep_hits(from, to)
	global_position = to

## Сколько секунд до поимки (−1 — молот не летит к руке). Для подсказки хвата (ui/catch_assist.gd).
## Обычный возврат прокручивается вперёд теми же шагами, что _step_return (дуга разворота учтена, рука — на месте);
## если возвратом управляет трейт — оценка по прямой с текущей скоростью.
func catch_eta() -> float:
	if state != State.RETURN or _caught or hand == null or not is_instance_valid(hand):
		return -1.0
	var target := hand.hand_point()
	if _recall_controller != null:
		var v := maxf(vel.length(), 0.1)
		return maxf((target - global_position).length() - 1.3, 0.0) / v
	var dt := 1.0 / 60.0
	var pos := global_position
	var v2 := vel
	var t := return_time
	var eta := 0.0
	for i in 240:
		var speed := hand.return_speed_at(t)
		var to_t := target - pos
		var dist := to_t.length()
		if dist < maxf(1.3, speed * dt * 1.5) or t > 4.0:
			return eta
		var steer := hand.return_turn_accel / speed * (1.0 + t * 4.0)
		v2 = v2.lerp(to_t / dist * speed, clampf(1.0 - exp(-steer * dt), 0.0, 1.0)).normalized() * speed
		pos += v2 * dt
		t += dt
		eta += dt
	return eta

## Молот в руке. Вызывать один раз (обработчики, взявшие возврат, — тоже через него).
func catch() -> void:
	if _caught:
		return
	_caught = true
	if not is_clone:
		hand.caught.emit()
		hand.on_caught()
	queue_free()

func _exit_tree() -> void:
	if hand and is_instance_valid(hand):
		_trait(&"on_projectile_removed", [self])

func _sweep_hits(from: Vector3, to: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = HIT_RADIUS
	q.shape = s
	q.collision_mask = (1 << 2) | (1 << 3) | (1 << 6)
	q.collide_with_areas = false
	var seg := to - from
	var steps := maxi(1, int(ceil(seg.length() / 0.4)))
	var dir := seg.normalized() if seg.length() > 0.001 else vel.normalized()
	for i in steps + 1:
		q.transform = Transform3D(Basis.IDENTITY, from + seg * (float(i) / steps))
		for h in space.intersect_shape(q, 16):
			var c: Object = h.collider
			if c == null:
				continue
			var id := c.get_instance_id()
			if hit_ids.has(id):
				continue
			hit_ids[id] = true
			_on_hit(c, dir)
			# Трейт мог развернуть молот (рикошет) — дальше по старому отрезку не идём
			if _redirected:
				return

## Попадание по врагу или физтелу.
func _on_hit(c: Object, dir: Vector3) -> void:
	var knock := Vector3(dir.x, 0, dir.z).normalized() * hand.pw(hand.hit_knock_forward, &"knock_forward") \
		+ Vector3.UP * hand.pw(hand.hit_knock_up, &"knock_up")
	if c is Destructible:
		# Бочка/ящик: ломается и летит, без трейтов «по врагу», цепной молнии и слова комикса
		(c as Destructible).take_hit(damage(), knock, "hammer")
		Audio.play("sounds/sfx/hammer_hit.wav")
		return
	if c.has_method("take_hit"):
		var dmg := damage()
		var en := c as Enemy
		if pierce and en:
			en.armor_pierce_hit = true
		hand.player.deal_damage(c, dmg, knock, "hammer")
		if en and is_instance_valid(en):
			en.armor_pierce_hit = false
			if stun_on_hit > 0.0 and not en.is_dead:
				en.stun(stun_on_hit)
		ComicFX.on_hammer_hit(c, global_position, state == State.RETURN, bounces_done)
		FX.hitstop(hand.hitstop_for(hits_done))
		hand.player.camera_fx.add_trauma(hand.pw(hand.hit_shake, &"hit_shake"))
		FX.burst(get_parent(), global_position, 0.6, Color(0.55, 0.85, 1.0, 0.7), 0.15)
		if hand.powered():
			_hit_impact(en)
		else:
			Audio.play("sounds/sfx/hammer_hit.wav")
		hits_done += 1
		var chain := 0 if is_clone else int(hand.trait_modify(&"chain_targets", hand.chain_targets))
		if chain > 0:
			chain_lightning(c as Node3D, dmg * hand.chain_damage_ratio, chain, hand.chain_radius)
		_trait(&"on_hit_enemy", [self, c, dmg])
		# Тяжёлый, щитоносец или босс остановил молот (рикошет мог уже развернуть его к следующей цели)
		if state == State.OUT and not _redirected and en and is_instance_valid(en) and not en.is_dead and stops_hammer(en):
			_stopped_by(en, dir)
	elif c is RigidBody3D:
		var rb := c as RigidBody3D
		rb.apply_central_impulse(knock * rb.mass * 0.7)

## П2: попадание по врагу — вспышка, искры, малая ударная волна (лёгкий отброс соседей без урона),
## тяжёлый «бум» (3 варианта) с треском молнии.
func _hit_impact(en: Enemy) -> void:
	var parent := get_parent()
	FX.hit_flash(parent, global_position, 1.2, Color(0.8, 0.93, 1.0))
	FX.sparks(parent, global_position, Color(0.65, 0.9, 1.0), 16, 8.0)
	Audio.play("sounds/sfx/hammer_boom_1.wav,sounds/sfx/hammer_boom_2.wav,sounds/sfx/hammer_boom_3.wav")
	Audio.play("sounds/sfx/hammer_crackle.wav")
	if en == null or not is_instance_valid(en):
		return
	var center := en.global_position
	FX.ring(parent, center + Vector3(0, 0.08, 0), hand.hit_wave_radius, Color(0.6, 0.88, 1.0, 0.7), 0.25)
	for n in get_tree().get_nodes_in_group("enemies"):
		var o := n as Enemy
		if o == null or o == en or o.is_dead or hit_ids.has(o.get_instance_id()):
			continue
		var d := o.global_position - center
		d.y = 0.0
		var dist := d.length()
		if dist > hand.hit_wave_radius or absf(o.global_position.y - center.y) > 2.0:
			continue
		var out := d / dist if dist > 0.05 else Vector3.RIGHT
		o.knockback_velocity += out * hand.hit_wave_knock * (1.0 - o.knock_resist) + Vector3.UP * hand.hit_wave_up

## Кто останавливает летящий «туда» молот: боссы, тяжёлые (Раздутый), щитоносцы (если бросок не пробивает).
## Корм и бойцов молот пробивает и летит дальше.
func stops_hammer(en: Enemy) -> bool:
	# Элита «Щит от бросков» (С5) — молот отскакивает всегда
	if en.has_meta(&"elite_hammer_shield"):
		return true
	if not hand.stopped_by_heavy or FeelSwitch.is_old(&"hammer_recall"):
		return false
	match en.kind:
		Enemy.Kind.BOSS, Enemy.Kind.BLOATED:
			return true
		Enemy.Kind.SHIELD:
			return not pierce
	return false

## Остановлен врагом: отскок назад-вверх и падение по дуге — воткнётся в пол рядом (ждёт ПКМ).
## Бумеранг (не втыкается) и копии — сразу летят к руке (их свой возврат).
func _stopped_by(en: Enemy, dir: Vector3) -> void:
	Perf.mark("hammer_stopped")
	_redirected = true
	FX.sparks(get_parent(), global_position, Color(0.85, 0.92, 1.0), 14, 7.0)
	Audio.play("sounds/sfx/hammer_bounce.wav")
	if is_clone or not _sticks:
		start_return(false)
		return
	var back := Vector3(-dir.x, 0, -dir.z).normalized()
	if back.length() < 0.1:
		back = (global_position - en.global_position) * Vector3(1, 0, 1)
		back = back.normalized() if back.length() > 0.01 else Vector3.BACK
	begin_drop(back * hand.stop_bounce_speed + Vector3.UP * hand.stop_bounce_up)

## Цепная молния: от source перескакивает к ближайшему ещё не задетому врагу, count раз.
func chain_lightning(source: Node3D, dmg: float, count: int, radius: float) -> int:
	if source == null or not is_instance_valid(source):
		return 0
	var chained: Dictionary = {source.get_instance_id(): true}
	var from := source.global_position + Vector3(0, 1, 0)
	var hits := 0
	for k in count:
		var best: Enemy = null
		var best_d := radius
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Enemy
			if en == null or en.is_dead or chained.has(en.get_instance_id()):
				continue
			var d := (en.global_position + Vector3(0, 1, 0)).distance_to(from)
			if d < best_d:
				best_d = d
				best = en
		if best == null:
			break
		chained[best.get_instance_id()] = true
		var to := best.global_position + Vector3(0, 1, 0)
		FX.lightning(get_parent(), from, to)
		hand.player.deal_damage(best, dmg, Vector3.UP * 2.0, "lightning")
		ComicFX.on_lightning(best)
		from = to
		hits += 1
	if hits > 0:
		Perf.mark("hammer_chain")
		Audio.play("sounds/sfx/lightning.wav")
	return hits
