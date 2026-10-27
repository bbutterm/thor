extends Resource
class_name ViewmodelMotionTuning
## Числа анимации рук от первого лица (блок Б2). Данные — player/viewmodel_motion.tres, описание — TUNING.md.
## Смещения — в метрах системы камеры рук (x вправо, y вверх, z к камере), повороты — градусы (x — кивок, y — рыскание, z — крен).

@export_group("Пружины")
## Жёсткость и затухание пружины добавок (отдача, ловля, приземление): больше — быстрее и резче возврат
@export var spring_stiffness: float = 170.0
@export var spring_damping: float = 17.0
## Пружина качания за мышью (общая для обеих рук)
@export var sway_stiffness: float = 90.0
@export var sway_damping: float = 13.0
## Считать руку вернувшейся в покой, когда пружины тише этого (м и град.)
@export var settle_epsilon: float = 0.004

@export_group("Покачивание при беге")
## Амплитуда при обычной скорости бега: вбок, вверх-вниз (м), крен (град.)
@export var bob_side: float = 0.022
@export var bob_up: float = 0.018
@export var bob_roll: float = 1.4
## Шагов в секунду на 1 м/с (фаза идёт от горизонтальной скорости)
@export var bob_freq_per_speed: float = 0.19
## Множитель выше обычной скорости (после рывка) — не больше
@export var bob_max_speed_ratio: float = 1.6
## Покачивание выключено в настройках («покачивание») — оставить эту долю (0 — совсем нет)
@export var bob_when_disabled: float = 0.0
## Дыхание в покое: амплитуда (м) и частота (Гц)
@export var idle_breath: float = 0.004
@export var idle_breath_freq: float = 0.35

@export_group("Качание за мышью")
## Сдвиг рук за поворотом камеры: м на радиан и град. на радиан (запаздывание)
@export var sway_pos_per_rad: float = 0.09
@export var sway_rot_per_rad: float = 9.0
## Предел сдвига (м) и поворота (град.)
@export var sway_max_pos: float = 0.06
@export var sway_max_rot: float = 6.0

@export_group("Прыжок, приземление, рывок")
## Толчок рук вверх при прыжке (скорость пружины, м/с) и при прыжке в воздухе
@export var jump_kick: float = 0.55
@export var air_jump_kick: float = 0.35
## Приседание рук при приземлении: м/с пружины на метр падения, предел; удар-приземление — отдельно
@export var land_kick_per_meter: float = 0.24
@export var land_kick_max: float = 1.6
@export var land_min_fall: float = 0.6
@export var slam_land_kick: float = 2.6
## Наклон рук вперёд при приземлении (град./с пружины на единицу толчка)
@export var land_tilt: float = 60.0
## Рывок: руки отводятся назад и вниз, пока он идёт (м), и толчок в начале
@export var dash_pull: Vector3 = Vector3(0.0, -0.05, 0.14)
@export var dash_tilt: Vector3 = Vector3(-8.0, 0.0, 0.0)
@export var dash_kick: float = 0.8
## Подкат: руки ниже и с креном
@export var slide_offset: Vector3 = Vector3(0.02, -0.06, 0.04)
@export var slide_roll: float = 7.0
## В воздухе руки чуть приподняты (от вертикальной скорости, м на 10 м/с)
@export var air_lift_per_speed: float = 0.03
## Скорость сглаживания постоянных добавок (рывок, подкат, воздух), 1/с
@export var offset_smooth: float = 14.0

@export_group("Мили")
## Запястье на замахе (взведено) и на ударе (доворот), град.: x — к себе/от себя, y — вбок
@export var windup_wrist: Vector3 = Vector3(-18.0, 0.0, 0.0)
@export var strike_wrist: Vector3 = Vector3(14.0, 0.0, 0.0)
## Доводка удара (импульс пружины в сторону взмаха, м/с) и отдача от попадания (град./с)
@export var strike_follow: float = 0.9
@export var hit_recoil: float = 180.0
## Восстановление: доля пути от конечной позы обратно к покою за время восстановления
@export var recovery_blend: float = 0.45
## Добивающий: толчок вниз в конце удара (м/с) и тряска
@export var finisher_kick: float = 1.4
## Сильный удар: дрожь при наборе (град.) и толчок на выпуске (м/с)
@export var heavy_tremor: float = 1.6
@export var heavy_release_kick: float = 1.9

@export_group("Мьёльнир")
## Бросок: взведённая поза (за плечом) → выпуск (рука вперёд) → пустая рука
@export var throw_cock_pos: Vector3 = Vector3(-0.15, 0.22, 0.25)
@export var throw_cock_rot: Vector3 = Vector3(55.0, -10.0, 20.0)
@export var throw_release_pos: Vector3 = Vector3(0.28, 0.08, -0.32)
@export var throw_release_rot: Vector3 = Vector3(-50.0, -15.0, 0.0)
@export var throw_time: float = 0.07
## Пустая рука: поза (смещение от покоя) и время, за которое она туда опускается
@export var empty_pos: Vector3 = Vector3(-0.02, -0.12, 0.12)
@export var empty_rot: Vector3 = Vector3(-15.0, 10.0, 25.0)
@export var empty_time: float = 0.28
## Возврат: рука тянется навстречу молоту (смещение от покоя), доля «тянуться к молоту» по экрану
@export var recall_pos: Vector3 = Vector3(0.14, 0.06, -0.12)
@export var recall_rot: Vector3 = Vector3(90.0, 75.0, -12.0)
@export var recall_track: float = 0.12
@export var recall_time: float = 0.18
## Ловля: толчок (м/с назад, град./с вверх); идеальный хват — сильнее и прокрут молота в руке
@export var catch_kick: float = 1.2
@export var catch_tilt: float = 260.0
@export var perfect_kick: float = 2.0
@export var perfect_tilt: float = 420.0
@export var perfect_twirl_time: float = 0.32
@export var perfect_twirl_turns: float = 1.0

@export_group("Ренж")
## Отдача выстрела: м/с назад и град./с вверх на 1° recoil_kick_deg оружия
@export var fire_kick_per_deg: float = 0.55
@export var fire_tilt_per_deg: float = 75.0
## Пределы на один выстрел (чтобы ракетница не улетала)
@export var fire_kick_max: float = 2.2
@export var fire_tilt_max: float = 300.0
## Перезарядка: опускание и наклон (смещение от покоя)
@export var reload_low_pos: Vector3 = Vector3(-0.1, -0.07, 0.02)
@export var reload_low_rot: Vector3 = Vector3(8.0, 22.0, 48.0)
## Толчок «вставили магазин» (м/с вверх)
@export var reload_slap: float = 0.7

## Огнестрел в руке крупнее (кулак Тора большой): множитель view_scale ренж-оружия во вьюмодели
@export var gun_view_scale: float = 1.4

@export_group("Свитч")
## Убрать оружие: смещение и поворот вниз от покоя
@export var switch_down_pos: Vector3 = Vector3(0.05, -0.55, 0.2)
@export var switch_down_rot: Vector3 = Vector3(-45.0, 0.0, 0.0)

@export_group("Берсерк")
## Лёгкая дрожь рук в берсерке: град. и частота шума
@export var berserk_tremor: float = 0.9
@export var tremor_freq: float = 22.0
