extends BodyTraitHandler
## «Тактическая перезарядка» (Солдат): рывок мгновенно перезаряжает ренж (из запаса).

func on_dash(p: Player) -> void:
	if p.weapons and p.weapons.gun and p.weapons.gun.instant_reload():
		mark("reload")
