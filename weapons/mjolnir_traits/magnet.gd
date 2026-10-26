extends MjolnirTraitHandler
## Магнит (группа «возврат»): воткнутый молот стягивает к себе врагов, а при возврате раскидывает их.

@export var radius: float = 6.0
@export var radius_lvl2: float = 9.0
## Скорость стягивания (м/с)
@export var pull_speed: float = 7.0
## Ближе этого не тянем
@export var hold_distance: float = 1.6
## Боссов тянет слабее
@export var boss_factor: float = 0.25
@export var blast_damage: float = 11.0
@export var blast_knockback: float = 15.0
## Сколько воткнутый молот ждёт ПКМ
@export var stuck_hold: float = 3.0
## Как часто рисуется искра к притянутому врагу (с)
@export var arc_interval: float = 0.3

func modify(stat: StringName, value: Variant) -> Variant:
	if stat == &"stuck_auto_return" and float(value) > 0.0:
		return maxf(float(value), stuck_hold)
	return value

func on_hit_world(proj: MjolnirProjectile, _pos: Vector3, _normal: Vector3, stuck: bool) -> void:
	if stuck:
		mark()
		proj.data["magnet_armed"] = true
		proj.data["magnet_arc"] = 0.0
		FX.ring(proj.fx_parent(), proj.global_position - Vector3(0, 0.3, 0), lvl(radius, radius_lvl2), Color(0.5, 0.8, 1.0, 0.6), 0.4)

func on_stuck_tick(proj: MjolnirProjectile, delta: float) -> void:
	var r: float = lvl(radius, radius_lvl2)
	var hp := proj.global_position
	var pulled: Array[Enemy] = []
	for e in enemies_near(proj.get_tree(), hp, r):
		var to := hp - e.global_position
		to.y = 0
		var d := to.length()
		if d < hold_distance:
			continue
		var f := pull_speed * (boss_factor if e.kind == Enemy.Kind.BOSS else 1.0)
		e.knockback_velocity = e.knockback_velocity.lerp(to / d * f, clampf(1.0 - exp(-6.0 * delta), 0.0, 1.0))
		pulled.append(e)
	proj.data["magnet_arc"] = float(proj.data.get("magnet_arc", 0.0)) - delta
	if not pulled.is_empty() and float(proj.data["magnet_arc"]) <= 0.0:
		proj.data["magnet_arc"] = arc_interval
		var e: Enemy = pulled[randi() % pulled.size()]
		FX.lightning(proj.fx_parent(), hp, e.global_position + Vector3(0, 1.0, 0), 0.12)

func on_recall_start(proj: MjolnirProjectile, _by_player: bool) -> void:
	if not proj.data.get("magnet_armed", false):
		return
	proj.data["magnet_armed"] = false
	mark("blast")
	var r: float = lvl(radius, radius_lvl2)
	var hp := proj.global_position
	for e in enemies_near(proj.get_tree(), hp, r):
		var dir := e.global_position - hp
		dir.y = 0
		var d := dir.length()
		dir = dir / d if d > 0.01 else Vector3.FORWARD
		var falloff := clampf(1.0 - d / r, 0.4, 1.0)
		e.take_hit(blast_damage * proj.damage_mult, dir * blast_knockback * falloff + Vector3.UP * 5.0 * falloff, "hammer")
	FX.ring(proj.fx_parent(), hp - Vector3(0, 0.3, 0), r, Color(0.55, 0.85, 1.0, 0.9), 0.35)
	FX.burst(proj.fx_parent(), hp, 1.2, Color(0.55, 0.85, 1.0, 0.5), 0.2)
	hand.player.camera_fx.add_trauma(0.25)
	Audio.play("sounds/sfx/hammer_hit.wav")
