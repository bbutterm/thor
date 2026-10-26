extends MjolnirTraitHandler
## Громоотвод (группа «воткнулся»): воткнутый молот раз в interval бьёт молнией всех в радиусе, пока его не позовёшь.

@export var interval: float = 1.0
@export var interval_lvl2: float = 0.6
@export var radius: float = 4.0
@export var damage: float = 15.0
## Сколько воткнутый молот ждёт ПКМ
@export var stuck_hold: float = 5.0

func modify(stat: StringName, value: Variant) -> Variant:
	if stat == &"stuck_auto_return" and float(value) > 0.0:
		return maxf(float(value), stuck_hold)
	return value

func on_hit_world(proj: MjolnirProjectile, _pos: Vector3, _normal: Vector3, stuck: bool) -> void:
	if stuck:
		# Первый разряд — почти сразу
		proj.data["rod_t"] = 0.15

func on_stuck_tick(proj: MjolnirProjectile, delta: float) -> void:
	var t: float = float(proj.data.get("rod_t", 0.15)) - delta
	if t > 0.0:
		proj.data["rod_t"] = t
		return
	proj.data["rod_t"] = float(lvl(interval, interval_lvl2))
	mark()
	var top := proj.global_position + proj.stuck_normal * 0.4
	var parent := proj.fx_parent()
	FX.lightning(parent, top + Vector3(0, 7.0, 0), top, 0.2)
	FX.ring(parent, proj.global_position - Vector3(0, 0.3, 0), radius, Color(0.6, 0.85, 1.0, 0.7), 0.25)
	for e in enemies_near(proj.get_tree(), proj.global_position, radius):
		var chest := e.global_position + Vector3(0, 1.0, 0)
		FX.lightning(parent, top, chest, 0.18)
		var dir := e.global_position - proj.global_position
		dir.y = 0
		e.take_hit(damage * proj.damage_mult, dir.normalized() * 2.0 + Vector3.UP * 2.0, "lightning")
	Audio.play("sounds/sfx/lightning.wav")
