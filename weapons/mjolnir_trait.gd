extends Resource
class_name MjolnirTrait
## Трейт Мьёльнира (GDD 10): меняет то, КАК играешь молотом. Выпадает с мини-боссов (выбор 1 из 3).
## Данные — здесь, поведение — в handler (ресурс со скриптом-обработчиком, см. mjolnir_trait_handler.gd),
## его поля — «ощущенческие» числа трейта (правятся в инспекторе .tres).
## Новый трейт = новый .tres в weapons/mjolnir_traits/ (+ скрипт-обработчик), остальной код не трогаем.

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var description: String = ""
## Что даёт второй уровень (повторно выпавший трейт)
@export_multiline var description_lvl2: String = ""
## Руна-иконка (HUD, экран выбора)
@export var glyph: String = "ᛗ"
@export var color: Color = Color(0.5, 0.83, 1.0)
## Группа несовместимости (GDD 10): след / возврат / попадание / воткнулся / бросок. Пусто — ни с кем.
## Трейт той же группы заменяет старый (с подтверждением на экране выбора).
@export var group: String = ""
@export_range(1, 3) var max_level: int = 2
@export var handler: MjolnirTraitHandler
