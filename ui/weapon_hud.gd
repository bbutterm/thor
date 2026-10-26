extends Control
class_name WeaponHUD
## HUD оружия (GDD 18): два слота справа внизу на рамках комплекта (мили — с топорами, ренж — с прицелом;
## активный — золотая «active»-рамка), в слоте иконка оружия (UISkin.weapon_icon), под ним уровень или
## патроны; крупно «магазин / запас» у активного ренжа, полоса перезарядки, подсказка подбора «[E] …»
## под прицелом. Строится кодом; подключается из HUD.bind_player.

## Размер рамки слота (активный крупнее)
@export var slot_size: float = 96.0
@export var active_slot_size: float = 112.0

var holder: WeaponHolder
var _slots: Array[WeaponSlot] = []
var _names: Array[Label] = []
var _subs: Array[Label] = []
var _ammo_label: Label
var _reload_bar: ProgressBar
var _prompt: Label
var _hint: Label

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

func _build() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_left = -440
	box.offset_top = -230
	box.offset_right = -16
	box.offset_bottom = -10
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	var ammo_row := HBoxContainer.new()
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
	box.add_child(row)
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
		_slots.append(slot)
		_names.append(n)
		_subs.append(s)
	_hint = UIStyle.label("Q / колесо — сменить · R — перезарядка", 13, UIStyle.TEXT_DIM, 3)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_hint)
	_prompt = UIStyle.label("", 22, UIStyle.GOLD, 6)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.offset_left = -400
	_prompt.offset_right = 400
	_prompt.offset_top = 34
	_prompt.offset_bottom = 70
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_prompt)

func bind(h: WeaponHolder) -> void:
	holder = h
	h.slots_changed.connect(_refresh)
	h.active_changed.connect(func(_s: int) -> void: _refresh())
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
		var was := slot.active
		slot.active = on
		slot.custom_minimum_size = Vector2.ONE * (active_slot_size if on else slot_size)
		slot.icon = UISkin.weapon_icon(it.def.id) if it and it.def else null
		slot.modulate.a = 1.0 if on else 0.72
		if on and not was:
			slot.pop()
		_names[i].modulate.a = 1.0 if on else 0.7
		_subs[i].modulate.a = 1.0 if on else 0.7
		if it == null:
			_names[i].text = "—"
			_subs[i].text = "пусто"
			slot.empty = false
			continue
		_names[i].text = it.title()
		slot.empty = it.is_ranged() and it.is_empty()
		if it.is_ranged():
			_subs[i].text = "%d / %d" % [it.mag, it.reserve] if not it.is_empty() else "ПУСТО"
			_subs[i].label_settings.font_color = UIStyle.BLOOD if it.is_empty() else UIStyle.TEXT_DIM
		else:
			_subs[i].text = "ур. %d" % it.level
			_subs[i].label_settings.font_color = UIStyle.TEXT_DIM
	var cur := holder.current()
	if cur and cur.is_ranged():
		_ammo_label.text = "%d / %d" % [cur.mag, cur.reserve]
		_ammo_label.label_settings.font_color = UIStyle.BLOOD if cur.mag == 0 else UIStyle.TEXT
	else:
		_ammo_label.text = ""

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
