extends RefCounted
## Общее движение появления для маркеров gate/edge/balcony.
## Только физический путь: неверная конфигурация возвращает false и не включается.

const FLOOR_MASK := 1
const OBSTACLE_MASK := 1 | (1 << 3)
# Короткие хорды с запасом охватывают дугу; шаг учитывает частоту физики.
const MAX_CHORD_TIME := 0.05

var active := false
var mode := ""
var target := Vector3.ZERO
var horizontal := Vector3.ZERO
var move_speed := 0.0
var elapsed := 0.0
var was_airborne := false
var timeout := 4.0
var arrival_tolerance := 0.18

func begin(body: CharacterBody3D, source: String, destination: Vector3, speed: float, gravity: float, tuning: Dictionary = {}) -> bool:
	active = false
	var jump_speed := float(tuning.get("jump_speed", 8.0))
	var max_time := float(tuning.get("timeout", 4.0))
	var min_drop := float(tuning.get("min_drop", 0.6))
	var max_drop := float(tuning.get("max_drop", 5.0))
	var max_distance := float(tuning.get("max_distance", 10.0))
	var arrival := float(tuning.get("arrival_tolerance", 0.18))
	if source not in ["gate", "edge", "balcony"] or speed <= 0.0 or gravity <= 0.0 \
		or jump_speed <= 0.0 or max_time <= 0.0 or min_drop < 0.0 or max_drop < min_drop \
		or max_distance <= 0.0 or arrival <= 0.0:
		return false
	var collider := body.get_node_or_null("Collider") as CollisionShape3D
	if collider == null or collider.shape == null or collider.disabled or not body.is_inside_tree():
		return false
	var space := body.get_world_3d().direct_space_state
	var start := body.global_position
	if not _supported(space, body, start) or not _supported(space, body, destination):
		return false
	var flat := Vector3(destination.x - start.x, 0.0, destination.z - start.z)
	if flat.length() < 0.15 or flat.length() > max_distance:
		return false
	var chosen := Vector3.ZERO
	if source == "balcony":
		var drop := start.y - destination.y
		if drop < min_drop or drop > max_drop:
			return false
		# Как в Enemy: гравитация применяется до move_and_slide каждый тик.
		var step := 1.0 / maxf(1.0, float(Engine.physics_ticks_per_second))
		var initial := jump_speed - gravity * step * 0.5
		var flight := (initial + sqrt(initial * initial + 2.0 * gravity * drop)) / gravity
		chosen = flat / flight
		if chosen.length() > speed:
			return false
		var point := start
		var segment_start := start
		var vy := jump_speed
		var steps := int(ceil(flight / step))
		var ticks_per_chord := maxi(1, int(floor(MAX_CHORD_TIME / step)))
		for i in steps:
			vy -= gravity * step
			point += Vector3(chosen.x, vy, chosen.z) * step
			if point.y < destination.y:
				point.y = destination.y
			if (i + 1) % ticks_per_chord == 0 or i == steps - 1:
				# Парабола находится выше хорды не более g*t²/8. Запас в
				# запросе покрывает отклонение и не пропускает тонкие преграды.
				var span := float(mini(ticks_per_chord, i + 1)) * step
				var margin := 0.005 + gravity * span * span / 8.0
				if not _clear_segment(space, body, collider, segment_start, point, margin):
					return false
				segment_start = point
	else:
		if absf(start.y - destination.y) > 0.16:
			return false
		for i in range(1, int(ceil(flat.length() / 0.4)) + 1):
			var test := start.lerp(destination, minf(1.0, float(i) * 0.4 / flat.length()))
			if not _supported(space, body, test):
				return false
		if not _clear_segment(space, body, collider, start, destination):
			return false
		chosen = flat.normalized() * speed
	mode = source
	target = destination
	horizontal = chosen
	move_speed = speed
	timeout = max_time
	arrival_tolerance = arrival
	elapsed = 0.0
	was_airborne = false
	active = true
	if mode == "balcony":
		# Задаём и горизонтальную скорость — _apply_movement сохраняет её без рывка.
		body.velocity = Vector3(horizontal.x, jump_speed, horizontal.z)
	return true

func desired_velocity(body: CharacterBody3D, acceleration: float = 18.0) -> Vector3:
	if not active:
		return Vector3.ZERO
	if mode == "balcony":
		return horizontal
	var delta := Vector3(target.x - body.global_position.x, 0.0, target.z - body.global_position.z)
	if delta.length() < arrival_tolerance:
		active = false
		return Vector3.ZERO
	return delta.normalized() * minf(move_speed, sqrt(2.0 * maxf(0.01, acceleration) * delta.length()))

func after_step(body: CharacterBody3D, delta: float) -> void:
	if not active:
		return
	elapsed += maxf(0.0, delta)
	if mode == "balcony":
		if not body.is_on_floor():
			was_airborne = true
		elif was_airborne and absf(body.global_position.y - target.y) <= 0.3 and _on_world_floor(body):
			active = false
	if elapsed >= timeout:
		active = false

## На голове другого врага is_on_floor тоже true: это не нижний пол.
func _on_world_floor(body: CharacterBody3D) -> bool:
	for i in body.get_slide_collision_count():
		var hit := body.get_slide_collision(i)
		var collider := hit.get_collider() as CollisionObject3D
		if collider != null and (collider.collision_layer & FLOOR_MASK) != 0 and hit.get_normal().y > 0.5:
			return true
	return false

func cancel() -> void:
	# Не меняем velocity: толчок от удара должен сохраняться.
	active = false

func _supported(space: PhysicsDirectSpaceState3D, body: CharacterBody3D, foot: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(foot + Vector3.UP * 0.25, foot - Vector3.UP * 0.45, FLOOR_MASK, [body.get_rid()])
	var hit := space.intersect_ray(ray)
	return not hit.is_empty() and absf(foot.y - (hit.position as Vector3).y) <= 0.16

func _clear_segment(space: PhysicsDirectSpaceState3D, body: CharacterBody3D, collider: CollisionShape3D, from: Vector3, to: Vector3, margin: float = 0.005) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = collider.shape
	q.transform = Transform3D(body.global_basis, from) * collider.transform
	q.motion = to - from
	q.margin = margin
	q.collision_mask = OBSTACLE_MASK
	q.exclude = [body.get_rid()]
	q.collide_with_areas = false
	# cast_motion не проверяет исходные пересечения, поэтому проверяем оба.
	if not space.intersect_shape(q, 1).is_empty():
		return false
	var fraction := space.cast_motion(q)
	return fraction.size() >= 1 and fraction[0] >= 0.999
