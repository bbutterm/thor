extends Resource
class_name OutlineTuning
## Числа комиксовой обводки (GDD 20, scripts/outline.gd, shaders/outline.gdshader). Данные — data/outline_tuning.tres.
## Включение и множитель толщины — настройки игрока ([video] outline / outline_width, GameSettings).

@export_group("Линия")
@export var color: Color = Color(0.03, 0.02, 0.02, 1.0)
## Толщина у близких объектов, px при высоте кадра 1080 (720p — ×0.67)
@export var width_px: float = 5.0
## До этого расстояния (м) — полная толщина, дальше тоньше (∝ 1/расстояние)
@export var near_dist: float = 6.0
## Дальняя обводка — не тоньше этой доли от полной
@export_range(0.0, 1.0) var min_scale: float = 0.4
## Оболочка отодвинута от камеры (м): не мерцает на плащах/волосах, прячется под одеждой
@export var depth_push: float = 0.04

@export_group("Кому")
# Руки и оружие от первого лица (свой SubViewport) — без обводки: по кадрам (tests/outline_shots.tscn, 04_hands)
# у рисованного топора вылезают чёрные пятна изнутри (тонкие двусторонние лезвия), у кулаков у края кадра — толстая
# чёрная полоса; читаемость своих рук не нужна.
## Мьёльнир в полёте/воткнутый (мировая модель)
@export var mjolnir_projectile: bool = true
