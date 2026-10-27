extends Node
## Локализация: переводы загружены (data/i18n/en.po), ключевые строки UI и данные (руны, трейты, оружие,
## тела, награды…) переводятся на en, подстановки (%d, %s) совпадают, нет пустых переводов; смена языка
## через GameSettings применяется сразу, сохраняется и перестраивает экраны; реплики Одина, воронов
## и боссов есть на en; шрифты с латиницей; в ui/*.gd нет русских литералов без tr().
## godot --headless --path . --fixed-fps 60 res://tests/i18n_test.tscn

const PO_PATH := "res://data/i18n/en.po"
## Пулы, которые обязаны быть переведены целиком
const REQUIRED_POOL_PREFIXES := ["odin.", "ravens.tutorial_", "jarl.intro", "jarl.defeat", "sven.intro", "sven.death",
	"hel.intro", "hel.defeat"]
## Строки, которым позволено совпадать с оригиналом (имена языков и т. п.)
const SAME_OK := ["Русский", "Язык / Language"]

var _fails: Array[String] = []
var _passes: int = 0
var game: Game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
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
		await get_tree().physics_frame

func set_lang(loc: String) -> void:
	GameSettings.set_value("text", "language", loc)

func _run() -> void:
	print("=== I18N TEST ===")
	check(GameSettings.path == GameSettings.TEST_PATH, "тесты пишут настройки в %s" % GameSettings.TEST_PATH)
	set_lang("ru")
	_test_loaded()
	_test_po_file()
	_test_switch()
	_test_data()
	_test_dialogues()
	_test_fonts()
	_test_literals()
	await _test_screens()
	await _test_game()
	set_lang("ru")
	_finish()

# --- Переводы загружены, русский по умолчанию ---

func _test_loaded() -> void:
	print("-- Загрузка")
	check("en" in TranslationServer.get_loaded_locales(), "перевод en загружен (%s)" % str(TranslationServer.get_loaded_locales()))
	check(ProjectSettings.get_setting("internationalization/locale/fallback", "") == "ru", "запасной язык — ru (нет перевода → русский)")
	check(I18n.locale() == "ru", "по умолчанию — русский (%s)" % TranslationServer.get_locale())
	check(tr("Назад") == "Назад" and I18n.t("ПАУЗА") == "ПАУЗА", "на ru ключи показываются как есть")
	check(GameSettings.DEFAULTS["text"]["language"] == "ru", "настройка по умолчанию — ru")

# --- Файл перевода: нет пустых, подстановки совпадают ---

func _po_entries() -> Dictionary:
	var out := {}
	var f := FileAccess.open(PO_PATH, FileAccess.READ)
	if f == null:
		return out
	var id := ""
	var cur := ""
	var mode := ""
	for raw in f.get_as_text().split("\n"):
		var l := raw.strip_edges()
		if l.begins_with("#") or l == "":
			continue
		if l.begins_with("msgid "):
			if mode == "str" and id != "":
				out[id] = cur
			id = l.substr(7, l.length() - 8).c_unescape()
			cur = ""
			mode = "id"
		elif l.begins_with("msgstr "):
			cur = l.substr(8, l.length() - 9).c_unescape()
			mode = "str"
		elif l.begins_with("\""):
			var part := l.substr(1, l.length() - 2).c_unescape()
			if mode == "id":
				id += part
			else:
				cur += part
	if mode == "str" and id != "":
		out[id] = cur
	return out

func _placeholders(s: String) -> Array:
	var re := RegEx.create_from_string("%(?:\\.\\d+|0\\d+)?[dsf%]")
	var out: Array = []
	for m in re.search_all(s):
		out.append(m.get_string())
	out.sort()
	return out

func _test_po_file() -> void:
	print("-- data/i18n/en.po")
	var e := _po_entries()
	check(e.size() >= 700, "ключей в en.po: %d" % e.size())
	var empty: Array = []
	var bad_ph: Array = []
	var cyr: Array = []
	var re_cyr := RegEx.create_from_string("[А-Яа-яЁё]")
	for k in e:
		var v: String = e[k]
		if v.strip_edges() == "":
			empty.append(k)
		elif _placeholders(k) != _placeholders(v):
			bad_ph.append(k)
		elif re_cyr.search(v) and not k in SAME_OK:
			cyr.append(k)
	check(empty.is_empty(), "нет пустых переводов%s" % ("" if empty.is_empty() else ": " + str(empty.slice(0, 5))))
	check(bad_ph.is_empty(), "подстановки %%d/%%s совпадают%s" % ("" if bad_ph.is_empty() else ": " + str(bad_ph.slice(0, 5))))
	check(cyr.is_empty(), "в английском нет кириллицы%s" % ("" if cyr.is_empty() else ": " + str(cyr.slice(0, 5))))
	var tr_res := load(PO_PATH) as Translation
	check(tr_res != null and tr_res.locale == "en", "en.po читается как Translation (локаль %s)" % (tr_res.locale if tr_res else "—"))
	if tr_res:
		var multi := "Тело: %s\nСлава: %d\nУбито врагов: %d\nЛучшая серия: %d\nПройдено залов: %d из %d\nРун собрано: %d"
		check(str(tr_res.get_message(multi)).begins_with("Body: %s\nGlory"), "многострочные ключи (\\n) читаются")

# --- Смена языка через настройки ---

func _test_switch() -> void:
	print("-- Смена языка")
	var changed := [0]
	var cb := func(section: String, key: String) -> void:
		if section == "text" and key == "language":
			changed[0] += 1
	GameSettings.events.changed.connect(cb)
	set_lang("en")
	check(I18n.locale() == "en", "GameSettings → TranslationServer.set_locale(en) сразу")
	check(changed[0] == 1, "сигнал GameSettings.events.changed(text, language)")
	check(tr("Назад") == "Back" and tr("Настройки") == "Settings" and tr("Начать забег") == "Start Run", "кнопки меню на en")
	check(I18n.t("ПАУЗА") == "PAUSE", "I18n.t в статических функциях")
	check(tr("СЛАВА %d") % 42 == "GLORY 42", "строки с подстановкой: «%s»" % (tr("СЛАВА %d") % 42))
	check(tr("Строка, которой нет в переводе") == "Строка, которой нет в переводе", "нет перевода → русский")
	check(GameSettings.binding_label("mouse:1") == "LMB" and GameSettings.binding_label("key:32") == "Space", "подписи клавиш на en")
	var cf := ConfigFile.new()
	check(cf.load(GameSettings.path) == OK and str(cf.get_value("text", "language", "")) == "en", "язык сохранён в settings.cfg [text] language")
	GameSettings.set_value("text", "language", "xx")
	check(GameSettings.language() == "ru" and I18n.locale() == "ru", "неизвестный язык → ru")
	set_lang("en")
	TranslationServer.set_locale("ru")
	GameSettings.apply_startup()
	check(I18n.locale() == "en", "apply_startup применяет язык из настроек")
	GameSettings.events.changed.disconnect(cb)

# --- Данные переводятся при показе ---

func _need(s: String, where: String, miss: Array) -> void:
	if s.strip_edges() == "" or not RegEx.create_from_string("[А-Яа-яЁё]").search(s):
		return
	if tr(s) == s:
		miss.append("%s: «%s»" % [where, s])

func _test_data() -> void:
	print("-- Данные (en)")
	var miss: Array = []
	var n := 0
	for r in Run.all_runes:
		var rd := r as RuneDef
		_need(rd.title, "руна " + rd.id, miss)
		_need(rd.description, "руна " + rd.id, miss)
		for d in rd.level_descriptions:
			_need(d, "руна " + rd.id, miss)
		n += 1
	check(n >= 25, "рун проверено: %d" % n)
	var rune := Run.rune_def("max_health")
	check(rune != null and tr(rune.title) == "Idunn's Apple", "руна: «%s»" % (tr(rune.title) if rune else "—"))
	n = 0
	for p in _files("res://weapons/mjolnir_traits/", "tres") + _files("res://weapons/mjolnir_traits/combos/", "tres"):
		var t := load(p) as MjolnirTrait
		if t:
			for s in [t.title, t.description, t.description_lvl2, t.description_lvl3, t.description_lvl4, t.group]:
				_need(s, "трейт " + str(t.id), miss)
			n += 1
	check(n >= 10, "трейтов проверено: %d" % n)
	n = 0
	for p in _files("res://weapons/defs/", "tres"):
		var w := load(p) as WeaponDef
		if w:
			_need(w.display_name, "оружие " + p.get_file(), miss)
			_need(w.description, "оружие " + p.get_file(), miss)
			n += 1
	check(n >= 10, "оружия проверено: %d" % n)
	var axe := load("res://weapons/defs/axe.tres") as WeaponDef
	check(axe != null and tr(axe.display_name) == "Axe", "оружие: «%s»" % (tr(axe.display_name) if axe else "—"))
	for b in Run.all_bodies:
		var bd := b as BodyDef
		for s in [bd.display_name, bd.description, bd.odin_comment]:
			_need(s, "тело " + bd.id, miss)
		for pd in [bd.passive, bd.flaw]:
			if pd:
				_need(pd.title, "пассивка " + bd.id, miss)
				_need(pd.description, "пассивка " + bd.id, miss)
				_need(pd.todo, "пассивка " + bd.id, miss)
	var dirs := {"res://run/unlocks/": ["title", "description", "odin_comment"], "res://run/rewards/": ["title", "description"],
		"res://run/shop/": ["title", "description"], "res://run/trials/": ["title", "condition"],
		"res://run/movement/": ["title", "description"], "res://enemies/defs/": ["title", "description"],
		"res://enemies/elite/mods/": ["title"], "res://run/passives/": ["title", "description"]}
	for dir in dirs:
		var cnt := 0
		for p in _files(dir, "tres"):
			var res := load(p)
			if res == null:
				continue
			cnt += 1
			for prop in dirs[dir]:
				var v: Variant = res.get(prop)
				if v is String:
					_need(v, p.trim_prefix("res://"), miss)
		check(cnt > 0, "%s: %d файлов" % [dir.trim_prefix("res://"), cnt])
	for p in _files("res://rooms/", "tscn"):
		var txt := FileAccess.get_file_as_string(p)
		var m := RegEx.create_from_string("room_title = \"([^\"]*)\"").search(txt)
		if m:
			_need(m.get_string(1), p.get_file(), miss)
	_need(JarlBoss.BOSS_TITLE, "полоса Ярла", miss)
	_need(MinibossDef.new().title, "полоса мини-босса", miss)
	check(miss.is_empty(), "все названия/описания данных переведены%s" % ("" if miss.is_empty() else ": " + str(miss.slice(0, 6))))

func _files(dir: String, ext: String) -> Array:
	var out: Array = []
	for f in ResourceLoader.list_directory(dir):
		if str(f).get_extension() == ext:
			out.append(dir + str(f))
	return out

# --- Диалоги ---

func _test_dialogues() -> void:
	print("-- Диалоги (en)")
	check(Dialogue.speakers.get("odin", {}).get("name", "") == "Odin", "имя говорящего на en: %s" % Dialogue.speakers.get("odin", {}).get("name", ""))
	var missing: Array = []
	var total := 0
	for pool in Dialogue.pools:
		var need := false
		for pre in REQUIRED_POOL_PREFIXES:
			if str(pool).begins_with(pre):
				need = true
		if not need:
			continue
		for it in Dialogue.pools[pool]:
			for l in it.lines:
				if l is Dictionary and l.has("id"):
					total += 1
					if not Dialogue.has_translation(str(l.id)):
						missing.append(str(l.id))
	check(total >= 150, "обязательных реплик (Один в бою, вороны, боссы): %d" % total)
	check(missing.is_empty(), "все переведены%s" % ("" if missing.is_empty() else ": " + str(missing.slice(0, 6))))
	var all := 0
	var done := 0
	for sc in Dialogue.scenes:
		for l in sc.get("lines", []):
			if l is Dictionary and l.has("id"):
				all += 1
				if Dialogue.has_translation(str(l.id)):
					done += 1
	check(all > 0 and done == all, "сцены-новеллы: %d / %d реплик на en" % [done, all])
	var t := Dialogue.pool_text("odin.idle")
	check(t != "" and not RegEx.create_from_string("[А-Яа-яЁё]").search(t), "Odin в бою на en: «%s»" % t)
	var lines := Dialogue.pool_lines("ravens.tutorial_jump")
	var tt := Tutorial.keys_in(str(lines[0].get("text", ""))) if not lines.is_empty() else ""
	check(tt.contains("Space") and not tt.contains("{key_"), "обучение воронов на en, клавиши подставлены: «%s»" % tt)
	var sc := {}
	for s in Dialogue.scenes:
		if s.get("id", "") == "odin_intro":
			sc = s
	var ex := Dialogue.expand(sc.get("lines", []))
	var choice_ok := false
	for l in ex:
		for ch in l.get("choices", []):
			if ch.get("id", "") == "snap":
				choice_ok = ch.get("label", "") == "Snap back" and not RegEx.create_from_string("[А-Яа-яЁё]").search(str(ch.get("text", "")))
	check(choice_ok, "выбор ответа Тора на en (подпись и текст)")
	var lr: Dictionary = Save.data.get("last_run", {}).duplicate(true)
	Save.data["last_run"] = {"killed_by": "draugr_warrior", "time": 75.0, "tags": []}
	check(RunTracker.describe_last_death() == "Killed by: draugr warrior · lasted 1:15", "причина смерти на en: «%s»" % RunTracker.describe_last_death())
	Save.data["last_run"] = lr
	set_lang("ru")
	check(Dialogue.speakers.get("odin", {}).get("name", "") == "Один", "обратно на ru — имена русские")
	var tr_ru := Dialogue.pool_text("odin.idle")
	check(RegEx.create_from_string("[А-Яа-яЁё]").search(tr_ru) != null, "обратно на ru — реплики русские: «%s»" % tr_ru)
	var errs := Dialogue.validate()
	check(errs.is_empty(), "данные диалогов без ошибок%s" % ("" if errs.is_empty() else ": " + str(errs.slice(0, 3))))
	set_lang("en")

# --- Шрифты ---

func _test_fonts() -> void:
	print("-- Шрифты")
	var latin := "AZaz09!?"
	for p in ["res://fonts/RussoOne-Regular.ttf", "res://fonts/Bangers-Regular.ttf"]:
		var f := load(p) as FontFile
		var ok := f != null
		if ok:
			for c in latin:
				ok = ok and f.has_char(c.unicode_at(0))
		check(ok, "латиница в %s" % p.get_file())
	var russo := load("res://fonts/RussoOne-Regular.ttf") as FontFile
	check(russo != null and russo.has_char("Ж".unicode_at(0)), "кириллица в RussoOne")

# --- В ui/*.gd нет русских литералов без tr() ---

func _test_literals() -> void:
	print("-- Литералы в ui/*.gd")
	var re_str := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"")
	var re_cyr := RegEx.create_from_string("[А-Яа-яЁё]")
	var re_wrap := RegEx.create_from_string("(\\btr|I18n\\.t|TranslationServer\\.translate)\\(\\s*$")
	var re_dev := RegEx.create_from_string("push_warning|push_error|print\\(|printerr|Perf\\.mark|@export")
	var bad: Array = []
	for f in ResourceLoader.list_directory("res://ui/"):
		if str(f).get_extension() != "gd":
			continue
		var depth := 0
		var no := 0
		for raw in FileAccess.get_file_as_string("res://ui/" + str(f)).split("\n"):
			no += 1
			var code := _strip_comment(raw)
			var st := code.strip_edges()
			var in_const := depth > 0 or st.begins_with("const ")
			if in_const:
				depth = maxi(0, depth + code.count("[") + code.count("{") + code.count("(") - code.count("]") - code.count("}") - code.count(")"))
				continue
			if st.begins_with("func ") or st.begins_with("static func ") or re_dev.search(code):
				continue
			for m in re_str.search_all(code):
				if re_cyr.search(m.get_string()) and not re_wrap.search(code.substr(0, m.get_start())):
					bad.append("%s:%d %s" % [f, no, m.get_string()])
	check(bad.is_empty(), "все русские строки ui/*.gd обёрнуты в tr()%s" % ("" if bad.is_empty() else ": " + str(bad.slice(0, 6))))

func _strip_comment(line: String) -> String:
	var in_str := false
	var esc := false
	for i in line.length():
		var c := line[i]
		if esc:
			esc = false
			continue
		if c == "\\":
			esc = true
		elif c == "\"":
			in_str = not in_str
		elif c == "#" and not in_str:
			return line.substr(0, i)
	return line

# --- Экраны перестраиваются при смене языка ---

func _find_text(n: Node, text: String) -> bool:
	if (n is Label and (n as Label).text == text) or (n is Button and (n as Button).text == text):
		return true
	for c in n.get_children():
		if _find_text(c, text):
			return true
	return false

func _test_screens() -> void:
	print("-- Экраны")
	set_lang("en")
	var sp := SettingsPanel.new()
	get_tree().root.add_child(sp)
	await wait(0.1)
	check(_find_text(sp, "SETTINGS") and _find_text(sp, "Sound"), "настройки на en")
	sp.show_tab(4)
	var opt: OptionButton = null
	for o in sp.find_children("*", "OptionButton", true, false):
		if str(o.get_meta("setting", "")) == "text/language":
			opt = o
	check(opt != null and opt.get_item_text(opt.selected) == "English", "пункт «Язык» во вкладке «Интерфейс»")
	if opt:
		var ru_idx := I18n.LOCALES.find("ru")
		opt.select(ru_idx)
		opt.item_selected.emit(ru_idx)
	await wait(0.1)
	check(I18n.locale() == "ru" and _find_text(sp, "НАСТРОЙКИ") and _find_text(sp, "Звук"), "смена языка из списка перестраивает экран настроек")
	check(sp._current == 4, "после перестройки открыта та же вкладка")
	sp.queue_free()
	var menu := (load("res://ui/main_menu.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(menu)
	await wait(0.1)
	check(_find_text(menu, "Начать забег"), "главное меню на ru")
	set_lang("en")
	await wait(0.1)
	check(_find_text(menu, "Start Run") and not _find_text(menu, "Начать забег"), "главное меню перестроилось на en")
	menu.queue_free()
	await wait(0.1)
	var bs := BodySelect.new()
	get_tree().root.add_child(bs)
	bs.open("Назад", "hunter")
	check(bs._stats_label.text.contains("runes 3"), "общий запас рун переведён в выборе тела")
	for pair in [["hunter", "1.67"], ["courier", "1.25"], ["berserker", "3.33"]]:
		bs.select(pair[0])
		check(bs._move_desc.text.contains(pair[1]) and bs._move_desc.text.contains("ground") and not bs._move_desc.text.contains("%s"),
			"%s: описание руны и её время переведены (%s)" % [pair[0], bs._move_desc.text])
	bs.close("")
	bs.queue_free()

# --- В бою: HUD, пауза, Один ---

func _test_game() -> void:
	print("-- Бой (en)")
	set_lang("ru")
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(1.0)
	game = get_tree().current_scene as Game
	if game == null:
		check(false, "сцена игры загрузилась")
		return
	game.room.set_physics_process(false)
	var hud := game.hud
	await wait(0.2)
	check(hud._room_label.text.begins_with("ЗАЛ"), "HUD на ru: «%s»" % hud._room_label.text)
	game.pause_menu.toggle()
	game.pause_menu.open_settings()
	await wait(0.1)
	set_lang("en")
	await wait(0.2)
	check(hud._room_label.text.begins_with("ROOM") and hud._room_label.text.contains("Barrel Hall"), "HUD перевёлся на лету: «%s»" % hud._room_label.text)
	check(hud._hammer_label.text.begins_with("MJOLNIR"), "подпись молота: «%s»" % hud._hammer_label.text)
	check(hud._body_label.text == "Body: Berserker", "тело в HUD: «%s»" % hud._body_label.text)
	check(_find_text(game.pause_menu._content, "PAUSE") and _find_text(game.pause_menu._content, "Continue"), "пауза перестроилась на en")
	check(is_instance_valid(game.pause_menu._settings) and _find_text(game.pause_menu._settings, "SETTINGS"), "настройки поверх паузы остались открыты и на en")
	game.pause_menu.toggle()
	await wait(0.1)
	Odin.reset_cooldown()
	var said := Odin.say("room_clear")
	check(said != "" and not RegEx.create_from_string("[А-Яа-яЁё]").search(said), "Один в бою на en: «%s»" % said)
	game.hud.toast(tr("ВЫБЕРИ ДВЕРЬ"))
	check(game.hud._toast_label.text == "CHOOSE A DOOR", "тост на en")
	var item := WeaponItem.create(load("res://weapons/defs/axe.tres"), 2)
	check(item.title() == "Axe +1", "название оружия в HUD: «%s»" % item.title())
	game.rune_pick.open(Run.random_rune_choices(3))
	await wait(0.1)
	check(_find_text(game.rune_pick, "THE NORNS OFFER A RUNE"), "выбор руны на en")
	get_tree().paused = false
	set_lang("ru")
	await wait(0.1)

func _finish() -> void:
	print("=== ИТОГ I18N: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("  FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
