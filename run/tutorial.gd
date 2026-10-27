extends Node
class_name Tutorial
## Обучение в первом зале (NIGHT_TASKS «если всё сделано»): Хугин и Мунин по очереди подсказывают механики.
## Шаг засчитывается, когда игрок сделал действие (или прошло step_timeout — тогда следующий шаг).
## Реплики — пулы ravens.tutorial_<шаг> в data/dialogues/ravens.json; {key_<действие>} — текущая клавиша из InputMap.
## Показывается в первом зале первых забегов, пока обучение не пройдено (событие сохранения «tutorial_done»).

## Шаги по порядку (id пула); условие «сделал» — _check / _mark.
const STEPS: Array[String] = ["move", "jump", "dash", "attack", "throw", "slam", "doors"]


## Сколько забегов подряд показывать, если игрок так и не прошёл все шаги
@export var max_runs: int = 2
## Пауза перед первой подсказкой и между подсказками (с)
@export var first_delay: float = 2.0
@export var step_gap: float = 1.2
## Через сколько секунд без действия показать следующую подсказку
@export var step_timeout: float = 14.0

var player: Player
var game: Game
var step: int = -1
var active: bool = false
var _t: float = 0.0
var _done_flag: bool = false
var _jumped_air: bool = false

static func attach(g: Game) -> Tutorial:
	var t := Tutorial.new()
	t.name = "Tutorial"
	t.game = g
	t.player = g.player
	g.add_child(t)
	return t

func should_run() -> bool:
	return Save.event_count("tutorial_done") == 0 and Save.event_count("tutorial_runs") < max_runs and Run.room_index == 0

func _ready() -> void:
	active = should_run()
	if not active:
		return
	Save.bump_event("tutorial_runs")
	_t = -first_delay
	player.slammed.connect(func(_p: float) -> void: _mark("slam"))
	if player.mjolnir:
		player.mjolnir.state_changed.connect(func(in_hand: bool) -> void:
			if not in_hand:
				_mark("throw"))
	if game.rewards and game.rewards.has_signal("doors_shown"):
		game.rewards.doors_shown.connect(func(_d: Array) -> void: _mark("doors"))

func _physics_process(delta: float) -> void:
	if not active or player == null or player.is_dead:
		return
	_t += delta
	if step < 0:
		if _t >= 0.0:
			_next()
		return
	var id := STEPS[step]
	if not _done_flag:
		_done_flag = _check(id)
	if _done_flag and _t >= step_gap:
		_next()
	elif _t >= step_timeout and id != "doors":
		_next()

func _check(id: String) -> bool:
	match id:
		"move":
			return player.horizontal_speed() > 3.0
		"jump":
			if not player.is_on_floor() and player._jumps_left < player.extra_jumps:
				_jumped_air = true
			return _jumped_air or player.extra_jumps == 0 and not player.is_on_floor()
		"dash":
			return player.is_dashing()
		"attack":
			return Input.is_action_pressed("attack")
	return false

func _mark(id: String) -> void:
	if active and step >= 0 and step < STEPS.size() and STEPS[step] == id:
		_done_flag = true

func _next() -> void:
	step += 1
	_t = 0.0
	_done_flag = false
	if step >= STEPS.size():
		active = false
		Save.bump_event("tutorial_done")
		return
	say(STEPS[step])

## Подсказка шага: реплика пула с подставленными клавишами.
func say(id: String) -> void:
	var lines := Dialogue.pool_lines("ravens.tutorial_" + id)
	if lines.is_empty():
		return
	var line: Dictionary = lines[0]
	line["text"] = keys_in(str(line.get("text", "")))
	Dialogue.bark(line)

## {key_jump} → «Пробел» и т. п. (первая привязка действия; переназначение клавиш учитывается само).
static func keys_in(text: String) -> String:
	var i := text.find("{key_")
	while i >= 0:
		var j := text.find("}", i)
		if j < 0:
			break
		var action := text.substr(i + 5, j - i - 5)
		text = text.substr(0, i) + key_name(action) + text.substr(j + 1)
		i = text.find("{key_")
	return text

static func key_name(action: String) -> String:
	return GameSettings.current_binding(action)

static func _ru_key(s: String) -> String:
	match s:
		"Space":
			return I18n.t("Пробел")
		"Shift":
			return "Shift"
		"Ctrl":
			return "Ctrl"
	return s
