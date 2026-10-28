extends RefCounted
class_name EnemyRangedAttacks
## Снаряды и опасные зоны врагов (GDD 12.6): выбор атаки и её выполнение.
## Метатель — веер или навесной; шаман — медленные сферы и круг проклятия под Тором; Раздутый — лужа после
## взрыва; воин с копьём — бросок копья с 8–12 м; наёмник — граната с меткой.
## Лимит одновременных снарядов и зон — Room.max_projectiles / Room.max_zones: при превышении враг
## берёт обычную атаку или ждёт. Числа — поля Enemy (группа «Снаряды и зоны»), TUNING.md.
## Компонент Enemy (этап 3 рефакторинга): состояние — поля Enemy (_attack_mode, _special_cd), доступ — enemy.ranged.

const PROJECTILE := preload("res://enemies/enemy_projectile.gd")

## Запасные лимиты, если враг не в зале (тесты, арены без Room)
static var default_max_projectiles: int = 14
static var default_max_zones: int = 5

var enemy: Enemy

func _init(owner_node: Enemy) -> void:
	enemy = owner_node

# --- Лимиты ---

static func _room_of(node: Node) -> Node:
	var n := node
	while n:
		if n is Room:
			return n
		n = n.get_parent()
	return null

static func _live_count(tree: SceneTree, group: String) -> int:
	var c := 0
	for n in tree.get_nodes_in_group(group):
		if not n.is_queued_for_deletion():
			c += 1
	return c

## Можно ли выпустить ещё n снарядов (лимит зала).
static func can_fire(node: Node, n: int = 1) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	var room := _room_of(node)
	var limit: int = int(room.get("max_projectiles")) if room else default_max_projectiles
	return _live_count(node.get_tree(), "enemy_projectiles") + n <= limit

## Можно ли поставить ещё n зон (лимит зала).
static func can_add_zone(node: Node, n: int = 1) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	var room := _room_of(node)
	var limit: int = int(room.get("max_zones")) if room else default_max_zones
	return _live_count(node.get_tree(), "hazard_zones") + n <= limit

# --- Выбор атаки (из Enemy._think_chase; &"" — обычная атака вида, &"wait" — ждать) ---

func choose_thrower() -> StringName:
	var r := randf()
	if r < enemy.thrower_fan_chance and can_fire(enemy, enemy.thrower_fan_count):
		return &"fan"
	if r < enemy.thrower_fan_chance + enemy.thrower_lob_chance and can_fire(enemy):
		return &"lob"
	return &"" if can_fire(enemy) else &"wait"

func choose_shaman() -> StringName:
	if enemy._special_cd > 0.0:
		return &"wait"
	if randf() < enemy.shaman_orb_chance:
		if can_fire(enemy):
			return &"orb"
	if can_add_zone(enemy):
		return &"curse"
	return &"orb" if can_fire(enemy) else &"wait"

func choose_merc(dist: float) -> StringName:
	if dist > enemy.merc_grenade_min_dist and enemy._special_cd <= 0.0 and randf() < enemy.merc_grenade_chance and can_fire(enemy):
		return &"grenade"
	return &""

## Воин с копьём на 8–12 м: бросок вместо подхода (раз в spear_cooldown).
func wants_spear(dist: float) -> bool:
	return enemy.hand_weapon == "q_spear" and enemy._special_cd <= 0.0 and enemy._cooldown <= 0.0 \
		and dist >= enemy.spear_min_dist and dist <= enemy.spear_max_dist and can_fire(enemy) \
		and enemy._has_line_of_sight()

# --- Телеграф замаха ---

func windup_telegraph(mode: StringName) -> void:
	var top := enemy.global_position + Vector3(0, 2.0 * enemy.model_scale, 0)
	match mode:
		&"orb", &"curse":
			FX.burst(enemy.get_parent(), top, 0.45, Color(0.75, 0.3, 1.0, 0.7), enemy.windup_time)
			Audio.sfx("orb_cast", "sounds/sfx/orb_cast.wav")
		&"spear", &"grenade":
			Audio.sfx("zombie_groan" if FX.is_undead(enemy) else "", "sounds/sfx/enemy_growl.wav")

# --- Выполнение (из Enemy._execute_attack) ---

func execute(mode: StringName) -> bool:
	match mode:
		&"fan":
			fire_fan()
		&"lob":
			fire_lob()
		&"orb":
			cast_orb()
		&"curse":
			cast_curse()
		&"spear":
			throw_spear()
		&"grenade":
			throw_grenade()
		_:
			return false
	return true

func _origin() -> Vector3:
	return enemy.global_position + Vector3(0, 1.4 * enemy.model_scale, 0) + enemy.global_transform.basis.z * 0.6

func _target(lead: float) -> Vector3:
	var p := enemy.player
	return p.global_position + Vector3(0, 0.9, 0) + p.velocity * lead

func _spawn(kind: EnemyProjectile.Kind, origin: Vector3, vel: Vector3, damage: float, setup: Callable = Callable()) -> EnemyProjectile:
	var proj := PROJECTILE.new() as EnemyProjectile
	proj.kind = kind
	if setup.is_valid():
		setup.call(proj)
	enemy.get_parent().add_child(proj)
	proj.launch(origin, vel, damage, enemy)
	return proj

## Веер: thrower_fan_count прямых снарядов в секторе thrower_fan_spread_deg.
func fire_fan() -> void:
	Perf.mark("enemy_fan")
	if enemy.player == null:
		return
	var origin := _origin()
	var dir := (_target(0.2) - origin).normalized()
	var n := maxi(1, enemy.thrower_fan_count)
	var spread := deg_to_rad(enemy.thrower_fan_spread_deg)
	for i in n:
		var a := 0.0 if n == 1 else lerpf(-spread * 0.5, spread * 0.5, float(i) / (n - 1))
		var center := i == int(n / 2.0)
		_spawn(EnemyProjectile.Kind.STRAIGHT, origin, dir.rotated(Vector3.UP, a) * enemy.projectile_speed,
			enemy.projectile_damage * enemy.thrower_fan_damage_mult, func(p: EnemyProjectile) -> void: p.light = center)
	Audio.play("sounds/sfx/curse_throw.wav")

## Скорость, чтобы за время t долететь из from в to при гравитации g.
static func lob_velocity(from: Vector3, to: Vector3, t: float, g: float) -> Vector3:
	t = maxf(t, 0.1)
	var v := (to - from) / t
	v.y += 0.5 * g * t
	return v

## Навесной: дуга в точку, где Тор будет через lob_flight_time (метка на полу), всплеск lob_radius.
func fire_lob() -> void:
	Perf.mark("enemy_lob")
	if enemy.player == null:
		return
	var origin := _origin()
	var t := enemy.lob_flight_time
	var ground := Loot.floor_point(enemy, _target(t * 0.6))
	_spawn(EnemyProjectile.Kind.LOB, origin, lob_velocity(origin, ground, t, enemy.lob_gravity), enemy.projectile_damage,
		func(p: EnemyProjectile) -> void:
			p.fall_gravity = enemy.lob_gravity
			p.landing = ground
			p.flight_time = t
			p.blast_radius = enemy.lob_radius
			p.color = Color(1.0, 0.45, 0.85))
	Audio.play("sounds/sfx/curse_throw.wav")

## Медленная проклятая сфера: крупная, слабо доворачивает, Мьёльнир сбивает.
func cast_orb() -> void:
	Perf.mark("enemy_orb")
	enemy._special_cd = enemy.shaman_cast_interval
	if enemy.player == null:
		return
	var origin := enemy.global_position + Vector3(0, 1.9 * enemy.model_scale, 0) + enemy.global_transform.basis.z * 0.7
	var dir := (_target(0.0) - origin).normalized()
	_spawn(EnemyProjectile.Kind.ORB, origin, dir * enemy.shaman_orb_speed, enemy.shaman_orb_damage,
		func(p: EnemyProjectile) -> void:
			p.radius = enemy.shaman_orb_radius
			p.homing = enemy.shaman_orb_homing
			p.max_life = enemy.shaman_orb_life
			p.color = Color(0.6, 1.0, 0.35))
	Audio.sfx("orb_cast", "sounds/sfx/orb_cast.wav")

## Круг проклятия под Тором: телеграф → удар → лужа.
func cast_curse() -> HazardZone:
	Perf.mark("enemy_curse")
	enemy._special_cd = enemy.shaman_cast_interval
	if enemy.player == null or not can_add_zone(enemy):
		return null
	var z := HazardZone.make(HazardZone.Shape.CIRCLE, enemy.player.global_position, Vector3.FORWARD,
		enemy.shaman_curse_radius, enemy.shaman_curse_telegraph, enemy.shaman_curse_damage, Color(0.7, 0.25, 1.0), enemy)
	z.puddle_time = enemy.shaman_curse_puddle_time
	z.puddle_dps = enemy.shaman_curse_puddle_dps
	z.source_id = RunTracker.source_id_of(enemy)
	return z.place(enemy.get_parent())

## Копьё: прямой быстрый снаряд с упреждением.
func throw_spear() -> void:
	Perf.mark("enemy_spear")
	enemy._special_cd = enemy.spear_cooldown
	if enemy.player == null:
		return
	var origin := _origin()
	var dir := (_target(0.25) - origin).normalized()
	_spawn(EnemyProjectile.Kind.SPEAR, origin, dir * enemy.spear_speed, enemy.attack_damage * enemy.spear_damage_mult,
		func(p: EnemyProjectile) -> void:
			p.radius = 0.25
			p.color = Color(0.95, 0.8, 0.55))
	Audio.play("sounds/sfx/axe_swing_2.wav")

## Граната наёмника: дуга с меткой, на полу — взрыв с фитилём (Blast.delayed, бьёт и своих).
func throw_grenade() -> void:
	Perf.mark("enemy_grenade")
	enemy._special_cd = enemy.merc_grenade_cooldown
	if enemy.player == null:
		return
	var origin := _origin()
	var t := enemy.merc_grenade_flight
	var ground := Loot.floor_point(enemy, _target(t * 0.5))
	_spawn(EnemyProjectile.Kind.GRENADE, origin, lob_velocity(origin, ground + Vector3(0, 0.15, 0), t, enemy.lob_gravity), enemy.merc_grenade_damage,
		func(p: EnemyProjectile) -> void:
			p.fall_gravity = enemy.lob_gravity
			p.landing = ground
			p.flight_time = t
			p.radius = 0.18
			p.blast_radius = enemy.merc_grenade_radius
			p.fuse = enemy.merc_grenade_fuse
			p.color = Color(1.0, 0.55, 0.15))
	Audio.play("sounds/sfx/hammer_throw.wav")

## Раздутый после взрыва: лужа браги/яда (BrewPuddle — замедляет; свой лимит луж).
func bloated_puddle() -> void:
	if enemy.bloat_puddle_time <= 0.0 or not enemy.is_inside_tree():
		return
	var p := BrewPuddle.spawn(enemy.get_parent(), enemy.global_position, enemy.bloat_puddle_radius, enemy.bloat_puddle_time, enemy.bloat_puddle_slow)
	if p:
		p.color = Color(0.55, 1.0, 0.45)
		FX.sprite_color(p._disc, p.color, 1.0)
