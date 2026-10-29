extends CanvasLayer
class_name BuildScreen
## Экран сборки по Tab (П6, макет T3 `docs/mockups/tab_T3_chosen.png`) — пауза с тем, что в бою скрыто:
## слева портрет текущего тела во весь рост (sprites/bodies/<id>.webp), справа тёмная панель-список —
## «МЬЁЛЬНИР» (иконка trait_*, название, стихия/приём и уровень, описание) и «РУНЫ» (иконка runecat_*,
## название, уровень, описание); внизу путь по миру — иконки дверей door_* в кружках на линии (пройденные
## тусклые, текущий зал — золотое кольцо «Ты здесь», неизвестные — «?»); сверху «ПАУЗА», тело и мир,
## Слава и серебро. Описания — из .tres через tr(). Игра на паузе; Tab или Esc — закрыть.
## Создаёт Game._ready; открывает Game._unhandled_input (действие build_screen).

signal closed
signal opened

## Ширина колонки с портретом тела, px (при 1280×720)
@export var portrait_width: float = 470.0
## Размер иконки строки и кружка пути, px
@export var entry_icon_size: float = 54.0
@export var path_icon_size: float = 50.0

var _root: Control
var _content: Control
var _list: VBoxContainer
var _portrait: TextureRect
var _sub: Label
var _glory: Label
var _silver: Label
var _path: PathStrip
var _opened_mouse: Input.MouseMode = Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	UIStyle.full_rect(_root)
	UISkin.apply(_root)
	add_child(_root)
	_build()
	GameSettings.events.changed.connect(func(section: String, key: String) -> void:
		if section == "text" and key == "language":
			_rebuild.call_deferred())

func _rebuild() -> void:
	if _content and is_instance_valid(_content):
		_root.remove_child(_content)
		_content.queue_free()
	_build()
	if visible:
		_fill()

func _build() -> void:
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.full_rect(_content)
	_root.add_child(_content)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.025, 0.02, 0.86)
	UIStyle.full_rect(dim)
	_content.add_child(dim)

	# Слева — тело во весь рост, низом в край экрана
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_portrait.offset_left = 0
	_portrait.offset_right = portrait_width
	_portrait.offset_top = 64
	_content.add_child(_portrait)

	# Сверху: «ПАУЗА», тело и мир; справа Слава и серебро
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 36
	top.offset_right = -36
	top.offset_top = 14
	top.offset_bottom = 70
	top.add_theme_constant_override("separation", 16)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(top)
	var title := UIStyle.label(tr("ПАУЗА"), 38, UIStyle.GOLD, 8)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(title)
	_sub = UIStyle.label("", 17, UIStyle.TEXT_DIM, 4)
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_sub)
	_glory = UIStyle.label("", 24, UIStyle.TEXT, 6)
	_glory.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_glory)
	var silver_icon := UISkin.texture("hud_silver")
	if silver_icon:
		var si := HudIcon.make(silver_icon, 30)
		si.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(si)
	_silver = UIStyle.label("", 24, UIStyle.TEXT, 6)
	_silver.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_silver)

	# Справа — тёмная панель со списком трейтов и рун
	var panel := UIStyle.panel(Color(0.09, 0.07, 0.05, 0.94), Color(UIStyle.GOLD, 0.55))
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = portrait_width
	panel.offset_right = -36
	panel.offset_top = 90
	panel.offset_bottom = -150
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)

	# Внизу — путь по миру
	_path = PathStrip.new()
	_path.icon_size = path_icon_size
	_path.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_path.offset_left = portrait_width - 10
	_path.offset_right = -20
	_path.offset_top = -138
	_path.offset_bottom = -26
	_content.add_child(_path)

func is_open() -> bool:
	return visible

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	if visible:
		return
	_fill()
	visible = true
	_set_hud(false)
	get_tree().paused = true
	_opened_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	opened.emit()

func close() -> void:
	if not visible:
		return
	visible = false
	_set_hud(true)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()

## HUD боя под экраном сборки прячется (полоса босса, всплывашки не лезут сквозь затемнение)
func _set_hud(on: bool) -> void:
	var hud := get_parent().get("hud") as CanvasLayer if get_parent() else null
	if hud:
		hud.visible = on

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("build_screen") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

## Собрать содержимое из состояния забега (Run)
func _fill() -> void:
	var body_id := Run.body.id if Run.body else ""
	_portrait.texture = ScreenArt.body_portrait(body_id) if body_id != "" else null
	var body_name := tr(Run.body.display_name) if Run.body else ""
	var world := tr(Run.map.title) if Run.map else ""
	_sub.text = tr("Тело: %s · %s") % [body_name, world]
	_glory.text = tr("СЛАВА %d") % Run.glory
	_silver.text = "%d" % Run.silver
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_list.add_child(_section(tr("МЬЁЛЬНИР")))
	var traits: Array = []
	for t in Run.mjolnir_traits:
		if (t as MjolnirTrait).is_element():
			traits.append(t)
	for t in Run.mjolnir_traits:
		if not (t as MjolnirTrait).is_element():
			traits.append(t)
	if traits.is_empty():
		_list.add_child(_note(tr("Трейтов пока нет — их дают мини-босс и Наковальня Эйтри.")))
	for t in traits:
		var mt := t as MjolnirTrait
		var lv := Run.mjolnir_trait_level(mt.id)
		var kind := tr("СТИХИЯ · УР. %d") % lv if mt.is_element() else tr("ПРИЁМ · УР. %d") % lv
		_list.add_child(_entry(UISkin.trait_icon(str(mt.id)), mt.glyph, tr(mt.title), kind, _trait_text(mt, lv), mt.color, Color(0.55, 0.75, 1.0)))
	for c in Run.active_combos():
		_list.add_child(_entry(UISkin.trait_icon(str(c.id)), c.glyph, tr(c.title), tr("СВЯЗКА"), GameSettings.throw_hint(tr(c.description)), Color(1.0, 0.78, 0.3), UIStyle.GOLD))
	_list.add_child(_section(tr("РУНЫ")))
	var counts := {}
	var order: Array = []
	for r in Run.runes:
		if not counts.has(r.id):
			counts[r.id] = 0
			order.append(r)
		counts[r.id] += 1
	if order.is_empty():
		_list.add_child(_note(tr("Рун пока нет — Норны ждут зачистки зала.")))
	for r in order:
		var rr := r as RuneDef
		var lvl := mini(counts[rr.id], Run.RUNE_MAX_LEVEL)
		var desc := rr.level_descriptions[lvl - 1] if lvl - 1 < rr.level_descriptions.size() else rr.description
		if rr.oath and rr.oath_cost != "":
			desc = tr(desc) + "\n" + tr("Цена: %s") % tr(rr.oath_cost)
		_list.add_child(_entry(UISkin.rune_icon(rr), rr.glyph, ("☠ " if rr.cursed else "") + tr(rr.title),
			tr("УР. %d") % lvl, tr(desc), rr.color, UIStyle.GOLD))
	_path.nodes = path_nodes()
	_path.queue_redraw()

## Путь по миру: [{icon, label, state}] — state "done" | "here" | "next" | "unknown"
static func path_nodes() -> Array:
	var out: Array = []
	var n := Run.room_order.size()
	for i in n:
		var id := ""
		if i < Run.room_rewards.size():
			id = Run.room_rewards[i]
		if i == n - 1:
			id = "boss"
		elif i in Run.miniboss_rooms:
			id = "miniboss"
		if i == Run.room_index and id == "":
			id = Run.current_reward()
		var state := "done" if i < Run.room_index else ("here" if i == Run.room_index else "next")
		var d := Run.doors.reward_def(id) if id != "" else null
		if d == null:
			out.append({"icon": null, "label": "?", "state": "unknown" if state == "next" else state})
			continue
		var label := I18n.t("Ты здесь") if state == "here" else I18n.t(d.title)
		out.append({"icon": d.icon(), "label": label, "state": state, "glyph": d.glyph, "color": d.color})
	return out

func _section(text: String) -> Label:
	return UIStyle.label(text, 18, UIStyle.GOLD, 5)

func _note(text: String) -> Label:
	var l := UIStyle.label(text, 15, UIStyle.TEXT_DIM, 3)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _entry(tex: Texture2D, glyph: String, title: String, kind: String, desc: String, col: Color, kind_col: Color) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := HudIcon.make(tex, entry_icon_size)
	if tex == null:
		icon.badge = glyph
		icon.badge_color = col.lightened(0.2)
		icon.badge_size = 28
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hb.add_child(icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	head.add_child(UIStyle.label(title, 21, UIStyle.TEXT, 4))
	var k := UIStyle.label(kind, 14, kind_col, 3)
	k.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	k.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(k)
	var d := UIStyle.label(desc, 15, UIStyle.TEXT_DIM, 2)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(560, 0)
	v.add_child(d)
	return hb

## Что делает трейт на уровне lv: у стихии — все взятые способы доставки по строке, у приёма — текст уровня
func _trait_text(t: MjolnirTrait, lv: int) -> String:
	if not t.is_element():
		return GameSettings.throw_hint(tr(t.level_description(lv)))
	var lines: Array[String] = []
	for i in range(1, lv + 1):
		lines.append(GameSettings.throw_hint(tr(t.level_description(i))))
	return " ".join(lines)

## Путь по миру: кружки с иконками дверей на линии, подписи снизу
class PathStrip extends Control:
	var nodes: Array = []
	var icon_size: float = 50.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func centers() -> Array[Vector2]:
		var out: Array[Vector2] = []
		var n := nodes.size()
		if n == 0:
			return out
		var step := size.x / n
		for i in n:
			out.append(Vector2(step * (i + 0.5), icon_size * 0.5 + 10.0))
		return out

	func _draw() -> void:
		var c := centers()
		if c.is_empty():
			return
		var here := -1
		for i in nodes.size():
			if str(nodes[i].state) == "here":
				here = i
		# Линия: пройденная часть — золотая, впереди — тусклая
		draw_line(c[0], c[c.size() - 1], Color(0.45, 0.38, 0.28, 0.8), 4.0)
		if here > 0:
			draw_line(c[0], c[here], UIStyle.GOLD, 4.0)
		var font := UIStyle.font()
		var r := icon_size * 0.5
		for i in nodes.size():
			var nd: Dictionary = nodes[i]
			var st := str(nd.state)
			var p := c[i]
			var big := r * (1.25 if st == "here" else 1.0)
			draw_circle(p, big + 3.0, Color(0.05, 0.04, 0.03, 0.95))
			if st == "unknown":
				# «?» — пунктирный кружок
				for k in 16:
					var a := TAU * k / 16.0
					draw_arc(p, big, a, a + TAU / 32.0, 4, Color(0.75, 0.68, 0.55, 0.8), 2.0)
				draw_string(font, p + Vector2(-big, 10), "?", HORIZONTAL_ALIGNMENT_CENTER, big * 2.0, 30, Color(0.85, 0.8, 0.7))
			else:
				var tex: Texture2D = nd.get("icon")
				var tint := Color(1, 1, 1, 0.45) if st == "done" else Color.WHITE
				if tex:
					var s := Vector2.ONE * big * 2.0
					draw_texture_rect(tex, Rect2(p - s * 0.5, s), false, tint)
				else:
					var col: Color = nd.get("color", UIStyle.GOLD)
					draw_circle(p, big - 3.0, Color(col, 0.35 if st == "done" else 0.8))
					draw_string(font, p + Vector2(-big, 9), str(nd.get("glyph", "ᚱ")), HORIZONTAL_ALIGNMENT_CENTER, big * 2.0, 24, Color(1, 1, 1, tint.a))
				if st == "here":
					draw_arc(p, big + 4.0, 0.0, TAU, 48, UIStyle.GOLD, 5.0)
			var label := str(nd.label)
			var lc := UIStyle.GOLD if st == "here" else (Color(0.7, 0.66, 0.6) if st == "done" else UIStyle.TEXT)
			var w := size.x / nodes.size()
			var lp := Vector2(p.x - w * 0.5, p.y + r * 1.25 + 26.0)
			draw_string_outline(font, lp, label, HORIZONTAL_ALIGNMENT_CENTER, w, 14, 4, Color(0, 0, 0, 0.9))
			draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_CENTER, w, 14, lc)
