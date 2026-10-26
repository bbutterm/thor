extends Node3D
class_name Room
## Зал-арена. Враги появляются волнами из маркеров в узле Spawns (метаданные kind/wave),
## дверь Door открывается после зачистки, триггер Exit переводит в следующий зал.
## Комнаты собираются скриптом tools/build_scenes.gd, но их можно править в редакторе руками:
## двигать маркеры, блоки, бочки. Тип врага маркера — метаданные "kind": grunt / thrower / boss / fodder / bloated /
## shieldbearer / shaman / merc; "wave": 0, 1...; "count" (необяз.) — сколько врагов из одного маркера (толпа корма),
## "spread" — радиус разброса толпы, м.
## Волны (GDD 12.5): поток по spawn_batch врагов за раз, следующая волна — когда живых меньше next_wave_fraction
## текущей волны или прошло next_wave_timeout секунд.

signal cleared
signal exit_reached
signal enemy_count_changed(alive: int)
signal boss_spawned(boss: Enemy)

@export var room_title: String = "Зал"
@export var wave_delay: float = 0.9
## Пауза между пачками врагов одной волны (с)
@export var spawn_interval: float = 0.12
## Сколько врагов появляется за раз (GDD 12.5: 2–3 за кадр)
@export var spawn_batch: int = 3
## Следующая волна, когда живых меньше этой доли текущей волны (GDD 12.5: 30 %)...
@export_range(0.0, 1.0) var next_wave_fraction: float = 0.3
## ...или через столько секунд после её начала
@export var next_wave_timeout: float = 25.0

@export_group("Оружие и элита")
## Шанс, что враг (не босс) появится элитой: светится, ×2.5 HP, роняет оружие
@export_range(0.0, 1.0) var elite_chance: float = 0.1
@export var max_elites: int = 1
## Шанс сундука с оружием после зачистки (в первом зале — всегда, у босса — никогда)
@export_range(0.0, 1.0) var chest_chance: float = 0.5

const ENEMY_SCENES := {
	"grunt": "res://enemies/grunt.tscn",
	"thrower": "res://enemies/thrower.tscn",
	"boss": "res://enemies/boss.tscn",
	"fodder": "res://enemies/fodder.tscn",
	"bloated": "res://enemies/bloated.tscn",
	"shieldbearer": "res://enemies/shieldbearer.tscn",
	"shaman": "res://enemies/shaman.tscn",
	"merc": "res://enemies/merc.tscn",
}

var _player: Player
var _waves: Dictionary = {}
var _wave_index: int = 0
var _alive: Array[Enemy] = []
var _started: bool = false
var _is_cleared: bool = false
var door_open: bool = false
var _spawn_queue: Array = []
var _spawn_timer: float = 0.0
var _last_death_pos: Vector3 = Vector3.INF
## Размер текущей волны и сколько она идёт (для перехода к следующей по GDD 12.5)
var _wave_size: int = 0
var _wave_time: float = 0.0
var _advance_pending: bool = false

@onready var spawns: Node3D = $Spawns
@onready var door: Node3D = get_node_or_null("Door")
@onready var exit_area: Area3D = get_node_or_null("Exit")

func _ready() -> void:
	if exit_area:
		exit_area.body_entered.connect(_on_exit_body_entered)
	for m in spawns.get_children():
		var w: int = int(m.get_meta("wave", 0))
		if not _waves.has(w):
			_waves[w] = []
		_waves[w].append(m)

func get_spawn_transform() -> Transform3D:
	var spawn := get_node_or_null("PlayerSpawn") as Node3D
	return spawn.global_transform if spawn else global_transform

func start(player: Player) -> void:
	_player = player
	_started = true
	_wave_index = 0
	_spawn_wave(0)

func wave_count() -> int:
	return _waves.size()

## Добавить волну после всех существующих (маркеры станут детьми Spawns). Возвращает номер волны.
## Вызывать до start() или пока зал не зачищен.
func add_wave(markers: Array[Node3D]) -> int:
	var w := 0
	for k in _waves.keys():
		w = maxi(w, int(k) + 1)
	_waves[w] = []
	for m in markers:
		m.set_meta("wave", w)
		if m.get_parent() == null:
			spawns.add_child(m)
		_waves[w].append(m)
	return w

func _spawn_wave(index: int) -> void:
	Perf.mark("spawn_wave")
	var markers: Array = _waves.get(index, [])
	_advance_pending = false
	if markers.is_empty():
		_check_clear()
		return
	# Поток пачками по spawn_batch (сборка персонажа дорогая: вся волна в одном кадре давала фриз).
	# Маркер с "count" — толпа: ставится в очередь count раз.
	var n := 0
	for m in markers:
		var c := maxi(1, int(m.get_meta("count", 1)))
		for k in c:
			_spawn_queue.append(m)
		n += c
	_wave_size = n
	_wave_time = 0.0
	_advance_pending = false
	_spawn_timer = 0.0

func _physics_process(delta: float) -> void:
	if _started and not _is_cleared:
		_wave_time += delta
		_check_next_wave()
	if _spawn_queue.is_empty():
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = spawn_interval
	for i in maxi(1, spawn_batch):
		if _spawn_queue.is_empty():
			break
		_spawn_enemy(_spawn_queue.pop_front() as Node3D)

## GDD 12.5: следующая волна, не дожидаясь полной зачистки — когда осталось меньше 30 % или прошло 25 с.
func _check_next_wave() -> void:
	if _advance_pending or not _spawn_queue.is_empty() or not _waves.has(_wave_index + 1):
		return
	if _alive.size() < _wave_size * next_wave_fraction or _wave_time >= next_wave_timeout:
		_advance_wave()

func _advance_wave() -> void:
	_advance_pending = true
	_wave_index += 1
	var idx := _wave_index
	get_tree().create_timer(wave_delay, false).timeout.connect(func() -> void: _spawn_wave(idx))

func _make_enemy(kind: String) -> Enemy:
	var path: String = ENEMY_SCENES.get(kind, ENEMY_SCENES["grunt"])
	var enemy := (load(path) as PackedScene).instantiate() as Enemy
	Perf.mark("spawn_" + kind)
	# Характеристики по GDD 12 (enemies/defs/*.tres), если вид врага там описан
	var def := EnemyDef.for_kind(kind)
	if def:
		enemy.apply_def(def)
	return enemy

func _register(enemy: Enemy) -> void:
	enemy.player = _player
	enemy.died.connect(_on_enemy_died)
	_alive.append(enemy)
	if enemy.kind == Enemy.Kind.BOSS:
		boss_spawned.emit(enemy)
	enemy_count_changed.emit(_alive.size() + _spawn_queue.size())

## Враг сверх волн (Шаман поднимает корм, элита-Призыватель): сразу в зал, считается в зачистке.
func spawn_extra(kind: String, global_pos: Vector3) -> Enemy:
	if _is_cleared:
		return null
	var enemy := _make_enemy(kind)
	enemy.position = to_local(global_pos) + Vector3(0, 0.05, 0)
	if _player:
		var to := _player.global_position - global_pos
		enemy.rotation.y = atan2(to.x, to.z) - global_rotation.y
	add_child(enemy)
	_register(enemy)
	return enemy

func _spawn_enemy(marker: Node3D) -> void:
	var kind: String = str(marker.get_meta("kind", "grunt"))
	var enemy := _make_enemy(kind)
	# Маркер может переопределить характеристики врага до _ready (мини-босс — см. MinibossDef)
	if marker.has_meta("setup"):
		var setup: Variant = marker.get_meta("setup")
		if setup is Callable and (setup as Callable).is_valid():
			(setup as Callable).call(enemy)
	# Позиция до add_child: в _ready враг рисует кольцо появления там, где стоит
	enemy.position = to_local(marker.global_position)
	var spread := float(marker.get_meta("spread", 0.0))
	if spread > 0.0:
		var a := randf() * TAU
		enemy.position += Vector3(cos(a), 0, sin(a)) * sqrt(randf()) * spread
	enemy.rotation.y = marker.global_rotation.y - global_rotation.y
	Loot.maybe_make_elite(self, enemy, elite_chance, max_elites)
	add_child(enemy)
	_register(enemy)

## Враги волны, которые ещё не появились.
func pending_spawns() -> int:
	return _spawn_queue.size()

func _on_enemy_died(enemy: Enemy) -> void:
	_alive.erase(enemy)
	_last_death_pos = enemy.global_position
	enemy_count_changed.emit(_alive.size() + _spawn_queue.size())
	_check_clear()

func _check_clear() -> void:
	if _is_cleared or not _alive.is_empty() or not _spawn_queue.is_empty() or _advance_pending:
		return
	if _waves.has(_wave_index + 1):
		_advance_wave()
	else:
		_is_cleared = true
		_spawn_chest()
		cleared.emit()

func alive_count() -> int:
	return _alive.size()

func alive_enemies() -> Array[Enemy]:
	return _alive

func open_door() -> void:
	Perf.mark("door_open")
	door_open = true
	if door == null:
		return
	for c in door.find_children("*", "CollisionShape3D", true, false):
		(c as CollisionShape3D).set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property(door, "position:y", door.position.y - 6.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: door.visible = false)
	Audio.play("sounds/sfx/door_open.wav")

func _on_exit_body_entered(body: Node) -> void:
	if door_open and body is Player:
		exit_reached.emit()

## Сундук с оружием там, где пал последний враг (или у точки входа).
func _spawn_chest() -> void:
	var pos := _last_death_pos
	if pos == Vector3.INF:
		pos = get_spawn_transform().origin + get_spawn_transform().basis.z * -4.0
	Loot.on_room_cleared(self, pos, chest_chance)
