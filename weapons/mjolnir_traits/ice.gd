extends MjolnirElementHandler
## Стихия «Лёд» (блок Б4, GDD 10). Бывший «Ледяной след» — её второй уровень.
## 1 — каждое попадание замедляет (стак), на freeze_hits-м враг замерзает; удар-приземление по замёрзшему
##     раскалывает: двойной урон удара и осколки в соседей. 2 — полоса льда: враги скользят и падают
##     (ice_zone.gd; с 3-го уровня падение = стан 1 с — бывший ур. 2 «Ледяного следа»).
## 3 — воткнутый молот промораживает всех вокруг (стак раз в aura_interval). 4 — ледяной шип с неба: заморозка.

@export_group("1. При попадании: промерзание")
## На каком попадании враг замерзает
@export var freeze_hits: int = 3
## Сколько держится промерзание (с) и насколько замедляет каждый стак (доля скорости), не медленнее slow_min_mult
@export var chill_time: float = 3.0
@export var slow_per_stack: float = 0.25
@export var slow_min_mult: float = 0.4
@export var freeze_time: float = 2.0

@export_group("Связка: раскол замёрзших")
## Раскол — урон удара-приземления ×shatter_mult (×2 = «двойной урон»: удар + столько же сверху)
@export var shatter_mult: float = 2.0
## Осколки: соседи в радиусе получают урон и стак промерзания
@export var shard_radius: float = 3.0
@export var shard_damage: float = 11.0

@export_group("2. След: лёд на полу")
@export var trail_fall_stun: float = 0.5
@export var trail_fall_stun_lvl3: float = 1.0
@export var trail_slide_push: float = 6.0

func apply_element(enemy: Enemy, power: float, _from: Vector3, _proj: MjolnirProjectile) -> void:
	var s := ElementStatus.of(enemy, true)
	if s == null:
		return
	s.slow_per_stack = slow_per_stack
	s.slow_min_mult = slow_min_mult
	s.chill(1 if power >= 0.5 else 0, freeze_hits, chill_time, freeze_time)
	FX.sparks(enemy.get_parent(), enemy.global_position + Vector3(0, 1.0, 0), Color(0.75, 0.92, 1.0), 6, 3.0)

func make_trail_zone(parent: Node, pos: Vector3, _proj: MjolnirProjectile) -> Node3D:
	var ice := preload("res://weapons/ice_zone.gd").new()
	ice.slide_push = trail_slide_push
	parent.add_child(ice)
	ice.setup(pos, trail_radius, trail_duration, trail_fall_stun_lvl3 if level >= LVL_AURA else trail_fall_stun)
	return ice

func aura_pulse(proj: MjolnirProjectile) -> void:
	var c := proj.global_position
	var parent := proj.fx_parent()
	FX.ring(parent, c - Vector3(0, 0.3, 0), aura_radius, Color(0.6, 0.88, 1.0, 0.75), 0.3)
	FX.sparks(parent, c, Color(0.8, 0.95, 1.0), 12, 4.0)
	for e in enemies_near(proj.get_tree(), c, aura_radius):
		hurt(e, aura_damage * proj.damage_mult, Vector3.ZERO, "hammer")
		if is_instance_valid(e) and not e.is_dead:
			apply_element(e, 1.0, c, proj)

func sky_strike(point: Vector3) -> void:
	var p := player()
	var parent := p.get_parent()
	FX.lightning(parent, point + Vector3(randf_range(-1, 1), 14.0, randf_range(-1, 1)), point, 0.3, Color(0.8, 0.95, 1.0))
	FX.ice_hit(parent, point, freeze_time)
	FX.ring(parent, point, sky_radius, Color(0.6, 0.88, 1.0, 0.9), 0.35)
	for e in enemies_near(p.get_tree(), point, sky_radius + 0.9):
		hurt(e, sky_damage, Vector3.UP * 2.0, "hammer")
		var s := ElementStatus.of(e, true)
		if s:
			s.freeze(freeze_time)
	p.camera_fx.add_trauma(0.3)
	Audio.play("sounds/sfx/lightning.wav")

## Удар-приземление по замёрзшим: раскол (урон удара ×shatter_mult) и осколки в соседей
func slam_combo(power: float, center: Vector3) -> void:
	var frozen := enemies_with(center, slam_radius(power) + slam_reach, func(e: Enemy) -> bool: return ElementStatus.is_frozen(e))
	if frozen.is_empty():
		return
	mark("shatter")
	var p := player()
	var parent := p.get_parent()
	var extra := slam_damage(power) * maxf(shatter_mult - 1.0, 0.0)
	for f in frozen:
		if not is_instance_valid(f):
			continue
		var c := f.global_position
		ElementStatus.of(f).thaw()
		hurt(f, extra, Vector3.UP * 3.0, "slam")
		FX.ice_hit(parent, c, 0.6)
		FX.sparks(parent, c + Vector3(0, 1.0, 0), Color(0.85, 0.97, 1.0), 22, 8.0)
		for e in enemies_near(p.get_tree(), c + Vector3(0, 0.9, 0), shard_radius):
			if e == f:
				continue
			FX.lightning(parent, c + Vector3(0, 1.0, 0), e.global_position + Vector3(0, 1.0, 0), 0.12, Color(0.8, 0.95, 1.0))
			hurt(e, shard_damage, (e.global_position - c).normalized() * 3.0, "hammer")
			if is_instance_valid(e) and not e.is_dead:
				apply_element(e, 1.0, c, null)
	ComicFX.pop("shatter", frozen[0].global_position + Vector3(0, 1.4, 0), frozen.size() >= 2)
	StyleMeter.event(&"shatter")
	FX.hitstop(0.06)
	Audio.sfx("ice_shatter", "sounds/sfx/hammer_bounce.wav")
