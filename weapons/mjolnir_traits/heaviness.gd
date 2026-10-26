extends MjolnirTraitHandler
## Тяжесть (группа «попадание»): попадание молота прибивает врага к земле (стан 1.5 с).
## Ур. 2: оглушает всех в радиусе 2 м от цели.

@export var pin_time: float = 1.5
@export var splash_radius: float = 2.0

func on_hit_enemy(proj: MjolnirProjectile, enemy: Node3D, _damage: float) -> void:
	var en := enemy as Enemy
	if en == null or en.is_dead:
		return
	en.knockback_velocity = Vector3.ZERO
	en.velocity.y = minf(en.velocity.y, -6.0)
	en.apply_stun(pin_time, true)
	FX.ring(proj.fx_parent(), en.global_position + Vector3(0, 0.05, 0), 1.2, Color(0.6, 0.65, 0.8, 0.8), 0.3)
	if level >= 2:
		for other in enemies_near(en.get_tree(), en.global_position + Vector3(0, 0.9, 0), splash_radius):
			if other != en:
				other.apply_stun(pin_time, true)
		FX.ring(proj.fx_parent(), en.global_position + Vector3(0, 0.05, 0), splash_radius, Color(0.6, 0.65, 0.8, 0.6), 0.4)
	mark()
