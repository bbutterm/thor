extends CanvasLayer
class_name TraitPick
## Выбор 1 из 3 трейтов Мьёльнира после мини-босса (GDD 10). Мышь или 1/2/3, игра на паузе.
## Визуально отдельно от рун: грозовой синий фон, карточки card_trait комплекта (золото и молнии).
## Трейт той же группы заменяет старый — требует второго нажатия (подтверждение).
## Строится кодом; в game.gd создаётся как TraitPick.new().

signal picked(t: MjolnirTrait)
## «Обслуживание Мьёльнира» в ларьке без трейтов → переброс выбора (Run.trait_rerolls); обработчик — RewardFlow
signal reroll_requested

const STORM := Color(0.03, 0.06, 0.12, 0.86)
const CARD := Color(0.07, 0.12, 0.2, 0.97)
const CARD_HOVER := Color(0.1, 0.18, 0.3, 0.99)
const REPLACE := Color(1.0, 0.5, 0.4)
const NEW := Color(0.55, 1.0, 0.65)
## Видимая ширина карточки (высота — по пропорциям card_trait)
@export var card_width: float = 300.0

var _choices: Array[MjolnirTrait] = []
var _cards: HBoxContainer
var _root: Control
var _status_labels: Array[Label] = []
var _open_time: float = 0.0
var _confirm_index: int = -1
var _reroll_btn: Button

func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	UIStyle.full_rect(_root)
	UISkin.apply(_root)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = STORM
	UIStyle.full_rect(dim)
	_root.add_child(dim)
	var center := CenterContainer.new()
	UIStyle.full_rect(center)
	_root.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
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
	_reroll_btn = UIStyle.button("ПЕРЕБРОС  [R]", 20)
	_reroll_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reroll_btn.visible = false
	_reroll_btn.pressed.connect(func() -> void: reroll_requested.emit())
	vb.add_child(_reroll_btn)

func open(choices: Array[MjolnirTrait]) -> void:
	Perf.mark("trait_pick_open")
	_choices = choices
	_confirm_index = -1
	_status_labels.clear()
	for c in _cards.get_children():
		c.queue_free()
	for i in choices.size():
		_cards.add_child(_make_card(choices[i], i))
	_reroll_btn.visible = Run.trait_rerolls > 0
	_reroll_btn.text = "ПЕРЕБРОС ОТ ЭЙТРИ (%d)  [R]" % Run.trait_rerolls
	visible = true
	_open_time = Time.get_ticks_msec() / 1000.0
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.modulate.a = 0.0
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.25)

func _status(t: MjolnirTrait) -> Array:
	var lv := Run.mjolnir_trait_level(t.id)
	if lv > 0:
		return ["УРОВЕНЬ %d" % (lv + 1), UIStyle.GOLD]
	var old := Run.mjolnir_trait_conflict(t)
	if old:
		return ["ЗАМЕНИТ: %s" % old.title, REPLACE]
	return ["НОВЫЙ", NEW]

## Карточка трейта — card_trait из UI-комплекта (SkinCard, золотые молнии — отличие от рун):
## иконка трейта в круге, название, группа, описание и статус (новый / уровень / заменит).
func _make_card(t: MjolnirTrait, index: int) -> Button:
	var lv := Run.mjolnir_trait_level(t.id)
	var b := SkinCard.make("card_trait", card_width, t.color, "legendary" if lv > 0 else "rare")
	b.key_label.text = "[%d]" % (index + 1)
	b.set_icon(UISkin.trait_icon(str(t.id)), "", t.color)
	if UISkin.trait_icon(str(t.id)) == null:
		b.set_icon(null, t.glyph, t.color)
	b.add_text(t.title, 19, t.color.lightened(0.45), 5)
	if t.group != "":
		b.add_text("группа: " + t.group, 13, Color(t.color, 0.85), 3)
	b.add_text(t.description_lvl2 if lv > 0 and t.description_lvl2 != "" else t.description, 13, UIStyle.TEXT, 3)
	var st := _status(t)
	var s := b.add_text(st[0], 15, st[1], 4)
	_status_labels.append(s)
	b.pressed.connect(func() -> void: choose(index))
	return b

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	for i in 3:
		if event.is_action_pressed("pick_%d" % (i + 1)):
			choose(i)
			get_viewport().set_input_as_handled()
	if event.is_action_pressed("reload") and _reroll_btn.visible:
		reroll_requested.emit()
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
