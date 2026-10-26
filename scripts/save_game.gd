extends Node
## Автозагрузка «Save» — постоянное сохранение между забегами: user://save.json.
## Счётчики забегов и смертей, причины смертей, просмотренные диалоги и выборы, рекорды.
## Формат версионирован: при изменении — подними CURRENT_VERSION и добавь шаг в _migrate().
## Тесты (сцены из res://tests/) и --selftest пишут в user://test_save.json и начинают с чистого листа,
## чтобы не портить настоящее сохранение. Явный путь: `-- --save=user://my.json` или use_path().

signal changed

const CURRENT_VERSION := 1
const DEFAULT_PATH := "user://save.json"
const TEST_PATH := "user://test_save.json"

var path: String = DEFAULT_PATH
var data: Dictionary = {}
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
	}
