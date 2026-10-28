extends Area3D
class_name EnemyProjectile
## Снаряд врага (GDD 12.6). Виды (kind):
##   STRAIGHT — прямой (сгусток проклятья метателя; веер — несколько прямых, EnemyRangedAttacks.fire_fan);
##   LOB      — навесной: летит дугой (gravity), место падения подсвечено на полу, при падении — всплеск blast_radius;
##   ORB      — медленная крупная сфера шамана, слабо доворачивает к Тору (homing); летящий Мьёльнир её сбивает;
##   GRENADE  — граната наёмника: дуга с меткой, на полу — Blast.delayed (fuse) — бьёт и своих;
##   SPEAR    — копьё воина: прямой, вытянутый вид.
## Топор отбивает любой (reflect) — отражённый летит прямо и бьёт врагов. Зоны (HazardZone) не отражаются.
## Меши и материалы — общие (FX.shared_mesh, FX.fx_apply), цвет — на экземпляре; свет — только у STRAIGHT с light и ORB.
## Лимит одновременных снарядов на зал — Room.max_projectiles (EnemyRangedAttacks.can_fire).

enum Kind { STRAIGHT, LOB, ORB, GRENADE, SPEAR }

var kind: Kind = Kind.STRAIGHT
var vel: Vector3 = Vector3.ZERO
var damage: float = 10.0
var reflected: bool = false
var shooter: Node = null
## Настраивается до launch (EnemyRangedAttacks):
var radius: float = RADIUS
var fall_gravity: float = 0.0
## ORB: скорость доворота к Тору (рад/с)
var homing: float = 0.0
## LOB: радиус всплеска при падении; GRENADE: радиус взрыва
var blast_radius: float = 0.0
## GRENADE: фитиль на полу (с)
var fuse: float = 0.6
## Точка падения (LOB/GRENADE) — для метки на полу
var landing: Vector3 = Vector3.INF
## Время полёта до точки падения (для заполнения метки)
var flight_time: float = 1.0
var light: bool = true
var max_life: float = MAX_LIFE
var color: Color = Color(0.7, 0.2, 1.0)

var _life: float = 0.0
var _mi: MeshInstance3D
var _light: OmniLight3D
var _marker: MeshInstance3D
var _marker_ring: MeshInstance3D

const RADIUS := 0.35
const MAX_LIFE := 6.0
## Отражённый снаряд бьёт врагов сильнее (GDD 8)
const REFLECT_DAMAGE_MULT := 1.8
## Слава за сбитую Мьёльниром сферу
const ORB_KNOCK_GLORY := 3

func launch(origin: Vector3, velocity_: Vector3, damage_: float, shooter_: Node) -> void:
	add_to_group("reflectable")
	add_to_group("enemy_projectiles")
	set_meta("transient", true)
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
	s.radius = maxf(radius * 1.6, 0.4)
	shape.shape = s
	add_child(shape)
	var mi := MeshInstance3D.new()
	_mi = mi
	match kind:
		Kind.SPEAR:
			mi.mesh = FX.shared_mesh("box")
			mi.scale = Vector3(0.07, 0.07, 1.3)
			FX.fx_apply(mi, "glow", color, 1.6)
		Kind.GRENADE:
			mi.mesh = FX.shared_mesh("sphere")
			mi.scale = Vector3.ONE * radius * 2.0
			FX.fx_apply(mi, "glow", color, 2.5)
		_:
			mi.mesh = FX.shared_mesh("sphere")
			mi.scale = Vector3.ONE * radius * 2.0
			FX.fx_apply(mi, "glow", color, 4.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_orient()
	if (light and kind == Kind.STRAIGHT) or kind == Kind.ORB:
		_light = OmniLight3D.new()
		_light.light_color = color.lightened(0.2)
		_light.omni_range = 3.0 if kind != Kind.ORB else 4.5
		_light.light_energy = 1.2
		add_child(_light)
	if landing != Vector3.INF and (kind == Kind.LOB or kind == Kind.GRENADE):
		_build_marker()

## Метка падения на полу: кольцо во весь радиус и заливка, растущая к моменту падения.
func _build_marker() -> void:
	var r := maxf(blast_radius, 0.8)
	_marker_ring = MeshInstance3D.new()
	_marker_ring.mesh = FX.shared_mesh("ring")
	FX.fx_apply(_marker_ring, "alpha", Color(color, 0.95), 2.2)
	_marker_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker_ring.top_level = true
	add_child(_marker_ring)
	_marker_ring.global_position = landing + Vector3(0, 0.06, 0)
	_marker_ring.scale = Vector3(r, 0.4, r)
	_marker = MeshInstance3D.new()
	_marker.mesh = FX.shared_mesh("disc")
	FX.fx_apply(_marker, "alpha", Color(color, 0.6), 1.5)
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.top_level = true
	add_child(_marker)
	_marker.global_position = landing + Vector3(0, 0.05, 0)
	_update_marker()

func _update_marker() -> void:
	if _marker == null:
		return
	var r := maxf(blast_radius, 0.8)
	var k := clampf(_life / maxf(flight_time, 0.05), 0.05, 1.0)
	_marker.scale = Vector3(r * k, 0.02, r * k)
	_marker.transparency = lerpf(0.7, 0.35, k)

func _drop_marker() -> void:
	if _marker:
		_marker.queue_free()
		_marker_ring.queue_free()
		_marker = null
		_marker_ring = null

func _orient() -> void:
	if kind == Kind.SPEAR and vel.length() > 0.1 and is_inside_tree():
		var d := vel.normalized()
		_mi.look_at(global_position + d, Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT)

## Вызывается топором.
func reflect(new_velocity: Vector3) -> void:
	Perf.mark("projectile_reflect")
	if reflected:
		return
	reflected = true
	vel = new_velocity.normalized() * maxf(vel.length() * 2.2, 18.0)
	fall_gravity = 0.0
	homing = 0.0
	_drop_marker()
	damage *= REFLECT_DAMAGE_MULT
	_life = 0.0
	color = Color(0.4, 0.85, 1.0)
	_mi.set_instance_shader_parameter("color", color)
	if _light:
		_light.light_color = Color(0.4, 0.85, 1.0)
	_orient()
	FX.burst(get_parent(), global_position, 0.6, Color(0.6, 0.9, 1.0, 0.7), 0.15)
	Audio.play("sounds/sfx/reflect.wav")
	ComicFX.pop("parry", global_position)
	StyleMeter.event(&"reflect")
	Run.add_glory(5)

## Сбита Мьёльниром (только ORB): лопается без урона, немного Славы.
func knock_down() -> void:
	Perf.mark("orb_knocked")
	FX.burst(get_parent(), global_position, radius * 2.0, Color(0.6, 0.9, 1.0, 0.8), 0.2)
	Audio.play("sounds/sfx/reflect.wav")
	ComicFX.pop("parry", global_position)
	Run.add_glory(ORB_KNOCK_GLORY)
	_drop_marker()
	queue_free()

func _physics_process(delta: float) -> void:
	_life += delta
	if _life > max_life:
		_pop(global_position)
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if not reflected:
		if fall_gravity > 0.0:
			vel.y -= fall_gravity * delta
		if homing > 0.0 and player and not player.is_dead:
			var want := (player.global_position + Vector3(0, 0.9, 0) - global_position).normalized()
			var cur := vel.normalized()
			var ang := cur.angle_to(want)
			if ang > 0.001:
				var axis := cur.cross(want)
				if axis.length() > 0.0001:
					vel = vel.rotated(axis.normalized(), minf(ang, homing * delta))
		if kind == Kind.ORB and _knocked_by_hammer():
			knock_down()
			return
	_update_marker()
	var from := global_position
	var to := from + vel * delta
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(ray)
	if hit:
		_land(hit.position)
		return
	global_position = to
	_orient()
	if reflected:
		var q := PhysicsShapeQueryParameters3D.new()
		var s := SphereShape3D.new()
		s.radius = radius + 0.3
		q.shape = s
		q.transform = Transform3D(Basis.IDENTITY, global_position)
		q.collision_mask = 1 << 2
		for h in space.intersect_shape(q, 4):
			var c: Object = h.collider
			if c and c.has_method("take_hit"):
				c.take_hit(damage, vel.normalized() * 8.0 + Vector3.UP * 2.0, "reflect")
				_land(global_position)
				return
	elif player and not player.is_dead:
		var center := player.global_position + Vector3(0, 0.9, 0)
		if center.distance_to(global_position) < radius + 0.55:
			if player.axe and player.axe.weapon_skill_try_parry_projectile(self):
				return
			if kind == Kind.GRENADE:
				_land(global_position)
				return
			_strike_player(player, damage, vel.normalized() * 4.0)
			_pop(global_position)

func _knocked_by_hammer() -> bool:
	for n in get_tree().get_nodes_in_group("mjolnir_projectiles"):
		var m := n as Node3D
		if m and is_instance_valid(m) and not m.is_queued_for_deletion() \
				and m.global_position.distance_to(global_position) < radius + MjolnirProjectile.HIT_RADIUS + 0.2:
			return true
	return false

func _strike_player(player: Player, amount: float, knock: Vector3) -> void:
	RunTracker.note_hit(shooter)
	var h0 := player.health
	player.take_damage(amount, knock)
	# Модификаторы элиты (Ледяной, Вампир) слушают удары, дошедшие до Тора
	if is_instance_valid(shooter) and shooter.has_signal("struck_player") and player.health < h0:
		shooter.emit_signal("struck_player", h0 - player.health)

## Упал / врезался: у навесного — всплеск по площади, у гранаты — взрыв с фитилём.
func _land(pos: Vector3) -> void:
	if reflected and kind == Kind.GRENADE:
		Blast.detonate(get_parent(), pos, blast_radius, damage, shooter if is_instance_valid(shooter) else null)
		_pop(pos)
		return
	if not reflected:
		match kind:
			Kind.GRENADE:
				Blast.delayed(get_parent(), pos, blast_radius, damage, fuse, shooter if is_instance_valid(shooter) else null, color)
			Kind.LOB:
				if blast_radius > 0.0:
					FX.ring(get_parent(), Loot.floor_point(self, pos + Vector3.UP * 0.3), blast_radius, Color(color, 0.9), 0.3)
					var player := get_tree().get_first_node_in_group("player") as Player
					if player and not player.is_dead:
						var d := player.global_position - pos
						# Всплеск по полу: в прыжке не задевает
						if Vector2(d.x, d.z).length() <= blast_radius + 0.3 and d.y < HazardZone.JUMP_CLEARANCE + 0.3 and d.y > -1.2:
							_strike_player(player, damage, Vector3(d.x, 0, d.z).normalized() * 4.0 + Vector3.UP * 2.0)
	_pop(pos)

func _pop(pos: Vector3) -> void:
	FX.burst(get_parent(), pos, 0.5 if kind != Kind.ORB else 1.0, color * Color(1, 1, 1, 0.6), 0.15)
	_drop_marker()
	queue_free()
