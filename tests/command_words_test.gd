extends Node
## Слова-команды (П10, NOW.md партия 9): каждое событие — своё слово, кулдаун 3 с, опасность перебивает,
## выключатель [hud] commands, события из игры (волна, мало ХП, удар со спины, последний враг, таран босса).
## godot --headless --path . --fixed-fps 60 res://tests/command_words_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var cw: CommandWords

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

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## Сброс кулдауна между проверками
func _fresh() -> void:
	cw._last_time = -100.0
	cw._last_kind = ""
	cw._left = 0.0
	cw.last_id = &""

func _run() -> void:
	print("=== COMMAND WORDS TEST ===")
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_02.tscn", Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(90)
	var game := get_tree().current_scene as Game
	var p := game.player
	cw = game.hud.commands
	check(cw != null and CommandWords.current == cw and CommandWords.enabled(), "слова-команды в HUD, включены по умолчанию")
	game.room.set_physics_process(false)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	game.room._alive.clear()
	(game.room.get("_spawn_queue") as Array).clear()
	await frames(3)
	# Каждое слово — свой текст и цвет вида
	for id in CommandWords.WORDS:
		_fresh()
		check(cw.request(id) and cw._label.text == tr(str(CommandWords.WORDS[id][0])) and cw.modulate.a > 0.9, "«%s» показано" % cw._label.text)
	# Кулдаун и приоритет
	_fresh()
	cw.request(&"go")
	check(not cw.request(&"smash"), "второе слово раньше 3 с — нет")
	check(cw.request(&"run"), "опасность перебивает слово попроще")
	check(not cw.request(&"behind"), "опасность подряд — тоже по кулдауну")
	cw._last_time -= cw.gap + 0.1
	check(cw.request(&"smash"), "через 3 с — снова можно")
	await frames(int(cw.show_time * 60.0) + 15)
	check(cw.modulate.a == 0.0, "слово держится %.1f с и гаснет" % cw.show_time)
	# Выключатель
	_fresh()
	GameSettings.set_value("hud", "commands", false, false)
	check(not cw.request(&"smash"), "выключатель [hud] commands")
	GameSettings.set_value("hud", "commands", true, false)
	# События игры: волна, мало ХП, удар со спины, последний враг, таран босса
	_fresh()
	game.room.wave_started.emit(1)
	check(cw.last_id == &"smash", "началась волна — «КРУШИ!»")
	_fresh()
	cw._low_hp = false
	p.health = p.max_health * 0.2
	cw._poll()
	check(cw.last_id == &"run", "ХП < 25 % — «БЕГИ!»")
	p.health = p.max_health
	cw._poll()
	_fresh()
	var e := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	game.room.add_child(e)
	var back := -p.get_aim_forward()
	back.y = 0.0
	e.global_position = p.global_position + back.normalized() * 2.5
	e.set_physics_process(false)
	await frames(2)
	e.state = Enemy.State.WINDUP
	cw._poll()
	check(cw.last_id == &"behind", "замах со спины — «СЗАДИ!»")
	_fresh()
	game.room._alive.append(e)
	e.state = Enemy.State.CHASE
	cw._finish_wave = -1
	cw._poll()
	check(cw.last_id == &"finish", "последний враг волны — «ДОБЕЙ!»")
	game.room._alive.erase(e)
	e.queue_free()
	_fresh()
	var boss := (load("res://enemies/bosses/sven.tscn") as PackedScene).instantiate() as BossEnemy if ResourceLoader.exists("res://enemies/bosses/sven.tscn") else null
	if boss == null and ResourceLoader.exists("res://enemies/sven.tscn"):
		boss = (load("res://enemies/sven.tscn") as PackedScene).instantiate() as BossEnemy
	if boss:
		game.room.add_child(boss)
		boss.global_position = p.global_position + p.get_aim_forward() * Vector3(1, 0, 1) * 8.0
		boss.set_physics_process(false)
		boss.player = p
		await frames(2)
		var to := p.global_position - boss.global_position
		to.y = 0.0
		boss.strip_show(to.normalized(), 15.0, 0.5)
		check(cw.last_id == &"dodge", "таран босса нацелен на Тора — «УВОРАЧИВАЙСЯ!»")
		boss.queue_free()
	else:
		check(false, "сцена Свена для проверки тарана")
	print("=== ИТОГ COMMAND WORDS: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().quit(1 if _fails.size() else 0)
