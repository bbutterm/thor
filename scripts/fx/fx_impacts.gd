extends RefCounted
class_name FXImpacts
## Текстурные эффекты ударов: вспышка, звезда искр, ихор и брызги, дым, взрыв, ударная волна, трещина,
## подпалина, удар-приземление, пыль бочки, блеск монеты, дым трупа.
## Модуль фасада FX (этап 5 рефакторинга): только static-функции; состояние, константы и вызовы снаружи — через FX.

## Анимированная вспышка попадания vfx_hit_flash (6 кадров за cfg().hit_flash_time).
static func hit_flash(parent: Node, pos: Vector3, size: float, color: Color = Color(1, 0.95, 0.8)) -> void:
	Perf.mark("fx_hit_flash")
	if parent == null or not parent.is_inside_tree():
		return
	var c := FXSpriteKit.cfg()
	var cam := FXSpriteKit._camera(parent)
	if cam:
		pos += (cam.global_position - pos).normalized() * c.hit_flash_push
	var mi := FXSpriteKit._sprite("hit_flash", parent, "hit_flash", pos, size, color, 1, c.hit_flash_limit, "quad", 1.4)
	FXSpriteKit._sprite_param(mi, 2, randf() * TAU)
	var tw := FXSpriteKit._tween(mi)
	FXSpriteKit._play_frames(tw, mi, int(FX.STRIPS.hit_flash), c.hit_flash_time)
	tw.tween_callback(mi.hide)

## Рисованная звезда-искра (случайная из vfx_sparks_01..12): вспыхивает, крутится, гаснет.
static func spark_star(parent: Node, pos: Vector3, color: Color, size: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var c := FXSpriteKit.cfg()
	var mi := FXSpriteKit._sprite("sparks", parent, FXSpriteKit.random_variant("sparks"), pos, size * 0.3, color.lerp(Color.WHITE, 0.25), 1, c.sparks_limit, "quad", 1.3)
	var spin0 := randf() * TAU
	FXSpriteKit._sprite_param(mi, 2, spin0)
	var tw := FXSpriteKit._tween(mi)
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, c.spark_time * 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_method(func(a: float) -> void: FXSpriteKit._sprite_param(mi, 2, a), spin0, spin0 + randf_range(-1.2, 1.2), c.spark_time)
	tw.tween_property(mi, "transparency", 1.0, c.spark_time * 0.6).set_delay(c.spark_time * 0.4)
	tw.chain().tween_callback(mi.hide)

## Брызги ихора нежити (vfx_ichor_splash_01..03): вылетают и гаснут.
static func ichor_splash(parent: Node, pos: Vector3, size: float) -> void:
	Perf.mark("fx_ichor")
	if parent == null or not parent.is_inside_tree():
		return
	var c := FXSpriteKit.cfg()
	var mi := FXSpriteKit._sprite("ichor_splash", parent, FXSpriteKit.random_variant("ichor_splash"), pos, size * 0.5, Color.WHITE, 1, c.ichor_splash_limit)
	FXSpriteKit._sprite_param(mi, 2, randf_range(-0.7, 0.7))
	var tw := FXSpriteKit._tween(mi)
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, c.ichor_splash_time * 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mi, "position", pos + Vector3(0, -0.35, 0), c.ichor_splash_time).set_ease(Tween.EASE_IN)
	tw.tween_property(mi, "transparency", 1.0, c.ichor_splash_time * 0.5).set_delay(c.ichor_splash_time * 0.5)
	tw.chain().tween_callback(mi.hide)

## Пятно ихора на полу (vfx_ichor_splat_01..03): растекается, лежит cfg().splat_life, исчезает.
## Пул cfg().splat_limit — сверх него исчезает самое старое.
static func splat(parent: Node, pos: Vector3, size: float) -> void:
	Perf.mark("fx_splat")
	if parent == null or not parent.is_inside_tree():
		return
	var c := FXSpriteKit.cfg()
	var mi := FXSpriteKit._floor_sprite("splat", parent, FXSpriteKit.random_variant("ichor_splat"), pos, size, Color.WHITE, c.splat_limit)
	if mi == null:
		return
	mi.transparency = c.splat_transparency
	var b := mi.basis
	mi.basis = b.scaled(Vector3.ONE * 0.4)
	var tw := FXSpriteKit._tween(mi)
	tw.tween_property(mi, "basis", b, 0.14).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(maxf(c.splat_life - c.splat_fade, 0.0))
	tw.tween_property(mi, "transparency", 1.0, maxf(c.splat_fade, 0.01))
	tw.tween_callback(mi.hide)

## Клуб дыма vfx_smoke (8 кадров за cfg().smoke_time): смерть, взрыв.
static func smoke(parent: Node, pos: Vector3, size: float, color: Color = Color(0.85, 0.83, 0.8)) -> void:
	Perf.mark("fx_smoke")
	if parent == null or not parent.is_inside_tree():
		return
	var c := FXSpriteKit.cfg()
	var mi := FXSpriteKit._sprite("smoke", parent, "smoke", pos, size, color, 1, c.smoke_limit)
	mi.transparency = c.smoke_transparency
	FXSpriteKit._sprite_param(mi, 2, randf_range(-0.4, 0.4))
	var tw := FXSpriteKit._tween(mi)
	tw.set_parallel(true)
	FXSpriteKit._play_frames(tw, mi, int(FX.STRIPS.smoke), c.smoke_time)
	tw.tween_property(mi, "position", pos + Vector3(0, c.smoke_rise, 0), c.smoke_time).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 1.25, c.smoke_time)
	tw.chain().tween_callback(mi.hide)

## Взрыв (enemies/blast.gd: Раздутый, элита «Взрывной», взрывная бочка, Свен): вместо плоского шара-диска —
## вспышка-ядро vfx_hit_flash, короткий огненный шар из языков vfx_fire, клубы тёмного дыма, ударная волна
## vfx_shockwave по полу на радиус урона (радиус читается), звёзды-искры. Всё — пулы и общие материалы FX.
static func explosion(parent: Node, pos: Vector3, radius: float, color: Color = Color(1.0, 0.45, 0.15)) -> void:
	Perf.mark("fx_explosion")
	if parent == null or not parent.is_inside_tree():
		return
	var c := FXSpriteKit.cfg()
	var hot := color.lerp(Color(1.0, 0.92, 0.7), 0.45)
	hit_flash(parent, pos, radius * c.explosion_flash, hot)
	var ground := pos
	var hit := FXSpriteKit._floor(FXSpriteKit._holder_for(parent), pos)
	if not hit.is_empty():
		ground = hit.position
	# Огненный шар: языки пламени вокруг центра, держатся explosion_fire_time и гаснут вместе с узлом
	if c.explosion_fire_time > 0.0:
		var ball := Node3D.new()
		ball.name = "ExplosionFire"
		ball.set_meta("transient", true)
		parent.add_child(ball)
		ball.global_position = ground
		ball.scale = Vector3.ONE * c.explosion_fire_scale
		FXElements.fire_sprites(ball, maxf(radius * c.explosion_fire, 0.4), c.explosion_fire_time)
		var tw := ball.create_tween()
		tw.tween_property(ball, "scale", Vector3.ONE * c.explosion_fire_scale * 1.25, c.explosion_fire_time).set_ease(Tween.EASE_OUT)
		tw.tween_interval(c.fire_fade + 0.1)
		tw.tween_callback(ball.queue_free)
	for i in maxi(c.explosion_smoke, 0):
		var a := TAU * float(i) / maxf(c.explosion_smoke, 1) + randf_range(-0.5, 0.5)
		var off := Vector3(cos(a), randf_range(0.1, 0.5), sin(a)) * radius * 0.35
		smoke(parent, pos + off, radius * c.explosion_smoke_size * randf_range(0.85, 1.15), c.explosion_smoke_color)
	shockwave(parent, ground, radius, hot)
	for i in maxi(c.explosion_stars, 0):
		var off2 := Vector3(randf_range(-1, 1), randf_range(-0.3, 0.8), randf_range(-1, 1)) * radius * 0.3
		spark_star(parent, pos + off2, hot, c.explosion_star_size * randf_range(0.8, 1.2))

## Дым взрыва (enemies/blast.gd): размер от радиуса.
static func blast_smoke(parent: Node, pos: Vector3, radius: float) -> void:
	var c := FXSpriteKit.cfg()
	smoke(parent, pos, c.smoke_size + radius * c.smoke_per_radius, Color(0.7, 0.66, 0.62))

## Пыль разбитой бочки (run/barrel_watch.gd): дым коричневатого оттенка.
static func barrel_dust(parent: Node, pos: Vector3) -> void:
	smoke(parent, pos, FXSpriteKit.cfg().barrel_dust_size, Color(0.78, 0.64, 0.48))

## Блеск монеты серебра при вылете (run/silver_coin.gd): звёздочка vfx_sparks_*, не чаще cfg().coin_glint_interval.
static func coin_glint(parent: Node, pos: Vector3, color: Color) -> void:
	var c := FXSpriteKit.cfg()
	var now := Time.get_ticks_msec()
	if now - FX._last_glint_ms < int(c.coin_glint_interval * 1000.0) or c.coin_glint_size <= 0.0:
		return
	FX._last_glint_ms = now
	spark_star(parent, pos + Vector3(0, 0.15, 0), color, c.coin_glint_size)

## «Пуф» исчезающего трупа (enemies/parts/enemy_visual.gd → _spawn_debris, когда тело сжимается).
static func corpse_smoke(body: Node3D) -> void:
	if body and is_instance_valid(body) and body.is_inside_tree():
		smoke(body.get_parent(), body.global_position + Vector3(0, 0.5, 0), FXSpriteKit.cfg().smoke_size * 0.8)

## Ударная волна vfx_shockwave по полу: кольцо растёт до радиуса удара и гаснет.
static func shockwave(parent: Node, pos: Vector3, radius: float, color: Color = Color(1.0, 0.92, 0.75)) -> void:
	Perf.mark("fx_shockwave")
	if parent == null or not parent.is_inside_tree():
		return
	var c := FXSpriteKit.cfg()
	var mi := FXSpriteKit._floor_sprite("shockwave", parent, "shockwave", pos, 1.0, color, c.shockwave_limit, 1.5)
	if mi == null:
		return
	var b := mi.basis.orthonormalized()
	mi.basis = b.scaled(Vector3.ONE * radius * 0.3)
	mi.transparency = c.shockwave_transparency
	var tw := FXSpriteKit._tween(mi)
	tw.set_parallel(true)
	tw.tween_property(mi, "basis", b.scaled(Vector3.ONE * radius * c.shockwave_scale), c.shockwave_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mi, "transparency", 1.0, c.shockwave_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(mi.hide)

## Трещина на полу (vfx_crack_decal_small/medium/large — по высоте падения), лежит cfg().crack_life.
static func crack(parent: Node, pos: Vector3, height: float) -> void:
	Perf.mark("fx_crack")
	if parent == null or not parent.is_inside_tree():
		return
	var c := FXSpriteKit.cfg()
	var key := "crack_decal_small"
	var size := c.crack_sizes.x
	if height >= c.crack_large_height:
		key = "crack_decal_large"
		size = c.crack_sizes.z
	elif height >= c.crack_medium_height:
		key = "crack_decal_medium"
		size = c.crack_sizes.y
	var mi := FXSpriteKit._floor_sprite("crack", parent, key, pos, size, Color.WHITE, c.crack_limit)
	if mi == null:
		return
	mi.set_meta("crack", key)
	var tw := FXSpriteKit._tween(mi)
	tw.tween_interval(maxf(c.crack_life - c.crack_fade, 0.0))
	tw.tween_property(mi, "transparency", 1.0, maxf(c.crack_fade, 0.01))
	tw.tween_callback(mi.hide)

## Подпалина на полу (assets/decals/scorch): след огня (fire_zone.gd) и взрыва (blast.gd). Лежит, пока горит огонь
## (burn), и ещё cfg().scorch_life, потом исчезает. Пул cfg().scorch_limit — сверх него исчезает самая старая.
static func scorch(parent: Node, pos: Vector3, radius: float, burn: float = 0.0) -> void:
	Perf.mark("fx_scorch")
	if parent == null or not parent.is_inside_tree():
		return
	var c := FXSpriteKit.cfg()
	if c.scorch_limit <= 0:
		return
	var size := clampf(radius * c.scorch_per_radius, c.scorch_size.x, c.scorch_size.y)
	var mi := FXSpriteKit._floor_sprite("scorch", parent, "scorch", pos, size, Color.WHITE, c.scorch_limit)
	if mi == null:
		return
	mi.transparency = c.scorch_transparency
	var tw := FXSpriteKit._tween(mi)
	tw.tween_interval(maxf(burn + c.scorch_life - c.scorch_fade, 0.0))
	tw.tween_property(mi, "transparency", 1.0, maxf(c.scorch_fade, 0.01))
	tw.tween_callback(mi.hide)

## Удар-приземление (player.gd → _do_slam_impact): волна по радиусу удара и трещина по высоте падения.
static func slam_impact(parent: Node, center: Vector3, radius: float, height: float) -> void:
	shockwave(parent, center, radius)
	crack(parent, center, height)
