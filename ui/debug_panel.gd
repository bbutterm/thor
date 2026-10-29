extends CanvasLayer
class_name DebugPanelUI
## Вид debug-панели баланса (П8, `DEBUG_PANEL.md`; логика и файл — автозагрузка DebugPanel, scripts/debug/debug_panel.gd).
## Слева полупрозрачная панель ~35 % ширины: пауза (F2) и скорость времени, строка состояния, вкладки с числом изменений,
## поиск, строки «название | ползунок | поле | умолчание | ↺» (изменённые — жёлтым, подсказка — поле в коде и строка
## TUNING.md), кнопки вкладки (спавн, зал, серебро) и сохранение. Строится кодом на скине UISkin; работает на паузе.

const CHANGED_COLOR := Color(1.0, 0.85, 0.3)
const ALL_TAB := "all"
## Классы источников для подсказки «поле в коде»
const SOURCE_CLASS := {"player": "Player", "mjolnir": "MjolnirHand", "camera": "CameraFX", "room": "Room", "style": "StyleTuning",
	"economy": "Economy", "enemy_mult": "DebugBalance.enemy", "econ_mult": "DebugBalance.econ", "waves_mult": "DebugBalance.waves"}
## Подписи источников в «Все параметры»
const SOURCE_TITLE := {"player": "Тор (Player)", "mjolnir": "Мьёльнир (MjolnirHand)", "room": "Зал (Room)", "style": "Шкала стиля (StyleTuning)", "camera": "Камера (CameraFX)"}

## Ширина панели — доля экрана
@export var width_fraction: float = 0.35

var _tab: String = "mjolnir"
var _rows: VBoxContainer
var _tabs: HFlowContainer
var _search: LineEdit
var _status: Label
var _pause_btn: Button
var _time_slider: HSlider
var _time_label: Label
var _actions: VBoxContainer
var _note: LineEdit
var _preset_name: LineEdit
var _presets: OptionButton
var _message: Label
var _row_widgets: Dictionary = {}
var _updating: bool = false
var _status_t: float = 0.0
var _tuning_text: String = ""

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	if FileAccess.file_exists("res://TUNING.md"):
		_tuning_text = FileAccess.get_file_as_string("res://TUNING.md")
	_build()
	DebugPanel.changed.connect(_on_value_changed)
	GameSettings.events.changed.connect(func(section: String, key: String) -> void:
		if section == "text" and key == "language":
			_rebuild.call_deferred())

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_row_widgets.clear()
	_build()
	refresh()

func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.full_rect(root)
	UISkin.apply(root)
	add_child(root)
	var bg := UIStyle.panel(Color(0.05, 0.045, 0.04, 0.88), Color(UIStyle.GOLD, 0.5))
	bg.anchor_right = width_fraction
	bg.anchor_bottom = 1.0
	root.add_child(bg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	bg.add_child(v)

	# Заголовок, пауза, скорость времени
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	head.add_child(UIStyle.label(tr("БАЛАНС · F1"), 18, UIStyle.GOLD, 4))
	_pause_btn = _button("", func() -> void:
		DebugPanel.toggle_pause()
		_refresh_pause())
	head.add_child(_pause_btn)
	_time_label = UIStyle.label("", 13, UIStyle.TEXT_DIM, 2)
	head.add_child(_time_label)
	_time_slider = HSlider.new()
	_time_slider.min_value = 0.1
	_time_slider.max_value = 2.0
	_time_slider.step = 0.05
	_time_slider.value = DebugBalance.time_mult
	_time_slider.custom_minimum_size = Vector2(90, 0)
	_time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_time_slider.tooltip_text = tr("Скорость времени. Двойной клик — сброс")
	_time_slider.value_changed.connect(func(x: float) -> void:
		DebugPanel.set_time_mult(x)
		_refresh_pause())
	_time_slider.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.double_click:
			_time_slider.value = 1.0)
	head.add_child(_time_slider)

	_status = UIStyle.label("", 13, UIStyle.TEXT, 2)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)

	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 4)
	_tabs.add_theme_constant_override("v_separation", 4)
	v.add_child(_tabs)
	_search = LineEdit.new()
	_search.placeholder_text = tr("Поиск параметра")
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _build_rows())
	v.add_child(_search)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 2)
	scroll.add_child(_rows)

	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 4)
	v.add_child(_actions)

	# Сохранение
	_note = LineEdit.new()
	_note.placeholder_text = tr("Комментарий к балансу")
	_note.text_changed.connect(func(t: String) -> void: DebugPanel.note = t)
	v.add_child(_note)
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 4)
	v.add_child(save_row)
	save_row.add_child(_button(tr("Сохранить"), func() -> void:
		_say(tr("Сохранено: %s") % DebugPanel.FILE if DebugPanel.save_file() else tr("Не удалось сохранить"))
		_fill_presets()))
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = tr("имя пресета")
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_preset_name)
	save_row.add_child(_button(tr("Сохранить как"), func() -> void:
		var path := DebugPanel.preset_path(_preset_name.text)
		_say(tr("Сохранено: %s") % path if DebugPanel.save_file(path) else tr("Не удалось сохранить"))
		_fill_presets()))
	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 4)
	v.add_child(load_row)
	_presets = OptionButton.new()
	_presets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_row.add_child(_presets)
	load_row.add_child(_button(tr("Загрузить"), func() -> void:
		if _presets.item_count == 0:
			return
		var n := DebugPanel.load_file(DebugPanel.DIR + _presets.get_item_text(_presets.selected))
		_note.text = DebugPanel.note
		_say(tr("Загружено изменений: %d") % n)))
	load_row.add_child(_button(tr("Сбросить всё"), func() -> void:
		DebugPanel.reset_all()
		_say(tr("Всё к значениям из кода"))))
	load_row.add_child(_button(tr("Открыть папку"), DebugPanel.open_folder))
	_message = UIStyle.label("", 12, UIStyle.TEXT_DIM, 2)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_message)

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	return b

func _say(text: String) -> void:
	_message.text = text

## Открытие панели: вкладки, строки, пресеты
func refresh() -> void:
	_note.text = DebugPanel.note
	_time_slider.set_value_no_signal(DebugBalance.time_mult)
	_refresh_pause()
	_fill_presets()
	_build_tabs()
	_build_rows()
	_update_status()

func _refresh_pause() -> void:
	_pause_btn.text = tr("▶ Дальше (F2)") if get_tree().paused else tr("⏸ Пауза (F2)")
	_time_label.text = tr("время ×%.2f") % DebugBalance.time_mult

func _fill_presets() -> void:
	_presets.clear()
	for f in DebugPanel.presets():
		_presets.add_item(f)

func _process(delta: float) -> void:
	if not visible:
		return
	_status_t -= delta / maxf(Engine.time_scale, 0.001) if Engine.time_scale > 0.0 else 0.05
	if _status_t <= 0.0:
		_status_t = 0.25
		_update_status()
		_refresh_pause()

func _update_status() -> void:
	_status.text = DebugPanel.status_text()

# --- Вкладки ---

func _tab_list() -> Array:
	var out: Array = []
	for tab in DebugPanel.TABS:
		out.append([tab.id, tr(tab.title)])
	out.append([ALL_TAB, tr("Все параметры")])
	return out

func _build_tabs() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	for t in _tab_list():
		var n := DebugPanel.changes_in(t[0])
		var b := _button(t[1] + (" • %d" % n if n > 0 else ""), _select_tab.bind(t[0]))
		b.toggle_mode = true
		b.button_pressed = t[0] == _tab
		if n > 0:
			b.add_theme_color_override("font_color", CHANGED_COLOR)
		_tabs.add_child(b)

func _select_tab(id: String) -> void:
	_tab = id
	_build_tabs()
	_build_rows()

## Строки текущей вкладки (с фильтром поиска)
func _build_rows() -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_row_widgets.clear()
	var q := _search.text.strip_edges().to_lower()
	if _tab == ALL_TAB:
		_build_all_rows(q)
	else:
		for tab in DebugPanel.TABS:
			if tab.id != _tab:
				continue
			if _tab == "movement" and Run.body:
				_rows.add_child(UIStyle.label(tr("Тело переопределяет часть чисел: %s") % tr(Run.body.display_name), 12, UIStyle.TEXT_DIM, 2))
			for p in tab.params:
				var label := tr(str(p[0]))
				if q != "" and not label.to_lower().contains(q) and not str(p[2]).to_lower().contains(q):
					continue
				var lo: Variant = p[3] if p.size() > 3 else null
				var hi: Variant = p[4] if p.size() > 4 else null
				_add_row(label, "%s.%s" % [p[1], p[2]], lo, hi)
			if _tab == "style":
				_add_style_points(q)
	_build_actions()

func _add_style_points(q: String) -> void:
	var st := DebugPanel.source(&"style")
	if st == null or not st.get("points") is Dictionary:
		return
	_rows.add_child(UIStyle.label(tr("Очки за приём"), 14, UIStyle.GOLD, 3))
	for k in (st.get("points") as Dictionary):
		if q != "" and not str(k).to_lower().contains(q):
			continue
		_add_row(str(k), "style.%s%s" % [DebugPanel.STYLE_POINTS_PREFIX, k], 0.0, 40.0)

## «Все параметры»: все числовые @export зарегистрированных источников, по @export_group
func _build_all_rows(q: String) -> void:
	for src in DebugPanel.AUTO_SOURCES:
		var obj := DebugPanel.source(StringName(src))
		if obj == null:
			continue
		var props: Array = DebugPanel.export_props(obj).filter(func(p: Dictionary) -> bool:
			return q == "" or str(p.name).to_lower().contains(q) or str(p.group).to_lower().contains(q))
		if props.is_empty():
			continue
		_rows.add_child(UIStyle.label(tr(SOURCE_TITLE.get(src, src)), 15, UIStyle.GOLD, 3))
		var group := "-"
		for p in props:
			if str(p.group) != group:
				group = str(p.group)
				if group != "":
					_rows.add_child(UIStyle.label(group, 12, UIStyle.ICE, 2))
			var key := "%s.%s" % [src, p.name]
			var lo: Variant = null
			var hi: Variant = null
			if int(p.type) != TYPE_BOOL:
				if bool(p.ranged):
					lo = p.min
					hi = p.max
				else:
					var d := float(DebugPanel.default_of(key) if DebugPanel.default_of(key) != null else 1.0)
					var span := maxf(absf(d) * 4.0, 1.0)
					lo = -span if d < 0.0 else 0.0
					hi = span
				if int(p.type) == TYPE_INT:
					lo = int(floor(float(lo)))
					hi = int(ceil(float(hi)))
			_add_row(str(p.name), key, lo, hi)

## Одна строка: название | ползунок | поле | умолчание | ↺
func _add_row(label: String, key: String, lo: Variant, hi: Variant) -> void:
	var cur: Variant = DebugPanel.value(key)
	var def: Variant = DebugPanel.default_of(key)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = _hint_for(key)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var name_l := UIStyle.label(label, 13, UIStyle.TEXT, 2)
	name_l.custom_minimum_size = Vector2(150, 0)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.mouse_filter = Control.MOUSE_FILTER_PASS
	name_l.tooltip_text = row.tooltip_text
	row.add_child(name_l)
	var w := {"label": name_l}
	if cur is bool or (lo == null and hi == null):
		var cb := CheckBox.new()
		cb.button_pressed = bool(cur)
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(on: bool) -> void:
			if not _updating:
				DebugPanel.set_value(key, on))
		row.add_child(cb)
		w["check"] = cb
	else:
		var is_int := cur is int
		var s := HSlider.new()
		s.min_value = float(lo)
		s.max_value = float(hi)
		s.step = 1.0 if is_int else 0.001
		s.allow_greater = true
		s.allow_lesser = true
		s.custom_minimum_size = Vector2(110, 0)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.focus_mode = Control.FOCUS_NONE
		s.value = float(cur) if cur != null else 0.0
		row.add_child(s)
		var sp := SpinBox.new()
		sp.min_value = float(lo)
		sp.max_value = float(hi)
		sp.step = 1.0 if is_int else 0.001
		sp.allow_greater = true
		sp.allow_lesser = true
		sp.custom_minimum_size = Vector2(84, 0)
		sp.value = s.value
		row.add_child(sp)
		s.value_changed.connect(func(x: float) -> void:
			if _updating:
				return
			_updating = true
			sp.value = x
			_updating = false
			DebugPanel.set_value(key, int(round(x)) if is_int else x))
		sp.value_changed.connect(func(x: float) -> void:
			if _updating:
				return
			_updating = true
			s.value = x
			_updating = false
			DebugPanel.set_value(key, int(round(x)) if is_int else x))
		w["slider"] = s
		w["spin"] = sp
	var def_l := UIStyle.label(_fmt(def), 12, Color(0.6, 0.58, 0.54), 2)
	def_l.custom_minimum_size = Vector2(44, 0)
	def_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(def_l)
	var reset := _button("↺", func() -> void: DebugPanel.reset_value(key))
	reset.tooltip_text = tr("К значению из кода")
	row.add_child(reset)
	_rows.add_child(row)
	_row_widgets[key] = w
	_mark(key)

static func _fmt(v: Variant) -> String:
	if v == null:
		return "—"
	if v is bool:
		return I18n.t("вкл") if v else I18n.t("выкл")
	if v is int:
		return str(v)
	return ("%.3f" % float(v)).rstrip("0").rstrip(".")

## Подсказка: поле в коде и строка TUNING.md, где оно упомянуто
func _hint_for(key: String) -> String:
	var dot := key.find(".")
	var src := key.left(dot)
	var field := key.substr(dot + 1)
	var base := field.split("[")[0].split("/")[0]
	var hint := "%s.%s" % [SOURCE_CLASS.get(src, src), field]
	if _tuning_text != "":
		var i := _tuning_text.find("`%s`" % base)
		if i >= 0:
			var a := _tuning_text.rfind("\n", i) + 1
			var b := _tuning_text.find("\n", i)
			var line := _tuning_text.substr(a, (b if b > 0 else _tuning_text.length()) - a).strip_edges()
			hint += "\nTUNING.md: " + (line.left(220) + ("…" if line.length() > 220 else ""))
	return hint

func _mark(key: String) -> void:
	var w: Dictionary = _row_widgets.get(key, {})
	if w.is_empty():
		return
	var on := DebugPanel.overrides.has(key)
	(w.label as Label).label_settings.font_color = CHANGED_COLOR if on else UIStyle.TEXT

## Значение поменялось (панель, сброс, загрузка): обновить строку и счётчики вкладок
func _on_value_changed(key: String) -> void:
	if key == "":
		_build_tabs()
		_build_rows()
		return
	var w: Dictionary = _row_widgets.get(key, {})
	if not w.is_empty():
		_updating = true
		var v: Variant = DebugPanel.value(key)
		if w.has("check"):
			(w.check as CheckBox).button_pressed = bool(v)
		elif v != null:
			(w.slider as HSlider).value = float(v)
			(w.spin as SpinBox).value = float(v)
		_updating = false
	_mark(key)
	_build_tabs()

# --- Кнопки вкладок ---

func _build_actions() -> void:
	for c in _actions.get_children():
		c.queue_free()
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	_actions.add_child(row)
	match _tab:
		"mjolnir":
			var cb := CheckBox.new()
			cb.text = tr("Подсветить окно хвата")
			cb.button_pressed = DebugPanel.highlight_catch
			cb.focus_mode = Control.FOCUS_NONE
			cb.toggled.connect(func(on: bool) -> void:
				DebugPanel.highlight_catch = on
				DebugPanel._apply_highlight())
			row.add_child(cb)
		"enemies":
			var kinds := OptionButton.new()
			for k in Room.ENEMY_SCENES:
				kinds.add_item(str(k))
			row.add_child(kinds)
			for n in [1, 5, 20]:
				row.add_child(_button(tr("+%d перед прицелом") % n, func() -> void:
					_say(tr("Появилось: %d") % spawn(kinds.get_item_text(kinds.selected), n))))
			row.add_child(_button(tr("Убить всех"), func() -> void: kill_all()))
			row.add_child(_button(tr("Пропустить волну"), func() -> void: skip_wave()))
		"waves":
			row.add_child(_button(tr("Перезапустить зал"), func() -> void: restart_room()))
			row.add_child(_button(tr("Пропустить волну"), func() -> void: skip_wave()))
		"economy":
			row.add_child(_button(tr("+100 серебра"), func() -> void: Run.add_silver(100)))
			row.add_child(_button(tr("+100 Славы"), func() -> void: Run.add_glory(100)))
	if row.get_child_count() == 0:
		row.queue_free()

## n врагов вида kind перед прицелом (на высоте Тора); сколько появилось
static func spawn(kind: String, n: int) -> int:
	var room := DebugPanel.source(&"room") as Room
	var p := DebugPanel.source(&"player") as Player
	if room == null or p == null:
		return 0
	var fwd := -p.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP)
	var made := 0
	for i in n:
		var pos := p.global_position + fwd * (6.0 + float(i / 5) * 1.5) + side * (float(i % 5) - 2.0) * 1.3
		if room.spawn_extra(kind, pos):
			made += 1
	return made

static func kill_all() -> void:
	var room := DebugPanel.source(&"room") as Room
	if room == null:
		return
	for e in room.alive_enemies().duplicate():
		if is_instance_valid(e) and not e.is_dead:
			e.take_hit(e.health + 99999.0, Vector3.ZERO, "hammer")

## Пропустить волну: очередь спавна текущей волны пуста, живые погибли — зал переходит к следующей
static func skip_wave() -> void:
	var room := DebugPanel.source(&"room") as Room
	if room == null:
		return
	(room.get("_spawn_queue") as Array).clear()
	kill_all()

static func restart_room() -> void:
	var game := DebugPanel.get_tree().current_scene as Game
	if game:
		game.get_tree().paused = false
		game._load_room()
