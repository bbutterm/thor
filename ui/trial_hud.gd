extends CanvasLayer
class_name TrialHUD
## Панель испытания (блок Ф): ведущий, условие, таймер / счётчик / ожог, итог. Слева сверху под залом.

const HOST_NAMES := {"odin": "ОДИН", "hild": "ХИЛЬД", "loki": "ЛОКИ"}

var _panel: PanelContainer
var _host: Label
var _title: Label
var _cond: Label
var _timer: Label
var _status: Label
var _def: TrialDef

func _ready() -> void:
	layer = 5
	var root := Control.new()
	UIStyle.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = UIStyle.panel(Color(0.05, 0.05, 0.07, 0.82), Color(UIStyle.GOLD, 0.6))
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = 28
	_panel.offset_top = 96
	_panel.offset_right = 470
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vb)
	_host = UIStyle.label("", 15, UIStyle.GOLD, 4)
	vb.add_child(_host)
	_title = UIStyle.label("", 22, UIStyle.TEXT, 6)
	vb.add_child(_title)
	_cond = UIStyle.label("", 15, UIStyle.TEXT_DIM, 3)
	_cond.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cond.custom_minimum_size = Vector2(410, 0)
	vb.add_child(_cond)
	_timer = UIStyle.label("", 26, UIStyle.ICE, 6)
	vb.add_child(_timer)
	_status = UIStyle.label("", 18, UIStyle.TEXT, 5)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(410, 0)
	vb.add_child(_status)

func setup(d: TrialDef) -> void:
	_def = d
	var sp: Dictionary = Dialogue.speakers.get(d.host, {})
	var col := Color.from_string(str(sp.get("color", "#e0b050")), UIStyle.GOLD).lightened(0.25)
	_host.text = tr("ИСПЫТАНИЕ · %s") % tr(HOST_NAMES.get(d.host, d.host.to_upper()))
	_host.label_settings.font_color = col
	_panel.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0.05, 0.05, 0.07, 0.82), Color(col, 0.75)))
	_title.text = tr(d.title)
	_cond.text = tr("%s · награда: %s") % [tr(d.condition), d.reward_text()]
	_status.text = ""
	_panel.pivot_offset = Vector2(0, 0)
	_panel.scale = Vector2(1.15, 1.15)
	var tw := _panel.create_tween()
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)

static func fmt(sec: float) -> String:
	var s := maxi(0, int(ceil(sec)))
	return "%d:%02d" % [s / 60, s % 60]

func update_state(t: TrialRunner) -> void:
	match _def.kind:
		"time_limit":
			_timer.text = tr("Осталось %s") % fmt(_def.time_limit - t.elapsed)
		"kill_count":
			_timer.text = tr("Убийств: %d / %d · %s") % [t.kills, _def.target, fmt(_def.time_limit - t.elapsed)]
		"floor_lava":
			_timer.text = tr("Ожог: %.1f / %.0f с · %s") % [t.burn, _def.lava_max_burn, fmt(t.elapsed)]
		_:
			_timer.text = fmt(t.elapsed)
	match t.state:
		"passed":
			_status.text = tr("ПРОЙДЕНО! Награда после зачистки: %s") % _def.reward_text()
			_status.label_settings.font_color = Color(0.55, 1.0, 0.6)
		"failed":
			_status.text = tr("ПРОВАЛ: %s") % t.fail_reason
			_status.label_settings.font_color = Color(1.0, 0.45, 0.4)
		_:
			_status.text = ""
