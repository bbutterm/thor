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
			var matches: Array = defs.filter(func(d: Dictionary) -> bool: return "res://rooms/%s.tscn" % d.file == p)
			var definition: Dictionary = matches[0] if matches.size() == 1 else {}
			var expected: Array = definition.get("enemies", [])
			var markers := inst.get_node("Spawns").get_children()
			var same: bool = markers.size() == expected.size() and inst.max_alive == 20 and definition.get("max_alive", 0) == 20
			var wave_totals := {}
			for i in mini(markers.size(), expected.size()):
				var marker := markers[i] as Node3D
				var spec: Array = expected[i]
				var amount := int(marker.get_meta("count", 1))
				var spread := float(marker.get_meta("spread", 0.0))
				var expected_amount := int(spec[3]) if spec.size() > 3 else 1
				var expected_spread := float(spec[4]) if spec.size() > 4 else 0.0
				same = same and str(marker.get_meta("kind", "grunt")) == str(spec[0]) and int(marker.get_meta("wave", 0)) == int(spec[2])
				same = same and amount == expected_amount and is_equal_approx(spread, expected_spread) and marker.position.is_equal_approx((spec[1] as Vector3) + Vector3(0, 0.05, 0))
				if spec.size() > 5:
					var entry: Dictionary = spec[5]
					for key in entry:
						same = same and marker.has_meta(key) and marker.get_meta(key) == entry[key]
				var wave := int(spec[2])
				if not wave_totals.has(wave):
					wave_totals[wave] = {"all": 0, "fodder": 0, "special": 0, "packs": 0}
				var kind := str(marker.get_meta("kind", "grunt"))
				if kind == "squad":
					# Отряд (SquadDef): считаем его состав; у всех вариантов он одинаковый
					var ids: Array = marker.get_meta("squad_options", [marker.get_meta("squad", "")])
					var override: Dictionary = marker.get_meta("squad_override", {})
					var totals := {}
					for sid in ids:
						var sq := SquadDef.find(str(sid))
						same = same and sq != null and (totals.is_empty() or sq.totals(override) == totals)
						if sq:
							totals = sq.totals(override)
					for k in totals:
						var n := int(totals[k])
						wave_totals[wave].all += n
						if k == "fodder":
							wave_totals[wave].fodder += n
							wave_totals[wave].packs += 1
							same = same and n >= 5 and n <= 8
						elif k != "grunt":
							wave_totals[wave].special += n
					continue
				wave_totals[wave].all += amount
				if kind == "fodder":
					wave_totals[wave].fodder += amount
					wave_totals[wave].packs += 1
					same = same and amount >= 5 and amount <= 8 and spread > 0.0
				elif kind != "grunt":
					wave_totals[wave].special += amount
			for wave in wave_totals:
				var stats: Dictionary = wave_totals[wave]
				var ratio := float(stats.fodder) / float(stats.all) if stats.all > 0 else 0.0
				same = same and ratio >= 0.6 and ratio <= 0.7 and stats.special >= 1 and stats.special <= 2 and stats.packs >= 1
			check(same and wave_totals.size() >= 2, "%s: сцена соответствует составу волн, 60–70 %% корма и 1–2 особых" % p.get_file())
			# Открытый периметр: физическая граница остаётся, непрерывные видимые стены удалены.
			var geo := inst.get_node_or_null("Geometry")
			var edges_ok := geo != null
			for wall_name in ["WallN_L", "WallN_R", "WallS", "WallW", "WallE"]:
				var wall := geo.get_node_or_null(wall_name) as StaticBody3D if geo else null
				var shape := wall.get_node_or_null("Shape") as CollisionShape3D if wall else null
				edges_ok = edges_ok and shape != null and shape.shape is BoxShape3D and (shape.shape as BoxShape3D).size.y >= 24.0 and not shape.disabled and wall.get_node_or_null("Mesh") == null
			var models := geo.get_node_or_null("WallModels") if geo else null
			if models:
				for model in models.get_children():
					var nm := String(model.name)
					if nm.begins_with("N_L_") or nm.begins_with("N_R_") or nm.begins_with("S_") or nm.begins_with("W_") or nm.begins_with("E_"):
						edges_ok = false
			check(edges_ok and inst.get_node_or_null("Dress/Backdrop") != null, "%s: невидимые границы и даль" % p.get_file())
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
