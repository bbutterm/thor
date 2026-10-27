extends Node3D
class_name ElementZone
## Пятно стихии на полу (след молота, блок Б4): молния — «под током», земля — разлом, ветер — порыв.
## Огонь и лёд используют свои зоны (fire_zone.gd, ice_zone.gd). Что делать с врагом внутри — Callable
## обработчика стихии (on_enemy(enemy, zone)), раз в tick или один раз на врага (once).
## Вид — общий диск и общий материал эффектов (FX.fx_apply "alpha", цвет per-instance), без света.

var radius: float = 1.2
var duration: float = 3.0
var tick: float = 0.25
var once: bool = false
## Мерцание (молния) вместо ровного свечения
var flicker: bool = false
## Направление следа (ветер толкает вдоль него)
var dir: Vector3 = Vector3.FORWARD
var on_enemy: Callable
var _time: float = 0.0
var _tick: float = 0.0
var _mi: MeshInstance3D
var _done: Dictionary = {}
var _alpha: float = 0.7

func setup(pos: Vector3, radius_: float, duration_: float, color: Color, callback: Callable, once_: bool = false, tick_: float = 0.25) -> void:
	Perf.mark("element_zone")
	radius = radius_
	duration = duration_
	on_enemy = callback
	once = once_
	tick = tick_
	_alpha = color.a
	global_position = pos
	set_meta("transient", true)
	_mi = MeshInstance3D.new()
	_mi.mesh = FX.shared_mesh("disc")
	_mi.scale = Vector3(radius, 0.05, radius)
	FX.fx_apply(_mi, "alpha", Color(color, 1.0), 1.3)
	_mi.position.y = 0.045
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.transparency = 1.0 - _alpha
	add_child(_mi)

func _physics_process(delta: float) -> void:
	_time += delta
	_tick += delta
	if _time >= duration:
		queue_free()
		return
	if _mi:
		var a := _alpha
		if flicker:
			a *= 0.55 + 0.45 * absf(sin(_time * 23.0 + sin(_time * 7.0) * 3.0))
		if _time > duration - 0.5:
			a *= clampf((duration - _time) / 0.5, 0.0, 1.0)
		_mi.transparency = 1.0 - a
	if _tick < tick:
		return
	_tick = 0.0
	if not on_enemy.is_valid():
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en == null or en.is_dead:
			continue
		var d := en.global_position - global_position
		if absf(d.y) > 1.2 or Vector2(d.x, d.z).length() > radius:
			continue
		if once:
			if _done.has(en.get_instance_id()):
				continue
			_done[en.get_instance_id()] = true
		on_enemy.call(en, self)
