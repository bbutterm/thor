extends CanvasLayer
class_name DialogueBox
## Окно диалога-новеллы: портреты слева (Тор) и справа (собеседник), плашка с именем, текст по букве,
## выбор ответа Тора, «Пропустить» и журнал прочитанного. Строится кодом. Создаёт и показывает Dialogue.
## Управление: клик / Пробел / Enter — допечатать или дальше; 1 / 2 — выбор; Tab или кнопка — журнал.

signal finished
signal choice_made(scene_id: String, choice_id: String)
signal line_shown(line: Dictionary)

## Скорость печати, букв в секунду
@export var chars_per_second: float = 48.0
## Доп. пауза после . ! ? … (с)
@export var punctuation_pause: float = 0.12
## Насколько «подпрыгивает» портрет при смене эмоции (доля высоты)
@export var portrait_bounce: float = 0.06
## Размер портрета в окне диалога (пропорции спрайтов 2:3) и сдвиг низа от низа экрана
@export var portrait_size: Vector2 = Vector2(440, 660)
@export var portrait_bottom: float = 40.0
## Затемнение неговорящего портрета (0 — не темнеет)
@export var inactive_dim: float = 0.45
## Защита от случайного двойного клика сразу после открытия (с)
@export var open_guard: float = 0.25

var _root: Control
var _backdrop: ColorRect
var _couch: Control
var _left: Portrait
var _right: Portrait
var _panel: PanelContainer
var _name_plate: PanelContainer
var _name_label: Label
var _text: Label
var _next_mark: Label
var _choices_box: VBoxContainer
var _log_panel: PanelContainer
var _log_text: RichTextLabel
var _skip_btn: Button
var _log_btn: Button

var _lines: Array = []
var _index: int = -1
var _scene_id: String = ""
var _typing: bool = false
var _shown: float = 0.0
var _pause_left: float = 0.0
var _waiting_choice: bool = false
## Сколько секунд окно открыто (по кадрам — работает и с --fixed-fps)
var _age: float = 0.0
var _left_sp: String = ""
var _right_sp: String = ""

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()

func _build() -> void:
	_root = Control.new()
	UIStyle.full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_backdrop = ColorRect.new()
	UIStyle.full_rect(_backdrop)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_click_input)
	_root.add_child(_backdrop)
	_couch = _make_couch_backdrop()
	_root.add_child(_couch)

	# Портреты по пояс (1024×1536, привязка — низ по центру): нижний край уходит под плашку текста
	_left = Portrait.new()
	_left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_left.offset_left = 30
	_left.offset_right = 30 + portrait_size.x
	_left.offset_top = portrait_bottom - portrait_size.y
	_left.offset_bottom = portrait_bottom
	_left.fallback_area = Rect2(0.1, 0.06, 0.8, 0.56)
	_root.add_child(_left)
	_right = Portrait.new()
	_right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_right.offset_left = -30 - portrait_size.x
	_right.offset_right = -30
	_right.offset_top = portrait_bottom - portrait_size.y
	_right.offset_bottom = portrait_bottom
	_right.fallback_area = Rect2(0.1, 0.06, 0.8, 0.56)
	_root.add_child(_right)

	_panel = UIStyle.panel(Color(0.06, 0.055, 0.07, 0.94), Color(UIStyle.GOLD, 0.55))
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 40
	_panel.offset_right = -40
	_panel.offset_top = -200
	_panel.offset_bottom = -24
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)
	var pm := MarginContainer.new()
	pm.add_theme_constant_override("margin_left", 18)
	pm.add_theme_constant_override("margin_right", 18)
	pm.add_theme_constant_override("margin_top", 16)
	pm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(pm)
	_text = UIStyle.label("", 27, UIStyle.TEXT, 5)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pm.add_child(_text)
	_next_mark = UIStyle.label("▼", 20, UIStyle.GOLD, 4)
	_next_mark.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_next_mark.offset_left = -96
	_next_mark.offset_top = -58
	_next_mark.offset_right = -60
	_next_mark.offset_bottom = -30
	_root.add_child(_next_mark)

	_name_plate = PanelContainer.new()
	_name_plate.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_name_plate.offset_top = -232
	_name_plate.offset_bottom = -186
	_name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_name_plate)
	_name_label = UIStyle.label("", 24, UIStyle.TEXT, 6)
	_name_plate.add_child(_name_label)

	_choices_box = VBoxContainer.new()
	_choices_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_choices_box.offset_left = -330
	_choices_box.offset_right = 330
	_choices_box.offset_top = -340
	_choices_box.offset_bottom = -216
	_choices_box.alignment = BoxContainer.ALIGNMENT_END
	_choices_box.add_theme_constant_override("separation", 10)
	_root.add_child(_choices_box)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top.offset_left = -420
	top.offset_right = -24
	top.offset_top = 20
	top.offset_bottom = 64
	top.alignment = BoxContainer.ALIGNMENT_END
	top.add_theme_constant_override("separation", 10)
	_root.add_child(top)
	_log_btn = _small_button("Журнал [Tab]")
	_log_btn.pressed.connect(toggle_log)
	top.add_child(_log_btn)
	_skip_btn = _small_button("Пропустить ▸▸")
	_skip_btn.pressed.connect(skip)
	top.add_child(_skip_btn)

	_log_panel = UIStyle.panel(Color(0.04, 0.04, 0.05, 0.97), Color(UIStyle.GOLD, 0.6))
	_log_panel.set_anchors_preset(Control.PRESET_CENTER)
	_log_panel.offset_left = -440
	_log_panel.offset_right = 440
	_log_panel.offset_top = -290
	_log_panel.offset_bottom = 250
	_log_panel.visible = false
	_root.add_child(_log_panel)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	_log_panel.add_child(lv)
	var lh := HBoxContainer.new()
	lv.add_child(lh)
	var lt := UIStyle.label("ЖУРНАЛ", 26, UIStyle.GOLD, 6)
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(lt)
	var lc := _small_button("Закрыть")
	lc.pressed.connect(toggle_log)
	lh.add_child(lc)
	_log_text = RichTextLabel.new()
	_log_text.bbcode_enabled = true
	_log_text.scroll_following = true
	_log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_text.add_theme_font_override("normal_font", UIStyle.font())
	_log_text.add_theme_font_size_override("normal_font_size", 19)
	_log_text.add_theme_color_override("default_color", UIStyle.TEXT)
	lv.add_child(_log_text)

## Фон «между забегами»: тёмная комната, диван-силуэт и подпись — Тор проснулся на диване.
func _make_couch_backdrop() -> Control:
	var c := Control.new()
	UIStyle.full_rect(c)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.set_color(0, Color(0.09, 0.07, 0.12))
	grad.set_color(1, Color(0.025, 0.02, 0.035))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 4
	gt.height = 128
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	UIStyle.full_rect(tr)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(tr)
	# Окно с луной и тусклый свет телевизора
	var win := ColorRect.new()
	win.color = Color(0.16, 0.2, 0.32, 0.55)
	win.set_anchors_preset(Control.PRESET_CENTER_TOP)
	win.offset_left = -120
	win.offset_right = 120
	win.offset_top = 60
	win.offset_bottom = 240
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(win)
	var frame_v := ColorRect.new()
	frame_v.color = Color(0.05, 0.04, 0.06)
	frame_v.position = Vector2(117, 0)
	frame_v.size = Vector2(6, 180)
	win.add_child(frame_v)
	var frame_h := ColorRect.new()
	frame_h.color = Color(0.05, 0.04, 0.06)
	frame_h.position = Vector2(0, 87)
	frame_h.size = Vector2(240, 6)
	win.add_child(frame_h)
	# Силуэт дивана: спинка, сиденье, подлокотники (то самое место силы)
	var couch_col := Color(0.14, 0.1, 0.16)
	for r in [Rect2(-300, -330, 600, 130), Rect2(-330, -230, 660, 70), Rect2(-360, -290, 80, 140), Rect2(280, -290, 80, 140)]:
		var part := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = couch_col
		sb.set_corner_radius_all(22)
		part.add_theme_stylebox_override("panel", sb)
		part.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		part.offset_left = r.position.x
		part.offset_top = r.position.y
		part.offset_right = r.position.x + r.size.x
		part.offset_bottom = r.position.y + r.size.y
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(part)
	# Голубой отсвет сериала
	var tv := ColorRect.new()
	tv.color = Color(0.35, 0.55, 0.9, 0.05)
	UIStyle.full_rect(tv)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(tv)
	var cap := UIStyle.label("Асгард · диван Тора", 18, Color(UIStyle.TEXT_DIM, 0.8), 4)
	cap.set_anchors_preset(Control.PRESET_TOP_LEFT)
	cap.position = Vector2(28, 24)
	c.add_child(cap)
	return c

func _small_button(t: String) -> Button:
	var b := UIStyle.button(t, 17)
	b.custom_minimum_size = Vector2(0, 40)
	b.focus_mode = Control.FOCUS_NONE
	return b

# --- Показ ---

## lines — уже раскрытые реплики (Dialogue.expand). backdrop: "run" или "couch".
func open(lines: Array, scene_id: String = "", backdrop: String = "run") -> void:
	_lines = lines.duplicate(true)
	_scene_id = scene_id
	_index = -1
	_waiting_choice = false
	_left_sp = ""
	_right_sp = ""
	_left.visible = false
	_right.visible = false
	_log_panel.visible = false
	_couch.visible = backdrop == "couch"
	_backdrop.color = Color(0.02, 0.02, 0.03, 1.0 if backdrop == "couch" else 0.55)
	visible = true
	_age = 0.0
	_root.modulate.a = 0.0
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.18)
	_next()

func is_open() -> bool:
	return visible

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _next() -> void:
	_index += 1
	_clear_choices()
	if _index >= _lines.size():
		_close()
		return
	_show_line(_lines[_index])

func _show_line(line: Dictionary) -> void:
	var sp := str(line.get("speaker", "odin"))
	var emo := str(line.get("emotion", "neutral"))
	var def: Dictionary = Dialogue.speakers.get(sp, {})
	var side := str(def.get("side", "left" if sp == "thor" else "right"))
	var col := Color.from_string(str(def.get("color", "#888888")), Color.GRAY)
	var p := _left if side == "left" else _right
	var other := _right if side == "left" else _left
	p.visible = true
	p.set_speaker(sp, emo, def, portrait_bounce)
	if side == "left":
		_left_sp = sp
	else:
		_right_sp = sp
	p.modulate = Color.WHITE
	other.modulate = Color(1, 1, 1, 1).darkened(inactive_dim)
	# Плашка с именем — над панелью со стороны говорящего, в цвете персонажа
	_name_label.text = str(def.get("name", sp.capitalize()))
	_name_plate.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(col.darkened(0.45), 0.97), col.lightened(0.2), 8, 2))
	var w := maxf(180.0, _name_label.get_minimum_size().x + 40.0)
	if side == "left":
		_name_plate.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_name_plate.offset_left = 70
		_name_plate.offset_right = 70 + w
	else:
		_name_plate.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_name_plate.offset_left = -70 - w
		_name_plate.offset_right = -70
	_name_plate.offset_top = -232
	_name_plate.offset_bottom = -186
	_text.text = str(line.get("text", ""))
	_text.visible_characters = 0
	_shown = 0.0
	_pause_left = 0.0
	_typing = true
	_next_mark.visible = false
	line_shown.emit(line)
	_log_append(def, col, _text.text)

func _process(delta: float) -> void:
	if not visible:
		return
	_age += delta
	_next_mark.modulate.a = 0.55 + 0.45 * sin(_now() * 6.0)
	if not _typing:
		return
	if _pause_left > 0.0:
		_pause_left -= delta
		return
	var before := int(_shown)
	_shown += delta * chars_per_second
	var total := _text.get_total_character_count()
	var n := mini(int(_shown), total)
	if n > before and n > 0 and n < total:
		var ch := _text.text.substr(n - 1, 1)
		if ch in [".", "!", "?", "…"]:
			_pause_left = punctuation_pause
	_text.visible_characters = n
	if n >= total:
		_finish_typing()

func _finish_typing() -> void:
	_typing = false
	_text.visible_characters = -1
	var line: Dictionary = _lines[_index] if _index >= 0 and _index < _lines.size() else {}
	var chs: Array = line.get("choices", [])
	if not chs.is_empty():
		_show_choices(chs)
	else:
		_next_mark.visible = true

func _show_choices(chs: Array) -> void:
	_waiting_choice = true
	_next_mark.visible = false
	for i in chs.size():
		var ch: Dictionary = chs[i]
		var b := UIStyle.button("%d · %s: «%s»" % [i + 1, ch.get("label", ""), ch.get("text", "")], 20)
		b.custom_minimum_size = Vector2(660, 52)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var accent := Color(0.95, 0.4, 0.3) if str(ch.get("id", "")) == "snap" else Color(0.5, 0.85, 0.55)
		b.add_theme_stylebox_override("normal", UIStyle.panel_style(UIStyle.STONE_LIGHT, Color(accent, 0.6), 8))
		b.add_theme_stylebox_override("hover", UIStyle.panel_style(Color(0.22, 0.19, 0.15, 0.98), accent, 8))
		b.add_theme_color_override("font_hover_color", accent.lightened(0.3))
		b.pressed.connect(choose.bind(i))
		_choices_box.add_child(b)

func _clear_choices() -> void:
	for c in _choices_box.get_children():
		_choices_box.remove_child(c)
		c.queue_free()
	_waiting_choice = false

## Выбор ответа Тора (0 или 1). Тор произносит выбранное, дальше — реакция из lines выбора.
func choose(i: int) -> void:
	if not _waiting_choice or _index < 0:
		return
	var line: Dictionary = _lines[_index]
	var chs: Array = line.get("choices", [])
	if i < 0 or i >= chs.size():
		return
	var ch: Dictionary = chs[i]
	choice_made.emit(_scene_id, str(ch.get("id", "")))
	var insert: Array = [{"id": str(line.get("id", "")) + "_" + str(ch.get("id", "")), "speaker": "thor",
		"emotion": str(ch.get("emotion", "angry" if ch.get("id", "") == "snap" else "embarrassed")), "text": str(ch.get("text", ""))}]
	insert.append_array(ch.get("lines", []))
	for k in insert.size():
		_lines.insert(_index + 1 + k, insert[k])
	_clear_choices()
	_next()

## Клик / Пробел: допечатать или дальше.
func advance() -> void:
	if not visible or _log_panel.visible:
		return
	if _age < open_guard:
		return
	if _typing:
		_typing = false
		_finish_typing()
		return
	if _waiting_choice:
		return
	_next()

## Пропустить сцену целиком. Если ждём выбор — он не записывается.
func skip() -> void:
	if not visible:
		return
	for i in range(maxi(_index + 1, 0), _lines.size()):
		var l: Dictionary = _lines[i]
		_log_append(Dialogue.speakers.get(str(l.get("speaker", "")), {}), Color.GRAY, str(l.get("text", "")))
	_close()

func _close() -> void:
	_typing = false
	_clear_choices()
	visible = false
	_log_panel.visible = false
	finished.emit()

func toggle_log() -> void:
	_log_panel.visible = not _log_panel.visible

func _log_append(def: Dictionary, col: Color, text: String) -> void:
	var name := str(def.get("name", "?"))
	_log_text.append_text("[color=#%s]%s:[/color] %s\n" % [col.lightened(0.2).to_html(false), name, text.replace("[", "[lb]")])

func _on_click_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.physical_keycode == KEY_TAB:
			toggle_log()
		elif _log_panel.visible and k.physical_keycode == KEY_ESCAPE:
			toggle_log()
		elif _waiting_choice and (event.is_action("pick_1") or k.physical_keycode == KEY_KP_1):
			choose(0)
		elif _waiting_choice and (event.is_action("pick_2") or k.physical_keycode == KEY_KP_2):
			choose(1)
		elif k.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] or event.is_action("jump"):
			advance()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		get_viewport().set_input_as_handled()
