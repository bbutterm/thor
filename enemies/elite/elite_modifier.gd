extends Resource
class_name EliteModifier
## Модификатор элиты (GDD 12.4). Данные — в enemies/elite/mods/*.tres, поведение — скрипт-обработчик
## (handler, наследник EliteHandler), который вешается на врага узлом. Новый модификатор = новый .tres
## (+ свой обработчик, если нужно новое поведение). Пустые поля обработчики не читают.

@export var id: String = ""
## Подпись над элитой
@export var title: String = ""
## Цвет подписи, свечения и кольца под ногами
@export var color: Color = Color(1.0, 0.72, 0.2)
## Скрипт-обработчик (extends EliteHandler)
@export var handler: Script
## Участвует в случайном выборе
@export var enabled: bool = true
@export var weight: float = 1.0

@export_group("Быстрый")
@export var speed_mult: float = 1.0

@export_group("Бронированный")
## Сколько урона (в «У», 1 У = 22) броня съедает, прежде чем урон пойдёт в HP
@export var armor_u: float = 0.0

@export_group("Ледяной")
## Удар замедляет Тора: множитель скорости бега и длительность
@export var slow_mult: float = 1.0
@export var slow_time: float = 0.0

@export_group("Вампир")
## Лечится на столько × нанесённого урона
@export var heal_ratio: float = 0.0

@export_group("Огненный")
## Раз в столько секунд на ходу оставляет лужу огня
@export var trail_interval: float = 0.0
@export var trail_radius: float = 1.2
@export var trail_duration: float = 3.0
## Урон огня Тору в секунду
@export var trail_dps: float = 12.0
## Сколько луж держится одновременно (старые гаснут)
@export var trail_max: int = 6

@export_group("Взрывной")
@export var blast_radius: float = 0.0
## Урон взрыва, «У»
@export var blast_damage_u: float = 0.0
## Телеграф перед взрывом, с
@export var blast_delay: float = 0.8

@export_group("Призыватель")
@export var summon_interval: float = 0.0
@export var summon_count: int = 3
@export var summon_kind: String = "fodder"
## Телеграф перед призывом, с
@export var summon_windup: float = 1.0
## Не призывает, если врагов в зале уже столько
@export var summon_cap: int = 30
