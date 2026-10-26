extends Control
class_name WeaponHUD
## HUD оружия: два слота (мили и ренж) справа внизу, активный подсвечен, патроны «магазин / запас»,
## полоса перезарядки, подсказка подбора «[E] …» под прицелом. Строится кодом; подключается из HUD.bind_player.

var holder: WeaponHolder
var _slots: Array[PanelContainer] = []
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
	_build()

func _build() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_left = -440
	box.offset_top = -150
	box.offset_right = -28
	box.offset_bottom = -20
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var ammo_row := HBoxContainer.new()
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_row.add_theme_constant_override("separation", 10)
	box.add_child(ammo_row)
	_reload_bar = ProgressBar.new()
	_reload_bar.custom_minimum_size = Vector2(120, 10)
	_reload_bar.show_percentage = false
	_reload_bar.visible = false
	_reload_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for i in 2:
		var p := UIStyle.panel()
		p.custom_minimum_size = Vector2(190, 0)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		p.add_child(v)
		var top := UIStyle.label("1 · МИЛИ" if i == 0 else "2 · РЕНЖ", 13, UIStyle.TEXT_DIM, 3)
		v.add_child(top)
		var n := UIStyle.label("", 20, UIStyle.TEXT, 5)
		v.add_child(n)
		var s := UIStyle.label("", 14, UIStyle.TEXT_DIM, 3)
		v.add_child(s)
		_slots.append(p)
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
		var col := (WeaponPickup.MELEE_COLOR if i == 0 else WeaponPickup.RANGED_COLOR)
		_slots[i].add_theme_stylebox_override("panel", UIStyle.panel_style(
			Color(0.12, 0.1, 0.08, 0.92) if on else Color(0.05, 0.05, 0.07, 0.6),
			Color(col, 0.95) if on else Color(1, 1, 1, 0.12), 8, 3 if on else 1))
		_slots[i].modulate.a = 1.0 if on else 0.65
		if it == null:
			_names[i].text = "—"
			_subs[i].text = "пусто"
			continue
		_names[i].text = it.title()
		if it.is_ranged():
			_subs[i].text = "%d / %d" % [it.mag, it.reserve] if not it.is_empty() else "ПУСТО"
		else:
			_subs[i].text = "ур. %d" % it.level
	var cur := holder.current()
	if cur and cur.is_ranged():
		_ammo_label.text = "%d / %d" % [cur.mag, cur.reserve]
		_ammo_label.label_settings.font_color = UIStyle.BLOOD if cur.mag == 0 else UIStyle.TEXT
	else:
		_ammo_label.text = ""

func _on_reload(active: bool, progress: float) -> void:
	_reload_bar.visible = active
	_reload_bar.value = progress * 100.0
