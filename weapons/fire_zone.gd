extends Node3D
## Горящая земля после удара-приземления (руна «Огонь Муспельхейма»). Урон в секунду врагам внутри радиуса.

var radius: float = 3.0
var duration: float = 2.0
var dps: float = 20.0
## Враждебный огонь (элита «Огненный»): жжёт Тора на земле, а не врагов
var hostile: bool = false
var source_node: Node = null
var _time: float = 0.0
var _tick: float = 0.0
var _mi: MeshInstance3D

## with_light = false — без источника света (много мелких зон «Огненного следа»)
func setup(pos: Vector3, radius_: float, duration_: float, dps_: float, with_light: bool = true) -> void:
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
	if not with_light:
		return
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
	if _tick >= 0.25 and hostile:
		_tick = 0.0
		var p := get_tree().get_first_node_in_group("player") as Player
		if p and not p.is_dead and p.is_on_floor() and absf(p.global_position.y - global_position.y) < 1.0 \
				and Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length() <= radius:
			RunTracker.note_hit(source_node if is_instance_valid(source_node) else null, "draugr_warrior")
			p.take_damage(dps * 0.25)
	elif _tick >= 0.25:
		_tick = 0.0
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Node3D
			if en and not e.get("is_dead") and en.global_position.distance_to(global_position) <= radius:
				en.take_hit(dps * 0.25, Vector3.ZERO, "fire")
	if _time >= duration:
		queue_free()
