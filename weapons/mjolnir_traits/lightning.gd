extends MjolnirElementHandler
## Стихия «Молния» (блок Б4, GDD 10) — бывшие три трейта как способы доставки:
## 1 — «Цепная молния»: попадание перескакивает на ближайших врагов (с 3-го уровня — на 5, бывший ур. 2);
##     все задетые — «под током»; удар-приземление выпускает разряд с неба по всем, кто под током.
## 2 — след: земля под током вдоль полёта. 3 — «Громоотвод»: воткнутый молот бьёт молнией вокруг
##     (на 4-м — чаще, бывший ур. 2). 4 — «Гром небесный»: идеальный хват — молния в точку прицела, оглушает.
## Окружение: ток по лужам браги Свена (BrewPuddle.electrify_near).

@export_group("1. При попадании: цепная молния")
@export var chain_targets: int = 3
@export var chain_targets_lvl3: int = 5
## 0.5 У
@export var chain_damage: float = 11.0
## Дальность одного прыжка молнии (м)
@export var chain_radius: float = 7.0
## Сколько секунд враг «под током» (для разряда удара-приземления)
@export var shock_time: float = 5.0

@export_group("Связка: разряд по всем под током")
@export var discharge_radius: float = 18.0
@export var discharge_damage: float = 15.0
@export var discharge_stun: float = 0.4
## Не больше стольких молний разряда за раз (ближайшие) — толпа и лимит эффектов
@export var discharge_max: int = 8

@export_group("2. След: земля под током")
@export var trail_tick: float = 0.5
@export var trail_damage: float = 4.0

@export_group("3. Аура: Громоотвод")
@export var aura_interval_lvl4: float = 0.6

@export_group("4. Гром небесный")
@export var sky_stun: float = 1.0

@export_group("Окружение: лужи браги под током")
@export var brew_shock_time: float = 4.0
@export var brew_shock_damage: float = 6.0

func damage_source() -> String:
	return "lightning"

func aura_interval_now() -> float:
	return aura_interval_lvl4 if level >= LVL_SKY else aura_interval

func apply_element(enemy: Enemy, power: float, _from: Vector3, proj: MjolnirProjectile) -> void:
	var s := ElementStatus.of(enemy, true)
	if s:
		s.shock(shock_time)
	if power < 1.0 or proj == null:
		return
	var n: int = chain_targets_lvl3 if level >= LVL_AURA else chain_targets
	chain(enemy, chain_damage * proj.damage_mult, n, chain_radius)

## Цепная молния от source: count прыжков к ближайшим ещё не задетым врагам. Возвращает число попаданий.
func chain(source: Node3D, dmg: float, count: int, radius: float) -> int:
	if source == null or not is_instance_valid(source) or hand == null:
		return 0
	var tree := hand.get_tree()
	var parent := hand.player.get_parent()
	var chained: Dictionary = {source.get_instance_id(): true}
	var from := source.global_position + Vector3(0, 1, 0)
	var hits := 0
	for k in count:
		var best: Enemy = null
		var best_d := radius
		for e in tree.get_nodes_in_group("enemies"):
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
		FX.lightning(parent, from, to, 0.25, element_color())
		var s := ElementStatus.of(best, true)
		if s:
			s.shock(shock_time)
		hurt(best, dmg, Vector3.UP * 2.0, "lightning")
		ComicFX.on_lightning(best)
		world_effect(to - Vector3(0, 1, 0), 0.6)
		from = to
		hits += 1
	if hits > 0:
		mark("chain")
		Audio.play("sounds/sfx/lightning.wav")
	return hits

func world_effect(pos: Vector3, radius: float) -> void:
	if hand and hand.is_inside_tree():
		BrewPuddle.electrify_near(hand.get_tree(), pos, radius, brew_shock_time, brew_shock_damage)

func make_trail_zone(parent: Node, pos: Vector3, _proj: MjolnirProjectile) -> Node3D:
	var z := ElementZone.new()
	parent.add_child(z)
	z.flicker = true
	z.setup(pos, trail_radius, trail_duration, Color(0.55, 0.85, 1.0, 0.65), _trail_shock, false, trail_tick)
	return z

func _trail_shock(enemy: Enemy, zone: ElementZone) -> void:
	FX.lightning(zone.get_parent(), zone.global_position + Vector3(0, 0.1, 0), enemy.global_position + Vector3(0, 1.0, 0), 0.12, element_color())
	hurt(enemy, trail_damage, Vector3.UP * 0.5, "lightning")
	var s := ElementStatus.of(enemy, true)
	if s:
		s.shock(shock_time)

## Громоотвод: молния с неба в молот и от него — во всех вокруг
func aura_pulse(proj: MjolnirProjectile) -> void:
	var top := proj.global_position + proj.stuck_normal * 0.4
	var parent := proj.fx_parent()
	FX.lightning(parent, top + Vector3(0, 7.0, 0), top, 0.2, element_color())
	FX.ring(parent, proj.global_position - Vector3(0, 0.3, 0), aura_radius, Color(element_color(), 0.7), 0.25)
	for e in enemies_near(proj.get_tree(), proj.global_position, aura_radius):
		var chest := e.global_position + Vector3(0, 1.0, 0)
		FX.lightning(parent, top, chest, 0.18, element_color())
		var dir := e.global_position - proj.global_position
		dir.y = 0
		var s := ElementStatus.of(e, true)
		if s:
			s.shock(shock_time)
		hurt(e, aura_damage * proj.damage_mult, dir.normalized() * 2.0 + Vector3.UP * 2.0, "lightning")
	world_effect(proj.global_position, aura_radius)
	Audio.play("sounds/sfx/lightning.wav")

## Гром небесный: молния в точку прицела, урон по кругу и оглушение
func sky_strike(point: Vector3) -> void:
	var p := player()
	var parent := p.get_parent()
	FX.lightning(parent, point + Vector3(randf_range(-1, 1), 14.0, randf_range(-1, 1)), point, 0.3, element_color().lightened(0.3))
	FX.ring(parent, point, sky_radius, Color(element_color(), 0.9), 0.35)
	FX.burst(parent, point + Vector3(0, 0.5, 0), sky_radius * 0.4, Color(element_color(), 0.6), 0.2)
	for e in enemies_near(p.get_tree(), point, sky_radius + 0.9):
		hurt(e, sky_damage, Vector3.UP * 4.0, "lightning")
		if is_instance_valid(e) and not e.is_dead:
			e.stun(sky_stun)
			var s := ElementStatus.of(e, true)
			if s:
				s.shock(shock_time)
	world_effect(point, sky_radius)
	p.camera_fx.add_trauma(0.3)
	Audio.play("sounds/sfx/lightning.wav")

## Удар-приземление: разряд с неба по всем врагам «под током» в радиусе discharge_radius
func slam_combo(_power: float, center: Vector3) -> void:
	var shocked := enemies_with(center, discharge_radius, func(e: Enemy) -> bool: return ElementStatus.is_shocked(e))
	if shocked.is_empty():
		return
	mark("discharge")
	var parent := player().get_parent()
	shocked.sort_custom(func(x: Enemy, y: Enemy) -> bool: return x.global_position.distance_squared_to(center) < y.global_position.distance_squared_to(center))
	if shocked.size() > discharge_max:
		shocked.resize(discharge_max)
	for e in shocked:
		if not is_instance_valid(e) or e.is_dead:
			continue
		var chest := e.global_position + Vector3(0, 1.0, 0)
		FX.lightning(parent, chest + Vector3(randf_range(-1, 1), 10.0, randf_range(-1, 1)), chest, 0.25, element_color().lightened(0.3))
		ElementStatus.of(e).shocked_left = 0.0
		hurt(e, discharge_damage, Vector3.UP * 2.5, "lightning")
		if is_instance_valid(e) and not e.is_dead:
			e.stun(discharge_stun)
		ComicFX.on_lightning(e)
	StyleMeter.event(&"element_slam")
	Audio.play("sounds/sfx/lightning.wav")

## Молния: разряд с неба в цель и вспышка
func hit_signature(_enemy: Enemy, proj: MjolnirProjectile, chest: Vector3) -> void:
	var parent := proj.fx_parent()
	FX.lightning(parent, chest + Vector3(randf_range(-0.8, 0.8), 6.0, randf_range(-0.8, 0.8)), chest, 0.22, element_color())
	FX.hit_flash(parent, chest, 1.6, element_color().lightened(0.4))
