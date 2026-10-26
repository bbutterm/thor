extends Node
class_name RunTracker
## Следит за забегом из сцены игры: время забега, кто последним ударил Тора (причина смерти),
## бой-реплики Одина (стоит столбом, мульти-килл, получил много урона).
## Создаётся из Game._ready() через RunTracker.attach(). Игрока не меняет — только читает.
##
## Источник урона: перед player.take_damage() вызови RunTracker.note_damage("barrel") или
## RunTracker.note_hit(enemy). Источник «съедается» ближайшим сигналом hurt.

## Быстрее этого (с) — «быстро сдох»
@export var quick_death_time: float = 45.0
## Дольше этого (с) — «долго жил»
@export var long_life_time: float = 420.0
## Сколько секунд стоять почти на месте в бою до «ДВИГАЙСЯ!»
@export var idle_time: float = 4.0
## Ниже этой горизонтальной скорости игрок «стоит»
@export var idle_speed: float = 0.6
## Мульти-килл: столько убийств…
@export var multikill_count: int = 3
## …за это время (с)
@export var multikill_window: float = 0.8
## «Скуф…»: доля макс. HP, потерянная за big_damage_window
@export var big_damage_fraction: float = 0.35
@export var big_damage_window: float = 3.0
## Ниже этой высоты (м) смерть считается падением
@export var fall_death_y: float = -15.0

## Ожидающий источник урона (ставится прямо перед take_damage)
static var pending_source: String = ""

## Подписи источников для экрана смерти
const SOURCE_NAMES := {
	"draugr_warrior": "драугр-воин", "draugr_thrower": "драугр-метатель", "draugr_fodder": "драугр-корм",
	"boss_jarl": "Ярл Бьорн", "miniboss_sven": "Толстый Свен", "fall": "падение", "barrel": "бочка",
	"own_fire": "собственный огонь", "shieldbearer": "щитоносец", "bloated": "раздутый", "shaman": "шаман",
	"loki_merc": "наёмник Локи", "unknown": "что-то невнятное",
}

var player: Player
var run_time: float = 0.0
var last_hit_by: String = ""
var _idle: float = 0.0
var _kill_times: Array[float] = []
var _last_kills: int = 0
var _damage_log: Array = []
var _finished: bool = false

## Подключает трекер к сцене игры. Возвращает созданный узел.
static func attach(game: Node, p: Player) -> RunTracker:
	var t := RunTracker.new()
	t.name = "RunTracker"
	t.player = p
	game.add_child(t)
	return t

## Кто-то ударит Тора прямо сейчас. Вызывать перед player.take_damage().
static func note_damage(source_id: String) -> void:
	pending_source = source_id

## Удар от врага/снаряда: id из enemy_id / death_source_id / kind. attacker может быть уже удалён
## (снаряд погибшего метателя) — тогда fallback.
static func note_hit(attacker: Variant, fallback: String = "draugr_thrower") -> void:
	pending_source = source_id_of(attacker) if is_instance_valid(attacker) else fallback

static func source_id_of(attacker: Variant) -> String:
	if not is_instance_valid(attacker) or not attacker is Node:
		return "unknown"
	if attacker.has_meta("death_source_id"):
		return str(attacker.get_meta("death_source_id"))
	for prop in ["death_source_id", "enemy_id"]:
		var v: Variant = attacker.get(prop)
		if v is String and v != "":
			return v
	var k: Variant = attacker.get("kind")
	if k != null:
		if k == Enemy.Kind.BOSS:
			return "boss_jarl"
		if k == Enemy.Kind.THROWER:
			return "draugr_thrower"
	return "draugr_warrior"

## Причина (категория для реакций Одина) по id источника.
static func cause_of(source_id: String) -> String:
	if source_id.begins_with("boss_") or source_id.begins_with("miniboss_"):
		return "boss"
	if source_id.begins_with("draugr") or source_id in ["shieldbearer", "bloated", "shaman", "loki_merc"]:
		return "draugr"
	if source_id in ["fall", "barrel", "own_fire"]:
		return source_id
	return "unknown" if source_id == "" else source_id

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	pending_source = ""
	if player:
		player.hurt.connect(_on_hurt)
	_last_kills = Run.kills
	Save.begin_run(Run.body.id if Run.body else "")

func _process(delta: float) -> void:
	if _finished or player == null or not is_instance_valid(player) or player.is_dead:
		return
	run_time += delta
	_watch_idle(delta)
	_watch_kills()

func _watch_idle(delta: float) -> void:
	if player.input_enabled and player.horizontal_speed() < idle_speed and player.is_on_floor() \
			and get_tree().get_first_node_in_group("enemies") != null:
		_idle += delta
		if _idle >= idle_time:
			_idle = 0.0
			Odin.say("idle")
	else:
		_idle = 0.0

func _watch_kills() -> void:
	if Run.kills == _last_kills:
		return
	var now := run_time
	for i in maxi(0, Run.kills - _last_kills):
		_kill_times.append(now)
	_last_kills = Run.kills
	_kill_times = _kill_times.filter(func(t: float) -> bool: return now - t <= multikill_window)
	if _kill_times.size() >= multikill_count:
		_kill_times.clear()
		Odin.say("multikill")

func _on_hurt(amount: float) -> void:
	last_hit_by = pending_source if pending_source != "" else "unknown"
	pending_source = ""
	var now := run_time
	_damage_log.append([now, amount])
	_damage_log = _damage_log.filter(func(e: Array) -> bool: return now - e[0] <= big_damage_window)
	var total := 0.0
	for e in _damage_log:
		total += e[1]
	if total >= player.max_health * big_damage_fraction and player.health > 0.0:
		_damage_log.clear()
		Odin.say("big_damage")

## Итог забега для сохранения и выбора реакции.
func result(won: bool) -> Dictionary:
	var source := "" if won else _death_source()
	var tags: Array[String] = []
	if not won:
		if run_time < quick_death_time:
			tags.append("quick")
		if run_time > long_life_time:
			tags.append("long")
		if player and is_instance_valid(player) and player.has_method("is_ranged_active") and player.call("is_ranged_active"):
			tags.append("ranged")
	return {
		"won": won,
		"cause": "" if won else cause_of(source),
		"killed_by": source,
		"tags": tags,
		"time": snappedf(run_time, 0.1),
		"rooms": Run.room_index + (1 if won else 0),
		"glory": Run.glory,
		"kills": Run.kills,
		"best_streak": Run.best_streak,
		"body": Run.body.id if Run.body else "",
	}

func _death_source() -> String:
	if player and is_instance_valid(player) and player.global_position.y < fall_death_y:
		return "fall"
	return last_hit_by if last_hit_by != "" else "unknown"

## Записывает итог в сохранение (один раз за забег).
func finish(won: bool) -> Dictionary:
	var r := result(won)
	if not _finished:
		_finished = true
		Save.end_run(r)
	return r

## Строка для экрана смерти по Save.last_run: «Убил: драугр-воин · 2:31».
static func describe_last_death() -> String:
	var lr: Dictionary = Save.data.get("last_run", {})
	var by := str(lr.get("killed_by", "unknown"))
	var t := float(lr.get("time", 0.0))
	var txt := "Убил: %s · продержался %d:%02d" % [SOURCE_NAMES.get(by, by), int(t) / 60, int(t) % 60]
	var tags: Array = lr.get("tags", [])
	if "quick" in tags:
		txt += " (рекорд скорости, но не тот)"
	if "ranged" in tags:
		txt += " · со стрелялкой в руке"
	return txt
