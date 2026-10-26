extends BodyTraitHandler
## Изъян Берсерка: лечение −50 %, орёт (враги замечают издалека).
## TODO: враги и так всегда знают, где Тор (радиуса обнаружения в enemy.gd нет) — пока «орёт» только звуком.

@export var heal_mult: float = 0.5
## Шанс заорать после убийства
@export_range(0.0, 1.0) var shout_chance: float = 0.3

func modify(stat: StringName, value: Variant) -> Variant:
	if stat == &"heal_mult":
		return float(value) * heal_mult
	return value

func on_kill(p: Player, _source: String) -> void:
	if randf() < shout_chance and p and not p.is_dead:
		Audio.play("sounds/sfx/enemy_growl.wav")
		p.camera_fx.add_trauma(0.08)
		mark("shout")
