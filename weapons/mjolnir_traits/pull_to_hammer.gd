extends MjolnirTraitHandler
## Приём «Притяжение к молоту» (группа «к молоту» — вместе с Обменом не берётся): по ПКМ не молот летит к тебе, а ты к нему, сбивая всех на пути.
## Способ перемещения: метни молот в стену у края башни — и «дёрни» себя наверх.
## На время полёта у игрока выключен его _physics_process — двигаем его сами (player.gd не трогаем).
## Возврат по таймеру — обычный (молот летит к руке), тянет только ПКМ.

@export var speed: float = 30.0
## Дольше этого не летим (с)
@export var max_time: float = 1.2
@export var hit_radius: float = 1.6
## 1 У
@export var damage: float = 22.0
@export var knockback: float = 11.0
## Скорость вверх в конце (если уступа над молотом нет)
@export var exit_up: float = 10.0
@export var exit_forward: float = 5.0
## Молот в стене, а над ним уступ не выше этого (м) — игрока перекидывает на уступ (залезание)
@export var mantle_height: float = 2.2
## Сколько воткнутый молот ждёт ПКМ — только при старом автовозврате (FeelSwitch hammer_recall); по умолчанию ждёт ПКМ всегда
@export var stuck_hold: float = 3.0
## Ур. 2: мини-удар-приземление на прилёте
@export var arrive_slam_radius: float = 3.5
@export var arrive_slam_damage: float = 22.0
@export var arrive_slam_knockback: float = 10.0

var _proj: MjolnirProjectile = null
var _saved_mask: int = 0
var _hit: Dictionary = {}
var _t: float = 0.0
var _stall: float = 0.0
var _dir: Vector3 = Vector3.FORWARD
## Точка на уступе над молотом (если есть) и фаза: 0 — к молоту, 1 — на уступ
var _mantle: Vector3 = Vector3.INF
var _phase: int = 0

func modify(stat: StringName, value: Variant) -> Variant:
	if stat == &"stuck_auto_return" and float(value) > 0.0:
		return maxf(float(value), stuck_hold)
	return value

func on_recall_start(proj: MjolnirProjectile, by_player: bool) -> void:
	var p := hand.player
	if not by_player or p == null or p.is_dead or _proj != null:
		return
	if not proj.take_recall_control(self):
		return
	mark()
	_proj = proj
	_t = 0.0
	_stall = 0.0
	_hit.clear()
	proj.vel = Vector3.ZERO
	_phase = 0
	_mantle = _find_ledge(proj)
	p.set_physics_process(false)
	_saved_mask = p.collision_mask
	# Сквозь врагов и бочки — их сбиваем сами
	p.collision_mask = 1
	p.camera_fx.kick_fov(12.0)
	p.camera_fx.speed_lines_pulse()
	Audio.play("sounds/sfx/dash.wav")

func is_pulling() -> bool:
	return _proj != null

## Молот в стене: есть ли сверху ровная площадка (край башни, платформы), куда можно залезть
func _find_ledge(proj: MjolnirProjectile) -> Vector3:
	if not proj.recalled_from_stuck or absf(proj.stuck_normal.y) > 0.6:
		return Vector3.INF
	var n := Vector3(proj.stuck_normal.x, 0, proj.stuck_normal.z).normalized()
	var surface := proj.global_position - proj.stuck_normal * 0.38
	var from := surface - n * 0.6 + Vector3.UP * mantle_height
	var space := proj.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, surface - n * 0.6 - Vector3.UP * 0.2, 1))
	if hit.is_empty() or (hit.normal as Vector3).y < 0.7:
		return Vector3.INF
	# Над площадкой должно хватать места для игрока
	var head := space.intersect_ray(PhysicsRayQueryParameters3D.create(hit.position + Vector3.UP * 0.1, hit.position + Vector3.UP * 1.9, 1))
	if not head.is_empty():
		return Vector3.INF
	return (hit.position as Vector3) - n * 0.4 + Vector3.UP * 0.05

func _target(proj: MjolnirProjectile) -> Vector3:
	if _phase == 1:
		return _mantle
	var hp := proj.global_position
	if proj.recalled_from_stuck:
		var n := proj.stuck_normal
		if n.y > 0.6:
			return hp + Vector3(0, 0.05, 0)
		return hp + Vector3(n.x, 0, n.z).normalized() * 0.7 - Vector3(0, 1.0, 0)
	return hp - Vector3(0, 1.1, 0)

func control_recall_tick(proj: MjolnirProjectile, delta: float) -> void:
	var p := hand.player
	if p == null or p.is_dead:
		_finish(proj, false)
		return
	_t += delta
	var target := _target(proj)
	var to := target - p.global_position
	var d := to.length()
	if _phase == 0 and _mantle != Vector3.INF and (d < 0.5 or _stall > 0.1):
		# Долетели до молота в стене — перекидываемся на уступ над ним
		_phase = 1
		_stall = 0.0
		return
	if d < 0.5 or _t > max_time or _stall > 0.15:
		_finish(proj, true)
		return
	var aim: Vector3
	if _phase == 1 and p.global_position.y < _mantle.y + 0.15:
		# Сначала вверх вдоль стены, потом вперёд на площадку
		aim = Vector3(p.global_position.x, _mantle.y + 0.6, p.global_position.z)
	else:
		# Чуть выше цели — дуга, чтобы перевалить через край
		aim = target + Vector3.UP * clampf(d * 0.2, 0.0, 1.2)
	_dir = (aim - p.global_position).normalized()
	var step_speed := minf(speed * (0.6 if _phase == 1 else 1.0), (aim - p.global_position).length() / maxf(delta, 0.0001))
	var before := p.global_position
	p.velocity = _dir * step_speed
	p.move_and_slide()
	var moved := p.global_position.distance_to(before)
	_stall = _stall + delta if moved < step_speed * delta * 0.2 else 0.0
	for e in enemies_near(p.get_tree(), p.global_position + Vector3(0, 0.9, 0), hit_radius):
		var id := e.get_instance_id()
		if _hit.has(id):
			continue
		_hit[id] = true
		var side := e.global_position - p.global_position
		side.y = 0
		side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
		var flat := Vector3(_dir.x, 0, _dir.z)
		hurt(e, damage * proj.damage_mult, (side + flat * 0.5).normalized() * knockback + Vector3.UP * 4.0, "hammer")
		FX.hitstop(0.03)
		p.camera_fx.add_trauma(0.12)
		Audio.play("sounds/sfx/hammer_hit.wav")

func _finish(proj: MjolnirProjectile, arrived: bool) -> void:
	var p := hand.player
	_restore()
	if arrived and p and not p.is_dead:
		var flat := Vector3(_dir.x, 0, _dir.z)
		flat = flat.normalized() if flat.length() > 0.01 else Vector3.ZERO
		if _phase == 1:
			# Залезли на уступ — мягко
			p.velocity = flat * exit_forward * 0.5
		else:
			p.velocity = flat * exit_forward + Vector3.UP * exit_up
		if level >= 2:
			_arrive_slam(p)
		# Связки (Ветер + Притяжение — снос толпы на прилёте)
		hand.trait_call(&"on_pull_arrive", [hand, p.global_position])
	proj.catch()

func _arrive_slam(p: Player) -> void:
	mark("slam")
	var center := p.global_position
	for e in enemies_near(p.get_tree(), center + Vector3(0, 0.9, 0), arrive_slam_radius):
		var dir := e.global_position - center
		dir.y = 0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
		hurt(e, arrive_slam_damage, dir * arrive_slam_knockback + Vector3.UP * 5.0, "slam")
	FX.ring(p.get_parent(), center, arrive_slam_radius, Color(0.6, 0.85, 1.0, 0.9), 0.3)
	FX.hitstop(0.05)
	p.camera_fx.add_trauma(0.35)
	Audio.play("sounds/sfx/slam.wav")

func _restore() -> void:
	if _proj == null:
		return
	_proj = null
	var p := hand.player if hand else null
	if p and is_instance_valid(p):
		p.collision_mask = _saved_mask
		p.set_physics_process(true)

func on_projectile_removed(proj: MjolnirProjectile) -> void:
	if proj == _proj:
		_restore()

func on_unequip(_hand: MjolnirHand) -> void:
	_restore()
