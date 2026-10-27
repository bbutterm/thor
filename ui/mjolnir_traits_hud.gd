extends HBoxContainer
class_name MjolnirTraitsHud
## Иконки активных трейтов Мьёльнира (отдельно от рун) — слева внизу, над здоровьем и строкой молота.
## Иконка трейта из UI-комплекта (нет — руна в круге цвета трейта), уровень в углу. Справа — «ИДЕАЛЬНЫЙ ХВАТ ×2», пока следующий бросок усилен.

var player: Player
var _icons: HBoxContainer
var _perfect: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 28
	offset_right = 600
	offset_top = -214
	offset_bottom = -156
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 14)
	_icons = HBoxContainer.new()
	_icons.add_theme_constant_override("separation", 8)
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icons)
	_perfect = UIStyle.label(tr("ИДЕАЛЬНЫЙ ХВАТ ×2"), 18, UIStyle.GOLD, 6)
	_perfect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_perfect.visible = false
	add_child(_perfect)
	Run.mjolnir_traits_changed.connect(_rebuild)
	_rebuild(Run.mjolnir_traits)

func _process(_delta: float) -> void:
	var on := player != null and is_instance_valid(player) and player.mjolnir.perfect_ready
	if on != _perfect.visible:
		_perfect.visible = on

func _rebuild(traits: Array = []) -> void:
	for c in _icons.get_children():
		c.queue_free()
	for t in traits:
		var mt := t as MjolnirTrait
		if mt == null:
			continue
		_icons.add_child(_icon(mt, Run.mjolnir_trait_level(mt.id)))

func _icon(t: MjolnirTrait, level: int) -> Control:
	# Иконка трейта из комплекта (UISkin.trait_icon); нет картинки — руна в круге цвета трейта
	var tex := UISkin.trait_icon(str(t.id))
	if tex:
		var icon := HudIcon.make(tex, 44)
		icon.badge = "I" if level <= 1 else "II"
		icon.badge_color = t.color.lightened(0.3)
		icon.tooltip_text = tr(t.title)
		return icon
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	var ring := PanelContainer.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.06, 0.12, 0.8)
	sb.border_color = t.color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(20)
	ring.add_theme_stylebox_override("panel", sb)
	ring.custom_minimum_size = Vector2(40, 40)
	var g := UIStyle.label(t.glyph, 24, t.color, 4)
	g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ring.add_child(g)
	box.add_child(ring)
	var l := UIStyle.label("I" if level <= 1 else "II", 12, UIStyle.TEXT_DIM, 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	box.tooltip_text = tr(t.title)
	return box
