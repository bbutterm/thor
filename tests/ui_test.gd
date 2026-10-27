extends Node
## Блок С: скин UI (манифест, стили, тема, карточки), HUD в бою (полосы реагируют на урон, щит, рывок,
## шкала стиля, Мьёльнир, индикаторы за экраном, шкала высоты), настройки (сохранение/чтение, применение
## к игроку), переназначение клавиш (сохраняется и применяется), экран настроек и журнал паузы.
## godot --headless --path . --fixed-fps 60 res://tests/ui_test.tscn

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

func _run() -> void:
	print("=== UI TEST ===")
	check(GameSettings.path == GameSettings.TEST_PATH, "тесты пишут настройки в %s" % GameSettings.TEST_PATH)
	GameSettings.reset_all()
	_test_skin()
	await _test_settings()
	_test_remap()
	await _test_hud()
	await _test_screens()
	GameSettings.reset_all()
	_finish()

func _test_skin() -> void:
	print("-- Манифест и скин")
	var ids := UISkin.ids()
	check(ids.size() >= 150, "манифест прочитан: %d id" % ids.size())
	var missing: Array = []
	for id in ids:
		if not ResourceLoader.exists(UISkin.path(id)):
			missing.append(id)
	check(missing.is_empty(), "все пути манифеста существуют%s" % ("" if missing.is_empty() else ": нет " + str(missing.slice(0, 5))))
	var bad: Array = []
	for id in ids:
		if UISkin.path(id).begins_with("res://sprites/ui/") and UISkin.texture(id) == null:
			bad.append(id)
	check(bad.is_empty(), "все текстуры UI грузятся%s" % ("" if bad.is_empty() else ": " + str(bad.slice(0, 5))))
	var nine := 0
	var nine_ok := 0
	for id in ids:
		if UISkin.entry(id).has("nine_slice"):
			nine += 1
			var sb := UISkin.stylebox(id, 0.3)
			if sb is SkinStyleBox and (sb as SkinStyleBox).mode == SkinStyleBox.Mode.NINE and sb.get_minimum_size().y > 0.0:
				nine_ok += 1
	check(nine >= 12 and nine_ok == nine, "9-slice стили строятся: %d / %d" % [nine_ok, nine])
	var btn := UISkin.stylebox("button_main_normal", 0.3) as SkinStyleBox
	check(btn != null and is_equal_approx(btn.slice.x, 180.0 * UISkin.src_to_tex("button_main_normal")), "поля кнопки — из манифеста (180 px исходника)")
	check(btn != null and btn.content_margin_top + btn.content_margin_bottom < 24.0 and btn.content_margin_left > 25.0,
		"масштаб 0.3: торцы ~%.0f px, поля сверху/снизу %.0f px" % [btn.content_margin_left if btn else 0.0, btn.content_margin_top if btn else 0.0])
	var k := UISkin.src_to_tex("weapon_axe")
	check(k > 0.0 and k <= 1.0, "иконки уменьшены импортом (size_limit): текстура/исходник = %.2f" % k)
	check(UISkin.rect("hud_hp_frame", "fill_rect") == Rect2(238, 79, 446, 49), "fill_rect полосы HP из манифеста")
	var th := UISkin.theme()
	check(th.get_stylebox("normal", "Button") is SkinStyleBox and th.get_stylebox("panel", "WoodPanel") is SkinStyleBox,
		"общая тема: кнопки и панели на картинках комплекта")
	check(th.get_type_variation_base("DangerButton") == &"Button" and th.has_icon("checked", "CheckBox") and th.has_stylebox("slider", "HSlider"),
		"тема: опасная кнопка, флажок, ползунок")
	var card := SkinCard.make("card_rune", 300.0, Color.CYAN)
	check(card.get_theme_stylebox("normal") is SkinStyleBox and (card.get_theme_stylebox("hover") as SkinStyleBox).overlay != null,
		"карточка руны: card_rune + рамка редкости при наведении")
	check(absf(card.custom_minimum_size.y - 300.0 * 522.0 / 390.0) < 1.0, "карточка масштабируется равномерно (%.0f×%.0f)" % [card.custom_minimum_size.x, card.custom_minimum_size.y])
	card.free()
	check(UISkin.weapon_icon("rifle") != null and UISkin.weapon_icon("axe") != null and UISkin.trait_icon("fire_trail") != null
		and UISkin.rune_category_icon("defense") != null and UISkin.rune_category_icon("mjolnir") != null,
		"иконки оружия, трейтов и категорий рун находятся по id")
	var b := UIStyle.button("Тест")
	check(b.get_theme_stylebox("normal") is SkinStyleBox and b.get_theme_stylebox("disabled") is SkinStyleBox, "UIStyle.button — на скине")
	b.free()

func _test_settings() -> void:
	print("-- Настройки: сохранение и чтение")
	GameSettings.set_value("audio", "music", 0.3)
	GameSettings.set_value("video", "fov", 102.0)
	GameSettings.set_value("controls", "invert_y", true)
	GameSettings.set_value("controls", "mouse_sensitivity", 1.5)
	GameSettings.set_value("hud", "crosshair", "circle")
	GameSettings.set_value("text", "typing_speed", 0.0)
	GameSettings.set_value("access", "aim_assist", true)
	GameSettings.set_value("video", "fov", 300.0)
	check(is_equal_approx(float(GameSettings.get_value("video", "fov")), GameSettings.FOV_MAX), "FOV ограничен 70–110")
	GameSettings.set_value("video", "fov", 102.0)
	var cf := ConfigFile.new()
	check(cf.load(GameSettings.path) == OK and is_equal_approx(float(cf.get_value("video", "fov", 0.0)), 102.0)
		and cf.get_value("controls", "invert_y", false) == true and str(cf.get_value("hud", "crosshair", "")) == "circle",
		"значения записаны в файл по секциям")
	cf.set_value("foreign", "x", 42)
	cf.save(GameSettings.path)
	GameSettings.set_value("audio", "sfx", 0.5)
	var cf2 := ConfigFile.new()
	cf2.load(GameSettings.path)
	check(int(cf2.get_value("foreign", "x", 0)) == 42, "чужие секции файла не стираются")
	GameSettings.values["video"]["fov"] = 85.0
	GameSettings.reload()
	check(is_equal_approx(float(GameSettings.get_value("video", "fov")), 102.0) and bool(GameSettings.get_value("controls", "invert_y"))
		and is_equal_approx(float(GameSettings.get_value("audio", "music")), 0.3) and GameSettings.typing_speed() == 0.0 and GameSettings.aim_assist(),
		"после перечитывания файла значения на месте")
	var sfx := AudioServer.get_bus_index("SFX")
	check(sfx >= 0 and absf(AudioServer.get_bus_volume_db(sfx) - linear_to_db(0.5)) < 0.1, "громкость эффектов — на шине SFX (%.1f дБ)" % (AudioServer.get_bus_volume_db(sfx) if sfx >= 0 else 0.0))
	check(absf(float(Music.get("user_volume_db")) - linear_to_db(0.3)) < 0.1, "громкость музыки передана Music")
	check(AudioServer.get_bus_index("Voice") >= 0, "шина Voice создана")
	GameSettings.set_value("access", "colorblind", "deuteranopia")
	await get_tree().process_frame
	var f := GameSettings.colorblind_filter()
	check(f != null and f.visible and int(((f.get_child(0) as ColorRect).material as ShaderMaterial).get_shader_parameter("mode")) == 2,
		"цветовая слепота: фильтр экрана включён (дейтеранопия)")
	GameSettings.set_value("access", "colorblind", "off")
	check(f == null or not f.visible, "фильтр выключается")

func _test_remap() -> void:
	print("-- Переназначение клавиш")
	GameSettings.reset_input()
	check("key:%d" % KEY_SPACE in GameSettings.bindings("jump"), "по умолчанию прыжок — Пробел")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_K
	GameSettings.rebind("jump", k)
	var press := InputEventKey.new()
	press.physical_keycode = KEY_K
	press.pressed = true
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	check(InputMap.event_is_action(press, "jump") and not InputMap.event_is_action(space, "jump"), "прыжок на K: K срабатывает, Пробел — нет")
	var pad_left := false
	for e in InputMap.action_get_events("jump"):
		if e is InputEventJoypadButton:
			pad_left = true
	check(pad_left, "кнопка геймпада у прыжка осталась")
	var cf := ConfigFile.new()
	cf.load(GameSettings.path)
	check(cf.get_value("input", "jump", []) == ["key:%d" % KEY_K], "клавиша сохранена в [input] settings.cfg")
	# «Перезапуск»: InputMap как в проекте, потом настройки читаются из файла
	InputMap.load_from_project_settings()
	check(InputMap.event_is_action(space, "jump"), "(после сброса InputMap прыжок снова на Пробеле)")
	GameSettings.reload()
	GameSettings.apply_input()
	check(InputMap.event_is_action(press, "jump") and not InputMap.event_is_action(space, "jump"), "после перезапуска K применяется из файла")
	var taken := GameSettings.rebind("dash", k)
	check(taken == "jump" and InputMap.event_is_action(press, "dash") and not InputMap.event_is_action(press, "jump"),
		"K на рывок — снята с прыжка (конфликт)")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_XBUTTON1
	GameSettings.rebind("throw", mouse)
	var mp := InputEventMouseButton.new()
	mp.button_index = MOUSE_BUTTON_XBUTTON1
	mp.pressed = true
	check(InputMap.event_is_action(mp, "throw") and GameSettings.action_label("throw") == "Мышь 4", "кнопка мыши на бросок Мьёльнира («%s»)" % GameSettings.action_label("throw"))
	GameSettings.reset_input()
	check(InputMap.event_is_action(space, "jump") and GameSettings.action_label("throw") == "ПКМ", "«Сбросить» — клавиши как в project.godot")

func _test_hud() -> void:
	print("-- HUD в бою")
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.6)
	game = get_tree().current_scene as Game
	game.room.set_physics_process(false)
	await wait(0.8)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	await wait(0.2)
	var p := game.player
	var hud := game.hud
	check(is_equal_approx(p.camera_fx.base_fov, 102.0) and p.invert_y and is_equal_approx(p.mouse_sensitivity, GameSettings.BASE_MOUSE_SENS * 1.5),
		"настройки применены к игроку: FOV 102, инверсия, чувствительность ×1.5")
	GameSettings.set_value("video", "shake", 0.25)
	p.camera_fx.trauma = 0.0
	p.camera_fx.add_trauma(0.4)
	check(is_equal_approx(p.camera_fx.trauma, 0.1), "тряска 25 %%: add_trauma(0.4) → %.2f" % p.camera_fx.trauma)
	GameSettings.set_value("video", "head_bob", false)
	check(not p.camera_fx.head_bob_enabled, "покачивание камеры выключается сразу")
	check(hud._hp_bar is SkinBar and is_equal_approx(hud._hp_bar.value, 1.0), "полоса HP на рамке комплекта, полная")
	var before: float = hud._hp_bar.value
	p.take_damage(40.0)
	await wait(0.1)
	check(hud._hp_bar.value < before - 0.1 and hud._hp_label.text.begins_with(str(int(ceil(p.health)))),
		"урон: полоса HP %.2f → %.2f, цифры «%s»" % [before, hud._hp_bar.value, hud._hp_label.text])
	check(hud._hp_bar._trail > hud._hp_bar.value, "след урона на полосе")
	Run.add_rune(Run.rune_def("sif_shield"))
	p.recalc_from_runes(Run)
	p.refill_shield()
	await wait(0.05)
	check(p.shield > 0.0 and hud._hp_bar.overlay > 0.0 and "⛨" in hud._hp_label.text, "щит Сиф поверх HP (%.0f)" % p.shield)
	p.dash_charges = 0
	p.dash_charges_changed.emit(0, p.dash_charges_max, 0.5)
	check(hud._dash_pips.size() == p.dash_charges_max and is_equal_approx(hud._dash_pips[0].fill, 0.5), "руны Мьёльнира на бойке, восстановление видно (%d)" % hud._dash_pips.size())
	var style_hud := hud.get_node_or_null("StyleHUD") as StyleHUD
	p.style.set_points(40.0)
	await wait(0.05)
	check(style_hud != null and style_hud._bar is SkinBar and absf(style_hud._bar.value - 0.4) < 0.01 and style_hud._rank_label.text == "Неплохо",
		"шкала стиля: 40 очков — 40 %%, «%s»" % (style_hud._rank_label.text if style_hud else ""))
	p.style.reset()
	check(hud._hammer_state == "hand", "Мьёльнир в руке")
	p.mjolnir.throw_hammer()
	await wait(0.05)
	check(hud._hammer_state == "out" and hud._hammer_label.text.begins_with("ЛЕТИТ"), "Мьёльнир летит: «%s»" % hud._hammer_label.text)
	var t := 0
	while hud._hammer_state != "stuck" and hud._hammer_state != "return" and t < 180:
		await get_tree().physics_frame
		t += 1
	check(hud._hammer_state in ["stuck", "return"], "Мьёльнир воткнулся / возвращается: %s" % hud._hammer_state)
	p.mjolnir.force_return_instant()
	await wait(0.05)
	check(hud._hammer_state == "cooldown" and hud._hammer_label.text.begins_with("ПЕРЕЗАРЯДКА"), "снова в руке, перезарядка броска: «%s»" % hud._hammer_label.text)
	p.mjolnir.reset_cooldown()
	await wait(0.05)
	check(hud._hammer_state == "hand", "перезарядка кончилась — «В РУКЕ»")
	var wh := hud.get_node_or_null("WeaponHUD") as WeaponHUD
	check(wh != null and wh._slots[0].icon != null and wh._slots[0].active, "слот мили: иконка оружия, активный")
	# Индикатор врага за спиной
	var e := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	game.add_child(e)
	var back := -p.get_aim_forward()
	back.y = 0
	e.global_position = p.global_position + back.normalized() * 6.0
	e.set_physics_process(false)
	await wait(0.1)
	check(hud._offscreen.shown.size() >= 1, "враг за спиной — индикатор на краю экрана")
	GameSettings.set_value("hud", "offscreen", false)
	await wait(0.05)
	check(hud._offscreen.shown.is_empty(), "индикаторы выключаются в настройках")
	GameSettings.set_value("hud", "offscreen", true)
	e.queue_free()
	# Шкала высоты удара-приземления
	p.global_position += Vector3.UP * 8.0
	p.velocity = Vector3.ZERO
	await wait(0.05)
	check(hud._slam_meter.visible and hud._slam_meter.value > 0.4, "в воздухе на 8 м — шкала высоты в рукояти (%.2f)" % hud._slam_meter.value)
	var t2 := 0
	while not p.is_on_floor() and t2 < 240:
		await get_tree().physics_frame
		t2 += 1
	await wait(0.05)
	check(not hud._slam_meter.visible, "на земле шкалы нет")
	GameSettings.set_value("hud", "crosshair", "cross")
	check(hud._crosshair.texture == UISkin.texture("crosshair_cross"), "прицел меняется из настроек")
	# Помощь в прицеливании: луч доводится до врага в конусе
	p.rotation_target.x = 0.0
	await wait(0.05)
	var e2 := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	game.add_child(e2)
	var fwd := p.get_aim_forward()
	fwd.y = 0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	# Точка прицеливания врага (центр +1.1 м) — на высоте глаз, чуть в стороне от прицела
	e2.global_position = p.get_aim_origin() + fwd * 8.0 + side * 0.4 - Vector3.UP * 1.1
	e2.set_physics_process(false)
	await wait(0.1)
	var origin := p.get_aim_origin()
	var aim := RangedWeapon.assisted_aim(p, origin, p.get_aim_forward(), 40.0, 6.0)
	var to_e := (e2.global_position + Vector3.UP * 1.1 - origin).normalized()
	var plain := p.get_aim_forward().dot(to_e)
	check(aim.dot(to_e) > 0.999 and plain < 0.999, "помощь в прицеливании доводит до врага в конусе 6° (%.4f → %.4f)" % [plain, aim.dot(to_e)])
	e2.queue_free()
	# Замедление при ударе-приземлении
	GameSettings.set_value("access", "slam_slowmo", true)
	p.global_position += Vector3.UP * 6.0
	await wait(0.05)
	p.call("_start_slam")
	await wait(0.05)
	check(is_equal_approx(Engine.time_scale, p.slam_assist_time_scale), "замедление при ударе-приземлении: время ×%.2f" % Engine.time_scale)
	GameSettings.set_value("access", "slam_slowmo", false)
	var t3 := 0
	while (p.is_slamming or Engine.time_scale < 0.99) and t3 < 300:
		await get_tree().physics_frame
		t3 += 1
	check(is_equal_approx(Engine.time_scale, 1.0), "выключили — время снова 1.0")

func _test_screens() -> void:
	print("-- Экраны")
	var sp := SettingsPanel.new()
	game.add_child(sp)
	await get_tree().process_frame
	check(sp.tab_count() == 6, "в настройках 6 вкладок")
	var keys := ["audio/master", "audio/music", "audio/sfx", "audio/voice", "controls/mouse_sensitivity", "controls/invert_y",
		"video/fov", "video/shake", "video/head_bob", "video/fullscreen", "video/vsync", "video/max_fps", "hud/crosshair",
		"hud/crosshair_size", "hud/crosshair_alpha", "comic/enabled", "comic/scale", "text/text_scale", "text/typing_speed",
		"access/colorblind", "access/aim_assist", "access/slam_slowmo"]
	var found := {}
	for c in sp.find_children("*", "Control", true, false):
		if c.has_meta("setting"):
			found[str(c.get_meta("setting"))] = true
	var miss: Array = []
	for k in keys:
		if not found.has(k):
			miss.append(k)
	check(miss.is_empty(), "все пункты GDD 22 есть на экране%s" % ("" if miss.is_empty() else ": нет " + str(miss)))
	var jump_btn := sp._key_buttons.get("jump") as Button
	check(jump_btn != null and jump_btn.text == "Пробел", "кнопка прыжка показывает «%s»" % (jump_btn.text if jump_btn else ""))
	sp._start_capture("jump", jump_btn)
	check(jump_btn.text.begins_with("нажми"), "клик — ждём клавишу")
	var j := InputEventKey.new()
	j.physical_keycode = KEY_J
	j.pressed = true
	sp.apply_capture(j)
	check(jump_btn.text == "J" and InputMap.event_is_action(j, "jump"), "нажата J — прыжок на J, подпись «%s»" % jump_btn.text)
	sp._reset_all()
	check(jump_btn.text == "Пробел" and is_equal_approx(float(GameSettings.get_value("video", "fov")), 85.0), "«Сбросить всё» — значения и клавиши по умолчанию")
	sp.close()
	await get_tree().process_frame
	game.pause_menu.toggle()
	await get_tree().process_frame
	check(game.pause_menu._journal.get_child_count() >= 2, "журнал рун и трейтов в паузе")
	game.pause_menu.open_settings()
	await get_tree().process_frame
	check(game.pause_menu._settings != null and is_instance_valid(game.pause_menu._settings), "настройки открываются из паузы")
	game.pause_menu.toggle()
	await get_tree().process_frame
	check(not is_instance_valid(game.pause_menu._settings) or game.pause_menu._settings.is_queued_for_deletion(), "выход из паузы закрывает настройки")
	game.rune_pick.open(Run.random_rune_choices(3))
	await get_tree().process_frame
	check(game.rune_pick._cards.get_child_count() == 3 and game.rune_pick._cards.get_child(0) is SkinCard, "выбор руны — карточки комплекта")
	game.rune_pick.visible = false
	get_tree().paused = false

func _finish() -> void:
	print("=== ИТОГ UI: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("  FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
