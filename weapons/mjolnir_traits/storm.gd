extends MjolnirTraitHandler
## Приём «Буря» (группа «удержание ПКМ» — с Пращой и Зарядом не берётся): зажми ПКМ при броске — молот зависает и крутится на месте, нанося урон по кругу.
## Отпустил ПКМ или вышло время — летит обратно. Ур. 2 — дольше и тянет к себе корм (не боссов).

## Пролетев столько метров (ПКМ всё ещё зажата), молот зависает. Было время 0.18 с — с броском 45 м/с
## (П2) молот улетал дальше; по расстоянию место зависания не зависит от скорости броска
@export var hover_distance: float = 6.0
@export var duration: float = 3.0
@export var duration_lvl2: float = 5.0
@export var radius: float = 3.0
## Шаг урона (с)
@export var tick: float = 0.3
## 0.5 У за шаг
@export var tick_damage: float = 11.0
@export var knockback: float = 4.0
## Ур. 2: скорость стягивания корма (м/с)
@export var pull_speed_lvl2: float = 5.0
@export var pull_radius_lvl2: float = 7.0

func on_flight_tick(proj: MjolnirProjectile, delta: float) -> void:
	if proj.state == MjolnirProjectile.State.OUT:
		if not proj.data.get("storm_done", false) and proj.travelled >= hover_distance and hand.is_throw_held():
			proj.hover(true)
			proj.data["storm_t"] = 0.0
			proj.data["storm_tick"] = 0.0
			mark()
		return
	if proj.state != MjolnirProjectile.State.HOVER:
		return
	var t: float = float(proj.data.get("storm_t", 0.0)) + delta
	proj.data["storm_t"] = t
	if not hand.is_throw_held() or t >= float(lvl(duration, duration_lvl2)):
		proj.data["storm_done"] = true
		proj.hover(false)
		proj.start_return(false)
		return
	var hp := proj.global_position
	if level >= 2:
		for e in enemies_near(proj.get_tree(), hp, pull_radius_lvl2):
			if e.kind == Enemy.Kind.BOSS:
				continue
			var to := hp - e.global_position
			to.y = 0
			if to.length() > 1.2:
				e.knockback_velocity = e.knockback_velocity.lerp(to.normalized() * pull_speed_lvl2, clampf(1.0 - exp(-6.0 * delta), 0.0, 1.0))
	var k: float = float(proj.data.get("storm_tick", 0.0)) - delta
	if k > 0.0:
		proj.data["storm_tick"] = k
		return
	proj.data["storm_tick"] = tick
	var any := false
	for e in enemies_near(proj.get_tree(), hp, radius):
		var dir := e.global_position - hp
		dir.y = 0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
		# Касательная + наружу — враги «закручиваются»
		var tangent := dir.cross(Vector3.UP)
		hurt(e, tick_damage * proj.damage_mult, (dir + tangent).normalized() * knockback + Vector3.UP * 1.5, "hammer")
		any = true
	FX.ring(proj.fx_parent(), hp - Vector3(0, 0.6, 0), radius, Color(0.55, 0.85, 1.0, 0.55), tick)
	if any:
		Audio.play("sounds/sfx/hammer_hit.wav")
