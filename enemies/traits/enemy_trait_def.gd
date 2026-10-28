extends Resource
class_name EnemyTraitDef
## Черта моба (GDD 12.6; не элита): мелкая читаемая особенность бойца или особого врага.
## Данные — enemies/traits/*.tres, поведение — обработчик (handler, наследник EnemyTraitHandler), узел на враге.
## Выдаёт EnemyTraits.maybe_assign (Room._spawn_enemy): ~20–25 % бойцов и особых (Room.trait_chance),
## корм и боссы — никогда, не вместе с элитой, не больше Room.max_traited на зал.
## Значок над головой — маленькая фигура на общем меше и общем материале эффектов (без нового материала).

@export var id: String = ""
@export var title: String = ""
## Цвет значка
@export var color: Color = Color(1, 1, 1)
## Фигура значка: общий меш FX ("sphere" / "box" / "ring" / "wedge")
@export_enum("sphere", "box", "ring", "wedge") var icon_shape: String = "sphere"
@export var icon_scale: Vector3 = Vector3(0.22, 0.22, 0.22)
@export var icon_rotation: Vector3 = Vector3.ZERO
@export var handler: Script
@export var enabled: bool = true
@export var weight: float = 1.0

@export_group("Трус")
## Убегает, когда HP ниже этой доли, на flee_time секунд; зовёт соседей в call_radius
@export var flee_hp: float = 0.3
@export var flee_time: float = 3.0
@export var call_radius: float = 10.0

@export_group("Яростный")
## После попадания по нему: скорость ×rage_speed_mult и перезарядка атаки ×rage_cooldown_mult на rage_time секунд
@export var rage_speed_mult: float = 1.4
@export var rage_cooldown_mult: float = 0.6
@export var rage_time: float = 4.0

@export_group("Ловкий")
## Уворачивается от летящего Мьёльнира раз в dodge_interval секунд: замечает его ближе dodge_detect м
@export var dodge_interval: float = 6.0
@export var dodge_detect: float = 6.0
@export var dodge_speed: float = 11.0

@export_group("Крикун")
## Заметив Тора, будит всех врагов в радиусе
@export var shout_radius: float = 18.0

@export_group("Тяжёлый")
## Не отлетает от обычных ударов (сопротивление отбрасыванию)
@export var heavy_knock_resist: float = 0.85

@export_group("Прыгун")
## Прыгает к Тору с leap_min–leap_max м раз в leap_cooldown секунд, полёт leap_time
@export var leap_min: float = 6.0
@export var leap_max: float = 8.0
@export var leap_cooldown: float = 5.0
@export var leap_time: float = 0.6
