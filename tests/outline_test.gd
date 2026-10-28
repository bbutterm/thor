extends Node
## Комиксовая обводка (GDD 20, scripts/outline.gd): обведены враги всех видов (и боссы), бочки/ящики, оружие на полу,
## патроны, сундук, Мьёльнир в полёте; стены, пол, декор, кольца-метки и руки от первого лица — нет; материал один
## на всех и без instance-переменных; вспышка урона — обводка в её next_pass;
## настройка «Обводка» выключает/включает вживую, толщина меняется вживую; прогрев обводит при выключенной настройке.
## godot --headless --path . --fixed-fps 60 res://tests/outline_test.tscn

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
	for i in maxi(1, int(ceil(sec * 60.0))):
		await get_tree().physics_frame
		if game and is_instance_valid(game) and game.player:
			game.player.health = game.player.max_health

func _run() -> void:
	GameSettings.set_value("video", "outline", true, false)
	GameSettings.set_value("video", "outline_width", 1.0, false)
	_test_material()
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn"])
	Run.room_index = 0
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.6)
	game = get_tree().current_scene as Game
	game.room.set_physics_process(false)
	await wait(0.6)
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	await wait(0.1)
	var enemies := await _test_enemies()
	var things := await _test_items()
	_test_walls()
	await _test_flash(enemies)
	await _test_budget()
	await _test_setting(enemies, things)
	_test_warmup()
	_test_panel()
	GameSettings.set_value("video", "outline", true, false)
	GameSettings.set_value("video", "outline_width", 1.0, false)
	_finish()

func _finish() -> void:
	print("=== ИТОГ OUTLINE: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("  FAIL: ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)

## Узел обведён: в группе и в оверлее — общий материал (или вспышка, у которой он в next_pass)
func _outlined(gi: GeometryInstance3D) -> bool:
	if not gi.is_in_group(Outline.GROUP):
		return false
	var m := gi.material_overlay
	return m == Outline.material() or (m == Enemy.FLASH_MATERIAL and Outline.flash_next_pass() == Outline.material())

func _meshes(root: Node) -> Array:
	var out: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		out.append(root)
	return out

## Все меши под root (кроме глаз/бровей и исключённых по имени) обведены
func _all_outlined(root: Node, skip: Array = []) -> bool:
	var n := 0
	for m in _meshes(root):
		var gi := m as GeometryInstance3D
		if gi.name.begins_with("Eye") or gi.name in skip or not gi.is_visible_in_tree():
			continue
		if not _outlined(gi):
			print("    не обведён: ", gi.get_path())
			return false
		n += 1
	return n > 0

# --- Материал ---

func _test_material() -> void:
	print("-- Материал")
	var m := Outline.material()
	check(m != null and m.shader == Outline.SHADER, "общий ShaderMaterial обводки")
	check(Outline.material() == m, "material() отдаёт один и тот же экземпляр")
	check(not Outline.SHADER.code.contains("instance uniform"), "шейдер без instance-переменных")
	check(not FX._has_iu(m), "FX не считает материал обводки текущим instance-материалом")
	check(Outline.SHADER.code.contains("cull_front") and Outline.SHADER.code.contains("depth_draw_never"),
		"вывернутая оболочка: cull_front, без записи глубины (проход прозрачных — без теней и prepass)")
	check(absf(float(m.get_shader_parameter("width_px")) - Outline.cfg().width_px) < 0.001, "толщина из data/outline_tuning.tres")

# --- Кому обводка ---

func _test_enemies() -> Array:
	print("-- Враги и боссы")
	var base := game.room.global_position
	var kinds := ["grunt", "thrower", "fodder", "bloated", "shieldbearer", "shaman", "merc", "sven", "jarl"]
	var list: Array = []
	for i in kinds.size():
		var e := game.room.spawn_extra(kinds[i], base + Vector3((i - 4) * 2.2, 0.05, -2.0))
		if e == null:
			check(false, "враг %s появился" % kinds[i])
			continue
		e.set_physics_process(false)
		list.append(e)
	await wait(0.3)
	for e in list:
		var en := e as Enemy
		var skip: Array = ["Laser", "LaserDot"]
		var ok := _all_outlined(en._visual, skip)
		check(ok, "%s (%s): все меши модели обведены" % [en.name, Enemy.Kind.keys()[en.kind]])
	var sven: Enemy = null
	for e in list:
		if e is FatSven:
			sven = e
	if sven:
		var barrel := sven.get_node_or_null("Barrel/Model")
		check(barrel != null and _all_outlined(barrel), "бочка Толстого Свена обведена")
	# Глаза — без обводки
	var eyes := 0
	for e in list:
		for m in _meshes((e as Enemy)._visual):
			if (m as Node).name.begins_with("Eye") and (m as Node).is_in_group(Outline.GROUP):
				eyes += 1
	check(eyes == 0, "глаза и брови не обводятся")
	# Лазер наёмника и телеграфы — не обводятся
	var laser_ok := true
	for e in list:
		var en := e as Enemy
		if en._laser and en._laser.is_in_group(Outline.GROUP):
			laser_ok = false
	check(laser_ok, "лазер наёмника без обводки")
	return list

func _test_items() -> Array:
	print("-- Пропсы, оружие на полу, сундук, Мьёльнир")
	var base := game.room.global_position
	var things: Array = []
	for i in 3:
		var path: String = [Destructible.BARREL_SCENE, Destructible.CRATE_SCENE, Destructible.EXPLOSIVE_SCENE][i]
		var d := (load(path) as PackedScene).instantiate() as Destructible
		d.freeze = true
		game.room.add_child(d)
		d.global_position = base + Vector3(-2.0 + i * 1.2, 0.0, 3.0)
		check(_all_outlined(d.get_node("Model")), "%s: модель обведена" % path.get_file())
		var mark := d.get_node_or_null("Mark") as GeometryInstance3D
		if mark:
			check(not _outlined(mark), "метка взрывной бочки — без обводки")
		things.append(d)
	var defs := Loot.all_defs()
	var pk := Loot.spawn_weapon(game.room, base + Vector3(1.5, 0.0, 3.0), WeaponItem.create(defs[0]))
	check(_all_outlined(pk._model), "оружие на полу обведено")
	check(not _outlined(pk.get_node("Ring")) and not _outlined(pk.get_node("Beam")), "кольцо и луч под оружием — без обводки")
	things.append(pk)
	var am := Loot.spawn_ammo(game.room, base + Vector3(2.5, 0.0, 3.0))
	var am_ok := 0
	for m in _meshes(am):
		if _outlined(m):
			am_ok += 1
	check(am_ok == 2, "ящик патронов обведён (ящик и обруч, не метка): %d" % am_ok)
	things.append(am)
	var ch := Loot.spawn_chest(game.room, base + Vector3(3.5, 0.0, 2.0))
	check(_all_outlined(ch.get_node("Model")) and not _outlined(ch.get_node("Ring")), "сундук обведён, кольцо — нет")
	things.append(ch)
	# Мьёльнир в полёте
	var p := game.player
	p.mjolnir.throw_hammer()
	await wait(0.1)
	var proj := p.mjolnir.projectile
	check(proj != null and _all_outlined(proj._mesh_root), "Мьёльнир в полёте обведён")
	p.mjolnir.force_return_instant()
	await wait(0.1)
	return things

func _test_walls() -> void:
	print("-- Стены, пол, декор, руки")
	var bad := 0
	var total := 0
	for m in game.room.find_children("*", "MeshInstance3D", true, false):
		var gi := m as GeometryInstance3D
		var owner_ok := false
		var n: Node = gi
		while n and n != game.room:
			if n is Enemy or n is Destructible or n is WeaponPickup or n is AmmoPickup or n is Chest or n.is_in_group("debris"):
				owner_ok = true
				break
			n = n.get_parent()
		if owner_ok:
			continue
		total += 1
		if _outlined(gi) or gi.material_overlay == Outline.material():
			bad += 1
			print("    лишняя обводка: ", gi.get_path())
	check(total > 20 and bad == 0, "стены/пол/декор зала без обводки (мешей %d, обведено %d)" % [total, bad])
	var vm := game.player.get_node_or_null("Head/Camera/ViewmodelContainer/SubViewport")
	var vm_bad := 0
	if vm:
		for m in vm.find_children("*", "MeshInstance3D", true, false):
			if (m as GeometryInstance3D).material_overlay == Outline.material():
				vm_bad += 1
	check(vm != null and vm_bad == 0, "руки и оружие от первого лица без обводки")

func _test_flash(enemies: Array) -> void:
	print("-- Вспышка урона и обводка")
	var e := enemies[0] as Enemy
	e._set_overlay(1.0, 0.0)
	var g := e._flash_meshes[0]
	check(g.material_overlay == Enemy.FLASH_MATERIAL and Outline.flash_next_pass() == Outline.material(),
		"при вспышке: оверлей — вспышка, обводка — её next_pass")
	e._set_overlay(0.0, 0.0)
	check(g.material_overlay == Outline.material(), "вспышка погасла — оверлей снова обводка")
	# Состояния стихий используют тот же слот, что вспышка и обводка.
	e.status_glow = Color(1.0, 0.2, 0.0, 0.7)
	e._set_overlay(0.0, 0.0)
	var glow: Color = g.get_instance_shader_parameter("elite")
	check(g.material_overlay == Enemy.FLASH_MATERIAL and Outline.flash_next_pass() == Outline.material()
		and glow.r > 0.9 and glow.a > 0.6, "подсветка стихии и обводка вместе")
	GameSettings.set_value("video", "outline", false, false)
	check(g.material_overlay == Enemy.FLASH_MATERIAL and Outline.flash_next_pass() == null,
		"выключение обводки не гасит подсветку стихии")
	GameSettings.set_value("video", "outline", true, false)
	e.status_glow = Color(0, 0, 0, 0)
	e._set_overlay(0.0, 0.0)
	var el := game.room._make_enemy("grunt")
	Loot.make_elite(el)
	el.position = game.room.to_local(game.room.global_position + Vector3(0, 0.05, 5))
	game.room.add_child(el)
	game.room._register(el)
	el.set_physics_process(false)
	await wait(0.2)
	el._set_overlay(0.0, 0.0)
	check(_all_outlined(el._visual), "элита (постоянное свечение) обведена")
	enemies.append(el)

func _test_budget() -> void:
	print("-- Текущие instance-материалы (толпа 40; не занятые слоты)")
	var base := game.room.global_position
	for i in 40:
		var e := game.room.spawn_extra("fodder" if i % 4 else "grunt", base + Vector3(randf_range(-7, 7), 0.05, randf_range(-8, 0)))
		if e:
			e.set_physics_process(false)
	await wait(0.3)
	var on_iu := FX.instance_uniform_users(get_tree().root)
	var on_count := Outline.active_count()
	GameSettings.set_value("video", "outline", false, false)
	await wait(0.05)
	var off_iu := FX.instance_uniform_users(get_tree().root)
	GameSettings.set_value("video", "outline", true, false)
	await wait(0.05)
	print("    обведено узлов %d; текущие instance-материалы: с обводкой %d, без %d" % [on_count, on_iu, off_iu])
	check(on_count > 200, "толпа обведена (%d узлов)" % on_count)
	check(on_iu == off_iu, "обводка не меняет число текущих instance-материалов (%d = %d)" % [on_iu, off_iu])
	var mats := {}
	for n in get_tree().get_nodes_in_group(Outline.GROUP):
		var m := (n as GeometryInstance3D).material_overlay
		if m == Enemy.FLASH_MATERIAL:
			m = m.next_pass
		if m:
			mats[m.get_instance_id()] = true
	check(mats.size() == 1, "у всех обведённых узлов один и тот же материал (%d разных)" % mats.size())

func _test_setting(enemies: Array, things: Array) -> void:
	print("-- Настройка: вкл/выкл и толщина вживую")
	GameSettings.set_value("video", "outline", false, false)
	await wait(0.05)
	var left := 0
	for n in get_tree().get_nodes_in_group(Outline.GROUP):
		if (n as GeometryInstance3D).material_overlay == Outline.material():
			left += 1
	check(left == 0 and Outline.active_count() == 0, "выключили — обводки нет нигде (осталось %d)" % left)
	check(Outline.flash_next_pass() == null, "выключили — и у вспышки нет next_pass")
	var e := enemies[1] as Enemy
	e._set_overlay(1.0, 0.0)
	e._set_overlay(0.0, 0.0)
	check(e._flash_meshes[0].material_overlay == null, "после вспышки при выключенной обводке — оверлея нет")
	var fresh := game.room.spawn_extra("grunt", game.room.global_position + Vector3(0, 0.05, -5))
	await wait(0.2)
	var fresh_clean := true
	for m in _meshes(fresh._visual):
		if (m as GeometryInstance3D).material_overlay == Outline.material():
			fresh_clean = false
	check(fresh_clean, "новый враг при выключенной обводке — без неё")
	GameSettings.set_value("video", "outline", true, false)
	await wait(0.05)
	check(_all_outlined(fresh._visual), "включили — новый враг обведён")
	var all_back := true
	for t in things:
		if is_instance_valid(t) and t is Destructible and not _all_outlined((t as Node).get_node("Model")):
			all_back = false
	check(all_back and Outline.flash_next_pass() == Outline.material(), "включили — пропсы и вспышка снова с обводкой")
	GameSettings.set_value("video", "outline_width", 1.5, false)
	check(absf(float(Outline.material().get_shader_parameter("width_scale")) - 1.5) < 0.001, "толщина 150 % — сразу в материале")
	GameSettings.set_value("video", "outline_width", 9.0, false)
	check(absf(float(GameSettings.get_value("video", "outline_width")) - Outline.WIDTH_MAX) < 0.001
		and absf(float(Outline.material().get_shader_parameter("width_scale")) - Outline.WIDTH_MAX) < 0.001, "толщина ограничена %d %%" % roundi(Outline.WIDTH_MAX * 100))
	GameSettings.set_value("video", "outline_width", 1.0, false)
	# Если у объекта появился чужой оверлей, переключатель не должен его уничтожать.
	var sample := MeshInstance3D.new()
	var custom := StandardMaterial3D.new()
	sample.material_overlay = custom
	game.add_child(sample)
	Outline.add(sample)
	GameSettings.set_value("video", "outline", false, false)
	GameSettings.set_value("video", "outline", true, false)
	check(sample.material_overlay == custom, "переключение сохраняет чужой оверлей")
	sample.queue_free()

func _test_warmup() -> void:
	print("-- Прогрев")
	GameSettings.set_value("video", "outline", false, false)
	Outline.begin_warmup()
	check(Outline.overlay() == Outline.material() and Outline.flash_next_pass() == Outline.material(),
		"при прогреве образцы обводятся и при выключенной настройке")
	Outline.end_warmup()
	check(Outline.overlay() == null and Outline.flash_next_pass() == null, "после прогрева — снова по настройке")
	GameSettings.set_value("video", "outline", true, false)
	check(GameSettings.DEFAULTS["video"]["outline"] == true, "по умолчанию обводка включена")

func _test_panel() -> void:
	print("-- Вкладка «Экран»")
	var panel := SettingsPanel.new()
	game.add_child(panel)
	var keys := {}
	for c in panel.find_children("*", "", true, false):
		if c.has_meta("setting"):
			keys[str(c.get_meta("setting"))] = c
	check(keys.has("video/outline") and keys.has("video/outline_width"), "переключатель и ползунок толщины в настройках")
	if keys.has("video/outline"):
		(keys["video/outline"] as CheckBox).button_pressed = false
		check(not Outline.enabled() and Outline.active_count() == 0, "галочка выключает обводку сразу")
		(keys["video/outline"] as CheckBox).button_pressed = true
		check(Outline.enabled() and Outline.active_count() > 0, "и включает обратно")
	panel.queue_free()
