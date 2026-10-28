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
## По врагу прошёл урон (после щита и брони) — для черт мобов (EnemyTraitHandler.on_hit)
signal hit_taken(damage: float, source: String)

const SpawnEntry = preload("res://enemies/spawn_entry.gd")
const TierNavigation = preload("res://rooms/enemy_navigation.gd")

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
## Разница высот ног, в пределах которой обычная ближняя атака может достать Тора.
@export var melee_vertical_reach: float = 1.6
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

@export_group("Снаряды и зоны")
## GDD 12.6: метатель иногда кидает веер (несколько прямых снарядов) или навесом (дуга, метка на полу)
@export_range(0.0, 1.0, 0.05) var thrower_fan_chance: float = 0.35
@export_range(1, 7) var thrower_fan_count: int = 4
@export var thrower_fan_spread_deg: float = 36.0
## Урон каждого снаряда веера — доля projectile_damage
@export_range(0.1, 1.0, 0.05) var thrower_fan_damage_mult: float = 0.6
@export_range(0.0, 1.0, 0.05) var thrower_lob_chance: float = 0.3
## Навесной (метатель) и граната (наёмник): время полёта до метки и гравитация дуги
@export var lob_flight_time: float = 1.1
@export var lob_gravity: float = 20.0
## Радиус всплеска навесного снаряда (м)
@export var lob_radius: float = 1.6
## Шаман между обрядами: медленная сфера или круг проклятия под Тором, раз в столько секунд
@export var shaman_cast_interval: float = 4.5
@export var shaman_cast_range: float = 22.0
@export_range(0.0, 1.0, 0.05) var shaman_orb_chance: float = 0.5
@export var shaman_orb_speed: float = 4.0
## Доворот сферы к Тору, рад/с (слабо — уйти рывком)
@export var shaman_orb_homing: float = 0.9
@export var shaman_orb_radius: float = 0.6
@export var shaman_orb_damage: float = 18.0
@export var shaman_orb_life: float = 7.0
@export var shaman_curse_radius: float = 2.4
## Телеграф круга (GDD 12.6: 0.8–1.2 с)
@export var shaman_curse_telegraph: float = 1.0
@export var shaman_curse_damage: float = 15.0
## Лужа проклятия после удара: секунды и урон в секунду, пока стоишь
@export var shaman_curse_puddle_time: float = 3.0
@export var shaman_curse_puddle_dps: float = 6.0
## Раздутый: лужа браги/яда после взрыва (замедляет; 0 с — без лужи)
@export var bloat_puddle_radius: float = 2.2
@export var bloat_puddle_time: float = 5.0
@export_range(0.1, 1.0, 0.05) var bloat_puddle_slow: float = 0.6
## Доля воинов с копьём (бросают копьё с spear_min_dist–spear_max_dist м)
@export_range(0.0, 1.0, 0.05) var spear_chance: float = 0.25
@export var spear_min_dist: float = 8.0
@export var spear_max_dist: float = 12.0
@export var spear_speed: float = 20.0
@export var spear_damage_mult: float = 1.0
@export var spear_cooldown: float = 6.0
## Наёмник: граната с меткой (взрыв бьёт и своих)
@export_range(0.0, 1.0, 0.05) var merc_grenade_chance: float = 0.35
@export var merc_grenade_min_dist: float = 5.0
@export var merc_grenade_cooldown: float = 5.0
@export var merc_grenade_flight: float = 1.0
@export var merc_grenade_radius: float = 2.6
@export var merc_grenade_fuse: float = 0.7
@export var merc_grenade_damage: float = 22.0

@export_group("Роли")
## GDD 12.6, enemies/parts/enemy_tactics.gd. Доля воинов, обходящих с фланга (остальные — окружение)
@export_range(0.0, 1.0, 0.05) var tactics_flank_chance: float = 0.3
## Окружение: радиус круга точек вокруг Тора (меньше attack_range — из точки можно бить)
@export var tactics_surround_radius: float = 1.6
## Окружение: боец дальше этого угла от своей точки круга и в толкучке сначала обходит (не дольше patience, с)
@export var tactics_surround_slot_deg: float = 50.0
@export var tactics_surround_patience: float = 1.2
## Толкучка: у Тора уже есть другой боец ближе стольких метров
@export var tactics_surround_crowd: float = 3.5
## Обход по кругу начинается ближе attack_range + 0.6 + столько метров
@export var tactics_surround_orbit: float = 2.0
## Фланг: обход на таком радиусе и угле от спины Тора, потом сходится
@export var tactics_flank_radius: float = 3.5
@export var tactics_flank_angle_deg: float = 75.0
## Прикрытие: щитоносец в пределах стольких метров, стрелок встаёт за ним на cover_offset
@export var tactics_cover_search: float = 14.0
@export var tactics_cover_offset: float = 2.5
## Свита (отряд «Шаман и свита»): кольцо вокруг якоря, бой — когда Тор ближе escort_engage
@export var tactics_escort_radius: float = 3.0
@export var tactics_escort_engage: float = 6.0
## Раздутый в засаде: выбегает, когда Тор ближе rush_dist или занят (busy_count врагов в busy_radius)
@export var tactics_lurk_rush_dist: float = 5.0
@export var tactics_busy_radius: float = 3.0
@export var tactics_busy_count: int = 2
## Отступление раненого стрелка: ниже доли HP, на столько секунд
@export_range(0.0, 1.0, 0.05) var tactics_retreat_hp: float = 0.4
@export var tactics_retreat_time: float = 2.5

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
## Сдвиг вида при любом попадании. Не меняет состояние или движение врага.
@export_range(0.0, 1.0, 0.01) var flinch_distance: float = 0.13
@export_range(0.01, 1.0, 0.01) var flinch_time: float = 0.12
@export var body_color: Color = Color(0.32, 0.45, 0.33)
@export var model_scale: float = 1.0

@export_group("Мясо корма (П3)")
## Корм при смерти разлетается на куски (enemies/parts/fodder_gibs.gd): торс — тело, голова/руки/ноги — куски
@export var gib_on_death: bool = true
## Общий лимит кусков (без торсов) в зале: сверх — самые старые исчезают сразу
@export var gib_limit: int = 40
## Сколько секунд кусок лежит, прежде чем провалиться в пол
@export var gib_life: float = 4.0
@export var gib_sink_time: float = 0.6
## Скорость кусков по удару: доля силы отброса (не меньше 4 м/с) и предел, м/с
@export var gib_knock_ratio: float = 0.9
@export var gib_knock_max: float = 14.0
## Разлёт кусков от центра тела, вверх и вращение
@export var gib_outward: float = 5.5
## Куски появляются уже разнесёнными от центра на столько метров (× масштаб модели)
@export var gib_burst_offset: float = 0.25
@export var gib_up: float = 4.5
@export var gib_spin: float = 12.0

@export_group("Броня босса (П4)")
## Множитель урона обычных ударов мили (melee / melee_finisher) по боссу и мини-боссу (Kind.BOSS).
## Число — в данных: EnemyDef.melee_resist (Ярл), MinibossDef.melee_resist. Молот, стихии, удар-приземление,
## приёмы оружия (melee_heavy) и прочее — полный урон. Обычных врагов не касается.
@export_range(0.05, 1.0, 0.05) var melee_resist: float = 1.0
## Удар по броне: вспышка тусклее (доля обычной) — видно, что рукой не берётся
@export_range(0.0, 1.0, 0.05) var armor_flash: float = 0.3

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
## Только при наличии у зала настроенной навигации между ярусами.
var _tier_navigation: TierNavigation
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
var _flinch_left: float = 0.0
var _flinch_direction: Vector3 = Vector3.ZERO
var _flinch_applied: Vector3 = Vector3.ZERO
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
## GDD 12.6: выбранная особая атака замаха (EnemyRangedAttacks: &"fan", &"lob", &"orb", &"curse",
## &"spear", &"grenade"; &"" — обычная атака вида) и перезарядка особых атак (копьё, шаман, граната)
var _attack_mode: StringName = &""
var _special_cd: float = 0.0
## Роль поведения (EnemyTactics.Role) и её состояние
var _role: int = 0
var _slot_angle: float = 0.0
var _flank_sign: float = 1.0
var _retreated: bool = false
var _retreat_left: float = 0.0
var _reposition_t: float = 0.0
## Черта моба (Трус) может на время задать направление бега вместо обычного мышления
var _forced_move: Vector3 = Vector3.ZERO
var _forced_move_left: float = 0.0
## Прыжок черты «Прыгун»: пока > 0, горизонтальная скорость прыжка не гаснет (EnemyMotion)
var _leap_left: float = 0.0
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

## Компоненты (этап 3 рефакторинга): логика по файлам enemies/parts/*.gd, состояние — поля выше.
var notice: EnemyNotice
var fodder_lod: EnemyFodderLod
var motion: EnemyMotion
var shield: EnemyShield
var shaman: EnemyShaman
var merc: EnemyMerc
var visual: EnemyVisual
var ranged: EnemyRangedAttacks
var tactics: EnemyTactics

func _init() -> void:
	notice = EnemyNotice.new(self)
	fodder_lod = EnemyFodderLod.new(self)
	motion = EnemyMotion.new(self)
	shield = EnemyShield.new(self)
	shaman = EnemyShaman.new(self)
	merc = EnemyMerc.new(self)
	visual = EnemyVisual.new(self)
	ranged = EnemyRangedAttacks.new(self)
	tactics = EnemyTactics.new(self)

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
			# GDD 12.6: часть воинов — с копьём, бросают его издалека
			if kind == Kind.GRUNT and rng.randf() < spear_chance:
				hand_weapon = "q_spear"
		_humanoid.skin_tint = Color.WHITE if kind == Kind.FODDER else skin_tint
		_humanoid.cloth_tint = cloth_tint
		_humanoid.eye_glow = Color(0, 0, 0, 0) if kind == Kind.FODDER else eye_glow
		add_child(_humanoid)
		_humanoid.scale = Vector3.ONE * model_scale
		_visual = _humanoid
		if hand_weapon != "":
			visual._attach_weapon(hand_weapon)
	elif _visual is HumanoidModel:
		_humanoid = _visual as HumanoidModel
	if _visual == null:
		_visual = visual._build_procedural_model()
	visual._collect_meshes(_visual)
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

## Room регистрирует и обычные волны, и призывы через одну точку.
func enable_tier_navigation(root: Node3D, settings: Dictionary) -> void:
	if root == null or _tier_navigation != null:
		return
	_tier_navigation = TierNavigation.new()
	_tier_navigation.setup(self, root, settings)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Player
	_state_time += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	_special_cd = maxf(0.0, _special_cd - delta)

	var move_dir := Vector3.ZERO
	match state:
		State.SPAWNING:
			if _spawn_entry != null and _spawn_entry.active:
				move_dir = _spawn_entry.desired_velocity(self, accel) / maxf(move_speed, 0.01)
			elif _state_time >= _spawn_time:
				_set_state(State.CHASE)
		State.CHASE:
			if _tier_navigation != null and _tier_navigation.is_jumping():
				move_dir = _tier_navigation.jump_direction(move_speed, accel)
			elif _tier_navigation != null and _tier_navigation.is_waiting_for_landing():
				move_dir = Vector3.ZERO
			elif notice._notice_tick(delta):
				if _tier_navigation != null:
					if _tier_navigation.step(player):
						_fodder_lod_move_valid = false
					_tier_navigation.try_jump(move_speed, gravity)
				if _tier_navigation != null and _tier_navigation.is_jumping():
					move_dir = _tier_navigation.jump_direction(move_speed, accel)
				elif _tier_navigation == null or not _tier_navigation.has_pending_jump():
					move_dir = fodder_lod._think_chase_lod(delta)
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

	motion._apply_movement(move_dir, delta)
	if _spawn_entry != null:
		_spawn_entry.after_step(self, delta)
	if _tier_navigation != null:
		_tier_navigation.after_move(delta)
	_update_special(delta)
	visual._update_visual_feedback(delta)
	visual._update_animation(delta)
	fodder_lod._update_fodder_animation_lod(delta)

func _set_state(s: State) -> void:
	if s != State.CHASE and _tier_navigation != null:
		_tier_navigation.interrupt_jump()
	if s != State.SPAWNING and _spawn_entry != null:
		_spawn_entry.cancel()
	state = s
	_state_time = 0.0
	if s != State.CHASE:
		_fodder_lod_move_valid = false
	if s != State.WINDUP:
		_windup_glow = 0.0
		_attack_mode = &""  # прерванный замах не переносит особую атаку на следующий
	if s == State.STUNNED and _humanoid:
		_humanoid.play(anim_stun, 0.05)

# --- Мышление ---

func _think_chase() -> Vector3:
	if player == null or player.is_dead:
		return Vector3.ZERO
	var to_player := player.global_position - global_position
	to_player.y = 0
	var dist := to_player.length()
	var dir := to_player.normalized() if dist > 0.01 else Vector3.ZERO
	if _forced_move_left > 0.0:
		_forced_move_left -= get_physics_process_delta_time()
		_face_dir(_forced_move, get_physics_process_delta_time())
		return _forced_move
	_face_dir(dir, get_physics_process_delta_time())
	var move := Vector3.ZERO
	match kind:
		Kind.GRUNT, Kind.BOSS, Kind.FODDER, Kind.SHIELD:
			if kind == Kind.GRUNT and ranged.wants_spear(dist):
				_attack_mode = &"spear"
				_begin_windup(false)
				return Vector3.ZERO
			var reach := attack_range
			if kind == Kind.BOSS and dist > 5.0 and _cooldown <= 0.0 and randf() < boss_far_slam_chance:
				_begin_windup(true)
				return Vector3.ZERO
			if dist <= reach and _cooldown <= 0.0 and (kind == Kind.BOSS or _can_reach_melee_target()) \
					and (kind == Kind.BOSS or tactics.strike_ok(get_physics_process_delta_time())):
				_begin_windup(kind == Kind.BOSS and _attack_count % 3 == 2)
				return Vector3.ZERO
			move = tactics.melee_dir(dist, dir) if kind != Kind.BOSS else dir
		Kind.BLOATED:
			# Бежит к Тору; вплотную — фитиль (телеграф-диск радиусом взрыва), потом взрыв
			if dist <= bloat_trigger_range and _cooldown <= 0.0 and _state_time > 0.2 and _can_reach_melee_target():
				_begin_windup(true)
				return Vector3.ZERO
			move = tactics.melee_dir(dist, dir)
		Kind.SHAMAN:
			move = tactics.ranged_move(dist, dir, shaman._think_shaman(dist, dir), get_physics_process_delta_time())
			if _ritual_left <= 0.0:
				_ritual_left = ritual_interval
				_begin_windup(false)
				return Vector3.ZERO
			# Между обрядами — сфера или круг проклятия (не откладывая обряд)
			if _special_cd <= 0.0 and _ritual_left > windup_time + recover_time + 0.5 \
					and dist < shaman_cast_range and notice.is_alert_to_player() and _has_line_of_sight():
				var mode := ranged.choose_shaman()
				if mode != &"wait":
					_attack_mode = mode
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
			move = tactics.ranged_move(dist, dir, move, get_physics_process_delta_time())
			if _cooldown <= 0.0 and dist < keep_max_dist + 6.0 and _has_line_of_sight():
				var mode := ranged.choose_thrower() if kind == Kind.THROWER else ranged.choose_merc(dist)
				if mode == &"wait":
					_cooldown = 0.5  # лимит снарядов зала: ждём
				else:
					_attack_mode = mode
					_begin_windup(false)
					return Vector3.ZERO
	if _tier_navigation != null and _tier_navigation.is_active():
		# Стрелок с видимой целью может продолжать бой с балкона; пока ждёт
		# перезарядку, не отступает вслепую через край. Шаман сохраняет обряд выше.
		if kind in [Kind.THROWER, Kind.MERC] and dist < keep_max_dist + 6.0 and _has_line_of_sight():
			return Vector3.ZERO
		move = _tier_navigation.direction()
		if move == Vector3.ZERO:
			return Vector3.ZERO  # нет проверенного пути: не толкаем себя к краю
		_face_dir(move, get_physics_process_delta_time())
	elif _detour_left > 0.0 and move != Vector3.ZERO:
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
		# На отдельном этаже чужая капсула не должна сдвигать нас с настила.
		if _tier_navigation != null and absf(d.y) > melee_vertical_reach * model_scale:
			continue
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

## Не бить сквозь настил и не начинать замах по цели на другом ярусе.
func _can_reach_melee_target() -> bool:
	return player != null and is_instance_valid(player) and not player.is_dead \
		and absf(player.global_position.y - global_position.y) <= melee_vertical_reach * model_scale \
		and _has_line_of_sight()

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
	notice.alert_to_player()  # Вручную начатая атака и её оставшаяся очередь уже видят цель.
	Perf.mark("enemy_windup")
	_doing_slam = slam
	_windup_serial += 1
	_set_state(State.WINDUP)
	if kind != Kind.THROWER and kind != Kind.MERC and (slam or randf() < (0.15 if kind == Kind.FODDER else 0.5)):
		Audio.sfx("zombie_groan" if FX.is_undead(self) else "", "sounds/sfx/enemy_growl.wav")
	if _attack_mode != &"":
		ranged.windup_telegraph(_attack_mode)
	if kind == Kind.SHAMAN:
		if _attack_mode == &"":
			shaman._ritual_telegraph()
	elif kind == Kind.MERC and _attack_mode == &"":
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
	var mode := _attack_mode
	_attack_mode = &""
	if mode != &"" and kind != Kind.BOSS and ranged.execute(mode):
		pass
	else:
		_execute_kind_attack()
	_doing_slam = false
	# Парирование во время удара уже могло оглушить атакующего.
	if not is_dead and state != State.STUNNED:
		_set_state(State.RECOVER)

func _execute_kind_attack() -> void:
	match kind:
		Kind.THROWER:
			_throw_projectile()
		Kind.BLOATED:
			_doing_slam = false
			_die("self_blast")
			return
		Kind.SHIELD:
			shield._do_shield_bash()
		Kind.SHAMAN:
			shaman._do_ritual()
		Kind.MERC:
			merc._start_burst()
		_:
			if _doing_slam:
				_do_boss_slam()
			else:
				_do_melee()

func _do_melee() -> void:
	var fwd := global_transform.basis.z
	knockback_velocity += fwd * lunge_speed
	if player == null or player.is_dead:
		return
	var to_p := player.global_position - global_position
	to_p.y = 0
	var reach := attack_range * 1.35 + 0.3
	if to_p.length() <= reach and fwd.dot(to_p.normalized()) > 0.25 and (kind == Kind.BOSS or _can_reach_melee_target()):
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
		shield.attach_front_shield()
	if kind == Kind.MERC:
		merc.build_laser()
	if kind == Kind.SHAMAN:
		_special_cd = shaman_cast_interval * randf_range(0.3, 0.6)
	tactics.assign()

func _update_special(delta: float) -> void:
	match kind:
		Kind.SHAMAN:
			if state == State.CHASE and notice.is_alert_to_player():
				_ritual_left -= delta
		Kind.BLOATED:
			if _visual:
				var s := 1.0 + bloat_swell * _windup_glow
				_visual.scale = Vector3(bloat_fatness * s, s, bloat_fatness * s) * model_scale
		Kind.MERC:
			merc._update_merc(delta)

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

# Шаман: стоит на высоте, отходит от Тора (не прыгая с края); раз в ritual_interval — обряд с телеграфом

# Наёмник Локи: держит дистанцию как метатель; лазер ведёт Тора windup_time (0.8 с), затем очередь по точке

func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)

# --- Урон ---

func take_hit(damage: float, knockback: Vector3, source: String = "") -> void:
	Perf.mark("enemy_hit")
	if is_dead:
		return
	if _tier_navigation != null:
		_tier_navigation.interrupt_jump()
	if _spawn_entry != null:
		_spawn_entry.cancel()
	# Даже блок щитом или поглощение брони сообщает врагу о присутствии игрока.
	notice.alert_to_player()
	if damage > 0.0:
		visual._begin_flinch(knockback)
	if kind == Kind.SHIELD and damage < DEBUG_KILL_DAMAGE and shield._shield_blocks(knockback, source):
		shield._on_blocked(knockback)
		return
	if not elite_handlers.is_empty() and damage < DEBUG_KILL_DAMAGE:
		for h in elite_handlers:
			damage = (h as EliteHandler).filter_damage(damage, knockback, source)
		if damage <= 0.0:
			return
	# П4: броня боссов от спама мили — обычные удары мили ×melee_resist, «тынк», искры, тусклая вспышка
	var armored := is_armored_against(source) and damage < DEBUG_KILL_DAMAGE
	if armored:
		damage *= melee_resist
	health -= damage
	_last_hit_time = Run.combat_clock
	hit_taken.emit(damage, source)
	ComicFX.on_enemy_hit(self, damage, source)
	_hurt_flash = armor_flash if armored else 1.0
	var big := source == "melee_finisher" or source == "melee_heavy" or source == "slam"
	if armored:
		_armor_feedback()
	elif source != "fire" and source != "ranged":
		FX.sparks(get_parent(), global_position + Vector3(0, 1.1 * model_scale, 0), Color(1, 0.85, 0.4) if source.begins_with("melee") else Color(0.6, 0.85, 1.0), 18 if big else 10, 7.0 if big else 5.0)
	FX.enemy_hit(self, damage, source, big)  # вспышка, у нежити — ихор (VFX-комплект)
	FX.damage_number(get_parent(), global_position + Vector3(0, 1.8 * model_scale, 0), damage,
		Color(1, 0.55, 0.2) if big else (Color(0.6, 0.85, 1.0) if source in ["hammer", "lightning"] else Color(1, 0.92, 0.4)), big)
	var k := motion.apply_knockback_only(knockback)
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

## Броня босса (П4): обычный удар мили по боссу/мини-боссу ослаблен (melee_resist < 1).
## «Старое» (FeelSwitch boss_armor, F6 в «Быстрой проверке») — без брони, ×1.0.
func is_armored_against(source: String) -> bool:
	return kind == Kind.BOSS and melee_resist < 1.0 and (source == "melee" or source == "melee_finisher") \
		and not FeelSwitch.is_old(&"boss_armor")

## Удар по броне: искры как по щиту, глухой «тынк»; раз за бой — подсказка Одина «молотом!».
func _armor_feedback() -> void:
	Perf.mark("boss_armor_hit")
	var pos := global_position + Vector3(0, 1.1 * model_scale, 0)
	if player and is_instance_valid(player):
		var to_p := player.global_position - global_position
		to_p.y = 0.0
		if to_p.length() > 0.1:
			pos += to_p.normalized() * 0.5 * model_scale
	FX.sparks(get_parent(), pos, Color(0.8, 0.86, 0.95), 10, 5.0)
	Audio.play("sounds/sfx/armor_tink.wav")
	# Раз за бой; если Один молчит (идёт диалог) — подскажет при следующем ударе по броне
	if not has_meta("_armor_hinted") and Odin.say("boss_armor") != "":
		set_meta("_armor_hinted", true)

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
	melee_resist = d.melee_resist

func stun(time: float) -> void:
	apply_stun(time, true)

## Оглушение оружием (дубина и т. п.). Элиту и босса — только сильным ударом (strong), босса — никогда.
func apply_stun(time: float, strong: bool = false) -> void:
	if is_dead or time <= 0.0:
		return
	notice.alert_to_player()
	if kind == Kind.BOSS or ((has_meta("elite") or _tough) and not strong):
		return
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_stun_left = maxf(_stun_left, time)
	_set_state(State.STUNNED)

func _die(source: String) -> void:
	if is_dead:
		return
	# Тело продолжает анимацию смерти после передачи в RigidBody3D.
	fodder_lod._restore_fodder_animation()
	is_dead = true
	# Смерть отмечаем до эффектов и взрыва: Раздутый и самоподрыв не создают обычный труп.
	Perf.mark("enemy_death")
	remove_from_group("enemies")
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	if kind == Kind.BLOATED:
		# Взрывается и сам (дошёл до Тора), и от смерти (GDD: «убить издалека, молотом в толпу»)
		Blast.detonate(get_parent(), global_position + Vector3(0, 0.9 * model_scale, 0), boss_slam_radius, attack_damage, self, self)
		ranged.bloated_puddle()  # GDD 12.6: лужа браги/яда
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
	if source == "fall" and _fall_forced and _fall_peak_y - global_position.y >= fall_kill_height:
		ComicFX.pop("ledge_kill", global_position + Vector3.UP * model_scale)
		StyleMeter.event(&"ledge_kill")
	ComicFX.on_enemy_killed(self, source)
	FX.enemy_died(self, source)
	if player and is_instance_valid(player) and not player.is_dead:
		player.heal(player.kill_heal(source))
	Loot.on_enemy_died(self, source)
	Audio.sfx("zombie_death" if FX.is_undead(self) and kind != Kind.BLOATED else "", "sounds/enemy_destroy.ogg")
	if kind == Kind.FODDER and gib_on_death:
		Audio.play(GIB_SOUNDS)  # П3: хрусткий звук мяса
	if kind != Kind.BLOATED:
		visual._spawn_debris()
	died.emit(self)
	queue_free()

## Общий финал тела — используется комнатой после окончания конкретной волны.
static func fade_debris(rb: RigidBody3D, vis: Node3D, delay: float = 0.0) -> void:
	if not is_instance_valid(rb) or not is_instance_valid(vis) or rb.is_queued_for_deletion():
		return
	var tw := rb.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_callback(FX.corpse_smoke.bind(rb))
	tw.tween_property(vis, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
	tw.tween_callback(rb.queue_free)

# --- Вид ---

const FLASH_MATERIAL := preload("res://shaders/hit_flash.tres")
## П3: хруст при разрыве корма (tools/make_sfx.py, случайный из трёх)
const GIB_SOUNDS := "sounds/sfx/gib_crunch_1.wav,sounds/sfx/gib_crunch_2.wav,sounds/sfx/gib_crunch_3.wav"
const FLASH_GL_SHADER := preload("res://shaders/hit_flash_gl.gdshader")
const FLASH_MATERIAL_GL := preload("res://shaders/hit_flash_gl.tres")

# --- Функции компонентов, доступные на Enemy ---
# API (## API →) и приватные функции, которые зовут другие файлы (## совместимость →).
# Реализация и описание — в компоненте.

# EnemyNotice (enemy_notice.gd)

## API → notice.alert_to_player
func alert_to_player() -> void:
	notice.alert_to_player()

## API → notice.is_alert_to_player
func is_alert_to_player() -> bool:
	return notice.is_alert_to_player()

# EnemyFodderLod (enemy_fodder_lod.gd)

## совместимость → fodder_lod._fodder_lod_active
func _fodder_lod_active() -> bool:
	return fodder_lod._fodder_lod_active()

## совместимость → fodder_lod._think_chase_lod
func _think_chase_lod(delta: float) -> Vector3:
	return fodder_lod._think_chase_lod(delta)

# EnemyMotion (enemy_motion.gd)

## API → motion.apply_knockback_only
func apply_knockback_only(knockback: Vector3) -> Vector3:
	return motion.apply_knockback_only(knockback)

## совместимость → motion._below_fall_limit
func _below_fall_limit() -> bool:
	return motion._below_fall_limit()

# EnemyShield (enemy_shield.gd)

## API → shield.hit_breaks_armor
func hit_breaks_armor(source: String) -> bool:
	return shield.hit_breaks_armor(source)

# EnemyShaman (enemy_shaman.gd)

## API → shaman.summon_around
func summon_around(kind_name: String, count: int, cap: int) -> int:
	return shaman.summon_around(kind_name, count, cap)

# EnemyVisual (enemy_visual.gd)

## совместимость → visual._update_visual_feedback
func _update_visual_feedback(delta: float) -> void:
	visual._update_visual_feedback(delta)

## совместимость → visual._set_overlay
func _set_overlay(flash: float, glow: float) -> void:
	visual._set_overlay(flash, glow)
