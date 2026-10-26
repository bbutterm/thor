extends Enemy
class_name BossEnemy
## Основа боссов со своими атаками (Толстый Свен, Ярл Бьорн): поверх обычного врага (Kind.BOSS) —
## «действия» (act): таран с телеграфом-полосой на полу, прыжки, оглушение об стену и т. п.
## Пока действия нет (act == 0) — работает обычный ИИ врага (подход, замах, удар по площади), а подкласс
## в _boss_think() решает, когда начать своё. Во время действия обычный ИИ стоит, движением управляет подкласс.

## Таран не задевает Тора, если его ноги выше этого над землёй (м) — таран можно перепрыгнуть
@export var charge_jump_clear: float = 1.0

## Действие 0 — «нет», остальные номера задаёт подкласс
var act: int = 0
var act_time: float = 0.0
var _strip: MeshInstance3D
## Таран: направление, пройденный путь, попал ли уже по Тору
var _charge_dir: Vector3 = Vector3.FORWARD
var _charge_dist: float = 0.0
var _charge_hit: bool = false
## Тор на время тарана — исключение коллизий (таран проходит сквозь него, а не упирается)
var _charge_exc: Node = null
## Сколько секунд подряд таран почти не двигается (упёрся в бочку/свиту)
var _charge_stuck_t: float = 0.0

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Player
	if act == 0:
		super._physics_process(delta)
		if not is_dead and act == 0:
			_boss_think(delta)
		return
	act_time += delta
	_run_act(delta)
	if is_dead:
		return
	_update_visual_feedback(delta)
	if global_position.y < -30.0:
		_die("fall")

## Подкласс: решить, не начать ли своё действие (вызывается каждый кадр, пока act == 0).
func _boss_think(_delta: float) -> void:
	pass

## Подкласс: кадр текущего действия.
func _run_act(_delta: float) -> void:
	pass

func set_act(a: int) -> void:
	act = a
	act_time = 0.0
	if a == 0:
		_windup_glow = 0.0
		_set_state(State.CHASE)
	else:
		# Обычный замах (если был) отменяется
		if _telegraph and is_instance_valid(_telegraph):
			_telegraph.queue_free()
		_doing_slam = false
		_set_state(State.RECOVER)

## Можно ли начать действие сейчас: обычный ИИ в погоне (не посреди замаха/восстановления).
func can_start_act() -> bool:
	return act == 0 and state == State.CHASE and player != null and is_instance_valid(player) and not player.is_dead

func dir_to_player() -> Vector3:
	if player == null or not is_instance_valid(player):
		return global_transform.basis.z
	var d := player.global_position - global_position
	d.y = 0
	return d.normalized() if d.length() > 0.01 else global_transform.basis.z

func dist_to_player() -> float:
	if player == null or not is_instance_valid(player):
		return INF
	var d := player.global_position - global_position
	d.y = 0
	return d.length()

## Движение во время действия: горизонтальная скорость задаётся, гравитация и отбрасывание — как обычно.
## Возвращает нормаль стены, в которую упёрлись (Vector3.ZERO — не упёрлись).
func act_move(horiz: Vector3, delta: float) -> Vector3:
	knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, clampf(knock_decay * delta, 0.0, 1.0))
	var h := horiz + Vector3(knockback_velocity.x, 0, knockback_velocity.z)
	velocity.x = h.x
	velocity.z = h.z
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0:
		velocity.y = -0.5
	move_and_slide()
	var wall := Vector3.ZERO
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		var rb := other as RigidBody3D
		if rb:
			# Бочки и ящики разлетаются от тарана
			var push := horiz.length() * 0.45
			rb.apply_central_impulse((-col.get_normal() * Vector3(1, 0, 1)).normalized() * push * rb.mass + Vector3.UP * 2.0 * rb.mass)
			continue
		var n := col.get_normal()
		if absf(n.y) > 0.5 or other is CharacterBody3D:
			continue
		if horiz.length() > 0.1 and horiz.normalized().dot(-n) > 0.5:
			wall = n
	return wall

# --- Таран (бочка Свена, «бодается» Ярла) ---

## Начать таран в направлении dir.
func charge_begin(dir: Vector3) -> void:
	_charge_dir = Vector3(dir.x, 0, dir.z).normalized()
	_charge_dist = 0.0
	_charge_hit = false
	_charge_stuck_t = 0.0
	strip_hide()
	if player and is_instance_valid(player) and _charge_exc == null:
		add_collision_exception_with(player)
		_charge_exc = player

## Таран закончился — Тор снова твёрдый.
func charge_end() -> void:
	if _charge_exc and is_instance_valid(_charge_exc):
		remove_collision_exception_with(_charge_exc)
	_charge_exc = null

## Шаг тарана. Возвращает: 0 — едем дальше, 1 — врезался в стену, 2 — путь пройден.
func charge_step(delta: float, speed: float, max_dist: float, damage: float, knock: float) -> int:
	var before := global_position
	var wall := act_move(_charge_dir * speed, delta)
	_face_dir(_charge_dir, delta * 3.0)
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_charge_dist += moved
	# По Тору — один раз за таран
	if not _charge_hit and player and is_instance_valid(player) and not player.is_dead:
		var to_p := player.global_position - global_position
		var flat := Vector3(to_p.x, 0, to_p.z)
		# Перепрыгнул (ноги выше charge_jump_clear над землёй) — мимо
		if flat.length() < 1.1 * model_scale + 0.6 and to_p.y < charge_jump_clear and to_p.y > -1.2:
			_charge_hit = true
			var side := _charge_dir.cross(Vector3.UP)
			var away := side * signf(side.dot(flat) + 0.001)
			_hit_player(damage, (_charge_dir * 0.7 + away * 0.5).normalized() * knock + Vector3.UP * 5.0)
			if player:
				player.camera_fx.add_trauma(0.5)
	# Своих — расталкивает
	for e in _enemies_now():
		var en := e as Enemy
		if en == null or en == self or not is_instance_valid(en) or en.is_dead:
			continue
		var d := en.global_position - global_position
		d.y = 0
		if d.length() < 1.0 * model_scale + 0.6:
			var side2 := _charge_dir.cross(Vector3.UP)
			en.knockback_velocity += (side2 * signf(side2.dot(d) + 0.001) * 9.0 + _charge_dir * 4.0)
	_charge_stuck_t = _charge_stuck_t + delta if moved < speed * delta * 0.15 else 0.0
	if wall != Vector3.ZERO and _charge_dist > 0.5:
		charge_end()
		return 1
	if _charge_dist >= max_dist or _charge_stuck_t > 0.25:
		charge_end()
		return 2
	return 0

## Врезался в стену: удар, тряска, пыль.
func charge_wall_hit() -> void:
	Perf.mark("boss_wall_hit")
	var pos := global_position + _charge_dir * 0.8 * model_scale + Vector3(0, 1.0 * model_scale, 0)
	FX.burst(get_parent(), pos, 1.2, Color(1, 0.95, 0.8, 0.6), 0.25)
	FX.sparks(get_parent(), pos, Color(1.0, 0.85, 0.5), 16, 7.0)
	Audio.play("sounds/sfx/wall_splat.wav")
	ComicFX.pop("slam", pos)
	if player and is_instance_valid(player):
		player.camera_fx.add_trauma(0.35)
	knockback_velocity = -_charge_dir * 4.0

# --- Телеграф: полоса на полу по направлению тарана ---

func strip_show(dir: Vector3, length: float, alpha: float, color: Color = Color(1, 0.2, 0.1)) -> void:
	if _strip == null or not is_instance_valid(_strip):
		Perf.mark("boss_strip")
		_strip = MeshInstance3D.new()
		_strip.name = "ChargeStrip"
		_strip.mesh = FX.shared_mesh("box")
		FX.fx_apply(_strip, "alpha", color, 1.4)
		_strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_strip.top_level = true
		add_child(_strip)
	var d := Vector3(dir.x, 0, dir.z).normalized()
	if d.length() < 0.01:
		return
	_strip.visible = true
	var ground := global_position + Vector3(0, 0.07, 0)
	_strip.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP), ground + d * length * 0.5)
	_strip.scale = Vector3(1.0 * model_scale, 0.03, length)
	_strip.transparency = 1.0 - clampf(alpha, 0.0, 1.0)

func strip_hide() -> void:
	if _strip and is_instance_valid(_strip):
		_strip.visible = false

## Свободная длина пути по полу в направлении dir (до стены), не больше max_len.
func clear_length(dir: Vector3, max_len: float) -> float:
	var from := global_position + Vector3(0, 0.9, 0)
	var hit := _ray(from, from + dir.normalized() * max_len, 1)
	return from.distance_to(hit.position) if not hit.is_empty() else max_len

## Реплика босса пузырём (пул data/dialogues/<файл>.<имя>).
func bark(pool: String) -> void:
	if Dialogue.has_pool(pool):
		Dialogue.bark_pool(pool)

func _die(source: String) -> void:
	if is_dead:
		return
	strip_hide()
	charge_end()
	super._die(source)

## Образец для прогрева шейдеров (полоса телеграфа).
func warmup_strip() -> void:
	strip_show(global_transform.basis.z, 3.0, 0.5)
