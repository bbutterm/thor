extends Control
class_name RageHUD
## Шкала Ярости (GDD 8, 18) — внизу по центру: копится за убийства в серии, тонкая полоска под ней —
## сколько осталось до сброса серии (окно 3 с). В берсерке — «БЕРСЕРК» с таймером и красная виньетка.
## Картинки комплекта (UISkin): рамка hud_rage_frame + заливка hud_rage_fill по fill_rect (SkinBar),
## виньетка vfx_rage_vignette; нет файлов — процедурная заглушка. Подключение: RageHUD.attach(hud, player).

const RAGE_COLOR := Color(1.0, 0.45, 0.12)
const BERSERK_COLOR := Color(1.0, 0.18, 0.08)

## Ширина шкалы, px (высота — по пропорциям рамки 768×192)
@export var bar_width: float = 340.0
## Насколько видна виньетка в берсерке (0..1)
@export var vignette_alpha: float = 0.75

var rage: Rage
var _bar: SkinBar
var _window_bar: ProgressBar
var _label: Label
var _vignette: TextureRect
var _pulse: float = 0.0
var _shown: float = 0.0

static func attach(hud: CanvasLayer, p: Player) -> RageHUD:
	if p == null or p.rage == null:
		return null
	var r := RageHUD.new()
	r.name = "RageHUD"
	# Под затемнением между залами (как WeaponHUD)
	r.z_index = -1
	hud.add_child(r)
	r.bind(p.rage)
	return r

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.full_rect(self)
	_build()

func _build() -> void:
	# Виньетка берсерка — на весь экран, под шкалой
	_vignette = TextureRect.new()
	UIStyle.full_rect(_vignette)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	var vig := UISkin.texture("vfx_rage_vignette")
	_vignette.texture = vig if vig else _make_vignette()
	_vignette.modulate.a = 0.0
	add_child(_vignette)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -bar_width * 0.5
	box.offset_right = bar_width * 0.5
	box.offset_top = -bar_width * 0.25 - 30
	box.offset_bottom = -8
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 3)
	add_child(box)
	_label = UIStyle.label("ЯРОСТЬ", 16, Color(RAGE_COLOR, 0.85), 4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_label)
	_bar = SkinBar.new()
	_bar.frame_id = "hud_rage_frame"
	_bar.fill_id = "hud_rage_fill"
	_bar.flat_color = RAGE_COLOR
	_bar.trail_delay = 0.0
	_bar.custom_minimum_size = Vector2(bar_width, bar_width * 0.25)
	_bar.value = 0.0
	box.add_child(_bar)
	# Окно серии: сколько осталось до сброса
	_window_bar = ProgressBar.new()
	_window_bar.show_percentage = false
	_window_bar.max_value = 1.0
	_window_bar.step = 0.0
	var wbg := StyleBoxFlat.new()
	wbg.bg_color = Color(0, 0, 0, 0.0)
	var wfg := StyleBoxFlat.new()
	wfg.bg_color = Color(1, 0.85, 0.6, 0.7)
	_window_bar.add_theme_stylebox_override("background", wbg)
	_window_bar.add_theme_stylebox_override("fill", wfg)
	_window_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Тонкая полоска окна — по нижнему краю заливки рамки
	_bar.add_child(_window_bar)
	_bar.resized.connect(func() -> void:
		var a := _bar.fill_area()
		_window_bar.position = Vector2(a.position.x, a.end.y - 4)
		_window_bar.size = Vector2(a.size.x, 4))
	_apply(0.0, false)

## Радиальный градиент: прозрачный центр, красные края
static func _make_vignette() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(1, 0.2, 0.05, 0.0), Color(1, 0.2, 0.05, 0.0), Color(0.85, 0.08, 0.02, 0.9)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 1.0)
	t.width = 256
	t.height = 256
	return t

func bind(r: Rage) -> void:
	rage = r
	rage.changed.connect(_apply)
	rage.berserk_started.connect(func() -> void: _pulse = 1.0)
	_apply(rage.value(), rage.active)

func _apply(v: float, active: bool) -> void:
	if _bar == null:
		return
	_shown = v
	_bar.value = v
	_bar.fill_modulate = Color(1.3, 0.75, 0.6) if active else Color.WHITE
	if active and rage:
		_label.text = "БЕРСЕРК  %.1f" % maxf(rage.berserk_left, 0.0)
		_label.label_settings.font_color = BERSERK_COLOR.lightened(0.3)
	else:
		_label.text = "ЯРОСТЬ" if rage == null or rage.kills == 0 else "ЯРОСТЬ  %d / %d" % [rage.kills, rage.kills_to_full]
		_label.label_settings.font_color = Color(RAGE_COLOR, 0.85)
	# Пустая шкала вне боя — приглушена
	modulate.a = 1.0 if active or v > 0.0 else 0.55

func _process(delta: float) -> void:
	if rage == null:
		return
	_window_bar.value = rage.window_left() / maxf(rage.kill_window, 0.01)
	_pulse = maxf(0.0, _pulse - delta * 1.5)
	var target := vignette_alpha * (0.75 + 0.25 * sin(Time.get_ticks_msec() / 130.0)) if rage.active else 0.0
	_vignette.modulate.a = lerpf(_vignette.modulate.a, maxf(target, _pulse), clampf(delta * 8.0, 0.0, 1.0))
