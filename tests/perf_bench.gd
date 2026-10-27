extends Node
## Замер среднего времени кадра в тяжёлых сценах (не тест — без FAIL, только цифры):
##   1) «Толпа»: 18 корма + 2 элиты вокруг Тора в зале 1, Тор машет топором и бросает молот;
##   2) «Ярл, фаза 3»: балконы сломаны (обломки на полу), Ярл бодается и прыгает, корм рядом.
## Headless (CPU):  godot --headless --path . --fixed-fps 60 res://tests/perf_bench.tscn
## С рендером:      xvfb-run -a godot --path . --fixed-fps 60 --rendering-method gl_compatibility --resolution 320x180 res://tests/perf_bench.tscn
## Аргумент после «--» — секунд замера на сцену (по умолчанию 8).
## «-- 8 outline»: вместо обычных сцен — толпа 44 врагов с комиксовой обводкой и без (scripts/outline.gd).
## Пишет: среднее/медиану/95-й перцентиль кадра (мс, по часам; в headless это вся CPU-часть кадра),
## число узлов и draw calls.

var game: Game
var seconds: float = 8.0
## «-- 8 ablate»: в толпе ещё и замеры с выключенными частями (где тратится CPU)
var ablate: bool = false
## «-- 8 outline»: цена обводки на толпе 44
var outline: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "PerfBench"
		get_tree().root.add_child.call_deferred(runner)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_float():
		seconds = args[0].to_float()
	ablate = "ablate" in args
	outline = "outline" in args
	_run.call_deferred()

func wait(sec: float) -> void:
	for i in int(ceil(sec * 60.0)):
		await get_tree().physics_frame
		_immortal()

func _immortal() -> void:
	if game and is_instance_valid(game) and game.player:
		game.player.health = game.player.max_health
		game.player.is_dead = false

func _start(order: Array, index: int) -> void:
	Run.start_run("berserker")
	Run.room_order.assign(order)
	Run.room_index = index
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.6)
	game = get_tree().current_scene as Game

func _run() -> void:
	var mode := "headless" if DisplayServer.get_name() == "headless" else RenderingServer.get_current_rendering_method()
	print("=== PERF BENCH (%s, %.0f с на сцену) ===" % [mode, seconds])
	if outline:
		await _bench_outline()
	else:
		await _bench_crowd()
		await _bench_jarl()
	print("=== ИТОГ PERF BENCH ===")
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0)

## Тор держится на месте, машет топором, раз в 2 с бросает молот; враги вокруг атакуют.
func _measure(label: String) -> void:
	var p := game.player
	var spot := p.global_position
	var times := PackedFloat32Array()
	var n := int(seconds * 60.0)
	var iu_peak := 0
	var last := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
		_immortal()
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		if i % 20 == 0:
			p.axe.request_attack()
		if i % 120 == 60 and p.mjolnir.in_hand:
			p.mjolnir.throw_hammer()
		if i % 120 == 100 and not p.mjolnir.in_hand:
			p.mjolnir.force_return_instant()
		if i % 30 == 0:
			iu_peak = maxi(iu_peak, FX.instance_uniform_users(get_tree().root))
		if p.global_position.distance_to(spot) > 6.0:
			p.global_position = spot
			p.velocity = Vector3.ZERO
	var sorted := times.duplicate()
	sorted.sort()
	var sum := 0.0
	for t in times:
		sum += t
	print("%s: кадр среднее %.2f мс, медиана %.2f, p95 %.2f, макс %.1f | узлов %d, врагов %d, draw calls %d, instance uniform %d (пик %d)" % [
		label, sum / times.size(), sorted[sorted.size() / 2], sorted[int(sorted.size() * 0.95)], sorted[sorted.size() - 1],
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		get_tree().get_nodes_in_group("enemies").size(), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		FX.instance_uniform_users(get_tree().root), iu_peak])

func _bench_crowd() -> void:
	await _start([Run.ROOM_SCENES[0]], 0)
	await wait(1.0)
	# Свои волны зала убираем — толпа своя
	game.room._spawn_queue.clear()
	for e in game.room.alive_enemies().duplicate():
		if is_instance_valid(e) and not e.is_dead:
			e.take_hit(9999, Vector3.ZERO, "test")
	await wait(1.5)
	var c := game.player.global_position
	for i in 20:
		var a := TAU * i / 20.0
		var r := 5.0 + (i % 3) * 1.5
		var kind := "grunt" if i < 2 else "fodder"
		var e := game.room.spawn_extra(kind, c + Vector3(cos(a) * r, 0.05, sin(a) * r))
		if e:
			if i < 2:
				Loot.make_elite(e)
			# Бессмертная толпа — число врагов в замере не меняется (эффекты попаданий остаются)
			e.max_health = 1e6
			e.health = 1e6
		await get_tree().physics_frame
	await wait(2.5)
	await _measure("Толпа (18 корма + 2 элиты)")
	_iu_breakdown()
	if ablate:
		await _ablations()

## Толпа 44 (11 воинов + 33 корма, 2 элиты): с обводкой, без, снова с (порядок — против дрейфа прогрева)
func _bench_outline() -> void:
	GameSettings.set_value("video", "outline", true, false)
	await _start([Run.ROOM_SCENES[0]], 0)
	await wait(1.0)
	game.room._spawn_queue.clear()
	for e in game.room.alive_enemies().duplicate():
		if is_instance_valid(e) and not e.is_dead:
			e.take_hit(9999, Vector3.ZERO, "test")
	await wait(1.5)
	var c := game.player.global_position
	for i in 44:
		var a := TAU * i / 44.0
		var r := 5.0 + (i % 4) * 1.5
		var e := game.room.spawn_extra("grunt" if i % 4 == 0 else "fodder", c + Vector3(cos(a) * r, 0.05, sin(a) * r))
		if e:
			if i < 2:
				Loot.make_elite(e)
			e.max_health = 1e6
			e.health = 1e6
		await get_tree().physics_frame
	await wait(2.5)
	print("  обведено узлов: %d" % Outline.active_count())
	await _measure("Толпа 44, обводка ВКЛ")
	GameSettings.set_value("video", "outline", false, false)
	await wait(0.5)
	await _measure("Толпа 44, обводка ВЫКЛ")
	GameSettings.set_value("video", "outline", true, false)
	await wait(0.5)
	await _measure("Толпа 44, обводка ВКЛ (повтор)")
	# Для сравнения — вариант (b): экранный контур по глубине (полноэкранный проход, 5 выборок глубины).
	# Только замер: в игру не вошёл — обводит всё подряд (и стены), в GL Compatibility нет буфера нормалей.
	GameSettings.set_value("video", "outline", false, false)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2, 2)
	quad.mesh = qm
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = SCREEN_EDGE_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	quad.material_override = sm
	get_viewport().get_camera_3d().add_child(quad)
	await wait(0.5)
	await _measure("Толпа 44, экранный контур по глубине (b), без обводки")
	quad.queue_free()
	GameSettings.set_value("video", "outline", true, false)

const SCREEN_EDGE_SHADER := """shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
float lin(vec2 uv, mat4 inv) {
	float d = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	d = d * 2.0 - 1.0;
#endif
	vec4 v = inv * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}
void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}
void fragment() {
	vec2 px = 1.5 / VIEWPORT_SIZE;
	float c = lin(SCREEN_UV, INV_PROJECTION_MATRIX);
	float e = abs(lin(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX) - c) + abs(lin(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX) - c)
		+ abs(lin(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX) - c) + abs(lin(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX) - c);
	ALBEDO = vec3(0.0);
	ALPHA = clamp(e / (c * 0.08) - 0.5, 0.0, 1.0);
}
"""

## Выключаем по одной части и мерим снова — разница = её цена.
func _ablations() -> void:
	var parts := {
		"анимации врагов": func(on: bool) -> void:
			for e in get_tree().get_nodes_in_group("enemies"):
				for ap in (e as Node).find_children("*", "AnimationPlayer", true, false):
					(ap as AnimationPlayer).active = on,
		"ИИ и физика врагов": func(on: bool) -> void:
			for e in get_tree().get_nodes_in_group("enemies"):
				(e as Node).set_physics_process(on),
		"HUD": func(on: bool) -> void:
			game.hud.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED,
		"экранные VFX": func(on: bool) -> void:
			if VfxScreen.instance:
				VfxScreen.instance.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED,
		"комикс-слова": func(on: bool) -> void:
			ComicFX.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED,
	}
	for k in parts:
		(parts[k] as Callable).call(false)
		await _measure("  без: " + k)
		(parts[k] as Callable).call(true)
		await wait(0.5)

func _bench_jarl() -> void:
	await _start([Run.BOSS_SCENE], 0)
	var jarl: JarlBoss = null
	for i in 40:
		for e in game.room.alive_enemies():
			if e is JarlBoss:
				jarl = e as JarlBoss
		if jarl:
			break
		await wait(0.2)
	if jarl == null:
		print("Ярл не появился")
		return
	await wait(jarl._spawn_time + 0.3)
	# Сразу в фазу 3: ломает балконы — доски-обломки на полу
	jarl.take_hit((jarl.health - jarl.max_health * 0.3) / jarl.armed_damage_mult, Vector3.ZERO, "melee")
	for i in 20 * 60:
		await get_tree().physics_frame
		_immortal()
		if jarl.phase == 3:
			break
	var o := game.room.global_position
	for i in 6:
		var e := game.room.spawn_extra("fodder", o + Vector3(-4 + i * 1.6, 0.05, 4))
		if e:
			e.set_meta("jarl_summon", true)
	game.player.global_position = o + Vector3(0, 0.3, 6)
	# Замер с начала фазы 3: ломает балконы по одному (обломки живут debris_lifetime), бодается, прыгает
	print("  обломков: %d, балконов: %d, фаза %d" % [get_tree().get_nodes_in_group("debris").size(), get_tree().get_nodes_in_group("balconies").size(), jarl.phase])
	await _measure("Ярл, фаза 3 (обломки, корм)")

## Кто занимает буфер instance-переменных: по шейдеру и видимости
func _iu_breakdown() -> void:
	var by := {}
	for g in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		for m in [gi.material_override, gi.material_overlay]:
			if FX._has_iu(m):
				var key := "%s %s %s" % [(m as ShaderMaterial).shader.resource_path.get_file(), "vis" if gi.is_visible_in_tree() else "HID", gi.get_parent().name if gi.get_parent() else ""]
				by[key] = int(by.get(key, 0)) + 1
				break
	var keys := by.keys()
	keys.sort_custom(func(a, b) -> bool: return by[a] > by[b])
	for k in keys:
		print("  IU %4d  %s" % [by[k], k])
