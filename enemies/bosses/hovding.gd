extends BossEnemy
class_name HovdingBoss
## Хёвдинг с дружиной — мини-босс Мидгарда (GDD 14.1): драугр-вожак со знаменем и отрядом из 4–6 воинов.
## - Знамя-аура: пока он жив, дружина (метаданные squad_id = guard_squad или hovding_guard) в aura_radius
##   быстрее и бьёт сильнее; под ногами у них — золотое кольцо.
## - Рог: поднимает рог (телеграф horn_windup: рог над головой + звук), созывает подкрепление и ставит круг
##   под Тором (HazardZone). Раз в horn_interval.
## - Фаза 1: держится за дружиной (hold_min–hold_max м от Тора), кидает топоры (снаряд-«копьё»).
## - При engage_hp_fraction HP сам идёт в бой: быстрее, обычный ближний бой босса с ударом по площади.
## Урок: «убей вожака первым». Числа и вид перекрывает MinibossDef (enemies/minibosses/hovding.tres).

enum Act { NONE, HORN, AXE }

@export_group("Хёвдинг: знамя")
@export var aura_radius: float = 14.0
@export var aura_speed_mult: float = 1.25
@export var aura_damage_mult: float = 1.3
## id отряда дружины (SquadDef) — его участники под аурой
@export var guard_squad: String = "hovding_guard"
@export_group("Хёвдинг: рог")
@export var horn_interval: float = 11.0
## Телеграф рога: поднял рог, звук (с)
@export var horn_windup: float = 1.2
@export var horn_reinforce_count: int = 2
@export var horn_reinforce_kind: String = "grunt"
## Не зовёт, если врагов в зале уже столько
@export var horn_cap: int = 24
@export var horn_zone_radius: float = 2.6
@export var horn_zone_telegraph: float = 1.0
@export var horn_zone_damage: float = 16.0
@export_group("Хёвдинг: топор")
@export var axe_cooldown: float = 4.0
@export var axe_windup: float = 0.55
@export var axe_speed: float = 18.0
@export var axe_damage: float = 14.0
@export_group("Хёвдинг: фазы")
## Держится за дружиной на таком расстоянии от Тора, пока HP выше engage_hp_fraction
@export var hold_min: float = 7.0
@export var hold_max: float = 11.0
@export_range(0.0, 1.0) var engage_hp_fraction: float = 0.5
@export var engage_speed_mult: float = 1.3

var engaged: bool = false
var horns: int = 0
var _horn_cd: float = 5.0
var _axe_cd: float = 2.0
var _aura_t: float = 0.0
var _horn_mesh: MeshInstance3D
## Кто сейчас под аурой (instance id → Enemy)
var _aura_targets: Dictionary = {}

const GOLD := Color(1.0, 0.78, 0.25)

func _ready() -> void:
	super._ready()
	set_meta("death_source_id", "miniboss_hovding")
	_build_banner()

# --- Вид: знамя на спине и рог (общие меши и материалы эффектов) ---

func _build_banner() -> void:
	var root := Node3D.new()
	root.name = "Banner"
	add_child(root)
	root.position = Vector3(0, 0, -0.35 * model_scale)
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	pole.mesh = FX.shared_mesh("box")
	FX.fx_apply(pole, "glow", Color(0.35, 0.22, 0.12), 0.6)
	pole.scale = Vector3(0.07, 3.2, 0.07) * model_scale
	pole.position = Vector3(0, 1.6 * model_scale, 0)
	root.add_child(pole)
	var flag := MeshInstance3D.new()
	flag.name = "Flag"
	flag.mesh = FX.shared_mesh("box")
	FX.fx_apply(flag, "glow", Color(0.75, 0.12, 0.1), 1.3)
	flag.scale = Vector3(0.9, 0.7, 0.03) * model_scale
	flag.position = Vector3(0.48 * model_scale, 2.75 * model_scale, 0)
	root.add_child(flag)
	var sigil := MeshInstance3D.new()
	sigil.name = "Sigil"
	sigil.mesh = FX.shared_mesh("ring")
	FX.fx_apply(sigil, "glow", GOLD, 2.0)
	sigil.scale = Vector3(0.22, 0.3, 0.22) * model_scale
	sigil.rotation_degrees = Vector3(90, 0, 0)
	sigil.position = Vector3(0.48 * model_scale, 2.75 * model_scale, 0.03)
	root.add_child(sigil)
	for mi in [pole, flag, sigil]:
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_horn_mesh = MeshInstance3D.new()
	_horn_mesh.name = "Horn"
	_horn_mesh.mesh = FX.shared_mesh("wedge")
	FX.fx_apply(_horn_mesh, "alpha_nocull", Color(0.95, 0.88, 0.7, 1.0), 1.4)
	_horn_mesh.scale = Vector3(0.18, 1.0, 0.6) * model_scale
	_horn_mesh.rotation_degrees = Vector3(-60, 0, 0)
	_horn_mesh.position = Vector3(0.25 * model_scale, 2.1 * model_scale, 0.2 * model_scale)
	_horn_mesh.visible = false
	add_child(_horn_mesh)

# --- Мышление ---

## Фаза 1: держится за дружиной, бьёт только того, кто подошёл вплотную. Фаза 2 — обычный ИИ босса.
func _think_chase() -> Vector3:
	if engaged or player == null or player.is_dead:
		return super._think_chase()
	var dist := dist_to_player()
	if dist < attack_range + 0.8:
		return super._think_chase()
	var dir := dir_to_player()
	_face_dir(dir, get_physics_process_delta_time())
	var move := Vector3.ZERO
	if dist < hold_min and _has_floor_ahead(-dir):
		move = -dir
	elif dist > hold_max:
		move = dir
	return (move + _separation()).normalized() if move != Vector3.ZERO else _separation()

func _boss_think(delta: float) -> void:
	_horn_cd -= delta
	_axe_cd -= delta
	_aura_t -= delta
	if _aura_t <= 0.0:
		_aura_t = 0.3
		_update_aura()
	if not engaged and health <= max_health * engage_hp_fraction:
		_engage()
	if not can_start_act():
		return
	if _horn_cd <= 0.0:
		_start_horn()
	elif not engaged and _axe_cd <= 0.0 and dist_to_player() > 4.5 and _has_line_of_sight() \
			and EnemyRangedAttacks.can_fire(self):
		set_act(Act.AXE)
		_windup_glow = 0.0

func _run_act(delta: float) -> void:
	match act:
		Act.HORN:
			_face_dir(dir_to_player(), delta * 2.0)
			act_move(Vector3.ZERO, delta)
			_windup_glow = clampf(act_time / horn_windup, 0.0, 1.0)
			if act_time >= horn_windup:
				_blow_horn()
				set_act(Act.NONE)
		Act.AXE:
			_face_dir(dir_to_player(), delta * 4.0)
			act_move(Vector3.ZERO, delta)
			_windup_glow = clampf(act_time / axe_windup, 0.0, 1.0)
			if act_time >= axe_windup:
				_throw_axe()
				set_act(Act.NONE)

## Вторая фаза: сам идёт в бой.
func _engage() -> void:
	engaged = true
	Perf.mark("hovding_engage")
	move_speed *= engage_speed_mult
	horn_interval *= 1.5
	bark("hovding.engage")
	ComicFX.pop("slam", global_position + Vector3(0, 2.0 * model_scale, 0), true)
	FX.ring(get_parent(), global_position, 3.0, Color(GOLD, 0.9), 0.5)

# --- Рог ---

func _start_horn() -> void:
	Perf.mark("hovding_horn_telegraph")
	set_act(Act.HORN)
	_horn_cd = horn_interval
	if _horn_mesh:
		_horn_mesh.visible = true
	Audio.sfx("horn_call", "sounds/sfx/horn_call.wav")
	FX.ring(get_parent(), global_position, 2.5, Color(GOLD, 0.9), horn_windup)
	bark("hovding.horn")

func is_horn_raised() -> bool:
	return act == Act.HORN

func _blow_horn() -> void:
	Perf.mark("hovding_horn")
	horns += 1
	if _horn_mesh:
		_horn_mesh.visible = false
	FX.shockwave(get_parent(), global_position, 4.0, GOLD)
	var room := _room()
	if room and get_tree().get_nodes_in_group("enemies").size() < horn_cap:
		var made := 0
		for i in horn_reinforce_count * 3:
			if made >= horn_reinforce_count:
				break
			var a := randf() * TAU
			var cand := global_position + Vector3(cos(a), 0, sin(a)) * randf_range(2.5, 4.5)
			if not _clear_path(global_position + Vector3(0, 1.0, 0), cand + Vector3(0, 1.0, 0)):
				continue
			var ground := Loot.floor_point(self, cand)
			if ground == cand:
				continue
			var e := room.call("spawn_extra", horn_reinforce_kind, ground) as Enemy
			if e:
				e.set_meta("hovding_guard", true)
				made += 1
	if player and is_instance_valid(player) and not player.is_dead and EnemyRangedAttacks.can_add_zone(self):
		var z := HazardZone.make(HazardZone.Shape.CIRCLE, player.global_position, Vector3.FORWARD,
			horn_zone_radius, horn_zone_telegraph, horn_zone_damage, GOLD, self)
		z.source_id = "miniboss_hovding"
		z.place(get_parent())

# --- Топор ---

func _throw_axe() -> void:
	Perf.mark("hovding_axe")
	_axe_cd = axe_cooldown
	if player == null or not is_instance_valid(player):
		return
	var origin := global_position + Vector3(0, 1.7 * model_scale, 0) + global_transform.basis.z * 0.8
	var target := player.global_position + Vector3(0, 0.9, 0) + player.velocity * 0.25
	var proj := EnemyProjectile.new()
	proj.kind = EnemyProjectile.Kind.SPEAR
	proj.radius = 0.3
	proj.color = Color(0.8, 0.85, 0.9)
	get_parent().add_child(proj)
	proj.launch(origin, (target - origin).normalized() * axe_speed, axe_damage, self)
	Audio.play("sounds/sfx/axe_swing_2.wav")

# --- Знамя-аура ---

func is_guard(e: Enemy) -> bool:
	return e.has_meta("hovding_guard") or str(e.get_meta("squad_id", "")) == guard_squad

func _update_aura() -> void:
	var keep := {}
	for n in _enemies_now():
		var e := n as Enemy
		if e == null or e == self or not is_instance_valid(e) or e.is_dead or not is_guard(e):
			continue
		if e.global_position.distance_to(global_position) > aura_radius:
			continue
		keep[e.get_instance_id()] = e
		if not _aura_targets.has(e.get_instance_id()):
			_aura_on(e)
	for id in _aura_targets.keys():
		if not keep.has(id):
			_aura_off(_aura_targets[id])
	_aura_targets = keep

func _aura_on(e: Enemy) -> void:
	e.set_meta("_aura_speed", e.move_speed)
	e.set_meta("_aura_damage", e.attack_damage)
	e.move_speed *= aura_speed_mult
	e.attack_damage *= aura_damage_mult
	e.set_meta("hovding_aura", true)
	var ring := MeshInstance3D.new()
	ring.name = "AuraRing"
	ring.mesh = FX.shared_mesh("ring")
	FX.fx_apply(ring, "alpha", Color(GOLD, 0.75), 1.6)
	ring.scale = Vector3(0.8, 0.3, 0.8) * e.model_scale
	ring.position.y = 0.1
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.add_child(ring)

func _aura_off(e: Variant) -> void:
	if not is_instance_valid(e):
		return
	var en := e as Enemy
	if en.has_meta("_aura_speed"):
		en.move_speed = float(en.get_meta("_aura_speed"))
		en.attack_damage = float(en.get_meta("_aura_damage"))
		en.remove_meta("_aura_speed")
		en.remove_meta("_aura_damage")
	if en.has_meta("hovding_aura"):
		en.remove_meta("hovding_aura")
	var ring := en.get_node_or_null("AuraRing")
	if ring:
		ring.queue_free()

## Под аурой ли враг (для тестов и HUD).
static func has_aura(e: Enemy) -> bool:
	return is_instance_valid(e) and e.has_meta("hovding_aura")

func _die(source: String) -> void:
	if is_dead:
		return
	for id in _aura_targets.keys():
		_aura_off(_aura_targets[id])
	_aura_targets.clear()
	if _horn_mesh:
		_horn_mesh.visible = false
	super._die(source)
