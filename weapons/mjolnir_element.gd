extends MjolnirTraitHandler
class_name MjolnirElementHandler
## Стихия Мьёльнира (блок Б4, GDD 10): общий каркас огня, льда, молнии, земли и ветра.
## Уровень = способ доставки (каждый следующий добавляется к прежним):
##   1 — при попадании молота (apply_element) + своя связка с ударом-приземлением (slam_combo);
##   2 — след на полу вдоль полёта (make_trail_zone);
##   3 — аура воткнутого молота: раз в aura_interval (aura_pulse); воткнутый молот ждёт ПКМ дольше;
##   4 — удар с неба в точку прицела при идеальном хвате (sky_strike).
## Плюс окружение (world_effect): огонь поджигает бочки и брагу Свена, молния пускает ток по лужам браги.
## Скрипт стихии переопределяет apply_element / slam_combo и, если нужно, остальные способы.

const LVL_TRAIL := 2
const LVL_AURA := 3
const LVL_SKY := 4

@export_group("2. След на полу")
## Шаг между пятнами вдоль полёта (м)
@export var trail_spacing: float = 1.8
@export var trail_radius: float = 1.1
@export var trail_duration: float = 3.0
## След ложится на пол, если молот не выше этого (м)
@export var trail_max_height: float = 4.0
## Не больше стольких пятен одновременно (старые гаснут) — фризы и лимит instance uniform
@export var trail_max_zones: int = 10

@export_group("3. Аура воткнутого молота")
@export var aura_interval: float = 1.0
@export var aura_radius: float = 4.0
@export var aura_damage: float = 8.0
## Сколько воткнутый молот ждёт ПКМ (с аурой)
@export var aura_stuck_hold: float = 5.0

@export_group("4. Удар с неба (идеальный хват)")
@export var sky_max_distance: float = 40.0
@export var sky_radius: float = 3.0
@export var sky_damage: float = 33.0

@export_group("Связка с ударом-приземлением и окружение")
## Насколько дальше радиуса удара-приземления ищем врагов со статусом стихии (м)
@export var slam_reach: float = 2.0
## Радиус, в котором стихия задевает окружение у точки удара (лужи браги, бочки), м
@export var world_radius: float = 1.6

var _zones: Array[Node] = []
var _zone_count: int = 0

func element_color() -> Color:
	return trait_def.color if trait_def else Color(0.6, 0.85, 1.0)

func player() -> Player:
	return hand.player if hand and is_instance_valid(hand) else null

# --- Что переопределяет стихия ---

## Эффект стихии на враге. power — 1 у попадания молота, меньше у следа/ауры; from — откуда пришёл удар;
## proj — снаряд (null, если не от молота)
func apply_element(_enemy: Enemy, _power: float, _from: Vector3, _proj: MjolnirProjectile) -> void:
	pass

## Связка с ударом-приземлением (уровень 1+)
func slam_combo(_power: float, _center: Vector3) -> void:
	pass

## Окружение в точке pos (лужи браги, бочки)
func world_effect(_pos: Vector3, _radius: float) -> void:
	pass

## Пятно следа на полу (уровень 2). По умолчанию — ElementZone с вызовом zone_touch.
func make_trail_zone(parent: Node, pos: Vector3, proj: MjolnirProjectile) -> Node3D:
	var z := ElementZone.new()
	parent.add_child(z)
	z.dir = Vector3(proj.vel.x, 0, proj.vel.z).normalized() if proj and proj.vel.length() > 0.1 else Vector3.FORWARD
	z.setup(pos, trail_radius, trail_duration, Color(element_color(), 0.6), zone_touch, true)
	return z

## Враг наступил в пятно следа (ElementZone)
func zone_touch(enemy: Enemy, _zone: ElementZone) -> void:
	apply_element(enemy, 0.5, enemy.global_position, null)

## Импульс ауры воткнутого молота (уровень 3)
func aura_pulse(proj: MjolnirProjectile) -> void:
	var c := proj.global_position
	FX.ring(proj.fx_parent(), c - Vector3(0, 0.3, 0), aura_radius, Color(element_color(), 0.7), 0.3)
	for e in enemies_near(proj.get_tree(), c, aura_radius):
		var dir := e.global_position - c
		dir.y = 0
		hurt(e, aura_damage * proj.damage_mult, dir.normalized() * 2.0 + Vector3.UP * 1.5, damage_source())
		if is_instance_valid(e) and not e.is_dead:
			apply_element(e, 0.6, c, proj)
	world_effect(c, aura_radius)

## Удар с неба в точку point (уровень 4)
func sky_strike(point: Vector3) -> void:
	var p := player()
	var parent := p.get_parent()
	FX.lightning(parent, point + Vector3(randf_range(-1, 1), 14.0, randf_range(-1, 1)), point, 0.3, element_color().lightened(0.3))
	FX.ring(parent, point, sky_radius, Color(element_color(), 0.9), 0.35)
	FX.burst(parent, point + Vector3(0, 0.5, 0), sky_radius * 0.4, Color(element_color(), 0.6), 0.2)
	for e in enemies_near(p.get_tree(), point, sky_radius + 0.9):
		hurt(e, sky_damage, Vector3.UP * 4.0, damage_source())
		if is_instance_valid(e) and not e.is_dead:
			apply_element(e, 1.0, point, null)
	world_effect(point, sky_radius)
	p.camera_fx.add_trauma(0.3)
	Audio.play("sounds/sfx/lightning.wav")

## Интервал ауры на текущем уровне (молния на 4-м — чаще)
func aura_interval_now() -> float:
	return aura_interval

## Источник урона стихии (Щитоносец пропускает огонь и молнию — enemy.gd _shield_blocks)
func damage_source() -> String:
	return "hammer"

# --- Хуки молота ---

func modify(stat: StringName, value: Variant) -> Variant:
	if stat == &"stuck_auto_return" and level >= LVL_AURA and float(value) > 0.0:
		return maxf(float(value), aura_stuck_hold)
	return value

func on_hit_enemy(proj: MjolnirProjectile, enemy: Node3D, _damage: float) -> void:
	var en := enemy as Enemy
	if en == null or en.is_dead:
		return
	apply_element(en, 1.0, proj.global_position, proj)
	world_effect(en.global_position, world_radius)
	mark("hit")

func on_hit_world(proj: MjolnirProjectile, pos: Vector3, _normal: Vector3, stuck: bool) -> void:
	world_effect(pos, world_radius)
	if stuck and level >= LVL_AURA:
		# Первый импульс — почти сразу
		proj.data["aura_t"] = 0.15

func on_flight_tick(proj: MjolnirProjectile, _delta: float) -> void:
	if level >= LVL_TRAIL:
		_trail(proj)

func on_recall_tick(proj: MjolnirProjectile, _delta: float) -> void:
	if level >= LVL_TRAIL:
		_trail(proj)

func on_stuck_tick(proj: MjolnirProjectile, delta: float) -> void:
	if level < LVL_AURA:
		return
	var t: float = float(proj.data.get("aura_t", 0.15)) - delta
	if t > 0.0:
		proj.data["aura_t"] = t
		return
	proj.data["aura_t"] = aura_interval_now()
	mark("aura")
	aura_pulse(proj)

func on_perfect_catch(h: MjolnirHand) -> void:
	if level < LVL_SKY:
		return
	var p := h.player
	var from := p.get_aim_origin()
	var to := from + p.get_aim_forward() * sky_max_distance
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | (1 << 2))
	q.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	mark("sky")
	sky_strike(hit.position)

func on_player_slam(_h: MjolnirHand, power: float, center: Vector3) -> void:
	slam_combo(power, center)

# --- Помощники ---

func _trail(proj: MjolnirProjectile) -> void:
	var pos := proj.global_position
	var key := "trail_last_" + str(trait_def.id if trait_def else &"el")
	if not proj.data.has(key):
		proj.data[key] = pos
		return
	if pos.distance_to(proj.data[key]) < trail_spacing:
		return
	proj.data[key] = pos
	var hit := floor_below(proj, pos, trail_max_height)
	if hit.is_empty():
		return
	_zones.assign(_zones.filter(func(z: Variant) -> bool: return is_instance_valid(z) and not (z as Node).is_queued_for_deletion()))
	while _zones.size() >= maxi(1, trail_max_zones):
		_zones.pop_front().queue_free()
	_zone_count += 1
	var z := make_trail_zone(proj.fx_parent(), hit.position, proj)
	if z:
		_zones.append(z)
	world_effect(hit.position, trail_radius)
	if _zone_count == 1:
		mark("trail")

## Сколько пятен следа сейчас лежит (для тестов)
func active_zones() -> int:
	return _zones.filter(func(z: Variant) -> bool: return is_instance_valid(z) and not (z as Node).is_queued_for_deletion()).size()

## Радиус удара-приземления силы power (как в Player._do_slam_impact, без рун)
func slam_radius(power: float) -> float:
	var p := player()
	if p == null:
		return 3.5
	return (p.slam_base_radius + slam_height(power) * p.slam_radius_per_meter) * p.slam_radius_mult

func slam_height(power: float) -> float:
	return maxf(0.0, (power - 0.25) * 14.0)

func slam_damage(power: float) -> float:
	var p := player()
	if p == null:
		return 30.0
	return (p.slam_base_damage + slam_height(power) * p.slam_damage_per_meter) * p.slam_damage_mult

## Враги в радиусе от center, у которых есть статус (проверка check(enemy) -> bool)
func enemies_with(center: Vector3, radius: float, check: Callable) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if hand == null or not hand.is_inside_tree():
		return out
	for e in enemies_near(hand.get_tree(), center + Vector3(0, 0.9, 0), radius):
		if check.call(e):
			out.append(e)
	return out

## Толкнуть врага (стихия ветра и т. п.) — как отбрасывание в take_hit, с учётом knock_resist
static func push_enemy(en: Enemy, push: Vector3) -> void:
	if en == null or en.is_dead:
		return
	var k := push * (1.0 - en.knock_resist)
	# Сброшен Тором: падение с высоты засчитывается (enemy.gd _check_fall смотрит на время последнего удара)
	en._last_hit_time = Run.now()
	en.knockback_velocity += Vector3(k.x, 0, k.z)
	en.velocity.x += k.x
	en.velocity.z += k.z
	if k.y > 1.0:
		en.velocity.y = maxf(en.velocity.y, k.y)
