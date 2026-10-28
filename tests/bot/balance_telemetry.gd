extends Node
## Событийный журнал только для тестового бота. Не меняет игровой ввод, состояние или случайные числа.
## Срабатывает на игровых сигналах; выбор бота записывается из bot_player.gd, только если включён trace=1.

const DEFAULT_LIMIT := 10000

var game: Game
var player: Player
var enabled := false
var limit := DEFAULT_LIMIT
var events: Array[Dictionary] = []
var dropped := 0
var _health := 0.0
var _max_health := 0.0
var _shield := 0.0
var _shield_max := 0.0
var _skip_marks := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Выполняться до Perf._process, который сбрасывает накопленные метки.
	process_priority = Perf.process_priority - 1
	set_process(false)

func begin(g: Game, event_limit: int = DEFAULT_LIMIT) -> void:
	game = g
	player = g.player
	limit = clampi(event_limit, 1, DEFAULT_LIMIT)
	events.clear()
	dropped = 0
	_health = maxf(0.0, player.health)
	_max_health = player.max_health
	_shield = player.shield
	_shield_max = player.shield_max
	enabled = true
	# Эти отметки появились до начала измерения и не принадлежат новому забегу.
	_skip_marks = Perf._marks.size()
	player.hurt.connect(_on_hurt)
	player.health_changed.connect(_on_health_changed)
	player.slammed.connect(_on_slammed)
	player.axe.swung.connect(_on_swung)
	player.axe.hit_landed.connect(_on_melee_contact)
	set_process(true)
	record("begin", {"hp": _health, "hp_max": _max_health, "shield": _shield, "shield_max": _shield_max})

func record(kind: String, fields: Dictionary = {}) -> void:
	if not enabled:
		return
	if events.size() >= limit:
		dropped += 1
		return
	var t := game.tracker.run_time if is_instance_valid(game) and is_instance_valid(game.tracker) else 0.0
	var event := {"type": kind, "t": t, "physics_frame": Engine.get_physics_frames(), "room": Run.room_index}
	event.merge(fields, true)
	events.append(event)

func _on_hurt(amount: float) -> void:
	if not enabled or not is_instance_valid(player):
		return
	var after := maxf(0.0, player.health)
	# RunTracker соединён с hurt до наблюдателя и уже перенёс pending_source в last_hit_by.
	var source := game.tracker.last_hit_by if is_instance_valid(game) and is_instance_valid(game.tracker) else "unknown"
	record("hurt", {"source": source, "amount": amount, "hp_before": _health, "hp_after": after,
		"hp_max": player.max_health, "shield": player.shield})
	_health = after
	_max_health = player.max_health

func _on_health_changed(current: float, maximum: float) -> void:
	if not enabled or not is_instance_valid(player):
		return
	var now := maxf(0.0, current)
	if not is_equal_approx(now, _health) or not is_equal_approx(maximum, _max_health):
		# Это прирост/изменение HP, а не обязательно вызов heal(): сюда попадают руны и воскрешение.
		record("health_change", {"hp_before": _health, "hp_after": now, "max_before": _max_health, "max_after": maximum})
	if not is_equal_approx(player.shield, _shield) or not is_equal_approx(player.shield_max, _shield_max):
		var source := RunTracker.pending_source if player.shield < _shield else ""
		record("shield_change", {"before": _shield, "after": player.shield, "max_before": _shield_max,
			"max_after": player.shield_max, "pending_source": source})
	_health = now
	_max_health = maximum
	_shield = player.shield
	_shield_max = player.shield_max

func _on_swung(stage: int) -> void:
	if is_instance_valid(player):
		record("melee_swing", {"stage": stage, "heavy": player.axe.heavy})

func _on_melee_contact(count: int, stage: int) -> void:
	# ShapeCast включает пропсы и блокированные удары, не только нанесённый врагу урон.
	record("melee_contact", {"count": count, "stage": stage})

func _on_slammed(power: float) -> void:
	if is_instance_valid(player):
		record("slam_impact", {"power": power, "enemies_contacted": player._last_slam_hits})

func _process(_delta: float) -> void:
	if not enabled:
		return
	# Тик наблюдателя перед Perf._process: читаем каждую отметку один раз, не меняя её.
	var marks: PackedStringArray = Perf._marks
	for i in range(mini(_skip_marks, marks.size()), marks.size()):
		if marks[i] == "shield_block" or marks[i] == "*shield_block":
			record("shield_block", {"precision": "process_frame"})
	_skip_marks = 0

func finish() -> void:
	if not enabled:
		return
	record("end")
	enabled = false
	set_process(false)

func result() -> Dictionary:
	return {"version": 1, "event_limit": limit, "dropped": dropped, "events": events.duplicate(true)}
