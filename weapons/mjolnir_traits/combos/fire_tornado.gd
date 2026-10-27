extends MjolnirTraitHandler
## Связка «Огненный смерч» (Огонь + Буря, блок Б4): зависший молот Бури — смерч: шире, тянет к себе
## всех (не боссов), поджигает каждого в круге и оставляет под собой горящую землю.

@export var radius_mult: float = 1.35
@export var pull_radius: float = 7.0
@export var pull_speed: float = 6.0
## Шаг поджога (с)
@export var ignite_tick: float = 0.3
## Горящая земля под смерчем: раз в fire_every с, радиус, сколько горит
@export var fire_every: float = 0.7
@export var fire_radius: float = 2.0
@export var fire_time: float = 2.0
@export var fire_dps: float = 6.6
@export var max_fires: int = 3

var _fires: Array[Node] = []
## Сколько врагов поджёг (для тестов)
var ignited: int = 0

func on_flight_tick(proj: MjolnirProjectile, delta: float) -> void:
	if proj.state != MjolnirProjectile.State.HOVER:
		return
	var storm := hand.trait_handler(&"storm")
	var fire := hand.element_handler()
	var base_r: float = float(storm.get("radius")) if storm and storm.get("radius") != null else 3.0
	var r := base_r * radius_mult
	var hp := proj.global_position
	for e in enemies_near(proj.get_tree(), hp, pull_radius):
		if e.kind == Enemy.Kind.BOSS:
			continue
		var to := hp - e.global_position
		to.y = 0
		if to.length() > 1.2:
			e.knockback_velocity = e.knockback_velocity.lerp(to.normalized() * pull_speed, clampf(1.0 - exp(-6.0 * delta), 0.0, 1.0))
	var k: float = float(proj.data.get("tornado_tick", 0.0)) - delta
	proj.data["tornado_tick"] = k
	if k <= 0.0:
		proj.data["tornado_tick"] = ignite_tick
		FX.ring(proj.fx_parent(), hp - Vector3(0, 0.6, 0), r, Color(1.0, 0.5, 0.15, 0.6), ignite_tick)
		FX.sparks(proj.fx_parent(), hp, Color(1.0, 0.55, 0.15), 10, 6.0, -4.0)
		for e in enemies_near(proj.get_tree(), hp, r):
			if fire:
				fire.apply_element(e, 1.0, hp, null)
			ignited += 1
		Destructible.ignite_area(proj, hp, r)
	var f: float = float(proj.data.get("tornado_fire", 0.0)) - delta
	proj.data["tornado_fire"] = f
	if f <= 0.0:
		proj.data["tornado_fire"] = fire_every
		var hit := floor_below(proj, hp, 5.0)
		if not hit.is_empty():
			_fires.assign(_fires.filter(func(z: Variant) -> bool: return is_instance_valid(z) and not (z as Node).is_queued_for_deletion()))
			while _fires.size() >= maxi(1, max_fires):
				_fires.pop_front().queue_free()
			var zone := preload("res://weapons/fire_zone.gd").new()
			proj.fx_parent().add_child(zone)
			zone.setup(hit.position, fire_radius, fire_time, fire_dps, _fires.is_empty())
			_fires.append(zone)
			mark()
