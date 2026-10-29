extends Node
## Автозагрузка «DebugPanel» — debug-панель баланса (П8, ТЗ `DEBUG_PANEL.md`). Только там же, где «Быстрая проверка»
## (`available()` = QuickCheck.available(): сборка `playtest` или отладка); в релизе — ни клавиш, ни файла.
## F1 — панель (игра идёт, Тор не слушает ввод), F2 — пауза. Вид — ui/debug_panel.gd (DebugPanelUI).
##
## Источники значений регистрируются по ключу: `register(&"player", player)`, &"mjolnir", &"camera" (Game._ready, после тела),
## &"room" (Room._ready), &"style" (копия StyleTuning, StyleMeter._ready), &"economy" (Silver.cfg()), множители
## DebugBalance (&"enemy_mult", &"econ_mult", &"waves_mult"). Изменённые значения — `overrides` («источник.поле» → число),
## накладываются при регистрации, сохраняются в `user://debug/balance.json` (только изменённое) и подхватываются при старте.
## Поле может быть с индексом (`rank_points[2]`) или ключом словаря (`points/slam`). Числа в код — `tools/apply_balance.py`.

signal changed(key: String)
signal opened(on: bool)

const DIR := "user://debug/"
const FILE := "user://debug/balance.json"
const VERSION := 1

## Слой A — «Баланс»: [название, источник, поле, мин, макс] (bool — мин/макс не нужны). Вкладки — по порядку.
const TABS := [
	{"id": "mjolnir", "title": "Мьёльнир", "params": [
		["КД после поимки", "mjolnir", "catch_cooldown", 0.0, 5.0],
		["КД после идеального хвата", "mjolnir", "perfect_catch_cooldown", 0.0, 3.0],
		["Окно идеального хвата", "mjolnir", "perfect_window", 0.03, 0.6],
		["Урон после идеального хвата ×", "mjolnir", "perfect_damage_mult", 1.0, 5.0],
		["Урон броска", "mjolnir", "base_damage", 5.0, 150.0],
		["Скорость полёта", "mjolnir", "throw_speed", 10.0, 120.0],
		["Дальность", "mjolnir", "max_range", 5.0, 60.0],
		["Возврат: скорость в начале", "mjolnir", "return_speed", 5.0, 150.0],
		["Возврат: скорость максимум", "mjolnir", "return_speed_max", 5.0, 150.0],
		["Возврат: разгон", "mjolnir", "return_accel", 5.0, 150.0],
		["Автовозврат через (старое, F6)", "mjolnir", "auto_return_after", 0.0, 10.0],
		["Втыкается в землю при промахе", "mjolnir", "sticks_to_world"],
		["Отскоки от стен", "mjolnir", "max_wall_bounces", 0, 5],
		["Цепная молния: целей", "mjolnir", "chain_targets", 0, 10],
		["Цепная молния: доля урона", "mjolnir", "chain_damage_ratio", 0.0, 1.0],
		["Цепная молния: радиус", "mjolnir", "chain_radius", 1.0, 20.0],
		["Отброс врага вперёд", "mjolnir", "hit_knock_forward", 0.0, 60.0],
		["Отброс врага вверх", "mjolnir", "hit_knock_up", 0.0, 30.0],
		["Волна при попадании: радиус", "mjolnir", "hit_wave_radius", 0.0, 8.0],
		["Волна при попадании: отброс", "mjolnir", "hit_wave_knock", 0.0, 40.0],
		["Волна при втыкании: радиус", "mjolnir", "stick_wave_radius", 0.0, 10.0],
		["Волна при втыкании: урон", "mjolnir", "stick_wave_damage", 0.0, 60.0],
		["Волна при втыкании: отброс", "mjolnir", "stick_wave_knock", 0.0, 40.0],
		["Хит-стоп попадания", "mjolnir", "hit_hitstop", 0.0, 0.3],
		["Тряска при попадании", "mjolnir", "hit_shake", 0.0, 1.0],
		["Тряска при поимке", "mjolnir", "catch_shake", 0.0, 1.0],
	]},
	{"id": "enemies", "title": "Мобы", "params": [
		["ХП мобов ×", "enemy_mult", "hp", 0.1, 5.0],
		["ХП элиты и мини-боссов ×", "enemy_mult", "hp_elite", 0.1, 5.0],
		["ХП боссов ×", "enemy_mult", "hp_boss", 0.1, 5.0],
		["Применить ХП и к живым", "enemy_mult", "apply_to_live"],
		["Урон мобов ×", "enemy_mult", "damage", 0.0, 5.0],
		["Скорость мобов ×", "enemy_mult", "speed", 0.2, 3.0],
		["Замах ×", "enemy_mult", "windup", 0.3, 3.0],
		["Пауза между атаками ×", "enemy_mult", "cooldown", 0.2, 3.0],
		["Устойчивость к отбросу +", "enemy_mult", "knock_resist_add", -1.0, 1.0],
		["Броня боссов от мили (<0 — из данных)", "enemy_mult", "boss_melee_resist", -0.05, 1.0],
	]},
	{"id": "waves", "title": "Волны", "params": [
		["Максимум живых (0 — без предела)", "room", "max_alive", 0, 80],
		["Количество корма ×", "waves_mult", "fodder_count", 0.1, 5.0],
		["Врагов за раз", "room", "spawn_batch", 1, 12],
		["Интервал спавна", "room", "spawn_interval", 0.02, 1.0],
		["Пауза перед волной", "room", "wave_delay", 0.0, 5.0],
		["Следующая волна, когда живых меньше (доля)", "room", "next_wave_fraction", 0.0, 1.0],
		["Следующая волна не позже чем через", "room", "next_wave_timeout", 3.0, 90.0],
	]},
	{"id": "movement", "title": "Движение", "params": [
		["Скорость бега", "player", "move_speed", 2.0, 20.0],
		["Разгон", "player", "ground_accel", 10.0, 200.0],
		["Торможение", "player", "ground_decel", 10.0, 200.0],
		["Управление в воздухе", "player", "air_control", 0.0, 1.5],
		["Высота прыжка", "player", "jump_velocity", 3.0, 20.0],
		["Прыжков в воздухе", "player", "extra_jumps", 0, 4],
		["Гравитация", "player", "gravity", 5.0, 60.0],
		["Тяжесть падения ×", "player", "fall_gravity_mult", 0.5, 3.0],
		["Рывков (рун)", "player", "dash_charges_max", 0, 6],
		["Сила рывка", "player", "dash_speed", 5.0, 60.0],
		["Длина рывка", "player", "dash_duration", 0.05, 0.6],
		["Перезарядка руны", "player", "dash_recharge", 0.2, 8.0],
		["Неуязвимость рывка", "player", "dash_invuln", 0.0, 0.6],
		["Удар-приземление: мин. высота", "player", "slam_min_height", 0.5, 10.0],
		["Удар-приземление: скорость падения", "player", "slam_speed", 10.0, 80.0],
		["Удар-приземление: урон база", "player", "slam_base_damage", 0.0, 120.0],
		["Удар-приземление: урон за метр", "player", "slam_damage_per_meter", 0.0, 15.0],
		["Удар-приземление: радиус база", "player", "slam_base_radius", 0.5, 12.0],
		["Удар-приземление: радиус за метр", "player", "slam_radius_per_meter", 0.0, 1.5],
		["Супер-прыжок: окно", "player", "super_jump_window", 0.0, 1.0],
		["Супер-прыжок: высота ×", "player", "super_jump_height_mult", 1.0, 5.0],
		["Прыжки от стен", "player", "wall_jumps", 0, 6],
	]},
	{"id": "style", "title": "Стиль", "params": [
		["Очки до ранга «Сойдёт»", "style", "rank_points[1]", 0.0, 100.0],
		["Очки до ранга «Неплохо»", "style", "rank_points[2]", 0.0, 100.0],
		["Очки до ранга «Достойно»", "style", "rank_points[3]", 0.0, 150.0],
		["Очки до «ДОСТОЙНЕЙШИЙ!»", "style", "rank_points[4]", 10.0, 200.0],
		["Слава × «Скуф»", "style", "rank_glory_mult[0]", 0.5, 3.0],
		["Слава × «Сойдёт»", "style", "rank_glory_mult[1]", 0.5, 3.0],
		["Слава × «Неплохо»", "style", "rank_glory_mult[2]", 0.5, 3.0],
		["Слава × «Достойно»", "style", "rank_glory_mult[3]", 0.5, 3.0],
		["Слава × «ДОСТОЙНЕЙШИЙ!»", "style", "rank_glory_mult[4]", 0.5, 3.0],
		["Спад «Сойдёт»", "style", "rank_drain[1]", 0.0, 10.0],
		["Спад «Неплохо»", "style", "rank_drain[2]", 0.0, 10.0],
		["Спад «Достойно»", "style", "rank_drain[3]", 0.0, 10.0],
		["Спад за повтор приёма", "style", "repeat_falloff", 0.0, 1.0],
		["Минимум за повтор", "style", "repeat_min_mult", 0.0, 1.0],
		["Пауза до спада", "style", "idle_delay", 0.0, 10.0],
		["Спад без действий", "style", "idle_drain", 0.0, 30.0],
		["Берсерк: длительность", "style", "berserk_time", 1.0, 20.0],
		["Берсерк: урон ×", "style", "damage_mult", 1.0, 4.0],
		["Берсерк: скорость ×", "style", "speed_mult", 1.0, 3.0],
	]},
	{"id": "economy", "title": "Экономика", "params": [
		["Серебро из сундука", "economy", "chest_silver", 0, 100],
		["Серебро из бочки: мин", "economy", "barrel_silver_min", 0, 40],
		["Серебро из бочки: макс", "economy", "barrel_silver_max", 0, 40],
		["Серебро за элиту", "economy", "elite_silver", 0, 60],
		["Серебро за мини-босса", "economy", "miniboss_silver", 0, 100],
		["Ящик: шанс серебра", "economy", "crate_silver_chance", 0.0, 1.0],
		["Ящик: шанс патронов", "economy", "crate_ammo_chance", 0.0, 1.0],
		["Ящик: шанс лечения", "economy", "crate_heal_chance", 0.0, 1.0],
		["Лечение из ящика", "economy", "crate_heal_amount", 0.0, 60.0],
		["Шанс взрывной бочки", "economy", "explosive_barrel_chance", 0.0, 1.0],
		["Взрывных бочек максимум", "economy", "explosive_barrel_max", 0, 8],
		["Цены ларька ×", "econ_mult", "shop_price", 0.1, 3.0],
		["Слава за врага ×", "econ_mult", "glory", 0.1, 5.0],
	]},
]
## Слой B — «Все параметры»: у этих источников все числовые и логические @export
const AUTO_SOURCES := ["player", "mjolnir", "room", "style", "camera"]
## Очки стиля за приём — отдельные строки (словарь StyleTuning.points), собираются при регистрации стиля
const STYLE_POINTS_PREFIX := "points/"

## Изменённые значения «источник.поле» → значение; заметка к файлу
var overrides: Dictionary = {}
var note: String = ""
## Подсветить окно хвата в кольце CatchAssist, пока панель открыта
var highlight_catch: bool = true
## Значения по умолчанию (из кода/сцены) «источник.поле» → значение, запоминаются при регистрации
var defaults: Dictionary = {}
## Сколько изменений пришло из файла при старте (плашка «Баланс из файла»)
var loaded_from_file: int = 0
var room_started_msec: int = 0
var _sources: Dictionary = {}
var _ui: CanvasLayer
var _badge: CanvasLayer
var _open: bool = false
var _input_was: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not available():
		return
	register(&"enemy_mult", DebugBalance.enemy)
	register(&"econ_mult", DebugBalance.econ)
	register(&"waves_mult", DebugBalance.waves)
	register(&"economy", Silver.cfg())
	if FileAccess.file_exists(FILE):
		loaded_from_file = load_file(FILE)
		_show_badge()

## Тесты: представить релизную сборку (панели нет)
static var force_off: bool = false

static func available() -> bool:
	return not force_off and QuickCheck.available()

func is_open() -> bool:
	return _open

# --- Источники ---

## Зарегистрировать источник: запомнить умолчания и наложить изменённые значения. Узел снимается сам при выходе.
func register(source: StringName, obj: Object) -> void:
	if not available() or obj == null:
		return
	_sources[source] = obj
	if source == &"room":
		room_started_msec = Time.get_ticks_msec()
	for f in _fields_of(source, obj):
		var v: Variant = read_field(obj, f)
		if v != null:
			defaults["%s.%s" % [source, f]] = v
	_apply_source(source)
	if obj is Node and not (obj as Node).tree_exiting.is_connected(_on_source_exit):
		(obj as Node).tree_exiting.connect(_on_source_exit.bind(source, obj))

func _on_source_exit(source: StringName, obj: Object) -> void:
	if _sources.get(source) == obj:
		_sources.erase(source)

func source(key: StringName) -> Object:
	var o: Object = _sources.get(key)
	return o if o != null and is_instance_valid(o) else null

## Наложить изменённые значения источника ещё раз (тело/руны пересчитали игрока)
func reapply(source_key: StringName) -> void:
	if available() and _sources.has(source_key):
		_apply_source(source_key)

func _apply_source(source_key: StringName) -> void:
	var obj := source(source_key)
	if obj == null:
		return
	var prefix := str(source_key) + "."
	for k in overrides:
		if str(k).begins_with(prefix):
			write_field(obj, str(k).substr(prefix.length()), overrides[k])

## Поля источника, умолчания которых запоминаем: слой A + все @export (слой B) + очки стиля
func _fields_of(source_key: StringName, obj: Object) -> Array[String]:
	var out: Array[String] = []
	for tab in TABS:
		for p in tab.params:
			if p[1] == str(source_key) and not out.has(p[2]):
				out.append(p[2])
	if str(source_key) in AUTO_SOURCES:
		for prop in export_props(obj):
			if not out.has(prop.name):
				out.append(prop.name)
	if source_key == &"style" and obj.get("points") is Dictionary:
		for k in (obj.get("points") as Dictionary):
			out.append(STYLE_POINTS_PREFIX + str(k))
	return out

## Числовые и логические @export объекта по порядку, с группой (@export_group) и подсказкой диапазона
static func export_props(obj: Object) -> Array:
	var out: Array = []
	var group := ""
	for p in obj.get_property_list():
		var usage := int(p.usage)
		if usage & PROPERTY_USAGE_GROUP:
			group = str(p.name)
			continue
		if usage & PROPERTY_USAGE_CATEGORY:
			group = ""
			continue
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_EDITOR):
			continue
		var t := int(p.type)
		if t != TYPE_FLOAT and t != TYPE_INT and t != TYPE_BOOL:
			continue
		if int(p.hint) == PROPERTY_HINT_ENUM or int(p.hint) == PROPERTY_HINT_FLAGS or str(p.name).ends_with("_layers"):
			continue
		var lo := 0.0
		var hi := 0.0
		if int(p.hint) == PROPERTY_HINT_RANGE:
			var parts := str(p.hint_string).split(",")
			if parts.size() >= 2:
				lo = float(parts[0])
				hi = float(parts[1])
		out.append({"name": str(p.name), "type": t, "group": group, "min": lo, "max": hi, "ranged": hi > lo})
	return out

## Поле с индексом массива «имя[i]» или ключом словаря «имя/ключ»
static func read_field(obj: Object, f: String) -> Variant:
	var slash := f.find("/")
	if slash > 0:
		var d: Variant = obj.get(f.left(slash))
		return (d as Dictionary).get(f.substr(slash + 1)) if d is Dictionary else null
	var br := f.find("[")
	if br > 0:
		var arr: Variant = obj.get(f.left(br))
		var i := int(f.substr(br + 1, f.length() - br - 2))
		if (arr is PackedFloat32Array or arr is Array or arr is PackedInt32Array) and i < arr.size():
			return arr[i]
		return null
	return obj.get(f)

static func write_field(obj: Object, f: String, v: Variant) -> void:
	var slash := f.find("/")
	if slash > 0:
		var d: Variant = obj.get(f.left(slash))
		if d is Dictionary:
			(d as Dictionary)[f.substr(slash + 1)] = v
		return
	var br := f.find("[")
	if br > 0:
		var name := f.left(br)
		var arr: Variant = obj.get(name)
		var i := int(f.substr(br + 1, f.length() - br - 2))
		if (arr is PackedFloat32Array or arr is Array or arr is PackedInt32Array) and i < arr.size():
			arr[i] = v
			obj.set(name, arr)
		return
	var cur: Variant = obj.get(f)
	if cur is int and not (v is bool):
		obj.set(f, int(round(float(v))))
	elif cur is bool:
		obj.set(f, bool(v))
	else:
		obj.set(f, float(v))

# --- Значения ---

func value(key: String) -> Variant:
	if overrides.has(key):
		return overrides[key]
	var dot := key.find(".")
	var obj := source(StringName(key.left(dot)))
	if obj:
		return read_field(obj, key.substr(dot + 1))
	return defaults.get(key)

func default_of(key: String) -> Variant:
	return defaults.get(key)

## Поменять значение: сразу к живому объекту; равное умолчанию — не считается изменением
func set_value(key: String, v: Variant) -> void:
	var dot := key.find(".")
	var src := StringName(key.left(dot))
	var field := key.substr(dot + 1)
	var def: Variant = defaults.get(key)
	if def != null and _same(def, v):
		overrides.erase(key)
	else:
		overrides[key] = v
	var obj := source(src)
	if obj:
		write_field(obj, field, v)
	_after_change(src, field)
	changed.emit(key)

func reset_value(key: String) -> void:
	if defaults.has(key):
		set_value(key, defaults[key])
	else:
		overrides.erase(key)
		changed.emit(key)

## Всё к значениям из кода
func reset_all() -> void:
	for k in overrides.keys():
		var def: Variant = defaults.get(k)
		var dot := str(k).find(".")
		var obj := source(StringName(str(k).left(dot)))
		if obj and def != null:
			write_field(obj, str(k).substr(dot + 1), def)
	overrides.clear()
	DebugBalance.refresh_live_hp(get_tree())
	changed.emit("")

static func _same(a: Variant, b: Variant) -> bool:
	if a is bool or b is bool:
		return bool(a) == bool(b)
	return is_equal_approx(float(a), float(b))

func _after_change(src: StringName, field: String) -> void:
	if src == &"enemy_mult" and field.begins_with("hp"):
		DebugBalance.refresh_live_hp(get_tree())
	elif src == &"player" and field == "dash_charges_max":
		var p := source(&"player") as Player
		if p:
			p.dash_charges = mini(p.dash_charges, p.dash_charges_max)
			p.dash_charges_changed.emit(p.dash_charges, p.dash_charges_max, 0.0)

## Сколько изменений на вкладке (для подписи «Мьёльнир • 3»); «all» — слой B
func changes_in(tab_id: String) -> int:
	var n := 0
	for tab in TABS:
		if tab.id != tab_id:
			continue
		for p in tab.params:
			if overrides.has("%s.%s" % [p[1], p[2]]):
				n += 1
	if tab_id == "all":
		var seen := {}
		for tab in TABS:
			for p in tab.params:
				seen["%s.%s" % [p[1], p[2]]] = true
		for k in overrides:
			if not seen.has(k):
				n += 1
	return n

# --- Файл ---

func save_file(path: String = FILE) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var data := {"version": VERSION, "build": _build_id(), "saved": Time.get_datetime_string_from_system(), "note": note, "values": overrides}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t", true))
	return true

## Загрузить: значения применяются к зарегистрированным источникам; неизвестные ключи — в лог, без падения.
## Возвращает число применённых значений.
func load_file(path: String = FILE) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not (parsed as Dictionary).get("values") is Dictionary:
		push_warning("DebugPanel: не читается %s" % path)
		return 0
	reset_all()
	note = str(parsed.get("note", ""))
	var n := 0
	for k in (parsed.values as Dictionary):
		var key := str(k)
		var dot := key.find(".")
		if dot <= 0 or not _known_source(key.left(dot)):
			print("DebugPanel: неизвестный ключ «%s» — пропущен" % key)
			continue
		var v: Variant = parsed.values[k]
		if not (v is float or v is int or v is bool):
			print("DebugPanel: значение «%s» не число — пропущено" % key)
			continue
		overrides[key] = v
		var obj := source(StringName(key.left(dot)))
		if obj:
			write_field(obj, key.substr(dot + 1), v)
		n += 1
	DebugBalance.refresh_live_hp(get_tree())
	changed.emit("")
	return n

static func _known_source(s: String) -> bool:
	return s in ["player", "mjolnir", "camera", "room", "style", "economy", "enemy_mult", "econ_mult", "waves_mult"]

## Пресеты: balance.json и balance_<имя>.json
func presets() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.begins_with("balance") and f.ends_with(".json"):
			out.append(f)
	out.sort()
	return out

static func preset_path(name: String) -> String:
	name = name.strip_edges().replace("/", "_").replace("\\", "_")
	return FILE if name == "" else DIR + "balance_%s.json" % name

func open_folder() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	OS.shell_open(ProjectSettings.globalize_path(DIR))

static func _build_id() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	return v if v != "" else Time.get_date_string_from_system()

# --- Ввод, пауза, время ---

func _input(event: InputEvent) -> void:
	if not available() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).physical_keycode
	if k == KEY_F1:
		toggle()
		get_viewport().set_input_as_handled()
	elif k == KEY_F2 and _open:
		toggle_pause()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	set_open(not _open)

func set_open(on: bool) -> void:
	if not available() or on == _open:
		return
	_open = on
	if on and (_ui == null or not is_instance_valid(_ui)):
		_ui = DebugPanelUI.new()
		_ui.name = "DebugPanelUI"
		get_tree().root.add_child(_ui)
	if _ui:
		_ui.visible = on
		if on:
			_ui.call("refresh")
	var p := source(&"player") as Player
	if p:
		if on:
			_input_was = p.input_enabled
			p.input_enabled = false
		else:
			p.input_enabled = _input_was
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else (Input.MOUSE_MODE_CAPTURED if p and not get_tree().paused else Input.mouse_mode)
	_apply_highlight()
	opened.emit(on)

func toggle_pause() -> void:
	get_tree().paused = not get_tree().paused

func set_time_mult(v: float) -> void:
	DebugBalance.set_time_mult(v)

## Подсветка окна хвата: кольцо CatchAssist рисует золотое окно контрастным цветом, пока панель открыта
func _apply_highlight() -> void:
	var ca := get_tree().root.find_child("CatchAssist", true, false)
	if ca == null:
		return
	if not ca.has_meta("_window_color"):
		ca.set_meta("_window_color", ca.get("window_color"))
	ca.set("window_color", Color(1.0, 0.1, 0.9) if _open and highlight_catch else ca.get_meta("_window_color"))

# --- Строка состояния ---

func status_text() -> String:
	var room := source(&"room") as Room
	var alive := room.alive_enemies().size() if room else 0
	var wave := "%d / %d" % [int(room.get("_wave_index")) + 1, (room.get("_waves") as Dictionary).size()] if room else "—"
	var t := (Time.get_ticks_msec() - room_started_msec) / 1000.0 if room else 0.0
	var s := tr("Живых: %d · волна %s · в зале %d с · урон/с за 10 с: %.0f") % [alive, wave, int(t), DebugBalance.dps()]
	if room:
		for e in room.alive_enemies():
			if is_instance_valid(e) and e.kind == Enemy.Kind.BOSS and not e.has_meta("miniboss"):
				s += "\n" + tr("Босс: %d / %d ХП · бой %d с") % [int(e.health), int(e.max_health), int((Time.get_ticks_msec() - int(e.get_meta("_debug_spawn_msec", Time.get_ticks_msec()))) / 1000.0)]
	return s

# --- Плашка «Баланс из файла» ---

func _show_badge() -> void:
	if loaded_from_file <= 0:
		return
	_badge = CanvasLayer.new()
	_badge.layer = 30
	_badge.name = "DebugBalanceBadge"
	var l := UIStyle.label(tr("Баланс из файла: %d изм.") % loaded_from_file, 14, Color(1.0, 0.85, 0.3), 4)
	l.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	l.offset_left = 8
	l.offset_top = -26
	l.offset_right = 400
	l.offset_bottom = -6
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_child(l)
	add_child(_badge)
