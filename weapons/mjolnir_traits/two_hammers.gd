extends MjolnirTraitHandler
## Два молота (группа «бросок»): бросок раздваивается веером, каждый молот ×0.6 урона.
## Ур. 2: три молота. Копии летят сами по себе: трейты на них не действуют, не втыкаются, возвращаются и исчезают у руки.

@export var damage_mult: float = 0.6
## Угол между молотами веера (градусы)
@export var spread_deg: float = 12.0

func on_throw(proj: MjolnirProjectile) -> void:
	if proj.is_clone:
		return
	proj.damage_mult *= damage_mult
	var extra: int = lvl(1, 2)
	var angles: Array[float] = [-spread_deg, spread_deg]
	if extra == 1:
		# Два молота — симметрично: основной чуть влево, копия чуть вправо
		proj.vel = proj.vel.rotated(Vector3.UP, deg_to_rad(-spread_deg * 0.5))
		angles = [spread_deg]
	for a in angles:
		var c := MjolnirProjectile.new()
		proj.fx_parent().add_child(c)
		c.launch_clone(proj.hand, proj.global_position, proj.vel.rotated(Vector3.UP, deg_to_rad(a)), proj.damage_mult)
	mark()
