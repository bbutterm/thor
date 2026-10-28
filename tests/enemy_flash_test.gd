extends Node
## Вспышка врагов: независимые значения двух врагов, реальные состояния стихий,
## повторное использование и освобождение GL-материала после смерти.
## godot --headless --path . --fixed-fps 60 res://tests/enemy_flash_test.tscn

var _passes: int = 0
var _fails: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.name = "EnemyFlashTestRunner"
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	if condition:
		_passes += 1
		print("  [OK] ", description)
	else:
		_fails.append(description)
		print("  [FAIL] ", description)

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

## Игнорируем комментарии и отличие вида uniform; код и настройки рендера должны совпадать.
func _shader_code(shader: Shader) -> String:
	var lines := PackedStringArray()
	for line in shader.code.split("\n"):
		var item := line.strip_edges()
		if not item.is_empty() and not item.begins_with("//"):
			lines.append(item.replace("instance uniform ", "uniform "))
	return "\n".join(lines)

func _value(e: Enemy, name: StringName) -> Variant:
	if e._flash_material_gl != null:
		return e._flash_material_gl.get_shader_parameter(name)
	return e._flash_meshes[0].get_instance_shader_parameter(name)

func _spawn(room: Room, kind: String, offset: Vector3) -> Enemy:
	var scene := load("res://enemies/%s.tscn" % kind) as PackedScene
	var e := scene.instantiate() as Enemy
	room.add_child(e)
	e.global_position = room.global_position + offset
	e.set_physics_process(false)
	return e

func _all_overlays(e: Enemy, expected: Material) -> bool:
	if e._flash_meshes.is_empty():
		return false
	for part in e._flash_meshes:
		if not is_instance_valid(part) or part.material_overlay != expected:
			return false
	return true

func _test_materials(a: Enemy, b: Enemy, is_gl: bool) -> void:
	check(not a._flash_meshes.is_empty() and not b._flash_meshes.is_empty(), "у обоих врагов найдены меши для вспышки")
	if a._flash_meshes.is_empty() or b._flash_meshes.is_empty():
		return
	check((a._flash_material_gl != null and b._flash_material_gl != null) if is_gl
		else (a._flash_material_gl == null and b._flash_material_gl == null), "материал создаётся только для GL")

	# Сначала проверяем реальный выбранный режим, включая общий материал Forward+.
	a._set_overlay(0.8, 0.3)
	b._set_overlay(0.2, 0.6)
	if is_gl:
		check(a._flash_material_gl != b._flash_material_gl
			and _all_overlays(a, a._flash_material_gl) and _all_overlays(b, b._flash_material_gl),
			"GL: по одному раздельному материалу на врага, общий для его частей")
	else:
		check(_all_overlays(a, Enemy.FLASH_MATERIAL) and _all_overlays(b, Enemy.FLASH_MATERIAL),
			"другой рендерер: исходный общий материал на обоих врагах")
	check(is_equal_approx(float(_value(a, &"flash")), 0.8)
		and is_equal_approx(float(_value(b, &"flash")), 0.2)
		and is_equal_approx(float(_value(a, &"glow")), 0.3)
		and is_equal_approx(float(_value(b, &"glow")), 0.6), "вспышка и замах двух врагов независимы")
	a.status_glow = Color(1.0, 0.2, 0.0, 0.7)
	b.status_glow = Color(0.1, 0.7, 1.0, 0.4)
	a._set_overlay(0.8, 0.3)
	b._set_overlay(0.2, 0.6)
	var native_a: Color = _value(a, &"elite")
	var native_b: Color = _value(b, &"elite")
	check(native_a.is_equal_approx(a.status_glow) and native_b.is_equal_approx(b.status_glow),
		"цвета двух врагов независимы в выбранном рендерере")
	a.status_glow = Color(0, 0, 0, 0)
	b.status_glow = Color(0, 0, 0, 0)
	a._set_overlay(0.0, 0.0)
	b._set_overlay(0.0, 0.0)
	check(_all_overlays(a, Outline.overlay()) and _all_overlays(b, Outline.overlay()),
		"после затухания вспышка снята и восстановлена выбранная обводка")
	# В headless с другим методом отдельно проверяем логику GL на созданных материалах;
	# это не замена проверки реального GL-рендерера и _ready в этом режиме.
	if not is_gl:
		a._flash_material_gl = Enemy.FLASH_MATERIAL_GL.duplicate() as ShaderMaterial
		b._flash_material_gl = Enemy.FLASH_MATERIAL_GL.duplicate() as ShaderMaterial
	var reused: ShaderMaterial = a._flash_material_gl
	a.elite_glow = Color(0.3, 1.0, 0.1, 0.5)
	a.status_glow = Color(1.0, 0.2, 0.0, 0.7)
	b.status_glow = Color(0.1, 0.7, 1.0, 0.4)
	a._set_overlay(0.8, 0.3)
	b._set_overlay(0.2, 0.6)
	var ca: Color = _value(a, &"elite")
	var cb: Color = _value(b, &"elite")
	check(a._flash_material_gl == reused and a._flash_material_gl != b._flash_material_gl
		and _all_overlays(a, reused) and _all_overlays(b, b._flash_material_gl),
		"GL-материал повторно используется после выключения и не делится между врагами")
	check(ca.is_equal_approx(a.status_glow) and cb.is_equal_approx(b.status_glow)
		and is_equal_approx(float(_value(a, &"flash")), 0.8)
		and is_equal_approx(float(_value(b, &"glow")), 0.6),
		"разные цвета и параметры не смешиваются; стихия важнее элиты")
	a.status_glow = Color(0, 0, 0, 0)
	a._set_overlay(0.0, 0.0)
	var elite_only: Color = _value(a, &"elite")
	check(Color(elite_only.r, elite_only.g, elite_only.b).is_equal_approx(Color(0.3, 1.0, 0.1))
		and elite_only.a > 0.0 and elite_only.a <= 0.5, "после стихии возвращается пульсирующий цвет элиты")
	a.elite_glow = Color(0, 0, 0, 0)
	a._set_overlay(0.0, 0.0)
	b.status_glow = Color(0, 0, 0, 0)
	b._set_overlay(0.0, 0.0)

func _test_elements(e: Enemy) -> void:
	var status := ElementStatus.of(e, true)
	check(status != null, "создан реальный ElementStatus")
	if status == null:
		return
	status.set_physics_process(false)
	status.ignite(0.0, 5.0)
	status._update_glow(0.0)
	e._set_overlay(0.0, 0.0)
	var burn: Color = _value(e, &"elite")
	status.shock(5.0)
	status._update_glow(0.0)
	e._set_overlay(0.0, 0.0)
	var shock: Color = _value(e, &"elite")
	status.freeze(5.0)
	status._update_glow(0.0)
	e._set_overlay(0.0, 0.0)
	var frozen: Color = _value(e, &"elite")
	check(Color(burn.r, burn.g, burn.b).is_equal_approx(ElementStatus.GLOW_BURN) and burn.a > 0.0
		and Color(shock.r, shock.g, shock.b).is_equal_approx(ElementStatus.GLOW_SHOCK) and shock.a > 0.0
		and Color(frozen.r, frozen.g, frozen.b).is_equal_approx(ElementStatus.GLOW_FROZEN) and frozen.a > 0.0,
		"ElementStatus: огонь, ток и заморозка сохраняют цвет и приоритет")
	status.queue_free()
	e.status_glow = Color(0, 0, 0, 0)
	e._set_overlay(0.0, 0.0)

func _test_death(room: Room, is_gl: bool, simulate_gl: bool = true) -> void:
	var dying := _spawn(room, "fodder", Vector3(2, 0.1, 3))
	if not is_gl and simulate_gl:
		dying._flash_material_gl = Enemy.FLASH_MATERIAL_GL.duplicate() as ShaderMaterial
	if dying._flash_meshes.is_empty() or ((is_gl or simulate_gl) and dying._flash_material_gl == null):
		check(false, "подготовлен враг с мешами и нужным материалом")
		return
	dying.elite_glow = Color(0.7, 0.1, 0.8, 0.5)
	dying.status_glow = Color(0.2, 0.6, 1.0, 0.7)
	dying._set_overlay(1.0, 0.5)
	var material_ref: WeakRef = weakref(dying._flash_material_gl) if dying._flash_material_gl != null else null
	var visual := dying._visual
	var parts := dying._flash_meshes.duplicate()
	dying.gib_on_death = false  # П3: проверяем путь «целого трупа»; у корма по умолчанию куски (FodderGibs, enemy_test)
	dying.take_hit(Enemy.DEBUG_KILL_DAMAGE, Vector3.ZERO, "ranged")
	var cleared := true
	var corpse_overlay := Outline.overlay()
	for part in parts:
		if not is_instance_valid(part) or (part as GeometryInstance3D).material_overlay != corpse_overlay:
			cleared = false
	check(dying.is_dead and is_instance_valid(visual) and visual.get_parent() is RigidBody3D and cleared,
		"при смерти вспышка снята, а обводка трупа соответствует настройке")
	await _frames(4)
	if material_ref != null:
		check(material_ref.get_ref() == null, "труп не удерживает материал погибшего врага")

func _run() -> void:
	print("=== ENEMY FLASH TEST ===")
	var original_outline := bool(GameSettings.get_value("video", "outline"))
	GameSettings.set_value("video", "outline", true, false)
	var original: ShaderMaterial = Enemy.FLASH_MATERIAL
	var candidate: ShaderMaterial = Enemy.FLASH_MATERIAL_GL
	check(candidate.shader == Enemy.FLASH_GL_SHADER
		and not Enemy.FLASH_GL_SHADER.code.contains("instance uniform"), "GL-шейдер использует обычные uniform")
	check(original.render_priority == candidate.render_priority and _shader_code(original.shader) == _shader_code(candidate.shader),
		"GL-шейдер совпадает с исходным после замены вида uniform")
	var is_gl := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	print("Режим: ", RenderingServer.get_current_rendering_method())
	Dialogue.in_run_scenes = false
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", Run.BOSS_SCENE])
	Run.room_rewards.clear()
	Run.miniboss_rooms.clear()
	Run.doors_enabled = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(30)
	var game := get_tree().current_scene as Game
	if game == null or not is_instance_valid(game.room):
		check(false, "игра и зал созданы")
	else:
		var room: Room = game.room
		room.set_physics_process(false)
		room._spawn_queue.clear()
		for enemy in room.alive_enemies().duplicate():
			enemy.queue_free()
		room._alive.clear()
		var a := _spawn(room, "fodder", Vector3(-2, 0.1, 3))
		var b := _spawn(room, "grunt", Vector3(0, 0.1, 3))
		if not is_gl:
			var native_enemy := _spawn(room, "fodder", Vector3(-3, 0.1, 3))
			if not native_enemy._flash_meshes.is_empty():
				_test_elements(native_enemy)
			native_enemy.queue_free()
			await _test_death(room, false, false)
		_test_materials(a, b, is_gl)
		if not a._flash_meshes.is_empty() and a._flash_material_gl != null:
			_test_elements(a)
		await _test_death(room, is_gl)
		GameSettings.set_value("video", "outline", false, false)
		a._set_overlay(0.8, 0.0)
		a._set_overlay(0.0, 0.0)
		check(_all_overlays(a, null), "после вспышки без обводки материал убран")
		await _test_death(room, is_gl)
	GameSettings.set_value("video", "outline", original_outline, false)
	get_tree().paused = false
	FX.reset_time()
	if is_instance_valid(game):
		game.queue_free()
	await _frames(50)
	print("=== ИТОГ ENEMY FLASH: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for failure in _fails:
		print("  FAIL: ", failure)
	get_tree().quit(1 if not _fails.is_empty() else 0)
