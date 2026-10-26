extends HBoxContainer
class_name SilverHUD
## Счётчик серебра в HUD (блок К, GDD 18) — под Славой справа вверху.
## Иконка — sprites/ui/hud/hud_silver.png (UI_PROMPTS 3.8), если есть; иначе только текст.

const ICON := "res://sprites/ui/hud/hud_silver.png"
const COLOR := Color(0.86, 0.9, 1.0)

var _label: Label
var _shown: float = 0.0

## Встроить под надпись Славы в HUD.
static func attach(hud: HUD) -> SilverHUD:
	var glory := hud.get("_glory_label") as Label
	if glory == null or glory.get_parent() == null:
		return null
	var s := SilverHUD.new()
	s.name = "SilverHUD"
	var box := glory.get_parent()
	box.add_child(s)
	box.move_child(s, glory.get_index() + 1)
	return s

func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	if ResourceLoader.exists(ICON):
		var tr := TextureRect.new()
		tr.texture = load(ICON)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(30, 30)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
	_label = UIStyle.label("", 24, COLOR, 6)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_label)
	_shown = Run.silver
	_update_text()
	Run.silver_changed.connect(_on_silver_changed)

func _update_text() -> void:
	_label.text = "СЕРЕБРО %d" % int(round(_shown))

func _on_silver_changed(total: int) -> void:
	var up := total > _shown
	_shown = total
	_update_text()
	if up:
		pivot_offset = size * Vector2(1, 0.5)
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2(1.12, 1.12), 0.05)
		tw.tween_property(self, "scale", Vector2.ONE, 0.12)
