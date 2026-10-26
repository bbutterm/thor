extends MjolnirTraitHandler
## Огненный след (группа «след»): молот в полёте (туда и обратно) оставляет на полу полосу огня.

## Шаг между пятнами огня вдоль полёта (м)
@export var spacing: float = 1.8
@export var radius: float = 1.1
@export var radius_lvl2: float = 1.6
@export var duration: float = 3.0
@export var duration_lvl2: float = 5.0
## Урон в секунду (0.3 У/с)
@export var dps: float = 6.6
## Огонь ложится на пол, если молот не выше этого (м)
@export var max_height: float = 4.0
## Не больше стольких пятен одновременно (старые гаснут) — фризы и свет
@export var max_zones: int = 10
## Свет только у каждого n-го пятна
@export var light_every: int = 3

var _zones: Array[Node] = []
var _count: int = 0

func on_flight_tick(proj: MjolnirProjectile, _delta: float) -> void:
	_trail(proj)

func on_recall_tick(proj: MjolnirProjectile, _delta: float) -> void:
	_trail(proj)

func _trail(proj: MjolnirProjectile) -> void:
	var pos := proj.global_position
	if not proj.data.has("fire_last"):
		proj.data["fire_last"] = pos
		return
	if pos.distance_to(proj.data["fire_last"]) < spacing:
		return
	proj.data["fire_last"] = pos
	_drop(proj, pos)

func _drop(proj: MjolnirProjectile, pos: Vector3) -> void:
	var space := proj.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos, pos - Vector3(0, max_height, 0), 1))
	if hit.is_empty() or (hit.normal as Vector3).y < 0.6:
		return
	_zones = _zones.filter(func(z: Node) -> bool: return is_instance_valid(z) and not z.is_queued_for_deletion())
	while _zones.size() >= max_zones:
		_zones.pop_front().queue_free()
	var fire := preload("res://weapons/fire_zone.gd").new()
	proj.fx_parent().add_child(fire)
	_count += 1
	fire.setup(hit.position, lvl(radius, radius_lvl2), lvl(duration, duration_lvl2), dps, _count % maxi(1, light_every) == 0)
	_zones.append(fire)
	if _count == 1:
		mark()

## Сколько пятен огня сейчас горит (для тестов)
func active_zones() -> int:
	return _zones.filter(func(z: Node) -> bool: return is_instance_valid(z) and not z.is_queued_for_deletion()).size()
