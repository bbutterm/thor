extends MjolnirTraitHandler
## Приём «Молот-ступенька» (блок Б4): воткнутый в стену молот — платформа. Встань на рукоять и прыгни —
## прыжок выше обычного (вертикаль: высота = сила удара-приземления). Управление — как у базы:
## ПКМ — бросок в стену, запрыгнуть на молот, Пробел; ПКМ ещё раз — молот вернулся, ступеньки нет.
## Платформа — StaticBody3D на слое мира (1) поверх рукояти; живёт, пока молот воткнут.
## Ур. 2 — прыжок ещё выше, молот ждёт дольше.

## Насколько выше прыжок со ступеньки (множитель вертикальной скорости прыжка)
@export var jump_mult: float = 1.5
@export var jump_mult_lvl2: float = 1.85
## Сколько воткнутый в стену молот ждёт ПКМ (с)
@export var stuck_hold: float = 6.0
@export var stuck_hold_lvl2: float = 10.0
## Размер площадки (ширина вдоль стены, толщина, вынос от стены), м
@export var platform_size: Vector3 = Vector3(1.0, 0.2, 0.9)
## Стена — поверхность круче этого (|нормаль.y| меньше)
@export var max_wall_normal_y: float = 0.5

var _body: StaticBody3D = null
var _proj: MjolnirProjectile = null
var _on_step: float = 0.0

func on_hit_world(proj: MjolnirProjectile, pos: Vector3, normal: Vector3, stuck: bool) -> void:
	if not stuck or absf(normal.y) > max_wall_normal_y:
		return
	_remove()
	_proj = proj
	proj.hold_stuck(float(lvl(stuck_hold, stuck_hold_lvl2)))
	var n := Vector3(normal.x, 0, normal.z).normalized()
	_body = StaticBody3D.new()
	_body.name = "HammerStep"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("transient", true)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = platform_size
	cs.shape = box
	_body.add_child(cs)
	proj.fx_parent().add_child(_body)
	# Площадка — на высоте рукояти, у стены (вынос — вдоль нормали)
	var center := pos + n * (platform_size.z * 0.5 + 0.02)
	center.y = proj.global_position.y - platform_size.y * 0.5
	_body.global_transform = Transform3D(Basis.looking_at(-n, Vector3.UP), center)
	mark()

func step_top() -> Vector3:
	return _body.global_position + Vector3(0, platform_size.y * 0.5, 0) if _body else Vector3.INF

func has_step() -> bool:
	return _body != null and is_instance_valid(_body)

func on_stuck_tick(proj: MjolnirProjectile, delta: float) -> void:
	if proj != _proj or not has_step():
		return
	var p := hand.player
	var top := step_top()
	var d := p.global_position - top
	var standing := p.is_on_floor() and Vector2(d.x, d.z).length() < maxf(platform_size.x, platform_size.z) * 0.75 and d.y > -0.2 and d.y < 0.45
	if standing:
		_on_step = 0.25
		return
	_on_step = maxf(0.0, _on_step - delta)
	# Прыжок со ступеньки: игрок только что оторвался от неё вверх — подбросить выше
	if _on_step > 0.0 and p.velocity.y > 3.0 and not p.is_on_floor():
		_on_step = 0.0
		p.velocity.y = p.jump_velocity * float(lvl(jump_mult, jump_mult_lvl2))
		p._air_peak_y = p.global_position.y
		p.camera_fx.kick_fov(8.0)
		FX.ring(p.get_parent(), top, 1.4, Color(0.6, 0.85, 1.0, 0.85), 0.3)
		FX.sparks(p.get_parent(), top, Color(0.7, 0.9, 1.0), 12, 5.0)
		Audio.play("sounds/sfx/super_jump.wav")
		StyleMeter.event(&"hammer_step")
		mark("jump")

func on_recall_start(proj: MjolnirProjectile, _by_player: bool) -> void:
	if proj == _proj:
		_remove()

func on_projectile_removed(proj: MjolnirProjectile) -> void:
	if proj == _proj:
		_remove()

func on_unequip(_hand: MjolnirHand) -> void:
	_remove()

func _remove() -> void:
	if _body and is_instance_valid(_body):
		_body.queue_free()
	_body = null
	_proj = null
	_on_step = 0.0
