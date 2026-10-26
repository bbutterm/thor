extends Control
class_name SettingsPanel
## Простой экран настроек поверх главного меню (пока только комиксовые слова).
## Блок `comic_controls()` встраивается и в меню паузы. Сохранение — GameSettings (user://settings.cfg, [comic]).

signal closed

## Переключатель «Comic FX» и ползунок размера слов. Изменения сохраняются сразу.
static func comic_controls() -> Control:
	GameSettings.ensure_loaded()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	var toggle := CheckButton.new()
	toggle.text = "Комиксовые слова (Comic FX)"
	toggle.button_pressed = GameSettings.comic_enabled
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.add_theme_font_override("font", UIStyle.font())
	toggle.add_theme_font_size_override("font_size", 20)
	toggle.add_theme_color_override("font_color", UIStyle.TEXT)
	toggle.add_theme_color_override("font_hover_color", UIStyle.GOLD)
	toggle.add_theme_color_override("font_focus_color", UIStyle.GOLD)
	toggle.add_theme_color_override("font_pressed_color", UIStyle.TEXT)
	toggle.add_theme_color_override("font_hover_pressed_color", UIStyle.GOLD)
	vb.add_child(toggle)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UIStyle.label("Размер слов", 18, UIStyle.TEXT_DIM, 4))
	var slider := HSlider.new()
	slider.min_value = GameSettings.COMIC_SCALE_MIN
	slider.max_value = GameSettings.COMIC_SCALE_MAX
	slider.step = 0.05
	slider.value = GameSettings.comic_scale
	slider.custom_minimum_size = Vector2(170, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_ALL
	row.add_child(slider)
	var value := UIStyle.label("%d%%" % roundi(GameSettings.comic_scale * 100.0), 18, UIStyle.TEXT, 4)
	value.custom_minimum_size = Vector2(58, 0)
	row.add_child(value)
	vb.add_child(row)
	slider.editable = GameSettings.comic_enabled
	toggle.toggled.connect(func(on: bool) -> void:
		GameSettings.set_comic_enabled(on)
		slider.editable = on
		ComicFX.preview())
	slider.value_changed.connect(func(v: float) -> void:
		GameSettings.set_comic_scale(v)
		value.text = "%d%%" % roundi(v * 100.0)
		ComicFX.preview())
	return vb

func _ready() -> void:
	UIStyle.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	UIStyle.full_rect(dim)
	add_child(dim)
	var center := CenterContainer.new()
	UIStyle.full_rect(center)
	add_child(center)
	var panel := UIStyle.panel()
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var t := UIStyle.label("НАСТРОЙКИ", 40, UIStyle.GOLD, 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	vb.add_child(comic_controls())
	var back := UIStyle.button("Назад")
	back.pressed.connect(close)
	vb.add_child(back)
	back.grab_focus.call_deferred()

func close() -> void:
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
