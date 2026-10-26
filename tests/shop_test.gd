extends Node
## Тест серебра и ларька Брокка и Эйтри (блок К, GDD 13, 15.2):
##  • серебро: с врагов (EnemyDef), из разбитой бочки (3–8), из сундука (20), монеты летят к Тору, счётчик в HUD,
##    новый забег — с нуля («Жадность» — 30);
##  • зал-ларёк через дверь: тихий, ларёк из пропсов, два гнома, вывеска, E — экран покупки;
##  • каждый товар списывает серебро и даёт эффект; скидка −15 %; нет денег — не продаёт; реакции Брокка;
##  • «Обслуживание Мьёльнира» без трейтов — переброс выбора трейта.
## godot --headless --path . --fixed-fps 60 res://tests/shop_test.tscn

const DoorHelper := preload("res://tests/door_helper.gd")

var _fails: Array[String] = []
var _passes: int = 0
var game: Game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "ShopRunner"
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
	await DoorHelper.wait(get_tree(), sec)

func _run() -> void:
	print("=== SHOP TEST ===")
	_test_wallet()
	Run.start_run("berserker")
	Run.room_order.assign(["res://rooms/room_01.tscn", "res://rooms/room_02.tscn", Run.BOSS_SCENE])
	Run.forced_offers.assign([["shop", "combat"], ["boss"]])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await wait(0.5)
	game = get_tree().current_scene as Game
	await _test_silver_sources()
	await _test_shop_room()
	await _test_purchases()
	await _test_reroll()
	await wait(2.0)
	_finish()

func _test_wallet() -> void:
	print("-- Кошелёк")
	Run.start_run("berserker")
	check(Run.silver == 0, "новый забег — 0 серебра")
	Run.add_silver(25)
	check(Run.silver == 25 and Run.silver_earned == 25, "серебро прибавилось")
	check(not Run.spend_silver(40) and Run.silver == 25, "нельзя потратить больше, чем есть")
	check(Run.spend_silver(20) and Run.silver == 5, "списание")
	Save.data.unlocks["greed"] = 1
	Run.start_run("berserker")
	check(Run.silver == 30, "«Жадность»: старт с 30 серебра (%d)" % Run.silver)
	Save.data.unlocks.erase("greed")
	Run.start_run("berserker")
	check(Run.silver == 0, "серебро сгорает: следующий забег снова с нуля")
	var greed := Save.get_unlock("greed")
	var disc := Save.get_unlock("discount")
	check(greed != null and greed.available and disc != null and disc.available, "перки «Жадность» и «Скидка у Брокка» продаются")

func _coins() -> int:
	return get_tree().get_nodes_in_group("silver_coins").size()

func _test_silver_sources() -> void:
	print("-- Источники серебра")
	var hud_silver := game.hud.find_child("SilverHUD", true, false)
	check(hud_silver != null, "счётчик серебра в HUD")
	await wait(1.4)
	var room := game.room
	# Враги
	var s0 := Run.silver
	var expected := 0
	for e in room.alive_enemies().duplicate():
		expected += e.enemy_def.silver_min if e.enemy_def and not Loot.is_elite(e) else 0
		e.take_hit(9999, Vector3(0, 3, -5), "melee_finisher")
	await wait(0.1)
	check(_coins() > 0, "с врагов выпали монеты (%d)" % _coins())
	await wait(3.0)
	check(Run.silver >= s0 + expected and Run.silver > s0, "монеты долетели до Тора: %d → %d (не меньше %d)" % [s0, Run.silver, s0 + expected])
	check(_coins() == 0, "все монеты собраны")
	if hud_silver:
		var lbl := hud_silver.find_children("*", "Label", true, false)
		check(not lbl.is_empty() and (lbl[0] as Label).text.contains(str(Run.silver)), "HUD показывает %d" % Run.silver)
	# Бочка
	var barrel: RigidBody3D = null
	for n in get_tree().get_nodes_in_group("props"):
		if n is RigidBody3D and (n as RigidBody3D).scene_file_path == BarrelWatch.BARREL_SCENE:
			barrel = n
			break
	check(barrel != null, "в зале есть бочка")
	if barrel:
		var s1 := Run.silver
		barrel.linear_velocity = Vector3(1, 0, 0)
		await wait(0.2)
		check(is_instance_valid(barrel) and not barrel.is_queued_for_deletion(), "медленная бочка цела")
		barrel.linear_velocity = Vector3(14, 3, 0)
		await wait(0.1)
		check(not is_instance_valid(barrel) or barrel.is_queued_for_deletion(), "отброшенная бочка разбилась")
		await wait(3.0)
		var got := Run.silver - s1
		check(got >= 3 and got <= 8, "из бочки 3–8 серебра (%d)" % got)
	# Сундук
	var p := game.player
	var s2 := Run.silver
	var fwd := p.get_aim_forward()
	fwd.y = 0
	var chest := Loot.spawn_chest(game.room, p.global_position + fwd.normalized() * 2.0)
	await wait(0.2)
	var before := get_tree().get_nodes_in_group("silver_coins")
	chest.interact(p.weapons)
	var chest_silver := 0
	for c in get_tree().get_nodes_in_group("silver_coins"):
		if not c in before:
			chest_silver += (c as SilverCoin).value
	await wait(3.0)
	check(chest_silver == 20 and Run.silver - s2 >= 20, "сундук: +20 серебра (%d)" % chest_silver)
	# Элита: оружие или 10 серебра (GDD 12.4) — решает Loot, обычного серебра у неё нет
	var e2 := (load("res://enemies/grunt.tscn") as PackedScene).instantiate() as Enemy
	Loot.make_elite(e2)
	check(Silver.for_enemy(e2) == 0 and Silver.cfg().elite_silver == 10 and Loot.elite_silver_chance > 0.0, "элита роняет оружие или 10 серебра")
	e2.free()

func _kill_all(room: Room) -> void:
	var safety := 0
	while not room._is_cleared and safety < 40:
		safety += 1
		await wait(1.0)
		for e in room.alive_enemies().duplicate():
			if is_instance_valid(e):
				e.take_hit(9999, Vector3(0, 3, -5), "melee_finisher")
		game.player.heal(999)

func _test_shop_room() -> void:
	print("-- Зал-ларёк")
	await _kill_all(game.room)
	await wait(1.5)
	await DoorHelper.resolve_reward(get_tree(), game)
	var ids := game.rewards.doors.map(func(d: RewardDoor) -> String: return d.reward_id)
	check(ids.has("shop"), "дверь ларька (%s)" % ", ".join(ids))
	await DoorHelper.take_door(get_tree(), game, ids.find("shop"))
	check(Run.current_reward() == "shop" and game.room.scene_file_path == Run.map.shop_scene, "загружен зал-ларёк (%s)" % game.room.scene_file_path)
	await wait(1.2)
	check(Run.is_peaceful_room() and game.room.alive_count() == 0, "в ларьке без боя")
	var stall := game.room.get_node_or_null("ShopStall") as ShopStall
	check(stall != null, "ларёк на месте")
	if stall == null:
		return
	check(stall.brokk != null and stall.eitri != null and stall.brokk.scale.x < 0.8, "два гнома, маленькие (×%.2f)" % stall.brokk.scale.x)
	check(stall.brokk.hair.contains("Beard"), "у гномов бороды")
	var sign := stall.find_child("Sign", true, false) as Label3D
	check(sign != null and sign.text == "РУНЫ • ШАУРМА • ЗАТОЧКА", "вывеска «РУНЫ • ШАУРМА • ЗАТОЧКА»")
	check(stall.find_children("*", "Node3D", true, false).size() > 12, "ларёк собран из пропсов")
	check(game.rewards.doors.size() >= 1, "двери дальше уже стоят (%d)" % game.rewards.doors.size())
	# Подойти и нажать E
	var p := game.player
	p.global_position = stall.global_position + Vector3(0, 0.1, 0.6)
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2(-0.2, 0.0)
	await wait(0.4)
	check(p.weapons.focused() == stall, "ларёк в фокусе: «%s»" % p.weapons._prompt)
	p.weapons.interact()
	await wait(0.3)
	var shop := game.rewards.shop
	check(shop != null and shop.visible and get_tree().paused, "E — экран ларька, игра на паузе")
	check(shop._rows.get_child_count() == 7, "все 7 товаров GDD 13 (%d)" % shop._rows.get_child_count())
	check(shop._speech.text != "", "Брокк что-то сказал: «%s»" % shop._speech.text)
	shop.close()
	await wait(0.2)
	check(not get_tree().paused, "ларёк закрыт — пауза снята")

func _item(id: String) -> ShopItemDef:
	return Shop.get_item(id)

func _test_purchases() -> void:
	print("-- Покупки")
	var p := game.player
	var shop := game.rewards.shop
	shop.open()
	await wait(0.4)
	shop._open_time = -10.0
	Run.silver = 1000
	# Шаурма
	p.health = 50.0
	var r := shop.try_buy(_item("shawarma"))
	check(r.ok and Run.silver == 960, "шаурма: −40 (%d)" % Run.silver)
	check(absf(p.health - minf(p.max_health, 50.0 + p.max_health * 0.3 * float(p.modify_stat(&"heal_mult", 1.0)))) < 0.6, "шаурма лечит 30 %% (%.0f)" % p.health)
	# Руна 1 из 3
	var runes0 := Run.runes.size()
	r = shop.try_buy(_item("rune"))
	await wait(0.1)
	check(r.ok and Run.silver == 900, "руна: −60 (%d)" % Run.silver)
	check(game.rune_pick.visible and not shop.visible, "выбор руны поверх ларька")
	game.rune_pick._open_time = -10.0
	game.rune_pick.choose(0)
	await wait(0.2)
	check(Run.runes.size() == runes0 + 1, "руна взята")
	check(shop.visible and get_tree().paused, "после выбора — снова ларёк")
	check(game.rewards.doors.size() >= 1 and game.rewards.doors[0].is_inside_tree(), "двери не пересоздались")
	# Заточка 80 / 120
	var w := p.weapons.melee
	w.level = 1
	r = shop.try_buy(_item("sharpen"))
	check(r.ok and w.level == 2 and Run.silver == 820, "заточка 1→2: −80 (ур. %d, %d)" % [w.level, Run.silver])
	r = shop.try_buy(_item("sharpen"))
	check(r.ok and w.level == 3 and Run.silver == 700, "заточка 2→3: −120 (ур. %d, %d)" % [w.level, Run.silver])
	check(Shop.unavailable_reason(game, _item("sharpen")) != "", "уровень 3 — точить нечего")
	# Патроны
	check(Shop.unavailable_reason(game, _item("ammo")) != "", "без ренжа патроны не продаются")
	p.weapons.equip(Loot.get_def("crossbow"), 1, false)
	p.weapons.ranged.reserve = 0
	r = shop.try_buy(_item("ammo"))
	check(r.ok and p.weapons.ranged.reserve == p.weapons.ranged.def.reserve_max and Run.silver == 670, "патроны: полный запас, −30 (%d)" % Run.silver)
	# Обслуживание Мьёльнира: без трейтов — переброс; с трейтом — уровень
	Run.mjolnir_traits.clear()
	Run.mjolnir_trait_levels.clear()
	r = shop.try_buy(_item("mjolnir_service"))
	check(r.ok and Run.trait_rerolls == 1 and Run.silver == 570, "обслуживание без трейтов: переброс заказан, −100")
	var t: MjolnirTrait = Run.all_mjolnir_traits[0]
	Run.add_mjolnir_trait(t)
	r = shop.try_buy(_item("mjolnir_service"))
	await wait(0.1)
	check(shop._sub.visible, "обслуживание: выбор трейта")
	var idx := shop._sub.index_of(str(t.id))
	shop._sub.choose(idx, true)
	await wait(0.1)
	check(Run.mjolnir_trait_level(t.id) == 2 and Run.silver == 470, "трейт %s — уровень 2, −100 (%d)" % [t.id, Run.silver])
	check(shop.visible, "снова ларёк")
	# Кот в мешке
	r = shop.try_buy(_item("mystery_bag"))
	check(r.ok and Run.silver <= 420 + Shop.BAG_SILVER and r.text != "", "кот в мешке: −50, «%s»" % r.text)
	var hp := p.health
	var n_runes := Run.runes.size()
	Shop._open_bag(game, "rune")
	check(Run.runes.size() == n_runes + 1, "мешок: руна")
	var sv := Run.silver
	Shop._open_bag(game, "silver")
	check(Run.silver == sv + Shop.BAG_SILVER, "мешок: серебро")
	p.health = 100.0
	Shop._open_bag(game, "curse")
	check(p.health < 100.0, "мешок: проклятие (%.0f)" % p.health)
	Shop._open_bag(game, "heal")
	check(p.health > 75.0, "мешок: лечение")
	var picks := 0
	for c in game.room.get_children():
		if c is WeaponPickup:
			picks += 1
	Shop._open_bag(game, "weapon")
	await wait(0.1)
	var picks2 := 0
	for c in game.room.get_children():
		if c is WeaponPickup:
			picks2 += 1
	check(picks2 == picks + 1, "мешок: оружие ур. 2–3")
	# Сдать руну: +20
	var sell_id: String = Run.runes[0].id
	sv = Run.silver
	r = shop.try_buy(_item("sell_rune"))
	await wait(0.1)
	check(shop._sub.visible, "сдать руну: выбор руны")
	var si := shop._sub.index_of(sell_id)
	if si < 0:
		sell_id = str(shop._sub._choices[0].id)
		si = 0
	shop._sub.choose(si, true)
	await wait(0.1)
	check(Run.rune_count(sell_id) == 0 and Run.silver == sv + 20, "руна %s сдана: +20 (%d)" % [sell_id, Run.silver])
	# Скидка «Плана тренировок»
	Save.data.unlocks["discount"] = 1
	check(Shop.price(game, _item("shawarma")) == 34, "скидка −15 %%: шаурма за %d" % Shop.price(game, _item("shawarma")))
	Save.data.unlocks.erase("discount")
	# Нет денег
	Run.silver = 10
	p.health = 40.0
	shop.refresh()
	r = shop.try_buy(_item("shawarma"))
	check(not r.ok and Run.silver == 10 and is_equal_approx(p.health, 40.0), "без серебра Брокк не продаёт")
	check(shop._speech.text != "", "Брокк ворчит: «%s»" % shop._speech.text)
	p.health = p.max_health
	check(Shop.reaction_pool(game) == "dwarves.shop_broke", "реакция «нет денег»")
	p.health = p.max_health * 0.2
	check(Shop.reaction_pool(game) == "dwarves.shop_low_hp", "реакция «мало HP»")
	p.health = p.max_health
	Run.silver = 400
	check(Shop.reaction_pool(game) == "dwarves.shop_rich", "реакция «много серебра»")
	shop.close()
	await wait(0.2)

func _test_reroll() -> void:
	print("-- Переброс трейта")
	Run.trait_rerolls = 1
	var choices := Run.random_mjolnir_trait_choices(3)
	game.trait_pick.open(choices)
	await wait(0.1)
	check(game.trait_pick._reroll_btn.visible, "кнопка переброса видна")
	game.trait_pick.reroll_requested.emit()
	await wait(0.1)
	check(Run.trait_rerolls == 0 and game.trait_pick.visible and not game.trait_pick._reroll_btn.visible, "переброс использован, новый выбор")
	game.trait_pick._open_time = -10.0
	game.trait_pick.choose(0, true)
	await wait(0.2)

func _finish() -> void:
	print("=== ИТОГ: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
