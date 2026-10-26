extends Node
## Музыка (GDD 21): треки и слои, переход слоёв на доле, приглушение, стингер, авто-выбор трека в забеге.
## godot --headless --path . --fixed-fps 60 res://tests/music_test.tscn

var _fails: Array[String] = []
var _passes: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()

func check(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
		print("  [OK] ", what)
	else:
		_fails.append(what)
		print("  [FAIL] ", what)

func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().process_frame

func _layer_db(i: int) -> float:
	var sync := Music._player.stream as AudioStreamSynchronized
	return sync.get_sync_stream_volume(i) if sync else -999.0

func _run() -> void:
	print("=== MUSIC TEST ===")
	for t in ["midgard", "boss", "miniboss", "menu", "plan", "shop"]:
		check(Music.has_track(t), "трек «%s» найден" % t)
	check(Music._stinger.stream != null, "стингер удара-приземления загружен")
	Music.auto = false
	Music.play_track("midgard", true)
	await wait(0.2)
	var sync := Music._player.stream as AudioStreamSynchronized
	check(sync != null and sync.stream_count == 3, "три слоя играют синхронно")
	check(Music._player.playing, "трек играет")
	check(_layer_db(0) > -1.0 and _layer_db(1) < -60.0 and _layer_db(2) < -60.0, "вне боя — только фон")
	Music.set_intensity(1)
	await wait(1.6)
	check(Music.intensity == 1 and _layer_db(1) > -3.0, "бой — добавились барабаны (%.1f дБ)" % _layer_db(1))
	Music.set_intensity(2)
	await wait(1.6)
	check(_layer_db(2) > -3.0, "Ярость — полный трек")
	Music.set_intensity(0)
	await wait(1.6)
	check(_layer_db(1) < -60.0 and _layer_db(0) > -1.0, "зал зачищен — обратно фон, без обрыва")
	Music.set_muffled(true)
	await wait(0.6)
	check(Music._lpf.cutoff_hz < 2000.0, "пауза/диалог — фильтр низких частот (%.0f Гц)" % Music._lpf.cutoff_hz)
	Music.set_muffled(false)
	await wait(0.6)
	check(Music._lpf.cutoff_hz > 15000.0, "фильтр снят")
	Music.play_track("boss")
	await wait(2.5)
	check(Music.current_track == "boss", "смена трека на такте (сейчас %s)" % Music.current_track)

	print("-- В забеге")
	Music.auto = true
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(2.5)
	var g := get_tree().current_scene as Game
	check(Music.current_track == "midgard" or Music._pending_track == "midgard", "в зале Мидгарда — тема Мидгарда")
	await wait(1.5)
	check(Music.intensity == 1, "враги в зале — слой боя")
	g.player._do_slam_impact(12.0)
	await wait(0.05)
	check(Music._duck_left > 0.0, "удар-приземление с высоты — стингер и провал музыки")
	get_tree().paused = true
	await wait(0.6)
	check(Music.muffled, "пауза — музыка приглушена")
	get_tree().paused = false
	await wait(0.6)
	check(not Music.muffled, "после паузы — снова чисто")
	_finish()

func _finish() -> void:
	print("=== ИТОГ MUSIC: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
