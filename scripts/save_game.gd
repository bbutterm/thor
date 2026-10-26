extends Node
## Автозагрузка «Save» — постоянное сохранение между забегами: user://save.json.
## Счётчики забегов и смертей, причины смертей, просмотренные диалоги и выборы, рекорды,
## накопленная Слава и открытия «Плана тренировок» (run/unlocks/*.tres).
## Для пулов других систем: Save.is_in_pool("weapon", "spear") — закрытое не выпадает.
## Формат версионирован: при изменении — подними CURRENT_VERSION и добавь шаг в _migrate().
## Тесты (сцены из res://tests/) и --selftest пишут в user://test_save.json и начинают с чистого листа,
## чтобы не портить настоящее сохранение. Явный путь: `-- --save=user://my.json` или use_path().

signal changed

const CURRENT_VERSION := 2
const UNLOCKS_DIR := "res://run/unlocks/"
## Где искать определения оружия/трейтов (для «скоро» на экране плана)
const TARGET_DIRS := {"weapon": "res://weapons/defs/", "trait": "res://weapons/mjolnir_traits/"}
const DEFAULT_PATH := "user://save.json"
const TEST_PATH := "user://test_save.json"

var path: String = DEFAULT_PATH
var data: Dictionary = {}
## Все открытия (UnlockDef), по порядку
var all_unlocks: Array[UnlockDef] = []
var _target_ids: Dictionary = {}
## Сохранение тестовое (не пользовательское)
var is_test: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_args():
		if a.begins_with("res://tests/"):
			is_test = true
	var user_args := OS.get_cmdline_user_args()
	if "--selftest" in user_args:
		is_test = true
	for a in user_args:
		if a.begins_with("--save="):
			path = a.substr(7)
	_load_unlocks()
	if is_test and path == DEFAULT_PATH:
		path = TEST_PATH
		reset()
	else:
		load_game()

func _exit_tree() -> void:
	save_game()

# --- Файл ---

## Переключает файл сохранения (тесты). fresh = начать с пустого сохранения.
func use_path(p: String, fresh: bool = true) -> void:
	path = p
	if fresh:
		reset()
	else:
		load_game()

func reset() -> void:
	data = defaults()
	changed.emit()

static func defaults() -> Dictionary:
	return {
		"version": CURRENT_VERSION,
		"stats": {"runs": 0, "deaths": 0, "wins": 0, "boss_kills": 0, "kills": 0, "playtime": 0.0},
		"deaths_by_cause": {},
		"killed_by": {},
		"last_run": {},
		"seen": {},
		"choices": {},
		"events": {},
		"records": {"best_glory": 0, "best_kills": 0, "best_streak": 0, "best_rooms": 0, "fastest_win": 0.0, "longest_run": 0.0},
		"glory": {"bank": 0, "earned": 0, "spent": 0},
		"unlocks": {},
		"purchases": [],
	}

func load_game() -> bool:
	data = defaults()
	if not FileAccess.file_exists(path):
		changed.emit()
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("Save: не открыть %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		push_warning("Save: файл повреждён, начинаем заново (%s)" % path)
		# Не затираем испорченный файл молча — откладываем копию
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".broken"))
		changed.emit()
		return false
	data = _migrate(parsed)
	_fill_defaults(data, defaults())
	changed.emit()
	return true

func save_game() -> bool:
	if data.is_empty():
		return false
	data["version"] = CURRENT_VERSION
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Save: не записать %s" % tmp)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	# Запись через временный файл: обрыв посреди записи не портит сохранение
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	return err == OK

## Приводит старый формат к текущему. Каждая версия — свой шаг.
func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0))
	if v < 1:
		# v0 — гипотетический ранний формат без версии: просто счётчики в корне
		var s := defaults()
		for k in ["runs", "deaths", "wins"]:
			if d.has(k):
				s.stats[k] = int(d[k])
		d = s
		v = 1
	if v < 2:
		# v2: накопленная Слава и открытия «Плана тренировок»
		d["glory"] = {"bank": 0, "earned": 0, "spent": 0}
		d["unlocks"] = {}
		d["purchases"] = []
		v = 2
	d["version"] = v
	return d

## Дописывает недостающие ключи (новые поля в той же версии).
static func _fill_defaults(target: Dictionary, defs: Dictionary) -> void:
	for k in defs:
		if not target.has(k):
			target[k] = defs[k]
		elif defs[k] is Dictionary and target[k] is Dictionary:
			_fill_defaults(target[k], defs[k])

# --- Счётчики ---

func stat(key: String) -> Variant:
	return data.stats.get(key, 0)

func runs() -> int:
	return int(data.stats.runs)

func deaths() -> int:
	return int(data.stats.deaths)

func wins() -> int:
	return int(data.stats.wins)

## Начало забега (вызывает Game._ready через RunTracker).
func begin_run(body_id: String) -> void:
	data.stats.runs = runs() + 1
	data["current_body"] = body_id
	changed.emit()
	save_game()

## Конец забега. result: won, cause, killed_by, time, rooms, glory, kills, best_streak, body, tags.
func end_run(result: Dictionary) -> void:
	var won: bool = result.get("won", false)
	if won:
		data.stats.wins = wins() + 1
		data.stats.boss_kills = int(data.stats.boss_kills) + 1
	else:
		data.stats.deaths = deaths() + 1
		var cause: String = result.get("cause", "unknown")
		data.deaths_by_cause[cause] = int(data.deaths_by_cause.get(cause, 0)) + 1
		var by: String = result.get("killed_by", "")
		if by != "":
			data.killed_by[by] = int(data.killed_by.get(by, 0)) + 1
	data.stats.kills = int(data.stats.kills) + int(result.get("kills", 0))
	var t: float = result.get("time", 0.0)
	data.stats.playtime = float(data.stats.playtime) + t
	var rec: Dictionary = data.records
	rec.best_glory = maxi(int(rec.best_glory), int(result.get("glory", 0)))
	rec.best_kills = maxi(int(rec.best_kills), int(result.get("kills", 0)))
	rec.best_streak = maxi(int(rec.best_streak), int(result.get("best_streak", 0)))
	rec.best_rooms = maxi(int(rec.best_rooms), int(result.get("rooms", 0)))
	rec.longest_run = maxf(float(rec.longest_run), t)
	if won and (float(rec.fastest_win) <= 0.0 or t < float(rec.fastest_win)):
		rec.fastest_win = t
	var g := maxi(0, int(result.get("glory", 0)))
	data.glory.bank = glory_bank() + g
	data.glory.earned = int(data.glory.earned) + g
	data.last_run = result.duplicate(true)
	changed.emit()
	save_game()

## Совместимое имя для других систем: записать причину смерти без полного итога.
func record_death(cause: String, killed_by: String = "") -> void:
	end_run({"won": false, "cause": cause, "killed_by": killed_by})

func deaths_by(cause: String) -> int:
	return int(data.deaths_by_cause.get(cause, 0))

func killed_by_count(id: String) -> int:
	return int(data.killed_by.get(id, 0))

# --- Диалоги ---

func is_seen(dialogue_id: String) -> bool:
	return data.seen.has(dialogue_id)

func mark_seen(dialogue_id: String) -> void:
	data.seen[dialogue_id] = runs()
	changed.emit()

func set_choice(scene_id: String, choice_id: String) -> void:
	data.choices[scene_id] = choice_id

func get_choice(scene_id: String) -> String:
	return str(data.choices.get(scene_id, ""))

## Событие диалогов (death, victory, boss_intro...) — сколько раз случалось, включая текущее.
func bump_event(trigger: String) -> int:
	var n := int(data.events.get(trigger, 0)) + 1
	data.events[trigger] = n
	return n

func event_count(trigger: String) -> int:
	return int(data.events.get(trigger, 0))

## Плоский словарь переменных для условий диалогов.
func context() -> Dictionary:
	var lr: Dictionary = data.last_run
	return {
		"runs": runs(),
		"run_count": runs(),
		"deaths": deaths(),
		"wins": wins(),
		"boss_kills": int(data.stats.boss_kills),
		"kills_total": int(data.stats.kills),
		"cause_of_death": str(lr.get("cause", "")),
		"killed_by": str(lr.get("killed_by", "")),
		"last_won": bool(lr.get("won", false)),
		"last_run_time": float(lr.get("time", 0.0)),
		"last_rooms": int(lr.get("rooms", 0)),
		"last_glory": int(lr.get("glory", 0)),
		"last_kills": int(lr.get("kills", 0)),
		"body": str(lr.get("body", data.get("current_body", ""))),
		"best_glory": int(data.records.best_glory),
		"glory_bank": glory_bank(),
		"unlocks_count": data.unlocks.size(),
	}

# --- Слава и открытия ---

func glory_bank() -> int:
	return int(data.glory.bank)

func add_glory_bank(amount: int) -> void:
	data.glory.bank = maxi(0, glory_bank() + amount)
	changed.emit()

func _load_unlocks() -> void:
	all_unlocks.clear()
	var dir := DirAccess.open(UNLOCKS_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		var clean := f.trim_suffix(".remap")
		if clean.ends_with(".tres"):
			var u := load(UNLOCKS_DIR + clean) as UnlockDef
			if u and u.id != "":
				all_unlocks.append(u)
	all_unlocks.sort_custom(func(a: UnlockDef, b: UnlockDef) -> bool: return a.order < b.order)

func get_unlock(id: String) -> UnlockDef:
	for u in all_unlocks:
		if u.id == id:
			return u
	return null

func is_unlocked(id: String) -> bool:
	return data.unlocks.has(id)

## Можно ли этому оружию / трейту / телу / руне выпадать. Нет открытия на этот id — значит, открыто с начала.
func is_in_pool(kind: String, id: String) -> bool:
	var locked := false
	for u in all_unlocks:
		if u.kind == kind and id in u.targets():
			if is_unlocked(u.id):
				return true
			locked = true
	return not locked

## Сумма эффектов купленных перков (move_speed_pct, max_health, dash_charges, catch_window…).
func perk(key: String) -> float:
	var total := 0.0
	for u in all_unlocks:
		if u.kind == "perk" and u.target_id == key and is_unlocked(u.id):
			total += u.amount
	return total

## Есть ли в игре то, что открывает открытие (иначе — «скоро»).
func target_exists(u: UnlockDef) -> bool:
	match u.kind:
		"perk":
			return u.available
		"rune":
			for r in Run.all_runes:
				if r.id == u.target_id:
					return true
			return false
		"body":
			for b in Run.all_bodies:
				if b.id == u.target_id:
					return true
			return false
		_:
			if not _target_ids.has(u.kind):
				_target_ids[u.kind] = _scan_ids(str(TARGET_DIRS.get(u.kind, "")))
			return u.target_id in _target_ids[u.kind]

func _scan_ids(dir_path: String) -> Array:
	var out: Array = []
	if dir_path == "" or not DirAccess.dir_exists_absolute(dir_path):
		return out
	for f in DirAccess.get_files_at(dir_path):
		var clean := f.trim_suffix(".remap")
		if clean.ends_with(".tres"):
			var r := load(dir_path + clean)
			if r and r.get("id") != null:
				out.append(str(r.get("id")))
	return out

## Почему нельзя купить ("" — можно): unknown, owned, soon, requires, no_glory.
func buy_block_reason(id: String) -> String:
	var u := get_unlock(id)
	if u == null:
		return "unknown"
	if is_unlocked(id):
		return "owned"
	if not target_exists(u):
		return "soon"
	if u.requires != "" and not is_unlocked(u.requires):
		return "requires"
	if glory_bank() < u.price:
		return "no_glory"
	return ""

## Покупка открытия за Славу. Возвращает "" при успехе или причину отказа.
func buy(id: String) -> String:
	var reason := buy_block_reason(id)
	if reason != "":
		return reason
	var u := get_unlock(id)
	data.glory.bank = glory_bank() - u.price
	data.glory.spent = int(data.glory.spent) + u.price
	data.unlocks[id] = runs()
	data.purchases.append({"id": id, "price": u.price, "run": runs()})
	changed.emit()
	save_game()
	return ""

## Эффекты «навсегда» для тела забега: копия BodyDef с +HP, +рывком и скоростью.
func apply_permanent_to_body(body: BodyDef) -> BodyDef:
	if body == null or body.has_meta("perma_applied"):
		return body
	var b := body.duplicate() as BodyDef
	b.max_health += perk("max_health")
	b.move_speed *= 1.0 + perk("move_speed_pct")
	b.dash_charges += int(perk("dash_charges"))
	b.set_meta("perma_applied", true)
	return b
