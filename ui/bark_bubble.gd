extends CanvasLayer
class_name BarkBubble
## Мини-реплика в бою без паузы: маленький пузырь в правом нижнем углу с портретом.
## Для Одина используется пузырь HUD (Odin.line_spoken); этот — для остальных (босс, Локи, Брокк…).

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
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -520
	_panel.offset_right = -28
	_panel.offset_top = -250
	_panel.offset_bottom = -150
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
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
	_portrait.custom_minimum_size = Vector2(72, 84)
	hb.add_child(_portrait)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	_name = UIStyle.label("", 16, UIStyle.GOLD, 4)
	vb.add_child(_name)
	_text = UIStyle.label("", 19, UIStyle.TEXT, 5)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(320, 0)
	vb.add_child(_text)

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
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = _panel.create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.18)
	_tween.tween_interval(clampf(hold_time + text.length() * 0.035, hold_time, max_hold_time))
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.4)
