extends Node
## Кадры рук от первого лица (блок Б2): ключевые позы мили, Мьёльнира, ренжа и общего движения,
## склеенные в листы 4×N (кадры уменьшены вдвое). Нужен дисплей (xvfb):
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/hands_shots.tscn -- <папка>
## Порядок кадров в листах печатается в лог («frame: …»).

var out_dir := "user://hands_shots"
var _sheet: Array[Image] = []
var _labels: PackedStringArray = []
var game: Game
var p: Player
## «quick» вторым аргументом — только несколько поз (подбор посадки рук)
var quick := false

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
	quick = args.size() > 1 and args[1] == "quick"
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()

func wait(sec: float) -> void:
	for i in maxi(1, int(ceil(sec * 60.0))):
		await get_tree().process_frame

func grab(label: String) -> void:
	# HUD, пузыри реплик и комикс-слова появляются в любой момент — прячем перед каждым кадром
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	_sheet.append(img)
	_labels.append(label)
	print("frame: ", label)

func flush(sheet_name: String) -> void:
	if _sheet.is_empty():
		return
	var w := _sheet[0].get_width()
	var h := _sheet[0].get_height()
	var cols := 4
	var rows := int(ceil(_sheet.size() / float(cols)))
	var out := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
	for i in _sheet.size():
		out.blit_rect(_sheet[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	out.save_png(out_dir.path_join(sheet_name + ".png"))
	print("sheet: ", sheet_name, " = ", ", ".join(_labels))
	_sheet.clear()
	_labels.clear()

func _run() -> void:
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_02.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.4)
	game = get_tree().current_scene as Game
	p = game.player
	await wait(1.4)
	for en in game.room.alive_enemies():
		en.set_physics_process(false)
		en.global_position += Vector3(0, 0, -30)
	# Без HUD и пузырей реплик: в кадре только руки и мир
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	p.rotation_target = Vector2(-0.05, p.rotation_target.y)
	var h := p.weapons
	var axe := h.axe
	h.equip(load("res://weapons/defs/axe.tres") as WeaponDef, 1, false)
	h.switch_to(WeaponHolder.MELEE, true)
	await wait(0.6)
	# --- Мили ---
	await grab("rest")
	if quick:
		await _quick()
		return
	for s in 3:
		axe.request_attack()
		# Середина удара: замах + половина активной фазы
		await wait(axe._windup_time() + axe._active_time() * 0.5)
		await grab("combo %d mid" % (s + 1))
		await wait(axe._active_time() * 0.5 + axe._recovery_time() * 0.3)
	await wait(0.8)
	axe.request_attack()
	await wait(axe._windup_time() * 0.6)
	await grab("combo 1 windup")
	await wait(0.8)
	axe.request_heavy()
	await wait(axe._windup_time() * 0.8)
	await grab("heavy charge")
	await wait(axe._windup_time() * 0.2 + axe._active_time() * 0.6)
	await grab("heavy release")
	await wait(1.0)
	h.equip(load("res://weapons/defs/sword.tres") as WeaponDef, 1, false)
	h.switch_to(WeaponHolder.MELEE, true)
	await wait(0.4)
	for s in axe.combo_count():
		axe.request_attack()
		await wait(axe._windup_time() + axe._active_time() * (0.5 if s == axe.combo_count() - 1 else 1.0))
		if s == axe.combo_count() - 1:
			await grab("finisher (sword)")
		await wait(axe._recovery_time() * 0.45)
	await wait(0.8)
	flush("melee")
	# --- Мьёльнир ---
	var mj := p.mjolnir
	mj.throw_hammer()
	await wait(0.02)
	await grab("throw release")
	await wait(0.4)
	await grab("hand empty")
	if mj.projectile and is_instance_valid(mj.projectile):
		mj.projectile.start_return(true)
	await wait(0.12)
	await grab("recall reach")
	await _wait_catch(false)
	await wait(0.05)
	await grab("catch")
	await wait(1.0)
	mj.throw_hammer()
	await wait(0.5)
	if mj.projectile and is_instance_valid(mj.projectile):
		mj.projectile.start_return(true)
	await _wait_catch(true)
	await wait(0.08)
	await grab("perfect catch")
	await wait(0.15)
	await grab("perfect catch +0.15")
	await wait(1.0)
	flush("mjolnir")
	# --- Ренж ---
	h.equip(load("res://weapons/defs/pistol.tres") as WeaponDef, 1, false)
	h.switch_to(WeaponHolder.RANGED, true)
	await wait(0.5)
	await grab("pistol rest")
	h.gun.try_fire()
	await wait(0.03)
	await grab("pistol fire")
	await wait(0.6)
	h.equip(load("res://weapons/defs/shotgun.tres") as WeaponDef, 1, false)
	h.switch_to(WeaponHolder.RANGED, true)
	await wait(0.5)
	h.gun.try_fire()
	await wait(0.03)
	await grab("shotgun fire")
	await wait(0.6)
	h.ranged.mag = 0
	h.gun.start_reload()
	var rt := h.ranged.def.reload_time
	await wait(rt * 0.35)
	await grab("reload low")
	await wait(rt * 0.75)
	h.switch_to(WeaponHolder.MELEE)
	await wait(h.switch_time * 0.45)
	await grab("switch down")
	await wait(h.switch_time * 0.4)
	await grab("switch up")
	await wait(0.6)
	flush("ranged")
	# --- Общее ---
	Input.action_press("move_forward")
	await wait(0.9)
	await grab("run bob")
	await wait(0.17)
	await grab("run bob +0.17")
	Input.action_release("move_forward")
	await wait(0.8)
	p.velocity = Vector3(0, p.jump_velocity, 0)
	await wait(0.12)
	await grab("jump lift")
	# Падение с высоты: приседание рук
	await wait(1.0)
	p.global_position += Vector3(0, 5.0, 0)
	p.velocity = Vector3.ZERO
	var t := 0.0
	while not p.is_on_floor() and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await wait(0.06)
	await grab("land dip (5 m)")
	await wait(1.0)
	p.global_position += Vector3(0, 6.0, 0)
	p.velocity = Vector3.ZERO
	await wait(0.1)
	p._start_slam()
	t = 0.0
	while not p.is_on_floor() and t < 3.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	await wait(0.1)
	await grab("slam land")
	await wait(1.0)
	p._start_dash(-p.global_transform.basis.z)
	await wait(0.06)
	await grab("dash")
	await wait(0.8)
	# Взгляд вниз и вверх: руки не залезают в камеру
	p.rotation_target.x = -1.2
	await wait(0.5)
	await grab("look down")
	p.rotation_target.x = 0.9
	await wait(0.5)
	await grab("look up")
	flush("general")
	FX.reset_time()
	get_tree().quit(0)

## Быстрый лист: покой, удары, тяжёлый, молот улетел, пистолет, взгляд вниз.
func _quick() -> void:
	var h := p.weapons
	var axe := h.axe
	for s in 3:
		axe.request_attack()
		await wait(axe._windup_time() + axe._active_time() * 0.5)
		await grab("combo %d mid" % (s + 1))
		await wait(axe._active_time() * 0.5 + axe._recovery_time() * 0.3)
	await wait(0.8)
	axe.request_heavy()
	await wait(axe._windup_time() * 0.8)
	await grab("heavy charge")
	await wait(1.0)
	p.mjolnir.throw_hammer()
	await wait(0.4)
	await grab("hand empty")
	p.mjolnir.force_return_instant()
	h.equip(load("res://weapons/defs/pistol.tres") as WeaponDef, 1, false)
	h.switch_to(WeaponHolder.RANGED, true)
	await wait(0.5)
	await grab("pistol rest")
	p.rotation_target.x = -1.2
	await wait(0.5)
	await grab("look down")
	flush("quick")
	FX.reset_time()
	get_tree().quit(0)

## Дождаться поимки молота; perfect — нажимать «вернуть» на подлёте (идеальный хват).
func _wait_catch(perfect: bool) -> void:
	var mj := p.mjolnir
	var t := 0.0
	while not mj.in_hand and t < 4.0:
		if perfect and mj.projectile and is_instance_valid(mj.projectile) \
				and mj.projectile.state == MjolnirProjectile.State.RETURN \
				and mj.projectile.global_position.distance_to(p.get_aim_origin()) < 3.0:
			mj.request_throw_or_recall()
		await get_tree().physics_frame
		t += 1.0 / 60.0
