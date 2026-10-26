extends Node3D
class_name MjolnirProjectile
## Летящий Мьёльнир. Кинематический (не RigidBody): двигаем сами, проверяем попадания вдоль отрезка.
## База (GDD 10): летит до max_range, бьёт всех на пути, втыкается в стену или пол; возврат по дуге
## сквозь стены (ПКМ или сам через auto_return_after / stuck_auto_return). Бьёт врагов в обе стороны.
## Трейты (MjolnirTraitHandler) подключаются через хуки — см. вызовы hand.trait_call(...).
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
## Возврат начат игроком (ПКМ), а не таймером
var recalled_by_player: bool = false
## Возврат начат из воткнутого состояния (stuck_normal — нормаль поверхности)
var recalled_from_stuck: bool = false
## Состояние броска для трейтов
var data: Dictionary = {}
## Кого уже задели на этом проходе (туда / обратно) — id коллайдеров
var hit_ids: Dictionary = {}

var _time: float = 0.0
var _caught: bool = false
var _recall_controller: MjolnirTraitHandler = null
var _mesh_root: Node3D
var _light: OmniLight3D
var _sticks: bool = true
var _max_range: float = 25.0
var _auto_return_after: float = 1.5
var _stuck_auto_return: float = 0.8
var _spin_speed: float = 22.0
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
	_auto_return_after = float(hand.trait_modify(&"auto_return_after", hand.auto_return_after))
	_stuck_auto_return = float(hand.trait_modify(&"stuck_auto_return", hand.stuck_auto_return))
	_build_visual()
	hand.trait_call(&"on_throw", [self])

func _build_visual() -> void:
	_mesh_root = Node3D.new()
	add_child(_mesh_root)
	var hm := WeaponMeshes.hammer()
	hm.position = Vector3(0, -0.3, 0)
	hm.scale = Vector3.ONE * 1.15
	_mesh_root.add_child(hm)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.85, 0.45) if damage_mult > 1.0 else Color(0.5, 0.8, 1.0)
	_light.light_energy = 1.5
	_light.omni_range = 4.0
	add_child(_light)

## Включить свечение «идеального» броска (вызывает рука после launch)
func set_empowered(mult: float) -> void:
	damage_mult = mult
	if _light:
		_light.light_color = Color(1.0, 0.85, 0.45) if mult > 1.0 else Color(0.5, 0.8, 1.0)
		_light.light_energy = 3.0 if mult > 1.0 else 1.5

func fx_parent() -> Node:
	return get_parent()

func is_stuck() -> bool:
	return state == State.STUCK

func damage() -> float:
	return hand.current_damage() * damage_mult

## Сменить направление полёта «туда» (рикошет). Сбрасывает таймеры дальности и автовозврата.
func redirect(new_vel: Vector3) -> void:
	vel = new_vel
	flight_time = 0.0
	travelled = 0.0
	hit_ids.clear()
	_redirected = true

## Зависнуть на месте (Буря). Пока висит — on_flight_tick продолжает вызываться, автовозврата нет.
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
		_spin_speed = 22.0

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
	recalled_by_player = by_player
	recalled_from_stuck = was_stuck
	hit_ids.clear()
	_redirected = false
	if was_stuck:
		# Выдёргиваем из стены: сначала от поверхности, дальше дуга к руке
		vel = stuck_normal * hand.return_speed * 0.5
		_spin_speed = 22.0
	if vel.length() < 0.1:
		vel = (hand.hand_point() - global_position).normalized() * 0.1
	Audio.play("sounds/weapon_change.ogg")
	hand.trait_call(&"on_recall_start", [self, by_player])

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
			hand.trait_call(&"on_flight_tick", [self, delta])
			if state == State.OUT:
				_step_out(delta)
				if state == State.OUT and (flight_time >= _auto_return_after or travelled >= _max_range):
					start_return(false)
		State.HOVER:
			hand.trait_call(&"on_flight_tick", [self, delta])
		State.STUCK:
			stuck_time += delta
			hand.trait_call(&"on_stuck_tick", [self, delta])
			if state == State.STUCK and _stuck_auto_return > 0.0 and stuck_time >= _stuck_auto_return:
				start_return(false)
		State.RETURN:
			return_time += delta
			hand.trait_call(&"on_recall_tick", [self, delta])
			if _caught:
				return
			if _recall_controller:
				_recall_controller.control_recall_tick(self, delta)
			else:
				_step_return(delta)

func _step_out(delta: float) -> void:
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
	if bounces_left > 0:
		bounces_left -= 1
		bounces_done += 1
		ComicFX.pop("ricochet", pos)
		global_position = pos + normal * 0.3
		vel = vel.bounce(normal) * 0.85
		FX.burst(get_parent(), pos, 0.5, Color(0.6, 0.85, 1.0, 0.6), 0.15)
		FX.sparks(get_parent(), pos, Color(0.7, 0.9, 1.0), 14, 6.0)
		Audio.play("sounds/sfx/hammer_bounce.wav")
		hand.trait_call(&"on_hit_world", [self, pos, normal, false])
	elif _sticks:
		_stick(pos, normal)
	else:
		global_position = pos + normal * 0.3
		FX.burst(get_parent(), pos, 0.5, Color(0.6, 0.85, 1.0, 0.6), 0.15)
		FX.sparks(get_parent(), pos, Color(0.7, 0.9, 1.0), 14, 6.0)
		Audio.play("sounds/sfx/hammer_bounce.wav")
		vel = vel.bounce(normal) * 0.5
		hand.trait_call(&"on_hit_world", [self, pos, normal, false])
		start_return(false)

## Молот воткнулся: боёк в поверхности, рукоять наружу (на полу — стоит рукоятью вверх).
func _stick(pos: Vector3, normal: Vector3) -> void:
	Perf.mark("hammer_stick")
	state = State.STUCK
	stuck_time = 0.0
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
	hand.player.camera_fx.add_trauma(0.08)
	hand.trait_call(&"on_hit_world", [self, pos, stuck_normal, true])

func _step_return(delta: float) -> void:
	var target := hand.hand_point()
	var to_target := target - global_position
	var dist := to_target.length()
	var speed := hand.return_speed * hand.return_speed_mult
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

## Молот в руке. Вызывать один раз (обработчики, взявшие возврат, — тоже через него).
func catch() -> void:
	if _caught:
		return
	_caught = true
	hand.on_caught()
	queue_free()

func _exit_tree() -> void:
	if hand and is_instance_valid(hand):
		hand.trait_call(&"on_projectile_removed", [self])

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
	var knock := Vector3(dir.x, 0, dir.z).normalized() * 9.0 + Vector3.UP * 3.0
	if c.has_method("take_hit"):
		var dmg := damage()
		c.take_hit(dmg, knock, "hammer")
		ComicFX.on_hammer_hit(c, global_position, state == State.RETURN, bounces_done)
		FX.hitstop(hand.hit_hitstop)
		hand.player.camera_fx.add_trauma(0.12)
		FX.burst(get_parent(), global_position, 0.6, Color(0.55, 0.85, 1.0, 0.7), 0.15)
		Audio.play("sounds/sfx/hammer_hit.wav")
		var chain := int(hand.trait_modify(&"chain_targets", hand.chain_targets))
		if chain > 0:
			chain_lightning(c as Node3D, dmg * hand.chain_damage_ratio, chain, hand.chain_radius)
		hand.trait_call(&"on_hit_enemy", [self, c, dmg])
	elif c is RigidBody3D:
		var rb := c as RigidBody3D
		rb.apply_central_impulse(knock * rb.mass * 0.7)

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
		best.take_hit(dmg, Vector3.UP * 2.0, "lightning")
		ComicFX.on_lightning(best)
		from = to
		hits += 1
	if hits > 0:
		Perf.mark("hammer_chain")
		Audio.play("sounds/sfx/lightning.wav")
	return hits
