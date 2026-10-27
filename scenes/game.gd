extends Node3D
class_name Game
## Сцена забега: грузит залы по порядку из Run, связывает игрока, HUD, выбор рун, паузу и финальный экран.

@onready var level: Node3D = $Level
@onready var player: Player = $Player
@onready var hud: HUD = $HUD
@onready var rune_pick: RunePick = $RunePick
@onready var end_screen: EndScreen = $EndScreen
@onready var pause_menu: PauseMenu = $PauseMenu

var room: Room
var _ending: bool = false
## Выбор трейта Мьёльнира после мини-босса (строится кодом, не из game.tscn)
var trait_pick: TraitPick
## Время забега, причина смерти, бой-реплики Одина (run/run_tracker.gd)
var tracker: RunTracker
var tutorial: Tutorial
## Двери-награды и выдача наград залов (run/reward_flow.gd, блок И)
var rewards: RewardFlow
var _after_run_started: bool = false

func _ready() -> void:
	FX.reset_time()
	get_tree().paused = false
	if Run.body == null or Run.room_order.is_empty():
		Run.start_run()
	Run.body = Save.apply_permanent_to_body(Run.body)  # открытия «навсегда»: +HP, +рывок, скорость
	player.apply_body_and_runes(Run.body, Run)
	player.died.connect(_on_player_died)
	Run.kill_streak.connect(_on_kill_streak)
	rune_pick.picked.connect(_on_rune_picked)
	trait_pick = TraitPick.new()
	trait_pick.name = "TraitPick"
	add_child(trait_pick)
	trait_pick.picked.connect(_on_trait_picked)
	Run.mjolnir_combo_unlocked.connect(_on_combo_unlocked)
	rewards = RewardFlow.attach(self)
	end_screen.restart_requested.connect(_after_run)
	end_screen.menu_requested.connect(go_to_menu)
	pause_menu.restart_requested.connect(restart_run)
	pause_menu.menu_requested.connect(go_to_menu)
	hud.bind_player(player)
	tracker = RunTracker.attach(self, player)
	# Обучение в первом зале — подсказки Хугина и Мунина (run/tutorial.gd)
	tutorial = Tutorial.attach(self)
	VfxScreen.attach(self, player)  # линии скорости, виньетка берсерка, идеальный хват
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Дожидаемся фоновой загрузки моделей (обычно уже готово, пока игрок был в меню)
	AssetCache.finish()
	# Небо и дымка мира (панорама из run/maps/<мир>.tres; Мидгард — закат)
	WorldArt.apply_world(self, Run.map)
	_load_room()
	Dialogue.on_run_start(Run.body.id if Run.body else "")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _ending and not rune_pick.visible and not trait_pick.visible and not rewards.is_screen_open():
		pause_menu.toggle()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not get_tree().paused and not _ending:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _load_room() -> void:
	Perf.mark("room_load")
	if room and is_instance_valid(room):
		level.remove_child(room)
		room.queue_free()
	for c in get_children():
		# Убираем «мусор» прошлого зала (снаряды, огонь), оставляя постоянные узлы
		if c.has_meta("transient") or c is Area3D or (c.get_script() and c.get_script().resource_path.ends_with("fire_zone.gd")):
			c.queue_free()
	var path := Run.current_room_path()
	var scene: PackedScene
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		scene = ResourceLoader.load_threaded_get(path) as PackedScene
	else:
		scene = load(path) as PackedScene
	room = scene.instantiate() as Room
	level.add_child(room)
	# Новый зал — Мьёльнир сразу готов к броску
	if player and player.mjolnir:
		player.mjolnir.reset_cooldown()
	# Атмосфера зала по миру: искры над факелами и очагом, пылинки, низкий туман (scripts/world_art.gd)
	WorldArt.dress_room(room, Run.map)
	# Под крышей (Room.indoor) — свой свет без неба и солнца; тени факелов (scripts/world_art.gd, блок Б0)
	WorldArt.apply_room(self, room, Run.map)
	var t := room.get_spawn_transform()
	player.global_position = t.origin
	player.velocity = Vector3.ZERO
	player.rotation_target = Vector2(0.0, t.basis.get_euler().y)
	player.mjolnir.force_return_instant()
	player.on_room_start()  # пассивки тела «на зал» (скальд: первый удар не ранит)
	room.cleared.connect(_on_room_cleared)
	room.exit_reached.connect(_on_exit_reached)
	room.boss_spawned.connect(hud.show_boss)
	room.boss_spawned.connect(_on_boss_spawned)
	room.enemy_count_changed.connect(hud.set_enemy_count)
	# Руна «Щит Сиф» восстанавливается между волнами
	room.wave_started.connect(func(_i: int) -> void: player.refill_shield())
	rewards.on_room_loaded(room)
	# Мини-босс — последней волной зала (Run.miniboss_rooms)
	if Run.is_miniboss_room():
		var mb := Run.miniboss_def() as MinibossDef
		if mb:
			mb.add_to_room(room, hud)
	hud.set_room(Run.room_index + 1, Run.total_rooms(), room.room_title, Run.is_boss_room())
	hud.fade_in()
	# Пока экран затемнён — прогреваем шейдеры (в каждом зале: свои материалы под светом огня/снарядов)
	ShaderWarmup.run(self)
	# Загрузочный экран (старт забега / переход между залами) — зал готов, убираем
	LoadingScreen.finish(get_tree())
	if Run.is_boss_room() and not Dialogue.on_boss_intro():
		Odin.say("boss_start")
	# Даём осмотреться полсекунды
	get_tree().create_timer(0.6, false).timeout.connect(func() -> void:
		if is_instance_valid(room) and not player.is_dead:
			rewards.start_room(room, player))

func _on_room_cleared() -> void:
	Run.add_glory(Run.glory_room_clear)
	# Следующий зал грузим в фоне, пока игрок выбирает руну
	if Run.room_index + 1 < Run.room_order.size():
		ResourceLoader.load_threaded_request(Run.room_order[Run.room_index + 1], "", true)
	if Run.is_boss_room():
		Run.won = true
		_ending = true
		ScreenArt.prefetch_between_runs()
		Dialogue.on_boss_defeat()
		Dialogue.thor_bark("boss_win", 1.0)
		get_tree().create_timer(1.6, false).timeout.connect(func() -> void:
			Odin.say("victory")
			_show_end(true))
		return
	Odin.say("room_clear_clean" if tracker.room_clean() else "room_clear")
	get_tree().create_timer(0.7, false).timeout.connect(func() -> void:
		if player.is_dead:
			return
		# После мини-босса — сначала трейт Мьёльнира, потом руна
		if Run.is_miniboss_room():
			var traits := Run.random_mjolnir_trait_choices()
			if not traits.is_empty():
				trait_pick.open(traits)
				return
		_offer_rune())

func _offer_rune() -> void:
	# Двери-награды: награда зала по типу двери (руна, оружие, отдых, Локи, Фрейя…)
	if Run.doors_enabled:
		rewards.grant()
		return
	var choices := Run.random_rune_choices(3)
	if choices.is_empty():
		room.open_door()
	else:
		rune_pick.open(choices)

func _on_trait_picked(t: MjolnirTrait) -> void:
	var combos := Run.add_mjolnir_trait(t)
	if combos.is_empty():
		Odin.say("trait_pick")
	Audio.play("sounds/sfx/rune_pick.wav")
	var lv := Run.mjolnir_trait_level(t.id)
	hud.toast("%s %s — %s" % [t.glyph, tr(t.title), tr("уровень %d") % lv if lv > 1 else (tr("стихия") if t.is_element() else tr("приём"))])
	# Наковальня Эйтри: выбор стихии и был наградой зала — дальше двери; мини-босс — дальше руна
	var anvil := rewards.take_anvil_pick()
	get_tree().create_timer(0.5, false).timeout.connect(func() -> void:
		if player.is_dead:
			return
		if anvil:
			rewards.finish()
		else:
			_offer_rune())

## Стихия и приём сложились в связку (блок Б4): карточка-объявление, комикс-слово, реплика Одина.
func _on_combo_unlocked(c: MjolnirTrait) -> void:
	ComboAnnounce.show_combo(self, c)
	if player and is_instance_valid(player):
		ComicFX.pop("combo", player.get_aim_origin() + player.get_aim_forward() * 3.0, true)
	if Odin.say("combo_" + str(c.id)) == "":
		Odin.say("combo")

func _on_rune_picked(rune: RuneDef) -> void:
	Run.add_rune(rune)
	var reward_done := rewards.on_rune_picked(rune)
	player.recalc_from_runes(Run)
	if rune.id == "heal":
		player.heal(Run.rune_value("heal"))  # уровень 1–3: 50 → 100 (у жреца ×2)
	Odin.say("rune_pick")
	Audio.play("sounds/sfx/rune_pick.wav")
	if reward_done:
		_after_reward()

## Награда зала выдана: двери с наградами (блок И) или старая единственная дверь.
func _after_reward() -> void:
	if player.is_dead or _ending:
		return
	if Run.doors_enabled:
		rewards.show_doors()
	else:
		room.open_door()
		hud.toast(tr("Дверь открыта — вперёд!"))

func _on_exit_reached() -> void:
	if _ending:
		return
	if Run.advance_room():
		hud.fade_out(0.25)
		LoadingScreen.transition(get_tree(), 0.25)
		get_tree().create_timer(0.25, false).timeout.connect(_load_room)
	else:
		Run.won = true
		_show_end(true)

func _on_player_died() -> void:
	if _ending:
		return
	_ending = true
	var result := tracker.finish(false)
	ScreenArt.prefetch_between_runs()  # фоны дивана, портреты тел — пока идёт страница и итог
	# «Страница комикса» (ui/comic_page.gd): стоп-кадр смерти ~2 с, потом сразу итог
	var page := ComicPage.show_death(self, result)
	if page:
		await page.closed
		_show_end(false)
		return
	get_tree().create_timer(1.4, false).timeout.connect(func() -> void: _show_end(false))

## Босс со своей заставкой (Свен, Ярл — ScreenArt.BOSSES): карточка-«вклейка» при появлении,
## «страница комикса» при смерти. Поток не меняется: вставки ставят игру на паузу и ждут.
func _on_boss_spawned(boss: Enemy) -> void:
	var info := ScreenArt.boss_info(boss)
	if info.is_empty():
		return
	BossCard.show_for(self, boss)
	var boss_id := str(info.id)
	var title := str(boss.get_meta("boss_title", ""))
	boss.died.connect(func(_e: Enemy) -> void:
		if not player.is_dead:
			ComicPage.show_boss(self, boss_id, title), CONNECT_ONE_SHOT)

func _on_kill_streak(_count: int) -> void:
	Odin.say("streak10")

func _show_end(victory: bool) -> void:
	_ending = true
	tracker.finish(victory)
	FX.reset_time()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	end_screen.show_result(victory)

## После итога забега: диалог у дивана (Dialogue.after_run) → «План тренировок» → новый забег.
func _after_run() -> void:
	if _after_run_started:
		return
	_after_run_started = true
	end_screen.visible = false
	await Dialogue.after_run(Run.won)
	var plan := TrainingPlan.new()
	plan.name = "TrainingPlan"
	add_child(plan)
	plan.open(tr("В меню"))
	var start: bool = await plan.closed
	if not start:
		go_to_menu()
		return
	# Выбор тела на следующий забег (ui/body_select.gd); «Назад» — в меню
	var bs := BodySelect.new()
	bs.name = "BodySelect"
	add_child(bs)
	bs.open(tr("В меню"), Run.body.id if Run.body else "")
	var body_id: String = await bs.closed
	if body_id == "":
		go_to_menu()
	else:
		restart_run(body_id)

## Новый забег. body_id — тело (пусто — то же тело, что сейчас: «Заново» из паузы).
func restart_run(body_id: String = "") -> void:
	FX.reset_time()
	get_tree().paused = false
	if body_id == "" and Run.body:
		body_id = Run.body.id
	Run.start_run(body_id)
	await LoadingScreen.show_now(get_tree())
	get_tree().reload_current_scene()

func go_to_menu() -> void:
	FX.reset_time()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
