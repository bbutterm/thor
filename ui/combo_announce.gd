extends CanvasLayer
class_name ComboAnnounce
## Объявление связки «стихия + приём» (блок Б4, GDD 10): особая карточка-плашка сверху экрана —
## «СВЯЗКА!», иконки стихии и приёма, название и что делает. Не ставит на паузу и не ловит мышь;
## видна и поверх выбора руны (слой 12, работает на паузе), уходит сама через MjolnirRules.combo_card_time.
## Комикс-слово и реплику Одина запускает Game._on_combo_unlocked. Строится кодом.

const GOLD := Color(1.0, 0.78, 0.3)
@export var width: float = 620.0

var combo: MjolnirTrait
var _root: Control
var _panel: PanelContainer
var _tw: Tween

## Показать связку c (один узел на сцену — повторный вызов заменяет показ)
static func show_combo(parent: Node, c: MjolnirTrait) -> ComboAnnounce:
	if parent == null or c == null or not parent.is_inside_tree():
		return null
	var a := parent.get_node_or_null("ComboAnnounce") as ComboAnnounce
	if a == null:
		a = ComboAnnounce.new()
		a.name = "ComboAnnounce"
		parent.add_child(a)
	a.present(c)
	return a

func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.full_rect(_root)
	UISkin.apply(_root)
	add_child(_root)
	visible = false

func present(c: MjolnirTrait) -> void:
	Perf.mark("combo_announce")
	combo = c
	if _panel and is_instance_valid(_panel):
		_panel.queue_free()
	if _tw and _tw.is_valid():
		_tw.kill()
	_panel = UIStyle.panel(Color(0.04, 0.07, 0.13, 0.94), Color(GOLD, 0.9), "plate")
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(width, 0)
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	_panel.offset_top = 70
	_root.add_child(_panel)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 14)
	_panel.add_child(hb)
	var el := Run.mjolnir_trait_def(c.combo_element)
	var te := Run.mjolnir_trait_def(c.combo_technique)
	hb.add_child(_icon(el))
	var plus := UIStyle.label("+", 30, GOLD, 6)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(plus)
	hb.add_child(_icon(te))
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	hb.add_child(vb)
	vb.add_child(UIStyle.label(tr("СВЯЗКА!  %s") % tr(c.title).to_upper(), 26, GOLD, 8))
	var parts := UIStyle.label("%s + %s" % [tr(el.title) if el else "?", tr(te.title) if te else "?"], 15, c.color.lightened(0.3), 4)
	vb.add_child(parts)
	var d := UIStyle.label(tr(c.description), 15, UIStyle.TEXT, 4)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(width - 200, 0)
	vb.add_child(d)
	visible = true
	_panel.modulate.a = 0.0
	_panel.pivot_offset = Vector2(width * 0.5, 40)
	_panel.scale = Vector2(1.25, 1.25)
	_tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tw.set_parallel(true)
	_tw.tween_property(_panel, "modulate:a", 1.0, 0.18)
	_tw.tween_property(_panel, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.chain().tween_interval(maxf(Run.rules().combo_card_time - 0.6, 0.3))
	_tw.chain().tween_property(_panel, "modulate:a", 0.0, 0.4)
	_tw.chain().tween_callback(func() -> void: visible = false)

func is_showing() -> bool:
	return visible

func _icon(t: MjolnirTrait) -> Control:
	var tex := UISkin.trait_icon(str(t.id)) if t else null
	if tex:
		var icon := HudIcon.make(tex, 64)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return icon
	var ring := PanelContainer.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	var col := t.color if t else GOLD
	sb.bg_color = Color(0.03, 0.06, 0.12, 0.85)
	sb.border_color = col
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(30)
	ring.add_theme_stylebox_override("panel", sb)
	ring.custom_minimum_size = Vector2(60, 60)
	var g := UIStyle.label(t.glyph if t else "?", 32, col, 4)
	g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ring.add_child(g)
	return ring
