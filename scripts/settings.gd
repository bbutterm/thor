extends RefCounted
class_name GameSettings
## Настройки игрока (GDD 22) с сохранением в user://settings.cfg (ConfigFile).
## Секции: [audio] громкости шин, [controls] чувствительность/инверсия, [video] экран, камера и комиксовая обводка (outline, outline_width — scripts/outline.gd),
## [hud] прицел и индикаторы, [text] размер текста, скорость печати и язык (ru/en, scripts/i18n.gd), [access] доступность,
## [comic] комиксовые слова (enabled, scale), стоп-кадр «страница комикса» (page) и заставка босса (boss_card),
## [input] клавиатура/мышь и [pad_input] геймпад (действие → список событий).
## Чужие секции файла при сохранении не трогаем. Тесты (res://tests/*) и --selftest пишут в
## user://test_settings.cfg — настоящий файл игрока не портится.
## Применение: apply_startup() — из Run._ready (звук, окно, клавиши, фильтр цвета);
## apply_to_player(p) — из Player._ready и при каждом изменении (чувствительность, FOV, тряска).
## UI — ui/settings_panel.gd (SettingsPanel). Изменение значения: set_value(секция, ключ, v) — сохраняет,
## применяет и шлёт events.changed(секция, ключ).

const PATH := "user://settings.cfg"
const TEST_PATH := "user://test_settings.cfg"
const COMIC_SCALE_MIN := 0.5
const COMIC_SCALE_MAX := 1.6
## Базовая чувствительность мыши/стика (множитель 1.0 = как было до настроек)
const BASE_MOUSE_SENS := 0.0022
const BASE_PAD_SENS := 3.0
const FOV_MIN := 70.0
const FOV_MAX := 110.0
## Шины звука: ключ настройки → имя шины. Master есть всегда, Music создаёт scripts/music.gd,
## SFX и Voice — здесь (Audio и будущая озвучка играют в них)
const BUSES := {"master": "Master", "music": "Music", "sfx": "SFX", "voice": "Voice"}
const FPS_OPTIONS := [0, 30, 60, 90, 120, 144, 165, 240]
const CROSSHAIRS := ["dot", "cross", "circle", "classic"]
const CROSSHAIR_COLORS := {
	"white": Color(1, 1, 1), "yellow": Color(1.0, 0.88, 0.3), "green": Color(0.45, 1.0, 0.45),
	"cyan": Color(0.45, 0.9, 1.0), "red": Color(1.0, 0.35, 0.3), "magenta": Color(1.0, 0.45, 1.0),
}
## Режимы цветовой слепоты (фильтр-коррекция всего экрана, ui/color_filter.gdshader)
const COLORBLIND := ["off", "protanopia", "deuteranopia", "tritanopia"]

## Значения по умолчанию: секция → ключ → значение
const DEFAULTS := {
	"audio": {"master": 1.0, "music": 0.8, "sfx": 1.0, "voice": 1.0},
	"controls": {"mouse_sensitivity": 1.0, "gamepad_sensitivity": 1.0, "invert_y": false},
	"video": {"fullscreen": false, "vsync": true, "max_fps": 0, "fov": 85.0, "shake": 1.0, "head_bob": true, "ui_scale": 1.0,
		"outline": true, "outline_width": 1.0},
	"hud": {"crosshair": "dot", "crosshair_size": 1.0, "crosshair_alpha": 0.85, "crosshair_color": "white", "offscreen": true, "damage_numbers": false},
	"text": {"text_scale": 1.0, "typing_speed": 1.0, "language": "ru"},
	"access": {"colorblind": "off", "aim_assist": false, "slam_slowmo": false, "catch_assist": true},
	"comic": {"enabled": true, "scale": 1.0, "page": true, "boss_card": true},
}

## Действия, которые можно переназначить (пауза — нет: Esc всегда выводит из меню).
## Подписи — ключи перевода (tr при показе, ui/settings_panel.gd)
const REMAP_ACTIONS := [
	["move_forward", "Вперёд"], ["move_back", "Назад"], ["move_left", "Влево"], ["move_right", "Вправо"],
	["jump", "Прыжок"], ["dash", "Рывок"], ["slam", "Удар-приземление (в воздухе)"],
	["attack", "Удар / выстрел"], ["throw", "Метнуть / вернуть Мьёльнир"],
	["weapon_switch", "Сменить оружие"], ["weapon_melee", "Мили-оружие"], ["weapon_ranged", "Ренж-оружие"],
	["reload", "Перезарядка"], ["interact", "Подобрать / действие"], ["build_screen", "Сборка (пауза)"],
]
## Камера переназначается только на геймпаде: мышь управляет ею напрямую.
const PAD_CAMERA_ACTIONS := [
	["camera_left", "Камера влево"], ["camera_right", "Камера вправо"],
	["camera_up", "Камера вверх"], ["camera_down", "Камера вниз"],
]
const PAD_CAPTURE_THRESHOLD := 0.7

## Сигнал об изменении (статическому классу свои сигналы не положены)
class Events extends RefCounted:
	signal changed(section: String, key: String)

static var events := Events.new()
static var path: String = ""
static var values: Dictionary = {}
## Быстрый доступ (ComicFX читает каждый кадр)
static var comic_enabled: bool = true
static var comic_scale: float = 1.0
static var _loaded: bool = false
static var _filter: CanvasLayer
## Тип последнего намеренного ввода — для подсказок; не сохраняется между запусками.
static var _gamepad_active: bool = false

static func _is_test() -> bool:
	for a in OS.get_cmdline_args():
		if a.begins_with("res://tests/"):
			return true
	return "--selftest" in OS.get_cmdline_user_args()

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if path == "":
		path = TEST_PATH if _is_test() else PATH
	values = DEFAULTS.duplicate(true)
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		for section in DEFAULTS:
			for key in DEFAULTS[section]:
				if cf.has_section_key(section, key):
					values[section][key] = _sanitize(section, key, cf.get_value(section, key))
		for section in ["input", "pad_input"]:
			if cf.has_section(section):
				values[section] = {}
				for action in cf.get_section_keys(section):
					values[section][action] = cf.get_value(section, action, [])
	# Тесты сравнивают русские строки: язык из тестового файла не берём (i18n_test включает его сам)
	if _is_test():
		values["text"]["language"] = DEFAULTS["text"]["language"]
	_sync_fast()

## Перечитать файл (тесты, смена пути)
static func reload() -> void:
	_loaded = false
	ensure_loaded()

static func _sync_fast() -> void:
	comic_enabled = bool(values["comic"]["enabled"])
	comic_scale = float(values["comic"]["scale"])

## Приводит значение из файла к типу и диапазону по умолчанию
static func _sanitize(section: String, key: String, v: Variant) -> Variant:
	var def: Variant = DEFAULTS[section][key]
	match typeof(def):
		TYPE_BOOL:
			return bool(v)
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			var f := float(v)
			match key:
				"scale":
					return clampf(f, COMIC_SCALE_MIN, COMIC_SCALE_MAX)
				"fov":
					return clampf(f, FOV_MIN, FOV_MAX)
				"mouse_sensitivity", "gamepad_sensitivity":
					return clampf(f, 0.1, 5.0)
				"ui_scale":
					return clampf(f, 0.75, 1.5)
				"text_scale":
					return clampf(f, 0.75, 1.6)
				"typing_speed":
					return clampf(f, 0.0, 4.0)
				"crosshair_size":
					return clampf(f, 0.4, 2.5)
				"outline_width":
					return clampf(f, Outline.WIDTH_MIN, Outline.WIDTH_MAX)
			return clampf(f, 0.0, 1.0)
		TYPE_STRING:
			if key == "language":
				return I18n.sanitize(str(v))
			return str(v)
	return v

static func get_value(section: String, key: String) -> Variant:
	ensure_loaded()
	return values.get(section, {}).get(key, DEFAULTS.get(section, {}).get(key))

## Меняет, сохраняет, применяет и оповещает
static func set_value(section: String, key: String, v: Variant, do_save: bool = true) -> void:
	ensure_loaded()
	if not values.has(section):
		values[section] = {}
	values[section][key] = _sanitize(section, key, v) if DEFAULTS.has(section) and DEFAULTS[section].has(key) else v
	_sync_fast()
	if do_save:
		save()
	_apply_one(section, key)
	events.changed.emit(section, key)

static func save() -> void:
	ensure_loaded()
	var cf := ConfigFile.new()
	cf.load(path)  # сохраняем чужие секции, если файл уже есть
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			cf.set_value(section, key, values[section][key])
	for section in ["input", "pad_input"]:
		if cf.has_section(section):
			cf.erase_section(section)
		for action in values.get(section, {}):
			cf.set_value(section, action, values[section][action])
	var err := cf.save(path)
	if err != OK:
		push_warning("GameSettings: не удалось сохранить %s (%d)" % [path, err])

## Все настройки — по умолчанию (клавиши тоже)
static func reset_all() -> void:
	ensure_loaded()
	values = DEFAULTS.duplicate(true)
	_sync_fast()
	reset_input(false)
	reset_pad_input(false)
	save()
	apply_startup()
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			events.changed.emit(section, key)

# --- Совместимость со старым API (комиксовые слова) ---

static func set_comic_enabled(v: bool) -> void:
	set_value("comic", "enabled", v)

static func set_comic_scale(v: float) -> void:
	set_value("comic", "scale", v)

# --- Удобные геттеры для игрового кода ---

static func text_scale() -> float:
	return float(get_value("text", "text_scale"))

## Множитель скорости печати диалогов; 0 — текст сразу целиком
static func typing_speed() -> float:
	return float(get_value("text", "typing_speed"))

static func aim_assist() -> bool:
	return bool(get_value("access", "aim_assist"))

static func slam_slowmo() -> bool:
	return bool(get_value("access", "slam_slowmo"))

## Подсказка идеального хвата Мьёльнира — кольца у прицела (ui/catch_assist.gd)
static func catch_assist() -> bool:
	return bool(get_value("access", "catch_assist"))

static func crosshair_color() -> Color:
	var c: Color = CROSSHAIR_COLORS.get(str(get_value("hud", "crosshair_color")), Color.WHITE)
	c.a = float(get_value("hud", "crosshair_alpha"))
	return c

# --- Применение ---

## При старте игры: звук, окно, клавиши, фильтр цвета
static func apply_startup() -> void:
	ensure_loaded()
	apply_language()
	apply_audio()
	apply_video()
	apply_input()
	apply_colorblind()
	Outline.apply_settings()

static func _apply_one(section: String, key: String) -> void:
	match section:
		"audio":
			apply_audio()
		"video":
			if key in ["fullscreen", "vsync", "max_fps", "ui_scale"]:
				apply_video()
			elif key in ["outline", "outline_width"]:
				Outline.apply_settings()
		"access":
			if key == "colorblind":
				apply_colorblind()
		"text":
			if key == "language":
				apply_language()
	if section in ["controls", "video"]:
		var tree := Engine.get_main_loop() as SceneTree
		if tree:
			for p in tree.get_nodes_in_group("player"):
				apply_to_player(p)

## Язык интерфейса и диалогов (TranslationServer)
static func apply_language() -> void:
	I18n.apply(str(get_value("text", "language")))

static func language() -> String:
	return str(get_value("text", "language"))

## Индекс шины по имени; SFX и Voice создаём, если их нет (посылают в Master)
static func bus_index(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0 and bus_name != "Music":
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")
	return i

static func apply_audio() -> void:
	ensure_loaded()
	for key in BUSES:
		var lin := float(values["audio"][key])
		if key == "music":
			# Громкость Music ставит scripts/music.gd каждый кадр (стингер, провалы) — передаём ему поправку
			var tree := Engine.get_main_loop() as SceneTree
			var music: Node = tree.root.get_node_or_null("Music") if tree else null
			if music and "user_volume_db" in music:
				music.set("user_volume_db", _lin_to_db(lin))
			continue
		var i := bus_index(BUSES[key])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, _lin_to_db(lin))
			AudioServer.set_bus_mute(i, lin <= 0.001)

static func _lin_to_db(lin: float) -> float:
	return -80.0 if lin <= 0.001 else linear_to_db(lin)

static func apply_video() -> void:
	ensure_loaded()
	var v: Dictionary = values["video"]
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.window_get_mode()
		var fs := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if bool(v["fullscreen"]) and not fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not bool(v["fullscreen"]) and fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var vs := DisplayServer.VSYNC_ENABLED if bool(v["vsync"]) else DisplayServer.VSYNC_DISABLED
		if DisplayServer.window_get_vsync_mode() != vs:
			DisplayServer.window_set_vsync_mode(vs)
	# --fixed-fps тестов не трогаем
	if not _is_test():
		Engine.max_fps = int(v["max_fps"])
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.content_scale_factor = float(v["ui_scale"])

## Чувствительность, инверсия, FOV, тряска и покачивание камеры — живому игроку
static func apply_to_player(p: Node) -> void:
	ensure_loaded()
	if p == null or not is_instance_valid(p):
		return
	var c: Dictionary = values["controls"]
	var v: Dictionary = values["video"]
	p.set("mouse_sensitivity", BASE_MOUSE_SENS * float(c["mouse_sensitivity"]))
	p.set("gamepad_sensitivity", BASE_PAD_SENS * float(c["gamepad_sensitivity"]))
	p.set("invert_y", bool(c["invert_y"]))
	var steps: Variant = p.get("footsteps")
	if steps is AudioStreamPlayer:
		(steps as AudioStreamPlayer).bus = BUSES["sfx"] if bus_index(BUSES["sfx"]) >= 0 else "Master"
	var cam: Node = p.get("camera_fx")
	if cam:
		cam.set("base_fov", float(v["fov"]))
		cam.set("shake_scale", float(v["shake"]))
		cam.set("head_bob_enabled", bool(v["head_bob"]))
		cam.set("strafe_tilt_enabled", bool(v["head_bob"]))

# --- Цветовая слепота: коррекция цвета всего экрана ---

static func apply_colorblind() -> void:
	var mode := COLORBLIND.find(str(get_value("access", "colorblind")))
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if mode <= 0:
		if _filter and is_instance_valid(_filter):
			_filter.visible = false
		return
	# Фильтр создаём только когда режим включён (один общий шейдер на всю игру)
	if _filter == null or not is_instance_valid(_filter):
		_filter = CanvasLayer.new()
		_filter.name = "ColorFilter"
		_filter.layer = 120
		_filter.process_mode = Node.PROCESS_MODE_ALWAYS
		var rect := ColorRect.new()
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = load("res://ui/color_filter.gdshader")
		rect.material = mat
		_filter.add_child(rect)
		tree.root.add_child.call_deferred(_filter)
	_filter.visible = true
	((_filter.get_child(0) as ColorRect).material as ShaderMaterial).set_shader_parameter("mode", mode)

static func colorblind_filter() -> CanvasLayer:
	return _filter if _filter and is_instance_valid(_filter) else null

# --- Клавиши ---

## Событие → строка для файла, ось сохраняется с направлением, а не с текущим значением.
static func event_to_string(e: InputEvent) -> String:
	if e is InputEventKey:
		var k := e as InputEventKey
		return "key:%d" % (k.physical_keycode if k.physical_keycode != 0 else k.keycode)
	if e is InputEventMouseButton:
		return "mouse:%d" % (e as InputEventMouseButton).button_index
	if e is InputEventJoypadButton:
		return "pad_button:%d" % (e as InputEventJoypadButton).button_index
	if e is InputEventJoypadMotion:
		var motion := e as InputEventJoypadMotion
		if absf(motion.axis_value) >= PAD_CAPTURE_THRESHOLD:
			return "pad_axis:%d:%d" % [motion.axis, 1 if motion.axis_value > 0.0 else -1]
	return ""

static func event_from_string(s: String) -> InputEvent:
	var parts := s.split(":")
	if parts.size() == 2 and parts[0] == "key" and parts[1].is_valid_int():
		var k := InputEventKey.new()
		k.physical_keycode = int(parts[1]) as Key
		return k
	if parts.size() == 2 and parts[0] == "mouse" and parts[1].is_valid_int():
		var m := InputEventMouseButton.new()
		m.button_index = int(parts[1]) as MouseButton
		return m
	if parts.size() == 2 and parts[0] == "pad_button" and parts[1].is_valid_int():
		var button := int(parts[1])
		if button < 0 or button >= JOY_BUTTON_MAX or button == JOY_BUTTON_START:
			return null
		var p := InputEventJoypadButton.new()
		p.device = -1  # любой подключённый геймпад
		p.button_index = button as JoyButton
		return p
	if parts.size() == 3 and parts[0] == "pad_axis" and parts[1].is_valid_int() and parts[2] in ["-1", "1"]:
		var axis := int(parts[1])
		if axis < 0 or axis >= JOY_AXIS_MAX:
			return null
		var p := InputEventJoypadMotion.new()
		p.device = -1
		p.axis = axis as JoyAxis
		p.axis_value = float(parts[2])
		return p
	return null

static func _is_kbm(e: InputEvent) -> bool:
	return e is InputEventKey or e is InputEventMouseButton

static func _is_pad(e: InputEvent) -> bool:
	return e is InputEventJoypadButton or e is InputEventJoypadMotion

static func _project_events(action: String) -> Array:
	var d: Variant = ProjectSettings.get_setting("input/" + action)
	if d is Dictionary:
		return (d as Dictionary).get("events", [])
	return []

## В проекте стандартные ui_accept/ui_cancel содержат только Enter/Esc;
## сохраняем их и добавляем A/B для навигации, независимо от игровых назначений.
static func _apply_ui_pad() -> void:
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var action: String = pair[0]
		if not InputMap.has_action(action):
			continue
		var button := InputEventJoypadButton.new()
		button.device = -1
		button.button_index = pair[1] as JoyButton
		if not InputMap.action_has_event(action, button):
			InputMap.action_add_event(action, button)

## Клавиатура и геймпад сохраняются раздельно: изменение одного не стирает другое.
static func apply_input() -> void:
	ensure_loaded()
	_apply_ui_pad()
	var saved: Dictionary = values.get("input", {})
	var saved_pad: Dictionary = values.get("pad_input", {})
	for pair in REMAP_ACTIONS + PAD_CAMERA_ACTIONS:
		var action: String = pair[0]
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		var custom: Variant = saved.get(action)
		var custom_pad: Variant = saved_pad.get(action)
		for e in _project_events(action):
			if custom is Array and _is_kbm(e):
				continue
			if custom_pad is Array and _is_pad(e):
				continue
			InputMap.action_add_event(action, e)
		if custom is Array:
			for s in custom:
				var ev := event_from_string(str(s))
				if ev and _is_kbm(ev):
					InputMap.action_add_event(action, ev)
		if custom_pad is Array:
			for s in custom_pad:
				var ev := event_from_string(str(s))
				if ev and _is_pad(ev):
					InputMap.action_add_event(action, ev)

## Назначить действию одну клавишу/кнопку мыши. Если она была у другого действия — снимаем оттуда.
## Возвращает id действия, у которого клавишу забрали («» — ни у кого).
static func rebind(action: String, e: InputEvent) -> String:
	ensure_loaded()
	if not _is_kbm(e):
		return ""
	var s := event_to_string(e)
	if s == "":
		return ""
	if not values.has("input"):
		values["input"] = {}
	var taken := ""
	for pair in REMAP_ACTIONS:
		var other: String = pair[0]
		if other == action:
			continue
		var cur := bindings(other)
		if s in cur:
			cur.erase(s)
			values["input"][other] = cur
			taken = other
	values["input"][action] = [s]
	apply_input()
	save()
	events.changed.emit("input", action)
	return taken

## Текущие клавиши действия (строки event_to_string)
static func bindings(action: String) -> Array:
	var out: Array = []
	if not InputMap.has_action(action):
		return out
	for e in InputMap.action_get_events(action):
		if _is_kbm(e):
			var s := event_to_string(e)
			if s != "" and not s in out:
				out.append(s)
	return out

## Назначение кнопки или направления оси. Start остаётся паузой и отменой захвата.
static func rebind_pad(action: String, e: InputEvent) -> String:
	ensure_loaded()
	if not _is_pad(e):
		return ""
	var s := event_to_string(e)
	if s == "" or event_from_string(s) == null:
		return ""
	var known := false
	for pair in REMAP_ACTIONS + PAD_CAMERA_ACTIONS:
		if pair[0] == action:
			known = true
			break
	if not known:
		return ""
	if not values.has("pad_input"):
		values["pad_input"] = {}
	var taken := ""
	for pair in REMAP_ACTIONS + PAD_CAMERA_ACTIONS:
		var other: String = pair[0]
		if other == action:
			continue
		var cur := pad_bindings(other)
		if s in cur:
			cur.erase(s)
			values["pad_input"][other] = cur
			taken = other
	values["pad_input"][action] = [s]
	apply_input()
	save()
	events.changed.emit("pad_input", action)
	return taken

static func pad_bindings(action: String) -> Array:
	var out: Array = []
	if not InputMap.has_action(action):
		return out
	for e in InputMap.action_get_events(action):
		if _is_pad(e):
			var s := event_to_string(e)
			if s != "" and not s in out:
				out.append(s)
	return out

static func reset_pad_input(do_save: bool = true) -> void:
	ensure_loaded()
	values["pad_input"] = {}
	apply_input()
	if do_save:
		save()
	events.changed.emit("pad_input", "")

static func pad_action_label(action: String) -> String:
	var parts: PackedStringArray = []
	for s in pad_bindings(action):
		parts.append(pad_binding_label(s))
	return " / ".join(parts) if not parts.is_empty() else "—"

static func pad_binding_label(s: String) -> String:
	var parts := s.split(":")
	if parts.size() == 2 and parts[0] == "pad_button":
		var names := ["A", "B", "X", "Y", "View", "Guide", "Start", "L3", "R3", "LB", "RB", "D-pad ↑", "D-pad ↓", "D-pad ←", "D-pad →"]
		var index := int(parts[1])
		return names[index] if index >= 0 and index < names.size() else I18n.t("Кнопка %d") % index
	if parts.size() == 3 and parts[0] == "pad_axis":
		var axis := int(parts[1])
		var positive := parts[2] == "1"
		match axis:
			JOY_AXIS_LEFT_X:
				return "L ←" if not positive else "L →"
			JOY_AXIS_LEFT_Y:
				return "L ↑" if not positive else "L ↓"
			JOY_AXIS_RIGHT_X:
				return "R ←" if not positive else "R →"
			JOY_AXIS_RIGHT_Y:
				return "R ↑" if not positive else "R ↓"
			JOY_AXIS_TRIGGER_LEFT:
				return "LT" if positive else "LT −"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT" if positive else "RT −"
		return I18n.t("Ось %d %s") % [axis, "+" if positive else "−"]
	return s

## Подсказки следуют за устройством, которым действительно пользуется игрок.
## Дребезг стиков и неподвижная мышь не переключают устройство.
static func note_input(event: InputEvent) -> void:
	var next := _gamepad_active
	if event is InputEventJoypadButton and event.pressed:
		next = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= PAD_CAPTURE_THRESHOLD:
		next = true
	elif event is InputEventKey and event.pressed and not event.echo:
		next = false
	elif event is InputEventMouseButton and event.pressed:
		next = false
	elif event is InputEventMouseMotion and event.relative.length_squared() >= 4.0:
		next = false
	if next != _gamepad_active:
		_gamepad_active = next
		events.changed.emit("input_device", "")

static func using_gamepad() -> bool:
	return _gamepad_active

static func current_binding(action: String) -> String:
	if not InputMap.has_action(action):
		return action
	var current := pad_bindings(action) if _gamepad_active else bindings(action)
	if current.is_empty():
		return "—"
	return pad_binding_label(current[0]) if _gamepad_active else binding_label(current[0])

## Описания старых приёмов содержат ПКМ; подставляем текущую кнопку после перевода.
static func throw_hint(text: String) -> String:
	return text.replace(I18n.t("ПКМ"), current_binding("throw"))

## Все клавиши — как в project.godot
static func reset_input(do_save: bool = true) -> void:
	ensure_loaded()
	values["input"] = {}
	apply_input()
	if do_save:
		save()
	events.changed.emit("input", "")

## «key:32» → «Пробел», «mouse:1» → «ЛКМ»
static func binding_label(s: String) -> String:
	var parts := s.split(":")
	if parts.size() != 2:
		return s
	if parts[0] == "mouse":
		match int(parts[1]):
			MOUSE_BUTTON_LEFT:
				return I18n.t("ЛКМ")
			MOUSE_BUTTON_RIGHT:
				return I18n.t("ПКМ")
			MOUSE_BUTTON_MIDDLE:
				return I18n.t("СКМ")
			MOUSE_BUTTON_WHEEL_UP:
				return I18n.t("Колесо ↑")
			MOUSE_BUTTON_WHEEL_DOWN:
				return I18n.t("Колесо ↓")
			MOUSE_BUTTON_XBUTTON1:
				return I18n.t("Мышь 4")
			MOUSE_BUTTON_XBUTTON2:
				return I18n.t("Мышь 5")
		return I18n.t("Мышь %s") % parts[1]
	var code := int(parts[1])
	match code:
		KEY_SPACE:
			return I18n.t("Пробел")
		KEY_SHIFT:
			return "Shift"
		KEY_CTRL:
			return "Ctrl"
		KEY_ALT:
			return "Alt"
		KEY_ESCAPE:
			return "Esc"
		KEY_TAB:
			return "Tab"
		KEY_ENTER:
			return "Enter"
	return OS.get_keycode_string(code as Key)

static func action_label(action: String) -> String:
	var parts: PackedStringArray = []
	for s in bindings(action):
		parts.append(binding_label(s))
	return " / ".join(parts) if not parts.is_empty() else "—"
