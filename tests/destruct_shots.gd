extends Node
## Кадры разрушаемого для глаз: бочка и ящик до и после удара, обломки на полу, взрывная бочка и цепь,
## горящий ящик, мост деревни после удара-приземления.
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/destruct_shots.tscn -- <папка>

var out_dir := "user://destruct_shots"
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

func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().process_frame
		if game and is_instance_valid(game) and game.player:
			game.player.health = game.player.max_health

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot: ", name)

func spawn(path: String, pos: Vector3) -> Destructible:
	var d := (load(path) as PackedScene).instantiate() as Destructible
	game.room.add_child(d)
	d.global_position = pos
	d.rotation.y = randf() * TAU
	return d

func _run() -> void:
	Destructible.surprise_chance_override = 0.0
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_09.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.3)
	game = get_tree().current_scene as Game
	game.room.set_physics_process(false)
	await wait(1.2)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	for n in get_tree().get_nodes_in_group("props"):
		(n as Node).queue_free()
	var p := game.player
	p.global_position = Vector3(0, 0.1, 10)
	p.rotation_target = Vector2(-0.22, 0)
	await wait(0.4)

	# Бочки и ящики перед Тором
	var row: Array[Destructible] = []
	row.append(spawn("res://props/barrel.tscn", Vector3(-1.2, 0, 7)))
	row.append(spawn("res://props/crate.tscn", Vector3(0.3, 0, 6.8)))
	row.append(spawn("res://props/barrel_explosive.tscn", Vector3(1.8, 0, 7.2)))
	row.append(spawn("res://props/barrel.tscn", Vector3(3.2, 0, 7.6)))
	await wait(0.6)
	await shot("01_props")
	# Удар: бочка и ящик разлетаются
	row[0].take_hit(99.0, Vector3(-3, 3, -8), "melee_finisher")
	row[1].take_hit(99.0, Vector3(2, 3, -9), "melee_heavy")
	await wait(0.08)
	await shot("02_smash")
	await wait(0.5)
	await shot("03_debris")
	# Взрывная бочка и цепь
	await wait(0.4)
	row[2].take_hit(99.0, Vector3.ZERO, "ranged")
	await wait(0.1)
	await shot("04_explosion")
	await wait(1.0)
	# Горящий ящик
	var c := spawn("res://props/crate.tscn", Vector3(0, 0, 7))
	await wait(0.4)
	c.ignite()
	await wait(0.8)
	await shot("05_burning")
	await wait(2.5)
	# Мост деревни после удара-приземления
	var deck: Balcony = null
	for n in game.room.find_children("*", "StaticBody3D", true, false):
		if n is Balcony and (n as Balcony).slam_breakable:
			deck = n
	if deck:
		p.global_position = Vector3(1.5, 0.1, 6.5)
		p.velocity = Vector3.ZERO
		p.rotation_target = Vector2(0.2, 0.1)
		await wait(0.5)
		await shot("06_bridge")
		deck.break_apart(true)
		await wait(0.35)
		await shot("07_bridge_broken")
	Destructible.surprise_chance_override = -1.0
	get_tree().quit()
