extends RefCounted
class_name FXBasic
## Процедурные эффекты: цифры урона, молния, вспышка-сфера, кольцо, искры, материал-заглушка.
## Модуль фасада FX (этап 5 рефакторинга): только static-функции; состояние, константы и вызовы снаружи — через FX.

## Всплывающая цифра урона в мире.
static func damage_number(parent: Node, pos: Vector3, amount: float, color: Color = Color(1, 0.9, 0.3), big: bool = false) -> void:
	Perf.mark("fx_damage_number")
	if parent == null or not parent.is_inside_tree():
		return
	var label := Label3D.new()
	label.text = str(int(round(amount)))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0018 if big else 0.0013
	label.font_size = 48
	label.outline_size = 12
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 0.8)
	var font: Font = load("res://fonts/RussoOne-Regular.ttf")
	if font:
		label.font = font
	parent.add_child(label)
	label.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.3, 0.3))
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "global_position", label.global_position + Vector3(0, 1.2, 0), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(label.queue_free)

## Молния между точками: текстурные ленты vfx_lightning_01..04 (по отрезку на cfg().lightning_segment м,
## каждая повёрнута к камере вокруг своей оси) и тонкая ломаная-сердцевина. Гаснет за lifetime с мерцанием.
static func lightning(parent: Node, from: Vector3, to: Vector3, lifetime: float = 0.25, color: Color = Color(0.55, 0.85, 1.0)) -> void:
	Perf.mark("fx_lightning")
	if parent == null or not parent.is_inside_tree():
		return
	var c := FXSpriteKit.cfg()
	if c.lightning_core_alpha > 0.0:
		var mesh := ImmediateMesh.new()
		var mi := MeshInstance3D.new()
		FXShared.fx_apply(mi, "alpha", color, 2.5)
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		mi.global_transform = Transform3D.IDENTITY
		mi.transparency = 1.0 - c.lightning_core_alpha
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var segments := 8
		var prev := from
		for i in range(1, segments + 1):
			var t := float(i) / segments
			var p := from.lerp(to, t)
			if i < segments:
				p += Vector3(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35), randf_range(-0.35, 0.35))
			mesh.surface_add_vertex(prev)
			mesh.surface_add_vertex(p)
			prev = p
		mesh.surface_end()
		var tw := mi.create_tween()
		tw.tween_property(mi, "transparency", 1.0, lifetime)
		tw.tween_callback(mi.queue_free)
	FXElements._lightning_ribbons(parent, from, to, lifetime, color)

## Вспышка-шар (удар, приземление).
static func burst(parent: Node, pos: Vector3, radius: float, color: Color, lifetime: float = 0.3) -> void:
	Perf.mark("fx_burst")
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = FXShared.shared_mesh("sphere")
	FXShared.fx_apply(mi, "alpha_nocull", color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 2.0, lifetime).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(mi, "transparency", 1.0, lifetime)
	tw.chain().tween_callback(mi.queue_free)

## Плоское кольцо на земле (волна удара-приземления, телеграф босса).
static func ring(parent: Node, pos: Vector3, radius: float, color: Color, lifetime: float = 0.35) -> void:
	Perf.mark("fx_ring")
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = FXShared.shared_mesh("ring")
	FXShared.fx_apply(mi, "alpha", color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.08, 0)
	mi.scale = Vector3(0.3, 0.15, 0.3)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.15, radius), lifetime).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mi, "transparency", 1.0, lifetime)
	tw.chain().tween_callback(mi.queue_free)

## Разлёт частиц: искры от ударов, пыль от приземления, щепки.
static func sparks(parent: Node, pos: Vector3, color: Color, amount: int = 14, speed: float = 6.0, gravity: float = 14.0, size: float = 0.07, lifetime: float = 0.45) -> void:
	Perf.mark("fx_sparks")
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = 0.6 * size
	p.scale_amount_max = 1.2 * size
	p.mesh = FXShared.shared_mesh("box")
	FXShared.fx_apply(p, "unshaded", color)
	if FX._shrink_curve == null:
		FX._shrink_curve = Curve.new()
		FX._shrink_curve.add_point(Vector2(0, 1))
		FX._shrink_curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = FX._shrink_curve
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := p.get_tree().create_timer(lifetime + 0.3, true, false, true)
	t.timeout.connect(p.queue_free)
	# Рисованные звёзды vfx_sparks_* поверх частиц — только у ярких искр (не у пыли и щепок)
	var cf := FXSpriteKit.cfg()
	if color.get_luminance() >= cf.spark_min_luma and cf.sparks_max > 0:
		var n := clampi(amount / maxi(cf.sparks_per_star, 1), 1, cf.sparks_max)
		var k := clampf(size / 0.07, 0.6, 1.5)
		for i in n:
			var off := Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)) * cf.spark_spread * k
			FXImpacts.spark_star(parent, pos + off, color, randf_range(cf.spark_size.x, cf.spark_size.y) * k)

static func make_material(color: Color, roughness: float = 0.85, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m
