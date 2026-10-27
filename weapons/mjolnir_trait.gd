extends Resource
class_name MjolnirTrait
## Трейт Мьёльнира (GDD 10, блок Б4). Три вида (kind):
##   element   — СТИХИЯ: что делает удар молота (эффект на враге + своя связка с ударом-приземлением).
##               Уровни меняют способ доставки: 1 — при попадании, 2 — след на полу, 3 — аура воткнутого молота,
##               4 — удар с неба при идеальном хвате (каждый уровень добавляет способ, старые остаются).
##   technique — ПРИЁМ: меняет глагол молота (бросок, полёт, возврат, хват). Уровни 1–2.
##   combo     — СВЯЗКА «стихия + приём»: не выбирается, включается сама, когда взяты обе части
##               (weapons/mjolnir_traits/combos/, Run.active_combos()).
## Данные — здесь, поведение — в handler (ресурс со скриптом-обработчиком, см. mjolnir_trait_handler.gd),
## его поля — «ощущенческие» числа трейта (правятся в инспекторе .tres).
## Новый трейт = новый .tres в weapons/mjolnir_traits/ (+ скрипт-обработчик), остальной код не трогаем.
## Правила выбора (сколько стихий и приёмов, наковальня) — weapons/mjolnir_rules.tres (MjolnirRules).

@export var id: StringName = &""
@export_enum("technique", "element", "combo") var kind: String = "technique"
@export var title: String = ""
@export_multiline var description: String = ""
## Что даёт второй уровень (повторно выпавший трейт)
@export_multiline var description_lvl2: String = ""
## Стихии: третий и четвёртый уровни (аура воткнутого молота, удар с неба)
@export_multiline var description_lvl3: String = ""
@export_multiline var description_lvl4: String = ""
## Руна-иконка (HUD, экран выбора), если нет картинки в UI-комплекте (UISkin.trait_icon)
@export var glyph: String = "ᛗ"
@export var color: Color = Color(0.5, 0.83, 1.0)
## Группа несовместимости (GDD 10): трейт той же группы заменяет старый (с подтверждением на экране выбора).
## Приёмы: «удержание ПКМ» (Буря, Праща, Заряд), «к молоту» (Притяжение, Обмен). Пусто — ни с кем.
## Стихии — группа «стихия» (заменяют друг друга, только если MjolnirRules.element_swap; иначе одна на забег).
@export var group: String = ""
## Ещё несовместимые трейты (id) — например, Бумеранг не втыкается, и приёмы «воткнутого молота» с ним не работают
@export var conflicts: Array[StringName] = []
@export_range(1, 4) var max_level: int = 2
## Открытия «Плана тренировок» по уровням (стихии): id цели UnlockDef для уровня (индекс = уровень − 1),
## пусто — уровень открыт всегда. Это бывшие трейты (ice_trail, lightning_rod, sky_thunder…): их открытия
## в run/unlocks/*.tres работают как раньше — открывают тот же способ доставки, только теперь у стихии.
@export var level_pool_ids: PackedStringArray = []
## Связка: из каких стихии и приёма складывается (только kind = combo)
@export var combo_element: StringName = &""
@export var combo_technique: StringName = &""
@export var handler: MjolnirTraitHandler

func is_element() -> bool:
	return kind == "element"

func is_technique() -> bool:
	return kind == "technique"

func is_combo() -> bool:
	return kind == "combo"

## Описание уровня lv (1…max_level); нет текста — описание первого уровня
func level_description(lv: int) -> String:
	var s := description
	match lv:
		2:
			s = description_lvl2
		3:
			s = description_lvl3
		4:
			s = description_lvl4
	return s if s != "" else description

## id открытия, которое нужно для уровня lv ("" — не нужно)
func level_pool_id(lv: int) -> String:
	var i := lv - 1
	return level_pool_ids[i] if i >= 0 and i < level_pool_ids.size() else ""

## Все id, на которые могут ссылаться открытия (Save.target_exists): свой и бывших трейтов-уровней
func all_ids() -> PackedStringArray:
	var out := PackedStringArray([str(id)])
	for s in level_pool_ids:
		if s != "" and not s in out:
			out.append(s)
	return out

## Несовместим ли с other (группа или список conflicts в любую сторону)
func conflicts_with(other: MjolnirTrait) -> bool:
	if other == null or other.id == id:
		return false
	if group != "" and group == other.group:
		return true
	return other.id in conflicts or id in other.conflicts
