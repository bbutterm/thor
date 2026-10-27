extends Node
## Тест системы диалогов: все JSON грузятся, у каждой реплики есть id, говорящий и эмоция, условия
## разбираются; выбор по приоритету и «просмотрено»; пул; окно новеллы с выбором; сценарий
## «смерть → диалог → (план тренировок) → новый забег». Пишет в отдельное сохранение (user://dialogue_test_save.json).
## godot --headless --path . --fixed-fps 60 res://tests/dialogue_test.tscn

var _fails: Array[String] = []
var _passes: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "DialogueRunner"
		get_tree().root.add_child.call_deferred(runner)
		return
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

func _run() -> void:
	print("=== DIALOGUE TEST ===")
	Save.use_path("user://dialogue_test_save.json")
	_test_data()
	_test_conditions()
	_test_selection()
	_test_shop_greeting_history()
	_test_content()
	_test_finale_gating()
	_test_story_order()
	await _test_box()
	await _test_run_start_scene()
	await _test_death_flow()
	_finish()

## Первый забег в настоящей игре: сцена-знакомство на паузе, после неё зал оживает
func _test_run_start_scene() -> void:
	print("-- Сцена на старте первого забега")
	Save.reset()
	Dialogue.in_run_scenes = true
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.6)
	var box := Dialogue.box()
	check(box.visible and Save.is_seen("odin_intro"), "первый забег начинается со сцены odin_intro")
	check(get_tree().paused, "забег на паузе, пока идёт сцена")
	var game := get_tree().current_scene as Game
	check(game != null and game.room.alive_count() == 0, "враги ждут конца сцены")
	box.skip()
	await wait(2.0)
	check(not get_tree().paused, "после сцены пауза снята")
	check(game != null and game.room.alive_count() > 0, "после сцены пошла волна врагов")
	Dialogue.in_run_scenes = false

func _test_data() -> void:
	print("-- Данные")
	Dialogue.load_all()
	var files := 0
	for f in DirAccess.get_files_at(Dialogue.DIR):
		if f.get_extension() == "json":
			files += 1
	check(files >= 3, "найдено JSON-файлов: %d" % files)
	check(Dialogue.load_errors.is_empty(), "все JSON разобрались (%s)" % str(Dialogue.load_errors))
	var errs := Dialogue.validate()
	for e in errs.slice(0, 20):
		print("     ", e)
	check(errs.is_empty(), "реплики: id, говорящий, эмоция, текст, условия, выборы — ошибок %d" % errs.size())
	var lines := 0
	for sc in Dialogue.scenes:
		lines += (sc.lines as Array).size()
	var pool_items := 0
	for p in Dialogue.pools:
		pool_items += (Dialogue.pools[p] as Array).size()
	print("    сцен %d (реплик %d), пулов %d (вариантов %d), говорящих %d" % [Dialogue.scenes.size(), lines, Dialogue.pools.size(), pool_items, Dialogue.speakers.size()])
	check(Dialogue.speakers.has("thor") and Dialogue.speakers.has("odin"), "есть говорящие Тор и Один")
	check(Dialogue.has_pool("odin.run_start") and Dialogue.has_pool("odin.death") and Dialogue.has_pool("odin.idle"), "пулы Одина на месте")
	for sp in Dialogue.speakers:
		var d: Dictionary = Dialogue.speakers[sp]
		check(d.has("name") and d.has("color"), "говорящий %s: имя и цвет" % sp)
	check(Portrait.texture_path("odin", "angry") == "" or ResourceLoader.exists(Portrait.texture_path("odin", "angry")), "путь портрета или заглушка")

func _test_conditions() -> void:
	print("-- Условия")
	for s in ["deaths >= 3", "killed_by == \"boss_jarl\"", "first_time", "has_unlock:boomerang", "run_count > 1",
			"cause_of_death == fall", "!seen:odin_intro", "tag:quick", "choice:odin_intro == snap", "deaths_by.fall >= 2", "random < 0.5"]:
		check(Dialogue.parse_condition(s).ok, "разбирается «%s»" % s)
	for s in ["", "deaths >>", "??", "seen:"]:
		check(not Dialogue.parse_condition(s).ok, "отвергается «%s»" % s)
	var ctx := {"deaths": 4, "killed_by": "boss_jarl", "cause_of_death": "fall", "event_count": 1}
	check(Dialogue.check([Dialogue.parse_condition("deaths >= 3")], ctx), "deaths >= 3 при 4")
	check(not Dialogue.check([Dialogue.parse_condition("deaths < 3")], ctx), "deaths < 3 при 4 — нет")
	check(Dialogue.check([Dialogue.parse_condition("killed_by == \"boss_jarl\"")], ctx), "killed_by == boss_jarl")
	check(Dialogue.check([Dialogue.parse_condition("cause_of_death != draugr")], ctx), "cause_of_death != draugr")
	check(Dialogue.check([Dialogue.parse_condition("first_time")], ctx), "first_time при первом событии")
	ctx.event_count = 2
	check(not Dialogue.check([Dialogue.parse_condition("first_time")], ctx), "first_time при втором — нет")
	check(Dialogue.check([Dialogue.parse_condition("!has_unlock:nothing_such")], ctx), "!has_unlock неизвестного")

func _test_selection() -> void:
	print("-- Выбор сцены")
	Save.reset()
	var a := {"id": "t_low", "trigger": "test_evt", "priority": 5, "lines": [{"id": "t_low_1", "speaker": "odin", "emotion": "neutral", "text": "низкий"}]}
	var b := {"id": "t_high", "trigger": "test_evt", "priority": 10, "lines": [{"id": "t_high_1", "speaker": "odin", "emotion": "neutral", "text": "высокий"}]}
	var c := {"id": "t_cond", "trigger": "test_evt", "priority": 50, "conditions": ["deaths >= 99"], "lines": [{"id": "t_c", "speaker": "odin", "emotion": "neutral", "text": "никогда"}]}
	for sc in [a, b, c]:
		sc["_conds"] = Dialogue._parse_all(sc.get("conditions", []), "test")
		sc["_file"] = "test"
		Dialogue.scenes.append(sc)
	check(Dialogue.pick_scene("test_evt").get("id", "") == "t_high", "выбрана сцена с высшим приоритетом (условие не выполнено у ещё более высокой)")
	Save.mark_seen("t_high")
	check(Dialogue.pick_scene("test_evt").get("id", "") == "t_low", "просмотренная не повторяется — следующая по приоритету")
	Save.mark_seen("t_low")
	check(Dialogue.pick_scene("test_evt").is_empty(), "все просмотрены — сцены нет (будет пул)")
	Dialogue.scenes = Dialogue.scenes.filter(func(s: Dictionary) -> bool: return s.get("trigger", "") != "test_evt")
	var seen := {}
	for i in 30:
		seen[Dialogue.pool_text("odin.run_start")] = true
	check(seen.size() > 1 and not seen.has(""), "пул отдаёт разные реплики (%d)" % seen.size())
	Save.data.last_run = {"won": false, "cause": "fall", "tags": ["quick"]}
	var rp := Dialogue.reaction_pool(false)
	check(rp.begins_with("odin.death"), "пул реакции на смерть: %s" % rp)
	check(Dialogue.reaction_pool(true) == "odin.victory_reaction", "пул реакции на победу")
	var first := Dialogue.pick_scene("death")
	Save.reset()
	Save.bump_event("death")
	first = Dialogue.pick_scene("death")
	check(not first.is_empty(), "на первую смерть есть сюжетная сцена (%s)" % first.get("id", ""))
	Save.reset()

## Брокк не называет Тора постоянным клиентом до повторного открытия ларька.
func _test_shop_greeting_history() -> void:
	print("-- Приветствие ларька")
	Save.reset()
	var regular: Dictionary = {}
	for item in Dialogue.pools.get("dwarves.shop_enter", []):
		if str(item.lines[0].get("id", "")) == "dwarves.shop_enter.03":
			regular = item
			break
	check(not regular.is_empty(), "реплика о постоянном клиенте существует")
	if regular.is_empty():
		return
	check(not Dialogue.check(regular._conds, Dialogue.context()), "в первый вход в зал реплика недоступна")
	Save.data.stats.deaths = 1
	Save.bump_event("shop_enter")
	check(not Dialogue.check(regular._conds, Dialogue.context()), "первое открытие после смерти ещё не делает Тора постоянным клиентом")
	Save.reset()
	# Событие увеличивается при открытии прилавка, до реплики в ShopScreen.open().
	Save.bump_event("shop_enter")
	check(not Dialogue.check(regular._conds, Dialogue.context()), "в первое открытие прилавка реплика недоступна")
	Save.end_run({"won": false, "cause": "draugr", "rooms": 1})
	Save.load_game()
	check(Save.deaths() == 1 and Save.event_count("shop_enter") == 1, "смерть и первое открытие сохраняются между забегами")
	check(not Dialogue.check(regular._conds, Dialogue.context()), "на входе в ларёк следующего забега реплика ещё недоступна")
	Save.bump_event("shop_enter")
	check(Dialogue.check(regular._conds, Dialogue.context()), "после повторного открытия и смерти реплика доступна")
	Save.data.stats.deaths = 0
	check(not Dialogue.check(regular._conds, Dialogue.context()), "без смертей реплика об умирающем клиенте недоступна")
	Save.reset()

func _pool_size(prefix: String) -> int:
	var n := 0
	for p in Dialogue.pools:
		if str(p).begins_with(prefix):
			n += (Dialogue.pools[p] as Array).size()
	return n

## Объёмы текстов блока Б
func _test_content() -> void:
	print("-- Тексты")
	var death := _pool_size("odin.death")
	check(death >= 40, "реакций Одина на смерть: %d (нужно 40+)" % death)
	for c in ["draugr", "boss", "fall", "barrel", "own_fire", "ranged", "quick", "long"]:
		check(Dialogue.has_pool("odin.death_" + c), "есть реакции на причину «%s»" % c)
	check(_pool_size("odin.run_start") >= 15, "реплик на старте забега: %d" % _pool_size("odin.run_start"))
	var combat := 0
	for p in ["odin.idle", "odin.multikill", "odin.big_damage", "odin.ranged_kill", "odin.big_slam"]:
		combat += _pool_size(p)
	check(combat >= 10, "боевых мини-реплик: %d" % combat)
	var choices := 0
	for sc in Dialogue.scenes:
		for l in sc.lines:
			if l is Dictionary and l.has("choices"):
				choices += 1
	check(choices >= 8, "мест с выбором ответа Тора: %d" % choices)
	for who in ["ravens", "loki", "sif", "freya", "hild", "hel", "skadi", "heimdall", "dwarves", "jarl"]:
		var has_scene := false
		for sc in Dialogue.scenes:
			if sc._file == who:
				has_scene = true
		check(has_scene and (_pool_size(who + ".visit") >= 3 or who == "jarl"), "персонаж %s: сцена + повторяемые реплики" % who)
	for b in ["jarl", "hel"]:
		check(Dialogue.has_pool(b + ".intro") and Dialogue.has_pool(b + ".defeat"), "босс %s: интро и поражение" % b)
	var story := 0
	for sc in Dialogue.scenes:
		if sc.trigger in ["death", "victory", "run_start"]:
			story += 1
	check(story >= 10, "сюжетных сцен между забегами: %d" % story)

## Черновики финала не должны появиться в обычной игре или до титров.
func _test_finale_gating() -> void:
	print("-- Финал и сцена после титров")
	Save.reset()
	check(Dialogue.pick_scene("meet").is_empty(), "без финального события сцены не выбираются")
	# Даже множество обычных смертей и побед не подменяет будущие события финала и титров.
	Save.data.stats.runs = 100
	Save.data.stats.deaths = 80
	Save.data.stats.wins = 20
	for sc in Dialogue.scenes:
		if sc.get("id", "") in ["finale_a", "finale_post_credits_b"]:
			check(not Dialogue.check(sc._conds, Dialogue.context("victory")), "%s не открывается обычными победами" % sc.id)
	Save.bump_event("odin_finale_unlocked")
	check(Dialogue.pick_scene("meet").get("id", "") == "finale_a", "победа над Одином открывает финал A")
	Save.mark_seen("finale_a")
	check(Dialogue.pick_scene("meet").is_empty(), "после финала эпилог не открывается до титров")
	Save.bump_event("finale_credits_complete")
	check(Dialogue.pick_scene("meet").get("id", "") == "finale_post_credits_b", "эпилог B открывается после финала и титров")
	Save.mark_seen("finale_post_credits_b")
	check(Dialogue.pick_scene("meet").is_empty(), "сюжетные сцены не повторяются")
	Save.reset()
	Save.bump_event("finale_credits_complete")
	check(Dialogue.pick_scene("meet").is_empty(), "событие титров само по себе не обходит финал A")
	Save.reset()
	Save.mark_seen("loki_reveal")
	Save.bump_event("odin_finale_unlocked")
	check(Dialogue.pick_scene("meet").get("id", "") == "finale_a", "финал доступен и после признания Локи между забегами")
	# Если до финала не встретились сцены с разгадкой, они не возвращают уже
	# раскрытый обман в состояние загадки при следующих смертях.
	for pair in [["ravens_gossip", ["loki_intro"]], ["loki_reveal", ["loki_intro", "ravens_gossip"]],
			["dwarves_secret", ["dwarves_intro"]]]:
		Save.reset()
		Save.data.stats.deaths = 14
		for prerequisite in pair[1]:
			Save.mark_seen(prerequisite)
		var matches := Dialogue.scenes.filter(func(sc: Dictionary) -> bool: return sc.get("id", "") == pair[0])
		check(matches.size() == 1, "сцена %s существует" % pair[0])
		if matches.size() != 1:
			continue
		var sc: Dictionary = matches[0]
		check(Dialogue.check(sc._conds, Dialogue.context("death")), "%s доступна до финала" % pair[0])
		if pair[0] == "dwarves_secret":
			Save.mark_seen("loki_reveal")
			check(Dialogue.check(sc._conds, Dialogue.context("death")), "Брокк может предложить доказательство после признания Локи")
		Save.mark_seen("finale_a")
		check(not Dialogue.check(sc._conds, Dialogue.context("death")), "%s не возникает после разгадки финала" % pair[0])
	Save.reset()

## Симуляция 30 смертей: какие сцены открываются и когда (для отчёта)
func _test_story_order() -> void:
	print("-- Порядок сюжета (30 смертей, причины по кругу)")
	Save.reset()
	var causes := ["draugr_warrior", "fall", "boss_jarl", "draugr_thrower", "own_fire"]
	var order: Array[String] = []
	Save.begin_run("berserker")
	Save.bump_event("run_start")
	var s0 := Dialogue.pick_scene("run_start")
	if not s0.is_empty():
		Save.mark_seen(s0.id)
		order.append("старт1:" + s0.id)
	for i in 30:
		var by: String = causes[i % causes.size()]
		Save.end_run({"won": false, "cause": RunTracker.cause_of(by), "killed_by": by, "time": 30.0 + i * 20.0,
			"rooms": i % 4, "tags": ["quick"] if i % 7 == 3 else []})
		Save.bump_event("death")
		var sc := Dialogue.pick_scene("death")
		if not sc.is_empty():
			Save.mark_seen(sc.id)
			order.append("%d:%s" % [i + 1, sc.id])
		Save.begin_run("berserker")
		Save.bump_event("run_start")
		var rs := Dialogue.pick_scene("run_start")
		if not rs.is_empty():
			Save.mark_seen(rs.id)
			order.append("старт%d:%s" % [i + 2, rs.id])
	print("    ", ", ".join(order))
	check(order.size() >= 12, "за 30 смертей открылось сцен: %d" % order.size())
	Save.reset()

func _test_box() -> void:
	print("-- Окно новеллы")
	var lines := [
		{"id": "b1", "speaker": "odin", "emotion": "angry", "text": "Первая реплика."},
		{"id": "b2", "speaker": "thor", "emotion": "embarrassed", "text": "Вторая.", "choices": [
			{"id": "snap", "label": "Огрызнуться", "text": "Нет!", "lines": [{"id": "b3", "speaker": "odin", "emotion": "smug", "text": "Да."}]},
			{"id": "agree", "label": "Согласиться", "text": "Ладно.", "lines": []}]},
		{"id": "b4", "speaker": "odin", "emotion": "happy", "text": "Конец {deaths}."},
	]
	var box := Dialogue.box()
	var cps := box.chars_per_second
	box.chars_per_second = 1.0
	var done := [false]
	var p := func() -> void:
		await Dialogue.play_lines(lines, "test_box")
		done[0] = true
	p.call()
	await wait(0.1)
	check(box.visible, "окно открыто")
	check(get_tree().paused, "игра на паузе во время диалога")
	await wait(0.3)
	box.advance()  # допечатать
	check(box._text.visible_characters == -1, "клик допечатывает строку")
	box.advance()  # дальше
	await wait(0.4)
	box.advance()
	check(box._waiting_choice and box._choices_box.get_child_count() == 2, "показан выбор из 2 ответов")
	box.choose(0)
	await wait(0.05)
	check(box._text.text == "Нет!", "Тор произносит выбранный ответ")
	check(Save.get_choice("test_box") == "snap", "выбор записан в сохранение")
	box.advance()
	box.advance()
	await wait(0.05)
	check(box._text.text == "Да.", "реакция на выбор")
	box.advance()
	box.advance()
	await wait(0.05)
	check(box._text.text.begins_with("Конец 0"), "подстановка {deaths}: «%s»" % box._text.text)
	box.advance()
	box.advance()
	await wait(0.1)
	check(done[0] and not box.visible, "диалог закончился")
	check(not get_tree().paused, "пауза снята после диалога")
	check(Dialogue.history.size() >= 4, "журнал прочитанного (%d)" % Dialogue.history.size())
	# «Пропустить»
	done[0] = false
	p.call()
	await wait(0.4)
	box.skip()
	await wait(0.05)
	check(done[0] and not box.visible, "«Пропустить» закрывает сцену")
	box.chars_per_second = cps

func _test_death_flow() -> void:
	print("-- Смерть → диалог → новый забег")
	Save.reset()
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(1.0)
	var game := get_tree().current_scene as Game
	check(game != null, "забег начался")
	if game == null:
		return
	check(Save.runs() == 1, "сохранение: забег засчитан (%d)" % Save.runs())
	RunTracker.note_damage("draugr_warrior")
	game.player.take_damage(99999.0, Vector3.ZERO, true)
	await wait(2.0)
	check(game.end_screen.visible, "экран итога показан")
	check(Save.deaths() == 1, "смерть записана")
	check(Save.data.last_run.get("killed_by", "") == "draugr_warrior", "причина: %s" % Save.data.last_run.get("killed_by", ""))
	check(Save.data.last_run.get("cause", "") == "draugr", "категория причины: драугр")
	check("quick" in Save.data.last_run.get("tags", []), "метка «быстро сдох»")
	var loaded := FileAccess.open(Save.path, FileAccess.READ)
	check(loaded != null and loaded.get_as_text().find("draugr_warrior") >= 0, "файл сохранения записан")
	game.end_screen.restart_requested.emit()
	await wait(0.5)
	var box := Dialogue.box()
	check(box.visible, "после итога — диалог у дивана")
	check(box._couch.visible, "фон «диван»")
	check(Save.is_seen("odin_first_death"), "первая смерть — сюжетная сцена (просмотрена)")
	var guard := 0
	while box.visible and guard < 400:
		guard += 1
		if box._waiting_choice:
			box.choose(1)
		else:
			box.advance()
		await wait(0.05)
	check(not box.visible, "диалог пройден")
	await wait(0.3)
	var plan := game.get_node_or_null("TrainingPlan") as TrainingPlan
	check(plan != null and plan.visible, "затем «План тренировок» (блок В)")
	if plan:
		plan._fight_btn.pressed.emit()
	await wait(0.3)
	# Блок Л: после «В бой» — выбор тела
	var bs := game.get_node_or_null("BodySelect") as BodySelect
	if bs:
		bs.choose(bs.selected.id)
	await wait(1.0)
	var g2 := get_tree().current_scene as Game
	check(g2 != null and g2 != game, "начался новый забег")
	check(g2 != null and not get_tree().paused, "новый забег не на паузе")
	check(Save.runs() == 2, "второй забег засчитан")
	await wait(0.3)

func _finish() -> void:
	print("=== ИТОГ: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	var used := Save.path
	Save.path = Save.TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(used))
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
