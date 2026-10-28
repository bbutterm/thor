extends Control
## Главное меню: начать забег, выход, подсказка по управлению.

## Всё меню (фон, кнопки, подсказка) — пересобирается при смене языка
var _ui: Control

func _ready() -> void:
	FX.reset_time()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UIStyle.full_rect(self)
	UISkin.apply(self)
	_build()
	GameSettings.events.changed.connect(_on_setting_changed)
	# Экраны выбора тела и «Плана тренировок» — картинки заранее в фоне (ui/screen_art.gd)
	ScreenArt.prefetch_between_runs()
	if "--selftest" in OS.get_cmdline_user_args():
		_selftest.call_deferred()

func _on_setting_changed(section: String, key: String) -> void:
	if section == "text" and key == "language":
		_rebuild.call_deferred()

## Смена языка (настройки поверх меню): меню собирается заново под открытой панелью настроек
func _rebuild() -> void:
	if _ui and is_instance_valid(_ui):
		remove_child(_ui)
		_ui.queue_free()
	_build(false)
	move_child(_ui, 0)

func _build(focus: bool = true) -> void:
	_ui = Control.new()
	_ui.name = "UI"
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.full_rect(_ui)
	add_child(_ui)
	# Фон и эмблема из комплекта владельца (menu_background, logo_emblem); нет картинок — тёмный фон
	var bg_tex := UISkin.texture("menu_background")
	if bg_tex:
		var bg := TextureRect.new()
		bg.texture = bg_tex
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		UIStyle.full_rect(bg)
		_ui.add_child(bg)
		# Левая треть — под меню: мягкое затемнение, чтобы читались кнопки
		var shade := TextureRect.new()
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.78))
		g.set_color(1, Color(0, 0, 0, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0.0, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 128
		gt.height = 4
		shade.texture = gt
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		shade.offset_right = 760
		_ui.add_child(shade)
	else:
		var bgc := ColorRect.new()
		UIStyle.full_rect(bgc)
		bgc.color = Color(0.05, 0.05, 0.07)
		_ui.add_child(bgc)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 60
	col.offset_right = 520
	col.offset_top = 16
	col.offset_bottom = -16
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	_ui.add_child(col)
	var vb := col

	var logo_tex := UISkin.texture("logo_emblem")
	if logo_tex:
		var logo := TextureRect.new()
		logo.texture = logo_tex
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(0, 150)
		vb.add_child(logo)
	var title := UIStyle.label(tr("ТОР"), 64, UIStyle.GOLD, 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := UIStyle.label(tr("ДОСТОЙНАЯ СМЕРТЬ"), 30, UIStyle.TEXT, 8)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var tag := UIStyle.label(tr("Тор скуфнулся. Один вселяет его в смертных воинов — возвращать форму."), 16, UIStyle.TEXT_DIM, 4)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(tag)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vb.add_child(spacer)

	var start := UIStyle.button(tr("Начать забег"), 28)
	start.custom_minimum_size = Vector2(360, 64)
	start.pressed.connect(_on_start)
	var start_box := CenterContainer.new()
	start_box.add_child(start)
	vb.add_child(start_box)
	var plan := UIStyle.button(tr("План тренировок"), 22, "secondary")
	plan.custom_minimum_size = Vector2(320, 54)
	plan.pressed.connect(_on_plan)
	var plan_box := CenterContainer.new()
	plan_box.add_child(plan)
	vb.add_child(plan_box)
	var settings := UIStyle.button(tr("Настройки"), 22, "secondary")
	settings.custom_minimum_size = Vector2(320, 54)
	settings.pressed.connect(func() -> void:
		var sp := SettingsPanel.new()
		sp.closed.connect(settings.grab_focus)
		add_child(sp))
	var settings_box := CenterContainer.new()
	settings_box.add_child(settings)
	vb.add_child(settings_box)
	var quit := UIStyle.button(tr("Выход"), 22, "danger")
	quit.custom_minimum_size = Vector2(320, 54)
	quit.pressed.connect(func() -> void: get_tree().quit())
	var quit_box := CenterContainer.new()
	quit_box.add_child(quit)
	vb.add_child(quit_box)

	# Подсказка по управлению — справа внизу, поверх фона
	var controls := UIStyle.panel(Color(0.08, 0.08, 0.1, 0.9), Color(UIStyle.ICE, 0.35))
	controls.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	controls.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	controls.grow_vertical = Control.GROW_DIRECTION_BEGIN
	controls.offset_right = -24
	controls.offset_bottom = -20
	controls.modulate.a = 0.92
	var cl := UIStyle.label(
		tr("WASD — бег  ·  Пробел — прыжок / двойной\nShift — рывок  ·  Ctrl или C в воздухе — удар-приземление\nCtrl+Shift — подкат  ·  Пробел после приземления — СУПЕР-ПРЫЖОК\nЛКМ — удар (комбо из 3)  ·  ПКМ — метнуть / вернуть Мьёльнир\nQ — сменить оружие  ·  E — подобрать  ·  Esc — пауза"), 15, UIStyle.TEXT_DIM, 3)
	cl.text += "\n" + tr("Геймпад: управление и кнопки — в настройках.")
	controls.add_child(cl)
	_ui.add_child(controls)
	if focus:
		start.grab_focus()

## «План тренировок Одина» из меню: «В бой» — сразу забег, «Назад» — в меню.
func _on_plan() -> void:
	var tp := TrainingPlan.new()
	add_child(tp)
	tp.open(tr("Назад"))
	if await tp.closed:
		tp.queue_free()
		_on_start()
	else:
		tp.queue_free()

## «Начать забег»: экран выбора тела (ui/body_select.gd), потом забег этим телом.
func _on_start() -> void:
	var bs := BodySelect.new()
	bs.name = "BodySelect"
	add_child(bs)
	bs.open(tr("Назад"), Run.body.id if Run.body else "")
	var id: String = await bs.closed
	bs.queue_free()
	if id != "":
		_start_with(id)

func _start_with(body_id: String) -> void:
	Run.start_run(body_id)
	# Картинка и совет Одина, пока грузится забег (ui/loading_screen.gd; скрывает Game после первого зала)
	await LoadingScreen.show_now(get_tree())
	get_tree().change_scene_to_file("res://scenes/game.tscn")

## Проверка собранной игры: ./Thor.exe --headless -- --selftest.
## Проверка F5 требует изолированный профиль с файлами-маркерами и --selftest-lag-desktop=<путь>.
func _selftest() -> void:
	var has_odin_line := Odin.pick("death") != ""
	print("SELFTEST bodies=%d runes=%d odin=%s" % [Run.all_bodies.size(), Run.all_runes.size(), has_odin_line])
	if Run.all_bodies.is_empty() or Run.all_runes.is_empty() or not has_odin_line:
		printerr("SELFTEST FAIL: не загружены тела, руны или реплики Одина")
		get_tree().quit(1)
		return
	# Новелла не должна останавливать физику, пока проверяем загрузку первой боевой волны.
	Dialogue.in_run_scenes = false
	get_tree().root.add_child(SelfTestRunner.new())
	_start_with("")

class SelfTestRunner extends Node:
	func _ready() -> void:
		# Process-кадры в headless могут закончиться до первого тика физики и появления врагов.
		for i in 600:
			await get_tree().physics_frame
			var g := get_tree().current_scene as Game
			if g and is_instance_valid(g.room) and g.room._started and g.room.alive_enemies().size() > 0:
				if "--selftest-lag" in OS.get_cmdline_user_args():
					var lag_ok := await _test_lag_report()
					if not lag_ok:
						get_tree().quit(1)
						return
				print("SELFTEST OK scene=%s room=%s enemies=%d" % [g.name, Run.current_room_path(), g.room.alive_enemies().size()])
				get_tree().quit(0)
				return
		var current := get_tree().current_scene
		printerr("SELFTEST FAIL: за 600 физических кадров не появилась боевая волна (сцена=%s, зал=%s)" % [current.name if current else "нет", Run.current_room_path()])
		get_tree().quit(1)

	func _test_lag_report() -> bool:
		var arg_prefix := "--selftest-lag-desktop="
		var expected := ""
		var path_args := 0
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with(arg_prefix):
				expected = arg.trim_prefix(arg_prefix)
				path_args += 1
		var desktop := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
		if path_args != 1 or expected.is_empty() or not expected.replace("\\", "/").is_absolute_path() \
				or desktop.is_empty() or _normalize_path(expected) != _normalize_path(desktop) \
				or not DirAccess.dir_exists_absolute(desktop):
			printerr("SELFTEST LAG FAIL: рабочий стол не совпал с ожидаемым или недоступен: %s" % desktop)
			return false
		var dir := DirAccess.open(desktop)
		if dir == null:
			printerr("SELFTEST LAG FAIL: не удалось открыть рабочий стол: %s" % desktop)
			return false
		dir.include_hidden = true
		# Не допускаем перезаписи ранее созданного отчёта: имя содержит время только до секунды.
		for name in dir.get_files():
			if name.to_lower().begins_with("thor_lag_") and name.to_lower().ends_with(".zip"):
				printerr("SELFTEST LAG FAIL: рабочий стол теста уже содержит отчёт: %s" % name)
				return false
		# Фикстуры создаёт запускающий тест в изолированном профиле; настоящие файлы не заменяем.
		for name in ["save.json", "settings.cfg"]:
			var user_path: String = "user://" + name
			if not FileAccess.file_exists(user_path) or not FileAccess.get_file_as_string(user_path).contains("isolated_selftest"):
				printerr("SELFTEST LAG FAIL: нет тестового файла %s" % user_path)
				return false

		# Создаём узнаваемую запись настоящим механизмом логирования и восстанавливаем настройки.
		var marker := "selftest_lag_%d" % Time.get_ticks_usec()
		var old_hitch_ms: float = Perf.hitch_ms
		var old_logging: bool = Perf.enabled_logging
		Perf.hitch_ms = -1.0
		Perf.enabled_logging = true
		Perf.mark(marker)
		await get_tree().process_frame
		await get_tree().process_frame
		Perf.hitch_ms = old_hitch_ms
		Perf.enabled_logging = old_logging

		# Событие проходит через обычную доставку ввода, а не прямой вызов Perf.report_lag().
		var key := InputEventKey.new()
		key.physical_keycode = KEY_F5
		key.pressed = true
		Input.parse_input_event(key)
		for i in 6:
			await get_tree().process_frame
			var reports: PackedStringArray = []
			for name in dir.get_files():
				if name.to_lower().begins_with("thor_lag_") and name.to_lower().ends_with(".zip"):
					reports.append(name)
			if reports.size() == 1:
				var release := InputEventKey.new()
				release.physical_keycode = KEY_F5
				Input.parse_input_event(release)
				return _check_lag_zip(desktop.path_join(reports[0]), marker)
			if reports.size() > 1:
				printerr("SELFTEST LAG FAIL: после F5 найдено несколько отчётов")
				return false
		printerr("SELFTEST LAG FAIL: после F5 отчёт на рабочем столе не появился")
		return false

	func _normalize_path(path: String) -> String:
		var normalized := path.replace("\\", "/").simplify_path().trim_suffix("/")
		return normalized.to_lower() if OS.get_name() == "Windows" else normalized

	func _check_lag_zip(path: String, marker: String) -> bool:
		var zip := ZIPReader.new()
		if zip.open(path) != OK:
			printerr("SELFTEST LAG FAIL: не удалось открыть ZIP: %s" % path)
			return false
		var files := zip.get_files()
		var ok := "system.txt" in files and "hitches.log" in files
		if ok:
			var info := zip.read_file("system.txt").get_string_from_utf8()
			var log := zip.read_file("hitches.log").get_string_from_utf8()
			ok = info.contains(OS.get_name()) and info.contains("API:") and info.contains("Godot:") and log.contains(marker)
		# Проверяем, что именно тестовые сохранение и настройки вошли в архив без изменений.
		for name in ["save.json", "settings.cfg"]:
			var user_path: String = "user://" + name
			if not name in files or zip.read_file(name) != FileAccess.get_file_as_bytes(user_path):
				ok = false
		zip.close()
		if not ok:
			printerr("SELFTEST LAG FAIL: архив не содержит ожидаемые данные (%s)" % str(files))
			return false
		print("SELFTEST LAG OK desktop=%s archive=%s files=%s" % [path.get_base_dir(), path, str(files)])
		return true
