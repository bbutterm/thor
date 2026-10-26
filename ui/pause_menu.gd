extends CanvasLayer
class_name PauseMenu
## Пауза на Esc: продолжить, новый забег, в меню.

signal restart_requested
signal menu_requested

var _first: Button

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var root := Control.new()
	UIStyle.full_rect(root)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	UIStyle.full_rect(dim)
	root.add_child(dim)
	var center := CenterContainer.new()
	UIStyle.full_rect(center)
	root.add_child(center)
	var panel := UIStyle.panel()
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var t := UIStyle.label("ПАУЗА", 40, UIStyle.GOLD, 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var sub := UIStyle.label("Один ждёт. Нетерпеливо.", 18, UIStyle.TEXT_DIM, 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	_first = UIStyle.button("Продолжить")
	_first.pressed.connect(toggle)
	vb.add_child(_first)
	var r := UIStyle.button("Новое тело (заново)")
	r.pressed.connect(func() -> void: restart_requested.emit())
	vb.add_child(r)
	var m := UIStyle.button("В главное меню")
	m.pressed.connect(func() -> void: menu_requested.emit())
	vb.add_child(m)
	vb.add_child(SettingsPanel.comic_controls())

func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_first.grab_focus()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()
