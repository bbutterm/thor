extends Node
## Тест сохранений и «Плана тренировок»: сохранить → загрузить → данные совпадают; миграция старых версий;
## покупка списывает Славу; закрытое оружие / руны / тела не выпадают; эффекты «навсегда» применяются к игроку.
## Пишет в отдельный файл user://save_test.json (настоящее сохранение не трогает).
## godot --headless --path . --fixed-fps 60 res://tests/save_test.tscn

const TEST_FILE := "user://save_test.json"

var _fails: Array[String] = []
var _passes: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "SaveRunner"
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

func _write(text: String) -> void:
	var f := FileAccess.open(TEST_FILE, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _run() -> void:
	print("=== SAVE TEST ===")
	check(Save.path != Save.DEFAULT_PATH, "тест не пишет в настоящее сохранение (%s)" % Save.path)
	Save.use_path(TEST_FILE)
	_test_roundtrip()
	_test_migration()
	_test_buy()
	_test_pools()
	await _test_permanent()
	await _test_screen()
	_finish()

func _test_roundtrip() -> void:
	print("-- Сохранить → загрузить")
	Save.reset()
	Save.begin_run("hunter")
	Save.end_run({"won": false, "cause": "fall", "killed_by": "fall", "time": 75.5, "rooms": 2, "glory": 340, "kills": 21, "best_streak": 9, "body": "hunter", "tags": []})
	Save.begin_run("berserker")
	Save.end_run({"won": true, "time": 610.0, "rooms": 5, "glory": 900, "kills": 60, "best_streak": 14, "body": "berserker", "tags": []})
	Save.mark_seen("odin_intro")
	Save.set_choice("odin_intro", "snap")
	Save.bump_event("death")
	check(Save.buy("belly") == "", "купили «Сбросил пузо»")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(Save.data))
	check(Save.save_game(), "сохранение записано")
	Save.data = {}
	check(Save.load_game(), "сохранение прочитано")
	# Версию сравниваем отдельно (миграция ставит её целым числом, JSON читает числа как float)
	var loaded := Save.data.duplicate(true)
	loaded.erase("version")
	snapshot.erase("version")
	var same := JSON.stringify(loaded, "", true) == JSON.stringify(snapshot, "", true)
	if not same:
		print("    было:  ", JSON.stringify(snapshot, "", true))
		print("    стало: ", JSON.stringify(Save.data, "", true))
	check(same, "данные совпадают после загрузки")
	check(Save.runs() == 2 and Save.deaths() == 1 and Save.wins() == 1, "счётчики: забеги 2, смерти 1, победы 1")
	check(Save.deaths_by("fall") == 1 and Save.killed_by_count("fall") == 1, "причина смерти: падение")
	check(Save.is_seen("odin_intro") and Save.get_choice("odin_intro") == "snap", "просмотренные сцены и выборы")
	check(Save.glory_bank() == 340 + 900 - 100, "накопленная Слава: %d" % Save.glory_bank())
	check(int(Save.data.records.best_glory) == 900 and int(Save.data.records.best_kills) == 60, "рекорды")
	check(float(Save.data.records.fastest_win) == 610.0, "рекорд быстрой победы")
	check(Save.is_unlocked("belly"), "открытие сохранилось")
	check(int(Save.data.version) == Save.CURRENT_VERSION, "версия формата %d" % Save.CURRENT_VERSION)
	# Испорченный файл
	_write("{ это не json")
	check(not Save.load_game(), "испорченный файл не ломает игру")
	check(Save.runs() == 0, "…и начинается чистое сохранение")
	check(FileAccess.file_exists(TEST_FILE + ".broken"), "копия испорченного файла отложена")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_FILE + ".broken"))

func _test_migration() -> void:
	print("-- Миграция")
	_write(JSON.stringify({"version": 1, "stats": {"runs": 7, "deaths": 6, "wins": 1, "boss_kills": 1, "kills": 300, "playtime": 1000.0},
		"deaths_by_cause": {"draugr": 6}, "killed_by": {}, "last_run": {}, "seen": {"odin_intro": 1}, "choices": {}, "events": {},
		"records": {"best_glory": 500}}))
	check(Save.load_game(), "читается сохранение версии 1")
	check(int(Save.data.version) == 2, "мигрировано до версии 2")
	check(Save.runs() == 7 and Save.deaths_by("draugr") == 6 and Save.is_seen("odin_intro"), "старые данные на месте")
	check(Save.glory_bank() == 0 and Save.data.unlocks.is_empty(), "новые поля v2 добавлены")
	check(int(Save.data.records.best_kills) == 0, "недостающие ключи дописаны")
	_write(JSON.stringify({"runs": 3, "deaths": 2}))
	Save.load_game()
	check(Save.runs() == 3 and Save.deaths() == 2 and int(Save.data.version) == 2, "сохранение без версии (v0) мигрировано")

func _test_buy() -> void:
	print("-- Покупки")
	Save.reset()
	check(Save.all_unlocks.size() >= 25, "открытий в run/unlocks: %d" % Save.all_unlocks.size())
	var ids := {}
	for u in Save.all_unlocks:
		check(u.id != "" and not ids.has(u.id) and u.title != "" and u.price > 0, "открытие %s: id, название, цена" % u.id)
		ids[u.id] = true
		check(u.requires == "" or Save.get_unlock(u.requires) != null, "требование %s существует" % u.id)
	Save.add_glory_bank(300)
	check(Save.buy("belly") == "", "покупка за 100")
	check(Save.glory_bank() == 200, "Слава списана: 300 → %d" % Save.glory_bank())
	check(Save.is_unlocked("belly"), "куплено отмечено")
	check(Save.buy("belly") == "owned", "повторно не купить")
	check(Save.glory_bank() == 200, "Слава не списана повторно")
	check(Save.buy("rune_slam_fire") == "", "руна в пул за 120")
	check(Save.buy("no_whining") == "no_glory", "не хватает Славы (80 < 150)")
	check(Save.glory_bank() == 80, "при отказе Слава цела")
	Save.add_glory_bank(1000)
	check(Save.buy("dwarf_lab") in ["requires", "soon"], "сначала нужен «Сундук Локи» (или оружия ещё нет)")
	check(Save.buy("catch") == "soon", "нереализованный перк не продаётся")
	check(Save.buy("nope") == "unknown", "неизвестное открытие")

func _test_pools() -> void:
	print("-- Пулы: закрытое не выпадает")
	Save.reset()
	check(not Save.is_in_pool("weapon", "spear"), "копьё закрыто на старте")
	check(not Save.is_in_pool("weapon", "smg"), "ПП закрыт (доп. цель открытия)")
	check(Save.is_in_pool("weapon", "axe") and Save.is_in_pool("weapon", "pistol"), "стартовое оружие открыто")
	check(not Save.is_in_pool("trait", "boomerang"), "трейт «Бумеранг» закрыт")
	check(Save.is_in_pool("trait", "chain_lightning"), "трейт без открытия — в пуле")
	Save.data.unlocks["spear"] = 1
	Save.data.unlocks["loki_chest"] = 1
	check(Save.is_in_pool("weapon", "spear") and Save.is_in_pool("weapon", "smg"), "после покупки — в пуле")
	Save.reset()
	var locked_seen := false
	for i in 300:
		for r in Run.random_rune_choices(3):
			if not Save.is_in_pool("rune", r.id):
				locked_seen = true
	check(not locked_seen, "закрытые руны не выпадают (300 выборов)")
	Save.data.unlocks["rune_slam_fire"] = 1
	var fire_seen := false
	for i in 300:
		for r in Run.random_rune_choices(3):
			if r.id == "slam_fire":
				fire_seen = true
	check(fire_seen, "купленная руна начала выпадать")
	var bodies_ok := true
	for i in 50:
		Run.start_run()
		bodies_ok = bodies_ok and Save.is_in_pool("body", Run.body.id)
	check(bodies_ok, "тело забега — только из открытых (50 стартов)")

func _test_permanent() -> void:
	print("-- Эффекты навсегда")
	Save.reset()
	for id in ["belly", "no_whining", "morning_jog"]:
		Save.data.unlocks[id] = 1
	var base: BodyDef
	for b in Run.all_bodies:
		if b.id == "berserker":
			base = b
	var boosted := Save.apply_permanent_to_body(base)
	check(boosted != base and is_equal_approx(boosted.max_health, base.max_health + 20.0), "+20 HP (%.0f)" % boosted.max_health)
	check(boosted.dash_charges == base.dash_charges + 1, "+1 рывок")
	check(is_equal_approx(boosted.move_speed, base.move_speed * 1.05), "скорость +5 %")
	check(Save.apply_permanent_to_body(boosted) == boosted, "не применяется дважды")
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.8)
	var game := get_tree().current_scene as Game
	check(game != null and is_equal_approx(game.player.max_health, 170.0), "игрок в забеге: 170 HP")
	check(game != null and game.player.dash_charges_max == base.dash_charges + 1, "игрок в забеге: %d рывка (тело + 1)" % (base.dash_charges + 1))
	game.player.recalc_from_runes(Run)
	check(is_equal_approx(game.player.max_health, 170.0), "после пересчёта рун бонус не пропал")
	# Слава забега уходит в копилку
	var bank := Save.glory_bank()
	Run.glory = 123
	game.player.take_damage(99999.0, Vector3.ZERO, true)
	await wait(2.0)
	check(Save.glory_bank() == bank + 123, "Слава забега добавлена в копилку (%d)" % Save.glory_bank())

func _test_screen() -> void:
	print("-- Экран «План тренировок»")
	var game := get_tree().current_scene as Game
	if game == null:
		check(false, "нет сцены игры")
		return
	Save.add_glory_bank(500)
	game.end_screen.restart_requested.emit()
	await wait(0.3)
	Dialogue.box().skip()
	await wait(0.3)
	var plan := game.get_node_or_null("TrainingPlan") as TrainingPlan
	check(plan != null and plan.visible, "экран открылся после диалога")
	if plan == null:
		return
	check(plan._cards.size() == Save.all_unlocks.size(), "все открытия на экране (%d)" % plan._cards.size())
	var btn := plan.card_button("kitchen_knife") if plan._cards.has("kitchen_knife") else null
	var buyable := ""
	for u in Save.all_unlocks:
		if Save.buy_block_reason(u.id) == "":
			buyable = u.id
			break
	check(buyable != "", "есть что купить (%s)" % buyable)
	var before := Save.glory_bank()
	var price := Save.get_unlock(buyable).price
	plan.card_button(buyable).pressed.emit()
	await wait(0.1)
	check(Save.glory_bank() == before - price and Save.is_unlocked(buyable), "покупка с экрана списала %d Славы" % price)
	check(plan.card_button(buyable).disabled, "купленное отмечено")
	check(plan._odin_text.text != "", "Один прокомментировал: «%s»" % plan._odin_text.text)
	check(btn == null or btn is Button, "кнопки карточек")
	var done := [false, false]
	plan.closed.connect(func(start: bool) -> void:
		done[0] = true
		done[1] = start)
	plan._fight_btn.pressed.emit()
	await wait(0.3)
	# Блок Л: после «В бой» — выбор тела
	var bs := game.get_node_or_null("BodySelect") as BodySelect
	check(bs != null and bs.visible, "после «В бой» — выбор тела")
	if bs:
		bs.choose(bs.selected.id)
	await wait(1.0)
	check(done[0] and done[1], "«В бой» закрывает экран")
	var g2 := get_tree().current_scene as Game
	check(g2 != null and g2 != game and not get_tree().paused, "начался новый забег")

func _finish() -> void:
	print("=== ИТОГ: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	Save.path = Save.TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_FILE))
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
