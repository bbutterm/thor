extends Node
class_name ElementStatus
## Состояние стихий Мьёльнира на враге (блок Б4, GDD 10): горит, промёрз / заморожен, под током, прибит.
## Узел-ребёнок врага (имя "ElementStatus"), создаётся при первом эффекте: ElementStatus.of(enemy, true).
## Числа приходят от обработчика стихии (weapons/mjolnir_traits/<стихия>.tres), здесь только таймеры.
## Урон горения — через player.deal_damage (источник "fire"); вид — общие пулы FX (без своих материалов).
## Боссы (Kind.BOSS: Свен, Ярл) не замедляются и не замерзают по-настоящему: скорость им не трогаем (фазы
## босса сами меняют move_speed), «заморозка» — только отметка на BOSS_FREEZE_MULT времени (для раскола).
const BOSS_FREEZE_MULT := 0.5

const NODE_NAME := "ElementStatus"

var enemy: Enemy
# --- Огонь ---
var burn_left: float = 0.0
var burn_dps: float = 0.0
## Поколение огня: 0 — поджёг молот, 1+ — перекинулся с соседа (дальше spread_max_gen не идёт)
var burn_gen: int = 0
var spread_radius: float = 2.5
var spread_interval: float = 1.0
var spread_max_gen: int = 2
## Перекинувшийся огонь горит дольше/короче в столько раз
var spread_time_mult: float = 0.7
# --- Лёд ---
var chill_stacks: int = 0
var chill_left: float = 0.0
var frozen_left: float = 0.0
var slow_per_stack: float = 0.25
var slow_min_mult: float = 0.4
# --- Молния ---
var shocked_left: float = 0.0
# --- Земля ---
var pinned_left: float = 0.0

## Искры горения на всех врагах — не больше стольких за кадр физики (лимит узлов с instance uniform в GL Compatibility)
const BURN_FX_PER_FRAME := 2
static var _fx_frame: int = -1
static var _fx_count: int = 0

var _burn_tick: float = 0.0
var _spread_t: float = 0.0
var _fx_t: float = 0.0
var _base_speed: float = -1.0

## Состояние врага; create — создать, если нет. null — не враг или мёртв.
static func of(e: Node, create: bool = false) -> ElementStatus:
	var en := e as Enemy
	if en == null or not is_instance_valid(en):
		return null
	var s := en.get_node_or_null(NODE_NAME) as ElementStatus
	if s == null and create and not en.is_dead:
		s = ElementStatus.new()
		s.name = NODE_NAME
		s.enemy = en
		en.add_child(s)
	return s

static func is_burning(e: Node) -> bool:
	var s := of(e)
	return s != null and s.burn_left > 0.0

static func is_frozen(e: Node) -> bool:
	var s := of(e)
	return s != null and s.frozen_left > 0.0

static func is_shocked(e: Node) -> bool:
	var s := of(e)
	return s != null and s.shocked_left > 0.0

static func is_pinned(e: Node) -> bool:
	var s := of(e)
	return s != null and s.pinned_left > 0.0

func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player if is_inside_tree() else null

# --- Огонь ---

## Поджечь: dps урона в секунду на time секунд (повторный поджог продлевает, не складывается)
func ignite(dps: float, time: float, gen: int = 0) -> void:
	if enemy == null or enemy.is_dead:
		return
	if burn_left <= 0.0:
		burn_gen = gen
		_spread_t = spread_interval
		FX.sparks(enemy.get_parent(), _chest(), Color(1.0, 0.55, 0.15), 10, 4.0, -2.0)
	else:
		burn_gen = mini(burn_gen, gen)
	burn_left = maxf(burn_left, time)
	burn_dps = maxf(burn_dps, dps)

func extinguish() -> void:
	burn_left = 0.0

# --- Лёд ---

## Промёрз: +stacks; на freeze_at стаке — заморозка на freeze_time. true — заморозило.
func chill(stacks: int, freeze_at: int, chill_time: float, freeze_time: float) -> bool:
	if enemy == null or enemy.is_dead or frozen_left > 0.0:
		return false
	chill_stacks += stacks
	chill_left = chill_time
	if freeze_at > 0 and chill_stacks >= freeze_at:
		freeze(freeze_time)
		return true
	_apply_speed()
	return false

func freeze(time: float) -> void:
	if enemy == null or enemy.is_dead:
		return
	chill_stacks = 0
	chill_left = 0.0
	if _is_boss():
		frozen_left = maxf(frozen_left, time * BOSS_FREEZE_MULT)
	else:
		frozen_left = maxf(frozen_left, time)
		enemy.knockback_velocity = Vector3.ZERO
		enemy.apply_stun(time, true)
		_apply_speed()
	FX.ice_hit(enemy.get_parent(), enemy.global_position, time)
	ComicFX.pop("freeze", _chest())
	Audio.sfx("ice_freeze", "sounds/sfx/hammer_bounce.wav")
	Perf.mark("element_freeze")

## Расколоть заморозку (удар-приземление льда): вернуть скорость
func thaw() -> void:
	frozen_left = 0.0
	chill_stacks = 0
	chill_left = 0.0
	_apply_speed()

# --- Молния и земля ---

func shock(time: float) -> void:
	shocked_left = maxf(shocked_left, time)

func pin(time: float) -> void:
	if enemy == null or enemy.is_dead:
		return
	pinned_left = maxf(pinned_left, time)
	enemy.knockback_velocity = Vector3.ZERO
	enemy.velocity.y = minf(enemy.velocity.y, -6.0)
	enemy.apply_stun(time, true)

# --- Тик ---

func _physics_process(delta: float) -> void:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_dead:
		set_physics_process(false)
		return
	shocked_left = maxf(0.0, shocked_left - delta)
	pinned_left = maxf(0.0, pinned_left - delta)
	if frozen_left > 0.0:
		frozen_left -= delta
		if frozen_left <= 0.0:
			thaw()
	if chill_left > 0.0:
		chill_left -= delta
		if chill_left <= 0.0:
			chill_stacks = 0
			_apply_speed()
	if burn_left > 0.0:
		_burn(delta)
	if enemy == null or not is_instance_valid(enemy) or enemy.is_dead:
		return
	_update_glow(delta)

## Цвета состояний на теле врага (пульс), по важности: заморожен > под током > горит > прибит > промёрз
const GLOW_FROZEN := Color(0.55, 0.9, 1.0)
const GLOW_SHOCK := Color(1.0, 0.95, 0.45)
const GLOW_BURN := Color(1.0, 0.42, 0.08)
const GLOW_PIN := Color(0.85, 0.55, 0.25)
const GLOW_CHILL := Color(0.5, 0.75, 1.0)
var _glow_t: float = 0.0
var _arc_t: float = 0.0

func _update_glow(delta: float) -> void:
	_glow_t += delta
	var c := Color(0, 0, 0, 0)
	if frozen_left > 0.0:
		c = Color(GLOW_FROZEN, 0.75 + 0.1 * sin(_glow_t * 6.0))
	elif shocked_left > 0.0:
		# Под током — рваное мигание и искры-дуги по телу
		c = Color(GLOW_SHOCK, 0.35 + 0.6 * float(randf() < 0.5))
		_arc_t -= delta
		if _arc_t <= 0.0 and _fx_budget():
			_arc_t = 0.22
			var ch := _chest()
			FX.lightning(enemy.get_parent(), ch + Vector3(randf_range(-0.4, 0.4), 0.5, randf_range(-0.4, 0.4)),
				ch + Vector3(randf_range(-0.4, 0.4), -0.6, randf_range(-0.4, 0.4)), 0.1, GLOW_SHOCK)
	elif burn_left > 0.0:
		c = Color(GLOW_BURN, 0.55 + 0.3 * sin(_glow_t * 14.0))
	elif pinned_left > 0.0:
		c = Color(GLOW_PIN, 0.45 + 0.15 * sin(_glow_t * 5.0))
	elif chill_stacks > 0 and chill_left > 0.0:
		c = Color(GLOW_CHILL, 0.25 + 0.12 * chill_stacks)
	enemy.status_glow = c

func _burn(delta: float) -> void:
	burn_left -= delta
	_burn_tick += delta
	_fx_t -= delta
	if _fx_t <= 0.0 and _fx_budget():
		_fx_t = 0.3
		FX.sparks(enemy.get_parent(), _chest() + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2)), Color(1.0, 0.5, 0.12), 9, 3.0, -4.0, 0.1, 0.6)
	if _burn_tick >= 0.5:
		var p := _player()
		var dmg := burn_dps * _burn_tick
		_burn_tick = 0.0
		if p:
			p.deal_damage(enemy, dmg, Vector3.ZERO, "fire")
		else:
			enemy.take_hit(dmg, Vector3.ZERO, "fire")
		if enemy == null or not is_instance_valid(enemy) or enemy.is_dead:
			return
	# Огонь перекидывается на ближайшего соседа (GDD 10: «перекидывается на соседей»)
	_spread_t -= delta
	if _spread_t <= 0.0 and burn_gen < spread_max_gen:
		_spread_t = spread_interval
		var best: Enemy = null
		var best_d := spread_radius
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Enemy
			if en == null or en == enemy or en.is_dead or ElementStatus.is_burning(en):
				continue
			var d := en.global_position.distance_to(enemy.global_position)
			if d < best_d:
				best_d = d
				best = en
		if best:
			var s := ElementStatus.of(best, true)
			s.spread_radius = spread_radius
			s.spread_interval = spread_interval
			s.spread_max_gen = spread_max_gen
			s.spread_time_mult = spread_time_mult
			s.ignite(burn_dps, maxf(1.0, burn_left * spread_time_mult + 1.0), burn_gen + 1)
			FX.lightning(enemy.get_parent(), _chest(), best.global_position + Vector3(0, 1.0, 0), 0.15, Color(1.0, 0.55, 0.15))
	if burn_left <= 0.0:
		burn_gen = 0

static func _fx_budget() -> bool:
	var f := Engine.get_physics_frames()
	if f != _fx_frame:
		_fx_frame = f
		_fx_count = 0
	_fx_count += 1
	return _fx_count <= BURN_FX_PER_FRAME

func _is_boss() -> bool:
	return enemy != null and enemy.kind == Enemy.Kind.BOSS

func _apply_speed() -> void:
	if enemy == null or not is_instance_valid(enemy) or _is_boss():
		return
	if _base_speed < 0.0:
		_base_speed = enemy.move_speed
	var mult := 1.0
	if frozen_left > 0.0:
		mult = 0.0
	elif chill_stacks > 0:
		mult = maxf(slow_min_mult, 1.0 - slow_per_stack * chill_stacks)
	enemy.move_speed = _base_speed * mult
	if mult >= 1.0:
		_base_speed = -1.0

func _chest() -> Vector3:
	return enemy.global_position + Vector3(0, 1.0 * enemy.model_scale, 0)
