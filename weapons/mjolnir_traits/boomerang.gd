extends MjolnirTraitHandler
## Бумеранг (группа «возврат»): молот не втыкается, летит по дуге и возвращается сам — ПКМ не нужен.
## Ур. 2 — две петли (сначала в одну сторону, потом в другую).

@export var speed_mult: float = 1.25
## Сколько секунд молот загибает в одну сторону
@export var loop_time: float = 0.5
## Скорость поворота (рад/с): 3.6 × 0.5 с ≈ 100°
@export var turn_rate: float = 3.6

func modify(stat: StringName, value: Variant) -> Variant:
	match stat:
		&"sticks":
			return false
		&"throw_speed":
			return float(value) * speed_mult
	return value

func on_throw(proj: MjolnirProjectile) -> void:
	proj.data["boom_t"] = 0.0
	proj.data["boom_side"] = 1.0 if randf() < 0.5 else -1.0
	mark()

func on_flight_tick(proj: MjolnirProjectile, delta: float) -> void:
	if proj.state != MjolnirProjectile.State.OUT:
		return
	var t: float = float(proj.data.get("boom_t", 0.0)) + delta
	proj.data["boom_t"] = t
	var loops: int = lvl(1, 2)
	var phase := int(t / loop_time)
	if phase >= loops:
		proj.start_return(false)
		return
	var side: float = float(proj.data.get("boom_side", 1.0)) * (1.0 if phase % 2 == 0 else -1.0)
	proj.vel = proj.vel.rotated(Vector3.UP, side * turn_rate * delta)
