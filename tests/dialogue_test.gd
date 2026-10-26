extends Node
## Тест системы диалогов: все JSON грузятся, у каждой реплики есть id, говорящий и эмоция, условия
## разбираются; выбор по приоритету и «просмотрено»; пул; окно новеллы с выбором; сценарий
## «смерть → диалог → новый забег». Пишет в отдельное сохранение (user://dialogue_test_save.json).
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
	await _test_box()
	await _test_death_flow()
	_finish()

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
