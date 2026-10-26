extends Resource
class_name BodyDef
## Тело смертного воина, в которое вселяется дух Тора на забег.
## Создавай новые тела, дублируя файлы в run/bodies/ и меняя числа в инспекторе.

@export var id: String = "berserker"
@export var display_name: String = "Берсерк"
@export_multiline var description: String = ""
@export var max_health: float = 100.0
@export var move_speed: float = 8.0
@export var dash_charges: int = 2
@export var axe_damage_mult: float = 1.0
@export var hammer_damage_mult: float = 1.0
@export var glory_mult: float = 1.0
@export var hand_color: Color = Color(0.86, 0.66, 0.52)
## Цвет рукавов на руках от первого лица
@export var sleeve_color: Color = Color(0.45, 0.32, 0.22)
## Стартовое оружие (этап 1): мили — обязательно, ренж — может быть пусто
@export var start_melee: WeaponDef
@export var start_ranged: WeaponDef
## Стиль движения (GDD 7.3): base / nimble / nimble_plus / ram / jumper / heavy / slider — механика в блоке Л
@export_enum("base", "nimble", "nimble_plus", "ram", "jumper", "heavy", "slider") var movement_style: String = "base"
## Пассивка и изъян (GDD 6)
@export var passive: PassiveDef
@export var flaw: PassiveDef
## Цена открытия в «Плане тренировок» (0 — открыто с начала; само открытие — run/unlocks/body_*.tres)
@export var price: int = 0
## Смешное описание от Одина для экрана выбора тела
@export_multiline var odin_comment: String = ""

