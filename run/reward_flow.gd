extends Node
class_name RewardFlow
## Двери-награды (блок И, GDD 15.1): что выдаётся после зачистки зала и какие двери открываются дальше.
## Цикл: зал зачищен → (трейт после мини-босса) → награда зала по типу двери, через которую вошли →
## 2–3 двери с иконками следующих наград → вошёл в дверь → следующий зал с этой наградой.
## Тихие залы (Отдых, Ларёк) — без врагов: награда сразу при входе.
## Узел создаётся в Game (RewardFlow.attach), экраны выбора строит сам (ChoicePick).

signal doors_shown(doors: Array)
signal reward_granted(id: String)

var game: Game
var choice: ChoicePick
## Экран ларька (блок К), создаётся при первом открытии
var shop: ShopScreen
## Двери текущего зала
var doors: Array[RewardDoor] = []
## Что сейчас выбирается в RunePick: "rune" / "freya" / "upgrade"
var rune_mode: String = "rune"
var _choice_kind: String = ""
var _granted: bool = false

static func attach(g: Game) -> RewardFlow:
	var f := RewardFlow.new()
	f.name = "RewardFlow"
	f.game = g
	g.add_child(f)
	return f

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	choice = ChoicePick.new()
	choice.name = "ChoicePick"
	add_child(choice)
	choice.picked.connect(_on_choice_picked)
	# Бочки, которые разбили, роняют серебро (блок К)
	var bw := BarrelWatch.new()
	bw.name = "BarrelWatch"
	add_child(bw)
	if game and game.trait_pick:
		game.trait_pick.reroll_requested.connect(_on_trait_reroll)

func map() -> RunMap:
	return Run.map if Run.map else RunMap.new()

func is_screen_open() -> bool:
	return choice.visible or (shop != null and shop.is_open())

# --- Зал загружен / начат ---

## Новый зал (до start): элитный бой — больше элиты; сброс дверей.
func on_room_loaded(room: Room) -> void:
	doors.clear()
	_granted = false
	rune_mode = "rune"
	var id := Run.current_reward()
	if id == "elite":
		room.elite_chance = map().elite_room_chance
		room.max_elites = map().elite_room_max

## Вместо room.start: тихий зал не будит врагов, награда — сразу.
func start_room(room: Room, player: Player) -> void:
	if Run.doors_enabled and Run.is_peaceful_room():
		Perf.mark("peaceful_room")
		game.hud.set_enemy_count(0)
		_start_peaceful(room)
	else:
		room.start(player)

func _start_peaceful(room: Room) -> void:
	match Run.current_reward():
		"rest":
			_decorate_rest(room)
			Odin.say("rest")
			get_tree().create_timer(0.7, false).timeout.connect(func() -> void:
				if not game.player.is_dead:
					grant())
		"shop":
			Dialogue.bark_pool("dwarves.shop_enter")
			grant()
		_:
			grant()

## Отдых: котёл с похлёбкой и тёплый свет посреди зала (модели Quaternius, без новых материалов).
func _decorate_rest(room: Room) -> void:
	var at := room.get_spawn_transform().origin + room.get_spawn_transform().basis.z * -5.0
	var n := Node3D.new()
	n.name = "RestCamp"
	room.add_child(n)
	n.global_position = Loot.floor_point(room, at)
	for item in [["res://assets/quaternius/props/Cauldron.gltf", Vector3.ZERO, 1.3], ["res://assets/quaternius/props/Barrel.gltf", Vector3(1.6, 0, 0.4), 1.0], ["res://assets/quaternius/props/Potion_1.gltf", Vector3(-1.2, 0, 0.3), 2.0]]:
		if ResourceLoader.exists(item[0]):
			var m := (load(item[0]) as PackedScene).instantiate() as Node3D
			m.position = item[1]
			m.scale = Vector3.ONE * float(item[2])
			n.add_child(m)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.65, 0.3)
	l.light_energy = 2.5
	l.omni_range = 7.0
	l.position = Vector3(0, 1.4, 0)
	n.add_child(l)

# --- Награда зала ---

## Выдать награду текущего зала (после зачистки; для мини-босса — после трейта).
func grant() -> void:
	if _granted:
		return
	_granted = true
	var id := Run.current_reward()
	Perf.mark("reward_" + id)
	reward_granted.emit(id)
	match id:
		"freya":
			_offer_runes("freya")
		"elite":
			_grant_elite()
		"chest", "shop":
			# Сундук ставит Loot.on_room_cleared там, где пал последний враг; ларёк — подойти к прилавку (E)
			finish()
		"rest":
			_offer_rest()
		"loki":
			_offer_loki()
		_:
			_offer_runes("rune")

## Награда выдана — открыть двери (или старая дверь, если двери выключены).
func finish() -> void:
	game.call("_after_reward")

func _offer_runes(mode: String) -> void:
	rune_mode = mode
	var choices := Run.random_rune_choices(3)
	if choices.is_empty():
		finish()
		return
	var title := ""
	if mode == "freya":
		title = "БЛАГОСЛОВЕНИЕ ФРЕЙИ — РУНА СРАЗУ УР. %d" % map().freya_rune_level
		Dialogue.bark_pool("freya.blessing")
	game.rune_pick.open(choices, title)

## Game._on_rune_picked уже добавил руну; Фрейя добавляет ещё уровни (повтор руны = уровень).
## false — награда зала не закончена (руна куплена в ларьке: вернуться в ларёк, двери не трогать).
func on_rune_picked(rune: RuneDef) -> bool:
	if rune_mode == "shop":
		rune_mode = "rune"
		game.hud.toast("%s %s — уровень %d" % [rune.glyph, rune.title, Run.rune_count(rune.id)])
		if shop:
			shop.reopen()
			shop.say("Руна «%s». Почти не проклятая." % rune.title, "smug")
		return false
	if rune_mode == "freya":
		var target := mini(map().freya_rune_level, map().rune_max_level)
		while Run.rune_count(rune.id) < target:
			Run.add_rune(rune)
		Dialogue.bark_pool("freya.blessing_pick")
		game.hud.toast("ᛒ %s — уровень %d" % [rune.title, Run.rune_count(rune.id)])
	elif rune_mode == "upgrade":
		game.hud.toast("%s %s — уровень %d" % [rune.glyph, rune.title, Run.rune_count(rune.id)])
	rune_mode = "rune"
	return true

func _front_point(dist: float = 2.5) -> Vector3:
	var p := game.player
	var fwd := p.get_aim_forward()
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	return p.global_position + fwd * dist

## Элитный бой: оружие (60 % мили / 40 % ренж) + серебро + Слава.
func _grant_elite() -> void:
	var d := Loot.random_def("melee" if randf() < 0.6 else "ranged")
	if d == null:
		d = Loot.random_def()
	var at := _front_point()
	if d:
		Loot.spawn_weapon(game.room, at, WeaponItem.create(d, Loot.random_level()), at + Vector3(0, 2.0, 0))
	Run.add_glory(map().elite_reward_glory)
	_give_silver(map().elite_reward_silver)
	Odin.say("elite_reward")
	game.hud.toast("ЭЛИТА ПОВЕРЖЕНА: ОРУЖИЕ + СЛАВА")
	finish()

## Серебро (блок К): монеты рассыпаются перед Тором и летят к нему.
func _give_silver(amount: int) -> void:
	Silver.drop(game.room, _front_point(1.5), amount)

# --- Отдых ---

## Руны, которые можно улучшить (повтор = уровень, до rune_max_level; одноразовое лечение — нет).
func upgradable_runes() -> Array[RuneDef]:
	var out: Array[RuneDef] = []
	var seen := {}
	for r in Run.runes:
		if seen.has(r.id) or r.id == "heal":
			continue
		seen[r.id] = true
		if Run.rune_count(r.id) < map().rune_max_level:
			out.append(r)
	return out

func _offer_rest() -> void:
	var p := game.player
	var heal := int(round(p.max_health * map().rest_heal_fraction))
	var ups := upgradable_runes()
	_choice_kind = "rest"
	choice.open("ПРИВАЛ", "Один разрешил пять минут. Выбери одно.", [
		{"id": "heal", "title": "Похлёбка", "desc": "Лечение %d %% (+%d HP)" % [int(map().rest_heal_fraction * 100), heal], "glyph": "ᚹ", "color": Color(0.45, 1.0, 0.55)},
		{"id": "upgrade", "title": "Точить руну", "desc": "Улучшить руну на 1 уровень" if not ups.is_empty() else "Нет рун для улучшения", "glyph": "ᚱ", "color": Color(0.55, 0.8, 1.0), "enabled": not ups.is_empty()},
	], "odin", "neutral")

# --- Сделка Локи ---

func _offer_loki() -> void:
	var m := map()
	_choice_kind = "loki"
	Dialogue.bark_pool("loki.deal")
	choice.open("СДЕЛКА ЛОКИ", "Проклятых рун у Локи пока нет, зато есть риск. Подписывай, не читая.", [
		{"id": "blood", "title": "Кровь за сталь", "desc": "−%d %% здоровья → легендарное оружие (ур. 3)" % int(m.loki_hp_cost * 100), "glyph": "ᛚ", "color": Color(0.35, 0.9, 0.35), "enabled": game.player.health > 2.0},
		{"id": "dice", "title": "Кости Локи", "desc": "%d %%: две руны. Иначе −%d %% здоровья" % [int(m.loki_dice_win_chance * 100), int(m.loki_dice_hp_loss * 100)], "glyph": "ᛜ", "color": Color(0.6, 0.95, 0.4)},
		{"id": "refuse", "title": "Отказаться", "desc": "Локи обидится. Ненадолго.", "glyph": "ᚾ", "color": Color(0.7, 0.7, 0.7)},
	], "loki", "smug")

func _loki_result(id: String) -> void:
	var m := map()
	var p := game.player
	match id:
		"blood":
			p.take_damage(p.health * m.loki_hp_cost, Vector3.ZERO, true)
			var d := Loot.random_def("melee" if randf() < 0.6 else "ranged")
			if d == null:
				d = Loot.random_def()
			var at := _front_point()
			if d:
				Loot.spawn_weapon(game.room, at, WeaponItem.create(d, 3), at + Vector3(0, 2.0, 0))
			Dialogue.bark_pool("loki.deal_blood")
			game.hud.toast("ЛЕГЕНДАРНОЕ ОРУЖИЕ — ЗА ПОЛОВИНУ ЗДОРОВЬЯ")
		"dice":
			if randf() < m.loki_dice_win_chance:
				var got: Array[String] = []
				for r in Run.random_rune_choices(2):
					Run.add_rune(r)
					got.append(r.title)
				p.recalc_from_runes(Run)
				Dialogue.bark_pool("loki.deal_dice_win")
				game.hud.toast("КОСТИ: " + ", ".join(got))
			else:
				p.take_damage(p.health * m.loki_dice_hp_loss, Vector3.ZERO, true)
				Dialogue.bark_pool("loki.deal_dice_lose")
				game.hud.toast("КОСТИ: НЕ ПОВЕЗЛО")
		_:
			Dialogue.bark_pool("loki.deal_refuse")

func _on_choice_picked(id: String) -> void:
	var kind := _choice_kind
	_choice_kind = ""
	match kind:
		"rest":
			if id == "upgrade":
				rune_mode = "upgrade"
				var ups := upgradable_runes()
				ups.shuffle()
				game.rune_pick.open(ups.slice(0, 3), "УЛУЧШИТЬ РУНУ (+1 УРОВЕНЬ)")
				return
			var p := game.player
			p.heal(p.max_health * map().rest_heal_fraction)
			Audio.play("sounds/sfx/rune_pick.wav")
			game.hud.toast("ПОХЛЁБКА: +%d %% ЗДОРОВЬЯ" % int(map().rest_heal_fraction * 100))
		"loki":
			_loki_result(id)
	finish()

# --- Ларёк (блок К) ---

## Открыть экран ларька (E у прилавка). Первый раз — сцена знакомства (если сцены в забеге разрешены).
func open_shop() -> void:
	if shop == null:
		shop = ShopScreen.new()
		shop.name = "Shop"
		shop.game = game
		add_child(shop)
	if shop.is_open():
		return
	if Dialogue.in_run_scenes:
		await Dialogue.run_trigger("shop_enter")
	else:
		Save.bump_event("shop_enter")
	shop.open()
	var stall := get_tree().get_first_node_in_group("shop_stall") as ShopStall
	if stall:
		stall.nod("brokk")

## Переброс выбора трейта (заказан в ларьке): новые 3 карточки.
func _on_trait_reroll() -> void:
	if Run.trait_rerolls <= 0:
		return
	Run.trait_rerolls -= 1
	Perf.mark("trait_reroll")
	var traits := Run.random_mjolnir_trait_choices(3)
	if not traits.is_empty():
		game.trait_pick.open(traits)

# --- Двери ---

## Поставить 2–3 двери с наградами у северной стены зала (у старой двери).
func show_doors() -> void:
	var room := game.room
	if room == null or Run.is_boss_room():
		return
	Perf.mark("doors_show")
	var offers := Run.roll_door_offers()
	var half_w := 12.0
	var wall := room.get_node_or_null("Geometry/WallE") as Node3D
	if wall:
		half_w = wall.position.x - 0.5
	var z := -10.0
	if room.door:
		z = room.door.position.z + 1.5
	var n := offers.size()
	var spacing := clampf((half_w * 2.0 - 4.0) / maxf(1.0, n - 1.0), 3.0, 4.6) if n > 1 else 0.0
	doors.clear()
	for i in n:
		var id := offers[i]
		var def := Run.reward_def(id)
		var d := RewardDoor.create(def, id)
		var x := (i - (n - 1) / 2.0) * spacing
		x = clampf(x, -half_w + 1.8, half_w - 1.8)
		var local := Vector3(x, 0, z)
		var ground := Loot.floor_point(room, room.to_global(local))
		room.add_child(d)
		d.global_position = ground
		d.rotation.y = 0.0
		d.appear(0.12 * i)
		d.entered.connect(_on_door_entered)
		doors.append(d)
	# Следующий зал (ларёк — свой) грузим в фоне, пока игрок выбирает
	if "shop" in offers and Run.map and ResourceLoader.exists(Run.map.shop_scene):
		ResourceLoader.load_threaded_request(Run.map.shop_scene, "", true)
	Audio.play("sounds/sfx/door_open.wav")
	game.hud.toast("ВЫБЕРИ ДВЕРЬ" if n > 1 else "ДВЕРЬ ОТКРЫТА — ВПЕРЁД!")
	if n > 1:
		Odin.say("doors")
	doors_shown.emit(doors)

func _on_door_entered(door: RewardDoor) -> void:
	for d in doors:
		if d != door and is_instance_valid(d):
			d.dim()
	Run.choose_door(door.reward_id)
	game.call("_on_exit_reached")

## Тесты: войти в дверь с наградой id (или по индексу). false — такой двери нет.
func take_door(id: String = "", index: int = 0) -> bool:
	for i in doors.size():
		var d := doors[i]
		if is_instance_valid(d) and not d.used and ((id != "" and d.reward_id == id) or (id == "" and i == index)):
			d.used = true
			_on_door_entered(d)
			return true
	return false

## Образцы для прогрева шейдеров (ShaderWarmup): дверь с иконкой-глифом и подписями.
static func warmup_samples(parent: Node3D, right: Vector3) -> void:
	var d := RewardDoor.create(Run.reward_def("combat"), "combat")
	d.set_meta("warmup", true)
	parent.add_child(d)
	d.position = right * -2.4 + Vector3(0, -1.0, -1.0)
	d.scale = Vector3.ONE * 0.5
	for path in ["res://assets/quaternius/props/Cauldron.gltf", "res://assets/quaternius/props/Potion_1.gltf"]:
		if ResourceLoader.exists(path):
			var m := (load(path) as PackedScene).instantiate() as Node3D
			parent.add_child(m)
			m.position = right * 2.4 + Vector3(0, -0.6, 0)
			m.scale = Vector3.ONE * 0.4
