extends CanvasLayer
class_name EndScreen
## Экран смерти / победы: Слава, статистика, вердикт Одина.

signal restart_requested
signal menu_requested

var _title: Label
var _verdict: Label
var _stats: Label
var _quote: Label
var _restart: Button
var _root: Control

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	UIStyle.full_rect(_root)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.02, 0.85)
	UIStyle.full_rect(dim)
	_root.add_child(dim)
	var center := CenterContainer.new()
	UIStyle.full_rect(center)
	_root.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	vb.custom_minimum_size = Vector2(640, 0)
	center.add_child(vb)
	_title = UIStyle.label("", 54, UIStyle.BLOOD, 12)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)
	_verdict = UIStyle.label("", 34, UIStyle.GOLD, 10)
	_verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_verdict)
	_quote = UIStyle.label("", 20, UIStyle.TEXT, 5)
	_quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_quote)
	var panel := UIStyle.panel()
	vb.add_child(panel)
	_stats = UIStyle.label("", 20, UIStyle.TEXT, 4)
	panel.add_child(_stats)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)
	_restart = UIStyle.button("Новое тело")
	_restart.pressed.connect(func() -> void: restart_requested.emit())
	hb.add_child(_restart)
	var menu := UIStyle.button("В меню")
	menu.pressed.connect(func() -> void: menu_requested.emit())
	hb.add_child(menu)

func show_result(victory: bool) -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if victory:
		_title.text = "ВАЛЬХАЛЛА!"
		_title.label_settings.font_color = UIStyle.GOLD
		_quote.text = "«%s»" % Odin.pick("victory")
	else:
		_title.text = "ТЫ ПАЛ"
		_title.label_settings.font_color = UIStyle.BLOOD
		_quote.text = "«%s»" % Odin.pick("death")
	_verdict.text = "Вердикт Одина: %s" % Run.verdict()
	var body_name := Run.body.display_name if Run.body else "—"
	_stats.text = "Тело: %s\nСлава: %d\nУбито врагов: %d\nЛучшая серия: %d\nПройдено залов: %d из %d\nРун собрано: %d" % [
		body_name, Run.glory, Run.kills, Run.best_streak,
		Run.room_index + (1 if victory else 0), Run.total_rooms(), Run.runes.size()]
	_root.modulate.a = 0.0
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.5)
	_restart.grab_focus()
