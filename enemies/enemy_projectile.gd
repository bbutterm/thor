extends Area3D
## Медленный снаряд метателя (сгусток проклятья). Топор отбивает его обратно — тогда он бьёт врагов.

var vel: Vector3 = Vector3.ZERO
var damage: float = 10.0
var reflected: bool = false
var shooter: Node = null
var _life: float = 0.0
var _mi: MeshInstance3D
var _color: Color = Color(0.7, 0.2, 1.0)
var _light: OmniLight3D

const RADIUS := 0.35
const MAX_LIFE := 6.0

func launch(origin: Vector3, velocity_: Vector3, damage_: float, shooter_: Node) -> void:
	add_to_group("reflectable")
	collision_layer = 1 << 4
	collision_mask = 0
	monitorable = true
	monitoring = false
	global_position = origin
	vel = velocity_
	damage = damage_
	shooter = shooter_
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = RADIUS * 1.6
	shape.shape = s
	add_child(shape)
	var mi := MeshInstance3D.new()
	mi.mesh = FX.shared_mesh("sphere")
	mi.scale = Vector3.ONE * RADIUS * 2.0
	_mi = mi
	FX.fx_apply(mi, "glow", _color, 4.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.7, 0.3, 1.0)
	_light.omni_range = 3.0
	_light.light_energy = 1.2
	add_child(_light)

## Вызывается топором.
func reflect(new_velocity: Vector3) -> void:
	Perf.mark("projectile_reflect")
	if reflected:
		return
	reflected = true
	vel = new_velocity.normalized() * maxf(vel.length() * 2.2, 18.0)
	damage *= 3.0
	_life = 0.0
	_color = Color(0.4, 0.85, 1.0)
	_mi.set_instance_shader_parameter("color", _color)
	_light.light_color = Color(0.4, 0.85, 1.0)
	FX.burst(get_parent(), global_position, 0.6, Color(0.6, 0.9, 1.0, 0.7), 0.15)
	Audio.play("sounds/sfx/reflect.wav")
	ComicFX.pop("parry", global_position)
	Run.add_glory(5)

func _physics_process(delta: float) -> void:
	_life += delta
	if _life > MAX_LIFE:
		queue_free()
		return
	var from := global_position
	var to := from + vel * delta
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(ray)
	if hit:
		_pop(hit.position)
		return
	global_position = to
	if reflected:
		var q := PhysicsShapeQueryParameters3D.new()
		var s := SphereShape3D.new()
		s.radius = RADIUS + 0.3
		q.shape = s
		q.transform = Transform3D(Basis.IDENTITY, global_position)
		q.collision_mask = 1 << 2
		for h in space.intersect_shape(q, 4):
			var c: Object = h.collider
			if c and c.has_method("take_hit"):
				c.take_hit(damage, vel.normalized() * 8.0 + Vector3.UP * 2.0, "reflect")
				_pop(global_position)
				return
	else:
		var player := get_tree().get_first_node_in_group("player") as Player
		if player and not player.is_dead:
			var center := player.global_position + Vector3(0, 0.9, 0)
			if center.distance_to(global_position) < RADIUS + 0.55:
				player.take_damage(damage, vel.normalized() * 4.0)
				_pop(global_position)

func _pop(pos: Vector3) -> void:
	FX.burst(get_parent(), pos, 0.5, _color * Color(1, 1, 1, 0.6), 0.15)
	queue_free()
