extends Node
## «Быстрая проверка» (NOW.md, П0): экран в меню, вход в зал каждого пункта без сюжета и обучения,
## оружие пункта, F6 — старое/новое (FeelSwitch), возврат в меню всё восстанавливает.
## godot --headless --path . --fixed-fps 60 res://tests/quick_check_test.tscn

var _fails: Array[String] = []
var _passes: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "QuickCheckRunner"
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

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _game() -> Game:
	return get_tree().current_scene as Game

func _wait_room(timeout: float = 20.0) -> bool:
	for i in int(timeout * 60.0):
		var g := _game()
		if g and is_instance_valid(g.room) and g.room.is_inside_tree():
			return true
		await get_tree().physics_frame
	return false

func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await frames(2)
	var u := InputEventKey.new()
	u.keycode = code
	u.pressed = false
	Input.parse_input_event(u)
	await frames(1)

func _run() -> void:
	print("=== QUICK CHECK TEST ===")
	seed(6161)
	check(QuickCheck.available(), "в отладочном запуске кнопка есть (в релизе — только с признаком playtest)")
	check(QuickCheck.ITEMS.size() >= 3 and QuickCheck.ITEMS.size() <= 5, "пунктов 3–5: %d" % QuickCheck.ITEMS.size())
	# Экран в меню
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
	await frames(10)
	var menu := get_tree().current_scene
	var qc := QuickCheck.new()
	menu.add_child(qc)
	await frames(3)
	var tries: Array = qc.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == tr("Попробовать"))
	check(tries.size() == QuickCheck.ITEMS.size(), "у каждого пункта «Попробовать»")
	qc.queue_free()
	await frames(2)
	for i in QuickCheck.ITEMS.size():
		var item: Dictionary = QuickCheck.ITEMS[i]
		print("-- %s" % item.title)
		QuickCheck.start(get_tree(), i)
		var ok := await _wait_room()
		var g := _game()
		check(ok and g != null, "зал загрузился")
		if g == null:
			continue
		await frames(20)
		var want: String = Run.BOSS_SCENE if item.room == "boss" else str(item.room)
		check(g.room.scene_file_path == want, "нужный зал: %s" % want.get_file())
		check(QuickCheck.active and not Dialogue.in_run_scenes, "без сюжетных сцен")
		check(g.tutorial == null or not g.tutorial.active, "без обучения")
		var w := g.player.current_weapon()
		check(w != null and w.id == str(item.weapon), "оружие пункта: %s" % (w.id if w else "нет"))
		var overlays := g.find_children("*", "CanvasLayer", false, false).filter(func(n: Node) -> bool: return n is QuickCheck.Overlay)
		check(overlays.size() == 1, "плашка «Быстрой проверки» на экране")
		check(not FeelSwitch.is_old(&"hammer_cooldown"), "по умолчанию — новое")
		await _key(KEY_F6)
		check(FeelSwitch.is_old(&"hammer_cooldown") and FeelSwitch.is_old(&"enemy_count") and FeelSwitch.is_old(&"boss_armor"), "F6 — всё старое")
		if item.has("old_room"):
			# Пункт со старой раскладкой зала: F6 перезапускает зал в старой сцене (QuickCheck.start, keep_switch)
			await _wait_room()
			await frames(20)
			g = _game()
			check(g != null and g.room.scene_file_path == str(item.old_room) and FeelSwitch.is_old(&"hammer_cooldown"), "F6 — старая раскладка зала")
		await _key(KEY_F6)
		check(not FeelSwitch.is_old(&"hammer_recall"), "F6 ещё раз — снова новое")
		if item.has("old_room"):
			await _wait_room()
			await frames(20)
			g = _game()
			check(g != null and g.room.scene_file_path == want, "F6 ещё раз — новая раскладка")
		await _key(KEY_F6)
		if item.has("old_room"):
			await _wait_room()
			await frames(20)
			g = _game()
		g.go_to_menu()
		await frames(15)
		check(not QuickCheck.active and Dialogue.in_run_scenes and not FeelSwitch.is_old(&"hammer_power"), "меню возвращает всё как было")
	var total := _passes + _fails.size()
	print("=== ИТОГ QUICK CHECK: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().quit(1 if not _fails.is_empty() or total == 0 else 0)
