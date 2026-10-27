extends CanvasLayer
class_name ComicInsert
## Общее у комиксовых вставок поверх боя (BossCard — заставка босса, ComicPage — «страница комикса»):
## игра на паузе, своё время (FX.real_delta — не зависит от hit-stop), пропуск кликом / клавишей / кнопкой
## геймпада после короткой защиты, одна вставка за раз; пока идёт сцена-новелла (интро босса) — ждём её конца.
## Наследник рисует в _build() и двигает всё в _tick(t); закончил — finish().

signal closed

## Защита от случайного пропуска (игрок как раз жмёт атаку), с
@export var skip_guard: float = 0.3

## Открытая сейчас вставка (одна за раз; тесты и Game смотрят сюда)
static var current: ComicInsert

## Сколько секунд вставка на экране (реальное время)
var age: float = 0.0
## Попросили пропустить (клик после skip_guard)
var skipped: bool = false
var _was_paused: bool = false
var _started: bool = false
var _closing: bool = false

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Дождаться своей очереди (другая вставка, сцена-новелла) и поставить игру на паузу.
func begin() -> void:
	while is_inside_tree() and (Dialogue.is_playing() or _other_open()):
		await get_tree().process_frame
	if not is_inside_tree():
		return
	current = self
	_was_paused = get_tree().paused
	get_tree().paused = true
	_started = true
	age = 0.0

func _other_open() -> bool:
	return current != null and is_instance_valid(current) and current != self and not current._closing

func is_running() -> bool:
	return _started and not _closing

func _process(delta: float) -> void:
	if not _started or _closing:
		return
	age += FX.real_delta(delta)
	_tick(age)

## Кадр анимации (переопределить). t — секунды с начала.
func _tick(_t: float) -> void:
	pass

func skip() -> void:
	if is_running() and age >= skip_guard:
		skipped = true

## Снять паузу, сообщить и исчезнуть.
func finish() -> void:
	if _closing:
		return
	_closing = true
	if _started and is_inside_tree():
		get_tree().paused = _was_paused
	if current == self:
		current = null
	closed.emit()
	queue_free()

func _exit_tree() -> void:
	if current == self:
		current = null

func _input(event: InputEvent) -> void:
	if not is_running():
		return
	var press: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if press:
		skip()
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()

## Плавный «удар» 0..1 (быстро в начале, с лёгким перелётом в конце)
static func ease_back(x: float, overshoot: float = 1.6) -> float:
	var t := clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + t * t * ((overshoot + 1.0) * t + overshoot)

static func ease_out(x: float) -> float:
	var t := 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - t * t * t
