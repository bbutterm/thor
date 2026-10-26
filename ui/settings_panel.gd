extends Control
class_name SettingsPanel
## Экран настроек (GDD 22) поверх главного меню и паузы: вкладки «Звук», «Управление», «Клавиши»,
## «Экран», «Интерфейс», «Доступность». Значения — GameSettings (user://settings.cfg), меняются и
## применяются сразу. Клавиши: клик по кнопке действия → нажми клавишу или кнопку мыши (Esc — отмена);
## «Сбросить клавиши» — как в project.godot. Рамка и кнопки — на скине комплекта (UISkin).

signal closed

const TABS := ["Звук", "Управление", "Клавиши", "Экран", "Интерфейс", "Доступность"]
const CAPTION_WIDTH := 330.0

var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _scroll: ScrollContainer
var _current: int = 0
var _capture_action: String = ""
var _capture_btn: Button
var _key_buttons: Dictionary = {}
var _key_note: Label
## Обновить подписи контролов после «Сбросить всё»: [секция, ключ, Callable(значение)]
var _refreshers: Array = []

func _ready() -> void:
	UIStyle.full_rect(self)
	UISkin.apply(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameSettings.ensure_loaded()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	UIStyle.full_rect(dim)
	add_child(dim)
	var center := CenterContainer.new()
	UIStyle.full_rect(center)
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"WoodPanel"
	panel.custom_minimum_size = Vector2(980, 600)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var t := UIStyle.label("НАСТРОЙКИ", 38, UIStyle.GOLD, 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 4)
	vb.add_child(tabs)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.theme_type_variation = &"SmallButton"
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(146, 42)
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(show_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 360)
	vb.add_child(_scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	for i in TABS.size():
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 8)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.visible = false
		pages.add_child(page)
		_pages.append(page)
	_build_audio(_pages[0])
	_build_controls(_pages[1])
	_build_keys(_pages[2])
	_build_video(_pages[3])
	_build_interface(_pages[4])
	_build_access(_pages[5])
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 16)
	vb.add_child(foot)
	var reset := UIStyle.button("Сбросить всё", 19, "danger")
	reset.custom_minimum_size = Vector2(240, 50)
	reset.pressed.connect(_reset_all)
	foot.add_child(reset)
	var back := UIStyle.button("Назад", 22)
	back.custom_minimum_size = Vector2(260, 54)
	back.pressed.connect(close)
	foot.add_child(back)
	show_tab(0)
	back.grab_focus.call_deferred()

func tab_count() -> int:
	return TABS.size()

func show_tab(i: int) -> void:
	_current = clampi(i, 0, _pages.size() - 1)
	for k in _pages.size():
		_pages[k].visible = k == _current
		_tab_buttons[k].set_pressed_no_signal(k == _current)
	_scroll.scroll_vertical = 0
	_cancel_capture()

func close() -> void:
	_cancel_capture()
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if _capture_action != "":
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

# --- Строки ---

func _row(page: Control, caption: String, control: Control, hint: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := UIStyle.label(caption, 19, UIStyle.TEXT, 5)
	l.custom_minimum_size = Vector2(CAPTION_WIDTH, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if hint != "":
		l.tooltip_text = hint
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	page.add_child(row)
	return row

func _header(page: Control, text: String) -> void:
	var h := UIStyle.label(text, 16, Color(UIStyle.GOLD, 0.85), 4)
	page.add_child(h)

func _note(page: Control, text: String) -> Label:
	var l := UIStyle.label(text, 15, UIStyle.TEXT_DIM, 3)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(860, 0)
	page.add_child(l)
	return l

## Ползунок с подписью значения. fmt(v) → текст; on_change — доп. действие (превью)
func _slider(page: Control, caption: String, section: String, key: String, lo: float, hi: float, step: float,
		fmt: Callable, on_change: Callable = Callable()) -> HSlider:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(GameSettings.get_value(section, key))
	s.custom_minimum_size = Vector2(380, 32)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	box.add_child(s)
	var val := UIStyle.label(fmt.call(s.value), 18, UIStyle.GOLD, 4)
	val.custom_minimum_size = Vector2(96, 0)
	box.add_child(val)
	s.value_changed.connect(func(v: float) -> void:
		GameSettings.set_value(section, key, v)
		val.text = fmt.call(v)
		if on_change.is_valid():
			on_change.call())
	_row(page, caption, box)
	_refreshers.append([section, key, func(v: Variant) -> void:
		s.set_value_no_signal(float(v))
		val.text = fmt.call(float(v))])
	s.set_meta("setting", section + "/" + key)
	return s

func _check(page: Control, caption: String, section: String, key: String, on_change: Callable = Callable()) -> CheckBox:
	var c := CheckBox.new()
	c.text = "вкл"
	c.button_pressed = bool(GameSettings.get_value(section, key))
	c.text = "вкл" if c.button_pressed else "выкл"
	c.focus_mode = Control.FOCUS_ALL
	c.toggled.connect(func(on: bool) -> void:
		GameSettings.set_value(section, key, on)
		c.text = "вкл" if on else "выкл"
		if on_change.is_valid():
			on_change.call())
	_row(page, caption, c)
	_refreshers.append([section, key, func(v: Variant) -> void:
		c.set_pressed_no_signal(bool(v))
		c.text = "вкл" if bool(v) else "выкл"])
	c.set_meta("setting", section + "/" + key)
	return c

## Выпадающий список: items — [[значение, подпись], ...]
func _option(page: Control, caption: String, section: String, key: String, items: Array) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(320, 44)
	o.focus_mode = Control.FOCUS_ALL
	var cur: Variant = GameSettings.get_value(section, key)
	for i in items.size():
		o.add_item(str(items[i][1]), i)
		if items[i][0] == cur:
			o.select(i)
	o.item_selected.connect(func(i: int) -> void: GameSettings.set_value(section, key, items[i][0]))
	var box := HBoxContainer.new()
	box.add_child(o)
	_row(page, caption, box)
	_refreshers.append([section, key, func(v: Variant) -> void:
		for i in items.size():
			if items[i][0] == v:
				o.select(i)])
	o.set_meta("setting", section + "/" + key)
	return o

static func _pct(v: float) -> String:
	return "%d %%" % roundi(v * 100.0)

# --- Вкладки ---

func _build_audio(page: Control) -> void:
	_header(page, "ГРОМКОСТЬ")
	_slider(page, "Общая", "audio", "master", 0.0, 1.0, 0.05, _pct)
	_slider(page, "Музыка", "audio", "music", 0.0, 1.0, 0.05, _pct)
	_slider(page, "Эффекты", "audio", "sfx", 0.0, 1.0, 0.05, _pct,
		func() -> void: Audio.play("sounds/sfx/hammer_catch.wav"))
	_slider(page, "Голоса", "audio", "voice", 0.0, 1.0, 0.05, _pct)

func _build_controls(page: Control) -> void:
	_header(page, "МЫШЬ И ГЕЙМПАД")
	_slider(page, "Чувствительность мыши", "controls", "mouse_sensitivity", 0.1, 3.0, 0.05,
		func(v: float) -> String: return "×%.2f" % v)
	_slider(page, "Чувствительность стика", "controls", "gamepad_sensitivity", 0.1, 3.0, 0.05,
		func(v: float) -> String: return "×%.2f" % v)
	_check(page, "Инверсия по вертикали", "controls", "invert_y")
	_note(page, "Клавиши переназначаются на вкладке «Клавиши».")

func _build_keys(page: Control) -> void:
	_header(page, "КЛАВИШИ — клик по кнопке, затем нажми клавишу или кнопку мыши (Esc — отмена)")
	for pair in GameSettings.REMAP_ACTIONS:
		var action: String = pair[0]
		var b := Button.new()
		b.theme_type_variation = &"SecondaryButton"
		b.custom_minimum_size = Vector2(300, 44)
		b.text = GameSettings.action_label(action)
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(_start_capture.bind(action, b))
		var box := HBoxContainer.new()
		box.add_child(b)
		_row(page, pair[1], box)
		_key_buttons[action] = b
	var reset := UIStyle.button("Сбросить клавиши", 18, "danger")
	reset.custom_minimum_size = Vector2(260, 48)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		GameSettings.reset_input()
		_refresh_keys()
		_key_note.text = "Клавиши — как по умолчанию.")
	page.add_child(reset)
	_key_note = _note(page, "Esc — пауза, 1/2/3 — выбор карточек; геймпад не меняется.")

func _build_video(page: Control) -> void:
	_header(page, "ОКНО")
	_check(page, "Полноэкранный режим", "video", "fullscreen")
	_check(page, "Вертикальная синхронизация (VSync)", "video", "vsync")
	var fps: Array = []
	for f in GameSettings.FPS_OPTIONS:
		fps.append([f, "без ограничения" if f == 0 else "%d" % f])
	_option(page, "Ограничение FPS", "video", "max_fps", fps)
	_header(page, "КАМЕРА")
	_slider(page, "Поле зрения (FOV)", "video", "fov", GameSettings.FOV_MIN, GameSettings.FOV_MAX, 1.0,
		func(v: float) -> String: return "%d°" % roundi(v))
	_slider(page, "Тряска камеры", "video", "shake", 0.0, 1.0, 0.05, _pct)
	_check(page, "Покачивание и наклон камеры", "video", "head_bob")

func _build_interface(page: Control) -> void:
	_header(page, "ПРИЦЕЛ")
	_option(page, "Вид прицела", "hud", "crosshair",
		[["dot", "точка"], ["cross", "крест"], ["circle", "круг с молнией"], ["classic", "классический"]])
	_slider(page, "Размер прицела", "hud", "crosshair_size", 0.4, 2.5, 0.05, _pct)
	_slider(page, "Яркость прицела", "hud", "crosshair_alpha", 0.2, 1.0, 0.05, _pct)
	_option(page, "Цвет прицела", "hud", "crosshair_color",
		[["white", "белый"], ["yellow", "жёлтый"], ["green", "зелёный"], ["cyan", "голубой"], ["red", "красный"], ["magenta", "пурпурный"]])
	_header(page, "HUD")
	_check(page, "Индикаторы врагов за экраном", "hud", "offscreen")
	_check(page, "Шкала высоты удара-приземления", "hud", "slam_meter")
	_slider(page, "Масштаб интерфейса", "video", "ui_scale", 0.75, 1.5, 0.05, _pct)
	_header(page, "КОМИКСОВЫЕ СЛОВА")
	_comic_rows(page)
	_header(page, "СУБТИТРЫ И ТЕКСТ")
	_slider(page, "Размер текста диалогов", "text", "text_scale", 0.75, 1.6, 0.05, _pct)
	_option(page, "Скорость печати", "text", "typing_speed",
		[[0.6, "медленно"], [1.0, "обычно"], [1.6, "быстро"], [2.5, "очень быстро"], [0.0, "сразу целиком"]])

func _comic_rows(page: Control) -> void:
	var holder: Array = [null]
	_check(page, "Комиксовые слова (Comic FX)", "comic", "enabled", func() -> void:
		if holder[0]:
			(holder[0] as HSlider).editable = GameSettings.comic_enabled
		ComicFX.preview())
	var size_slider := _slider(page, "Размер слов", "comic", "scale", GameSettings.COMIC_SCALE_MIN, GameSettings.COMIC_SCALE_MAX, 0.05,
		_pct, func() -> void: ComicFX.preview())
	size_slider.editable = GameSettings.comic_enabled
	holder[0] = size_slider

func _build_access(page: Control) -> void:
	_header(page, "ЦВЕТ")
	_option(page, "Цветовая слепота (коррекция экрана)", "access", "colorblind",
		[["off", "выкл"], ["protanopia", "протанопия"], ["deuteranopia", "дейтеранопия"], ["tritanopia", "тританопия"]])
	_note(page, "Телеграфы атак врагов дублируются формой и звуком, не только цветом.")
	_header(page, "ПОМОЩЬ (облегчённый режим, без штрафа к Славе)")
	_check(page, "Помощь в прицеливании (ренж)", "access", "aim_assist")
	_check(page, "Замедление времени при ударе-приземлении", "access", "slam_slowmo")

# --- Переназначение клавиш ---

func _start_capture(action: String, b: Button) -> void:
	_cancel_capture()
	_capture_action = action
	_capture_btn = b
	b.text = "нажми клавишу…"
	_key_note.text = "Esc — отмена."

func _cancel_capture() -> void:
	if _capture_action == "":
		return
	var a := _capture_action
	_capture_action = ""
	if _capture_btn and is_instance_valid(_capture_btn):
		_capture_btn.text = GameSettings.action_label(a)
	_capture_btn = null

func _input(event: InputEvent) -> void:
	if _capture_action == "":
		return
	var ok := false
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.physical_keycode == KEY_ESCAPE or k.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_cancel_capture()
			_key_note.text = "Отменено."
			return
		ok = true
	elif event is InputEventMouseButton and event.pressed:
		ok = true
	if not ok:
		return
	get_viewport().set_input_as_handled()
	apply_capture(event)

## Назначить пойманное событие действию, которое ждёт клавишу (тест зовёт напрямую)
func apply_capture(event: InputEvent) -> void:
	var action := _capture_action
	if action == "":
		return
	_capture_action = ""
	var taken := GameSettings.rebind(action, event)
	_refresh_keys()
	_capture_btn = null
	var label := GameSettings.binding_label(GameSettings.event_to_string(event))
	if taken != "":
		_key_note.text = "%s — теперь «%s» (снято с «%s»)." % [label, _title(action), _title(taken)]
	else:
		_key_note.text = "%s — теперь «%s»." % [label, _title(action)]

func _title(action: String) -> String:
	for pair in GameSettings.REMAP_ACTIONS:
		if pair[0] == action:
			return pair[1]
	return action

func _refresh_keys() -> void:
	for a in _key_buttons:
		(_key_buttons[a] as Button).text = GameSettings.action_label(a)

func _reset_all() -> void:
	GameSettings.reset_all()
	for r in _refreshers:
		(r[2] as Callable).call(GameSettings.get_value(r[0], r[1]))
	_refresh_keys()
	ComicFX.preview()
