extends Node
## Настройки геймпада и фактическая навигация фокусом через синтетические кнопки.
## godot --headless --path . --fixed-fps 60 res://tests/gamepad_test.tscn
## Это не заменяет проверку физического Steam Deck и конкретных драйверов.

var failures: Array[String] = []
var passes := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	if ok:
		passes += 1
		print("  [OK] ", description)
	else:
		failures.append(description)
		print("  [FAIL] ", description)

func frames(count: int = 3) -> void:
	for i in count:
		await get_tree().process_frame

func pad_press(button: JoyButton) -> void:
	var down := InputEventJoypadButton.new()
	down.device = 0
	down.button_index = button
	down.pressed = true
	Input.parse_input_event(down)
	await frames(2)
	var up := InputEventJoypadButton.new()
	up.device = 0
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)

func _run() -> void:
	print("=== GAMEPAD TEST ===")
	await frames()
	Save.use_path("user://gamepad_test_save.json")
	Save.reset()
	GameSettings.reset_all()
	_test_bindings()
	await _test_settings_capture()
	await _test_settings_rebuild_focus()
	await _test_card_choices()
	await _test_trait_reroll_focus()
	await _test_dialogue()
	await _test_dialogue_deferred_focus()
	await _test_body_and_training()
	await _test_main_menu_and_shop()
	GameSettings.reset_all()
	GameSettings._gamepad_active = false
	get_tree().paused = false
	print("RESULT: %d OK / %d FAIL" % [passes, failures.size()])
	for f in failures:
		print("  FAIL: ", f)
	get_tree().quit(1 if not failures.is_empty() else 0)

func _test_bindings() -> void:
	print("-- Сохранение и независимость устройств")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	GameSettings.rebind("jump", key)
	var rb := InputEventJoypadButton.new()
	rb.device = 0
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	var removed := GameSettings.rebind_pad("jump", rb)
	check(removed == "attack" and InputMap.event_is_action(rb, "jump") and not InputMap.event_is_action(rb, "attack"),
		"назначение RB переносит кнопку с удара на прыжок")
	check(GameSettings.bindings("jump") == ["key:%d" % KEY_K], "переназначение геймпада не меняет клавиатуру")
	var cf := ConfigFile.new()
	cf.load(GameSettings.path)
	check(cf.get_value("pad_input", "jump", []) == ["pad_button:%d" % JOY_BUTTON_RIGHT_SHOULDER], "кнопка записана в отдельную секцию")
	InputMap.load_from_project_settings()
	GameSettings.reload()
	GameSettings.apply_input()
	check(InputMap.event_is_action(rb, "jump") and GameSettings.bindings("jump") == ["key:%d" % KEY_K], "оба набора восстанавливаются после перечитывания")
	var axis := InputEventJoypadMotion.new()
	axis.device = 0
	axis.axis = JOY_AXIS_RIGHT_X
	axis.axis_value = -0.9
	removed = GameSettings.rebind_pad("move_forward", axis)
	check(removed == "camera_left" and InputMap.event_is_action(axis, "move_forward") and not InputMap.event_is_action(axis, "camera_left"),
		"направление оси назначается и убирается только из конфликтующего действия")
	var other_direction := InputEventJoypadMotion.new()
	other_direction.device = 0
	other_direction.axis = JOY_AXIS_RIGHT_X
	other_direction.axis_value = 0.9
	check(InputMap.event_is_action(other_direction, "camera_right"), "противоположное направление оси не потеряно")
	var weak := InputEventJoypadMotion.new()
	weak.axis = JOY_AXIS_LEFT_X
	weak.axis_value = 0.3
	check(GameSettings.event_to_string(weak) == "", "слабое движение стика не захватывается")
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	var before := GameSettings.pad_bindings("jump")
	GameSettings.rebind_pad("jump", start)
	check(GameSettings.pad_bindings("jump") == before, "Start зарезервирован для паузы и отмены")
	GameSettings.note_input(rb)
	check(GameSettings.using_gamepad() and GameSettings.current_binding("jump") == "RB" and Tutorial.key_name("jump") == "RB",
		"обучение и подсказки показывают кнопку активного геймпада")
	key.pressed = true
	GameSettings.note_input(key)
	check(not GameSettings.using_gamepad() and GameSettings.current_binding("jump") == "K", "после клавиатуры показывается её текущая привязка")
	GameSettings.reset_pad_input()
	check(GameSettings.pad_action_label("jump") == "A" and GameSettings.bindings("jump") == ["key:%d" % KEY_K], "сброс геймпада не сбрасывает клавиатуру")
	GameSettings.reset_input()

func _test_settings_capture() -> void:
	print("-- Экран настроек")
	var panel := SettingsPanel.new()
	get_tree().root.add_child(panel)
	await frames()
	var frames_found := panel.find_children("*", "PanelContainer", true, false)
	var window: PanelContainer
	for candidate in frames_found:
		if (candidate as Control).custom_minimum_size.x >= 980.0:
			window = candidate as PanelContainer
			break
	if window:
		var bounds := window.get_global_rect()
		var viewport := panel.get_viewport_rect()
		check(bounds.position.x >= 0.0 and bounds.position.y >= 0.0 and bounds.end.x <= viewport.size.x and bounds.end.y <= viewport.size.y,
			"рамка настроек помещается в viewport %s (%s)" % [viewport.size, bounds])
	else:
		check(false, "найдена рамка настроек")
	panel.show_tab(2)
	await frames()
	var b := panel._pad_buttons["jump"] as Button
	check(b != null and b.text == "A", "у действия есть независимая кнопка геймпада")
	panel._start_capture("jump", b, true)
	await pad_press(JOY_BUTTON_RIGHT_SHOULDER)
	check(panel._capture_action == "" and b.text == "RB" and GameSettings.pad_action_label("jump") == "RB", "экран принимает нажатие геймпада")
	var attack := panel._pad_buttons["attack"] as Button
	check(attack.text == "—" and not attack.disabled, "действие, потерявшее кнопку из-за конфликта, остаётся доступным для назначения")
	panel._start_capture("jump", b, true)
	await pad_press(JOY_BUTTON_START)
	check(panel._capture_action == "" and b.text == "RB", "Start отменяет ожидание без потери настройки")
	panel._start_capture("attack", attack, true)
	await pad_press(JOY_BUTTON_X)
	check(attack.text == "X" and b.text == "RB" and not attack.disabled, "действие без кнопки назначается заново, первая привязка сохраняется")
	panel.close()
	await frames()
	GameSettings.reset_pad_input()

## Несколько обновлений локали могут перестроить одни и те же кнопки за кадр.
func _test_settings_rebuild_focus() -> void:
	print("-- Фокус после смены языка")
	var panel := SettingsPanel.new()
	get_tree().root.add_child(panel)
	await frames()
	panel.show_tab(4)
	GameSettings.set_value("text", "language", "en")
	GameSettings.set_value("text", "language", "ru")
	await frames(6)
	check(GameSettings.language() == "ru" and panel._current == 4, "после двух смен языка открыта та же вкладка")
	check(get_viewport().gui_get_focus_owner() == panel._tab_buttons[4], "фокус перенесён на актуальную кнопку вкладки")
	await pad_press(JOY_BUTTON_B)
	check(not is_instance_valid(panel), "после перестроения настройки закрываются кнопкой B")
	await frames()

func _test_card_choices() -> void:
	print("-- Карточки рун, приёмов и наград")
	Run.start_run("berserker")
	var rp := RunePick.new()
	get_tree().root.add_child(rp)
	await frames()
	var runes: Array[RuneDef] = []
	runes.assign(Run.all_runes.slice(0, 2))
	var picked_rune: Array = [null]
	rp.picked.connect(func(r: RuneDef) -> void: picked_rune[0] = r)
	rp.open(runes)
	rp._open_time = -10.0
	await frames()
	check(get_viewport().gui_get_focus_owner() == rp._cards.get_child(0), "первой руне передан фокус")
	await pad_press(JOY_BUTTON_A)
	check(picked_rune[0] == runes[0] and not rp.visible, "руна выбирается кнопкой A")
	rp.queue_free()
	await frames()
	var tp := TraitPick.new()
	get_tree().root.add_child(tp)
	await frames()
	var traits: Array[MjolnirTrait] = []
	traits.assign(Run.all_mjolnir_traits.slice(0, 2))
	var picked_trait: Array = [null]
	tp.picked.connect(func(t: MjolnirTrait) -> void: picked_trait[0] = t)
	tp.open(traits)
	tp._open_time = -10.0
	await frames()
	check(get_viewport().gui_get_focus_owner() == tp._cards.get_child(0), "первому приёму передан фокус")
	await pad_press(JOY_BUTTON_DPAD_RIGHT)
	check(get_viewport().gui_get_focus_owner() == tp._cards.get_child(1), "D-pad переводит фокус на вторую карточку")
	await pad_press(JOY_BUTTON_A)
	check(picked_trait[0] == traits[1] and not tp.visible, "второй приём выбирается кнопкой A")
	tp.queue_free()
	await frames()
	var cp := ChoicePick.new()
	get_tree().root.add_child(cp)
	await frames()
	var picked_choice := [""]
	cp.picked.connect(func(id: String) -> void: picked_choice[0] = id)
	cp.open("Выбор", "", [{"id": "disabled", "enabled": false}, {"id": "enabled"}])
	cp._open_time = -10.0
	await frames()
	check(get_viewport().gui_get_focus_owner() == cp._cards.get_child(1), "фокус пропускает недоступную награду")
	await pad_press(JOY_BUTTON_A)
	check(picked_choice[0] == "enabled" and not cp.visible, "награда выбирается кнопкой A")
	cp.queue_free()
	await frames()

## Переброс по R в кадре появления карточек заменяет старые, не ломая фокус.
func _test_trait_reroll_focus() -> void:
	print("-- Фокус после переброса трейтов")
	var picker := TraitPick.new()
	get_tree().root.add_child(picker)
	await frames()
	var game := Game.new()
	game.trait_pick = picker
	var flow := RewardFlow.new()
	flow.game = game
	picker.reroll_requested.connect(flow._on_trait_reroll)
	var initial: Array[MjolnirTrait] = [load("res://weapons/mjolnir_traits/fire.tres") as MjolnirTrait]
	var old_rerolls := Run.trait_rerolls
	Run.trait_rerolls = 1
	picker.open(initial)
	var old_card := picker._cards.get_child(0)
	var event := InputEventAction.new()
	event.action = "reload"
	event.pressed = true
	picker._unhandled_input(event)
	check(Run.trait_rerolls == 0 and not old_card.is_inside_tree(), "переброс сразу заменил старую карточку")
	await frames()
	check(picker._cards.get_child_count() > 0 and (picker._cards.get_child(0) as Button).has_focus(),
		"после отложенного фокуса выбрана новая карточка")
	var selected: Array[MjolnirTrait] = []
	picker.picked.connect(func(t: MjolnirTrait) -> void: selected.append(t))
	picker._open_time = -10.0
	await pad_press(JOY_BUTTON_A)
	check(selected.size() == 1 and not picker.visible, "геймпад подтверждает новую карточку после переброса")
	Run.trait_rerolls = old_rerolls
	picker.queue_free()
	flow.free()
	game.free()
	get_tree().paused = false
	await frames()

func _test_dialogue() -> void:
	print("-- Диалог")
	var box := DialogueBox.new()
	get_tree().root.add_child(box)
	await frames()
	box.open_guard = 0.0
	box.chars_per_second = 1.0
	box.open([
		{"id": "pad_line", "speaker": "odin", "text": "Длинная реплика."},
		{"id": "pad_choice", "speaker": "odin", "text": "Выбор.", "choices": [
			{"id": "first", "label": "Первый", "text": "Первый ответ", "lines": []},
			{"id": "second", "label": "Второй", "text": "Второй ответ", "lines": []},
		]},
	], "pad_test")
	await frames()
	await pad_press(JOY_BUTTON_A)
	check(not box._typing and box._index == 0, "A допечатывает реплику")
	await pad_press(JOY_BUTTON_A)
	check(box._index == 1, "A переходит к следующей реплике")
	await pad_press(JOY_BUTTON_A)
	await frames()
	check(box._waiting_choice and get_viewport().gui_get_focus_owner() == box._choices_box.get_child(0), "ответы получают начальный фокус")
	box._log_text.clear()
	for i in 35:
		box._log_append({"name": "Один"}, Color.WHITE, "Реплика журнала %d." % i)
	await pad_press(JOY_BUTTON_BACK)
	await frames(10)
	var bar := box._log_text.get_v_scroll_bar()
	bar.value = 0.0
	await pad_press(JOY_BUTTON_A)
	check(box._waiting_choice and box._log_panel.visible, "A в открытом журнале не выбирает ответ под ним")
	var one := InputEventKey.new()
	one.physical_keycode = KEY_1
	one.pressed = true
	Input.parse_input_event(one)
	await frames()
	one.pressed = false
	Input.parse_input_event(one)
	check(box._waiting_choice and box._log_panel.visible, "клавиша 1 также не выбирает ответ под журналом")
	var axis := InputEventJoypadMotion.new()
	axis.device = 0
	axis.axis = JOY_AXIS_RIGHT_Y
	axis.axis_value = 1.0
	Input.parse_input_event(axis)
	await frames(30)
	axis.axis_value = 0.0
	Input.parse_input_event(axis)
	check(bar.value > 0.0, "правый стик прокручивает журнал")
	await pad_press(JOY_BUTTON_B)
	check(not box._log_panel.visible and box._waiting_choice, "B закрывает журнал, не меняя ответ")
	await pad_press(JOY_BUTTON_DPAD_DOWN)
	check(get_viewport().gui_get_focus_owner() == box._choices_box.get_child(1), "D-pad выбирает второй ответ")
	await pad_press(JOY_BUTTON_A)
	check(not box._waiting_choice and box._text.text == "Второй ответ", "A подтверждает второй ответ")
	await pad_press(JOY_BUTTON_BACK)
	check(box._log_panel.visible, "View открывает журнал")
	await pad_press(JOY_BUTTON_B)
	check(not box._log_panel.visible, "B закрывает журнал")
	await pad_press(JOY_BUTTON_Y)
	check(not box.visible, "Y пропускает диалог")
	box.queue_free()
	await frames()

## Отложенный фокус не должен обращаться к ответу, удалённому в тот же кадр.
func _test_dialogue_deferred_focus() -> void:
	print("-- Фокус удалённого ответа")
	var box := DialogueBox.new()
	get_tree().root.add_child(box)
	await frames()
	var lines := [{"id": "focus_choice", "speaker": "odin", "text": "Выбор.", "choices": [
		{"id": "first", "label": "Первый", "text": "Ответ", "lines": []},
		{"id": "second", "label": "Второй", "text": "Ответ 2", "lines": []},
	]}]
	box.open(lines, "focus_test", "none")
	box._finish_typing()
	var first := box._choices_box.get_child(0) as Button
	check(first.is_inside_tree(), "ответ добавлен до выбора")
	box.choose(0)
	check(not first.is_inside_tree(), "ответ удалён в том же кадре, до отложенного фокуса")
	await frames()
	check(not box._waiting_choice and box._text.text == "Ответ", "выбор в том же кадре не ломает продолжение диалога")
	box.skip()
	box.open(lines, "focus_test", "none")
	box._finish_typing()
	box.skip()
	await frames()
	check(not box.visible and not box._waiting_choice, "пропуск в том же кадре безопасно закрывает выбор")
	box.open(lines, "focus_test", "none")
	box._finish_typing()
	box.toggle_log()
	await frames()
	check(box._waiting_choice and box._log_panel.visible and not (box._choices_box.get_child(0) as Button).has_focus(),
		"открытый журнал не получает отложенный фокус ответа")
	box.toggle_log()
	await frames()
	check((box._choices_box.get_child(0) as Button).has_focus(), "закрытие журнала возвращает фокус к ответам")
	box.skip()
	box.queue_free()
	await frames()

func _test_body_and_training() -> void:
	print("-- Выбор тела и план тренировок")
	var bs := BodySelect.new()
	get_tree().root.add_child(bs)
	await frames()
	bs.open("Назад", "berserker")
	await frames()
	check(get_viewport().gui_get_focus_owner() != null, "выбор тела открывается с фокусом")
	await pad_press(JOY_BUTTON_B)
	check(not bs.visible, "B возвращает из выбора тела")
	bs.queue_free()
	await frames()
	var tp := TrainingPlan.new()
	get_tree().root.add_child(tp)
	await frames()
	Save.add_glory_bank(100000)
	tp.open("Назад")
	await frames()
	check(get_viewport().gui_get_focus_owner() == tp._fight_btn, "план тренировок открывается с фокусом")
	check(tp._scroll.follow_focus, "план тренировок прокручивается вслед за фокусом")
	var buy_button: Button
	var buy_id := ""
	for id in tp._cards:
		var candidate := (tp._cards[id] as Control).get_meta("button") as Button
		if candidate and not candidate.disabled and Save.buy_block_reason(id) == "":
			buy_button = candidate
			buy_id = id
			break
	check(buy_button != null, "найдено доступное открытие для проверки покупки")
	if buy_button:
		buy_button.grab_focus()
		await pad_press(JOY_BUTTON_A)
		if Dialogue.is_playing():
			Dialogue.box().skip()
			await frames()
		await frames()
		var after := get_viewport().gui_get_focus_owner()
		check(Save.is_unlocked(buy_id) and after != null and (tp._root.is_ancestor_of(after) or after == tp._root),
			"после покупки открытие записано, фокус остаётся на плане")
	await pad_press(JOY_BUTTON_B)
	check(not tp.visible, "B возвращает из плана тренировок")
	tp.queue_free()
	await frames()

func _test_main_menu_and_shop() -> void:
	print("-- Главное меню, ларёк, пауза и подсказки в настоящей игре")
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await frames(10)
	check(get_viewport().gui_get_focus_owner() != null, "главное меню открывается с фокусом")
	await pad_press(JOY_BUTTON_A)
	await frames()
	var body := get_tree().current_scene.find_child("BodySelect", true, false) as BodySelect
	check(body != null and body.visible, "A в меню открывает выбор тела")
	if body and body.visible:
		await pad_press(JOY_BUTTON_B)
		await frames()
	Dialogue.in_run_scenes = false
	Run.start_run("berserker")
	Run.room_order.assign([Run.ROOM_SCENES[0], Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(30)
	var game := get_tree().current_scene as Game
	check(game != null and game.player != null, "сцена забега загрузилась")
	if game == null or game.player == null:
		return
	game.player.mjolnir.force_return_instant()
	game.player.mjolnir.reset_cooldown()
	var keyboard := InputEventKey.new()
	keyboard.physical_keycode = KEY_K
	keyboard.pressed = true
	GameSettings.note_input(keyboard)
	await frames()
	var wh := game.hud.get_node_or_null("WeaponHUD") as WeaponHUD
	check(wh != null and wh._hint.text.contains("Q"), "боевой HUD показывает клавиатуру/мышь («%s»)" % (wh._hint.text if wh else ""))
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	GameSettings.note_input(pad)
	await frames()
	check(wh != null and not wh._hint.text.contains("Q") and wh._hint.text.contains(GameSettings.current_binding("weapon_switch")),
		"уже открытый HUD переключается на геймпад («%s»)" % (wh._hint.text if wh else ""))
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	GameSettings.rebind_pad("throw", rb)
	await frames()
	check(Tutorial.key_name("throw").contains("RB") and "mouse:2" in GameSettings.bindings("throw"), "подсказка броска (кольцо хвата) обновляется после переназначения, мышь сохранена")
	GameSettings.reset_pad_input()
	Run.silver = 1000
	game.rewards.open_shop()
	await frames()
	var shop := game.rewards.shop
	check(shop != null and shop.visible and get_viewport().gui_get_focus_owner() != null, "ларёк открывается с фокусом")
	if shop:
		shop._open_time = -10.0
		await pad_press(JOY_BUTTON_DPAD_DOWN)
		await pad_press(JOY_BUTTON_DPAD_UP)
		check(shop.visible, "D-pad вверх перемещает фокус и не закрывает ларёк")
		await pad_press(JOY_BUTTON_B)
		check(not shop.visible, "B закрывает ларёк")
	await pad_press(JOY_BUTTON_START)
	check(game.pause_menu.visible, "Start открывает паузу")
	game.pause_menu.open_settings()
	await frames()
	await pad_press(JOY_BUTTON_B)
	await frames()
	check(game.pause_menu.visible and (game.pause_menu._settings == null or not is_instance_valid(game.pause_menu._settings) or game.pause_menu._settings.is_queued_for_deletion()),
		"B закрывает настройки и оставляет паузу открытой")
	game.pause_menu.toggle()
