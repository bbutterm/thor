extends Resource
class_name SquadMember
## Участник отряда (SquadDef): вид × количество, роль поведения (EnemyTactics), место в строю.

## Вид врага: grunt / thrower / fodder / bloated / shieldbearer / shaman / merc
@export var kind: String = "grunt"
@export var count: int = 1
## Роль (EnemyTactics.ROLE_NAMES): "" — по виду; surround / flank / cover / escort / lurk / none
@export var role: String = ""
## Ряд строя: 0 — передний, 1 — задний, 2 — центр (якорь кольца)
@export_range(0, 2) var row: int = 0
## Множитель скорости (быстрые бойцы засады)
@export var speed_mult: float = 1.0
## Якорь отряда (шаман свиты): свита с ролью escort держится вокруг него
@export var anchor: bool = false
