extends Resource
class_name EnemyDef
## Описание врага по GDD 12: слой толпы, HP в «У» (1 У = 22 урона), скорость, урон, мир, награды.
## Враги, которые уже есть в игре (game_kind = grunt / thrower), берут HP, скорость и урон отсюда (enemy.gd → apply_def).

const U := 22.0

@export var id: String = ""
@export var title: String = ""
@export_enum("midgard", "jotunheim", "helheim", "yggdrasil") var world: String = "midgard"
@export_enum("fodder", "fighter", "special", "elite", "miniboss", "boss") var layer: String = "fighter"
## HP в «У»
@export var hp_u: float = 1.0
@export var move_speed: float = 4.0
## Урон по Тору за удар (GDD 8: корм 5, боец 12, особый 15)
@export var damage: float = 12.0
## П4: множитель урона обычных ударов мили (melee / melee_finisher) — броня босса от спама; 1 — без брони.
## Действует только на Kind.BOSS (Enemy.is_armored_against).
@export_range(0.05, 1.0, 0.05) var melee_resist: float = 1.0
## П4, «старое» по F6 (FeelSwitch boss_armor): HP в «У» до брони; 0 — как hp_u
@export var legacy_hp_u: float = 0.0
## Слава за убийство (GDD 15.2: корм 1, боец 3, особый 5)
@export var glory: int = 3
## Серебро за убийство (GDD 15.2), выпадет, когда появится серебро (блок К)
@export var silver_min: int = 0
@export var silver_max: int = 0
## Какой враг игры это описывает: "grunt" / "thrower" / "boss" / "" (ещё нет в игре)
@export var game_kind: String = ""
@export_multiline var description: String = ""
## HP, скорость и урон применяются к врагу в игре
@export var implemented: bool = false

func max_health() -> float:
	if legacy_hp_u > 0.0 and FeelSwitch.is_old(&"boss_armor"):
		return legacy_hp_u * U
	return hp_u * U

static var _by_kind: Dictionary = {}
static var _loaded := false

## Описание для вида врага игры (Enemy.Kind → строка). null — нет описания.
static func for_kind(kind_name: String) -> EnemyDef:
	if not _loaded:
		_loaded = true
		for f in ResourceLoader.list_directory("res://enemies/defs/"):
			if f.get_extension() == "tres":
				var d := load("res://enemies/defs/" + f) as EnemyDef
				if d and d.game_kind != "" and d.implemented:
					_by_kind[d.game_kind] = d
	return _by_kind.get(kind_name)
