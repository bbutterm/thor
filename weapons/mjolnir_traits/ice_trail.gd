extends MjolnirTraitHandler
## Ледяной след (группа «след»): молот в полёте оставляет на полу полосу льда — враги скользят и падают.
## Ур. 2: падение = стан 1 с.

## Шаг между пятнами льда вдоль полёта (м)
@export var spacing: float = 1.8
@export var radius: float = 1.3
@export var duration: float = 4.0
@export var fall_stun: float = 0.5
@export var fall_stun_lvl2: float = 1.0
@export var slide_push: float = 6.0
## Лёд ложится на пол, если молот не выше этого (м)
@export var max_height: float = 4.0
## Не больше стольких пятен одновременно (старые тают)
@export var max_zones: int = 12

var _zones: Array[Node] = []

func on_flight_tick(proj: MjolnirProjectile, _delta: float) -> void:
	_trail(proj)

func on_recall_tick(proj: MjolnirProjectile, _delta: float) -> void:
	_trail(proj)

func _trail(proj: MjolnirProjectile) -> void:
	var pos := proj.global_position
	if not proj.data.has("ice_last"):
		proj.data["ice_last"] = pos
		return
	if pos.distance_to(proj.data["ice_last"]) < spacing:
		return
	proj.data["ice_last"] = pos
	var space := proj.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos, pos - Vector3(0, max_height, 0), 1))
	if hit.is_empty() or (hit.normal as Vector3).y < 0.6:
		return
	_zones.assign(_zones.filter(func(z: Variant) -> bool: return is_instance_valid(z) and not (z as Node).is_queued_for_deletion()))
	while _zones.size() >= max_zones:
		_zones.pop_front().queue_free()
	var ice := preload("res://weapons/ice_zone.gd").new()
	ice.slide_push = slide_push
	proj.fx_parent().add_child(ice)
	ice.setup(hit.position, radius, duration, lvl(fall_stun, fall_stun_lvl2))
	_zones.append(ice)
	if _zones.size() == 1:
		mark()

## Сколько пятен льда сейчас лежит (для тестов)
func active_zones() -> int:
	return _zones.filter(func(z: Node) -> bool: return is_instance_valid(z) and not z.is_queued_for_deletion()).size()
