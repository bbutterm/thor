extends Resource
class_name WorldArtTuning
## «Ощущенческие» числа графики мира (комплект владельца docs/world_art/): декали, декор на стенах,
## атмосферные частицы (искры факелов и очага, пылинки, низкий туман). Данные — data/world_art.tres,
## WorldArt.cfg() читает его один раз. Что включено в мире (небо, туман, цвета) — RunMap (run/maps/<мир>.tres).

@export_group("Декали на полу")
## Круг прыжковой руны: диаметр относительно радиуса руны (текстура с полями)
@export var jump_circle_scale: float = 2.5
## Яркость круга прыжковой руны (больше 1 — светится в Glow) и «дыхание» (доля размера)
@export var jump_circle_energy: float = 1.3
@export var jump_circle_breath: float = 0.05
## Круг под дверью-наградой: диаметр, м, яркость и сдвиг вперёд от арки, м
@export var door_circle_size: float = 3.6
@export var door_circle_energy: float = 1.2
@export var door_circle_forward: float = 0.7
## Высота статичных декалей над полом (против мерцания), м
@export var decal_lift: float = 0.03

@export_group("Декор на стенах")
## Отступ картинки от стены, м
@export var wall_offset: float = 0.06
## Порог альфы (alpha scissor): ниже — дырка
@export_range(0.0, 1.0) var alpha_scissor: float = 0.4

@export_group("Искры факелов (ember)")
@export var torch_embers: int = 5
@export var torch_ember_life: float = 1.3
## Размер искры-квада, м (мин, макс): на текстуре — горсть искр
@export var torch_ember_size: Vector2 = Vector2(0.06, 0.12)
## Скорость подъёма, м/с (мин, макс)
@export var torch_ember_speed: Vector2 = Vector2(0.5, 1.1)
@export var ember_color: Color = Color(1.0, 0.62, 0.25, 0.9)

@export_group("Очаг длинного дома (ember + vfx_fire)")
@export var hearth_embers: int = 26
@export var hearth_ember_life: float = 2.4
@export var hearth_ember_size: Vector2 = Vector2(0.07, 0.15)
@export var hearth_ember_speed: Vector2 = Vector2(1.2, 2.6)
## Языки пламени очага (полоса vfx_fire, петля): сколько, высота, м (мин, макс)
@export var hearth_flames: int = 7
@export var hearth_flame_size: Vector2 = Vector2(1.1, 1.7)

@export_group("Пылинки (dust)")
## Пылинок на 100 м² пола (не больше dust_max)
@export var dust_per_100m2: float = 3.5
@export var dust_max: int = 40
@export var dust_life: float = 9.0
@export var dust_size: Vector2 = Vector2(0.06, 0.14)
## Высота облака пылинок над полом, м (от, до)
@export var dust_height: Vector2 = Vector2(0.6, 4.5)
@export var dust_color: Color = Color(1.0, 0.8, 0.55, 0.18)

@export_group("Низкий туман (fog_puff_01..04)")
## Клубов на 100 м² пола (не больше fog_max на вариант текстуры)
@export var fog_per_100m2: float = 4.0
@export var fog_max: int = 26
@export var fog_life: float = 16.0
## Размер клуба (лежит у пола), м
@export var fog_size: Vector2 = Vector2(3.5, 6.0)
## Высота клубов над полом, м (от, до)
@export var fog_height: Vector2 = Vector2(0.12, 0.85)
## Дрейф, м/с
@export var fog_drift: float = 0.18
## Сколько вариантов текстуры клуба (по эмиттеру на вариант, 1–4)
@export var fog_variants: int = 2
