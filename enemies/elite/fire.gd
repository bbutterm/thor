extends EliteHandler
## Огненный: на ходу оставляет лужи огня (weapons/fire_zone.gd, враждебный режим — жжёт Тора, не своих).
## Не больше mod.trail_max луж от одной элиты, без источников света — общий материал огня.

var _t: float = 0.0
var _zones: Array = []

func _physics_process(delta: float) -> void:
	if not alive() or mod.trail_interval <= 0.0:
		return
	var hs := Vector2(enemy.velocity.x, enemy.velocity.z).length()
	if hs < 0.5 or not enemy.is_on_floor():
		return
	_t += delta
	if _t < mod.trail_interval:
		return
	_t = 0.0
	_zones = _zones.filter(func(z: Variant) -> bool: return is_instance_valid(z) and not (z as Node).is_queued_for_deletion())
	while _zones.size() >= maxi(1, mod.trail_max):
		(_zones.pop_front() as Node).queue_free()
	var f := preload("res://weapons/fire_zone.gd").new()
	f.hostile = true
	f.source_node = enemy
	enemy.get_parent().add_child(f)
	f.setup(enemy.global_position, mod.trail_radius, mod.trail_duration, mod.trail_dps, false)
	_zones.append(f)
