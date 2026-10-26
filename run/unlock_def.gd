extends Resource
class_name UnlockDef
## Открытие «Плана тренировок Одина» (GDD 15.3): покупается за Славу между забегами.
## Дублируй файл в run/unlocks/ и меняй поля — новое открытие появится на экране само.
##
## kind:
##   weapon — оружие в пул выпадения (target_id = WeaponDef.id);
##   trait  — трейт Мьёльнира в пул (MjolnirTrait.id);
##   body   — тело (BodyDef.id);
##   rune   — руна в пул (RuneDef.id);
##   perk   — эффект навсегда: target_id = ключ (move_speed_pct, max_health, dash_charges,
##            catch_window, start_silver, shop_discount, first_rune_level), amount — величина.
## Пока у оружия/трейта/тела/руны нет определения в игре — открытие показывается «скоро» и не продаётся.
## Перк, который ещё не реализован, — available = false.

@export var id: String = ""
## Название в духе «Тор вспоминает…»
@export var title: String = ""
## Что даёт (видно на карточке)
@export_multiline var description: String = ""
## Реплика Одина после покупки (пусто — случайная из пула odin.plan_buy)
@export var odin_comment: String = ""
@export var price: int = 100
@export_enum("perk", "weapon", "trait", "body", "rune") var kind: String = "perk"
@export var target_id: String = ""
## Ещё цели того же типа (например, «Нашёл в сундуке Локи» — три ствола)
@export var extra_target_ids: PackedStringArray = []
## Величина эффекта для perk
@export var amount: float = 0.0
## id открытия, которое нужно купить раньше
@export var requires: String = ""
## Можно ли купить сейчас (перк уже работает в игре)
@export var available: bool = true
@export var glyph: String = ""
@export var icon: Texture2D
## Порядок на экране (меньше — выше)
@export var order: int = 0

func targets() -> PackedStringArray:
	var out := PackedStringArray([target_id])
	out.append_array(extra_target_ids)
	return out
