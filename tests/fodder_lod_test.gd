extends Node
## Дальний корм: физика, погони и полноценные фазы удара при редком обновлении позы/ИИ.
## godot --headless --path . --fixed-fps 60 res://tests/fodder_lod_test.tscn

var _passes := 0
var _fails: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		_passes += 1
		print("  [OK] ", label)
	else:
		_fails.append(label)
		print("  [FAIL] ", label)

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _run() -> void:
	print("=== FODDER LOD TEST ===")
	Run.start_run("berserker")
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var ground := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	collider.shape = box
	ground.add_child(collider)
	ground.position.y = -0.5
	world.add_child(ground)
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as Player
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	var room := Room.new()
	var spawns := Node3D.new()
	spawns.name = "Spawns"
	room.add_child(spawns)
	world.add_child(room)
	room._player = player
	var e := room.spawn_extra("fodder", Vector3(28, 0.05, 0))
	check(e != null and e.kind == Enemy.Kind.FODDER and room.alive_count() == 1, "настоящий корм зарегистрирован в зале")
	if e == null:
		_finish(world)
		return
	e._set_state(Enemy.State.CHASE)
	e._cooldown = 0.0
	e.alert_to_player()
	await frames(5)
	check(e._fodder_lod_active() and e._fodder_anim_lod
		and e._humanoid.anim.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,
		"за 20 м анимация корма переходит на ручное редкое обновление")
	var start := e.global_position
	var anim_pos := e._humanoid.anim.current_animation_position
	await frames(18)
	check(e.global_position.distance_to(start) > 0.4, "дальний корм продолжает двигаться каждый физический кадр")
	check(not is_equal_approx(e._humanoid.anim.current_animation_position, anim_pos), "дальняя анимация продолжает проигрываться")
	check(room.alive_count() == 1 and not room._is_cleared, "живой дальний враг удерживает зачистку")

	# В отдельный неподходящий кадр решение кешируется; в следующий подходящий пересчитывается.
	e.set_physics_process(false)
	e._fodder_lod_move = Vector3.RIGHT
	e._fodder_lod_move_valid = true
	player.global_position = e.global_position + Vector3(0, 0, 25)
	for i in 4:
		if Engine.get_physics_frames() % e.fodder_lod_frames != e.get_instance_id() % e.fodder_lod_frames:
			break
		await get_tree().physics_frame
	var held := e._think_chase_lod(1.0 / 60.0)
	check(held.is_equal_approx(Vector3.RIGHT), "вне выбранного кадра направление остаётся кешированным")
	for i in 4:
		if Engine.get_physics_frames() % e.fodder_lod_frames == e.get_instance_id() % e.fodder_lod_frames:
			break
		await get_tree().physics_frame
	var refreshed := e._think_chase_lod(1.0 / 60.0)
	check(not refreshed.is_equal_approx(Vector3.RIGHT), "в выбранный кадр направление пересчитывается")
	player.global_position = e.global_position + Vector3(20.1, 0, 0)
	check(e._fodder_lod_active(), "20,1 м — редкий режим")
	player.global_position = e.global_position + Vector3(19.9, 0, 0)
	check(not e._fodder_lod_active(), "19,9 м — обычный режим")
	# Запас для инерции: в точке 19,9 м враг физически может снова выйти за порог.
	player.global_position = e.global_position + Vector3(19.0, 0, 0)
	e.set_physics_process(true)
	await frames(3)
	check(not e._fodder_anim_lod and e._humanoid.anim.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,
		"возврат ближе 20 м сразу восстанавливает анимацию")
	player.global_position = e.global_position + Vector3(28, 0, 0)
	await frames(4)
	check(e._fodder_anim_lod, "после телепорта вдаль снова работает редкая анимация")

	# Даже при телепортации игрока далеко запущенный замах не должен потеряться.
	e._begin_windup(false)
	var windup := e.windup_time
	await frames(3)
	check(e.state == Enemy.State.WINDUP and not e._fodder_anim_lod, "замах всегда идёт на полной частоте")
	await frames(ceili(windup * 60.0) + 3)
	check(e.state != Enemy.State.WINDUP and e._cooldown > 0.0, "после телепорта замах завершается и включает восстановление")

	# Проверяем реальный удар вблизи, без изменений урона/длительности замаха.
	e._set_state(Enemy.State.CHASE)
	e._cooldown = 0.0
	e.rotation.y = PI * 0.5
	player.global_position = e.global_position + Vector3(1.0, 0.0, 0.0)
	player._invuln_left = 0.0
	var hp := player.health
	var started := false
	var elapsed := 0
	for i in 100:
		await get_tree().physics_frame
		if e.state == Enemy.State.WINDUP:
			started = true
		if started:
			elapsed += 1
		if player.health < hp:
			break
	check(started and player.health < hp, "после приближения корм действительно попадает")
	check(elapsed >= floori(windup * 60.0) - 1, "замах не сокращён после выхода из LOD")

	# Смерть вдали не должна оставлять AnimationPlayer в ручном режиме у тела.
	e._set_state(Enemy.State.CHASE)
	player.global_position = e.global_position + Vector3(28, 0, 0)
	await frames(4)
	var ap := e._humanoid.anim
	var visual := e._visual
	check(e._fodder_anim_lod, "дальний режим активен перед смертью")
	e.take_hit(9999, Vector3.ZERO, "test")
	check(not e._fodder_anim_lod and ap.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,
		"анимация смерти возвращена в обычный режим")
	check(visual.get_parent() is RigidBody3D, "тело передано физическому трупу")
	check(room.alive_count() == 0 and room._is_cleared, "смерть дальнего корма завершает зачистку")
	_finish(world)

func _finish(world: Node) -> void:
	print("=== ИТОГ FODDER LOD: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	world.queue_free()
	get_tree().quit(0 if _fails.is_empty() else 1)
