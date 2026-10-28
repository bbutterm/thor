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
## Удар врага дошёл до Тора (amount — сколько HP снято на самом деле). Для модификаторов элиты.
signal struck_player(amount: float)

const SpawnEntry = preload("res://enemies/spawn_entry.gd")

## Новые виды — только в конец (номера сохранены в сценах).
## FODDER — драугр-корм, BLOATED — Раздутый, SHIELD — Щитоносец, SHAMAN — Шаман, MERC — Наёмник Локи (GDD 12.1)
enum Kind { GRUNT, THROWER, BOSS, FODDER, BLOATED, SHIELD, SHAMAN, MERC }
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

@export_group("Обнаружение")
## Расстояние, на котором враг замечает обычного Тора (только по горизонтали).
@export var notice_radius: float = 20.0
## Если Тор далеко, враг всё равно включается в бой спустя это время: последний враг не запирает зал.
@export var notice_fallback_time: float = 3.0

@export_group("Атака")
@export var attack_range: float = 2.0
@export var attack_damage: float = 12.0
@export var windup_time: float = 0.6
## До какой доли замаха запоздавший звук ещё оставляет время среагировать.
@export_range(0.05, 1.0, 0.05) var warning_deadline_fraction: float = 0.5
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

@export_group("Раздутый")
## С какой дистанции до Тора поджигает фитиль (радиус и время телеграфа — boss_slam_radius / boss_slam_windup)
@export var bloat_trigger_range: float = 2.4
## Во сколько раз толще обычного драугра
@export var bloat_fatness: float = 1.55
## На сколько раздувается к взрыву
@export var bloat_swell: float = 0.3

@export_group("Щитоносец")
## Щит закрывает удары, пришедшие спереди: косинус половины угла (0.3 ≈ ±72°)
@export var shield_front_dot: float = 0.3
## Удар щитом отталкивает Тора (скорость, м/с) — теснит к краю
@export var shove_force: float = 13.0
@export var shove_up: float = 2.5
## Щит на корпусе (в системе модели): смещение, поворот, масштаб
@export var shield_offset: Vector3 = Vector3(0.1, 0.5, 0.45)
@export var shield_rotation: Vector3 = Vector3(0, 0, 0)
@export var shield_scale: float = 1.45

@export_group("Шаман")
## Раз в столько секунд — обряд (телеграф = windup_time): лечит своих и поднимает корм
@export var ritual_interval: float = 6.0
@export var ritual_heal_radius: float = 12.0
## Лечение за обряд, доля максимума HP каждого врага рядом
@export var ritual_heal_fraction: float = 0.35
@export var ritual_raise_count: int = 2
## Не поднимает корм, если в зале и так столько живых врагов
@export var ritual_raise_cap: int = 30
## Ближе этого к Тору — отходит (но не прыгает с края)
@export var shaman_flee_dist: float = 5.0

@export_group("Наёмник")
## Лазерная точка ведёт Тора windup_time секунд (0.8 по GDD), потом очередь по последней точке
@export var merc_aim_track: float = 7.0
@export var merc_burst_count: int = 6
@export var merc_burst_interval: float = 0.1
## Урон пули — доля attack_damage (15 по GDD); Тор неуязвим 0.25 с после попадания, так что за очередь доходит 2–3 пули
@export var merc_bullet_mult: float = 0.5
@export var merc_spread_deg: float = 2.0
@export var merc_range: float = 40.0

@export_group("Об стену")
@export var wall_splat_speed: float = 8.5
@export var wall_splat_damage: float = 12.0
@export var wall_splat_stun: float = 1.0

## Падение с высоты (GDD 8): сброшенный (после удара/отбрасывания) с > fall_kill_height м — корм умирает, остальным fall_damage
@export var fall_kill_height: float = 6.0
@export var fall_damage: float = 44.0
## Падение считается «сброшенным», если враг получил удар не раньше стольких секунд до отрыва от земли
@export var fall_hit_window: float = 1.5

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

@export_group("Дальняя массовка")
## Корм дальше этого расстояния обновляет направление и позу реже; физика и таймеры идут каждый кадр.
@export var fodder_lod_distance: float = 20.0
@export_range(1, 8, 1) var fodder_lod_frames: int = 3

var health: float
## Описание по GDD 12 (EnemyDef), если враг появился в зале; Слава за убийство (-1 — по умолчанию забега)
var enemy_def: EnemyDef
var glory_value: int = -1
var is_dead: bool = false
var state: State = State.SPAWNING
var knockback_velocity: Vector3 = Vector3.ZERO
## Создаётся только для маркера с активным входом.
var _spawn_entry: SpawnEntry
var player: Player
## Каждый враг запоминает обнаруженного игрока до смерти или смены игрока.
var _notice_player_id: int = 0
var _notice_pending: bool = false
var _noticed_player: bool = false
var _notice_wait: float = 0.0

var _state_time: float = 0.0
var _cooldown: float = 0.0
var _stun_left: float = 0.0
var _last_splat_time: float = -10.0
var _last_hit_time: float = -10.0
## Следующий удар пробивает щит и броню элиты (Мьёльнир: Заряд в полную силу, Праща — weapons/mjolnir_projectile.gd)
var armor_pierce_hit: bool = false
var _airborne: bool = false
var _fall_peak_y: float = 0.0
var _fall_forced: bool = false
var _last_knock: Vector3 = Vector3.ZERO
var _attack_count: int = 0
## Идентификатор замаха: прерванная атака не передаёт своё предупреждение следующей.
var _windup_serial: int = 0
var _doing_slam: bool = false
var _strafe_sign: float = 1.0
var _visual: Node3D
## Меши врага — для общего оверлея вспышки/свечения (см. shaders/hit_flash.gdshader)
var _flash_meshes: Array[GeometryInstance3D] = []
## GL Compatibility: one material per enemy, shared by all of its meshes.
## Allocated at spawn and reused through hits, windups and status changes.
var _flash_material_gl: ShaderMaterial
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
## Особые враги (GDD 8): замах сбивают только сильные удары, Мьёльнир и удар-приземление
var _tough: bool = false
var _ritual_left: float = 3.0
var _laser: MeshInstance3D
var _laser_dot: MeshInstance3D
var _aim_point: Vector3 = Vector3.ZERO
var _burst_left: int = 0
var _burst_t: float = 0.0
var _burst_dir: Vector3 = Vector3.FORWARD
## Урон не меньше этого — отладочное «убить» (тесты): проходит сквозь щит и броню
const DEBUG_KILL_DAMAGE := 9999.0
## Элита (GDD 12.4): обработчики модификаторов (EliteHandler, enemies/elite/) и цвет постоянного свечения
var elite_handlers: Array[Node] = []
var elite_glow: Color = Color(0, 0, 0, 0)
## Подсветка состояния стихии (ElementStatus ставит каждый кадр; сила — в альфе, уже с пульсом)
var status_glow: Color = Color(0, 0, 0, 0)
var _fodder_lod_move := Vector3.ZERO
var _fodder_lod_move_valid := false
var _fodder_anim_lod := false
var _fodder_anim_delta := 0.0
var _fodder_anim_previous_mode: int = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE

func _ready() -> void:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		_flash_material_gl = FLASH_MATERIAL_GL.duplicate() as ShaderMaterial
	add_to_group("enemies")
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 1) | (1 << 2) | (1 << 3)
	health = max_health
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0
	_visual = get_node_or_null("Visual")
	if _visual == null and (model_outfit != "" or kind == Kind.FODDER):
		_humanoid = HumanoidModel.new()
		_humanoid.name = "Visual"
		# У корма уже одетый персонаж в одном заранее собранном меше/материале.
		_humanoid.body = "base/Fodder_Midgard.glb" if kind == Kind.FODDER else model_body
		_humanoid.outfit = "" if kind == Kind.FODDER else model_outfit
		_humanoid.hair = "" if kind == Kind.FODDER else model_hair
		if randomize_look and kind != Kind.FODDER:
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
		_humanoid.skin_tint = Color.WHITE if kind == Kind.FODDER else skin_tint
		_humanoid.cloth_tint = cloth_tint
		_humanoid.eye_glow = Color(0, 0, 0, 0) if kind == Kind.FODDER else eye_glow
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
	if kind == Kind.FODDER:
		for mesh in _flash_meshes:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	_setup_special()

## Запуск входа из метаданных маркера. Непроверенный путь возвращает false.
func begin_spawn_entry(mode: String, target: Vector3, tuning: Dictionary = {}) -> bool:
	if _spawn_entry == null:
		_spawn_entry = SpawnEntry.new()
	var ok := _spawn_entry.begin(self, mode, target, move_speed, gravity, tuning)
	if ok and _humanoid:
		_humanoid.play(anim_move, 0.1)
	return ok

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
			if _spawn_entry != null and _spawn_entry.active:
				move_dir = _spawn_entry.desired_velocity(self, accel) / maxf(move_speed, 0.01)
			elif _state_time >= _spawn_time:
				_set_state(State.CHASE)
		State.CHASE:
			if _notice_tick(delta):
				move_dir = _think_chase_lod(delta)
			else:
				_fodder_lod_move_valid = false
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
	if _spawn_entry != null:
		_spawn_entry.after_step(self, delta)
	_update_special(delta)
	_update_visual_feedback(delta)
	_update_animation(delta)
	_update_fodder_animation_lod(delta)

func _set_state(s: State) -> void:
	if s != State.SPAWNING and _spawn_entry != null:
		_spawn_entry.cancel()
	state = s
	_state_time = 0.0
	if s != State.CHASE:
		_fodder_lod_move_valid = false
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

## Только ближний корм: дальние стрелки и боссы по-прежнему думают каждый кадр.
## Если дальность атаки переопределили, её область тоже остаётся на полной частоте.
func _fodder_lod_active() -> bool:
	if kind != Kind.FODDER or state != State.CHASE or not is_instance_valid(player) or player.is_dead:
		return false
	var d := player.global_position - global_position
	var distance := maxf(maxf(0.0, fodder_lod_distance), attack_range + 1.0)
	return d.x * d.x + d.z * d.z > distance * distance and fodder_lod_frames > 1

## Задерживаем только пересчёт направления и раздвигания толпы. Движение, гравитация,
## обнаружение, таймеры и все фазы удара продолжают обновляться каждый физический кадр.
func _think_chase_lod(delta: float) -> Vector3:
	if not _fodder_lod_active():
		_fodder_lod_move_valid = false
		return _think_chase()
	var interval := maxi(1, fodder_lod_frames)
	if not _fodder_lod_move_valid or Engine.get_physics_frames() % interval == get_instance_id() % interval:
		_fodder_lod_move = _think_chase()
		_fodder_lod_move_valid = true
	else:
		_face_player(delta)
	return _fodder_lod_move

## У дальнего корма обновляем именно позу анимации, а не просто повторный вызов play().
func _update_fodder_animation_lod(delta: float) -> void:
	if not _fodder_lod_active() or _humanoid == null or _humanoid.anim == null:
		_restore_fodder_animation()
		return
	var ap := _humanoid.anim
	if not _fodder_anim_lod:
		_fodder_anim_previous_mode = ap.callback_mode_process
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_fodder_anim_delta = 0.0
		_fodder_anim_lod = true
	_fodder_anim_delta += delta
	var interval := maxi(1, fodder_lod_frames)
	if Engine.get_physics_frames() % interval == (get_instance_id() + 1) % interval:
		ap.advance(_fodder_anim_delta)
		_fodder_anim_delta = 0.0

func _restore_fodder_animation() -> void:
	if not _fodder_anim_lod:
		return
	if _humanoid and is_instance_valid(_humanoid) and _humanoid.anim:
		if _fodder_anim_delta > 0.0:
			_humanoid.anim.advance(_fodder_anim_delta)
		_humanoid.anim.callback_mode_process = _fodder_anim_previous_mode
	_fodder_anim_delta = 0.0
	_fodder_anim_lod = false

## Новая цель не наследует знание прошлой. Без живого игрока время поиска не идёт.
func _sync_notice_player() -> bool:
	var valid_player: Player = null
	if is_instance_valid(player) and not player.is_dead:
		valid_player = player
	var player_id: int = valid_player.get_instance_id() if valid_player else 0
	if player_id != _notice_player_id:
		_notice_player_id = player_id
		_notice_wait = 0.0
		_noticed_player = _notice_pending and player_id != 0
		if player_id != 0:
			_notice_pending = false
	return player_id != 0

## Удар/толчок будит врага сразу; сигнал до назначения player не теряется.
func alert_to_player() -> void:
	if _sync_notice_player():
		_noticed_player = true
	else:
		_notice_pending = true

func is_alert_to_player() -> bool:
	return _sync_notice_player() and (kind == Kind.BOSS or _noticed_player)

func _notice_tick(delta: float) -> bool:
	if not _sync_notice_player():
		return false
	if kind == Kind.BOSS or _noticed_player:
		return true
	var mult := maxf(0.0, float(player.modify_stat(&"enemy_notice_radius_mult", 1.0)))
	var radius := maxf(0.0, notice_radius) * mult
	var diff := player.global_position - global_position
	# Слух не требует дополнительного луча через всю толпу и работает за стенами.
	if diff.x * diff.x + diff.z * diff.z <= radius * radius:
		_noticed_player = true
	else:
		_notice_wait += maxf(0.0, delta)
		if _notice_wait >= maxf(0.0, notice_fallback_time):
			_noticed_player = true
	return _noticed_player

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
		Kind.GRUNT, Kind.BOSS, Kind.FODDER, Kind.SHIELD:
			var reach := attack_range
			if kind == Kind.BOSS and dist > 5.0 and _cooldown <= 0.0 and randf() < boss_far_slam_chance:
				_begin_windup(true)
				return Vector3.ZERO
			if dist <= reach and _cooldown <= 0.0:
				_begin_windup(kind == Kind.BOSS and _attack_count % 3 == 2)
				return Vector3.ZERO
			move = dir
		Kind.BLOATED:
			# Бежит к Тору; вплотную — фитиль (телеграф-диск радиусом взрыва), потом взрыв
			if dist <= bloat_trigger_range and _cooldown <= 0.0 and _state_time > 0.2:
				_begin_windup(true)
				return Vector3.ZERO
			move = dir
		Kind.SHAMAN:
			move = _think_shaman(dist, dir)
			if _ritual_left <= 0.0:
				_ritual_left = ritual_interval
				_begin_windup(false)
				return Vector3.ZERO
		Kind.THROWER, Kind.MERC:
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

## Список врагов — один на кадр физики для всех (раньше каждый враг собирал свой массив: при толпе в 40–60 это лишние аллокации)
static var _group_frame: int = -1
static var _group_cache: Array[Node] = []

func _enemies_now() -> Array[Node]:
	var f := Engine.get_physics_frames()
	if f != _group_frame:
		_group_frame = f
		_group_cache = get_tree().get_nodes_in_group("enemies")
	return _group_cache

func _separation() -> Vector3:
	var push := Vector3.ZERO
	for e in _enemies_now():
		if e == self or not is_instance_valid(e):
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
	alert_to_player()  # Вручную начатая атака и её оставшаяся очередь уже видят цель.
	Perf.mark("enemy_windup")
	_doing_slam = slam
	_windup_serial += 1
	_set_state(State.WINDUP)
	if kind != Kind.THROWER and kind != Kind.MERC and (slam or randf() < (0.15 if kind == Kind.FODDER else 0.5)):
		Audio.sfx("zombie_groan" if FX.is_undead(self) else "", "sounds/sfx/enemy_growl.wav")
	if kind == Kind.SHAMAN:
		_ritual_telegraph()
	elif kind == Kind.MERC:
		_aim_point = player.global_position + Vector3(0, 1.0, 0) if player else global_position + global_transform.basis.z * 5.0
		# Механический сигнал прицеливания до очереди.
		Audio.sfx_while("merc_aim", "sounds/sfx/gun_reload.wav", _warning_is_timely.bind(_windup_serial))
	elif kind == Kind.THROWER:
		# Предупреждение до выпуска снаряда; ударный curse_throw остаётся отдельно.
		Audio.sfx_while("thrower_aim", "sounds/sfx/enemy_growl.wav", _warning_is_timely.bind(_windup_serial))
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

## Сигнал нужен в начале именно этого замаха, чтобы оставалось время среагировать.
func _warning_is_timely(serial: int) -> bool:
	return not is_dead and state == State.WINDUP and _windup_serial == serial and _state_time < windup_time * warning_deadline_fraction

func _execute_attack() -> void:
	_attack_count += 1
	_cooldown = attack_cooldown
	if _visual and _humanoid == null:
		var tw := create_tween()
		tw.tween_property(_visual, "scale", Vector3.ONE * model_scale, 0.12).set_trans(Tween.TRANS_BACK)
	match kind:
		Kind.THROWER:
			_throw_projectile()
		Kind.BLOATED:
			_doing_slam = false
			_die("self_blast")
			return
		Kind.SHIELD:
			_do_shield_bash()
		Kind.SHAMAN:
			_do_ritual()
		Kind.MERC:
			_start_burst()
		_:
			if _doing_slam:
				_do_boss_slam()
			else:
				_do_melee()
	_doing_slam = false
	# Парирование во время удара уже могло оглушить атакующего.
	if state != State.STUNNED:
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
		_hit_player(attack_damage, to_p.normalized() * 6.0 + Vector3.UP * 2.5, true)
	FX.burst(get_parent(), global_position + fwd * attack_range * 0.8 + Vector3(0, 1, 0), 0.5 * model_scale, Color(1, 0.3, 0.2, 0.5), 0.15)
	Audio.play("sounds/enemy_attack.ogg")

func _do_boss_slam() -> void:
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	FX.ring(get_parent(), global_position, boss_slam_radius, Color(1, 0.35, 0.2, 0.9), 0.4)
	FX.burst(get_parent(), global_position + Vector3(0, 0.5, 0), 1.5, Color(1, 0.4, 0.2, 0.4), 0.25)
	FX.shockwave(get_parent(), global_position, boss_slam_radius, Color(1.0, 0.55, 0.4))
	Audio.play("sounds/sfx/boss_slam.wav")
	if player and not player.is_dead:
		player.camera_fx.add_trauma(0.45)
		var d := player.global_position - global_position
		d.y = 0
		if d.length() <= boss_slam_radius and player.is_on_floor():
			_hit_player(boss_slam_damage, d.normalized() * 10.0 + Vector3.UP * 6.0)
	# Удар по площади ломает бочки и ящики (props/destructible.gd)
	Destructible.hit_area(self, global_position, boss_slam_radius, boss_slam_damage, 6.0, 4.0, "enemy_slam", 1.0)

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

# --- Враги Мидгарда (GDD 12.1): корм, Раздутый, Щитоносец, Шаман, Наёмник Локи ---

## id источника для причины смерти Тора (RunTracker) — совпадают с EnemyDef.id
const SOURCE_IDS := {Kind.FODDER: "draugr_fodder", Kind.BLOATED: "bloated", Kind.SHIELD: "shieldbearer", Kind.SHAMAN: "shaman", Kind.MERC: "loki_merc"}

func _setup_special() -> void:
	_tough = kind in [Kind.BLOATED, Kind.SHIELD, Kind.SHAMAN, Kind.MERC]
	if SOURCE_IDS.has(kind) and not has_meta("death_source_id"):
		set_meta("death_source_id", SOURCE_IDS[kind])
	_ritual_left = ritual_interval * randf_range(0.4, 0.7)
	if kind == Kind.SHIELD and _visual:
		# Щит — на корпусе спереди (а не в кисти): всегда виден там, где он блокирует
		var sh := WeaponMeshes.build("q_shield")
		sh.name = "FrontShield"
		sh.rotation_degrees = shield_rotation
		sh.position = shield_offset
		sh.scale = Vector3.ONE * shield_scale
		_visual.add_child(sh)
		_collect_meshes(_visual)
	if kind == Kind.MERC:
		# Лазер и точка — общие меш/материал эффектов, создаются один раз на наёмника и только прячутся
		_laser = MeshInstance3D.new()
		_laser.name = "Laser"
		_laser.mesh = FX.shared_mesh("box")
		FX.fx_apply(_laser, "alpha_nocull", Color(1.0, 0.1, 0.08, 0.75), 3.0)
		_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_laser.top_level = true
		_laser.visible = false
		add_child(_laser)
		_laser_dot = MeshInstance3D.new()
		_laser_dot.name = "LaserDot"
		_laser_dot.mesh = FX.shared_mesh("sphere")
		FX.fx_apply(_laser_dot, "glow", Color(1.0, 0.1, 0.05), 6.0)
		_laser_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_laser_dot.top_level = true
		_laser_dot.scale = Vector3.ONE * 0.14
		_laser_dot.visible = false
		add_child(_laser_dot)

func _update_special(delta: float) -> void:
	match kind:
		Kind.SHAMAN:
			if state == State.CHASE and is_alert_to_player():
				_ritual_left -= delta
		Kind.BLOATED:
			if _visual:
				var s := 1.0 + bloat_swell * _windup_glow
				_visual.scale = Vector3(bloat_fatness * s, s, bloat_fatness * s) * model_scale
		Kind.MERC:
			_update_merc(delta)

func _room() -> Node:
	var p := get_parent()
	return p if p and p.has_method("spawn_extra") else null

## Удар по Тору от этого врага; возвращает, сколько HP на самом деле снято (неуязвимость — 0).
func _hit_player(amount: float, knock: Vector3, parryable: bool = false) -> float:
	if player == null or not is_instance_valid(player) or player.is_dead:
		return 0.0
	if parryable and player.axe and player.axe.weapon_skill_try_parry_melee(self):
		return 0.0
	var h0 := player.health
	RunTracker.note_hit(self)
	ComicFX.on_player_struck(self, player)
	player.take_damage(amount, knock)
	var dealt := maxf(0.0, h0 - player.health)
	if dealt > 0.0:
		struck_player.emit(dealt)
	return dealt

func _has_floor_ahead(dir: Vector3, ahead: float = 0.9) -> bool:
	var from := global_position + dir.normalized() * ahead + Vector3(0, 0.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -1.6, 0), 1)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## Свободна ли линия (по миру) — чтобы не ставить поднятый корм в стену или за неё.
func _clear_path(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

# Щитоносец: щит спереди блокирует всё; проходят удар сверху (удар-приземление, по головам, Тор выше),
# сзади/сбоку, кирка (WeaponDef.special = "armor_break"), огонь и молнии. Оглушённый щит не держит.
func _shield_blocks(knockback: Vector3, source: String) -> bool:
	if state == State.STUNNED or state == State.SPAWNING:
		return false
	if source in ["slam", "stomp", "fire", "lightning", "explosion", "wall", "fall"]:
		return false
	if player and is_instance_valid(player):
		if hit_breaks_armor(source):
			return false
		if player.global_position.y - global_position.y > 1.6 * model_scale:
			return false
	var from_dir := Vector3.ZERO
	if source in ["hammer", "reflect"] and knockback.length() > 0.1:
		from_dir = -knockback
	elif player and is_instance_valid(player):
		from_dir = player.global_position - global_position
	from_dir.y = 0
	if from_dir.length() < 0.01:
		return false
	return from_dir.normalized().dot(global_transform.basis.z) > shield_front_dot

## Удар мили оружием, ломающим броню и щиты (кирка: WeaponDef.special = "armor_break").
func hit_breaks_armor(source: String) -> bool:
	if armor_pierce_hit:
		return true
	if not source.begins_with("melee") or player == null or not is_instance_valid(player):
		return false
	var w := player.current_weapon()
	return w != null and w.special == "armor_break"

func _on_blocked(knockback: Vector3) -> void:
	Perf.mark("shield_block")
	var push := Vector3(knockback.x, 0, knockback.z) * 0.25 * (1.0 - knock_resist)
	knockback_velocity += push
	velocity += push  # как в take_hit: база не должна съедать толчок
	var pos := global_position + Vector3(0, 1.2 * model_scale, 0) + global_transform.basis.z * 0.6
	FX.sparks(get_parent(), pos, Color(0.85, 0.92, 1.0), 12, 6.0)
	Audio.play("sounds/sfx/hammer_bounce.wav")
	ComicFX.pop("ricochet", pos)

## Удар щитом: урон и сильный толчок — теснит Тора (к краю, в огонь, под удары толпы).
func _do_shield_bash() -> void:
	var fwd := global_transform.basis.z
	knockback_velocity += fwd * lunge_speed
	if player and not player.is_dead:
		var to_p := player.global_position - global_position
		to_p.y = 0
		if to_p.length() <= attack_range * 1.35 + 0.3 and fwd.dot(to_p.normalized()) > 0.25:
			_hit_player(attack_damage, to_p.normalized() * shove_force + Vector3.UP * shove_up, true)
	FX.burst(get_parent(), global_position + fwd * attack_range * 0.8 + Vector3(0, 1, 0), 0.6 * model_scale, Color(0.8, 0.85, 1.0, 0.5), 0.15)
	Audio.play("sounds/sfx/wall_splat.wav")

# Шаман: стоит на высоте, отходит от Тора (не прыгая с края); раз в ritual_interval — обряд с телеграфом
func _think_shaman(dist: float, dir: Vector3) -> Vector3:
	if dist < shaman_flee_dist and _has_floor_ahead(-dir):
		return -dir
	return Vector3.ZERO

func _ritual_telegraph() -> void:
	Perf.mark("shaman_telegraph")
	FX.ring(get_parent(), global_position, 3.0, Color(0.35, 1.0, 0.45, 0.9), windup_time)
	FX.burst(get_parent(), global_position + Vector3(0, 2.0 * model_scale, 0), 0.4, Color(0.35, 1.0, 0.45, 0.6), windup_time)
	Audio.play("sounds/sfx/curse_throw.wav")

func _do_ritual() -> void:
	Perf.mark("shaman_ritual")
	var parent := get_parent()
	var top := global_position + Vector3(0, 2.0 * model_scale, 0)
	for e in _enemies_now():
		var en := e as Enemy
		if en == null or not is_instance_valid(en) or en.is_dead:
			continue
		if en.global_position.distance_to(global_position) > ritual_heal_radius or en.health >= en.max_health:
			continue
		var amt := minf(en.max_health * ritual_heal_fraction, en.max_health - en.health)
		en.health += amt
		FX.damage_number(parent, en.global_position + Vector3(0, 1.8 * en.model_scale, 0), amt, Color(0.4, 1.0, 0.5))
		FX.lightning(parent, top, en.global_position + Vector3(0, 1.0, 0), 0.3, Color(0.4, 1.0, 0.5))
	summon_around("fodder", ritual_raise_count, ritual_raise_cap)
	FX.ring(parent, global_position, 3.5, Color(0.35, 1.0, 0.45, 0.9), 0.4)
	Audio.play("sounds/sfx/lightning.wav")

## Поднять/призвать count врагов вида kind в 2.5–4.5 м вокруг (не в стену, не за край); не больше cap врагов в зале.
## Шаман и элита-Призыватель. Возвращает, сколько появилось.
func summon_around(kind_name: String, count: int, cap: int) -> int:
	var room := _room()
	if room == null or get_tree().get_nodes_in_group("enemies").size() >= cap:
		return 0
	Perf.mark("summon_" + kind_name)
	var made := 0
	for i in count * 3:
		if made >= count:
			break
		var a := randf() * TAU
		var cand := global_position + Vector3(cos(a), 0, sin(a)) * randf_range(2.5, 4.5)
		if not _clear_path(global_position + Vector3(0, 1.0, 0), cand + Vector3(0, 1.0, 0)):
			continue
		var ground := Loot.floor_point(self, cand)
		if ground == cand:
			continue
		if room.call("spawn_extra", kind_name, ground) != null:
			made += 1
	return made

# Наёмник Локи: держит дистанцию как метатель; лазер ведёт Тора windup_time (0.8 с), затем очередь по точке
func _muzzle() -> Vector3:
	return global_position + Vector3(0, 1.35 * model_scale, 0) + global_transform.basis.z * 0.55

func _update_merc(delta: float) -> void:
	if state == State.WINDUP and player and is_instance_valid(player):
		var target := player.global_position + Vector3(0, 1.0, 0)
		_aim_point = _aim_point.lerp(target, clampf(merc_aim_track * delta, 0.0, 1.0))
		_show_laser(_muzzle(), _aim_point)
	elif _laser and _laser.visible:
		_laser.visible = false
		_laser_dot.visible = false
	if state == State.STUNNED:
		_burst_left = 0
	if _burst_left > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_burst_t = merc_burst_interval
			_burst_left -= 1
			_fire_bullet()

func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)

func _show_laser(from: Vector3, aim: Vector3) -> void:
	if _laser == null:
		return
	var dir := (aim - from).normalized()
	var to := from + dir * merc_range
	var hit := _ray(from, to, 1 | (1 << 1))
	if not hit.is_empty():
		to = hit.position
	var length := from.distance_to(to)
	if length < 0.05:
		return
	_laser.visible = true
	_laser_dot.visible = true
	_laser.global_position = (from + to) * 0.5
	_laser.look_at(to, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	_laser.scale = Vector3(0.018, 0.018, length)
	_laser_dot.global_position = to - dir * 0.05

func _start_burst() -> void:
	Perf.mark("merc_burst")
	_burst_dir = (_aim_point - _muzzle()).normalized()
	_burst_left = merc_burst_count
	_burst_t = 0.0

func _fire_bullet() -> void:
	Perf.mark("merc_shot")
	var from := _muzzle()
	var spread := deg_to_rad(merc_spread_deg)
	var dir := _burst_dir.rotated(Vector3.UP, randf_range(-spread, spread))
	var side := dir.cross(Vector3.UP)
	if side.length() > 0.01:
		dir = dir.rotated(side.normalized(), randf_range(-spread, spread))
	var to := from + dir * merc_range
	var hit := _ray(from, to, 1 | (1 << 1))
	if not hit.is_empty():
		to = hit.position
		if hit.collider is Player:
			_hit_player(attack_damage * merc_bullet_mult, dir * 2.0)
	var tr := RangedWeapon.make_tracer_mesh()
	get_parent().add_child(tr)
	tr.global_position = from
	if from.distance_to(to) > 0.1:
		tr.look_at(to, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	var tw := tr.create_tween()
	tw.tween_property(tr, "global_position", to, from.distance_to(to) / 140.0)
	tw.tween_callback(tr.queue_free)
	FX.burst(get_parent(), from, 0.12, Color(1.0, 0.85, 0.4, 0.8), 0.06)
	Audio.play("sounds/sfx/gun_smg.wav")

# --- Урон ---

func take_hit(damage: float, knockback: Vector3, source: String = "") -> void:
	Perf.mark("enemy_hit")
	if is_dead:
		return
	if _spawn_entry != null:
		_spawn_entry.cancel()
	# Даже блок щитом или поглощение брони сообщает врагу о присутствии игрока.
	alert_to_player()
	if kind == Kind.SHIELD and damage < DEBUG_KILL_DAMAGE and _shield_blocks(knockback, source):
		_on_blocked(knockback)
		return
	if not elite_handlers.is_empty() and damage < DEBUG_KILL_DAMAGE:
		for h in elite_handlers:
			damage = (h as EliteHandler).filter_damage(damage, knockback, source)
		if damage <= 0.0:
			return
	health -= damage
	_last_hit_time = Run.combat_clock
	ComicFX.on_enemy_hit(self, damage, source)
	_hurt_flash = 1.0
	var big := source == "melee_finisher" or source == "melee_heavy" or source == "slam"
	if source != "fire" and source != "ranged":
		FX.sparks(get_parent(), global_position + Vector3(0, 1.1 * model_scale, 0), Color(1, 0.85, 0.4) if source.begins_with("melee") else Color(0.6, 0.85, 1.0), 18 if big else 10, 7.0 if big else 5.0)
	FX.enemy_hit(self, damage, source, big)  # вспышка, у нежити — ихор (VFX-комплект)
	FX.damage_number(get_parent(), global_position + Vector3(0, 1.8 * model_scale, 0), damage,
		Color(1, 0.55, 0.2) if big else (Color(0.6, 0.85, 1.0) if source in ["hammer", "lightning"] else Color(1, 0.92, 0.4)), big)
	var k := apply_knockback_only(knockback)
	# Реакция на удар (не сбиваем анимацию атаки и оглушения)
	if _humanoid and health > 0.0 and state in [State.CHASE, State.RECOVER] and k.length() > 1.0:
		_humanoid.play(anim_hit, 0.03, 1.3)
		_hit_anim_left = 0.25
	if k.length() > 0.1:
		_last_knock = k
	if k.y > 2.5 and is_on_floor():
		velocity.y = k.y
		knockback_velocity.y = 0
	# Замах сбивают мили и Мьёльнир (ренж — нет); элиту — только сильные удары и молот; босса — ничто
	var interrupts := big or source == "hammer" or source == "stomp" or (source.begins_with("melee") and not has_meta("elite") and not _tough)
	if kind != Kind.BOSS and kind != Kind.BLOATED and state == State.WINDUP and interrupts:
		if _telegraph and is_instance_valid(_telegraph):
			_telegraph.queue_free()
		_set_state(State.RECOVER)
	if health <= 0.0:
		_die(source)

## Толчок без урона: волна посоха на первых двух уровнях использует ту же физику, что и попадание.
func apply_knockback_only(knockback: Vector3) -> Vector3:
	if is_dead:
		return Vector3.ZERO
	if knockback.length_squared() > 0.0001:
		if _spawn_entry != null:
			_spawn_entry.cancel()
		alert_to_player()
	var k := knockback * (1.0 - knock_resist)
	if k.length_squared() > 0.0001:
		# Толчок без урона тоже может сбросить врага с уступа.
		_last_hit_time = Run.combat_clock
	knockback_velocity += k
	# _apply_movement вычитает накопленный толчок из velocity при вычислении базовой скорости.
	velocity.x += k.x
	velocity.z += k.z
	return k

## Оглушить на time секунд (трейты, эффекты, Мьёльнир — сильное оглушение: элиту тоже). Босса — нет.
## HP, скорость, урон и Слава из описания GDD (вызывается залом до add_child).
func apply_def(d: EnemyDef) -> void:
	enemy_def = d
	max_health = d.max_health()
	move_speed = d.move_speed
	if kind == Kind.THROWER:
		projectile_damage = d.damage
	else:
		attack_damage = d.damage
	glory_value = d.glory

func stun(time: float) -> void:
	apply_stun(time, true)

## Оглушение оружием (дубина и т. п.). Элиту и босса — только сильным ударом (strong), босса — никогда.
func apply_stun(time: float, strong: bool = false) -> void:
	if is_dead or time <= 0.0:
		return
	alert_to_player()
	if kind == Kind.BOSS or ((has_meta("elite") or _tough) and not strong):
		return
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_stun_left = maxf(_stun_left, time)
	_set_state(State.STUNNED)

func _apply_movement(move_dir: Vector3, delta: float) -> void:
	var can_move: bool = state == State.CHASE or (state == State.SPAWNING and _spawn_entry != null and _spawn_entry.active)
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
	_check_fall()
	_update_stuck(move_dir, delta)
	if global_position.y < -30.0:
		_die("fall")

## Сброшенный с высоты враг (GDD 8): корм — насмерть, остальные — fall_damage. Босса не касается.
func _check_fall() -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		if not _airborne:
			_airborne = true
			_fall_peak_y = global_position.y
			_fall_forced = state != State.SPAWNING and Run.combat_clock - _last_hit_time <= fall_hit_window
		_fall_peak_y = maxf(_fall_peak_y, global_position.y)
		return
	if not _airborne:
		return
	_airborne = false
	var h := _fall_peak_y - global_position.y
	if not _fall_forced or h < fall_kill_height or kind == Kind.BOSS or is_dead:
		return
	Perf.mark("enemy_fall")
	var dmg := health + 1.0 if kind == Kind.FODDER else fall_damage
	take_hit(dmg, Vector3.ZERO, "fall")

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
		_last_splat_time = Run.combat_clock
		knockback_velocity = n * 2.0
		FX.burst(get_parent(), col.get_position(), 0.8, Color(1, 1, 1, 0.6), 0.2)
		if player:
			player.camera_fx.add_trauma(0.2)
		Audio.play("sounds/sfx/wall_splat.wav")
		StyleMeter.event(&"wall_splat")
		if kind != Kind.BOSS:
			_stun_left = wall_splat_stun
			_set_state(State.STUNNED)
		take_hit(wall_splat_damage, Vector3.ZERO, "wall")
		return

func _die(source: String) -> void:
	if is_dead:
		return
	# Тело продолжает анимацию смерти после передачи в RigidBody3D.
	_restore_fodder_animation()
	is_dead = true
	# Смерть отмечаем до эффектов и взрыва: Раздутый и самоподрыв не создают обычный труп.
	Perf.mark("enemy_death")
	remove_from_group("enemies")
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	if kind == Kind.BLOATED:
		# Взрывается и сам (дошёл до Тора), и от смерти (GDD: «убить издалека, молотом в толпу»)
		Blast.detonate(get_parent(), global_position + Vector3(0, 0.9 * model_scale, 0), boss_slam_radius, attack_damage, self, self)
	if source == "self_blast":
		# Подорвался сам — не убийство Тора: ни Славы, ни лечения, ни добычи
		died.emit(self)
		queue_free()
		return
	var now := Run.combat_clock
	# Мини-босс — тоже Kind.BOSS (поведение босса), но Славу за него даёт MinibossDef
	# Слава по GDD 15.2: по слою врага (EnemyDef), элита — 15
	var glory_base := Run.glory_elite_kill if has_meta("elite") else glory_value
	Run.register_kill(source == "melee_finisher", now - _last_splat_time < 0.6,
		kind == Kind.BOSS and not has_meta("miniboss"), source, glory_base,
		kind == Kind.FODDER and not has_meta("elite"))
	ComicFX.on_enemy_killed(self, source)
	FX.enemy_died(self, source)
	if player and is_instance_valid(player) and not player.is_dead:
		player.heal(player.kill_heal(source))
	Loot.on_enemy_died(self, source)
	Audio.sfx("zombie_death" if FX.is_undead(self) and kind != Kind.BLOATED else "", "sounds/enemy_destroy.ogg")
	if kind != Kind.BLOATED:
		_spawn_debris()
	died.emit(self)
	queue_free()

func _spawn_debris() -> void:
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
	tw.tween_callback(FX.corpse_smoke.bind(rb))
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
const FLASH_GL_SHADER := preload("res://shaders/hit_flash_gl.gdshader")
const FLASH_MATERIAL_GL := preload("res://shaders/hit_flash_gl.tres")

## Forward+ использует общий оверлей с per-instance параметрами; в GL у каждого врага
## свой материал с обычными uniform, чтобы части модели не занимали ограниченный буфер.
## Оверлей включается только пока есть что показывать (лишний проход рисования не нужен).
## Элита светится постоянно (цвет модификатора, мягкая пульсация) — тот же материал, параметр "elite".
func _set_overlay(flash: float, glow: float) -> void:
	var el := 0.0
	var el_color := Color(elite_glow.r, elite_glow.g, elite_glow.b)
	if elite_glow.a > 0.0 and not is_dead:
		el = elite_glow.a * (0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.004))
	# Состояние стихии (горит, заморожен, под током…) важнее свечения элиты — тот же параметр, без нового материала
	if status_glow.a > 0.001 and not is_dead:
		el = status_glow.a
		el_color = Color(status_glow.r, status_glow.g, status_glow.b)
	var on := flash > 0.001 or glow > 0.001 or el > 0.001
	if not on and not _overlay_on:
		return
	var use_gl_material := _flash_material_gl != null
	if on and use_gl_material:
		if not _overlay_on:
			_flash_material_gl.next_pass = Outline.flash_next_pass()
		_flash_material_gl.set_shader_parameter("flash", flash)
		_flash_material_gl.set_shader_parameter("glow", glow)
		_flash_material_gl.set_shader_parameter("elite", Color(el_color.r, el_color.g, el_color.b, el))
	for g in _flash_meshes:
		if not is_instance_valid(g):
			continue
		if on != _overlay_on:
			# Погасла — обратно комиксовая обводка (scripts/outline.gd; при вспышке она — next_pass FLASH_MATERIAL)
			g.material_overlay = (_flash_material_gl if use_gl_material else FLASH_MATERIAL) if on else Outline.overlay()
		if on and not use_gl_material:
			g.set_instance_shader_parameter("flash", flash)
			g.set_instance_shader_parameter("glow", glow)
			g.set_instance_shader_parameter("elite", Color(el_color.r, el_color.g, el_color.b, el))
	_overlay_on = on

func _collect_meshes(root: Node) -> void:
	_flash_meshes.clear()
	for mi in root.find_children("*", "GeometryInstance3D", true, false):
		# Глаза и брови (Eyes, Eyebrows*) вспышку не показывают — светятся сами и крошечные.
		if mi is MeshInstance3D and not mi.name.begins_with("Eye"):
			_flash_meshes.append(mi as GeometryInstance3D)
	# Комиксовая обводка (GDD 20) — тот же слот оверлея, те же меши
	Outline.add_meshes(_flash_meshes)

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
