extends SceneTree
## Одноразовый скрипт настройки проекта (запуск: godot --headless --path . -s tools/setup_project.gd)
## Ставит Jolt, имена слоёв физики, управление, автозагрузки и главную сцену.

func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

func _mouse(button: int) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e

func _joy(button: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e

func _set_action(name: String, events: Array, deadzone := 0.5) -> void:
	ProjectSettings.set_setting("input/" + name, {"deadzone": deadzone, "events": events})

func _init() -> void:
	ProjectSettings.set_setting("application/config/name", "Тор: Достойная смерть")
	ProjectSettings.set_setting("application/run/main_scene", "res://ui/main_menu.tscn")
	ProjectSettings.set_setting("physics/3d/physics_engine", "Jolt Physics")
	ProjectSettings.set_setting("physics/common/physics_ticks_per_second", 60)
	ProjectSettings.set_setting("display/window/size/viewport_width", 1280)
	ProjectSettings.set_setting("display/window/size/viewport_height", 720)
	ProjectSettings.set_setting("display/window/stretch/mode", "canvas_items")
	ProjectSettings.set_setting("display/window/stretch/aspect", "expand")
	ProjectSettings.set_setting("gui/theme/custom_font", "res://fonts/RussoOne-Regular.ttf")

	var layers := {1: "world", 2: "player", 3: "enemies", 4: "props", 5: "projectiles", 6: "triggers", 7: "debris"}
	for i in layers:
		ProjectSettings.set_setting("layer_names/3d_physics/layer_%d" % i, layers[i])

	# Убираем действия бластера из кита
	for old in ["shoot", "weapon_toggle", "mouse_capture", "mouse_capture_exit"]:
		if ProjectSettings.has_setting("input/" + old):
			ProjectSettings.set_setting("input/" + old, null)

	_set_action("attack", [_mouse(MOUSE_BUTTON_LEFT), _joy(JOY_BUTTON_RIGHT_SHOULDER)])
	_set_action("throw", [_mouse(MOUSE_BUTTON_RIGHT), _joy(JOY_BUTTON_LEFT_SHOULDER)])
	_set_action("dash", [_key(KEY_SHIFT), _joy(JOY_BUTTON_B)])
	_set_action("slam", [_key(KEY_CTRL), _key(KEY_C), _joy(JOY_BUTTON_X)])
	_set_action("pause", [_key(KEY_ESCAPE), _joy(JOY_BUTTON_START)])
	_set_action("pick_1", [_key(KEY_1)])
	_set_action("pick_2", [_key(KEY_2)])
	_set_action("pick_3", [_key(KEY_3)])
	# Оружие (этап 1): свитч мили ↔ ренж, подбор, перезарядка
	_set_action("weapon_switch", [_key(KEY_Q), _joy(JOY_BUTTON_Y)])
	_set_action("weapon_next", [_mouse(MOUSE_BUTTON_WHEEL_DOWN)])
	_set_action("weapon_prev", [_mouse(MOUSE_BUTTON_WHEEL_UP)])
	_set_action("weapon_melee", [_key(KEY_1)])
	_set_action("weapon_ranged", [_key(KEY_2)])
	_set_action("interact", [_key(KEY_E), _joy(JOY_BUTTON_DPAD_UP)])
	_set_action("reload", [_key(KEY_R), _joy(JOY_BUTTON_DPAD_LEFT)])

	ProjectSettings.set_setting("autoload/Run", "*res://run/run_manager.gd")
	ProjectSettings.set_setting("autoload/Odin", "*res://run/odin.gd")
	ProjectSettings.set_setting("autoload/Perf", "*res://scripts/perf.gd")
	# Короткий путь к user:// (лог фризов): %APPDATA%/ThorDostoynayaSmert
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "ThorDostoynayaSmert")

	var err := ProjectSettings.save()
	print("setup_project: save -> ", err)
	quit(0 if err == OK else 1)
