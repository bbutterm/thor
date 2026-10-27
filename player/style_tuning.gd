extends Resource
class_name StyleTuning
## Числа шкалы стиля «ДОСТОЙНО!» (блок Б3, GDD 8) — данные `player/style_tuning.tres`, читает StyleMeter.
## Ранги: 0 Скуф → 1 Сойдёт → 2 Неплохо → 3 Достойно → 4 ДОСТОЙНЕЙШИЙ! (берсерк).

@export_group("Ранги")
## С какого числа очков начинается ранг (0..4). Последний — полная шкала: берсерк
@export var rank_points: PackedFloat32Array = PackedFloat32Array([0.0, 15.0, 35.0, 60.0, 100.0])
## Множитель Славы за убийство на ранге (Run.register_kill)
@export var rank_glory_mult: PackedFloat32Array = PackedFloat32Array([1.0, 1.1, 1.25, 1.4, 1.6])
## Постоянная утечка очков в секунду на ранге — чем выше, тем быстрее уходит (берсерк не течёт)
@export var rank_drain: PackedFloat32Array = PackedFloat32Array([0.0, 0.6, 1.2, 2.0, 0.0])
## Слово комикса при повышении ранга не чаще раза в N секунд (на каждый ранг отдельно)
@export var rank_pop_cooldown: float = 4.0
## …и через столько секунд после приёма, поднявшего ранг (слово приёма — первым; высший ранг — сразу)
@export var rank_pop_delay: float = 1.15

@export_group("Очки за приёмы")
## Сколько очков даёт приём при первом применении. Убийства — kill_<способ>, трюки — без приставки.
## Способ убийства — по источнику урона (StyleMeter.kill_action): melee, finisher, heavy, ranged, slam,
## stomp (прыжок по головам), hammer (Мьёльнир и его молнии), fall (сбил с края), wall (шмяк о стену),
## reflect (отражённый снаряд), dash (рывок/таран), explosion (бочка, Раздутый), fire, other.
@export var points: Dictionary = {
	"kill_melee": 4.0, "kill_finisher": 6.0, "kill_heavy": 7.0, "kill_ranged": 2.0,
	"kill_slam": 9.0, "kill_stomp": 12.0, "kill_hammer": 9.0, "kill_fall": 14.0,
	"kill_wall": 12.0, "kill_reflect": 12.0, "kill_dash": 7.0, "kill_explosion": 10.0,
	"kill_fire": 5.0, "kill_other": 3.0,
	"slam_bounce": 5.0, "stomp": 5.0, "perfect_catch": 8.0, "wall_splat": 6.0, "reflect": 8.0,
	"multikill": 10.0, "multikill_big": 15.0,
	# Мьёльнир (блок Б4): перехват в воздухе, связка стихии с ударом-приземлением, пике молотом,
	# прыжок с молота-ступеньки, обмен местами, раскол замёрзшего
	"air_catch": 6.0, "element_slam": 6.0, "hammer_dive": 6.0, "hammer_step": 6.0, "hammer_swap": 5.0, "shatter": 8.0,
}
## Мульти-килл: столько убийств за multikill_window секунд (и multikill_big_count — крупный)
@export var multikill_count: int = 3
@export var multikill_big_count: int = 5
@export var multikill_window: float = 0.8

@export_group("Повтор одного приёма")
## Каждое недавнее применение того же приёма умножает очки на это (0.6 → 100 %, 60 %, 36 %, 22 %…)
@export_range(0.0, 1.0) var repeat_falloff: float = 0.6
## Но не меньше этой доли
@export_range(0.0, 1.0) var repeat_min_mult: float = 0.15
## Память о приёме: «усталость» +1 за применение, тает на столько в секунду
@export var repeat_memory_decay: float = 0.35
## Потолок усталости (чтобы заспамленный приём «отдыхал» не дольше repeat_memory_max / decay секунд)
@export var repeat_memory_max: float = 4.0

@export_group("Спад и урон")
## Без новых очков столько секунд — шкала начинает пустеть
@export var idle_delay: float = 2.5
## …со скоростью (очков в секунду) — сверх утечки ранга
@export var idle_drain: float = 5.0
## Урон по Тору сбивает: max(damage_knock_min, урон × damage_knock_per_hp) очков (в берсерке — нет)
@export var damage_knock_min: float = 12.0
@export var damage_knock_per_hp: float = 0.8

@export_group("Берсерк (высший ранг)")
@export var berserk_time: float = 8.0
@export var damage_mult: float = 1.5
@export var speed_mult: float = 1.5
## Хит-стоп при включении, с
@export var hitstop_on_start: float = 0.12
## После берсерка шкала падает в середину этого ранга (2 — «Неплохо»: 47.5 очков)
@export var after_berserk_rank: int = 2

@export_group("Музыка и голос")
## С этого ранга в бою играет полный трек (Music: слой full), ниже — барабаны
@export var music_full_rank: int = 3
## На этом ранге Один говорит «Достойно!» (пул odin.rank_worthy, с лимитом боевых реплик)
@export var voice_rank: int = 3
## Одна и та же реплика ранга — не чаще раза в N секунд; «ДОСТОЙНЕЙШИЙ!» в пределах — заменяет пул berserk
@export var voice_cooldown: float = 30.0
## Если лимит реплик Одина (12 с) занят — пробовать сказать «Достойно!» ещё столько секунд
@export var voice_retry_time: float = 2.5
