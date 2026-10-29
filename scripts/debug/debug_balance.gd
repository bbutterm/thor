extends RefCounted
class_name DebugBalance
## Глобальные множители debug-панели (П8, DEBUG_PANEL.md): мобы, корм в волнах, цены ларька, Слава, скорость времени.
## По умолчанию всё ×1 — без панели игра не меняется. Значения крутит DebugPanel (источники «enemy_mult», «econ_mult»,
## «waves_mult» — это объекты Mults ниже), читают: Enemy._ready (apply_enemy), Room.start (корм), Shop.price, Run.register_kill,
## FXTime._set_time_scale (time_mult). Урон Тора по врагам за 10 с для строки состояния — note_damage из Player.deal_damage.

class Mults extends RefCounted:
	## ХП мобов (кроме элиты, мини-боссов и боссов) / элиты и мини-боссов / боссов
	var hp: float = 1.0
	var hp_elite: float = 1.0
	var hp_boss: float = 1.0
	## Урон (attack_damage, projectile_damage, boss_slam_damage), скорость, замах, пауза между атаками
	var damage: float = 1.0
	var speed: float = 1.0
	var windup: float = 1.0
	var cooldown: float = 1.0
	## Прибавка к устойчивости к отбросу (потолок 1)
	var knock_resist_add: float = 0.0
	## Броня боссов от мили (П4): < 0 — из данных врага
	var boss_melee_resist: float = -1.0
	## Изменение ХП-множителя пересчитывает и живых врагов
	var apply_to_live: bool = true

class Econ extends RefCounted:
	## Цены ларька × и Слава за врага ×
	var shop_price: float = 1.0
	var glory: float = 1.0

class Waves extends RefCounted:
	## Количество корма в волнах ×
	var fodder_count: float = 1.0

static var enemy := Mults.new()
static var econ := Econ.new()
static var waves := Waves.new()
## Множитель скорости времени поверх хит-стопа и замедлений (FXTime умножает, а не перезаписывает)
static var time_mult: float = 1.0
## Множители, с которыми уже пересчитан каждый живой враг (для «Применить и к живым»)
const APPLIED_META := &"_debug_hp_mult"

static var _damage_log: Array = []

## Вид врага для ХП-множителя: «boss» (финальный), «elite» (элита и мини-боссы), «mob»
static func layer_of(e: Enemy) -> String:
	if e.kind == Enemy.Kind.BOSS and not e.has_meta("miniboss"):
		return "boss"
	if e.has_meta("elite") or e.has_meta("miniboss") or e.kind == Enemy.Kind.BOSS:
		return "elite"
	return "mob"

static func hp_mult_for(e: Enemy) -> float:
	match layer_of(e):
		"boss":
			return enemy.hp_boss
		"elite":
			return enemy.hp_elite
	return enemy.hp

## Новый враг (Enemy._ready, отложенно — после элиты и мини-босса): множители поверх EnemyDef
static func apply_enemy(e: Enemy) -> void:
	if not is_instance_valid(e) or e.is_dead or e.has_meta(APPLIED_META):
		return
	var k := hp_mult_for(e)
	e.set_meta(APPLIED_META, k)
	e.set_meta(&"_debug_spawn_msec", Time.get_ticks_msec())
	if not is_equal_approx(k, 1.0):
		e.max_health *= k
		e.health *= k
	if not is_equal_approx(enemy.damage, 1.0):
		e.attack_damage *= enemy.damage
		e.projectile_damage *= enemy.damage
		e.boss_slam_damage *= enemy.damage
	if not is_equal_approx(enemy.speed, 1.0):
		e.move_speed *= enemy.speed
	if not is_equal_approx(enemy.windup, 1.0):
		e.windup_time *= enemy.windup
		e.boss_slam_windup *= enemy.windup
	if not is_equal_approx(enemy.cooldown, 1.0):
		e.attack_cooldown *= enemy.cooldown
		e.recover_time *= enemy.cooldown
	if not is_zero_approx(enemy.knock_resist_add):
		e.knock_resist = clampf(e.knock_resist + enemy.knock_resist_add, 0.0, 1.0)
	if enemy.boss_melee_resist >= 0.0 and e.kind == Enemy.Kind.BOSS:
		e.melee_resist = clampf(enemy.boss_melee_resist, 0.05, 1.0)

## ХП-множитель поменялся: живые враги пересчитывают max_health и текущее ХП пропорционально
static func refresh_live_hp(tree: SceneTree) -> void:
	if not enemy.apply_to_live or tree == null:
		return
	for n in tree.get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.is_dead or not e.has_meta(APPLIED_META):
			continue
		var old := float(e.get_meta(APPLIED_META))
		var k := hp_mult_for(e)
		if is_equal_approx(old, k) or old <= 0.0:
			continue
		e.max_health *= k / old
		e.health *= k / old
		e.set_meta(APPLIED_META, k)

## Скорость времени: текущий масштаб пересчитывается, дальше FXTime._set_time_scale умножает сам
static func set_time_mult(v: float) -> void:
	v = clampf(v, 0.05, 4.0)
	var base := Engine.time_scale / maxf(time_mult, 0.001)
	time_mult = v
	Engine.time_scale = base * v

## Урон Тора по врагу (Player.deal_damage) — для «урон в секунду за 10 с»
static func note_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	_damage_log.append([now, amount])
	while not _damage_log.is_empty() and now - float(_damage_log[0][0]) > 10.0:
		_damage_log.pop_front()

static func dps() -> float:
	var now := Time.get_ticks_msec() / 1000.0
	var sum := 0.0
	for d in _damage_log:
		if now - float(d[0]) <= 10.0:
			sum += float(d[1])
	return sum / 10.0

## Всё к ×1 (сброс панели, тесты)
static func reset() -> void:
	enemy = Mults.new()
	econ = Econ.new()
	waves = Waves.new()
	if not is_equal_approx(time_mult, 1.0):
		set_time_mult(1.0)
	_damage_log.clear()
