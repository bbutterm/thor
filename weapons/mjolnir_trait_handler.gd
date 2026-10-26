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

## Уровень трейта (1–2), выставляет рука
var level: int = 1
var trait_def: MjolnirTrait
var hand: MjolnirHand

## Значение по уровню: lvl(1-й, 2-й)
func lvl(a: Variant, b: Variant) -> Variant:
	return b if level >= 2 else a

## Изменение параметров броска. stat: "sticks" (bool), "wall_bounces" (int), "chain_targets" (int),
## "throw_speed", "max_range", "auto_return_after", "stuck_auto_return" (float).
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

## Начало возврата. by_player — по ПКМ (а не по таймеру/дальности). Чтобы управлять возвратом самому
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

## Отметить срабатывание трейта (для лога фризов F3)
func mark(what: String = "") -> void:
	Perf.mark("trait_" + str(trait_def.id if trait_def else &"?") + ("_" + what if what != "" else ""))
