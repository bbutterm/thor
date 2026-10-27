extends Node
## Правило генератора: обычные залы строит tools/build_scenes.gd, арены боссов и сюжетные залы (MANUAL_SCENES) —
## ручные сцены, генератор их не создаёт и не перезаписывает. Все залы забега существуют и собраны.
## godot --headless --path . --fixed-fps 60 res://tests/generator_test.tscn

var _fails: Array[String] = []
var _passes: int = 0

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

func _run() -> void:
	print("=== GENERATOR TEST ===")
	var gen := Node.new()
	gen.set_script(load("res://tools/build_scenes.gd"))  # вне дерева: _ready (сборка) не запускается
	var manual: Array = gen.get("MANUAL_SCENES")
	check(manual.has(Run.BOSS_SCENE) and manual.has("res://rooms/sven_arena.tscn"), "арены Ярла и Свена — ручные сцены")
	for path in manual:
		check(ResourceLoader.exists(path), "ручная сцена есть: %s" % path)
	var defs: Array = gen.call("room_defs")
	var generated: Array[String] = []
	for d in defs:
		generated.append("res://rooms/%s.tscn" % d.file)
	generated.append("res://rooms/%s.tscn" % (gen.call("shop_room_def") as Dictionary).file)
	check(generated.filter(func(p: String) -> bool: return p in manual).is_empty(), "генератор не описывает ни одной ручной сцены")
	check(defs.size() >= 9, "обычных планировок: %d" % defs.size())
	for p in Run.ROOM_SCENES:
		check(p in generated, "зал забега %s собирается генератором" % p)
		var ps := load(p) as PackedScene
		var inst := ps.instantiate() if ps else null
		check(inst != null and inst.get_node_or_null("Spawns") != null and inst.get_node("Spawns").get_child_count() >= 8 and inst.get_node_or_null("PlayerSpawn") != null, "%s: маркеры волн и точка появления" % p.get_file())
		if inst:
			inst.free()
	# Попытка сохранить ручную сцену — отказ, файл не меняется
	var path: String = manual[0]
	var before := FileAccess.get_modified_time(path)
	var dummy := Node3D.new()
	dummy.name = "Dummy"
	gen.call("_save", dummy, path)
	check(FileAccess.get_modified_time(path) == before and ResourceLoader.exists(path), "_save отказывается перезаписать ручную сцену")
	gen.free()
	_finish()

func _finish() -> void:
	print("=== ИТОГ GENERATOR: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)
