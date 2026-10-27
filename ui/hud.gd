extends CanvasLayer
class_name HUD
## Интерфейс боя (GDD 18) на графике комплекта (UISkin): HP и щит Сиф, заряды рывка, Мьёльнир (в руке /
## летит / воткнут / возвращается) и его трейты, Слава, серебро (ui/silver_hud.gd), руны иконками по категориям,
## прицел и шкала высоты удара-приземления, индикаторы врагов за экраном, реплики Одина,
## полоса босса, линии скорости. Оружие — ui/weapon_hud.gd, шкала стиля «ДОСТОЙНО!» — ui/style_hud.gd.
## Раскладка якорями от углов: 1280×720 и 1920×1080 (stretch canvas_items) выглядят одинаково.

## Высота полосы HP (ширина — по пропорциям рамки 768×192)
@export var hp_bar_height: float = 84.0
## Размер иконки Мьёльнира и камня рывка
@export var hammer_icon_size: float = 58.0
@export var dash_icon_size: float = 38.0
## Шкала высоты удара-приземления: с какой высоты над полом показывать (м)
@export var slam_meter_min_height: float = 2.5
## Базовый размер прицела (px; множитель — настройки)
@export var crosshair_base_size: float = 30.0
## Размер иконки руны в ряду
@export var rune_icon_size: float = 36.0

const CROSSHAIR_IDS := {"dot": "crosshair_dot", "cross": "crosshair_cross", "circle": "crosshair_circle"}
const CLASSIC_CROSSHAIR := "res://sprites/crosshair.png"
## Имя на полосе босса, если враг не задал своё (ключ перевода)
const DEFAULT_BOSS_TITLE := "ХРИМТУРС ПОЖИРАТЕЛЬ ГЕРОЕВ"

var player: Player

var _hp_bar: SkinBar
var _hp_label: Label
var _dash_box: HBoxContainer
var _dash_pips: Array[HudIcon] = []
var _hammer_icon: HudIcon
var _hammer_label: Label
var _hammer_state: String = ""
var _glory_label: Label
var _room_label: Label
var _body_label: Label
var _enemies_label: Label
var _runes_box: HFlowContainer
var _odin_panel: PanelContainer
var _odin_label: Label
var _odin_tween: Tween
var _toast_label: Label
var _speed_rect: ColorRect
var _speed_mat: ShaderMaterial
var _hurt_rect: ColorRect
var _fade_rect: ColorRect
var _boss_box: VBoxContainer
var _boss_bar: BossBar
var _boss: Enemy
var _boss_title: Label
var _mjolnir_traits: MjolnirTraitsHud
var _crosshair: TextureRect
var _slam_meter: SkinBar
var _offscreen: OffscreenIndicators
var _glory_shown: float = 0.0
## Для перевода на лету (смена языка из паузы): последние аргументы set_room и число врагов
var _room_args: Array = []
var _enemies_alive: int = 0
var _odin_name: Label

func _ready() -> void:
	layer = 5
	_build()
	Run.glory_changed.connect(_on_glory_changed)
	Run.runes_changed.connect(_on_runes_changed)
	Odin.line_spoken.connect(show_odin_line)
	GameSettings.events.changed.connect(_on_setting_changed)
	_on_runes_changed(Run.runes)
	_on_glory_changed(Run.glory)

func bind_player(p: Player) -> void:
	player = p
	player.health_changed.connect(_on_health_changed)
	player.dash_charges_changed.connect(_on_dash_changed)
	player.hurt.connect(_on_hurt)
	player.slam_unavailable.connect(func() -> void: toast(tr("НУЖЕН ВТОРОЙ ПРЫЖОК")))
	player.mjolnir.state_changed.connect(_on_hammer_state)
	# Бросок на перезарядке: подпись вспыхивает красным, иконка дёргается
	player.mjolnir.throw_blocked.connect(func(_left: float) -> void:
		_hammer_icon.pop()
		_hammer_flash_until = Time.get_ticks_msec() + 400)
	_on_health_changed(player.health, player.max_health)
	_on_dash_changed(player.dash_charges, player.dash_charges_max, 0.0)
	_on_hammer_state(true)
	if _mjolnir_traits:
		_mjolnir_traits.player = p
	if _offscreen:
		_offscreen.player = p
	if Run.body:
		_body_label.text = tr("Тело: %s") % tr(Run.body.display_name)
	# Слоты оружия, патроны, подсказка подбора — ui/weapon_hud.gd
	WeaponHUD.attach(self, p)
	# Шкала стиля «ДОСТОЙНО!» (ранг, комикс-подпись) и виньетка берсерка — ui/style_hud.gd (блок Б3)
	StyleHUD.attach(self, p)
	# Серебро под Славой — ui/silver_hud.gd (блок К)
	SilverHUD.attach(self)

func _build() -> void:
	UISkin.preload_game()
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.full_rect(root)
	UISkin.apply(root)
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

	# Индикаторы врагов за экраном (под остальным HUD)
	_offscreen = OffscreenIndicators.new()
	root.add_child(_offscreen)

	# Прицел (вид, размер, яркость — настройки [hud])
	_crosshair = TextureRect.new()
	_crosshair.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crosshair.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	root.add_child(_crosshair)
	_apply_crosshair()

	# Левый низ: трейты Мьёльнира, молот + рывок, здоровье
	var bl := VBoxContainer.new()
	_anchor(bl, Control.PRESET_BOTTOM_LEFT, 14, -300, 560, -10)
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bl.alignment = BoxContainer.ALIGNMENT_END
	bl.add_theme_constant_override("separation", 0)
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bl)
	# Трейты Мьёльнира — над молотом (отдельно от рун)
	_mjolnir_traits = MjolnirTraitsHud.new()
	bl.add_child(_mjolnir_traits)
	var hammer_row := HBoxContainer.new()
	hammer_row.add_theme_constant_override("separation", 8)
	hammer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl.add_child(hammer_row)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(22, 0)
	hammer_row.add_child(pad)
	_hammer_icon = HudIcon.make(UISkin.texture("hud_mjolnir_ready"), hammer_icon_size)
	hammer_row.add_child(_hammer_icon)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Ресурс и высота образуют один молот: руны на бойке, шкала в рукояти.
	var rune_hammer := RuneHammer.new()
	hammer_row.add_child(rune_hammer)
	_dash_box = HBoxContainer.new()
	_dash_box.position = Vector2(11, 5)
	_dash_box.size = Vector2(122, 34)
	_dash_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_dash_box.add_theme_constant_override("separation", 2)
	_dash_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rune_hammer.add_child(_dash_box)
	_slam_meter = SkinBar.new()
	_slam_meter.frame_id = "hud_slam_meter_frame"
	_slam_meter.fill_id = "hud_slam_meter_fill"
	_slam_meter.flat_color = UIStyle.ICE
	_slam_meter.trail_delay = 0.0
	_slam_meter.position = Vector2(60, 42)
	_slam_meter.size = Vector2(24, 58)
	_slam_meter.visible = false
	rune_hammer.add_child(_slam_meter)
	hammer_row.add_child(hv)
	_hammer_label = UIStyle.label("", 15, UIStyle.ICE, 4)
	hv.add_child(_hammer_label)
	_hp_bar = SkinBar.new()
	_hp_bar.frame_id = "hud_hp_frame"
	_hp_bar.fill_id = "hud_hp_fill"
	_hp_bar.custom_minimum_size = Vector2(hp_bar_height * 4.0, hp_bar_height)
	bl.add_child(_hp_bar)
	_hp_label = UIStyle.label("100", 20, UIStyle.TEXT, 6)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_bar.add_child(_hp_label)
	_hp_bar.resized.connect(_place_hp_label)

	# Правый верх: Слава, серебро, тело, руны (сжатый ряд)
	var top_right := VBoxContainer.new()
	_anchor(top_right, Control.PRESET_TOP_RIGHT, -380, 18, -24, 300)
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_right.add_theme_constant_override("separation", 2)
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_right)
	_glory_label = UIStyle.label(tr("СЛАВА 0"), 30, UIStyle.GOLD, 8)
	_glory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_right.add_child(_glory_label)
	# Серебро — ui/silver_hud.gd (SilverHUD.attach в bind_player встаёт сразу под Славу)
	_body_label = UIStyle.label("", 16, UIStyle.TEXT_DIM, 4)
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_right.add_child(_body_label)
	_runes_box = HFlowContainer.new()
	_runes_box.alignment = FlowContainer.ALIGNMENT_END
	_runes_box.add_theme_constant_override("h_separation", 2)
	_runes_box.add_theme_constant_override("v_separation", 2)
	_runes_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_right.add_child(_runes_box)

	# Левый верх: зал и враги
	var tl := VBoxContainer.new()
	_anchor(tl, Control.PRESET_TOP_LEFT, 24, 18, 600, 120)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tl)
	_room_label = UIStyle.label("", 22, UIStyle.TEXT)
	tl.add_child(_room_label)
	_enemies_label = UIStyle.label("", 18, UIStyle.TEXT_DIM, 4)
	tl.add_child(_enemies_label)

	# Полоса босса
	_boss_box = VBoxContainer.new()
	_anchor(_boss_box, Control.PRESET_CENTER_TOP, -320, 18, 320, 96)
	_boss_box.visible = false
	_boss_box.add_theme_constant_override("separation", 0)
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_boss_box)
	_boss_title = UIStyle.label(tr(DEFAULT_BOSS_TITLE), 20, UIStyle.GOLD)
	_boss_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_title)
	_boss_bar = BossBar.new()
	_boss_bar.custom_minimum_size = Vector2(640, 30)
	_boss_box.add_child(_boss_bar)

	# Реплика Одина — сверху по центру, чтобы не закрывать бой
	_odin_panel = UIStyle.panel(Color(0.05, 0.05, 0.07, 0.82), Color(UIStyle.GOLD, 0.5))
	_anchor(_odin_panel, Control.PRESET_CENTER_TOP, -340, 104, 340, 164)
	_odin_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_odin_panel.grow_vertical = Control.GROW_DIRECTION_END
	_odin_panel.modulate.a = 0.0
	_odin_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_odin_panel)
	var ob := VBoxContainer.new()
	ob.add_theme_constant_override("separation", 0)
	_odin_panel.add_child(ob)
	_odin_name = UIStyle.label(tr("ОДИН"), 15, UIStyle.GOLD, 4)
	ob.add_child(_odin_name)
	_odin_label = UIStyle.label("", int(19 * GameSettings.text_scale()), UIStyle.TEXT, 5)
	_odin_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_odin_label.custom_minimum_size = Vector2(560, 0)
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

## Цифры HP — по центру области заливки рамки
func _place_hp_label() -> void:
	var a := _hp_bar.fill_area()
	_hp_label.position = a.position
	_hp_label.size = a.size

func _apply_crosshair() -> void:
	var kind := str(GameSettings.get_value("hud", "crosshair"))
	var tex: Texture2D = UISkin.texture(CROSSHAIR_IDS.get(kind, ""))
	if tex == null:
		tex = load(CLASSIC_CROSSHAIR)
	_crosshair.texture = tex
	var s := crosshair_base_size * float(GameSettings.get_value("hud", "crosshair_size"))
	if kind == "dot":
		s *= 1.4
	_anchor(_crosshair, Control.PRESET_CENTER, -s * 0.5, -s * 0.5, s * 0.5, s * 0.5)
	_crosshair.modulate = GameSettings.crosshair_color()

func _on_setting_changed(section: String, key: String) -> void:
	if section == "hud":
		_apply_crosshair()
		_offscreen.enabled = bool(GameSettings.get_value("hud", "offscreen"))
	elif section == "text":
		_odin_label.label_settings.font_size = int(19 * GameSettings.text_scale())
		if key == "language":
			_retranslate()
	elif section in ["input", "pad_input", "input_device"]:
		_hammer_state = ""

## Смена языка посреди забега: подписи, которые сами не обновляются каждый кадр
func _retranslate() -> void:
	_odin_name.text = tr("ОДИН")
	_hammer_state = ""
	if player and is_instance_valid(player):
		_update_hammer()
	_glory_label.text = tr("СЛАВА %d") % int(round(_glory_shown))
	if Run.body:
		_body_label.text = tr("Тело: %s") % tr(Run.body.display_name)
	if _room_args.size() == 4:
		var t := tr(str(_room_args[2]))
		_room_label.text = (tr("ФИНАЛ: %s") % t) if _room_args[3] else (tr("ЗАЛ %d / %d · %s") % [_room_args[0], _room_args[1], t])
	set_enemy_count(_enemies_alive)
	if _boss and is_instance_valid(_boss):
		_boss_title.text = tr(str(_boss.get_meta("boss_title", DEFAULT_BOSS_TITLE)))
	_on_runes_changed(Run.runes)

## На паузе (выбор руны/трейта/награды, ларёк, меню паузы) HUD стоит, и его твин тоже: пузырь Одина
## застывал видимым под затемнением и наезжал на заголовок экрана выбора. Прячем до снятия паузы.
func _notification(what: int) -> void:
	if _odin_panel == null:
		return
	if what == NOTIFICATION_PAUSED:
		_odin_panel.visible = false
	elif what == NOTIFICATION_UNPAUSED:
		_odin_panel.visible = true

func _process(delta: float) -> void:
	_position_odin_notice()
	if player and is_instance_valid(player):
		_speed_mat.set_shader_parameter("intensity", player.camera_fx.speed_lines)
		_update_hammer()
		_update_slam_meter()
	_hurt_rect.color.a = maxf(0.0, _hurt_rect.color.a - delta * 1.6)
	if _boss and is_instance_valid(_boss):
		_boss_bar.value = maxf(0.0, _boss.health) / _boss.max_health
	if absf(_glory_shown - Run.glory) > 0.5:
		_glory_shown = lerpf(_glory_shown, Run.glory, minf(1.0, delta * 8.0))
		_glory_label.text = tr("СЛАВА %d") % int(round(_glory_shown))

## Объявление связки и реплика Одина часто появляются одновременно. Пузырь
## временно уходит ниже плашки, затем возвращается на обычное место.
func _position_odin_notice() -> void:
	if _odin_panel == null:
		return
	var top := 104.0
	var left := -340.0
	var announce := get_parent().get_node_or_null("ComboAnnounce") as ComboAnnounce
	if announce and announce.is_showing():
		var bounds := announce.visual_rect()
		var style := _odin_panel.get_theme_stylebox("panel") as SkinStyleBox
		var frame_top := style.grow.y if style else 0.0
		top = maxf(top, bounds.end.y + frame_top + 12.0)
		# Если ворон тоже говорит, размещаем подписи рядом, чтобы их можно было читать.
		var bubble := Dialogue.get("_bubble") as BarkBubble
		if is_instance_valid(bubble) and is_instance_valid(bubble._panel) and bubble._panel.modulate.a > 0.01:
			var vp_width := get_viewport().get_visible_rect().size.x
			var frame_right := style.grow.z if style else 0.0
			var right_limit := bubble.visual_rect().position.x - frame_right - 12.0
			left = minf(left, right_limit - 680.0 - vp_width * 0.5)
			left = maxf(left, -vp_width * 0.5 + (style.grow.x if style else 0.0) + 6.0)
	_odin_panel.offset_left = left
	_odin_panel.offset_right = left + 680.0
	_odin_panel.offset_top = top
	_odin_panel.offset_bottom = top + 60.0

func _on_health_changed(current: float, maximum: float) -> void:
	_hp_bar.value = current / maxf(maximum, 1.0)
	_hp_label.text = "%d / %d" % [int(ceil(current)), int(maximum)]
	# Щит (руна «Щит Сиф», GDD 18: HP и щит) — светлая полоса поверх HP и «+N»
	var sh := player.shield if player else 0.0
	_hp_bar.overlay = sh / maxf(maximum, 1.0) if sh > 0.5 else 0.0
	if sh > 0.5:
		_hp_label.text += "  ⛨%d" % int(ceil(sh))

func _on_dash_changed(current: int, maximum: int, progress: float) -> void:
	if _dash_pips.size() != maximum:
		for c in _dash_box.get_children():
			c.queue_free()
		_dash_pips.clear()
		for i in maximum:
			var icon_size := minf(dash_icon_size, (122.0 - maxf(0, maximum - 1) * 2.0) / maxf(1, maximum))
			var pip := HudIcon.make(UISkin.texture("hud_dash_empty"), icon_size)
			pip.over = UISkin.texture("hud_dash_full")
			_dash_box.add_child(pip)
			_dash_pips.append(pip)
	for i in _dash_pips.size():
		var pip := _dash_pips[i]
		var was := pip.fill
		if i < current:
			pip.fill = 1.0
			if was < 1.0:
				pip.pop()
		elif i == current:
			pip.fill = progress
		else:
			pip.fill = 0.0

## Мьёльнир: в руке / летит / воткнут / возвращается (иконки комплекта)
## До какого момента (мс) подпись перезарядки красная — после попытки броска
var _hammer_flash_until: int = 0

func _update_hammer() -> void:
	var m := player.mjolnir
	var st := "hand"
	if m.in_hand and m.cooldown_left > 0.0:
		st = "cooldown"
		# Секунды перезарядки обновляются каждый кадр
		_hammer_label.text = tr("ПЕРЕЗАРЯДКА %.1f с · ПОЙМАЙ ИДЕАЛЬНО — БЫСТРЕЕ") % m.cooldown_left
		if _hammer_state == "cooldown":
			_hammer_label.label_settings.font_color = Color(1.0, 0.35, 0.3) if Time.get_ticks_msec() < _hammer_flash_until else Color(0.75, 0.75, 0.8)
	if not m.in_hand and m.projectile and is_instance_valid(m.projectile):
		match m.projectile.state:
			MjolnirProjectile.State.STUCK:
				st = "stuck"
			MjolnirProjectile.State.RETURN:
				st = "return"
			_:
				st = "out"
	elif not m.in_hand:
		st = "out"
	if st == _hammer_state:
		return
	_hammer_state = st
	match st:
		"cooldown":
			_hammer_icon.base = UISkin.texture("hud_mjolnir_ready")
			_hammer_icon.tint = Color(0.45, 0.45, 0.5)
			_hammer_label.text = tr("ПЕРЕЗАРЯДКА %.1f с · ПОЙМАЙ ИДЕАЛЬНО — БЫСТРЕЕ") % m.cooldown_left
			_hammer_label.label_settings.font_color = Color(0.75, 0.75, 0.8)
		"hand":
			_hammer_icon.base = UISkin.texture("hud_mjolnir_ready")
			_hammer_icon.tint = Color.WHITE
			_hammer_label.text = GameSettings.throw_hint(tr("МЬЁЛЬНИР В РУКЕ · ПКМ"))
			_hammer_label.label_settings.font_color = UIStyle.ICE
			_hammer_icon.pop()
		"out":
			_hammer_icon.base = UISkin.texture("hud_mjolnir_thrown")
			_hammer_icon.tint = Color.WHITE
			_hammer_label.text = GameSettings.throw_hint(tr("ЛЕТИТ · ПКМ — ВЕРНУТЬ"))
			_hammer_label.label_settings.font_color = Color(1, 0.85, 0.4)
		"stuck":
			_hammer_icon.base = UISkin.texture("hud_mjolnir_thrown")
			_hammer_icon.tint = Color(1.0, 0.8, 0.55)
			_hammer_label.text = GameSettings.throw_hint(tr("ВОТКНУТ · ПКМ — ВЕРНУТЬ"))
			_hammer_label.label_settings.font_color = Color(1, 0.7, 0.35)
		"return":
			_hammer_icon.base = UISkin.texture("hud_mjolnir_returning")
			_hammer_icon.tint = Color.WHITE
			_hammer_label.text = tr("ВОЗВРАЩАЕТСЯ · ЛОВИ!")
			_hammer_label.label_settings.font_color = UIStyle.ICE.lightened(0.3)

## Шкала высоты в рукояти молота: сколько метров будет падение ударом-приземлением
func _update_slam_meter() -> void:
	if not bool(GameSettings.get_value("hud", "slam_meter")) or player.is_on_floor() or player.is_dead:
		_slam_meter.visible = false
		return
	var peak: float = player.get("_air_peak_y") if player.get("_air_peak_y") != null else player.global_position.y
	var ground := player.global_position.y - 40.0
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(player.global_position, player.global_position + Vector3.DOWN * 40.0, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		ground = (hit.position as Vector3).y
	var fall := maxf(peak, player.global_position.y) - ground
	_slam_meter.visible = fall >= slam_meter_min_height or player.is_slamming
	if _slam_meter.visible:
		var big := player.big_slam_height
		_slam_meter.value = clampf(fall / maxf(big, 0.1), 0.0, 1.0)
		_slam_meter.fill_modulate = Color(1.0, 0.9, 0.5) if fall >= big else Color.WHITE

func _on_hammer_state(_in_hand: bool) -> void:
	_hammer_state = ""
	if player and is_instance_valid(player):
		_update_hammer()

func _on_hurt(_amount: float) -> void:
	_hurt_rect.color.a = 0.35

func _on_glory_changed(total: int) -> void:
	if _glory_label and total > _glory_shown + 5:
		var tw := _glory_label.create_tween()
		_glory_label.pivot_offset = _glory_label.size * Vector2(1, 0.5)
		tw.tween_property(_glory_label, "scale", Vector2(1.15, 1.15), 0.06)
		tw.tween_property(_glory_label, "scale", Vector2.ONE, 0.15)

## Руны — сжатый ряд иконок категорий (GDD 18); руна значком в углу, уровень цифрой.
## Полный список с названиями — журнал в паузе.
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
		var lvl := mini(counts[rr.id], Run.RUNE_MAX_LEVEL)
		var icon := HudIcon.make(UISkin.rune_category_icon(rr.category), rune_icon_size)
		icon.badge = rr.glyph + (str(lvl) if lvl > 1 else "")
		icon.badge_color = rr.color.lightened(0.2)
		if rr.cursed:
			icon.tint = Color(0.8, 0.55, 1.0)
			icon.badge_color = Color(0.85, 0.5, 1.0)
		icon.tooltip_text = tr(rr.title)
		_runes_box.add_child(icon)

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
	_room_args = [index, total, title, boss]
	title = tr(title)
	_room_label.text = (tr("ФИНАЛ: %s") % title) if boss else (tr("ЗАЛ %d / %d · %s") % [index, total, title])
	_boss_box.visible = false
	_boss = null
	toast(title.to_upper())

func set_enemy_count(alive: int) -> void:
	_enemies_alive = alive
	_enemies_label.text = tr("Врагов: %d") % alive if alive > 0 else ""

func show_boss(boss: Enemy) -> void:
	_boss = boss
	_boss_box.visible = true
	_boss_bar.value = 1.0
	# Имя на полосе — из метаданных врага (мини-босс), иначе финальный босс
	_boss_title.text = tr(str(boss.get_meta("boss_title", DEFAULT_BOSS_TITLE)))
	boss.died.connect(func(_e: Enemy) -> void: _boss_box.visible = false)

func fade_in(time: float = 0.35) -> void:
	_fade_rect.color.a = 1.0
	var tw := _fade_rect.create_tween()
	tw.tween_property(_fade_rect, "color:a", 0.0, time)

func fade_out(time: float = 0.25) -> void:
	var tw := _fade_rect.create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, time)
