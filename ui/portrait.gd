extends Control
class_name Portrait
## Портрет персонажа для диалогов: sprites/portraits/<speaker>_<emotion>.png или .webp;
## нет эмоции — <speaker>_neutral, нет файла — процедурная заглушка (силуэт в цвете персонажа,
## инициал и простое лицо по эмоции).

const DIR := "res://sprites/portraits/"

var speaker: String = ""
var emotion: String = "neutral"
var color: Color = Color(0.5, 0.5, 0.5)
var initial: String = "?"
var accessory: String = ""
## Компактный вид (пузырь в бою): без лишних деталей
var compact: bool = false

var _tex_rect: TextureRect
var _bounce_tween: Tween

## Где рисовать процедурную заглушку (доли размера): большой портрет по пояс уходит под плашку текста,
## а карточка-заглушка должна оставаться над ней
var fallback_area: Rect2 = Rect2(0, 0, 1, 1)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_tex_rect = TextureRect.new()
	_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_tex_rect)

## Один спрайт на двоих: Хугин и Мунин нарисованы вместе
const ALIASES := {"munin": "hugin", "hovding": "draugr"}
const EXTS := ["png", "webp"]
## Точки лица (центр глаз) на холсте исходника — для крупного плана в пузыре (data/portrait_faces.json)
const FACES_PATH := "res://data/portrait_faces.json"
## Крупный план лица в компактном режиме: сторона квадрата в долях ширины холста
@export var face_crop: float = 0.34

static var _faces: Dictionary = {}

const EMOTIONS := ["neutral", "happy", "angry", "shocked", "smug", "embarrassed"]
## Портреты, которые держим в памяти (prefetch): путь → текстура; и ещё грузящиеся в фоне
static var _held: Dictionary = {}
static var _pending: PackedStringArray = []

## Заранее (при входе в зал, под затемнением) грузит в фоне портреты тех, кто может заговорить в бою
## пузырём (Хугин в обучении, босс, ведущий испытания): иначе первая реплика читала картинку 1024 px
## посреди боя — ~20 мс CPU и загрузка в видеопамять. Держит только последний набор, прежний отпускает.
static func prefetch(speakers: PackedStringArray) -> void:
	var want: Dictionary = {}
	for s in speakers:
		var sp: String = ALIASES.get(s, s)
		for emo in EMOTIONS:
			for ext in EXTS:
				var p := DIR + "%s_%s.%s" % [sp, emo, ext]
				if ResourceLoader.exists(p):
					want[p] = true
	for p in _pending:
		var res := ResourceLoader.load_threaded_get(p)
		if res and want.has(p):
			_held[p] = res
	_pending.clear()
	for p in _held.keys():
		if not want.has(p):
			_held.erase(p)
	for p in want:
		if _held.has(p):
			continue
		# Dummy может повредить RID, если текстуры грузятся параллельно созданию ресурсов.
		if DisplayServer.get_name() == "headless" or ResourceLoader.has_cached(p):
			_held[p] = load(p)
		elif ResourceLoader.load_threaded_request(p) == OK:
			_pending.append(p)

## Что сейчас держит prefetch (тесты)
static func prefetched() -> PackedStringArray:
	var out := PackedStringArray(_held.keys())
	out.append_array(_pending)
	return out

static func texture_path(sp: String, emo: String) -> String:
	sp = ALIASES.get(sp, sp)
	for e in [emo, "neutral"]:
		for ext in EXTS:
			var p := DIR + "%s_%s.%s" % [sp, e, ext]
			if ResourceLoader.exists(p):
				return p
	return ""

static func face_of(sp: String) -> Dictionary:
	if _faces.is_empty() and FileAccess.file_exists(FACES_PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FACES_PATH))
		if d is Dictionary:
			_faces = (d as Dictionary).get("faces", {})
	# Своя точка лица важнее общей картинки (Хугин и Мунин — два ворона на одном рисунке)
	return _faces.get(sp, _faces.get(ALIASES.get(sp, sp), {}))

## Компактный вид: квадрат вокруг лица (по центру глаз из данных комплекта портретов).
func _face_texture(tex: Texture2D, sp: String) -> Texture2D:
	var f := face_of(sp)
	var canvas: Array = f.get("canvas", [tex.get_width(), tex.get_height()])
	var eye: Array = f.get("eye_center", [canvas[0] * 0.5, canvas[1] * 0.24])
	var k := float(tex.get_width()) / float(canvas[0])
	var side := float(canvas[0]) * face_crop * k
	var cx := float(eye[0]) * k
	var cy := float(eye[1]) * k + side * 0.12
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(clampf(cx - side * 0.5, 0.0, tex.get_width() - side), clampf(cy - side * 0.5, 0.0, tex.get_height() - side), side, side)
	return at

## Меняет говорящего/эмоцию. bounce — насколько «подпрыгнуть» при смене эмоции (0 — не прыгать).
func set_speaker(sp: String, emo: String, def: Dictionary, bounce: float = 0.06) -> void:
	var changed := sp != speaker or emo != emotion
	speaker = sp
	emotion = emo
	color = Color.from_string(str(def.get("color", "#888888")), Color(0.5, 0.5, 0.5))
	initial = str(def.get("initial", str(def.get("name", sp)).left(1)))
	accessory = str(def.get("accessory", ""))
	var tp := texture_path(sp, emo)
	var tex: Texture2D = load(tp) if tp != "" else null
	if tex and compact:
		tex = _face_texture(tex, sp)
	_tex_rect.texture = tex
	_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if compact else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	queue_redraw()
	if bounce > 0.0 and changed:
		do_bounce(bounce)

## Лёгкое «подпрыгивание» при смене эмоции. Величина — Dialogue.box().portrait_bounce.
func do_bounce(amount: float = 0.06, time: float = 0.22) -> void:
	pivot_offset = Vector2(size.x * 0.5, size.y)
	if _bounce_tween and _bounce_tween.is_valid():
		_bounce_tween.kill()
	scale = Vector2(1.0 - amount * 0.5, 1.0 + amount)
	_bounce_tween = create_tween()
	_bounce_tween.tween_property(self, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _draw() -> void:
	if _tex_rect.texture != null:
		return
	var area := Rect2(size * fallback_area.position, size * fallback_area.size)
	draw_set_transform(area.position)
	var w := area.size.x
	var h := area.size.y
	if w < 4.0 or h < 4.0:
		return
	var dark := color.darkened(0.55)
	var light := color.lightened(0.25)
	# Подложка-карточка
	var card := StyleBoxFlat.new()
	card.bg_color = Color(color.darkened(0.78), 0.92)
	card.border_color = Color(color, 0.85)
	card.set_border_width_all(3 if not compact else 2)
	card.set_corner_radius_all(int(minf(w, h) * 0.08))
	draw_style_box(card, Rect2(Vector2.ZERO, area.size))
	# Свечение за силуэтом
	draw_circle(Vector2(w * 0.5, h * 0.42), w * 0.42, Color(color, 0.18))
	# Плечи
	var sh_top := h * 0.66
	var pts := PackedVector2Array([
		Vector2(w * 0.08, h), Vector2(w * 0.14, sh_top + h * 0.06), Vector2(w * 0.32, sh_top - h * 0.02),
		Vector2(w * 0.68, sh_top - h * 0.02), Vector2(w * 0.86, sh_top + h * 0.06), Vector2(w * 0.92, h)])
	draw_colored_polygon(pts, dark)
	# Шея и голова
	var head_c := Vector2(w * 0.5, h * 0.4)
	var head_r := w * 0.2
	draw_rect(Rect2(w * 0.43, head_c.y + head_r * 0.6, w * 0.14, h * 0.12), dark.lightened(0.1))
	_draw_accessory_back(head_c, head_r)
	draw_circle(head_c, head_r, color.darkened(0.25))
	draw_arc(head_c, head_r, 0, TAU, 48, light, 2.0 if not compact else 1.5, true)
	_draw_face(head_c, head_r)
	_draw_accessory_front(head_c, head_r)
	# Инициал на груди
	if not compact:
		var f := UIStyle.font()
		var fs := int(h * 0.14)
		var tw := f.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(f, Vector2(w * 0.5 - tw * 0.5, h * 0.94), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.6))
		draw_string(f, Vector2(w * 0.5 - tw * 0.5, h * 0.94), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, light)

func _draw_face(c: Vector2, r: float) -> void:
	var ink := Color(0.05, 0.04, 0.06, 0.9)
	var lw := maxf(1.5, r * 0.07)
	var ey := c.y - r * 0.12
	var ex := r * 0.38
	var eye_r := r * 0.09
	match emotion:
		"happy":
			draw_arc(Vector2(c.x - ex, ey + eye_r), eye_r * 1.4, PI, TAU, 10, ink, lw)
			draw_arc(Vector2(c.x + ex, ey + eye_r), eye_r * 1.4, PI, TAU, 10, ink, lw)
			draw_arc(Vector2(c.x, c.y + r * 0.22), r * 0.32, 0.15, PI - 0.15, 16, ink, lw)
		"angry":
			draw_circle(Vector2(c.x - ex, ey), eye_r, ink)
			draw_circle(Vector2(c.x + ex, ey), eye_r, ink)
			draw_line(Vector2(c.x - ex - r * 0.2, ey - r * 0.28), Vector2(c.x - ex + r * 0.16, ey - r * 0.12), ink, lw * 1.2)
			draw_line(Vector2(c.x + ex + r * 0.2, ey - r * 0.28), Vector2(c.x + ex - r * 0.16, ey - r * 0.12), ink, lw * 1.2)
			draw_arc(Vector2(c.x, c.y + r * 0.58), r * 0.28, PI + 0.4, TAU - 0.4, 12, ink, lw)
		"shocked":
			draw_arc(Vector2(c.x - ex, ey), eye_r * 1.5, 0, TAU, 14, ink, lw)
			draw_arc(Vector2(c.x + ex, ey), eye_r * 1.5, 0, TAU, 14, ink, lw)
			draw_circle(Vector2(c.x, c.y + r * 0.42), r * 0.14, ink)
		"smug":
			draw_line(Vector2(c.x - ex - eye_r * 1.3, ey), Vector2(c.x - ex + eye_r * 1.3, ey + eye_r * 0.4), ink, lw)
			draw_line(Vector2(c.x + ex - eye_r * 1.3, ey + eye_r * 0.4), Vector2(c.x + ex + eye_r * 1.3, ey), ink, lw)
			draw_arc(Vector2(c.x + r * 0.12, c.y + r * 0.22), r * 0.24, 0.3, PI * 0.75, 10, ink, lw)
		"embarrassed":
			draw_line(Vector2(c.x - ex - eye_r, ey), Vector2(c.x - ex + eye_r, ey), ink, lw)
			draw_line(Vector2(c.x + ex - eye_r, ey), Vector2(c.x + ex + eye_r, ey), ink, lw)
			draw_circle(Vector2(c.x - r * 0.55, c.y + r * 0.18), r * 0.13, Color(1.0, 0.45, 0.5, 0.55))
			draw_circle(Vector2(c.x + r * 0.55, c.y + r * 0.18), r * 0.13, Color(1.0, 0.45, 0.5, 0.55))
			draw_polyline(PackedVector2Array([Vector2(c.x - r * 0.2, c.y + r * 0.4), Vector2(c.x - r * 0.07, c.y + r * 0.34),
				Vector2(c.x + r * 0.07, c.y + r * 0.42), Vector2(c.x + r * 0.2, c.y + r * 0.36)]), ink, lw)
		_:
			draw_circle(Vector2(c.x - ex, ey), eye_r, ink)
			draw_circle(Vector2(c.x + ex, ey), eye_r, ink)
			draw_line(Vector2(c.x - r * 0.2, c.y + r * 0.4), Vector2(c.x + r * 0.2, c.y + r * 0.4), ink, lw)

func _draw_accessory_back(c: Vector2, r: float) -> void:
	var col := color.lightened(0.15)
	match accessory:
		"bun":  # пучок Тора
			draw_circle(Vector2(c.x + r * 0.5, c.y - r * 0.95), r * 0.38, color.darkened(0.1))
		"braid":  # коса Сиф
			for i in 5:
				draw_circle(Vector2(c.x + r * 0.95, c.y + r * (0.2 + i * 0.42)), r * (0.26 - i * 0.02), col)
		"wings":  # крылья Хильд
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - r * 0.9, c.y + r * 1.4), Vector2(c.x - r * 2.2, c.y - r * 0.6), Vector2(c.x - r * 1.4, c.y + r * 1.8)]), Color(0.95, 0.95, 1.0, 0.7))
			draw_colored_polygon(PackedVector2Array([Vector2(c.x + r * 0.9, c.y + r * 1.4), Vector2(c.x + r * 2.2, c.y - r * 0.6), Vector2(c.x + r * 1.4, c.y + r * 1.8)]), Color(0.95, 0.95, 1.0, 0.7))
		"flowers":  # волосы Фрейи
			draw_circle(Vector2(c.x, c.y + r * 0.1), r * 1.25, Color(color.lightened(0.3), 0.55))

func _draw_accessory_front(c: Vector2, r: float) -> void:
	var lw := maxf(2.0, r * 0.1)
	match accessory:
		"eyepatch":  # Один
			draw_line(Vector2(c.x - r * 0.95, c.y - r * 0.5), Vector2(c.x + r * 0.9, c.y - r * 0.05), Color(0.05, 0.05, 0.05), lw * 0.6)
			draw_circle(Vector2(c.x - r * 0.38, c.y - r * 0.12), r * 0.2, Color(0.05, 0.05, 0.05))
			_draw_beard(c, r, Color(0.92, 0.92, 0.95), 1.15)
		"beard":  # Брокк, Эйтри
			_draw_beard(c, r, color.lightened(0.35), 1.3)
		"bun":
			_draw_beard(c, r, Color(0.85, 0.35, 0.18), 0.9)
		"horns":  # Локи
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - r * 0.55, c.y - r * 0.8), Vector2(c.x - r * 0.95, c.y - r * 1.55), Vector2(c.x - r * 0.25, c.y - r * 0.95)]), Color(0.95, 0.78, 0.3))
			draw_colored_polygon(PackedVector2Array([Vector2(c.x + r * 0.55, c.y - r * 0.8), Vector2(c.x + r * 0.95, c.y - r * 1.55), Vector2(c.x + r * 0.25, c.y - r * 0.95)]), Color(0.95, 0.78, 0.3))
		"crown":  # Хель, Ярл
			var pts := PackedVector2Array([Vector2(c.x - r * 0.75, c.y - r * 0.75), Vector2(c.x - r * 0.6, c.y - r * 1.35), Vector2(c.x - r * 0.25, c.y - r * 0.95),
				Vector2(c.x, c.y - r * 1.45), Vector2(c.x + r * 0.25, c.y - r * 0.95), Vector2(c.x + r * 0.6, c.y - r * 1.35), Vector2(c.x + r * 0.75, c.y - r * 0.75)])
			draw_colored_polygon(pts, Color(0.85, 0.82, 0.75))
		"hat":  # шапка с ушками Скади
			draw_arc(c, r * 1.02, PI * 1.05, PI * 1.95, 20, Color(0.97, 0.97, 1.0), lw * 2.2)
			draw_rect(Rect2(c.x - r * 1.05, c.y - r * 0.1, r * 0.3, r * 0.75), Color(0.97, 0.97, 1.0))
			draw_rect(Rect2(c.x + r * 0.75, c.y - r * 0.1, r * 0.3, r * 0.75), Color(0.97, 0.97, 1.0))
		"helmet":  # Хеймдалль
			draw_arc(c, r * 1.0, PI * 1.0, TAU, 24, Color(1.0, 0.85, 0.3), lw * 1.8)
			draw_line(Vector2(c.x, c.y - r * 1.05), Vector2(c.x, c.y - r * 0.2), Color(1.0, 0.85, 0.3), lw)
		"beak":  # вороны
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - r * 0.25, c.y + r * 0.05), Vector2(c.x + r * 0.25, c.y + r * 0.05), Vector2(c.x, c.y + r * 0.7)]), Color(0.95, 0.75, 0.25))
		"split":  # Хель: половина лица со «светящимися костями»
			draw_arc(c, r * 0.75, -PI * 0.5, PI * 0.5, 16, Color(0.85, 0.75, 1.0, 0.75), lw * 0.5)
			draw_line(Vector2(c.x + r * 0.2, c.y - r * 0.6), Vector2(c.x + r * 0.2, c.y + r * 0.6), Color(0.85, 0.75, 1.0, 0.6), lw * 0.4)

func _draw_beard(c: Vector2, r: float, col: Color, length: float) -> void:
	var pts := PackedVector2Array([Vector2(c.x - r * 0.85, c.y + r * 0.15), Vector2(c.x - r * 0.6, c.y + r * (0.8 + length * 0.4)),
		Vector2(c.x, c.y + r * (1.0 + length * 0.6)), Vector2(c.x + r * 0.6, c.y + r * (0.8 + length * 0.4)), Vector2(c.x + r * 0.85, c.y + r * 0.15),
		Vector2(c.x + r * 0.35, c.y + r * 0.55), Vector2(c.x - r * 0.35, c.y + r * 0.55)])
	draw_colored_polygon(pts, col)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
