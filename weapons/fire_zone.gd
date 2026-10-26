extends Node3D
## Горящая земля после удара-приземления (руна «Огонь Муспельхейма»). Урон в секунду врагам внутри радиуса.

var radius: float = 3.0
var duration: float = 2.0
var dps: float = 20.0
var _time: float = 0.0
var _tick: float = 0.0
var _mi: MeshInstance3D

func setup(pos: Vector3, radius_: float, duration_: float, dps_: float) -> void:
	Perf.mark("fire_zone")
	radius = radius_
	duration = duration_
	dps = dps_
	global_position = pos
	var mi := MeshInstance3D.new()
	_mi = mi
	mi.mesh = FX.shared_mesh("disc")
	mi.scale = Vector3(radius, 0.05, radius)
	FX.fx_apply(mi, "alpha", Color(1.0, 0.45, 0.1, 1.0), 1.4)
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
	if _mi:
		# Мерцание — прозрачностью экземпляра (материал общий для всех огней)
		_mi.transparency = 1.0 - (0.35 + 0.2 * sin(_time * 18.0))
	if _tick >= 0.25:
		_tick = 0.0
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Node3D
			if en and not e.get("is_dead") and en.global_position.distance_to(global_position) <= radius:
				en.take_hit(dps * 0.25, Vector3.ZERO, "fire")
	if _time >= duration:
		queue_free()
