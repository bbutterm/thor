extends Node
## Ограничение толпы не теряет очередь и не меняет арены с max_alive = 0.

var failures := 0

func check(ok: bool, message: String) -> void:
	print("[%s] %s" % ["OK" if ok else "FAIL", message])
	if not ok:
		failures += 1

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var room := Room.new()
	room.max_alive = 2
	room.chest_chance = 0.0
	var spawns := Node3D.new()
	spawns.name = "Spawns"
	room.add_child(spawns)
	var marker := Marker3D.new()
	marker.set_meta("kind", "shaman")
	marker.position = Vector3(5.0, 0.05, 0.0)
	spawns.add_child(marker)
	var pack := Marker3D.new()
	pack.set_meta("kind", "fodder")
	pack.set_meta("wave", 0)
	pack.set_meta("count", 4)
	pack.position.y = 0.05
	spawns.add_child(pack)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50.0, 1.0, 50.0)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.collision_layer = 1
	floor_body.add_child(floor_shape)
	room.add_child(floor_body)
	add_child(room)
	room.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	room.start(null)
	check(room._wave_size == 5 and room.pending_spawns() == 5, "пачка полностью попала в очередь")
	room._physics_process(0.2)
	check(room.alive_count() == 2 and room.pending_spawns() == 3, "очередь останавливается на лимите")
	room._physics_process(0.2)
	check(room.alive_count() == 2 and room.pending_spawns() == 3 and not room._is_cleared, "ожидание слота не теряет волну и не очищает зал")
	check(room.spawn_extra("fodder", Vector3.ZERO) == null, "дополнительный призыв не превышает лимит")
	var shaman: Enemy = room.alive_enemies().filter(func(e: Enemy) -> bool: return e.kind == Enemy.Kind.SHAMAN)[0]
	var summoned := shaman.summon_around("fodder", 3, 300)
	check(summoned == 0 and room.alive_count() == 2 and room.pending_spawns() == 3, "призыватель не превышает лимит и не теряет очередь")
	var defeated: Enemy = room.alive_enemies().filter(func(e: Enemy) -> bool: return e.kind == Enemy.Kind.FODDER)[0]
	defeated.take_hit(9999.0, Vector3.ZERO, "test")
	check(room.alive_count() == 1, "смерть освобождает слот")
	summoned = shaman.summon_around("fodder", 3, 300)
	check(summoned == 1 and room.alive_count() == 2 and room.pending_spawns() == 3, "призыв занимает только доступный слот")
	defeated = room.alive_enemies().filter(func(e: Enemy) -> bool: return e.kind == Enemy.Kind.FODDER)[0]
	defeated.take_hit(9999.0, Vector3.ZERO, "test")
	room._physics_process(0.2)
	check(room.alive_count() == 2 and room.pending_spawns() == 2, "после смерти очередь продолжает появление")
	room.max_alive = 0
	room._physics_process(0.2)
	check(room.alive_count() == 4 and room.pending_spawns() == 0, "нулевой лимит оставляет поведение ручных арен без изменений")
	room.queue_free()
	await get_tree().process_frame
	print("=== ИТОГ HORDE WAVE: %d FAIL ===" % failures)
	get_tree().quit(0 if failures == 0 else 1)
