extends Node
## Полоса двух боссов соответствует границе их реального тарана по бокам.
## godot --headless --path . --fixed-fps 60 res://tests/boss_charge_telegraph_test.tscn

var _fails: Array[String] = []
var _passes := 0
var _arena: Node3D
var _player: Player

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	if ok:
		_passes += 1
		print("  [OK] ", what)
	else:
		_fails.append(what)
		print("  [FAIL] ", what)

func _run() -> void:
	print("=== BOSS CHARGE TELEGRAPH TEST ===")
	Run.start_run("berserker")
	_arena = Node3D.new()
	get_tree().root.add_child(_arena)
	_player = (load("res://player/player.tscn") as PackedScene).instantiate() as Player
	_arena.add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	await get_tree().physics_frame
	await _check_boss("res://enemies/sven.tscn", "Свен", 1.5)
	await get_tree().physics_frame  # сбросить общий покадровый кеш врагов
	await _check_boss("res://enemies/jarl.tscn", "Ярл", 2.1)
	_arena.queue_free()
	print("=== ИТОГ BOSS CHARGE TELEGRAPH: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _check_boss(path: String, title: String, expected_scale: float) -> void:
	var boss := (load(path) as PackedScene).instantiate() as BossEnemy
	_arena.add_child(boss)
	boss.set_physics_process(false)
	await get_tree().physics_frame  # тело должно попасть в физический мир до charge_step
	boss.player = _player
	boss.global_position = Vector3.ZERO
	check(is_equal_approx(boss.model_scale, expected_scale), "%s: реальный размер модели %.1f" % [title, expected_scale])
	boss.strip_show(Vector3.FORWARD, 12.0, 0.7)
	var strip := boss._strip
	check(strip != null and strip.visible, "%s: создана видимая полоса" % title)
	if strip == null:
		boss.queue_free()
		return
	# Берём реальные размер меша и мировой масштаб, а не значение из расчёта коллизии.
	var half_width := strip.mesh.get_aabb().size.x * strip.global_transform.basis.x.length() * 0.5
	var side_axis := strip.global_transform.basis.x.normalized()
	boss.charge_begin(Vector3.FORWARD)
	# Центр тарана в середине отмеченного участка: торцы проверяются отдельно вручную.
	boss.global_position = Vector3.FORWARD * 4.0
	for side in [-1.0, 1.0]:
		for outside in [false, true]:
			_player.global_position = boss.global_position + side_axis * side * (half_width + (0.05 if outside else -0.05))
			_player.velocity = Vector3.ZERO
			_player.health = _player.max_health
			_player._invuln_left = 0.0
			boss._charge_hit = false
			boss.charge_step(0.0, 0.0, 100.0, 4.0, 0.0)
			var lost_health := _player.health < _player.max_health
			check(boss._charge_hit == (not outside) and lost_health == (not outside),
				"%s: %s полоса, сторона %+.0f — %s" % [title, "за" if outside else "внутри", side, "мимо" if outside else "попадание"])
	boss.charge_end()
	boss.free()
