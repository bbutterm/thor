extends Resource
class_name ShopItemDef
## Товар ларька Брокка и Эйтри (GDD 13) — run/shop/*.tres. Эффект — по id в run/shop.gd (Shop.buy).
## id: shawarma, rune, sharpen, ammo, mjolnir_service, mystery_bag, sell_rune.

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
## Цена в серебре (у «Сдать руну» — сколько получишь)
@export var price: int = 40
## Вторая цена: заточка 2 → 3 уровня (GDD 13: 80 / 120)
@export var price2: int = 0
## true — серебро не тратится, а приходит (сдать руну)
@export var pays_player: bool = false
@export var glyph: String = "ᚠ"
@export var color: Color = Color(0.93, 0.71, 0.3)
## Делает Эйтри (реплика «Угу»), а не Брокк
@export var by_eitri: bool = false
## Реплика Одина после покупки (пул odin.<имя>), пусто — без реплики
@export var odin_pool: String = ""
## Число эффекта: шаурма — доля лечения
@export var amount: float = 0.0
## Порядок в списке
@export var order: int = 0
