extends Node3D
class_name BrewGlob
## Плевок брагой (Толстый Свен): летит по дуге в точку на полу и растекается лужей (BrewPuddle).
## Попал в Тора на лету — немного урона и всё равно лужа под ним. Общий меш/материал эффектов.

var damage: float = 6.0
var puddle_radius: float = 1.8
var puddle_time: float = 7.0
var puddle_slow: float = 0.55
var shooter: Node = null

var _from: Vector3
var _to: Vector3
var _flight: float = 0.9
var _arc: float = 3.0
var _t: float = 0.0
var _mi: MeshInstance3D
const COLOR := Color(0.95, 0.65, 0.15)

## Запустить из from в точку на полу to за flight секунд (высота дуги arc).
static func launch(parent: Node, from: Vector3, to: Vector3, flight: float, arc: float, shooter_: Node) -> BrewGlob:
	Perf.mark("brew_glob")
	var g := BrewGlob.new()
	g._from = from
	g._to = to
	g._flight = maxf(0.2, flight)
	g._arc = arc
	g.shooter = shooter_
	parent.add_child(g)
	g.global_position = from
	return g

func _ready() -> void:
	set_meta("transient", true)
	_mi = MeshInstance3D.new()
	_mi.mesh = FX.shared_mesh("sphere")
	_mi.scale = Vector3.ONE * 0.45
	FX.fx_apply(_mi, "glow", COLOR, 2.5)
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)

func _physics_process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / _flight, 0.0, 1.0)
	var pos := _from.lerp(_to, k) + Vector3(0, sin(PI * k) * _arc, 0)
	global_position = pos
	_mi.scale = Vector3(0.45, 0.45 + 0.25 * sin(_t * 18.0), 0.45)
	var p := get_tree().get_first_node_in_group("player") as Player
	if p and not p.is_dead and k < 0.95 and (p.global_position + Vector3(0, 0.9, 0)).distance_to(pos) < 0.9:
		if is_instance_valid(shooter):
			RunTracker.note_hit(shooter)
		p.take_damage(damage, (p.global_position - pos).normalized() * 3.0)
		_splash(p.global_position)
		return
	if k >= 1.0:
		_splash(_to)

func _splash(at: Vector3) -> void:
	FX.burst(get_parent(), at + Vector3(0, 0.3, 0), 0.7, Color(COLOR, 0.6), 0.2)
	Audio.play("sounds/sfx/wall_splat.wav")
	BrewPuddle.spawn(get_parent(), at, puddle_radius, puddle_time, puddle_slow)
	queue_free()
