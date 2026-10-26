extends CanvasLayer
class_name BodySelect
## Экран выбора тела перед забегом (GDD 6, 18): слева — 9 тел (закрытые под замком с ценой),
## справа — выбранное тело: HP и скорость, стартовое оружие, стиль движения, пассивка, изъян и слово Одина.
## Открывают главное меню («Начать забег») и Game после «Плана тренировок». Строится кодом.
## Закрытое тело можно открыть прямо здесь, если хватает Славы (то же открытие, что в «Плане тренировок»).

## body_id — выбранное тело; "" — «Назад»
signal closed(body_id: String)

## Колонок в сетке тел
@export var columns: int = 3
@export var card_size: Vector2 = Vector2(230, 100)
## Иконка замка (UI_PROMPTS 4.6); нет файла — надпись
const LOCK_ICON := "res://sprites/ui/icons/icon_lock.png"
const STYLE_GLYPH := {"base": "ᚱ", "nimble": "ᚹ", "nimble_plus": "ᚹ", "ram": "ᚦ", "jumper": "ᛇ", "heavy": "ᛟ", "slider": "ᛚ"}

var bodies: Array[BodyDef] = []
var selected: BodyDef
var _root: Control
var _grid: GridContainer
var _cards: Dictionary = {}
var _glory_label: Label
var _name_label: Label
var _stats_label: Label
var _start_label: Label
var _move_title: Label
var _move_desc: Label
var _passive_title: Label
var _passive_desc: Label
var _flaw_title: Label
var _flaw_desc: Label
var _odin_text: Label
var _odin: Portrait
var _fight_btn: Button
var _back_btn: Button
var _was_paused: bool = false
var _lock_tex: Texture2D

func _ready() -> void:
	layer = 36
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if ResourceLoader.exists(LOCK_ICON):
		_lock_tex = load(LOCK_ICON) as Texture2D
	bodies.assign(Run.all_bodies)
	# Порядок: открытые с начала, потом по цене
	bodies.sort_custom(func(a: BodyDef, b: BodyDef) -> bool:
		return a.price < b.price if a.price != b.price else a.display_name < b.display_name)
	_build()

## Цена открытия тела: из открытия «Плана тренировок» (run/unlocks/body_*.tres), иначе BodyDef.price
static func unlock_for(body_id: String) -> UnlockDef:
	for u in Save.all_unlocks:
		if u.kind == "body" and body_id in u.targets():
			return u
	return null

static func is_locked(body_id: String) -> bool:
	return not Save.is_in_pool("body", body_id)

static func price_of(b: BodyDef) -> int:
	var u := unlock_for(b.id)
	return u.price if u else b.price

func _build() -> void:
	_root = Control.new()
	UIStyle.full_rect(_root)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.045, 0.04, 0.06, 1.0)
	UIStyle.full_rect(bg)
	_root.add_child(bg)
	var glyph := UIStyle.label("ᛒ", 460, Color(UIStyle.GOLD, 0.035), 0)
	glyph.position = Vector2(-40, 140)
	_root.add_child(glyph)

	var margin := MarginContainer.new()
	UIStyle.full_rect(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_root.add_child(margin)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 14)
	margin.add_child(main)

	var head := HBoxContainer.new()
	main.add_child(head)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	head.add_child(tv)
	tv.add_child(UIStyle.label("В КОГО ВСЕЛИТЬСЯ?", 40, UIStyle.GOLD, 10))
	tv.add_child(UIStyle.label("Один подобрал смертных. Выбирай тело на забег.", 17, UIStyle.TEXT_DIM, 4))
	var gp := UIStyle.panel(Color(0.1, 0.08, 0.05, 0.95), Color(UIStyle.GOLD, 0.8))
	head.add_child(gp)
	_glory_label = UIStyle.label("", 30, UIStyle.GOLD, 8)
	gp.add_child(_glory_label)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(body)

	# Слева: сетка тел, под ней — слово Одина о выбранном теле
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	body.add_child(left)
	var lp := UIStyle.panel(Color(0.07, 0.065, 0.08, 0.9), Color(UIStyle.GOLD, 0.35))
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(lp)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = columns
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)

	# Карточка выбранного тела
	var rp := UIStyle.panel(Color(0.06, 0.055, 0.08, 0.95), Color(UIStyle.GOLD, 0.6))
	rp.custom_minimum_size = Vector2(470, 0)
	body.add_child(rp)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	rp.add_child(rv)
	_name_label = UIStyle.label("", 30, UIStyle.GOLD, 8)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.custom_minimum_size = Vector2(420, 0)
	rv.add_child(_name_label)
	_stats_label = UIStyle.label("", 17, UIStyle.TEXT, 4)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.custom_minimum_size = Vector2(420, 0)
	rv.add_child(_stats_label)
	_start_label = UIStyle.label("", 18, UIStyle.TEXT, 4)
	_start_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_start_label)
	var pair := _section(rv, "ДВИЖЕНИЕ", UIStyle.ICE)
	_move_title = pair[0]
	_move_desc = pair[1]
	pair = _section(rv, "ПАССИВКА", Color(0.55, 0.9, 0.5))
	_passive_title = pair[0]
	_passive_desc = pair[1]
	pair = _section(rv, "ИЗЪЯН", Color(0.95, 0.5, 0.4))
	_flaw_title = pair[0]
	_flaw_desc = pair[1]
	var op := UIStyle.panel(Color(0.06, 0.055, 0.08, 0.95), Color(0.3, 0.42, 0.85, 0.8))
	left.add_child(op)
	var oh := HBoxContainer.new()
	oh.add_theme_constant_override("separation", 12)
	op.add_child(oh)
	_odin = Portrait.new()
	_odin.custom_minimum_size = Vector2(96, 104)
	oh.add_child(_odin)
	var ov := VBoxContainer.new()
	ov.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oh.add_child(ov)
	ov.add_child(UIStyle.label("ОДИН", 15, Color(0.55, 0.68, 1.0), 4))
	_odin_text = UIStyle.label("", 18, UIStyle.TEXT, 4)
	_odin_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_odin_text.custom_minimum_size = Vector2(300, 0)
	ov.add_child(_odin_text)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 14)
	main.add_child(foot)
	var hint := UIStyle.label("Закрытые тела открываются за Славу — здесь или в «Плане тренировок».", 16, UIStyle.TEXT_DIM, 3)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(200, 0)
	foot.add_child(hint)
	_back_btn = UIStyle.button("Назад", 22)
	_back_btn.custom_minimum_size = Vector2(200, 56)
	_back_btn.pressed.connect(func() -> void: close(""))
	foot.add_child(_back_btn)
	_fight_btn = UIStyle.button("В бой ▸", 28)
	_fight_btn.custom_minimum_size = Vector2(300, 60)
	_fight_btn.pressed.connect(_on_fight)
	foot.add_child(_fight_btn)

func _section(parent: Control, caption: String, col: Color) -> Array:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(col, 0.25))
	parent.add_child(sep)
	var t := UIStyle.label("", 20, col, 4)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(UIStyle.label(caption, 13, Color(col, 0.7), 3))
	parent.add_child(t)
	var d := UIStyle.label("", 16, UIStyle.TEXT_DIM, 3)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(420, 0)
	parent.add_child(d)
	return [t, d]

## Показывает экран. preselect — id тела, выбранного по умолчанию (прошлое тело).
func open(back_text: String = "Назад", preselect: String = "") -> void:
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_back_btn.text = back_text
	_odin.set_speaker("odin", "smug", Dialogue.speakers.get("odin", {}), 0.0)
	_rebuild()
	var pick: BodyDef = null
	for b in bodies:
		if b.id == preselect and not is_locked(b.id):
			pick = b
	if pick == null:
		for b in bodies:
			if not is_locked(b.id):
				pick = b
				break
	if pick:
		select(pick.id)
		(_cards[pick.id] as Button).grab_focus()
	_root.modulate.a = 0.0
	_root.create_tween().tween_property(_root, "modulate:a", 1.0, 0.2)
	Perf.mark("body_select_open")

func close(body_id: String) -> void:
	visible = false
	get_tree().paused = _was_paused
	closed.emit(body_id)

func _rebuild() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_cards.clear()
	for b in bodies:
		var card := _make_card(b)
		_grid.add_child(card)
		_cards[b.id] = card
	_glory_label.text = "СЛАВА %d" % Save.glory_bank()
	if selected:
		_update_detail()

func _make_card(b: BodyDef) -> Button:
	var locked := is_locked(b.id)
	var mp := b.movement_profile()
	var btn := Button.new()
	btn.custom_minimum_size = card_size
	btn.focus_mode = Control.FOCUS_ALL
	btn.toggle_mode = false
	var border := Color(UIStyle.GOLD, 0.25) if not locked else Color(1, 1, 1, 0.08)
	var bgc := UIStyle.STONE_LIGHT if not locked else Color(0.09, 0.09, 0.1, 0.95)
	btn.add_theme_stylebox_override("normal", UIStyle.panel_style(bgc, border, 8, 2))
	btn.add_theme_stylebox_override("hover", UIStyle.panel_style(bgc.lightened(0.08), Color(UIStyle.GOLD, 0.7), 8, 2))
	btn.add_theme_stylebox_override("focus", UIStyle.panel_style(bgc.lightened(0.08), UIStyle.GOLD, 8, 3))
	btn.add_theme_stylebox_override("pressed", UIStyle.panel_style(bgc.lightened(0.12), UIStyle.GOLD, 8, 3))
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 10)
	UIStyle.full_rect(hb)
	hb.offset_left = 12
	hb.offset_right = -10
	hb.offset_top = 8
	hb.offset_bottom = -8
	btn.add_child(hb)
	# Значок: руна стиля движения или замок
	var icon_box := PanelContainer.new()
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.custom_minimum_size = Vector2(56, 56)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0.05, 0.05, 0.06, 0.95)
	isb.border_color = UIStyle.ICE if not locked else Color(0.6, 0.6, 0.6, 0.4)
	isb.set_border_width_all(2)
	isb.set_corner_radius_all(28)
	icon_box.add_theme_stylebox_override("panel", isb)
	hb.add_child(icon_box)
	if locked and _lock_tex:
		var tr := TextureRect.new()
		tr.texture = _lock_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_box.add_child(tr)
	else:
		var gl := UIStyle.label("ᛉ" if locked else STYLE_GLYPH.get(b.movement_style, "ᚱ"), 28,
			Color(0.6, 0.6, 0.6, 0.6) if locked else UIStyle.ICE, 3)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_box.add_child(gl)
	var tv := VBoxContainer.new()
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	hb.add_child(tv)
	var nl := UIStyle.label(b.display_name, 17, UIStyle.TEXT if not locked else UIStyle.TEXT_DIM, 4)
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(nl)
	var sl := UIStyle.label("HP %d · %s м/с" % [int(b.max_health), _num(b.move_speed)], 14, UIStyle.TEXT_DIM, 2)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(sl)
	var ml := UIStyle.label(("ЗАКРЫТО · %d ᛟ" % price_of(b)) if locked else (mp.title if mp else ""), 15,
		Color(0.85, 0.6, 0.4) if locked else UIStyle.ICE, 2)
	ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(ml)
	btn.pressed.connect(_on_card_pressed.bind(b.id))
	btn.focus_entered.connect(select.bind(b.id))
	btn.set_meta("locked", locked)
	return btn

static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else "%.1f" % v

func _on_card_pressed(id: String) -> void:
	if selected and selected.id == id and not is_locked(id):
		_on_fight()
		return
	select(id)

## Выбрать тело (показать справа). Закрытое тоже можно выбрать — чтобы прочитать и открыть.
func select(id: String) -> void:
	for b in bodies:
		if b.id == id:
			selected = b
	if selected:
		_update_detail()

## Выбранная карточка — с золотой рамкой (фокус клавиатуры может быть на другой)
func _mark_selected() -> void:
	for id in _cards:
		var btn := _cards[id] as Button
		var locked: bool = btn.get_meta("locked")
		var bgc := UIStyle.STONE_LIGHT if not locked else Color(0.09, 0.09, 0.1, 0.95)
		var border := Color(UIStyle.GOLD, 0.25) if not locked else Color(1, 1, 1, 0.08)
		if selected and id == selected.id:
			border = UIStyle.GOLD if not locked else Color(0.85, 0.6, 0.4)
		btn.add_theme_stylebox_override("normal", UIStyle.panel_style(bgc, border, 8, 3 if selected and id == selected.id else 2))

func _update_detail() -> void:
	var b := selected
	var locked := is_locked(b.id)
	_mark_selected()
	_name_label.text = b.display_name.to_upper()
	_stats_label.text = ("ЗАКРЫТО · %d ᛟ\n" % price_of(b) if locked else "") + \
		"HP %d  ·  скорость %s  ·  рывков %d" % [int(b.max_health), _num(b.move_speed), b.dash_charges]
	_stats_label.label_settings.font_color = Color(0.95, 0.7, 0.5) if locked else UIStyle.TEXT
	var start := b.start_melee.display_name if b.start_melee else "—"
	if b.start_ranged:
		start += " + " + b.start_ranged.display_name
	_start_label.text = "Старт: " + start
	var mp := b.movement_profile()
	_move_title.text = mp.title if mp else b.movement_style
	_move_desc.text = mp.description if mp else ""
	_fill_trait(b.passive, _passive_title, _passive_desc)
	_fill_trait(b.flaw, _flaw_title, _flaw_desc)
	_odin_text.text = b.odin_comment if b.odin_comment != "" else b.description
	if locked:
		var price := price_of(b)
		var u := unlock_for(b.id)
		var can := u != null and Save.buy_block_reason(u.id) == ""
		_fight_btn.text = ("Открыть · %d ᛟ" % price) if can else ("Нужно %d ᛟ" % price)
		_fight_btn.disabled = not can
	else:
		_fight_btn.text = "В бой ▸"
		_fight_btn.disabled = false

func _fill_trait(pd: PassiveDef, title: Label, desc: Label) -> void:
	if pd == null:
		title.text = "—"
		desc.text = ""
		return
	title.text = pd.title + ("" if pd.implemented else "  (скоро)")
	desc.text = pd.description + (("\n· " + pd.todo) if pd.todo != "" else "")

func _on_fight() -> void:
	if selected == null:
		return
	if is_locked(selected.id):
		var u := unlock_for(selected.id)
		if u and Save.buy(u.id) == "":
			Audio.play("sounds/sfx/rune_pick.wav")
			var keep := selected.id
			_rebuild()
			select(keep)
			(_cards[keep] as Button).grab_focus()
			Dialogue.run_trigger("plan_buy")
		return
	choose(selected.id)

## Начать забег этим телом (закрытое — нельзя). true — экран закрылся.
func choose(id: String) -> bool:
	if is_locked(id):
		return false
	Audio.play("sounds/sfx/rune_pick.wav")
	close(id)
	return true

func card(id: String) -> Button:
	return _cards.get(id) as Button
