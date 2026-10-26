extends Resource
class_name Economy
## Числа серебра (GDD 15.2) — run/economy.tres. Серебро с врагов — в enemies/defs/*.tres (silver_min/max),
## цены ларька — в run/shop/*.tres.

## Сундук (GDD 15.2: 20)
@export var chest_silver: int = 20
## Бочка, которую разбили (GDD 15.2: 3–8)
@export var barrel_silver_min: int = 3
@export var barrel_silver_max: int = 8
## Бочка «разбита», если её отбросило быстрее (м/с): удар-приземление, молот, сильный удар, рывок-таран
@export var barrel_break_speed: float = 8.0
## Элита (GDD 15.2 и 12.4: 10) — вместо серебра обычного врага
@export var elite_silver: int = 10
## Мини-босс (в GDD не указано — 0)
@export var miniboss_silver: int = 0

@export_group("Монеты")
## Сколько монет-моделей на одну выдачу максимум (номинал делится)
@export var max_coins_per_drop: int = 5
## Разлёт монет: скорость вбок / вверх
@export var coin_spread_speed: float = 3.0
@export var coin_up_speed: float = 5.0
@export var coin_gravity: float = 18.0
## Через сколько секунд монета летит к игроку (магнит)
@export var magnet_delay: float = 0.45
## Радиус магнита; после magnet_any_after секунд — с любого расстояния
@export var magnet_radius: float = 8.0
@export var magnet_any_after: float = 2.0
## Скорость полёта к игроку: старт и максимум (м/с), разгон
@export var magnet_speed_start: float = 5.0
@export var magnet_speed_max: float = 26.0
@export var magnet_accel: float = 40.0
## Монета засчитана ближе этого (м)
@export var collect_radius: float = 0.8
