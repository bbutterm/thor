extends CanvasLayer
class_name TrainingPlan
## Экран «План тренировок Одина» (GDD 15.3): открытия за Славу между забегами.
## Слева Один и его реплика, справа — список открытий по разделам; «В бой» запускает новый забег.
## Строится кодом. Открывает Game после диалога у дивана и главное меню (кнопка «План тренировок»).

signal closed(start_run: bool)

## Высота карточки открытия
@export var card_height: float = 92.0
## Сколько секунд пульсирует счётчик Славы после покупки
@export var glory_pulse_time: float = 0.25

const SECTIONS := [
	["perk", "ТОР ПРИХОДИТ В ФОРМУ", "ᚢ", Color(1.0, 0.62, 0.3)],
	["weapon", "ОРУЖИЕ В ПУЛ", "ᛏ", Color(0.95, 0.42, 0.36)],
	["trait", "МЬЁЛЬНИР", "ᛗ", Color(0.5, 0.83, 1.0)],
	["body", "ТЕЛА СМЕРТНЫХ", "ᛒ", Color(0.55, 0.9, 0.5)],
	["rune", "РУНЫ В ПУЛ", "ᚱ", Color(0.78, 0.55, 1.0)],
]

var _root: Control
var _glory_label: Label
var _stats_label: Label
var _odin: Portrait
var _odin_text: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _fight_btn: Button
var _back_btn: Button
var _cards: Dictionary = {}
var _was_paused: bool = false

func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()

func _build() -> void:
	_root = Control.new()
	UIStyle.full_rect(_root)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.045, 0.04, 0.06, 1.0)
	UIStyle.full_rect(bg)
	_root.add_child(bg)
	var glyph := UIStyle.label("ᛟ", 460, Color(UIStyle.GOLD, 0.035), 0)
	glyph.position = Vector2(-60, 120)
	_root.add_child(glyph)

	var margin := MarginContainer.new()
	UIStyle.full_rect(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_root.add_child(margin)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 14)
	margin.add_child(main)

	# Заголовок и Слава
	var head := HBoxContainer.new()
	main.add_child(head)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	tv.add_child(UIStyle.label("ПЛАН ТРЕНИРОВОК ОДИНА", 40, UIStyle.GOLD, 10))
	_stats_label = UIStyle.label("", 17, UIStyle.TEXT_DIM, 4)
	tv.add_child(_stats_label)
	var gp := UIStyle.panel(Color(0.1, 0.08, 0.05, 0.95), Color(UIStyle.GOLD, 0.8))
	head.add_child(gp)
	_glory_label = UIStyle.label("", 34, UIStyle.GOLD, 8)
	_glory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gp.add_child(_glory_label)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(body)

	# Один слева
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	_odin = Portrait.new()
	_odin.custom_minimum_size = Vector2(300, 330)
	left.add_child(_odin)
	var sp := UIStyle.panel(Color(0.06, 0.055, 0.08, 0.95), Color(0.3, 0.42, 0.85, 0.8))
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sp)
	var sv := VBoxContainer.new()
	sp.add_child(sv)
	sv.add_child(UIStyle.label("ОДИН", 16, Color(0.55, 0.68, 1.0), 4))
	_odin_text = UIStyle.label("", 19, UIStyle.TEXT, 4)
	_odin_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_odin_text.custom_minimum_size = Vector2(270, 0)
	sv.add_child(_odin_text)

	# Список открытий справа
	var lp := UIStyle.panel(Color(0.07, 0.065, 0.08, 0.9), Color(UIStyle.GOLD, 0.35))
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(lp)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)

	# Кнопки
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 14)
	main.add_child(foot)
	var hint := UIStyle.label("Слава копится за забеги и не сгорает. Купленное действует со следующего забега.", 16, UIStyle.TEXT_DIM, 3)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	_back_btn = UIStyle.button("В меню", 22)
	_back_btn.custom_minimum_size = Vector2(200, 56)
	_back_btn.pressed.connect(func() -> void: close(false))
	foot.add_child(_back_btn)
	_fight_btn = UIStyle.button("В бой ▸", 28)
	_fight_btn.custom_minimum_size = Vector2(260, 60)
	_fight_btn.pressed.connect(func() -> void: close(true))
	foot.add_child(_fight_btn)

## Показывает экран. back_text — подпись второй кнопки («В меню» / «Назад»).
func open(back_text: String = "В меню") -> void:
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_back_btn.text = back_text
	_rebuild()
	_odin.set_speaker("odin", "neutral", Dialogue.speakers.get("odin", {}), 0.0)
	_say(Dialogue.pool_lines("odin.plan_open"))
	_root.modulate.a = 0.0
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.25)
	_fight_btn.grab_focus()

func close(start_run: bool) -> void:
	visible = false
	get_tree().paused = _was_paused
	Save.save_game()
	closed.emit(start_run)

func _say(lines: Array, fallback_emotion: String = "neutral") -> void:
	if lines.is_empty():
		return
	var l: Dictionary = lines[0]
	_odin_text.text = Dialogue.format_text(str(l.get("text", "")))
	_odin.set_speaker("odin", str(l.get("emotion", fallback_emotion)), Dialogue.speakers.get("odin", {}), 0.08)

func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_cards.clear()
	for sec in SECTIONS:
		var items: Array[UnlockDef] = []
		for u in Save.all_unlocks:
			if u.kind == sec[0]:
				items.append(u)
		if items.is_empty():
			continue
		# То, чего ещё нет в игре («скоро»), — в конец раздела
		items.sort_custom(func(a: UnlockDef, b: UnlockDef) -> bool:
			var sa := 0 if Save.target_exists(a) else 1
			var sb := 0 if Save.target_exists(b) else 1
			return sa < sb if sa != sb else a.order < b.order)
		var owned := 0
		for u in items:
			if Save.is_unlocked(u.id):
				owned += 1
		var h := UIStyle.label("%s %s   %d / %d" % [sec[2], sec[1], owned, items.size()], 20, sec[3], 5)
		_list.add_child(h)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.add_child(grid)
		for u in items:
			var card := _make_card(u, sec[2], sec[3])
			grid.add_child(card)
			_cards[u.id] = card
	_update_header()

func _update_header() -> void:
	_glory_label.text = "СЛАВА %d" % Save.glory_bank()
	_stats_label.text = "Забегов: %d · Смертей: %d · Побед: %d · Открыто: %d из %d" % [
		Save.runs(), Save.deaths(), Save.wins(), Save.data.unlocks.size(), Save.all_unlocks.size()]

func _make_card(u: UnlockDef, glyph: String, col: Color) -> PanelContainer:
	var reason := Save.buy_block_reason(u.id)
	var owned := reason == "owned"
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, card_height)
	var bg := Color(0.12, 0.16, 0.1, 0.95) if owned else UIStyle.STONE_LIGHT
	var border := Color(0.55, 0.9, 0.5, 0.8) if owned else Color(col, 0.35 if reason == "" else 0.15)
	var sb := UIStyle.panel_style(bg, border, 8, 2)
	sb.set_content_margin_all(10)
	sb.shadow_size = 0
	card.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	card.add_child(hb)
	# Иконка: картинка или руна в цвете раздела
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(56, 56)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(col.darkened(0.7), 0.95)
	isb.border_color = col if reason != "soon" else Color(col, 0.3)
	isb.set_border_width_all(2)
	isb.set_corner_radius_all(28)
	icon_box.add_theme_stylebox_override("panel", isb)
	hb.add_child(icon_box)
	if u.icon:
		var tr := TextureRect.new()
		tr.texture = u.icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_box.add_child(tr)
	else:
		var gl := UIStyle.label(u.glyph if u.glyph != "" else glyph, 28, col if reason != "soon" else Color(col, 0.35), 3)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_box.add_child(gl)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 2)
	hb.add_child(tv)
	var title := UIStyle.label(u.title, 19, UIStyle.TEXT if reason != "soon" else UIStyle.TEXT_DIM, 4)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(title)
	var desc := UIStyle.label(u.description, 14, UIStyle.TEXT_DIM, 2)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(200, 0)
	tv.add_child(desc)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(108, 48)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_override("font", UIStyle.font())
	btn.add_theme_font_size_override("font_size", 17)
	match reason:
		"owned":
			btn.text = "✓ Есть"
			btn.disabled = true
			btn.add_theme_color_override("font_disabled_color", Color(0.6, 0.95, 0.55))
		"soon":
			btn.text = "Скоро"
			btn.disabled = true
			btn.tooltip_text = "Этого ещё нет в игре — откроется, когда появится."
		"requires":
			var r := Save.get_unlock(u.requires)
			btn.text = "%d ᛟ" % u.price
			btn.disabled = true
			btn.tooltip_text = "Сначала: %s" % (r.title if r else u.requires)
			desc.text = "Сначала «%s». %s" % [r.title if r else u.requires, u.description]
		"no_glory":
			btn.text = "%d ᛟ" % u.price
			btn.add_theme_color_override("font_color", Color(0.85, 0.45, 0.4))
			btn.add_theme_color_override("font_hover_color", Color(1.0, 0.55, 0.5))
		_:
			btn.text = "%d ᛟ" % u.price
			btn.add_theme_color_override("font_color", UIStyle.GOLD)
	if not owned:
		btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.53, 0.5))
	btn.add_theme_stylebox_override("normal", UIStyle.panel_style(Color(0.16, 0.13, 0.08, 0.95), Color(UIStyle.GOLD, 0.5), 8, 2))
	btn.add_theme_stylebox_override("hover", UIStyle.panel_style(Color(0.26, 0.2, 0.1, 1.0), UIStyle.GOLD, 8, 2))
	btn.add_theme_stylebox_override("focus", UIStyle.panel_style(Color(0.26, 0.2, 0.1, 1.0), UIStyle.GOLD, 8, 2))
	btn.add_theme_stylebox_override("pressed", UIStyle.panel_style(Color(0.32, 0.24, 0.1, 1.0), UIStyle.GOLD, 8, 2))
	btn.add_theme_stylebox_override("disabled", UIStyle.panel_style(Color(0.1, 0.1, 0.11, 0.9), Color(1, 1, 1, 0.08), 8, 2))
	btn.pressed.connect(buy.bind(u.id))
	hb.add_child(btn)
	card.set_meta("button", btn)
	return card

## Покупка с экрана: списывает Славу, отмечает купленное, Один комментирует.
func buy(id: String) -> bool:
	var u := Save.get_unlock(id)
	var reason := Save.buy(id)
	if reason == "no_glory":
		_say(Dialogue.pool_lines("odin.plan_broke"), "smug")
		_shake(_glory_label)
		return false
	if reason != "":
		return false
	Audio.play("sounds/sfx/rune_pick.wav")
	if u and u.odin_comment != "":
		_say([{"speaker": "odin", "emotion": "happy", "text": u.odin_comment}])
	else:
		_say(Dialogue.pool_lines("odin.plan_buy"), "happy")
	var scroll_pos := _scroll.scroll_vertical
	_rebuild()
	_scroll.set_deferred("scroll_vertical", scroll_pos)
	_glory_label.pivot_offset = _glory_label.size * Vector2(1, 0.5)
	var tw := _glory_label.create_tween()
	tw.tween_property(_glory_label, "scale", Vector2(1.15, 1.15), glory_pulse_time * 0.4)
	tw.tween_property(_glory_label, "scale", Vector2.ONE, glory_pulse_time * 0.6)
	Dialogue.run_trigger("plan_buy")
	return true

func _shake(c: Control) -> void:
	var x := c.position.x
	var tw := c.create_tween()
	for i in 4:
		tw.tween_property(c, "position:x", x + (8.0 if i % 2 == 0 else -8.0), 0.04)
	tw.tween_property(c, "position:x", x, 0.04)

func card_button(id: String) -> Button:
	var card: Node = _cards.get(id)
	return card.get_meta("button") if card else null
