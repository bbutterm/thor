extends RefCounted
class_name WeaponItem
## Экземпляр оружия в забеге: описание (WeaponDef, общее) + своё состояние — уровень и патроны.
## Лежит в слоте игрока или на полу (WeaponPickup) и переходит между ними без потерь.

var def: WeaponDef
var level: int = 1
var mag: int = 0
var reserve: int = 0

static func create(d: WeaponDef, lvl: int = 1) -> WeaponItem:
	var it := WeaponItem.new()
	it.def = d
	it.level = clampi(lvl, 1, 3)
	if d and d.is_ranged():
		it.mag = d.mag_size
		it.reserve = d.reserve_start
	return it

func is_ranged() -> bool:
	return def != null and def.is_ranged()

func damage_mult() -> float:
	return WeaponDef.level_mult(level)

## Патронов совсем нет (ни в магазине, ни в запасе).
func is_empty() -> bool:
	return is_ranged() and mag <= 0 and reserve <= 0

## Добавить патроны в запас (не выше предела). Возвращает, сколько взято.
func add_ammo(amount: int) -> int:
	if not is_ranged():
		return 0
	var take := clampi(amount, 0, maxi(0, reserve_cap() - reserve))
	reserve += take
	return take

func title() -> String:
	if def == null:
		return ""
	return tr(def.display_name) + ("" if level <= 1 else " +%d" % (level - 1))

## Предел запаса патронов: у оружия + руна «Бездонный колчан» (+50 % → +150 %)
func reserve_cap() -> int:
	return int(round(def.reserve_max * (1.0 + Run.rune_value("endless_quiver"))))

