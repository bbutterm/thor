extends Node
class_name RunManager
## Автозагрузка «Run» — состояние одного забега: тело, порядок залов, руны, Слава.

signal glory_changed(total: int)
signal runes_changed(runes: Array)
signal kill_streak(count: int)
signal mjolnir_traits_changed(traits: Array)
## Взятая стихия или приём сложились в связку (блок Б4) — Game показывает карточку, слово и реплику Одина
signal mjolnir_combo_unlocked(combo: MjolnirTrait)
## Связка сработала в бою (MjolnirTraitHandler.mark у связки) — HUD коротко вспыхивает её иконкой (П6)
signal mjolnir_combo_fired(combo: MjolnirTrait)
## Убийство засчитано (после Славы). Слушают пассивки тела (Player) и шкала стиля (StyleMeter).
signal kill_registered(source: String)
## Серебро — валюта забега (блок К, GDD 15.2), сгорает после смерти
signal silver_changed(total: int)

const BODIES_DIR := "res://run/bodies/"
const RUNES_DIR := "res://run/runes/"
const ROOM_SCENES := [
	"res://rooms/room_01.tscn",
	"res://rooms/room_02.tscn",
	"res://rooms/room_03.tscn",
	"res://rooms/room_04.tscn",
	"res://rooms/room_05.tscn",
	"res://rooms/room_06.tscn",
	"res://rooms/room_07.tscn",
	"res://rooms/room_08.tscn",
	"res://rooms/room_09.tscn",
	"res://rooms/room_10.tscn",
	"res://rooms/room_11.tscn",
]
const BOSS_SCENE := "res://rooms/boss_arena.tscn"
const MJOLNIR_TRAITS_DIR := "res://weapons/mjolnir_traits/"
## Связки «стихия + приём» (не выбираются — включаются сами) и правила выбора (блок Б4)
const MJOLNIR_COMBOS_DIR := "res://weapons/mjolnir_traits/combos/"
const MJOLNIR_RULES_PATH := "res://weapons/mjolnir_rules.tres"
## Двери-награды (блок И, GDD 15.1): награды и структура мира
const REWARDS_DIR := "res://run/rewards/"
const MAP_PATH := "res://run/maps/midgard.tres"
## Испытания (блок Ф): run/trials/*.tres
const TRIALS_DIR := "res://run/trials/"

## Залов до босса, если нет карты мира (с картой — RunMap.rooms, Мидгард: 7)
@export var rooms_per_run: int = 7
@export var glory_per_kill: int = 3
@export var glory_combo_finisher_bonus: int = 0
@export var glory_multikill_bonus: int = 1
## Корм получает и увеличивает денежный бонус мультикилла; по умолчанию не участвует.
@export var glory_fodder_multikill: bool = false
## У обычного корма фиксированная базовая Слава без множителей оружия и ранга.
@export var glory_fodder_flat: bool = true
@export var glory_wall_splat_bonus: int = 1
@export var glory_room_clear: int = 5
@export var glory_boss_kill: int = 150
## Слава за элиту и бонус за серию из 10 убийств (GDD 15.2)
@export var glory_elite_kill: int = 15
@export var glory_streak_bonus: int = 10
@export var multikill_window: float = 0.6
@export_group("Мини-боссы и трейты Мьёльнира")
## После каких залов (индекс с 0) в зале появляется мини-босс — последней волной; за него выбор трейта
## (с картой мира — RunMap.miniboss_room: Мидгард — 4-й зал, индекс 3)
@export var miniboss_rooms: PackedInt32Array = [3]
## Какой мини-босс (MinibossDef) в этом забеге — выбирает _pick_miniboss из miniboss_pool при start_run
@export var miniboss_def_path: String = "res://enemies/minibosses/fat_sven.tres"
## Мини-боссы Мидгарда (GDD 14.1): 4-й зал берёт случайного, без повтора подряд в соседних забегах
## (последний — Save.data["last_miniboss"]). В тестах — всегда первый, если не задан forced_miniboss
## или miniboss_rotation_in_tests.
@export var miniboss_pool: PackedStringArray = ["res://enemies/minibosses/fat_sven.tres", "res://enemies/minibosses/hovding.tres",
	"res://enemies/minibosses/volva.tres", "res://enemies/minibosses/berserker.tres"]
## Тесты: id мини-босса (MinibossDef.id) на следующие забеги; "" — по правилам
var forced_miniboss: String = ""
var miniboss_rotation_in_tests: bool = false
## Своя арена мини-босса (блок Н): зал мини-босса (miniboss_rooms) — эта сцена. Пусто — мини-босс
## выходит последней волной обычного зала
@export var miniboss_arena: String = "res://rooms/sven_arena.tscn"
## Множители Славы за убийство: добил мили / ренжем (GDD 15.2: ×1.5 / ×0.5)
@export var glory_melee_kill_mult: float = 1.5
@export var glory_ranged_kill_mult: float = 0.5

var body: BodyDef
var room_order: Array[String] = []
var room_index: int = 0
var runes: Array[RuneDef] = []
var glory: int = 0
var kills: int = 0
var streak: int = 0
var best_streak: int = 0
var won: bool = false
## Множитель Славы за убийство от ранга шкалы стиля «ДОСТОЙНО!» (ставит StyleMeter, блок Б3)
var style_glory_mult: float = 1.0

var all_bodies: Array[BodyDef] = []
var all_runes: Array[RuneDef] = []
var all_mjolnir_traits: Array[MjolnirTrait] = []
var all_mjolnir_combos: Array[MjolnirTrait] = []
var mjolnir_rules: MjolnirRules
## Двери-награды (блок И): структура мира, награды залов
var map: RunMap
var all_rewards: Array[RewardDef] = []
var all_trials: Array[TrialDef] = []
## Для тестов: id испытания следующего зала «Испытание» ("" — случайное)
var forced_trial: String = ""
## Награда каждого зала по индексу (id RewardDef); зал без записи — обычный бой
var room_rewards: Array[String] = []
## Сколько раз в этом мире входили в зал с наградой (id → n): ларёк гарантирован shop_per_world раз
var reward_visits: Dictionary = {}
## Двери с наградами после зачистки (false — старый линейный порядок: руна → одна дверь)
var doors_enabled: bool = true
## Серебро забега (GDD 15.2): с врагов, бочек, сундуков; тратится в ларьке; новый забег — с нуля
## (или со стартовыми 30 у открытия «Жадность»)
var silver: int = 0
## Всего собрано за забег (итог, реакции Брокка)
var silver_earned: int = 0
## «Обслуживание Мьёльнира» без трейтов: переброс выбора трейта у следующего мини-босса
var trait_rerolls: int = 0
## Для тестов: наборы дверей по очереди (каждый — массив id наград); пусто — случайно по GDD
var forced_offers: Array = []
## Активные трейты Мьёльнира: стихия (≤ MjolnirRules.max_elements) и приёмы (≤ max_techniques),
## без несовместимых; уровни (id → 1..max_level). Связки сюда не входят — Run.active_combos()
var mjolnir_traits: Array[MjolnirTrait] = []
var mjolnir_trait_levels: Dictionary = {}
## История денежного бонуса; шкала стиля и комикс считают свою серию независимо.
var _recent_kill_times: Array[float] = []
## Непрерывное реальное время кадров. Работает при паузе и хит-стопе, как прежние системные часы,
## но также остаётся корректным при ускоренном headless с --fixed-fps.
var combat_clock: float = 0.0
## Во сколько раз считается каждая руна (Старый жрец: «все руны ×2»), см. BodyDef.stat("rune_power")
var rune_power: int = 1

## Компоненты (этап 5 рефакторинга): логика по файлам run/parts/run_*.gd, состояние — поля выше.
var mjolnir: RunMjolnir
var doors: RunDoors

func _init() -> void:
	mjolnir = RunMjolnir.new(self)
	doors = RunDoors.new(self)

func _exit_tree() -> void:
	AssetCache.shutdown()
	ScreenArt.shutdown()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Русский шрифт + запасной шрифт с рунами (ᚠ ᛗ ᚦ ...)
	var main_font := load("res://fonts/RussoOne-Regular.ttf") as FontFile
	var runic := load("res://fonts/NotoSansRunic-Regular.ttf") as Font
	if main_font and runic:
		main_font.fallbacks = [runic]
	all_bodies.assign(_load_dir(BODIES_DIR))
	all_runes.assign(_load_dir(RUNES_DIR))
	all_mjolnir_traits.assign(_load_dir(MJOLNIR_TRAITS_DIR))
	all_mjolnir_combos.assign(_load_dir(MJOLNIR_COMBOS_DIR))
	mjolnir_rules = load(MJOLNIR_RULES_PATH) as MjolnirRules if ResourceLoader.exists(MJOLNIR_RULES_PATH) else MjolnirRules.new()
	all_rewards.assign(_load_dir(REWARDS_DIR))
	all_trials.assign(_load_dir(TRIALS_DIR))
	map = load(MAP_PATH) as RunMap if ResourceLoader.exists(MAP_PATH) else null
	# Модели, анимации и звуки грузятся в фоне, пока игрок в меню (см. AssetCache)
	AssetCache.start()
	# Настройки игрока (звук, окно, клавиши) — после остальных автозагрузок (шина Music)
	GameSettings.apply_startup.call_deferred()

func _process(delta: float) -> void:
	# Отсчёт окон использует ту же реальную длительность кадра, что и hit-stop.
	# real_delta учитывает масштаб в начале кадра даже при его смене в физике.
	combat_clock += FX.real_delta(delta)
	FX.tick(delta / maxf(Engine.time_scale, 0.0001))

func _input(event: InputEvent) -> void:
	GameSettings.note_input(event)

func _load_dir(path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("Run: нет папки %s" % path)
		return out
	for file in dir.get_files():
		var clean := file.trim_suffix(".remap")
		if clean.ends_with(".tres"):
			var res := load(path + clean)
			if res:
				out.append(res)
	return out

func start_run(forced_body_id: String = "") -> void:
	body = null
	if forced_body_id != "":
		for b in all_bodies:
			if b.id == forced_body_id:
				body = b
	if body == null and not all_bodies.is_empty():
		# Закрытые в «Плане тренировок» тела не выпадают (Save.is_in_pool)
		var open_bodies: Array = all_bodies.filter(func(b: BodyDef) -> bool: return Save.is_in_pool("body", b.id))
		if open_bodies.is_empty():
			open_bodies = all_bodies
		body = open_bodies[randi() % open_bodies.size()]
	if body == null:
		body = BodyDef.new()
	rune_power = maxi(1, int(body.stat(&"rune_power", 1)))
	doors._build_room_order()
	_pick_miniboss()
	_place_miniboss_arenas()
	room_index = 0
	room_rewards.clear()
	room_rewards.append(map.first_room_reward if map else "combat")
	reward_visits.clear()
	forced_offers.clear()
	silver = int(Save.perk("start_silver"))
	silver_earned = 0
	trait_rerolls = 0
	silver_changed.emit(silver)
	runes.clear()
	glory = 0
	kills = 0
	streak = 0
	best_streak = 0
	won = false
	style_glory_mult = 1.0
	_recent_kill_times.clear()
	combat_clock = 0.0
	mjolnir_traits.clear()
	mjolnir_trait_levels.clear()
	mjolnir_traits_changed.emit(mjolnir_traits)
	runes_changed.emit(runes)
	glory_changed.emit(glory)

func current_room_path() -> String:
	# Ларёк — свой зал (блок К), остальные награды — в залах из room_order
	if doors.current_reward() == "shop" and map and ResourceLoader.exists(map.shop_scene):
		return map.shop_scene
	return room_order[room_index] if room_index < room_order.size() else BOSS_SCENE

func is_boss_room() -> bool:
	return current_room_path() == BOSS_SCENE

func total_rooms() -> int:
	return room_order.size()

func advance_room() -> bool:
	room_index += 1
	return room_index < room_order.size()

func add_glory(amount: int) -> void:
	var mult := body.glory_mult if body else 1.0
	# Руна «Слава предков» (GDD 11)
	mult *= 1.0 + rune_value("ancestor_glory")
	glory += int(round(amount * mult))
	glory_changed.emit(glory)

## Вызывается при убийстве врага. Считает мультикиллы и серии.
func register_kill(finisher: bool, wall_splat: bool, is_boss: bool, source: String = "", base_glory: int = -1, is_fodder: bool = false) -> void:
	kills += 1
	streak += 1
	best_streak = maxi(best_streak, streak)
	# База — Слава за врага по GDD 15.2 (корм 1, боец 3, особый 5, элита 15); враги без описания — glory_per_kill
	var amount := glory_per_kill if base_glory < 0 else base_glory
	# «Слава за врага ×» debug-панели (П8; без панели ×1)
	amount = int(round(amount * DebugBalance.econ.glory))
	if finisher:
		amount += glory_combo_finisher_bonus
	if wall_splat:
		amount += glory_wall_splat_bonus
	# Большая пачка корма сохраняет малую награду; тело и руна всё ещё
	# применяются в add_glory, а серия и события стиля остаются общими.
	if not is_fodder or not glory_fodder_flat:
		# «Один не уважает тех, кто стреляет издалека»
		if source.begins_with("melee"):
			amount = int(round(amount * glory_melee_kill_mult))
		elif source == "ranged":
			amount = int(round(amount * glory_ranged_kill_mult))
		# Ранг шкалы стиля — на самого врага, без бонуса босса.
		amount = int(round(amount * style_glory_mult))
	if is_boss:
		amount += glory_boss_kill
	var now := combat_clock
	_recent_kill_times = _recent_kill_times.filter(func(t: float) -> bool: return now - t <= multikill_window)
	if not is_fodder or glory_fodder_multikill:
		amount += glory_multikill_bonus * _recent_kill_times.size()
		_recent_kill_times.append(now)
	# Серия из 10+ убийств без урона — +10 (GDD 15.2)
	if streak > 0 and streak % 10 == 0:
		amount += glory_streak_bonus
	add_glory(amount)
	if streak > 0 and streak % 10 == 0:
		kill_streak.emit(streak)
	kill_registered.emit(source)

func register_player_hit() -> void:
	streak = 0

## Максимальный уровень руны (GDD 11: повторная руна повышает уровень, 1–3)
const RUNE_MAX_LEVEL := 3

func add_rune(rune: RuneDef) -> void:
	if rune_level(rune.id) >= RUNE_MAX_LEVEL:
		return
	runes.append(rune)
	runes_changed.emit(runes)

## Сколько раз руна взята (без учёта жреца). Совместимость: старый код считает силу руны так.
func rune_count(id: String) -> int:
	return rune_level(id) * rune_power

## Уровень руны 0–3 (0 — нет руны).
func rune_level(id: String) -> int:
	var n := 0
	for r in runes:
		if r.id == id:
			n += 1
	return mini(n, RUNE_MAX_LEVEL)

func rune_def(id: String) -> RuneDef:
	for r in all_runes:
		if r.id == id:
			return r
	return null

## Значение руны на её текущем уровне (GDD 11, поле level_values; b — второе число, level_values_b).
## У Старого жреца (rune_power 2): «add» — ×2, «mult» — (v − 1) ×2 + 1, «interval» — «каждый N-й» → N / 2.
## Нет руны — 0 (для mult — 1, для interval — 0 = выключено).
func rune_value(id: String, b: bool = false) -> float:
	var lvl := rune_level(id)
	var d := rune_def(id)
	if d == null:
		return 0.0
	var vals: PackedFloat32Array = d.level_values_b if b else d.level_values
	var kind := d.value_kind if not b else "add"
	if lvl <= 0 or vals.is_empty():
		return 1.0 if kind == "mult" else 0.0
	var v := vals[mini(lvl, vals.size()) - 1]
	match kind:
		"mult":
			return (v - 1.0) * rune_power + 1.0
		"interval":
			return maxf(1.0, round(v / rune_power))
		_:
			return v * rune_power if not b else v

## Обычный выбор рун: не проклятые, с механикой, открытые, ещё не на максимальном уровне.
func random_rune_choices(count: int = 3) -> Array[RuneDef]:
	# Закрытые в «Плане тренировок» руны не выпадают (Save.is_in_pool)
	# Руны без механики (implemented = false) не выпадают
	var pool := all_runes.filter(func(r: RuneDef) -> bool:
		return r.implemented and not r.cursed and rune_level(r.id) < RUNE_MAX_LEVEL and Save.is_in_pool("rune", r.id))
	pool.shuffle()
	var out: Array[RuneDef] = []
	for i in mini(count, pool.size()):
		out.append(pool[i])
	return out

## Проклятая руна Локи (особые события — сделка Локи): ещё не взятая, или null.
func random_cursed_rune() -> RuneDef:
	var pool := all_runes.filter(func(r: RuneDef) -> bool: return r.cursed and rune_level(r.id) == 0)
	return pool[randi() % pool.size()] if not pool.is_empty() else null

func verdict() -> String:
	if won:
		return tr("Вальхалла ждёт")
	# Экономика GDD 15.2: удачный забег по Мидгарду — 150–250 Славы
	if glory >= 200:
		return tr("Вальхалла ждёт")
	if glory >= 80:
		return tr("Сойдёт")
	return tr("Недостоин")

# --- Мини-боссы и трейты Мьёльнира (GDD 10, 14.1) ---

## В текущем зале есть мини-босс (финальный босс — не мини-босс)
func is_miniboss_room() -> bool:
	return not is_boss_room() and room_index in miniboss_rooms

## Мини-босс забега: forced_miniboss, иначе случайный из miniboss_pool, кроме прошлого (Save); его арена.
func _pick_miniboss() -> void:
	var defs: Array[MinibossDef] = []
	for path in miniboss_pool:
		if ResourceLoader.exists(path):
			var d := load(path) as MinibossDef
			if d:
				defs.append(d)
	if defs.is_empty():
		return
	var chosen: MinibossDef = null
	if forced_miniboss != "":
		for d in defs:
			if d.id == forced_miniboss:
				chosen = d
	elif Save.is_test and not miniboss_rotation_in_tests:
		chosen = defs[0]
	else:
		var last := str(Save.data.get("last_miniboss", ""))
		var options := defs.filter(func(d: MinibossDef) -> bool: return d.id != last)
		if options.is_empty():
			options = defs
		chosen = options[randi() % options.size()]
	if chosen == null:
		chosen = defs[0]
	miniboss_def_path = chosen.resource_path
	miniboss_arena = chosen.arena
	Save.data["last_miniboss"] = chosen.id

## Залы мини-босса (miniboss_rooms) — его своя арена (кроме финального зала).
func _place_miniboss_arenas() -> void:
	if miniboss_arena == "" or not ResourceLoader.exists(miniboss_arena):
		return
	for i in miniboss_rooms:
		if i >= 0 and i < room_order.size() - 1:
			room_order[i] = miniboss_arena

func miniboss_def() -> Resource:
	return load(miniboss_def_path) if miniboss_def_path != "" and ResourceLoader.exists(miniboss_def_path) else null

# --- Трейты Мьёльнира: стихии, приёмы, связки (блок Б4, GDD 10) ---

# --- Двери-награды (блок И, GDD 15.1) ---

# --- Серебро (блок К) ---

func add_silver(amount: int) -> void:
	if amount <= 0:
		return
	# Руна «Жадность Брокка»: +25 % → +60 %
	amount = int(round(amount * (1.0 + rune_value("brokk_greed"))))
	silver += amount
	silver_earned += amount
	silver_changed.emit(silver)

## Списать серебро; false — не хватает (ничего не списано).
func spend_silver(amount: int) -> bool:
	if amount > silver:
		return false
	silver -= maxi(0, amount)
	silver_changed.emit(silver)
	return true

## Убрать одну копию руны (уровень −1; «Сдать руну» в ларьке).
func remove_rune(id: String) -> bool:
	for i in range(runes.size() - 1, -1, -1):
		if runes[i].id == id:
			runes.remove_at(i)
			runes_changed.emit(runes)
			return true
	return false

# --- Функции компонентов, доступные на RunManager ---
# API (## API →) и приватные функции, которые зовут другие файлы (## совместимость →).
# Реализация и описание — в компоненте.

# RunMjolnir (run_mjolnir.gd)

## API → mjolnir.mjolnir_trait_level
func mjolnir_trait_level(id: StringName) -> int:
	return mjolnir.mjolnir_trait_level(id)

## API → mjolnir.rules
func rules() -> MjolnirRules:
	return mjolnir.rules()

## API → mjolnir.mjolnir_trait_def
func mjolnir_trait_def(id: StringName) -> MjolnirTrait:
	return mjolnir.mjolnir_trait_def(id)

## API → mjolnir.owned_elements
func owned_elements() -> Array[MjolnirTrait]:
	return mjolnir.owned_elements()

## API → mjolnir.owned_element
func owned_element() -> MjolnirTrait:
	return mjolnir.owned_element()

## API → mjolnir.owned_techniques
func owned_techniques() -> Array[MjolnirTrait]:
	return mjolnir.owned_techniques()

## API → mjolnir.active_combos
func active_combos() -> Array[MjolnirTrait]:
	return mjolnir.active_combos()

## API → mjolnir.combos_completed_by
func combos_completed_by(t: MjolnirTrait) -> Array[MjolnirTrait]:
	return mjolnir.combos_completed_by(t)

## API → mjolnir.mjolnir_level_in_pool
func mjolnir_level_in_pool(t: MjolnirTrait, lv: int) -> bool:
	return mjolnir.mjolnir_level_in_pool(t, lv)

## API → mjolnir.can_level_up
func can_level_up(t: MjolnirTrait) -> bool:
	return mjolnir.can_level_up(t)

## API → mjolnir.mjolnir_offer_ok
func mjolnir_offer_ok(t: MjolnirTrait) -> bool:
	return mjolnir.mjolnir_offer_ok(t)

## API → mjolnir.mjolnir_trait_conflict
func mjolnir_trait_conflict(t: MjolnirTrait) -> MjolnirTrait:
	return mjolnir.mjolnir_trait_conflict(t)

## API → mjolnir.random_mjolnir_trait_choices
func random_mjolnir_trait_choices(count: int = -1, kinds: Array = []) -> Array[MjolnirTrait]:
	return mjolnir.random_mjolnir_trait_choices(count, kinds)

## API → mjolnir.anvil_available
func anvil_available() -> bool:
	return mjolnir.anvil_available()

## API → mjolnir.add_mjolnir_trait
func add_mjolnir_trait(t: MjolnirTrait) -> Array[MjolnirTrait]:
	return mjolnir.add_mjolnir_trait(t)

# RunDoors (run_doors.gd)

## API → doors.reward_def
func reward_def(id: String) -> RewardDef:
	return doors.reward_def(id)

## API → doors.current_reward
func current_reward() -> String:
	return doors.current_reward()

## API → doors.is_peaceful_room
func is_peaceful_room() -> bool:
	return doors.is_peaceful_room()

## API → doors.shop_available
func shop_available() -> bool:
	return doors.shop_available()

## API → doors.roll_door_offers
func roll_door_offers() -> Array[String]:
	return doors.roll_door_offers()

## API → doors.choose_door
func choose_door(id: String) -> void:
	doors.choose_door(id)
