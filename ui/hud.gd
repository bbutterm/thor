extends CanvasLayer
class_name HUD
## Интерфейс боя: здоровье, заряды рывка, Мьёльнир, Слава, руны, реплики Одина, полоса босса, линии скорости.

var player: Player

var _hp_bar: ProgressBar
var _hp_label: Label
var _dash_box: HBoxContainer
var _dash_pips: Array[ProgressBar] = []
var _hammer_label: Label
var _glory_label: Label
var _room_label: Label
var _body_label: Label
var _enemies_label: Label
var _runes_box: VBoxContainer
var _odin_panel: PanelContainer
var _odin_label: Label
var _odin_tween: Tween
var _toast_label: Label
var _speed_rect: ColorRect
var _speed_mat: ShaderMaterial
var _hurt_rect: ColorRect
var _fade_rect: ColorRect
var _boss_box: VBoxContainer
var _boss_bar: ProgressBar
var _boss: Enemy
var _crosshair: TextureRect
var _glory_shown: float = 0.0

func _ready() -> void:
	layer = 5
	_build()
	Run.glory_changed.connect(_on_glory_changed)
	Run.runes_changed.connect(_on_runes_changed)
	Odin.line_spoken.connect(show_odin_line)
	_on_runes_changed(Run.runes)
	_on_glory_changed(Run.glory)

func bind_player(p: Player) -> void:
	player = p
	player.health_changed.connect(_on_health_changed)
	player.dash_charges_changed.connect(_on_dash_changed)
	player.hurt.connect(_on_hurt)
	player.mjolnir.state_changed.connect(_on_hammer_state)
	_on_health_changed(player.health, player.max_health)
	_on_dash_changed(player.dash_charges, player.dash_charges_max, 0.0)
	_on_hammer_state(true)
	if Run.body:
		_body_label.text = "Тело: " + Run.body.display_name
	# Слоты оружия, патроны, подсказка подбора — ui/weapon_hud.gd
	WeaponHUD.attach(self, p)

func _build() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.full_rect(root)
	add_child(root)

	# Линии скорости
	_speed_rect = ColorRect.new()
	UIStyle.full_rect(_speed_rect)
	_speed_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_mat = ShaderMaterial.new()
	_speed_mat.shader = load("res://ui/speed_lines.gdshader")
	_speed_rect.material = _speed_mat
	root.add_child(_speed_rect)

	# Красная вспышка при уроне
	_hurt_rect = ColorRect.new()
	UIStyle.full_rect(_hurt_rect)
	_hurt_rect.color = Color(0.8, 0.05, 0.05, 0.0)
	_hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hurt_rect)

	# Прицел
	_crosshair = TextureRect.new()
	_crosshair.texture = load("res://sprites/crosshair.png")
	_crosshair.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crosshair.custom_minimum_size = Vector2(36, 36)
	_crosshair.size = Vector2(36, 36)
	_anchor(_crosshair, Control.PRESET_CENTER, -18, -18, 18, 18)
	_crosshair.modulate = Color(1, 1, 1, 0.8)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_crosshair)

	# Левый низ: здоровье + рывок + молот
	var bl := VBoxContainer.new()
	_anchor(bl, Control.PRESET_BOTTOM_LEFT, 28, -150, 480, -20)
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bl.alignment = BoxContainer.ALIGNMENT_END
	bl.add_theme_constant_override("separation", 8)
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bl)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 12)
	bl.add_child(hp_row)
	_hp_bar = _make_bar(UIStyle.BLOOD, Vector2(300, 26))
	hp_row.add_child(_hp_bar)
	_hp_label = UIStyle.label("100", 24)
	hp_row.add_child(_hp_label)
	var dash_row := HBoxContainer.new()
	dash_row.add_theme_constant_override("separation", 10)
	bl.add_child(dash_row)
	dash_row.add_child(UIStyle.label("РЫВОК", 16, UIStyle.TEXT_DIM, 4))
	_dash_box = HBoxContainer.new()
	_dash_box.add_theme_constant_override("separation", 6)
	dash_row.add_child(_dash_box)
	_hammer_label = UIStyle.label("", 20, UIStyle.ICE)
	bl.add_child(_hammer_label)

	# Правый верх: Слава, тело, руны
	var tr := VBoxContainer.new()
	_anchor(tr, Control.PRESET_TOP_RIGHT, -380, 22, -28, 420)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.alignment = BoxContainer.ALIGNMENT_BEGIN
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tr)
	_glory_label = UIStyle.label("СЛАВА 0", 30, UIStyle.GOLD, 8)
	_glory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_glory_label)
	_body_label = UIStyle.label("", 18, UIStyle.TEXT_DIM, 4)
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_body_label)
	_runes_box = VBoxContainer.new()
	_runes_box.add_theme_constant_override("separation", 2)
	tr.add_child(_runes_box)

	# Левый верх: зал и враги
	var tl := VBoxContainer.new()
	_anchor(tl, Control.PRESET_TOP_LEFT, 28, 22, 600, 120)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tl)
	_room_label = UIStyle.label("", 22, UIStyle.TEXT)
	tl.add_child(_room_label)
	_enemies_label = UIStyle.label("", 18, UIStyle.TEXT_DIM, 4)
	tl.add_child(_enemies_label)

	# Полоса босса
	_boss_box = VBoxContainer.new()
	_anchor(_boss_box, Control.PRESET_CENTER_TOP, -300, 24, 300, 90)
	_boss_box.visible = false
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_boss_box)
	var bl2 := UIStyle.label("ХРИМТУРС ПОЖИРАТЕЛЬ ГЕРОЕВ", 20, UIStyle.GOLD)
	bl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(bl2)
	_boss_bar = _make_bar(Color(0.75, 0.15, 0.1), Vector2(600, 18))
	_boss_box.add_child(_boss_bar)

	# Реплика Одина
	_odin_panel = UIStyle.panel(Color(0.05, 0.05, 0.07, 0.82), Color(UIStyle.GOLD, 0.5))
	# Реплики Одина — сверху по центру, чтобы не закрывать бой
	_anchor(_odin_panel, Control.PRESET_CENTER_TOP, -330, 100, 330, 160)
	_odin_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_odin_panel.grow_vertical = Control.GROW_DIRECTION_END
	_odin_panel.modulate.a = 0.0
	_odin_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_odin_panel)
	var ob := VBoxContainer.new()
	_odin_panel.add_child(ob)
	ob.add_child(UIStyle.label("ОДИН", 15, UIStyle.GOLD, 4))
	_odin_label = UIStyle.label("", 19, UIStyle.TEXT, 5)
	_odin_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_odin_label.custom_minimum_size = Vector2(620, 0)
	ob.add_child(_odin_label)

	# Короткая подсказка по центру
	_toast_label = UIStyle.label("", 28, UIStyle.GOLD, 8)
	_anchor(_toast_label, Control.PRESET_CENTER, -400, 60, 400, 110)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.modulate.a = 0.0
	root.add_child(_toast_label)

	# Затемнение между залами
	_fade_rect = ColorRect.new()
	UIStyle.full_rect(_fade_rect)
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade_rect)

func _anchor(c: Control, preset: Control.LayoutPreset, l: float, t: float, r: float, b: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b

func _make_bar(color: Color, size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = size
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = 100
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(5)
	bg.border_color = Color(1, 1, 1, 0.15)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar

func _process(delta: float) -> void:
	if player and is_instance_valid(player):
		_speed_mat.set_shader_parameter("intensity", player.camera_fx.speed_lines)
	_hurt_rect.color.a = maxf(0.0, _hurt_rect.color.a - delta * 1.6)
	if _boss and is_instance_valid(_boss):
		_boss_bar.value = maxf(0.0, _boss.health) / _boss.max_health * 100.0
	elif _boss_box.visible and _boss == null:
		pass
	if absf(_glory_shown - Run.glory) > 0.5:
		_glory_shown = lerpf(_glory_shown, Run.glory, minf(1.0, delta * 8.0))
		_glory_label.text = "СЛАВА %d" % int(round(_glory_shown))

func _on_health_changed(current: float, maximum: float) -> void:
	_hp_bar.max_value = maximum
	_hp_bar.value = current
	_hp_label.text = "%d / %d" % [int(ceil(current)), int(maximum)]

func _on_dash_changed(current: int, maximum: int, progress: float) -> void:
	if _dash_pips.size() != maximum:
		for c in _dash_box.get_children():
			c.queue_free()
		_dash_pips.clear()
		for i in maximum:
			var pip := _make_bar(UIStyle.ICE, Vector2(46, 12))
			_dash_box.add_child(pip)
			_dash_pips.append(pip)
	for i in _dash_pips.size():
		if i < current:
			_dash_pips[i].value = 100
		elif i == current:
			_dash_pips[i].value = progress * 100.0
		else:
			_dash_pips[i].value = 0

func _on_hammer_state(in_hand: bool) -> void:
	_hammer_label.text = "ᛗ МЬЁЛЬНИР: В РУКЕ  [ПКМ]" if in_hand else "ᛗ МЬЁЛЬНИР: ЛЕТИТ  [ПКМ — вернуть]"
	_hammer_label.label_settings.font_color = UIStyle.ICE if in_hand else Color(1, 0.85, 0.4)

func _on_hurt(_amount: float) -> void:
	_hurt_rect.color.a = 0.35

func _on_glory_changed(total: int) -> void:
	if _glory_label and total > _glory_shown + 5:
		var tw := _glory_label.create_tween()
		_glory_label.pivot_offset = _glory_label.size * Vector2(1, 0.5)
		tw.tween_property(_glory_label, "scale", Vector2(1.15, 1.15), 0.06)
		tw.tween_property(_glory_label, "scale", Vector2.ONE, 0.15)

func _on_runes_changed(runes: Array) -> void:
	if _runes_box == null:
		return
	for c in _runes_box.get_children():
		c.queue_free()
	var counts := {}
	var order: Array = []
	for r in runes:
		var rr := r as RuneDef
		if not counts.has(rr.id):
			counts[rr.id] = 0
			order.append(rr)
		counts[rr.id] += 1
	for r in order:
		var rr := r as RuneDef
		var txt := "%s %s" % [rr.glyph, rr.title]
		if counts[rr.id] > 1:
			txt += " ×%d" % counts[rr.id]
		var l := UIStyle.label(txt, 16, rr.color, 4)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_runes_box.add_child(l)

func show_odin_line(text: String) -> void:
	Perf.mark("odin_line")
	if text == "" or _odin_label == null:
		return
	_odin_label.text = text
	if _odin_tween and _odin_tween.is_valid():
		_odin_tween.kill()
	_odin_tween = _odin_panel.create_tween()
	_odin_tween.tween_property(_odin_panel, "modulate:a", 1.0, 0.2)
	_odin_tween.tween_interval(clampf(1.6 + text.length() * 0.035, 2.0, 3.5))
	_odin_tween.tween_property(_odin_panel, "modulate:a", 0.0, 0.4)

func toast(text: String) -> void:
	_toast_label.text = text
	var tw := _toast_label.create_tween()
	tw.tween_property(_toast_label, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.4)
	tw.tween_property(_toast_label, "modulate:a", 0.0, 0.4)

func set_room(index: int, total: int, title: String, boss: bool) -> void:
	_room_label.text = ("ФИНАЛ: %s" % title) if boss else ("ЗАЛ %d / %d · %s" % [index, total, title])
	_boss_box.visible = false
	_boss = null
	toast(title.to_upper())

func set_enemy_count(alive: int) -> void:
	_enemies_label.text = "Врагов: %d" % alive if alive > 0 else ""

func show_boss(boss: Enemy) -> void:
	_boss = boss
	_boss_box.visible = true
	boss.died.connect(func(_e: Enemy) -> void: _boss_box.visible = false)

func fade_in(time: float = 0.35) -> void:
	_fade_rect.color.a = 1.0
	var tw := _fade_rect.create_tween()
	tw.tween_property(_fade_rect, "color:a", 0.0, time)

func fade_out(time: float = 0.25) -> void:
	var tw := _fade_rect.create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, time)
