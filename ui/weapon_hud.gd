extends Control
class_name WeaponHUD
## HUD оружия (GDD 18, П6): два слота справа над шкалой стиля на рамках комплекта (мили — с топорами, ренж — с
## прицелом; активный — золотая «active»-рамка), в слоте иконка оружия (UISkin.weapon_icon), под ним уровень или
## патроны. Слоты видны только show_time с после смены/подбора, потом гаснут; «магазин / запас» и полоса
## перезарядки — пока в руках ствол. Подсказка подбора «[E] …» — внизу над пузырём реплик (центр — только прицел).
## Строится кодом; подключается из HUD.bind_player.

## Размер рамки слота (активный крупнее)
@export var slot_size: float = 96.0
@export var active_slot_size: float = 112.0
## Сколько секунд видны слоты после смены/подбора оружия (П6)
@export var show_time: float = 2.0

var holder: WeaponHolder
var _slots: Array[WeaponSlot] = []
var _names: Array[Label] = []
var _subs: Array[Label] = []
var _skills: Array[Label] = []
var _ammo_label: Label
var _reload_bar: ProgressBar
var _prompt: Label
var _hint: Label
## Слоты с подписями и подсказкой клавиш — гаснут через show_time
var _slots_box: VBoxContainer
var _ammo_row: HBoxContainer
var _slots_left: float = 0.0

static func attach(hud: CanvasLayer, p: Player) -> WeaponHUD:
	if p.weapons == null:
		return null
	var w := WeaponHUD.new()
	w.name = "WeaponHUD"
	# Под затемнением между залами и вспышками экрана
	w.z_index = -1
	hud.add_child(w)
	w.bind(p.weapons)
	return w

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.full_rect(self)
	UISkin.apply(self)
	_build()
	GameSettings.events.changed.connect(_on_setting_changed)

func _build() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_left = -440
	box.offset_top = -380
	box.offset_right = -16
	box.offset_bottom = -150
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_slots_box = VBoxContainer.new()
	_slots_box.alignment = BoxContainer.ALIGNMENT_END
	_slots_box.add_theme_constant_override("separation", 2)
	_slots_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots_box.modulate.a = 0.0
	box.add_child(_slots_box)
	var ammo_row := HBoxContainer.new()
	_ammo_row = ammo_row
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_row.add_theme_constant_override("separation", 10)
	ammo_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ammo_row)
	_reload_bar = ProgressBar.new()
	_reload_bar.custom_minimum_size = Vector2(120, 10)
	_reload_bar.show_percentage = false
	_reload_bar.visible = false
	_reload_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reload_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = UIStyle.ICE
	fg.set_corner_radius_all(4)
	_reload_bar.add_theme_stylebox_override("background", bg)
	_reload_bar.add_theme_stylebox_override("fill", fg)
	ammo_row.add_child(_reload_bar)
	_ammo_label = UIStyle.label("", 34, UIStyle.TEXT, 8)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_row.add_child(_ammo_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots_box.add_child(row)
	for i in 2:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -8)
		v.alignment = BoxContainer.ALIGNMENT_END
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.custom_minimum_size = Vector2(active_slot_size + 30, 0)
		row.add_child(v)
		var slot := WeaponSlot.new()
		slot.ranged = i == 1
		slot.key_text = "1" if i == 0 else "2"
		slot.custom_minimum_size = Vector2(slot_size, slot_size)
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(slot)
		var n := UIStyle.label("", 16, UIStyle.TEXT, 5)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(n)
		var s := UIStyle.label("", 14, UIStyle.TEXT_DIM, 4)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(s)
		var skill := UIStyle.label("", 12, UIStyle.GOLD, 3)
		skill.name = "WeaponSkill"
		skill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		skill.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		skill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		skill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		skill.visible = false
		v.add_child(skill)
		_slots.append(slot)
		_names.append(n)
		_subs.append(s)
		_skills.append(skill)
	_hint = UIStyle.label("", 13, UIStyle.TEXT_DIM, 3)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_slots_box.add_child(_hint)
	# Ammo — под слотами, у самой шкалы стиля
	box.move_child(ammo_row, box.get_child_count() - 1)
	_prompt = UIStyle.label("", 22, UIStyle.GOLD, 6)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -400
	_prompt.offset_right = 400
	_prompt.offset_top = -290
	_prompt.offset_bottom = -246
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_prompt)

func bind(h: WeaponHolder) -> void:
	holder = h
	h.slots_changed.connect(func() -> void:
		_refresh()
		reveal())
	h.active_changed.connect(func(_s: int) -> void:
		_refresh()
		reveal())
	h.ammo_changed.connect(func(_m: int, _r: int) -> void: _refresh())
	h.reload_changed.connect(_on_reload)
	h.prompt_changed.connect(func(t: String) -> void: _prompt.text = t)
	_refresh()

func _refresh() -> void:
	if holder == null or _slots.is_empty():
		return
	var items := [holder.melee, holder.ranged]
	for i in 2:
		var it: WeaponItem = items[i]
		var on := holder.active_slot == i
		var slot := _slots[i]
		slot.key_text = "" if GameSettings.using_gamepad() else GameSettings.current_binding("weapon_melee" if i == 0 else "weapon_ranged")
		slot.queue_redraw()
		var was := slot.active
		slot.active = on
		slot.custom_minimum_size = Vector2.ONE * (active_slot_size if on else slot_size)
		slot.icon = UISkin.weapon_icon(it.def.id) if it and it.def else null
		slot.modulate.a = 1.0 if on else 0.72
		if on and not was:
			slot.pop()
		_names[i].modulate.a = 1.0 if on else 0.7
		_subs[i].modulate.a = 1.0 if on else 0.7
		_skills[i].modulate.a = 1.0 if on else 0.7
		_skills[i].visible = false
		if it == null:
			_names[i].text = "—"
			_subs[i].text = tr("пусто")
			slot.empty = false
			continue
		_names[i].text = it.title()
		slot.empty = it.is_ranged() and it.is_empty()
		if it.is_ranged():
			_subs[i].text = "%d / %d" % [it.mag, it.reserve] if not it.is_empty() else tr("ПУСТО")
			_subs[i].label_settings.font_color = UIStyle.BLOOD if it.is_empty() else UIStyle.TEXT_DIM
		else:
			_subs[i].text = tr("ур. %d") % it.level
			_subs[i].label_settings.font_color = UIStyle.TEXT_DIM
			if it.def and it.def.skill_kind != "none" and it.def.skill_title != "":
				_skills[i].text = tr("Приём: %s") % tr(it.def.skill_title)
				_skills[i].visible = true
	var cur := holder.current()
	_ammo_row.visible = cur != null and cur.is_ranged()
	if cur and cur.is_ranged():
		_ammo_label.text = "%d / %d" % [cur.mag, cur.reserve]
		_ammo_label.label_settings.font_color = UIStyle.BLOOD if cur.mag == 0 else UIStyle.TEXT
	else:
		_ammo_label.text = ""
	_hint.text = tr("%s — сменить · %s — перезарядка") % [GameSettings.current_binding("weapon_switch"), GameSettings.current_binding("reload")]

## Показать слоты на show_time (смена, подбор оружия)
func reveal() -> void:
	_slots_left = show_time
	_slots_box.modulate.a = 1.0

func _process(delta: float) -> void:
	if _slots_left <= 0.0:
		return
	_slots_left = maxf(0.0, _slots_left - delta)
	_slots_box.modulate.a = clampf(_slots_left / 0.4, 0.0, 1.0)

func _on_setting_changed(section: String, _key: String) -> void:
	if section in ["input", "pad_input", "input_device", "text"]:
		_refresh()

func _on_reload(active: bool, progress: float) -> void:
	_reload_bar.visible = active
	_reload_bar.value = progress * 100.0

## Рамка слота с иконкой оружия внутри content_rect рамки и цифрой клавиши в углу
class WeaponSlot extends Control:
	var ranged: bool = false
	var key_text: String = ""
	var active: bool = false:
		set(v):
			active = v
			queue_redraw()
	var empty: bool = false:
		set(v):
			empty = v
			queue_redraw()
	var icon: Texture2D:
		set(v):
			icon = v
			queue_redraw()
	var _pop: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
		set_process(false)

	func pop() -> void:
		_pop = 1.0
		set_process(true)

	func _process(delta: float) -> void:
		_pop = maxf(0.0, _pop - delta * 5.0)
		queue_redraw()
		if _pop <= 0.0:
			set_process(false)

	func _draw() -> void:
		var id := "hud_weapon_slot_%s_%s" % ["ranged" if ranged else "melee", "active" if active else "normal"]
		var frame := UISkin.texture(id)
		var src := UISkin.source_size(id)
		var k := minf(size.x / src.x, size.y / src.y) * (1.0 + 0.12 * _pop)
		var off := (size - src * k) * 0.5
		var content := UISkin.rect(id, "content_rect")
		if not content.has_area():
			content = Rect2(src * 0.22, src * 0.56)
		var inner := Rect2(off + content.position * k, content.size * k).grow(-content.size.x * k * 0.06)
		draw_rect(inner, Color(0.04, 0.035, 0.03, 0.75))
		if icon:
			var ts := icon.get_size()
			var ik := minf(inner.size.x / ts.x, inner.size.y / ts.y)
			var isz := ts * ik
			draw_texture_rect(icon, Rect2(inner.position + (inner.size - isz) * 0.5, isz), false,
				Color(1, 0.55, 0.5) if empty else Color.WHITE)
		if frame:
			draw_texture_rect(frame, Rect2(off, src * k), false)
		else:
			draw_rect(inner, WeaponPickup.RANGED_COLOR if ranged else WeaponPickup.MELEE_COLOR, false, 2.0)
		if key_text != "":
			var font := UIStyle.font()
			var p := off + Vector2(content.position.x * k + 2, content.position.y * k + 16)
			draw_string_outline(font, p, key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0, 0, 0, 0.9))
			draw_string(font, p, key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIStyle.GOLD if active else UIStyle.TEXT_DIM)
