extends Node3D
class_name Game
## Сцена забега: грузит залы по порядку из Run, связывает игрока, HUD, выбор рун, паузу и финальный экран.

@onready var level: Node3D = $Level
@onready var player: Player = $Player
@onready var hud: HUD = $HUD
@onready var rune_pick: RunePick = $RunePick
@onready var end_screen: EndScreen = $EndScreen
@onready var pause_menu: PauseMenu = $PauseMenu

var room: Room
var _ending: bool = false

func _ready() -> void:
	FX.reset_time()
	get_tree().paused = false
	if Run.body == null or Run.room_order.is_empty():
		Run.start_run()
	player.apply_body_and_runes(Run.body, Run)
	player.died.connect(_on_player_died)
	Run.kill_streak.connect(_on_kill_streak)
	rune_pick.picked.connect(_on_rune_picked)
	end_screen.restart_requested.connect(restart_run)
	end_screen.menu_requested.connect(go_to_menu)
	pause_menu.restart_requested.connect(restart_run)
	pause_menu.menu_requested.connect(go_to_menu)
	hud.bind_player(player)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Дожидаемся фоновой загрузки моделей (обычно уже готово, пока игрок был в меню)
	AssetCache.finish()
	_load_room()
	var body_id := Run.body.id if Run.body else ""
	if randf() < 0.5:
		Odin.say("run_start_" + body_id)
	else:
		Odin.say("run_start")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _ending and not rune_pick.visible:
		pause_menu.toggle()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not get_tree().paused and not _ending:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _load_room() -> void:
	Perf.mark("room_load")
	if room and is_instance_valid(room):
		level.remove_child(room)
		room.queue_free()
	for c in get_children():
		# Убираем «мусор» прошлого зала (снаряды, огонь), оставляя постоянные узлы
		if c.has_meta("transient") or c is Area3D or (c.get_script() and c.get_script().resource_path.ends_with("fire_zone.gd")):
			c.queue_free()
	var path := Run.current_room_path()
	var scene: PackedScene
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		scene = ResourceLoader.load_threaded_get(path) as PackedScene
	else:
		scene = load(path) as PackedScene
	room = scene.instantiate() as Room
	level.add_child(room)
	var t := room.get_spawn_transform()
	player.global_position = t.origin
	player.velocity = Vector3.ZERO
	player.rotation_target = Vector2(0.0, t.basis.get_euler().y)
	player.mjolnir.force_return_instant()
	room.cleared.connect(_on_room_cleared)
	room.exit_reached.connect(_on_exit_reached)
	room.boss_spawned.connect(hud.show_boss)
	room.enemy_count_changed.connect(hud.set_enemy_count)
	hud.set_room(Run.room_index + 1, Run.total_rooms(), room.room_title, Run.is_boss_room())
	hud.fade_in()
	# Пока экран затемнён — прогреваем шейдеры (в каждом зале: свои материалы под светом огня/снарядов)
	ShaderWarmup.run(self)
	if Run.is_boss_room():
		Odin.say("boss_start")
	# Даём осмотреться полсекунды
	get_tree().create_timer(0.6, false).timeout.connect(func() -> void:
		if is_instance_valid(room) and not player.is_dead:
			room.start(player))

func _on_room_cleared() -> void:
	Run.add_glory(Run.glory_room_clear)
	# Следующий зал грузим в фоне, пока игрок выбирает руну
	if Run.room_index + 1 < Run.room_order.size():
		ResourceLoader.load_threaded_request(Run.room_order[Run.room_index + 1], "", true)
	if Run.is_boss_room():
		Run.won = true
		_ending = true
		get_tree().create_timer(1.6, false).timeout.connect(func() -> void:
			Odin.say("victory")
			_show_end(true))
		return
	Odin.say("room_clear")
	get_tree().create_timer(0.7, false).timeout.connect(func() -> void:
		if player.is_dead:
			return
		var choices := Run.random_rune_choices(3)
		if choices.is_empty():
			room.open_door()
		else:
			rune_pick.open(choices))

func _on_rune_picked(rune: RuneDef) -> void:
	Run.add_rune(rune)
	player.recalc_from_runes(Run)
	if rune.id == "heal":
		player.heal(50.0)
	Odin.say("rune_pick")
	Audio.play("sounds/sfx/rune_pick.wav")
	room.open_door()
	hud.toast("Дверь открыта — вперёд!")

func _on_exit_reached() -> void:
	if _ending:
		return
	if Run.advance_room():
		hud.fade_out(0.25)
		get_tree().create_timer(0.25, false).timeout.connect(_load_room)
	else:
		Run.won = true
		_show_end(true)

func _on_player_died() -> void:
	if _ending:
		return
	_ending = true
	Odin.say("death")
	get_tree().create_timer(1.4, false).timeout.connect(func() -> void: _show_end(false))

func _on_kill_streak(_count: int) -> void:
	Odin.say("streak10")

func _show_end(victory: bool) -> void:
	_ending = true
	FX.reset_time()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	end_screen.show_result(victory)

func restart_run() -> void:
	FX.reset_time()
	get_tree().paused = false
	Run.start_run()
	get_tree().reload_current_scene()

func go_to_menu() -> void:
	FX.reset_time()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
