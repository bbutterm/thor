extends RefCounted
class_name Oaths
## Клятвы Одина (С3, NOW.md партия 5): руны с большим плюсом и явной ценой (RuneDef.oath, цена — RuneDef.oath_cost).
## В выборе рун клятва — одна карточка из трёх примерно в oath_chance выборов (Run.random_rune_choices), своя рамка,
## цена красной строкой, реплика Одина (пул odin.oath_offer); снять нельзя, уровень один. Числа — level_values (плюс)
## и level_values_b (цена) в run/runes/oath_*.tres. Эффекты — здесь, вызовы — одной строкой в игровом коде:
## урон (PlayerRunes._rune_damage_mult), лечение (PlayerHealth.heal), руны на земле (Player._update_timers),
## Слава (Run.add_glory), первый удар в зале (PlayerHealth.take_damage), здоровье/скорость/руны (PlayerRunes.recalc,
## Player.effective_move_speed), хват (attach: сигналы MjolnirHand), зал без урона (Game._on_room_cleared), отдых (RewardFlow).

const FURY := "oath_fury"
const SKY := "oath_sky"
const HAMMER := "oath_hammer"
const STORM := "oath_storm"
const PRIDE := "oath_pride"
const WIND := "oath_wind"
const WARRIOR := "oath_warrior"
## Урон Мьёльнира (снаряд, стихии с молота) и оружия правой руки — для Клятвы молота
const HAMMER_SOURCES := ["hammer", "lightning", "fire", "ice", "earth", "wind", "storm"]
const HAND_SOURCES := ["melee", "melee_finisher", "melee_heavy", "ranged"]

## Урон уже получен в этом зале (Клятва гордыни — первый удар двойной; Клятва воина — зал без урона)
static var _hurt_this_room: bool = false

static func has(id: String) -> bool:
	return Run.rune_level(id) > 0

## Плюс клятвы (level_values[0]) и цена (level_values_b[0])
static func plus(id: String) -> float:
	var r := Run.rune_def(id)
	return float(r.level_values[0]) if r and r.level_values.size() > 0 else 0.0

static func cost(id: String) -> float:
	var r := Run.rune_def(id)
	return float(r.level_values_b[0]) if r and r.level_values_b.size() > 0 else 0.0

## Множитель урона Тора по врагу
static func damage_mult(source: String) -> float:
	var m := 1.0
	if has(FURY):
		m *= 1.0 + plus(FURY)
	if has(SKY) and source == "slam":
		m *= plus(SKY)
	if has(HAMMER):
		if source in HAMMER_SOURCES:
			m *= 1.0 + plus(HAMMER)
		elif source in HAND_SOURCES:
			m *= 1.0 - cost(HAMMER)
	return m

static func heal_mult() -> float:
	return cost(FURY) if has(FURY) else 1.0

## Руны копятся на земле (Клятва небес — только поимкой молота)
static func ground_recharge() -> bool:
	return not has(SKY)

static func glory_mult() -> float:
	return 1.0 + plus(PRIDE) if has(PRIDE) else 1.0

static func speed_mult() -> float:
	return 1.0 + plus(WIND) if has(WIND) else 1.0

static func max_health_mult() -> float:
	return 1.0 - cost(WIND) if has(WIND) else 1.0

static func extra_dash() -> int:
	return int(Run.rune_def(WIND).level_values[1]) if has(WIND) and Run.rune_def(WIND).level_values.size() > 1 else 0

## Отдых лечит (Клятва воина — нет)
static func rest_heals() -> bool:
	return not has(WARRIOR)

## Новый зал (Game._load_room)
static func on_room_start() -> void:
	_hurt_this_room = false

## Пришёл урон (до вычета): Клятва гордыни — первый удар в зале двойной
static func on_damaged(amount: float) -> float:
	if amount <= 0.0:
		return amount
	var first := not _hurt_this_room
	_hurt_this_room = true
	if first and has(PRIDE):
		amount *= cost(PRIDE)
	return amount

## Зал зачищен: Клятва воина — без полученного урона случайная руна +1 уровень. Возвращает руну или null.
static func on_room_cleared() -> RuneDef:
	if not has(WARRIOR) or _hurt_this_room:
		return null
	var ups: Array[RuneDef] = []
	var seen := {}
	for r in Run.runes:
		var rr := r as RuneDef
		if seen.has(rr.id) or rr.oath or rr.cursed:
			continue
		seen[rr.id] = true
		if Run.rune_level(rr.id) < Run.RUNE_MAX_LEVEL:
			ups.append(rr)
	if ups.is_empty():
		return null
	var pick := ups[randi() % ups.size()]
	Run.add_rune(pick)
	return pick

## Клятва бури: сигналы хвата у руки игрока (Game._ready)
static func attach(p: Player) -> void:
	p.mjolnir.perfect_catch.connect(func() -> void: _storm_strike(p))
	p.mjolnir.catch_timing.connect(func(result: StringName, _offset: float) -> void:
		if has(STORM) and result != &"perfect" and not p.is_dead:
			RunTracker.note_damage("oath_storm")
			p.take_damage(cost(STORM), Vector3.ZERO, true))

## Идеальный хват бьёт молнией всех рядом (radius — level_values[1], урон — level_values[0])
static func _storm_strike(p: Player) -> void:
	if not has(STORM) or p.is_dead:
		return
	var r := Run.rune_def(STORM)
	var radius := float(r.level_values[1]) if r.level_values.size() > 1 else 7.0
	var from := p.global_position + Vector3(0, 1.4, 0)
	for n in p.get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e and not e.is_dead and e.global_position.distance_to(p.global_position) <= radius:
			FX.lightning(p.get_parent(), from, e.global_position + Vector3(0, 1.0, 0), 0.18)
			p.deal_damage(e, plus(STORM), Vector3.UP * 2.0, "lightning")
	Audio.play("sounds/sfx/lightning.wav")
