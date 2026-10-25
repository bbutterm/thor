extends RefCounted
class_name FX
## Общие эффекты «сочности»: hit-stop, всплывающий урон, вспышки, линии молний.

static var _hitstop_left: float = 0.0
static var _hitstop_scale: float = 1.0

static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

## Замедление времени на долю секунды при попадании.
## Отсчёт идёт в реальном времени через FX.tick() из автозагрузки Run.
static func hitstop(duration: float, scale: float = 0.05) -> void:
	if duration <= 0.0:
		return
	_hitstop_left = maxf(_hitstop_left, duration)
	_hitstop_scale = minf(_hitstop_scale, scale) if _hitstop_left > 0.0 else scale
	Engine.time_scale = _hitstop_scale

## Вызывается каждый кадр с НЕмасштабированной дельтой.
static func tick(real_delta: float) -> void:
	if _hitstop_left <= 0.0:
		return
	_hitstop_left -= real_delta
	if _hitstop_left <= 0.0:
		_hitstop_left = 0.0
		_hitstop_scale = 1.0
		Engine.time_scale = 1.0

static func reset_time() -> void:
	_hitstop_left = 0.0
	_hitstop_scale = 1.0
	Engine.time_scale = 1.0

## Всплывающая цифра урона в мире.
static func damage_number(parent: Node, pos: Vector3, amount: float, color: Color = Color(1, 0.9, 0.3), big: bool = false) -> void:
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

## Ломаная линия молнии между точками, гаснет за lifetime.
static func lightning(parent: Node, from: Vector3, to: Vector3, lifetime: float = 0.25, color: Color = Color(0.55, 0.85, 1.0)) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mesh := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
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
	tw.tween_property(mat, "albedo_color:a", 0.0, lifetime)
	tw.tween_callback(mi.queue_free)

## Вспышка-шар (удар, приземление).
static func burst(parent: Node, pos: Vector3, radius: float, color: Color, lifetime: float = 0.3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 2.0, lifetime).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(mat, "albedo_color:a", 0.0, lifetime)
	tw.chain().tween_callback(mi.queue_free)

## Плоское кольцо на земле (волна удара-приземления, телеграф босса).
static func ring(parent: Node, pos: Vector3, radius: float, color: Color, lifetime: float = 0.35) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	mi.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.08, 0)
	mi.scale = Vector3(0.3, 0.15, 0.3)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 0.15, radius), lifetime).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, lifetime)
	tw.chain().tween_callback(mi.queue_free)

## Разлёт частиц: искры от ударов, пыль от приземления, щепки.
static func sparks(parent: Node, pos: Vector3, color: Color, amount: int = 14, speed: float = 6.0, gravity: float = 14.0, size: float = 0.07, lifetime: float = 0.45) -> void:
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
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = false
	mesh.material = mat
	p.mesh = mesh
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := p.get_tree().create_timer(lifetime + 0.3, true, false, true)
	t.timeout.connect(p.queue_free)

static func make_material(color: Color, roughness: float = 0.85, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m
