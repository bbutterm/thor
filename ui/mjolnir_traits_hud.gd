extends HBoxContainer
class_name MjolnirTraitsHud
## Иконки активных трейтов Мьёльнира (отдельно от рун) — слева внизу, над здоровьем и строкой молота.
## Порядок: стихия, приёмы, связки (золотая рамка). Иконка трейта из UI-комплекта (нет — руна в круге цвета
## трейта), уровень в углу римской цифрой. Справа — «ИДЕАЛЬНЫЙ ХВАТ ×2», пока следующий бросок усилен,
## и полоска удержания ПКМ (Заряд, Праща — MjolnirHand.hold_progress).

var player: Player
var _icons: HBoxContainer
var _perfect: Label
var _hold: Label

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
	_hold = UIStyle.label("", 18, UIStyle.ICE, 6)
	_hold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hold.visible = false
	add_child(_hold)
	Run.mjolnir_traits_changed.connect(_rebuild)
	_rebuild(Run.mjolnir_traits)

func _process(_delta: float) -> void:
	var ok := player != null and is_instance_valid(player)
	var on := ok and player.mjolnir.perfect_ready
	if on != _perfect.visible:
		_perfect.visible = on
	var hp := player.mjolnir.hold_progress if ok and player.mjolnir.holding else 0.0
	_hold.visible = hp > 0.0
	if _hold.visible:
		var n := int(round(hp * 10.0))
		_hold.text = "%s %s" % [tr(player.mjolnir.hold_label), "▮".repeat(n) + "▯".repeat(10 - n)]
		_hold.label_settings.font_color = UIStyle.GOLD if hp >= 1.0 else UIStyle.ICE

func _rebuild(traits: Array = []) -> void:
	for c in _icons.get_children():
		c.queue_free()
	var ordered: Array = []
	for t in traits:
		if t is MjolnirTrait and (t as MjolnirTrait).is_element():
			ordered.append(t)
	for t in traits:
		if t is MjolnirTrait and not (t as MjolnirTrait).is_element():
			ordered.append(t)
	for mt in ordered:
		_icons.add_child(_icon(mt, Run.mjolnir_trait_level(mt.id)))
	for c in Run.active_combos():
		_icons.add_child(_icon(c, 0))

func _icon(t: MjolnirTrait, level: int) -> Control:
	# Иконка трейта из комплекта (UISkin.trait_icon); нет картинки — руна в круге цвета трейта
	var tex := UISkin.trait_icon(str(t.id))
	var badge := "★" if t.is_combo() else TraitPick.roman(level)
	if tex:
		var icon := HudIcon.make(tex, 44)
		icon.badge = badge
		icon.badge_color = Color(1.0, 0.78, 0.3) if t.is_combo() else t.color.lightened(0.3)
		icon.tooltip_text = tr(t.title)
		return icon
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	var ring := PanelContainer.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.06, 0.12, 0.8)
	sb.border_color = Color(1.0, 0.78, 0.3) if t.is_combo() else t.color
	sb.set_border_width_all(3 if t.is_combo() else 2)
	sb.set_corner_radius_all(20)
	ring.add_theme_stylebox_override("panel", sb)
	ring.custom_minimum_size = Vector2(40, 40)
	var g := UIStyle.label(t.glyph, 24, t.color, 4)
	g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ring.add_child(g)
	box.add_child(ring)
	var l := UIStyle.label(badge, 12, UIStyle.TEXT_DIM, 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	box.tooltip_text = tr(t.title)
	return box
