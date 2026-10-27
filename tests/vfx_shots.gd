extends Node
## Кадры VFX-комплекта для глаз: попадание, ихор, удар-приземление, молнии, огонь, лёд, дым, Ярость,
## линии скорости, идеальный хват, комиксовые слова.
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/vfx_shots.tscn -- <папка>

var out_dir := "user://vfx_shots"
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

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot: ", name)

func ahead(d: float, h: float = 1.0, side: float = 0.0) -> Vector3:
	var p := game.player
	var f := -p.global_transform.basis.z
	f.y = 0
	f = f.normalized()
	return p.global_position + f * d + f.cross(Vector3.UP) * side + Vector3(0, h, 0)

func look(pitch: float) -> void:
	var p := game.player
	p.rotation_target.x = pitch
	await wait(0.15)

func dummy(scene: String, d: float, side: float = 0.0) -> Enemy:
	var e := (load(scene) as PackedScene).instantiate() as Enemy
	e.max_health = 5000.0
	game.add_child(e)
	e.global_position = Loot.floor_point(game.player, ahead(d, 0.0, side))
	e.health = 5000.0
	e.player = game.player
	e.look_at(game.player.global_position * Vector3(1, 0, 1) + Vector3(0, e.global_position.y, 0), Vector3.UP, true)
	e.set_physics_process(false)
	return e

func _run() -> void:
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.3)
	game = get_tree().current_scene as Game
	game.room.set_physics_process(false)
	await wait(1.2)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	game.room._spawn_queue.clear()
	var p := game.player
	p.max_health = 99999.0
	p.health = 99999.0
	await look(-0.08)

	# Попадание: вспышка, звёзды, ихор
	var g := dummy("res://enemies/grunt.tscn", 3.2)
	await wait(0.3)
	g.take_hit(30.0, Vector3.ZERO, "melee_finisher")
	await wait(0.03)
	await shot("01_hit")
	await wait(0.05)
	await shot("01b_hit_later")
	await wait(0.5)
	g.take_hit(30.0, Vector3.ZERO, "hammer")
	await wait(0.04)
	await shot("02_hit_hammer")
	await wait(0.4)
	# Пятна ихора на полу
	for i in 6:
		g.take_hit(30.0, Vector3.ZERO, "melee_finisher")
		await wait(0.05)
	await look(-0.6)
	await wait(0.3)
	await shot("03_splats")
	g.queue_free()
	await look(-0.35)

	# Удар-приземление с 12 м: волна, трещина
	var c := ahead(4.0, 0.0)
	FX.slam_impact(game, c, 6.0, 12.0)
	FX.ring(game, c, 6.0, Color(1.0, 0.85, 0.5, 0.9), 0.4)
	FX.sparks(game, c + Vector3(0, 0.2, 0), Color(0.55, 0.47, 0.4), 40, 10.0, 18.0, 0.14, 0.7)
	await wait(0.1)
	await shot("04_slam")
	await wait(1.0)
	await shot("04b_crack")
	await look(-0.08)

	# Молнии
	FX.lightning(game, ahead(3.0, 1.2, -3.0), ahead(9.0, 1.0, 3.0), 0.5)
	FX.lightning(game, ahead(7.0, 12.0, 1.0), ahead(7.0, 0.0, 1.0), 0.5, Color(0.85, 0.95, 1.0))
	await wait(0.06)
	await shot("05_lightning")
	await wait(0.6)

	# Огонь
	var fire := preload("res://weapons/fire_zone.gd").new()
	game.add_child(fire)
	fire.setup(Loot.floor_point(p, ahead(5.0, 0.0)), 2.5, 3.0, 0.0)
	await wait(0.6)
	await shot("06_fire")
	await wait(3.0)

	# Лёд
	FX.ice_hit(game, ahead(3.5, 0.0), 2.0)
	await look(-0.3)
	await wait(0.1)
	await shot("07_ice")
	await look(-0.08)
	await wait(2.0)

	# Дым взрыва
	Blast.detonate(game, ahead(6.0, 0.8), 3.0, 0.0)
	await wait(0.12)
	await shot("08_blast")
	await wait(0.2)
	await shot("08b_smoke")
	await wait(0.6)

	# Идеальный хват
	FX.perfect_catch(p.mjolnir.hand_point() + p.get_aim_forward() * 0.7)
	await wait(0.08)
	await shot("09_perfect_catch")
	await wait(0.5)

	# Линии скорости (рывок) и Ярость
	p.camera_fx.speed_lines_pulse()
	await wait(0.08)
	await shot("10_speed_lines")
	await wait(1.2)
	p.style.start_berserk()
	await wait(0.8)
	await shot("11_rage")
	p.camera_fx.speed_lines_pulse()
	await wait(0.08)
	await shot("11b_rage_speed")
	p.style.reset()
	await wait(1.5)

	# Комиксовые слова
	GameSettings.comic_enabled = true
	ComicFX.reset_state()
	ComicFX.pop("lightning", ahead(4.0, 1.6, -1.5), false)
	await wait(0.2)
	await shot("12_comic_lightning")
	await wait(0.6)
	ComicFX.reset_state()
	ComicFX.pop("blade", ahead(4.0, 1.6, 1.5), false)
	await wait(0.2)
	await shot("12b_comic_blade")
	await wait(0.6)
	ComicFX.reset_state()
	ComicFX.pop("slam", ahead(4.0, 1.0), true)
	await wait(0.25)
	await shot("13_comic_big")
	await wait(1.0)
	get_tree().quit()
