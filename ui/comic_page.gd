extends ComicInsert
class_name ComicPage
## «Страница комикса» (GDD 20, 26.6; NEXT_TASKS 3): при смерти Тора и смерти босса — стоп-кадр игры,
## белая вспышка, кадр «вклеивается» в рамку страницы sprites/death/frame.webp (рваный край, наклон,
## растр shaders/comic_page.gdshader). У смерти Тора рядом — иллюстрация причины sprites/death/<причина>.webp
## (ScreenArt.death_key); на плашке рамки — подпись Одина из пула odin.page_<причина> / odin.page_boss_<id>.
## ~2 с, клик / клавиша пропускает; дальше поток как раньше (Game: смерть → итог, босс → награда).
## Выключатель — настройка [comic] page («Стоп-кадр комикса»). В тестах выключено (ScreenArt.pauses_allowed).

## Сколько держится страница, с (клик — раньше)
@export var hold_time: float = 2.1
## Белая вспышка в начале, с
@export var flash_time: float = 0.15
## За сколько кадр «влетает» в страницу, с
@export var slam_time: float = 0.2
## Второй кадр (иллюстрация причины) — позже первого на столько, с
@export var second_delay: float = 0.18
@export var fade_out_time: float = 0.22
## Наклон кадров, градусы
@export var tilt_main: float = -3.5
@export var tilt_second: float = 3.0
## С какого размера кадр «влетает» (1 — без увеличения)
@export var slam_scale: float = 1.35
## Стоп-кадр шире этого (px) уменьшается — меньше памяти и загрузки в видеопамять
@export var shot_max_width: int = 1600

## Окно рамки (доли frame.webp 1024×768): кадр под ним, рваный край рамки ложится поверх
const WINDOW := Rect2(0.035, 0.055, 0.93, 0.9)
## Плашка рамки справа внизу — подпись Одина
const PLAQUE := Rect2(0.615, 0.83, 0.34, 0.125)
const INK := Color(0.16, 0.1, 0.05)

## "death" — смерть Тора, "boss" — смерть босса
var kind: String = "death"
## Причина смерти (ScreenArt.death_key) или id босса (sven, jarl)
var key: String = ""
var caption: String = ""
var boss_title: String = ""
## Кто убил Тора (подпись RunTracker.SOURCE_NAMES) — на плашке стоп-кадра
var killer: String = ""
## Стоп-кадр (null — не сняли: headless или пустой кадр)
var shot: Texture2D

## Для тестов: сколько страниц показано и что было на последней
static var shown_count: int = 0
static var last_kind: String = ""
static var last_key: String = ""
static var last_caption: String = ""
static var _material: ShaderMaterial

var _root: Control
var _dim: ColorRect
var _flash: ColorRect
var _header: Control
var _panels: Array[Control] = []
var _panel_tilts: Array[float] = []
var _panel_from: Array[Vector2] = []
var _caption_box: Control
var _out_at: float = -1.0

## Смерть Тора: result — итог забега (RunTracker.finish / result). null — выключено.
static func show_death(parent: Node, result: Dictionary) -> ComicPage:
	if not ScreenArt.page_enabled() or parent == null:
		return null
	var p := ComicPage.new()
	p.kind = "death"
	p.key = ScreenArt.death_key(result)
	p.caption = Dialogue.pool_text("odin.page_" + p.key)
	var by := str(result.get("killed_by", ""))
	if by != "":
		p.killer = I18n.t(str(RunTracker.SOURCE_NAMES.get(by, by)))
	parent.add_child(p)
	return p

## Смерть босса со своей заставкой (ScreenArt.BOSSES): boss_id — sven / jarl, title — имя на полосе HP.
static func show_boss(parent: Node, boss_id: String, title: String = "") -> ComicPage:
	if not ScreenArt.page_enabled() or parent == null:
		return null
	var p := ComicPage.new()
	p.kind = "boss"
	p.key = boss_id
	p.boss_title = title
	p.caption = Dialogue.pool_text("odin.page_boss_" + boss_id)
	parent.add_child(p)
	return p

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/comic_page.gdshader")
	return _material

func _ready() -> void:
	layer = 28  # над паузой (20), под экраном итога (30)
	await begin()
	if not is_inside_tree():
		return
	Perf.mark("comic_page")
	await _capture()
	if not is_inside_tree():
		return
	shown_count += 1
	last_kind = kind
	last_key = key
	last_caption = caption
	_build()
	age = 0.0
	_tick(0.0)

## Снимок кадра игры без HUD (полоски и прицел в стоп-кадре не нужны). Игра уже на паузе — кадр тот же.
func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var hud: CanvasLayer = null
	if get_parent():
		hud = get_parent().get("hud") as CanvasLayer
	var hide_hud := hud != null and hud.visible
	if hide_hud:
		hud.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if hide_hud and is_instance_valid(hud):
		hud.visible = true
	if img == null or img.is_empty():
		return
	if img.get_width() > shot_max_width:
		img.resize(shot_max_width, int(img.get_height() * float(shot_max_width) / img.get_width()), Image.INTERPOLATE_BILINEAR)
	shot = ImageTexture.create_from_image(img)

func _build() -> void:
	_root = Control.new()
	UIStyle.full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.025, 0.04, 0.0)
	UIStyle.full_rect(_dim)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)

	var vp := _root.get_viewport_rect().size
	if kind == "death":
		var art := ScreenArt.death_art(key)
		var w := vp.x * 0.47
		if shot:
			_add_panel(shot, true, Vector2(w, w * 0.75), Vector2(0.68, 0.44), tilt_second, Vector2(0.25, -0.1))
		if art:
			var w2 := w if shot else vp.x * 0.6
			# Стоп-кадр — справа сверху, рисунок причины — слева снизу поверх (плашки обоих видны)
			var at := Vector2(0.33, 0.58) if shot else Vector2(0.5, 0.5)
			_add_panel(art, false, Vector2(w2, w2 * 0.75), at, tilt_main, Vector2(-0.25, 0.12))
		_header = _plate(tr("ВЫПУСК №%d") % maxi(1, Save.deaths()), tr("Тор снова на диване"))
	else:
		var content := shot if shot else ScreenArt.tex(ScreenArt.boss_card_path(str(_boss_card())))
		var w := vp.x * 0.6
		if content:
			_add_panel(content, shot != null, Vector2(w, w * 0.75), Vector2(0.5, 0.52), tilt_main * 0.7, Vector2(0.0, -0.2))
		_header = _plate((tr("%s ПОВЕРЖЕН!") % tr(boss_title)) if boss_title != "" else tr("БОСС ПОВЕРЖЕН!"), tr("Страница для альбома Одина"))
	_root.add_child(_header)
	_header.position = Vector2(vp.x * 0.04, vp.y * 0.035)
	_header.rotation = deg_to_rad(-2.5)
	# Подпись Одина — на плашке последнего (верхнего) кадра
	if not _panels.is_empty() and caption != "":
		_add_caption(_panels.back())
	# На плашке стоп-кадра (под картинкой причины) — кто победил Тора
	if kind == "death" and _panels.size() > 1 and killer != "":
		_plaque_text(_panels[0], tr("Тор против: %s") % killer)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 1)
	UIStyle.full_rect(_flash)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

func _boss_card() -> String:
	for src in ScreenArt.BOSSES:
		if str(ScreenArt.BOSSES[src].id) == key:
			return str(ScreenArt.BOSSES[src].card)
	return ""

## Кадр в рамке страницы: тень, картинка в окне рамки (стоп-кадр — с растром), рамка поверх.
## at — центр (доли экрана), from — откуда влетает (доли экрана от центра).
func _add_panel(t: Texture2D, raster: bool, size: Vector2, at: Vector2, tilt: float, from: Vector2) -> void:
	var vp := _root.get_viewport_rect().size
	var p := Control.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size = size
	p.pivot_offset = size * 0.5
	p.position = vp * at - size * 0.5
	p.set_meta("base", p.position)
	var frame_tex := ScreenArt.tex(ScreenArt.FRAME)
	# Тень: та же рамка чёрным + тёмное окно, со сдвигом — повторяет рваный край
	var sh_win := ColorRect.new()
	sh_win.color = Color(0, 0, 0, 0.5)
	_place(sh_win, WINDOW, size, Vector2(10, 12))
	p.add_child(sh_win)
	if frame_tex:
		var sh := TextureRect.new()
		sh.texture = frame_tex
		sh.modulate = Color(0, 0, 0, 0.55)
		_place(sh, Rect2(0, 0, 1, 1), size, Vector2(10, 12))
		p.add_child(sh)
	var pic := TextureRect.new()
	pic.texture = t
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if raster:
		pic.material = material()
	_place(pic, WINDOW, size)
	p.add_child(pic)
	if frame_tex:
		var fr := TextureRect.new()
		fr.texture = frame_tex
		_place(fr, Rect2(0, 0, 1, 1), size)
		p.add_child(fr)
	else:
		# Нет рамки — процедурная: светлая кайма
		var border := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.border_color = Color(0.98, 0.94, 0.84)
		sb.set_border_width_all(int(size.x * 0.03))
		border.add_theme_stylebox_override("panel", sb)
		_place(border, Rect2(0, 0, 1, 1), size)
		p.add_child(border)
	p.modulate.a = 0.0
	_root.add_child(p)
	_panels.append(p)
	_panel_tilts.append(tilt)
	_panel_from.append(from * vp)

func _place(c: Control, r: Rect2, size: Vector2, shift: Vector2 = Vector2.ZERO) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Сначала «не по размеру текстуры», иначе size не станет меньше картинки
	if c is TextureRect:
		(c as TextureRect).expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	c.position = r.position * size + shift
	c.size = r.size * size

## Текст на плашке рамки (справа внизу): кегль подбирается под длину.
func _plaque_text(panel: Control, text: String) -> Control:
	var size := panel.size
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = PLAQUE.position * size
	box.size = PLAQUE.size * size
	box.pivot_offset = box.size * 0.5
	panel.add_child(box)
	var lbl := UIStyle.label(text, 18, INK, 0)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var inner := box.size - Vector2(12, 6)
	lbl.label_settings.font_size = fit_font_size(text, inner, 20, 11)
	lbl.label_settings.line_spacing = -2
	lbl.position = Vector2(6, 3)
	lbl.size = inner
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lbl)
	return box

## Подпись Одина на плашке рамки + маленький Один рядом.
func _add_caption(panel: Control) -> void:
	var size := panel.size
	_caption_box = _plaque_text(panel, caption)
	var odin := Portrait.new()
	odin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ph := size.y * 0.3
	odin.size = Vector2(ph * 0.72, ph)
	odin.position = Vector2(PLAQUE.position.x * size.x - ph * 0.6, size.y * 0.985 - ph)
	odin.set_speaker("odin", "smug" if kind == "death" else "happy", Dialogue.speakers.get("odin", {}), 0.0)
	panel.add_child(odin)
	panel.move_child(odin, _caption_box.get_index())
	_caption_box.modulate.a = 0.0

## Самый крупный кегль, при котором текст влезает в box.
static func fit_font_size(text: String, box: Vector2, biggest: int, smallest: int) -> int:
	var f := UIStyle.font()
	var fs := biggest
	while fs > smallest:
		var s := f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, box.x, fs)
		if s.y <= box.y and s.x <= box.x + 1.0:
			break
		fs -= 1
	return fs

## Плашка-заголовок страницы: «ВЫПУСК №…» / «… ПОВЕРЖЕН!»
func _plate(title: String, sub: String) -> Control:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.93, 0.78)
	sb.border_color = Color(0.08, 0.06, 0.05)
	sb.set_border_width_all(3)
	sb.set_content_margin_all(10)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(6, 6)
	pc.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	pc.add_child(v)
	v.add_child(UIStyle.label(title, 30, Color(0.75, 0.12, 0.08), 0))
	v.add_child(UIStyle.label(sub, 15, INK, 0))
	pc.modulate.a = 0.0
	return pc

func _tick(t: float) -> void:
	if _root == null:
		return
	if skipped and _out_at < 0.0:
		_out_at = t
	if _out_at < 0.0 and t >= hold_time:
		_out_at = t
	_flash.color.a = clampf(1.0 - t / maxf(flash_time, 0.01), 0.0, 1.0)
	_dim.color.a = 0.78 * clampf(t / 0.12, 0.0, 1.0)
	for i in _panels.size():
		var p := _panels[i]
		var k := (t - 0.03 - i * second_delay) / maxf(slam_time, 0.01)
		var e := ease_out(k)
		p.modulate.a = clampf(k * 4.0, 0.0, 1.0)
		p.scale = Vector2.ONE * lerpf(slam_scale, 1.0, ease_back(k, 1.2))
		p.rotation = deg_to_rad(lerpf(_panel_tilts[i] * -1.5, _panel_tilts[i], e))
		p.position = (p.get_meta("base") as Vector2) + _panel_from[i] * (1.0 - e)
	var last_k := (t - 0.03 - (_panels.size() - 1) * second_delay - slam_time) / 0.15
	if _caption_box:
		_caption_box.modulate.a = clampf(last_k, 0.0, 1.0)
		_caption_box.scale = Vector2.ONE * lerpf(1.25, 1.0, ease_out(last_k))
	_header.modulate.a = clampf((t - 0.1) / 0.15, 0.0, 1.0)
	if _out_at >= 0.0:
		var o := (t - _out_at) / maxf(fade_out_time, 0.01)
		_root.modulate.a = 1.0 - clampf(o, 0.0, 1.0)
		if o >= 1.0:
			finish()
