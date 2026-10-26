extends Resource
class_name RuneDef
## Руна-улучшение, выбирается после зачистки зала. Эффект применяется в player.gd по id.

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var glyph: String = "ᚠ"
@export var color: Color = Color(0.4, 0.75, 1.0)
## Категория по GDD 11: attack / mjolnir / movement / slam / defense / ranged / rage / meta (цвет руны — по категории)
@export var category: String = "attack"
## Что даёт руна на уровнях 1–3 (повторная руна повышает уровень — блок Т)
@export var level_descriptions: PackedStringArray = []
## Механика есть в игре; false — руна только в данных и не выпадает
@export var implemented: bool = true
