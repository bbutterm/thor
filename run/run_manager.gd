extends Node
## Автозагрузка «Run» — состояние одного забега: тело, порядок залов, руны, Слава.

signal glory_changed(total: int)
signal runes_changed(runes: Array)
signal kill_streak(count: int)

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

@export var rooms_per_run: int = 4
@export var glory_per_kill: int = 10
@export var glory_combo_finisher_bonus: int = 5
@export var glory_multikill_bonus: int = 15
@export var glory_wall_splat_bonus: int = 5
@export var glory_room_clear: int = 25
@export var glory_boss_kill: int = 150
@export var multikill_window: float = 0.6

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
	# Закрытые в «Плане тренировок» руны не выпадают (Save.is_in_pool)
	var pool := all_runes.filter(func(r: RuneDef) -> bool: return Save.is_in_pool("rune", r.id))
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
