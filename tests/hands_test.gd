extends Node
## Руки от первого лица (блок Б2): каждое действие включает своё движение, рука возвращается в покой за отведённое
## время, в трансформах нет NaN, кадры попадания (мили, бросок, выстрел) не зависят от анимации.
## godot --headless --path . --fixed-fps 60 res://tests/hands_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game
var p: Player
var vm: ViewmodelMotion
## Кадры с NaN в руках (проверяется каждый кадр всего теста)
var _nan_frames: int = 0
var _frames: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "HandsRunner"
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
		await get_tree().physics_frame

func _process(_delta: float) -> void:
	if vm and is_instance_valid(vm):
		_frames += 1
		if not vm.transforms_finite():
			_nan_frames += 1

## Ждать, пока рука вернётся в покой (не дольше limit). Возвращает прошедшее время или -1.
func wait_rest(h: ViewmodelMotion.Hand, limit: float) -> float:
	var t := 0.0
	while t < limit:
		if h.state == &"rest":
			return t
		await get_tree().physics_frame
		t += 1.0 / 60.0
	return -1.0

func _dummy(pos: Vector3, hp: float = 5000.0) -> Enemy:
	var e := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	e.max_health = hp
	game.add_child(e)
	e.global_position = pos
	e.health = hp
	e.set_physics_process(false)
	return e

func _run() -> void:
	print("=== HANDS TEST ===")
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.5)
	game = get_tree().current_scene as Game
	await wait(1.0)
	game.room.set_physics_process(false)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	p = game.player
	vm = p.view_motion
	var floor_pos := Vector3(game.room.global_position.x, 0.05, game.room.global_position.z + 8.0)
	p.global_position = floor_pos
	p.velocity = Vector3.ZERO
	await wait(0.4)

	print("-- Сборка")
	check(vm != null and vm.right != null and vm.left != null, "ViewmodelMotion и две руки")
	check(vm.right.arm != null and vm.right.arm.skeleton != null and vm.left.arm != null and vm.left.arm.skeleton != null,
		"обе руки собраны из модели с костями")
	check(vm.right.arm.side == "right" and vm.left.arm.side == "left", "правая — мили/ренж, левая — Мьёльнир")
	check(vm.right.state == &"rest" and vm.left.state == &"rest", "в начале обе руки в покое")
	check(vm.tuning != null and vm.tuning.resource_path == ViewmodelMotion.TUNING_PATH, "числа — из player/viewmodel_motion.tres")
	check(vm.transforms_finite(), "трансформы рук конечны")

	await _melee()
	await _hit_timing()
	await _hitstop_freeze()
	await _mjolnir()
	await _ranged()
	await _general()
	check(_nan_frames == 0, "ни одного кадра с NaN в руках (%d кадров)" % _frames)
	_finish()

func _melee() -> void:
	print("-- Мили: комбо, добивающий, вертушка")
	var h := vm.right
	var axe := p.axe
	p.weapons.equip(load("res://weapons/defs/axe.tres") as WeaponDef, 1, false)
	p.weapons.switch_to(WeaponHolder.MELEE, true)
	await wait(0.3)
	var saw_windup := false
	var saw_strike := false
	var saw_fin := false
	var poses: Array[Vector3] = []
	for s in axe.combo_count():
		axe.request_attack()
		await get_tree().physics_frame
		if h.state == &"melee_windup" or h.state == &"finisher_windup":
			saw_windup = true
		while axe.phase == Axe.Phase.WINDUP:
			await get_tree().physics_frame
		await get_tree().process_frame
		if h.state == &"melee_strike":
			saw_strike = true
		if h.state == &"finisher":
			saw_fin = true
		while axe.phase == Axe.Phase.ACTIVE:
			await get_tree().physics_frame
		poses.append(h.position)
		while axe.phase != Axe.Phase.IDLE and axe.phase != Axe.Phase.WINDUP:
			if axe.phase == Axe.Phase.RECOVERY and axe._phase_time > axe._recovery_time() * 0.5:
				break
			await get_tree().physics_frame
	check(saw_windup, "замах включает состояние windup")
	check(saw_strike, "удар включает состояние strike")
	check(saw_fin, "последний удар комбо — состояние finisher")
	check(poses.size() == 3 and signf(poses[0].x - poses[1].x) != 0.0 and poses[0].x < poses[1].x,
		"удары 1 и 2 — в разные стороны (справа налево, слева направо)")
	var t := await wait_rest(h, 2.0)
	check(t >= 0.0, "после комбо рука в покое (%.2f с)" % t)
	check(h.position.distance_to(h.rest_pos) < 0.02, "поза покоя — поза оружия")
	await wait(0.3)
	axe.request_heavy()
	await get_tree().physics_frame
	check(axe.is_busy() and h.state == &"melee_strike", "вертушка включает анимацию руки")
	await wait(axe.def.skill_duration * 0.35)
	check(absf(h.rotation_degrees.z - h.rest_rot.z) > 30.0, "рука заметно поворачивается во время вертушки")
	t = await wait_rest(h, 2.5)
	check(t >= 0.0, "после вертушки рука возвращается в покой (%.2f с)" % t)

## Кадр попадания мили и момент броска не зависят от анимации рук (с ней и без неё одинаково).
func _hit_timing() -> void:
	print("-- Тайминги не зависят от анимации")
	var axe := p.axe
	var fwd := -p.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var e := _dummy(p.global_position + fwd * 1.6)
	await wait(0.3)
	var frames: Array[int] = []
	for on in [true, false]:
		vm.enabled = on
		await wait(1.0)
		var hit := [-1]
		var cb := func(_c: int, _s: int) -> void:
			if hit[0] < 0:
				hit[0] = Engine.get_physics_frames()
		axe.hit_landed.connect(cb)
		var f0 := Engine.get_physics_frames()
		axe.request_attack()
		for i in 60:
			await get_tree().physics_frame
			if hit[0] >= 0:
				break
		axe.hit_landed.disconnect(cb)
		frames.append(hit[0] - f0 if hit[0] >= 0 else -1)
		FX.reset_time()
	vm.enabled = true
	var expect := int(ceil(axe.stage_windup[0] * 60.0))
	check(frames[0] > 0 and frames[0] == frames[1], "кадр попадания одинаков с анимацией и без (%s)" % str(frames))
	check(absi(frames[0] - expect) <= 2, "попадание на %d-м кадре — по замаху оружия (~%d)" % [frames[0], expect])
	e.queue_free()
	await wait(1.0)
	# Бросок: молот вылетает в том же кадре, что и нажатие
	var mj := p.mjolnir
	mj.throw_hammer()
	check(not mj.in_hand and mj.projectile != null, "бросок: молот вылетел сразу (вид его догоняет)")
	mj.force_return_instant()
	await wait(0.6)

## Hit-stop: руки замирают (игровое время), потом продолжают.
func _hitstop_freeze() -> void:
	print("-- Hit-stop")
	var h := vm.right
	var axe := p.axe
	await wait_rest(h, 2.0)
	axe.request_attack()
	await get_tree().process_frame
	await get_tree().process_frame
	var a := h.pivot.transform.origin
	await get_tree().process_frame
	await get_tree().process_frame
	var free_move := h.pivot.transform.origin.distance_to(a)
	axe.cancel()
	await wait(0.5)
	axe.request_attack()
	FX.hitstop(0.3)
	await get_tree().process_frame
	await get_tree().process_frame
	a = h.pivot.transform.origin
	await get_tree().process_frame
	await get_tree().process_frame
	var frozen_move := h.pivot.transform.origin.distance_to(a)
	check(free_move > 0.003 and frozen_move < free_move * 0.25, "в hit-stop руки почти стоят (%.4f против %.4f)" % [frozen_move, free_move])
	FX.reset_time()
	await wait(1.0)

func _mjolnir() -> void:
	print("-- Мьёльнир: бросок, пустая рука, возврат, ловля, идеальный хват")
	var h := vm.left
	var mj := p.mjolnir
	await wait_rest(h, 1.0)
	mj.throw_hammer()
	check(h.state == &"throw", "бросок: поза броска")
	await wait(vm.tuning.throw_time + 0.03)
	check(not h.arm.weapon.visible and h.pivot.visible, "молот улетел — рука видна, в кулаке пусто")
	check(h.arm.grip_target < 0.5, "пальцы разжались")
	await wait(vm.tuning.empty_time)
	check(h.state == &"empty" or h.state == &"rest", "пустая рука опустилась (%s)" % h.state)
	if mj.projectile and is_instance_valid(mj.projectile):
		mj.projectile.start_return(true)
	await wait(0.05)
	check(h.state == &"recall", "возврат: рука тянется навстречу")
	check(h.arm.open_style > 0.5 and h.arm.grip_target < 0.5, "пальцы раскрыты для хвата")
	var t := 0.0
	while not mj.in_hand and t < 4.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await get_tree().process_frame
	check(mj.in_hand and h.state == &"catch", "ловля: толчок в руку")
	check(h.arm.weapon.visible and h.arm.grip > 0.9, "молот снова в кулаке")
	t = await wait_rest(h, 1.5)
	check(t >= 0.0, "после ловли — покой (%.2f с)" % t)
	# Идеальный хват: нажать «вернуть» на подлёте
	mj.throw_hammer()
	await wait(0.5)
	if mj.projectile and is_instance_valid(mj.projectile):
		mj.projectile.start_return(true)
	t = 0.0
	while not mj.in_hand and t < 4.0:
		if mj.projectile and is_instance_valid(mj.projectile) and mj.projectile.state == MjolnirProjectile.State.RETURN \
				and mj.projectile.global_position.distance_to(p.get_aim_origin()) < 3.0:
			mj.request_throw_or_recall()
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await get_tree().process_frame
	check(mj.perfect_ready and h.state == &"perfect_catch", "идеальный хват: своё движение")
	var w := h.arm.weapon
	await wait(vm.tuning.perfect_twirl_time * 0.4)
	check(absf(w.rotation_degrees.y - h.arm.weapon_rotation.y) > 30.0, "молот прокручивается в руке")
	await wait(vm.tuning.perfect_twirl_time)
	check(absf(w.rotation_degrees.y - h.arm.weapon_rotation.y) < 0.5, "после прокрута молот на месте")
	t = await wait_rest(h, 1.5)
	check(t >= 0.0, "после идеального хвата — покой (%.2f с)" % t)
	mj.perfect_ready = false

func _ranged() -> void:
	print("-- Ренж: выстрел, перезарядка, свитч")
	var h := vm.right
	var wh := p.weapons
	wh.equip(load("res://weapons/defs/pistol.tres") as WeaponDef, 1, false)
	wh.switch_to(WeaponHolder.RANGED, true)
	await wait(0.5)
	var f0 := Engine.get_physics_frames()
	var shots := [0]
	var cb := func(_it: WeaponItem) -> void: shots[0] += 1
	wh.gun.fired.connect(cb)
	wh.gun.try_fire()
	check(shots[0] == 1 and Engine.get_physics_frames() == f0, "выстрел в кадре нажатия")
	wh.gun.fired.disconnect(cb)
	check(h.state == &"fire", "выстрел: отдача в руке")
	await get_tree().process_frame
	var kick_pistol := h.sp_pos.length() + h.sp_vel.length() * 0.01
	var t := await wait_rest(h, 1.0)
	check(t >= 0.0, "после выстрела — покой (%.2f с)" % t)
	wh.equip(load("res://weapons/defs/shotgun.tres") as WeaponDef, 1, false)
	wh.switch_to(WeaponHolder.RANGED, true)
	await wait(0.5)
	wh.gun.try_fire()
	await get_tree().process_frame
	var kick_shotgun := h.sp_pos.length() + h.sp_vel.length() * 0.01
	check(kick_shotgun > kick_pistol * 1.3, "обрез отдаёт сильнее пистолета (%.3f > %.3f)" % [kick_shotgun, kick_pistol])
	await wait(0.6)
	wh.ranged.mag = 0
	wh.gun.start_reload()
	check(h.state == &"reload", "перезарядка: своё движение")
	await wait(wh.ranged.def.reload_time * 0.4)
	check(h.position.y < h.rest_pos.y - 0.05 and h.rotation_degrees.z > h.rest_rot.z + 20.0, "при перезарядке оружие опущено и наклонено")
	t = await wait_rest(h, wh.ranged.def.reload_time + 1.0)
	check(t >= 0.0 and not wh.gun.reloading, "после перезарядки — покой")
	wh.switch_to(WeaponHolder.MELEE)
	check(h.state == &"switch_down", "свитч: убрать вниз")
	await wait(wh.switch_time * 0.5 + 0.03)
	check(h.state == &"switch_up", "свитч: достать снизу")
	t = await wait_rest(h, wh.switch_time + 1.0)
	check(t >= 0.0 and h.rest_pos.is_equal_approx(wh.melee.def.view_rest_pos), "после свитча — покой мили-оружия")

func _general() -> void:
	print("-- Общее: бег, мышь, прыжок, приземление, рывок, удар-приземление")
	Input.action_press("move_forward")
	await wait(0.8)
	var bob_max := 0.0
	for i in 30:
		await get_tree().process_frame
		bob_max = maxf(bob_max, vm.bob_offset.length())
	check(bob_max > 0.01, "при беге руки покачиваются (%.3f м)" % bob_max)
	p.camera_fx.head_bob_enabled = false
	await wait(0.3)
	var bob_off := 0.0
	for i in 20:
		await get_tree().process_frame
		bob_off = maxf(bob_off, vm.bob_offset.length())
	check(bob_off < 0.001, "настройка «покачивание» выключена — без покачивания")
	p.camera_fx.head_bob_enabled = true
	Input.action_release("move_forward")
	await wait(0.6)
	p.rotation_target.y += 0.15
	await get_tree().process_frame
	await get_tree().process_frame
	check(vm._sway_pos.x > 0.005, "поворот камеры влево — руки отстают вправо")
	await wait(0.8)
	check(vm._sway_pos.length() < 0.003, "качание за мышью гаснет само")
	p.velocity.y = p.jump_velocity
	await wait(0.1)
	check(vm.last_event == &"jump", "прыжок: руки подбрасывает")
	await wait(1.2)
	p.global_position += Vector3(0, 5.0, 0)
	p.velocity = Vector3.ZERO
	await wait(0.1)
	var t := 0.0
	while not p.is_on_floor() and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await get_tree().process_frame
	await get_tree().process_frame
	var dip_small := absf(minf(vm._c_pos.y, 0.0))
	for i in 10:
		await get_tree().process_frame
		dip_small = maxf(dip_small, -vm._c_pos.y)
	check(vm.last_event == &"land" and dip_small > 0.01, "приземление с 5 м: руки приседают (%.3f м, %s)" % [dip_small, vm.last_event])
	await wait(1.0)
	p.global_position += Vector3(0, 8.0, 0)
	p.velocity = Vector3.ZERO
	await wait(0.1)
	p._start_slam()
	t = 0.0
	while not p.is_on_floor() and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	FX.reset_time()
	var dip_big := 0.0
	for i in 12:
		await get_tree().process_frame
		dip_big = maxf(dip_big, -vm._c_pos.y)
	check(vm.last_event == &"slam_land", "удар-приземление: своё событие")
	check(dip_big > dip_small, "после удара-приземления руки приседают сильнее (%.3f > %.3f)" % [dip_big, dip_small])
	await wait(1.0)
	p._start_dash(-p.global_transform.basis.z)
	await wait(0.03)
	check(vm.last_event == &"dash" and vm._hold_pos.z > 0.01, "рывок: руки отводятся назад")
	await wait(1.0)
	check(vm._hold_pos.length() < 0.01, "после рывка руки вернулись")
	check(vm.right.state == &"rest" and vm.left.state == &"rest", "в конце обе руки в покое")

func _finish() -> void:
	print("=== ИТОГ HANDS: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	Input.action_release("move_forward")
	get_tree().quit(0 if _fails.is_empty() else 1)
