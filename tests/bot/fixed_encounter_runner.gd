extends Node
## Черновик контрольного боя: один процесс = одно тело, один seed, один фиксированный зал.
## Тестовая сцена использует реальные Player, Enemy и BotPlayer. Боевые числа не переопределяются.
## Запуск только с новым out=<абсолютный путь>, изолированным XDG_DATA_HOME и --fixed-fps 60.

const BotPlayer := preload("res://tests/bot/bot_player.gd")
const FIXTURE := "res://tests/bot/fixed_encounter_room.tscn"
const TIME_CAP_SECONDS := 180

var args := {"body": "thrall", "seed": "1", "profile": "skilled", "trace": "0", "out": ""}
var game: Game
var room: Room
var bot: Node
var planned: Array[Dictionary] = []
var spawned: Array[Dictionary] = []
var _seen: Dictionary = {}
var _args_error := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	for argument in OS.get_cmdline_user_args():
		if argument == "sync_load":
			continue
		var kv := argument.split("=", true, 1)
		if kv.size() == 2 and args.has(kv[0]):
			args[kv[0]] = kv[1]
		else:
			_args_error = "неизвестный аргумент " + argument
	_run.call_deferred()

func _abort(reason: String) -> void:
	push_error("fixed encounter: " + reason)
	get_tree().paused = false
	get_tree().quit(1)

func _coords(p: Vector3) -> Array[float]:
	var coords: Array[float] = [p.x, p.y, p.z]
	return coords

func _manifest_ok() -> bool:
	if spawned.size() > planned.size():
		return false
	for i in spawned.size():
		if spawned[i].kind != planned[i].kind or spawned[i].elite:
			return false
		var a: Array = spawned[i].position
		var b: Array = planned[i].position
		if Vector3(a[0], a[1], a[2]).distance_to(Vector3(b[0], b[1], b[2])) > 0.001:
			return false
		if absf(wrapf(float(spawned[i].yaw) - float(planned[i].yaw), -PI, PI)) > 0.001:
			return false
	return true

## Сигнал отправляется после _register: это исходная позиция до следующего шага физики.
func _on_enemy_count(_count: int) -> void:
	for enemy in room.alive_enemies():
		if not is_instance_valid(enemy) or _seen.has(enemy.get_instance_id()):
			continue
		_seen[enemy.get_instance_id()] = true
		spawned.append({"kind": enemy.enemy_def.game_kind if enemy.enemy_def else "unknown",
			"position": _coords(enemy.global_position), "yaw": enemy.global_rotation.y, "elite": enemy.has_meta("elite"),
			"max_hp": enemy.max_health, "t": game.tracker.run_time})

func _run() -> void:
	GameSettings.ensure_loaded()
	if not Save.is_test or Save.path != Save.TEST_PATH or GameSettings.path != GameSettings.TEST_PATH \
			or FileAccess.file_exists(Save.TEST_PATH) or FileAccess.file_exists(GameSettings.TEST_PATH):
		# Save._exit_tree пишет содержимое на диск: при ошибочной конфигурации не перезаписывать чужой файл.
		Save.data.clear()
		_abort("нужен новый XDG_DATA_HOME с тестовыми сохранением и настройками")
		return
	if _args_error != "":
		_abort(_args_error)
		return
	var body := str(args.body)
	var known: Array = Run.all_bodies.map(func(b: BodyDef) -> String: return b.id)
	var seed_arg := str(args.seed)
	var out := str(args.out)
	if not body in known or not seed_arg.is_valid_int() or int(seed_arg) < 0 or not str(args.profile) in BotPlayer.PROFILES \
			or not str(args.trace) in ["0", "1"] or not out.is_absolute_path() or out.begins_with("res://") or FileAccess.file_exists(out):
		_abort("неверные аргументы или файл результата уже существует")
		return
	var seed_value := int(seed_arg)
	seed(seed_value)
	Run.start_run(body)
	Run.room_order.assign([FIXTURE])
	Run.room_rewards.assign(["combat"])
	Run.doors_enabled = true
	if Run.is_miniboss_room() or Run.current_room_path() != FIXTURE:
		_abort("контрольный зал не должен быть ареной мини-босса или ларьком")
		return
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	for i in 180:
		await get_tree().physics_frame
		game = get_tree().current_scene as Game
		if game and game.is_node_ready() and game.room:
			break
	if not is_instance_valid(game) or not game.is_node_ready() or not game.room:
		_abort("игровая сцена не загрузилась")
		return
	room = game.room
	if room._started or room.elite_chance != 0.0 or room.wave_count() != 1:
		_abort("неверная конфигурация контрольного зала")
		return
	for marker in room.spawns.get_children():
		if not marker is Node3D or float(marker.get_meta("spread", 0.0)) != 0.0 or int(marker.get_meta("count", 1)) != 1:
			_abort("у маркера должен быть один враг и фиксированная позиция")
			return
		planned.append({"kind": str(marker.get_meta("kind", "grunt")), "position": _coords((marker as Node3D).global_position),
			"yaw": (marker as Node3D).global_rotation.y})
	if planned.size() != 4:
		_abort("в сценарии должно быть четыре маркера")
		return
	room.enemy_count_changed.connect(_on_enemy_count)
	bot = BotPlayer.new()
	bot.telemetry_enabled = str(args.trace) == "1"
	add_child(bot)
	bot.set_profile(str(args.profile))
	bot.begin(game, seed_value)  # rng бота и глобальный RNG устанавливаются до появления врагов.
	var melee := game.player.weapons.melee
	var ranged := game.player.weapons.ranged
	var start := {"hp": game.player.health, "max_hp": game.player.max_health,
		"position": _coords(game.player.global_position), "yaw": game.player.rotation_target.y,
		"move_speed": game.player.move_speed, "dash_charges": game.player.dash_charges, "dash_max": game.player.dash_charges_max,
		"melee": melee.def.id if melee and melee.def else "", "melee_level": melee.level if melee else 0,
		"ranged": ranged.def.id if ranged and ranged.def else "", "ranged_level": ranged.level if ranged else 0}
	var start_frame := Engine.get_physics_frames()
	var outcome := "timeout"
	while Engine.get_physics_frames() - start_frame < TIME_CAP_SECONDS * Engine.physics_ticks_per_second:
		await get_tree().physics_frame
		if game.player.is_dead or room._is_cleared:
			outcome = "clear_and_death" if game.player.is_dead and room._is_cleared else ("death" if game.player.is_dead else "cleared")
			break
	bot.stop()  # раньше выбора руны и автоматического подбора после зачистки.
	var valid: bool = room._started and _manifest_ok() and (not outcome.begins_with("clear") or spawned.size() == planned.size()) \
		and bot.picks.is_empty() and Run.runes.is_empty()
	var row := {
		"scenario": FIXTURE, "body": body, "seed": seed_value, "profile": str(args.profile), "trace_enabled": bool(bot.telemetry_enabled),
		"engine": Engine.get_version_info().string, "display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "physics_hz": Engine.physics_ticks_per_second,
		"save": "fresh_test", "outcome": outcome, "valid": valid, "room_started": room._started,
		"planned": planned, "spawned": spawned, "unspawned": planned.size() - spawned.size(),
		"start": start,
		"spawn_batch": room.spawn_batch, "spawn_interval": room.spawn_interval,
		"end_hp": maxf(0.0, game.player.health), "end_position": _coords(game.player.global_position),
		"cause": str(game.tracker.result(false).get("killed_by", "")) if game.player.is_dead else "",
		"last_hit_by": game.tracker.last_hit_by if game.player.is_dead else "",
		"kills": Run.kills, "alive": room.alive_count(), "picks": bot.picks.duplicate(), "stats": bot.stats.duplicate(true),
		"rooms": bot.rooms.duplicate(true), "game_time": game.tracker.run_time,
	}
	if bot.telemetry_enabled and is_instance_valid(bot.telemetry):
		row["telemetry"] = bot.telemetry.result()
	if FileAccess.file_exists(out):
		_abort("результат появился во время боя; существующий файл не перезаписывается")
		return
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		_abort("нельзя записать файл результата")
		return
	file.store_line(JSON.stringify(row))
	file.close()
	print("FIXED ENCOUNTER: %s, body=%s, seed=%d, spawned=%d/%d, valid=%s" % [outcome, body, seed_value, spawned.size(), planned.size(), str(valid)])
	if not valid:
		_abort("встреча не соответствует запланированным маркерам или получена награда")
		return
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit()
