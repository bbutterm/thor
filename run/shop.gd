extends RefCounted
class_name Shop
## Ларёк Брокка и Эйтри (блок К, GDD 13): цены, доступность и эффекты товаров (run/shop/*.tres).
## Экран — ui/shop.gd (ShopScreen); ларёк в зале — rooms/shop_stall.gd. Тесты зовут buy() напрямую.

const DIR := "res://run/shop/"
## «Кот в мешке»: исходы и веса (сумма — любая)
const BAG_OUTCOMES := {"rune": 25, "weapon": 20, "heal": 15, "silver": 10, "curse": 15, "nothing": 15}
## «Кот в мешке»: лечение (доля макс. HP), серебро-«сдача», проклятие (доля текущего HP)
const BAG_HEAL := 0.5
const BAG_SILVER := 80
const BAG_CURSE := 0.25
## Брокк «богат клиент» — от стольких серебра
const RICH_SILVER := 150

static var _items: Array[ShopItemDef] = []

static func items() -> Array[ShopItemDef]:
	if _items.is_empty():
		for f in ResourceLoader.list_directory(DIR):
			var clean := f.trim_suffix(".remap")
			if clean.ends_with(".tres"):
				var it := load(DIR + clean) as ShopItemDef
				if it:
					_items.append(it)
		_items.sort_custom(func(a: ShopItemDef, b: ShopItemDef) -> bool: return a.order < b.order)
	return _items

static func get_item(id: String) -> ShopItemDef:
	for it in items():
		if it.id == id:
			return it
	return null

static func _holder(game: Game) -> WeaponHolder:
	return game.player.weapons if game and game.player else null

## Оружие, которое точит Эйтри: то, что в руке.
static func sharpen_target(game: Game) -> WeaponItem:
	var h := _holder(game)
	return h.current() if h else null

## Цена с учётом скидки «Плана тренировок» (−15 %) и Кузнеца (заточка −50 %).
static func price(game: Game, it: ShopItemDef) -> int:
	var p := float(it.price)
	if it.pays_player:
		return it.price
	if it.id == "sharpen":
		var w := sharpen_target(game)
		if w and w.level >= 2 and it.price2 > 0:
			p = float(it.price2)
		if game and game.player:
			p *= float(game.player.modify_stat(&"sharpen_cost_mult", 1.0))  # «Своя наковальня» Кузнеца — ×0.5
	p *= 1.0 - clampf(Save.perk("shop_discount"), 0.0, 0.9)
	return int(round(p))

## Трейты Мьёльнира, которые можно улучшить.
static func upgradable_traits() -> Array[MjolnirTrait]:
	var out: Array[MjolnirTrait] = []
	for t in Run.mjolnir_traits:
		if Run.mjolnir_trait_level(t.id) < t.max_level:
			out.append(t)
	return out

## Руны в наличии (без повторов).
static func owned_runes() -> Array[RuneDef]:
	var out: Array[RuneDef] = []
	var seen := {}
	for r in Run.runes:
		if not seen.has(r.id):
			seen[r.id] = true
			out.append(r)
	return out

## "" — можно купить, иначе — почему нельзя (без учёта денег).
static func unavailable_reason(game: Game, it: ShopItemDef) -> String:
	var p := game.player
	match it.id:
		"shawarma":
			if p.health >= p.max_health - 0.5:
				return "Ты и так сыт"
		"rune":
			if Run.random_rune_choices(1).is_empty():
				return "Руны кончились"
		"sharpen":
			var w := sharpen_target(game)
			if w == null:
				return "Нечего точить"
			if w.level >= 3:
				return "%s — уже уровень 3" % w.def.display_name
		"ammo":
			var h := _holder(game)
			if h == null or h.ranged == null:
				return "Нет ренжа"
			if h.ranged.reserve >= h.ranged.def.reserve_max and h.ranged.mag >= h.ranged.def.mag_size:
				return "Запас полный"
		"mjolnir_service":
			if not Run.mjolnir_traits.is_empty() and upgradable_traits().is_empty():
				return "Трейты на максимуме"
			if Run.mjolnir_traits.is_empty() and Run.trait_rerolls > 0:
				return "Переброс уже заказан"
		"sell_rune":
			if Run.runes.is_empty():
				return "Нет рун"
	return ""

## Подробность для строки (что именно будет).
static func detail(game: Game, it: ShopItemDef) -> String:
	match it.id:
		"shawarma":
			return "+%d HP" % int(round(game.player.max_health * it.amount))
		"sharpen":
			var w := sharpen_target(game)
			return ("%s: ур. %d → %d" % [w.def.display_name, w.level, w.level + 1]) if w and w.level < 3 else ""
		"mjolnir_service":
			return "Улучшить трейт" if not Run.mjolnir_traits.is_empty() else "Переброс у мини-босса"
	return ""

static func can_buy(game: Game, it: ShopItemDef) -> bool:
	return unavailable_reason(game, it) == "" and (it.pays_player or Run.silver >= price(game, it))

## Самая дешёвая покупка (для реакции «нет денег»).
static func cheapest(game: Game) -> int:
	var best := 1 << 30
	for it in items():
		if not it.pays_player and unavailable_reason(game, it) == "":
			best = mini(best, price(game, it))
	return best

## Варианты второго шага: какой трейт улучшить / какую руну сдать. Пусто — выбор не нужен.
static func sub_choices(it: ShopItemDef) -> Array:
	var out: Array = []
	match it.id:
		"mjolnir_service":
			for t in upgradable_traits():
				out.append({"id": str(t.id), "title": t.title, "desc": "Уровень %d → %d" % [Run.mjolnir_trait_level(t.id), Run.mjolnir_trait_level(t.id) + 1], "glyph": t.glyph, "color": t.color})
		"sell_rune":
			var owned := owned_runes()
			for i in range(owned.size() - 1, maxi(-1, owned.size() - 3), -1):
				var r := owned[i]
				out.append({"id": r.id, "title": r.title, "desc": "Уровень %d. Брокк даст +%d" % [Run.rune_level(r.id), it.price], "glyph": r.glyph, "color": r.color})
	return out

## Купить. arg — выбор второго шага (id трейта / руны; для «Руны» — id руны без экрана выбора).
## Возвращает {ok, text, opened} — opened: открыт экран выбора руны (ларёк спрячется до выбора).
static func buy(game: Game, it: ShopItemDef, arg: String = "") -> Dictionary:
	if not can_buy(game, it):
		return {"ok": false, "text": unavailable_reason(game, it)}
	Perf.mark("shop_buy_" + it.id)
	var cost := price(game, it)
	var p := game.player
	var res := {"ok": true, "text": it.title, "opened": false}
	if it.pays_player:
		if not Run.remove_rune(arg):
			return {"ok": false, "text": "Нет такой руны"}
		while Run.remove_rune(arg):
			pass
		p.recalc_from_runes(Run)
		Run.add_silver(cost)
		res.text = "Руна сдана: +%d серебра" % cost
		return res
	Run.spend_silver(cost)
	match it.id:
		"shawarma":
			p.heal(p.max_health * it.amount)
			res.text = "Шаурма: +%d HP" % int(round(p.max_health * it.amount))
		"rune":
			if arg != "":
				for r in Run.all_runes:
					if r.id == arg:
						Run.add_rune(r)
						p.recalc_from_runes(Run)
						res.text = "Руна: " + r.title
			else:
				game.rewards.rune_mode = "shop"
				game.rune_pick.open(Run.random_rune_choices(3), "РУНА ИЗ ЛАРЬКА")
				res.opened = true
		"sharpen":
			var w := sharpen_target(game)
			w.level = mini(3, w.level + 1)
			var h := _holder(game)
			if w.is_ranged():
				h.gun.equip(w)
			else:
				h.axe.apply_def(w.def, w.level)
			h.slots_changed.emit()
			res.text = "%s — уровень %d" % [w.def.display_name, w.level]
		"ammo":
			var h := _holder(game)
			h.ranged.reserve = h.ranged.def.reserve_max
			h.ranged.mag = h.ranged.def.mag_size
			h.ammo_changed.emit(h.ranged.mag, h.ranged.reserve)
			h.slots_changed.emit()
			Audio.play("sounds/sfx/ammo_pickup.wav")
			res.text = "Патроны: полный запас"
		"mjolnir_service":
			if Run.mjolnir_traits.is_empty():
				Run.trait_rerolls += 1
				res.text = "Эйтри перебросит выбор трейта у мини-босса"
			else:
				var t: MjolnirTrait = null
				for o in upgradable_traits():
					if str(o.id) == arg or (arg == "" and t == null):
						t = o
				Run.add_mjolnir_trait(t)
				res.text = "%s — уровень %d" % [t.title, Run.mjolnir_trait_level(t.id)]
		"mystery_bag":
			res.text = _open_bag(game)
	if it.odin_pool != "":
		Odin.say(it.odin_pool)
	return res

static func _roll_bag() -> String:
	var total := 0
	for k in BAG_OUTCOMES:
		total += int(BAG_OUTCOMES[k])
	var x := randi() % maxi(1, total)
	for k in BAG_OUTCOMES:
		x -= int(BAG_OUTCOMES[k])
		if x < 0:
			return k
	return "nothing"

## «Кот в мешке»: случайная вещь — может быть отличная, может быть «проклятая».
static func _open_bag(game: Game, forced: String = "") -> String:
	var p := game.player
	var o := forced if forced != "" else _roll_bag()
	match o:
		"rune":
			var rs := Run.random_rune_choices(1)
			if not rs.is_empty():
				Run.add_rune(rs[0])
				p.recalc_from_runes(Run)
				return "В мешке руна: %s!" % rs[0].title
		"weapon":
			var d := Loot.random_def()
			if d:
				var at := p.global_position + p.get_aim_forward() * Vector3(1, 0, 1) * 1.8
				Loot.spawn_weapon(game.room, at, WeaponItem.create(d, randi_range(2, 3)), at + Vector3(0, 1.5, 0))
				return "В мешке %s! Острое." % d.display_name
		"heal":
			p.heal(p.max_health * BAG_HEAL)
			return "В мешке… вторая шаурма. +%d HP" % int(p.max_health * BAG_HEAL)
		"silver":
			Run.add_silver(BAG_SILVER)
			return "Брокк перепутал мешки: +%d серебра" % BAG_SILVER
		"curse":
			p.take_damage(p.health * BAG_CURSE, Vector3.ZERO, true)
			return "В мешке был кот. Злой. Проклятый."
	return "Пустой мешок. Почти: записка «Брака не бывает»."

## Реакция Брокка на ситуацию (пул data/dialogues/dwarves.json).
static func reaction_pool(game: Game) -> String:
	var p := game.player
	if p.health < p.max_health * 0.35:
		return "dwarves.shop_low_hp"
	if Run.silver >= RICH_SILVER:
		return "dwarves.shop_rich"
	if Run.silver < cheapest(game):
		return "dwarves.shop_broke"
	return "dwarves.shop_enter"
