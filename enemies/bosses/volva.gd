extends BossEnemy
class_name VolvaBoss
## Вёльва-ведьма — мини-босс Мидгарда (GDD 14.1): колдунья на уступах.
## - Телепорт между высокими точками зала (верх блоков, балконы, вышки — ищет сама лучами сверху; нет высоких —
##   точки на полу подальше от Тора). Телеграф: фиолетовые кольца там, где она и куда уйдёт.
## - Огненные круги на полу (HazardZone, телеграф fire_telegraph ≈ 1 с, потом лужа огня) под Тором и рядом.
## - Поднимает корм (как шаман).
## - Летящий Мьёльнир сбивает её с уступа: падает, оглушена knock_stun секунд, урон по ней ×knock_damage_mult.
##   Лезть к ней или сбивать молотом. При engage_hp_fraction — злее: больше кругов, чаще.
## Числа и вид перекрывает MinibossDef (enemies/minibosses/volva.tres).

enum Act { NONE, TELEPORT, FIRE, RAISE, KNOCKED }

@export_group("Вёльва: телепорт")
@export var teleport_interval: float = 7.0
## Телеграф телепорта (с)
@export var teleport_time: float = 0.7
## Высокая точка — выше пола зала хотя бы на столько (м)
@export var high_min: float = 1.2
## Высокая точка не ближе к Тору, чем столько (м)
@export var teleport_min_dist: float = 6.0
@export_group("Вёльва: огонь")
@export var fire_interval: float = 4.5
@export var fire_windup: float = 0.7
@export var fire_count: int = 2
@export var fire_radius: float = 2.0
## Телеграф круга (GDD 14.1: 1 с)
@export var fire_telegraph: float = 1.0
@export var fire_damage: float = 14.0
@export var fire_puddle_time: float = 3.0
@export var fire_puddle_dps: float = 8.0
## Второй и следующие круги — рядом с Тором на таком расстоянии
@export var fire_spread: float = 3.2
@export_group("Вёльва: корм")
@export var raise_interval: float = 9.0
@export var raise_windup: float = 1.0
@export var raise_count: int = 3
@export var raise_cap: int = 24
@export_group("Вёльва: сбить молотом")
@export var knock_stun: float = 2.0
@export var knock_damage_mult: float = 1.5
@export_group("Вёльва: злость")
@export_range(0.0, 1.0) var engage_hp_fraction: float = 0.5
@export var engage_extra_fire: int = 1
@export var engage_interval_mult: float = 0.75

var high_points: Array[Vector3] = []
var teleports: int = 0
var knockdowns: int = 0
var engaged: bool = false
var _tp_cd: float = 2.5
var _fire_cd: float = 2.0
var _raise_cd: float = 5.0
var _tp_target: Vector3 = Vector3.INF
var _tp_ring: MeshInstance3D

const VIOLET := Color(0.7, 0.3, 1.0)
const FIRE := Color(1.0, 0.45, 0.12)

func _ready() -> void:
	super._ready()
	set_meta("death_source_id", "miniboss_volva")
	_find_high_points.call_deferred()

## Высокие точки зала: лучи сверху по сетке, поверхность выше пола на high_min, есть место встать.
func _find_high_points() -> void:
	high_points.clear()
	var room := _room() as Node3D
	if room == null or not is_inside_tree():
		return
	var floor_y := room.global_position.y
	var half := Vector2(14, 14)
	var fl := room.get_node_or_null("Geometry/Floor/Shape") as CollisionShape3D
	if fl and fl.shape is BoxShape3D:
		var sz := (fl.shape as BoxShape3D).size
		half = Vector2(sz.x, sz.z) * 0.5 - Vector2(1.5, 1.5)
		floor_y = fl.global_position.y + sz.y * 0.5
	var space := get_world_3d().direct_space_state
	var step := 2.0
	var x := -half.x
	while x <= half.x:
		var z := -half.y
		while z <= half.y:
			var top := room.global_position + Vector3(x, floor_y - room.global_position.y + 9.0, z)
			var q := PhysicsRayQueryParameters3D.create(top, top + Vector3(0, -12, 0), 1)
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and (hit.normal as Vector3).y > 0.8:
				var p: Vector3 = hit.position
				var h := p.y - floor_y
				if h >= high_min and h < 8.0:
					var up := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.1, 0), p + Vector3(0, 2.2, 0), 1)
					if space.intersect_ray(up).is_empty():
						high_points.append(p)
			z += step
		x += step

## Куда телепортироваться: высокая точка подальше от Тора; нет высоких — пол в 8–12 м от Тора.
func pick_teleport_point() -> Vector3:
	var pp := player.global_position if player and is_instance_valid(player) else global_position
	var cands: Array[Vector3] = []
	for p in high_points:
		if p.distance_to(global_position) > 2.0 and Vector2(p.x - pp.x, p.z - pp.z).length() >= teleport_min_dist:
			cands.append(p)
	if not cands.is_empty():
		return cands.pick_random()
	for i in 8:
		var a := randf() * TAU
		var c := pp + Vector3(cos(a), 0, sin(a)) * randf_range(8.0, 12.0)
		var g := Loot.floor_point(self, c)
		if g != c and absf(g.y - pp.y) < 2.0 and _clear_path(pp + Vector3.UP, g + Vector3.UP):
			return g
	return Vector3.INF

# --- Мышление ---

## Стоит на месте и колдует; вплотную к Тору — бьёт посохом (обычный ИИ босса).
func _think_chase() -> Vector3:
	if player == null or player.is_dead:
		return Vector3.ZERO
	if dist_to_player() < attack_range + 0.6:
		return super._think_chase()
	_face_dir(dir_to_player(), get_physics_process_delta_time())
	return Vector3.ZERO

func _boss_think(delta: float) -> void:
	_tp_cd -= delta
	_fire_cd -= delta
	_raise_cd -= delta
	if not engaged and health <= max_health * engage_hp_fraction:
		engaged = true
		fire_count += engage_extra_fire
		fire_interval *= engage_interval_mult
		teleport_interval *= engage_interval_mult
		bark("volva.engage")
	if not can_start_act():
		return
	var close := dist_to_player() < teleport_min_dist * 0.7
	if _tp_cd <= 0.0 or (close and _tp_cd < teleport_interval * 0.6):
		var t := pick_teleport_point()
		if t != Vector3.INF:
			_start_teleport(t)
			return
		_tp_cd = 1.0
	if _fire_cd <= 0.0 and EnemyRangedAttacks.can_add_zone(self):
		set_act(Act.FIRE)
		FX.burst(get_parent(), global_position + Vector3(0, 2.2 * model_scale, 0), 0.5, Color(FIRE, 0.7), fire_windup)
		Audio.sfx("orb_cast", "sounds/sfx/orb_cast.wav")
	elif _raise_cd <= 0.0:
		set_act(Act.RAISE)
		FX.ring(get_parent(), global_position, 3.0, Color(0.35, 1.0, 0.45, 0.9), raise_windup)
		Audio.play("sounds/sfx/curse_throw.wav")

func _run_act(delta: float) -> void:
	match act:
		Act.TELEPORT:
			act_move(Vector3.ZERO, delta)
			_windup_glow = clampf(act_time / teleport_time, 0.0, 1.0)
			if act_time >= teleport_time:
				_finish_teleport()
				set_act(Act.NONE)
		Act.FIRE:
			_face_dir(dir_to_player(), delta * 3.0)
			act_move(Vector3.ZERO, delta)
			_windup_glow = clampf(act_time / fire_windup, 0.0, 1.0)
			if act_time >= fire_windup:
				_cast_fire()
				set_act(Act.NONE)
		Act.RAISE:
			act_move(Vector3.ZERO, delta)
			_windup_glow = clampf(act_time / raise_windup, 0.0, 1.0)
			if act_time >= raise_windup:
				_raise_cd = raise_interval
				summon_around("fodder", raise_count, raise_cap)
				FX.ring(get_parent(), global_position, 3.5, Color(0.35, 1.0, 0.45, 0.9), 0.4)
				set_act(Act.NONE)
		Act.KNOCKED:
			act_move(Vector3.ZERO, delta)
			if act_time >= knock_stun:
				_tp_cd = minf(_tp_cd, 0.5)
				set_act(Act.NONE)

# --- Телепорт ---

func _start_teleport(target: Vector3) -> void:
	Perf.mark("volva_teleport_telegraph")
	set_act(Act.TELEPORT)
	_tp_cd = teleport_interval
	_tp_target = target
	FX.ring(get_parent(), global_position, 1.6, Color(VIOLET, 0.9), teleport_time)
	_tp_ring = MeshInstance3D.new()
	_tp_ring.mesh = FX.shared_mesh("ring")
	FX.fx_apply(_tp_ring, "alpha", Color(VIOLET, 0.9), 2.0)
	_tp_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tp_ring.top_level = true
	add_child(_tp_ring)
	_tp_ring.global_position = target + Vector3(0, 0.08, 0)
	_tp_ring.scale = Vector3(1.4, 0.4, 1.4)
	Audio.sfx("orb_cast", "sounds/sfx/orb_cast.wav")

func is_teleporting() -> bool:
	return act == Act.TELEPORT

func _finish_teleport() -> void:
	Perf.mark("volva_teleport")
	if _tp_ring and is_instance_valid(_tp_ring):
		_tp_ring.queue_free()
	_tp_ring = null
	if _tp_target == Vector3.INF:
		return
	FX.burst(get_parent(), global_position + Vector3(0, 1.0, 0), 1.0, Color(VIOLET, 0.6), 0.25)
	global_position = _tp_target + Vector3(0, 0.05, 0)
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	FX.burst(get_parent(), global_position + Vector3(0, 1.0, 0), 1.0, Color(VIOLET, 0.6), 0.25)
	teleports += 1
	_tp_target = Vector3.INF

## На высокой точке (выше пола зала на high_min).
func is_elevated() -> bool:
	var room := _room() as Node3D
	return room != null and global_position.y - room.global_position.y >= high_min - 0.2

# --- Огненные круги ---

func _cast_fire() -> void:
	Perf.mark("volva_fire")
	_fire_cd = fire_interval
	if player == null or not is_instance_valid(player):
		return
	var pp := player.global_position
	for i in fire_count:
		if not EnemyRangedAttacks.can_add_zone(self):
			break
		var pos := pp
		if i > 0:
			var a := TAU * float(i) / float(fire_count) + randf() * 0.6
			pos = pp + Vector3(cos(a), 0, sin(a)) * fire_spread
		var z := HazardZone.make(HazardZone.Shape.CIRCLE, pos, Vector3.FORWARD, fire_radius, fire_telegraph, fire_damage, FIRE, self)
		z.puddle_time = fire_puddle_time
		z.puddle_dps = fire_puddle_dps
		z.source_id = "miniboss_volva"
		z.place(get_parent())
	bark("volva.fire")

# --- Сбить молотом ---

func take_hit(damage: float, knockback: Vector3, source: String = "") -> void:
	if is_dead:
		return
	if act == Act.KNOCKED and damage < DEBUG_KILL_DAMAGE:
		damage *= knock_damage_mult
	super.take_hit(damage, knockback, source)
	if not is_dead and source == "hammer" and act != Act.KNOCKED:
		_knock_down(knockback)

func _knock_down(knockback: Vector3) -> void:
	Perf.mark("volva_knocked")
	knockdowns += 1
	if _tp_ring and is_instance_valid(_tp_ring):
		_tp_ring.queue_free()
	_tp_ring = null
	_tp_target = Vector3.INF
	set_act(Act.KNOCKED)
	CommandWords.cue(&"hit")  # сбита молотом — окно урона
	# С уступа — вниз: толчок наружу
	var push := Vector3(knockback.x, 0, knockback.z)
	push = push.normalized() if push.length() > 0.1 else -dir_to_player()
	knockback_velocity = push * 7.0
	velocity.y = 3.0
	if _humanoid:
		_humanoid.play(anim_stun, 0.05)
	ComicFX.pop("slam", global_position + Vector3(0, 2.0 * model_scale, 0))
	bark("volva.knocked")

func is_knocked() -> bool:
	return act == Act.KNOCKED

func _die(source: String) -> void:
	if _tp_ring and is_instance_valid(_tp_ring):
		_tp_ring.queue_free()
	super._die(source)
