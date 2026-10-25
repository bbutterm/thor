extends Node3D
class_name Room
## Зал-арена. Враги появляются волнами из маркеров в узле Spawns (метаданные kind/wave),
## дверь Door открывается после зачистки, триггер Exit переводит в следующий зал.
## Комнаты собираются скриптом tools/build_scenes.gd, но их можно править в редакторе руками:
## двигать маркеры, блоки, бочки. Тип врага маркера — метаданные "kind": grunt / thrower / boss; "wave": 0, 1...

signal cleared
signal exit_reached
signal enemy_count_changed(alive: int)
signal boss_spawned(boss: Enemy)

@export var room_title: String = "Зал"
@export var wave_delay: float = 0.9

const ENEMY_SCENES := {
	"grunt": "res://enemies/grunt.tscn",
	"thrower": "res://enemies/thrower.tscn",
	"boss": "res://enemies/boss.tscn",
}

var _player: Player
var _waves: Dictionary = {}
var _wave_index: int = 0
var _alive: Array[Enemy] = []
var _started: bool = false
var _is_cleared: bool = false
var door_open: bool = false

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

func _spawn_wave(index: int) -> void:
	var markers: Array = _waves.get(index, [])
	for m in markers:
		var marker := m as Node3D
		var kind: String = str(marker.get_meta("kind", "grunt"))
		var path: String = ENEMY_SCENES.get(kind, ENEMY_SCENES["grunt"])
		var enemy := (load(path) as PackedScene).instantiate() as Enemy
		add_child(enemy)
		enemy.global_position = marker.global_position
		enemy.rotation.y = marker.global_rotation.y
		enemy.player = _player
		enemy.died.connect(_on_enemy_died)
		_alive.append(enemy)
		if enemy.kind == Enemy.Kind.BOSS:
			boss_spawned.emit(enemy)
	enemy_count_changed.emit(_alive.size())
	if markers.is_empty():
		_check_clear()

func _on_enemy_died(enemy: Enemy) -> void:
	_alive.erase(enemy)
	enemy_count_changed.emit(_alive.size())
	_check_clear()

func _check_clear() -> void:
	if _is_cleared or not _alive.is_empty():
		return
	_wave_index += 1
	if _waves.has(_wave_index):
		var idx := _wave_index
		get_tree().create_timer(wave_delay, false).timeout.connect(func() -> void: _spawn_wave(idx))
	else:
		_is_cleared = true
		cleared.emit()

func alive_count() -> int:
	return _alive.size()

func alive_enemies() -> Array[Enemy]:
	return _alive

func open_door() -> void:
	door_open = true
	if door == null:
		return
	for c in door.find_children("*", "CollisionShape3D", true, false):
		(c as CollisionShape3D).set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property(door, "position:y", door.position.y - 6.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: door.visible = false)
	Audio.play("sounds/land.ogg")

func _on_exit_body_entered(body: Node) -> void:
	if door_open and body is Player:
		exit_reached.emit()
