extends Resource
class_name DestructTuning
## Числа разрушаемых пропсов (props/destructible.gd, props/prop_debris.gd) — props/destruct_tuning.tres.
## Прочность и содержимое конкретного пропса — @export на его сцене (генератор: build_props),
## шансы содержимого ящика — run/economy.tres.

@export_group("Урон по пропсам")
## Множитель урона по источнику: ренж слабый по одной пуле — ×2 (бочка ломается с 2–3 выстрелов);
## удар-приземление и взрывы ×1.5, удары врагов по площади ×2 — ломают и ящик с одного удара
@export var source_mult: Dictionary = {"ranged": 2.0, "slam": 1.5, "enemy_slam": 2.0, "explosion": 1.5}
## Удар-приземление бьёт пропсы без спада к краю радиуса (урон центра) — ломает всё вокруг
@export var slam_full_damage: bool = true
## Урон рывка по пропсу (любой рывок, один раз за рывок; таран — тоже)
@export var dash_damage: float = 40.0
## Урон тарана босса (Свен, Ярл) по пропсу на пути
@export var boss_charge_damage: float = 80.0

@export_group("Обломки")
## Сколько обломков пропсов живёт в зале одновременно; сверх — самые старые исчезают сразу
@export var debris_limit: int = 40
## Сколько секунд обломок лежит, потом проваливается в пол
@export var debris_life: float = 3.5
## Провал в пол (с) и глубина (м)
@export var debris_sink_time: float = 0.7
@export var debris_sink_depth: float = 0.45
## Разлёт: скорость по направлению удара (доля от силы удара, м/с), от центра, вверх; вращение (рад/с)
@export var debris_knock_ratio: float = 0.55
@export var debris_knock_max: float = 11.0
@export var debris_outward: float = 2.6
@export var debris_up: float = 2.8
@export var debris_spin: float = 9.0
## Масса обломка (кг) — лёгкие, не толкают бочки
@export var debris_mass: float = 0.35

@export_group("Отдача")
## Хит-стоп, если пропс разбил Тор (мили, молот, рывок, удар-приземление)
@export var break_hitstop: float = 0.035
## Тряска камеры при разрушении рядом с Тором (≤ 6 м)
@export var break_shake: float = 0.12
## Удар без разрушения: щепки (шт.)
@export var hit_chips: int = 5
