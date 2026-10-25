extends Node3D
## Горящая земля после удара-приземления (руна «Огонь Муспельхейма»). Урон в секунду врагам внутри радиуса.

var radius: float = 3.0
var duration: float = 2.0
var dps: float = 20.0
var _time: float = 0.0
var _tick: float = 0.0
var _mat: StandardMaterial3D

func setup(pos: Vector3, radius_: float, duration_: float, dps_: float) -> void:
	radius = radius_
	duration = duration_
	dps = dps_
	global_position = pos
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.05
	mi.mesh = cyl
	_mat = FX.make_material(Color(1.0, 0.45, 0.1, 0.55), 1.0, 2.5)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = _mat
	mi.position.y = 0.05
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.5, 0.15)
	light.light_energy = 2.0
	light.omni_range = radius * 1.5
	light.position.y = 0.6
	add_child(light)

func _physics_process(delta: float) -> void:
	_time += delta
	_tick += delta
	if _mat:
		_mat.albedo_color.a = 0.35 + 0.2 * sin(_time * 18.0)
	if _tick >= 0.25:
		_tick = 0.0
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Node3D
			if en and not e.get("is_dead") and en.global_position.distance_to(global_position) <= radius:
				en.take_hit(dps * 0.25, Vector3.ZERO, "fire")
	if _time >= duration:
		queue_free()
