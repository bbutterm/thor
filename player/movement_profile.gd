extends Resource
class_name MovementProfile
## Стиль движения тела (GDD 7.3): набор чисел и флагов, которые Player.apply_movement_profile() кладёт
## в свои поля (наследников у игрока нет — только параметры). Данные — run/movement/<style>.tres,
## имя файла = BodyDef.movement_style. Число зарядов рывка — у тела (BodyDef.dash_charges), чтобы
## перк «+1 рывок» работал у всех.

@export var id: String = "base"
@export var title: String = "Базовый"
## Коротко для экрана выбора тела
@export_multiline var description: String = ""

@export_group("Рывок")
@export var dash_speed: float = 24.0
@export var dash_duration: float = 0.16
## Перезарядка одного заряда, с
@export var dash_recharge: float = 2.5
## Рывок на земле / в воздухе разрешён
@export var dash_on_ground: bool = true
@export var dash_in_air: bool = true

@export_group("Таран")
## Рывок проходит сквозь врагов и бьёт каждого (GDD 7.3: 0.7 У), отбрасывает, толкает бочки
@export var dash_ram: bool = false
@export var ram_damage: float = 15.4
@export var ram_knockback: float = 13.0
@export var ram_knock_up: float = 4.0
@export var ram_radius: float = 1.4
## Толчок бочек и ящиков (импульс × масса)
@export var ram_prop_impulse: float = 9.0

@export_group("Подкат")
## Рывок на земле переходит в подкат, скорость не гасится (Скользящий)
@export var dash_to_slide: bool = false
## Трение подката (м/с²): 0 — скорость не гасится вовсе
@export var slide_friction: float = 9.0

@export_group("Прыжки")
## Прыжков в воздухе: 1 — двойной, 2 — тройной, 0 — нет двойного
@export var extra_jumps: int = 1
## Отскоков от стены до касания земли и их сила (множитель к базовой)
@export var wall_jumps: int = 2
@export var wall_jump_mult: float = 1.0

@export_group("Удар-приземление")
@export var slam_radius_mult: float = 1.0
@export var slam_damage_mult: float = 1.0
## Стан врагов от удара-приземления, с (0 — нет)
@export var slam_stun: float = 0.0
## Отскок от удара-приземления (множитель к высоте)
@export var slam_bounce_mult: float = 1.0

@export_group("Импульс (GDD 7.4)")
## Предел горизонтальной скорости от рывка, подката и отскоков — во сколько раз выше бега
@export var momentum_cap: float = 1.8
## Скорость выше бега в воздухе не гасится (Скользящий: bunny-hop)
@export var keep_air_momentum: bool = false

const DIR := "res://run/movement/"

static func for_style(style: String) -> MovementProfile:
	var path := DIR + style + ".tres"
	if style != "" and ResourceLoader.exists(path):
		return load(path) as MovementProfile
	return load(DIR + "base.tres") as MovementProfile
