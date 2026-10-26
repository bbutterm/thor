extends RefCounted
class_name UIStyle
## Общий стиль интерфейса: тёмный камень, золото Асгарда, лёд Мьёльнира.
## Кнопки и панели — на графике комплекта владельца (ui/ui_skin.gd), цвета и шрифт — здесь.

const GOLD := Color(0.93, 0.71, 0.3)
const ICE := Color(0.5, 0.83, 1.0)
const BLOOD := Color(0.86, 0.22, 0.18)
const STONE := Color(0.07, 0.07, 0.09, 0.86)
const STONE_LIGHT := Color(0.16, 0.15, 0.17, 0.95)
const TEXT := Color(0.95, 0.93, 0.88)
const TEXT_DIM := Color(0.7, 0.68, 0.64)

static func font() -> Font:
	return load("res://fonts/RussoOne-Regular.ttf")

static func label(text: String, size: int = 22, color: Color = TEXT, outline: int = 6) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = font()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = Color(0, 0, 0, 0.75)
	l.label_settings = ls
	return l

static func panel_style(bg: Color = STONE, border: Color = Color(GOLD, 0.6), radius: int = 10, border_w: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	return sb

## Панель на графике комплекта (UISkin). kind: "" — тёмная рамка panel_dialogue (широкие и невысокие:
## реплики, подсказки), "wood" — деревянная рамка panel_training (высокие списки и окна; scale 0.3),
## "window" — она же крупнее (пауза, настройки), "plate" — железная плашка panel_nameplate (счётчики).
## Нет картинок — плоская панель цветов bg/border.
static func panel(bg: Color = STONE, border: Color = Color(GOLD, 0.6), kind: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	var spec: Array = {"wood": ["panel_training", 0.3], "window": ["panel_training", 0.42],
		"plate": ["panel_nameplate", 0.34]}.get(kind, ["panel_dialogue", 0.3])
	if UISkin.texture(spec[0]):
		p.add_theme_stylebox_override("panel", UISkin.stylebox(spec[0], spec[1], 6))
	else:
		p.add_theme_stylebox_override("panel", panel_style(bg, border))
	return p

## Старая плоская панель (карточки, ячейки, где рамка комплекта не по размеру)
static func flat_panel(bg: Color = STONE, border: Color = Color(GOLD, 0.6)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, border))
	return p

## kind — картинка комплекта: main (основная), secondary (второстепенная), danger (опасное действие)
static func button(text: String, size: int = 24, kind: String = "main") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	b.add_theme_constant_override("outline_size", 5)
	if UISkin.texture("button_main_normal"):
		# Кнопки комплекта (UISkin): main / secondary / danger
		UISkin.style_button(b, kind)
	else:
		b.add_theme_stylebox_override("normal", panel_style(STONE_LIGHT, Color(GOLD, 0.35), 8))
		b.add_theme_stylebox_override("hover", panel_style(Color(0.22, 0.19, 0.15, 0.98), GOLD, 8))
		b.add_theme_stylebox_override("focus", panel_style(Color(0.22, 0.19, 0.15, 0.98), GOLD, 8))
		b.add_theme_stylebox_override("pressed", panel_style(Color(0.3, 0.24, 0.14, 1.0), GOLD, 8))
	b.custom_minimum_size = Vector2(280, 56)
	return b

static func full_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
