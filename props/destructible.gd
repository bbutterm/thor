extends RigidBody3D
class_name Destructible
## Разрушаемый пропс (GDD 16: «бочки катятся», разрушаемое; GDD 19: сочность): бочка, ящик, взрывная бочка.
## Скрипт на RigidBody3D сцены пропса (props/*.tscn, генератор: build_props), группа props, слой 4.
## Прочность и содержимое — @export ниже (на сцене), общие числа — props/destruct_tuning.tres (DestructTuning).
##
## Ломается:
## - от урона take_hit(dmg, knock, source): мили (axe.gd), Мьёльнир (бросок/возврат), ренж (ranged.gd),
##   удар-приземление (player.gd), рывок/таран (player.gd), взрывы и удары по площади (hit_area: blast.gd,
##   rocket.gd, удар босса, прыжок Ярла), таран Свена/Ярла (boss_enemy.gd); урон Тора идёт сюда в обход
##   множителей тела/берсерка/рун — Player.deal_damage отдаёт пропс сразу сюда (без on_hit, критов, «Зова грома»);
## - от огня (ignite / ignite_area: fire_zone.gd): горит burn_time секунд и разваливается, поджигает соседей;
## - от скорости (старое правило BarrelWatch): отбросило быстрее break_speed — удар о стену, падение с высоты.
## Разрушение: обломки модели (PropDebris — те же материалы), пыль/щепки FX, звук, малый hit-stop, слово
## комикса; содержимое — серебро (бочка), серебро/патроны/лечение (ящик, шансы в run/economy.tres), взрыв
## Blast (взрывная бочка; цепная реакция через chain_delay). Славы и убийств за пропсы нет.

signal broken(prop: Destructible, source: String)

@export_group("Прочность")
@export var max_health: float = 15.0
## Ломается, если отбросило быстрее (м/с). 0 — Economy.barrel_break_speed, < 0 — от скорости не ломается
@export var break_speed: float = 0.0
## Удар без разрушения толкает: knock × масса × это
@export var knock_impulse: float = 0.6

@export_group("Обломки")
## "radial" — клёпки по секторам + крышка и дно (бочка), "box" — шесть стенок (ящик)
@export var debris_mode: String = "radial"
@export var debris_sectors: int = 6
## Цвет щепок и пыли
@export var wood_color: Color = Color(0.55, 0.36, 0.2)
@export var break_sound: String = "sounds/sfx/barrel_break.wav"
@export var hit_sound: String = "sounds/sfx/prop_hit.wav"
## Событие комиксового слова (data/comic_words.json), "" — без слова
@export var comic_event: String = "smash"

@export_group("Огонь")
## Сколько горит до развала (с)
@export var burn_time: float = 2.5
## Через сколько секунд горения поджигает соседей в радиусе (м)
@export var fire_spread_delay: float = 1.0
@export var fire_spread_radius: float = 1.5

@export_group("Содержимое")
## "barrel" — серебро Silver.barrel_amount(); "crate" — серебро/патроны/лечение (Economy); "none"
@export var loot: String = "barrel"

@export_group("Взрыв")
@export var explosive: bool = false
@export var blast_radius: float = 4.0
@export var blast_damage: float = 40.0
## Задержка взрыва от чужого взрыва или огня — цепная реакция идёт волной, а не в один кадр
@export var chain_delay: float = 0.22
## Фитиль, если бочку ударили вплотную (мили, рывок, удар-приземление): шипит — успей отскочить.
## Ренж и Мьёльнир взрывают сразу
@export var melee_fuse: float = 0.6
@export var fuse_sound: String = "sounds/sfx/barrel_fuse.wav"
@export var blast_color: Color = Color(1.0, 0.4, 0.12)

var health: float = 0.0
var is_broken: bool = false
var burning: bool = false
var _burn_t: float = 0.0
var _spread_done: bool = false
var _fusing: bool = false
var _fire: Node3D

## Источники, разбитые которыми, — заслуга Тора (hit-stop, тряска)
const PLAYER_SOURCES := ["melee", "melee_finisher", "melee_heavy", "hammer", "ranged", "slam", "dash", "stomp", "lightning", "reflect"]
## Разбил ими — слово комикса (KRAK!/SMASH!)
const COMIC_SOURCES := ["melee_finisher", "melee_heavy", "hammer", "slam", "dash"]
## < 0 — шанс «сюрпризов» из Economy (в тестах — 0), иначе — этот (0 — без подмены бочек)
static var surprise_chance_override: float = -1.0

func _ready() -> void:
	health = max_health
	add_to_group("props")
	add_to_group("destructibles")
	# Причина смерти Тора от взрыва бочки (RunTracker.note_hit → «barrel», реплики Одина)
	set_meta("death_source_id", "barrel")
	# Комиксовая обводка (GDD 20): модель пропса (метка взрывной бочки — нет)
	Outline.add(get_node_or_null("Model"))

static func tuning() -> DestructTuning:
	return PropDebris.cfg()

func _speed_limit() -> float:
	if break_speed < 0.0:
		return INF
	return break_speed if break_speed > 0.0 else Silver.cfg().barrel_break_speed

func _physics_process(delta: float) -> void:
	if is_broken:
		return
	if burning:
		_burn_t += delta
		if not _spread_done and _burn_t >= fire_spread_delay:
			_spread_done = true
			Destructible.ignite_area(self, global_position, fire_spread_radius, self)
		if _burn_t >= burn_time:
			smash(Vector3.UP * 2.0, "fire")
			return
	if sleeping or freeze:
		return
	# Старое правило BarrelWatch: сильно отбросило — удар о стену, падение с высоты, рывок, молот
	if linear_velocity.length() > _speed_limit():
		smash(linear_velocity, "speed")

## Урон по пропсу. knock — направление и сила (как у врагов, м/с).
func take_hit(damage: float, knock: Vector3 = Vector3.ZERO, source: String = "") -> void:
	_hit(damage, knock, source, knock_impulse)

func _hit(damage: float, knock: Vector3, source: String, impulse_scale: float) -> void:
	if is_broken or _fusing or not is_inside_tree():
		return
	var mult: float = float(tuning().source_mult.get(source, 1.0))
	health -= damage * mult
	if source == "fire":
		ignite()
	if health <= 0.0:
		smash(knock, source)
		return
	if knock.length() > 0.01 and not freeze:
		apply_central_impulse(knock * mass * impulse_scale)
		apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * mass * 0.5)
	var chips := tuning().hit_chips
	if chips > 0:
		FX.sparks(get_parent(), global_position + Vector3(0, 0.5, 0), wood_color, chips, 4.0, 14.0, 0.06, 0.35)
	if hit_sound != "":
		Audio.play(hit_sound)

## Поджечь: горит burn_time секунд и разваливается.
func ignite() -> void:
	if burning or is_broken or not is_inside_tree():
		return
	burning = true
	_burn_t = 0.0
	Perf.mark("prop_ignite")
	_fire = Node3D.new()
	_fire.name = "Fire"
	add_child(_fire)
	_fire.position = Vector3(0, 0.15, 0)
	FX.fire_sprites(_fire, 0.35, burn_time + 0.3)
	if explosive:
		# Фитиль: взрывная бочка горит быстрее
		burn_time = minf(burn_time, 1.2)

## Разрушить. knock — откуда ударили (обломки летят по нему), source — чем.
func smash(knock: Vector3 = Vector3.ZERO, source: String = "") -> void:
	if is_broken or _fusing or not is_inside_tree():
		return
	var fuse := 0.0
	if explosive:
		if source in ["explosion", "fire", "chain"]:
			fuse = chain_delay
		elif source.begins_with("melee") or source in ["dash", "slam", "stomp"]:
			fuse = melee_fuse
	if fuse > 0.0:
		# Цепная реакция / удар вплотную: фитиль, потом взрыв
		_fusing = true
		Perf.mark("barrel_fuse")
		FX.sparks(get_parent(), global_position + Vector3(0, 1.0, 0), Color(1.0, 0.75, 0.3), 10, 4.0, 6.0, 0.05, maxf(0.3, fuse))
		if fuse >= 0.3 and fuse_sound != "":
			Audio.play(fuse_sound)
		get_tree().create_timer(fuse, false, true).timeout.connect(func() -> void:
			_fusing = false
			if is_instance_valid(self) and is_inside_tree():
				_break_now(knock, source))
		return
	_break_now(knock, source)

func _break_now(knock: Vector3, source: String) -> void:
	if is_broken:
		return
	is_broken = true
	Perf.mark("prop_break")
	remove_from_group("props")
	remove_from_group("destructibles")
	var parent := get_parent()
	var pos := global_position + global_transform.basis.y * 0.5
	var t := tuning()
	PropDebris.spawn(self, knock, debris_mode, debris_sectors, linear_velocity)
	FX.sparks(parent, pos, wood_color, 16, 6.0, 14.0, 0.09, 0.5)
	FX.burst(parent, pos, 0.7, Color(0.8, 0.6, 0.35, 0.5), 0.25)
	FX.barrel_dust(parent, pos)
	if break_sound != "":
		Audio.play(break_sound)
	if source in PLAYER_SOURCES:
		if t.break_hitstop > 0.0:
			FX.hitstop(t.break_hitstop)
		var p := get_tree().get_first_node_in_group("player") as Player
		if p and p.camera_fx and p.global_position.distance_to(pos) < 6.0:
			p.camera_fx.add_trauma(t.break_shake)
		# Слово — только на сильных моментах (GDD 19): не от обычного удара и не от пули
		if comic_event != "" and not explosive and source in COMIC_SOURCES:
			ComicFX.pop(comic_event, pos)
	if explosive:
		Blast.detonate(parent, pos + Vector3(0, 0.3, 0), blast_radius, blast_damage, self, self, blast_color)
	_drop_loot(parent, pos)
	broken.emit(self, source)
	queue_free()

func _drop_loot(parent: Node, pos: Vector3) -> void:
	match loot:
		"barrel":
			Silver.drop(parent, pos, Silver.barrel_amount())
		"crate":
			Destructible.crate_loot(parent, pos)

## Содержимое ящика (run/economy.tres): серебро, патроны (если в руке-слоте есть ренж), лечение или ничего.
static func crate_loot(parent: Node, pos: Vector3) -> String:
	var c := Silver.cfg()
	var r := randf()
	if r < c.crate_silver_chance:
		Silver.drop(parent, pos, randi_range(mini(c.crate_silver_min, c.crate_silver_max), maxi(c.crate_silver_min, c.crate_silver_max)))
		return "silver"
	r -= c.crate_silver_chance
	if r < c.crate_ammo_chance:
		var p := parent.get_tree().get_first_node_in_group("player") as Player if parent.is_inside_tree() else null
		if p and p.weapons and p.weapons.ranged != null:
			Loot.spawn_ammo(parent, pos)
			return "ammo"
		Silver.drop(parent, pos, c.crate_silver_min)
		return "silver"
	r -= c.crate_ammo_chance
	if r < c.crate_heal_chance:
		var h := HealOrb.new()
		h.amount = c.crate_heal_amount
		parent.add_child(h)
		h.launch(pos)
		return "heal"
	return "none"

# --- По площади ---

## Удар/взрыв по площади: пропсы в радиусе получают урон (спад к краю до min_falloff) и толчок
## (dir × push + вверх × up, как раньше в blast/rocket); RigidBody без Destructible — только толчок.
## Возвращает, сколько пропсов задело.
static func hit_area(from: Node, center: Vector3, radius: float, damage: float, push: float = 7.0, up: float = 4.0,
		source: String = "explosion", min_falloff: float = 0.5) -> int:
	if from == null or not from.is_inside_tree():
		return 0
	var n := 0
	for c in from.get_tree().get_nodes_in_group("props"):
		var rb := c as RigidBody3D
		if rb == null or rb == from or rb.is_queued_for_deletion():
			continue
		var d := rb.global_position - center
		var dist := d.length()
		if dist >= radius:
			continue
		var dir := d.normalized() if dist > 0.01 else Vector3.FORWARD
		var knock := dir * push + Vector3.UP * up
		var falloff := clampf(1.0 - dist / maxf(radius, 0.01), min_falloff, 1.0)
		if rb is Destructible:
			(rb as Destructible)._hit(damage * falloff, knock, source, 1.0)
		else:
			rb.apply_central_impulse(knock * rb.mass)
		n += 1
	return n

## Огонь по площади (fire_zone.gd, горящий пропс): поджечь пропсы в радиусе.
static func ignite_area(from: Node, center: Vector3, radius: float, except: Node = null) -> int:
	if from == null or not from.is_inside_tree():
		return 0
	var n := 0
	for c in from.get_tree().get_nodes_in_group("destructibles"):
		var d := c as Destructible
		if d == null or d == except or d.burning or d.is_broken:
			continue
		var off := d.global_position - center
		if Vector2(off.x, off.z).length() <= radius + 0.4 and absf(off.y) < 2.0:
			d.ignite()
			n += 1
	return n

# --- Сюрпризы ---

const EXPLOSIVE_SCENE := "res://props/barrel_explosive.tscn"
const BARREL_SCENE := "res://props/barrel.tscn"

## При загрузке зала (RewardFlow.on_room_loaded): часть обычных бочек — взрывные (Economy: шанс, предел на зал;
## в зале остаются хотя бы 2 обычные бочки). Тихие залы (привал, ларёк) не трогаем.
static func roll_surprises(room: Node) -> int:
	if room == null or not room.is_inside_tree():
		return 0
	var c := Silver.cfg()
	# В тестах (Save.is_test) сюрпризов нет — случайный взрыв ломал бы чужие проверки; свои — через override
	var chance := surprise_chance_override if surprise_chance_override >= 0.0 else (0.0 if Save.is_test else c.explosive_barrel_chance)
	if chance <= 0.0 or c.explosive_barrel_max <= 0:
		return 0
	var barrels: Array[Destructible] = []
	for n in room.find_children("*", "RigidBody3D", true, false):
		if n is Destructible and n.scene_file_path == BARREL_SCENE:
			barrels.append(n)
	barrels.shuffle()
	var scene := load(EXPLOSIVE_SCENE) as PackedScene
	var made := 0
	for b in barrels:
		if made >= c.explosive_barrel_max or barrels.size() - made <= 2:
			break
		if randf() >= chance:
			continue
		var e := scene.instantiate() as Destructible
		e.name = String(b.name) + "_boom"
		b.get_parent().add_child(e)
		e.global_transform = b.global_transform
		b.remove_from_group("props")
		b.remove_from_group("destructibles")
		b.queue_free()
		made += 1
	if made > 0:
		Perf.mark("explosive_barrels")
	return made

# --- Прогрев (ShaderWarmup) ---

const CRATE_SCENE := "res://props/crate.tscn"

## Образцы пропсов (взрывная бочка — свой материал метки), их обломки (режутся здесь — один раз за игру;
## свой формат вершин — свои пайплайны) и шар лечения. Без групп и физики — их не разбить при прогреве.
static func warmup_samples(parent: Node3D, right: Vector3) -> void:
	var x := -1.0
	for path in [BARREL_SCENE, CRATE_SCENE, EXPLOSIVE_SCENE]:
		if not ResourceLoader.exists(path):
			continue
		var d := (load(path) as PackedScene).instantiate() as Destructible
		if d == null:
			continue
		d.freeze = true
		d.collision_layer = 0
		d.collision_mask = 0
		parent.add_child(d)
		d.remove_from_group("props")
		d.remove_from_group("destructibles")
		d.set_physics_process(false)
		d.position = right * x + Vector3(0, -0.6, 0.4)
		var k := 0
		for p in PropDebris.pieces_for(d, d.debris_mode, d.debris_sectors):
			var mi := MeshInstance3D.new()
			mi.mesh = p.mesh
			parent.add_child(mi)
			mi.position = d.position + right * 0.45 + Vector3(0, 0.12 * k, 0)
			k += 1
		x += 1.0
	var h := HealOrb.new()
	parent.add_child(h)
	h.set_physics_process(false)
	h.remove_from_group("heal_orbs")
	h.position = right * -1.4 + Vector3(0, 0.5, 0)
