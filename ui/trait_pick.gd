extends CanvasLayer
class_name TraitPick
## Выбор 1 из 3 трейтов Мьёльнира после мини-босса (GDD 10). Мышь или 1/2/3, игра на паузе.
## Визуально отдельно от рун: грозовой синий фон, скошенные «ледяные» карточки, руна в круге.
## Трейт той же группы заменяет старый — требует второго нажатия (подтверждение).
## Строится кодом; в game.gd создаётся как TraitPick.new().

signal picked(t: MjolnirTrait)

const STORM := Color(0.03, 0.06, 0.12, 0.86)
const CARD := Color(0.07, 0.12, 0.2, 0.97)
const CARD_HOVER := Color(0.1, 0.18, 0.3, 0.99)
const REPLACE := Color(1.0, 0.5, 0.4)
const NEW := Color(0.55, 1.0, 0.65)

var _choices: Array[MjolnirTrait] = []
var _cards: HBoxContainer
var _root: Control
var _status_labels: Array[Label] = []
var _open_time: float = 0.0
var _confirm_index: int = -1

func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	UIStyle.full_rect(_root)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = STORM
	UIStyle.full_rect(dim)
	_root.add_child(dim)
	var center := CenterContainer.new()
	UIStyle.full_rect(center)
	_root.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vb)
	var title := UIStyle.label("ᛗ  МЬЁЛЬНИР ЖАЖДЕТ СИЛЫ  ᛗ", 40, UIStyle.ICE, 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var hint := UIStyle.label("Трейт молота меняет то, как ты им играешь. Кликни или нажми 1 / 2 / 3", 18, UIStyle.TEXT_DIM, 4)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 30)
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(_cards)

func open(choices: Array[MjolnirTrait]) -> void:
	Perf.mark("trait_pick_open")
	_choices = choices
	_confirm_index = -1
	_status_labels.clear()
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
	tw.tween_property(_root, "modulate:a", 1.0, 0.25)

func _card_style(bg: Color, border: Color, w: int) -> StyleBoxFlat:
	var sb := UIStyle.panel_style(bg, border, 4, w)
	sb.skew = Vector2(0.08, 0)
	sb.shadow_color = Color(0.2, 0.5, 1.0, 0.25)
	sb.shadow_size = 12
	return sb

func _status(t: MjolnirTrait) -> Array:
	var lv := Run.mjolnir_trait_level(t.id)
	if lv > 0:
		return ["УРОВЕНЬ %d" % (lv + 1), UIStyle.GOLD]
	var old := Run.mjolnir_trait_conflict(t)
	if old:
		return ["ЗАМЕНИТ: %s" % old.title, REPLACE]
	return ["НОВЫЙ", NEW]

func _make_card(t: MjolnirTrait, index: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(270, 360)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_stylebox_override("normal", _card_style(CARD, Color(t.color, 0.55), 2))
	b.add_theme_stylebox_override("hover", _card_style(CARD_HOVER, t.color, 3))
	b.add_theme_stylebox_override("focus", _card_style(CARD_HOVER, t.color, 3))
	b.add_theme_stylebox_override("pressed", _card_style(CARD_HOVER.lightened(0.1), t.color, 3))
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 10)
	UIStyle.full_rect(vb)
	vb.offset_left = 20
	vb.offset_right = -20
	vb.offset_top = 16
	vb.offset_bottom = -16
	b.add_child(vb)
	var key := UIStyle.label("[%d]" % (index + 1), 16, UIStyle.TEXT_DIM, 4)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(key)
	# Руна в круге — отличие от карточек рун (там руна без рамки)
	var ring := PanelContainer.new()
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(0, 0, 0, 0.35)
	rs.border_color = t.color
	rs.set_border_width_all(3)
	rs.set_corner_radius_all(48)
	rs.set_content_margin_all(6)
	ring.add_theme_stylebox_override("panel", rs)
	ring.custom_minimum_size = Vector2(96, 96)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(ring)
	var glyph := UIStyle.label(t.glyph, 56, t.color, 8)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ring.add_child(glyph)
	var name_l := UIStyle.label(t.title, 22, UIStyle.TEXT, 6)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(name_l)
	if t.group != "":
		var g := UIStyle.label("группа: " + t.group, 14, Color(t.color, 0.8), 3)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(g)
	var lv := Run.mjolnir_trait_level(t.id)
	var d := UIStyle.label(t.description_lvl2 if lv > 0 and t.description_lvl2 != "" else t.description, 15, UIStyle.TEXT_DIM, 3)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(d)
	var st := _status(t)
	var s := UIStyle.label(st[0], 16, st[1], 4)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(s)
	_status_labels.append(s)
	for c in vb.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(func() -> void: choose(index))
	return b

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	for i in 3:
		if event.is_action_pressed("pick_%d" % (i + 1)):
			choose(i)
			get_viewport().set_input_as_handled()

## Выбрать карточку. Замена трейта той же группы — только со второго нажатия.
func choose(index: int, confirmed: bool = false) -> void:
	if not visible or index < 0 or index >= _choices.size():
		return
	if Time.get_ticks_msec() / 1000.0 - _open_time < 0.25:
		return
	var t := _choices[index]
	var old := Run.mjolnir_trait_conflict(t) if Run.mjolnir_trait_level(t.id) == 0 else null
	if old and not confirmed and _confirm_index != index:
		_confirm_index = index
		var l := _status_labels[index]
		l.text = "Ещё раз — заменить «%s»" % old.title
		l.label_settings.font_color = REPLACE
		return
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	picked.emit(t)
