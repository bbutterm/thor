extends Node3D
## Физический вход пачки: проход, край и прыжок с балкона. Только изолированный user://.

var failures := 0
var passes := 0

func check(ok: bool, what: String) -> void:
	print("[%s] %s" % ["OK" if ok else "FAIL", what])
	if ok:
		passes += 1
	else:
		failures += 1

func _ready() -> void:
	_run.call_deferred()

func _box(parent: Node, label: String, center: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.name = label
	b.collision_layer = 1
	b.position = center
	var c := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	c.shape = s
	b.add_child(c)
	parent.add_child(b)

func _new_fodder(parent: Node, position: Vector3) -> Enemy:
	var e := (load("res://enemies/fodder.tscn") as PackedScene).instantiate() as Enemy
	e.position = position
	parent.add_child(e)
	return e

func _run() -> void:
	Run.start_run("hunter")
	var args := OS.get_cmdline_user_args()
	var shift := int(args[0]) if not args.is_empty() and args[0].is_valid_int() else 0
	await _check_gate()
	await _check_room("res://rooms/room_01.tscn", "edge", 10, Vector3(0, 0.05, 6), 11 + shift)
	await _check_room("res://rooms/room_05.tscn", "balcony", 14, Vector3(2, 0.05, 3), 23 + shift)
	print("=== ИТОГ HORDE ENTRY: %d OK, %d FAIL ===" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _check_gate() -> void:
	var fixture := Node3D.new()
	add_child(fixture)
	_box(fixture, "Floor", Vector3(0, -0.5, 0), Vector3(30, 1, 30))
	_box(fixture, "WallA", Vector3(0, 1.5, -5), Vector3(0.5, 3, 8))
	_box(fixture, "WallB", Vector3(0, 1.5, 5), Vector3(0.5, 3, 8))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var actor := _new_fodder(fixture, Vector3(-4, 0.05, 0))
	var open: bool = actor.begin_spawn_entry("gate", Vector3(4, 0.05, 0))
	var crossed := false
	for i in 240:
		await get_tree().physics_frame
		crossed = crossed or actor.global_position.x > 0.8
		if not actor._spawn_entry.active:
			break
	check(open and crossed and actor.is_on_floor() and absf(actor.global_position.x - 4.0) < 0.4, "вход через открытый проём реально проходит стену")
	actor.queue_free()
	await get_tree().physics_frame
	actor = _new_fodder(fixture, Vector3(-4, 0.05, 5))
	check(not actor.begin_spawn_entry("gate", Vector3(4, 0.05, 5)), "вход через закрытую стену отклоняется")
	actor.queue_free()
	fixture.queue_free()
	await get_tree().physics_frame

func _check_room(path: String, mode: String, expected: int, player_position: Vector3, test_seed: int) -> void:
	var room := (load(path) as PackedScene).instantiate() as Room
	var group := room.get_node("Spawns")
	var marker: Node3D
	for n in group.get_children():
		if str(n.get_meta("entry_mode", "")) == mode:
			marker = n as Node3D
		else:
			n.free()
	if marker == null:
		check(false, "%s: маркер %s существует" % [path.get_file(), mode])
		room.free()
		return
	add_child(room)
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as Player
	player.position = player_position
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.max_health = 9999.0
	player.health = 9999.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	seed(test_seed)
	room.start(player)
	var seen := {}
	var prev_alive := 0
	var max_per_frame := 0
	for i in 600:
		await get_tree().physics_frame
		var now := room.alive_count()
		max_per_frame = maxi(max_per_frame, now - prev_alive)
		prev_alive = now
		for enemy in room.alive_enemies():
			var id := enemy.get_instance_id()
			if not seen.has(id):
				seen[id] = {"enemy": enemy, "start": enemy.global_position, "active": enemy._spawn_entry != null and enemy._spawn_entry.active, "invalid": false, "air": false, "landed": false, "complete": false, "near": false, "peak": enemy.global_position.y}
			var row: Dictionary = seen[id]
			row.peak = maxf(row.peak, enemy.global_position.y)
			row.invalid = row.invalid or enemy.has_meta("entry_failed")
			if enemy._spawn_entry != null:
				row.air = row.air or (enemy._spawn_entry.was_airborne and enemy.global_position.y > 2.25)
				row.landed = row.landed or (row.air and enemy.is_on_floor() and enemy.global_position.y < 0.25)
				if mode == "edge" and row.active and not enemy._spawn_entry.active and enemy.global_position.z - row.start.z > 2.5:
					row.complete = true
			row.near = row.near or (mode == "balcony" and row.landed and enemy.global_position.distance_to(player.global_position) < 2.0)
	var invalid := 0
	var complete := 0
	var near := 0
	for row in seen.values():
		if mode == "balcony" and not row.landed:
			var e: Enemy = row.enemy
			print("ENTRY DETAIL pos=", e.global_position, " state=", e.state, " alive=", not e.is_dead, " floor=", e.is_on_floor(), " active=", e._spawn_entry.active, " was_air=", e._spawn_entry.was_airborne, " peak=", row.peak, " invalid=", row.invalid)
		invalid += int(row.invalid)
		complete += int(row.landed if mode == "balcony" else row.complete)
		near += int(row.near)
	check(seen.size() == expected and invalid == 0 and room.pending_spawns() == 0 and max_per_frame <= 1,
		"%s: %d врагов вышли по одному без потери очереди и неверных путей" % [path.get_file(), expected])
	check(complete == expected, "%s: вся пачка прошла физический путь (%d/%d)" % [path.get_file(), complete, expected])
	if mode == "balcony":
		# Освобождаем проход: давка сама по себе не означает непроходимую геометрию.
		for row in seen.values():
			if row.near and is_instance_valid(row.enemy):
				room._alive.erase(row.enemy)
				row.enemy.queue_free()
		await get_tree().physics_frame
		for i in 240:
			await get_tree().physics_frame
			for row in seen.values():
				if not row.near and is_instance_valid(row.enemy):
					row.near = row.enemy.global_position.distance_to(player.global_position) < 2.0
		near = 0
		for row in seen.values(): near += int(row.near)
		check(near == expected, "после прыжка каждый может дойти до игрока (%d/%d)" % [near, expected])
		for enemy in room.alive_enemies().duplicate(): enemy.queue_free()
		room._alive.clear()
		await get_tree().physics_frame
		room._is_cleared = false
		marker.set_meta("spread_axes", Vector2.ZERO)
		room._spawn_enemy(marker)
		var hit_enemy: Enemy = room.alive_enemies().back()
		for i in 8: await get_tree().physics_frame
		var active: bool = hit_enemy._spawn_entry != null and hit_enemy._spawn_entry.active
		hit_enemy.take_hit(1.0, Vector3(5, 0, 0), "test")
		await get_tree().physics_frame
		check(active and not hit_enemy._spawn_entry.active and hit_enemy.velocity.x > 0, "удар прерывает прыжок и сохраняет толчок")
	room.queue_free()
	player.queue_free()
	await get_tree().process_frame
