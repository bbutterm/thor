extends Resource
class_name VfxTuning
## «Ощущенческие» числа VFX-комплекта (sprites/vfx/*): размеры, длительности, лимиты пулов, прозрачность.
## Данные — data/vfx_tuning.tres (открыть в инспекторе Godot); FX.cfg() читает его один раз.
## Экранные эффекты (линии скорости, виньетка Ярости, идеальный хват) — в scripts/vfx_screen.gd (@export там же).

@export_group("Вспышка попадания (vfx_hit_flash)")
## Размер вспышки, м (крупный удар — × hit_flash_big_mult)
@export var hit_flash_size: float = 0.9
@export var hit_flash_big_mult: float = 1.6
## Ренж-попадание — меньше
@export var hit_flash_ranged_mult: float = 0.55
## Длительность 6 кадров, с (манифест: 250 мс, 24 fps). Идёт в игровом времени — во время hit-stop «стоит»
@export var hit_flash_time: float = 0.25
## Насколько вспышку выдвинуть к камере, м (чтобы не утонула в теле врага)
@export var hit_flash_push: float = 0.45
@export var hit_flash_limit: int = 12

@export_group("Искры-звёзды (vfx_sparks_01..12)")
## Сколько звёзд поверх частиц FX.sparks (на каждые sparks_per_star частиц — одна, до sparks_max)
@export var sparks_per_star: int = 6
@export var sparks_max: int = 3
## Размер звезды, м (мин, макс)
@export var spark_size: Vector2 = Vector2(0.35, 0.7)
@export var spark_time: float = 0.22
## Разлёт звёзд от точки удара, м
@export var spark_spread: float = 0.45
## Частицы темнее этой яркости (пыль, щепки) звёзд не дают
@export var spark_min_luma: float = 0.55
@export var sparks_limit: int = 24

@export_group("Ихор нежити (vfx_ichor_splash / splat)")
## Брызги при уроне: размер, м (мин, макс), длительность
@export var ichor_splash_size: Vector2 = Vector2(0.7, 1.1)
@export var ichor_splash_time: float = 0.35
@export var ichor_splash_limit: int = 16
## Шанс пятна на полу при обычном ударе (крупный удар и смерть — всегда)
@export_range(0.0, 1.0) var splat_chance: float = 0.35
## Пятно на полу: размер, м (мин, макс); при смерти — × splat_death_mult
@export var splat_size: Vector2 = Vector2(0.9, 1.5)
@export var splat_death_mult: float = 1.5
## Сколько пятно лежит, с, и за сколько исчезает в конце
@export var splat_life: float = 10.0
@export var splat_fade: float = 2.0
## Прозрачность пятна (0 — непрозрачное)
@export_range(0.0, 1.0) var splat_transparency: float = 0.1
## Пул пятен: сверх лимита исчезает самое старое
@export var splat_limit: int = 24

@export_group("Дым (vfx_smoke)")
## Размер облака, м (на радиус взрыва — × smoke_per_radius)
@export var smoke_size: float = 1.6
@export var smoke_per_radius: float = 0.9
## Длительность 8 кадров, с (манифест: 500 мс)
@export var smoke_time: float = 0.5
## Подъём облака за время жизни, м
@export var smoke_rise: float = 0.8
@export_range(0.0, 1.0) var smoke_transparency: float = 0.15
@export var smoke_limit: int = 12
## Пыль разбитой бочки, м
@export var barrel_dust_size: float = 1.3

@export_group("Взрыв (enemies/blast.gd → FX.explosion)")
## Вспышка-ядро vfx_hit_flash: размер на 1 м радиуса взрыва
@export var explosion_flash: float = 1.15
## Огненный шар из языков vfx_fire: радиус шара на 1 м радиуса взрыва, масштаб языков, сколько горит, с
@export var explosion_fire: float = 0.45
@export var explosion_fire_scale: float = 1.5
@export var explosion_fire_time: float = 0.55
## Клубы дыма vfx_smoke: сколько, размер на 1 м радиуса, цвет
@export var explosion_smoke: int = 3
@export var explosion_smoke_size: float = 0.85
@export var explosion_smoke_color: Color = Color(0.36, 0.32, 0.3)
## Звёзды-искры vfx_sparks поверх частиц: сколько и размер, м
@export var explosion_stars: int = 3
@export var explosion_star_size: float = 1.1

@export_group("Серебро")
## Блеск-звёздочка при вылете монеты: размер, м (0 — нет), и не чаще раза в столько секунд
@export var coin_glint_size: float = 0.3
@export var coin_glint_interval: float = 0.06

@export_group("Огонь (vfx_fire)")
## Языков пламени на 1 м радиуса зоны (не больше fire_max)
@export var fire_per_meter: float = 2.0
@export var fire_max: int = 7
## Высота языка, м (мин, макс)
@export var fire_height: Vector2 = Vector2(1.2, 1.9)
## Кадров в секунду (манифест: 16, петля)
@export var fire_fps: float = 16.0
## Появление и угасание, с
@export var fire_fade: float = 0.25

@export_group("Молния (vfx_lightning_01..04)")
## Длина одного отрезка-текстуры, м (длинная молния — несколько отрезков)
@export var lightning_segment: float = 2.6
## Ширина ленты относительно длины отрезка (текстура 1:3)
@export var lightning_width: float = 0.5
## Отрезки внахлёст: длина квада × столько (рисованная молния не доходит до краёв текстуры)
@export var lightning_overlap: float = 1.35
## Яркость (больше 1 — светится в Glow)
@export var lightning_energy: float = 2.2
## Тонкая линия-примитив в сердцевине поверх текстуры (0 — нет)
@export var lightning_core_alpha: float = 0.6
@export var lightning_limit: int = 32

@export_group("Удар-приземление (vfx_shockwave, vfx_crack_decal_*)")
## Ударная волна: во сколько раз больше радиуса удара в конце, длительность
@export var shockwave_scale: float = 2.1
@export var shockwave_time: float = 0.38
## Прозрачность волны в начале (0 — непрозрачная)
@export_range(0.0, 1.0) var shockwave_transparency: float = 0.45
@export var shockwave_limit: int = 4
## Трещина: с какой высоты падения средняя и крупная, м
@export var crack_medium_height: float = 4.0
@export var crack_large_height: float = 10.0
## Размер трещины (малая, средняя, крупная), м
@export var crack_sizes: Vector3 = Vector3(2.2, 3.6, 5.5)
## Сколько лежит, с, и за сколько исчезает
@export var crack_life: float = 6.0
@export var crack_fade: float = 1.5
@export var crack_limit: int = 6

@export_group("Лёд (vfx_ice_patch, vfx_ice_shard_01..05)")
## Наледь под Тором при ударе ледяной элиты: размер, м
@export var ice_patch_size: float = 2.2
@export var ice_patch_limit: int = 4
## Кристаллы вокруг: сколько, высота (мин, макс), радиус
@export var ice_shards: int = 3
@export var ice_shard_height: Vector2 = Vector2(0.45, 0.8)
@export var ice_shard_radius: float = 0.8
## Рост кристалла и сколько он стоит (доля времени замедления)
@export var ice_shard_grow: float = 0.12
@export var ice_shard_stay: float = 0.5
@export var ice_shard_limit: int = 16

@export_group("Декали на полу")
## Высота над полом (против мерцания с полом), м
@export var decal_lift: float = 0.025

@export_group("Подпалина (assets/decals/scorch — огонь, взрыв)")
## Размер подпалины относительно радиуса огня/взрыва (диаметр = радиус × столько), м
@export var scorch_per_radius: float = 1.7
## Пределы размера, м
@export var scorch_size: Vector2 = Vector2(1.4, 6.0)
## Сколько лежит, с (после конца огня), и за сколько исчезает
@export var scorch_life: float = 8.0
@export var scorch_fade: float = 2.5
## Прозрачность (0 — непрозрачная)
@export_range(0.0, 1.0) var scorch_transparency: float = 0.12
## Пул подпалин: сверх лимита исчезает самая старая
@export var scorch_limit: int = 10
