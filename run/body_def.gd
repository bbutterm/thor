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
