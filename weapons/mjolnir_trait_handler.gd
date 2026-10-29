extends Resource
class_name MjolnirTraitHandler
## Обработчик трейта Мьёльнира: набор хуков, которые вызывают mjolnir_hand.gd и mjolnir_projectile.gd.
## Скрипт конкретного трейта наследует этот класс и переопределяет нужные хуки; его @export-поля —
## настройки трейта (хранятся в .tres трейта как вложенный ресурс).
## На забег создаётся копия (duplicate), поэтому в полях обработчика можно хранить состояние.
## Состояние одного броска — в proj.data (Dictionary), оно умирает вместе со снарядом.
##
## Порядок событий броска:
##   on_throw → on_flight_tick… → on_hit_enemy / on_hit_world(stuck=false — отскок)
##   → on_hit_world(stuck=true — воткнулся) → on_stuck_tick… → on_recall_start → on_recall_tick… → on_caught
## Плюс: on_player_slam (удар-приземление игрока), on_perfect_catch (идеальный хват),
##       on_projectile_removed (снаряд исчез любым путём — убрать за собой).
## Удержание ПКМ с молотом в руке (Праща, Заряд — modify(&"hold_throw") = true): on_hold_start →
##   on_hold_tick… → on_hold_release (отпустил — следом бросок); короткое нажатие — обычный бросок.
## События приёмов для связок: on_pull_arrive (Притяжение долетело), on_dive_slam (Пике молотом ударило),
##   on_swap (Обмен).
## Стихии — общий класс MjolnirElementHandler (weapons/mjolnir_element.gd), связки — обычные обработчики.

## Уровень трейта (1–2, у стихий 1–4), выставляет рука
var level: int = 1
var trait_def: MjolnirTrait
var hand: MjolnirHand

## Значение по уровню: lvl(1-й, 2-й)
func lvl(a: Variant, b: Variant) -> Variant:
	return b if level >= 2 else a

## Значение по уровню для стихий: at_level([1-й, 2-й, 3-й, 4-й]) — берётся последнее, если уровней больше
func at_level(values: Array) -> Variant:
	if values.is_empty():
		return null
	return values[clampi(level - 1, 0, values.size() - 1)]

## Изменение параметров броска. stat: "sticks" (bool), "wall_bounces" (int), "chain_targets" (int),
## "throw_speed", "max_range", "catch_cooldown", "perfect_catch_cooldown" (float),
## старое под FeelSwitch (F6): "throw_cooldown", "perfect_cooldown_refund", "auto_return_after", "stuck_auto_return",
## "hold_throw" (bool — бросок по отпусканию ПКМ: Праща, Заряд).
func modify(_stat: StringName, value: Variant) -> Variant:
	return value

func on_equip(_hand: MjolnirHand) -> void:
	pass

func on_unequip(_hand: MjolnirHand) -> void:
	pass

func on_throw(_proj: MjolnirProjectile) -> void:
	pass

## Каждый кадр полёта «туда» и зависания (proj.state OUT / HOVER)
func on_flight_tick(_proj: MjolnirProjectile, _delta: float) -> void:
	pass

func on_hit_enemy(_proj: MjolnirProjectile, _enemy: Node3D, _damage: float) -> void:
	pass

## Молот ударился о стену/пол. stuck = true — воткнулся, false — отскочил
func on_hit_world(_proj: MjolnirProjectile, _pos: Vector3, _normal: Vector3, _stuck: bool) -> void:
	pass

func on_stuck_tick(_proj: MjolnirProjectile, _delta: float) -> void:
	pass

## Начало возврата. by_player — по ПКМ; false — служебный возврат или приём со своим возвратом
## (Бумеранг, Буря, копии Двух молотов). Автовозврата у базы нет (П5). Чтобы управлять возвратом самому
## (например, тянуть игрока к молоту), вызови proj.take_recall_control(self) и реализуй control_recall_tick.
func on_recall_start(_proj: MjolnirProjectile, _by_player: bool) -> void:
	pass

func on_recall_tick(_proj: MjolnirProjectile, _delta: float) -> void:
	pass

## Только для обработчика, взявшего возврат на себя (take_recall_control). Закончить — proj.catch().
func control_recall_tick(_proj: MjolnirProjectile, _delta: float) -> void:
	pass

func on_caught(_hand: MjolnirHand) -> void:
	pass

func on_player_slam(_hand: MjolnirHand, _power: float, _center: Vector3) -> void:
	pass

func on_perfect_catch(_hand: MjolnirHand) -> void:
	pass

func on_projectile_removed(_proj: MjolnirProjectile) -> void:
	pass

## ПКМ зажата с молотом в руке (только если какой-то трейт вернул modify(&"hold_throw") = true)
func on_hold_start(_hand: MjolnirHand) -> void:
	pass

## held — сколько секунд держим
func on_hold_tick(_hand: MjolnirHand, _held: float, _delta: float) -> void:
	pass

## Отпустил ПКМ: следом рука бросает молот (усиление — в hand.next_throw)
func on_hold_release(_hand: MjolnirHand, _held: float) -> void:
	pass

## Притяжение к молоту: Тор долетел (pos — где он теперь)
func on_pull_arrive(_hand: MjolnirHand, _pos: Vector3) -> void:
	pass

## Пике молотом: Тор ударил в точку молота (power — как у удара-приземления, 0.25…1)
func on_dive_slam(_hand: MjolnirHand, _center: Vector3, _power: float) -> void:
	pass

## Обмен: Тор и молот поменялись местами
func on_swap(_hand: MjolnirHand, _from: Vector3, _to: Vector3) -> void:
	pass

# --- Помощники для обработчиков ---

## Живые враги в радиусе (по горизонтали и вертикали — обычное расстояние)
func enemies_near(tree: SceneTree, pos: Vector3, radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in tree.get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en == null or en.is_dead:
			continue
		if (en.global_position + Vector3(0, 0.9, 0)).distance_to(pos) <= radius:
			out.append(en)
	return out

## Урон Тора по врагу — только через player.deal_damage (множители тела, берсерк, руны «за удар»)
func hurt(target: Object, dmg: float, knock: Vector3, source: String = "hammer") -> float:
	if hand == null or not is_instance_valid(hand) or hand.player == null:
		return 0.0
	return hand.player.deal_damage(target, dmg, knock, source)

## Точка пола под pos (не глубже max_drop м); пусто — пола нет или он слишком крутой
static func floor_below(world_node: Node3D, pos: Vector3, max_drop: float = 4.0) -> Dictionary:
	if world_node == null or not world_node.is_inside_tree():
		return {}
	var space := world_node.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.2, 0), pos - Vector3(0, max_drop, 0), 1))
	if hit.is_empty() or (hit.normal as Vector3).y < 0.6:
		return {}
	return hit

## Отметить срабатывание трейта (для лога фризов F3)
func mark(what: String = "") -> void:
	Perf.mark("trait_" + str(trait_def.id if trait_def else &"?") + ("_" + what if what != "" else ""))
	if trait_def and trait_def.is_combo():
		Run.mjolnir_combo_fired.emit(trait_def)
