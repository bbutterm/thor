extends Node3D
## Полоса льда трейта «Ледяной след»: враг, наступивший на лёд, поскальзывается и падает (короткий стан),
## каждый — один раз за пятно. Вид — общий материал эффектов (FX.fx_apply), без света.

var radius: float = 1.2
var duration: float = 4.0
## Стан при падении (ур. 2 — 1 с) и толчок скольжения
var fall_stun: float = 0.5
var slide_push: float = 6.0
var _time: float = 0.0
var _tick: float = 0.0
var _mi: MeshInstance3D
var _slipped: Dictionary = {}

func setup(pos: Vector3, radius_: float, duration_: float, fall_stun_: float) -> void:
	Perf.mark("ice_zone")
	radius = radius_
	duration = duration_
	fall_stun = fall_stun_
	global_position = pos
	_mi = MeshInstance3D.new()
	_mi.mesh = FX.shared_mesh("disc")
	_mi.scale = Vector3(radius, 0.05, radius)
	FX.fx_apply(_mi, "alpha", Color(0.55, 0.85, 1.0, 0.75), 1.1)
	_mi.position.y = 0.04
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)

func _physics_process(delta: float) -> void:
	_time += delta
	_tick += delta
	if _time >= duration:
		queue_free()
		return
	# Тает к концу
	if _mi and _time > duration - 0.6:
		_mi.transparency = clampf((_time - (duration - 0.6)) / 0.6, 0.0, 1.0)
	if _tick < 0.1:
		return
	_tick = 0.0
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en == null or en.is_dead or _slipped.has(en.get_instance_id()) or not en.is_on_floor():
			continue
		var d := en.global_position - global_position
		if absf(d.y) > 1.0 or Vector2(d.x, d.z).length() > radius:
			continue
		_slipped[en.get_instance_id()] = true
		var h := Vector3(en.velocity.x, 0, en.velocity.z)
		var dir := h.normalized() if h.length() > 0.3 else Vector3(d.x, 0, d.z).normalized()
		en.knockback_velocity += dir * slide_push
		en.apply_stun(fall_stun, true)
		FX.sparks(get_parent(), en.global_position + Vector3(0, 0.2, 0), Color(0.7, 0.9, 1.0), 8, 3.0)
