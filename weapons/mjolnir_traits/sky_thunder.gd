extends MjolnirTraitHandler
## Гром небесный (без группы): идеальный хват вызывает удар молнии с неба в точку прицела.
## Ур. 2 — ещё и оглушает.

@export var max_distance: float = 40.0
@export var radius: float = 3.0
## 1.5 У
@export var damage: float = 33.0
@export var stun_time_lvl2: float = 1.0

func on_perfect_catch(h: MjolnirHand) -> void:
	var p := h.player
	var from := p.get_aim_origin()
	var to := from + p.get_aim_forward() * max_distance
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | (1 << 2))
	q.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	mark()
	var point: Vector3 = hit.position
	var parent := p.get_parent()
	FX.lightning(parent, point + Vector3(randf_range(-1, 1), 14.0, randf_range(-1, 1)), point, 0.3, Color(0.85, 0.95, 1.0))
	FX.ring(parent, point, radius, Color(0.7, 0.9, 1.0, 0.9), 0.35)
	FX.burst(parent, point + Vector3(0, 0.5, 0), radius * 0.4, Color(0.8, 0.95, 1.0, 0.6), 0.2)
	for e in enemies_near(p.get_tree(), point, radius + 0.9):
		e.take_hit(damage, Vector3.UP * 4.0, "lightning")
		if level >= 2:
			e.stun(stun_time_lvl2)
	p.camera_fx.add_trauma(0.3)
	Audio.play("sounds/sfx/lightning.wav")
