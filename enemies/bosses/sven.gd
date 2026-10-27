extends BossEnemy
class_name FatSven
## Толстый Свен — мини-босс Мидгарда (GDD 14.1): раздутый драугр с бочкой пива.
## - Катается на бочке: встаёт, красная полоса на полу показывает путь (телеграф), потом таранный проезд.
##   Врезался в стену — оглушён (окно урона). Бочки и свиту по пути раскидывает.
## - Плюётся брагой: дуга из нескольких плевков, на полу — лужи (BrewPuddle), они замедляют Тора.
## - При низком HP раздувается, светится и бежит к Тору; вплотную — фитиль (красный круг) и взрыв (Blast).
##   Взрыв — его конец: увернулся рывком — победа. Убил раньше — всё равно бахнет (слабее).
## Характеристики (HP, урон, вид) перекрывает MinibossDef (enemies/minibosses/fat_sven.tres).

enum Act { NONE, CHARGE_AIM, CHARGE, CHARGE_STUN, CHARGE_END, SPIT, SWELL, FUSE }

@export_group("Свен: бочка")
## Телеграф тарана: полоса на полу (с); последние charge_lock_at доли — направление уже не меняется
@export var charge_aim_time: float = 0.9
@export_range(0.0, 1.0) var charge_lock_at: float = 0.7
@export var charge_speed: float = 15.0
@export var charge_max_dist: float = 20.0
@export var charge_damage: float = 22.0
@export var charge_knock: float = 13.0
## Врезался в стену — оглушён на столько секунд (окно урона)
@export var charge_wall_stun: float = 1.8
@export var charge_cooldown: float = 6.0
## Таранит, только если Тор не ближе этого (м)
@export var charge_min_dist: float = 4.5
@export_group("Свен: брага")
@export var spit_cooldown: float = 5.0
@export var spit_windup: float = 0.65
@export var spit_count: int = 3
## Разброс луж вокруг Тора (м)
@export var spit_spread: float = 2.4
@export var spit_flight_time: float = 0.85
@export var spit_arc: float = 3.0
@export var spit_damage: float = 6.0
@export var puddle_radius: float = 1.8
@export var puddle_time: float = 7.0
## Скорость Тора в луже — доля от обычной
@export_range(0.1, 1.0) var puddle_slow: float = 0.55
@export_group("Свен: раздувание")
## С какой доли HP раздувается и бежит взрываться
@export_range(0.0, 1.0) var swell_hp_fraction: float = 0.25
@export var swell_speed_mult: float = 1.4
## Сколько бежит, прежде чем всё равно поджечь фитиль (с)
@export var swell_max_time: float = 6.0
## На сколько раздувается к взрыву
@export var swell_amount: float = 0.5
@export var fuse_range: float = 3.0
## Фитиль: красный круг на полу растёт столько секунд — время увернуться рывком
@export var fuse_time: float = 1.1
@export var blast_radius: float = 5.0
@export var blast_damage: float = 30.0
## Убит до взрыва (во время раздувания) — взрыв слабее и быстрее
@export_range(0.0, 1.0) var death_blast_mult: float = 0.6
@export_group("Свен: вид")
@export var barrel_scale: float = 1.15
@export var anim_ride: String = "Driving_Loop"
@export var anim_spit: String = "Consume"
@export var anim_swell_run: String = "Jog_Fwd_Loop"

const BARREL_MODEL := "res://assets/quaternius/props/Barrel.gltf"

var _charge_cd: float = 3.0
var _spit_cd: float = 2.0
var _swollen: bool = false
var _base_visual_scale: Vector3 = Vector3.ZERO
var _barrel_pivot: Node3D
var _barrel_back: Vector3
var _barrel_r: float = 0.45

func _ready() -> void:
	super._ready()
	set_meta("death_source_id", "miniboss_sven")
	_build_barrel()

# --- Бочка: на спине, а при таране — под ним и катится ---

func _build_barrel() -> void:
	if not ResourceLoader.exists(BARREL_MODEL):
		return
	_barrel_pivot = Node3D.new()
	_barrel_pivot.name = "Barrel"
	add_child(_barrel_pivot)
	var model := (load(BARREL_MODEL) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	_barrel_pivot.add_child(model)
	var s := barrel_scale * model_scale
	model.scale = Vector3.ONE * s
	# Модель стоит на дне (высота ≈ 0.9 м, диаметр ≈ 0.7 м): центр — в пивот
	model.position = Vector3(0, -0.45 * s, 0)
	_barrel_r = 0.36 * s
	_barrel_back = Vector3(0, 1.25 * model_scale, -0.5 * model_scale)
	_barrel_on_back()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		_flash_meshes.append(mi as GeometryInstance3D)
	Outline.add(model)

func _barrel_on_back() -> void:
	if _barrel_pivot == null:
		return
	_barrel_pivot.position = _barrel_back
	_barrel_pivot.rotation = Vector3(deg_to_rad(15), 0, 0)
	if _visual:
		_visual.position.y = 0.0

func _barrel_under() -> void:
	if _barrel_pivot == null:
		return
	# Лёжа (ось вдоль X — катится вперёд), Свен сидит сверху
	_barrel_pivot.position = Vector3(0, _barrel_r, 0.1 * model_scale)
	_barrel_pivot.rotation = Vector3(0, 0, PI / 2)
	if _visual:
		_visual.position.y = _barrel_r * 1.2

func _roll_barrel(speed: float, delta: float) -> void:
	if _barrel_pivot:
		_barrel_pivot.rotate_object_local(Vector3.UP, -speed / maxf(_barrel_r, 0.1) * delta)

# --- Мышление ---

func _boss_think(delta: float) -> void:
	_charge_cd -= delta
	_spit_cd -= delta
	if not can_start_act():
		return
	var dist := dist_to_player()
	if _charge_cd <= 0.0 and dist >= charge_min_dist and _has_line_of_sight():
		_start_charge_aim()
	elif _spit_cd <= 0.0 and dist >= 3.0:
		_start_spit()

func _run_act(delta: float) -> void:
	match act:
		Act.CHARGE_AIM:
			var k := act_time / charge_aim_time
			if k < charge_lock_at:
				_face_dir(dir_to_player(), delta * 1.5)
			var dir := global_transform.basis.z
			_windup_glow = clampf(k, 0.0, 1.0)
			strip_show(dir, clear_length(dir, charge_max_dist), 0.25 + 0.4 * k)
			act_move(Vector3.ZERO, delta)
			if act_time >= charge_aim_time:
				charge_begin(dir)
				Audio.play("sounds/sfx/dash.wav")
				ComicFX.pop("slam", global_position + Vector3(0, 1.5 * model_scale, 0))
				set_act(Act.CHARGE)
		Act.CHARGE:
			_roll_barrel(charge_speed, delta)
			match charge_step(delta, charge_speed, charge_max_dist, charge_damage, charge_knock):
				1:
					charge_wall_hit()
					_barrel_on_back()
					if _humanoid:
						_humanoid.play(anim_stun, 0.05)
					set_act(Act.CHARGE_STUN)
				2:
					_barrel_on_back()
					set_act(Act.CHARGE_END)
		Act.CHARGE_STUN:
			act_move(Vector3.ZERO, delta)
			if _visual:
				_visual.rotation.z = sin(act_time * 14.0) * 0.08
			if act_time >= charge_wall_stun:
				if _visual:
					_visual.rotation.z = 0.0
				_end_act(charge_cooldown)
		Act.CHARGE_END:
			act_move(Vector3.ZERO, delta)
			if act_time >= 0.5:
				_end_act(charge_cooldown)
		Act.SPIT:
			_face_dir(dir_to_player(), delta * 0.8)
			_windup_glow = clampf(act_time / spit_windup, 0.0, 1.0) * 0.6
			act_move(Vector3.ZERO, delta)
			if act_time >= spit_windup:
				_do_spit()
				_spit_cd = spit_cooldown
				_charge_cd = maxf(_charge_cd, 1.2)
				set_act(0)
		Act.SWELL:
			# Сразу заметно толще и растёт дальше, пока бежит
			_update_swell(0.3 + 0.3 * clampf(act_time / 2.0, 0.0, 1.0))
			_windup_glow = 0.3 + 0.2 * sin(act_time * 8.0)
			var d := dir_to_player()
			_face_dir(d, delta)
			act_move(d * move_speed * swell_speed_mult + _separation(), delta)
			if _humanoid:
				_humanoid.play(anim_swell_run, 0.2, clampf(move_speed * swell_speed_mult / 3.2, 0.5, 2.5))
			if dist_to_player() <= fuse_range or act_time >= swell_max_time:
				_start_fuse()
		Act.FUSE:
			act_move(Vector3.ZERO, delta)
			_update_swell(0.6 + 0.4 * clampf(act_time / fuse_time, 0.0, 1.0))
			_windup_glow = clampf(act_time / fuse_time, 0.0, 1.0)
			if act_time >= fuse_time:
				_explode(1.0)

func _end_act(cd: float) -> void:
	_charge_cd = cd
	_spit_cd = maxf(_spit_cd, 1.0)
	set_act(0)

func _start_charge_aim() -> void:
	Perf.mark("sven_charge")
	set_act(Act.CHARGE_AIM)
	_barrel_under()
	if _humanoid:
		_humanoid.play(anim_ride, 0.15)
	Audio.play("sounds/sfx/enemy_growl.wav")

func _start_spit() -> void:
	Perf.mark("sven_spit")
	set_act(Act.SPIT)
	if _humanoid:
		var full := _humanoid.resolve(anim_spit)
		if full != "":
			_humanoid.anim.play(full, 0.1, clampf(_humanoid.anim.get_animation(full).length / maxf(spit_windup * 1.6, 0.1), 0.5, 3.0))

func _do_spit() -> void:
	if player == null or not is_instance_valid(player):
		return
	var mouth := global_position + Vector3(0, 1.6 * model_scale, 0) + global_transform.basis.z * 0.5 * model_scale
	var target := player.global_position + Vector3(player.velocity.x, 0, player.velocity.z) * 0.4
	for i in spit_count:
		var off := Vector3.ZERO if i == 0 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(0.6, 1.0) * spit_spread
		var g := BrewGlob.launch(get_parent(), mouth, target + off, spit_flight_time * randf_range(0.9, 1.1), spit_arc, self)
		g.damage = spit_damage
		g.puddle_radius = puddle_radius
		g.puddle_time = puddle_time
		g.puddle_slow = puddle_slow
	Audio.play("sounds/sfx/curse_throw.wav")

# --- Раздувание и взрыв ---

func take_hit(damage: float, knockback: Vector3, source: String = "") -> void:
	if is_dead:
		return
	# Оглушён о стену — бить больнее (окно урона)
	if act == Act.CHARGE_STUN and damage < DEBUG_KILL_DAMAGE:
		damage *= 1.5
	super.take_hit(damage, knockback, source)
	if not is_dead and not _swollen and health <= max_health * swell_hp_fraction:
		_start_swell()

func _start_swell() -> void:
	Perf.mark("sven_swell")
	_swollen = true
	strip_hide()
	_barrel_on_back()
	if _barrel_pivot:
		_barrel_pivot.visible = false
	set_act(Act.SWELL)
	bark("sven.swell")
	Audio.play("sounds/sfx/enemy_growl.wav")
	ComicFX.pop("slam", global_position + Vector3(0, 2.0 * model_scale, 0))

func _update_swell(k: float) -> void:
	if _visual == null:
		return
	if _base_visual_scale == Vector3.ZERO:
		_base_visual_scale = _visual.scale
	var s := 1.0 + swell_amount * k
	_visual.scale = Vector3(_base_visual_scale.x * s, _base_visual_scale.y * (1.0 + swell_amount * 0.4 * k), _base_visual_scale.z * s)

func _start_fuse() -> void:
	Perf.mark("sven_fuse")
	set_act(Act.FUSE)
	boss_slam_radius = blast_radius
	boss_slam_windup = fuse_time
	_show_slam_telegraph()
	if _humanoid:
		_humanoid.play(anim_idle, 0.1, 2.5)
	Audio.play("sounds/sfx/enemy_growl.wav")

func _explode(mult: float) -> void:
	if is_dead:
		return
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	Blast.detonate(get_parent(), global_position + Vector3(0, 0.9 * model_scale, 0), blast_radius * lerpf(0.7, 1.0, mult), blast_damage * mult, self, self, Color(1.0, 0.6, 0.15))
	if player and is_instance_valid(player):
		player.camera_fx.add_trauma(0.6)
	_die("sven_blast")

func _die(source: String) -> void:
	if is_dead:
		return
	# Убит, пока раздувался, — всё равно бахнет (слабее), с коротким телеграфом
	if act in [Act.SWELL, Act.FUSE] and source != "sven_blast" and is_inside_tree():
		Blast.delayed(get_parent(), global_position, blast_radius * 0.7, blast_damage * death_blast_mult, 0.45, null, Color(1.0, 0.6, 0.15))
	super._die(source)
