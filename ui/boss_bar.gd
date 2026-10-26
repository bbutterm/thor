extends Control
class_name BossBar
## Полоса HP босса: широкая, поэтому не рамка HP с головой (она тянется только равномерно),
## а деревянная дорожка slider_track (9-slice) и лавовая заливка hud_hp_fill, обрезанная по значению.
## След урона — бледный хвост, догоняет значение. Только _draw, без материалов.

@export var trail_speed: float = 0.35

var value: float = 1.0:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if v > value:
			_trail = v
		value = v
		queue_redraw()

var _frame: StyleBox
var _fill: Texture2D
var _fill_src: Rect2
var _trail: float = 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = UISkin.stylebox("slider_track", 0.42)
	if _frame is SkinStyleBox:
		(_frame as SkinStyleBox).draw_center = false
	_fill = UISkin.texture("hud_hp_fill")
	if _fill:
		var k := UISkin.src_to_tex("hud_hp_fill")
		var r := UISkin.rect("hud_hp_fill", "fill_rect")
		_fill_src = Rect2(r.position * k, r.size * k)
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if _trail > value:
		_trail = maxf(value, _trail - trail_speed * delta)
		queue_redraw()

func _draw() -> void:
	var inner := Rect2(Vector2.ZERO, size).grow_individual(-14, -7, -14, -7)
	draw_rect(inner, Color(0, 0, 0, 0.6))
	if _trail > value:
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * _trail, inner.size.y)), Color(1.0, 0.85, 0.6, 0.5))
	var w := inner.size.x * value
	if _fill:
		draw_texture_rect_region(_fill, Rect2(inner.position, Vector2(w, inner.size.y)),
			Rect2(_fill_src.position, Vector2(_fill_src.size.x * value, _fill_src.size.y)))
	else:
		draw_rect(Rect2(inner.position, Vector2(w, inner.size.y)), Color(0.75, 0.15, 0.1))
	if _frame:
		_frame.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
