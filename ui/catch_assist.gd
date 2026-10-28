extends Control
class_name CatchAssist
## Подсказка идеального хвата Мьёльнира (вокруг прицела), пока молот летит обратно:
## - сходящееся кольцо: радиус = цель + время до поимки (MjolnirProjectile.catch_eta), сходится с целевым ровно в момент поимки;
## - целевое кольцо золотеет и «дышит», пока открыто эффективное окно хвата до и после поимки;
## - стрелка на кольце — откуда летит молот (если он за спиной или сбоку);
## - после попытки — «ИДЕАЛЬНО!» / «РАНО» / «ПОЗДНО» (сигнал MjolnirHand.catch_timing).
## Рисуется draw_arc стандартным 2D-материалом — новых шейдеров и материалов нет. Выключатель — [access] catch_assist.
## Создаёт VfxScreen._ready.

## Радиус целевого кольца, px (при 1280×720)
@export var target_radius: float = 34.0
## На сколько px шире кольцо за каждую секунду до поимки
@export var px_per_second: float = 150.0
## За сколько секунд до поимки появляется сходящееся кольцо
@export var lead_time: float = 0.8
@export var ring_width: float = 3.0
@export var ring_color: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var target_color: Color = Color(1.0, 1.0, 1.0, 0.35)
@export var window_color: Color = Color(1.0, 0.8, 0.25, 1.0)
## Ширина и пульсация целевого кольца в окне хвата
@export var window_width: float = 6.0
@export var window_pulse_hz: float = 9.0
## Стрелка «откуда летит», px
@export var arrow_size: float = 11.0
## Подписи итога: сколько висят (с) и цвета
@export var feedback_time: float = 0.7
@export var perfect_text_color: Color = Color(1.0, 0.82, 0.3)
@export var miss_text_color: Color = Color(0.85, 0.85, 0.9)

var player: Player
var _eta: float = -1.0
var _window: bool = false
var _arrow_angle: float = 0.0
var _arrow_on: bool = false
var _t: float = 0.0
var _key: Label
var _feedback: Label
var _feedback_left: float = 0.0
var _hand: MjolnirHand
var _enabled: bool = true
## Нажал раньше окна — на этот возврат хват провален: кольцо красное до поимки
var _failed: bool = false
@export var fail_color: Color = Color(1.0, 0.3, 0.25, 0.9)

static func attach(parent: Node, p: Player) -> CatchAssist:
	var c := CatchAssist.new()
	c.name = "CatchAssist"
	c.player = p
	parent.add_child(c)
	return c

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key = _label(18)
	_feedback = _label(22)
	_feedback.visible = false
	_enabled = GameSettings.catch_assist()
	GameSettings.events.changed.connect(func(section: String, key: String) -> void:
		if section == "access" and key == "catch_assist":
			_enabled = GameSettings.catch_assist())

func _label(size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.outline_size = 6
	ls.outline_color = Color(0, 0, 0, 0.85)
	l.label_settings = ls
	add_child(l)
	return l

func _hook_hand() -> void:
	var h: MjolnirHand = player.mjolnir if player else null
	if h == _hand:
		return
	_hand = h
	if _hand:
		_hand.catch_timing.connect(_on_timing)

func _on_timing(result: StringName, offset: float) -> void:
	if not _enabled:
		return
	match result:
		&"perfect":
			_feedback.text = tr("ИДЕАЛЬНО!")
			_feedback.label_settings.font_color = perfect_text_color
		&"early":
			_failed = true
			_feedback.text = tr("РАНО · %d мс") % int(round(absf(offset) * 1000.0))
			_feedback.label_settings.font_color = miss_text_color
		_:
			_feedback.text = tr("ПОЗДНО · %d мс") % int(round(absf(offset) * 1000.0))
			_feedback.label_settings.font_color = miss_text_color
	_feedback.visible = true
	_feedback_left = feedback_time

func _process(delta: float) -> void:
	_t += delta
	_hook_hand()
	_eta = -1.0
	_window = false
	_arrow_on = false
	if _hand and _hand.in_hand and _hand.perfect_window_left() < 0.0:
		_failed = false
	if _enabled and _hand and not player.is_dead:
		var proj := _hand.projectile
		if proj and is_instance_valid(proj):
			_eta = proj.catch_eta()
			if _eta > lead_time:
				_eta = -1.0
			if _eta >= 0.0:
				_window = _eta <= _hand.effective_perfect_window() and not _failed
				_aim_arrow(proj.global_position)
		elif _hand.perfect_window_left() >= 0.0 and not _failed:
			_eta = 0.0
			_window = true
	_key.visible = _eta >= 0.0
	if _key.visible:
		_key.text = Tutorial.key_name("throw")
		var c := get_viewport_rect().size * 0.5
		_key.size = Vector2(160, 30)
		_key.position = c + Vector2(-80, target_radius + 10.0)
		_key.label_settings.font_color = window_color if _window else Color(1, 1, 1, 0.8)
		var s := 1.0 + (0.18 * absf(sin(_t * TAU * window_pulse_hz * 0.5)) if _window else 0.0)
		_key.pivot_offset = _key.size * 0.5
		_key.scale = Vector2.ONE * s
	if _feedback_left > 0.0:
		_feedback_left -= delta
		var c2 := get_viewport_rect().size * 0.5
		_feedback.size = Vector2(320, 34)
		_feedback.position = c2 + Vector2(-160, target_radius + 38.0)
		_feedback.modulate.a = clampf(_feedback_left / (feedback_time * 0.4), 0.0, 1.0)
		if _feedback_left <= 0.0:
			_feedback.visible = false
	queue_redraw()

## Направление на молот в экране; стрелка нужна, только когда он не перед прицелом
func _aim_arrow(world: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Проекция точки в плоскости камеры не определена; сохраняем сторону и направление стрелки.
	var camera_transform := cam.get_camera_transform()
	var depth := (camera_transform.affine_inverse() * world).z
	if absf(depth) < 0.05:
		var safe_depth := 0.05 if depth > 0.0 else -0.05
		world += camera_transform.basis.z * (safe_depth - depth)
	var c := get_viewport_rect().size * 0.5
	var sp := cam.unproject_position(world)
	var d := sp - c
	if cam.is_position_behind(world):
		d = -d
	if d.length() < target_radius * 2.5 and not cam.is_position_behind(world):
		return
	_arrow_on = true
	_arrow_angle = d.angle()

func _draw() -> void:
	if _eta < 0.0:
		return
	var vs := get_viewport_rect().size
	var c := vs * 0.5
	var k := vs.y / 720.0
	var r0 := target_radius * k
	if _window:
		var pulse := 0.5 + 0.5 * sin(_t * TAU * window_pulse_hz)
		draw_arc(c, r0, 0.0, TAU, 48, window_color, window_width * k * (0.8 + 0.4 * pulse), true)
	else:
		draw_arc(c, r0, 0.0, TAU, 48, target_color, ring_width * k, true)
		var r := r0 + _eta * px_per_second * k
		var col := fail_color if _failed else ring_color
		col.a *= clampf(1.0 - _eta / lead_time + 0.25, 0.0, 1.0)
		draw_arc(c, r, 0.0, TAU, 64, col, ring_width * k, true)
	if _arrow_on:
		var dir := Vector2.from_angle(_arrow_angle)
		var tip := c + dir * (r0 + arrow_size * 1.6 * k)
		var base := c + dir * (r0 + 2.0 * k)
		var side := dir.orthogonal() * arrow_size * 0.6 * k
		draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), window_color if _window else ring_color)
