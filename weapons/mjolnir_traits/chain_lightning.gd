extends MjolnirTraitHandler
## Цепная молния (группа «попадание»): при попадании молния перескакивает на ближайших врагов.

@export var targets: int = 3
@export var targets_lvl2: int = 5
## 0.5 У
@export var damage: float = 11.0
## Дальность одного прыжка молнии (м)
@export var radius: float = 7.0

func on_hit_enemy(proj: MjolnirProjectile, enemy: Node3D, _damage: float) -> void:
	if proj.chain_lightning(enemy, damage * proj.damage_mult, lvl(targets, targets_lvl2), radius) > 0:
		mark()
