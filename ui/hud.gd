extends CanvasLayer
class_name HUD
## Интерфейс боя (GDD 18, П6 — «в бою только главное», макет B `docs/mockups/hud_B_chosen.png`) на скине UISkin.
## Всё внизу по центру в одну линию: слева здоровье в рамке со шлемом (hud_hp_*), по центру Мьёльнир
## (hud_mjolnir_*: в руке / летит / воткнут / возвращается; перезарядка — затемнение иконки) и руны-камни
## (hud_dash_*), справа шкала стиля «ДОСТОЙНО!» (ui/style_hud.gd). Над линией — один пузырь реплик.
## Слава и серебро — только всплывают «+N» справа на 2 с; суммы, трейты и руны — по Tab (ui/build_screen.gd).
## Связка сработала — короткая вспышка её иконки над молотом. Центр экрана — только прицел (и кольцо хвата).
## Ещё: полоса босса, индикаторы за экраном, линии скорости, оружие (ui/weapon_hud.gd — на 2 с при смене).
## Раскладка якорями от низа по центру: 1280×720 и 1920×1080 (stretch canvas_items) выглядят одинаково.

## Высота полосы HP (ширина — по пропорциям рамки 768×192)
@export var hp_bar_height: float = 78.0
## Размер иконки Мьёльнира и камня рывка
@export var hammer_icon_size: float = 72.0
@export var dash_icon_size: float = 40.0
## Базовый размер прицела (px; множитель — настройки)
@export var crosshair_base_size: float = 30.0
## Сколько секунд висит «+N СЛАВЫ» / «+N» серебра после последнего получения
@export var gain_show_time: float = 2.0
## Вспышка иконки сработавшей связки: сколько держится и не чаще раза в combo_flash_gap с на связку
@export var combo_flash_time: float = 1.0
@export var combo_flash_gap: float = 4.0
## Нижняя линия: половина ширины (от центра до края HP/шкалы стиля), px
@export var row_half_width: float = 505.0
## Промежуток от центра до внутреннего края HP/шкалы стиля, px
@export var row_inner_gap: float = 195.0

const CROSSHAIR_IDS := {"dot": "crosshair_dot", "cross": "crosshair_cross", "circle": "crosshair_circle"}
const CLASSIC_CROSSHAIR := "res://sprites/crosshair.png"
## Имя на полосе босса, если враг не задал своё (ключ перевода)
const DEFAULT_BOSS_TITLE := "ХРИМТУРС ПОЖИРАТЕЛЬ ГЕРОЕВ"
const SILVER_COLOR := Color(0.86, 0.9, 1.0)

var player: Player

var _hp_bar: SkinBar
var _hp_label: Label
var _dash_box: HBoxContainer
var _dash_pips: Array[HudIcon] = []
var _hammer_icon: HudIcon
var _hammer_state: String = ""
## Бросок на перезарядке (осечка): до этого момента (мс) иконка молота красная
var _hammer_flash_until: int = 0
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
var _offscreen: OffscreenIndicators
var _odin_name: Label
## Всплывающие «+N СЛАВЫ» и «+N» серебра (П6): сумма за последние gain_show_time с
var _glory_gain: Label
var _heal_gain: Label
var _heal_left: float = 0.0
var _heal_acc: float = 0.0
var _silver_gain: HBoxContainer
var _silver_gain_label: Label
var _glory_seen: int = 0
var _silver_seen: int = 0
var _glory_acc: int = 0
var _silver_acc: int = 0
var _glory_left: float = 0.0
var _silver_left: float = 0.0
## Вспышка иконки связки
var _combo_flash: HudIcon
## Слова-команды «КРУШИ!», «БЕГИ!»… (ui/command_words.gd)
var commands: CommandWords
var _combo_left: float = 0.0
var _combo_last: Dictionary = {}
## Для перевода на лету (смена языка из паузы): последние аргументы set_room и число врагов
var _room_args: Array = []
var _enemies_alive: int = 0

func _ready() -> void:
	layer = 5
	_build()
	Run.glory_changed.connect(_on_glory_changed)
	Run.silver_changed.connect(_on_silver_changed)
	Run.mjolnir_combo_fired.connect(_on_combo_fired)
	Odin.line_spoken.connect(show_odin_line)
	GameSettings.events.changed.connect(_on_setting_changed)
	_glory_seen = Run.glory
	_silver_seen = Run.silver

func bind_player(p: Player) -> void:
	player = p
	player.health_changed.connect(_on_health_changed)
	player.slam_healed.connect(_on_slam_healed)
	player.dash_charges_changed.connect(_on_dash_changed)
	player.hurt.connect(_on_hurt)
	player.slam_unavailable.connect(func() -> void: toast(tr("НУЖЕН ВТОРОЙ ПРЫЖОК")))
	player.mjolnir.state_changed.connect(_on_hammer_state)
	# Бросок на перезарядке: иконка молота вспыхивает красным и дёргается
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
	if commands:
		commands.player = p
	# Слоты оружия (на 2 с при смене/подборе), патроны — пока в руках ствол, подсказка подбора — ui/weapon_hud.gd
	WeaponHUD.attach(self, p)
	# Шкала стиля «ДОСТОЙНО!» (ранг, комикс-подпись) справа в нижней линии — ui/style_hud.gd (блок Б3)
	var sh := StyleHUD.attach(self, p)
	if sh:
		sh.place(row_inner_gap, row_half_width)

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

	# Нижняя линия, слева: здоровье в рамке со шлемом
	_hp_bar = SkinBar.new()
	_hp_bar.frame_id = "hud_hp_frame"
	_hp_bar.fill_id = "hud_hp_fill"
	_anchor(_hp_bar, Control.PRESET_CENTER_BOTTOM, -row_half_width, -hp_bar_height - 8, -row_inner_gap, -8)
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hp_bar)
	# «+N» зелёным над полосой HP — лечение ударом-приземлением (партия 12), на gain_show_time
	_heal_gain = UIStyle.label("", 24, Color(0.45, 1.0, 0.5), 7)
	_heal_gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heal_gain.modulate.a = 0.0
	_anchor(_heal_gain, Control.PRESET_CENTER_BOTTOM, -row_half_width, -hp_bar_height - 44, -row_inner_gap, -hp_bar_height - 8)
	root.add_child(_heal_gain)
	_hp_label = UIStyle.label("100", 18, UIStyle.TEXT, 6)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_bar.add_child(_hp_label)
	_hp_bar.resized.connect(_place_hp_label)
	_place_hp_label.call_deferred()

	# По центру: Мьёльнир и руны-камни справа от него
	var mid := HBoxContainer.new()
	_anchor(mid, Control.PRESET_CENTER_BOTTOM, -row_inner_gap + 70, -hammer_icon_size - 14, row_inner_gap - 30, -14)
	mid.alignment = BoxContainer.ALIGNMENT_BEGIN
	mid.add_theme_constant_override("separation", 6)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mid)
	_hammer_icon = HudIcon.make(UISkin.texture("hud_mjolnir_ready"), hammer_icon_size)
	mid.add_child(_hammer_icon)
	_dash_box = HBoxContainer.new()
	_dash_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_dash_box.add_theme_constant_override("separation", 2)
	_dash_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dash_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(_dash_box)

	# Над молотом: «ИДЕАЛЬНЫЙ ХВАТ ×2» и полоска удержания ПКМ (иконки трейтов — только по Tab)
	_mjolnir_traits = MjolnirTraitsHud.new()
	root.add_child(_mjolnir_traits)
	# Вспышка иконки сработавшей связки — над молотом
	_combo_flash = HudIcon.make(null, 56)
	_anchor(_combo_flash, Control.PRESET_CENTER_BOTTOM, -row_inner_gap + 78, -hammer_icon_size - 76, -row_inner_gap + 134, -hammer_icon_size - 20)
	_combo_flash.modulate.a = 0.0
	root.add_child(_combo_flash)

	# Справа по центру: «+25 СЛАВЫ» и «+6» серебра — всплывают на gain_show_time
	var gains := VBoxContainer.new()
	_anchor(gains, Control.PRESET_CENTER_RIGHT, -420, -70, -24, 30)
	gains.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	gains.alignment = BoxContainer.ALIGNMENT_CENTER
	gains.add_theme_constant_override("separation", 0)
	gains.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(gains)
	_glory_gain = UIStyle.label("", 28, UIStyle.GOLD, 8)
	_glory_gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_glory_gain.modulate.a = 0.0
	gains.add_child(_glory_gain)
	_silver_gain = HBoxContainer.new()
	_silver_gain.alignment = BoxContainer.ALIGNMENT_END
	_silver_gain.add_theme_constant_override("separation", 6)
	_silver_gain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_silver_gain.modulate.a = 0.0
	gains.add_child(_silver_gain)
	var silver_icon := UISkin.texture("hud_silver")
	if silver_icon:
		_silver_gain.add_child(HudIcon.make(silver_icon, 30))
	_silver_gain_label = UIStyle.label("", 22, SILVER_COLOR, 6)
	_silver_gain.add_child(_silver_gain_label)

	# Слова-команды (П10) — крупно по центру сверху
	commands = CommandWords.new()
	commands.name = "CommandWords"
	root.add_child(commands)

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

	# Пузырь реплик — один, внизу по центру над линией HUD (Один здесь, остальные — BarkBubble на том же месте)
	_odin_panel = UIStyle.panel(Color(0.05, 0.05, 0.07, 0.82), Color(UIStyle.GOLD, 0.5))
	_anchor(_odin_panel, Control.PRESET_CENTER_BOTTOM, -BarkBubble.WIDTH * 0.5, -BarkBubble.BOTTOM - 64, BarkBubble.WIDTH * 0.5, -BarkBubble.BOTTOM)
	_odin_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_odin_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
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
	_odin_label.custom_minimum_size = Vector2(BarkBubble.WIDTH - 60.0, 0)
	ob.add_child(_odin_label)

	# Короткая подсказка — сверху, под полосой босса (центр экрана — только прицел)
	_toast_label = UIStyle.label("", 28, UIStyle.GOLD, 8)
	_anchor(_toast_label, Control.PRESET_CENTER_TOP, -400, 104, 400, 150)
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
		_fit_odin_text()
		if key == "language":
			_retranslate()

## Смена языка посреди забега: подписи, которые сами не обновляются каждый кадр
func _retranslate() -> void:
	_odin_name.text = tr("ОДИН")
	if _glory_acc > 0:
		_glory_gain.text = tr("+%d СЛАВЫ") % _glory_acc
	if _boss and is_instance_valid(_boss):
		_boss_title.text = tr(str(_boss.get_meta("boss_title", DEFAULT_BOSS_TITLE)))

## На паузе (выбор руны/трейта/награды, ларёк, меню паузы, экран сборки) HUD стоит, и его твин тоже: пузырь
## застывал видимым под затемнением. Прячем до снятия паузы.
func _notification(what: int) -> void:
	if _odin_panel == null:
		return
	if what == NOTIFICATION_PAUSED:
		_odin_panel.visible = false
	elif what == NOTIFICATION_UNPAUSED:
		_odin_panel.visible = true

func _process(delta: float) -> void:
	if player and is_instance_valid(player):
		_speed_mat.set_shader_parameter("intensity", player.camera_fx.speed_lines)
		_update_hammer()
	_hurt_rect.color.a = maxf(0.0, _hurt_rect.color.a - delta * 1.6)
	if _boss and is_instance_valid(_boss):
		_boss_bar.value = maxf(0.0, _boss.health) / _boss.max_health
	_glory_left = _fade_gain(_glory_gain, _glory_left, delta)
	_heal_left = _fade_gain(_heal_gain, _heal_left, delta)
	if _heal_left <= 0.0:
		_heal_acc = 0.0
	if _glory_left <= 0.0:
		_glory_acc = 0
	_silver_left = _fade_gain(_silver_gain, _silver_left, delta)
	if _silver_left <= 0.0:
		_silver_acc = 0
	if _combo_left > 0.0:
		_combo_left -= delta
		_combo_flash.modulate.a = clampf(_combo_left / 0.3, 0.0, 1.0)

## Всплывашка: видна, пока left > 0, последние 0.4 с гаснет
func _fade_gain(c: Control, left: float, delta: float) -> float:
	if left <= 0.0:
		return 0.0
	left = maxf(0.0, left - delta)
	c.modulate.a = clampf(left / 0.4, 0.0, 1.0)
	return left

func _on_health_changed(current: float, maximum: float) -> void:
	_hp_bar.value = current / maxf(maximum, 1.0)
	_place_hp_label()
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
			var icon_size := minf(dash_icon_size, (150.0 - maxf(0, maximum - 1) * 2.0) / maxf(1, maximum))
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

## Мьёльнир: в руке / летит / воткнут / возвращается (иконки комплекта); перезарядка — затемнение иконки
func _update_hammer() -> void:
	var m := player.mjolnir
	var st := "hand"
	var cd := 0.0
	if m.in_hand and m.cooldown_left > 0.0:
		st = "cooldown"
		cd = m.cooldown_left / maxf(m.cooldown_total, 0.01)
	_hammer_icon.shade = cd
	var red := Time.get_ticks_msec() < _hammer_flash_until
	_hammer_icon.shade_color = Color(0.55, 0.06, 0.04, 0.85) if red else Color(0.08, 0.09, 0.13, 0.82)
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
			_hammer_icon.tint = Color.WHITE
		"hand":
			_hammer_icon.base = UISkin.texture("hud_mjolnir_ready")
			_hammer_icon.tint = Color.WHITE
			_hammer_icon.pop()
		"out":
			_hammer_icon.base = UISkin.texture("hud_mjolnir_thrown")
			_hammer_icon.tint = Color.WHITE
		"stuck":
			_hammer_icon.base = UISkin.texture("hud_mjolnir_thrown")
			_hammer_icon.tint = Color(1.0, 0.8, 0.55)
		"return":
			_hammer_icon.base = UISkin.texture("hud_mjolnir_returning")
			_hammer_icon.tint = Color.WHITE

func _on_hammer_state(_in_hand: bool) -> void:
	_hammer_state = ""
	if player and is_instance_valid(player):
		_update_hammer()

func _on_hurt(_amount: float) -> void:
	_hurt_rect.color.a = 0.35

## Слава выросла — «+N СЛАВЫ» на gain_show_time (повторные получения складываются); сумма — по Tab
func _on_glory_changed(total: int) -> void:
	var gain := total - _glory_seen
	_glory_seen = total
	if gain <= 0 or _glory_gain == null:
		return
	_glory_acc += gain
	_glory_gain.text = tr("+%d СЛАВЫ") % _glory_acc
	_glory_left = gain_show_time
	_glory_gain.modulate.a = 1.0
	_punch(_glory_gain)

func _on_slam_healed(amount: float) -> void:
	if _heal_gain == null:
		return
	_heal_acc += amount
	_heal_gain.text = "+%d HP" % int(round(_heal_acc))
	_heal_left = gain_show_time
	_heal_gain.modulate.a = 1.0
	_punch(_heal_gain)

func _on_silver_changed(total: int) -> void:
	var gain := total - _silver_seen
	_silver_seen = total
	if gain <= 0 or _silver_gain == null:
		return
	_silver_acc += gain
	_silver_gain_label.text = "+%d" % _silver_acc
	_silver_left = gain_show_time
	_silver_gain.modulate.a = 1.0
	_punch(_silver_gain)

func _punch(c: Control) -> void:
	c.pivot_offset = c.size * Vector2(1, 0.5)
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(1.15, 1.15), 0.06)
	tw.tween_property(c, "scale", Vector2.ONE, 0.15)

## Связка сработала — её иконка коротко вспыхивает над молотом (не чаще раза в combo_flash_gap на связку)
func _on_combo_fired(combo: MjolnirTrait) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_combo_last.get(combo.id, -100.0)) < combo_flash_gap:
		return
	_combo_last[combo.id] = now
	var tex := UISkin.trait_icon(str(combo.id))
	if tex == null:
		return
	_combo_flash.base = tex
	_combo_flash.modulate.a = 1.0
	_combo_left = combo_flash_time
	_combo_flash.pop()

func show_odin_line(text: String) -> void:
	Perf.mark("odin_line")
	if text == "" or _odin_label == null:
		return
	# Один пузырь: реплика Одина убирает пузырь другого говорящего
	var other := Dialogue.get("_bubble") as BarkBubble
	if is_instance_valid(other):
		other.hide_now()
	_odin_label.text = text
	_fit_odin_text()
	if _odin_tween and _odin_tween.is_valid():
		_odin_tween.kill()
	_odin_tween = _odin_panel.create_tween()
	_odin_tween.tween_property(_odin_panel, "modulate:a", 1.0, 0.2)
	_odin_tween.tween_interval(clampf(1.6 + text.length() * 0.035, 2.0, 3.5))
	_odin_tween.tween_property(_odin_panel, "modulate:a", 0.0, 0.4)

## Перенос строк Label в контейнере может обрезать последнюю строку: высоту считаем по шрифту на ширине текста
## (плюс обводка), а рамка растёт вверх (grow_vertical BEGIN)
func _fit_odin_text() -> void:
	var ls := _odin_label.label_settings
	var w := _odin_label.custom_minimum_size.x
	var extent := ls.font.get_multiline_string_size(_odin_label.text, HORIZONTAL_ALIGNMENT_LEFT, w, ls.font_size)
	_odin_label.custom_minimum_size = Vector2(w, extent.y + ls.outline_size * 2.0 + 6.0)
	# Рамка сама не сжимается: ставим верх по нужной высоте, низ — на месте
	_odin_panel.offset_top = _odin_panel.offset_bottom - _odin_panel.get_combined_minimum_size().y

## Убрать пузырь Одина сразу (заговорил другой)
func hide_odin_line() -> void:
	if _odin_tween and _odin_tween.is_valid():
		_odin_tween.kill()
	if _odin_panel:
		_odin_panel.modulate.a = 0.0

func toast(text: String) -> void:
	_toast_label.text = text
	var tw := _toast_label.create_tween()
	tw.tween_property(_toast_label, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.4)
	tw.tween_property(_toast_label, "modulate:a", 0.0, 0.4)

## Новый зал: название — подсказкой сверху (номер зала и путь — по Tab)
func set_room(index: int, total: int, title: String, boss: bool) -> void:
	_room_args = [index, total, title, boss]
	_boss_box.visible = false
	_boss = null
	toast(tr(title).to_upper())

func set_enemy_count(alive: int) -> void:
	_enemies_alive = alive

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
