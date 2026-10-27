extends Resource
class_name WeaponDef
## Оружие правой руки: мили (средневековое, бесконечное) или ренж (дальнобойное, патроны).
## Новое оружие — новый файл в weapons/defs/ (дублируй .tres и меняй поля в инспекторе), код не нужен.
## Урон в GDD — в «У»: 1 У = 22 урона (см. U ниже).

const U := 22.0

@export var id: String = "axe"
@export var display_name: String = "Топор"
@export_multiline var description: String = ""
@export_enum("melee", "ranged") var weapon_class: String = "melee"
## Стиль удара (эффекты, комиксовые слова): blade — рубящее/режущее, blunt — дробящее, pierce — колющее/пули
@export_enum("blade", "blunt", "pierce") var style: String = "blade"
## Урон одного удара (мили — до множителя ступени комбо) или одной пули/дробины (ренж)
@export var damage: float = 22.0
## Множитель скорости бега, пока оружие в руке
@export var move_speed_mult: float = 1.0
## Множитель времени перезарядки рывка, пока оружие в руке (ренж — дольше)
@export var dash_recharge_mult: float = 1.0
## Особое свойство (id) для будущих механик: parry, pin, invis_backstab… Пусто — нет.
@export var special: String = ""

@export_group("Выпадение")
## Есть ли в пуле выпадения с самого начала (остальное — после открытий, см. WeaponHolder.drop_all_weapons)
@export var in_drop_pool: bool = true
## Убрано из игры (владелец 27.10: нет хорошей модели) — не выпадает, не продаётся, не стартовое. Вернуть — снять флаг.
@export var retired: bool = false
@export var drop_weight: float = 1.0

@export_group("Модель")
## Ключ WeaponMeshes.build (q_axe, q_sword, club, crossbow, gun_pistol…)
@export var model: String = "q_axe"
## Положение модели в кулаке (рукоять вдоль +Y от точки хвата, лезвие/ствол в -Z)
@export var view_offset: Vector3 = Vector3.ZERO
@export var view_rotation: Vector3 = Vector3.ZERO
@export var view_scale: float = 1.0
## Поза руки в покое (позиция/поворот пивота вьюмодели)
@export var view_rest_pos: Vector3 = Vector3(0.46, -0.36, -0.95)
@export var view_rest_rot: Vector3 = Vector3(-8, 12, -14)
## Масштаб модели, лежащей на полу
@export var pickup_scale: float = 1.0

@export_group("Мили")
## Во сколько раз быстрее базовых таймингов топора (замах/удар/восстановление делятся на это)
@export var attack_speed: float = 1.0
## Дальность взмаха (множитель хода хитбокса вперёд)
@export var reach: float = 1.0
## Ширина дуги (множитель ширины хитбокса): коса — 180°
@export var arc: float = 1.0
## Ударов в комбо; последний — добивающий («melee_finisher»)
@export var combo_count: int = 3
## Набор поз взмаха: slash — рубящие, thrust — тычки
@export_enum("slash", "thrust") var swing_set: String = "slash"
## Множитель урона по ступеням комбо (короче combo_count — повторяется последний не-финальный)
@export var stage_damage_mult: Array[float] = [1.0, 1.0, 2.2]
@export var knockback_mult: float = 1.0
## Сколько врагов задевает один взмах (0 — без ограничений)
@export var max_targets: int = 0
## Оглушение врага при попадании, с (дубина)
@export var stun_on_hit: float = 0.0
## Урон в спину
@export var backstab_mult: float = 1.5
## Урон по оглушённым (кирка ×2)
@export var stunned_mult: float = 1.0
## Сильный удар (зажать ЛКМ): множитель урона и замах
@export var heavy_damage_mult: float = 2.0
@export var heavy_windup: float = 0.4
@export var hitstop_mult: float = 1.0

@export_group("Ренж")
## Пауза между выстрелами, с
@export var fire_interval: float = 0.25
## Стреляет, пока зажат курок
@export var automatic: bool = false
## Дробин за выстрел
@export var pellets: int = 1
## Разброс (градусы) и его рост от стрельбы
@export var spread_deg: float = 0.5
@export var spread_per_shot_deg: float = 0.0
@export var spread_max_deg: float = 6.0
## Скорость возврата разброса, град/с
@export var spread_recover: float = 10.0
## Визуальная отдача камеры (вверх), градусы
@export var recoil_kick_deg: float = 1.2
## Прицел уходит вверх насовсем на столько градусов за выстрел (автомат)
@export var recoil_climb_deg: float = 0.0
@export var mag_size: int = 8
## Запас патронов при выдаче и его предел
@export var reserve_start: int = 40
@export var reserve_max: int = 40
@export var reload_time: float = 1.1
## Сколько врагов пробивает пуля/болт насквозь
@export var pierce: int = 0
@export var max_range: float = 70.0
## Множитель скорости бега во время стрельбы (вместо move_speed_mult)
@export var fire_move_mult: float = 0.65
## Вид трассера: bullet / bolt / pellet
@export_enum("bullet", "bolt", "pellet") var tracer: String = "bullet"
@export var tracer_speed: float = 160.0
@export var shell_casing: bool = true
## Дуло в системе модели оружия (до view_scale)
@export var muzzle_offset: Vector3 = Vector3(0, 0.1, -0.3)
@export var muzzle_flash_size: float = 1.0
@export var sound_fire: String = "sounds/sfx/gun_pistol.wav"
@export var sound_reload: String = "sounds/sfx/gun_reload.wav"
## Тряска камеры на выстрел
@export var shake: float = 0.06

func is_ranged() -> bool:
	return weapon_class == "ranged"

## Уровень оружия 1–3 (заточка): +20 % урона за уровень.
static func level_mult(level: int) -> float:
	return 1.0 + 0.2 * (clampi(level, 1, 3) - 1)
