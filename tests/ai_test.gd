extends Node
## Проверка ИИ врагов: игрок стоит (бессмертный), враги должны дойти, замахнуться, ударить; метатели — стрелять.
## godot --headless --path . --fixed-fps 60 res://tests/ai_test.tscn

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var r := Node.new()
		r.set_script(get_script())
		r.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(r)
		return
	_run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _run() -> void:
	var fails := 0
	for room in Run.ROOM_SCENES + [Run.BOSS_SCENE]:
		Run.start_run("berserker")
		Run.room_order.assign([room, Run.BOSS_SCENE])
		get_tree().change_scene_to_file("res://scenes/game.tscn")
		await frames(20)
		var g := get_tree().current_scene as Game
		var p := g.player
		var hits := [0]
		var dmg := [0.0]
		p.hurt.connect(func(a: float) -> void:
			hits[0] += 1
			dmg[0] += a)
		var projectiles := 0
		for i in 60 * 15:
			await get_tree().physics_frame
			p.health = p.max_health
			if i % 30 == 0:
				for n in g.room.get_children():
					if n.is_in_group("reflectable"):
						projectiles += 1
		var stuck := 0
		for e in g.room.alive_enemies():
			if e.kind != Enemy.Kind.THROWER and e.global_position.distance_to(p.global_position) > 6.0:
				stuck += 1
		var ok: bool = hits[0] > 0
		print("[%s] %s: попаданий по игроку %d (урон %.0f за 15 с), снарядов в воздухе (сэмплы) %d, грунтов далеко от игрока %d" % ["OK" if ok else "FAIL", room.get_file(), hits[0], dmg[0], projectiles, stuck])
		if not ok:
			fails += 1
	FX.reset_time()
	get_tree().quit(1 if fails > 0 else 0)
