extends RefCounted
class_name Loot
## Откуда берётся оружие: элитные враги (гарантированно), сундук после зачистки зала (выбор 1 из 2),
## патроны с врагов. Описания оружия — все .tres из weapons/defs/ (новое оружие подхватывается само).

const DEFS_DIR := "res://weapons/defs/"
const ELITE_COLOR := Color(1.0, 0.72, 0.2)

static var _defs: Array[WeaponDef] = []

static func all_defs() -> Array[WeaponDef]:
	if _defs.is_empty():
		for f in ResourceLoader.list_directory(DEFS_DIR):
			var clean := f.trim_suffix(".remap")
			if clean.ends_with(".tres"):
				var d := load(DEFS_DIR + clean) as WeaponDef
				if d:
					_defs.append(d)
	return _defs

static func get_def(id: String) -> WeaponDef:
	for d in all_defs():
		if d.id == id:
			return d
	return null

static func _holder() -> WeaponHolder:
	var tree := Engine.get_main_loop() as SceneTree
	var p := tree.get_first_node_in_group("player") as Player if tree else null
	return p.weapons if p else null

## Случайное оружие класса cls ("" — любого) из пула выпадения, кроме id из exclude.
static func random_def(cls: String = "", exclude: Array = []) -> WeaponDef:
	var h := _holder()
	var all := h.drop_all_weapons if h else false
	var pool: Array[WeaponDef] = []
	var total := 0.0
	for d in all_defs():
		if (cls != "" and d.weapon_class != cls) or d.id in exclude:
			continue
		if not all and not in_run_pool(d):
			continue
		pool.append(d)
		total += maxf(0.0, d.drop_weight)
	if pool.is_empty():
		return null
	var r := randf() * total
	for d in pool:
		r -= maxf(0.0, d.drop_weight)
		if r <= 0.0:
			return d
	return pool[pool.size() - 1]

## В пуле выпадения: стартовое (in_drop_pool) или купленное в «Плане тренировок»; закрытое — нет.
static func in_run_pool(d: WeaponDef) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var save: Node = tree.root.get_node_or_null("Save") if tree else null
	if save == null:
		return d.in_drop_pool
	if not save.is_in_pool("weapon", d.id):
		return false
	if d.in_drop_pool:
		return true
	for u in save.all_unlocks:
		if u.kind == "weapon" and d.id in u.targets() and save.is_unlocked(u.id):
			return true
	return false

static func random_level() -> int:
	var h := _holder()
	var r := randf()
	if h and r < h.drop_level3_chance:
		return 3
	if h and r < h.drop_level3_chance + h.drop_level2_chance:
		return 2
	return 1

## Точка на полу под pos (луч вниз по миру).
static func floor_point(node: Node3D, pos: Vector3) -> Vector3:
	var space := node.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.5, 0), pos + Vector3(0, -30, 0), 1)
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else pos

## Оружие на полу. from — откуда «вылетает» (брошенное из руки, из сундука).
static func spawn_weapon(parent: Node, pos: Vector3, item: WeaponItem, from: Vector3 = Vector3.INF) -> WeaponPickup:
	Perf.mark("weapon_drop")
	var p := WeaponPickup.new()
	p.item = item
	parent.add_child(p)
	var ground := floor_point(p, pos)
	p.place(ground, from)
	return p

static func spawn_ammo(parent: Node, pos: Vector3) -> Node3D:
	var a := AmmoPickup.new()
	parent.add_child(a)
	a.global_position = floor_point(a, pos) + Vector3(0, 0.02, 0)
	return a

# --- Элита ---

## Решить при спавне, станет ли враг элитой (до add_child: меняет здоровье, урон, вид).
static func maybe_make_elite(room: Node, enemy: Enemy, chance: float, max_per_room: int) -> void:
	if enemy.kind == Enemy.Kind.BOSS or chance <= 0.0:
		return
	var n: int = room.get_meta("elites", 0)
	if n >= max_per_room or randf() >= chance:
		return
	room.set_meta("elites", n + 1)
	make_elite(enemy)

## Элита (GDD 12.4): светится, ×2.5 HP, урон ×1.5, гарантированно роняет оружие.
static func make_elite(enemy: Enemy) -> void:
	enemy.set_meta("elite", true)
	enemy.max_health *= 2.5
	enemy.attack_damage *= 1.5
	enemy.projectile_damage *= 1.5
	enemy.model_scale *= 1.12
	enemy.eye_glow = Color(1.0, 0.6, 0.15, 1.0)
	# Метка над головой: вращающийся золотой ромб (общий меш и материал эффектов)
	var mark := Node3D.new()
	mark.name = "EliteMark"
	var mi := MeshInstance3D.new()
	mi.mesh = FX.shared_mesh("box")
	FX.fx_apply(mi, "glow", ELITE_COLOR, 2.0)
	mi.scale = Vector3(0.22, 0.22, 0.22)
	mi.rotation_degrees = Vector3(45, 0, 45)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.add_child(mi)
	var ring := MeshInstance3D.new()
	ring.mesh = FX.shared_mesh("ring")
	FX.fx_apply(ring, "alpha", Color(ELITE_COLOR, 0.8), 1.0)
	ring.name = "EliteRing"
	ring.scale = Vector3(0.75, 0.3, 0.75) * enemy.model_scale
	ring.position.y = 0.08
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	enemy.add_child(ring)
	enemy.add_child(mark)
	mark.position = Vector3(0, 2.45 * enemy.model_scale, 0)
	var tw := mark.create_tween().set_loops()
	tw.tween_property(mark, "rotation:y", TAU, 1.6).from(0.0)

static func is_elite(enemy: Node) -> bool:
	return enemy != null and enemy.has_meta("elite")

## Смерть врага: элита роняет оружие (60 % мили / 40 % ренж), иногда — патроны.
static func on_enemy_died(enemy: Enemy, _source: String) -> void:
	var parent := enemy.get_parent()
	if parent == null:
		return
	var pos := enemy.global_position
	var h := _holder()
	if is_elite(enemy):
		var cls := "melee" if randf() < 0.6 else "ranged"
		var d := random_def(cls)
		if d == null:
			d = random_def()
		if d:
			spawn_weapon(parent, pos, WeaponItem.create(d, random_level()), pos + Vector3(0, 1.5, 0))
		if h and h.ranged:
			spawn_ammo(parent, pos + Vector3(0.6, 0, 0.3))
		return
	if h and h.wants_ammo():
		var chance := h.ammo_drop_chance * (2.0 if enemy.kind == Enemy.Kind.THROWER else 1.0)
		if randf() < chance:
			spawn_ammo(parent, pos)

# --- Сундук ---

## Зал зачищен: иногда сундук там, где пал последний враг.
static func on_room_cleared(room: Node3D, pos: Vector3, chance: float) -> void:
	if Run.is_boss_room():
		return
	# Двери-награды (блок И): сундук — только в зале, куда вошли через дверь «Сундук»
	if Run.doors_enabled:
		if Run.current_reward() != "chest":
			return
	elif Run.room_index > 0 and randf() >= chance:
		return
	# Последний враг пал в низине/пропасти — ставим сундук рядом с игроком
	var p := (Engine.get_main_loop() as SceneTree).get_first_node_in_group("player") as Player
	var ground := floor_point(room, pos)
	if p and (absf(ground.y - p.global_position.y) > 2.5 or ground.distance_to(pos) > 6.0):
		var fwd := p.get_aim_forward()
		fwd.y = 0
		pos = p.global_position + (fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD) * 2.5
	spawn_chest(room, pos)

static func spawn_chest(parent: Node3D, pos: Vector3) -> Chest:
	Perf.mark("chest_spawn")
	var c := Chest.new()
	parent.add_child(c)
	c.global_position = floor_point(c, pos)
	var p := (Engine.get_main_loop() as SceneTree).get_first_node_in_group("player") as Node3D
	if p:
		var to := p.global_position - c.global_position
		to.y = 0
		if to.length() > 0.1:
			c.rotation.y = atan2(to.x, to.z)
	return c

# --- Прогрев шейдеров (вызывается из ShaderWarmup) ---

## Образцы всего, что появляется с оружием: модели ренжа на полу, кольца/лучи подбора, сундук, ящик патронов,
## трассер, болт, гильза, вспышка дула, метка элиты. Без групп — их нельзя подобрать во время прогрева.
static func warmup_samples(parent: Node3D, right: Vector3) -> void:
	var x := -1.2
	for d in all_defs():
		var p := WeaponPickup.new()
		p.item = WeaponItem.create(d)
		parent.add_child(p)
		p.remove_from_group("interactable")
		p.remove_from_group("pickups")
		p.position = right * x + Vector3(0, -0.4, 0.4)
		x += 0.22
	var c := Chest.new()
	c.set_meta("warmup", true)
	parent.add_child(c)
	c.remove_from_group("interactable")
	c.position = right * 1.4 + Vector3(0, -0.2, 0)
	var a := AmmoPickup.new()
	parent.add_child(a)
	a.remove_from_group("ammo_pickups")
	a.position = right * -1.6
	var t := RangedWeapon.make_tracer_mesh()
	parent.add_child(t)
	t.position = Vector3(0, 0.6, 0)
	var b := WeaponMeshes.bolt()
	parent.add_child(b)
	b.position = Vector3(0.3, 0.6, 0)
	var cs := RangedWeapon.make_casing()
	cs.freeze = true
	cs.remove_from_group("casings")
	parent.add_child(cs)
	cs.position = Vector3(-0.3, 0.6, 0)
	var f := RangedWeapon.make_flash_mesh(1)
	f.visible = true
	parent.add_child(f)
	f.position = Vector3(0, 0.9, 0)
	f.scale = Vector3(0.1, 0.1, 0.25)
