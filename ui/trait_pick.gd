extends CanvasLayer
class_name TraitPick
## Выбор 1 из 3 трейтов Мьёльнира (GDD 10, блок Б4): после мини-босса — стихия или приём,
## у наковальни Эйтри — стихия. Мышь или 1/2/3, игра на паузе.
## Визуально отдельно от рун: грозовой синий фон, карточки card_trait комплекта (золото и молнии).
## Карточка пишет вид (СТИХИЯ / ПРИЁМ) и способ доставки уровня; если трейт сложит связку «стихия + приём» —
## особая карточка: легендарная рамка и строка «+ СВЯЗКА: …» (сама связка объявляется ComboAnnounce).
## Несовместимый приём заменяет старый — требует второго нажатия (подтверждение).
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
@export var card_width: float = 340.0
const TITLE_DEFAULT := "ᛗ  МЬЁЛЬНИР ЖАЖДЕТ СИЛЫ  ᛗ"
## Римские цифры уровней (HUD, журнал, карточки)
const ROMAN := ["", "I", "II", "III", "IV", "V"]
## Подписи способов доставки стихии по уровням (tr при показе)
const DELIVERY := ["", "при попадании", "след на полу", "аура воткнутого молота", "удар с неба"]
const COMBO := Color(1.0, 0.78, 0.3)

## Заголовок открытого выбора ("" — обычный)
var title_text: String = ""
var _title: Label

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
	_title = UIStyle.label(tr(TITLE_DEFAULT), 40, UIStyle.ICE, 10)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)
	var hint := UIStyle.label(tr("Стихия — чем бьёт молот, приём — как ты им играешь. Мышь, 1 / 2 / 3 или геймпад"), 18, UIStyle.TEXT_DIM, 4)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 30)
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(_cards)
	_reroll_btn = UIStyle.button(tr("ПЕРЕБРОС  [R]"), 20)
	_reroll_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reroll_btn.visible = false
	_reroll_btn.pressed.connect(func() -> void: reroll_requested.emit())
	vb.add_child(_reroll_btn)

func open(choices: Array[MjolnirTrait], title: String = "") -> void:
	Perf.mark("trait_pick_open")
	title_text = title
	_title.text = title if title != "" else tr(TITLE_DEFAULT)
	_choices = choices
	_confirm_index = -1
	_status_labels.clear()
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	for i in choices.size():
		_cards.add_child(_make_card(choices[i], i))
	_reroll_btn.visible = Run.trait_rerolls > 0
	_reroll_btn.text = tr("ПЕРЕБРОС ОТ ЭЙТРИ (%d)  [R]") % Run.trait_rerolls
	visible = true
	if _cards.get_child_count() > 0:
		(_cards.get_child(0) as Button).grab_focus.call_deferred()
	_open_time = Time.get_ticks_msec() / 1000.0
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.modulate.a = 0.0
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.25)

func _status(t: MjolnirTrait) -> Array:
	var lv := Run.mjolnir_trait_level(t.id)
	if lv > 0:
		return [tr("УРОВЕНЬ %d") % (lv + 1), UIStyle.GOLD]
	var combos := Run.combos_completed_by(t)
	if not combos.is_empty():
		# Особая карточка: вместо «НОВЫЙ» — какая связка сложится (одна строка, карточка не переполняется)
		return [tr("+ СВЯЗКА: «%s»") % tr(combos[0].title), COMBO]
	var old := Run.mjolnir_trait_conflict(t)
	if old:
		return [tr("ЗАМЕНИТ: %s") % tr(old.title), REPLACE]
	return [tr("НОВЫЙ"), NEW]

## Карточка трейта — card_trait из UI-комплекта (SkinCard, золотые молнии — отличие от рун):
## иконка трейта в круге, название, группа, описание и статус (новый / уровень / заменит).
func _make_card(t: MjolnirTrait, index: int) -> Button:
	var lv := Run.mjolnir_trait_level(t.id)
	var combos := Run.combos_completed_by(t)
	var b := SkinCard.make("card_trait", card_width, t.color, "legendary" if lv > 0 or not combos.is_empty() else "rare")
	b.key_label.text = "[%d]" % (index + 1)
	b.set_icon(UISkin.trait_icon(str(t.id)), "", t.color)
	if UISkin.trait_icon(str(t.id)) == null:
		b.set_icon(null, t.glyph, t.color)
	b.add_text(tr(t.title), 19, t.color.lightened(0.45), 5)
	b.add_text(kind_line(t, lv + 1), 13, Color(t.color, 0.85), 3)
	b.add_text(GameSettings.throw_hint(tr(t.level_description(lv + 1))), 13, UIStyle.TEXT, 3)
	var st := _status(t)
	var s := b.add_text(st[0], 15, st[1], 4)
	_fit_card_text(b)
	_status_labels.append(s)
	b.pressed.connect(func() -> void: choose(index))
	return b

## Подгоняем текст под окно иллюстрации: длинное описание или подтверждение замены
## не должны выталкивать статус на рамку. Размер меняется только при необходимости.
func _fit_card_text(card: SkinCard) -> void:
	var labels := card.body.get_children()
	var floors := [14, 10, 9, 10]
	var width := SkinCard.TEXT_BOX.size.x * card_width / SkinCard.VISIBLE.size.x
	var height := SkinCard.TEXT_BOX.size.y * card_width / SkinCard.VISIBLE.size.x
	card.body.add_theme_constant_override("separation", 2)
	for step in 12:
		var total := float(maxi(0, labels.size() - 1) * 2)
		for i in labels.size():
			var label := labels[i] as Label
			var preferred := int(label.get_meta("preferred_font_size"))
			label.label_settings.font_size = maxi(mini(floors[i], preferred), preferred - step)
			var settings := label.label_settings
			var extent := settings.font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER,
				width, settings.font_size)
			total += extent.y + settings.outline_size * 2
		if total <= height - 8.0:
			break

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
		l.text = tr("Ещё раз — заменить «%s»") % tr(old.title)
		l.label_settings.font_color = REPLACE
		_fit_card_text(l.get_parent().get_parent() as SkinCard)
		return
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	picked.emit(t)

## Строка вида под названием: «СТИХИЯ · след на полу», «ПРИЁМ · удержание ПКМ», «СВЯЗКА»
static func kind_line(t: MjolnirTrait, lv: int) -> String:
	if t.is_element():
		return I18n.t("СТИХИЯ · %s") % I18n.t(DELIVERY[clampi(lv, 1, DELIVERY.size() - 1)])
	if t.is_combo():
		return I18n.t("СВЯЗКА")
	return I18n.t("ПРИЁМ · %s") % GameSettings.throw_hint(I18n.t(t.group)) if t.group != "" else I18n.t("ПРИЁМ")

static func roman(lv: int) -> String:
	return ROMAN[clampi(lv, 0, ROMAN.size() - 1)]
