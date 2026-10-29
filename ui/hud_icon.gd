extends Control
class_name HudIcon
## Иконка HUD из комплекта: картинка вписана в контрол с сохранением пропорций.
## Для зарядов (рывок): base — пустой камень, over — полный, fill 0..1 — сколько полного видно снизу вверх.
## pop() — короткий «подскок» (зарядился, сменилось состояние). Рисует только _draw.
## shade 0..1 — затемнение сверху вниз (перезарядка Мьёльнира, П6): тёмная часть убывает к нулю.

var base: Texture2D:
	set(v):
		base = v
		queue_redraw()
var over: Texture2D:
	set(v):
		over = v
		queue_redraw()
var fill: float = 1.0:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if not is_equal_approx(v, fill):
			fill = v
			queue_redraw()
var tint: Color = Color.WHITE:
	set(v):
		tint = v
		queue_redraw()
## Подпись в правом нижнем углу (уровень, руна)
var badge: String = "":
	set(v):
		badge = v
		queue_redraw()
var badge_color: Color = UIStyle.TEXT
var shade: float = 0.0:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if v != shade and (v == 0.0 or not is_equal_approx(v, shade)):
			shade = v
			queue_redraw()
var shade_color: Color = Color(0.08, 0.09, 0.13, 0.82)
var badge_size: int = 13

var _pop: float = 0.0

static func make(tex: Texture2D, px: float) -> HudIcon:
	var h := HudIcon.new()
	h.base = tex
	h.custom_minimum_size = Vector2(px, px)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h

func pop() -> void:
	_pop = 1.0
	set_process(true)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

func _process(delta: float) -> void:
	_pop = maxf(0.0, _pop - delta * 5.0)
	queue_redraw()
	if _pop <= 0.0:
		set_process(false)

func _rect_for(t: Texture2D) -> Rect2:
	var ts := t.get_size()
	var k := minf(size.x / ts.x, size.y / ts.y) * (1.0 + 0.18 * _pop)
	var sz := ts * k
	return Rect2((size - sz) * 0.5, sz)

func _draw() -> void:
	if base:
		draw_texture_rect(base, _rect_for(base), false, tint)
	if over and fill > 0.0:
		var r := _rect_for(over)
		var ts := over.get_size()
		if fill >= 1.0:
			draw_texture_rect(over, r, false, tint)
		else:
			var h := r.size.y * fill
			draw_texture_rect_region(over, Rect2(r.position.x, r.end.y - h, r.size.x, h),
				Rect2(0, ts.y * (1.0 - fill), ts.x, ts.y * fill), tint)
	if shade > 0.0 and base:
		# Та же картинка тёмным поверх верхней части — силуэт, а не прямоугольник
		var r := _rect_for(base)
		var ts := base.get_size()
		var h := r.size.y * shade
		draw_texture_rect_region(base, Rect2(r.position.x, r.position.y, r.size.x, h), Rect2(0, 0, ts.x, ts.y * shade), shade_color)
	if badge != "":
		var font := UIStyle.font()
		var w := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, badge_size).x
		var pos := Vector2(size.x - w, size.y)
		draw_string_outline(font, pos, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, badge_size, 4, Color(0, 0, 0, 0.9))
		draw_string(font, pos, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, badge_size, badge_color)
