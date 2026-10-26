extends StyleBox
class_name SkinStyleBox
## StyleBox из картинки UI-комплекта с 9-slice И масштабом (UISkin.stylebox).
## Обычный StyleBoxTexture рисует поля 1:1 в пикселях текстуры — кнопки 1024×192 вышли бы огромными.
## Здесь поля задаются в пикселях текстуры, а на экран идут ×draw_scale: картинка остаётся в полном
## разрешении (с мипмапами), поэтому чёткая и на 1280×720, и на 1920×1080.
## Режимы: NINE — 9 кусков (углы не тянутся, края — по своей оси), FIT — вся картинка равномерно
## (карточки, круглые кнопки, пузыри — README комплекта: «uniform scale only»).
## Материалов не создаёт: только команды отрисовки текстуры (этап 0 — без новых пайплайнов).

enum Mode { NINE, FIT, STRETCH }

@export var texture: Texture2D:
	set(v):
		texture = v
		emit_changed()
@export var mode: Mode = Mode.NINE
## Поля 9-slice в пикселях ТЕКСТУРЫ (после size_limit импорта): left, top, right, bottom
@export var slice: Vector4 = Vector4.ZERO
## Рисуемая часть текстуры (пиксели текстуры); пусто — вся
@export var region: Rect2 = Rect2()
## Экранных пикселей на пиксель текстуры
@export var draw_scale: float = 0.3
## Насколько рисунок выходит за прямоугольник контрола (экранные px): прозрачные поля картинки
## и выступы рамки не съедают место под содержимое
@export var grow: Vector4 = Vector4.ZERO
@export var modulate: Color = Color.WHITE
@export var draw_center: bool = true

func _region() -> Rect2:
	if region.has_area():
		return region
	return Rect2(Vector2.ZERO, texture.get_size()) if texture else Rect2()

func _draw_rect_of(rect: Rect2) -> Rect2:
	return Rect2(rect.position - Vector2(grow.x, grow.y), rect.size + Vector2(grow.x + grow.z, grow.y + grow.w))

func _get_draw_rect(rect: Rect2) -> Rect2:
	return _draw_rect_of(rect)

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if texture == null:
		return
	var rid := texture.get_rid()
	var src := _region()
	var dst := _draw_rect_of(rect)
	if dst.size.x <= 0.0 or dst.size.y <= 0.0:
		return
	match mode:
		Mode.STRETCH:
			RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item, dst, rid, src, modulate)
			return
		Mode.FIT:
			var k := minf(dst.size.x / src.size.x, dst.size.y / src.size.y)
			var sz := src.size * k
			RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item,
				Rect2(dst.position + (dst.size - sz) * 0.5, sz), rid, src, modulate)
			return
	# 9-slice: экранные поля = поля текстуры × масштаб; если контрол меньше суммы полей — ужимаем
	var l := slice.x * draw_scale
	var t := slice.y * draw_scale
	var r := slice.z * draw_scale
	var b := slice.w * draw_scale
	if l + r > dst.size.x and l + r > 0.0:
		var kx := dst.size.x / (l + r)
		l *= kx
		r *= kx
	if t + b > dst.size.y and t + b > 0.0:
		var ky := dst.size.y / (t + b)
		t *= ky
		b *= ky
	var sx := PackedFloat32Array([src.position.x, src.position.x + slice.x, src.end.x - slice.z, src.end.x])
	var sy := PackedFloat32Array([src.position.y, src.position.y + slice.y, src.end.y - slice.w, src.end.y])
	var dx := PackedFloat32Array([dst.position.x, dst.position.x + l, dst.end.x - r, dst.end.x])
	var dy := PackedFloat32Array([dst.position.y, dst.position.y + t, dst.end.y - b, dst.end.y])
	for j in 3:
		for i in 3:
			if i == 1 and j == 1 and not draw_center:
				continue
			var dr := Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j])
			var sr := Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j])
			if dr.size.x <= 0.01 or dr.size.y <= 0.01 or sr.size.x <= 0.0 or sr.size.y <= 0.0:
				continue
			RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item, dr, rid, sr, modulate)

## Копия с другим цветом (disabled/focus) — та же текстура, без новых материалов.
func tinted(c: Color) -> SkinStyleBox:
	var s := duplicate() as SkinStyleBox
	s.modulate = c
	return s
