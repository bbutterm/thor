extends CanvasLayer
class_name RunePick
## Выбор 1 из 3 рун после зачистки зала. Мышь, клавиши 1/2/3 или геймпад. На время выбора игра на паузе.

signal picked(rune: RuneDef)

var _choices: Array[RuneDef] = []
var _cards: HBoxContainer
var _root: Control
var _open_time: float = 0.0
var _title: Label
## Реплика Одина под заголовком, если в выборе клятва (С3)
var _odin: Label
const OATH_COLOR := Color(1.0, 0.32, 0.25)
const DEFAULT_TITLE := "НОРНЫ ПРЕДЛАГАЮТ РУНУ"
## Видимая ширина карточки (высота — по пропорциям card_rune)
@export var card_width: float = 300.0

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	UIStyle.full_rect(_root)
	UISkin.apply(_root)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.72)
	UIStyle.full_rect(dim)
	_root.add_child(dim)
	var center := CenterContainer.new()
	UIStyle.full_rect(center)
	_root.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vb)
	_title = UIStyle.label(tr(DEFAULT_TITLE), 40, UIStyle.GOLD, 10)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)
	var hint := UIStyle.label(tr("Выбери руну: мышь, 1 / 2 / 3 или геймпад"), 18, UIStyle.TEXT_DIM, 4)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)
	_odin = UIStyle.label("", 18, Color(1.0, 0.82, 0.5), 4)
	_odin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_odin.visible = false
	vb.add_child(_odin)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 22)
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(_cards)

## title — заголовок (Благословение Фрейи, улучшение руны на отдыхе); пусто — обычный.
func open(choices: Array[RuneDef], title: String = "") -> void:
	Perf.mark("rune_pick")
	_choices = choices
	_title.text = title if title != "" else tr(DEFAULT_TITLE)
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	for i in choices.size():
		_cards.add_child(_make_card(choices[i], i))
	# Клятва в выборе — Один предлагает её вслух (пузырь на паузе спрятан, поэтому строкой здесь)
	var has_oath := choices.any(func(r: RuneDef) -> bool: return r.oath)
	_odin.visible = has_oath
	if has_oath:
		_odin.text = tr("Один: «%s»") % Odin.pick("oath_offer")
		# Обучение: при первой клятве в выборе ворон объясняет, что это (пузырь на паузе спрятан — строкой здесь)
		if Save.event_count("tutorial_oath") == 0 and Dialogue.has_pool("ravens.tutorial_oath"):
			Save.bump_event("tutorial_oath")
			_odin.text += "\n" + tr("Хугин: «%s»") % Dialogue.pool_text("ravens.tutorial_oath")
	visible = true
	if _cards.get_child_count() > 0:
		(_cards.get_child(0) as Button).grab_focus.call_deferred()
	_open_time = Time.get_ticks_msec() / 1000.0
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.modulate.a = 0.0
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.2)

## Карточка руны на графике комплекта (card_rune): иконка категории в круге, руна в углу круга,
## название и описание следующего уровня в окне; проклятые — рамка «epic», с уровнем — «legendary».
func _make_card(rune: RuneDef, index: int) -> Button:
	var lvl := Run.rune_level(rune.id)
	var rarity := "epic" if rune.cursed else ("legendary" if lvl > 0 or rune.oath else "rare")
	var b := SkinCard.make("card_rune", card_width, rune.color, rarity)
	b.key_label.text = "[%d]" % (index + 1)
	b.set_icon(UISkin.rune_category_icon(rune.category), rune.glyph, rune.color.lightened(0.25))
	if rune.oath:
		# Своя рамка клятвы: красная обводка карточки (иконки клятв владелец сгенерирует — пока runecat_*)
		b.self_modulate = Color(1.0, 0.62, 0.55)
		b.add_text(tr("КЛЯТВА НАВСЕГДА"), 13, OATH_COLOR, 4)
	# Уровень (GDD 11: повторная руна повышает уровень 1–3) и описание следующего уровня
	var title_txt := tr(rune.title) + ("  %d → %d" % [lvl, lvl + 1] if lvl > 0 else "")
	b.add_text(title_txt, 19, rune.color.lightened(0.45), 5)
	var desc := tr(rune.description)
	if lvl < rune.level_descriptions.size():
		desc = tr(rune.level_descriptions[lvl])
	if rune.cursed:
		desc = tr("☠ Проклятие Локи\n") + desc
	b.add_text(desc, 14 if rune.oath else 15, UIStyle.TEXT, 3)
	if rune.oath and rune.oath_cost != "":
		b.add_text(tr("Цена: %s") % tr(rune.oath_cost), 14, OATH_COLOR, 3)
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
