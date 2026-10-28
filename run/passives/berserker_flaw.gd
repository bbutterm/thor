extends BodyTraitHandler
## Изъян Берсерка: лечение −50 %, орёт (враги замечают издалека).
## Более громкого Берсерка враги раньше замечают; после убийств он иногда действительно орёт.

@export var heal_mult: float = 0.5
## Радиус, на котором враги замечают шумного Берсерка, относительно обычного тела.
@export var notice_radius_mult: float = 1.5
## Шанс заорать после убийства
@export_range(0.0, 1.0) var shout_chance: float = 0.3

func modify(stat: StringName, value: Variant) -> Variant:
	match stat:
		&"heal_mult":
			return float(value) * heal_mult
		&"enemy_notice_radius_mult":
			return float(value) * notice_radius_mult
	return value

func on_kill(p: Player, _source: String) -> void:
	if randf() < shout_chance and p and not p.is_dead:
		Audio.play("sounds/sfx/enemy_growl.wav")
		p.camera_fx.add_trauma(0.08)
		mark("shout")
