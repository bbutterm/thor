extends MjolnirElementHandler
## Стихия «Ветер» (блок Б4, GDD 10, новая). Сильно отбрасывает: сбивает с краёв и балконов, бросает о стены
## (шмяк и падение с высоты — enemies/parts/enemy_motion.gd: _check_wall_splat, _check_fall, GDD 8).
## 1 — попадание отбрасывает вдоль полёта молота; удар-приземление — вихрь: всех вокруг сносит наружу.
## 2 — след: порывы вдоль полёта сдувают наступивших. 3 — воткнутый молот отталкивает всех вокруг.
## 4 — смерч с неба при идеальном хвате: подбрасывает врагов в точке прицела.

@export_group("1. При попадании: отбросить")
## Добавка к отбрасыванию молота (по горизонтали и вверх), м/с
@export var knockback: float = 16.0
@export var lift: float = 5.0
## Боссов сдувает слабее
@export var boss_factor: float = 0.3

@export_group("Связка: вихрь удара-приземления")
@export var gust_radius_mult: float = 1.6
@export var gust_knockback: float = 18.0
@export var gust_lift: float = 6.0
@export var gust_damage: float = 5.0

@export_group("2. След: порывы")
@export var trail_push: float = 9.0
@export var trail_lift: float = 3.0

@export_group("3. Аура: отталкивание")
@export var aura_push: float = 11.0

@export_group("4. Смерч с неба")
@export var sky_lift: float = 11.0

const WIND := Color(0.85, 0.95, 0.9)

func _factor(e: Enemy) -> float:
	return boss_factor if e.kind == Enemy.Kind.BOSS else 1.0

func apply_element(enemy: Enemy, power: float, from: Vector3, proj: MjolnirProjectile) -> void:
	var dir := Vector3.ZERO
	if proj and proj.vel.length() > 0.1:
		dir = Vector3(proj.vel.x, 0, proj.vel.z)
	if dir.length() < 0.01:
		dir = enemy.global_position - from
		dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var f := _factor(enemy) * power
	push_enemy(enemy, dir * knockback * f + Vector3.UP * lift * f)
	FX.smoke(enemy.get_parent(), enemy.global_position + Vector3(0, 0.8, 0), 1.0, Color(WIND, 0.8))
	if power >= 1.0:
		ComicFX.pop("gust", enemy.global_position + Vector3(0, 1.4, 0))

func make_trail_zone(parent: Node, pos: Vector3, proj: MjolnirProjectile) -> Node3D:
	var z := ElementZone.new()
	parent.add_child(z)
	z.dir = Vector3(proj.vel.x, 0, proj.vel.z).normalized() if proj and proj.vel.length() > 0.1 else Vector3.FORWARD
	z.setup(pos, trail_radius * 1.2, trail_duration, Color(WIND, 0.45), _trail_gust, true, 0.1)
	return z

func _trail_gust(enemy: Enemy, zone: ElementZone) -> void:
	# Сдувает поперёк следа, от его оси (иначе вдоль следа враг просто «уезжает» в ту же полосу)
	var side := zone.dir.cross(Vector3.UP)
	var off := enemy.global_position - zone.global_position
	if side.dot(off) < 0.0:
		side = -side
	push_enemy(enemy, (side + zone.dir * 0.5).normalized() * trail_push * _factor(enemy) + Vector3.UP * trail_lift)
	FX.smoke(enemy.get_parent(), enemy.global_position + Vector3(0, 0.5, 0), 0.8, Color(WIND, 0.7))

func aura_pulse(proj: MjolnirProjectile) -> void:
	var c := proj.global_position
	var parent := proj.fx_parent()
	FX.ring(parent, c - Vector3(0, 0.3, 0), aura_radius, Color(WIND, 0.6), 0.35)
	for e in enemies_near(proj.get_tree(), c, aura_radius):
		var dir := e.global_position - c
		dir.y = 0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
		hurt(e, aura_damage * proj.damage_mult, Vector3.ZERO, "hammer")
		if is_instance_valid(e) and not e.is_dead:
			push_enemy(e, dir * aura_push * _factor(e) + Vector3.UP * 2.0)
	FX.smoke(parent, c, 1.6, Color(WIND, 0.6))

func sky_strike(point: Vector3) -> void:
	var p := player()
	var parent := p.get_parent()
	FX.ring(parent, point, sky_radius, Color(WIND, 0.9), 0.4)
	for i in 4:
		FX.smoke(parent, point + Vector3(0, 0.6 + i * 1.1, 0), 1.4 + i * 0.5, Color(WIND, 0.85))
	for e in enemies_near(p.get_tree(), point, sky_radius + 0.9):
		hurt(e, sky_damage, Vector3.ZERO, "hammer")
		if is_instance_valid(e) and not e.is_dead:
			var to := point - e.global_position
			to.y = 0
			push_enemy(e, to * 1.5 * _factor(e) + Vector3.UP * sky_lift * _factor(e))
	ComicFX.pop("gust", point + Vector3(0, 1.5, 0), true)
	p.camera_fx.add_trauma(0.25)
	Audio.sfx("wind_gust", "sounds/sfx/dash.wav")

## Удар-приземление: вихрь — всех в радиусе удара ×gust_radius_mult сносит наружу (в стены, с краёв)
func slam_combo(power: float, center: Vector3) -> void:
	var p := player()
	if p == null:
		return
	var r := slam_radius(power) * gust_radius_mult
	var any := false
	for e in enemies_near(p.get_tree(), center + Vector3(0, 0.9, 0), r):
		var dir := e.global_position - center
		dir.y = 0
		var d := dir.length()
		dir = dir / d if d > 0.01 else Vector3.FORWARD
		var falloff := clampf(1.0 - d / r, 0.5, 1.0)
		hurt(e, gust_damage, Vector3.ZERO, "slam")
		if is_instance_valid(e) and not e.is_dead:
			push_enemy(e, dir * gust_knockback * falloff * _factor(e) + Vector3.UP * gust_lift * falloff)
			any = true
	var parent := p.get_parent()
	FX.ring(parent, center, r, Color(WIND, 0.85), 0.45)
	for i in 6:
		var a := TAU * i / 6.0
		FX.smoke(parent, center + Vector3(cos(a) * r * 0.5, 0.4, sin(a) * r * 0.5), 1.2, Color(WIND, 0.75))
	if any:
		mark("gust")
		ComicFX.pop("gust", center + Vector3(0, 1.2, 0), true)
		StyleMeter.event(&"element_slam")
	Audio.sfx("wind_gust", "sounds/sfx/dash.wav")

## Ветер: вихрь дыма и кольцо порыва
func hit_signature(enemy: Enemy, proj: MjolnirProjectile, chest: Vector3) -> void:
	var parent := proj.fx_parent()
	FX.smoke(parent, chest, 1.6, Color(element_color(), 0.75))
	FX.shockwave(parent, enemy.global_position + Vector3(0, 0.1, 0), 2.2, element_color())
