extends MjolnirTraitHandler
## Приём «Пике молотом» (блок Б4): в воздухе брось молот вниз (взгляд круче min_down_angle) — он уходит
## в пол, а Тор летит за ним и бьёт ударом-приземлением с бонусом высоты. Молот сразу в руке.
## Удар — обычный удар-приземление игрока (player.gd: _start_slam, сила от высоты _air_peak_y), поэтому
## все руны, стили тела и связки стихий с ударом-приземлением работают и здесь.
## Ур. 2 — бонус высоты больше. Связка Земля + Пике — кратер (on_dive_slam).

## Насколько круто вниз надо смотреть (градусы ниже горизонта)
@export var min_down_angle: float = 30.0
@export var throw_speed_mult: float = 1.6
## Скорость, с которой Тор летит за молотом (м/с)
@export var follow_speed: float = 40.0
## Бонус к высоте удара-приземления (м)
@export var height_bonus: float = 4.0
@export var height_bonus_lvl2: float = 7.0
## Не ждём дольше (молот в полу, а Тор так и не приземлился) — обычный молот
@export var max_follow_time: float = 1.5

var _proj: MjolnirProjectile = null
var _t: float = 0.0

func on_throw(proj: MjolnirProjectile) -> void:
	var p := hand.player
	if p == null or not p.can_start_slam():
		return
	if p.get_aim_forward().y > -sin(deg_to_rad(min_down_angle)):
		return
	proj.data["dive"] = true
	proj.vel *= throw_speed_mult
	proj._sticks = true
	proj.bounces_left = 0
	mark("throw")

func on_hit_world(proj: MjolnirProjectile, _pos: Vector3, normal: Vector3, stuck: bool) -> void:
	if not stuck or not proj.data.get("dive", false) or normal.y < 0.6:
		return
	var p := hand.player
	if p == null or p.is_dead or p.is_on_floor():
		return
	if not p._start_slam():
		return
	_proj = proj
	_t = 0.0
	proj.hold_stuck(max_follow_time + 0.5)
	# Бонус высоты: удар считается с вершины выше на height_bonus
	p._air_peak_y = maxf(p._air_peak_y, p.global_position.y) + float(lvl(height_bonus, height_bonus_lvl2))
	var target := proj.global_position - proj.stuck_normal * 0.38
	var dir := (target - p.global_position).normalized()
	if dir.y > -0.3:
		dir = (dir + Vector3.DOWN).normalized()
	p._slam_velocity = dir * follow_speed
	p.camera_fx.speed_lines_pulse()
	p.camera_fx.kick_fov(-8.0)
	mark("follow")

func on_stuck_tick(proj: MjolnirProjectile, delta: float) -> void:
	if proj != _proj:
		return
	_t += delta
	var p := hand.player
	if _t > max_follow_time or (p and p.is_on_floor() and not p.is_slamming):
		_proj = null

## Удар-приземление после пике — сигнал связкам и молот в руку
func on_player_slam(h: MjolnirHand, power: float, center: Vector3) -> void:
	if _proj == null or not is_instance_valid(_proj):
		_proj = null
		return
	var proj := _proj
	_proj = null
	mark("slam")
	StyleMeter.event(&"hammer_dive")
	FX.ring(h.player.get_parent(), center, 2.5, Color(0.6, 0.85, 1.0, 0.9), 0.3)
	h.trait_call(&"on_dive_slam", [h, center, power])
	if is_instance_valid(proj) and not proj.is_queued_for_deletion():
		proj.catch()

func is_following() -> bool:
	return _proj != null

func on_projectile_removed(proj: MjolnirProjectile) -> void:
	if proj == _proj:
		_proj = null
