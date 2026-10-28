extends RefCounted
class_name Silver
## Серебро (блок К, GDD 15.2): откуда выпадает. Враги — Loot.on_enemy_died → Silver.on_enemy_died
## (EnemyDef.silver_min/max, элита — 10), бочки — BarrelWatch (разбили = отбросило сильно), сундуки — Chest.
## Монеты (SilverCoin) разлетаются и магнитом летят к Тору; кошелёк — Run.silver.

const CONFIG := "res://run/economy.tres"
static var _cfg: Economy

static func cfg() -> Economy:
	if _cfg == null:
		_cfg = load(CONFIG) as Economy if ResourceLoader.exists(CONFIG) else Economy.new()
	return _cfg

## Рассыпать amount серебра монетами из точки pos.
static func drop(parent: Node, pos: Vector3, amount: int) -> void:
	if amount <= 0 or parent == null or not parent.is_inside_tree():
		return
	Perf.mark("silver_drop")
	var n := clampi(amount, 1, maxi(1, cfg().max_coins_per_drop))
	var left := amount
	for i in n:
		var v := left / (n - i)
		left -= v
		var c := SilverCoin.new()
		c.value = v
		parent.add_child(c)
		c.launch(pos + Vector3(0, 0.6, 0))

## Сколько серебра даёт враг (EnemyDef; элита — через Loot: оружие или cfg().elite_silver).
static func for_enemy(enemy: Enemy) -> int:
	if enemy.has_meta("miniboss"):
		return cfg().miniboss_silver
	if Loot.is_elite(enemy):
		return 0  # элита роняет оружие или 10 серебра — решает Loot.on_enemy_died (GDD 12.4)
	var d: EnemyDef = enemy.enemy_def
	if d == null:
		return 0
	return randi_range(mini(d.silver_min, d.silver_max), maxi(d.silver_min, d.silver_max))

static func on_enemy_died(enemy: Enemy, pos: Vector3 = Vector3.INF) -> void:
	if enemy.kind == Enemy.Kind.BOSS and not enemy.has_meta("miniboss"):
		return
	drop(enemy.get_parent(), enemy.global_position if pos == Vector3.INF else pos, for_enemy(enemy))

## Серебро из бочки.
static func barrel_amount() -> int:
	return randi_range(cfg().barrel_silver_min, cfg().barrel_silver_max)
