extends Node3D
class_name SilverCoin
## Монета серебра: вылетает, падает на пол, через миг магнитом летит к Тору (GDD 15.2).
## Общий меш (диск) и общий материал эффектов — без новых материалов на монету.

const COLOR := Color(0.86, 0.9, 1.0)

var value: int = 1
var _vel: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _ground_y: float = -INF
var _homing: bool = false
var _speed: float = 0.0
var _mesh: MeshInstance3D

func _ready() -> void:
	set_meta("transient", true)
	add_to_group("silver_coins")
	_mesh = MeshInstance3D.new()
	_mesh.mesh = FX.shared_mesh("disc")
	FX.fx_apply(_mesh, "glow", COLOR, 1.4)
	_mesh.scale = Vector3(0.14, 0.03, 0.14)
	_mesh.rotation_degrees.x = 80.0
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

## Вылет из точки pos (вызывать после add_child).
func launch(pos: Vector3) -> void:
	global_position = pos
	var c := Silver.cfg()
	var a := randf() * TAU
	_vel = Vector3(cos(a), 0, sin(a)) * randf_range(0.4, 1.0) * c.coin_spread_speed + Vector3.UP * c.coin_up_speed * randf_range(0.8, 1.2)
	_ground_y = Loot.floor_point(self, pos).y + 0.12

func _physics_process(delta: float) -> void:
	var c := Silver.cfg()
	_age += delta
	_mesh.rotation.y += delta * 6.0
	var p := _player()
	if p == null:
		return
	var target := p.global_position + Vector3(0, 0.9, 0)
	var to := target - global_position
	if not _homing and _age >= c.magnet_delay and not p.is_dead and (to.length() <= c.magnet_radius or _age >= c.magnet_any_after):
		_homing = true
		_speed = c.magnet_speed_start
	if _homing:
		_speed = minf(c.magnet_speed_max, _speed + c.magnet_accel * delta)
		if to.length() <= c.collect_radius or to.length() <= _speed * delta:
			_collect()
			return
		global_position += to.normalized() * _speed * delta
		return
	# Свободный полёт и падение на пол
	_vel.y -= c.coin_gravity * delta
	global_position += _vel * delta
	if global_position.y <= _ground_y and _vel.y < 0.0:
		global_position.y = _ground_y
		_vel = Vector3(_vel.x * 0.4, -_vel.y * 0.25 if absf(_vel.y) > 2.0 else 0.0, _vel.z * 0.4)

func _player() -> Player:
	var tree := get_tree()
	return tree.get_first_node_in_group("player") as Player if tree else null

static var _last_sound_ms: int = 0

func _collect() -> void:
	Perf.mark("silver_pickup")
	Run.add_silver(value)
	# Звон не чаще раза в 60 мс (монеты прилетают пачкой)
	var now := Time.get_ticks_msec()
	if now - _last_sound_ms > 60:
		_last_sound_ms = now
		Audio.play("sounds/sfx/coin_pickup.wav")
	queue_free()
