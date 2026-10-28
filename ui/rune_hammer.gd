extends Control
class_name RuneHammer
## Молот для HUD: руны на бойке, шкала высоты — в рукояти, перезарядка броска — полоска по низу бойка.

## Доля оставшейся перезарядки 0…1 (0 — полоски нет); пишет HUD._update_hammer
var cooldown: float = 0.0
## До какого момента (мс) полоска красная — бросок на перезарядке (осечка)
var flash_until: int = 0

func _ready() -> void:
	custom_minimum_size = Vector2(144, 106)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_cooldown(frac: float) -> void:
	frac = clampf(frac, 0.0, 1.0)
	if absf(frac - cooldown) > 0.002 or (frac == 0.0) != (cooldown == 0.0) or Time.get_ticks_msec() < flash_until + 50:
		cooldown = frac
		queue_redraw()

func _draw() -> void:
	# Отдельный силуэт не зависит от состояния оружия и не создаёт материалов.
	draw_rect(Rect2(57, 32, 30, 72), Color(0.12, 0.09, 0.07, 0.95))
	draw_rect(Rect2(61, 35, 22, 65), Color(0.35, 0.20, 0.12))
	draw_rect(Rect2(55, 100, 34, 5), Color(0.72, 0.52, 0.25))
	draw_rect(Rect2(3, 2, 138, 42), Color(0.07, 0.09, 0.13, 0.96))
	draw_rect(Rect2(6, 5, 132, 36), Color(0.24, 0.28, 0.34, 0.98))
	draw_rect(Rect2(7, 5, 130, 2), Color(0.77, 0.60, 0.30))
	if cooldown <= 0.0:
		draw_rect(Rect2(7, 39, 130, 2), Color(0.77, 0.60, 0.30))
		return
	# Перезарядка после поимки: короткая полоска убывает к нулю (вместо надписи на весь HUD)
	var red := Time.get_ticks_msec() < flash_until
	draw_rect(Rect2(6, 38, 132, 6), Color(0.05, 0.06, 0.09, 1.0))
	draw_rect(Rect2(7, 39, 130 * cooldown, 4), Color(1.0, 0.35, 0.3) if red else Color(0.62, 0.85, 1.0))
