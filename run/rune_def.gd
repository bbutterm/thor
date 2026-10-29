extends Resource
class_name RuneDef
## Руна-улучшение, выбирается после зачистки зала. Эффект применяется в player.gd по id.

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var glyph: String = "ᚠ"
@export var color: Color = Color(0.4, 0.75, 1.0)
## Категория по GDD 11: attack / mjolnir / movement / slam / defense / ranged / rage (шкала стиля) / meta (цвет руны — по категории)
@export var category: String = "attack"
## Что даёт руна на уровнях 1–3 (повторная руна повышает уровень — блок Т)
@export var level_descriptions: PackedStringArray = []
## Механика есть в игре; false — руна только в данных и не выпадает
@export var implemented: bool = true
## Числа уровней 1–3 (GDD 11) и второе число, если руна даёт два эффекта (Гнев Мьёльнира: урон и возврат)
@export var level_values: PackedFloat32Array = []
@export var level_values_b: PackedFloat32Array = []
## Как руна усиливается у Старого жреца («все руны ×2»): add — значение ×2, mult — (значение − 1) ×2 + 1,
## interval — «каждый N-й» становится чаще (N / 2)
@export_enum("add", "mult", "interval") var value_kind: String = "add"
## Проклятая руна Локи: сильный плюс и смешной минус, выпадает только в особых событиях (сделка Локи)
@export var cursed: bool = false
## Клятва Одина (С3): большой плюс и явная цена; в выборе рун — одна карточка из трёх примерно в каждом
## третьем выборе (RunManager.oath_chance), уровень один, снять нельзя. Эффекты — run/oaths.gd
@export var oath: bool = false
## Цена клятвы — красной строкой на карточке
@export var oath_cost: String = ""

