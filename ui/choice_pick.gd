extends CanvasLayer
class_name ChoicePick
## Экран выбора из 2–3 вариантов (Отдых, Сделка Локи, награда испытания): карточки как у рун,
## слева — портрет того, кто предлагает. Мышь, 1/2/3 или геймпад; на время выбора игра на паузе.
## Вариант: {id, title, desc, glyph, color, enabled (по умолчанию true)}.

signal picked(id: String)

var _choices: Array = []
var _cards: HBoxContainer
var _root: Control
var _title: Label
var _hint: Label
var _portrait: Portrait
var _speaker_name: Label
var _speaker_box: VBoxContainer
var _open_time: float = 0.0

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	UIStyle.full_rect(_root)
	UISkin.apply(_root)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.74)
	UIStyle.full_rect(dim)
	_root.add_child(dim)
	var center := CenterContainer.new()
	UIStyle.full_rect(center)
	_root.add_child(center)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 34)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(hb)
	_speaker_box = VBoxContainer.new()
	_speaker_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(_speaker_box)
	_portrait = Portrait.new()
	_portrait.custom_minimum_size = Vector2(220, 280)
	_speaker_box.add_child(_portrait)
	_speaker_name = UIStyle.label("", 22, UIStyle.GOLD, 6)
	_speaker_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker_box.add_child(_speaker_name)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(vb)
	_title = UIStyle.label("", 38, UIStyle.GOLD, 10)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title)
	_hint = UIStyle.label("", 18, UIStyle.TEXT_DIM, 4)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(760, 0)
	vb.add_child(_hint)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 22)
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(_cards)

## Открыть выбор. speaker — id говорящего из data/dialogues (портрет и имя), "" — без портрета.
func open(title: String, hint: String, choices: Array, speaker: String = "", emotion: String = "smug") -> void:
	Perf.mark("choice_pick")
	_choices = choices
	_title.text = title
	_hint.text = hint
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	for i in choices.size():
		_cards.add_child(_make_card(choices[i], i))
	_speaker_box.visible = speaker != ""
	if speaker != "":
		var def: Dictionary = Dialogue.speakers.get(speaker, {})
		_portrait.set_speaker(speaker, emotion, def, 0.08)
		_speaker_name.text = str(def.get("name", speaker)).to_upper()
	visible = true
	for card in _cards.get_children():
		if not (card as Button).disabled:
			(card as Button).grab_focus.call_deferred()
			break
	_open_time = Time.get_ticks_msec() / 1000.0
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.modulate.a = 0.0
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.2)

## Карточка варианта — card_rune из UI-комплекта (SkinCard): руна в круге, название и описание в окне.
func _make_card(ch: Dictionary, index: int) -> Button:
	var col: Color = ch.get("color", UIStyle.GOLD)
	var enabled: bool = ch.get("enabled", true)
	var b := SkinCard.make("card_rune", 260.0, col, "legendary")
	b.disabled = not enabled
	b.key_label.text = "[%d]" % (index + 1)
	b.set_icon(null, str(ch.get("glyph", "ᚱ")), col if enabled else Color(0.45, 0.45, 0.45))
	b.add_text(str(ch.get("title", "")), 19, col.lightened(0.45) if enabled else UIStyle.TEXT_DIM, 5)
	b.add_text(str(ch.get("desc", "")), 14, UIStyle.TEXT if enabled else UIStyle.TEXT_DIM, 3)
	b.pressed.connect(func() -> void: choose(index))
	return b

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	for i in 3:
		if event.is_action_pressed("pick_%d" % (i + 1)):
			choose(i)
			get_viewport().set_input_as_handled()

## Индекс варианта по id (-1 — нет).
func index_of(id: String) -> int:
	for i in _choices.size():
		if str(_choices[i].get("id", "")) == id:
			return i
	return -1

func choose(index: int, force: bool = false) -> void:
	if not visible or index < 0 or index >= _choices.size():
		return
	if not force and Time.get_ticks_msec() / 1000.0 - _open_time < 0.25:
		return
	if not bool(_choices[index].get("enabled", true)):
		return
	var id := str(_choices[index].get("id", ""))
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	picked.emit(id)
