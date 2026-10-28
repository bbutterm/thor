extends Node
## Тест трейтов Мьёльнира (GDD 10, блок Б4 «стихии × приёмы»):
##  • база: втыкается в стену, сам возвращается; идеальный хват → следующий бросок ×2; без молота рывок быстрее;
##  • данные: 5 стихий (4 уровня), 13 приёмов, 5 связок; все бывшие 13 трейтов нашли место; открытия
##    «Плана тренировок» (ice_trail, lightning_rod, sky_thunder, heaviness, earthquake…) работают и не «скоро»;
##  • правила: одна стихия, не больше двух приёмов (и это настраивается), несовместимые заменяют друг друга,
##    в одном наборе нет несовместимых, после мини-босса — и стихия, и приём, наковальня — только стихии;
##  • выбор: экран (связка — особая карточка, замена с подтверждением), объявление связки, HUD, наковальня Эйтри;
##  • каждая стихия на уровнях 1–4: эффект на враге, след, аура, удар с неба, связка с ударом-приземлением;
##  • каждый приём на уровнях 1–2 и каждая связка; окружение — лужи браги под током и в огне, бочки.
## godot --headless --path . --fixed-fps 60 res://tests/trait_test.tscn

var _fails: Array[String] = []
var _passes: int = 0
var game: Game
var p: Player
var hand: MjolnirHand
## Длинный дом Ярла (Run.BOSS_SCENE): стена за «стенными» манекенами (16 м вперёд) — в 2 м от них
const START := Vector3(-3, 0.1, -4)
const ELEMENTS := [&"fire", &"ice", &"lightning", &"earth", &"wind"]
const TECHNIQUES := [&"pull_to_hammer", &"magnet", &"boomerang", &"ricochet", &"storm", &"two_hammers",
	&"hammer_step", &"swap", &"hammer_dive", &"sling", &"charge", &"air_catch", &"loyal_dog"]
const COMBOS := [&"fire_tornado", &"ice_ricochet", &"lightning_magnet", &"wind_pull", &"earth_dive"]
## Бывшие 13 трейтов → где они теперь (id стихии/приёма или id уровня стихии в level_pool_ids)
const OLD_TRAITS := [&"fire_trail", &"ice_trail", &"pull_to_hammer", &"magnet", &"boomerang", &"chain_lightning",
	&"heaviness", &"ricochet", &"lightning_rod", &"storm", &"two_hammers", &"earthquake", &"sky_thunder"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		runner.name = "TraitRunner"
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

func wait(sec: float) -> void:
	await frames(int(ceil(sec * 60.0)))

func _run() -> void:
	print("=== TRAIT TEST ===")
	Run.start_run("berserker")
	Run.room_order.assign([Run.BOSS_SCENE])
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await frames(20)
	game = get_tree().current_scene as Game
	p = game.player
	hand = p.mjolnir
	# Перезарядку броска проверяет catch_test; здесь броски подряд
	hand.throw_cooldown = 0.0
	game.room.set_physics_process(false)
	await wait(1.0)
	game.room._spawn_queue.clear()
	for e in game.room.alive_enemies().duplicate():
		e.queue_free()
	await frames(5)
	_test_data()
	_test_locked_pool()
	for u in Save.all_unlocks:
		if u.kind == "trait":
			Save.data.unlocks[u.id] = 0
	_test_rules()
	_test_doors()
	await _test_pick_ui()
	await _test_card_layout()
	await _test_anvil_flow()
	await _test_base()
	await _test_environment()
	# -- elements / -- techniques / -- combos: прогнать только эту часть (отладка)
	var only := OS.get_cmdline_user_args()
	if only.is_empty() or "elements" in only:
		for id in ELEMENTS:
			for lv in [1, 2, 3, 4]:
				await _test_element(_find(id), lv)
	if only.is_empty() or "techniques" in only:
		for id in TECHNIQUES:
			for lv in [1, 2]:
				await _test_technique(_find(id), lv)
	if only.is_empty() or "combos" in only:
		for id in COMBOS:
			await _test_combo(_find(id))
	_finish()

# --- Данные и правила ---

func _set_traits(list: Array) -> void:
	Run.mjolnir_traits.clear()
	Run.mjolnir_trait_levels.clear()
	Run.mjolnir_traits_changed.emit(Run.mjolnir_traits)
	for t in list:
		if t:
			Run.add_mjolnir_trait(t)

func _find(id: StringName) -> MjolnirTrait:
	return Run.mjolnir_trait_def(id)

func _lv(id: StringName, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(_find(id))
	return out

func _test_data() -> void:
	print("-- Данные: стихии, приёмы, связки")
	var els := Run.all_mjolnir_traits.filter(func(t: MjolnirTrait) -> bool: return t.is_element())
	var techs := Run.all_mjolnir_traits.filter(func(t: MjolnirTrait) -> bool: return t.is_technique())
	check(els.size() == ELEMENTS.size(), "стихий: %d" % els.size())
	check(techs.size() == TECHNIQUES.size(), "приёмов: %d (6 старых + 7 новых)" % techs.size())
	check(Run.all_mjolnir_combos.size() == COMBOS.size(), "связок: %d" % Run.all_mjolnir_combos.size())
	var bad := 0
	for id in ELEMENTS + TECHNIQUES + COMBOS:
		var t := _find(id)
		if t == null or t.handler == null or t.title == "" or t.description == "":
			bad += 1
			print("    нет данных: ", id)
	check(bad == 0, "у каждого трейта есть .tres, обработчик и описание")
	check(els.all(func(t: MjolnirTrait) -> bool: return t.max_level == 4 and t.description_lvl4 != "" and t.handler is MjolnirElementHandler), "у стихий 4 уровня (попадание / след / аура / с неба)")
	check(techs.all(func(t: MjolnirTrait) -> bool: return t.max_level == 2 and t.description_lvl2 != ""), "у приёмов 2 уровня")
	var combos_ok := Run.all_mjolnir_combos.all(func(c: MjolnirTrait) -> bool:
		var e := _find(c.combo_element)
		var te := _find(c.combo_technique)
		return c.is_combo() and e != null and e.is_element() and te != null and te.is_technique())
	check(combos_ok, "связки ссылаются на существующие стихию и приём")
	var lost: Array[String] = []
	for old in OLD_TRAITS:
		var found := false
		for t in Run.all_mjolnir_traits:
			if old in t.all_ids():
				found = true
		if not found:
			lost.append(str(old))
	check(lost.is_empty(), "все 13 бывших трейтов нашли место (потеряны: %s)" % ", ".join(lost))
	var soon: Array[String] = []
	for u in Save.all_unlocks:
		if u.kind == "trait" and not Save.target_exists(u):
			soon.append(u.id)
	check(soon.is_empty(), "открытия трейтов «Плана тренировок» не «скоро» (%s)" % ", ".join(soon))

func _test_locked_pool() -> void:
	print("-- Пул открытий (Save.is_in_pool)")
	_set_traits([])
	var earth := _find(&"earth")
	var locked_earth := not Save.is_in_pool("trait", "heaviness")
	var offered_earth := false
	var locked_ok := true
	for i in 60:
		for t in Run.random_mjolnir_trait_choices():
			if not Save.is_in_pool("trait", str(t.id)) or not Run.mjolnir_level_in_pool(t, 1):
				locked_ok = false
			if t == earth:
				offered_earth = true
	check(locked_ok, "закрытые трейты («План тренировок») в выбор не попадают")
	if locked_earth:
		check(not offered_earth, "Земля закрыта открытием «heaviness» (бывшая Тяжесть)")
	if not Save.is_in_pool("trait", "lightning_rod"):
		_set_traits(_lv(&"lightning", 2))
		check(not Run.can_level_up(_find(&"lightning")), "Молния ур. 3 (Громоотвод) закрыта открытием «lightning_rod»")
	_set_traits([])

func _test_rules() -> void:
	print("-- Правила выбора")
	var r := Run.rules()
	check(r.max_elements == 1 and not r.element_swap and r.max_techniques == 2, "по умолчанию: 1 стихия на забег, до 2 приёмов")
	var fire := _find(&"fire")
	_set_traits(_lv(&"lightning", 2))
	check(Run.can_level_up(_find(&"lightning")), "после открытия lightning_rod — Молния ур. 3")
	# Одна стихия: другие не предлагаются; не больше двух приёмов; несовместимых нет ни в наборе, ни у игрока
	var other_el := 0
	var too_many := 0
	var clash := 0
	var maxed := 0
	var short := 0
	for i in 300:
		var owned: Array = []
		if randf() < 0.6:
			owned.append(_find(ELEMENTS[randi() % ELEMENTS.size()]))
		for k in randi() % 3:
			owned.append(_find(TECHNIQUES[randi() % TECHNIQUES.size()]))
		if randf() < 0.3 and not owned.is_empty():
			owned.append(owned[0])
		_set_traits(owned)
		var ch := Run.random_mjolnir_trait_choices()
		var el := Run.owned_element()
		for t in ch:
			if el and t.is_element() and t != el:
				other_el += 1
			if Run.mjolnir_trait_level(t.id) >= t.max_level:
				maxed += 1
		for a in ch:
			for b in ch:
				if a != b and a.is_technique() and b.is_technique() and a.conflicts_with(b):
					clash += 1
		if Run.owned_elements().size() > 1 or Run.owned_techniques().size() > 2:
			too_many += 1
		for a in Run.mjolnir_traits:
			for b in Run.mjolnir_traits:
				if a != b and a.is_technique() and b.is_technique() and a.conflicts_with(b):
					clash += 1
		# 3 варианта, если в пуле хватает (меньше — только если оставшиеся несовместимы между собой)
		var pool := Run.all_mjolnir_traits.filter(func(x: MjolnirTrait) -> bool: return Run.mjolnir_offer_ok(x))
		var pool_clash := false
		for a in pool:
			for b in pool:
				if a != b and a.is_technique() and b.is_technique() and a.conflicts_with(b):
					pool_clash = true
		if ch.size() < mini(3, pool.size()) and not pool_clash:
			short += 1
	check(other_el == 0, "одна стихия на забег: другие стихии не предлагаются")
	check(too_many == 0, "у игрока не больше 1 стихии и 2 приёмов")
	check(clash == 0, "в наборе и у игрока нет несовместимых приёмов")
	check(maxed == 0, "трейт на макс. уровне не выпадает")
	check(short == 0, "3 варианта, если в пуле хватает")
	# Мини-босс: и стихия, и приём
	_set_traits([])
	var mixed := 0
	for i in 100:
		var ch := Run.random_mjolnir_trait_choices()
		if ch.any(func(t: MjolnirTrait) -> bool: return t.is_element()) and ch.any(func(t: MjolnirTrait) -> bool: return t.is_technique()):
			mixed += 1
	check(mixed == 100, "выбор после мини-босса: есть и стихия, и приём (%d/100)" % mixed)
	var only_el := true
	for i in 50:
		for t in Run.random_mjolnir_trait_choices(-1, ["element"]):
			if not t.is_element():
				only_el = false
	check(only_el, "наковальня: только стихии")
	# Два приёма — новый не предлагается, кроме замены несовместимого
	_set_traits([fire, _find(&"magnet"), _find(&"storm")])
	var new_tech := 0
	var sling_offered := false
	for i in 100:
		for t in Run.random_mjolnir_trait_choices():
			if t.is_technique() and Run.mjolnir_trait_level(t.id) == 0:
				if Run.mjolnir_trait_conflict(t) == null:
					new_tech += 1
				if t.id == &"sling":
					sling_offered = true
	check(new_tech == 0, "два приёма — новый приём только как замена")
	check(sling_offered, "Праща предлагается как замена Бури (одна группа «удержание ПКМ»)")
	_set_traits([_find(&"storm"), _find(&"sling")])
	check(Run.mjolnir_trait_level(&"storm") == 0 and Run.mjolnir_trait_level(&"sling") == 1, "Праща заменила Бурю")
	_set_traits([_find(&"boomerang"), _find(&"magnet")])
	check(Run.mjolnir_trait_level(&"boomerang") == 0 and Run.mjolnir_trait_level(&"magnet") == 1, "Магнит заменил Бумеранг (не втыкается)")
	_set_traits([_find(&"pull_to_hammer"), _find(&"swap")])
	check(Run.mjolnir_traits.size() == 1 and Run.mjolnir_traits[0].id == &"swap", "Обмен заменил Притяжение (группа «к молоту»)")
	# Настройки: один приём; смена стихии
	r.max_techniques = 1
	_set_traits([_find(&"magnet")])
	var any_new := false
	for i in 60:
		for t in Run.random_mjolnir_trait_choices():
			if t.is_technique() and Run.mjolnir_trait_level(t.id) == 0 and Run.mjolnir_trait_conflict(t) == null:
				any_new = true
	check(not any_new, "MjolnirRules.max_techniques = 1 — второй приём не предлагается")
	r.max_techniques = 2
	r.element_swap = true
	_set_traits([fire])
	var ice := _find(&"ice")
	check(Run.mjolnir_offer_ok(ice) and Run.mjolnir_trait_conflict(ice) == fire, "element_swap: Лёд заменит Огонь")
	_set_traits([fire, ice])
	check(Run.owned_element() == ice and Run.owned_elements().size() == 1, "element_swap: стихия сменилась")
	r.element_swap = false
	# Повтор — уровень; стихия до 4, на 4-м — больше не предлагается, наковальне нечего дать
	_set_traits(_lv(&"fire", 4))
	check(Run.mjolnir_trait_level(&"fire") == 4, "повтор стихии — уровень (до 4)")
	check(not Run.mjolnir_offer_ok(fire) and not Run.anvil_available(), "Огонь ур. 4 — не предлагается, наковальня закрыта")
	_set_traits([])
	check(Run.anvil_available(), "без стихии наковальне есть что дать")
	# Связки
	var fired: Array = []
	var cb := func(c: MjolnirTrait) -> void: fired.append(c)
	Run.mjolnir_combo_unlocked.connect(cb)
	_set_traits([fire])
	var storm := _find(&"storm")
	var completes := Run.combos_completed_by(storm)
	check(completes.size() == 1 and completes[0].id == &"fire_tornado", "карточка Бури при Огне — «+ СВЯЗКА: Огненный смерч»")
	var got := Run.add_mjolnir_trait(storm)
	check(got.size() == 1 and fired.size() == 1 and Run.active_combos().size() == 1, "Огонь + Буря — связка появилась сама (сигнал)")
	Run.add_mjolnir_trait(storm)
	check(fired.size() == 1, "повышение уровня связку не объявляет повторно")
	Run.mjolnir_combo_unlocked.disconnect(cb)
	check(hand.combo_traits.size() == 1 and hand.traits.size() == Run.mjolnir_traits.size(), "обработчик связки у молота — отдельно от трейтов")
	_set_traits([])

func _test_doors() -> void:
	print("-- Дверь «Наковальня Эйтри»")
	var m := Run.map
	var boss := 7
	var seen := 0
	for i in 200:
		if "anvil" in m.roll_offers(Run.all_rewards, 1, boss, {"shop": 9}, "combat", false, true):
			seen += 1
	check(seen == 200, "к залу 2 — наковальня в каждом наборе, пока есть что дать (%d/200)" % seen)
	var late := 0
	var visited := 0
	var closed := 0
	for i in 200:
		if "anvil" in m.roll_offers(Run.all_rewards, 4, boss, {"shop": 9}, "combat", false, true):
			late += 1
		if "anvil" in m.roll_offers(Run.all_rewards, 1, boss, {"shop": 9, "anvil": 1}, "combat", false, true):
			visited += 1
		if "anvil" in m.roll_offers(Run.all_rewards, 1, boss, {"shop": 9}, "combat", false, false):
			closed += 1
	check(late == 0 and visited == 0 and closed == 0, "не после зала %d, не повторно, не когда нечего дать" % m.anvil_latest_room)
	var d := Run.reward_def("anvil")
	check(d != null and d.combat and is_zero_approx(d.weight), "награда «anvil»: боевой зал, только по правилу (вес 0)")

# --- Экран выбора, объявление связки, HUD ---

func _test_pick_ui() -> void:
	print("-- Экран выбора трейта")
	var fire := _find(&"fire")
	var storm := _find(&"storm")
	var magnet := _find(&"magnet")
	_set_traits([fire])
	await frames(2)
	var tp := game.trait_pick
	var choices: Array[MjolnirTrait] = [storm, magnet]
	tp.open(choices)
	tp._open_time = -10.0
	check(tp.visible and get_tree().paused, "экран открыт, игра на паузе")
	var card := tp._cards.get_child(0)
	var texts := _texts(card)
	check(texts.any(func(s: String) -> bool: return s.contains("СВЯЗКА")), "карточка Бури — особая: «+ СВЯЗКА»")
	check(_texts(tp._cards.get_child(1)).any(func(s: String) -> bool: return s.contains("ПРИЁМ")), "на карточке подписан вид (ПРИЁМ)")
	tp.choose(0)
	await wait(0.6)
	check(not tp.visible and Run.mjolnir_trait_level(&"storm") == 1, "Буря взята")
	var ann := game.get_node_or_null("ComboAnnounce") as ComboAnnounce
	check(ann != null and ann.visible and ann.combo and ann.combo.id == &"fire_tornado", "объявление связки на экране")
	if ann:
		var bubble := Dialogue.bubble()
		var text_scale := GameSettings.text_scale()
		GameSettings.set_value("text", "text_scale", 1.6, false)
		bubble.show_line("hugin", "neutral", "Кар! Прыгни дважды и жми удар-приземление. С высокой площадки можно и без второго прыжка.")
		await frames(4)
		game.hud._position_odin_notice()
		var odin := _visual_rect(game.hud._odin_panel)
		var raven := bubble.visual_rect()
		var banner := ann.visual_rect()
		check(not banner.intersects(odin) and not banner.intersects(raven) and not raven.intersects(odin), "плашка, подсказка ворона и реплика Одина не перекрывают друг друга")
		await _test_combo_word_layout(ann, bubble)
		GameSettings.set_value("text", "text_scale", text_scale, false)
		ann.visible = false
		await frames(3)
		game.hud._position_odin_notice()
		check(is_zero_approx(bubble._combo_shift) and is_equal_approx(game.hud._odin_panel.offset_left, -340.0), "после плашки подсказки возвращаются на обычные места")
	var hud_icons: int = game.hud._mjolnir_traits._icons.get_child_count()
	check(hud_icons == 3, "HUD: стихия, приём и связка (%d иконки)" % hud_icons)
	if game.rune_pick.visible:
		game.rune_pick._open_time = -10.0
		game.rune_pick.choose(0)
	await wait(0.3)
	get_tree().paused = false
	# Замена несовместимого — с подтверждением
	_set_traits([storm])
	var got: Array = []
	var cb := func(t: MjolnirTrait) -> void: got.append(t)
	tp.picked.disconnect(game._on_trait_picked)
	tp.picked.connect(cb)
	var c2: Array[MjolnirTrait] = [_find(&"sling")]
	tp.open(c2)
	tp._open_time = -10.0
	tp.choose(0)
	check(tp.visible and got.is_empty(), "замена приёма требует подтверждения")
	await frames(3)
	var status := tp._status_labels[0]
	var body := status.get_parent() as Control
	var text_height := SkinCard.TEXT_BOX.size.y * tp.card_width / SkinCard.VISIBLE.size.x
	check(body.size.y <= text_height + 1.0 and status.position.y + status.size.y <= text_height + 1.0,
		"подтверждение замены помещается в текстовое окно")
	tp.choose(0)
	check(not tp.visible and got.size() == 1, "второе нажатие — выбрано")
	tp.picked.disconnect(cb)
	tp.picked.connect(game._on_trait_picked)
	check(not get_tree().paused, "пауза снята")
	await frames(5)
	_set_traits([])

## Длинные описания, переводы и статус остаются внутри текстового окна карточки.
func _test_card_layout() -> void:
	print("-- Длинные описания карточек")
	var tp := game.trait_pick
	tp.visible = true
	var compact := SkinCard.make("card_trait", 200.0, Color.WHITE)
	var heading := compact.add_text("Ураганный рывок", 19, Color.WHITE, 5)
	var word_width := heading.label_settings.font.get_string_size("Ураганный", HORIZONTAL_ALIGNMENT_LEFT, -1,
		heading.label_settings.font_size).x
	check(word_width + heading.label_settings.outline_size * 2 <= compact.text_width(), "длинное слово заголовка целиком помещается на узкой карточке")
	compact.free()
	for lang in ["ru", "en"]:
		GameSettings.set_value("text", "language", lang, false)
		var overflow: Array[String] = []
		for t in Run.all_mjolnir_traits:
			var card := tp._make_card(t, 0) as SkinCard
			tp._root.add_child(card)
			await frames(3)
			var limit := SkinCard.TEXT_BOX.size.y * tp.card_width / SkinCard.VISIBLE.size.x
			var bottom := 0.0
			for child in card.body.get_children():
				var label := child as Label
				bottom = maxf(bottom, label.position.y + label.size.y)
			if card.body.size.y > limit + 1.0 or bottom > limit + 1.0:
				overflow.append(str(t.id))
			card.queue_free()
		check(overflow.is_empty(), "%s: описания и статусы внутри рамки (%s)" % [lang, ", ".join(overflow)])
		# Первый проход проверяет новые приёмы; отдельно проверяем карточки их второго уровня.
		for id in [&"hammer_dive", &"hammer_step"]:
			var technique: MjolnirTrait = _find(id)
			_set_traits([technique])
			var upgrade: SkinCard = tp._make_card(technique, 0) as SkinCard
			tp._root.add_child(upgrade)
			await frames(3)
			var limit: float = SkinCard.TEXT_BOX.size.y * tp.card_width / SkinCard.VISIBLE.size.x
			var bottom: float = 0.0
			for child in upgrade.body.get_children():
				var label: Label = child as Label
				bottom = maxf(bottom, label.position.y + label.size.y)
			check(upgrade.body.size.y <= limit + 1.0 and bottom <= limit + 1.0,
				"%s: %s ур. 2 внутри рамки" % [lang, id])
			upgrade.queue_free()
			_set_traits([])
	GameSettings.set_value("text", "language", "ru", false)
	tp.visible = false
	tp._status_labels.clear()

func _test_combo_word_layout(ann: ComboAnnounce, bubble: BarkBubble) -> void:
	var old_size: Vector2i = get_viewport().size
	var old_language: String = GameSettings.get_value("text", "language")
	var old_scale := GameSettings.text_scale()
	var old_enabled := GameSettings.comic_enabled
	var old_comic_scale := GameSettings.comic_scale
	GameSettings.comic_enabled = true
	for viewport_size in [Vector2i(1280, 720), Vector2i(1280, 800)]:
		get_viewport().size = viewport_size
		await frames(2)
		for language in ["ru", "en"]:
			GameSettings.set_value("text", "language", language, false)
			for scale in [1.0, 1.6]:
				GameSettings.set_value("text", "text_scale", scale, false)
				for comic_scale in [1.0, 1.6]:
					GameSettings.comic_scale = comic_scale
					var line := "Связка! Молот и стихия договорились. Тебе бы так с диваном." if language == "ru" else "A fusion! Hammer and element agreed. If only you and the couch could do that."
					game.hud.show_odin_line(line)
					bubble.show_line("hugin", "neutral", line)
					ComicFX.reset_state()
					ComicFX.pop("combo", Vector3.ZERO, true)
					await frames(5)
					game.hud._position_odin_notice()
					await frames(2)
					var word: Variant = null
					for w in ComicFX._pool:
						if w.active and w.event == "combo" and not w.preview:
							word = w
					var odin := _visual_rect(game.hud._odin_panel)
					var tag := "%dx%d %s text=%.1f word=%.1f" % [viewport_size.x, viewport_size.y, language, scale, comic_scale]
					check(word != null, "%s: слово связки активно" % tag)
					if word:
						var letters: Rect2 = word.label.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, word.label.size)
						check(not odin.intersects(letters), "%s: реплика не перекрывает слово связки" % tag)
					var label := game.hud._odin_label
					var text_rect: Rect2 = label.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, label.size)
					var contained := odin.encloses(text_rect)
					var extent := label.label_settings.font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, label.size.x, label.label_settings.font_size)
					check(contained and label.size.y >= extent.y + label.label_settings.outline_size * 2.0,
						"%s: текст реплики помещается в рамке целиком" % tag)
					check(not odin.intersects(ann.visual_rect()) and not odin.intersects(bubble.visual_rect()),
						"%s: реплика отдельно от плашки и ворона" % tag)
					check(not odin.intersects(game.hud._hammer_icon.get_global_rect()) and not odin.intersects(game.hud._mjolnir_traits.get_global_rect()),
						"%s: реплика не закрывает молот и трейты (трейты %s)" % [tag, game.hud._mjolnir_traits.get_global_rect()])
					var narrow := game.hud._odin_panel.offset_right - game.hud._odin_panel.offset_left
					ComicFX.reset_state()
					await frames(2)
					game.hud._position_odin_notice()
					check(game.hud._odin_panel.offset_right - game.hud._odin_panel.offset_left > narrow + 100.0,
						"%s: после слова возвращается обычная ширина реплики" % tag)
	GameSettings.comic_enabled = old_enabled
	GameSettings.comic_scale = old_comic_scale
	GameSettings.set_value("text", "language", old_language, false)
	GameSettings.set_value("text", "text_scale", old_scale, false)
	get_viewport().size = old_size
	await frames(2)

func _visual_rect(control: Control) -> Rect2:
	var rect := Rect2(Vector2.ZERO, control.size)
	var style := control.get_theme_stylebox("panel") as SkinStyleBox
	if style:
		rect = style._draw_rect_of(rect)
	return control.get_global_transform_with_canvas() * rect

func _texts(n: Node) -> Array[String]:
	var out: Array[String] = []
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		out.append_array(_texts(c))
	return out

func _eitri_barks() -> int:
	var count := 0
	for line in Dialogue.history:
		if str(line.get("speaker", "")) == "eitri":
			count += 1
	return count

func _test_anvil_flow() -> void:
	print("-- Наковальня Эйтри: награда зала")
	_set_traits([])
	while Run.room_rewards.size() <= Run.room_index:
		Run.room_rewards.append("")
	var was: String = Run.room_rewards[Run.room_index]
	var old_rerolls := Run.trait_rerolls
	Run.room_rewards[Run.room_index] = "anvil"
	game.rewards._granted = false
	var before := _eitri_barks()
	game.rewards.grant()
	var tp := game.trait_pick
	check(tp.visible and tp._title.text.contains("НАКОВАЛЬНЯ"), "после зачистки — выбор стихии у наковальни")
	check(tp._choices.all(func(t: MjolnirTrait) -> bool: return t.is_element()), "в выборе только стихии")
	check(_eitri_barks() == before, "при открытых карточках Эйтри ещё не говорит")
	Run.trait_rerolls = 1
	game.rewards._on_trait_reroll()
	check(tp.visible and _eitri_barks() == before and game.rewards._anvil_pick,
		"переброс сохраняет выбор наковальни и не вызывает реплику")
	tp._open_time = -10.0
	tp.choose(0)
	check(not tp.visible and _eitri_barks() == before + 1, "после подтверждения и закрытия карточек — одна реплика Эйтри")
	tp.choose(0)
	check(_eitri_barks() == before + 1, "повторный выбор закрытого окна не повторяет реплику")
	await wait(0.35)
	var bubble := Dialogue.bubble()
	check(not tp.visible and not game.rune_pick.visible and bubble._name.text == str(Dialogue.speakers["eitri"].name).to_upper()
		and bubble._text.text != "" and bubble._panel.modulate.a > 0.5,
		"пузырь Эйтри виден после выбора и не закрыт карточками")
	await wait(0.45)
	check(Run.owned_element() != null, "стихия взята: %s" % (str(Run.owned_element().id) if Run.owned_element() else "—"))
	check(not game.rune_pick.visible and not tp.visible, "после наковальни — без руны (награда выдана)")
	check(not game.rewards._anvil_pick, "признак наковальни сброшен")

	# При разрешённой смене стихии первая попытка только просит подтверждение.
	var old_swap := Run.rules().element_swap
	Run.rules().element_swap = true
	_set_traits([_find(&"fire")])
	game.rewards._granted = false
	before = _eitri_barks()
	game.rewards.grant()
	var swap_index := -1
	for i in tp._choices.size():
		if tp._choices[i].id != &"fire":
			swap_index = i
			break
	check(tp.visible and swap_index >= 0, "наковальня предлагает замену стихии")
	if tp.visible and swap_index >= 0:
		tp._open_time = -10.0
		tp.choose(swap_index)
		check(tp.visible and tp._confirm_index == swap_index and _eitri_barks() == before,
			"первое нажатие просит подтверждение без реплики Эйтри")
		tp.choose(swap_index)
		check(not tp.visible and _eitri_barks() == before + 1 and Run.owned_element().id != &"fire",
			"подтверждённая замена закрывает окно и вызывает одну реплику Эйтри")
		await wait(0.8)
	else:
		tp.visible = false
		get_tree().paused = false
		game.rewards.take_anvil_pick()
	Run.rules().element_swap = old_swap

	# Когда стихия исчерпана, наковальня сохраняет обычный запасной выбор руны и не вызывает реплику.
	_set_traits(_lv(&"fire", 4))
	game.rewards._granted = false
	before = _eitri_barks()
	game.rewards.grant()
	check(not tp.visible and game.rune_pick.visible and not game.rewards._anvil_pick and _eitri_barks() == before,
		"пустой выбор стихии: запасная руна без реплики Эйтри")
	if game.rune_pick.visible:
		game.rune_pick._open_time = -10.0
		game.rune_pick.choose(0)
	await wait(0.3)

	# Обычный выбор после мини-босса не связан с наковальней.
	_set_traits([])
	Run.room_rewards[Run.room_index] = "combat"
	game.rewards._granted = false
	before = _eitri_barks()
	var choices: Array[MjolnirTrait] = [_find(&"fire")]
	tp.open(choices)
	tp._open_time = -10.0
	tp.choose(0)
	check(not tp.visible and _eitri_barks() == before, "обычный выбор трейта не вызывает Эйтри")
	await wait(0.8)
	if game.rune_pick.visible:
		game.rune_pick._open_time = -10.0
		game.rune_pick.choose(0)
	await wait(0.2)
	Run.trait_rerolls = old_rerolls
	Run.room_rewards[Run.room_index] = was
	get_tree().paused = false
	_set_traits([])
	await frames(5)

# --- База молота ---

func _reset_player(pitch: float = 0.0) -> void:
	hand.hold_override = false
	if not hand.in_hand:
		hand.force_return_instant()
	p.set_physics_process(true)
	p.global_position = START
	p.velocity = Vector3.ZERO
	p.rotation_target = Vector2(pitch, 0.0)
	p.rotation.y = 0.0
	p.head.rotation.x = pitch
	p.health = p.max_health
	p._invuln_left = 0.0
	hand.perfect_ready = false
	if p.is_slamming:
		p._cancel_slam()

func _clear_dummies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	for n in game.get_children():
		var s: Script = n.get_script()
		if s and (s.resource_path.ends_with("fire_zone.gd") or s.resource_path.ends_with("ice_zone.gd") or s.resource_path.ends_with("element_zone.gd") \
				or s.resource_path.ends_with("brew_puddle.gd")):
			n.queue_free()

## Манекен: без своего ИИ (если physics = false), много HP. Позиция — относительно START (x вбок, z — вперёд по -Z).
func _dummy(side: float, fwd: float, physics: bool = false, scene: String = "grunt") -> Enemy:
	var e := (load("res://enemies/%s.tscn" % scene) as PackedScene).instantiate() as Enemy
	if scene == "grunt":
		e.max_health = 500
	e.move_speed = 0.0
	e.attack_range = 0.0
	game.add_child(e)
	e.global_position = Vector3(START.x + side, 0.0, START.z - fwd)
	e.set_physics_process(physics)
	e.health = e.max_health
	return e

func _hurt(e: Enemy) -> bool:
	return not is_instance_valid(e) or e.health < e.max_health

func _hp(e: Enemy) -> float:
	return e.health if is_instance_valid(e) else -1.0

## Ждать, пока молот в руке (или timeout). Возвращает true, если вернулся.
func _wait_in_hand(timeout: float) -> bool:
	for i in int(timeout * 60):
		if hand.in_hand:
			return true
		await get_tree().physics_frame
	return hand.in_hand

## Ждать состояния снаряда. Возвращает true, если дождались.
func _wait_state(s: MjolnirProjectile.State, timeout: float) -> bool:
	for i in int(timeout * 60):
		if hand.projectile and is_instance_valid(hand.projectile) and hand.projectile.state == s:
			return true
		if hand.in_hand:
			return false
		await get_tree().physics_frame
	return false

func _recall_and_wait() -> bool:
	if not hand.in_hand and hand.projectile and is_instance_valid(hand.projectile) and hand.projectile.state != MjolnirProjectile.State.RETURN:
		hand.request_throw_or_recall()
	return await _wait_in_hand(4.0)

## Прыжок и удар-приземление на месте (как игрок: Пробел, Ctrl), ждём приземления
func _slam() -> void:
	p.restore_mjolnir_runes(p.dash_charges_max)
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await wait(0.15)
	Input.action_press("jump")
	await frames(2)
	Input.action_release("jump")
	await wait(0.1)
	Input.action_press("slam")
	await frames(2)
	Input.action_release("slam")
	for i in 90:
		await get_tree().physics_frame
		if p.is_on_floor():
			break

func _test_base() -> void:
	print("-- База молота (без трейтов)")
	_set_traits([])
	_clear_dummies()
	await frames(3)
	_reset_player()
	await frames(5)
	var d := _dummy(0, 6)
	hand.throw_hammer()
	check(not hand.in_hand, "бросок")
	var stuck := await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	check(stuck, "молот воткнулся в стену")
	check(_hurt(d), "попал по манекену на пути")
	var back := await _wait_in_hand(3.0)
	check(back, "воткнутый молот сам вернулся (stuck_auto_return %.1f с)" % hand.stuck_auto_return)
	# Без трейтов удержания ПКМ бросает сразу по нажатию
	check(not bool(hand.trait_modify(&"hold_throw", false)), "без Пращи/Заряда — бросок по нажатию")
	_clear_dummies()
	await frames(2)
	p.dash_charges = p.dash_charges_max - 1
	p.set("_dash_recharge_timer", 0.0)
	hand.throw_hammer()
	await wait(0.5)
	var t: float = p.get("_dash_recharge_timer")
	check(t > 0.55, "без молота рывок перезаряжается быстрее (таймер %.2f за 0.5 с)" % t)
	await _wait_in_hand(4.0)
	hand.throw_hammer()
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	hand.request_throw_or_recall()
	await _wait_in_hand(3.0)
	hand.request_throw_or_recall()
	check(hand.projectile != null and is_equal_approx(hand.projectile.damage_mult, hand.perfect_damage_mult), "идеальный хват (после поимки): бросок ×%.0f" % hand.perfect_damage_mult)
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	hand.request_throw_or_recall()
	await _wait_in_hand(3.0)
	await wait(0.4)
	hand.request_throw_or_recall()
	check(hand.projectile != null and is_equal_approx(hand.projectile.damage_mult, 1.0), "без идеального хвата — обычный урон")
	await _wait_in_hand(4.0)
	_clear_dummies()

# --- Окружение ---

func _test_environment() -> void:
	print("-- Окружение: брага Свена, бочки")
	_set_traits([_find(&"lightning")])
	_clear_dummies()
	await frames(3)
	_reset_player()
	var d := _dummy(0, 6)
	var puddle := BrewPuddle.spawn(game, d.global_position, 1.8, 7.0, 0.55)
	await frames(3)
	var el := hand.element_handler()
	el.world_effect(d.global_position + Vector3(1.0, 0, 0), 0.5)
	check(puddle.shock_left > 0.0, "молния: лужа браги под током")
	await wait(0.7)
	check(_hurt(d) and ElementStatus.is_shocked(d), "ток в луже бьёт врага в ней")
	_set_traits([_find(&"fire")])
	await frames(2)
	var puddle2 := BrewPuddle.spawn(game, START + Vector3(4, 0, -6), 1.8, 7.0, 0.55)
	var barrel := (load("res://props/barrel.tscn") as PackedScene).instantiate() as Destructible
	game.add_child(barrel)
	barrel.global_position = START + Vector3(-4, 0.5, -6)
	await frames(5)
	el = hand.element_handler()
	el.world_effect(puddle2.global_position, 0.5)
	el.world_effect(barrel.global_position, 0.8)
	check(puddle2.burning, "огонь: брага горит")
	check(not is_instance_valid(barrel) or barrel.burning or barrel.is_broken, "огонь: бочка загорелась")
	if is_instance_valid(barrel):
		barrel.queue_free()
	_set_traits([])
	_clear_dummies()
	await frames(5)

# --- Стихии ---

func _test_element(t: MjolnirTrait, lv: int) -> void:
	print("-- Стихия %s (%s), ур. %d" % [t.title, t.id, lv])
	_set_traits(_lv(t.id, lv))
	var h := hand.element_handler()
	check(h != null and h.level == lv and hand.traits.size() == 1, "обработчик стихии у молота, уровень %d" % lv)
	_clear_dummies()
	await frames(3)
	await _element_throw(t, h, lv)
	if lv == 1:
		_clear_dummies()
		await frames(3)
		await _element_slam(t, h)
	if lv == 3 and t.id == &"earth":
		_clear_dummies()
		await frames(3)
		await _scenario_quake()
	if lv == 4:
		_clear_dummies()
		await frames(3)
		await _scenario_sky(t)
	check(hand.in_hand, "молот в руке после сценария")
	check(p.is_physics_processing(), "игрок снова управляется")
	_clear_dummies()
	await frames(3)

func _element_throw(t: MjolnirTrait, h: MjolnirElementHandler, lv: int) -> void:
	_reset_player()
	await frames(5)
	var wind := t.id == &"wind"
	var line := _dummy(0, 4, wind)
	# Ветер толкает врага на линии вперёд — второй на пути не стоит
	var line2 := _dummy(4.0 if wind else 0.0, 7)
	var side := _dummy(3.0, 7.5)
	var wall_l := _dummy(2.2, 16.0)
	var wall_r := _dummy(-2.2, 16.0)
	var line_pos := line.global_position
	var saw_stuck := false
	hand.throw_hammer()
	for i in 150:
		await get_tree().physics_frame
		if hand.projectile and is_instance_valid(hand.projectile) and hand.projectile.is_stuck():
			saw_stuck = true
			break
		if hand.in_hand:
			break
	check(_hurt(line), "попал по врагу на линии")
	match t.id:
		&"fire":
			check(ElementStatus.is_burning(line), "Огонь: враг горит")
		&"ice":
			var s := ElementStatus.of(line)
			check(s != null and (s.chill_stacks >= 1 or s.frozen_left > 0.0), "Лёд: враг промёрз (стак)")
			check(is_instance_valid(line) and line.move_speed <= 0.0 or (s and s._base_speed >= 0.0), "Лёд: замедление")
		&"lightning":
			check(ElementStatus.is_shocked(line), "Молния: враг под током")
			check(_hurt(side), "Молния: перескочила на врага в стороне")
		&"earth":
			check(ElementStatus.is_pinned(line) and line.state == Enemy.State.STUNNED, "Земля: прибила и оглушила")
			if lv >= 2:
				check(ElementStatus.is_pinned(line2) or line2.state == Enemy.State.STUNNED or ElementStatus.is_pinned(side), "Земля ур. 2+: оглушение по кругу")
		&"wind":
			await wait(0.4)
			var moved := line_pos.distance_to(line.global_position) if is_instance_valid(line) else 99.0
			check(moved > 1.5, "Ветер: отбросило на %.1f м" % moved)
	if lv >= 2:
		check(h.active_zones() > 0, "ур. 2: след на полу (%d пятен)" % h.active_zones())
	check(saw_stuck, "молот воткнулся")
	if saw_stuck and lv >= 3:
		await wait(1.3)
		check(hand.projectile != null and hand.projectile.is_stuck(), "ур. 3: воткнутый молот с аурой ждёт ПКМ дольше")
		check(_hurt(wall_l) or _hurt(wall_r), "ур. 3: аура задела врага у молота")
	check(await _recall_and_wait(), "молот вернулся")
	if lv >= 2:
		check(h.active_zones() <= h.trail_max_zones, "пятен следа не больше trail_max_zones")
	# Ледяная заморозка: третье попадание
	if t.id == &"ice" and is_instance_valid(line):
		var s := ElementStatus.of(line, true)
		h.apply_element(line, 1.0, line.global_position, null)
		h.apply_element(line, 1.0, line.global_position, null)
		h.apply_element(line, 1.0, line.global_position, null)
		check(s.frozen_left > 0.0 and line.state == Enemy.State.STUNNED, "Лёд: на третьем попадании замёрз")

## Связка стихии с ударом-приземлением
func _element_slam(t: MjolnirTrait, h: MjolnirElementHandler) -> void:
	_reset_player()
	await frames(5)
	var near := _dummy(0, 2.0)
	var other := _dummy(0, -2.0)
	var far := _dummy(0, 2.0 + 2.5) if t.id != &"wind" else _dummy(5.0, 2.0)
	var very_far := _dummy(0, 10.0)
	if t.id == &"wind":
		near.queue_free()
		near = _dummy(0, 2.5, true)
	await frames(2)
	var ns := ElementStatus.of(near, true)
	match t.id:
		&"fire":
			ns.ignite(1.0, 10.0)
		&"ice":
			ns.freeze(10.0)
		&"lightning":
			ElementStatus.of(very_far, true).shock(10.0)
		&"earth":
			ns.pin(10.0)
	var near0 := near.global_position
	var hp_near := near.health
	var hp_other := other.health
	var hp_far := far.health
	var hp_vfar := very_far.health
	await _slam()
	var landed_near := _hp(near)
	await wait(0.5)
	match t.id:
		&"fire":
			check(_hp(far) < hp_far, "Огонь + удар-приземление: вспышка у горящего задела соседа")
		&"ice":
			check(hp_near - _hp(near) > (hp_other - _hp(other)) * 1.5, "Лёд + удар-приземление: раскол — двойной урон (%.0f против %.0f)" % [hp_near - _hp(near), hp_other - _hp(other)])
			check(_hp(far) < hp_far, "Лёд: осколки задели соседа")
		&"lightning":
			check(_hp(very_far) < hp_vfar, "Молния + удар-приземление: разряд по врагу под током в 10 м")
		&"earth":
			check(_hp(near) < landed_near, "Земля + удар-приземление: вторая волна у прибитого")
		&"wind":
			var moved := near0.distance_to(near.global_position) if is_instance_valid(near) else 99.0
			check(moved > 2.0, "Ветер + удар-приземление: вихрь снёс врага на %.1f м" % moved)

func _scenario_quake() -> void:
	# Бывшее «Землетрясение»: молот — в пол в ~4 м, враг в 3 м за молотом (вне волны игрока)
	var pitch := -atan2(1.6, 4.0)
	_reset_player(pitch)
	await frames(5)
	var far := _dummy(0, 7.6)
	hand.throw_hammer()
	var stuck := await _wait_state(MjolnirProjectile.State.STUCK, 1.0)
	check(stuck and hand.projectile.stuck_normal.y > 0.6, "молот воткнулся в пол")
	if stuck:
		await _slam()
		await wait(0.5)
		check(_hurt(far), "Земля ур. 3 (Землетрясение): волна у молота задела врага")
	check(await _recall_and_wait(), "молот вернулся")

func _scenario_sky(t: MjolnirTrait) -> void:
	var pitch := -atan2(1.6, 8.0)
	_reset_player(pitch)
	await frames(5)
	var target := _dummy(0, 8.5)
	hand.throw_hammer()
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	hand.request_throw_or_recall()
	await _wait_in_hand(3.0)
	var hp0 := target.health
	hand.request_throw_or_recall()
	await frames(2)
	check(_hp(target) < hp0, "ур. 4 (%s): удар с неба в точку прицела" % t.id)
	if t.id == &"lightning":
		check(target.state == Enemy.State.STUNNED, "Гром небесный оглушает")
	check(hand.projectile != null and hand.projectile.damage_mult > 1.0, "бросок после идеального хвата усилен")
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	check(await _recall_and_wait(), "молот вернулся")

# --- Приёмы ---

func _test_technique(t: MjolnirTrait, lv: int) -> void:
	print("-- Приём %s (%s), ур. %d" % [t.title, t.id, lv])
	_set_traits(_lv(t.id, lv))
	check(hand.traits.size() == 1 and hand.traits[0].level == lv, "обработчик у молота, уровень %d" % lv)
	_clear_dummies()
	await frames(3)
	match t.id:
		&"storm":
			await _scenario_storm()
		&"hammer_step":
			await _scenario_step(lv)
		&"swap":
			await _scenario_swap(lv)
		&"hammer_dive":
			await _scenario_dive()
		&"sling":
			await _scenario_sling(lv)
		&"charge":
			await _scenario_charge(lv)
		&"air_catch":
			await _scenario_air_catch(lv)
		&"loyal_dog":
			await _scenario_dog()
		_:
			await _scenario_generic(t)
	check(hand.in_hand, "молот в руке после сценария")
	check(p.is_physics_processing(), "игрок снова управляется")
	_clear_dummies()
	await frames(3)

func _scenario_generic(t: MjolnirTrait) -> void:
	_reset_player()
	await frames(5)
	var line := [_dummy(0, 4), _dummy(0, 7)]
	var side := [_dummy(3.0, 7.5), _dummy(-3.0, 10.0)]
	var wall_l := _dummy(2.2, 16.0, t.id == &"magnet")
	var _wall_r := _dummy(-2.2, 16.0, t.id == &"magnet")
	var wall_d0 := 0.0
	var start_pos := p.global_position
	var saw_stuck := false
	var clones_seen := 0
	hand.throw_hammer()
	check(not hand.in_hand, "бросок")
	for i in 150:
		await get_tree().physics_frame
		var cl := 0
		for c in p.get_parent().get_children():
			if c is MjolnirProjectile and (c as MjolnirProjectile).is_clone:
				cl += 1
		clones_seen = maxi(clones_seen, cl)
		if hand.projectile and is_instance_valid(hand.projectile) and hand.projectile.is_stuck():
			saw_stuck = true
			wall_d0 = _flat_dist(wall_l, hand.projectile.global_position)
			break
		if hand.in_hand:
			break
	check(line.any(_hurt), "попал по врагу на линии")
	match t.id:
		&"boomerang":
			check(not saw_stuck, "Бумеранг не втыкается")
			check(await _wait_in_hand(3.0), "Бумеранг вернулся сам, без ПКМ")
			return
		&"ricochet":
			check(side.any(_hurt), "рикошет задел врага в стороне")
		&"two_hammers":
			check(clones_seen >= hand.traits[0].level, "Два молота: копий в полёте %d" % clones_seen)
	if t.id != &"ricochet":
		check(saw_stuck, "молот воткнулся")
	if saw_stuck:
		await wait(1.2 if t.handler.get("stuck_hold") != null else 0.3)
		if t.id == &"magnet":
			var d1 := _flat_dist(wall_l, hand.projectile.global_position)
			check(d1 < wall_d0 - 0.5, "Магнит стянул врага (%.1f → %.1f м)" % [wall_d0, d1])
		check(hand.projectile != null and hand.projectile.is_stuck(), "воткнутый молот ждёт ПКМ")
		var hp_before := _hp(wall_l)
		hand.request_throw_or_recall()
		if t.id == &"pull_to_hammer":
			check(not p.is_physics_processing(), "Притяжение: игрок летит к молоту")
		await frames(2)
		if t.id == &"magnet":
			check(not is_instance_valid(wall_l) or wall_l.health < hp_before, "Магнит раскидал врагов при возврате")
	check(await _wait_in_hand(4.0), "молот вернулся")
	if t.id == &"pull_to_hammer":
		var moved := start_pos.distance_to(p.global_position)
		check(moved > 10.0, "Притяжение перенесло игрока к стене (%.1f м)" % moved)

func _flat_dist(e: Node3D, pos: Vector3) -> float:
	if not is_instance_valid(e):
		return 0.0
	return Vector2(e.global_position.x - pos.x, e.global_position.z - pos.z).length()

func _scenario_storm() -> void:
	_reset_player()
	await frames(5)
	var side := _dummy(2.0, 6.5)
	hand.hold_override = true
	hand.throw_hammer()
	var hovered := await _wait_state(MjolnirProjectile.State.HOVER, 1.0)
	check(hovered, "Буря: молот завис")
	await wait(1.0)
	check(hand.projectile != null and hand.projectile.state == MjolnirProjectile.State.HOVER, "висит, пока ПКМ зажата")
	check(_hurt(side), "Буря: урон по кругу")
	hand.hold_override = false
	check(await _wait_in_hand(3.0), "отпустил ПКМ — вернулся")

func _scenario_step(lv: int) -> void:
	_reset_player()
	await frames(5)
	var h := hand.traits[0]
	hand.throw_hammer()
	var stuck := await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	check(stuck and absf(hand.projectile.stuck_normal.y) < 0.5, "молот воткнулся в стену")
	check(bool(h.call("has_step")), "Ступенька: площадка на рукояти")
	if bool(h.call("has_step")):
		var top: Vector3 = h.call("step_top")
		p.global_position = top + Vector3(0, 0.05, 0)
		p.velocity = Vector3.ZERO
		await wait(0.3)
		check(p.is_on_floor(), "Тор стоит на молоте (%.2f м)" % p.global_position.y)
		Input.action_press("jump")
		await frames(2)
		Input.action_release("jump")
		var peak := p.global_position.y
		for i in 90:
			await get_tree().physics_frame
			peak = maxf(peak, p.global_position.y)
		var normal := p.jump_velocity * p.jump_velocity / (2.0 * p.gravity)
		check(peak - top.y > normal * 1.6, "прыжок со ступеньки выше обычного (%.1f м против %.1f)" % [peak - top.y, normal])
		if lv >= 2:
			check(peak - top.y > normal * 2.5, "ур. 2: ещё выше (%.1f м)" % (peak - top.y))
		check(hand.projectile != null and hand.projectile.is_stuck(), "молот-ступенька ждёт ПКМ")
	check(await _recall_and_wait(), "молот вернулся")
	check(not bool(h.call("has_step")), "площадка исчезла с молотом")

func _scenario_swap(lv: int) -> void:
	_reset_player()
	await frames(5)
	# Между старым и новым местом Тора: молот задевает его и туда (до обмена), и обратно — с места Тора
	var near_old := _dummy(0.0, 1.6)
	var start_pos := p.global_position
	hand.throw_hammer()
	await wait(0.22)
	check(hand.projectile != null and hand.projectile.state == MjolnirProjectile.State.OUT, "молот в полёте")
	var hp0 := _hp(near_old)
	hand.request_throw_or_recall()
	await frames(1)
	var moved := start_pos.distance_to(p.global_position)
	check(moved > 4.0, "Обмен: Тор на месте молота (%.1f м)" % moved)
	check(await _wait_in_hand(3.0), "молот прилетел с места Тора в руку")
	check(_hp(near_old) < hp0, "молот на возврате задел врага у старого места Тора")
	var h := hand.traits[0]
	check(int(h.get("swaps")) == 1, "обмен засчитан")
	if lv >= 2:
		check(int(h.get("bursts")) == 1, "ур. 2: волна в точке прибытия")
	# Воткнутый молот ПКМ возвращает как обычно
	_reset_player()
	await frames(3)
	hand.throw_hammer()
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	var before := p.global_position
	hand.request_throw_or_recall()
	await frames(2)
	check(before.distance_to(p.global_position) < 1.0, "воткнутый молот — обычный возврат (без обмена)")
	await _wait_in_hand(3.0)

func _scenario_dive() -> void:
	_reset_player(-1.2)
	p.global_position = START + Vector3(0, 7.0, 0)
	await frames(2)
	var target := _dummy(0, 3.3)
	var powers: Array[float] = []
	var cb := func(pw: float) -> void: powers.append(pw)
	p.slammed.connect(cb)
	hand.throw_hammer()
	check(hand.projectile != null and hand.projectile.data.get("dive", false), "Пике: бросок вниз в воздухе")
	var followed := false
	for i in 120:
		await get_tree().physics_frame
		if p.is_slamming:
			followed = true
		if hand.in_hand:
			break
	p.slammed.disconnect(cb)
	check(followed, "Тор полетел за молотом ударом-приземлением")
	check(not powers.is_empty() and powers[0] > 0.25 + 7.0 / 14.0, "бонус высоты: сила %.2f (без бонуса ≤ %.2f)" % [powers[0] if not powers.is_empty() else 0.0, 0.25 + 7.0 / 14.0])
	check(hand.in_hand, "после удара молот сразу в руке")
	check(_hurt(target), "удар пике задел врага у молота")
	# На земле бросок вниз — обычный
	_reset_player(-1.2)
	await frames(10)
	hand.throw_hammer()
	check(hand.projectile != null and not hand.projectile.data.get("dive", false), "на земле — обычный бросок")
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	check(await _recall_and_wait(), "молот вернулся")

func _scenario_sling(lv: int) -> void:
	_reset_player()
	await frames(5)
	var h := hand.traits[0]
	var near := _dummy(1.6, 0.6)
	check(bool(hand.trait_modify(&"hold_throw", false)), "Праща: бросок по отпусканию ПКМ")
	hand.hold_override = true
	hand.begin_hold()
	await wait(1.0)
	check(hand.in_hand and hand.holding, "держим ПКМ — молот ещё «в руке»")
	check(bool(h.call("is_spinning")), "молот крутится вокруг Тора")
	check(_hurt(near), "Праща: удар по врагу рядом")
	check(hand.hold_progress > 0.0, "HUD: прогресс пращи")
	hand.hold_override = false
	await frames(2)
	check(not hand.in_hand and hand.projectile != null, "отпустил — бросок")
	if hand.projectile:
		var want: float = float(h.get("launch_damage_mult_lvl2") if lv >= 2 else h.get("launch_damage_mult"))
		check(hand.projectile.pierce and is_equal_approx(hand.projectile.damage_mult, want), "бросок с разгона: пробивает, ×%.1f урона" % want)
	check(not bool(h.call("is_spinning")), "молот на ремне исчез")
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	check(await _recall_and_wait(), "молот вернулся")
	# Короткое нажатие — обычный бросок
	await wait(0.4)
	hand.hold_override = true
	hand.begin_hold()
	await frames(3)
	hand.hold_override = false
	await frames(2)
	check(hand.projectile != null and not hand.projectile.pierce and is_equal_approx(hand.projectile.damage_mult, 1.0), "короткое нажатие — обычный бросок")
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	check(await _recall_and_wait(), "молот вернулся")

func _scenario_charge(lv: int) -> void:
	_reset_player()
	await frames(5)
	var h := hand.traits[0]
	# Щитоносец на линии, смотрит на Тора: обычный бросок щит держит, полный заряд — пробивает
	var sh := _dummy(0, 5, false, "shieldbearer")
	sh.state = Enemy.State.CHASE
	var to := p.global_position - sh.global_position
	sh.rotation.y = atan2(to.x, to.z)
	await frames(2)
	var hp0 := sh.health
	hand.hold_override = true
	hand.begin_hold()
	await frames(3)
	hand.hold_override = false
	await frames(2)
	check(hand.projectile != null and is_equal_approx(hand.projectile.damage_mult, 1.0) and not hand.projectile.pierce, "короткое нажатие — обычный бросок")
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	check(is_equal_approx(sh.health, hp0), "щит держит обычный бросок")
	await _recall_and_wait()
	sh.state = Enemy.State.CHASE
	await wait(0.4)
	hand.hold_override = true
	hand.begin_hold()
	await wait(1.0)
	check(is_equal_approx(hand.hold_progress, 1.0) and hand.hold_label != "", "полный заряд (HUD: %s)" % hand.hold_label)
	hand.hold_override = false
	await frames(2)
	var want: float = float(h.get("max_damage_mult_lvl2") if lv >= 2 else h.get("max_damage_mult"))
	check(hand.projectile != null and hand.projectile.pierce and is_equal_approx(hand.projectile.damage_mult, want), "полный заряд: ×%.1f урона и пробитие" % want)
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	check(sh.health < hp0, "полный заряд пробил щит")
	if lv >= 2:
		check(not is_instance_valid(sh) or sh.state == Enemy.State.STUNNED or sh.is_dead, "ур. 2: полный заряд оглушает")
	check(await _recall_and_wait(), "молот вернулся")

func _scenario_air_catch(lv: int) -> void:
	_reset_player()
	var g := p.gravity
	var rech := p.dash_recharge
	p.gravity = 0.0
	p.dash_recharge = 999.0
	p.global_position = START + Vector3(0, 3.0, 0)
	p.velocity = Vector3.ZERO
	await frames(3)
	var h := hand.traits[0]
	hand.throw_hammer()
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	p._jumps_left = 0
	p._wall_jumps_left = 0
	p.dash_charges = 0
	hand.request_throw_or_recall()
	await _wait_in_hand(3.0)
	await frames(1)
	check(int(h.get("catches")) == 1, "Перехват: поймал в воздухе")
	check(p._jumps_left == p.extra_jumps, "двойной прыжок снова есть")
	check(p.dash_charges >= mini(p.dash_charges_max, 1 + (2 if lv >= 2 else 1)), "руны восстановлены: база и приём (%d)" % p.dash_charges)
	p.gravity = g
	p.dash_recharge = rech
	# На земле — без эффекта
	_reset_player()
	await wait(0.4)
	hand.throw_hammer()
	await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	await _recall_and_wait()
	check(int(h.get("catches")) == 1, "на земле — без перехвата")

func _scenario_dog() -> void:
	_reset_player()
	await frames(5)
	var h := hand.traits[0]
	var wall_l := _dummy(2.5, 12.0)
	hand.throw_hammer()
	var stuck := await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
	check(stuck, "молот воткнулся")
	var hp0 := _hp(wall_l)
	await wait(2.2)
	check(int(h.get("bites")) >= 1 and _hp(wall_l) < hp0, "Верный пёс укусил врага рядом (%d раз)" % int(h.get("bites")))
	check(hand.projectile != null and hand.projectile.is_stuck(), "молот остаётся воткнутым")
	check(await _recall_and_wait(), "молот вернулся")

# --- Связки ---

func _test_combo(c: MjolnirTrait) -> void:
	print("-- Связка %s (%s)" % [c.title, c.id])
	_set_traits([_find(c.combo_element), _find(c.combo_technique)])
	check(Run.active_combos().size() == 1 and Run.active_combos()[0] == c, "связка активна сама")
	check(hand.combo_traits.size() == 1, "обработчик связки у молота")
	var h := hand.combo_traits[0]
	_clear_dummies()
	await frames(3)
	match c.id:
		&"fire_tornado":
			_reset_player()
			await frames(5)
			var d := _dummy(2.0, 6.5)
			hand.hold_override = true
			hand.throw_hammer()
			await _wait_state(MjolnirProjectile.State.HOVER, 1.0)
			await wait(1.0)
			check(ElementStatus.is_burning(d) and int(h.get("ignited")) > 0, "Огненный смерч поджигает врагов в круге")
			hand.hold_override = false
			await _wait_in_hand(3.0)
		&"ice_ricochet":
			_reset_player()
			await frames(5)
			var _a := [_dummy(0, 4), _dummy(3.0, 7.5), _dummy(-3.0, 10.0)]
			hand.throw_hammer()
			await _wait_in_hand(4.0)
			if not hand.in_hand:
				await _recall_and_wait()
			check(int(h.get("crusts")) > 0, "Ледяной рикошет: корок на полу %d" % int(h.get("crusts")))
		&"lightning_magnet":
			_reset_player()
			await frames(5)
			var _w := [_dummy(2.2, 16.0, true), _dummy(-2.2, 16.0, true)]
			hand.throw_hammer()
			await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
			await wait(1.4)
			check(int(h.get("discharges")) > 0, "Грозовой магнит: разряды по стянутым (%d)" % int(h.get("discharges")))
			await _recall_and_wait()
		&"wind_pull":
			# Молот — в пол в 7 м, враг рядом с точкой прилёта
			_reset_player(-atan2(1.6, 7.0))
			await frames(5)
			var w := _dummy(2.2, 7.5, true)
			var w0 := w.global_position
			hand.throw_hammer()
			await _wait_state(MjolnirProjectile.State.STUCK, 1.5)
			hand.request_throw_or_recall()
			await _wait_in_hand(3.0)
			await wait(0.4)
			check(int(h.get("gusts")) == 1, "Ураганный рывок: вихрь на прилёте")
			check(not is_instance_valid(w) or w0.distance_to(w.global_position) > 1.0, "толпу у молота снесло (%.1f м)" % (w0.distance_to(w.global_position) if is_instance_valid(w) else 0.0))
		&"earth_dive":
			_reset_player(-1.2)
			p.global_position = START + Vector3(0, 7.0, 0)
			await frames(2)
			var f := _dummy(1.5, 3.3, false, "fodder")
			var g := _dummy(-1.5, 3.3)
			hand.throw_hammer()
			await _wait_in_hand(3.0)
			await frames(3)
			check(int(h.get("craters")) == 1, "Кратер после пике")
			check(not is_instance_valid(f) or f.is_dead, "корм в кратере упал замертво")
			check(ElementStatus.is_pinned(g) or not is_instance_valid(g), "остальных прибило к полу")
	check(hand.in_hand, "молот в руке после сценария")
	check(p.is_physics_processing(), "игрок снова управляется")
	_clear_dummies()
	await frames(3)

func _finish() -> void:
	_set_traits([])
	print("=== ИТОГ TRAITS: %d OK, %d FAIL ===" % [_passes, _fails.size()])
	for f in _fails:
		print("   FAIL: ", f)
	get_tree().paused = false
	FX.reset_time()
	get_tree().quit(0 if _fails.is_empty() else 1)
