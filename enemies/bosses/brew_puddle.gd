extends Node3D
class_name BrewPuddle
## Лужа браги Толстого Свена (GDD 14.1): замедляет Тора, пока он стоит в ней (PlayerSlow — то же
## замедление, что у элиты «Ледяной»). Над лужей в прыжке — не замедляет. Общий диск и материал эффектов.

## Радиус лужи (м), сколько живёт (с), множитель скорости Тора в луже
var radius: float = 1.8
var lifetime: float = 7.0
var slow_mult: float = 0.55
## Сколько секунд замедление держится после выхода из лужи
var slow_linger: float = 0.35
var color: Color = Color(0.85, 0.6, 0.15)
## Больше луж одновременно не бывает (старые высыхают сразу)
static var max_puddles: int = 8

var _t: float = 0.0
var _disc: MeshInstance3D

## Лужа на полу под точкой pos.
static func spawn(parent: Node, pos: Vector3, radius_: float, lifetime_: float, slow_: float) -> BrewPuddle:
	Perf.mark("brew_puddle")
	if parent == null or not parent.is_inside_tree():
		return null
	var old := parent.get_tree().get_nodes_in_group("brew_puddles").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	for k in maxi(0, old.size() - max_puddles + 1):
		old[k].queue_free()
	var p := BrewPuddle.new()
	p.radius = radius_
	p.lifetime = lifetime_
	p.slow_mult = slow_
	parent.add_child(p)
	p.global_position = Loot.floor_point(p, pos) + Vector3(0, 0.04, 0)
	return p

func _ready() -> void:
	add_to_group("brew_puddles")
	set_meta("transient", true)
	_disc = MeshInstance3D.new()
	_disc.name = "Disc"
	_disc.mesh = FX.shared_mesh("disc")
	FX.fx_apply(_disc, "alpha", color, 1.2)
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.scale = Vector3(radius * 0.3, 0.02, radius * 0.3)
	_disc.transparency = 0.35
	add_child(_disc)

func _physics_process(delta: float) -> void:
	_t += delta
	# Растекается за 0.25 с, последнюю секунду высыхает
	var grow := clampf(_t / 0.25, 0.0, 1.0)
	var r := radius * lerpf(0.3, 1.0, grow)
	_disc.scale = Vector3(r, 0.02, r)
	_disc.transparency = lerpf(0.35, 1.0, clampf((_t - lifetime + 1.0), 0.0, 1.0))
	if _t >= lifetime:
		queue_free()
		return
	var p := get_tree().get_first_node_in_group("player") as Player
	if p and not p.is_dead and contains(p.global_position):
		PlayerSlow.apply(p, slow_mult, slow_linger)

## Точка (ноги Тора) в луже: по горизонтали внутри радиуса и не выше 0.6 м над ней.
func contains(pos: Vector3) -> bool:
	var d := pos - global_position
	return Vector2(d.x, d.z).length() <= radius and d.y > -0.6 and d.y < 0.6
