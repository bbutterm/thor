extends Control
class_name RageHUD
## Шкала Ярости (GDD 8, 18) — внизу по центру: копится за убийства в серии, тонкая полоска под ней —
## сколько осталось до сброса серии (окно 3 с). В берсерке — «БЕРСЕРК» с таймером и красная виньетка.
## Картинки (UI_PROMPTS.txt 3.3, 5.13): sprites/ui/hud/hud_rage_frame.png + hud_rage_fill.png,
## sprites/vfx/vfx_rage_vignette.png; нет файлов — процедурная заглушка. Подключение: RageHUD.attach(hud, player).

const FRAME_TEX := "res://sprites/ui/hud/hud_rage_frame.png"
const FILL_TEX := "res://sprites/ui/hud/hud_rage_fill.png"
const VIGNETTE_TEX := "res://sprites/vfx/vfx_rage_vignette.png"
const RAGE_COLOR := Color(1.0, 0.45, 0.12)
const BERSERK_COLOR := Color(1.0, 0.18, 0.08)

## Ширина шкалы, px
@export var bar_width: float = 380.0
## Насколько видна виньетка в берсерке (0..1)
@export var vignette_alpha: float = 0.75

var rage: Rage
var _bar: Range
var _window_bar: ProgressBar
var _label: Label
var _vignette: TextureRect
var _fill_style: StyleBoxFlat
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
	_vignette.texture = load(VIGNETTE_TEX) if ResourceLoader.exists(VIGNETTE_TEX) else _make_vignette()
	_vignette.modulate.a = 0.0
	add_child(_vignette)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -bar_width * 0.5
	box.offset_right = bar_width * 0.5
	box.offset_top = -92
	box.offset_bottom = -22
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 3)
	add_child(box)
	_label = UIStyle.label("ЯРОСТЬ", 16, Color(RAGE_COLOR, 0.85), 4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_label)
	if ResourceLoader.exists(FRAME_TEX) and ResourceLoader.exists(FILL_TEX):
		var tp := TextureProgressBar.new()
		tp.texture_over = load(FRAME_TEX)
		tp.texture_progress = load(FILL_TEX)
		tp.nine_patch_stretch = true
		tp.custom_minimum_size = Vector2(bar_width, 26)
		tp.max_value = 1.0
		tp.step = 0.0
		tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar = tp
	else:
		var pb := ProgressBar.new()
		pb.custom_minimum_size = Vector2(bar_width, 16)
		pb.show_percentage = false
		pb.max_value = 1.0
		pb.step = 0.0
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.55)
		bg.set_corner_radius_all(5)
		bg.border_color = Color(RAGE_COLOR, 0.45)
		bg.set_border_width_all(1)
		_fill_style = StyleBoxFlat.new()
		_fill_style.bg_color = RAGE_COLOR
		_fill_style.set_corner_radius_all(5)
		pb.add_theme_stylebox_override("background", bg)
		pb.add_theme_stylebox_override("fill", _fill_style)
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar = pb
	box.add_child(_bar)
	# Окно серии: сколько осталось до сброса
	_window_bar = ProgressBar.new()
	_window_bar.custom_minimum_size = Vector2(bar_width, 3)
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
	box.add_child(_window_bar)
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
	if _fill_style:
		_fill_style.bg_color = BERSERK_COLOR if active else RAGE_COLOR.lerp(Color(1, 0.75, 0.2), v)
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
