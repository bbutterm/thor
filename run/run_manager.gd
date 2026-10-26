extends Node
## Автозагрузка «Run» — состояние одного забега: тело, порядок залов, руны, Слава.

signal glory_changed(total: int)
signal runes_changed(runes: Array)
signal kill_streak(count: int)
signal mjolnir_traits_changed(traits: Array)
## Убийство засчитано (после Славы). Слушают пассивки тела (Player) и Ярость.
signal kill_registered(source: String)

const BODIES_DIR := "res://run/bodies/"
const RUNES_DIR := "res://run/runes/"
const ROOM_SCENES := [
	"res://rooms/room_01.tscn",
	"res://rooms/room_02.tscn",
	"res://rooms/room_03.tscn",
	"res://rooms/room_04.tscn",
	"res://rooms/room_05.tscn",
	"res://rooms/room_06.tscn",
]
const BOSS_SCENE := "res://rooms/boss_arena.tscn"
const MJOLNIR_TRAITS_DIR := "res://weapons/mjolnir_traits/"

@export var rooms_per_run: int = 4
@export var glory_per_kill: int = 3
@export var glory_combo_finisher_bonus: int = 0
@export var glory_multikill_bonus: int = 1
@export var glory_wall_splat_bonus: int = 1
@export var glory_room_clear: int = 5
@export var glory_boss_kill: int = 150
## Слава за элиту и бонус за серию из 10 убийств (GDD 15.2)
@export var glory_elite_kill: int = 15
@export var glory_streak_bonus: int = 10
@export var multikill_window: float = 0.6
@export_group("Мини-боссы и трейты Мьёльнира")
## После каких залов (индекс с 0) в зале появляется мини-босс — последней волной; за него выбор трейта
@export var miniboss_rooms: PackedInt32Array = [1, 3]
## Какой мини-босс (MinibossDef)
@export var miniboss_def_path: String = "res://enemies/minibosses/fat_sven.tres"
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

var all_bodies: Array[BodyDef] = []
var all_runes: Array[RuneDef] = []
var all_mjolnir_traits: Array[MjolnirTrait] = []
## Активные трейты Мьёльнира (не больше одного на группу) и их уровни (id → 1..2)
var mjolnir_traits: Array[MjolnirTrait] = []
var mjolnir_trait_levels: Dictionary = {}
var _recent_kill_times: Array[float] = []
## Во сколько раз считается каждая руна (Старый жрец: «все руны ×2»), см. BodyDef.stat("rune_power")
var rune_power: int = 1

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
	# Модели, анимации и звуки грузятся в фоне, пока игрок в меню (см. AssetCache)
	AssetCache.start()

func _process(delta: float) -> void:
	# delta здесь уже умножен на Engine.time_scale — возвращаем реальное время для hit-stop
	FX.tick(delta / maxf(Engine.time_scale, 0.0001))

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
	var pool := ROOM_SCENES.duplicate()
	pool.shuffle()
	room_order.clear()
	for i in mini(rooms_per_run, pool.size()):
		room_order.append(pool[i])
	room_order.append(BOSS_SCENE)
	room_index = 0
	runes.clear()
	glory = 0
	kills = 0
	streak = 0
	best_streak = 0
	won = false
	_recent_kill_times.clear()
	mjolnir_traits.clear()
	mjolnir_trait_levels.clear()
	mjolnir_traits_changed.emit(mjolnir_traits)
	runes_changed.emit(runes)
	glory_changed.emit(glory)

func current_room_path() -> String:
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
func register_kill(finisher: bool, wall_splat: bool, is_boss: bool, source: String = "", base_glory: int = -1) -> void:
	kills += 1
	streak += 1
	best_streak = maxi(best_streak, streak)
	# База — Слава за врага по GDD 15.2 (корм 1, боец 3, особый 5, элита 15); враги без описания — glory_per_kill
	var amount := glory_per_kill if base_glory < 0 else base_glory
	if finisher:
		amount += glory_combo_finisher_bonus
	if wall_splat:
		amount += glory_wall_splat_bonus
	# «Один не уважает тех, кто стреляет издалека»
	if source.begins_with("melee"):
		amount = int(round(amount * glory_melee_kill_mult))
	elif source == "ranged":
		amount = int(round(amount * glory_ranged_kill_mult))
	if is_boss:
		amount += glory_boss_kill
	var now := Time.get_ticks_msec() / 1000.0
	_recent_kill_times = _recent_kill_times.filter(func(t: float) -> bool: return now - t <= multikill_window)
	if not _recent_kill_times.is_empty():
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
		return "Вальхалла ждёт"
	# Экономика GDD 15.2: удачный забег по Мидгарду — 150–250 Славы
	if glory >= 200:
		return "Вальхалла ждёт"
	if glory >= 80:
		return "Сойдёт"
	return "Недостоин"

# --- Мини-боссы и трейты Мьёльнира (GDD 10, 14.1) ---

## В текущем зале есть мини-босс (финальный босс — не мини-босс)
func is_miniboss_room() -> bool:
	return not is_boss_room() and room_index in miniboss_rooms

func miniboss_def() -> Resource:
	return load(miniboss_def_path) if miniboss_def_path != "" and ResourceLoader.exists(miniboss_def_path) else null

func mjolnir_trait_level(id: StringName) -> int:
	return int(mjolnir_trait_levels.get(id, 0))

## Активный трейт той же группы (его заменит t), или null
func mjolnir_trait_conflict(t: MjolnirTrait) -> MjolnirTrait:
	if t.group == "":
		return null
	for o in mjolnir_traits:
		if o.id != t.id and o.group == t.group:
			return o
	return null

## Выбор 1 из count: в одном предложении нет двух трейтов одной группы; трейты на макс. уровне не выпадают.
## Уже взятый трейт может выпасть — это повышение уровня; трейт группы, которая занята, — замена.
func random_mjolnir_trait_choices(count: int = 3) -> Array[MjolnirTrait]:
	var pool: Array[MjolnirTrait] = []
	for t in all_mjolnir_traits:
		if mjolnir_trait_level(t.id) < t.max_level:
			pool.append(t)
	pool.shuffle()
	var out: Array[MjolnirTrait] = []
	var groups: Dictionary = {}
	for t in pool:
		if out.size() >= count:
			break
		if t.group != "" and groups.has(t.group):
			continue
		out.append(t)
		if t.group != "":
			groups[t.group] = true
	return out

## Взять трейт: новый — уровень 1 (трейт той же группы уходит), повтор — уровень выше.
func add_mjolnir_trait(t: MjolnirTrait) -> void:
	Perf.mark("trait_pick")
	if mjolnir_trait_levels.has(t.id):
		mjolnir_trait_levels[t.id] = mini(mjolnir_trait_level(t.id) + 1, t.max_level)
	else:
		var old := mjolnir_trait_conflict(t)
		if old:
			mjolnir_traits.erase(old)
			mjolnir_trait_levels.erase(old.id)
		mjolnir_traits.append(t)
		mjolnir_trait_levels[t.id] = 1
	mjolnir_traits_changed.emit(mjolnir_traits)
