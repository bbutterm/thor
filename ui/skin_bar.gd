extends Control
class_name SkinBar
## Полоса HUD на графике комплекта: рамка (hud_hp_frame, hud_rage_frame — шкала стиля) и
## заливка на холсте того же размера. По README: сначала заливка, обрезанная по fill_rect
## (меняется только ширина/высота области — сама текстура не тянется), сверху рамка.
## Масштаб равномерный — по высоте контрола (custom_minimum_size), ширина — по пропорциям картинки.
## Вторая заливка «след» (trail) — бледный хвост убывающего значения; overlay — щит Сиф поверх HP.
## Нет картинок — плоская полоса (как старый ProgressBar). Рисует только _draw, материалов не создаёт.

@export var frame_id: String = "hud_hp_frame"
@export var fill_id: String = "hud_hp_fill"
## Скорость, с которой след догоняет значение (доля полосы в секунду)
@export var trail_speed: float = 0.6
## Задержка следа после удара, с
@export var trail_delay: float = 0.35

## 0..1
var value: float = 1.0:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if v == value:
			return  # HUD задаёт значение каждый кадр — без изменений не перерисовываем
		if v < value:
			_trail_wait = trail_delay
		value = v
		if _trail < value:
			_trail = value
		queue_redraw()
## Щит поверх (0..1 от длины полосы); цвет — overlay_color
var overlay: float = 0.0:
	set(v):
		overlay = clampf(v, 0.0, 1.0)
		queue_redraw()
var overlay_color: Color = Color(0.45, 0.8, 1.0, 0.7)
## Цвет заливки (берсерк краснее, вне боя тусклее)
var fill_modulate: Color = Color.WHITE:
	set(v):
		fill_modulate = v
		queue_redraw()
var flat_color: Color = UIStyle.BLOOD

var _frame: Texture2D
var _fill: Texture2D
var _fill_rect: Rect2
var _vertical: bool = false
var _src: Vector2 = Vector2(768, 192)
var _trail: float = 1.0
var _trail_wait: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = UISkin.texture(frame_id)
	_fill = UISkin.texture(fill_id)
	_src = UISkin.source_size(frame_id)
	_fill_rect = UISkin.rect(frame_id, "fill_rect")
	_vertical = str(UISkin.entry(frame_id).get("fill_direction", "")) == "bottom_to_top"
	if not _fill_rect.has_area():
		_fill_rect = Rect2(Vector2.ZERO, _src)
	resized.connect(queue_redraw)

## Масштаб и смещение картинки внутри контрола (вписываем с сохранением пропорций)
func _fit() -> Array:
	var k := minf(size.x / _src.x, size.y / _src.y)
	var off := (size - _src * k) * 0.5
	return [k, off]

## Прямоугольник заливки на экране (для подписи поверх)
func fill_area() -> Rect2:
	var f := _fit()
	return Rect2(f[1] + _fill_rect.position * f[0], _fill_rect.size * f[0])

func _process(delta: float) -> void:
	if _trail <= value:
		return
	if _trail_wait > 0.0:
		_trail_wait -= delta
		return
	_trail = maxf(value, _trail - trail_speed * delta)
	queue_redraw()

func _draw() -> void:
	var area := fill_area()
	if _frame == null or _fill == null:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * value, size.y)), flat_color)
		if overlay > 0.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * overlay, size.y * 0.4)), overlay_color)
		return
	var tk := float(_fill.get_width()) / _src.x
	if _trail > value + 0.001:
		_draw_fill(area, tk, _trail, Color(1.0, 0.92, 0.75, 0.55))
	_draw_fill(area, tk, value, fill_modulate)
	if overlay > 0.0:
		# Щит — светло-голубая полоса по верхней половине заливки (модуляция красной текстуры дала бы
		# грязный цвет — рисуем плоским цветом с яркой кромкой)
		var inset := area.grow_individual(-area.size.y * 0.12, -area.size.y * 0.1, -area.size.y * 0.12, 0.0)
		var band := Rect2(inset.position, Vector2(inset.size.x * overlay, inset.size.y * 0.42))
		draw_rect(band, overlay_color)
		draw_rect(Rect2(band.position, Vector2(band.size.x, maxf(2.0, band.size.y * 0.2))), Color(0.9, 0.97, 1.0, 0.95))
	var f := _fit()
	draw_texture_rect(_frame, Rect2(f[1], _src * f[0]), false)

func _draw_fill(area: Rect2, tk: float, v: float, col: Color) -> void:
	if v <= 0.0:
		return
	var src := Rect2(_fill_rect.position * tk, _fill_rect.size * tk)
	if _vertical:
		var h := area.size.y * v
		var sh := src.size.y * v
		draw_texture_rect_region(_fill, Rect2(area.position.x, area.end.y - h, area.size.x, h),
			Rect2(src.position.x, src.end.y - sh, src.size.x, sh), col)
	else:
		draw_texture_rect_region(_fill, Rect2(area.position, Vector2(area.size.x * v, area.size.y)),
			Rect2(src.position, Vector2(src.size.x * v, src.size.y)), col)
