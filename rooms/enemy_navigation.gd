extends RefCounted
## Навигация врага только для залов с EnemyNavigation и реальными регионами.
## Скорость, гравитация, толчки и столкновения остаются в Enemy.move_and_slide.
## Ходовые связи ведут по поверхности; односторонний jump-link включает
## проверенный SpawnEntry, а не переносит врага в конечную точку.

const SpawnEntry = preload("res://enemies/spawn_entry.gd")

var _body: CharacterBody3D
var _root: Node3D
var _agent: NavigationAgent3D
var _surface_tolerance: float
var _target_move: float
var _refresh_frames: int
var _last_frame := -1
var _last_map_iteration := 0
var _target_player_id := 0
var _target_floor := Vector3.INF
var _target_region := RID()
var _requested_target := Vector3.INF
var _requested_target_region := RID()
var _have_request := false
var _active := true
var _next := Vector3.ZERO
var _path_index := -1
var _walk_layers: int = 1
var _jump_layers: int = 2
var _jump_settings: Dictionary = {}
var _pending_jump: Dictionary = {}
var _jump: SpawnEntry
var _jump_slot := false
var _waiting_landing := false
var _jump_banned := false
var _banned_target_region := RID()

func setup(body: CharacterBody3D, root: Node3D, settings: Dictionary) -> void:
	_body = body
	_root = root
	_surface_tolerance = maxf(0.1, float(settings.get("surface_tolerance", 1.2)))
	_target_move = maxf(0.05, float(settings.get("target_move", 0.75)))
	_refresh_frames = maxi(1, int(ceil(maxf(0.05, float(settings.get("refresh_interval", 0.3))) * Engine.physics_ticks_per_second)))
	_agent = NavigationAgent3D.new()
	_agent.name = "TierNavigationAgent"
	_walk_layers = maxi(1, int(settings.get("walk_layers", 1)))
	_jump_layers = maxi(0, int(settings.get("jump_layers", 2))) & ~_walk_layers
	_jump_settings = settings.duplicate()
	_agent.navigation_layers = _walk_layers | _jump_layers
	_agent.link_reached.connect(_on_link_reached)
	_agent.path_desired_distance = maxf(0.05, float(settings.get("point_distance", 0.35)))
	_agent.target_desired_distance = maxf(0.05, float(settings.get("target_distance", 0.65)))
	_agent.avoidance_enabled = false
	_body.add_child(_agent)
	_next = _body.global_position

## Сигнал приходит внутри get_next_path_position: сохраняем данные, ничего не
## меняя в NavigationAgent до выхода из его внутреннего обхода массива пути.
func _on_link_reached(details: Dictionary) -> void:
	var link := details.get("owner") as NavigationLink3D
	if link == null:
		_pending_jump = {"valid": false}
		return
	var jump_layer: bool = (link.navigation_layers & _jump_layers) != 0
	if not jump_layer and str(link.get_meta("traverse", "")) != "jump":
		return  # обычная связь на физическом настиле
	var enter: Vector3 = details.get("link_entry_position", Vector3.INF)
	var exit: Vector3 = details.get("link_exit_position", Vector3.INF)
	var valid: bool = link.enabled and not link.bidirectional and jump_layer \
		and (link.navigation_layers & _walk_layers) == 0 and str(link.get_meta("traverse", "")) == "jump" \
		and enter.distance_to(link.get_global_start_position()) < 0.01 \
		and exit.distance_to(link.get_global_end_position()) < 0.01
	_pending_jump = {"valid": valid, "link": weakref(link), "exit": exit}

func has_pending_jump() -> bool:
	return not _pending_jump.is_empty()

func is_jumping() -> bool:
	return _jump != null and _jump.active

func is_waiting_for_landing() -> bool:
	return _waiting_landing

func jump_direction(speed: float, acceleration: float) -> Vector3:
	return _jump.desired_velocity(_body, acceleration) / maxf(speed, 0.01) if is_jumping() else Vector3.ZERO

## Сигнал уже обработан целиком; пробуем один раз, отклонение ведёт на лестницу.
func try_jump(speed: float, gravity: float) -> void:
	if _pending_jump.is_empty() or not is_instance_valid(_body) or not is_instance_valid(_root):
		return
	if not bool(_pending_jump.get("valid", false)):
		_reject_jump()
		return
	var link_ref: WeakRef = _pending_jump.get("link")
	var link: NavigationLink3D = link_ref.get_ref() as NavigationLink3D if link_ref else null
	if not is_instance_valid(link) or not link.enabled:
		_reject_jump()
		return
	# Не затираем оставшийся толчок начальной скоростью прыжка.
	var knockback: Vector3 = _body.get("knockback_velocity")
	if knockback.length_squared() > 0.01:
		_reject_jump()
		return
	if not _body.is_on_floor():
		return
	var room := _root.get_parent()
	if not is_instance_valid(room) or not room.has_method("try_navigation_jump"):
		_reject_jump()
		return
	if not bool(room.call("try_navigation_jump", _body)):
		return
	_jump_slot = true
	if _jump == null:
		_jump = SpawnEntry.new()
	# Оставляем расчётную капсулу чуть над целевым полом, чтобы запас дуги
	# не считал само касание пола препятствием. Реальное положение не меняем.
	var destination: Vector3 = _pending_jump["exit"] + Vector3.UP * maxf(0.01, float(_jump_settings.get("landing_clearance", 0.05)))
	if not _jump.begin(_body, "balcony", destination, speed, gravity, _jump_settings):
		_release_jump_slot()
		_reject_jump()
		return
	_pending_jump.clear()

## Удар/оглушение отменяет вход без изменения velocity и сохраняет отбрасывание.
func interrupt_jump() -> void:
	if is_jumping():
		_jump.cancel()
		_waiting_landing = true
		_reject_jump()
	elif has_pending_jump():
		_reject_jump()

## Вызывается после move_and_slide во всех состояниях, в том числе STUNNED.
func after_move(delta: float) -> void:
	if not is_instance_valid(_body):
		return
	if is_jumping():
		_jump.after_step(_body, delta)
		if not _jump.active:
			var flat_error := Vector2(_body.global_position.x - _jump.target.x, _body.global_position.z - _jump.target.z).length()
			var landed: bool = _jump.was_airborne and _body.is_on_floor() and _jump._on_world_floor(_body) \
				and absf(_body.global_position.y - _jump.target.y) <= 0.3 \
				and flat_error <= maxf(_jump.arrival_tolerance, _agent.path_desired_distance)
			if landed:
				_release_jump_slot()
				_have_request = false
				_last_frame = -1
			else:
				_waiting_landing = true
				_reject_jump()
	if _waiting_landing and _body.is_on_floor() and _jump != null and _jump._on_world_floor(_body):
		_waiting_landing = false
		_release_jump_slot()
		_have_request = false
		_last_frame = -1

func _release_jump_slot() -> void:
	if not _jump_slot:
		return
	_jump_slot = false
	if is_instance_valid(_root) and is_instance_valid(_body):
		var room := _root.get_parent()
		if is_instance_valid(room) and room.has_method("release_navigation_jump"):
			room.call("release_navigation_jump", _body)

func _reject_jump() -> void:
	_pending_jump.clear()
	_jump_banned = true
	_banned_target_region = _target_region
	_agent.navigation_layers = _walk_layers
	_have_request = false
	_last_frame = -1
	_next = _body.global_position

func is_active() -> bool:
	return _active

func direction() -> Vector3:
	if not _active or not is_instance_valid(_body):
		return Vector3.ZERO
	var to := _next - _body.global_position
	to.y = 0.0
	return to.normalized() if to.length_squared() > 0.0001 else Vector3.ZERO

## Вызывается каждый физический кадр, пока враг видит цель. true — LOD-кэш
## направления устарел. Запрос нового пути и определение регионов распределены.
func step(target: CharacterBody3D) -> bool:
	if has_pending_jump() or is_jumping() or _waiting_landing:
		return false
	if not is_instance_valid(_body) or not is_instance_valid(_root) or not is_instance_valid(_agent):
		_active = true
		return true
	var old_active := _active
	var old_index := _path_index
	var old_next := _next
	var was_moving := Vector2(old_next.x - _body.global_position.x, old_next.z - _body.global_position.z).length_squared() > 0.0001
	var changed := false
	var map := _agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		_active = true
		_have_request = false
		_next = _body.global_position
		return old_active != _active or old_next != _next
	var iteration: int = NavigationServer3D.map_get_iteration_id(map)
	var frame := Engine.get_physics_frames()
	var player_id: int = target.get_instance_id() if is_instance_valid(target) else 0
	if player_id != _target_player_id:
		_target_player_id = player_id
		_target_floor = Vector3.INF
		_target_region = RID()
		_have_request = false
		_last_frame = -1
		changed = true
	var due: bool = _last_frame < 0 or iteration != _last_map_iteration \
		or frame % _refresh_frames == _body.get_instance_id() % _refresh_frames
	if due:
		_last_frame = frame
		var map_changed := iteration != _last_map_iteration
		_last_map_iteration = iteration
		if is_instance_valid(target) and (target.is_on_floor() or _target_floor == Vector3.INF):
			var target_point: Vector3 = NavigationServer3D.map_get_closest_point(map, target.global_position)
			var target_region: RID = NavigationServer3D.map_get_closest_point_owner(map, target.global_position)
			if target_region.is_valid() and target_point.distance_to(target.global_position) <= _surface_tolerance:
				_target_floor = target_point
				_target_region = target_region
			elif target.is_on_floor():
				_target_floor = Vector3.INF
				_target_region = RID()
		if _jump_banned and (map_changed or (_target_region.is_valid() and _target_region != _banned_target_region)):
			_jump_banned = false
			_agent.navigation_layers = _walk_layers | _jump_layers
			_have_request = false
		var source_point: Vector3 = NavigationServer3D.map_get_closest_point(map, _body.global_position)
		var source_region: RID = NavigationServer3D.map_get_closest_point_owner(map, _body.global_position)
		var source_valid: bool = source_region.is_valid() and source_point.distance_to(_body.global_position) <= _surface_tolerance
		if not source_valid or not _target_region.is_valid():
			_active = true
			_have_request = false
			_next = _body.global_position
		else:
			# Путь нужен и на одном регионе: между точками может быть проём пола.
			_active = true
			if not _have_request or map_changed or _requested_target_region != _target_region \
					or _requested_target.distance_to(_target_floor) >= _target_move:
				_agent.target_position = _target_floor
				_requested_target = _target_floor
				_requested_target_region = _target_region
				_have_request = true
				changed = true
	if _active and _have_request:
		# После новой цели вызвать один раз даже если предыдущий путь закончился.
		if changed or not _agent.is_navigation_finished():
			_next = _agent.get_next_path_position()
			if has_pending_jump():
				_next = _body.global_position
				changed = true
			_path_index = _agent.get_current_navigation_path_index()
			if _agent.is_navigation_finished():
				_next = _body.global_position
	else:
		_path_index = -1
	var moving := Vector2(_next.x - _body.global_position.x, _next.z - _body.global_position.z).length_squared() > 0.0001
	return changed or old_active != _active or old_index != _path_index or was_moving != moving
