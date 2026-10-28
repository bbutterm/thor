extends Node
## Жизненный цикл перехода: первый вход, удаление старых объектов до прогрева,
## повторный запрос, пауза, отмена и перезапуск. Запускать с --headless --fixed-fps 60.

var game: Game
var ok: int = 0
var failed: int = 0
var _old_room: WeakRef
var _watch_warmup: bool = false
var _warmups: int = 0
var _old_alive_at_warmup: bool = false
var _pause_on_detach: bool = false
var _paused_on_detach: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.name = "RoomTransitionTestRunner"
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	print("%s %s" % ["OK" if condition else "FAIL", description])
	if condition:
		ok += 1
	else:
		failed += 1

func _on_node_added(node: Node) -> void:
	if node is Game:
		var started_frame := Engine.get_process_frames()
		var added := node as Game
		added.ready.connect(func() -> void:
			_check(is_instance_valid(added.room) and Engine.get_process_frames() == started_frame,
				"первый зал готов синхронно в кадре добавления Game"))
	if _watch_warmup and node is ShaderWarmup:
		_warmups += 1
		if _old_room and _old_room.get_ref() != null:
			_old_alive_at_warmup = true

func _on_node_removed(node: Node) -> void:
	if _pause_on_detach and _old_room and _old_room.get_ref() == node:
		_pause_on_detach = false
		_paused_on_detach = true
		get_tree().paused = true

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _start_game() -> bool:
	Dialogue.in_run_scenes = false
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_06.tscn", "res://rooms/room_07.tscn", "res://rooms/room_01.tscn"])
	Run.room_rewards.clear()
	Run.room_index = 0
	Run.miniboss_rooms.clear()
	Run.doors_enabled = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(3)
	game = get_tree().current_scene as Game
	if not game or not is_instance_valid(game.room):
		_check(false, "игра и начальный зал созданы")
		return false
	await _frames(15) # первый ShaderWarmup отработал свои 10 кадров
	return true

func _wait_for_detach() -> bool:
	for i in 120:
		if _paused_on_detach:
			return true
		await _frames(1)
	return false

func _wait_for_room(path_suffix: String) -> bool:
	for i in 120:
		if is_instance_valid(game) and is_instance_valid(game.room) and game.room.scene_file_path.ends_with(path_suffix):
			return true
		await _frames(1)
	return false

func _wait_for_menu(old_game: WeakRef) -> bool:
	for i in 120:
		var current := get_tree().current_scene
		if old_game.get_ref() == null and current and current.scene_file_path.ends_with("ui/main_menu.tscn"):
			return true
		await _frames(1)
	return false

func _watch_old_room() -> void:
	_old_room = weakref(game.room)
	_warmups = 0
	_old_alive_at_warmup = false
	_watch_warmup = true

func _transition_and_pause() -> void:
	var original_mode := game.player.process_mode
	FX.hit_flash(game, game.player.global_position + Vector3.UP, 0.5)
	var holder: WeakRef = weakref(FX._holder)
	_watch_old_room()
	_pause_on_detach = true
	_paused_on_detach = false
	game._on_exit_reached()
	game._on_exit_reached()
	_check(Run.room_index == 1 and game._exit_pending, "двойной запрос продвигает забег один раз")
	var ls := LoadingScreen._inst
	var old_safety := ls.safety_time
	get_tree().paused = true
	ls.safety_time = 0.001
	await _frames(8)
	_check(_old_room.get_ref() != null and LoadingScreen.is_showing(), "пауза до таймера сохраняет зал и экран загрузки")
	ls.safety_time = old_safety
	get_tree().paused = false
	var detached := await _wait_for_detach()
	_check(detached, "переход дошёл до удаления прежнего зала")
	if not detached:
		get_tree().paused = false
		return
	_check(game.room == null and game._room_load_active and game.player.process_mode == Node.PROCESS_MODE_DISABLED,
		"игрок приостановлен, пока следующий зал отсутствует")
	ls.safety_time = 0.001
	await _frames(8)
	_check(_old_room.get_ref() == null and holder.get_ref() == null, "старый зал и временный FX уничтожены при паузе")
	_check(_warmups == 0 and LoadingScreen.is_showing(), "пауза не начинает прогрев и не прячет загрузку")
	ls.safety_time = old_safety
	get_tree().paused = false
	var loaded := await _wait_for_room("room_07.tscn")
	_check(loaded, "после паузы загружен следующий зал")
	if not loaded:
		return
	_check(_warmups == 1 and not _old_alive_at_warmup, "один прогрев после уничтожения старого зала")
	_check(game.player.process_mode == original_mode and not game._room_load_active and not game._exit_pending,
		"режим игрока и флаги перехода восстановлены")
	_check(not LoadingScreen.is_showing(), "успешный переход отпускает экран загрузки")
	var new_room := game.room
	var starts := [0]
	new_room.wave_started.connect(func(i: int) -> void:
		if i == 0:
			starts[0] += 1)
	await _frames(45)
	_check(new_room._started and starts[0] == 1, "старый таймер не запускает новый зал повторно")
	_watch_warmup = false

func _cancel_before_timer() -> void:
	_watch_old_room()
	var old_game: WeakRef = weakref(game)
	game._on_exit_reached()
	game.go_to_menu()
	_check(await _wait_for_menu(old_game), "отмена до таймера возвращает в меню")
	await _frames(25)
	_check(_warmups == 0 and not LoadingScreen.is_showing(), "отменённый таймер не прогревает зал и не держит загрузку")
	_watch_warmup = false

func _cancel_during_wait() -> void:
	_watch_old_room()
	var old_game: WeakRef = weakref(game)
	_pause_on_detach = true
	_paused_on_detach = false
	game._on_exit_reached()
	var detached := await _wait_for_detach()
	_check(detached and game._room_load_active, "отмена во время ожидания достигла барьера")
	if not detached:
		get_tree().paused = false
		return
	game.go_to_menu()
	_check(await _wait_for_menu(old_game), "отмена во время ожидания возвращает в меню")
	await _frames(15)
	_check(_warmups == 0 and not LoadingScreen.is_showing() and not get_tree().paused,
		"отменённое ожидание не прогревает зал и восстанавливает паузу")
	_watch_warmup = false

func _restart_during_wait() -> void:
	_watch_old_room()
	var old_game: WeakRef = weakref(game)
	_pause_on_detach = true
	_paused_on_detach = false
	game._on_exit_reached()
	var detached := await _wait_for_detach()
	_check(detached and game._room_load_active, "перезапуск во время ожидания достиг барьера")
	if not detached:
		get_tree().paused = false
		return
	game.restart_run()
	var restarted := false
	for i in 150:
		await _frames(1)
		var current := get_tree().current_scene
		if old_game.get_ref() == null and current is Game and is_instance_valid((current as Game).room):
			restarted = true
			break
	_check(restarted and not get_tree().paused, "перезапуск отменяет ожидание и создаёт новую игру")
	_check(_warmups == 1, "при перезапуске прогрет только первый зал новой игры")
	_watch_warmup = false

func _free_during_wait() -> void:
	_watch_old_room()
	var old_game: WeakRef = weakref(game)
	game._load_room()
	_check(game._room_load_active, "закрытие игры начато во время ожидания удаления")
	game.queue_free()
	await _frames(8)
	_check(old_game.get_ref() == null and _warmups == 0, "удалённая игра не продолжает загрузку и прогрев")
	_watch_warmup = false

func _run() -> void:
	print("=== ROOM TRANSITION TEST ===")
	if await _start_game():
		await _transition_and_pause()
		if is_instance_valid(game):
			await _cancel_before_timer()
	if await _start_game():
		await _cancel_during_wait()
	if await _start_game():
		await _free_during_wait()
	if await _start_game():
		await _restart_during_wait()
	get_tree().paused = false
	FX.reset_time()
	# Дать образцам нового прогрева завершиться, затем удалить игру и дождаться
	# отложенных таймеров, чтобы ошибки очистки были видны до итога теста.
	await _frames(15)
	var final_scene := get_tree().current_scene
	if final_scene:
		final_scene.queue_free()
	await _frames(50)
	print("ROOM TRANSITION RESULT: %d OK, %d FAIL" % [ok, failed])
	get_tree().quit(1 if failed else 0)
