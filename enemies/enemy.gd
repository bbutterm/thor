extends CharacterBody3D
class_name Enemy
## Базовый враг: грунт (ближний), метатель (дальний), босс. Тип задаётся полем kind.
## Отбрасывание через knockback_velocity, оглушение об стену, «рэгдолл» RigidBody при смерти.
## Вид врага (по приоритету):
##   1) свой узел "Visual" в сцене (например, модель Synty со своим AnimationPlayer);
##   2) персонаж Quaternius, собранный HumanoidModel по полям группы «Модель» ниже;
##   3) процедурная заглушка из примитивов (если model_outfit пустой).
## Имена анимаций — в группе «Анимации»: при смене моделей достаточно поменять их там.

signal died(enemy: Enemy)

enum Kind { GRUNT, THROWER, BOSS }
enum State { SPAWNING, CHASE, WINDUP, RECOVER, STUNNED, DEAD }

@export var kind: Kind = Kind.GRUNT

@export_group("Характеристики")
@export var max_health: float = 70.0
@export var move_speed: float = 4.2
@export var accel: float = 18.0
@export var gravity: float = 24.0
@export var turn_speed: float = 8.0
## 0 = летит от каждого удара, 1 = не сдвигается
@export_range(0.0, 1.0) var knock_resist: float = 0.0
@export var knock_decay: float = 5.0

@export_group("Атака")
@export var attack_range: float = 2.0
@export var attack_damage: float = 12.0
@export var windup_time: float = 0.6
@export var recover_time: float = 0.7
@export var attack_cooldown: float = 0.9
@export var lunge_speed: float = 7.0

@export_group("Метатель")
@export var keep_min_dist: float = 8.0
@export var keep_max_dist: float = 12.0
@export var projectile_speed: float = 10.0
@export var projectile_damage: float = 10.0

@export_group("Босс")
@export var boss_slam_radius: float = 6.5
@export var boss_slam_damage: float = 25.0
@export var boss_slam_windup: float = 1.0
## Шанс (за кадр) начать удар по площади издалека (> 5 м) — давление на игрока, но и задержка подхода
@export var boss_far_slam_chance: float = 0.02

@export_group("Об стену")
@export var wall_splat_speed: float = 8.5
@export var wall_splat_damage: float = 12.0
@export var wall_splat_stun: float = 1.0

@export_group("Вид")
## Сколько трупов-«рэгдоллов» может лежать одновременно (каждый — физтело с анимацией)
@export var max_debris: int = 10
## Сколько секунд труп лежит, прежде чем исчезнуть
@export var debris_lifetime: float = 4.0
@export var body_color: Color = Color(0.32, 0.45, 0.33)
@export var model_scale: float = 1.0

@export_group("Модель")
@export var model_body: String = "base/Superhero_Male_FullBody.gltf"
@export var model_outfit: String = ""
@export var model_hair: String = ""
@export var skin_tint: Color = Color.WHITE
@export var cloth_tint: Color = Color.WHITE
@export var eye_glow: Color = Color(0, 0, 0, 0)
## Оружие в правой руке: "" / "club" / "staff" / "q_axe" / "q_sword"... (см. WeaponMeshes)
@export var hand_weapon: String = ""
## Массовка: случайный комплект одежды/волос (цвета одежды умножаются на cloth_tint)
@export var randomize_look: bool = false
## Если не пусто — оружие выбирается случайно из списка
@export var weapon_pool: PackedStringArray = []
@export_range(0.0, 1.0) var shield_chance: float = 0.0

@export_group("Анимации")
@export var anim_spawn: String = "LayToIdle"
@export var anim_idle: String = "Idle_Loop"
@export var anim_move: String = "Walk_Loop"
## Скорость (м/с), при которой анимация ходьбы играет с ×1
@export var anim_move_ref_speed: float = 1.6
@export var anim_attack: String = "Punch_Cross"
## В какой доле анимации атаки происходит удар (для синхронизации с телеграфом)
@export_range(0.05, 1.0) var anim_attack_hit_at: float = 0.5
@export var anim_slam: String = ""
@export var anim_hit: String = "Hit_Chest"
@export var anim_stun: String = "Hit_Knockback"
@export var anim_death: String = "Death01"

var health: float
var is_dead: bool = false
var state: State = State.SPAWNING
var knockback_velocity: Vector3 = Vector3.ZERO
var player: Player

var _state_time: float = 0.0
var _cooldown: float = 0.0
var _stun_left: float = 0.0
var _last_splat_time: float = -10.0
var _last_knock: Vector3 = Vector3.ZERO
var _attack_count: int = 0
var _doing_slam: bool = false
var _strafe_sign: float = 1.0
var _visual: Node3D
## Меши врага — для общего оверлея вспышки/свечения (см. shaders/hit_flash.gdshader)
var _flash_meshes: Array[GeometryInstance3D] = []
var _overlay_on: bool = false
var _hurt_flash: float = 0.0
var _windup_glow: float = 0.0
var _telegraph: Node3D
var _walk_t: float = 0.0
# Обход препятствий: если долго не можем сдвинуться — идём вбок
var _stuck_check_t: float = 0.0
var _stuck_check_pos: Vector3 = Vector3.ZERO
var _detour_left: float = 0.0
var _detour_dir: Vector3 = Vector3.ZERO
var _humanoid: HumanoidModel
var _hit_anim_left: float = 0.0
var _spawn_time: float = 0.5

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 1) | (1 << 2) | (1 << 3)
	health = max_health
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0
	_visual = get_node_or_null("Visual")
	if _visual == null and model_outfit != "":
		_humanoid = HumanoidModel.new()
		_humanoid.name = "Visual"
		_humanoid.body = model_body
		_humanoid.outfit = model_outfit
		_humanoid.hair = model_hair
		if randomize_look:
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			var look := HumanoidModel.random_look(rng, rng.randf() < 0.3)
			_humanoid.body = look.body
			_humanoid.outfit = ""
			_humanoid.hair = ""
			_humanoid.parts = look.parts
			var tints: Array[Color] = []
			for c in look.part_tints:
				tints.append((c as Color) * cloth_tint)
			_humanoid.part_tints = tints
			if not weapon_pool.is_empty():
				hand_weapon = weapon_pool[rng.randi() % weapon_pool.size()]
		_humanoid.skin_tint = skin_tint
		_humanoid.cloth_tint = cloth_tint
		_humanoid.eye_glow = eye_glow
		add_child(_humanoid)
		_humanoid.scale = Vector3.ONE * model_scale
		_visual = _humanoid
		if hand_weapon != "":
			_attach_weapon(hand_weapon)
	elif _visual is HumanoidModel:
		_humanoid = _visual as HumanoidModel
	if _visual == null:
		_visual = _build_procedural_model()
	_collect_meshes(_visual)
	FX.ring(get_parent(), global_position, 1.5 * model_scale, Color(0.7, 0.2, 1.0, 0.8), 0.45)
	if _humanoid:
		# Появление: драугр поднимается с земли
		if _humanoid.play(anim_spawn, 0.0, 1.6):
			var a := _humanoid.anim.get_animation(_humanoid.resolve(anim_spawn))
			_spawn_time = a.length / 1.6
		else:
			_humanoid.play(anim_idle, 0.0)
	else:
		# Процедурная заглушка: вырастаем из-под земли
		_visual.scale = Vector3(0.1, 0.1, 0.1)
		var tw := create_tween()
		tw.tween_property(_visual, "scale", Vector3.ONE * model_scale, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Player
	_state_time += delta
	_cooldown = maxf(0.0, _cooldown - delta)

	var move_dir := Vector3.ZERO
	match state:
		State.SPAWNING:
			if _state_time >= _spawn_time:
				_set_state(State.CHASE)
		State.CHASE:
			move_dir = _think_chase()
		State.WINDUP:
			_face_player(delta * 0.5)
			var wt := boss_slam_windup if _doing_slam else windup_time
			_windup_glow = clampf(_state_time / wt, 0.0, 1.0)
			if _state_time >= wt:
				_execute_attack()
		State.RECOVER:
			if _state_time >= recover_time:
				_set_state(State.CHASE)
		State.STUNNED:
			_stun_left -= delta
			if _visual and _humanoid == null:
				_visual.rotation.z = sin(_state_time * 30.0) * 0.12
			if _stun_left <= 0.0:
				if _visual:
					_visual.rotation.z = 0.0
				_set_state(State.CHASE)

	_apply_movement(move_dir, delta)
	_update_visual_feedback(delta)
	_update_animation(delta)

func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0
	if s != State.WINDUP:
		_windup_glow = 0.0
	if s == State.STUNNED and _humanoid:
		_humanoid.play(anim_stun, 0.05)

## Анимации персонажа по состоянию. Атака запускается в _begin_windup, здесь — ходьба/стойка.
func _update_animation(delta: float) -> void:
	if _humanoid == null:
		return
	_hit_anim_left = maxf(0.0, _hit_anim_left - delta)
	match state:
		State.CHASE:
			if _hit_anim_left > 0.0:
				return
			var hs := Vector2(velocity.x, velocity.z).length()
			if hs > 0.4:
				_humanoid.play(anim_move, 0.2, clampf(hs / anim_move_ref_speed, 0.5, 2.5))
			else:
				_humanoid.play(anim_idle, 0.25)
		State.RECOVER:
			# Даём доиграть атаке, к концу восстановления — в стойку
			if _state_time > recover_time * 0.7:
				_humanoid.play(anim_idle, 0.25)

# --- Мышление ---

func _think_chase() -> Vector3:
	if player == null or player.is_dead:
		return Vector3.ZERO
	var to_player := player.global_position - global_position
	to_player.y = 0
	var dist := to_player.length()
	var dir := to_player.normalized() if dist > 0.01 else Vector3.ZERO
	_face_dir(dir, get_physics_process_delta_time())
	var move := Vector3.ZERO
	match kind:
		Kind.GRUNT, Kind.BOSS:
			var reach := attack_range
			if kind == Kind.BOSS and dist > 5.0 and _cooldown <= 0.0 and randf() < boss_far_slam_chance:
				_begin_windup(true)
				return Vector3.ZERO
			if dist <= reach and _cooldown <= 0.0:
				_begin_windup(kind == Kind.BOSS and _attack_count % 3 == 2)
				return Vector3.ZERO
			move = dir
		Kind.THROWER:
			if dist < keep_min_dist:
				move = -dir
			elif dist > keep_max_dist:
				move = dir
			else:
				move = dir.cross(Vector3.UP) * _strafe_sign * 0.6
				if randf() < 0.005:
					_strafe_sign *= -1.0
			if _cooldown <= 0.0 and dist < keep_max_dist + 6.0 and _has_line_of_sight():
				_begin_windup(false)
				return Vector3.ZERO
	if _detour_left > 0.0 and move != Vector3.ZERO:
		move = (_detour_dir + move * 0.35).normalized()
	return (move + _separation()).normalized() if move != Vector3.ZERO else _separation()

func _separation() -> Vector3:
	var push := Vector3.ZERO
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self:
			continue
		var other := e as Node3D
		var d := global_position - other.global_position
		d.y = 0
		var l := d.length()
		var min_d := 1.4 * model_scale
		if l < min_d and l > 0.01:
			push += d.normalized() * (min_d - l)
	return push

func _has_line_of_sight() -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.2, 0), player.global_position + Vector3(0, 1.0, 0), 1)
	return space.intersect_ray(q).is_empty()

func _face_dir(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var target_yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))

func _face_player(delta: float) -> void:
	if player:
		var d := player.global_position - global_position
		d.y = 0
		_face_dir(d.normalized(), delta)

# --- Атаки ---

func _begin_windup(slam: bool) -> void:
	Perf.mark("enemy_windup")
	_doing_slam = slam
	_set_state(State.WINDUP)
	if kind != Kind.THROWER and (slam or randf() < 0.5):
		Audio.play("sounds/sfx/enemy_growl.wav")
	if slam:
		_show_slam_telegraph()
	if _humanoid:
		var a_name := anim_slam if slam and anim_slam != "" else anim_attack
		var full := _humanoid.resolve(a_name)
		if full != "":
			var wt := boss_slam_windup if slam else windup_time
			var hit_t := _humanoid.anim.get_animation(full).length * anim_attack_hit_at
			_humanoid.anim.play(full, 0.08, clampf(hit_t / maxf(wt, 0.05), 0.3, 4.0))
	elif _visual:
		var tw := create_tween()
		tw.tween_property(_visual, "scale", Vector3(1.12, 0.88, 1.12) * model_scale, 0.15)
		tw.tween_property(_visual, "scale", Vector3(0.95, 1.08, 0.95) * model_scale, maxf(0.05, (boss_slam_windup if slam else windup_time) - 0.15))

func _execute_attack() -> void:
	_attack_count += 1
	_cooldown = attack_cooldown
	if _visual and _humanoid == null:
		var tw := create_tween()
		tw.tween_property(_visual, "scale", Vector3.ONE * model_scale, 0.12).set_trans(Tween.TRANS_BACK)
	match kind:
		Kind.THROWER:
			_throw_projectile()
		_:
			if _doing_slam:
				_do_boss_slam()
			else:
				_do_melee()
	_doing_slam = false
	_set_state(State.RECOVER)

func _do_melee() -> void:
	var fwd := global_transform.basis.z
	knockback_velocity += fwd * lunge_speed
	if player == null or player.is_dead:
		return
	var to_p := player.global_position - global_position
	to_p.y = 0
	var reach := attack_range * 1.35 + 0.3
	if to_p.length() <= reach and fwd.dot(to_p.normalized()) > 0.25:
		ComicFX.on_player_struck(self, player)
		player.take_damage(attack_damage, to_p.normalized() * 6.0 + Vector3.UP * 2.5)
	FX.burst(get_parent(), global_position + fwd * attack_range * 0.8 + Vector3(0, 1, 0), 0.5 * model_scale, Color(1, 0.3, 0.2, 0.5), 0.15)
	Audio.play("sounds/enemy_attack.ogg")

func _do_boss_slam() -> void:
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	FX.ring(get_parent(), global_position, boss_slam_radius, Color(1, 0.35, 0.2, 0.9), 0.4)
	FX.burst(get_parent(), global_position + Vector3(0, 0.5, 0), 1.5, Color(1, 0.4, 0.2, 0.4), 0.25)
	Audio.play("sounds/sfx/boss_slam.wav")
	if player and not player.is_dead:
		player.camera_fx.add_trauma(0.45)
		var d := player.global_position - global_position
		d.y = 0
		if d.length() <= boss_slam_radius and player.is_on_floor():
			ComicFX.on_player_struck(self, player)
			player.take_damage(boss_slam_damage, d.normalized() * 10.0 + Vector3.UP * 6.0)
	for c in get_tree().get_nodes_in_group("props"):
		var rb := c as RigidBody3D
		if rb and rb.global_position.distance_to(global_position) < boss_slam_radius:
			rb.apply_central_impulse((rb.global_position - global_position).normalized() * 6.0 * rb.mass + Vector3.UP * 4.0 * rb.mass)

func _show_slam_telegraph() -> void:
	Perf.mark("boss_telegraph")
	_telegraph = MeshInstance3D.new()
	(_telegraph as MeshInstance3D).mesh = FX.shared_mesh("disc")
	_telegraph.scale = Vector3(boss_slam_radius, 0.03, boss_slam_radius)
	var tele := _telegraph as MeshInstance3D
	FX.fx_apply(tele, "alpha", Color(1, 0.2, 0.1, 1.0))
	tele.transparency = 1.0
	get_parent().add_child(_telegraph)
	_telegraph.global_position = global_position + Vector3(0, 0.06, 0)
	var tw := _telegraph.create_tween()
	tw.tween_property(tele, "transparency", 0.55, boss_slam_windup)

func _throw_projectile() -> void:
	Perf.mark("enemy_projectile")
	if player == null:
		return
	var origin := global_position + Vector3(0, 1.4 * model_scale, 0) + global_transform.basis.z * 0.6
	var target := player.global_position + Vector3(0, 0.9, 0) + player.velocity * 0.35
	var proj: Node3D = preload("res://enemies/enemy_projectile.gd").new()
	get_parent().add_child(proj)
	proj.call("launch", origin, (target - origin).normalized() * projectile_speed, projectile_damage, self)
	Audio.play("sounds/sfx/curse_throw.wav")

# --- Урон ---

func take_hit(damage: float, knockback: Vector3, source: String = "") -> void:
	Perf.mark("enemy_hit")
	if is_dead:
		return
	health -= damage
	ComicFX.on_enemy_hit(self, damage, source)
	_hurt_flash = 1.0
	var big := source == "axe_finisher" or source == "slam"
	if source != "fire":
		FX.sparks(get_parent(), global_position + Vector3(0, 1.1 * model_scale, 0), Color(1, 0.85, 0.4) if source.begins_with("axe") else Color(0.6, 0.85, 1.0), 18 if big else 10, 7.0 if big else 5.0)
	FX.damage_number(get_parent(), global_position + Vector3(0, 1.8 * model_scale, 0), damage,
		Color(1, 0.55, 0.2) if big else (Color(0.6, 0.85, 1.0) if source in ["hammer", "lightning"] else Color(1, 0.92, 0.4)), big)
	var k := knockback * (1.0 - knock_resist)
	knockback_velocity += k
	# Реакция на удар (не сбиваем анимацию атаки и оглушения)
	if _humanoid and health > 0.0 and state in [State.CHASE, State.RECOVER] and k.length() > 1.0:
		_humanoid.play(anim_hit, 0.03, 1.3)
		_hit_anim_left = 0.25
	if k.length() > 0.1:
		_last_knock = k
	if k.y > 2.5 and is_on_floor():
		velocity.y = k.y
		knockback_velocity.y = 0
	# Сильные удары сбивают замах (кроме босса)
	if kind != Kind.BOSS and state == State.WINDUP and (big or source == "hammer"):
		if _telegraph and is_instance_valid(_telegraph):
			_telegraph.queue_free()
		_set_state(State.RECOVER)
	if health <= 0.0:
		_die(source)

## Оглушить на time секунд (босса и мини-босса — нет). Для трейтов и эффектов.
func stun(time: float) -> void:
	if is_dead or kind == Kind.BOSS:
		return
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_stun_left = maxf(_stun_left, time)
	_set_state(State.STUNNED)

func _apply_movement(move_dir: Vector3, delta: float) -> void:
	var can_move := state == State.CHASE
	var target := move_dir * move_speed if can_move else Vector3.ZERO
	var horiz := Vector3(velocity.x, 0, velocity.z)
	# Базовая скорость стремится к цели, отбрасывание добавляется сверху
	var base := horiz - Vector3(knockback_velocity.x, 0, knockback_velocity.z)
	base = base.move_toward(target, accel * delta)
	knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, clampf(knock_decay * delta, 0.0, 1.0))
	if not is_on_floor():
		knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, clampf(knock_decay * 0.3 * delta, 0.0, 1.0))
	var new_h := base + Vector3(knockback_velocity.x, 0, knockback_velocity.z)
	velocity.x = new_h.x
	velocity.z = new_h.z
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0:
		velocity.y = -0.5
	var pre := Vector3(velocity.x, 0, velocity.z)
	move_and_slide()
	_push_props()
	_check_wall_splat(pre)
	_update_stuck(move_dir, delta)
	if global_position.y < -30.0:
		_die("fall")

func _push_props() -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var rb := col.get_collider() as RigidBody3D
		if rb:
			var dir := -col.get_normal()
			dir.y = 0.1
			rb.apply_central_impulse(dir.normalized() * 0.9 * model_scale * model_scale)

func _update_stuck(move_dir: Vector3, delta: float) -> void:
	if _detour_left > 0.0:
		_detour_left -= delta
	if state != State.CHASE or move_dir == Vector3.ZERO:
		_stuck_check_t = 0.0
		_stuck_check_pos = global_position
		return
	_stuck_check_t += delta
	if _stuck_check_t >= 0.6:
		var moved := Vector2(global_position.x - _stuck_check_pos.x, global_position.z - _stuck_check_pos.z).length()
		if moved < move_speed * 0.6 * 0.25 and _detour_left <= 0.0:
			_detour_dir = move_dir.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
			_detour_left = 0.9
		_stuck_check_t = 0.0
		_stuck_check_pos = global_position

func _check_wall_splat(pre_horiz: Vector3) -> void:
	var kspeed := Vector2(knockback_velocity.x, knockback_velocity.z).length()
	if kspeed < wall_splat_speed:
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) > 0.5:
			continue
		var other := col.get_collider()
		if other is CharacterBody3D or other is RigidBody3D:
			continue
		if pre_horiz.normalized().dot(-n) < 0.3:
			continue
		_last_splat_time = Time.get_ticks_msec() / 1000.0
		knockback_velocity = n * 2.0
		FX.burst(get_parent(), col.get_position(), 0.8, Color(1, 1, 1, 0.6), 0.2)
		if player:
			player.camera_fx.add_trauma(0.2)
		Audio.play("sounds/sfx/wall_splat.wav")
		if kind != Kind.BOSS:
			_stun_left = wall_splat_stun
			_set_state(State.STUNNED)
		take_hit(wall_splat_damage, Vector3.ZERO, "wall")
		return

func _die(source: String) -> void:
	if is_dead:
		return
	is_dead = true
	remove_from_group("enemies")
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	var now := Time.get_ticks_msec() / 1000.0
	# Мини-босс — тоже Kind.BOSS (поведение босса), но Славу за него даёт MinibossDef
	Run.register_kill(source == "axe_finisher", now - _last_splat_time < 0.6, kind == Kind.BOSS and not has_meta("miniboss"))
	ComicFX.on_enemy_killed(self, source)
	if player and is_instance_valid(player) and not player.is_dead:
		player.heal(player.heal_per_kill)
	Audio.play("sounds/enemy_destroy.ogg")
	_spawn_debris()
	died.emit(self)
	queue_free()

func _spawn_debris() -> void:
	Perf.mark("enemy_death")
	if _visual == null:
		return
	# Не копим трупы: сверх лимита самый старый исчезает сразу
	var old := get_tree().get_nodes_in_group("debris").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	for k in maxi(0, old.size() - max_debris + 1):
		old[k].queue_free()
	var rb := RigidBody3D.new()
	rb.add_to_group("debris")
	rb.collision_layer = 1 << 6
	rb.collision_mask = 1 | (1 << 3) | (1 << 6)
	rb.mass = 2.0 * model_scale
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 1.6, 0.7) * model_scale
	shape.shape = box
	shape.position = Vector3(0, 0.8 * model_scale, 0)
	rb.add_child(shape)
	get_parent().add_child(rb)
	rb.global_transform = global_transform
	var vis := _visual
	vis.get_parent().remove_child(vis)
	rb.add_child(vis)
	vis.scale = Vector3.ONE * model_scale
	_set_overlay(0.0, 0.0)
	var knock := _last_knock if _last_knock.length() > 0.5 else -global_transform.basis.z * 4.0
	if _humanoid:
		# Персонаж с анимацией: тело летит от удара, но не кувыркается — играет анимация смерти
		rb.lock_rotation = true
		box.size = Vector3(0.6, 0.4, 0.6) * model_scale
		shape.position = Vector3(0, 0.2 * model_scale, 0)
		_humanoid.play(anim_death, 0.05, 1.4)
		rb.apply_central_impulse((knock * 0.9 + Vector3.UP * 3.0) * rb.mass)
	else:
		rb.apply_central_impulse((knock * 1.1 + Vector3.UP * 4.0) * rb.mass)
		rb.apply_torque_impulse(Vector3(randf_range(-3, 3), randf_range(-2, 2), randf_range(-3, 3)) * rb.mass)
	# Через 4 с «рэгдолл» сжимается и исчезает (твин привязан к телу и умрёт вместе с ним)
	var tw := rb.create_tween()
	tw.tween_interval(debris_lifetime)
	tw.tween_property(vis, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
	tw.tween_callback(rb.queue_free)

# --- Вид ---

func _update_visual_feedback(delta: float) -> void:
	_hurt_flash = maxf(0.0, _hurt_flash - delta * 8.0)
	# Процедурная «анимация» (только для заглушки): покачивание, отклонение на замахе, рывок на ударе
	if _visual and _humanoid == null and state != State.STUNNED:
		var hs := Vector2(velocity.x, velocity.z).length()
		var bob := 0.0
		if hs > 0.5 and is_on_floor():
			_walk_t += delta * hs * 2.4
			bob = absf(sin(_walk_t)) * 0.09 * model_scale
		_visual.position.y = lerpf(_visual.position.y, bob, clampf(delta * 14.0, 0.0, 1.0))
		var lean := clampf(hs * 0.035, 0.0, 0.2)
		if state == State.WINDUP:
			lean = -0.28
		elif state == State.RECOVER and _state_time < 0.18:
			lean = 0.38
		_visual.rotation.x = lerp_angle(_visual.rotation.x, lean, clampf(delta * 14.0, 0.0, 1.0))
		_visual.rotation.z = sin(_walk_t) * 0.06 if hs > 0.5 else lerpf(_visual.rotation.z, 0.0, clampf(delta * 10.0, 0.0, 1.0))
	var glow := 0.0
	if _windup_glow > 0.0:
		var pulse := 0.5 + 0.5 * sin(_state_time * 30.0)
		glow = _windup_glow * (1.0 + pulse) * (0.35 if _humanoid else 0.8)
	_set_overlay(_hurt_flash, glow)

const FLASH_MATERIAL := preload("res://shaders/hit_flash.tres")

## Вспышка и свечение — общим оверлей-материалом с per-instance параметрами.
## Оверлей включается только пока есть что показывать (лишний проход рисования не нужен).
func _set_overlay(flash: float, glow: float) -> void:
	var on := flash > 0.001 or glow > 0.001
	if not on and not _overlay_on:
		return
	for g in _flash_meshes:
		if not is_instance_valid(g):
			continue
		if on != _overlay_on:
			g.material_overlay = FLASH_MATERIAL if on else null
		if on:
			g.set_instance_shader_parameter("flash", flash)
			g.set_instance_shader_parameter("glow", glow)
	_overlay_on = on

func _collect_meshes(root: Node) -> void:
	_flash_meshes.clear()
	for mi in root.find_children("*", "GeometryInstance3D", true, false):
		if mi is MeshInstance3D:
			_flash_meshes.append(mi as GeometryInstance3D)

## Оружие в правую руку (процедурное, в текстурах Quaternius).
func _attach_weapon(kind_name: String) -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "hand_r"
	_humanoid.skeleton.add_child(att)
	var w := WeaponMeshes.build(kind_name)
	# Хват: рукоять поперёк кулака, оружие смотрит вверх-вперёд
	w.rotation_degrees = Vector3(0, 0, -90)
	w.position = Vector3(0, 0.08, 0)
	att.add_child(w)
	if shield_chance > 0.0 and randf() < shield_chance:
		var att2 := BoneAttachment3D.new()
		att2.bone_name = "hand_l"
		_humanoid.skeleton.add_child(att2)
		var sh := WeaponMeshes.build("q_shield")
		sh.rotation_degrees = Vector3(0, 0, 90)
		att2.add_child(sh)

func _build_procedural_model() -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	add_child(root)
	var skin := FX.make_material(body_color, 0.9)
	var dark := FX.make_material(body_color.darkened(0.45), 0.9)
	var metal := FX.make_material(Color(0.55, 0.55, 0.6), 0.4)
	metal.metallic = 0.6
	var eye := FX.make_material(Color(1.0, 0.85, 0.2), 0.5, 4.0)
	eye.set_meta("glow", true)
	match kind:
		Kind.THROWER:
			# Тощий шаман-драугр с капюшоном
			_add_mesh(root, _capsule(0.32, 1.3), Vector3(0, 0.75, 0), dark)
			_add_mesh(root, _sphere(0.3), Vector3(0, 1.55, 0), skin)
			_add_mesh(root, _cone(0.36, 0.55), Vector3(0, 1.85, -0.05), dark)
			_add_mesh(root, _sphere(0.06), Vector3(-0.1, 1.58, 0.25), eye)
			_add_mesh(root, _sphere(0.06), Vector3(0.1, 1.58, 0.25), eye)
			_add_mesh(root, _box(Vector3(0.08, 1.2, 0.08)), Vector3(0.42, 0.9, 0.15), FX.make_material(Color(0.35, 0.22, 0.12)))
			_add_mesh(root, _sphere(0.13), Vector3(0.42, 1.55, 0.15), FX.make_material(Color(0.6, 0.2, 1.0), 0.4, 3.0))
		_:
			# Коренастый драугр в рогатом шлеме
			_add_mesh(root, _capsule(0.42, 1.25), Vector3(0, 0.72, 0), skin)
			_add_mesh(root, _box(Vector3(0.9, 0.35, 0.6)), Vector3(0, 1.2, 0), dark)
			_add_mesh(root, _sphere(0.32), Vector3(0, 1.6, 0.03), skin)
			_add_mesh(root, _sphere(0.34), Vector3(0, 1.7, 0), metal)
			_add_mesh(root, _cone(0.08, 0.45), Vector3(-0.32, 1.9, 0), FX.make_material(Color(0.92, 0.88, 0.78)), Vector3(0, 0, 40))
			_add_mesh(root, _cone(0.08, 0.45), Vector3(0.32, 1.9, 0), FX.make_material(Color(0.92, 0.88, 0.78)), Vector3(0, 0, -40))
			_add_mesh(root, _sphere(0.065), Vector3(-0.12, 1.6, 0.28), eye)
			_add_mesh(root, _sphere(0.065), Vector3(0.12, 1.6, 0.28), eye)
			# Дубина
			_add_mesh(root, _box(Vector3(0.12, 0.9, 0.12)), Vector3(0.55, 0.9, 0.25), FX.make_material(Color(0.35, 0.22, 0.12)), Vector3(35, 0, 0))
			_add_mesh(root, _box(Vector3(0.26, 0.32, 0.26)), Vector3(0.55, 1.25, 0.5), metal, Vector3(35, 0, 0))
	return root

func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: StandardMaterial3D, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat.duplicate() if not mat.has_meta("glow") else mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m

func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	return m

func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m

func _cone(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 10
	return m
