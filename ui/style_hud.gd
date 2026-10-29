extends Control
class_name StyleHUD
## Шкала стиля «ДОСТОЙНО!» (блок Б3, GDD 8, 18) — справа в нижней линии HUD (П6, макет B; place()).
## Сверху — комикс-подпись ранга (Скуф → Сойдёт → Неплохо → Достойно → ДОСТОЙНЕЙШИЙ!) на рисованном «взрыве»
## комплекта (comic_burst_01..06, перекрашен в цвет ранга через modulate — без новых материалов), при повышении
## ранга подпись «бьёт» масштабом и меняет взрыв. Под ней — рамка hud_rage_frame + заливка hud_rage_fill
## (SkinBar) с засечками порогов рангов; цвет заливки — по рангу, справа на заливке — множитель Славы ранга.
## В берсерке — «БЕРСЕРК 5.2» с таймером, заливка пульсирует, виньетка (рисованную показывает VfxScreen).
## Шрифт подписи: на английском — Bangers (комиксовый, только латиница), на русском — Russo One.
## Подключение: StyleHUD.attach(hud, player).

const RANK_COLORS := [Color(0.62, 0.6, 0.56), Color(0.86, 0.76, 0.5), Color(1.0, 0.6, 0.2), Color(1.0, 0.8, 0.22), Color(1.0, 0.24, 0.1)]
const FILL_TINT := [Color(0.5, 0.5, 0.5), Color(0.85, 0.8, 0.7), Color(1.0, 0.85, 0.7), Color(1.15, 1.0, 0.75), Color(1.35, 0.8, 0.6)]
const COMIC_FONT := "res://fonts/Bangers-Regular.ttf"
const BURSTS := 6

## Ширина шкалы, px (высота — по пропорциям рамки 768×192)
@export var bar_width: float = 340.0
## Высота подписи ранга, px
@export var caption_height: float = 58.0
## Размер «взрыва» под подписью, px
@export var burst_size: Vector2 = Vector2(210, 92)
## Насколько видна виньетка в берсерке (0..1)
@export var vignette_alpha: float = 0.75
## Удар подписи при повышении ранга: на сколько больше и как быстро гаснет (в секунду)
@export var punch_scale: float = 0.5
@export var punch_decay: float = 3.0

var style: StyleMeter
var _bar: SkinBar
var _ticks: Control
var _caption: Control
var _burst: TextureRect
var _rank_label: Label
var _glory_label: Label
var _vignette: TextureRect
var _pulse: float = 0.0
var _punch: float = 0.0
var _burst_idx: int = 1
var _shown_rank: int = -1
var _box: VBoxContainer

static func attach(hud: CanvasLayer, p: Player) -> StyleHUD:
	if p == null or p.style == null:
		return null
	var r := StyleHUD.new()
	r.name = "StyleHUD"
	# Под затемнением между залами (как WeaponHUD)
	r.z_index = -1
	hud.add_child(r)
	r.bind(p.style)
	return r

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.full_rect(self)
	_build()
	GameSettings.events.changed.connect(_on_setting_changed)

func _build() -> void:
	# Виньетка берсерка — на весь экран, под шкалой (VfxScreen прячет её и рисует свою)
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
	_box = box
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -bar_width * 0.5
	box.offset_right = bar_width * 0.5
	box.offset_top = -bar_width * 0.25 - caption_height - 10
	box.offset_bottom = -8
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", -6)
	add_child(box)

	# Подпись ранга: «взрыв» + слово, масштаб вокруг центра
	_caption = Control.new()
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.custom_minimum_size = Vector2(bar_width, caption_height)
	box.add_child(_caption)
	_burst = TextureRect.new()
	_burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_burst.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_burst.stretch_mode = TextureRect.STRETCH_SCALE
	_burst.set_anchors_preset(Control.PRESET_CENTER)
	_burst.offset_left = -burst_size.x * 0.5
	_burst.offset_right = burst_size.x * 0.5
	_burst.offset_top = -burst_size.y * 0.5 + 6.0
	_burst.offset_bottom = burst_size.y * 0.5 + 6.0
	_burst.pivot_offset = burst_size * 0.5
	_caption.add_child(_burst)
	_rank_label = UIStyle.label("", 30, Color.WHITE, 10)
	_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rank_label.label_settings.outline_color = Color(0.05, 0.02, 0.02, 1.0)
	_rank_label.label_settings.shadow_size = 0
	_rank_label.label_settings.shadow_color = Color(0, 0, 0, 0.6)
	_rank_label.label_settings.shadow_offset = Vector2(3, 4)
	_caption.add_child(_rank_label)
	UIStyle.full_rect(_rank_label)
	_caption.resized.connect(func() -> void: _caption.pivot_offset = _caption.size * 0.5)
	_apply_font()

	_bar = SkinBar.new()
	_bar.frame_id = "hud_rage_frame"
	_bar.fill_id = "hud_rage_fill"
	_bar.flat_color = RANK_COLORS[2]
	_bar.trail_delay = 0.0
	_bar.custom_minimum_size = Vector2(bar_width, bar_width * 0.25)
	_bar.value = 0.0
	box.add_child(_bar)
	# Засечки порогов рангов — по области заливки рамки
	_ticks = Control.new()
	_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticks.draw.connect(_draw_ticks)
	_bar.add_child(_ticks)
	# Множитель Славы / таймер берсерка — мелко по правому краю заливки
	_glory_label = UIStyle.label("", 14, Color(UIStyle.GOLD, 0.95), 5)
	_glory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_glory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar.add_child(_glory_label)
	_bar.resized.connect(_layout_bar)
	_layout_bar.call_deferred()

## Засечки и подпись — по области заливки рамки (известна, когда SkinBar прочитал манифест)
func _layout_bar() -> void:
	var a := _bar.fill_area()
	_ticks.position = a.position
	_ticks.size = a.size
	_ticks.queue_redraw()
	_glory_label.position = a.position + Vector2(0, -2)
	_glory_label.size = a.size - Vector2(6, 0)

## Радиальный градиент: прозрачный центр, красные края (нет картинки комплекта)
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

func _draw_ticks() -> void:
	if style == null:
		return
	var h := _ticks.size.y
	for r in range(1, StyleMeter.TOP):
		var x := roundf(_ticks.size.x * style.rank_fraction(r))
		var reached := style.active or style.rank >= r
		_ticks.draw_line(Vector2(x, -2), Vector2(x, h + 2), Color(0, 0, 0, 0.85), 4.0)
		_ticks.draw_line(Vector2(x, 0), Vector2(x, h), Color(1, 0.95, 0.75, 0.95) if reached else Color(1, 1, 1, 0.35), 2.0)

## Встать в нижнюю линию HUD: от inner до outer px вправо от центра экрана (ширина = ширина шкалы)
func place(inner: float, outer: float) -> void:
	bar_width = outer - inner
	_box.offset_left = inner
	_box.offset_right = outer
	_box.offset_top = -bar_width * 0.25 - caption_height - 10
	_caption.custom_minimum_size = Vector2(bar_width, caption_height)
	_bar.custom_minimum_size = Vector2(bar_width, bar_width * 0.25)

func bind(s: StyleMeter) -> void:
	style = s
	style.changed.connect(_apply)
	style.rank_changed.connect(_on_rank_changed)
	style.berserk_started.connect(func() -> void: _pulse = 1.0)
	_apply(style.value(), style.active)

## Шрифт подписи — по языку (Bangers без кириллицы)
func _apply_font() -> void:
	var en := not I18n.is_default()
	_rank_label.label_settings.font = load(COMIC_FONT) if en else UIStyle.font()
	_rank_label.label_settings.font_size = 38 if en else 28

func _on_setting_changed(section: String, key: String) -> void:
	if section == "text" and key == "language":
		_apply_font()
		_shown_rank = -1
		if style:
			_apply(style.value(), style.active)

func _on_rank_changed(rank: int, previous: int) -> void:
	if rank > previous:
		_punch = 1.0
		# Новый «взрыв» (не тот же подряд)
		_burst_idx = 1 + (_burst_idx + randi() % (BURSTS - 1)) % BURSTS
		_burst.rotation = deg_to_rad(randf_range(-6.0, 6.0))
		_burst.flip_h = randf() < 0.5

func _apply(v: float, active: bool) -> void:
	if _bar == null or style == null:
		return
	var r := style.rank
	_bar.value = v
	var tint: Color = FILL_TINT[r]
	if active:
		var k := 1.0 + 0.25 * sin(Time.get_ticks_msec() / 90.0)
		tint = Color(tint.r * k, tint.g * k, tint.b * k)
	_bar.fill_modulate = tint
	if r != _shown_rank:
		_shown_rank = r
		_rank_label.text = tr(StyleMeter.rank_name(r))
		var col: Color = RANK_COLORS[r]
		_rank_label.label_settings.font_color = col.lightened(0.55) if r > 0 else Color(0.82, 0.8, 0.76)
		var tex := UISkin.texture("comic_burst_%02d" % _burst_idx)
		_burst.texture = tex
		_burst.visible = tex != null and r > 0
		_burst.modulate = Color(col, 0.95)
		_ticks.queue_redraw()
	if active:
		_glory_label.text = tr("БЕРСЕРК  %.1f") % maxf(style.berserk_left, 0.0)
		_glory_label.label_settings.font_color = RANK_COLORS[StyleMeter.TOP].lightened(0.35)
	else:
		_glory_label.text = tr("СЛАВА ×%s") % _fmt_mult(style.glory_mult()) if r > 0 else ""
		_glory_label.label_settings.font_color = Color(UIStyle.GOLD, 0.95)
	# Пустая шкала вне боя — приглушена
	modulate.a = 1.0 if active or v > 0.0 else 0.55

static func _fmt_mult(m: float) -> String:
	var s := "%.2f" % m
	while s.ends_with("0"):
		s = s.left(-1)
	return s.trim_suffix(".")

func _process(delta: float) -> void:
	if style == null:
		return
	_pulse = maxf(0.0, _pulse - delta * 1.5)
	_punch = maxf(0.0, _punch - delta * punch_decay)
	var k := _punch * _punch
	_caption.scale = Vector2.ONE * (1.0 + punch_scale * k)
	_caption.rotation = deg_to_rad(-3.0 + 6.0 * k * sin(Time.get_ticks_msec() / 25.0))
	var target := vignette_alpha * (0.75 + 0.25 * sin(Time.get_ticks_msec() / 130.0)) if style.active else 0.0
	_vignette.modulate.a = lerpf(_vignette.modulate.a, maxf(target, _pulse), clampf(delta * 8.0, 0.0, 1.0))
