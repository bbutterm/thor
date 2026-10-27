extends Node3D
class_name BrewPuddle
## Лужа браги Толстого Свена (GDD 14.1): замедляет Тора, пока он стоит в ней (PlayerSlow — то же
## замедление, что у элиты «Ледяной»). Над лужей в прыжке — не замедляет. Вид — декаль assets/decals/puddle_mead
## на общем квадрате и общем материале текстурных эффектов (FX.sprite_apply, шейдер fx_sprite).
## Стихии Мьёльнира (блок Б4): молния пускает по луже ток (electrify — бьёт врагов в луже), огонь поджигает
## брагу (ignite — горящая лужа, fire_zone.gd). Вызывают обработчики стихий (BrewPuddle.electrify_near / ignite_near).

## Радиус лужи (м), сколько живёт (с), множитель скорости Тора в луже
var radius: float = 1.8
var lifetime: float = 7.0
var slow_mult: float = 0.55
## Сколько секунд замедление держится после выхода из лужи
var slow_linger: float = 0.35
var color: Color = Color(1.0, 1.0, 1.0)
## Картинка лужи с брызгами по краям: сторона квада = радиус × столько (тело лужи ≈ радиус замедления)
const DECAL_SCALE := 2.5
## Больше луж одновременно не бывает (старые высыхают сразу)
static var max_puddles: int = 8

var _t: float = 0.0
var _disc: MeshInstance3D
## Под током: сколько ещё секунд, урон за тик и шаг тика
var shock_left: float = 0.0
var shock_damage: float = 6.0
var shock_tick: float = 0.4
var _shock_t: float = 0.0
## Брага горит (огонь Мьёльнира)
var burning: bool = false

## Пустить ток по лужам, которых касается круг (pos, radius). Возвращает, сколько луж под током.
static func electrify_near(tree: SceneTree, pos: Vector3, radius: float, time: float, damage: float) -> int:
	var n := 0
	for p in _near(tree, pos, radius):
		p.electrify(time, damage)
		n += 1
	return n

## Поджечь лужи, которых касается круг. dps — урон огня врагам в луже. Возвращает, сколько подожгли.
static func ignite_near(tree: SceneTree, pos: Vector3, radius: float, dps: float, time: float) -> int:
	var n := 0
	for p in _near(tree, pos, radius):
		if not p.burning:
			p.ignite(dps, time)
			n += 1
	return n

static func _near(tree: SceneTree, pos: Vector3, radius: float) -> Array[BrewPuddle]:
	var out: Array[BrewPuddle] = []
	if tree == null:
		return out
	for n in tree.get_nodes_in_group("brew_puddles"):
		var p := n as BrewPuddle
		if p == null or p.is_queued_for_deletion():
			continue
		var d := p.global_position - pos
		if Vector2(d.x, d.z).length() <= p.radius + radius and absf(d.y) < 1.5:
			out.append(p)
	return out

func electrify(time: float, damage: float) -> void:
	if shock_left <= 0.0:
		Perf.mark("brew_electrify")
		_shock_t = 0.0
	shock_left = maxf(shock_left, time)
	shock_damage = maxf(shock_damage, damage)

func ignite(dps: float, time: float) -> void:
	Perf.mark("brew_ignite")
	burning = true
	var fire := preload("res://weapons/fire_zone.gd").new()
	get_parent().add_child(fire)
	var burn := minf(time, maxf(lifetime - _t, 0.5))
	fire.setup(global_position, radius, burn, dps, true)
	# Брага выгорает вместе с огнём
	lifetime = minf(lifetime, _t + burn + 0.3)
	color = Color(0.55, 0.4, 0.3)
	FX.sprite_color(_disc, color, 1.0)

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
	_disc.mesh = FX.shared_mesh("quad_floor")
	FX.sprite_apply(_disc, "puddle_mead", color, 1.0)
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_disc.rotation.y = randf() * TAU
	var d0 := radius * 0.3 * DECAL_SCALE
	_disc.scale = Vector3(d0, 1.0, d0)
	_disc.transparency = 0.1
	add_child(_disc)

func _physics_process(delta: float) -> void:
	_t += delta
	# Растекается за 0.25 с, последнюю секунду высыхает
	var grow := clampf(_t / 0.25, 0.0, 1.0)
	var r := radius * lerpf(0.3, 1.0, grow) * DECAL_SCALE
	_disc.scale = Vector3(r, 1.0, r)
	_disc.transparency = lerpf(0.1, 1.0, clampf((_t - lifetime + 1.0), 0.0, 1.0))
	if _t >= lifetime:
		queue_free()
		return
	var p := get_tree().get_first_node_in_group("player") as Player
	if p and not p.is_dead and contains(p.global_position) and not burning:
		PlayerSlow.apply(p, slow_mult, slow_linger)
	if shock_left > 0.0:
		_shock(delta, p)

## Ток в луже: раз в shock_tick бьёт врагов, стоящих в ней (молния Тора — урон от Тора, источник "lightning")
func _shock(delta: float, p: Player) -> void:
	shock_left -= delta
	_shock_t -= delta
	if _shock_t > 0.0:
		return
	_shock_t = shock_tick
	var parent := get_parent()
	var a := randf() * TAU
	var edge := global_position + Vector3(cos(a), 0.05, sin(a)) * radius * 0.8
	FX.lightning(parent, global_position + Vector3(0, 0.1, 0), edge, 0.15)
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en == null or en.is_dead or not contains(en.global_position):
			continue
		FX.lightning(parent, edge, en.global_position + Vector3(0, 1.0, 0), 0.15)
		if p:
			p.deal_damage(en, shock_damage, Vector3.UP * 1.0, "lightning")
		else:
			en.take_hit(shock_damage, Vector3.UP, "lightning")
		var st := ElementStatus.of(en, true)
		if st:
			st.shock(2.0)

## Точка (ноги Тора) в луже: по горизонтали внутри радиуса и не выше 0.6 м над ней.
func contains(pos: Vector3) -> bool:
	var d := pos - global_position
	return Vector2(d.x, d.z).length() <= radius and d.y > -0.6 and d.y < 0.6
