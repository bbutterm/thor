extends Node
## Поиск фризов: проходит все залы, игрок бьёт топором, бросает молот, делает удар-приземление
## (с руной огня), враги атакуют. Фриз — кадр, который дольше медианы соседних кадров на порог и больше.
## (Относительно медианы — потому что программный рендер в xvfb сам по себе медленный.)
## С рендерингом (нужен xvfb):
##   xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 320x180 res://tests/hitch_test.tscn -- 50
## Без рендеринга (только CPU-часть: сборка врагов, загрузка ресурсов, физика):
##   godot --headless --path . --fixed-fps 60 res://tests/hitch_test.tscn -- 50
## Аргумент — порог в мс (по умолчанию 50).

## Сколько кадров после смены зала не считаем (затемнение экрана, загрузка)
const LOAD_GRACE_FRAMES := 45
const MEDIAN_WINDOW := 31

var game: Game
var threshold_ms: float = 50.0
var _load_frames: Array[int] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "HitchRunner"
		get_tree().root.add_child.call_deferred(runner)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_float():
		threshold_ms = args[0].to_float()
	_run.call_deferred()

func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().physics_frame

func _now() -> int:
	return Engine.get_process_frames()

func _run() -> void:
	print("=== HITCH TEST (порог +%d мс к медиане, %s) ===" % [int(threshold_ms), "headless" if DisplayServer.get_name() == "headless" else RenderingServer.get_current_rendering_method()])
	Run.start_run("berserker")
	Run.room_order.assign(Run.ROOM_SCENES.duplicate())
	Run.room_order.append(Run.BOSS_SCENE)
	_load_frames.append(_now())
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.3)
	game = get_tree().current_scene as Game
	# Руна огня — чтобы удар-приземление оставлял огонь; молот — молнии
	for r in Run.all_runes:
		if r.id in ["slam_fire", "hammer_power"]:
			Run.add_rune(r)
	game.player.recalc_from_runes(Run)
	Perf.frames.clear()
	Perf.record_all = true
	var total := Run.total_rooms()
	for i in total:
		await _play_room()
		if i == total - 1:
			break
		await _go_next()
	await wait(1.0)
	Perf.record_all = false
	_report()

func _play_room() -> void:
	var room := game.room
	var p := game.player
	var safety := 0
	var step := 0
	while not room._is_cleared and safety < 120:
		safety += 1
		step += 1
		p.heal(999)
		var alive := room.alive_enemies().duplicate()
		# Даём врагам подойти и замахнуться (свечение, снаряды, телеграф босса)
		await wait(0.35)
		if alive.is_empty() or not is_instance_valid(alive[0]):
			continue
		var e := alive[0] as Enemy
		if e.is_dead:
			continue
		# Разворачиваем игрока к врагу и пробуем разные действия
		var to := e.global_position - p.global_position
		p.rotation_target.y = atan2(-to.x, -to.z)
		match step % 4:
			0, 3:
				p.axe.request_attack()
			1:
				if p.mjolnir.in_hand:
					p.mjolnir.throw_hammer()
			2:
				p.velocity.y = 9.0
				await wait(0.25)
				Input.action_press("slam")
				await wait(0.05)
				Input.action_release("slam")
		await wait(0.25)
		# Добиваем по одному — смерть каждого врага отдельным событием
		if is_instance_valid(e) and not e.is_dead:
			e.take_hit(9999, Vector3(0, 3, -5), "axe_finisher")
	print("  зал зачищен: %s" % room.room_title)

func _go_next() -> void:
	var room := game.room
	await wait(1.2)
	if game.trait_pick.visible:
		game.trait_pick._open_time = -10.0
		game.trait_pick.choose(0, true)
		await wait(1.0)
	if game.rune_pick.visible:
		game.rune_pick._open_time = -10.0
		game.rune_pick.choose(0)
	await wait(0.6)
	_load_frames.append(_now())
	game.player.global_position = room.exit_area.global_position + Vector3(0, 0.2, 1.5)
	game.player.velocity = Vector3(0, 0, -6)
	for i in 120:
		await get_tree().physics_frame
		if game.room != room:
			break
	_load_frames.append(_now())

func _in_load_window(f: int) -> bool:
	for lf in _load_frames:
		if f >= lf - 2 and f <= lf + LOAD_GRACE_FRAMES:
			return true
	return false

func _report() -> void:
	var fr: Array = Perf.frames
	var times := PackedFloat32Array()
	for x in fr:
		times.append(x[1])
	var bad: Array = []
	var shown: Array = []
	var worst := 0.0
	var all_ms := times.duplicate()
	all_ms.sort()
	var global_median := all_ms[all_ms.size() / 2] if all_ms.size() > 0 else 0.0
	var headless := DisplayServer.get_name() == "headless"
	var noise := 0
	for i in fr.size():
		var lo := maxi(0, i - MEDIAN_WINDOW / 2)
		var hi := mini(fr.size(), i + MEDIAN_WINDOW / 2 + 1)
		var win := times.slice(lo, hi)
		win.sort()
		var med: float = win[win.size() / 2]
		var excess: float = fr[i][1] - med
		if excess > threshold_ms * 0.5:
			var loading := _in_load_window(fr[i][0])
			# Программный рендер (xvfb) сам по себе даёт случайные всплески в кадрах без событий —
			# с рендерингом считаем фризом только кадр, где (или кадром раньше) что-то произошло.
			var has_events: bool = fr[i][2] != "" or fr[i][3] != ""
			var counts := not loading and (has_events or headless)
			shown.append("  %s кадр %d  %.1f мс (медиана %.1f)  [%s]  (до: %s)" % [">>>" if counts else ("  ~" if not loading else "   "), fr[i][0], fr[i][1], med, fr[i][2], fr[i][3]])
			if not loading:
				if counts:
					worst = maxf(worst, excess)
					if excess > threshold_ms:
						bad.append(fr[i])
				elif excess > threshold_ms:
					noise += 1
	print("Кадров: %d, медиана %.1f мс; худший всплеск по событию вне загрузки залов: +%.1f мс" % [fr.size(), global_median, worst])
	print("(>>> — считается; ~ — всплеск без событий, шум программного рендера; без пометки — загрузка зала)")
	for line in shown:
		print(line)
	if noise > 0:
		print("Всплесков без событий > +%d мс: %d (не считаются)" % [int(threshold_ms), noise])
	print("=== ИТОГ HITCH: %d фризов > +%d мс вне загрузки ===" % [bad.size(), int(threshold_ms)])
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if bad.is_empty() else 1)
