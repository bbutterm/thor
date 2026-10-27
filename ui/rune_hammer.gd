extends Control
class_name RuneHammer
## Молот для HUD: руны на бойке, шкала высоты — в рукояти.

func _ready() -> void:
	custom_minimum_size = Vector2(144, 106)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	# Отдельный силуэт не зависит от состояния оружия и не создаёт материалов.
	draw_rect(Rect2(57, 32, 30, 72), Color(0.12, 0.09, 0.07, 0.95))
	draw_rect(Rect2(61, 35, 22, 65), Color(0.35, 0.20, 0.12))
	draw_rect(Rect2(55, 100, 34, 5), Color(0.72, 0.52, 0.25))
	draw_rect(Rect2(3, 2, 138, 42), Color(0.07, 0.09, 0.13, 0.96))
	draw_rect(Rect2(6, 5, 132, 36), Color(0.24, 0.28, 0.34, 0.98))
	draw_rect(Rect2(7, 5, 130, 2), Color(0.77, 0.60, 0.30))
	draw_rect(Rect2(7, 39, 130, 2), Color(0.77, 0.60, 0.30))
