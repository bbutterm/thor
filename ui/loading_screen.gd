extends CanvasLayer
class_name LoadingScreen
## Загрузочный экран: случайная картинка sprites/loading/1..8.webp + совет / шутка Одина (пул odin.loading).
## Показ — пока грузится забег (главное меню / «Заново» → show_now() → смена сцены → Game._ready:
## AssetCache.finish(), первый зал) и между залами под затемнением (transition()). Скрывает Game после
## загрузки зала (finish()). Загрузку не удлиняет: ждёт только кадр, чтобы картинка успела нарисоваться.
## Живёт на корне дерева (переживает смену сцены), одна на игру. Картинки держит AssetCache.

## Сколько исчезает после загрузки зала, с (игра под ним уже идёт — «осмотреться»)
@export var fade_out_time: float = 0.6
## Если никто не скрыл (сцена без Game), спрятаться самой через столько секунд
@export var safety_time: float = 12.0

static var _inst: LoadingScreen
## Последняя показанная картинка (1..8) — подряд одна и та же не выпадает
static var last_index: int = -1
## Сколько раз показан (тесты)
static var shown_count: int = 0

var tip: String = ""
var _root: Control
var _pic: TextureRect
var _tip_label: Label
var _alpha: float = 0.0
var _target: float = 0.0
var _speed: float = 4.0
var _shown_for: float = 0.0

static func instance(tree: SceneTree) -> LoadingScreen:
	if _inst == null or not is_instance_valid(_inst):
		_inst = LoadingScreen.new()
		_inst.name = "LoadingScreen"
		tree.root.add_child(_inst)
	return _inst

## Сразу на весь экран и дождаться, пока нарисуется (перед долгой загрузкой в главном потоке).
static func show_now(tree: SceneTree) -> void:
	var ls := instance(tree)
	ls._show(0.0)
	await tree.process_frame
	await tree.process_frame

## Плавно (вместе с затемнением HUD) — переход между залами.
static func transition(tree: SceneTree, fade_time: float = 0.25) -> void:
	instance(tree)._show(fade_time)

## Загрузка закончилась: плавно убрать (если показан).
static func finish(tree: SceneTree) -> void:
	if _inst and is_instance_valid(_inst) and _inst._target > 0.0:
		_inst._hide(_inst.fade_out_time)

static func is_showing() -> bool:
	return _inst != null and is_instance_valid(_inst) and _inst.visible and _inst._target > 0.0

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()

func _build() -> void:
	_root = Control.new()
	UIStyle.full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03)
	UIStyle.full_rect(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_pic = TextureRect.new()
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	UIStyle.full_rect(_pic)
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_pic)
	# Слева у картинок тёмное поле — туда совет; градиент, чтобы читалось на любой
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.82))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 4
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 720
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 56
	box.offset_right = 56 + 470
	box.offset_top = -290
	box.offset_bottom = -60
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	box.add_child(UIStyle.label(tr("СОВЕТ ОДИНА"), 20, Color(0.55, 0.68, 1.0), 5))
	_tip_label = UIStyle.label("", 24, UIStyle.TEXT, 6)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(470, 0)
	box.add_child(_tip_label)
	var load_l := UIStyle.label(tr("Загрузка…"), 16, Color(UIStyle.GOLD, 0.8), 4)
	load_l.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	load_l.offset_left = -260
	load_l.offset_right = -40
	load_l.offset_top = -64
	load_l.offset_bottom = -30
	load_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(load_l)

## Новая картинка и совет; fade_time 0 — сразу.
func _show(fade_time: float) -> void:
	var i := randi() % ScreenArt.LOADING_COUNT
	if i == last_index:
		i = (i + 1) % ScreenArt.LOADING_COUNT
	last_index = i
	_pic.texture = ScreenArt.tex(ScreenArt.loading_path(i))
	tip = Dialogue.pool_text("odin.loading")
	_tip_label.text = tip
	_tip_label.get_parent().visible = tip != ""
	shown_count += 1
	_shown_for = 0.0
	visible = true
	_target = 1.0
	if fade_time <= 0.0:
		_alpha = 1.0
	else:
		_speed = 1.0 / fade_time
	_apply()

func _hide(fade_time: float) -> void:
	_target = 0.0
	_speed = 1.0 / maxf(fade_time, 0.01)

func _apply() -> void:
	_root.modulate.a = _alpha
	visible = _alpha > 0.001 or _target > 0.0

func _process(delta: float) -> void:
	if not visible:
		return
	# После долгой загрузки в главном потоке кадр «длится» секунды — не проскакиваем исчезновение
	var dt := minf(FX.real_delta(delta), 1.0 / 30.0)
	_shown_for += dt
	if _target > 0.0 and _shown_for > safety_time:
		_hide(fade_out_time)
	_alpha = move_toward(_alpha, _target, _speed * dt)
	_apply()
