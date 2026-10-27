extends Node
## Кадры трейтов Мьёльнира (блок Б4): экран выбора (стихия, приём, связка — особая карточка), наковальня,
## объявление связки, HUD (иконки, полоска заряда), стихии в деле (след огня, аура молнии, заморозка
## и раскол, волна земли, вихрь ветра), огненный смерч, праща, журнал паузы.
## xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/trait_shots.tscn -- <папка>

var out_dir := "user://trait_shots"
var game: Game
var p: Player
var hand: MjolnirHand

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

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func wait(sec: float) -> void:
	await frames(int(ceil(sec * 60.0)))

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot: ", name)

func _t(id: StringName) -> MjolnirTrait:
	return Run.mjolnir_trait_def(id)

func _set(list: Array) -> void:
	Run.mjolnir_traits.clear()
	Run.mjolnir_trait_levels.clear()
	Run.mjolnir_traits_changed.emit(Run.mjolnir_traits)
	for id in list:
		Run.add_mjolnir_trait(_t(id))

func _clear() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()

func _dummy(side: float, fwd: float, physics: bool = false) -> Enemy:
	var e := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	e.max_health = 2000
	e.move_speed = 0.0
	e.attack_range = 0.0
	game.add_child(e)
	var fw := -p.global_transform.basis.z
	fw.y = 0
	fw = fw.normalized()
	var right := fw.cross(Vector3.UP)
	e.global_position = p.global_position + fw * fwd + right * side
	e.global_position.y = p.global_position.y - 0.1
	e.look_at(p.global_position, Vector3.UP, true)
	e.set_physics_process(physics)
	e.health = e.max_health
	return e

func _home(pitch: float = -0.12) -> void:
	if not hand.in_hand:
		hand.force_return_instant()
	p.global_position = Vector3(-3, 0.1, -4)
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2(pitch, 0.0)
	p.rotation.y = 0.0
	p.head.rotation.x = pitch
	p.health = p.max_health

func _slam() -> void:
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await wait(0.35)
	Input.action_press("slam")
	await frames(2)
	Input.action_release("slam")
	for i in 90:
		await get_tree().physics_frame
		if p.is_on_floor():
			break

func _run() -> void:
	Run.start_run("berserker")
	Run.room_order.assign([Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(2.0)
	game = get_tree().current_scene as Game
	p = game.player
	hand = p.mjolnir
	game.room.set_physics_process(false)
	game.room._spawn_queue.clear()
	_clear()
	game.trait_pick.picked.disconnect(game._on_trait_picked)
	for u in Save.all_unlocks:
		if u.kind == "trait":
			Save.data.unlocks[u.id] = 0
	_home()
	await wait(0.5)

	# Выбор после мини-босса: связка — особая карточка, приём, повышение стихии
	_set([&"fire"])
	var tp := game.trait_pick
	var c1: Array[MjolnirTrait] = [_t(&"storm"), _t(&"sling"), _t(&"fire")]
	tp.open(c1)
	await wait(0.5)
	await shot("01_pick_miniboss_combo")
	tp.visible = false
	get_tree().paused = false
	# Наковальня Эйтри: только стихии
	_set([])
	var c2: Array[MjolnirTrait] = [_t(&"ice"), _t(&"lightning"), _t(&"wind")]
	tp.open(c2, tr("НАКОВАЛЬНЯ ЭЙТРИ — СТИХИЯ МОЛОТА"))
	await wait(0.5)
	await shot("02_pick_anvil")
	tp.visible = false
	get_tree().paused = false
	await wait(0.2)

	# Связка сложилась: плашка «СВЯЗКА!», слово и реплика Одина
	_set([&"fire"])
	Run.add_mjolnir_trait(_t(&"storm"))
	await wait(0.45)
	await shot("03_combo_announce")
	await wait(3.2)

	# HUD: молния II + заряд, полоска заряда, рука отведена назад
	_set([&"lightning", &"lightning", &"charge"])
	_home()
	await wait(0.3)
	hand.hold_override = true
	hand.begin_hold()
	await wait(1.0)
	await shot("04_hud_charge")
	hand.hold_override = false
	await wait(1.5)
	if not hand.in_hand:
		hand.request_throw_or_recall()
	await wait(1.0)

	# Огонь ур. 2: след огня и горящие враги
	_set([&"fire", &"fire"])
	_home(-0.1)
	_dummy(0.4, 5)
	_dummy(-0.6, 8)
	_dummy(1.2, 10)
	await wait(0.4)
	hand.throw_hammer()
	await wait(0.45)
	await shot("05_fire_trail_burn")
	await wait(1.0)
	hand.request_throw_or_recall()
	await wait(1.2)
	_clear()

	# Молния ур. 3: Громоотвод — молот в полу среди толпы
	_set([&"lightning", &"lightning", &"lightning"])
	_home(-atan2(1.6, 9.0))
	_dummy(1.8, 9.5)
	_dummy(-1.8, 9.0)
	_dummy(0.5, 11.0)
	await wait(0.4)
	hand.throw_hammer()
	for i in 90:
		await get_tree().physics_frame
		if hand.projectile and is_instance_valid(hand.projectile) and hand.projectile.is_stuck():
			break
	await wait(0.17)
	await shot("06_lightning_rod_aura")
	await wait(0.4)
	hand.request_throw_or_recall()
	await wait(1.2)
	_clear()

	# Лёд: заморозка и раскол ударом-приземлением
	_set([&"ice"])
	_home(-0.35)
	var el := hand.element_handler()
	var a := _dummy(1.2, 2.6)
	var b := _dummy(-1.4, 3.0)
	var c := _dummy(0.2, 5.6)
	await wait(0.3)
	for e in [a, b]:
		for k in 3:
			el.apply_element(e, 1.0, e.global_position, null)
	el.apply_element(c, 1.0, c.global_position, null)
	await wait(0.35)
	await shot("07_ice_frozen")
	await _slam()
	await frames(3)
	await shot("08_ice_shatter")
	await wait(1.0)
	_clear()

	# Земля: прибитые и вторая волна
	_set([&"earth"])
	_home(-0.35)
	el = hand.element_handler()
	for e in [_dummy(1.2, 2.5), _dummy(-1.2, 3.0), _dummy(0.0, 5.5)]:
		el.apply_element(e, 1.0, e.global_position, null)
	await wait(0.3)
	await _slam()
	await wait(0.16)
	await shot("09_earth_wave")
	await wait(1.0)
	_clear()

	# Ветер: вихрь удара-приземления сносит толпу
	_set([&"wind"])
	_home(-0.25)
	for e in [_dummy(1.5, 2.5, true), _dummy(-1.5, 2.8, true), _dummy(0.3, 3.6, true)]:
		e.health = e.max_health
	await wait(0.5)
	await _slam()
	await wait(0.12)
	await shot("10_wind_gust")
	await wait(1.0)
	_clear()

	# Связка «Огненный смерч»: Огонь + Буря
	_set([&"fire", &"storm"])
	await wait(3.5)
	_home(-0.15)
	_dummy(1.6, 6.5)
	_dummy(-1.2, 7.5)
	_dummy(0.6, 9.0)
	await wait(0.3)
	hand.hold_override = true
	hand.throw_hammer()
	await wait(1.1)
	await shot("11_fire_tornado")
	hand.hold_override = false
	await wait(1.5)
	_clear()

	# Праща: молот крутится вокруг Тора
	_set([&"sling"])
	_home(-0.2)
	_dummy(2.0, 1.2)
	_dummy(-1.8, 1.6)
	await wait(0.3)
	hand.hold_override = true
	hand.begin_hold()
	await wait(0.62)
	await shot("12_sling_spin")
	hand.hold_override = false
	await wait(1.5)
	if not hand.in_hand:
		hand.request_throw_or_recall()
	await wait(1.0)
	_clear()

	# Журнал паузы: стихия по уровням, приём, связка
	_set([&"lightning", &"lightning", &"lightning", &"magnet"])
	await wait(3.5)
	game.pause_menu.toggle()
	await wait(0.4)
	await shot("13_pause_journal")
	game.pause_menu.toggle()
	get_tree().paused = false
	await wait(0.2)
	print("trait shots done: ", out_dir)
	get_tree().quit(0)
