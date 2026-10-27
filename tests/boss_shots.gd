extends Node
## Кадры боссов (нужен дисплей; в CI — через xvfb-run): Толстый Свен на своей арене (таран, лужи, раздувание)
## и Ярл Бьорн по фазам (рука-бумеранг, балкон и корм, сломанные балконы, бодание); и двери-награды после зала.
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/boss_shots.tscn -- <папка>

var out_dir := "user://boss_shots"
var game: Game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

## Ждать sec секунд; Тор бессмертен.
func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().physics_frame
		if game and is_instance_valid(game) and game.player:
			game.player.health = game.player.max_health

func wait_until(cond: Callable, timeout: float) -> bool:
	for i in int(ceil(timeout * 60.0)):
		if cond.call():
			return true
		await wait(1.0 / 60.0)
	return cond.call()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot: ", name)

func _start(order: Array, index: int) -> void:
	Run.start_run("berserker")
	Run.room_order.assign(order)
	Run.room_index = index
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.4)
	game = get_tree().current_scene as Game

## Тор стоит в pos и смотрит на target (чуть сверху вниз — pitch)
func _look(pos: Vector3, target: Vector3, pitch: float = -0.12) -> void:
	var p := game.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	var to := target - pos
	p.rotation_target = Vector2(pitch, atan2(-to.x, -to.z))

func _kill_all_but(keep: Enemy) -> void:
	for e in game.room.alive_enemies().duplicate():
		if e != keep and is_instance_valid(e) and not e.is_dead and not e.has_meta("jarl_summon"):
			e.take_hit(9999, Vector3.ZERO, "test")

func _run() -> void:
	await _doors()
	if not "doors_only" in OS.get_cmdline_user_args():
		await _sven()
		await _jarl()
	print("boss shots: done")
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0)

const DoorHelper := preload("res://tests/door_helper.gd")

## Двери-награды после зачистки первого зала: три арки с иконками и подписями.
func _doors() -> void:
	await _start([Run.ROOM_SCENES[1], Run.ROOM_SCENES[2]], 0)
	Run.forced_offers.assign([["elite", "shop", "freya"]])
	await wait(1.0)
	for i in 200:
		_kill_all_but(null)
		if game.room._is_cleared:
			break
		await wait(0.3)
	await wait(1.0)
	await DoorHelper.resolve_reward(get_tree(), game)
	for i in 40:
		if not game.rewards.doors.is_empty():
			break
		await DoorHelper.resolve_reward(get_tree(), game)
		await wait(0.3)
	await wait(1.5)
	if game.rewards.doors.is_empty():
		print("дверей нет")
		return
	# Без берсерка (зачистка набила серию) — виньетка не закрывает арки
	if game.player.rage:
		game.player.rage.reset()
	await wait(1.2)
	var mid := game.rewards.doors[game.rewards.doors.size() / 2]
	var dz := mid.global_position
	# С центральной платформы зала (2.6 м) — все три арки сверху
	_look(Vector3(dz.x, dz.y + 2.7, dz.z + 10.0), dz + Vector3(0, 2.4, 0), 0.0)
	await wait(0.6)
	await shot("doors_01")

func _sven() -> void:
	var mi: int = Run.miniboss_rooms[0] if not Run.miniboss_rooms.is_empty() else 3
	var order: Array = []
	for i in mi:
		order.append(Run.ROOM_SCENES[i % Run.ROOM_SCENES.size()])
	order.append(Run.miniboss_arena)
	order.append(Run.BOSS_SCENE)
	await _start(order, mi)
	var sven: FatSven = null
	for i in 40:
		for e in game.room.alive_enemies():
			if e is FatSven:
				sven = e as FatSven
		if sven:
			break
		_kill_all_but(null)
		await wait(0.3)
	if sven == null:
		print("Свен не появился")
		return
	await wait(sven._spawn_time + 0.3)
	_kill_all_but(sven)
	await wait(1.0)
	var o := game.room.global_position
	sven._spit_cd = 999.0
	sven._charge_cd = 999.0
	sven.global_position = o + Vector3(0, 0.05, -6)
	_look(o + Vector3(2.5, 0.1, 5), sven.global_position + Vector3(0, 1.4, 0), -0.05)
	await wait(0.6)
	await shot("sven_01_arena")
	# Таран: полоса-телеграф на полу
	sven._charge_cd = 0.0
	if await wait_until(func() -> bool: return sven.act == FatSven.Act.CHARGE_AIM, 4.0):
		_look(o + Vector3(4.5, 0.1, 5), sven.global_position + Vector3(0, 0.5, 0), -0.2)
		await wait(0.35)
		await shot("sven_02_charge_telegraph")
	await wait_until(func() -> bool: return sven.act == 0, 6.0)
	# Брага: плевки и лужи
	sven._charge_cd = 999.0
	sven._spit_cd = 0.0
	sven.global_position = o + Vector3(0, 0.05, -5)
	_look(o + Vector3(0, 0.1, 3), sven.global_position, -0.25)
	await wait_until(func() -> bool: return get_tree().get_nodes_in_group("brew_puddles").size() >= 2, 5.0)
	sven._spit_cd = 999.0
	_look(o + Vector3(3.5, 0.1, 6), o + Vector3(0, 0.0, 0), -0.35)
	await wait(0.4)
	await shot("sven_03_puddles")
	# Раздувание и фитиль
	sven.global_position = o + Vector3(0, 0.05, -6)
	_look(o + Vector3(0, 0.1, 4), sven.global_position + Vector3(0, 1.2, 0), -0.1)
	sven.take_hit(sven.health - sven.max_health * 0.2, Vector3.ZERO, "melee")
	if await wait_until(func() -> bool: return sven.act == FatSven.Act.FUSE, 8.0):
		var sp := sven.global_position
		_look(sp + (game.player.global_position - sp).normalized() * 6.5 + Vector3(0, 0.1, 0), sp + Vector3(0, 1.0, 0), -0.2)
		await wait(0.3)
		await shot("sven_04_fuse")
	await wait(2.5)

func _jarl() -> void:
	await _start([Run.BOSS_SCENE], 0)
	var jarl: JarlBoss = null
	for i in 40:
		for e in game.room.alive_enemies():
			if e is JarlBoss:
				jarl = e as JarlBoss
		if jarl:
			break
		await wait(0.2)
	if jarl == null:
		print("Ярл не появился")
		return
	await wait(jarl._spawn_time + 0.3)
	_kill_all_but(jarl)
	if Dialogue.box().visible:
		Dialogue.box().skip()
	get_tree().paused = false
	var o := game.room.global_position
	jarl.global_position = o + Vector3(0, 0.05, -8)
	_look(o + Vector3(1.5, 0.1, 4), jarl.global_position + Vector3(0, 1.8, 0), 0.0)
	await wait(0.5)
	await shot("jarl_01_hall")
	# Фаза 1: рука-бумеранг
	jarl._throw_cd = 0.0
	if await wait_until(func() -> bool: return jarl.act == JarlBoss.Act.ARMLESS, 5.0):
		await wait(0.25)
		await shot("jarl_02_arm_throw")
	await wait_until(func() -> bool: return jarl.act != JarlBoss.Act.ARMLESS, 6.0)
	# Фаза 2: балкон и корм
	jarl.take_hit((jarl.health - jarl.max_health * 0.6) / jarl.armed_damage_mult, Vector3.ZERO, "melee")
	if await wait_until(func() -> bool: return jarl.act == JarlBoss.Act.PERCH, 8.0):
		await wait_until(func() -> bool: return game.room.alive_enemies().any(func(e: Enemy) -> bool: return e.has_meta("jarl_summon")), jarl.summon_interval + 2.0)
		await wait(0.8)
		var jp := jarl.global_position
		var flat := Vector3(o.x - jp.x, 0, o.z - jp.z).normalized()
		_look(Vector3(jp.x, o.y, jp.z) + flat * 9.0 + Vector3(0, 0.1, 0), jp + Vector3(0, 1.2, 0), 0.18)
		await wait(0.4)
		await shot("jarl_03_balcony")
	# Фаза 3: ломает балконы
	jarl.take_hit(30.0, Vector3.ZERO, "slam")
	await wait_until(func() -> bool: return jarl.act == JarlBoss.Act.KNOCKED, 3.0)
	jarl.take_hit((jarl.health - jarl.max_health * 0.3) / jarl.window_damage_mult, Vector3.ZERO, "melee")
	if await wait_until(func() -> bool: return jarl.phase == 3 and jarl.act == JarlBoss.Act.BREAK, 8.0):
		_look(o + Vector3(0, 0.1, 9), o + Vector3(0, 1.5, -6), 0.08)
		await wait(1.2)
		await shot("jarl_04_break")
	await wait_until(func() -> bool: return jarl.act == 0, 8.0)
	# Бодание: полоса-телеграф
	for e in game.room.alive_enemies().duplicate():
		if e != jarl:
			e.take_hit(9999, Vector3.ZERO, "test")
	jarl.global_position = o + Vector3(0, 0.05, -10)
	_look(o + Vector3(3, 0.1, 5), jarl.global_position + Vector3(0, 0.6, 0), -0.18)
	jarl._slam_cd = 999.0
	jarl._butt_cd = 0.0
	if await wait_until(func() -> bool: return jarl.act == JarlBoss.Act.BUTT_AIM, 4.0):
		await wait(0.3)
		await shot("jarl_05_butt_telegraph")
	await wait_until(func() -> bool: return jarl.act == 0, 5.0)
	# Прыжок с ударной волной: круг на полу
	jarl._butt_cd = 999.0
	jarl._slam_cd = 0.0
	jarl.global_position = o + Vector3(0, 0.05, -10)
	_look(o + Vector3(0, 0.1, 2), jarl.global_position, -0.1)
	if await wait_until(func() -> bool: return jarl.act == JarlBoss.Act.SLAM_LEAP, 4.0):
		await wait(0.35)
		await shot("jarl_06_leap")
	await wait_until(func() -> bool: return jarl.act == 0, 4.0)
	# Поражение: голова катится
	jarl.take_hit(9999, Vector3.ZERO, "melee_finisher")
	await wait(1.2)
	await shot("jarl_07_defeat")
