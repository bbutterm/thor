extends CanvasLayer
class_name PauseMenu
## Пауза на Esc (GDD 18): продолжить, настройки, новый забег, в меню, «Сообщить о лаге»;
## справа — журнал рун и трейтов забега (полные названия и описания уровней). Скин комплекта (UISkin).

signal restart_requested
signal menu_requested

var _first: Button
var _root: Control
var _journal: VBoxContainer
var _settings: SettingsPanel
## Содержимое паузы (без панели настроек) — пересобирается при смене языка
var _content: Control

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	UIStyle.full_rect(_root)
	UISkin.apply(_root)
	add_child(_root)
	_build()
	GameSettings.events.changed.connect(_on_setting_changed)

## Смена языка из настроек поверх паузы: меню паузы собирается заново под панелью настроек
func _on_setting_changed(section: String, key: String) -> void:
	if section == "text" and key == "language":
		_rebuild.call_deferred()

func _rebuild() -> void:
	if _content and is_instance_valid(_content):
		_root.remove_child(_content)
		_content.queue_free()
	_build()
	_root.move_child(_content, 0)
	if visible:
		_fill_journal()

func _build() -> void:
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.full_rect(_content)
	_root.add_child(_content)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	UIStyle.full_rect(dim)
	_content.add_child(dim)
	var center := CenterContainer.new()
	UIStyle.full_rect(center)
	_content.add_child(center)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	center.add_child(hb)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"WoodPanel"
	hb.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var t := UIStyle.label(tr("ПАУЗА"), 40, UIStyle.GOLD, 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var sub := UIStyle.label(tr("Один ждёт. Нетерпеливо."), 18, UIStyle.TEXT_DIM, 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	_first = UIStyle.button(tr("Продолжить"))
	_first.pressed.connect(toggle)
	vb.add_child(_first)
	var s := UIStyle.button(tr("Настройки"), 22, "secondary")
	s.pressed.connect(open_settings)
	vb.add_child(s)
	var r := UIStyle.button(tr("Новое тело (заново)"), 22, "secondary")
	r.pressed.connect(func() -> void: restart_requested.emit())
	vb.add_child(r)
	var m := UIStyle.button(tr("В главное меню"), 22, "danger")
	m.pressed.connect(func() -> void: menu_requested.emit())
	vb.add_child(m)
	# «Сообщить о лаге» (GDD 23): zip с логом фризов и сохранением на рабочий стол
	var lag := UIStyle.button(tr("Сообщить о лаге"), 17, "secondary")
	lag.custom_minimum_size = Vector2(280, 46)
	lag.pressed.connect(func() -> void:
		var path := Perf.report_lag()
		lag.text = tr("Сохранено на рабочий стол") if path != "" else tr("Не удалось сохранить"))
	vb.add_child(lag)
	# Журнал рун и трейтов (GDD 18: «пауза — журнал рун и трейтов»)
	var jp := UIStyle.panel(UIStyle.STONE, Color(UIStyle.GOLD, 0.6), "wood")
	jp.custom_minimum_size = Vector2(440, 470)
	hb.add_child(jp)
	var jv := VBoxContainer.new()
	jv.add_theme_constant_override("separation", 6)
	jp.add_child(jv)
	jv.add_child(UIStyle.label(tr("ЖУРНАЛ ЗАБЕГА"), 22, UIStyle.GOLD, 6))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	jv.add_child(scroll)
	_journal = VBoxContainer.new()
	_journal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal.add_theme_constant_override("separation", 6)
	scroll.add_child(_journal)

func toggle() -> void:
	visible = not visible
	get_tree().paused = visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_fill_journal()
		_first.grab_focus()
	else:
		if _settings and is_instance_valid(_settings):
			_settings.close()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func open_settings() -> void:
	if _settings and is_instance_valid(_settings):
		return
	_settings = SettingsPanel.new()
	_settings.closed.connect(func() -> void:
		if visible:
			_first.grab_focus())
	_root.add_child(_settings)

func _fill_journal() -> void:
	for c in _journal.get_children():
		c.queue_free()
	var traits: Array = Run.mjolnir_traits
	if not traits.is_empty():
		_journal.add_child(UIStyle.label(tr("МЬЁЛЬНИР"), 16, UIStyle.ICE, 4))
		for t in traits:
			var mt := t as MjolnirTrait
			var lv := Run.mjolnir_trait_level(mt.id)
			_journal.add_child(_entry(UISkin.trait_icon(str(mt.id)), mt.glyph, "%s  %s" % [tr(mt.title), "I" if lv <= 1 else "II"],
				tr(mt.description_lvl2 if lv > 1 and mt.description_lvl2 != "" else mt.description), mt.color))
	var counts := {}
	var order: Array = []
	for r in Run.runes:
		if not counts.has(r.id):
			counts[r.id] = 0
			order.append(r)
		counts[r.id] += 1
	_journal.add_child(UIStyle.label(tr("РУНЫ") if not order.is_empty() else tr("Рун пока нет — Норны ждут зачистки зала."), 16, UIStyle.GOLD, 4))
	for r in order:
		var rr := r as RuneDef
		var lvl := mini(counts[rr.id], Run.RUNE_MAX_LEVEL)
		var desc := rr.level_descriptions[lvl - 1] if lvl - 1 < rr.level_descriptions.size() else rr.description
		_journal.add_child(_entry(UISkin.rune_category_icon(rr.category), rr.glyph,
			("☠ " if rr.cursed else "") + tr("%s  ур. %d") % [tr(rr.title), lvl], tr(desc), rr.color))

func _entry(tex: Texture2D, glyph: String, title: String, desc: String, col: Color) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var icon := HudIcon.make(tex, 40)
	icon.badge = glyph
	icon.badge_color = col.lightened(0.2)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hb.add_child(icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(v)
	v.add_child(UIStyle.label(title, 17, col.lightened(0.35), 4))
	var d := UIStyle.label(desc, 14, UIStyle.TEXT_DIM, 2)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(330, 0)
	v.add_child(d)
	return hb

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()
