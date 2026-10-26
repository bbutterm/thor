extends Node
## Кадры оружия от первого лица (нужен дисплей; в CI — xvfb-run): каждое оружие в покое и в действии
## (замах / выстрел / перезарядка), склеенные в листы по 4×3. Плюс оружие на полу, сундук и элита.
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 640x360 res://tests/weapon_shots.tscn -- <папка>

var out_dir := "user://weapon_shots"
var _sheet: Array[Image] = []

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

func grab(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	_sheet.append(img)
	print("frame: ", label)

func flush(name: String) -> void:
	if _sheet.is_empty():
		return
	var w := _sheet[0].get_width()
	var h := _sheet[0].get_height()
	var cols := 4
	var rows := int(ceil(_sheet.size() / float(cols)))
	var out := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
	for i in _sheet.size():
		out.blit_rect(_sheet[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	out.save_png(out_dir.path_join(name + ".png"))
	print("sheet: ", name)
	_sheet.clear()

func _run() -> void:
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_02.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.4)
	var game := get_tree().current_scene as Game
	var p := game.player
	var h := p.weapons
	await wait(1.4)
	for en in game.room.alive_enemies():
		en.set_physics_process(false)
		en.global_position += Vector3(0, 0, -30)
	p.rotation_target = Vector2(-0.05, p.rotation_target.y)
	var melee: Array[WeaponDef] = []
	var ranged: Array[WeaponDef] = []
	for d in Loot.all_defs():
		(ranged if d.is_ranged() else melee).append(d)
	for d in melee:
		h.equip(d, 1, false)
		h.switch_to(WeaponHolder.MELEE, true)
		await wait(0.3)
		await grab(d.id + " rest")
		h.axe.request_attack()
		await wait(0.07 / d.attack_speed + 0.04)
		await grab(d.id + " swing")
		await wait(0.8)
	flush("melee_1")
	for d in ranged:
		h.equip(d, 1, false)
		h.switch_to(WeaponHolder.RANGED, true)
		await wait(0.3)
		await grab(d.id + " rest")
		h.gun.try_fire()
		await get_tree().process_frame
		await grab(d.id + " fire")
		await wait(0.4)
		h.ranged.mag = 0
		h.gun.start_reload()
		await wait(d.reload_time * 0.4)
		await grab(d.id + " reload")
		await wait(d.reload_time)
	flush("ranged_1")
	# Свитч
	h.switch_to(WeaponHolder.MELEE)
	await wait(0.08)
	await grab("switch mid")
	await wait(0.3)
	# Оружие на полу, сундук, элита
	var fwd := -p.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := p.global_transform.basis.x
	var x := -1.5
	for d in [Loot.get_def("sword"), Loot.get_def("pistol"), Loot.get_def("crossbow"), Loot.get_def("club")]:
		Loot.spawn_weapon(game, p.global_position + fwd * 3.0 + right * x, WeaponItem.create(d))
		x += 1.0
	Loot.spawn_chest(game, p.global_position + fwd * 5.5 + right * 2.0)
	Loot.spawn_ammo(game, p.global_position + fwd * 2.5 + right * -2.2)
	var e := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	Loot.make_elite(e)
	game.add_child(e)
	e.global_position = p.global_position + fwd * 6.0 + right * -1.5
	e.set_physics_process(false)
	await wait(1.2)
	await grab("floor")
	p.rotation_target.x = -0.3
	await wait(0.2)
	await grab("floor down")
	h.interact()
	await wait(0.2)
	await grab("after pickup")
	flush("world")
	FX.reset_time()
	get_tree().quit(0)
