extends Resource
class_name PassiveDef
## Пассивка или изъян тела (GDD 6). Блок Г — только данные; хуки (on_kill, on_hit, on_damaged, on_dash, on_slam)
## добавит блок Л. implemented = false — механики пока нет, на экране выбора тела помечается «скоро».

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
## Изъян (отрицательная черта), а не пассивка
@export var is_flaw: bool = false
## Механика уже работает в игре
@export var implemented: bool = false
