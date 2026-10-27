extends Node
## Поиск фризов: проходит все залы (арена Свена — в зале мини-босса, ларёк/отдых — по дверям), игрок бьёт
## топором, стреляет, бросает молот, делает удар-приземление (с руной огня), встаёт на прыжковые руны;
## враги атакуют, боссы получают урон частями и успевают пройти фазы. Фриз — кадр, который дольше медианы соседних кадров на порог и больше.
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
var _slam_impacts: int = 0

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

const DoorHelper := preload("res://tests/door_helper.gd")
var _door_pick: int = 0

func _now() -> int:
	return Engine.get_process_frames()

func _run() -> void:
	print("=== HITCH TEST (порог +%d мс к медиане, %s) ===" % [int(threshold_ms), "headless" if DisplayServer.get_name() == "headless" else RenderingServer.get_current_rendering_method()])
	Run.start_run("berserker")
	Run.room_order.assign(Run.ROOM_SCENES.duplicate())
	Run.room_order.append(Run.BOSS_SCENE)
	# Зал мини-босса — арена Свена (как в настоящем забеге)
	Run._place_miniboss_arenas()
	_load_frames.append(_now())
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.3)
	game = get_tree().current_scene as Game
	game.player.slammed.connect(func(_power: float) -> void: _slam_impacts += 1)
	# Руна огня — чтобы удар-приземление оставлял огонь; молот — молнии
	for r in Run.all_runes:
		if r.id in ["slam_fire", "hammer_power"]:
			Run.add_rune(r)
	game.player.recalc_from_runes(Run)
	# Ренж в слоте — чтобы выстрелы, трассеры и гильзы тоже попали в замер
	game.player.weapons.equip(Loot.get_def("smg"), 1, false)
	game.player.weapons.switch_to(WeaponHolder.MELEE, true)
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
	if Run.is_peaceful_room():
		await wait(1.2)
		print("  тихий зал: %s (%s)" % [room.room_title, Run.current_reward()])
		return
	# Прыжковые руны зала (rooms/jump_pad.gd): встаём на каждую — подброс, кольцо, искры
	for pad in get_tree().get_nodes_in_group("jump_pads"):
		if room.is_ancestor_of(pad):
			p.global_position = (pad as Node3D).global_position + Vector3(0, 0.2, 0)
			p.velocity = Vector3.ZERO
			await wait(1.2)
	# Разрушаемое: первое разрушение бочки, ящика, взрывной бочки в зале — перед глазами Тора
	# (обломки, пыль, щепки, слово; пайплайны кусков прогреты ShaderWarmup)
	var kinds := {}
	for n in get_tree().get_nodes_in_group("destructibles"):
		# Взрыв прошлой бочки мог разбить соседей
		if not is_instance_valid(n) or (n as Node).is_queued_for_deletion():
			continue
		var d := n as Destructible
		if d == null or d.is_broken or not room.is_ancestor_of(d) or kinds.has(d.scene_file_path):
			continue
		kinds[d.scene_file_path] = true
		var to_d := d.global_position - p.global_position
		p.rotation_target.y = atan2(-to_d.x, -to_d.z)
		await wait(0.2)
		p.heal(999)
		d.take_hit(999.0, Vector3(0, 2, -6), "ranged")
		await wait(0.5)
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
			0:
				p.axe.request_attack()
			3:
				# Очередь из ренжа и обратно на мили
				p.weapons.switch_to(WeaponHolder.RANGED, true)
				for k in 4:
					p.weapons.gun.try_fire()
					await wait(0.08)
				p.weapons.ranged.reserve = p.weapons.ranged.def.reserve_max
				p.weapons.switch_to(WeaponHolder.MELEE, true)
			1:
				if p.mjolnir.in_hand:
					p.mjolnir.throw_hammer()
			2:
				# Н2: обычный прыжок не открывает удар. Делать воздушный прыжок,
				# как игрок, либо использовать доступный с высоты/отскока удар.
				await _jump_and_slam(p)
		await wait(0.25)
		# Добиваем по одному — смерть каждого врага отдельным событием. Босса и мини-босса — частями
		# («slam» сбивает Ярла с балкона): успевают показать свои атаки и фазы (таран, лужи, балконы, обломки)
		if is_instance_valid(e) and not e.is_dead:
			if e.kind == Enemy.Kind.BOSS:
				e.take_hit(e.max_health * 0.12, Vector3(0, 1, -2), "slam")
			else:
				e.take_hit(9999, Vector3(0, 3, -5), "melee_finisher")
	print("  зал зачищен: %s" % room.room_title)

## Страхуем запас рун в тестовой сцене, чтобы независимо от исхода предыдущих действий
## увидеть эффекты удара в каждом прогоне. Прыжок и Ctrl отправляются через обычный ввод.
func _jump_and_slam(p: Player) -> void:
	if p.is_on_floor():
		Input.action_press("jump")
		await wait(0.05)
		Input.action_release("jump")
		await wait(0.12)
	if not p.is_on_floor() and not p.can_start_slam() and p._jumps_left > 0:
		p.restore_mjolnir_runes(p.dash_charges_max)
		Input.action_press("jump")
		await wait(0.05)
		Input.action_release("jump")
		await wait(0.05)
	if p.can_start_slam():
		Input.action_press("slam")
		await wait(0.05)
		Input.action_release("slam")
		# Приземление и эффекты должны случиться до следующего сценария боя.
		for i in 90:
			if not p.is_slamming:
				break
			await get_tree().physics_frame

func _go_next() -> void:
	var room := game.room
	await wait(1.2)
	# Награда зала (трейт, руна, отдых, Локи…) → двери-награды (блок И) → входим в дверь по кругу
	await DoorHelper.resolve_reward(get_tree(), game)
	await wait(1.0)
	var doors := game.rewards.doors
	var d: RewardDoor = doors[_door_pick % doors.size()] if not doors.is_empty() else null
	_door_pick += 1
	_load_frames.append(_now())
	if d:
		game.player.global_position = d.trigger_position()
	game.player.velocity = Vector3(0, 0, -2)
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
	_report_pipelines(fr)
	print("Удары-приземления с реальным приземлением: %d" % _slam_impacts)
	if _slam_impacts == 0:
		printerr("HITCH FAIL: удар-приземление ни разу не выполнился")
	print("=== ИТОГ HITCH: %d фризов > +%d мс вне загрузки ===" % [bad.size(), int(threshold_ms)])
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if bad.is_empty() and _slam_impacts > 0 else 1)

## Компиляции пайплайнов (Forward+/Mobile; в GL Compatibility счётчиков нет) вне загрузки залов: сколько и
## после каких событий. pso_draw — компиляция прямо при отрисовке (= фриз на настоящей видеокарте).
func _report_pipelines(fr: Array) -> void:
	var totals := {}
	var lines: Array = []
	for x in fr:
		var ev: String = x[2]
		if not ev.contains("pso_") or _in_load_window(x[0]):
			continue
		var pso := PackedStringArray()
		for m in ev.split(","):
			if m.begins_with("pso_"):
				pso.append(m)
				var k := m.get_slice("+", 0)
				totals[k] = int(totals.get(k, 0)) + m.get_slice("+", 1).to_int()
		if not pso.is_empty() and lines.size() < 40:
			lines.append("  кадр %d  %.1f мс  %s  [%s]  (до: %s)" % [x[0], x[1], ",".join(pso), ev, x[3]])
	print("Компиляции пайплайнов вне загрузки залов: %s" % (str(totals) if not totals.is_empty() else "нет"))
	for l in lines:
		print(l)
