extends RefCounted
class_name FX
## Общие эффекты «сочности»: hit-stop, всплывающий урон, вспышки, линии молний.

static var _hitstop_left: float = 0.0
static var _hitstop_scale: float = 1.0
## Кадр, в котором последний раз менялся Engine.time_scale, и масштаб, бывший до этого в начале кадра
static var _scale_frame: int = -1
static var _scale_before: float = 1.0

static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

## Замедление времени на долю секунды при попадании.
## Отсчёт идёт в реальном времени через FX.tick() из автозагрузки Run.
static func hitstop(duration: float, scale: float = 0.05) -> void:
	if duration <= 0.0:
		return
	_hitstop_left = maxf(_hitstop_left, duration)
	_hitstop_scale = minf(_hitstop_scale, scale) if _hitstop_left > 0.0 else scale
	_set_time_scale(_hitstop_scale)

## Вызывается каждый кадр. Run передаёт delta / текущий time_scale; пересчитываем по масштабу,
## с которым движок на самом деле умножил delta этого кадра (см. real_delta).
static func tick(passed_real_delta: float) -> void:
	if _hitstop_left <= 0.0:
		return
	_hitstop_left -= real_delta(passed_real_delta * maxf(Engine.time_scale, 0.0001))
	if _hitstop_left <= 0.0:
		_hitstop_left = 0.0
		_hitstop_scale = 1.0
		_set_time_scale(1.0)

## Реальная длительность кадра по delta из _process. Движок умножает delta на time_scale, каким он был
## В НАЧАЛЕ кадра; удары (и hit-stop) случаются в физике этого же кадра. Если делить на новый 0.05,
## первый же тик насчитывал 1/60 / 0.05 = 0.33 с и стоп заканчивался в кадре, где начался.
static func real_delta(scaled_delta: float) -> float:
	var s := _scale_before if Engine.get_process_frames() == _scale_frame else Engine.time_scale
	return scaled_delta / maxf(s, 0.0001)

static func _set_time_scale(s: float) -> void:
	var f := Engine.get_process_frames()
	if f != _scale_frame:
		_scale_frame = f
		_scale_before = Engine.time_scale
	Engine.time_scale = s

static func reset_time() -> void:
	_hitstop_left = 0.0
	_hitstop_scale = 1.0
	_set_time_scale(1.0)

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

## Ломаная линия молнии между точками, гаснет за lifetime.
static func lightning(parent: Node, from: Vector3, to: Vector3, lifetime: float = 0.25, color: Color = Color(0.55, 0.85, 1.0)) -> void:
	Perf.mark("fx_lightning")
	if parent == null or not parent.is_inside_tree():
		return
	var mesh := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	fx_apply(mi, "alpha", color, 2.5)
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
	tw.tween_property(mi, "transparency", 1.0, lifetime)
	tw.tween_callback(mi.queue_free)

## Вспышка-шар (удар, приземление).
static func burst(parent: Node, pos: Vector3, radius: float, color: Color, lifetime: float = 0.3) -> void:
	Perf.mark("fx_burst")
	if parent == null or not parent.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = shared_mesh("sphere")
	fx_apply(mi, "alpha_nocull", color)
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
	mi.mesh = shared_mesh("ring")
	fx_apply(mi, "alpha", color)
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
	p.mesh = shared_mesh("box")
	fx_apply(p, "unshaded", color)
	if _shrink_curve == null:
		_shrink_curve = Curve.new()
		_shrink_curve.add_point(Vector2(0, 1))
		_shrink_curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = _shrink_curve
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

static var _fx_mats: Dictionary = {}
static var _meshes: Dictionary = {}
static var _shrink_curve: Curve

const FX_SHADERS := {
	"unshaded": preload("res://shaders/fx_unshaded.gdshader"),
	"alpha": preload("res://shaders/fx_alpha.gdshader"),
	"alpha_nocull": preload("res://shaders/fx_alpha_nocull.gdshader"),
	"glow": preload("res://shaders/fx_glow.gdshader"),
}

## Общий материал эффекта. Новый материал на каждую вспышку — это компиляция пайплайна при каждом
## эффекте (замерено на Forward+). Поэтому на вид эффекта — один материал, цвет и яркость задаются
## на экземпляре (fx_apply), затухание — через GeometryInstance3D.transparency.
## Виды: "unshaded", "alpha", "alpha_nocull", "glow" (освещённый, светится).
static func fx_material(kind: String) -> ShaderMaterial:
	if _fx_mats.has(kind):
		return _fx_mats[kind]
	var m := ShaderMaterial.new()
	m.shader = FX_SHADERS[kind]
	_fx_mats[kind] = m
	return m

## Назначить эффекту общий материал вида kind и задать цвет/яркость экземпляра.
static func fx_apply(gi: GeometryInstance3D, kind: String, color: Color, energy: float = 1.0) -> void:
	gi.material_override = fx_material(kind)
	gi.set_instance_shader_parameter("color", color)
	gi.set_instance_shader_parameter("energy", energy)

## Общие меши эффектов единичного размера (масштабируются узлом) — не строим примитив на каждую вспышку.
static func shared_mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m: Mesh
	match kind:
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 16
			sm.rings = 8
			m = sm
		"ring":
			var tm := TorusMesh.new()
			tm.inner_radius = 0.85
			tm.outer_radius = 1.0
			tm.rings = 32
			tm.ring_segments = 6
			m = tm
		"box":
			m = BoxMesh.new()
		"disc":
			# Плоский диск радиуса 1 (огонь на земле, телеграф босса) — масштабируется по X/Z
			var cm := CylinderMesh.new()
			cm.top_radius = 1.0
			cm.bottom_radius = 1.0
			cm.height = 1.0
			cm.radial_segments = 32
			cm.rings = 1
			m = cm
	_meshes[kind] = m
	return m
