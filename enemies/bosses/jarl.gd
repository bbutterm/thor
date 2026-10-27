extends BossEnemy
class_name JarlBoss
## Ярл Бьорн Мёртвый — босс Мидгарда (GDD 14.2), 60 У. Арена — длинный дом с балконами (rooms/boss_arena.tscn).
## Фаза 1 «Я ваш ярл!»: широкий замах рукой-дубиной, удар по площади, бросок руки бумерангом (JarlArm).
##   Пока рука летит (arm_window, 3 с) — он без руки: не бьёт, урон по нему ×window_damage_mult.
##   С рукой урон по нему ×armed_damage_mult (отмахивается).
## Фаза 2 «Пришить!» (с 66 % HP): прыгает на балкон (маркеры JarlPerches) и пришивает руку, из ворот
##   (маркеры FodderGates) лезут волны корма. Наверху его почти не ранить — сбить ударом-приземлением,
##   по головам или Мьёльниром: падает и оглушён (окно урона). Через perch_return_time снова наверх.
## Фаза 3 «Рагнарёк деревни!» (с 33 % HP): отваливаются обе руки, ломает все балконы (Balcony),
##   бодается (таран с полосой-телеграфом, о стену — оглушён) и прыгает с ударной волной (только по
##   стоящему на земле — прыгай).
## Поражение: голова укатывается, свита рассыпается. Реплики — data/dialogues/jarl.json.

enum Act { NONE, THROW, ARMLESS, LEAP, PERCH, KNOCKED, ROAR, BREAK, BUTT_AIM, BUTT, BUTT_STUN, BUTT_END, SLAM_LEAP }

@export_group("Ярл: фазы")
## Доли HP начала фаз 2 и 3 (GDD 14.2: 66 % и 33 %)
@export_range(0.0, 1.0) var phase2_at: float = 0.66
@export_range(0.0, 1.0) var phase3_at: float = 0.33
@export var roar_time: float = 1.2
@export_group("Ярл: рука-бумеранг (фаза 1–2)")
@export var throw_cooldown: float = 6.0
## Бросает, если Тор дальше этого (м); ближе — с шансом throw_close_chance за решение
@export var throw_min_dist: float = 6.0
@export_range(0.0, 1.0) var throw_close_chance: float = 0.004
@export var throw_windup: float = 0.75
@export var arm_damage: float = 20.0
## Окно урона: сколько летает рука и он без неё (GDD 14.2: 3 с)
@export var arm_window: float = 3.0
@export var arm_range: float = 16.0
## Урон по Ярлу с рукой (отмахивается) и в окнах (без руки, сбит, оглушён)
@export var armed_damage_mult: float = 0.7
@export var window_damage_mult: float = 1.5
@export_group("Ярл: балкон (фаза 2)")
@export var leap_time: float = 1.0
@export var leap_height: float = 4.0
## Наверху урон ×perch_damage_mult; удар-приземление, по головам, Мьёльнир, молния — сбивают
@export var perch_damage_mult: float = 0.2
@export var summon_interval: float = 5.0
@export var summon_count: int = 4
## Не зовёт корм, если врагов в зале столько или больше
@export var summon_cap: int = 16
## Сбит с балкона — оглушён (окно урона)
@export var knocked_stun: float = 3.0
## Через сколько секунд на земле снова лезет на балкон
@export var perch_return_time: float = 12.0
## Тор подошёл наверху ближе этого — отмахивается (урон, толкает с балкона)
@export var perch_swat_range: float = 2.6
@export var perch_swat_damage: float = 15.0
@export var perch_swat_cooldown: float = 1.8
@export_group("Ярл: ярость (фаза 3)")
@export var break_interval: float = 0.7
@export var butt_aim_time: float = 0.8
@export var butt_speed: float = 14.0
@export var butt_max_dist: float = 22.0
@export var butt_damage: float = 30.0
@export var butt_knock: float = 15.0
@export var butt_wall_stun: float = 2.0
@export var butt_cooldown: float = 2.5
@export var slam_leap_cooldown: float = 7.0
@export var slam_leap_time: float = 1.1
@export var slam_leap_radius: float = 5.0
@export var slam_leap_damage: float = 25.0
@export var phase3_move_mult: float = 1.25
@export_group("Ярл: анимации")
@export var anim_throw: String = "OverhandThrow"
@export var anim_armless: String = "Idle_No_Loop"
@export var anim_sew: String = "Fixing_Kneeling"
@export var anim_leap: String = "NinjaJump_Idle_Loop"
@export var anim_roar: String = "Idle_FoldArms_Loop"
@export var anim_butt: String = "Sprint_Loop"

## Удары, которые сбивают Ярла с балкона
const KNOCK_SOURCES := ["slam", "stomp", "hammer", "lightning"]
## Имя на полосе босса (ключ перевода — HUD показывает через tr)
const BOSS_TITLE := "ЯРЛ БЬОРН МЁРТВЫЙ"

var phase: int = 1
var _pending_phase: int = 1
var _throw_cd: float = 3.0
var _arm: JarlArm
var _armless: bool = false
var _leap_from: Vector3
var _leap_to: Vector3
var _leap_next: int = 0
var _perch: Marker3D
var _summon_t: float = 0.0
var _swat_cd: float = 0.0
var _perch_cd: float = 0.0
var _butt_cd: float = 2.0
var _slam_cd: float = 4.0
var _break_queue: Array = []
var _break_t: float = 0.0
var _arms_off: bool = false
var _base_speed: float = 0.0

func _ready() -> void:
	super._ready()
	set_meta("boss_title", BOSS_TITLE)
	set_meta("death_source_id", "boss_jarl")
	_base_speed = move_speed

func hp_frac() -> float:
	return health / maxf(max_health, 1.0)

func is_perched() -> bool:
	return act == Act.PERCH

func is_armless() -> bool:
	return _armless

# --- Мышление ---

## Фаза 3: без рук — обычных замахов нет, только подходит (таран и прыжок — _boss_think).
func _think_chase() -> Vector3:
	if phase < 3:
		return super._think_chase()
	if player == null or player.is_dead:
		return Vector3.ZERO
	var dir := dir_to_player()
	_face_dir(dir, get_physics_process_delta_time())
	return (dir + _separation()).normalized()

func _boss_think(delta: float) -> void:
	_throw_cd -= delta
	_perch_cd -= delta
	_butt_cd -= delta
	_slam_cd -= delta
	if not can_start_act():
		return
	if _pending_phase > phase:
		_advance_phase()
		return
	var dist := dist_to_player()
	match phase:
		1, 2:
			if phase == 2 and _perch_cd <= 0.0 and _pick_perch() != null:
				_leap_to_perch()
			elif _throw_cd <= 0.0 and (dist >= throw_min_dist or randf() < throw_close_chance) and _has_line_of_sight():
				_start_throw()
		3:
			if _slam_cd <= 0.0 and dist > 4.0:
				_start_slam_leap()
			elif _butt_cd <= 0.0 and dist > 3.0 and _has_line_of_sight():
				set_act(Act.BUTT_AIM)
				if _humanoid:
					_humanoid.play(anim_idle, 0.1, 2.0)
				Audio.play("sounds/sfx/enemy_growl.wav")

func _run_act(delta: float) -> void:
	match act:
		Act.THROW:
			_face_dir(dir_to_player(), delta * 1.2)
			_windup_glow = clampf(act_time / throw_windup, 0.0, 1.0)
			act_move(Vector3.ZERO, delta)
			if act_time >= throw_windup:
				_release_arm()
		Act.ARMLESS:
			# Без руки: топчется, ищет её глазами — окно урона
			act_move(Vector3.ZERO, delta)
			if not is_instance_valid(_arm) and act_time >= arm_window:
				_rearm()
		Act.LEAP, Act.SLAM_LEAP:
			var t := leap_time if act == Act.LEAP else slam_leap_time
			var k := clampf(act_time / t, 0.0, 1.0)
			var h := leap_height + maxf(0.0, _leap_to.y - _leap_from.y)
			global_position = _leap_from.lerp(_leap_to, k) + Vector3(0, sin(PI * k) * h, 0)
			velocity = Vector3.ZERO
			var d := _leap_to - _leap_from
			_face_dir(Vector3(d.x, 0, d.z).normalized(), delta)
			if k >= 1.0:
				_land()
		Act.PERCH:
			_run_perch(delta)
		Act.KNOCKED:
			act_move(Vector3.ZERO, delta)
			if _visual:
				_visual.rotation.z = sin(act_time * 12.0) * 0.07
			if act_time >= knocked_stun:
				if _visual:
					_visual.rotation.z = 0.0
				_perch_cd = perch_return_time
				set_act(0)
		Act.ROAR:
			act_move(Vector3.ZERO, delta)
			_windup_glow = 0.5 + 0.5 * sin(act_time * 10.0)
			if act_time >= roar_time:
				if phase >= 3:
					_begin_break()
				else:
					set_act(0)
		Act.BREAK:
			act_move(Vector3.ZERO, delta)
			_break_t -= delta
			if _break_t <= 0.0:
				_break_next()
		Act.BUTT_AIM:
			var k2 := act_time / butt_aim_time
			if k2 < 0.7:
				_face_dir(dir_to_player(), delta * 1.5)
			var dir := global_transform.basis.z
			_windup_glow = clampf(k2, 0.0, 1.0)
			strip_show(dir, clear_length(dir, butt_max_dist), 0.25 + 0.4 * k2)
			act_move(Vector3.ZERO, delta)
			if act_time >= butt_aim_time:
				charge_begin(dir)
				if _humanoid:
					_humanoid.play(anim_butt, 0.1, 1.6)
				Audio.play("sounds/sfx/dash.wav")
				set_act(Act.BUTT)
		Act.BUTT:
			match charge_step(delta, butt_speed, butt_max_dist, butt_damage, butt_knock):
				1:
					charge_wall_hit()
					_break_balcony_near(global_position, 4.0)
					if _humanoid:
						_humanoid.play(anim_stun, 0.05)
					set_act(Act.BUTT_STUN)
				2:
					set_act(Act.BUTT_END)
		Act.BUTT_STUN:
			act_move(Vector3.ZERO, delta)
			if act_time >= butt_wall_stun:
				_butt_cd = butt_cooldown
				set_act(0)
		Act.BUTT_END:
			act_move(Vector3.ZERO, delta)
			if act_time >= 0.5:
				_butt_cd = butt_cooldown
				set_act(0)

# --- Фазы ---

func _advance_phase() -> void:
	var to := _pending_phase
	if to >= 3 and phase < 3:
		phase = 3
		Perf.mark("jarl_phase3")
		bark("jarl.phase3")
		_drop_arms()
		move_speed = _base_speed * phase3_move_mult
		set_act(Act.ROAR)
		if _humanoid:
			_humanoid.play(anim_roar, 0.1)
	elif to == 2 and phase < 2:
		phase = 2
		Perf.mark("jarl_phase2")
		bark("jarl.phase2")
		_perch_cd = 0.0
		set_act(Act.ROAR)
		if _humanoid:
			_humanoid.play(anim_roar, 0.1)
	Audio.play("sounds/sfx/enemy_growl.wav")
	ComicFX.pop("slam", global_position + Vector3(0, 2.5 * model_scale, 0))

func _target_phase() -> int:
	var f := hp_frac()
	return 3 if f <= phase3_at else (2 if f <= phase2_at else 1)

# --- Рука-бумеранг ---

func _start_throw() -> void:
	Perf.mark("jarl_throw")
	set_act(Act.THROW)
	if _humanoid:
		var full := _humanoid.resolve(anim_throw)
		if full != "":
			var a := _humanoid.anim.get_animation(full)
			_humanoid.anim.play(full, 0.1, clampf(a.length * 0.55 / maxf(throw_windup, 0.1), 0.5, 3.0))

func _release_arm() -> void:
	var from := global_position + Vector3(0, 2.4, 0) + global_transform.basis.z * 0.8
	var target := player.global_position + Vector3(0, 1.0, 0) if player and is_instance_valid(player) else from + global_transform.basis.z * 10.0
	var to := target - from
	if to.length() > arm_range:
		target = from + to.normalized() * arm_range
	# Летит чуть дальше Тора (бумеранг), но не сквозь стену
	var hit := _ray(from, target + to.normalized() * 2.0, 1)
	if not hit.is_empty():
		target = hit.position - to.normalized() * 0.8
	else:
		target += to.normalized() * 2.0
	_arm = JarlArm.launch(get_parent(), self, from, target, arm_window, arm_damage)
	_set_armless(true)
	_throw_cd = throw_cooldown
	bark("jarl.throw")
	Audio.play("sounds/sfx/hammer_throw.wav" if ResourceLoader.exists("res://sounds/sfx/hammer_throw.wav") else "sounds/sfx/curse_throw.wav")
	set_act(Act.ARMLESS)
	if _humanoid:
		_humanoid.play(anim_armless, 0.2)

func _rearm() -> void:
	_set_armless(false)
	Audio.play("sounds/sfx/hammer_catch.wav" if ResourceLoader.exists("res://sounds/sfx/hammer_catch.wav") else "sounds/sfx/enemy_growl.wav")
	set_act(0)

## Рука в кисти (дубина) — видна/спрятана.
func _set_armless(on: bool) -> void:
	_armless = on
	if _humanoid and _humanoid.skeleton:
		for c in _humanoid.skeleton.get_children():
			if c is BoneAttachment3D and (c as BoneAttachment3D).bone_name == "hand_r":
				(c as Node3D).visible = not on

# --- Балкон (фаза 2) ---

func _perches() -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	var grp := get_parent().get_node_or_null("JarlPerches") if get_parent() else null
	if grp == null:
		return out
	for m in grp.get_children():
		if m is Marker3D and _balcony_at((m as Marker3D).global_position) != null:
			out.append(m as Marker3D)
	return out

func _balcony_at(p: Vector3) -> Balcony:
	for b in get_tree().get_nodes_in_group("balconies"):
		var bc := b as Balcony
		if bc and not bc.is_broken and not bc.is_queued_for_deletion() and bc.has_point_on_top(p):
			return bc
	return null

## Балкон подальше от Тора (чтобы пришлось лезть).
func _pick_perch() -> Marker3D:
	var best: Marker3D = null
	var best_d := -1.0
	for m in _perches():
		var d := m.global_position.distance_to(player.global_position) if player else 0.0
		if m != _perch and d > best_d:
			best_d = d
			best = m
	return best

func _leap_to_perch() -> void:
	var m := _pick_perch()
	if m == null:
		_perch_cd = 3.0
		return
	_perch = m
	_start_leap(m.global_position, Act.PERCH)
	bark("jarl.taunt")

func _start_leap(to: Vector3, next: int) -> void:
	Perf.mark("jarl_leap")
	_leap_from = global_position
	_leap_to = to
	_leap_next = next
	set_act(Act.LEAP)
	if _humanoid:
		_humanoid.play(anim_leap, 0.1)
	Audio.play("sounds/sfx/dash.wav")

func _land() -> void:
	global_position = _leap_to
	velocity = Vector3.ZERO
	FX.ring(get_parent(), global_position, 2.5, Color(0.6, 0.85, 1.0, 0.8), 0.3)
	Audio.play("sounds/sfx/boss_slam.wav")
	if player and is_instance_valid(player):
		player.camera_fx.add_trauma(0.3)
	if act == Act.SLAM_LEAP:
		_slam_land()
		return
	match _leap_next:
		Act.PERCH:
			set_act(Act.PERCH)
			_summon_t = 1.0
			if _humanoid:
				_humanoid.play(anim_sew, 0.2)
		Act.KNOCKED:
			set_act(Act.KNOCKED)
			if _humanoid:
				_humanoid.play(anim_stun, 0.05)
		_:
			if phase >= 3 and _pending_phase >= 3 and not _break_queue.is_empty():
				set_act(Act.BREAK)
			else:
				set_act(0)

func _run_perch(delta: float) -> void:
	act_move(Vector3.ZERO, delta)
	_face_dir(dir_to_player(), delta * 0.5)
	_windup_glow = 0.0
	# Балкон сломали под ним / настала фаза 3 — вниз
	if _perch == null or not is_instance_valid(_perch) or _balcony_at(_perch.global_position) == null or _pending_phase >= 3:
		_jump_down(false)
		return
	_summon_t -= delta
	if _summon_t <= 0.0:
		_summon_t = summon_interval
		_summon_fodder()
	_swat_cd -= delta
	if _swat_cd <= 0.0 and player and is_instance_valid(player) and not player.is_dead:
		var d := player.global_position - global_position
		if d.length() < perch_swat_range:
			_swat_cd = perch_swat_cooldown
			var out := Vector3(d.x, 0, d.z).normalized() if Vector2(d.x, d.z).length() > 0.05 else -global_transform.basis.z
			_hit_player(perch_swat_damage, out * shove_force + Vector3.UP * 4.0)
			FX.burst(get_parent(), global_position + Vector3(0, 1.5 * model_scale, 0) + out, 0.8, Color(1, 0.4, 0.2, 0.5), 0.15)
			Audio.play("sounds/enemy_attack.ogg")

## Зовёт корм из ворот (маркеры FodderGates; нет — вокруг себя внизу).
func _summon_fodder() -> void:
	var room := _room()
	if room == null or get_tree().get_nodes_in_group("enemies").size() >= summon_cap:
		return
	Perf.mark("jarl_summon")
	var gates: Array = []
	var grp := room.get_node_or_null("FodderGates")
	if grp:
		gates = grp.get_children()
	var made := 0
	for i in summon_count:
		var pos: Vector3
		if not gates.is_empty():
			var g := gates[randi() % gates.size()] as Node3D
			pos = g.global_position + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
		else:
			pos = Loot.floor_point(self, global_position + Vector3(randf_range(-5, 5), -2.0, randf_range(-5, 5)))
		var e: Enemy = room.call("spawn_extra", "fodder", pos)
		if e:
			e.set_meta("jarl_summon", true)
			made += 1
	if made > 0:
		FX.ring(get_parent(), global_position, 3.0, Color(0.5, 0.8, 1.0, 0.8), 0.4)
		Audio.play("sounds/sfx/enemy_growl.wav")

## Прыгнуть с балкона на пол перед ним. knocked — сбит (оглушён), иначе сам спрыгнул.
func _jump_down(knocked: bool) -> void:
	var pos := global_position
	var room_c: Vector3 = (get_parent() as Node3D).global_position if get_parent() is Node3D else Vector3.ZERO
	var toward := Vector3(room_c.x - pos.x, 0, 0).normalized()
	if toward.length() < 0.1:
		toward = -global_transform.basis.z
	var target := Loot.floor_point(self, pos + toward * 4.0 + Vector3(0, -1.0, 0))
	if target.y > pos.y - 1.0:
		target = Vector3(pos.x + toward.x * 4.0, room_c.y, pos.z + toward.z * 4.0)
	_perch = null
	_start_leap(target, Act.KNOCKED if knocked else 0)
	if knocked:
		act_time = leap_time * 0.35
		_leap_from = pos

# --- Ярость (фаза 3) ---

func _drop_arms() -> void:
	if _arms_off:
		return
	_arms_off = true
	_set_armless(true)
	if is_instance_valid(_arm):
		_arm.queue_free()
	# Обе руки — долой: кости плеч сжимаем (анимации их масштаб не трогают), на пол падают две дубины
	if _humanoid and _humanoid.skeleton:
		for bn in ["upperarm_l", "upperarm_r"]:
			var b := _humanoid.skeleton.find_bone(bn)
			if b >= 0:
				_humanoid.skeleton.set_bone_pose_scale(b, Vector3.ONE * 0.01)
	for side in [-1.0, 1.0]:
		var rb := RigidBody3D.new()
		rb.add_to_group("debris")
		rb.collision_layer = 1 << 6
		rb.collision_mask = 1 | (1 << 3) | (1 << 6)
		rb.mass = 3.0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.3, 1.4, 0.3)
		cs.shape = bs
		rb.add_child(cs)
		var club := WeaponMeshes.build("club")
		club.scale = Vector3.ONE * 2.2
		rb.add_child(club)
		get_parent().add_child(rb)
		rb.global_position = global_position + global_transform.basis.x * side * 1.0 * model_scale + Vector3(0, 2.6 * model_scale, 0)
		rb.apply_central_impulse((global_transform.basis.x * side * 3.0 + Vector3.UP * 2.0) * rb.mass)
		var tw := rb.create_tween()
		tw.tween_interval(6.0)
		tw.tween_property(club, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
		tw.tween_callback(rb.queue_free)

func _begin_break() -> void:
	_break_queue.clear()
	for b in get_tree().get_nodes_in_group("balconies"):
		if b is Balcony and not (b as Balcony).is_broken:
			_break_queue.append(b)
	# Ближние — первыми
	_break_queue.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
	_break_t = 0.0
	if _break_queue.is_empty():
		set_act(0)
	else:
		set_act(Act.BREAK)
		bark("jarl.balconies")

func _break_next() -> void:
	while not _break_queue.is_empty():
		var b: Variant = _break_queue.pop_front()
		if is_instance_valid(b) and not (b as Balcony).is_broken:
			(b as Balcony).break_apart()
			_stomp_fx()
			_break_t = break_interval
			return
	set_act(0)

func _stomp_fx() -> void:
	FX.ring(get_parent(), global_position, 4.0, Color(1, 0.5, 0.25, 0.85), 0.35)
	Audio.play("sounds/sfx/boss_slam.wav")
	if player and is_instance_valid(player):
		player.camera_fx.add_trauma(0.4)

func _break_balcony_near(pos: Vector3, radius: float) -> void:
	for b in get_tree().get_nodes_in_group("balconies"):
		var bc := b as Balcony
		if bc and not bc.is_broken:
			var tp := bc.top_point()
			if Vector2(tp.x - pos.x, tp.z - pos.z).length() < radius + 2.0:
				bc.break_apart()

func _start_slam_leap() -> void:
	Perf.mark("jarl_slam_leap")
	var target := Loot.floor_point(self, player.global_position) if player else global_position
	_leap_from = global_position
	_leap_to = target
	_leap_next = 0
	set_act(Act.SLAM_LEAP)
	boss_slam_radius = slam_leap_radius
	boss_slam_windup = slam_leap_time
	_show_slam_telegraph()
	if _telegraph:
		_telegraph.global_position = target + Vector3(0, 0.06, 0)
	if _humanoid:
		_humanoid.play(anim_leap, 0.1)
	Audio.play("sounds/sfx/enemy_growl.wav")

func _slam_land() -> void:
	_slam_cd = slam_leap_cooldown
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	FX.ring(get_parent(), global_position, slam_leap_radius, Color(1, 0.35, 0.2, 0.9), 0.4)
	FX.burst(get_parent(), global_position + Vector3(0, 0.5, 0), 1.8, Color(1, 0.4, 0.2, 0.4), 0.25)
	ComicFX.pop("slam", global_position + Vector3(0, 1.0, 0))
	if player and not player.is_dead:
		player.camera_fx.add_trauma(0.55)
		var d := player.global_position - global_position
		d.y = 0
		# Ударная волна — только по стоящему на земле (GDD 8: прыгай)
		if d.length() <= slam_leap_radius and player.is_on_floor():
			_hit_player(slam_leap_damage, d.normalized() * 10.0 + Vector3.UP * 6.0)
	_break_balcony_near(global_position, 3.0)
	set_act(0)

# --- Урон ---

func take_hit(damage: float, knockback: Vector3, source: String = "") -> void:
	if is_dead:
		return
	if damage < DEBUG_KILL_DAMAGE:
		match act:
			Act.PERCH:
				if source in KNOCK_SOURCES:
					super.take_hit(damage, Vector3.ZERO, source)
					if not is_dead:
						_knock_off()
					return
				damage *= perch_damage_mult
				knockback = Vector3.ZERO
			Act.ARMLESS, Act.KNOCKED, Act.BUTT_STUN:
				damage *= window_damage_mult
			Act.LEAP, Act.SLAM_LEAP, Act.ROAR, Act.BREAK:
				pass
			_:
				if phase < 3 and not _armless:
					damage *= armed_damage_mult
	super.take_hit(damage, knockback, source)
	if not is_dead:
		_pending_phase = maxi(_pending_phase, _target_phase())
		# Сидит на балконе, а пора в фазу 3 — _run_perch сам спрыгнет

func _knock_off() -> void:
	Perf.mark("jarl_knocked")
	bark("jarl.knocked")
	ComicFX.pop("slam", global_position + Vector3(0, 2.0 * model_scale, 0))
	_jump_down(true)

func _die(source: String) -> void:
	if is_dead:
		return
	if is_instance_valid(_arm):
		_arm.queue_free()
	var room := _room()
	var pos := global_position
	_spawn_rolling_head()
	super._die(source)
	# Свита без ярла рассыпается (без Славы — как подрыв); зал зачищается — победа
	if room:
		for e in (room.call("alive_enemies") as Array).duplicate():
			var en := e as Enemy
			if en and is_instance_valid(en) and not en.is_dead and en != self:
				FX.burst(en.get_parent(), en.global_position + Vector3(0, 1.0, 0), 0.8, Color(0.6, 0.8, 1.0, 0.4), 0.3)
				en._die("self_blast")
	FX.ring(get_parent(), pos, 6.0, Color(0.5, 0.85, 1.0, 0.9), 0.6)

## «Голова укатывается» (GDD 14.2): у трупа голова пропадает (кость сжата), отдельная голова катится прочь.
## Голова — тот же персонаж (тело и борода, те же общие покрашенные материалы), у которого сжаты все кости,
## кроме шеи и головы.
func _spawn_rolling_head() -> void:
	if _humanoid == null or _humanoid.skeleton == null or not is_inside_tree():
		return
	Perf.mark("jarl_head")
	var sk := _humanoid.skeleton
	var head_bone := sk.find_bone("Head")
	if head_bone < 0:
		return
	sk.set_bone_pose_scale(head_bone, Vector3.ONE * 0.01)
	var rb := RigidBody3D.new()
	rb.name = "JarlHead"
	rb.add_to_group("debris")
	rb.collision_layer = 1 << 6
	rb.collision_mask = 1 | (1 << 3) | (1 << 6)
	rb.mass = 2.0
	rb.angular_damp = 0.3
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 0.16 * model_scale
	cs.shape = ss
	rb.add_child(cs)
	var h := HumanoidModel.new()
	h.body = _humanoid.body
	h.outfit = ""
	h.hair = _humanoid.hair
	h.skin_tint = _humanoid.skin_tint
	h.cloth_tint = _humanoid.cloth_tint
	h.eye_glow = _humanoid.eye_glow
	rb.add_child(h)
	get_parent().add_child(rb)
	var head_pos := sk.global_transform * sk.get_bone_global_pose(head_bone).origin
	rb.global_position = head_pos
	h.scale = Vector3.ONE * model_scale
	if h.skeleton:
		var hs := h.skeleton
		var pelvis := hs.find_bone("pelvis")
		var neck := hs.find_bone("neck_01")
		if pelvis >= 0 and neck >= 0:
			hs.set_bone_pose_scale(pelvis, Vector3.ONE * 0.01)
			hs.set_bone_pose_scale(neck, Vector3.ONE * 100.0)
		var hb := hs.find_bone("Head")
		if hb >= 0:
			# Центр головы — в центр шара
			var c := hs.get_bone_global_pose(hb).origin + Vector3(0, 0.12, 0)
			h.position = -c * model_scale
	var side := global_transform.basis.x * (1.0 if randf() < 0.5 else -1.0)
	rb.apply_central_impulse((side * 2.5 + global_transform.basis.z * 1.5 + Vector3.UP * 2.0) * rb.mass)
	rb.apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * rb.mass)
	var tw := rb.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(h, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
	tw.tween_callback(rb.queue_free)
