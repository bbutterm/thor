extends Node
## Короткая графическая проверка ОДНОГО зала. Не проверяет скорость и не является hitch-прогоном.
## Пример: godot --path . --rendering-method forward_plus --resolution 320x180 res://tests/warmup_probe.tscn
## Нужен настоящий Forward+ с окном. Мониторы накопительные и асинхронные: метки фаз показывают,
## когда изменился счётчик, а не какой материал или процессорная операция вызвали компиляцию.
## frame_post_draw сам по себе не доказывает завершения работы GPU.

const MONITORS := {
	"canvas": Performance.PIPELINE_COMPILATIONS_CANVAS,
	"mesh": Performance.PIPELINE_COMPILATIONS_MESH,
	"surface": Performance.PIPELINE_COMPILATIONS_SURFACE,
	"draw": Performance.PIPELINE_COMPILATIONS_DRAW,
	"specialization": Performance.PIPELINE_COMPILATIONS_SPECIALIZATION,
}
var _last: Dictionary = {}
var _totals := {"before": {}, "warmup": {}, "after": {}, "replay": {}, "outline": {}, "skill": {}}
var _warm_seen := false
var _warm_active := false
var _warm_finished := false
var _frame_count := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "WarmupProbeRunner"
		get_tree().root.add_child.call_deferred(runner)
		return
	get_tree().node_added.connect(_node_added)
	get_tree().node_removed.connect(_node_removed)
	_run.call_deferred()

func _node_added(node: Node) -> void:
	if node is ShaderWarmup:
		_warm_seen = true
		_warm_active = true
	elif node is Room:
		# Комната одна; не включаем бои и переходы в другой зал.
		node.set_physics_process(false)

func _node_removed(node: Node) -> void:
	if node is ShaderWarmup:
		_warm_active = false
		_warm_finished = true

func _values() -> Dictionary:
	var out := {}
	for key in MONITORS:
		out[key] = int(Performance.get_monitor(MONITORS[key]))
	return out

## Отсчёт после сигнала — не синхронизация GPU; возможны запоздалые фоновые изменения.
func _capture(requested_phase: String = "") -> void:
	await RenderingServer.frame_post_draw
	_frame_count += 1
	var phase := requested_phase
	if phase == "":
		phase = "warmup" if _warm_active else ("after" if _warm_finished else "before")
	var now := _values()
	var bucket: Dictionary = _totals[phase]
	for key in MONITORS:
		var before: int = _last.get(key, now[key])
		var current: int = now[key]
		var delta := current - before if current >= before else current
		bucket[key] = int(bucket.get(key, 0)) + delta
		if delta > 0:
			print("  frame=%d phase=%s %s+%d" % [_frame_count, phase, key, delta])
	_last = now

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		printerr("WARMUP PROBE FAIL: нужен Forward+ с окном; headless и GL не измеряют этот счётчик")
		get_tree().quit(1)
		return
	print("=== FORWARD+ WARMUP PROBE: один зал, без оценки скорости ===")
	print("renderer=", RenderingServer.get_current_rendering_method(), " adapter=", RenderingServer.get_video_adapter_name())
	_last = _values()
	await _capture("before")
	Dialogue.in_run_scenes = false
	seed(28102026)
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	Run.room_rewards.clear()
	Run.miniboss_rooms.clear()
	Run.doors_enabled = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	for i in 40:
		await _capture()
		if _warm_finished:
			break
	if not _warm_seen or not _warm_finished:
		printerr("WARMUP PROBE FAIL: прогрев не появился и не завершился за 40 кадров")
		get_tree().quit(1)
		return
	var game := get_tree().current_scene as Game
	if game == null or game.room == null or game.room.scene_file_path != "res://rooms/room_01.tscn":
		printerr("WARMUP PROBE FAIL: первый зал не загружен")
		get_tree().quit(1)
		return
	game.player.input_enabled = false
	# После исчезновения образцов продолжаем наблюдать, включая отложенные изменения счётчиков.
	for i in 8:
		await _capture("after")
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		printerr("WARMUP PROBE FAIL: нет камеры")
		get_tree().quit(1)
		return
	# Повторно рисуем именно варианты материалов и форматов, отобранные из первого зала.
	var anchor := Node3D.new()
	anchor.position = Vector3(0, -1.0, -3.2)
	cam.add_child(anchor)
	var samples := RoomDress.warmup_room(anchor, game.room)
	var in_view := 0
	for node in samples.get_children():
		var gi := node as GeometryInstance3D
		var mesh := RoomDress._room_mesh(gi) if gi else null
		if gi and mesh and gi.is_visible_in_tree() and (gi.layers & cam.cull_mask) != 0 \
				and cam.is_position_in_frustum(gi.to_global(mesh.get_aabb().get_center())):
			in_view += 1
	print("Повторные образцы зала: %d, их центры в поле камеры: %d" % [samples.get_child_count(), in_view])
	if samples.get_child_count() == 0 or in_view != samples.get_child_count():
		printerr("WARMUP PROBE FAIL: часть образцов не находится в поле камеры")
		get_tree().quit(1)
		return
	for i in 8:
		await _capture("replay")
	anchor.queue_free()
	# Настоящий корм в кадре стоит неподвижно: проверяем переключение обводки не на пустой сцене.
	var fodder := (load("res://enemies/fodder.tscn") as PackedScene).instantiate() as Enemy
	fodder.process_mode = Node.PROCESS_MODE_DISABLED
	fodder.position = game.to_local(cam.global_position - cam.global_basis.z * 3.0 - Vector3.UP * 0.8)
	game.add_child(fodder)
	fodder.collision_layer = 0
	fodder.collision_mask = 0
	if fodder._humanoid:
		fodder._humanoid.play(fodder.anim_idle, 0.0)
		if fodder._humanoid.anim:
			fodder._humanoid.anim.seek(0.1, true)
	for i in 3:
		await _capture("outline")
	var outlined := Outline.active_count(fodder)
	if fodder.is_dead or fodder._flash_meshes.is_empty() or outlined == 0 \
			or not cam.is_position_in_frustum(fodder.global_position + Vector3.UP * 0.8) \
			or not fodder._flash_meshes.any(func(g: GeometryInstance3D) -> bool: return g.is_visible_in_tree() and (g.layers & cam.cull_mask) != 0):
		printerr("WARMUP PROBE FAIL: живой обведённый враг не виден камере")
		get_tree().quit(1)
		return
	print("Неподвижный корм в поле камеры, обведённых мешей: ", outlined)
	GameSettings.set_value("video", "outline", false, false)
	for i in 3:
		await _capture("outline")
	if Outline.active_count(fodder) != 0:
		printerr("WARMUP PROBE FAIL: обводка врага не выключилась")
		get_tree().quit(1)
		return
	GameSettings.set_value("video", "outline", true, false)
	for i in 3:
		await _capture("outline")
	if Outline.active_count(fodder) != outlined:
		printerr("WARMUP PROBE FAIL: обводка врага не включилась обратно")
		get_tree().quit(1)
		return
	# Кольцо и слово нового приёма используют те же ресурсы, что и настоящие действия.
	var impact := cam.global_position - cam.global_basis.z * 3.0 - Vector3.UP
	FX.ring(game, impact, 2.5, Color(0.7, 0.9, 1.0, 0.8), 0.35)
	ComicFX.pop("weapon_whirl", impact + Vector3.UP)
	for i in 8:
		await _capture("skill")
	for phase in ["before", "warmup", "after", "replay", "outline", "skill"]:
		print("  %s: %s" % [phase, _totals[phase]])
	var later_draw := 0
	var later_all := 0
	for phase in ["after", "replay", "outline", "skill"]:
		var bucket: Dictionary = _totals[phase]
		later_draw += int(bucket.get("draw", 0))
		for key in MONITORS:
			later_all += int(bucket.get(key, 0))
	print("После прогрева: draw +%d; все счётчики вместе +%d" % [later_draw, later_all])
	print("Фазы привязаны к наблюдению счётчиков, не к завершению GPU и не доказывают причину старого +14.")
	if later_all > 0:
		printerr("WARMUP PROBE FAIL: после прогрева остались компиляции (draw +%d, всего +%d)" % [later_draw, later_all])
	get_tree().quit(1 if later_all > 0 else 0)
