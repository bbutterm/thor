extends Area3D
class_name JumpPad
## Прыжковая руна (GDD 7.2): светящийся круг на полу подбрасывает Тора на height метров.
## Ставит генератор (ключ "jump_pads" у зала); вид собирается при запуске из общих мешей/материалов FX.

## Высота подброса (м), GDD: 8–12
@export var height: float = 9.0
@export var radius: float = 1.2
## Повторно не срабатывает раньше (с)
@export var cooldown: float = 0.4
@export var color: Color = Color(0.45, 0.85, 1.0)

var _cd: float = 0.0
var _glow: MeshInstance3D
var _ring: MeshInstance3D
var _t: float = 0.0

func _ready() -> void:
	add_to_group("jump_pads")
	if get_child_count() > 0:
		return
	collision_layer = 1 << 5
	collision_mask = 1 << 1
	monitoring = true
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = 0.6
	cs.shape = sh
	cs.position.y = 0.3
	add_child(cs)
	_glow = MeshInstance3D.new()
	_glow.mesh = FX.shared_mesh("disc")
	_glow.scale = Vector3(radius, 0.05, radius)
	_glow.position.y = 0.03
	FX.fx_apply(_glow, "alpha", Color(color, 0.55), 1.6)
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)
	_ring = MeshInstance3D.new()
	_ring.mesh = FX.shared_mesh("ring")
	_ring.scale = Vector3(radius, 0.4, radius)
	_ring.position.y = 0.06
	FX.fx_apply(_ring, "glow", color, 2.5)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	body_entered.connect(_on_body)

func _physics_process(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	_t += delta
	# Кольцо «дышит» — видно издалека
	if _ring:
		var k := 1.0 + 0.08 * sin(_t * 4.0)
		_ring.scale = Vector3(radius * k, 0.4, radius * k)
	if _cd <= 0.0:
		for b in get_overlapping_bodies():
			_on_body(b)

func _on_body(b: Node) -> void:
	if _cd > 0.0 or not (b is Player):
		return
	var p := b as Player
	if p.is_dead or p.velocity.y > 4.0:
		return
	_cd = cooldown
	p.launch_up(height)
	Perf.mark("jump_pad")
	FX.ring(get_parent(), global_position + Vector3(0, 0.1, 0), radius * 1.8, Color(color, 0.9), 0.35)
	FX.sparks(get_parent(), global_position + Vector3(0, 0.3, 0), color, 14, 6.0)
	Audio.play("sounds/sfx/hammer_throw.wav")
