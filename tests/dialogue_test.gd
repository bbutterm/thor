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
	_test_visit_outcomes()
	_test_heimdall_visit_history()
	_test_boss_death_reactions()
	_test_content()
	_test_finale_gating()
	_test_loki_finale_branches()
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

## Реплики, говорящие о смерти в последнем забеге, не должны выпадать после победы.
func _test_visit_outcomes() -> void:
	print("-- Визиты после победы и смерти")
	var lost := Dialogue.parse_condition("lost")
	check(lost.get("ok", false), "существующее условие lost разбирается")
	check(Dialogue.check([lost], {"last_won": false}), "lost выполнено при проигрыше")
	check(not Dialogue.check([lost], {"last_won": true}), "lost не выполнено при победе")
	var saved_pools: Dictionary = Dialogue.pools
	var saved_locale := TranslationServer.get_locale()
	var cases := [
		{"pool": "loki.visit", "intro": "loki_intro", "line": "loki.visit.02_01", "file": "loki"},
		{"pool": "sif.visit", "intro": "sif_intro", "line": "sif.visit.01_01", "file": "sif"},
		{"pool": "skadi.visit", "intro": "skadi_intro", "line": "skadi.visit.01_01", "file": "skadi"},
	]
	for case_data in cases:
		var pool_name: String = case_data.pool
		var line_id: String = case_data.line
		var items: Array = saved_pools.get(pool_name, [])
		var target: Dictionary = {}
		for item in items:
			if str(item.lines[0].get("id", "")) == line_id:
				target = item
				break
		check(not target.is_empty(), "%s: реплика найдена" % line_id)
		if target.is_empty():
			continue
		var loc_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues/en/%s.json" % case_data.file))
		var loc_lines: Dictionary = (loc_data as Dictionary).get("lines", {}) if loc_data is Dictionary else {}
		var translation: Dictionary = loc_lines.get(line_id, {})
		check(not str(translation.get("en", "")).strip_edges().is_empty(), "%s: английский перевод найден" % line_id)
		# Оставляем один настоящий элемент: случайный выбор становится воспроизводимым.
		var one_pool := {}
		one_pool[pool_name] = [target]
		Dialogue.pools = one_pool
		Save.reset()
		Save.end_run({"won": false, "cause": "draugr", "rooms": 1})
		for language in ["ru", "en"]:
			I18n.apply(language)
			Dialogue.refresh_locale()
			check(Dialogue.visitor_lines().is_empty() and Dialogue.pool_lines(pool_name).is_empty(),
				"%s/%s: до знакомства визита нет и пустой пул безопасен" % [line_id, language])
		Save.mark_seen(case_data.intro)
		for language in ["ru", "en"]:
			I18n.apply(language)
			Dialogue.refresh_locale()
			var visit := Dialogue.visitor_lines()
			var shown: Dictionary = visit[0] if not visit.is_empty() else {}
			var expected := str(target.lines[0].text) if language == "ru" else str(translation.get("en", ""))
			check(shown.get("id", "") == line_id and shown.get("text", "") == expected,
				"%s/%s: после смерти случайный визит показан на выбранном языке" % [line_id, language])
		Save.end_run({"won": true, "rooms": 7})
		check(bool(Dialogue.context().get("last_won", false)), "%s: победа записана в контексте" % line_id)
		for language in ["ru", "en"]:
			I18n.apply(language)
			Dialogue.refresh_locale()
			check(Dialogue.visitor_lines().is_empty() and Dialogue.pool_lines(pool_name).is_empty(),
				"%s/%s: после победы реплика недоступна и пустой пул безопасен" % [line_id, language])
		# Остальные визиты этого персонажа должны оставаться доступны и после победы.
		var full_pool := {}
		full_pool[pool_name] = items
		Dialogue.pools = full_pool
		var others := 0
		for item in items:
			if str(item.lines[0].get("id", "")) != line_id and Dialogue.check(item._conds, Dialogue.context()):
				others += 1
		check(others > 0, "%s: после победы остались другие визиты" % pool_name)
		for language in ["ru", "en"]:
			I18n.apply(language)
			Dialogue.refresh_locale()
			var visits_ok := true
			for i in 10:
				var sample := Dialogue.visitor_lines()
				if sample.is_empty() or str(sample[0].get("id", "")) == line_id:
					visits_ok = false
			check(visits_ok, "%s/%s: выбор других визитов работает после победы" % [pool_name, language])
	Dialogue.pools = saved_pools
	TranslationServer.set_locale(saved_locale)
	Dialogue.refresh_locale()
	Save.reset()

## Хеймдалль знакомится и при победах без смертей, но о смерти говорит только после неё.
func _test_heimdall_visit_history() -> void:
	print("-- Хеймдалль и история смертей")
	var saved_pools: Dictionary = Dialogue.pools
	var saved_locale := TranslationServer.get_locale()
	var pool_name := "heimdall.visit"
	var line_id := "heimdall.visit.01_01"
	var target: Dictionary = {}
	for item in saved_pools.get(pool_name, []):
		if str(item.lines[0].get("id", "")) == line_id:
			target = item
			break
	check(not target.is_empty(), "реплика Хеймдалля найдена")
	if target.is_empty():
		return
	var loc_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues/en/heimdall.json"))
	var loc_lines: Dictionary = (loc_data as Dictionary).get("lines", {}) if loc_data is Dictionary else {}
	var translation: Dictionary = loc_lines.get(line_id, {})
	var one_pool := {}
	one_pool[pool_name] = [target]
	Dialogue.pools = one_pool
	Save.reset()
	for i in 2:
		Save.begin_run("berserker")
		Save.end_run({"won": true, "rooms": 7})
	Save.begin_run("berserker")
	Save.bump_event("run_start")
	check(Dialogue.pick_scene("run_start").get("id", "") == "heimdall_intro", "знакомство возможно в третьем забеге без смертей")
	Save.mark_seen("heimdall_intro")
	Save.end_run({"won": true, "rooms": 7})
	check(Save.deaths() == 0, "три победы не засчитываются как смерти")
	for language in ["ru", "en"]:
		I18n.apply(language)
		Dialogue.refresh_locale()
		check(Dialogue.visitor_lines().is_empty(), "%s: Хеймдалль не говорит о неслучившейся смерти" % language)
	var full_pool := {}
	full_pool[pool_name] = saved_pools[pool_name]
	Dialogue.pools = full_pool
	for language in ["ru", "en"]:
		I18n.apply(language)
		Dialogue.refresh_locale()
		var other_visit := Dialogue.visitor_lines()
		check(not other_visit.is_empty() and str(other_visit[0].get("id", "")) != line_id,
			"%s: остальные визиты Хеймдалля доступны без смертей" % language)
	Dialogue.pools = one_pool
	Save.begin_run("berserker")
	Save.end_run({"won": false, "cause": "draugr", "rooms": 1})
	for language in ["ru", "en"]:
		I18n.apply(language)
		Dialogue.refresh_locale()
		var visit := Dialogue.visitor_lines()
		var shown: Dictionary = visit[0] if not visit.is_empty() else {}
		var expected := str(target.lines[0].text) if language == "ru" else str(translation.get("en", ""))
		check(shown.get("id", "") == line_id and shown.get("text", "") == expected and expected != "",
			"%s: после первой смерти реплика доступна на выбранном языке" % language)
	Save.begin_run("berserker")
	Save.end_run({"won": true, "rooms": 7})
	for language in ["ru", "en"]:
		I18n.apply(language)
		Dialogue.refresh_locale()
		var visit := Dialogue.visitor_lines()
		check(not visit.is_empty() and str(visit[0].get("id", "")) == line_id,
			"%s: после победы реплика о прошлой смерти остаётся доступна" % language)
	Save.reset()
	Save.end_run({"won": false, "cause": "draugr", "rooms": 1})
	check(Dialogue.visitor_lines().is_empty(), "смерть не обходит условие знакомства")
	Dialogue.pools = saved_pools
	TranslationServer.set_locale(saved_locale)
	Dialogue.refresh_locale()
	Save.reset()

## Имя Ярла в реакции соответствует точному источнику урона, а не общей категории boss.
func _test_boss_death_reactions() -> void:
	print("-- Реакции на Свена и Ярла")
	var saved_pools: Dictionary = Dialogue.pools
	var saved_locale := TranslationServer.get_locale()
	var saved_body_chance := Dialogue.body_death_chance
	Dialogue.body_death_chance = 0.0
	var boss_items: Array = saved_pools.get("odin.death_boss", [])
	var jarl_ids := ["odin.death_boss.01", "odin.death_boss.03", "odin.death_boss.06"]
	var loc_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues/en/odin.json"))
	var loc_lines: Dictionary = (loc_data as Dictionary).get("lines", {}) if loc_data is Dictionary else {}
	for source_id in ["miniboss_sven", "boss_jarl"]:
		Save.reset()
		Dialogue.pools = saved_pools
		# Настоящий сигнал Player проходит через RunTracker, который сохраняет результат.
		# Узлы вне сцены: после сигнала player отключён, чтобы не читать global_position вне дерева.
		var actor := Player.new()
		var tracker := RunTracker.new()
		tracker.player = actor
		tracker.run_time = 60.0
		actor.hurt.connect(tracker._on_hurt)
		var attacker := Node.new()
		attacker.set_meta("death_source_id", source_id)
		RunTracker.note_hit(attacker)
		actor.hurt.emit(1.0)
		tracker.player = null
		var result := tracker.finish(false)
		check(result.get("cause", "") == "boss" and result.get("killed_by", "") == source_id,
			"%s: записаны общая категория и точный источник" % source_id)
		Save.load_game()
		check(Dialogue.context().get("killed_by", "") == source_id, "%s: источник дошёл из сохранения в контекст" % source_id)
		check(Dialogue.reaction_pool(false) == "odin.death_boss", "%s: выбран общий пул смерти от босса" % source_id)
		var named := 0
		var generic := 0
		for item in boss_items:
			var id := str(item.lines[0].get("id", ""))
			var allowed := Dialogue.check(item._conds, Dialogue.context())
			if id in jarl_ids:
				named += 1
				check(allowed == (source_id == "boss_jarl"), "%s: %s доступна только для Ярла" % [source_id, id])
				var single_pool := {}
				single_pool["odin.death_boss"] = [item]
				Dialogue.pools = single_pool
				for language in ["ru", "en"]:
					I18n.apply(language)
					Dialogue.refresh_locale()
					var lines := Dialogue.pool_lines("odin.death_boss")
					var translation: Dictionary = loc_lines.get(id, {})
					var expected := str(item.lines[0].text) if language == "ru" else str(translation.get("en", ""))
					var valid := lines.is_empty() if source_id == "miniboss_sven" else \
						(not lines.is_empty() and lines[0].get("id", "") == id and lines[0].get("text", "") == expected and expected != "")
					check(valid, "%s/%s: выбор и перевод %s" % [source_id, language, id])
			elif allowed:
				generic += 1
		check(named == jarl_ids.size() and generic > 0, "%s: три реплики Ярла и общие варианты на месте" % source_id)
		Dialogue.pools = saved_pools
		for language in ["ru", "en"]:
			I18n.apply(language)
			Dialogue.refresh_locale()
			var samples_ok := true
			for i in 20:
				var lines := Dialogue.pool_lines("odin.death_boss")
				if lines.is_empty() or (source_id == "miniboss_sven" and str(lines[0].get("id", "")) in jarl_ids):
					samples_ok = false
			check(samples_ok, "%s/%s: случайная выборка не пуста и соответствует боссу" % [source_id, language])
		attacker.free()
		actor.free()
		tracker.free()
	Dialogue.pools = saved_pools
	Dialogue.body_death_chance = saved_body_chance
	TranslationServer.set_locale(saved_locale)
	Dialogue.refresh_locale()
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
	for pair in [["loki_intro", []], ["ravens_gossip", ["loki_intro"]], ["loki_reveal", ["loki_intro", "ravens_gossip"]],
			["dwarves_secret", ["dwarves_intro"]]]:
		Save.reset()
		Save.data.stats.deaths = 5 if pair[0] == "loki_intro" else 14
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

## Альтернативная встреча и её визиты не пересекаются с обычным знакомством Локи.
func _test_loki_finale_branches() -> void:
	print("-- Локи после раннего финала")
	Save.reset()
	Save.data.stats.deaths = 5
	var alternate: Dictionary = {}
	for sc in Dialogue.scenes:
		if sc.get("id", "") == "loki_intro_after_finale":
			alternate = sc
			break
	check(not alternate.is_empty() and alternate.get("draft", false), "альтернативная сцена существует и остаётся черновиком")
	if alternate.is_empty():
		return
	var post_pool: Array = Dialogue.pools.get("loki.post_finale.visit", [])
	check(post_pool.size() == 3, "в альтернативном пуле три реплики")
	var ids := {}
	var repeated: Array[String] = []
	var new_lines: Array = alternate.lines.duplicate()
	for item in post_pool:
		check(item.get("draft", false), "послефинальный визит остаётся черновиком")
		new_lines.append_array(item.lines)
	for line in new_lines:
		var id := str(line.get("id", ""))
		if id == "" or ids.has(id):
			repeated.append(id)
		ids[id] = true
	check(repeated.is_empty(), "у новых реплик нет пустых или повторных id")
	var translation: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues/en/loki.json"))
	var localized: Dictionary = (translation as Dictionary).get("lines", {}) if translation is Dictionary else {}
	for line in new_lines:
		var text: Dictionary = localized.get(str(line.id), {})
		check(text.get("ru", "") == line.text and str(text.get("en", "")).strip_edges() != "", "%s переведена на en" % line.id)
	check(not Dialogue.check(alternate._conds, Dialogue.context("death")), "альтернативная встреча недоступна до финала")
	check(Dialogue.pool_lines("loki.post_finale.visit").is_empty(), "новые визиты недоступны до финала")
	Save.mark_seen("finale_a")
	check(Dialogue.check(alternate._conds, Dialogue.context("death")), "финал без старого знакомства открывает альтернативную встречу")
	check(Dialogue.pool_lines("loki.post_finale.visit").is_empty(), "финал сам по себе не открывает новые визиты")
	for prerequisite in ["odin_first_death", "ravens_intro", "sif_intro"]:
		Save.mark_seen(prerequisite)
	check(Dialogue.pick_scene("death").get("id", "") == "loki_intro_after_finale", "сцена выбирается при следующем подходящем событии смерти")
	Save.mark_seen("loki_intro_after_finale")
	check(Dialogue.pick_scene("death").get("id", "") != "loki_intro_after_finale", "альтернативная встреча не повторяется")
	check(Dialogue.pool_lines("loki.visit").is_empty(), "прежние визиты не включаются без старого знакомства")
	var all_pools := Dialogue.pools
	Dialogue.pools = {"loki.post_finale.visit": post_pool}
	var visitor := Dialogue.visitor_lines()
	Dialogue.pools = all_pools
	check(not visitor.is_empty() and ids.has(str(visitor[0].get("id", ""))), "общий выбор визитов находит новый пул")
	Save.reset()
	Save.data.stats.deaths = 5
	Save.mark_seen("loki_intro")
	Save.mark_seen("finale_a")
	check(not Dialogue.check(alternate._conds, Dialogue.context("death")), "после обычного знакомства альтернативная сцена не выбирается")
	check(not Dialogue.pool_lines("loki.visit").is_empty(), "после обычного знакомства доступны прежние визиты")
	check(Dialogue.pool_lines("loki.post_finale.visit").is_empty(), "новый пул не дублирует прежние визиты")
	Save.mark_seen("loki_intro_after_finale")
	check(Dialogue.pool_lines("loki.post_finale.visit").is_empty(), "при двух отметках новый пул также не дублирует прежний")
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
