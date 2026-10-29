extends CanvasLayer
class_name BarkBubble
## Мини-реплика в бою без паузы — тот же единственный пузырь внизу по центру, что и у Одина (П6), но с портретом.
## Для Одина используется пузырь HUD (Odin.line_spoken); этот — для остальных (босс, Локи, Брокк, вороны…).
## Показ одного прячет другой (HUD.hide_odin_line / hide_now).

## Ширина пузыря и отступ его низа от низа экрана (общие с пузырём Одина в HUD), px
const WIDTH := 470.0
const BOTTOM := 158.0

## Сколько секунд держится пузырь (плюс по 0.035 с на букву)
@export var hold_time: float = 2.2
@export var max_hold_time: float = 4.0

var _panel: PanelContainer
var _portrait: Portrait
var _name: Label
var _text: Label
var _tween: Tween

func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	UIStyle.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = UIStyle.panel(Color(0.05, 0.05, 0.07, 0.86), Color(UIStyle.GOLD, 0.5))
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -WIDTH * 0.5
	_panel.offset_right = WIDTH * 0.5
	_panel.offset_top = -BOTTOM - 80
	_panel.offset_bottom = -BOTTOM
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.modulate.a = 0.0
	root.add_child(_panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(hb)
	_portrait = Portrait.new()
	_portrait.compact = true
	_portrait.custom_minimum_size = Vector2(60, 70)
	hb.add_child(_portrait)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	_name = UIStyle.label("", 15, UIStyle.GOLD, 4)
	vb.add_child(_name)
	_text = UIStyle.label("", 19, UIStyle.TEXT, 5)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(WIDTH - 130.0, 0)
	vb.add_child(_text)

## Полные границы, включая выступающую рамку картинки.
func visual_rect() -> Rect2:
	if not is_instance_valid(_panel):
		return Rect2()
	var rect := Rect2(Vector2.ZERO, _panel.size)
	var style := _panel.get_theme_stylebox("panel") as SkinStyleBox
	if style:
		rect = style._draw_rect_of(rect)
	return _panel.get_global_transform_with_canvas() * rect

## Убрать сразу (заговорил Один)
func hide_now() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if _panel:
		_panel.modulate.a = 0.0

func show_line(speaker: String, emotion: String, text: String) -> void:
	var def: Dictionary = Dialogue.speakers.get(speaker, {})
	var col := Color.from_string(str(def.get("color", "#888888")), Color.GRAY)
	_portrait.set_speaker(speaker, emotion, def, 0.08)
	_name.text = str(def.get("name", speaker)).to_upper()
	_name.label_settings.font_color = col.lightened(0.3)
	if not UISkin.texture("panel_dialogue"):
		_panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.05, 0.05, 0.07, 0.86), Color(col, 0.7)))
	_text.label_settings.font_size = int(19 * GameSettings.text_scale())
	_text.text = text
	# Один пузырь: реплика прячет пузырь Одина
	var game := get_tree().current_scene as Game
	if game and game.hud:
		game.hud.hide_odin_line()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = _panel.create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.18)
	_tween.tween_interval(clampf(hold_time + text.length() * 0.035, hold_time, max_hold_time))
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.4)
