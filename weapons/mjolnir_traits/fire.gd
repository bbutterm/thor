extends MjolnirElementHandler
## Стихия «Огонь» (блок Б4, GDD 10). Бывший «Огненный след» — её второй уровень.
## 1 — попадание поджигает (урон со временем), огонь перекидывается на соседей; удар-приземление по горящим —
##     вспышка по площади у каждого. 2 — полоса огня вдоль полёта (fire_zone.gd; с 3-го уровня 5 с и шире —
##     бывший ур. 2 «Огненного следа»). 3 — воткнутый молот поджигает всех вокруг. 4 — огненный столб с неба.
## Окружение: поджигает бочки и ящики (Destructible.ignite_area) и брагу Свена (BrewPuddle.ignite_near).

@export_group("1. При попадании: поджог")
## Урон горения в секунду (0.3 У/с) и сколько горит
@export var burn_dps: float = 6.6
@export var burn_time: float = 3.0
## Огонь перекидывается на ближайшего соседа ближе этого (м) раз в spread_interval, не дальше spread_max_gen «поколений»
@export var spread_radius: float = 2.5
@export var spread_interval: float = 1.0
@export var spread_max_gen: int = 2

@export_group("Связка: вспышка горящих")
@export var flare_radius: float = 3.0
## 1 У
@export var flare_damage: float = 22.0
@export var flare_knockback: float = 8.0

@export_group("2. След: уровни 3–4 (бывший «Огненный след» ур. 2)")
@export var trail_dps: float = 6.6
@export var trail_radius_lvl3: float = 1.6
@export var trail_duration_lvl3: float = 5.0
## Свет только у каждого n-го пятна
@export var trail_light_every: int = 3

@export_group("4. Огненный столб: горящая земля")
@export var sky_fire_time: float = 3.0
@export var sky_fire_dps: float = 13.2

func damage_source() -> String:
	return "fire"

func apply_element(enemy: Enemy, power: float, _from: Vector3, _proj: MjolnirProjectile) -> void:
	var s := ElementStatus.of(enemy, true)
	if s == null:
		return
	s.spread_radius = spread_radius
	s.spread_interval = spread_interval
	s.spread_max_gen = spread_max_gen
	s.ignite(burn_dps, burn_time * clampf(power, 0.5, 1.0))

func world_effect(pos: Vector3, radius: float) -> void:
	var p := player()
	if p == null:
		return
	Destructible.ignite_area(p, pos, radius)
	BrewPuddle.ignite_near(p.get_tree(), pos, radius, trail_dps * 1.5, trail_duration_lvl3)

func make_trail_zone(parent: Node, pos: Vector3, _proj: MjolnirProjectile) -> Node3D:
	var fire := preload("res://weapons/fire_zone.gd").new()
	parent.add_child(fire)
	var big := level >= LVL_AURA
	fire.setup(pos, trail_radius_lvl3 if big else trail_radius, trail_duration_lvl3 if big else trail_duration, trail_dps,
		_zone_count % maxi(1, trail_light_every) == 0)
	return fire

func aura_pulse(proj: MjolnirProjectile) -> void:
	var c := proj.global_position
	var parent := proj.fx_parent()
	FX.ring(parent, c - Vector3(0, 0.3, 0), aura_radius, Color(1.0, 0.5, 0.15, 0.75), 0.3)
	FX.sparks(parent, c, Color(1.0, 0.55, 0.15), 12, 5.0, -2.0)
	for e in enemies_near(proj.get_tree(), c, aura_radius):
		hurt(e, aura_damage * proj.damage_mult, Vector3.UP * 1.0, "fire")
		if is_instance_valid(e) and not e.is_dead:
			apply_element(e, 0.7, c, proj)
	world_effect(c, aura_radius)
	Audio.sfx("fire_whoosh", "sounds/sfx/slam.wav")

func sky_strike(point: Vector3) -> void:
	var p := player()
	var parent := p.get_parent()
	FX.lightning(parent, point + Vector3(randf_range(-1, 1), 14.0, randf_range(-1, 1)), point, 0.3, Color(1.0, 0.6, 0.2))
	FX.burst(parent, point + Vector3(0, 0.6, 0), sky_radius * 0.5, Color(1.0, 0.5, 0.15, 0.7), 0.3)
	FX.ring(parent, point, sky_radius, Color(1.0, 0.5, 0.15, 0.9), 0.4)
	var fire := preload("res://weapons/fire_zone.gd").new()
	parent.add_child(fire)
	fire.setup(point, sky_radius, sky_fire_time, sky_fire_dps, true)
	for e in enemies_near(p.get_tree(), point, sky_radius + 0.9):
		hurt(e, sky_damage, Vector3.UP * 4.0, "fire")
		if is_instance_valid(e) and not e.is_dead:
			apply_element(e, 1.0, point, null)
	world_effect(point, sky_radius)
	ComicFX.pop("burn", point + Vector3(0, 1.0, 0), true)
	p.camera_fx.add_trauma(0.3)
	Audio.play("sounds/sfx/lightning.wav")

## Удар-приземление по горящим: у каждого горящего в радиусе — вспышка (урон и толчок вокруг него), огонь гаснет
func slam_combo(power: float, center: Vector3) -> void:
	var burning := enemies_with(center, slam_radius(power) + slam_reach, func(e: Enemy) -> bool: return ElementStatus.is_burning(e))
	if burning.is_empty():
		return
	mark("flare")
	var p := player()
	var parent := p.get_parent()
	var hit: Dictionary = {}
	for b in burning:
		if not is_instance_valid(b):
			continue
		var c := b.global_position
		ElementStatus.of(b).extinguish()
		FX.burst(parent, c + Vector3(0, 0.8, 0), flare_radius * 0.45, Color(1.0, 0.55, 0.15, 0.7), 0.25)
		FX.ring(parent, c, flare_radius, Color(1.0, 0.5, 0.15, 0.9), 0.3)
		FX.scorch(parent, c, flare_radius * 0.6, 0.5)
		for e in enemies_near(p.get_tree(), c + Vector3(0, 0.9, 0), flare_radius):
			if hit.has(e.get_instance_id()):
				continue
			hit[e.get_instance_id()] = true
			var dir := e.global_position - c
			dir.y = 0
			dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
			hurt(e, flare_damage, dir * flare_knockback + Vector3.UP * 4.0, "fire")
		Destructible.ignite_area(p, c, flare_radius)
	ComicFX.pop("burn", burning[0].global_position + Vector3(0, 1.4, 0), burning.size() >= 3)
	StyleMeter.event(&"element_slam")
	FX.hitstop(0.05)
	Audio.play("sounds/sfx/slam.wav")
