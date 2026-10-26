extends Resource
class_name RewardDef
## Награда зала за дверью (GDD 15.1, «двери как в Hades»). Над каждой дверью — иконка награды;
## награда выдаётся после зачистки зала, в который вошёл через эту дверь.
## Файлы — run/rewards/*.tres; частота (weight) — проценты из таблицы GDD 15.1.
## Иконка: sprites/ui/icons/door_<icon_name>.png (UI_PROMPTS.txt 4.1); нет файла — руна-глиф и цвет.

@export var id: String = ""
@export var title: String = ""
## Что получишь (подпись под иконкой и в тестах)
@export_multiline var description: String = ""
@export var glyph: String = "ᚱ"
@export var color: Color = Color(0.93, 0.71, 0.3)
## Имя PNG без префикса: rune, weapon, chest, rest, shop, trial, loki, freya, hammer
@export var icon_name: String = ""
## Частота в случайном наборе дверей, % (GDD 15.1). 0 — только по особым правилам (ларёк, мини-босс, босс)
@export var weight: float = 0.0
## В зале есть бой (false — тихий зал: отдых, ларёк)
@export var combat: bool = true
## Можно предлагать (false — механики ещё нет)
@export var enabled: bool = true

const ICON_DIR := "res://sprites/ui/icons/door_"

func icon_path() -> String:
	return ICON_DIR + (icon_name if icon_name != "" else id) + ".png"

## Текстура иконки, если владелец её положил (иначе null — процедурная заглушка).
func icon() -> Texture2D:
	var p := icon_path()
	return load(p) as Texture2D if ResourceLoader.exists(p) else null
