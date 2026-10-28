extends Node3D
## Физический тест реальных ворот и пачки в сгенерированном room_04.
## Требует входы из патча o1_entry_final.patch и пересборку room_04.

const GATE_X := -5.5
const GATE_Z_MIN := 9.1 + 0.3 + 0.4275
const GATE_Z_MAX := 13.9 - 0.3 - 0.4275
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

func _run() -> void:
	Run.start_run("hunter")
	await _check_room(17, true)
	await _check_room(73, false)
	await _check_room(131, false)
	print("=== ИТОГ GATE ENTRY: %d OK, %d FAIL ===" % [passes, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _check_room(test_seed: int, check_player: bool) -> void:
	var room := (load("res://rooms/room_04.tscn") as PackedScene).instantiate() as Room
	var group := room.get_node("Spawns")
	var marker: Node3D
	for n in group.get_children():
		if str(n.get_meta("entry_mode", "")) == "gate":
			if marker != null:
				check(false, "в room_04 единственный маркер входа gate")
			marker = n as Node3D
		else:
			n.free()
	if marker == null:
		check(false, "room_04: сгенерирован маркер gate")
		room.free()
		return
	add_child(room)
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as Player
	player.position = Vector3(-3.5, 0.1, 11.5)
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.max_health = 9999.0
	player.health = 9999.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	if check_player:
		var inner := player.move_and_collide(Vector3(-3.6, 0, 0))
		var entered: bool = inner == null and player.position.x < -7.0
		var boundary := player.move_and_collide(Vector3(-3.0, 0, 0))
		var escaped: bool = player.position.x < -8.0
		var outer := player.move_and_collide(Vector3(4.0, 0, 0))
		var exited: bool = outer == null and player.position.x > -4.0
		check(entered and exited, "игрок свободно проходит ворота в обе стороны")
		check(boundary != null and not escaped, "за карманом непроницаемая западная граница")
		var wall := room.get_node("Geometry/WallW/Shape") as CollisionShape3D
		check(not wall.disabled and (wall.shape as BoxShape3D).size.y >= 24.0, "высокая внешняя граница остаётся включённой")
		var exit_door := room.get_node("Door/Shape") as CollisionShape3D
		check(not exit_door.disabled, "отдельная дверь выхода остаётся закрыта")
	player.position = Vector3(0, 0.1, 14.5)
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	seed(test_seed)
	room.start(player)
	var seen := {}
	var previous_count := 0
	var max_per_frame := 0
	var expected := int(marker.get_meta("count", 0))
	for frame in 720:
		await get_tree().physics_frame
		var now := room.alive_count()
		max_per_frame = maxi(max_per_frame, now - previous_count)
		previous_count = now
		for enemy in room.alive_enemies():
			var id := enemy.get_instance_id()
			var pos := room.to_local(enemy.global_position)
			if not seen.has(id):
				seen[id] = {"previous": pos, "entry": enemy._spawn_entry != null and enemy._spawn_entry.active,
					"invalid": enemy.has_meta("entry_failed"), "crossed": false}
			var row: Dictionary = seen[id]
			row.invalid = bool(row.invalid) or enemy.has_meta("entry_failed")
			var previous: Vector3 = row.previous
			if not row.crossed and previous.x < GATE_X and pos.x >= GATE_X:
				var fraction := (GATE_X - previous.x) / (pos.x - previous.x)
				var crossing: Vector3 = previous.lerp(pos, fraction)
				row.crossed = crossing.z > GATE_Z_MIN and crossing.z < GATE_Z_MAX and crossing.y < 0.4
			row.previous = pos
		var finished := seen.size() == expected and room.pending_spawns() == 0
		if finished:
			for row in seen.values():
				finished = finished and bool(row.crossed)
		if finished:
			break
	var crossed := 0
	var active := 0
	var invalid := 0
	for row in seen.values():
		crossed += int(row.crossed)
		active += int(row.entry)
		invalid += int(row.invalid)
	check(expected == 13 and seen.size() == expected and room.pending_spawns() == 0 and max_per_frame <= 1,
		"seed %d: вся пачка из 13 появилась не чаще одного за кадр и очередь пуста" % test_seed)
	check(active == expected and invalid == 0 and crossed == expected,
		"seed %d: %d/%d реально пересекли проём на полу, входов без пути: %d" % [test_seed, crossed, expected, invalid])
	room.queue_free()
	player.queue_free()
	await get_tree().process_frame
