extends Node
class_name Tutorial
## Реплики воронов: ravens.tutorial_<шаг>, клавиши подставляются из текущих настроек.
## Пройденное учитывается сразу, даже если нужная подсказка ещё не дошла до очереди.

const STEPS: Array[String] = ["move", "jump", "dash", "attack", "weapon_skill", "throw", "runes", "slam", "doors", "build", "vertical"]
const NEW_STEPS: Array[String] = ["weapon_skill", "runes"]
const VERTICAL_STEP := "vertical"

# При пересоздании Game переносим остаток интервала; время в меню тоже учитывается.
static var _carry_hint_wait: float = 0.0
static var _carry_wall_msec: int = 0

@export var max_runs: int = 2
@export var first_delay: float = 2.0
## Общее ограничение для всех подсказок, в том числе вертикального зала.
@export var step_gap: float = 10.0
@export var step_timeout: float = 14.0

var player: Player
var game: Game
var step: int = -1
var active: bool = false
var _t: float = 0.0
var _done_flag: bool = false
var _jumped_air: bool = false
var _completed: Dictionary = {}
var _base_enabled: bool = false
var _new_enabled: bool = false
var _announced: bool = false
var _hint_wait: float = 0.0
var _saw_rune_spend: bool = false
var _last_charges: int = 0
var _observed_room_id: int = 0
var _vertical_room_id: int = 0

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
	for id in STEPS:
		if Save.event_count("tutorial_step_" + id) > 0:
			_completed[id] = true
	_base_enabled = should_run()
	# Новые уроки доступны и старым сохранениям с tutorial_done.
	_new_enabled = Save.event_count("tutorial_o6_done") == 0 and Save.event_count("tutorial_o6_runs") < max_runs
	active = _base_enabled or _new_enabled
	var outside_time := maxf(0.0, float(Time.get_ticks_msec() - _carry_wall_msec) / 1000.0)
	_hint_wait = maxf(maxf(0.0, first_delay), _carry_hint_wait - outside_time)
	if _base_enabled:
		Save.bump_event("tutorial_runs")
	if _new_enabled:
		Save.bump_event("tutorial_o6_runs")
	if not active or player == null:
		return
	_last_charges = player.dash_charges
	player.dash_charges_changed.connect(_on_charges_changed)
	player.slammed.connect(func(_p: float) -> void: _mark("slam"))
	if player.axe:
		player.axe.weapon_skill_started.connect(func(_kind: String) -> void: _mark("weapon_skill"))
	if player.mjolnir:
		player.mjolnir.state_changed.connect(func(in_hand: bool) -> void:
			if in_hand:
				# Автовозврат при загрузке зала не означает, что игрок видел поимку.
				if _saw_rune_spend and (game == null or not game._room_load_active):
					_mark("runes")
			else:
				_mark("throw"))
	if game.rewards and game.rewards.has_signal("doors_shown"):
		game.rewards.doors_shown.connect(func(_d: Array) -> void: _mark("doors"))
	# Tab — экран сборки (П6): открыл — урок пройден
	if game.build_screen:
		game.build_screen.opened.connect(func() -> void: _mark("build"))

func _exit_tree() -> void:
	_carry_hint_wait = maxf(0.0, _hint_wait)
	_carry_wall_msec = Time.get_ticks_msec()

func _on_charges_changed(current: int, _maximum: int, _progress: float) -> void:
	if current < _last_charges:
		_saw_rune_spend = true
	_last_charges = current

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.is_dead:
		return
	var elapsed := FX.real_delta(delta)
	_hint_wait = maxf(0.0, _hint_wait - elapsed)
	_watch_room()
	if active:
		# Наблюдаем ВСЕ действия, а не только текущий шаг.
		for id in ["move", "jump", "dash", "attack", "weapon_skill"]:
			if not _completed.has(id) and _check(id):
				_mark(id)
		if step < 0:
			_next()
		elif step < STEPS.size():
			var id := STEPS[step]
			_done_flag = _completed.has(id)
			if _announced:
				_t += elapsed
			if _done_flag or (_announced and _t >= step_timeout and id != "doors"):
				_next()
	if _hint_wait > 0.0:
		return
	# Контекстная подсказка действует и после завершения обычного обучения.
	if _vertical_room_id != 0 and not _completed.has(VERTICAL_STEP):
		if say(VERTICAL_STEP):
			_mark(VERTICAL_STEP)
			_vertical_room_id = 0
			Save.save_game()
		return
	if active and step >= 0 and step < STEPS.size() and not _announced:
		if say(STEPS[step]):
			_announced = true
			_t = 0.0
		else:
			_next()

func _watch_room() -> void:
	var room: Room = game.room if game != null and is_instance_valid(game) else null
	var current_id := room.get_instance_id() if room and is_instance_valid(room) else 0
	if current_id == _observed_room_id:
		return
	_observed_room_id = current_id
	_vertical_room_id = 0
	if current_id != 0 and room.has_meta("tutorial_vertical") and bool(room.get_meta("tutorial_vertical")) and not _completed.has(VERTICAL_STEP):
		_vertical_room_id = current_id

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
		"weapon_skill":
			# Оружие без особого приёма использует обычный сильный удар.
			return player.axe != null and player.axe.active and player.axe.heavy
	return false

func _mark(id: String) -> void:
	if not STEPS.has(id) or _completed.has(id):
		return
	_completed[id] = true
	Save.bump_event("tutorial_step_" + id)
	if _completed.has("weapon_skill") and _completed.has("runes") and Save.event_count("tutorial_o6_done") == 0:
		Save.bump_event("tutorial_o6_done")
	if step >= 0 and step < STEPS.size() and STEPS[step] == id:
		_done_flag = true

func _next() -> void:
	_t = 0.0
	_done_flag = false
	_announced = false
	step += 1
	while step < STEPS.size():
		var id := STEPS[step]
		if id != VERTICAL_STEP and not _completed.has(id) and ((id in NEW_STEPS and _new_enabled) or (id not in NEW_STEPS and _base_enabled)):
			return
		step += 1
	if active:
		active = false
		if _base_enabled and Save.event_count("tutorial_done") == 0:
			Save.bump_event("tutorial_done")

## Показывать только готовую реплику и соблюдать общий интервал, даже при прямом вызове.
func say(id: String) -> bool:
	if _hint_wait > 0.0 or _completed.has(id):
		return false
	var lines := Dialogue.pool_lines("ravens.tutorial_" + id)
	if lines.is_empty():
		return false
	var line: Dictionary = lines[0]
	line["text"] = keys_in(str(line.get("text", "")))
	Dialogue.bark(line)
	_hint_wait = maxf(10.0, step_gap)
	return true

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
