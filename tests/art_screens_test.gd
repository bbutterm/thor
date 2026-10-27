extends Node
## Графика экранов (комплект владельца): портреты тел, картинки «Плана тренировок», фоны и сюжетные кадры
## новеллы, загрузочные экраны, заставка босса и «страница комикса» (смерть Тора и босса) — и что поток
## забега после них прежний (Свен → трейт, Ярл → победа, смерть → итог → диван).
## godot --headless --path . --fixed-fps 60 res://tests/art_screens_test.tscn
## Кадры (xvfb): xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 1280x720 res://tests/art_screens_test.tscn -- <папка> [pages] [en]

var _fails: Array[String] = []
var _passes: int = 0
var game: Game
var shots_dir: String = ""
var only_pages: bool = false
## Держать Тора живым в wait()
var _immortal: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and DisplayServer.get_name() != "headless":
		shots_dir = args[0]
		DirAccess.make_dir_recursive_absolute(shots_dir)
	# Второй аргумент «pages» — только вставки в бою (быстрее под xvfb)
	only_pages = args.size() > 1 and args[1] == "pages"
	# «en» — кадры на английском
	if "en" in args:
		GameSettings.set_value("text", "language", "en", false)
	_run.call_deferred()

func check(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
		print("  [OK] ", what)
	else:
		_fails.append(what)
		print("  [FAIL] ", what)

func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().process_frame
		_keep_alive()

func wait_until(cond: Callable, timeout: float) -> bool:
	for i in int(ceil(timeout * 60.0)):
		if cond.call():
			return true
		await get_tree().process_frame
		_keep_alive()
	return cond.call()

func _keep_alive() -> void:
	if _immortal and game and is_instance_valid(game) and game.player and not game.player.is_dead:
		game.player.health = game.player.max_health

func shot(name: String) -> void:
	if shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(shots_dir.path_join(name + ".png"))
		print("shot: ", name)

func _start(order: Array, index: int = 0) -> void:
	Run.start_run("berserker")
	Run.room_order.assign(order)
	Run.room_index = index
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.4)
	game = get_tree().current_scene as Game

func _run() -> void:
	print("=== ART SCREENS TEST ===")
	if not only_pages:
		_test_data()
		await _test_body_select()
		await _test_training_plan()
		await _test_dialogue()
		await _test_loading()
	ScreenArt.pauses_in_tests = true
	await _test_sven()
	if not only_pages:
		await _test_jarl()
	await _test_death()
	if not only_pages:
		await _test_switches()
	ScreenArt.pauses_in_tests = false
	_finish()

# --- Данные и сопоставления ---

func _test_data() -> void:
	print("-- Данные")
	var missing: Array = []
	for b in Run.all_bodies:
		if ScreenArt.body_portrait(b.id) == null:
			missing.append(b.id)
	check(Run.all_bodies.size() == 9 and missing.is_empty(), "портреты всех 9 тел (%s)" % ("нет: " + str(missing) if not missing.is_empty() else "ок"))
	check(ScreenArt.body_portrait("berserker", true) == ScreenArt.tex(ScreenArt.BODIES + "locked.webp"), "закрытое тело — locked.webp")
	var thumb := ScreenArt.body_thumb("hunter") as AtlasTexture
	check(thumb != null and thumb.region.size.x > 100.0 and is_equal_approx(thumb.region.size.x, thumb.region.size.y), "значок тела — квадрат с головой")
	var with_icon := 0
	for u in Save.all_unlocks:
		if u.icon:
			with_icon += 1
	check(with_icon == 16, "картинки у открытий «Плана тренировок» (%d из %d)" % [with_icon, Save.all_unlocks.size()])
	check(Save.get_unlock("boomerang").icon.resource_path.ends_with("hammer_found.webp"), "«Вспомнил, где лежит молот» — hammer_found")
	check(Save.get_unlock("body_smith").icon.resource_path.ends_with("new_body.webp"), "тела в «Плане» — new_body")
	# Причины смерти → картинки и пулы подписей Одина
	var cases := [
		[{"cause": "fall"}, "fall"], [{"cause": "own_fire"}, "fire"], [{"cause": "barrel"}, "barrel"],
		[{"cause": "boss", "killed_by": "boss_jarl"}, "boss"], [{"cause": "draugr", "killed_by": "draugr_warrior"}, "draugr"],
		[{"cause": "draugr", "killed_by": "draugr_thrower"}, "ranged"], [{"cause": "draugr", "tags": ["ranged"]}, "ranged"],
		[{"cause": "unknown"}, "draugr"], [{}, "draugr"],
	]
	var bad: Array = []
	for c in cases:
		if ScreenArt.death_key(c[0]) != c[1]:
			bad.append("%s→%s" % [c[0], ScreenArt.death_key(c[0])])
	check(bad.is_empty(), "причина смерти → картинка %s" % ("" if bad.is_empty() else str(bad)))
	var no_art: Array = []
	for k in ["barrel", "boss", "draugr", "fall", "fire", "ranged"]:
		if ScreenArt.death_art(k) == null or not Dialogue.has_pool("odin.page_" + k):
			no_art.append(k)
	check(no_art.is_empty(), "у каждой причины — sprites/death/<причина>.webp и пул odin.page_<причина> %s" % str(no_art))
	for src in ScreenArt.BOSSES:
		var info: Dictionary = ScreenArt.BOSSES[src]
		check(ResourceLoader.exists(ScreenArt.boss_card_path(info.card)) and Dialogue.has_pool("odin.page_boss_" + str(info.id)),
			"босс %s: карточка %s и пул odin.page_boss_%s" % [info.id, info.card, info.id])
	check(Dialogue.has_pool("odin.loading") and Dialogue.pools["odin.loading"].size() >= 10, "советы Одина на загрузке (%d)" % Dialogue.pools.get("odin.loading", []).size())
	for i in ScreenArt.LOADING_COUNT:
		if ScreenArt.tex(ScreenArt.loading_path(i)) == null:
			check(false, "загрузочная картинка %d" % (i + 1))
	check(ScreenArt.backdrop_path("couch").ends_with("couch_room.webp") and ScreenArt.backdrop_path("shop").ends_with("dwarf_shop.webp")
		and ScreenArt.backdrop_path("run").ends_with("midgard_village.webp") and ScreenArt.backdrop_path("none") == ""
		and ScreenArt.backdrop_path("bifrost_gate").ends_with("bifrost_gate.webp"), "фоны новеллы: диван, ларёк, мир забега, по имени файла")
	# Боевые картинки держит AssetCache (не читаются с диска посреди боя)
	var held := AssetCache.paths()
	check(ScreenArt.boss_card_path("fat_sven") in held and ScreenArt.boss_card_path("jarl_bjorn") in held
		and ScreenArt.loading_path(0) in held and (ScreenArt.DEATH + "fall.webp") in held, "заставки, загрузки и кадры смерти — в AssetCache")
	# Сюжетные кадры в данных
	var intro: Dictionary = {}
	var first_death: Dictionary = {}
	var first_win: Dictionary = {}
	for sc in Dialogue.scenes:
		match str(sc.get("id", "")):
			"odin_intro": intro = sc
			"odin_first_death": first_death = sc
			"odin_first_win": first_win = sc
	var imgs: Array = []
	for l in intro.get("lines", []):
		if l.has("image"):
			imgs.append(str(l.image))
	check(imgs.size() >= 6 and "intro_1" in imgs and "intro_6" in imgs, "интро: кадры %s" % str(imgs))
	check(first_death.get("image", "") == "first_death" and first_win.get("image", "") == "first_boss_win", "первая смерть и первая победа — свои кадры")
	var errs := Dialogue.validate()
	check(errs.is_empty(), "данные диалогов без ошибок %s" % ("" if errs.is_empty() else str(errs.slice(0, 4))))
	check(bool(GameSettings.DEFAULTS.comic.page) and bool(GameSettings.DEFAULTS.comic.boss_card), "выключатели [comic] page / boss_card, по умолчанию вкл")
	var sp := SettingsPanel.new()
	add_child(sp)
	var found := {}
	for c in sp.find_children("*", "Control", true, false):
		if c.has_meta("setting"):
			found[str(c.get_meta("setting"))] = true
	check(found.has("comic/page") and found.has("comic/boss_card"), "выключатели на экране настроек")
	sp.queue_free()

# --- Экраны между забегами ---

func _test_body_select() -> void:
	print("-- Выбор тела")
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await wait(0.3)
	var bs := BodySelect.new()
	get_tree().current_scene.add_child(bs)
	bs.open("Назад", "berserker")
	await wait(0.4)
	check(bs.portrait_texture() == ScreenArt.body_portrait("berserker"), "портрет выбранного тела во весь рост")
	var locked_id := ""
	for b in bs.bodies:
		if BodySelect.is_locked(b.id):
			locked_id = b.id
			break
	await shot("01_body_select")
	if locked_id != "":
		bs.select(locked_id)
		await wait(0.1)
		check(bs.portrait_texture() == ScreenArt.body_portrait(locked_id, true), "закрытое тело (%s) — силуэт с замком" % locked_id)
	var faces := 0
	for id in bs._cards:
		for t in (bs.card(id) as Button).find_children("*", "TextureRect", true, false):
			if (t as TextureRect).texture is AtlasTexture:
				faces += 1
	check(faces == bs.bodies.size(), "на карточках — головы с портретов (%d)" % faces)
	bs.close("")
	bs.queue_free()

func _test_training_plan() -> void:
	print("-- План тренировок")
	var tp := TrainingPlan.new()
	get_tree().current_scene.add_child(tp)
	tp.open("Назад")
	await wait(0.4)
	var card: Node = tp._cards.get("belly")
	var pic := false
	if card:
		for t in card.find_children("*", "TextureRect", true, false):
			pic = pic or (t as TextureRect).texture == Save.get_unlock("belly").icon
	check(pic, "у «Сбросил пузо» — картинка belly")
	await shot("02_training_plan")
	tp.close(false)
	tp.queue_free()

func _test_dialogue() -> void:
	print("-- Новелла: фоны и сюжетные кадры")
	var lines := [
		{"id": "odin_intro_01", "speaker": "odin", "emotion": "angry", "text": "ПОДЪЁМ! Сколько можно лежать?", "image": "intro_2"},
		{"id": "odin_intro_02", "speaker": "thor", "emotion": "embarrassed", "text": "Пап, ещё серию… одну… там сейчас всё решится."},
		{"id": "odin_intro_03", "speaker": "odin", "emotion": "angry", "text": "Там уже тысячу лет «всё решится». Посмотри на себя.", "image": "intro_3"},
		{"id": "odin_intro_04", "speaker": "thor", "emotion": "shocked", "text": "А что не так?", "image": "none"},
	]
	Dialogue.play_lines(lines, "", "couch")
	var box := Dialogue.box()
	await wait(0.3)
	check(box.visible and box.story_id == "intro_2", "кадр intro_2 с первой реплики")
	check(box._bg.visible and box._bg.texture == ScreenArt.backdrop("couch"), "фон «диван» — картинка couch_room")
	check(not box._left.visible and not box._right.visible, "на сюжетном кадре портретов нет")
	await wait(1.2)
	await shot("03_dialogue_story")
	box._age = 10.0
	box.advance()
	box.advance()
	await wait(0.1)
	check(box.story_id == "intro_2", "реплика без image — кадр тот же")
	box.advance()
	box.advance()
	await wait(0.5)
	check(box.story_id == "intro_3", "смена кадра — intro_3")
	box.advance()
	box.advance()
	await wait(0.5)
	check(box.story_id == "" and (box._left.visible or box._right.visible), "\"image\": \"none\" — кадр убран, портреты вернулись")
	await shot("04_dialogue_couch")
	box.skip()
	await wait(0.2)
	# Сцена со своим фоном (ларёк гномов) и кадром с первой реплики
	Dialogue.play_scene({"id": "art_test_scene", "backdrop": "shop", "image": "first_death",
		"lines": [{"id": "x1", "speaker": "odin", "emotion": "neutral", "text": "…"}]}, "run")
	await wait(0.2)
	check(box.backdrop_path.ends_with("dwarf_shop.webp") and box.story_id == "first_death", "поля сцены backdrop / image")
	box.skip()
	await wait(0.2)
	Dialogue.play_lines([{"id": "x2", "speaker": "odin", "emotion": "neutral", "text": "…"}], "", "run")
	await wait(0.2)
	check(box.backdrop_path.ends_with("midgard_village.webp"), "сцена в забеге — фон деревни Мидгарда")
	box.skip()
	await wait(0.2)
	check(not get_tree().paused, "после новеллы пауза снята")

func _test_loading() -> void:
	print("-- Загрузочный экран")
	var before := LoadingScreen.shown_count
	await LoadingScreen.show_now(get_tree())
	check(LoadingScreen.is_showing() and LoadingScreen._inst._pic.texture != null, "картинка загрузки на весь экран")
	check(LoadingScreen._inst.tip != "", "совет Одина: «%s»" % LoadingScreen._inst.tip)
	await shot("05_loading")
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.ROOM_SCENES[1], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.3)
	game = get_tree().current_scene as Game
	var hidden := await wait_until(func() -> bool: return not LoadingScreen.is_showing(), 2.0)
	check(hidden and game != null and game.room != null, "зал загружен — экран загрузки убран")
	await wait(0.8)
	var room_id := game.room.get_instance_id()
	game._on_exit_reached()
	await wait(0.1)
	check(LoadingScreen.is_showing() and LoadingScreen.shown_count == before + 2, "переход между залами — картинка под затемнением")
	var moved := await wait_until(func() -> bool: return game.room.get_instance_id() != room_id and not LoadingScreen.is_showing(), 3.0)
	check(moved, "следующий зал загружен, экран убран")
	await wait(0.8)
	check(not LoadingScreen._inst.visible, "картинка исчезла совсем")

# --- Боссы ---

func _find(cls: String) -> Enemy:
	for e in game.room.alive_enemies():
		if is_instance_valid(e) and e.get_script() and (e.get_script() as Script).get_global_name() == cls:
			return e
	return null

func _kill_all_but(keep: Enemy) -> void:
	for e in game.room.alive_enemies().duplicate():
		if e != keep and is_instance_valid(e) and not e.is_dead:
			e.take_hit(9999, Vector3.ZERO, "test")

func _test_sven() -> void:
	print("-- Толстый Свен: заставка и страница")
	var mi: int = Run.miniboss_rooms[0] if not Run.miniboss_rooms.is_empty() else 3
	var order: Array = []
	for i in mi:
		order.append(Run.ROOM_SCENES[i % Run.ROOM_SCENES.size()])
	order.append(Run.miniboss_arena)
	order.append(Run.BOSS_SCENE)
	await _start(order, mi)
	if Run.miniboss_rooms.is_empty() or not Run.is_miniboss_room():
		check(false, "зал мини-босса")
		return
	var cards := BossCard.shown_count
	var sven: Enemy = null
	for i in 60:
		sven = _find("FatSven")
		if sven:
			break
		_kill_all_but(null)
		await wait(0.3)
	check(sven != null, "Свен вышел")
	if sven == null:
		return
	await wait(0.1)
	check(BossCard.shown_count == cards + 1 and BossCard.last_id == "sven", "заставка Свена")
	check(get_tree().paused, "на заставке игра на паузе")
	await wait(0.5)
	await shot("06_boss_card_sven")
	var closed := await wait_until(func() -> bool: return ComicInsert.current == null, 3.0)
	check(closed and not get_tree().paused, "заставка ушла сама (~2 с), пауза снята")
	_kill_all_but(sven)
	await wait(0.3)
	var pages := ComicPage.shown_count
	sven.take_hit(9999, Vector3.ZERO, "melee_finisher")
	await wait(0.1)
	check(ComicPage.shown_count == pages + 1 and ComicPage.last_kind == "boss" and ComicPage.last_key == "sven", "страница комикса: Свен повержен")
	check(ComicPage.last_caption != "", "подпись Одина: «%s»" % ComicPage.last_caption)
	check(get_tree().paused and not game.trait_pick.visible, "стоп-кадр: пауза, выбор трейта ждёт")
	await wait(0.6)
	await shot("07_page_sven")
	var after := await wait_until(func() -> bool: return game.trait_pick.visible, 5.0)
	check(after, "после страницы — выбор трейта Мьёльнира (поток прежний)")

func _test_jarl() -> void:
	print("-- Ярл Бьорн: заставка, пропуск, страница, победа")
	await _start([Run.BOSS_SCENE], 0)
	# Интро-сцена Ярла (в тестах сцены в забеге выключены) не мешает: карточка ждёт, пока идёт новелла
	var jarl: Enemy = null
	for i in 40:
		jarl = _find("JarlBoss")
		if jarl:
			break
		await wait(0.2)
	check(jarl != null, "Ярл появился")
	if jarl == null:
		return
	await wait(0.05)
	check(BossCard.last_id == "jarl" and ComicInsert.current is BossCard, "заставка Ярла")
	await wait(0.4)
	# Пропуск кликом
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.parse_input_event(ev)
	var skipped := await wait_until(func() -> bool: return ComicInsert.current == null, 0.6)
	check(skipped and not get_tree().paused, "клик пропускает заставку")
	_kill_all_but(jarl)
	await wait(0.3)
	jarl.take_hit(9999, Vector3.ZERO, "melee_finisher")
	await wait(0.1)
	check(ComicPage.last_key == "jarl" and ComicInsert.current is ComicPage, "страница комикса: Ярл повержен")
	check(not game.end_screen.visible, "экран победы ждёт страницу")
	# Оставшиеся волны корма (поток зала не наш) — добиваем, пока зал не зачищен
	for i in 30:
		if game.room._is_cleared:
			break
		_kill_all_but(null)
		await wait(0.3)
	var won := await wait_until(func() -> bool: return game.end_screen.visible and Run.won, 6.0)
	check(won, "после страницы — экран победы")
	if not won:
		print("    DEBUG won=%s cleared=%s alive=%d insert=%s paused=%s ending=%s dead=%s" % [Run.won, game.room._is_cleared, game.room.alive_count(), ComicInsert.current, get_tree().paused, game._ending, game.player.is_dead])

func _test_death() -> void:
	print("-- Смерть Тора: страница и поток")
	await _start([Run.ROOM_SCENES[0], Run.BOSS_SCENE], 0)
	await wait(1.0)
	_immortal = false
	var pages := ComicPage.shown_count
	RunTracker.note_damage("barrel")
	game.player.take_damage(99999.0, Vector3.ZERO, true)
	await wait(0.1)
	check(game.player.is_dead, "Тор погиб")
	check(ComicPage.shown_count == pages + 1 and ComicPage.last_kind == "death" and ComicPage.last_key == "barrel", "страница: смерть от бочки (%s)" % ComicPage.last_key)
	check(ComicPage.last_caption != "", "подпись Одина: «%s»" % ComicPage.last_caption)
	check(not game.end_screen.visible, "итог ждёт страницу")
	await wait(0.7)
	await shot("08_page_death")
	var shown := await wait_until(func() -> bool: return game.end_screen.visible, 4.0)
	check(shown, "после страницы — экран итога")
	game.end_screen.restart_requested.emit()
	await wait(0.4)
	var box := Dialogue.box()
	check(box.visible and box._bg.texture == ScreenArt.backdrop("couch"), "диалог у дивана — на картинке couch_room")
	box.skip()
	await wait(0.4)
	var plan := game.get_node_or_null("TrainingPlan") as TrainingPlan
	check(plan != null and plan.visible, "дальше — «План тренировок»")
	if plan:
		plan.close(false)
	_immortal = true
	await wait(0.4)

func _test_switches() -> void:
	print("-- Выключатели")
	GameSettings.set_value("comic", "page", false, false)
	GameSettings.set_value("comic", "boss_card", false, false)
	await _start([Run.BOSS_SCENE], 0)
	var cards := BossCard.shown_count
	var jarl: Enemy = null
	for i in 40:
		jarl = _find("JarlBoss")
		if jarl:
			break
		await wait(0.2)
	await wait(0.1)
	check(jarl != null and BossCard.shown_count == cards and not get_tree().paused, "заставка выключена — бой сразу")
	_immortal = false
	var pages := ComicPage.shown_count
	game.player.take_damage(99999.0, Vector3.ZERO, true)
	await wait(0.2)
	check(ComicPage.shown_count == pages, "стоп-кадр выключен — страницы нет")
	var shown := await wait_until(func() -> bool: return game.end_screen.visible, 2.5)
	check(shown, "итог — как раньше, через 1.4 с")
	_immortal = true
	GameSettings.set_value("comic", "page", true, false)
	GameSettings.set_value("comic", "boss_card", true, false)

func _finish() -> void:
	print("=== ИТОГ ART: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
