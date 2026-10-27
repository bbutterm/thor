extends Node3D
class_name WallDecor
## Картинка на стене из комплекта владельца (assets/decor/: щит, знамя, гобелен, плакат): плоский квад с альфой,
## без коллизии и тени, лицом к +Z узла. Ставят генератор (ключ "decor" у зала и авто-расстановка по стенам,
## tools/build_scenes.gd) и разовые скрипты ручных арен (tools/dress_longhouse_art.tscn). Вид собирается
## при запуске (WorldArt.decor_quad): общий меш и общий материал на текстуру, без instance uniform.

## Ключ картинки — имя файла в assets/decor/ без расширения
@export var art: String = "shield_sun"
## Высота самой картинки (без прозрачных полей), м; ширина — по пропорциям
@export var height: float = 1.0

func _ready() -> void:
	add_to_group("wall_decor")
	if get_child_count() > 0:
		return
	WorldArt.decor_quad(self, art, height)
