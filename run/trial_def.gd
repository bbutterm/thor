extends Resource
class_name TrialDef
## Испытание (GDD 15.1): условие на зал, таймер и ведущий — Один, Хильд или Локи.
## Файлы — run/trials/*.tres; новое испытание = новый .tres с одним из видов условия (kind).
## Награда — Слава (GDD 15.2: 40–80) или особая руна (руна сразу на уровень выше); провал — без награды.
##
## kind:
##   no_ranged    — зачистить зал, ни разу не выстрелив ренжем;
##   time_limit   — зачистить зал за time_limit секунд;
##   only_sources — добивать только источниками из allowed_sources (удар-приземление, молот…);
##                  убийство из forbidden_sources — провал;
##   kill_count   — target убийств за time_limit секунд (рекорд Хильд); зал получает extra_waves доп. волн;
##   floor_lava   — пол — лава: стоять на земле дольше lava_grace — жжёт, суммарно дольше lava_max_burn — провал.

@export var id: String = ""
@export_enum("odin", "hild", "loki") var host: String = "odin"
@export var title: String = ""
## Условие (видно в HUD испытания)
@export var condition: String = ""
@export_enum("no_ranged", "time_limit", "only_sources", "kill_count", "floor_lava") var kind: String = "time_limit"
## Секунды (time_limit, kill_count); 0 — без таймера
@export var time_limit: float = 0.0
## Сколько убийств нужно (kill_count)
@export var target: int = 0
## only_sources: чем можно добивать и что — провал (источники урона Enemy.take_hit)
@export var allowed_sources: PackedStringArray = []
@export var forbidden_sources: PackedStringArray = []
## kill_count: сколько волн добавить к залу (копии его волн), чтобы было кого бить
@export var extra_waves: int = 0
@export_group("Лава")
## Урон лавы за тик и период тика, с
@export var lava_tick_damage: float = 6.0
@export var lava_tick: float = 0.5
## Сколько можно стоять на земле без ожога (приземлился — сразу прыгай), с
@export var lava_grace: float = 0.4
## Суммарное время ожога, после которого испытание провалено, с
@export var lava_max_burn: float = 4.0
@export_group("Награда")
## Слава за успех (GDD 15.2: 40–80); 0 — награда руной
@export var reward_glory: int = 60
## Награда — особая руна: выбор 1 из 3, руна сразу на уровень выше
@export var reward_rune: bool = false
## Частота среди испытаний
@export var weight: float = 1.0
@export_group("Реплики")
## Пулы реплик ведущего (data/dialogues/<host>.json); пусто — <host>.trial_intro / trial_win / trial_fail
@export var intro_pool: String = ""
@export var win_pool: String = ""
@export var fail_pool: String = ""

func pool(which: String) -> String:
	var p := intro_pool if which == "intro" else (win_pool if which == "win" else fail_pool)
	return p if p != "" else "%s.trial_%s" % [host, which]

func reward_text() -> String:
	return tr("особая руна") if reward_rune else tr("+%d Славы") % reward_glory
