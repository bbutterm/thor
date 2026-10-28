extends Node
## Дальность обнаружения и гарантированное пробуждение волн (GDD 6).
## godot --headless --path . --fixed-fps 60 res://tests/awareness_test.tscn

var passes := 0
var failures: Array[String] = []
var game: Game
var room: Room
var player: Player

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func check(ok: bool, message: String) -> void:
	if ok:
		passes += 1
		print("  [OK] ", message)
	else:
		failures.append(message)
		print("  [FAIL] ", message)

func clear_enemies() -> void:
	for e in room.alive_enemies().duplicate():
		if is_instance_valid(e):
			e.queue_free()
	room._alive.clear()
	await frames(2)

## Через реальный путь волнового спавна; коллизии отключены только в этой
## проверке расстояний, чтобы границы короткого тестового зала не мешали.
func wave_enemy(kind: String, distance: float) -> Enemy:
	var marker := Marker3D.new()
	marker.set_meta("kind", kind)
	room.spawns.add_child(marker)
	marker.global_position = player.global_position + Vector3(distance, 0.0, 0.0)
	room._spawn_enemy(marker)
	marker.queue_free()
	var enemy := room._alive.back() as Enemy
	enemy.collision_layer = 0
	enemy.collision_mask = 0
	enemy.gravity = 0.0
	enemy.velocity = Vector3.ZERO
	enemy._set_state(Enemy.State.CHASE)
	return enemy

## Элита создаётся до add_child так же, как при появлении волны.
func elite_enemy(mod: EliteModifier, distance: float) -> Enemy:
	var enemy := room._make_enemy("grunt")
	Loot.make_elite(enemy, mod)
	enemy.position = room.to_local(player.global_position + Vector3(distance, 0.0, 0.0))
	room.add_child(enemy)
	room._register(enemy)
	enemy.collision_layer = 0
	enemy.collision_mask = 0
	enemy.gravity = 0.0
	enemy.velocity = Vector3.ZERO
	enemy._set_state(Enemy.State.CHASE)
	return enemy

func use_body(id: String) -> void:
	var body := load("res://run/bodies/%s.tres" % id) as BodyDef
	player.setup_body_traits(body)

func _run() -> void:
	print("=== AWARENESS TEST ===")
	Dialogue.in_run_scenes = false
	Run.start_run("hunter")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	for i in 180:
		await get_tree().physics_frame
		game = get_tree().current_scene as Game
		if game and game.room and game.player:
			break
	if game == null or game.room == null or game.player == null:
		check(false, "игра и зал загрузились")
		_finish()
		return
	game._exit_pending = true
	room = game.room
	# Проверяем собственно зачистку: экран награды из Game не должен
	# ставить тест на паузу после последнего искусственного противника.
	if room.cleared.is_connected(game._on_room_cleared):
		room.cleared.disconnect(game._on_room_cleared)
	room.set_physics_process(false)
	room._spawn_queue.clear()
	room.elite_chance = 0.0
	player = game.player
	room._player = player
	player.input_enabled = false
	player.set_physics_process(false)
	player.global_position = room.global_position + Vector3(0.0, 5.0, 0.0)
	await clear_enemies()

	# Один и тот же настоящий волновой спавн на 25 м: охотник не обнаружен,
	# а Берсерка слышно и враг действительно начинает двигаться к нему.
	use_body("hunter")
	var enemy := wave_enemy("grunt", 25.0)
	var start := enemy.global_position
	await frames(20)
	check(not enemy.is_alert_to_player() and enemy.global_position.distance_to(start) < 0.05,
		"на 25 м враг пока не обнаруживает обычное тело и стоит")
	await clear_enemies()
	use_body("berserker")
	enemy = wave_enemy("grunt", 25.0)
	start = enemy.global_position
	await frames(20)
	check(enemy.is_alert_to_player() and enemy.global_position.distance_to(start) > 0.2,
		"на 25 м враг замечает Берсерка и начинает движение")
	check(is_equal_approx(float(player.modify_stat(&"enemy_notice_radius_mult", 1.0)), 1.5),
		"множитель дальности берётся из пассивки Берсерка")

	# Другой живой Player не наследует обнаружение предыдущего.
	var alternate := (load("res://player/player.tscn") as PackedScene).instantiate() as Player
	alternate.process_mode = Node.PROCESS_MODE_DISABLED
	game.add_child(alternate)
	alternate.remove_from_group("player")
	alternate.global_position = player.global_position + Vector3(80.0, 0.0, 0.0)
	alternate.setup_body_traits(load("res://run/bodies/hunter.tres") as BodyDef)
	alternate.camera.current = false
	player.camera.make_current()
	enemy.player = alternate
	check(not enemy.is_alert_to_player(), "новый игрок не наследует чужое обнаружение")
	enemy.player = player
	check(not enemy.is_alert_to_player(), "возврат первого игрока тоже начинает обнаружение заново")
	alternate.queue_free()
	await clear_enemies()

	# Без игрока поиск не тикает. Полученное в этот момент событие пробуждения
	# передаётся вновь назначенному игроку, а не теряется.
	use_body("hunter")
	enemy = wave_enemy("grunt", 35.0)
	enemy.notice_fallback_time = 0.25
	player.remove_from_group("player")
	enemy.player = null
	await frames(30)
	check(enemy.player == null and not enemy.is_alert_to_player() and is_zero_approx(enemy._notice_wait),
		"без игрока отсчёт не идёт и враг не переходит в бой")
	enemy.alert_to_player()
	check(not enemy.is_alert_to_player(), "событие при отсутствии игрока не создаёт ложной цели")
	player.add_to_group("player")
	enemy.player = player
	check(enemy.is_alert_to_player(), "событие до назначения игрока будит при его появлении")
	await clear_enemies()

	# Далёкий волновой враг после тайм-аута всё равно идёт к игроку.
	enemy = wave_enemy("grunt", 35.0)
	start = enemy.global_position
	await frames(120)
	check(not enemy.is_alert_to_player() and enemy.global_position.distance_to(start) < 0.05,
		"до трёх секунд далёкий враг не знает позицию")
	await frames(80)
	check(enemy.is_alert_to_player() and enemy.global_position.distance_to(start) > 0.1,
		"через три секунды далёкий враг сам вступает в бой")

	# Последний враг с гарантированным поиском остаётся в учёте зала и
	# позволяет штатно закончить зал после смерти.
	room._waves.clear()
	room._spawn_queue.clear()
	room._advance_pending = false
	room._is_cleared = false
	check(room.alive_count() == 1 and not room._is_cleared, "последний живой враг не завершает зал")
	enemy.take_hit(9999.0, Vector3.ZERO, "ranged")
	check(room.alive_count() == 0 and room._is_cleared, "после последнего врага зал штатно зачищается")
	await clear_enemies()
	room._is_cleared = false

	# Реальный урон, блок щита, удар по броне и толчок немедленно пробуждают.
	enemy = wave_enemy("grunt", 35.0)
	enemy.notice_fallback_time = 30.0
	enemy.take_hit(1.0, Vector3.ZERO, "ranged")
	check(enemy.is_alert_to_player(), "получивший урон враг замечает игрока сразу")
	await clear_enemies()
	enemy = wave_enemy("shieldbearer", 35.0)
	enemy.notice_fallback_time = 30.0
	var toward := player.global_position - enemy.global_position
	enemy.rotation.y = atan2(toward.x, toward.z)
	var hp := enemy.health
	enemy.take_hit(1.0, Vector3.ZERO, "ranged")
	check(is_equal_approx(enemy.health, hp) and enemy.is_alert_to_player(),
		"щит блокирует урон, но его владелец всё равно замечает атаку")
	await clear_enemies()
	var armored := Loot.get_elite_modifier("armored")
	enemy = elite_enemy(armored, 35.0)
	enemy.notice_fallback_time = 30.0
	hp = enemy.health
	enemy.take_hit(1.0, Vector3.ZERO, "ranged")
	check(is_equal_approx(enemy.health, hp) and enemy.is_alert_to_player(),
		"поглощённый бронёй удар тоже будит элиту")
	await clear_enemies()
	enemy = wave_enemy("grunt", 35.0)
	enemy.notice_fallback_time = 30.0
	enemy.apply_knockback_only(Vector3(2.0, 0.0, 0.0))
	check(enemy.is_alert_to_player(), "толчок без урона будит врага")
	await clear_enemies()

	# Сильное оглушение будит и не сбрасывает память после завершения.
	enemy = wave_enemy("grunt", 35.0)
	enemy.notice_fallback_time = 30.0
	enemy.apply_stun(0.25, true)
	check(enemy.state == Enemy.State.STUNNED and enemy.is_alert_to_player(), "оглушение немедленно будит врага")
	await frames(30)
	check(enemy.state != Enemy.State.STUNNED and enemy.is_alert_to_player(), "после оглушения враг не забывает игрока")
	await clear_enemies()

	# Спящие особые не начинают ритуал, лазер или элитный призыв;
	# после пробуждения их штатные таймеры и телеграфы снова работают.
	enemy = wave_enemy("shaman", 35.0)
	enemy.notice_fallback_time = 30.0
	enemy._ritual_left = 1.0
	await frames(24)
	check(not enemy.is_alert_to_player() and is_equal_approx(enemy._ritual_left, 1.0),
		"шаман не готовит обряд, пока не заметил игрока")
	enemy.alert_to_player()
	await frames(12)
	check(enemy._ritual_left < 1.0, "после пробуждения отсчёт обряда продолжается")
	await clear_enemies()
	enemy = wave_enemy("merc", 35.0)
	enemy.notice_fallback_time = 30.0
	await frames(24)
	check(not enemy.is_alert_to_player() and not enemy._laser.visible and enemy._burst_left == 0,
		"наёмник не целится и не стреляет, пока не обнаружил игрока")
	enemy._begin_windup(false)
	await frames(2)
	check(enemy.is_alert_to_player() and enemy._laser.visible,
		"начатая атака будит наёмника и показывает штатный лазер")
	await clear_enemies()
	var mod := Loot.get_elite_modifier("summoner").duplicate(true) as EliteModifier
	mod.summon_interval = 0.3
	mod.summon_windup = 1.0
	enemy = elite_enemy(mod, 35.0)
	enemy.notice_fallback_time = 30.0
	enemy.set_physics_process(false)
	var summon := enemy.get_node("Elite_summoner")
	await frames(30)
	check(not enemy.is_alert_to_player() and float(summon.get("_casting")) < 0.0,
		"элитный призыватель не начинает ритуал до обнаружения")
	enemy.alert_to_player()
	await frames(12)
	check(float(summon.get("_casting")) >= 0.0, "призыватель начинает ритуал после пробуждения")
	await clear_enemies()

	# Боссы и призванный во время боя корм не получают задержку обнаружения.
	var boss := room._make_enemy("sven")
	room.add_child(boss)
	boss.player = player
	boss.set_physics_process(false)
	check(boss.is_alert_to_player(), "босс сразу знает игрока")
	boss.queue_free()
	var extra := room.spawn_extra("fodder", player.global_position + Vector3(35, 0, 0))
	check(extra != null and extra.is_alert_to_player(), "поднятый во время боя корм сразу активен")
	await clear_enemies()
	_finish()

func _finish() -> void:
	print("=== ИТОГ AWARENESS: %d OK, %d FAIL ===" % [passes, failures.size()])
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(1 if not failures.is_empty() else 0)
