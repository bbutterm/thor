extends CanvasLayer
class_name ShopScreen
## Экран ларька Брокка и Эйтри (GDD 13): слева братья и реплика Брокка, справа товары с ценами.
## Мышь или стрелки + Enter; E / Esc — уйти. Игра на паузе. Логика товаров — run/shop.gd.
## Рамка — panel_shop из UI-комплекта (UISkin), строки — кожаные планки; нет картинок — стиль UIStyle.

signal closed
signal bought(item: ShopItemDef, result: Dictionary)

const SILVER := Color(0.86, 0.9, 1.0)

var game: Game
var _root: Control
var _rows: VBoxContainer
var _silver: Label
var _speech: Label
var _brokk: Portrait
var _eitri: Portrait
var _sub: ChoicePick
var _sub_item: ShopItemDef
var _open_time: float = 0.0
var _buttons: Dictionary = {}

func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_sub = ChoicePick.new()
	_sub.name = "ShopChoice"
	add_child(_sub)
	_sub.picked.connect(_on_sub_picked)
	_root = Control.new()
	UIStyle.full_rect(_root)
	UISkin.apply(_root)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.01, 0.72)
	UIStyle.full_rect(dim)
	_root.add_child(dim)
	var center := CenterContainer.new()
	UIStyle.full_rect(center)
	_root.add_child(center)
	var frame := PanelContainer.new()
	# Рамка ларька из UI-комплекта (навес и фонари в углах — 9-slice, UISkin)
	if UISkin.texture("panel_shop"):
		frame.add_theme_stylebox_override("panel", UISkin.stylebox("panel_shop", 0.36, 4))
	else:
		frame.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.09, 0.065, 0.045, 0.97), Color(0.85, 0.55, 0.25, 0.85), 12, 3))
	center.add_child(frame)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 28)
	frame.add_child(hb)
	# Слева — братья и реплика
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(320, 0)
	left.add_theme_constant_override("separation", 10)
	hb.add_child(left)
	var faces := HBoxContainer.new()
	faces.add_theme_constant_override("separation", 8)
	left.add_child(faces)
	_brokk = Portrait.new()
	_brokk.custom_minimum_size = Vector2(170, 210)
	faces.add_child(_brokk)
	_eitri = Portrait.new()
	_eitri.custom_minimum_size = Vector2(140, 175)
	_eitri.size_flags_vertical = Control.SIZE_SHRINK_END
	faces.add_child(_eitri)
	var names := UIStyle.label(tr("БРОКК  И  ЭЙТРИ"), 18, Color(0.95, 0.65, 0.3), 5)
	left.add_child(names)
	var bubble := UIStyle.panel(Color(0.05, 0.04, 0.03, 0.9), Color(0.85, 0.55, 0.25, 0.6))
	left.add_child(bubble)
	_speech = UIStyle.label("", 18, UIStyle.TEXT, 4)
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech.custom_minimum_size = Vector2(290, 90)
	bubble.add_child(_speech)
	# Справа — вывеска, кошелёк, товары
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)
	var title := UIStyle.label(tr("РУНЫ • ШАУРМА • ЗАТОЧКА"), 34, Color(1.0, 0.72, 0.3), 9)
	right.add_child(title)
	_silver = UIStyle.label("", 24, SILVER, 6)
	right.add_child(_silver)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	right.add_child(_rows)
	var leave := UIStyle.button(tr("Уйти  [E / Esc]"), 20)
	leave.custom_minimum_size = Vector2(260, 46)
	leave.pressed.connect(close)
	right.add_child(leave)

func is_open() -> bool:
	return visible or _sub.visible

## Открыть ларёк. Реплика Брокка — по ситуации (мало HP, много серебра, нет денег).
func open() -> void:
	Perf.mark("shop_open")
	visible = true
	_open_time = Time.get_ticks_msec() / 1000.0
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_faces("happy")
	_say_pool(Shop.reaction_pool(game))
	refresh()
	_root.modulate.a = 0.0
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.18)

## Вернуться в ларёк после выбора руны / трейта (без новой приветственной реплики).
func reopen() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()

func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()

func _set_faces(emotion: String) -> void:
	_brokk.set_speaker("brokk", emotion, Dialogue.speakers.get("brokk", {}), 0.08)
	_eitri.set_speaker("eitri", "neutral", Dialogue.speakers.get("eitri", {}), 0.0)

func say(text: String, emotion: String = "neutral", speaker: String = "brokk") -> void:
	_speech.text = text
	if speaker == "eitri":
		_eitri.set_speaker("eitri", emotion, Dialogue.speakers.get("eitri", {}), 0.1)
	else:
		_brokk.set_speaker("brokk", emotion, Dialogue.speakers.get("brokk", {}), 0.08)

func _say_pool(pool: String) -> void:
	var lines := Dialogue.pool_lines(pool)
	if lines.is_empty():
		return
	var l: Dictionary = lines[0]
	Dialogue._on_line_shown(l)
	say(Dialogue.format_text(str(l.get("text", ""))), str(l.get("emotion", "neutral")), str(l.get("speaker", "brokk")))

func refresh() -> void:
	_silver.text = tr("СЕРЕБРО: %d") % Run.silver
	for c in _rows.get_children():
		c.queue_free()
	_buttons.clear()
	var first: Button = null
	for it in Shop.items():
		var b := _make_row(it)
		_rows.add_child(b)
		_buttons[it.id] = b
		if first == null and not b.disabled:
			first = b
	if first:
		first.grab_focus.call_deferred()

func _make_row(it: ShopItemDef) -> Button:
	var reason := Shop.unavailable_reason(game, it)
	var cost := Shop.price(game, it)
	var afford := it.pays_player or Run.silver >= cost
	var b := Button.new()
	b.custom_minimum_size = Vector2(640, 56)
	b.focus_mode = Control.FOCUS_ALL
	b.disabled = reason != ""
	var col := it.color
	if UISkin.texture("button_secondary_normal"):
		# Строка товара — кожаная планка комплекта (UISkin)
		UISkin.style_button(b, "secondary", 0.22)
	else:
		b.add_theme_stylebox_override("normal", UIStyle.panel_style(UIStyle.STONE_LIGHT, Color(col, 0.35), 8))
		b.add_theme_stylebox_override("disabled", UIStyle.panel_style(Color(0.1, 0.1, 0.1, 0.85), Color(0.4, 0.4, 0.4, 0.3), 8))
		for st in ["hover", "focus"]:
			b.add_theme_stylebox_override(st, UIStyle.panel_style(Color(0.22, 0.17, 0.12, 0.98), col, 8, 3))
		b.add_theme_stylebox_override("pressed", UIStyle.panel_style(Color(0.3, 0.22, 0.12, 1.0), col, 8, 3))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	UIStyle.full_rect(row)
	row.offset_left = 30
	row.offset_right = -32
	row.offset_top = 4
	row.offset_bottom = -4
	b.add_child(row)
	var glyph := UIStyle.label(it.glyph, 32, col if reason == "" else Color(0.45, 0.45, 0.45), 6)
	glyph.custom_minimum_size = Vector2(36, 0)
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(glyph)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 0)
	row.add_child(vb)
	vb.add_child(UIStyle.label(tr(it.title), 19, UIStyle.TEXT if reason == "" else UIStyle.TEXT_DIM, 4))
	var extra := Shop.detail(game, it)
	var desc := reason if reason != "" else (extra if extra != "" else tr(it.description))
	var d := UIStyle.label(desc, 13, UIStyle.TEXT_DIM if reason == "" else Color(1.0, 0.5, 0.4), 2)
	d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	d.custom_minimum_size = Vector2(430, 0)
	vb.add_child(d)
	var price_l := UIStyle.label(("+%d" % cost) if it.pays_player else str(cost), 24, SILVER if afford else Color(1.0, 0.4, 0.35), 5)
	price_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(price_l)
	for c in b.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(func() -> void: try_buy(it))
	return b

## Нажали на товар: нет денег — Брокк ворчит; нужен выбор — второй экран; иначе покупка.
func try_buy(it: ShopItemDef, arg: String = "") -> Dictionary:
	if Time.get_ticks_msec() / 1000.0 - _open_time < 0.2 and arg == "":
		return {"ok": false, "text": ""}
	if Shop.unavailable_reason(game, it) == "" and not it.pays_player and Run.silver < Shop.price(game, it):
		Audio.play("sounds/sfx/shop_broke.wav")
		Save.bump_event("shop_broke")
		_say_pool("dwarves.shop_broke")
		return {"ok": false, "text": tr("Нет серебра")}
	var subs := Shop.sub_choices(it)
	if arg == "" and not subs.is_empty() and Shop.can_buy(game, it):
		_sub_item = it
		subs.append({"id": "", "title": tr("Передумал"), "desc": tr("Брокк сделает вид, что не обиделся"), "glyph": "ᚾ", "color": Color(0.6, 0.6, 0.6)})
		# Второй шаг — поверх ларька (слой 10), ларёк не прячем: вложенный слой мог бы скрыться вместе с ним
		_sub.open(tr(it.title).to_upper(), tr("Выбери"), subs, "eitri" if it.by_eitri else "brokk", "smug")
		return {"ok": false, "text": tr("выбор")}
	var res := Shop.buy(game, it, arg)
	if res.ok:
		Save.bump_event("shop_buy")
		Audio.play("sounds/sfx/shop_buy.wav")
		if it.by_eitri:
			_say_pool("dwarves.eitri")
		else:
			say(res.text + ". " + _buy_quip(), "happy")
		bought.emit(it, res)
		if res.get("opened", false):
			visible = false
			return res
		game.hud.toast(res.text.to_upper())
	refresh()
	return res

func _buy_quip() -> String:
	var lines := Dialogue.pool_lines("dwarves.shop_buy")
	return Dialogue.format_text(str(lines[0].get("text", ""))) if not lines.is_empty() else ""

func _on_sub_picked(id: String) -> void:
	var it := _sub_item
	_sub_item = null
	reopen()
	if it == null or id == "":
		_say_pool("dwarves.shop_enter")
		return
	try_buy(it, id)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _sub.visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		if Time.get_ticks_msec() / 1000.0 - _open_time > 0.25:
			close()
		get_viewport().set_input_as_handled()
