extends MjolnirTraitHandler
## Приём «Верный пёс» (блок Б4): воткнутый молот сам бьёт ближайшего врага в радиусе раз в interval
## («поставил турель и дерусь топором»). Боёк «кусает» цель и возвращается — молот остаётся воткнутым
## и ждёт ПКМ дольше. Ур. 2 — чаще и дольше.

@export var interval: float = 1.0
@export var interval_lvl2: float = 0.6
@export var radius: float = 8.0
## 0.7 У
@export var damage: float = 15.0
@export var knockback: float = 6.0
## Сколько воткнутый молот ждёт ПКМ (с)
@export var stuck_hold: float = 6.0
@export var stuck_hold_lvl2: float = 9.0

## Сколько раз укусил (для тестов)
var bites: int = 0

func on_hit_world(proj: MjolnirProjectile, _pos: Vector3, _normal: Vector3, stuck: bool) -> void:
	if stuck:
		proj.hold_stuck(float(lvl(stuck_hold, stuck_hold_lvl2)))
		proj.data["dog_t"] = 0.3

func on_stuck_tick(proj: MjolnirProjectile, delta: float) -> void:
	var t: float = float(proj.data.get("dog_t", 0.3)) - delta
	if t > 0.0:
		proj.data["dog_t"] = t
		return
	proj.data["dog_t"] = float(lvl(interval, interval_lvl2))
	var target := _nearest(proj)
	if target == null:
		return
	var chest := target.global_position + Vector3(0, 1.0, 0)
	proj.lunge(chest)
	var dir := target.global_position - proj.global_position
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	hurt(target, damage * proj.damage_mult, dir * knockback + Vector3.UP * 2.5, "hammer")
	FX.burst(proj.fx_parent(), chest, 0.5, Color(0.55, 0.85, 1.0, 0.7), 0.15)
	Audio.play("sounds/sfx/hammer_hit.wav")
	bites += 1
	mark()

func _nearest(proj: MjolnirProjectile) -> Enemy:
	var space := proj.get_world_3d().direct_space_state
	var best: Enemy = null
	var best_d := radius
	var from := proj.global_position + proj.stuck_normal * 0.3
	for e in proj.get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en == null or en.is_dead:
			continue
		var chest := en.global_position + Vector3(0, 1.0, 0)
		var d := chest.distance_to(from)
		if d >= best_d:
			continue
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(from, chest, 1)).is_empty():
			best = en
			best_d = d
	return best
