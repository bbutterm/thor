extends Node
## Кадры телеграфов опасных зон и снарядов (GDD 12.6, ночь 29.10, Н2). Нужен дисплей (xvfb):
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/hazard_shots.tscn -- <папка>

var out_dir := "user://hazard_shots"
var game: Game
var p: Player
var room: Room

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
	for i in maxi(1, int(ceil(sec * 60.0))):
		await get_tree().process_frame
		if is_instance_valid(p):
			p.health = p.max_health

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot: ", name)

func _clear() -> void:
	for e in room.alive_enemies().duplicate():
		e.queue_free()
	room._alive.clear()
	for g in ["hazard_zones", "enemy_projectiles", "brew_puddles"]:
		for n in get_tree().get_nodes_in_group(g):
			n.queue_free()
	for n in room.get_children():
		if n is Blast:
			n.queue_free()
	_hide_talk()
	await wait(0.2)

## Окна реплик Одина/Хугина закрывают кадр — прячем.
func _hide_talk() -> void:
	for n in get_tree().root.find_children("*", "", true, false):
		if n is BarkBubble or n is DialogueBox:
			(n as CanvasItem).visible = false
	var hud: Node = game.get("hud")
	if hud and hud.get("_odin_panel"):
		(hud.get("_odin_panel") as Control).visible = false

func _zone(shape: HazardZone.Shape, pos: Vector3, facing: Vector3, size: float, color: Color, fill: float) -> HazardZone:
	var z := HazardZone.make(shape, pos, facing, size, 10.0, 0.0, color).place(room)
	z._t = z.telegraph * fill
	return z

func _freeze_projectiles() -> void:
	for n in get_tree().get_nodes_in_group("enemy_projectiles"):
		n.set_physics_process(false)

func _run() -> void:
	Dialogue.in_run_scenes = false
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.5)
	game = get_tree().current_scene as Game
	p = game.player
	room = game.room
	if game.tutorial:
		game.tutorial.active = false
	await wait(1.2)
	room.set_physics_process(false)
	room._spawn_queue.clear()
	var props := room.get_node_or_null("Props")
	if props:
		props.queue_free()
	await _clear()
	var base := room.global_position
	p.global_position = base + Vector3(0, 0.1, 9)
	p.rotation_target = Vector2(-0.45, 0.0)
	await wait(0.5)
	var front := p.global_position + Vector3(0, 0, -4.5)
	# 1. Три формы зон в разной стадии телеграфа: круг (проклятие), линия, конус
	_zone(HazardZone.Shape.CIRCLE, front + Vector3(-3.2, 0, -1.0), Vector3.FORWARD, 2.0, Color(0.7, 0.25, 1.0), 0.35)
	var line := _zone(HazardZone.Shape.LINE, front + Vector3(0.2, 0, 1.5), Vector3(0.05, 0, -1), 6.0, Color(1.0, 0.35, 0.15), 0.6)
	line.width = 1.4
	var cone := _zone(HazardZone.Shape.CONE, front + Vector3(3.0, 0, 1.0), Vector3(-0.35, 0, -1), 4.5, Color(1.0, 0.75, 0.15), 0.85)
	cone.half_angle_deg = 30.0
	_hide_talk()
	await wait(0.3)
	await shot("01_zones_telegraph")
	await _clear()
	# 2. Навесной снаряд метателя и граната наёмника: дуга и метки падения на полу
	var thrower := room.spawn_extra("thrower", base + Vector3(-4, 0.05, -4))
	var merc := room.spawn_extra("merc", base + Vector3(3, 0.05, -4))
	await wait(1.6)
	thrower.ranged.fire_lob()
	merc.ranged.throw_grenade()
	await wait(0.45)
	_freeze_projectiles()
	p.global_position = base + Vector3(0, 0.1, 11.3)
	thrower.set_physics_process(false)
	merc.set_physics_process(false)
	_hide_talk()
	await wait(0.2)
	await shot("02_lob_grenade_markers")
	await _clear()
	p.global_position = base + Vector3(0, 0.1, 9)
	# 3. Веер метателя, медленная сфера шамана, копьё воина — в полёте
	thrower = room.spawn_extra("thrower", base + Vector3(-4, 0.05, -4))
	var sh := room.spawn_extra("shaman", base + Vector3(-1.5, 0.05, -6))
	var g := room.spawn_extra("grunt", base + Vector3(3, 0.05, -4))
	await wait(1.6)
	thrower.ranged.fire_fan()
	sh.ranged.cast_orb()
	g.ranged.throw_spear()
	await wait(0.25)
	_freeze_projectiles()
	p.global_position = base + Vector3(0, 0.1, 11.3)
	for e in [thrower, sh, g]:
		e.set_physics_process(false)
	_hide_talk()
	await wait(0.2)
	await shot("03_fan_orb_spear")
	await _clear()
	p.global_position = base + Vector3(0, 0.1, 9)
	# 4. Круг проклятия ударил и оставил лужу; рядом — лужа браги Раздутого
	var curse := HazardZone.make(HazardZone.Shape.CIRCLE, front, Vector3.FORWARD, 2.4, 0.2, 0.0, Color(0.7, 0.25, 1.0))
	curse.puddle_time = 30.0
	curse.place(room)
	var b := room.spawn_extra("bloated", front + Vector3(3.5, 0, -1.0))
	await wait(0.4)
	b.take_hit(500.0, Vector3.ZERO, "ranged")
	await wait(0.8)
	_hide_talk()
	await shot("04_curse_puddle_brew")
	get_tree().quit(0)
