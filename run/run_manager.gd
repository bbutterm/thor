extends Node
## Автозагрузка «Run» — состояние одного забега: тело, порядок залов, руны, Слава.

signal glory_changed(total: int)
signal runes_changed(runes: Array)
signal kill_streak(count: int)
signal mjolnir_traits_changed(traits: Array)

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
@export var glory_per_kill: int = 10
@export var glory_combo_finisher_bonus: int = 5
@export var glory_multikill_bonus: int = 15
@export var glory_wall_splat_bonus: int = 5
@export var glory_room_clear: int = 25
@export var glory_boss_kill: int = 150
@export var multikill_window: float = 0.6
@export_group("Мини-боссы и трейты Мьёльнира")
## После каких залов (индекс с 0) в зале появляется мини-босс — последней волной; за него выбор трейта
@export var miniboss_rooms: PackedInt32Array = [1, 3]
## Какой мини-босс (MinibossDef)
@export var miniboss_def_path: String = "res://enemies/minibosses/fat_sven.tres"

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
		body = all_bodies[randi() % all_bodies.size()]
	if body == null:
		body = BodyDef.new()
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
	glory += int(round(amount * mult))
	glory_changed.emit(glory)

## Вызывается при убийстве врага. Считает мультикиллы и серии.
func register_kill(finisher: bool, wall_splat: bool, is_boss: bool) -> void:
	kills += 1
	streak += 1
	best_streak = maxi(best_streak, streak)
	var amount := glory_per_kill
	if finisher:
		amount += glory_combo_finisher_bonus
	if wall_splat:
		amount += glory_wall_splat_bonus
	if is_boss:
		amount += glory_boss_kill
	var now := Time.get_ticks_msec() / 1000.0
	_recent_kill_times = _recent_kill_times.filter(func(t: float) -> bool: return now - t <= multikill_window)
	if not _recent_kill_times.is_empty():
		amount += glory_multikill_bonus * _recent_kill_times.size()
	_recent_kill_times.append(now)
	add_glory(amount)
	if streak > 0 and streak % 10 == 0:
		kill_streak.emit(streak)

func register_player_hit() -> void:
	streak = 0

func add_rune(rune: RuneDef) -> void:
	runes.append(rune)
	runes_changed.emit(runes)

func rune_count(id: String) -> int:
	var n := 0
	for r in runes:
		if r.id == id:
			n += 1
	return n

func random_rune_choices(count: int = 3) -> Array[RuneDef]:
	var pool := all_runes.duplicate()
	pool.shuffle()
	var out: Array[RuneDef] = []
	for i in mini(count, pool.size()):
		out.append(pool[i])
	return out

func verdict() -> String:
	if won:
		return "Вальхалла ждёт"
	if glory >= 400:
		return "Вальхалла ждёт"
	if glory >= 150:
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
