extends Button
class_name SkinCard
## Карточка выбора на графике комплекта: card_rune (руны, выбор наград) или card_trait (трейты Мьёльнира).
## Картинка масштабируется только равномерно (README комплекта); сверху — круг под иконку, ниже — окно
## под название и описание. Наведение/фокус — рамка редкости card_rarity_* поверх (своя у каждой карточки).
## Содержимое кладут в icon_box (круг) и body (окно текста); key_label — «[1]» в углу.
## Нет картинок — плоская карточка UIStyle (как раньше).

## Видимая часть картинки и места под содержимое — пиксели исходника 512×704
const VISIBLE := Rect2(61, 91, 390, 522)
const CIRCLE_CENTER := Vector2(260, 216)
const CIRCLE_RADIUS := 66.0
const TEXT_BOX := Rect2(158, 318, 200, 222)

var card_id: String = "card_rune"
var rarity: String = "rare"
var accent: Color = UIStyle.GOLD
var icon_box: CenterContainer
var body: VBoxContainer
var key_label: Label

## width — видимая ширина карточки на экране (высота — по пропорциям)
static func make(id: String, width: float, accent_color: Color, rarity_id: String = "rare") -> SkinCard:
	var c := SkinCard.new()
	c.card_id = id
	c.rarity = rarity_id
	c.accent = accent_color
	c._build(width)
	return c

## Масштаб экрана к пикселям исходника
func _k(width: float) -> float:
	return width / VISIBLE.size.x

func _build(width: float) -> void:
	var k := _k(width)
	custom_minimum_size = VISIBLE.size * k
	focus_mode = Control.FOCUS_ALL
	var tex := UISkin.texture(card_id)
	if tex:
		var grow := Vector4(VISIBLE.position.x, VISIBLE.position.y, 512.0 - VISIBLE.end.x, 704.0 - VISIBLE.end.y) * k
		var normal := _style(tex, grow, Color.WHITE, null)
		var glow := UISkin.texture("card_rarity_" + rarity)
		add_theme_stylebox_override("normal", normal)
		add_theme_stylebox_override("hover", _style(tex, grow, Color(1.12, 1.12, 1.12), glow))
		add_theme_stylebox_override("pressed", _style(tex, grow, Color(1.25, 1.2, 1.1), glow))
		add_theme_stylebox_override("hover_pressed", _style(tex, grow, Color(1.25, 1.2, 1.1), glow))
		add_theme_stylebox_override("disabled", _style(tex, grow, Color(0.5, 0.5, 0.52), null))
		var f := _style(tex, grow, Color(1, 1, 1, 0), glow)
		f.overlay_modulate = Color(1, 1, 1, 0.8)
		add_theme_stylebox_override("focus", f)
	else:
		add_theme_stylebox_override("normal", UIStyle.panel_style(UIStyle.STONE_LIGHT, Color(accent, 0.5), 12))
		add_theme_stylebox_override("hover", UIStyle.panel_style(Color(0.2, 0.19, 0.22, 0.98), accent, 12, 3))
		add_theme_stylebox_override("focus", UIStyle.panel_style(Color(0.2, 0.19, 0.22, 0.98), accent, 12, 3))
		add_theme_stylebox_override("pressed", UIStyle.panel_style(Color(0.26, 0.24, 0.28, 1.0), accent, 12, 3))
	# Круг под иконку
	icon_box = CenterContainer.new()
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cc := (CIRCLE_CENTER - VISIBLE.position) * k
	var r := CIRCLE_RADIUS * k
	icon_box.position = cc - Vector2(r, r)
	icon_box.size = Vector2(r, r) * 2.0
	add_child(icon_box)
	# Окно текста
	body = VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 4)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.position = (TEXT_BOX.position - VISIBLE.position) * k
	body.size = TEXT_BOX.size * k
	body.clip_contents = true
	add_child(body)
	key_label = UIStyle.label("", 16, UIStyle.TEXT_DIM, 5)
	key_label.position = Vector2(10, 4) * k / 0.8
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(key_label)

func _style(tex: Texture2D, grow: Vector4, mod: Color, glow: Texture2D) -> SkinStyleBox:
	var s := SkinStyleBox.new()
	s.texture = tex
	s.mode = SkinStyleBox.Mode.FIT
	s.grow = grow
	s.modulate = mod
	s.overlay = glow
	return s

## Ширина текста в окне (для autowrap)
func text_width() -> float:
	return body.size.x

## Иконка в круг: картинка (TextureRect) или руна-глиф
func set_icon(tex: Texture2D, glyph: String = "", color: Color = Color.WHITE) -> void:
	for c in icon_box.get_children():
		c.queue_free()
	var d := icon_box.size.x
	if tex:
		var trect := TextureRect.new()
		trect.texture = tex
		trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		trect.custom_minimum_size = Vector2(d, d) * 0.86
		trect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_box.add_child(trect)
		if glyph != "":
			# Руна поверх картинки категории — в углу круга
			var g := UIStyle.label(glyph, int(d * 0.3), color, 6)
			g.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(g)
			g.position = icon_box.position + Vector2(d * 0.66, d * 0.6)
	else:
		var gl := UIStyle.label(glyph, int(d * 0.6), color, 8)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_box.add_child(gl)

## Строка текста в окне (название, описание, статус)
func add_text(text: String, font_size: int, color: Color, outline: int = 4) -> Label:
	var l := UIStyle.label(text, font_size, color, outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(body.size.x, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if body.get_child_count() == 0:
		# Заголовок не должен делить слово на отдельные буквы, даже на узкой карточке.
		var words := text.replace("\n", " ").replace("\t", " ").split(" ", false)
		var available := maxf(1.0, body.size.x - outline * 2.0)
		var size := font_size
		while size > 8:
			var longest := 0.0
			for word in words:
				longest = maxf(longest, l.label_settings.font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
			if longest <= available:
				break
			size -= 1
		l.label_settings.font_size = size
	l.set_meta("preferred_font_size", l.label_settings.font_size)
	body.add_child(l)
	return l
