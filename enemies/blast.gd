extends Node3D
class_name Blast
## Взрыв по площади: Раздутый (GDD 12.1), элита «Взрывной» (GDD 12.4).
## Бьёт и Тора, и своих (врагов), и раскидывает бочки. Всё на общих мешах/материалах эффектов (FX).
## detonate() — сразу; delayed() — с телеграфом (красный диск на земле растёт delay секунд).

var radius: float = 3.0
var damage: float = 44.0
var delay: float = 0.6
var color: Color = Color(1.0, 0.45, 0.15)
## Кто взрывается (для причины смерти Тора) — может быть уже удалён
var source_node: Node = null
var source_id: String = "bloated"
var _t: float = 0.0
var _disc: MeshInstance3D

## Взорвать сразу. exclude — кого не задевать (сам взрывающийся).
static func detonate(parent: Node, pos: Vector3, radius_: float, damage_: float, source: Node = null, exclude: Node = null, color_: Color = Color(1.0, 0.45, 0.15)) -> void:
	Perf.mark("blast")
	if parent == null or not parent.is_inside_tree():
		return
	FX.burst(parent, pos, radius_ * 0.75, Color(color_, 0.55), 0.3)
	var ground := Loot.floor_point(parent as Node3D, pos) if parent is Node3D else pos
	FX.ring(parent, ground, radius_, Color(color_, 0.9), 0.35)
	FX.sparks(parent, pos, color_.lightened(0.3), 22, 9.0)
	FX.blast_smoke(parent, pos, radius_)
	Audio.play("sounds/sfx/boss_slam.wav")
	ComicFX.pop("slam", pos)
	var tree := parent.get_tree()
	var player := tree.get_first_node_in_group("player") as Player
	if player and not player.is_dead:
		var center := player.global_position + Vector3(0, 0.9, 0)
		var d := center - pos
		if d.length() <= radius_ + 0.4:
			var dir := Vector3(d.x, 0, d.z).normalized() if Vector2(d.x, d.z).length() > 0.05 else Vector3.FORWARD
			RunTracker.note_hit(source, "bloated")
			player.take_damage(damage_, dir * 9.0 + Vector3.UP * 5.0)
		if d.length() < radius_ * 3.0:
			player.camera_fx.add_trauma(clampf(0.5 - d.length() * 0.04, 0.15, 0.5))
	# Своих — тоже (GDD 12.1: «бьёт и своих»)
	for e in tree.get_nodes_in_group("enemies"):
		if e == exclude or e == source or not is_instance_valid(e):
			continue
		var en := e as Node3D
		var dd := en.global_position + Vector3(0, 0.9, 0) - pos
		if dd.length() <= radius_ + 0.4:
			var kd := Vector3(dd.x, 0, dd.z).normalized() if Vector2(dd.x, dd.z).length() > 0.05 else Vector3.FORWARD
			en.call("take_hit", damage_, kd * 10.0 + Vector3.UP * 4.0, "explosion")
	# Бочки и ящики: урон и толчок (взрывные бочки рядом — цепная реакция), props/destructible.gd
	Destructible.hit_area(parent, pos, radius_ * 1.3, damage_, 7.0, 4.0, "explosion")

## Взрыв с телеграфом через delay секунд (диск на земле наливается красным).
static func delayed(parent: Node, pos: Vector3, radius_: float, damage_: float, delay_: float, source: Node = null, color_: Color = Color(1.0, 0.45, 0.15)) -> Blast:
	Perf.mark("blast_telegraph")
	var b := Blast.new()
	b.radius = radius_
	b.damage = damage_
	b.delay = delay_
	b.color = color_
	b.source_node = source
	parent.add_child(b)
	b.global_position = pos
	return b

func _ready() -> void:
	_disc = MeshInstance3D.new()
	_disc.mesh = FX.shared_mesh("disc")
	FX.fx_apply(_disc, "alpha", Color(color, 1.0), 1.4)
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.transparency = 1.0
	_disc.scale = Vector3(radius * 0.2, 0.03, radius * 0.2)
	add_child(_disc)
	_disc.global_position = Loot.floor_point(self, global_position) + Vector3(0, 0.06, 0)

func _physics_process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / maxf(delay, 0.01), 0.0, 1.0)
	if _disc:
		var r := lerpf(radius * 0.2, radius, k)
		_disc.scale = Vector3(r, 0.03, r)
		# Мигает всё чаще к взрыву
		_disc.transparency = 1.0 - (0.25 + 0.35 * k) * (0.6 + 0.4 * sin(_t * (10.0 + 30.0 * k)))
	if _t >= delay:
		detonate(get_parent(), global_position + Vector3(0, 0.8, 0), radius, damage, source_node if is_instance_valid(source_node) else null, null, color)
		queue_free()

## Образец для прогрева шейдеров (диск телеграфа).
static func warmup_sample(parent: Node3D, pos: Vector3) -> void:
	var b := Blast.new()
	b.delay = 999.0
	parent.add_child(b)
	b.position = pos
	b.set_physics_process(false)
	b._disc.transparency = 0.4
