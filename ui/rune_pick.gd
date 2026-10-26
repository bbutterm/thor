extends CanvasLayer
class_name RunePick
## Выбор 1 из 3 рун после зачистки зала. Мышь или клавиши 1/2/3. На время выбора игра на паузе.

signal picked(rune: RuneDef)

var _choices: Array[RuneDef] = []
var _cards: HBoxContainer
var _root: Control
var _open_time: float = 0.0

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	UIStyle.full_rect(_root)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.72)
	UIStyle.full_rect(dim)
	_root.add_child(dim)
	var center := CenterContainer.new()
	UIStyle.full_rect(center)
	_root.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 24)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vb)
	var title := UIStyle.label("НОРНЫ ПРЕДЛАГАЮТ РУНУ", 40, UIStyle.GOLD, 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var hint := UIStyle.label("Кликни по руне или нажми 1 / 2 / 3", 18, UIStyle.TEXT_DIM, 4)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 22)
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(_cards)

func open(choices: Array[RuneDef]) -> void:
	Perf.mark("rune_pick")
	_choices = choices
	for c in _cards.get_children():
		c.queue_free()
	for i in choices.size():
		_cards.add_child(_make_card(choices[i], i))
	visible = true
	_open_time = Time.get_ticks_msec() / 1000.0
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.modulate.a = 0.0
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.2)

func _make_card(rune: RuneDef, index: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(250, 300)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_stylebox_override("normal", UIStyle.panel_style(UIStyle.STONE_LIGHT, Color(rune.color, 0.5), 12))
	b.add_theme_stylebox_override("hover", UIStyle.panel_style(Color(0.2, 0.19, 0.22, 0.98), rune.color, 12, 3))
	b.add_theme_stylebox_override("focus", UIStyle.panel_style(Color(0.2, 0.19, 0.22, 0.98), rune.color, 12, 3))
	b.add_theme_stylebox_override("pressed", UIStyle.panel_style(Color(0.26, 0.24, 0.28, 1.0), rune.color, 12, 3))
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 12)
	UIStyle.full_rect(vb)
	vb.offset_left = 18
	vb.offset_right = -18
	vb.offset_top = 18
	vb.offset_bottom = -18
	b.add_child(vb)
	var key := UIStyle.label("[%d]" % (index + 1), 16, UIStyle.TEXT_DIM, 4)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(key)
	var glyph := UIStyle.label(rune.glyph, 72, rune.color, 10)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(glyph)
	# Уровень (GDD 11: повторная руна повышает уровень 1–3) и описание следующего уровня
	var lvl := Run.rune_level(rune.id)
	var title_txt := rune.title + ("  ур. %d → %d" % [lvl, lvl + 1] if lvl > 0 else "")
	var t := UIStyle.label(title_txt, 22, UIStyle.TEXT, 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(t)
	var desc := rune.description
	if lvl < rune.level_descriptions.size():
		desc = rune.level_descriptions[lvl]
	if rune.cursed:
		desc = "☠ Проклятие Локи\n" + desc
	var d := UIStyle.label(desc, 16, UIStyle.TEXT_DIM, 3)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(d)
	for c in vb.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(func() -> void: choose(index))
	return b

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	for i in 3:
		if event.is_action_pressed("pick_%d" % (i + 1)):
			choose(i)
			get_viewport().set_input_as_handled()

func choose(index: int) -> void:
	if not visible or index < 0 or index >= _choices.size():
		return
	# Защита от случайного клика сразу после открытия
	if Time.get_ticks_msec() / 1000.0 - _open_time < 0.25:
		return
	var rune := _choices[index]
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	picked.emit(rune)
